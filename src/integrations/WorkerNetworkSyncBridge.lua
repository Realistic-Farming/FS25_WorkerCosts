-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WorkerNetworkSyncBridge — optional bridge to FS25_NetworkSync v2 (bedrock)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- Strictly delegate-when-present. WorkerCosts is the FIRST NS v2 dual-consumer: it
-- exercises BOTH new paths SoilFertilizer never touched.
--
--   Path 1 (state + delta): the server-authoritative roster snapshot folds into
--     NetworkSync's 1Hz batch. onWriteState is the full snapshot (also the join
--     snapshot and the 30s drift-floor resync); onWriteDelta sends only the workers
--     that changed since the last delta tick, so a single hire / fire / fatigue tick
--     no longer reserializes the whole roster.
--   Path 3 (action channel): the six client-initiated worker commands (hire, fire,
--     assign, unassign, set-trusted, refresh-pool) route through NetworkSync's
--     validated client-to-server action channel instead of WCWorkerCommandEvent.
--
--   * NetworkSync absent -> nothing changes; WorkerCosts' own event classes
--     (WCRosterSyncEvent / WCWorkerCommandEvent / WCRequestRosterSyncEvent) carry
--     everything exactly as before.
--
-- WIRE MODEL. Both FULL and DELTA carry ABSOLUTE values (never incremental diffs),
-- so re-applying a delta a client already has (e.g. from its join FULL) is a no-op.
-- That, plus NS's two invariants (a client holds deltas until its FULL snapshot
-- lands; a 30s drift-floor FULL rebaselines any missed delta), makes the delta path
-- self-healing under any baseline skew. The full ordered uuid list in each delta
-- reproduces the server's trusted-first display order exactly (add / remove / reorder
-- all fall out of it), while only changed worker rows carry the 16 data fields.
--
-- The wire shape mirrors WCNetworkEvents' writeSnapshot/readSnapshot field-for-field
-- (the server computes every derived/financial value once; clients render what they
-- receive), so a client still needs no local settings or wage pipeline. Booleans go
-- on the wire as 0/1 ints to keep each array purely numeric+string.
--
-- Authority: the six actions register adminOnly=false to preserve the shipped model
-- (any farm member manages the one shared roster, charged to the farmId they pass);
-- the hire/fire farmId guard from WCWorkerCommandEvent:run is reproduced here. Tighter
-- gating would be a design change (PIPELINE), not part of this transport migration.
--
-- The cross-mod handle is g_currentMission.networkSync (published in Mission00.load).
-- =========================================================

WorkerNetworkSyncBridge = {}

-- LOCKED channel / module id (see BEDROCK-MIGRATION-BUILD-BRIEF). Never renamed.
WorkerNetworkSyncBridge.MODULE_ID = "WorkerCosts_Sync"
WorkerNetworkSyncBridge.CHANNEL   = "WorkerCosts_Sync"

-- Action ids for the six worker commands (Path 3). Runtime registrations, but kept
-- on the WorkerCosts_<Thing> scheme for legibility on the wire / in NS status.
WorkerNetworkSyncBridge.ACTIONS = {
    HIRE         = "WorkerCosts_Hire",
    FIRE         = "WorkerCosts_Fire",
    ASSIGN       = "WorkerCosts_Assign",
    UNASSIGN     = "WorkerCosts_Unassign",
    SET_TRUSTED  = "WorkerCosts_SetTrusted",
    REFRESH_POOL = "WorkerCosts_RefreshPool",
}

WorkerNetworkSyncBridge.active    = false   -- NetworkSync present and we registered
WorkerNetworkSyncBridge._lastRows = {}      -- server: uuid -> last-sent flat row (delta baseline)

-- =========================================================
-- Flat serialize / deserialize helpers (pure; server writes, client reads)
-- =========================================================

local function b2i(v) return v and 1 or 0 end
local function i2b(v) return (tonumber(v) or 0) ~= 0 end

-- Aggregate + finance + hiring header: 17 values. Shared prefix of FULL and DELTA.
local function writeAggregate(arr, snap)
    local levels  = snap.levels  or {}
    local finance = snap.finance or {}
    local hiring  = snap.hiring  or {}
    arr[#arr + 1] = snap.count   or 0
    arr[#arr + 1] = snap.working or 0
    arr[#arr + 1] = snap.pinned  or 0
    arr[#arr + 1] = levels.novice      or 0
    arr[#arr + 1] = levels.experienced or 0
    arr[#arr + 1] = levels.master      or 0
    arr[#arr + 1] = levels.legendary   or 0
    arr[#arr + 1] = finance.baseRate or 0
    arr[#arr + 1] = b2i(finance.isHourly == true)
    arr[#arr + 1] = finance.costModeName  or ""
    arr[#arr + 1] = finance.wageLevelName or ""
    arr[#arr + 1] = finance.monthAccrued    or 0
    arr[#arr + 1] = finance.estIntervalCost or 0
    arr[#arr + 1] = finance.proStaffDelta   or 0
    arr[#arr + 1] = hiring.limit     or 0
    arr[#arr + 1] = hiring.usedToday or 0
    arr[#arr + 1] = hiring.remaining or 0
end

local function readAggregate(arr, i, snap)
    snap.count   = arr[i]     or 0
    snap.working = arr[i + 1] or 0
    snap.pinned  = arr[i + 2] or 0
    snap.levels = {
        novice      = arr[i + 3] or 0,
        experienced = arr[i + 4] or 0,
        master      = arr[i + 5] or 0,
        legendary   = arr[i + 6] or 0,
    }
    snap.finance = {
        baseRate        = arr[i + 7]  or 0,
        isHourly        = i2b(arr[i + 8]),
        costModeName    = arr[i + 9]  or "",
        wageLevelName   = arr[i + 10] or "",
        monthAccrued    = arr[i + 11] or 0,
        estIntervalCost = arr[i + 12] or 0,
        proStaffDelta   = arr[i + 13] or 0,
    }
    snap.hiring = {
        limit     = arr[i + 14] or 0,
        usedToday = arr[i + 15] or 0,
        remaining = arr[i + 16] or 0,
    }
    return i + 17
end

-- One worker row: 16 values (matches WCNetworkEvents writeSnapshot per-worker order).
local function writeWorkerRow(arr, w)
    arr[#arr + 1] = w.uuid or 0
    arr[#arr + 1] = w.name or "Worker"
    arr[#arr + 1] = w.level or 1
    arr[#arr + 1] = w.totalHours or 0
    arr[#arr + 1] = w.totalJobs or 0
    arr[#arr + 1] = w.fatigue or 0
    arr[#arr + 1] = b2i(w.working == true)
    arr[#arr + 1] = b2i(w.pinned == true)
    arr[#arr + 1] = b2i(w.trusted == true)
    arr[#arr + 1] = w.baseRate or 0
    arr[#arr + 1] = w.effRate or 0
    arr[#arr + 1] = w.severance or 0
    arr[#arr + 1] = w.lifecycleState or "available"
    arr[#arr + 1] = w.histJobs or 0
    arr[#arr + 1] = w.histDone or 0
    arr[#arr + 1] = w.histFailed or 0
end

-- Read one worker row and rebuild the display-only fields the server did not ship
-- (levelName / proStaffDelta / status), exactly as WCNetworkEvents readSnapshot does.
local function readWorkerRow(arr, i)
    local w = {}
    w.uuid       = arr[i] or 0
    w.name       = arr[i + 1] or "Worker"
    w.level      = arr[i + 2] or 1
    w.totalHours = arr[i + 3] or 0
    w.totalJobs  = arr[i + 4] or 0
    w.fatigue    = arr[i + 5] or 0
    w.working    = i2b(arr[i + 6])
    w.pinned     = i2b(arr[i + 7])
    w.trusted    = i2b(arr[i + 8])
    w.baseRate   = arr[i + 9] or 0
    w.effRate    = arr[i + 10] or 0
    w.severance  = arr[i + 11] or 0
    w.lifecycleState = arr[i + 12] or "available"
    w.histJobs   = arr[i + 13] or 0
    w.histDone   = arr[i + 14] or 0
    w.histFailed = arr[i + 15] or 0

    w.levelName     = WorkerRoster.levelName(w.level)
    w.proStaffDelta = (w.effRate or 0) - (w.baseRate or 0)
    local status = w.working and "working" or "idle"
    if w.pinned then status = status .. ", pinned" end
    w.status = status
    return w, i + 16
end

local function writeRecruits(arr, snap)
    local recruits = snap.recruits or {}
    arr[#arr + 1] = #recruits
    for _, r in ipairs(recruits) do
        arr[#arr + 1] = r.slot or 1
        arr[#arr + 1] = r.name or "Recruit"
        arr[#arr + 1] = r.level or 1
        arr[#arr + 1] = r.hireCost or 0
    end
end

local function readRecruits(arr, i, snap)
    local n = arr[i] or 0
    i = i + 1
    local recruits = {}
    for _ = 1, n do
        local r = {
            slot     = arr[i] or 1,
            name     = arr[i + 1] or "Recruit",
            level    = arr[i + 2] or 1,
            hireCost = arr[i + 3] or 0,
        }
        r.levelName = WorkerRoster.levelName(r.level)
        recruits[#recruits + 1] = r
        i = i + 4
    end
    snap.recruits = recruits
    return i
end

-- FULL: aggregate, workerCount, [rows], recruits.
local function serializeSnapshot(snap)
    local arr = {}
    writeAggregate(arr, snap)
    local workers = snap.workers or {}
    arr[#arr + 1] = #workers
    for _, w in ipairs(workers) do writeWorkerRow(arr, w) end
    writeRecruits(arr, snap)
    return arr
end

local function deserializeSnapshot(arr)
    local snap = { authoritative = true }
    if type(arr) ~= "table" then
        snap.count = 0; snap.working = 0; snap.pinned = 0
        snap.levels = {}; snap.finance = {}; snap.hiring = {}
        snap.workers = {}; snap.recruits = {}
        return snap
    end
    local i = readAggregate(arr, 1, snap)
    local n = arr[i] or 0
    i = i + 1
    local workers = {}
    for _ = 1, n do
        local w
        w, i = readWorkerRow(arr, i)
        workers[#workers + 1] = w
    end
    snap.workers = workers
    readRecruits(arr, i, snap)
    return snap
end

-- Element-wise equality of two flat worker-row arrays (nil-safe).
local function rowsEqual(a, b)
    if a == nil or b == nil then return false end
    if #a ~= #b then return false end
    for k = 1, #a do
        if a[k] ~= b[k] then return false end
    end
    return true
end

-- =========================================================
-- NetworkSync module callbacks (plain functions - called with no self)
-- =========================================================

-- Server: full snapshot (join, drift-floor, and the FULL fallback).
function WorkerNetworkSyncBridge._onWriteState()
    local wm = g_WorkerManager
    if wm == nil or wm.getServerSnapshot == nil then return {} end
    return serializeSnapshot(wm:getServerSnapshot())
end

-- Client: apply a full snapshot, replacing the client mirror wholesale.
function WorkerNetworkSyncBridge._onReadState(arr)
    local wm = g_WorkerManager
    if wm == nil then return end
    wm:applyClientSnapshot(deserializeSnapshot(arr))
end

-- Server: only the workers changed since the last delta tick, plus the always-cheap
-- aggregate/finance/hiring header, the recruit pool, and the full ordered uuid list.
function WorkerNetworkSyncBridge._onWriteDelta()
    local wm = g_WorkerManager
    if wm == nil or wm.getServerSnapshot == nil then return {} end
    local snap = wm:getServerSnapshot()

    local order   = {}
    local changed = {}
    local newRows = {}
    for _, w in ipairs(snap.workers or {}) do
        local uuid = w.uuid or 0
        order[#order + 1] = uuid
        local row = {}
        writeWorkerRow(row, w)
        newRows[uuid] = row
        if not rowsEqual(WorkerNetworkSyncBridge._lastRows[uuid], row) then
            changed[#changed + 1] = w
        end
    end
    WorkerNetworkSyncBridge._lastRows = newRows

    local arr = {}
    writeAggregate(arr, snap)
    writeRecruits(arr, snap)
    arr[#arr + 1] = #order
    for _, uuid in ipairs(order) do arr[#arr + 1] = uuid end
    arr[#arr + 1] = #changed
    for _, w in ipairs(changed) do writeWorkerRow(arr, w) end
    return arr
end

-- Client: merge a delta into the stored snapshot. Aggregate/finance/hiring/recruits
-- are replaced; workers are rebuilt in the sent order, reusing unchanged rows from
-- the current mirror and overlaying the changed rows. NS guarantees a FULL landed
-- first, so wm.clientRosterSnapshot is present.
function WorkerNetworkSyncBridge._onReadDelta(arr)
    local wm = g_WorkerManager
    if wm == nil or type(arr) ~= "table" then return end
    local snap = wm.clientRosterSnapshot
    if type(snap) ~= "table" then return end   -- no base yet; drift-floor FULL will seed one

    local i = readAggregate(arr, 1, snap)
    i = readRecruits(arr, i, snap)

    local orderCount = arr[i] or 0; i = i + 1
    local order = {}
    for k = 1, orderCount do order[k] = arr[i]; i = i + 1 end

    local changedCount = arr[i] or 0; i = i + 1
    local changedByUuid = {}
    for _ = 1, changedCount do
        local w
        w, i = readWorkerRow(arr, i)
        changedByUuid[w.uuid or 0] = w
    end

    local oldByUuid = {}
    for _, w in ipairs(snap.workers or {}) do oldByUuid[w.uuid or 0] = w end

    local newWorkers = {}
    for _, uuid in ipairs(order) do
        local w = changedByUuid[uuid] or oldByUuid[uuid]
        if w ~= nil then newWorkers[#newWorkers + 1] = w end
    end
    snap.workers = newWorkers

    wm:applyClientSnapshot(snap)
end

-- =========================================================
-- Public: dirty flag (choke point) + client-to-server command send
-- =========================================================

-- Called from WorkerManager:_broadcastRosterSync at the single post-mutation choke
-- point. Flags the module for the next 1Hz batch. Returns true when handled (so the
-- own WCRosterSyncEvent broadcast stands down), false when NetworkSync is absent.
function WorkerNetworkSyncBridge.markRosterDirty()
    if not WorkerNetworkSyncBridge.active then return false end
    local ns = (g_currentMission and g_currentMission.networkSync) or g_networkSync
    if ns == nil then return false end
    ns:markDirty(WorkerNetworkSyncBridge.MODULE_ID)
    return true
end

-- Called from WCNetwork_SendCommand. Routes a worker command through the NS action
-- channel (Path 3). Returns true when handled (own WCWorkerCommandEvent stands down),
-- false when NetworkSync is absent so the caller runs its own path.
function WorkerNetworkSyncBridge.sendCommand(action, uuid, slot, vehicleUniqueId, farmId)
    if not WorkerNetworkSyncBridge.active then return false end
    local ns = (g_currentMission and g_currentMission.networkSync) or g_networkSync
    if ns == nil then return false end

    local A = WorkerNetworkSyncBridge.ACTIONS
    local actionId, args
    if action == WCCommand.HIRE then
        actionId, args = A.HIRE, { slot or 1, farmId or 0 }
    elseif action == WCCommand.FIRE then
        actionId, args = A.FIRE, { uuid or 0, farmId or 0 }
    elseif action == WCCommand.ASSIGN then
        actionId, args = A.ASSIGN, { uuid or 0, vehicleUniqueId or "" }
    elseif action == WCCommand.UNASSIGN then
        actionId, args = A.UNASSIGN, { uuid or 0 }
    elseif action == WCCommand.SET_TRUSTED then
        actionId, args = A.SET_TRUSTED, { uuid or 0, slot or 0 }
    elseif action == WCCommand.REFRESH_POOL then
        actionId, args = A.REFRESH_POOL, {}
    else
        return false
    end

    ns:requestAction(actionId, args)
    return true
end

-- =========================================================
-- Registration (loadMission00Finished)
-- =========================================================

local function registerActions(ns, mgr)
    local A = WorkerNetworkSyncBridge.ACTIONS

    -- Reproduce WCWorkerCommandEvent:run's guard: hire/fire need a real farm to charge.
    local function farmOk(farmId, action)
        if not farmId or farmId == 0 then
            Logging.warning("[Worker Costs] Rejected NS action (action=%d) - invalid farmId", action)
            return false
        end
        return true
    end

    ns:registerAction(A.HIRE, { adminOnly = false, onAction = function(_userId, args)
        local slot   = (args and args[1]) or 1
        local farmId = (args and args[2]) or 0
        if farmOk(farmId, WCCommand.HIRE) then
            mgr:_applyCommandFromNetwork(WCCommand.HIRE, 0, slot, "", farmId)
        end
    end })
    ns:registerAction(A.FIRE, { adminOnly = false, onAction = function(_userId, args)
        local uuid   = (args and args[1]) or 0
        local farmId = (args and args[2]) or 0
        if farmOk(farmId, WCCommand.FIRE) then
            mgr:_applyCommandFromNetwork(WCCommand.FIRE, uuid, 0, "", farmId)
        end
    end })
    ns:registerAction(A.ASSIGN, { adminOnly = false, onAction = function(_userId, args)
        mgr:_applyCommandFromNetwork(WCCommand.ASSIGN, (args and args[1]) or 0, 0, (args and args[2]) or "", 0)
    end })
    ns:registerAction(A.UNASSIGN, { adminOnly = false, onAction = function(_userId, args)
        mgr:_applyCommandFromNetwork(WCCommand.UNASSIGN, (args and args[1]) or 0, 0, "", 0)
    end })
    ns:registerAction(A.SET_TRUSTED, { adminOnly = false, onAction = function(_userId, args)
        mgr:_applyCommandFromNetwork(WCCommand.SET_TRUSTED, (args and args[1]) or 0, (args and args[2]) or 0, "", 0)
    end })
    ns:registerAction(A.REFRESH_POOL, { adminOnly = false, onAction = function(_userId, _args)
        mgr:_applyCommandFromNetwork(WCCommand.REFRESH_POOL, 0, 0, "", 0)
    end })
end

function WorkerNetworkSyncBridge.register(mgr)
    -- Reset per-load so a map swap / reload starts clean.
    WorkerNetworkSyncBridge.active    = false
    WorkerNetworkSyncBridge._lastRows = {}

    local ns = (g_currentMission and g_currentMission.networkSync) or g_networkSync
    if ns == nil then
        Logging.info("[Worker Costs] NetworkSync not detected; roster MP uses its own event classes")
        return
    end
    if mgr == nil then return end

    local ok, err = pcall(function()
        ns:registerModule(WorkerNetworkSyncBridge.MODULE_ID, {
            channel      = WorkerNetworkSyncBridge.CHANNEL,
            onWriteState = WorkerNetworkSyncBridge._onWriteState,
            onReadState  = WorkerNetworkSyncBridge._onReadState,
            onWriteDelta = WorkerNetworkSyncBridge._onWriteDelta,
            onReadDelta  = WorkerNetworkSyncBridge._onReadDelta,
        })
        registerActions(ns, mgr)
    end)

    if ok then
        WorkerNetworkSyncBridge.active = true
        Logging.info("[Worker Costs] Registered with NetworkSync as '%s' (delta roster sync + client-to-server action channel)",
            WorkerNetworkSyncBridge.MODULE_ID)
    else
        WorkerNetworkSyncBridge.active = false
        Logging.warning("[Worker Costs] NetworkSync registration failed: %s (falling back to WC event classes)", tostring(err))
    end
end

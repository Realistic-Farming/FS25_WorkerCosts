-- =========================================================
-- FS25 Realistic Worker Costs Mod — Network Events
-- =========================================================
-- Pro-Staff Phase 5 multiplayer layer. The roster is server-authoritative; the
-- host owns it, persists it, and is the only peer that mutates it. Clients see a
-- mirror via WCRosterSyncEvent and request management actions via
-- WCWorkerCommandEvent. Flow mirrors SoilFertilizer's proven event design:
--   client requests/commands -> server validates & applies -> server broadcasts.
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================

-- Command action codes (kept tiny — sent as a UInt8 on the wire).
WCCommand = {
    HIRE         = 1,
    FIRE         = 2,
    ASSIGN       = 3,
    UNASSIGN     = 4,
    REFRESH_POOL = 5,
}

-- ---------------------------------------------------------------------------
-- Shared snapshot serialization. The roster snapshot (built server-side by
-- WorkerManager:getServerSnapshot) IS the wire format: the server computes every
-- derived/financial value once and clients render exactly what they receive, so
-- clients never need the settings or wage pipeline locally.
-- ---------------------------------------------------------------------------
local function writeSnapshot(streamId, snap)
    snap = snap or {}
    local levels   = snap.levels   or { novice = 0, experienced = 0, master = 0 }
    local finance  = snap.finance  or {}
    local workers  = snap.workers  or {}
    local recruits = snap.recruits or {}

    streamWriteInt32(streamId, snap.count   or 0)
    streamWriteInt32(streamId, snap.working or 0)
    streamWriteInt32(streamId, snap.pinned  or 0)
    streamWriteInt32(streamId, levels.novice or 0)
    streamWriteInt32(streamId, levels.experienced or 0)
    streamWriteInt32(streamId, levels.master or 0)

    -- Finance block
    streamWriteFloat32(streamId, finance.baseRate or 0)
    streamWriteBool(streamId,    finance.isHourly == true)
    streamWriteString(streamId,  finance.costModeName or "")
    streamWriteString(streamId,  finance.wageLevelName or "")
    streamWriteInt32(streamId,   finance.monthAccrued or 0)
    streamWriteInt32(streamId,   finance.estIntervalCost or 0)
    streamWriteFloat32(streamId, finance.proStaffDelta or 0)

    -- Workers
    streamWriteInt32(streamId, #workers)
    for _, w in ipairs(workers) do
        streamWriteInt32(streamId,   w.uuid or 0)
        streamWriteString(streamId,  w.name or "Worker")
        streamWriteUInt8(streamId,   w.level or 1)
        streamWriteFloat32(streamId, w.totalHours or 0)
        streamWriteInt32(streamId,   w.totalJobs or 0)
        streamWriteFloat32(streamId, w.fatigue or 0)
        streamWriteBool(streamId,    w.working == true)
        streamWriteBool(streamId,    w.pinned == true)
        streamWriteFloat32(streamId, w.baseRate or 0)
        streamWriteFloat32(streamId, w.effRate or 0)
        streamWriteInt32(streamId,   w.severance or 0)
    end

    -- Recruit pool
    streamWriteInt32(streamId, #recruits)
    for _, r in ipairs(recruits) do
        streamWriteUInt8(streamId,  r.slot or 1)
        streamWriteString(streamId, r.name or "Recruit")
        streamWriteUInt8(streamId,  r.level or 1)
        streamWriteInt32(streamId,  r.hireCost or 0)
    end
end

local function readSnapshot(streamId)
    local snap = {
        authoritative = true,   -- a received snapshot is, by definition, server truth
        levels  = {},
        finance = {},
        workers = {},
        recruits = {},
    }

    snap.count   = streamReadInt32(streamId)
    snap.working = streamReadInt32(streamId)
    snap.pinned  = streamReadInt32(streamId)
    snap.levels.novice      = streamReadInt32(streamId)
    snap.levels.experienced = streamReadInt32(streamId)
    snap.levels.master      = streamReadInt32(streamId)

    snap.finance.baseRate        = streamReadFloat32(streamId)
    snap.finance.isHourly        = streamReadBool(streamId)
    snap.finance.costModeName    = streamReadString(streamId)
    snap.finance.wageLevelName   = streamReadString(streamId)
    snap.finance.monthAccrued    = streamReadInt32(streamId)
    snap.finance.estIntervalCost = streamReadInt32(streamId)
    snap.finance.proStaffDelta   = streamReadFloat32(streamId)

    local workerCount = streamReadInt32(streamId)
    for _ = 1, workerCount do
        local w = {}
        w.uuid       = streamReadInt32(streamId)
        w.name       = streamReadString(streamId)
        w.level      = streamReadUInt8(streamId)
        w.totalHours = streamReadFloat32(streamId)
        w.totalJobs  = streamReadInt32(streamId)
        w.fatigue    = streamReadFloat32(streamId)
        w.working    = streamReadBool(streamId)
        w.pinned     = streamReadBool(streamId)
        w.baseRate   = streamReadFloat32(streamId)
        w.effRate    = streamReadFloat32(streamId)
        w.severance  = streamReadInt32(streamId)
        -- Derive the display-only fields the server didn't ship.
        w.levelName     = WorkerRoster.levelName(w.level)
        w.proStaffDelta = (w.effRate or 0) - (w.baseRate or 0)
        local status = w.working and "working" or "idle"
        if w.pinned then status = status .. ", pinned" end
        w.status = status
        snap.workers[#snap.workers + 1] = w
    end

    local recruitCount = streamReadInt32(streamId)
    for _ = 1, recruitCount do
        local r = {}
        r.slot     = streamReadUInt8(streamId)
        r.name     = streamReadString(streamId)
        r.level    = streamReadUInt8(streamId)
        r.hireCost = streamReadInt32(streamId)
        r.levelName = WorkerRoster.levelName(r.level)
        snap.recruits[#snap.recruits + 1] = r
    end

    return snap
end

-- ========================================
-- WORKER COMMAND EVENT (Client -> Server)
-- ========================================
-- A single command channel for every roster mutation. The server applies it and
-- then broadcasts a fresh WCRosterSyncEvent so all peers converge.
WCWorkerCommandEvent = {}
WCWorkerCommandEvent_mt = Class(WCWorkerCommandEvent, Event)

InitEventClass(WCWorkerCommandEvent, "WCWorkerCommandEvent")

function WCWorkerCommandEvent.emptyNew()
    return Event.new(WCWorkerCommandEvent_mt)
end

function WCWorkerCommandEvent.new(action, uuid, slot, vehicleUniqueId, farmId)
    local self = WCWorkerCommandEvent.emptyNew()
    self.action          = action or 0
    self.uuid            = uuid or 0
    self.slot            = slot or 1
    self.vehicleUniqueId = vehicleUniqueId or ""
    self.farmId          = farmId or 0
    return self
end

function WCWorkerCommandEvent:readStream(streamId, connection)
    self.action          = streamReadUInt8(streamId)
    self.uuid            = streamReadInt32(streamId)
    self.slot            = streamReadUInt8(streamId)
    self.vehicleUniqueId = streamReadString(streamId)
    self.farmId          = streamReadInt32(streamId)
    self:run(connection)
end

function WCWorkerCommandEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId,  self.action)
    streamWriteInt32(streamId,  self.uuid)
    streamWriteUInt8(streamId,  self.slot)
    streamWriteString(streamId, self.vehicleUniqueId)
    streamWriteInt32(streamId,  self.farmId)
end

function WCWorkerCommandEvent:run(connection)
    -- SERVER ONLY: validate the originating farm, then apply + broadcast.
    if g_server == nil then return end

    local wm = g_currentMission and g_currentMission.workerCostsManager
    if not wm then return end

    -- Reject a spoofed/absent farm id for the money-spending actions. The client
    -- sends its own getFarmId(); a real farm must exist for hire/fire to charge.
    if (self.action == WCCommand.HIRE or self.action == WCCommand.FIRE) then
        if not self.farmId or self.farmId == 0 then
            Logging.warning("[Worker Costs] Rejected command (action=%d) — invalid farmId", self.action)
            return
        end
    end

    wm:_applyCommandFromNetwork(self.action, self.uuid, self.slot, self.vehicleUniqueId, self.farmId)
end

-- ========================================
-- ROSTER SYNC EVENT (Server -> Client[s])
-- ========================================
-- Carries the full enriched snapshot. Sent to one connection on join request, and
-- broadcast to all after every mutation. Pure clients cache it; the host ignores
-- its own broadcast (it computes the snapshot live).
WCRosterSyncEvent = {}
WCRosterSyncEvent_mt = Class(WCRosterSyncEvent, Event)

InitEventClass(WCRosterSyncEvent, "WCRosterSyncEvent")

function WCRosterSyncEvent.emptyNew()
    return Event.new(WCRosterSyncEvent_mt)
end

function WCRosterSyncEvent.new(snapshot)
    local self = WCRosterSyncEvent.emptyNew()
    self.snapshot = snapshot or {}
    return self
end

function WCRosterSyncEvent:readStream(streamId, connection)
    self.snapshot = readSnapshot(streamId)
    self:run(connection)
end

function WCRosterSyncEvent:writeStream(streamId, connection)
    writeSnapshot(streamId, self.snapshot)
end

function WCRosterSyncEvent:run(connection)
    -- CLIENT ONLY. On a listen-server host g_server is set; it owns the live roster
    -- and must not overwrite it with a mirror, so bail when we are the server.
    if g_client == nil or g_server ~= nil then return end

    local wm = g_currentMission and g_currentMission.workerCostsManager
    if wm then
        wm:applyClientSnapshot(self.snapshot)
    end
end

-- ========================================
-- REQUEST ROSTER SYNC (Client -> Server)
-- ========================================
WCRequestRosterSyncEvent = {}
WCRequestRosterSyncEvent_mt = Class(WCRequestRosterSyncEvent, Event)

InitEventClass(WCRequestRosterSyncEvent, "WCRequestRosterSyncEvent")

function WCRequestRosterSyncEvent.emptyNew()
    return Event.new(WCRequestRosterSyncEvent_mt)
end

function WCRequestRosterSyncEvent.new()
    return WCRequestRosterSyncEvent.emptyNew()
end

function WCRequestRosterSyncEvent:readStream(streamId, connection)
    self:run(connection)
end

function WCRequestRosterSyncEvent:writeStream(streamId, connection)
    -- No payload.
end

function WCRequestRosterSyncEvent:run(connection)
    -- SERVER ONLY: reply to the requesting connection with the current snapshot.
    if g_server == nil or not connection then return end
    local wm = g_currentMission and g_currentMission.workerCostsManager
    if wm then
        connection:sendEvent(WCRosterSyncEvent.new(wm:getServerSnapshot()))
    end
end

-- ========================================
-- HELPERS — the single entry points the rest of the mod calls
-- ========================================

--- Issue a roster command. Routes to the server on a client, applies directly on
--- the server/SP. Every caller (tablet, roster panel) goes through here so the
--- SP and MP paths can never drift.
function WCNetwork_SendCommand(action, uuid, slot, vehicleUniqueId, farmId)
    if g_client ~= nil and g_server == nil then
        -- Pure client: ask the server.
        g_client:getServerConnection():sendEvent(
            WCWorkerCommandEvent.new(action, uuid, slot, vehicleUniqueId, farmId))
    else
        -- Server / single-player: apply immediately.
        local wm = g_currentMission and g_currentMission.workerCostsManager
        if wm then
            wm:_applyCommandFromNetwork(action, uuid, slot, vehicleUniqueId, farmId)
        end
    end
end

--- Pure clients call this to pull the roster from the host (on join + retries).
function WCNetwork_RequestRosterSync()
    if g_client ~= nil and g_server == nil then
        g_client:getServerConnection():sendEvent(WCRequestRosterSyncEvent.new())
    end
end

Logging.info("[Worker Costs] Network events loaded (Pro-Staff MP layer)")

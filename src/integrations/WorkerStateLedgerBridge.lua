-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WorkerStateLedgerBridge — optional bridge to FS25_StateLedger (bedrock)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- Strictly delegate-when-present, mirroring SoilFertilizer's StateLedger bridge:
--   * StateLedger installed -> the shared master save file is the LOAD source of
--     truth for the roster and hire-hall lifecycle. workerData.xml and
--     hireHallCore.xml are still written every save as standalone safety copies,
--     so removing the ledger later never loses data.
--   * StateLedger absent    -> nothing changes; the two own XML files are primary
--     exactly as before.
--
-- Two modules, preserving WorkerCosts' deliberate file isolation (a bad job-history
-- write can never corrupt the roster):
--   * WorkerCosts_Roster   <-> WorkerRoster:toTable / applyTable
--   * WorkerCosts_HireHall <-> HireHallCore.Schema:toTable / applyTable
-- Both modIds are persistence keys inside the master file, LOCKED by Claude(A); a
-- rename orphans saved data, so they are never changed after first persist.
--
-- Timing note (differs from SoilFertilizer): WorkerCosts loads its roster inside
-- Mission00.loadMission00Finished, the same phase StateLedger parses its file in.
-- SoilFertilizer reads later (onMissionStarted), so hook order never mattered for
-- it. Here it would, so register() force-triggers the (idempotent) parse after
-- registering, guaranteeing deserialize has delivered before loadWorkerData reads
-- regardless of which mod's loadMission00Finished handler runs first.
--
-- The cross-mod handle is g_currentMission.stateLedger (published in Mission00.load
-- by both mods, so it is available here whatever the mod load order).
-- =========================================================

WorkerStateLedgerBridge = WorkerStateLedgerBridge or {}

-- LOCKED persistence keys (see BEDROCK-MIGRATION-BUILD-BRIEF). Never rename.
WorkerStateLedgerBridge.ROSTER_MODULE_ID   = "WorkerCosts_Roster"
WorkerStateLedgerBridge.HIREHALL_MODULE_ID = "WorkerCosts_HireHall"

WorkerStateLedgerBridge.active            = false   -- ledger present and we registered
WorkerStateLedgerBridge.rosterDelivered   = false   -- roster deserialize has fired
WorkerStateLedgerBridge.rosterPending     = nil     -- cached roster table (nil = new/no block)
WorkerStateLedgerBridge.hireHallDelivered = false   -- hire-hall deserialize has fired
WorkerStateLedgerBridge.hireHallPending   = nil     -- cached hire-hall table (nil = new/no block)

-- ---------------------------------------------------------------------------
-- Roster module
-- ---------------------------------------------------------------------------

--- True when the ledger is the roster load source of truth this session (present,
--- registered, and it delivered an actual block). When present but empty (new save
--- or first load after installing the ledger), loadWorkerData imports workerData.xml.
function WorkerStateLedgerBridge.hasRosterState()
    return WorkerStateLedgerBridge.active
        and WorkerStateLedgerBridge.rosterDelivered
        and WorkerStateLedgerBridge.rosterPending ~= nil
end

--- Apply the cached roster block into the given roster. Returns true if a real
--- block was applied.
function WorkerStateLedgerBridge.applyRosterState(roster)
    if roster == nil or type(WorkerStateLedgerBridge.rosterPending) ~= "table" then
        return false
    end
    return roster:applyTable(WorkerStateLedgerBridge.rosterPending)
end

-- ---------------------------------------------------------------------------
-- Hire-hall lifecycle module
-- ---------------------------------------------------------------------------

--- True when the ledger holds a hire-hall block to re-attach this session.
function WorkerStateLedgerBridge.hasHireHallState()
    return WorkerStateLedgerBridge.active
        and WorkerStateLedgerBridge.hireHallDelivered
        and WorkerStateLedgerBridge.hireHallPending ~= nil
end

--- Re-attach the cached hire-hall lifecycle block onto the roster's workers. The
--- roster must already be loaded (uuids must resolve), which holds because
--- loadWorkerData runs before HireHallCore:initialize.
function WorkerStateLedgerBridge.applyHireHallState(roster)
    if roster == nil or type(WorkerStateLedgerBridge.hireHallPending) ~= "table" then
        return false
    end
    if HireHallCore == nil or HireHallCore.Schema == nil then
        return false
    end
    return HireHallCore.Schema:applyTable(WorkerStateLedgerBridge.hireHallPending, roster)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

--- Register both modules with StateLedger if present. Called from
--- WorkerManager:onMissionLoaded, before the server loads the roster from disk.
function WorkerStateLedgerBridge.register(mgr)
    -- Reset per-load so a map swap / reload starts clean.
    WorkerStateLedgerBridge.active            = false
    WorkerStateLedgerBridge.rosterDelivered   = false
    WorkerStateLedgerBridge.rosterPending     = nil
    WorkerStateLedgerBridge.hireHallDelivered = false
    WorkerStateLedgerBridge.hireHallPending   = nil

    local ledger = (g_currentMission ~= nil and g_currentMission.stateLedger) or g_stateLedger
    if ledger == nil then
        Logging.info("[Worker Costs] StateLedger not detected; roster uses its own workerData.xml / hireHallCore.xml")
        return
    end
    if mgr == nil then
        return
    end

    local ok, err = pcall(function()
        ledger:registerModule(WorkerStateLedgerBridge.ROSTER_MODULE_ID, {
            serialize = function()
                if mgr.workerRoster == nil then
                    return { version = WorkerRoster.SCHEMA_VERSION, workers = {} }
                end
                return mgr.workerRoster:toTable()
            end,
            deserialize = function(data)
                WorkerStateLedgerBridge.rosterDelivered = true
                WorkerStateLedgerBridge.rosterPending   = data   -- nil on a brand-new save
            end,
        })

        ledger:registerModule(WorkerStateLedgerBridge.HIREHALL_MODULE_ID, {
            serialize = function()
                -- Same roster instance HireHallCore was set up with (WorkerManager
                -- passes self.workerRoster to HireHallCore:setup).
                if HireHallCore == nil or HireHallCore.Schema == nil then
                    return { version = 0, workers = {} }
                end
                return HireHallCore.Schema:toTable(mgr.workerRoster)
            end,
            deserialize = function(data)
                WorkerStateLedgerBridge.hireHallDelivered = true
                WorkerStateLedgerBridge.hireHallPending   = data
            end,
        })
    end)

    if not ok then
        Logging.warning("[Worker Costs] StateLedger registration failed: %s (falling back to own XML)", tostring(err))
        return
    end

    WorkerStateLedgerBridge.active = true

    -- Force the (idempotent, server-only-effectful) parse now so deserialize has
    -- delivered before loadWorkerData reads a few lines later, independent of which
    -- mod's loadMission00Finished handler ran first. A no-op if StateLedger already
    -- parsed (it loaded first), in which case deserialize fired at registerModule.
    if ledger.parseFile ~= nil then
        pcall(function() ledger:parseFile() end)
    end

    Logging.info("[Worker Costs] Registered with StateLedger as '%s' + '%s' (own XML kept as safety copy)",
        WorkerStateLedgerBridge.ROSTER_MODULE_ID, WorkerStateLedgerBridge.HIREHALL_MODULE_ID)
end

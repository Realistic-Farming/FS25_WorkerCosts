-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WorkerRoster — the mod-owned employee roster (Pro-Staff Phase 0)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- WHAT THIS IS
--   FS25 has no engine-side "worker" object that carries XP, seniority, or a
--   stable identity (a helper is just a name attached to a vehicle for the life
--   of one AI job). Per docs/PRO_STAFF_PLAN.md §3-4 the mod owns its own roster.
--   This file is that roster plus its self-contained savegame persistence.
--
-- PRO-STAFF BUILD CHECKLIST — work that lives in THIS file, ticked per phase
-- (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 0 — identity model + workerData.xml persistence
--   [x] Phase 1 — roster API for job attribution (createWorker / assignVehicle /
--                 getWorkerByVehicle / findIdleByName / unassignVehicle)
--   [ ] Phase 2 — XP accrual + Novice/Experienced/Master tier from totalXP
--   [ ] Phase 3 — fatigue feeds the wage modifier pipeline
--   [ ] Phase 4 — (no change here; UI reads the roster via the manager)
--   [ ] Phase 5 — getRosterSnapshot() read API + MP (de)serialization, and
--                 persist a STABLE vehicle uniqueId for assignedVehicleId
-- =========================================================

---@class WorkerRoster
WorkerRoster = {}
local WorkerRoster_mt = Class(WorkerRoster)

-- Persistence identifiers
WorkerRoster.SAVE_FILE      = "workerData.xml"
WorkerRoster.SAVE_ROOT      = "workerData"
WorkerRoster.SCHEMA_VERSION = "1.0"

-- Level tiers. XP -> level mapping is wired in Phase 2; defined here so the
-- model has a single source of truth from the start.
WorkerRoster.LEVEL_NOVICE      = 1
WorkerRoster.LEVEL_EXPERIENCED = 2
WorkerRoster.LEVEL_MASTER      = 3

function WorkerRoster.new()
    local self = setmetatable({}, WorkerRoster_mt)
    self.workers = {}   -- array, insertion order (stable for UI lists)
    self.byId    = {}   -- [uuid] -> worker, O(1) lookup
    self.nextId  = 1    -- monotonic, never reused; persisted so ids survive reload
    return self
end

--- Build a worker record with every Pro-Staff field defaulted.
-- `uuid` holds a stable integer id (never reused). It is named "uuid" to match
-- the roster contract in docs/PRO_STAFF_PLAN.md §4; an integer is sufficient and
-- collision-proof in the Lua 5.1 sandbox (no os.time/random seeding needed).
function WorkerRoster.newWorker(uuid, name)
    return {
        uuid       = uuid,
        name       = name or "Worker",
        level      = WorkerRoster.LEVEL_NOVICE,
        totalXP    = 0,
        totalHours = 0,
        totalJobs  = 0,
        fatigue    = 0,
        hiredDay   = (g_currentMission and g_currentMission.environment
                      and g_currentMission.environment.currentDay) or 0,
        -- Runtime-only in Phase 0. A runtime vehicle id is meaningless next
        -- session, so it is deliberately NOT written to disk (see save()).
        -- Phase 5 persists a stable vehicle uniqueId and re-binds on load.
        assignedVehicleId = nil,
    }
end

-- ---------------------------------------------------------------------------
-- Roster operations
-- ---------------------------------------------------------------------------

--- Hire: create and register a new worker. Returns the worker record.
function WorkerRoster:createWorker(name)
    local worker = WorkerRoster.newWorker(self.nextId, name)
    self.nextId = self.nextId + 1
    table.insert(self.workers, worker)
    self.byId[worker.uuid] = worker
    return worker
end

function WorkerRoster:getWorker(uuid)
    return self.byId[uuid]
end

function WorkerRoster:getAll()
    return self.workers
end

function WorkerRoster:getCount()
    return #self.workers
end

--- Fire: remove a worker by id. Returns true if one was removed.
function WorkerRoster:removeWorker(uuid)
    local worker = self.byId[uuid]
    if not worker then
        return false
    end
    self.byId[uuid] = nil
    for i, w in ipairs(self.workers) do
        if w.uuid == uuid then
            table.remove(self.workers, i)
            break
        end
    end
    return true
end

function WorkerRoster:getWorkerByVehicle(vehicleId)
    if vehicleId == nil then
        return nil
    end
    for _, w in ipairs(self.workers) do
        if w.assignedVehicleId == vehicleId then
            return w
        end
    end
    return nil
end

--- Find an unassigned worker by display name. Used by the Phase 1 auto-hire
-- bridge to reconnect a returning named helper to a new job instead of growing
-- the roster without bound.
function WorkerRoster:findIdleByName(name)
    if name == nil then
        return nil
    end
    for _, w in ipairs(self.workers) do
        if w.assignedVehicleId == nil and w.name == name then
            return w
        end
    end
    return nil
end

--- Bind a worker to a vehicle (one vehicle holds at most one worker).
function WorkerRoster:assignVehicle(uuid, vehicleId)
    local worker = self.byId[uuid]
    if not worker then
        return false
    end
    self:unassignVehicle(vehicleId)
    worker.assignedVehicleId = vehicleId
    return true
end

--- Clear any worker currently bound to the given vehicle.
function WorkerRoster:unassignVehicle(vehicleId)
    if vehicleId == nil then
        return
    end
    for _, w in ipairs(self.workers) do
        if w.assignedVehicleId == vehicleId then
            w.assignedVehicleId = nil
        end
    end
end

function WorkerRoster:clear()
    self.workers = {}
    self.byId    = {}
    self.nextId  = 1
end

-- ---------------------------------------------------------------------------
-- Persistence (server/SP only — callers guard the multiplayer case)
-- Mirrors the proven XMLFile.create / loadIfExists / iterate pattern.
-- ---------------------------------------------------------------------------

--- Write the roster to its own savegame file. Always writes (even when empty)
-- so nextId stays monotonic across a hire-then-fire-everyone cycle.
function WorkerRoster:save(missionInfo)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir then
        Logging.warning("[Worker Costs] Roster save skipped — no savegame directory")
        return false
    end

    local path = dir .. "/" .. WorkerRoster.SAVE_FILE
    local xmlFile = XMLFile.create("wc_RosterXML", path, WorkerRoster.SAVE_ROOT)
    if xmlFile == nil then
        Logging.warning("[Worker Costs] Failed to create roster save file: " .. path)
        return false
    end

    local root = WorkerRoster.SAVE_ROOT
    xmlFile:setString(root .. "#version", WorkerRoster.SCHEMA_VERSION)
    xmlFile:setInt(root .. "#nextId", self.nextId)
    xmlFile:setInt(root .. "#count", #self.workers)

    for i, w in ipairs(self.workers) do
        local key = string.format("%s.worker(%d)", root, i - 1)
        xmlFile:setInt(key .. "#uuid", w.uuid)
        xmlFile:setString(key .. "#name", w.name or "Worker")
        xmlFile:setInt(key .. "#level", w.level or WorkerRoster.LEVEL_NOVICE)
        xmlFile:setFloat(key .. "#totalXP", w.totalXP or 0)
        xmlFile:setFloat(key .. "#totalHours", w.totalHours or 0)
        xmlFile:setInt(key .. "#totalJobs", w.totalJobs or 0)
        xmlFile:setFloat(key .. "#fatigue", w.fatigue or 0)
        xmlFile:setInt(key .. "#hiredDay", w.hiredDay or 0)
        -- assignedVehicleId intentionally omitted in Phase 0 (see newWorker()).
    end

    xmlFile:save()
    xmlFile:delete()
    Logging.info(string.format("[Worker Costs] Roster saved (%d workers) -> %s", #self.workers, path))
    return true
end

--- Read the roster back. Returns false (and leaves an empty roster) for a new
-- career with no save file yet.
function WorkerRoster:loadIfExists(missionInfo)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir then
        return false
    end

    local path = dir .. "/" .. WorkerRoster.SAVE_FILE
    local xmlFile = XMLFile.loadIfExists("wc_RosterXML", path, WorkerRoster.SAVE_ROOT)
    if xmlFile == nil then
        Logging.info("[Worker Costs] No roster save found (new career) — starting empty")
        return false
    end

    self:clear()

    local root = WorkerRoster.SAVE_ROOT
    local savedNextId = xmlFile:getInt(root .. "#nextId", 1)
    local maxId = 0

    xmlFile:iterate(root .. ".worker", function(_, key)
        local uuid = xmlFile:getInt(key .. "#uuid")
        if uuid == nil then
            return
        end
        local w = {
            uuid       = uuid,
            name       = xmlFile:getString(key .. "#name", "Worker"),
            level      = xmlFile:getInt(key .. "#level", WorkerRoster.LEVEL_NOVICE),
            totalXP    = xmlFile:getFloat(key .. "#totalXP", 0),
            totalHours = xmlFile:getFloat(key .. "#totalHours", 0),
            totalJobs  = xmlFile:getInt(key .. "#totalJobs", 0),
            fatigue    = xmlFile:getFloat(key .. "#fatigue", 0),
            hiredDay   = xmlFile:getInt(key .. "#hiredDay", 0),
            assignedVehicleId = nil,  -- re-bound at runtime (Phase 5)
        }
        table.insert(self.workers, w)
        self.byId[uuid] = w
        if uuid > maxId then
            maxId = uuid
        end
    end)

    xmlFile:delete()

    -- Never reuse an id: honor the saved counter, but stay ahead of any id we
    -- actually loaded in case the counter was lost or hand-edited.
    self.nextId = math.max(savedNextId, maxId + 1)
    Logging.info(string.format("[Worker Costs] Roster loaded (%d workers, nextId=%d)",
        #self.workers, self.nextId))
    return true
end

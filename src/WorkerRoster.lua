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
--   [x] Phase 2 — levelForXP / recomputeLevel / levelName (Novice/Exp/Master)
--   [x] Phase 3 — fatigue model (addFatigue / recoverFatigue) for the wage pipeline
--   [ ] Phase 4 — (no change here; UI reads the roster via the manager)
--   [~] Phase 5 — persistent assignment by stable vehicle uniqueId DONE; still
--                 to do: getRosterSnapshot() read API + MP (de)serialization
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

-- Pro-Staff Phase 2: XP -> level thresholds. XP accrues at 1 per real hour
-- worked (see WorkerJobTracker), so these are effectively "hours worked". Tunable.
WorkerRoster.XP_EXPERIENCED = 40
WorkerRoster.XP_MASTER      = 160

-- Pro-Staff Phase 3: fatigue model (0..1). Accrues with work, recovers when idle.
WorkerRoster.FATIGUE_MAX          = 1.0
WorkerRoster.FATIGUE_PER_HOUR     = 0.05   -- added per real hour worked
WorkerRoster.FATIGUE_RECOVERY_DAY = 0.34   -- removed per full idle in-game day

function WorkerRoster.new()
    local self = setmetatable({}, WorkerRoster_mt)
    self.workers = {}   -- array, insertion order (stable for UI lists)
    self.byId    = {}   -- [uuid] -> worker, O(1) lookup
    self.nextId  = 1    -- monotonic, never reused; persisted so ids survive reload
    -- Hiring-Hall daily-cap state (#69). Stored in this mod's career file
    -- (workerData.xml) because it is per-career, server-authoritative hall state;
    -- the WorkerManager owns the policy (limit + day rollover), the roster just
    -- persists the two scalars.
    self.hiredToday  = 0
    self.lastHireDay = -1
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
        -- TRANSIENT runtime binding: which vehicle this worker is driving RIGHT
        -- NOW (set for the duration of one AI job). Runtime-only, never saved.
        assignedVehicleId = nil,
        -- PERSISTENT manual assignment (Phase 5): the stable vehicle uniqueId a
        -- player pinned this worker to. Saved; survives reload. Re-binds naturally
        -- when a job starts on that vehicle (its uniqueId matches).
        assignedVehicleUniqueId = nil,
        -- "Trusted Employee" favorite flag (#67). Trusted workers sort to the top of
        -- the roster lists. Persistent; survives save/reload.
        trusted = false,
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

--- O(1) existence check by uuid. FR5's job monitor calls this as a hard guard
--- before writing history, so an orphaned (fired-in-same-frame) worker is skipped.
function WorkerRoster:getWorkerExists(uuid)
    return uuid ~= nil and self.byId[uuid] ~= nil
end

--- A display-ordered VIEW of the roster (#67): Trusted ("favorite") workers first,
--- then the rest, each group preserving stable insertion order (uuid is monotonic).
--- Returns a fresh array — never the live self.workers — so callers can't reorder
--- the canonical list. Used by the roster panel and the snapshot so every surface
--- shows trusted staff pinned to the top.
function WorkerRoster:getDisplayOrder()
    local list = {}
    for i = 1, #self.workers do
        list[i] = self.workers[i]
    end
    table.sort(list, function(a, b)
        local ta = a.trusted and 1 or 0
        local tb = b.trusted and 1 or 0
        if ta ~= tb then
            return ta > tb            -- trusted (1) ahead of untrusted (0)
        end
        return (a.uuid or 0) < (b.uuid or 0)   -- stable: insertion/hire order
    end)
    return list
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

--- Find a free worker by display name. "Free" = not currently working AND not
-- pinned to a vehicle (so the bridge never steals a manually-assigned worker).
-- Used by the Phase 1 auto-hire bridge to reconnect a returning named helper.
function WorkerRoster:findIdleByName(name)
    if name == nil then
        return nil
    end
    for _, w in ipairs(self.workers) do
        if w.assignedVehicleId == nil and w.assignedVehicleUniqueId == nil and w.name == name then
            return w
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Phase 5: persistent manual assignment (by stable vehicle uniqueId)
-- ---------------------------------------------------------------------------

--- The worker a player pinned to this vehicle uniqueId, if any.
function WorkerRoster:getByAssignedUniqueId(vehicleUniqueId)
    if vehicleUniqueId == nil then
        return nil
    end
    for _, w in ipairs(self.workers) do
        if w.assignedVehicleUniqueId == vehicleUniqueId then
            return w
        end
    end
    return nil
end

--- Pin a worker to a vehicle (by its stable uniqueId). One vehicle holds at most
-- one pinned worker; any previous holder of that vehicle is released first.
function WorkerRoster:assignVehiclePersistent(uuid, vehicleUniqueId)
    local worker = self.byId[uuid]
    if not worker or vehicleUniqueId == nil then
        return false
    end
    local prev = self:getByAssignedUniqueId(vehicleUniqueId)
    if prev and prev.uuid ~= uuid then
        prev.assignedVehicleUniqueId = nil
    end
    worker.assignedVehicleUniqueId = vehicleUniqueId
    return true
end

--- Drop a worker's persistent assignment.
function WorkerRoster:unassignPersistent(uuid)
    local worker = self.byId[uuid]
    if not worker then
        return false
    end
    worker.assignedVehicleUniqueId = nil
    return true
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
    self.hiredToday  = 0
    self.lastHireDay = -1
end

-- ---------------------------------------------------------------------------
-- Phase 2: levels  /  Phase 3: fatigue (model-level mutators)
-- ---------------------------------------------------------------------------

--- The level tier implied by an XP total.
function WorkerRoster.levelForXP(xp)
    xp = xp or 0
    if xp >= WorkerRoster.XP_MASTER then
        return WorkerRoster.LEVEL_MASTER
    elseif xp >= WorkerRoster.XP_EXPERIENCED then
        return WorkerRoster.LEVEL_EXPERIENCED
    end
    return WorkerRoster.LEVEL_NOVICE
end

--- Human-readable level name (also used by the UI and console dump).
function WorkerRoster.levelName(level)
    if level == WorkerRoster.LEVEL_MASTER then
        return "Master"
    elseif level == WorkerRoster.LEVEL_EXPERIENCED then
        return "Experienced"
    end
    return "Novice"
end

--- Recompute a worker's level from its XP. Returns the new level if it changed
-- (so callers can fire a level-up notification), or nil if unchanged.
function WorkerRoster:recomputeLevel(worker)
    if not worker then
        return nil
    end
    local newLevel = WorkerRoster.levelForXP(worker.totalXP or 0)
    if newLevel ~= worker.level then
        worker.level = newLevel
        return newLevel
    end
    return nil
end

--- Add fatigue for `hours` of work, clamped to FATIGUE_MAX.
function WorkerRoster.addFatigue(worker, hours)
    if not worker then return end
    worker.fatigue = math.min(WorkerRoster.FATIGUE_MAX,
        (worker.fatigue or 0) + (hours or 0) * WorkerRoster.FATIGUE_PER_HOUR)
end

--- Recover fatigue for `days` of rest, floored at 0.
function WorkerRoster.recoverFatigue(worker, days)
    if not worker then return end
    worker.fatigue = math.max(0,
        (worker.fatigue or 0) - (days or 1) * WorkerRoster.FATIGUE_RECOVERY_DAY)
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
    -- Hiring-Hall daily-cap state (#69) — per-career hall state in this same file.
    xmlFile:setInt(root .. "#hiredToday", self.hiredToday or 0)
    xmlFile:setInt(root .. "#lastHireDay", self.lastHireDay or -1)

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
        -- Persistent manual assignment (Phase 5). The transient assignedVehicleId
        -- is still NOT saved (a runtime pointer is meaningless next session).
        if w.assignedVehicleUniqueId then
            xmlFile:setString(key .. "#assignedVehicleUniqueId", w.assignedVehicleUniqueId)
        end
        -- Trusted/favorite flag (#67). Only written when set, to keep files small.
        if w.trusted then
            xmlFile:setBool(key .. "#trusted", true)
        end
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
    -- Hiring-Hall daily-cap state (#69). Defaults keep a pre-#69 save uncapped on
    -- its first day (lastHireDay = -1 forces a rollover-reset on the next hire).
    self.hiredToday  = xmlFile:getInt(root .. "#hiredToday", 0)
    self.lastHireDay = xmlFile:getInt(root .. "#lastHireDay", -1)
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
            assignedVehicleId = nil,  -- transient; re-bound at job start
            assignedVehicleUniqueId = xmlFile:getString(key .. "#assignedVehicleUniqueId", nil),
            trusted = xmlFile:getBool(key .. "#trusted", false),
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

-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WorkerJobTracker — event-driven AI job lifecycle (Pro-Staff Phase 1)
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
--   The identity/lifecycle half of the worker system. It subscribes to the
--   engine's AI job messages and attributes each job to a persistent roster
--   worker, finalizing that worker's hours / jobs / XP when the job ends.
--   Billing stays in WorkerSystem's per-frame tick — this is the documented
--   "hybrid, not a rewrite" from docs/PRO_STAFF_PLAN.md §Phase 1.
--
-- VERIFIED ENGINE FACTS (game source: ai/AISystem.lua)
--   * MessageType.AI_JOB_STARTED is published as (job, startFarmId)
--   * MessageType.AI_JOB_STOPPED is published as (job, aiMessage)
--     (the proposal's "AI_JOB_FINISHED" does not exist — plan §2.1)
--   * g_messageCenter prepends the subscribe() target as the FIRST callback arg
--     (the receiver), THEN the published args. So a method reference is the
--     correct shape: subscribe(MessageType.X, self.handler, self) invokes
--     self:handler(publishedArgs...). Verified in game source — Dog,
--     FarmlandManager, FieldManager, etc. all use the `self.handler, self` form.
--     (A plain closure would receive the target as its first param — the arg
--      shift that left the roster empty in the first 2.0.0 test build.)
--   * Both publish inside *Internal() on the server, so handling is server-only.
--
-- PRO-STAFF BUILD CHECKLIST — work in THIS file, ticked per phase
-- (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 1 — AI_JOB_STARTED/STOPPED subscription; attribute jobs to roster
--                 workers (auto-hire bridge); finalize hours/jobs/XP on stop
--   [ ] Phase 2 — recompute Novice/Experienced/Master tier from totalXP on stop
--   [ ] Phase 3 — feed fatigue / overtime signals into the wage pipeline
--   [ ] Phase 4 — surface the job-complete summary in the UI (currently log-only)
--   [ ] Phase 5 — broadcast roster mutations (hire/assign/level) to MP clients
-- =========================================================

---@class WorkerJobTracker
WorkerJobTracker = {}
local WorkerJobTracker_mt = Class(WorkerJobTracker)

local MS_PER_HOUR = 3600000  -- real milliseconds in one hour (g_currentMission.time basis)

---@param roster WorkerRoster
---@param settings Settings
---@return WorkerJobTracker
function WorkerJobTracker.new(roster, settings)
    local self = setmetatable({}, WorkerJobTracker_mt)
    self.roster   = roster
    self.settings = settings
    -- [job] -> { workerUuid, vehicleId, startTime, name }
    -- Keyed by the job table reference: the same instance is passed to both the
    -- START and STOP handlers on the server, so this needs no job id lookup.
    self.activeJobs  = {}
    self.subscribed  = false
    return self
end

--- Subscribe to the AI job lifecycle. Server/SP only — the caller guards.
function WorkerJobTracker:initialize()
    if self.subscribed then
        return
    end
    if not g_messageCenter or not MessageType then
        Logging.warning("[Worker Costs] g_messageCenter/MessageType unavailable — job lifecycle not tracked")
        return
    end
    if MessageType.AI_JOB_STARTED == nil or MessageType.AI_JOB_STOPPED == nil then
        Logging.warning("[Worker Costs] MessageType.AI_JOB_STARTED/STOPPED not found — job lifecycle not tracked")
        return
    end

    -- g_messageCenter prepends the target as the callback receiver (see header),
    -- so the methods are passed directly: this calls self:_onJobStarted(job,
    -- startFarmId) and self:_onJobStopped(job, aiMessage). target=self also lets
    -- unsubscribeAll(self) drop both on unload.
    g_messageCenter:subscribe(MessageType.AI_JOB_STARTED, self._onJobStarted, self)
    g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, self._onJobStopped, self)

    self.subscribed = true
    Logging.info("[Worker Costs] Job lifecycle hooks installed (AI_JOB_STARTED / AI_JOB_STOPPED)")
end

--- Unsubscribe and drop any in-flight job records. Called on mission unload.
function WorkerJobTracker:delete()
    if g_messageCenter then
        g_messageCenter:unsubscribeAll(self)
    end
    self.activeJobs = {}
    self.subscribed = false
end

function WorkerJobTracker:log(msg, ...)
    if self.settings and self.settings.debugMode then
        print(string.format("[Worker Costs] " .. msg, ...))
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle handlers (server-authoritative)
-- ---------------------------------------------------------------------------

function WorkerJobTracker:_onJobStarted(job, startFarmId)
    if not self:_isActive() then
        return
    end
    if job == nil then
        return
    end

    -- Owning farm comes straight from the payload (plan §Phase 1: this replaces
    -- re-deriving the farm via the manual filter that billing still uses).
    -- Match billing's behaviour: only the local player's own jobs are tracked.
    local playerFarmId = g_currentMission.getFarmId and g_currentMission:getFarmId()
    if playerFarmId and playerFarmId ~= 0 and startFarmId and startFarmId ~= playerFarmId then
        return
    end

    local vehicle = self:_resolveVehicle(job)
    if vehicle == nil then
        return
    end

    local helperName = self:_resolveHelperName(job, vehicle)
    local worker = self:_resolveWorker(vehicle, helperName)
    if worker == nil then
        return
    end

    local now = (g_currentMission and g_currentMission.time) or 0
    self.activeJobs[job] = {
        workerUuid = worker.uuid,
        vehicleId  = tostring(vehicle),
        startTime  = now,
        name       = worker.name,
    }
    self:log("Job started: '%s' (uuid=%d) on %s", worker.name, worker.uuid, tostring(vehicle))
end

function WorkerJobTracker:_onJobStopped(job, aiMessage)
    if job == nil then
        return
    end

    local rec = self.activeJobs[job]
    if rec == nil then
        return
    end
    self.activeJobs[job] = nil

    local worker = self.roster and self.roster:getWorker(rec.workerUuid)
    if worker == nil then
        -- Worker was fired mid-job: just release the binding and move on.
        if self.roster then
            self.roster:unassignVehicle(rec.vehicleId)
        end
        return
    end

    local now       = (g_currentMission and g_currentMission.time) or rec.startTime
    local elapsedMs = math.max(0, now - (rec.startTime or now))
    local hours     = elapsedMs / MS_PER_HOUR

    worker.totalHours = (worker.totalHours or 0) + hours
    worker.totalJobs  = (worker.totalJobs or 0) + 1
    -- Raw XP accrues at 1 per real hour worked. Phase 2 maps totalXP -> level tier.
    worker.totalXP    = (worker.totalXP or 0) + hours

    -- Free the worker so it can take the next job (and be reused by the bridge).
    self.roster:unassignVehicle(rec.vehicleId)

    -- Phase 1 milestone (2.0.0) is invisible to players: log only, no HUD popup.
    -- The player-facing job summary is surfaced by the Phase 4 UI refresh.
    self:log("Job done: '%s' +%.2fh (totalHours=%.2f, jobs=%d, XP=%.1f)",
        worker.name, hours, worker.totalHours, worker.totalJobs, worker.totalXP)
end

-- ---------------------------------------------------------------------------
-- Resolution helpers
-- ---------------------------------------------------------------------------

function WorkerJobTracker:_isActive()
    if self.settings and self.settings.enabled == false then
        return false
    end
    -- Server-authoritative: the roster lives on the host. MP clients receive it
    -- via sync (Phase 5), so they must not mutate a local copy here.
    return g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer()
end

-- Mirrors WorkerSystem:getActiveWorkers() resolution: prefer the official
-- vehicleParameter API, fall back to a directly-set job.vehicle.
function WorkerJobTracker:_resolveVehicle(job)
    local vehicle = nil
    if job.vehicleParameter and job.vehicleParameter.getVehicle then
        local ok, v = pcall(function() return job.vehicleParameter:getVehicle() end)
        if ok then
            vehicle = v
        end
    end
    if vehicle == nil and job.vehicle then
        vehicle = job.vehicle
    end
    return vehicle
end

function WorkerJobTracker:_resolveHelperName(job, vehicle)
    local name = nil
    if job.getHelperName then
        local ok, helperName = pcall(function() return job:getHelperName() end)
        if ok and helperName and helperName ~= "" then
            name = helperName
        end
    end
    if name == nil and vehicle then
        name = (vehicle.getFullName and vehicle:getFullName())
            or (vehicle.getName and vehicle:getName())
    end
    return name or "Worker"
end

-- Phase 1 AUTO-HIRE BRIDGE (scaffolding — removed/made opt-in once the Phase 5
-- hire UI exists). Identity always lives in the persistent uuid; the helper name
-- is only a display seed. Resolution order:
--   1. a worker already bound to this vehicle,
--   2. an idle worker with the same name (a returning named helper),
--   3. a freshly auto-hired worker seeded with the helper name.
function WorkerJobTracker:_resolveWorker(vehicle, helperName)
    if self.roster == nil then
        return nil
    end
    local vehicleId = tostring(vehicle)

    local worker = self.roster:getWorkerByVehicle(vehicleId)
    if worker then
        return worker
    end

    worker = self.roster:findIdleByName(helperName)
    if worker then
        self.roster:assignVehicle(worker.uuid, vehicleId)
        return worker
    end

    worker = self.roster:createWorker(helperName)
    self.roster:assignVehicle(worker.uuid, vehicleId)
    self:log("Auto-hired '%s' (uuid=%d) [Phase 1 bridge]", worker.name, worker.uuid)
    return worker
end

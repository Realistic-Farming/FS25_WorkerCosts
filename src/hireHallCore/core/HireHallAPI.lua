-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.core.API — compound availability broker & public API (FR3)
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
--   The single source of truth for "can this worker be dispatched?" (FR3) plus the
--   small public surface other layers (the Phase 4 FarmTablet, console commands)
--   call. isWorkerAvailable() is O(1), allocates nothing, and short-circuits on the
--   first failing condition so an injured worker never costs a fatigue/idle check.
--
--   Evaluation order (strict short-circuit):
--     0. host authority         -> CLIENT_READ_ONLY
--     0. corruption / no roster  -> SYSTEM_ERROR
--     0. unknown id              -> INVALID_WORKER_ID
--     1. lifecycleState=available-> NOT_AVAILABLE
--     2. fatigue < 95            -> FATIGUED   (skipped on telemetry drift: treat available)
--     3. idle (no live job)      -> BUSY
--     4. pinned-but-parked is still available (FR3 vehicle-pinning rule)
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.core = HireHallCore.core or {}
HireHallCore.core.API = HireHallCore.core.API or {}
local API = HireHallCore.core.API

-- Idle = not bound to a vehicle on a live AI job right now. Prefer the job
-- tracker's authoritative view (FR3 cond.3 names WorkerJobTracker:isWorkerIdle);
-- fall back to the roster's transient binding, which is set for exactly the life
-- of one AI job. A pinned-but-parked worker has no transient binding -> idle ->
-- available (FR3 vehicle-pinning rule).
function API:_isIdle(worker)
    local tracker = HireHallCore.jobTracker
    if tracker and tracker.isWorkerIdle then
        local ok, idle = pcall(function() return tracker:isWorkerIdle(worker.uuid) end)
        if ok then
            return idle
        end
    end
    return worker.assignedVehicleId == nil
end

--- FR3 — the authoritative availability broker. Returns available(bool), reason(string).
function API:isWorkerAvailable(workerId)
    -- Read-only on clients (the real roster only exists on the host).
    if not HireHallCore._isHost() then
        return false, "CLIENT_READ_ONLY"
    end
    if HireHallCore.isCorrupted then
        return false, "SYSTEM_ERROR"
    end

    local roster = HireHallCore.roster
    if roster == nil then
        return false, "SYSTEM_ERROR"
    end

    local worker = roster:getWorker(workerId)
    if worker == nil then
        Logging.warning("[HireHallCore] isWorkerAvailable: unknown worker id %s", tostring(workerId))
        return false, "INVALID_WORKER_ID"
    end

    local Lifecycle = HireHallCore.core.Lifecycle
    local ProStaff  = HireHallCore.integration.ProStaff

    -- 1. Lifecycle gate — only 'available' permits dispatch.
    local meta = Lifecycle:ensureMeta(worker)
    if meta.lifecycleState ~= HireHallCore.STATE.AVAILABLE then
        return false, "NOT_AVAILABLE"
    end

    -- 2. Fatigue ceiling. On telemetry drift (FR2 unreadable) DON'T block — the
    --    FR3 rule is to treat the worker as available rather than lock the workforce.
    if ProStaff:isReadable(worker) then
        if ProStaff:getFatigue(worker) >= HireHallCore.FATIGUE_DISPATCH_MAX then
            return false, "FATIGUED"
        end
    end

    -- 3. Task occupancy — must be idle.
    if not self:_isIdle(worker) then
        return false, "BUSY"
    end

    -- 4. Assignment status — pinning alone does not block (covered by step 3).
    return true, "AVAILABLE"
end

-- ---------------------------------------------------------------------------
-- Public, host-checked convenience surface (the FarmTablet/dispatch consume these)
-- ---------------------------------------------------------------------------

--- Read a worker's lifecycle state string, or nil if unknown.
function API:getLifecycleState(workerId)
    local roster = HireHallCore.roster
    if roster == nil then
        return nil
    end
    local w = roster:getWorker(workerId)
    if w == nil then
        return nil
    end
    return HireHallCore.core.Lifecycle:getState(w)
end

--- Request a lifecycle transition (host-authoritative). Returns ok, reasonOrState.
function API:setLifecycleState(workerId, newState, reason)
    local roster = HireHallCore.roster
    if roster == nil then
        return false, "SYSTEM_ERROR"
    end
    local w = roster:getWorker(workerId)
    if w == nil then
        return false, "INVALID_WORKER_ID"
    end
    return HireHallCore.core.Lifecycle:transition(w, newState, reason)
end

--- Mark a worker as currently viewed in the UI (front-of-line in the evolver).
function API:markViewed(workerId)
    HireHallCore.core.Evolution:pushUrgent(workerId)
end

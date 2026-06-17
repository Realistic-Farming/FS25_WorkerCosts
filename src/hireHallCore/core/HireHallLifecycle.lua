-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.core.Lifecycle — extended lifecycle state machine (FR1)
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
--   The persistent lifecycle state machine. Each roster worker carries a
--   `hireHallMeta` block (lazily attached, isolated from the roster's own fields
--   per FR0). State mutations are host-authoritative, validated against the FR1
--   state set, zero-allocation (pre-defined string constants), mark the worker
--   dirty, and emit a reactive event so the UI/logging never poll.
--
--   `available` is the ONLY state that permits field deployment — it is the logic
--   bridge to the FR3 availability broker (per the issue's dev note).
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.core = HireHallCore.core or {}
HireHallCore.core.Lifecycle = HireHallCore.core.Lifecycle or {}
local Lifecycle = HireHallCore.core.Lifecycle

local function currentDay()
    return (g_currentMission and g_currentMission.environment
        and g_currentMission.environment.currentDay) or 0
end

--- Lazily attach the HireHallCore per-worker metadata block. FR0 isolation guard:
--- only create when absent, never collide with roster/core fields. The roster's
--- newWorker() deliberately knows nothing about this — keeping schemas separate.
function Lifecycle:ensureMeta(worker)
    if type(worker) ~= "table" then
        return nil
    end
    if not worker.hireHallMeta then
        worker.hireHallMeta = {
            lifecycleState = HireHallCore.STATE.AVAILABLE,
            history        = {},     -- reserved for FR8 circular buffer (Phase 2)
            dirtyMask      = 0,
            enteredDay     = currentDay(),
            cooldownEnd    = nil,    -- in-game day when injured/onLeave auto-clears
        }
    end
    return worker.hireHallMeta
end

--- Current lifecycle state string (ensures meta first; defaults to available).
function Lifecycle:getState(worker)
    local meta = self:ensureMeta(worker)
    return (meta and meta.lifecycleState) or HireHallCore.STATE.AVAILABLE
end

--- Authoritative state mutation (FR1). Host-only; validates the target string;
--- no-op when unchanged; sets the UI/HALL dirty bits; emits the lifecycle event.
--- Returns ok(bool), reasonCodeOrNewState(string). An invalid target string trips
--- corruption and logs the attempted path.
function Lifecycle:transition(worker, newState, reason)
    if not HireHallCore._isHost() then
        return false, "NOT_HOST"
    end
    if HireHallCore.isCorrupted then
        return false, "SYSTEM_ERROR"
    end
    if type(worker) ~= "table" then
        return false, "INVALID_WORKER"
    end
    if not HireHallCore.VALID_STATE[newState] then
        HireHallCore:fail("lifecycle.transition",
            string.format("invalid target state '%s' for worker %s (from '%s')",
                tostring(newState), tostring(worker.uuid),
                tostring(worker.hireHallMeta and worker.hireHallMeta.lifecycleState)))
        return false, "INVALID_STATE"
    end

    local meta = self:ensureMeta(worker)
    local old = meta.lifecycleState
    if old == newState then
        return true, newState   -- no churn, no event
    end

    meta.lifecycleState = newState
    meta.enteredDay     = currentDay()
    meta.dirtyMask = HireHallCore.maskSet(meta.dirtyMask, HireHallCore.DIRTY_UI)
    meta.dirtyMask = HireHallCore.maskSet(meta.dirtyMask, HireHallCore.DIRTY_HALL)

    HireHallCore.Events:onLifecycleChanged(worker.uuid, old, newState, reason or "")
    return true, newState
end

--- Begin an injury with a recovery cooldown N in-game days out (FR4 evolution then
--- clears it back to available). Host-only via transition().
function Lifecycle:setInjured(worker, recoveryDays, reason)
    local meta = self:ensureMeta(worker)
    if meta == nil then
        return false, "INVALID_WORKER"
    end
    meta.cooldownEnd = currentDay() + math.max(1, recoveryDays or 1)
    return self:transition(worker, HireHallCore.STATE.INJURED, reason or "injured")
end

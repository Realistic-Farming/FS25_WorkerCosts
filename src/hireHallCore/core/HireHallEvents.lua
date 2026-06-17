-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.Events — internal reactive event dispatcher (FR1)
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
--   A tiny in-process pub/sub so the lifecycle state machine can announce
--   transitions and the UI / logging / history modules react WITHOUT polling
--   (FR1: HireHallCore.Events:onLifecycleChanged). Listeners are invoked under
--   pcall so a single bad subscriber can never break the dispatcher (FR0 silent
--   failure). No subscribers ship in Phase 1 — this is the seam Phase 2/4 plug into.
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.Events = HireHallCore.Events or { _listeners = {} }
local Events = HireHallCore.Events

--- Register a callback for a named event. `fn` is called with the emitted args.
function Events:subscribe(eventName, fn)
    if type(eventName) ~= "string" or type(fn) ~= "function" then
        return
    end
    self._listeners[eventName] = self._listeners[eventName] or {}
    table.insert(self._listeners[eventName], fn)
end

--- Emit a named event to every subscriber. Each call is isolated by pcall.
function Events:emit(eventName, ...)
    local list = self._listeners[eventName]
    if list == nil then
        return
    end
    for i = 1, #list do
        pcall(list[i], ...)
    end
end

--- The documented lifecycle signal (FR1). Fired by the state machine on every
--- real transition: (workerId, oldState, newState, reason).
function Events:onLifecycleChanged(workerId, oldState, newState, reason)
    self:emit("lifecycleChanged", workerId, oldState, newState, reason)
end

--- The job-termination signal (FR5). Fired by WorkerJobTracker when an AI job ends,
--- carrying the already-resolved facts (workerUuid, hours, startLevel, fatigue, seq,
--- aiMessage). The Internal Job Termination Monitor is the sole subscriber; this is
--- the seam that replaces the spec's non-existent WorkerManager.onWorkerEnd hook.
function Events:onWorkerJobEnded(payload)
    self:emit("workerJobEnded", payload)
end

--- Drop all subscribers (called from HireHallCore:shutdown on mission unload so
--- listeners don't accumulate across reloads — the global is sourced once).
function Events:clear()
    self._listeners = {}
end

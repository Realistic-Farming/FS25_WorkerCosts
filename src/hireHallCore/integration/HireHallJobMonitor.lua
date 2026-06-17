-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.integration.JobMonitor — Internal Job Termination Monitor (FR5)
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
--   The "truth teller" for the Hiring Hall (FR5). It observes the end of every AI
--   job and commits a compact result row to the worker's history buffer, so each
--   employee accrues an accurate professional resume WITHOUT any polling and WITHOUT
--   a second job tracker.
--
-- DESIGN RECONCILIATION (the FR text references engine seams that do not exist):
--   * FR5 says "bind to WorkerManager.onWorkerEnd". There is no such method. The
--     authoritative job-end truth — worker identity, hours, level, fatigue — is
--     already resolved in WorkerJobTracker:_onJobStopped (the AI_JOB_STOPPED handler).
--     So instead of re-tracking jobs, the tracker EMITS one internal signal
--     (HireHallCore.Events "workerJobEnded") carrying those resolved facts, and this
--     monitor SUBSCRIBES to it. That satisfies FR5's own first directive verbatim:
--     "register a listener to the core mod's event dispatcher." One source of truth.
--   * FR5 references "HireHallCoreHistory" for the circular buffer — that is
--     HireHallCore.core.History here.
--
-- FR5 CONSTRAINTS HONORED
--   * Event-driven only — no work in any update() loop (we are a pure subscriber).
--   * Existence verification — roster:getWorkerExists() hard-check before any write,
--     so a worker fired+reassigned in the same frame is never logged as an orphan.
--   * Silent-failure policy — the write runs under HireHallCore:guard(); a failure
--     trips isCorrupted, logs the offending seq, and fires the one System Error toast.
--   * Host authority — the tracker only emits on the server, so this runs host-side;
--     the synced snapshot (Phase 5) carries the buffer to clients, no MP wait here.
--   * Growth transparency — StartRank and EndRank are both recorded when a worker is
--     promoted mid-job.
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.integration = HireHallCore.integration or {}
HireHallCore.integration.JobMonitor = HireHallCore.integration.JobMonitor or {}
local JobMonitor = HireHallCore.integration.JobMonitor

JobMonitor._installed = false

--- Subscribe to the internal job-end signal. Idempotent within a session; the
--- subscription is dropped by HireHallCore.Events:clear() on shutdown, and re-armed
--- on the next initialize() — so registration is deferred until the framework (and
--- thus the roster) is live, never bound to nil references (FR5 stability rule).
function JobMonitor:install()
    if self._installed then
        return
    end
    if HireHallCore.Events == nil then
        return
    end
    HireHallCore.Events:subscribe("workerJobEnded", function(payload)
        JobMonitor:_onJobEnded(payload)
    end)
    self._installed = true
    Logging.info("[HireHallCore] Job termination monitor armed (FR5)")
end

--- Cleared on shutdown so the next mission re-subscribes against fresh listeners.
function JobMonitor:reset()
    self._installed = false
end

-- ---------------------------------------------------------------------------
-- Outcome classification (engine AIMessage -> compact resume token)
-- ---------------------------------------------------------------------------
-- VERIFIED (FS25-Community-LUADOC, Errors/AIMessage*):
--   * AIMessage:getType() returns AIMessageType.OK | INFO | ERROR.
--   * AIMessageError* subclasses keep the base ERROR type  -> job failed.
--   * AIMessageSuccessFinishedJob / SiloEmpty return OK     -> completed.
--   * AIMessageSuccessStoppedByUser returns OK but means the player pulled the
--     helper early -> dismissed (partial work). Distinguished via :isa().

local function isStoppedByUser(aiMessage)
    -- Global class only exists in-game; guard so logic tests / odd states degrade.
    if AIMessageSuccessStoppedByUser == nil or aiMessage == nil then
        return false
    end
    local ok, res = pcall(function()
        return aiMessage.isa ~= nil and aiMessage:isa(AIMessageSuccessStoppedByUser)
    end)
    return ok and res == true
end

--- Map an aiMessage to (outcome, cause). A nil message (e.g. an internal stop)
--- is treated as a clean completion.
function JobMonitor:classify(aiMessage)
    local History = HireHallCore.core.History
    if aiMessage == nil then
        return History.OUTCOME_COMPLETED, "finished"
    end

    local okT, msgType = pcall(function()
        return aiMessage.getType ~= nil and aiMessage:getType() or nil
    end)
    if okT and AIMessageType ~= nil and msgType == AIMessageType.ERROR then
        -- A specific numeric error code is not exposed on the base class; the ERROR
        -- bucket is the honest, stable token we can store. (Finer codes would need
        -- class identity the engine does not surface generically.)
        return History.OUTCOME_FAILED, "error"
    end

    if isStoppedByUser(aiMessage) then
        return History.OUTCOME_DISMISSED, "stoppedByUser"
    end

    return History.OUTCOME_COMPLETED, "finished"
end

-- Indicative wage cost for one job (currency). Mirrors the steady-state rate the
-- roster snapshot advertises: base x level-efficiency x fatigue surcharge (Master
-- immune), times hours. In per-hectare mode wage is not hours-based, so this is a
-- best-effort estimate for the resume, not a billed figure.
function JobMonitor:_estimateWage(hours, level, fatigue)
    local settings = HireHallCore.settings
    local rate = (settings and settings.getWageRate and settings:getWageRate()) or 0
    local lf = 1.0
    if WorkerSystem and WorkerSystem.LEVEL_WAGE_FACTOR then
        lf = WorkerSystem.LEVEL_WAGE_FACTOR[level] or 1.0
    end
    local eff = rate * lf
    local isMaster = (WorkerRoster ~= nil and level == WorkerRoster.LEVEL_MASTER)
    if not isMaster and fatigue and fatigue > 0 and WorkerSystem then
        eff = eff * (1 + fatigue * (WorkerSystem.FATIGUE_SURCHARGE or 0))
    end
    return eff * math.max(0, hours or 0)
end

-- ---------------------------------------------------------------------------
-- The subscriber (host-only; the tracker only emits on the server)
-- ---------------------------------------------------------------------------
function JobMonitor:_onJobEnded(payload)
    if type(payload) ~= "table" then
        return
    end
    if HireHallCore.isCorrupted then
        return   -- subsystem halted for the session
    end

    local roster = HireHallCore.roster
    if roster == nil then
        return
    end

    -- FR5 existence verification: never process an orphan deleted from the roster in
    -- the same frame it terminated.
    local workerId = payload.workerUuid
    local exists = false
    if roster.getWorkerExists ~= nil then
        exists = roster:getWorkerExists(workerId)
    else
        exists = roster:getWorker(workerId) ~= nil
    end
    if not exists then
        return
    end

    local worker = roster:getWorker(workerId)
    local outcome, cause = self:classify(payload.aiMessage)
    local startLevel = payload.startLevel or (worker.level or 1)
    local endLevel   = worker.level or startLevel
    local fatigue    = payload.fatigue or worker.fatigue or 0
    local wage       = self:_estimateWage(payload.hours, endLevel, fatigue)
    local day = (g_currentMission and g_currentMission.environment
        and g_currentMission.environment.currentDay) or 0

    -- FR5 silent-failure policy: the write is the sensitive op. guard() pcalls it and,
    -- on failure, trips the one corruption flag + single System Error toast and logs
    -- the offending seq so the bad job is identifiable.
    HireHallCore:guard(string.format("jobMonitor.record(seq=%s)", tostring(payload.seq)), function()
        HireHallCore.core.History:record(worker, {
            day        = day,
            hours      = payload.hours or 0,
            outcome    = outcome,
            cause      = cause,
            startLevel = startLevel,
            endLevel   = endLevel,
            wage       = wage,
            seq        = payload.seq or 0,
        })
    end)
end

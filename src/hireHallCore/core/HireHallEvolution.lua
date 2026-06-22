-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.core.Evolution — time-sliced evolution engine (FR4)
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
--   A bucket-wheel background processor that evolves worker lifecycle state over
--   time (exhaustion -> onLeave, recovery -> available, injury cooldown -> available)
--   WITHOUT iterating the whole roster in one frame. It processes at most
--   SLICE_SIZE (5) workers per step, throttled to ~STEP_INTERVAL, so cost stays
--   well under the 0.05ms/frame budget even with 200+ workers.
--
--   IMPORTANT BOUNDARY: this engine reads fatigue via the FR2 accessor and decides
--   lifecycle STATE only. It never mutates fatigue/XP — WorkerSystem owns the
--   fatigue number (daily idle recovery). One owner per datum, no tug-of-war.
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.core = HireHallCore.core or {}
HireHallCore.core.Evolution = HireHallCore.core.Evolution or {
    lastProcessedIndex = 0,   -- bucket-wheel cursor (0-based; wraps via modulo)
    lastRosterCount    = 0,   -- detect shrinkage to reset the cursor (FR4)
    urgentQueue        = {},  -- workerIds viewed in the FarmTablet -> processed first
}
local Evolution = HireHallCore.core.Evolution

--- Push a workerId to the front-of-line (FR4 urgent queue). Used when a worker is
--- being viewed in the FarmTablet personnel app so the UI always sees fresh state
--- (the tablet's active app is known via the #84 focus API). Small set, deduped in
--- place — no allocation churn.
function Evolution:pushUrgent(workerId)
    if workerId == nil then
        return
    end
    for i = 1, #self.urgentQueue do
        if self.urgentQueue[i] == workerId then
            return
        end
    end
    self.urgentQueue[#self.urgentQueue + 1] = workerId
end

--- Reset the wheel (called on shutdown / roster shrinkage).
function Evolution:reset()
    self.lastProcessedIndex = 0
    self.lastRosterCount = 0
    for i = #self.urgentQueue, 1, -1 do
        self.urgentQueue[i] = nil
    end
end

-- Evolve one worker's lifecycle from its telemetry. Pure state logic; atomic
-- (a single transition per visit). Never splits a state change across frames.
function Evolution:_evolveWorker(core, worker)
    if type(worker) ~= "table" then
        return
    end
    local Lifecycle = HireHallCore.core.Lifecycle
    local ProStaff  = HireHallCore.integration.ProStaff

    local meta = Lifecycle:ensureMeta(worker)
    local state    = meta.lifecycleState
    local readable = ProStaff:isReadable(worker)
    local fatigue  = ProStaff:getFatigue(worker)   -- 0..100
    local today    = (g_currentMission and g_currentMission.environment
        and g_currentMission.environment.currentDay) or 0

    if state == HireHallCore.STATE.INJURED then
        -- Cooldown elapsed, OR telemetry unreadable -> back to available. FR4 stale
        -- rule: never leave a worker perpetually injured on a malformed read.
        if (meta.cooldownEnd ~= nil and today >= meta.cooldownEnd) or not readable then
            meta.cooldownEnd = nil
            Lifecycle:transition(worker, HireHallCore.STATE.AVAILABLE, "injury_recovered")
        end
    elseif state == HireHallCore.STATE.ON_LEAVE then
        -- Rested below the recovery floor (or unreadable) -> available again.
        if not readable or fatigue < HireHallCore.FATIGUE_RECOVER_TO then
            Lifecycle:transition(worker, HireHallCore.STATE.AVAILABLE, "rested")
        end
    elseif state == HireHallCore.STATE.AVAILABLE then
        -- Mandatory leave once exhausted (FR1 onLeave rule).
        if readable and fatigue >= HireHallCore.FATIGUE_LEAVE_AT then
            Lifecycle:transition(worker, HireHallCore.STATE.ON_LEAVE, "exhausted")
        end
    end
    -- training / contract / hired / retired / fired are user/host driven, not auto-evolved.

    -- Debounce (FR4): clear the UI dirty bit now that this worker has been processed.
    meta.dirtyMask = HireHallCore.maskClear(meta.dirtyMask, HireHallCore.DIRTY_UI)
end

--- Per-step driver (host only). Throttled to STEP_INTERVAL; processes the urgent
--- queue, then a SLICE_SIZE bucket-wheel batch. Wrapped in pcall: any error trips
--- corruption, halts the loop, and fires the single System Error toast (FR4).
function Evolution:update(core, dt)
    if not HireHallCore._isHost() then
        return
    end
    local roster = core.roster
    if roster == nil then
        return
    end

    core._stepTimer = (core._stepTimer or 0) + (dt or 0)
    if core._stepTimer < HireHallCore.STEP_INTERVAL then
        return
    end
    core._stepTimer = 0

    local ok, err = pcall(function()
        local workers = roster:getAll()
        local count = #workers

        -- Roster shrinkage guard (FR4): reset the cursor to avoid out-of-bounds.
        if count ~= self.lastRosterCount then
            self.lastProcessedIndex = 0
            self.lastRosterCount = count
        end
        if count == 0 then
            return
        end

        -- 1. Urgent queue first (UI-visible workers).
        local uq = self.urgentQueue
        local uqn = #uq
        if uqn > 0 then
            for i = 1, uqn do
                local w = roster:getWorker(uq[i])
                if w then
                    self:_evolveWorker(core, w)
                end
            end
            for i = uqn, 1, -1 do
                uq[i] = nil   -- clear without allocating a new table
            end
        end

        -- 2. Bucket-wheel slice: SLICE_SIZE workers from the cursor (wraps).
        local slice = HireHallCore.SLICE_SIZE
        if slice > count then
            slice = count
        end
        for _ = 1, slice do
            local idx = (self.lastProcessedIndex % count) + 1   -- 1..count
            self:_evolveWorker(core, workers[idx])
            self.lastProcessedIndex = self.lastProcessedIndex + 1
            if self.lastProcessedIndex >= count then
                self.lastProcessedIndex = 0
            end
        end
    end)

    if not ok then
        core:fail("evolution.update", err)
    end
end

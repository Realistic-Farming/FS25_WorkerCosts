-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore — framework foundation & engineering controls (FR0)
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
--   The authoritative HireHallCore orchestrator. It owns the framework-wide
--   constants, the bitwise dirty-mask helpers, the silent-failure / corruption
--   policy, the host-authority gate, and the per-frame entry point that drives
--   the time-sliced evolution engine. Every other hireHallCore module attaches
--   itself to this single global namespace.
--
-- DESIGN RECONCILIATIONS (the FR specs are written by a non-implementer and
-- contradict themselves in spots; the resolved decisions live here):
--   * Per-worker data namespace: the spec says both `worker.hireHall` (FR0) and
--     `worker.hireHallMeta` (FR1/FR3/FR4). We use ONE table — `worker.hireHallMeta`
--     — created lazily via the FR0 "if not ... then" isolation guard, so the
--     roster's own fields/save format are never touched.
--   * Lifecycle field name: FR1's init snippet says `.lifecycle`, but FR1's
--     property-injection directive AND FR3 condition 1 both say `.lifecycleState`.
--     Two votes to one — we standardize on `lifecycleState`.
--   * Host authority: the spec mandates `g_currentMission.isMasterUser`. That field
--     is false on a dedicated server (no local admin), yet the roster lives on the
--     server. Using it would break dedicated MP. The roster is server-authoritative,
--     so we gate on getIsServer() and keep the spec's NOT_HOST / CLIENT_READ_ONLY
--     reason codes. (Verified: FarmlandManager uses `getIsServer() or isMasterUser`.)
--   * Fatigue scale: the roster stores fatigue 0..1; the spec compares against 95.
--     The FR2 telemetry accessor normalizes to a 0..100 percentage so broker code
--     reads like the spec ("< 95").
-- =========================================================

---@class HireHallCore
HireHallCore = HireHallCore or {}

-- ---------------------------------------------------------------------------
-- Engineering constants (FR0)
-- ---------------------------------------------------------------------------

-- Bitwise dirty masks (single-bit power-of-two flags). Set when a worker needs
-- UI / history / hall reprocessing; cleared once the relevant module consumes it.
HireHallCore.DIRTY_UI      = 1   -- 001
HireHallCore.DIRTY_HISTORY = 2   -- 010
HireHallCore.DIRTY_HALL    = 4   -- 100

HireHallCore.SLICE_SIZE     = 5    -- workers processed per evolution step (FR4)
HireHallCore.STEP_INTERVAL  = 250  -- ms between evolution steps; keeps cost << 0.05ms/frame
HireHallCore.HISTORY_CAP    = 20   -- max job-result rows kept per worker (FR5 circular buffer)
HireHallCore.SCHEMA_VERSION = 2    -- <hireHallCore version="2"> — v2 adds per-worker history (FR5)

-- Lifecycle states (FR1). Pre-defined string constants so transitions never
-- allocate a temporary (zero-allocation directive).
HireHallCore.STATE = {
    AVAILABLE = "available",
    HIRED     = "hired",
    TRAINING  = "training",
    INJURED   = "injured",
    ON_LEAVE  = "onLeave",
    RETIRED   = "retired",
    FIRED     = "fired",
    CONTRACT  = "contract",
}

-- O(1) validity set for the FR1 invalid-state guard.
HireHallCore.VALID_STATE = {}
for _, s in pairs(HireHallCore.STATE) do
    HireHallCore.VALID_STATE[s] = true
end

-- Fatigue thresholds, all on the FR2 0..100 telemetry scale.
HireHallCore.FATIGUE_DISPATCH_MAX = 95   -- FR3 cond.2: not dispatchable at/above this
HireHallCore.FATIGUE_LEAVE_AT     = 95   -- FR1/FR4: mandatory onLeave at/above this
HireHallCore.FATIGUE_RECOVER_TO   = 30   -- FR4: onLeave -> available once rested below this

-- Sub-namespaces. Created here so module load order is forgiving: each file does
-- `HireHallCore.core = HireHallCore.core or {}` and attaches itself.
HireHallCore.core        = HireHallCore.core or {}
HireHallCore.integration = HireHallCore.integration or {}

-- ---------------------------------------------------------------------------
-- Runtime state
-- ---------------------------------------------------------------------------
HireHallCore.isCorrupted  = false   -- set by the silent-failure policy; halts the subsystem
HireHallCore._initialized = false
HireHallCore._toastShown  = false
HireHallCore._stepTimer   = 0

-- ---------------------------------------------------------------------------
-- Bitwise helpers (FR0). Prefer the engine ops (bitOR/bitAND, verified in the
-- LUADOC engine/Math reference); fall back to pure-Lua arithmetic for power-of-two
-- flags so the module is also correct/testable outside the in-game sandbox.
-- ---------------------------------------------------------------------------
local _bor = bitOR or function(a, b)
    local res, bit = 0, 1
    local hi = math.max(a, b)
    while bit <= hi do
        if (math.floor(a / bit) % 2 == 1) or (math.floor(b / bit) % 2 == 1) then
            res = res + bit
        end
        bit = bit * 2
    end
    return res
end

local _band = bitAND or function(a, b)
    local res, bit = 0, 1
    local hi = math.min(a, b)
    while bit <= hi do
        if (math.floor(a / bit) % 2 == 1) and (math.floor(b / bit) % 2 == 1) then
            res = res + bit
        end
        bit = bit * 2
    end
    return res
end

function HireHallCore.maskHas(mask, flag)
    return _band(mask or 0, flag) ~= 0
end

function HireHallCore.maskSet(mask, flag)
    return _bor(mask or 0, flag)
end

function HireHallCore.maskClear(mask, flag)
    local m = mask or 0
    if HireHallCore.maskHas(m, flag) then
        return m - flag   -- single-bit flag: subtract is exact
    end
    return m
end

-- ---------------------------------------------------------------------------
-- Host authority (FR0). The roster is server-authoritative; only the host owns
-- real worker objects. See the dedicated-server note in the header.
-- ---------------------------------------------------------------------------
function HireHallCore._isHost()
    return g_currentMission ~= nil
        and g_currentMission.getIsServer ~= nil
        and g_currentMission:getIsServer()
end

-- ---------------------------------------------------------------------------
-- Silent-failure & integrity policy (FR0). One corruption flag halts the whole
-- subsystem for the session; a single System Error toast informs the player.
-- ---------------------------------------------------------------------------

-- Fire the FarmTablet "System Error" toast once per session. The FarmTablet app is
-- Phase 4 (FR13); until it exists we degrade gracefully to the HUD warning + log.
function HireHallCore:fireSystemErrorToast(msg)
    if self._toastShown then
        return
    end
    self._toastShown = true
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        pcall(function()
            g_currentMission.hud:showBlinkingWarning(msg or "HireHallCore: personnel subsystem error", 5000)
        end)
    end
end

-- Trip the corruption flag, log the cause, fire the one-shot toast, halt operations.
function HireHallCore:fail(context, err)
    self.isCorrupted = true
    Logging.error("[HireHallCore] %s: %s", tostring(context), tostring(err))
    self:fireSystemErrorToast("HireHallCore error — personnel lifecycle suspended")
end

-- Run a sensitive op under pcall (FR0). On failure: corrupt + halt. Returns
-- ok(bool), plus the wrapped call's first two results on success.
function HireHallCore:guard(context, fn)
    if self.isCorrupted then
        return false
    end
    local ok, a, b = pcall(fn)
    if not ok then
        self:fail(context, a)
        return false
    end
    return true, a, b
end

-- ---------------------------------------------------------------------------
-- Lifecycle wiring (called by WorkerManager — the coordinator)
-- ---------------------------------------------------------------------------

--- Bind the framework to the mod's subsystems. Idempotent; the global IS the
--- singleton, so a stored reference (WorkerManager.hireHall) just aliases it.
function HireHallCore:setup(roster, settings, workerSystem, jobTracker)
    self.roster       = roster
    self.settings     = settings
    self.workerSystem = workerSystem
    self.jobTracker   = jobTracker
    self.isCorrupted  = false
    self._toastShown  = false
    self._initialized = false
    self._stepTimer   = 0
    return self
end

--- Initialize on the host once the roster has loaded: give every worker a meta
--- block (default available), then apply any persisted lifecycle states.
function HireHallCore:initialize(missionInfo)
    if not HireHallCore._isHost() then
        return   -- clients have no real roster; they read synced snapshots (Phase 4)
    end

    self:guard("initialize", function()
        if self.roster then
            for _, w in ipairs(self.roster:getAll()) do
                HireHallCore.core.Lifecycle:ensureMeta(w)
            end
        end
        if HireHallCore.Schema then
            HireHallCore.Schema:loadIfExists(missionInfo, self.roster)
        end
    end)

    -- Arm the FR5 job-termination monitor now the framework + roster are live
    -- (deferred registration — never bind against nil references).
    if HireHallCore.integration.JobMonitor then
        HireHallCore.integration.JobMonitor:install()
    end

    self._initialized = true
    Logging.info("[HireHallCore] Initialized (host) — lifecycle layer active")
end

--- Per-frame entry point (host only). Drives the time-sliced evolution engine.
function HireHallCore:update(dt)
    if not HireHallCore._isHost() then
        return
    end
    if self.isCorrupted or not self._initialized then
        return
    end
    HireHallCore.core.Evolution:update(self, dt)
end

--- Persist lifecycle state (host only) into the isolated <hireHallCore> file.
function HireHallCore:save(missionInfo)
    if not HireHallCore._isHost() then
        return
    end
    self:guard("save", function()
        if HireHallCore.Schema then
            HireHallCore.Schema:save(missionInfo, self.roster)
        end
    end)
end

--- Reset per-mission state on unload. The global persists across mission reloads
--- (source() runs once), so this prevents stale corruption flags / event listeners
--- / evolution cursors from leaking into the next session.
function HireHallCore:shutdown()
    self.isCorrupted  = false
    self._initialized = false
    self._toastShown  = false
    self._stepTimer   = 0
    if HireHallCore.core.Evolution and HireHallCore.core.Evolution.reset then
        HireHallCore.core.Evolution:reset()
    end
    if HireHallCore.integration.JobMonitor and HireHallCore.integration.JobMonitor.reset then
        HireHallCore.integration.JobMonitor:reset()   -- re-armed on next initialize()
    end
    if HireHallCore.Events and HireHallCore.Events.clear then
        HireHallCore.Events:clear()
    end
    self.roster       = nil
    self.settings     = nil
    self.workerSystem = nil
    self.jobTracker   = nil
end

getfenv(0)["HireHallCore"] = HireHallCore

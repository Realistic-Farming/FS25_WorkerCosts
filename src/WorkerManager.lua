-- =========================================================
-- FS25 Worker Costs Mod (version 1.0.4.0)
-- =========================================================
-- Hourly or per-hectare wages for workers
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- PRO-STAFF BUILD CHECKLIST — coordinator wiring in THIS file, ticked per phase
-- (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 0 — own WorkerRoster; load on mission start; expose save entry
--   [x] Phase 1 — own WorkerJobTracker; subscribe on load, unsubscribe on delete;
--                 flush in-progress jobs before each roster save
--   [x] Phase 2 — XP/level handled by tracker+roster (no extra wiring needed)
--   [x] Phase 3 — pass the roster to WorkerSystem for the labor-cost pipeline
--   [x] Phase 4 — roster reachable via g_WorkerManager.workerRoster; WCWorkerStatsFrame
--                 shows level/fatigue (dashboard/wage-settings columns still pending)
--   [~] Phase 5 — getRosterSnapshot() read API DONE (cross-repo contract for the
--                 Farm Tablet Pro-Staff app); MP roster-sync events still pending
-- =========================================================
---@class WorkerManager
WorkerManager = {}
local WorkerManager_mt = Class(WorkerManager)

-- Pro-Staff Phase 5: recruitment pool. The host keeps a small rotating set of
-- candidates the player can hire from the Farm Tablet Personnel app. Candidate
-- names come from this pool (no text-input field on a controller-friendly tablet).
WorkerManager.RECRUIT_POOL_SIZE = 4

-- #69 Daily hiring limit: at most this many new hires from the Hiring Hall per
-- in-game day. Server-authoritative; the counter resets on the day rollover.
WorkerManager.DAILY_HIRE_LIMIT = 5

-- #68 Progression-gated hiring: total accrued roster XP required before the recruit
-- roller will offer Experienced candidates. "Master" is NEVER offered in the pool —
-- it is earned exclusively through XP on the job (WorkerRoster.XP_MASTER).
WorkerManager.EXPERIENCED_UNLOCK_XP = 80
local RECRUIT_NAME_POOL = {
    "Alex", "Sam", "Jordan", "Casey", "Riley", "Morgan", "Taylor", "Jamie",
    "Drew", "Quinn", "Avery", "Parker", "Reese", "Skyler", "Hayden", "Rowan",
    "Emerson", "Finley", "Sawyer", "Blake", "Charlie", "Dakota", "Elliot", "Frankie",
}

---@param mission table  The FS25 Mission00 object
---@param modDirectory string
---@param modName string
---@return WorkerManager
function WorkerManager.new(mission, modDirectory, modName)
    local self = setmetatable({}, WorkerManager_mt)
    
    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)

    -- Pro-Staff Phase 0: the mod-owned employee roster. Empty until first hire;
    -- populated from workerData.xml on mission load (server/SP only).
    self.workerRoster = WorkerRoster.new()

    -- Pro-Staff Phase 1: event-driven AI job lifecycle. Attributes jobs to roster
    -- workers and finalizes their hours/XP. Subscribed in onMissionLoaded.
    self.jobTracker = WorkerJobTracker.new(self.workerRoster, self.settings)

    -- Phase 3: WorkerSystem reads the roster (level/fatigue) for the labor-cost
    -- pipeline and recovers idle workers' fatigue daily.
    self.workerSystem = WorkerSystem.new(self.settings, self.workerRoster)

    -- HireHallCore framework (FR0-FR4): server-authoritative personnel lifecycle
    -- layered on top of the existing roster. Read-only consumer of Pro-Staff data;
    -- isolates its own state in worker.hireHallMeta and its own hireHallCore.xml.
    -- The global IS the singleton; self.hireHall just aliases it for the coordinator.
    if HireHallCore then
        self.hireHall = HireHallCore:setup(self.workerRoster, self.settings,
            self.workerSystem, self.jobTracker)
    end

    -- Phase 5: clickable roster panel (custom-drawn overlay). Client-only — it
    -- renders. Opened via the WorkerCostsRoster console command.
    if mission:getIsClient() and WCRosterPanel then
        self.rosterPanel = WCRosterPanel.new(self.workerRoster, self.workerSystem)
        self:installRosterInput()
    end

    if mission:getIsClient() and g_gui then
        self.WorkerSettingsUI = WorkerSettingsUI.new(self.settings)
        
        -- FS25 does not pcall-wrap appendedFunction hooks on onFrameOpen.
        -- A throw here aborts InGameMenu.open() entirely, breaking ESC.
        -- Wrap inject() so any error is contained and logged.
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
            local ok, err = pcall(function() self.WorkerSettingsUI:inject() end)
            if not ok then
                Logging.error("Worker Costs Mod: Settings injection failed: " .. tostring(err))
            end
        end)
        
        InGameMenuSettingsFrame.updateButtons = Utils.appendedFunction(InGameMenuSettingsFrame.updateButtons, function(frame)
            if self.WorkerSettingsUI then
                self.WorkerSettingsUI:ensureResetButton(frame)
            end
        end)
    end
    
    self.WorkerSettingsGUI = WorkerSettingsGUI.new()
    self.WorkerSettingsGUI:registerConsoleCommands()
    
    self.settings:load()
    
    return self
end

function WorkerManager:onMissionLoaded()
    -- Reload settings here, not in new().  WorkerManager.new() runs during
    -- Mission00.load (prepended), before missionInfo.savegameDirectory is set, so
    -- the load() in the constructor reads nothing and falls back to defaults.
    -- loadMission00Finished is the first guaranteed-safe window: the savegame has
    -- been read and savegameDirectory is populated for loaded careers, so the saved
    -- FS25_WorkerCosts.xml is actually applied (fixes settings reverting on reload).
    if self.settings then
        self.settings:load()
    end

    -- Pro-Staff Phase 0: load the roster now that savegameDirectory is populated.
    -- The roster lives server-side; in multiplayer, clients receive it via sync
    -- (Phase 5), so only the server/SP host reads it from disk.
    if g_currentMission and g_currentMission:getIsServer() then
        self:loadWorkerData()

        -- Pro-Staff Phase 1: subscribe to the AI job lifecycle on the host only.
        -- The roster is server-authoritative; clients sync it in Phase 5.
        if self.jobTracker then
            self.jobTracker:initialize()
        end

        -- HireHallCore: give each loaded worker a lifecycle meta block and apply
        -- any persisted states. Host-only (the broker reads the real roster).
        if self.hireHall then
            self.hireHall:initialize(g_currentMission.missionInfo)
        end
    end

    if self.workerSystem then
        self.workerSystem:initialize()
    end

    -- Single startup banner — WorkerSystem no longer shows its own.
    if self.settings.enabled and self.settings.showNotifications then
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                "Worker Costs Mod Active - Type 'workerCosts' for commands",
                4000
            )
        end
    end
end

function WorkerManager:update(dt)
    if self.workerSystem then
        self.workerSystem:update(dt)
    end
    if self.hireHall then
        self.hireHall:update(dt)   -- host-only; drives the time-sliced evolution engine
    end
    if self.rosterPanel then
        self.rosterPanel:update()
    end

    -- Pro-Staff Phase 5: a pure MP client pulls the roster mirror from the host.
    -- Retry a handful of times in case our first request beats the host's mod init
    -- on join; stop as soon as the first snapshot lands.
    if g_currentMission and not g_currentMission:getIsServer() then
        if self.clientRosterSnapshot == nil and (self._syncRetries or 0) < 6 then
            self._syncRetryTimer = (self._syncRetryTimer or 2500) + dt
            if self._syncRetryTimer >= 2500 then
                self._syncRetryTimer = 0
                self._syncRetries = (self._syncRetries or 0) + 1
                WCNetwork_RequestRosterSync()
            end
        end
    end
end

-- Pro-Staff Phase 0: roster persistence entry points.
-- saveWorkerData is invoked from the FSCareerMissionInfo.saveToXMLFile hook in
-- main.lua (the real game-save event) — deliberately NOT from delete(), so a
-- quit-without-saving never overwrites the savegame's roster.

function WorkerManager:saveWorkerData(missionInfo)
    if not self.workerRoster then
        return
    end
    -- Phase 1 refinement: credit in-progress jobs so a save mid-job persists the
    -- time worked so far (stats otherwise only finalize on job stop).
    if self.jobTracker then
        self.jobTracker:flushActiveJobs()
    end
    missionInfo = missionInfo or (g_currentMission and g_currentMission.missionInfo)
    self.workerRoster:save(missionInfo)

    -- HireHallCore lifecycle state persists alongside the roster, into its own
    -- isolated hireHallCore.xml (a bad write here can never corrupt the roster file).
    if self.hireHall then
        self.hireHall:save(missionInfo)
    end
end

function WorkerManager:loadWorkerData()
    if not self.workerRoster then
        return
    end
    local missionInfo = g_currentMission and g_currentMission.missionInfo
    self.workerRoster:loadIfExists(missionInfo)
end

-- =========================================================
-- Pro-Staff Phase 5: recruitment pool (server-authoritative)
-- =========================================================

-- #68 Total XP across the whole roster — the "farm progression" signal that gates
-- which tiers the Hiring Hall will offer. Rises as the player's staff put in hours.
function WorkerManager:_totalRosterXP()
    local sum = 0
    if self.workerRoster then
        for _, w in ipairs(self.workerRoster:getAll()) do
            sum = sum + (w.totalXP or 0)
        end
    end
    return sum
end

-- #68 The highest tier the recruit roller may currently offer. Master is never
-- recruitable (earned via XP only); Experienced unlocks once the farm has invested
-- enough total staff XP. Novice is always available.
function WorkerManager:_maxRecruitTier()
    if self:_totalRosterXP() >= WorkerManager.EXPERIENCED_UNLOCK_XP then
        return WorkerRoster.LEVEL_EXPERIENCED
    end
    return WorkerRoster.LEVEL_NOVICE
end

-- Roll a single recruit. Level is weighted toward Novice; an Experienced recruit
-- costs more to sign (computeHireCost scales by level). Master is intentionally
-- excluded from the pool entirely (#68 — it is an earned milestone, not a hire).
function WorkerManager:_generateRecruit()
    local level = WorkerRoster.LEVEL_NOVICE
    if self:_maxRecruitTier() >= WorkerRoster.LEVEL_EXPERIENCED then
        -- ~20% Experienced once unlocked; the rest stay Novice.
        if math.random() < 0.20 then
            level = WorkerRoster.LEVEL_EXPERIENCED
        end
    end

    local name = RECRUIT_NAME_POOL[math.random(1, #RECRUIT_NAME_POOL)]
    local hireCost = self.workerSystem and self.workerSystem:computeHireCost(level) or 0
    return { name = name, level = level, hireCost = hireCost }
end

-- The current pool, generated lazily and refilled after each hire. Server/SP only;
-- clients read the pool through the synced snapshot.
function WorkerManager:getRecruitPool()
    if not self.recruitPool then
        self:refreshRecruitPool()
    end
    return self.recruitPool
end

function WorkerManager:refreshRecruitPool()
    self.recruitPool = {}
    for i = 1, WorkerManager.RECRUIT_POOL_SIZE do
        self.recruitPool[i] = self:_generateRecruit()
    end
end

-- =========================================================
-- Pro-Staff Phase 5: roster snapshot — the cross-repo read contract
-- =========================================================

-- Build the live, enriched snapshot. Server/SP only — it reads roster, settings,
-- and the wage pipeline. The snapshot doubles as the multiplayer wire format
-- (WCRosterSyncEvent), so every derived value clients need is computed here once.
function WorkerManager:getServerSnapshot()
    local settings   = self.settings
    local workerSys  = self.workerSystem
    local baseRate   = (settings and settings.getWageRate and settings:getWageRate()) or 0
    local isHourly   = (settings and settings.costMode == Settings.COST_MODE_HOURLY) and true or false

    -- Aggregate "this month" accrued wages from the worker system.
    local monthAccrued = 0
    if workerSys and workerSys.monthlyCosts then
        for _, amt in pairs(workerSys.monthlyCosts) do
            monthAccrued = monthAccrued + (amt or 0)
        end
    end

    local snapshot = {
        authoritative = true,
        count   = 0,
        working = 0,   -- workers currently driving a vehicle on a live AI job
        pinned  = 0,   -- workers with a persistent vehicle assignment
        levels  = { novice = 0, experienced = 0, master = 0 },
        workers = {},
        recruits = {},
        finance = {
            baseRate        = baseRate,
            isHourly        = isHourly,
            costModeName    = (settings and settings.getCostModeName and settings:getCostModeName()) or "",
            wageLevelName   = (settings and settings.getWageLevelName and settings:getWageLevelName()) or "",
            monthAccrued    = math.floor(monthAccrued),
            estIntervalCost = (workerSys and workerSys.getEstimatedIntervalCost and workerSys:getEstimatedIntervalCost()) or 0,
            proStaffDelta   = 0,   -- summed below
        },
        -- #69 Daily hiring quota, so the FarmTablet/clients can show "x of 5 today".
        hiring = {
            limit     = WorkerManager.DAILY_HIRE_LIMIT,
            usedToday = self:getHiresUsedToday(),
            remaining = math.max(0, WorkerManager.DAILY_HIRE_LIMIT - self:getHiresUsedToday()),
        },
    }

    if self.workerRoster then
        -- #67 Trusted workers sort to the top here too, so every consumer (panel,
        -- tablet, MP client) shows the same favorite-first ordering.
        for _, w in ipairs(self.workerRoster:getDisplayOrder()) do
            local isWorking = w.assignedVehicleId ~= nil
            local isPinned  = w.assignedVehicleUniqueId ~= nil
            local status    = isWorking and "working" or "idle"
            if isPinned then status = status .. ", pinned" end

            snapshot.count = snapshot.count + 1
            if isWorking then snapshot.working = snapshot.working + 1 end
            if isPinned  then snapshot.pinned  = snapshot.pinned  + 1 end

            local level = w.level or WorkerRoster.LEVEL_NOVICE
            if level == WorkerRoster.LEVEL_MASTER then
                snapshot.levels.master = snapshot.levels.master + 1
            elseif level == WorkerRoster.LEVEL_EXPERIENCED then
                snapshot.levels.experienced = snapshot.levels.experienced + 1
            else
                snapshot.levels.novice = snapshot.levels.novice + 1
            end

            -- Indicative per-worker rate: base * level-efficiency, then fatigue
            -- surcharge (Master is immune). Situational night/weather/overtime
            -- multipliers are deliberately excluded — this is the steady-state rate.
            local fatigue     = w.fatigue or 0
            local levelFactor = WorkerSystem.LEVEL_WAGE_FACTOR[level] or 1.0
            local effRate     = baseRate * levelFactor
            if level ~= WorkerRoster.LEVEL_MASTER and fatigue > 0 then
                effRate = effRate * (1 + fatigue * WorkerSystem.FATIGUE_SURCHARGE)
            end
            snapshot.finance.proStaffDelta = snapshot.finance.proStaffDelta + (effRate - baseRate)

            table.insert(snapshot.workers, {
                uuid       = w.uuid,
                name       = w.name or "Worker",
                level      = level,
                levelName  = WorkerRoster.levelName(level),
                totalHours = w.totalHours or 0,
                totalJobs  = w.totalJobs or 0,
                fatigue    = fatigue,   -- 0..1
                working    = isWorking,
                pinned     = isPinned,
                trusted    = w.trusted == true,
                status     = status,
                baseRate   = baseRate,
                effRate    = effRate,
                proStaffDelta = effRate - baseRate,
                severance  = (workerSys and workerSys:computeSeverance(level)) or 0,
            })
        end
    end

    -- Recruit pool (slot-indexed so the client can name the exact slot to hire).
    for i, cand in ipairs(self:getRecruitPool()) do
        table.insert(snapshot.recruits, {
            slot      = i,
            name      = cand.name,
            level     = cand.level,
            levelName = WorkerRoster.levelName(cand.level),
            hireCost  = cand.hireCost,
        })
    end

    return snapshot
end

-- The public read contract. Server/SP computes live; a pure MP client returns the
-- last snapshot synced from the host (or an empty, non-authoritative placeholder
-- until the first sync arrives, so consumers can show a "host-managed" note).
function WorkerManager:getRosterSnapshot()
    local isServer = (g_currentMission ~= nil
        and g_currentMission.getIsServer ~= nil
        and g_currentMission:getIsServer()) and true or false

    if isServer then
        return self:getServerSnapshot()
    end

    return self.clientRosterSnapshot or {
        authoritative = false,
        count   = 0,
        working = 0,
        pinned  = 0,
        levels  = { novice = 0, experienced = 0, master = 0 },
        workers = {},
        recruits = {},
        finance = {},
        hiring  = { limit = WorkerManager.DAILY_HIRE_LIMIT, usedToday = 0, remaining = WorkerManager.DAILY_HIRE_LIMIT },
    }
end

-- Client stores the host's snapshot mirror (called from WCRosterSyncEvent).
function WorkerManager:applyClientSnapshot(snapshot)
    self.clientRosterSnapshot = snapshot
end

-- =========================================================
-- Pro-Staff Phase 5: worker management command API
-- =========================================================
-- Public methods every UI calls. They route through WCNetwork_SendCommand so the
-- SP path (apply now) and MP path (ask the host) share one code path. farmId
-- defaults to the caller's own farm so the right account is charged in MP.

local function localFarmId()
    return (g_currentMission and g_currentMission:getFarmId()) or 0
end

function WorkerManager:hireWorker(slot, farmId)
    WCNetwork_SendCommand(WCCommand.HIRE, 0, slot or 1, "", farmId or localFarmId())
end

function WorkerManager:fireWorker(uuid, farmId)
    WCNetwork_SendCommand(WCCommand.FIRE, uuid or 0, 0, "", farmId or localFarmId())
end

function WorkerManager:assignWorker(uuid, vehicleUniqueId)
    WCNetwork_SendCommand(WCCommand.ASSIGN, uuid or 0, 0, vehicleUniqueId or "", 0)
end

function WorkerManager:unassignWorker(uuid)
    WCNetwork_SendCommand(WCCommand.UNASSIGN, uuid or 0, 0, "", 0)
end

-- #67 Mark/unmark a worker as a Trusted ("favorite") employee. The desired state
-- rides in the slot field (1 = trusted, 0 = not) — no new wire field needed.
function WorkerManager:setTrusted(uuid, trusted)
    WCNetwork_SendCommand(WCCommand.SET_TRUSTED, uuid or 0, trusted and 1 or 0, "", 0)
end

function WorkerManager:refreshRecruits()
    WCNetwork_SendCommand(WCCommand.REFRESH_POOL, 0, 0, "", 0)
end

-- Server-side executor. Invoked directly in SP, or from WCWorkerCommandEvent on the
-- host. Applies one mutation, persists, then broadcasts the new snapshot to clients.
function WorkerManager:_applyCommandFromNetwork(action, uuid, slot, vehicleUniqueId, farmId)
    if not self.workerRoster then return end

    -- Each _doX returns false when nothing actually changed (e.g. a hire blocked by
    -- the daily cap, or a missing worker), so we skip the save + client broadcast for
    -- a no-op. nil/true both count as "changed" to keep the existing actions simple.
    local changed
    if action == WCCommand.HIRE then
        changed = self:_doHire(slot, farmId)
    elseif action == WCCommand.FIRE then
        changed = self:_doFire(uuid, farmId)
    elseif action == WCCommand.ASSIGN then
        changed = self:_doAssign(uuid, vehicleUniqueId)
    elseif action == WCCommand.UNASSIGN then
        changed = self:_doUnassign(uuid)
    elseif action == WCCommand.SET_TRUSTED then
        changed = self:_doSetTrusted(uuid, slot)
    elseif action == WCCommand.REFRESH_POOL then
        self:refreshRecruitPool()
    else
        return
    end

    if changed == false then
        return
    end

    self:saveWorkerData()
    self:_broadcastRosterSync()
end

-- Current in-game day (FS25 sandbox: no os.time). -1 default forces a rollover.
function WorkerManager:_currentDay()
    return (g_currentMission and g_currentMission.environment
        and g_currentMission.environment.currentDay) or 0
end

-- #69 Roll the daily-hire counter over to today if a new in-game day has started.
function WorkerManager:_rolloverHireDay()
    local roster = self.workerRoster
    local today = self:_currentDay()
    if roster.lastHireDay ~= today then
        roster.hiredToday  = 0
        roster.lastHireDay = today
    end
end

-- #69 Hires already used today (0 if the stored day is stale / a new day began).
function WorkerManager:getHiresUsedToday()
    local roster = self.workerRoster
    if not roster then return 0 end
    if roster.lastHireDay ~= self:_currentDay() then
        return 0
    end
    return roster.hiredToday or 0
end

function WorkerManager:_doHire(slot, farmId)
    local pool = self:getRecruitPool()
    slot = slot or 1
    local cand = pool[slot]
    if not cand then
        return false
    end

    -- #69 Daily hiring cap (server-authoritative). Reset on the day rollover, then
    -- reject once the limit is reached so the save can't be bypassed by reloading.
    self:_rolloverHireDay()
    if (self.workerRoster.hiredToday or 0) >= WorkerManager.DAILY_HIRE_LIMIT then
        self:_notifyHireLimit()
        Logging.info("[Worker Costs] Hire blocked — daily limit (%d) reached",
            WorkerManager.DAILY_HIRE_LIMIT)
        return false
    end

    if self.workerSystem then
        self.workerSystem:chargeHireCost(cand.name, cand.level, farmId)
    end

    local w = self.workerRoster:createWorker(cand.name)
    -- Seed XP so the recruit's advertised level holds after recomputeLevel().
    -- (Master is never offered by the roller — #68 — so that branch is defensive.)
    if cand.level == WorkerRoster.LEVEL_EXPERIENCED then
        w.totalXP = WorkerRoster.XP_EXPERIENCED
    elseif cand.level == WorkerRoster.LEVEL_MASTER then
        w.totalXP = WorkerRoster.XP_MASTER
    end
    self.workerRoster:recomputeLevel(w)

    -- Count this hire against today's quota (#69).
    self.workerRoster.hiredToday = (self.workerRoster.hiredToday or 0) + 1

    -- Consume the slot and refill so the pool always offers a full set.
    table.remove(pool, slot)
    table.insert(pool, self:_generateRecruit())

    Logging.info("[Worker Costs] Hired %s (level %d, id=%d) — %d/%d today",
        cand.name, cand.level, w.uuid, self.workerRoster.hiredToday, WorkerManager.DAILY_HIRE_LIMIT)
    return true
end

-- #69 Player feedback when the daily hire limit is hit (host/SP HUD toast; MP
-- clients see the remaining count in the synced snapshot).
function WorkerManager:_notifyHireLimit()
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(
            "Daily hiring limit reached. Please wait for the next day.", 4000)
    end
end

function WorkerManager:_doFire(uuid, farmId)
    local w = self.workerRoster:getWorker(uuid)
    if not w then
        return false
    end
    if self.workerSystem then
        self.workerSystem:chargeSeverance(w.name or "Worker", w.level, farmId)
    end
    self.workerRoster:removeWorker(uuid)
    Logging.info("[Worker Costs] Fired worker id=%d", uuid)
    return true
end

function WorkerManager:_doAssign(uuid, vehicleUniqueId)
    if not vehicleUniqueId or vehicleUniqueId == "" then
        return false
    end
    return self.workerRoster:assignVehiclePersistent(uuid, vehicleUniqueId)
end

function WorkerManager:_doUnassign(uuid)
    return self.workerRoster:unassignPersistent(uuid)
end

-- #67 Toggle a worker's Trusted/favorite flag. slot carries the desired state (1/0)
-- so the existing command channel needs no new wire field.
function WorkerManager:_doSetTrusted(uuid, slot)
    local w = self.workerRoster:getWorker(uuid)
    if not w then
        return false
    end
    local wantTrusted = (slot == 1)
    if w.trusted == wantTrusted then
        return false   -- no change, no broadcast
    end
    w.trusted = wantTrusted
    Logging.info("[Worker Costs] Worker id=%d trusted=%s", uuid, tostring(wantTrusted))
    return true
end

-- Push the fresh snapshot to all clients after a mutation (no-op in SP).
function WorkerManager:_broadcastRosterSync()
    if g_server ~= nil then
        g_server:broadcastEvent(WCRosterSyncEvent.new(self:getServerSnapshot()))
    end
end

-- Phase 5: register the rebindable WC_OPEN_ROSTER action (default ALT+H, shown in
-- the Controls menu) in BOTH the on-foot (PLAYER) and in-vehicle (VEHICLE) input
-- contexts. Mirrors SoilFertilizer's proven dual-context registration so the hotkey
-- works whether the player is walking or driving. The console command is the fallback.
function WorkerManager:installRosterInput()
    if not (InputAction and InputAction.WC_OPEN_ROSTER and g_inputBinding) then
        Logging.warning("[Worker Costs] WC_OPEN_ROSTER action unavailable - roster hotkey not bound")
        return
    end

    -- PLAYER (on-foot) context.
    if PlayerInputComponent and PlayerInputComponent.registerActionEvents then
        local original = PlayerInputComponent.registerActionEvents
        self._rosterPlayerInputOriginal = original
        PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
            original(inputComponent, ...)
            if not (inputComponent.player and inputComponent.player.isOwner) then return end
            local mgr = g_WorkerManager
            if not mgr or not mgr.rosterPanel or mgr.rosterPlayerEventId then return end
            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
            local ok, id = g_inputBinding:registerActionEvent(
                InputAction.WC_OPEN_ROSTER, mgr, mgr.onOpenRosterInput, false, true, false, true)
            if ok and id then
                mgr.rosterPlayerEventId = id
                g_inputBinding:setActionEventTextVisibility(id, false)
            end
            g_inputBinding:endActionEventsModification()
        end
    end

    -- VEHICLE context, via InputBinding.endActionEventsModification (hooking
    -- Vehicle.registerActionEvents directly does not work once vehicles exist).
    if InputBinding and InputBinding.endActionEventsModification and Vehicle then
        local originalEndMod = InputBinding.endActionEventsModification
        self._rosterVehicleInputOriginal = originalEndMod
        local reentrant = false
        InputBinding.endActionEventsModification = function(binding, ignoreCheck)
            local contextName = ""
            if binding.registrationContext and
               binding.registrationContext ~= InputBinding.NO_REGISTRATION_CONTEXT then
                contextName = binding.registrationContext.name or ""
            end
            originalEndMod(binding, ignoreCheck)
            if contextName ~= Vehicle.INPUT_CONTEXT_NAME or reentrant then return end
            local mgr = g_WorkerManager
            if not mgr or not mgr.rosterPanel then return end
            reentrant = true
            -- Fires on every seat change; purge stale ids (slot-based removeActionEvent
            -- can invalidate the PLAYER slot too, so clear both and let them re-register).
            if mgr.rosterVehicleEventId then
                pcall(function() binding:removeActionEvent(mgr.rosterVehicleEventId) end)
                mgr.rosterVehicleEventId = nil
            end
            if mgr.rosterPlayerEventId then
                pcall(function() binding:removeActionEvent(mgr.rosterPlayerEventId) end)
                mgr.rosterPlayerEventId = nil
            end
            binding:beginActionEventsModification(Vehicle.INPUT_CONTEXT_NAME)
            local ok, id = binding:registerActionEvent(
                InputAction.WC_OPEN_ROSTER, mgr, mgr.onOpenRosterInput, false, true, false, true)
            if ok and id then
                mgr.rosterVehicleEventId = id
                binding:setActionEventTextVisibility(id, false)
            end
            binding:endActionEventsModification()
            reentrant = false
        end
    end
end

-- Input callback for the WC_OPEN_ROSTER action.
function WorkerManager:onOpenRosterInput()
    if self.rosterPanel then
        self.rosterPanel:toggle()
    end
end

function WorkerManager:delete()
    -- Restore the original input functions we hooked, so they don't accumulate.
    if self._rosterPlayerInputOriginal and PlayerInputComponent then
        PlayerInputComponent.registerActionEvents = self._rosterPlayerInputOriginal
        self._rosterPlayerInputOriginal = nil
    end
    if self._rosterVehicleInputOriginal and InputBinding then
        InputBinding.endActionEventsModification = self._rosterVehicleInputOriginal
        self._rosterVehicleInputOriginal = nil
    end

    -- Restore the original mission.addMoney before the mission object is torn down
    if self.workerSystem then
        self.workerSystem:delete()
    end

    -- Pro-Staff Phase 1: drop g_messageCenter subscriptions so hooks don't
    -- accumulate across mission reloads.
    if self.jobTracker then
        self.jobTracker:delete()
    end

    -- HireHallCore is a sourced-once global singleton: reset its per-mission state
    -- (corruption flag, event listeners, evolution cursor) so the next career
    -- starts clean.
    if self.hireHall and self.hireHall.shutdown then
        self.hireHall:shutdown()
    end

    if self.rosterPanel then
        self.rosterPanel:delete()
    end

    if self.settings then
        self.settings:save()
    end

    Logging.info("Worker Costs Mod: Shut down")
end
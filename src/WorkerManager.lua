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
--   [x] Phase 1 — own WorkerJobTracker; subscribe on load, unsubscribe on delete
--   [ ] Phase 2 — drive XP accrual + level recompute
--   [ ] Phase 3 — own the calculateLaborCost modifier pipeline
--   [ ] Phase 4 — feed roster data (level/fatigue) to the WC*Frame UI
--   [ ] Phase 5 — expose getRosterSnapshot(); register MP roster-sync events
-- =========================================================
---@class WorkerManager
WorkerManager = {}
local WorkerManager_mt = Class(WorkerManager)

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

    self.workerSystem = WorkerSystem.new(self.settings)
    
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
end

-- Pro-Staff Phase 0: roster persistence entry points.
-- saveWorkerData is invoked from the FSCareerMissionInfo.saveToXMLFile hook in
-- main.lua (the real game-save event) — deliberately NOT from delete(), so a
-- quit-without-saving never overwrites the savegame's roster.

function WorkerManager:saveWorkerData(missionInfo)
    if not self.workerRoster then
        return
    end
    missionInfo = missionInfo or (g_currentMission and g_currentMission.missionInfo)
    self.workerRoster:save(missionInfo)
end

function WorkerManager:loadWorkerData()
    if not self.workerRoster then
        return
    end
    local missionInfo = g_currentMission and g_currentMission.missionInfo
    self.workerRoster:loadIfExists(missionInfo)
end

function WorkerManager:delete()
    -- Restore the original mission.addMoney before the mission object is torn down
    if self.workerSystem then
        self.workerSystem:delete()
    end

    -- Pro-Staff Phase 1: drop g_messageCenter subscriptions so hooks don't
    -- accumulate across mission reloads.
    if self.jobTracker then
        self.jobTracker:delete()
    end

    if self.settings then
        self.settings:save()
    end

    Logging.info("Worker Costs Mod: Shut down")
end
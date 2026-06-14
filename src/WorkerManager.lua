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

function WorkerManager:delete()
    -- Restore the original mission.addMoney before the mission object is torn down
    if self.workerSystem then
        self.workerSystem:delete()
    end

    if self.settings then
        self.settings:save()
    end

    Logging.info("Worker Costs Mod: Shut down")
end
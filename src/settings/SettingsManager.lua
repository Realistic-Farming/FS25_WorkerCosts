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
---@class SettingsManager
SettingsManager = SettingsManager or {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = (WorkerCostsModName or g_currentModName) or "FS25_WorkerCostsMod"
SettingsManager.XMLTAG = "WorkerCostsManager"

SettingsManager.defaultConfig = {
    wageLevel = 2,              -- 1=Low, 2=Medium, 3=High
    enabled = true,
    debugMode = false,
    costMode = 1,               -- 1=Hourly, 2=Per Hectare
    showNotifications = true,
    customRate = 0,
    monthlySalaryEnabled = true -- end-of-month salary summary dialog
}

function SettingsManager.new()
    local self = setmetatable({}, SettingsManager_mt)
    return self
end

function SettingsManager:getSavegameXmlFilePath()
    if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return ("%s/%s.xml"):format(g_currentMission.missionInfo.savegameDirectory, SettingsManager.MOD_NAME)
    end
    return nil
end

function SettingsManager:loadSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    
    -- Set defaults first
    settingsObject.wageLevel = self.defaultConfig.wageLevel
    settingsObject.enabled = self.defaultConfig.enabled
    settingsObject.debugMode = self.defaultConfig.debugMode
    settingsObject.costMode = self.defaultConfig.costMode
    settingsObject.showNotifications = self.defaultConfig.showNotifications
    settingsObject.customRate = self.defaultConfig.customRate
    settingsObject.monthlySalaryEnabled = self.defaultConfig.monthlySalaryEnabled
    
    -- Load from file if it exists
    if xmlPath and fileExists(xmlPath) then
        local xml = XMLFile.load("wc_Config", xmlPath)
        if xml then
            settingsObject.wageLevel = xml:getInt(self.XMLTAG..".wageLevel", self.defaultConfig.wageLevel)
            settingsObject.enabled = xml:getBool(self.XMLTAG..".enabled", self.defaultConfig.enabled)
            settingsObject.debugMode = xml:getBool(self.XMLTAG..".debugMode", self.defaultConfig.debugMode)
            settingsObject.costMode = xml:getInt(self.XMLTAG..".costMode", self.defaultConfig.costMode)
            settingsObject.showNotifications = xml:getBool(self.XMLTAG..".showNotifications", self.defaultConfig.showNotifications)
            settingsObject.customRate = xml:getInt(self.XMLTAG..".customRate", self.defaultConfig.customRate)
            settingsObject.monthlySalaryEnabled = xml:getBool(self.XMLTAG..".monthlySalaryEnabled", self.defaultConfig.monthlySalaryEnabled)
            
            xml:delete()
            Logging.info("Worker Costs Mod: Settings loaded from savegame")
            return
        end
    end
    
    Logging.info("Worker Costs Mod: Using default settings")
end

function SettingsManager:saveSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    if not xmlPath then 
        Logging.warning("Worker Costs Mod: Cannot save settings - no savegame directory")
        return 
    end
    
    local xml = XMLFile.create("wc_Config", xmlPath, self.XMLTAG)
    if xml then
        xml:setInt(self.XMLTAG..".wageLevel", settingsObject.wageLevel or self.defaultConfig.wageLevel)
        xml:setBool(self.XMLTAG..".enabled", settingsObject.enabled)
        xml:setBool(self.XMLTAG..".debugMode", settingsObject.debugMode)
        xml:setInt(self.XMLTAG..".costMode", settingsObject.costMode or self.defaultConfig.costMode)
        xml:setBool(self.XMLTAG..".showNotifications", settingsObject.showNotifications)
        xml:setInt(self.XMLTAG..".customRate", settingsObject.customRate or 0)
        xml:setBool(self.XMLTAG..".monthlySalaryEnabled", settingsObject.monthlySalaryEnabled ~= false)
        
        xml:save()
        xml:delete()
        Logging.info("Worker Costs Mod: Settings saved")
    else
        Logging.warning("Worker Costs Mod: Failed to create XML file for settings")
    end
end

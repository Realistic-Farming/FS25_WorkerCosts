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
---@class Settings

Settings = {}
local Settings_mt = Class(Settings)

Settings.WAGE_LEVEL_LOW = 1
Settings.WAGE_LEVEL_MEDIUM = 2
Settings.WAGE_LEVEL_HIGH = 3

Settings.COST_MODE_HOURLY = 1
Settings.COST_MODE_PER_HECTARE = 2

---@param manager SettingsManager
---@return Settings
function Settings.new(manager)
    local self = setmetatable({}, Settings_mt)
    self.manager = manager
    
    self:resetToDefaults(false) 
    
    Logging.info("Worker Costs Mod: Settings initialized")
    
    return self
end

---@param wageLevel number 
function Settings:setWageLevel(wageLevel)
    if wageLevel >= Settings.WAGE_LEVEL_LOW and wageLevel <= Settings.WAGE_LEVEL_HIGH then
        self.wageLevel = wageLevel
        
        local levelName = "Medium"
        if wageLevel == Settings.WAGE_LEVEL_LOW then
            levelName = "Low"
        elseif wageLevel == Settings.WAGE_LEVEL_HIGH then
            levelName = "High"
        end
        
        Logging.info("Worker Costs Mod: Wage level changed to: %s", levelName)
    end
end

---@return string 
function Settings:getWageLevelName()
    if self.wageLevel == Settings.WAGE_LEVEL_LOW then
        return "Low"
    elseif self.wageLevel == Settings.WAGE_LEVEL_HIGH then
        return "High"
    else
        return "Medium"
    end
end

Settings.SPINE_WAGE_SCALE = {
    id   = "wc_wageScale",
    dial = "labor",
    base = 1.0,
}

---@return number
function Settings:getWageRate()
    local baseRate
    if self.customRate > 0 then
        baseRate = self.customRate
    elseif self.wageLevel == Settings.WAGE_LEVEL_LOW then
        baseRate = 15
    elseif self.wageLevel == Settings.WAGE_LEVEL_HIGH then
        baseRate = 40
    else
        baseRate = 25
    end

    if OptionScalingResolver ~= nil then
        local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
        local profile = OptionScalingResolver.readProfile(hub)
        if profile ~= nil then
            baseRate = baseRate * OptionScalingResolver.resolve(Settings.SPINE_WAGE_SCALE, profile)
        end
    end

    return baseRate
end

---@param mode number
function Settings:setCostMode(mode)
    if mode == Settings.COST_MODE_HOURLY or mode == Settings.COST_MODE_PER_HECTARE then
        self.costMode = mode
        local modeName = mode == Settings.COST_MODE_HOURLY and "Hourly" or "Per Hectare"
        Logging.info("Worker Costs Mod: Cost mode changed to: %s", modeName)
    end
end

---@return string
function Settings:getCostModeName()
    if self.costMode == Settings.COST_MODE_HOURLY then
        return "Hourly"
    else
        return "Per Hectare"
    end
end

function Settings:load()
    -- Apply file values, then clamp/validate whatever was read
    self.manager:loadSettings(self)
    self:validateSettings()

    Logging.info("Worker Costs Mod: Settings loaded. Enabled: %s, Wage Level: %s, Cost Mode: %s",
        tostring(self.enabled), self:getWageLevelName(), self:getCostModeName())
end

function Settings:validateSettings()
    if self.wageLevel < Settings.WAGE_LEVEL_LOW or self.wageLevel > Settings.WAGE_LEVEL_HIGH then
        Logging.warning("Worker Costs Mod: Invalid wageLevel value %d, resetting to Medium", self.wageLevel)
        self.wageLevel = Settings.WAGE_LEVEL_MEDIUM
    end
    
    if self.costMode ~= Settings.COST_MODE_HOURLY and self.costMode ~= Settings.COST_MODE_PER_HECTARE then
        Logging.warning("Worker Costs Mod: Invalid costMode value %d, resetting to Hourly", self.costMode)
        self.costMode = Settings.COST_MODE_HOURLY
    end
    
    self.enabled = not not self.enabled
    self.debugMode = not not self.debugMode
    self.showNotifications = not not self.showNotifications
    self.monthlySalaryEnabled = not not self.monthlySalaryEnabled
    
    self.customRate = tonumber(self.customRate) or 0
    if self.customRate < 0 then
        self.customRate = 0
    end
end

function Settings:save()
    self.manager:saveSettings(self)
    Logging.info("Worker Costs Mod: Settings saved. Wage Level: %s, Cost Mode: %s",
        self:getWageLevelName(), self:getCostModeName())
end

---@param saveImmediately boolean
function Settings:resetToDefaults(saveImmediately)
    saveImmediately = saveImmediately ~= false
    
    self.wageLevel = Settings.WAGE_LEVEL_MEDIUM
    self.enabled = true
    self.debugMode = false
    self.costMode = Settings.COST_MODE_HOURLY
    self.showNotifications = true
    self.customRate = 0
    self.monthlySalaryEnabled = true  -- end-of-month salary summary dialog
    
    if saveImmediately then
        self:save()
        print("Worker Costs Mod: Settings reset to defaults")
    end
end
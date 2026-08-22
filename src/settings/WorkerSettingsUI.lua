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
-- NOTE: Keep the version string above in sync with modDesc.xml
--       and the header in main.lua whenever the mod version changes.
-- =========================================================
local function getTextSafe(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

---@class WorkerSettingsUI
WorkerSettingsUI = WorkerSettingsUI or {}
local WorkerSettingsUI_mt = Class(WorkerSettingsUI)

function WorkerSettingsUI.new(settings)
    local self = setmetatable({}, WorkerSettingsUI_mt)
    self.settings = settings
    self.injected = false
    return self
end

function WorkerSettingsUI:inject()
    if self.injected then 
        return 
    end
    
    local page = g_gui.screenControllers[InGameMenu].pageSettings
    if not page then
        Logging.error("wc: Settings page not found - cannot inject settings!")
        return 
    end
    
    local layout = page.generalSettingsLayout
    if not layout then
        Logging.error("wc: Settings layout not found!")
        return 
    end
    
    local section = UIHelper.createSection(layout, "wc_section")
    if not section then
        Logging.error("wc: Failed to create settings section!")
        return
    end
    
    local enabledOpt = UIHelper.createBinaryOption(
        layout,
        "wc_enabled",
        "wc_enabled",
        self.settings.enabled,
        function(val)
            self.settings.enabled = val
            self.settings:save()
        end
    )
    
    local debugOpt = UIHelper.createBinaryOption(
        layout,
        "wc_debug",
        "wc_debug",
        self.settings.debugMode,
        function(val)
            self.settings.debugMode = val
            self.settings:save()
        end
    )
    
    local costModeOptions = {
        getTextSafe("wc_costmode_1"),
        getTextSafe("wc_costmode_2")
    }
    
    local costModeOpt = UIHelper.createMultiOption(
        layout,
        "wc_costmode",
        "wc_costmode",
        costModeOptions,
        self.settings.costMode,
        function(val)
            self.settings.costMode = val
            self.settings:save()
        end
    )
    
    local wageOptions = {
        getTextSafe("wc_diff_1"),
        getTextSafe("wc_diff_2"),
        getTextSafe("wc_diff_3")
    }
    
    local wageOpt = UIHelper.createMultiOption(
        layout,
        "wc_wage",
        "wc_difficulty",
        wageOptions,
        self.settings.wageLevel,
        function(val)
            self.settings.wageLevel = val
            self.settings:save()
        end
    )
    
    local notificationsOpt = UIHelper.createBinaryOption(
        layout,
        "wc_notifications",
        "wc_notifications",
        self.settings.showNotifications,
        function(val)
            self.settings.showNotifications = val
            self.settings:save()
        end
    )

    -- Monthly salary dialog toggle (end-of-month summary)
    local monthlySalaryOpt = UIHelper.createBinaryOption(
        layout,
        "wc_monthly_salary",
        "wc_monthly_salary",
        self.settings.monthlySalaryEnabled,
        function(val)
            self.settings.monthlySalaryEnabled = val
            self.settings:save()
        end
    )

    self.enabledOption         = enabledOpt
    self.debugOption           = debugOpt
    self.costModeOption        = costModeOpt
    self.wageLevelOption       = wageOpt
    self.notificationsOption   = notificationsOpt
    self.monthlySalaryOption   = monthlySalaryOpt
    
    self.injected = true
    layout:invalidateLayout()

    Logging.info("Worker Costs Mod: Settings UI injected successfully")
end

function WorkerSettingsUI:refreshUI()
    if not self.injected then
        return
    end
    
    if self.enabledOption and self.enabledOption.setIsChecked then
        self.enabledOption:setIsChecked(self.settings.enabled)
    elseif self.enabledOption and self.enabledOption.setState then
        self.enabledOption:setState(self.settings.enabled and 2 or 1)
    end
    
    if self.debugOption and self.debugOption.setIsChecked then
        self.debugOption:setIsChecked(self.settings.debugMode)
    elseif self.debugOption and self.debugOption.setState then
        self.debugOption:setState(self.settings.debugMode and 2 or 1)
    end
    
    if self.costModeOption and self.costModeOption.setState then
        self.costModeOption:setState(self.settings.costMode)
    end
    
    if self.wageLevelOption and self.wageLevelOption.setState then
        self.wageLevelOption:setState(self.settings.wageLevel)
    end
    
    if self.notificationsOption and self.notificationsOption.setIsChecked then
        self.notificationsOption:setIsChecked(self.settings.showNotifications)
    elseif self.notificationsOption and self.notificationsOption.setState then
        self.notificationsOption:setState(self.settings.showNotifications and 2 or 1)
    end

    if self.monthlySalaryOption and self.monthlySalaryOption.setIsChecked then
        self.monthlySalaryOption:setIsChecked(self.settings.monthlySalaryEnabled)
    elseif self.monthlySalaryOption and self.monthlySalaryOption.setState then
        self.monthlySalaryOption:setState(self.settings.monthlySalaryEnabled and 2 or 1)
    end
end

function WorkerSettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then
        return
    end

    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = g_i18n:getText("wc_reset") or "Reset Settings",
            callback = function()
                if g_WorkerManager and g_WorkerManager.settings then
                    g_WorkerManager.settings:resetToDefaults()
                    if g_WorkerManager.WorkerSettingsUI then
                        g_WorkerManager.WorkerSettingsUI:refreshUI()
                    end
                end
            end,
            showWhenPaused = true
        }
    end

    -- Guard against duplicate insertion (called on every frame open)
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn == self._resetButton then
            return
        end
    end

    table.insert(settingsFrame.menuButtonInfo, self._resetButton)
    settingsFrame:setMenuButtonInfoDirty()
end
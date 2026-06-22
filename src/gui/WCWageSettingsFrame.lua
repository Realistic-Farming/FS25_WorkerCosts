-- =========================================================
-- FS25 Worker Costs Mod
-- WCWageSettingsFrame.lua  -  Tab 2: Wage Settings
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class WCWageSettingsFrame
WCWageSettingsFrame = {}
local WCWageSettingsFrame_mt = Class(WCWageSettingsFrame, TabbedMenuFrameElement)

function WCWageSettingsFrame.new()
    local self = WCWageSettingsFrame:superClass().new(nil, WCWageSettingsFrame_mt)
    self.name       = "WCWageSettingsFrame"
    self.className  = "WCWageSettingsFrame"
    self._refreshing = false
    return self
end

function WCWageSettingsFrame:onGuiSetupFinished()
    WCWageSettingsFrame:superClass().onGuiSetupFinished(self)
    self:bindCallbacks()
end

function WCWageSettingsFrame:initialize()
    -- nothing extra needed at init time
end

-- Wire up all the option widgets → settings.
-- Reads current widget state via getState() to avoid the FS25 target-as-first-arg
-- issue where raiseCallback passes (self.target, state) to closures.
function WCWageSettingsFrame:bindCallbacks()
    if self.optEnabled then
        self.optEnabled.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings.enabled = (self.optEnabled:getState() == 2)
                g_WorkerManager.settings:save()
            end
        end
    end

    if self.optCostMode then
        self.optCostMode.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings:setCostMode(self.optCostMode:getState())
                g_WorkerManager.settings:save()
                self:refreshRatePreview()
                self:refreshHelpText()
                self:refreshWageLevelOptions()   -- #83 re-unit the tier labels for the new strategy
            end
        end
    end

    if self.optWageLevel then
        self.optWageLevel.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings:setWageLevel(self.optWageLevel:getState())
                g_WorkerManager.settings:save()
                self:refreshRatePreview()
            end
        end
    end

    if self.optNotifications then
        self.optNotifications.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings.showNotifications = (self.optNotifications:getState() == 2)
                g_WorkerManager.settings:save()
            end
        end
    end

    if self.optDebugMode then
        self.optDebugMode.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings.debugMode = (self.optDebugMode:getState() == 2)
                g_WorkerManager.settings:save()
            end
        end
    end

    if self.optMonthlySalary then
        self.optMonthlySalary.onClickCallback = function(...)
            if self._refreshing then return end
            if g_WorkerManager and g_WorkerManager.settings then
                g_WorkerManager.settings.monthlySalaryEnabled = (self.optMonthlySalary:getState() == 2)
                g_WorkerManager.settings:save()
            end
        end
    end
end

function WCWageSettingsFrame:onFrameOpen()
    WCWageSettingsFrame:superClass().onFrameOpen(self)
    self:refresh()
end

function WCWageSettingsFrame:onFrameClose()
    WCWageSettingsFrame:superClass().onFrameClose(self)
end

-- Sync all widgets to current settings values.
-- The _refreshing guard prevents any incidental callback fires during setState.
function WCWageSettingsFrame:refresh()
    if g_WorkerManager == nil then return end
    local settings = g_WorkerManager.settings
    if settings == nil then return end

    self._refreshing = true

    if self.optEnabled and self.optEnabled.setState then
        self.optEnabled:setState(settings.enabled and 2 or 1)
    end

    if self.optCostMode then
        if self.optCostMode.setTexts then
            self.optCostMode:setTexts({
                g_i18n:getText("wc_costmode_1"),
                g_i18n:getText("wc_costmode_2"),
            })
        end
        if self.optCostMode.setState then
            self.optCostMode:setState(settings.costMode)
        end
    end

    -- #83 Wage-level (Compensation Tier) labels are built with a mode-aware unit.
    self:refreshWageLevelOptions()

    if self.optNotifications and self.optNotifications.setState then
        self.optNotifications:setState(settings.showNotifications and 2 or 1)
    end

    if self.optDebugMode and self.optDebugMode.setState then
        self.optDebugMode:setState(settings.debugMode and 2 or 1)
    end

    if self.optMonthlySalary and self.optMonthlySalary.setState then
        self.optMonthlySalary:setState(settings.monthlySalaryEnabled and 2 or 1)
    end

    self._refreshing = false

    self:refreshRatePreview()
    self:refreshHelpText()
end

-- #83 Build the Compensation Tier option labels with a unit that tracks the active
-- Payment Strategy ($/h vs $/ha). The localized tier name is kept (the "(rate)" part
-- is stripped and rebuilt), and the unit matches the English format the big rate
-- display already uses — so the option no longer shows "/h" while in Per-Hectare mode.
function WCWageSettingsFrame:refreshWageLevelOptions()
    if self.optWageLevel == nil or self.optWageLevel.setTexts == nil then return end
    local settings = g_WorkerManager and g_WorkerManager.settings
    if settings == nil then return end

    local unit  = (settings.costMode == Settings.COST_MODE_PER_HECTARE) and "ha" or "h"
    local rates = { 15, 25, 40 }   -- Settings:getWageRate() per level (Low / Medium / High)
    local texts = {}
    for i = 1, 3 do
        local base = g_i18n:getText("wc_diff_" .. i) or ""
        local name = base:gsub("%s*%b()%s*$", "")   -- drop "($15/h)", keep the localized tier name
        texts[i] = string.format("%s ($%d/%s)", name, rates[i], unit)
    end

    -- Guard so setState() doesn't re-fire the wage-level callback mid-update.
    local wasRefreshing = self._refreshing
    self._refreshing = true
    self.optWageLevel:setTexts(texts)
    if self.optWageLevel.setState then
        self.optWageLevel:setState(settings.wageLevel)
    end
    self._refreshing = wasRefreshing
end

-- Update the live "effective rate" preview text
function WCWageSettingsFrame:refreshRatePreview()
    if g_WorkerManager == nil then return end
    local settings = g_WorkerManager.settings
    if settings == nil then return end

    local rate = settings:getWageRate()

    if self.txtBigRate then
        if settings.costMode == Settings.COST_MODE_HOURLY then
            self.txtBigRate:setText(string.format("$%d / h", rate))
        else
            self.txtBigRate:setText(string.format("$%d / ha", rate))
        end
    end

    if self.txtRateLabel then
        self.txtRateLabel:setText(settings:getWageLevelName())
    end

    if self.txtPayInterval and g_WorkerManager.workerSystem then
        local ms  = g_WorkerManager.workerSystem.paymentInterval
        local min = math.floor(ms / 60000)
        self.txtPayInterval:setText(string.format("%d min", min))
    end
end

-- Update the Cost Structure help body to reflect the active cost mode
function WCWageSettingsFrame:refreshHelpText()
    if self.txtHelpBody == nil then return end
    if g_WorkerManager == nil then return end
    local settings = g_WorkerManager.settings
    if settings == nil then return end

    if settings.costMode == Settings.COST_MODE_HOURLY then
        self.txtHelpBody:setText(g_i18n:getText("wc_help_body"))
    else
        self.txtHelpBody:setText(g_i18n:getText("wc_help_body_ha"))
    end
end

-- Reset button callback (wired from XML onClick)
function WCWageSettingsFrame:onClickReset()
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings:resetToDefaults()
        self:refresh()
        Logging.info("WCWageSettingsFrame: Settings reset to defaults.")
    end
end

function WCWageSettingsFrame:onBtnResetFocus()
    if self.btnResetBg then
        self.btnResetBg:setImageColor(0.50, 0.16, 0.16, 0.95)
    end
end

function WCWageSettingsFrame:onBtnResetLeave()
    if self.btnResetBg then
        self.btnResetBg:setImageColor(0.35, 0.12, 0.12, 0.95)
    end
end

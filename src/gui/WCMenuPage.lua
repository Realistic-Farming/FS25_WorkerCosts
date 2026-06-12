-- =========================================================
-- FS25 Worker Costs Mod
-- WCMenuPage.lua  -  Outer pause-menu tab (icon entry point)
-- =========================================================
-- Author: TisonK
-- =========================================================

local MOD_DIR = g_currentModDirectory

---@class WCMenuPage
WCMenuPage = {}
WCMenuPage.CLASS_NAME     = "WCMenuPage"
WCMenuPage.MENU_PAGE_NAME = "menuWorkerCosts"

-- MOD_DIR captured at source() time - always valid
function WCMenuPage.getXmlFilename()
    return MOD_DIR .. "xml/gui/WCMenuPage.xml"
end

local WCMenuPage_mt = Class(WCMenuPage, TabbedMenuFrameElement)

function WCMenuPage.new()
    local self = WCMenuPage:superClass().new(nil, WCMenuPage_mt)
    self.name      = "WCMenuPage"
    self.className = "WCMenuPage"
    self.menuButtonInfo = {}
    return self
end

function WCMenuPage:onGuiSetupFinished()
    WCMenuPage:superClass().onGuiSetupFinished(self)
end

function WCMenuPage:initialize()
    WCMenuPage:superClass().initialize(self)

    self.btnBack = { inputAction = InputAction.MENU_BACK, text = g_i18n:getText("button_back") }
    self.btnOpen = {
        inputAction = InputAction.MENU_ACCEPT,
        text = g_i18n:getText("wc_btn_open_manager"),
        callback = function() self:onOpenManager() end
    }

    self.menuButtonInfo = { self.btnBack, self.btnOpen }
end

function WCMenuPage:onFrameOpen()
    WCMenuPage:superClass().onFrameOpen(self)
    self._liveTimer = 0
    self:refresh()
end

function WCMenuPage:onFrameClose()
    WCMenuPage:superClass().onFrameClose(self)
end

function WCMenuPage:update(dt)
    WCMenuPage:superClass().update(self, dt)
    self._liveTimer = (self._liveTimer or 0) + dt
    if self._liveTimer >= 500 then
        self._liveTimer = 0
        self:refreshLive()
    end
end

function WCMenuPage:refresh()
    if g_WorkerManager == nil then return end
    local settings = g_WorkerManager.settings
    if settings == nil then return end

    if self.txtModEnabled then
        local enabled = settings.enabled
        self.txtModEnabled:setText(g_i18n:getText(enabled and "wc_status_active" or "wc_status_inactive"))
        if self.txtModEnabled.setTextColor then
            if enabled then
                self.txtModEnabled:setTextColor(0.18, 0.74, 0.22, 1)
            else
                self.txtModEnabled:setTextColor(1.0, 0.35, 0.35, 1)
            end
        end
    end

    if self.txtCostMode then
        self.txtCostMode:setText(settings:getCostModeName())
    end

    if self.txtWageLevel then
        self.txtWageLevel:setText(settings:getWageLevelName())
    end

    if self.txtWageRate then
        local rate = settings:getWageRate()
        if settings.costMode == Settings.COST_MODE_HOURLY then
            self.txtWageRate:setText(string.format("$%d / h", rate))
        else
            self.txtWageRate:setText(string.format("$%d / ha", rate))
        end
    end

    self:refreshLive()
end

-- Updates only time-varying fields (timer, worker count, est. cost, balance, countdown)
function WCMenuPage:refreshLive()
    if g_WorkerManager == nil then return end
    local ws       = g_WorkerManager.workerSystem
    local settings = g_WorkerManager.settings
    if ws == nil or settings == nil then return end

    local workers     = ws:getActiveWorkers()
    local workerCount = #workers

    if self.txtActiveWorkers then
        self.txtActiveWorkers:setText(tostring(workerCount))
    end

    if self.txtNextPayment then
        local remaining = math.max(0, ws.paymentInterval - ws.realTimeAccumulator)
        local mins = math.floor(remaining / 60000)
        local secs = math.floor((remaining % 60000) / 1000)
        self.txtNextPayment:setText(string.format("%d:%02d", mins, secs))
    end

    if self.txtEstCost then
        if workerCount > 0 then
            local estimate = ws:getEstimatedIntervalCost(workerCount)
            self.txtEstCost:setText(g_i18n:formatMoney(estimate, 0, true, false))
        else
            self.txtEstCost:setText("-")
        end
    end

    if self.txtFarmBalance and g_localPlayer and g_farmManager then
        local farm = g_farmManager:getFarmById(g_localPlayer.farmId)
        if farm then
            self.txtFarmBalance:setText(g_i18n:formatMoney(farm.money, 0, true, false))
        end
    end
end

function WCMenuPage:onOpenManager()
    if g_wcGui ~= nil then
        g_gui:showGui("WCGui")
    end
end

function WCMenuPage:onBtnOpenManagerFocus()
    if self.btnOpenManagerBg then
        self.btnOpenManagerBg:setImageColor(0.16, 0.45, 0.22, 0.95)
    end
end

function WCMenuPage:onBtnOpenManagerLeave()
    if self.btnOpenManagerBg then
        self.btnOpenManagerBg:setImageColor(0.12, 0.35, 0.12, 0.95)
    end
end

function WCMenuPage:getMenuButtonInfo()
    return self.menuButtonInfo
end

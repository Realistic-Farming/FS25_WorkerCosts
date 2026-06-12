-- =========================================================
-- FS25 Worker Costs Mod
-- WCDashboardFrame.lua  -  Tab 1: Live dashboard
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class WCDashboardFrame
WCDashboardFrame = {}
local WCDashboardFrame_mt = Class(WCDashboardFrame, TabbedMenuFrameElement)

function WCDashboardFrame.new()
    local self = WCDashboardFrame:superClass().new(nil, WCDashboardFrame_mt)
    self.name      = "WCDashboardFrame"
    self.className = "WCDashboardFrame"
    return self
end

function WCDashboardFrame:onGuiSetupFinished()
    WCDashboardFrame:superClass().onGuiSetupFinished(self)
end

function WCDashboardFrame:initialize()
    -- nothing extra needed at init time
end

function WCDashboardFrame:onFrameOpen()
    WCDashboardFrame:superClass().onFrameOpen(self)
    self:refresh()
end

function WCDashboardFrame:onFrameClose()
    WCDashboardFrame:superClass().onFrameClose(self)
end

-- Called whenever the frame becomes visible or data changes
function WCDashboardFrame:refresh()
    if g_WorkerManager == nil then return end
    local ws       = g_WorkerManager.workerSystem
    local settings = g_WorkerManager.settings
    if ws == nil or settings == nil then return end

    -- ── Mod status ──────────────────────────────────────────
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

    -- ── Current rate display ──────────────────────────────────
    if self.txtCurrentRate then
        local rate = settings:getWageRate()
        local rateFormatted = g_i18n:formatMoney(rate, 0, true, false)
        if settings.costMode == Settings.COST_MODE_HOURLY then
            self.txtCurrentRate:setText(rateFormatted .. " / h")
        else
            self.txtCurrentRate:setText(rateFormatted .. " / ha")
        end
    end

    -- ── Wage mode ─────────────────────────────────────────────
    if self.txtCostMode then
        self.txtCostMode:setText(settings:getCostModeName())
    end

    -- ── Wage level ────────────────────────────────────────────
    if self.txtWageLevel then
        self.txtWageLevel:setText(settings:getWageLevelName())
    end

    self:refreshLive()
end

-- Updates only the fields that change every payment tick (timer, workers, balance)
function WCDashboardFrame:refreshLive()
    if g_WorkerManager == nil then return end
    local ws       = g_WorkerManager.workerSystem
    local settings = g_WorkerManager.settings
    if ws == nil or settings == nil then return end

    -- ── Active workers ───────────────────────────────────────
    local workers = ws:getActiveWorkers()
    local workerCount = #workers

    if self.txtWorkerCount then
        self.txtWorkerCount:setText(tostring(workerCount))
    end

    -- ── Worker names list ─────────────────────────────────────
    if self.txtWorkerNames then
        if workerCount > 0 then
            local names = {}
            for _, w in ipairs(workers) do
                -- Show which vehicle the helper is driving (#48)
                local label = w.name
                if w.vehicleName ~= nil and w.vehicleName ~= w.name then
                    label = string.format("%s (%s)", w.name, w.vehicleName)
                end
                table.insert(names, label)
            end
            self.txtWorkerNames:setText(table.concat(names, "\n"))
        else
            self.txtWorkerNames:setText(g_i18n:getText("wc_no_workers"))
        end
    end

    -- ── Next payment countdown ───────────────────────────────
    if self.txtNextPayment then
        local remaining = math.max(0, ws.paymentInterval - ws.realTimeAccumulator)
        local mins = math.floor(remaining / 60000)
        local secs = math.floor((remaining % 60000) / 1000)
        self.txtNextPayment:setText(string.format("%d:%02d", mins, secs))
    end

    -- ── Estimated cost this interval ───────────────────────────
    if self.txtEstimatedCost then
        if workerCount > 0 then
            local estimate = ws:getEstimatedIntervalCost(workerCount)
            self.txtEstimatedCost:setText(g_i18n:formatMoney(estimate, 0, true, false))
        else
            self.txtEstimatedCost:setText("-")
        end
    end

    -- ── Farm balance ──────────────────────────────────────────
    if self.txtFarmBalance and g_localPlayer and g_farmManager then
        local farm = g_farmManager:getFarmById(g_localPlayer.farmId)
        if farm then
            self.txtFarmBalance:setText(g_i18n:formatMoney(farm.money, 0, true, false))
        end
    end
end

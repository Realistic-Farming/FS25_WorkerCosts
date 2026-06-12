-- =========================================================
-- FS25 Worker Costs Mod
-- WCWorkerStatsFrame.lua  -  Tab 3: Per-worker cost breakdown
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class WCWorkerStatsFrame
WCWorkerStatsFrame = {}
local WCWorkerStatsFrame_mt = Class(WCWorkerStatsFrame, TabbedMenuFrameElement)

function WCWorkerStatsFrame.new()
    local self = WCWorkerStatsFrame:superClass().new(nil, WCWorkerStatsFrame_mt)
    self.name      = "WCWorkerStatsFrame"
    self.className = "WCWorkerStatsFrame"
    return self
end

function WCWorkerStatsFrame:onGuiSetupFinished()
    WCWorkerStatsFrame:superClass().onGuiSetupFinished(self)
end

function WCWorkerStatsFrame:initialize()
    -- nothing extra needed at init time
end

function WCWorkerStatsFrame:onFrameOpen()
    WCWorkerStatsFrame:superClass().onFrameOpen(self)
    self:refresh()
end

function WCWorkerStatsFrame:onFrameClose()
    WCWorkerStatsFrame:superClass().onFrameClose(self)
end

function WCWorkerStatsFrame:refresh()
    if g_WorkerManager == nil then return end
    local settings = g_WorkerManager.settings
    if settings == nil then return end

    if self.txtCostMode then
        self.txtCostMode:setText(settings:getCostModeName())
    end

    if self.txtWageLevel then
        self.txtWageLevel:setText(settings:getWageLevelName())
    end

    if self.txtPayInterval and g_WorkerManager.workerSystem then
        local min = math.floor(g_WorkerManager.workerSystem.paymentInterval / 60000)
        self.txtPayInterval:setText(string.format("%d min", min))
    end

    self:refreshLive()
end

function WCWorkerStatsFrame:refreshLive()
    if g_WorkerManager == nil then return end
    local ws       = g_WorkerManager.workerSystem
    local settings = g_WorkerManager.settings
    if ws == nil or settings == nil then return end

    local workers     = ws:getActiveWorkers()
    local workerCount = #workers
    local rate        = settings:getWageRate()
    local intervalHrs = ws.paymentInterval / 3600000
    local isHourly    = (settings.costMode == Settings.COST_MODE_HOURLY)

    -- Active worker count (big)
    if self.txtWorkerCount then
        self.txtWorkerCount:setText(tostring(workerCount))
    end

    -- Cost per worker per interval
    if self.txtCostPerWorker then
        if isHourly and workerCount > 0 then
            local costPer = math.floor(rate * intervalHrs)
            self.txtCostPerWorker:setText(g_i18n:formatMoney(costPer, 0, true, false))
        elseif workerCount > 0 then
            -- Per-hectare: average of the accrued costs so far this interval
            local total = ws:getEstimatedIntervalCost(workerCount)
            self.txtCostPerWorker:setText(g_i18n:formatMoney(math.floor(total / workerCount), 0, true, false))
        else
            self.txtCostPerWorker:setText("-")
        end
    end

    -- Total cost per interval
    if self.txtTotalCost then
        if workerCount > 0 then
            local total = ws:getEstimatedIntervalCost(workerCount)
            self.txtTotalCost:setText(g_i18n:formatMoney(total, 0, true, false))
        else
            self.txtTotalCost:setText("-")
        end
    end

    -- Per-worker breakdown list
    if self.txtWorkerList then
        if workerCount > 0 then
            local lines = {}
            for _, w in ipairs(workers) do
                local cost
                if isHourly then
                    cost = math.floor(rate * intervalHrs)
                else
                    -- Per-hectare: cost accrued from area worked so far this interval (#46)
                    local hectares = ws.workerHectares[tostring(w.vehicle)] or 0
                    cost = math.floor(rate * hectares)
                end
                table.insert(lines, w.name .. "   -" .. g_i18n:formatMoney(cost, 0, true, false))
            end
            self.txtWorkerList:setText(table.concat(lines, "\n"))
        else
            self.txtWorkerList:setText(g_i18n:getText("wc_no_workers"))
        end
    end
end

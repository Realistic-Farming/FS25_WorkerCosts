-- =========================================================
-- FS25 Worker Costs Mod
-- WCSalaryDialog.lua  -  End-of-month salary summary screen
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================

local MOD_DIR = g_currentModDirectory

---@class WCSalaryDialog
WCSalaryDialog = {}
local WCSalaryDialog_mt = Class(WCSalaryDialog, MessageDialog)

WCSalaryDialog.CLASS_NAME   = "WCSalaryDialog"
WCSalaryDialog.XML_FILENAME = "xml/gui/WCSalaryDialog.xml"

function WCSalaryDialog.new()
    local self = MessageDialog.new(nil, WCSalaryDialog_mt)
    self.name      = WCSalaryDialog.CLASS_NAME
    self.className = WCSalaryDialog.CLASS_NAME

    self.salaryEntries     = {}
    self.totalAmount       = 0
    self.monthNumber       = 1
    self.isPenaltyMonth    = false
    self.onPayCallback     = nil
    self.onDeclineCallback = nil

    return self
end

-- ─────────────────────────────────────────────────────────
-- Registration: called once from WCModGui:load()
-- ─────────────────────────────────────────────────────────
function WCSalaryDialog.register()
    if g_gui == nil then return end
    local controller = WCSalaryDialog.new()
    g_gui:loadGui(MOD_DIR .. WCSalaryDialog.XML_FILENAME,
                  WCSalaryDialog.CLASS_NAME,
                  controller)
    g_wcSalaryDialog = controller
    Logging.info("WCSalaryDialog: registered")
end

-- ─────────────────────────────────────────────────────────
-- Data injection — call before g_gui:showGui
-- ─────────────────────────────────────────────────────────
function WCSalaryDialog:setData(entries, total, month, isPenalty, onPay, onDecline)
    self.salaryEntries     = entries or {}
    self.totalAmount       = total or 0
    self.monthNumber       = month or 1
    self.isPenaltyMonth    = isPenalty or false
    self.onPayCallback     = onPay
    self.onDeclineCallback = onDecline
end

-- ─────────────────────────────────────────────────────────
-- FS25 lifecycle
-- ─────────────────────────────────────────────────────────
function WCSalaryDialog:onCreate()
    WCSalaryDialog:superClass().onCreate(self)
end

function WCSalaryDialog:onGuiSetupFinished()
    WCSalaryDialog:superClass().onGuiSetupFinished(self)
end

function WCSalaryDialog:onOpen()
    WCSalaryDialog:superClass().onOpen(self)
    self:populateUI()
    if self.btnPay then
        FocusManager:setFocus(self.btnPay)
    end
end

function WCSalaryDialog:onClose()
    WCSalaryDialog:superClass().onClose(self)
end

-- ─────────────────────────────────────────────────────────
-- UI population
-- ─────────────────────────────────────────────────────────
function WCSalaryDialog:populateUI()
    if self.txtTitle then
        self.txtTitle:setText(string.format("Monthly Worker Salaries - Month %d", self.monthNumber))
    end

    if self.txtPenalty then
        if self.isPenaltyMonth then
            self.txtPenalty:setText(">> LATE PAYMENT PENALTY: 20% surcharge applied! <<")
            self.txtPenalty:setVisible(true)
        else
            self.txtPenalty:setVisible(false)
        end
    end

    if self.txtWorkerList then
        local lines = {}
        for _, entry in ipairs(self.salaryEntries) do
            local aStr = (g_i18n and g_i18n:formatMoney(entry.amount, 0, true, false) or tostring(entry.amount)); table.insert(lines, string.format("%s    %s", entry.name, aStr))
        end
        if #lines == 0 then
            table.insert(lines, "(No workers were active this month)")
        end
        self.txtWorkerList:setText(table.concat(lines, "\n"))
    end

    if self.txtTotal then
        self.txtTotal:setText(g_i18n and g_i18n:formatMoney(self.totalAmount, 0, true, false) or tostring(self.totalAmount))
    end

    if self.txtBtnPay then
        local pStr = (g_i18n and g_i18n:formatMoney(self.totalAmount, 0, true, false) or tostring(self.totalAmount)); self.txtBtnPay:setText("Pay  " .. pStr)
    end

    -- Show the penalty warning on the Decline button only when a penalty is actually active
    if self.txtBtnDecline then
        if self.isPenaltyMonth then
            self.txtBtnDecline:setText("Decline (penalty already applied)")
        else
            self.txtBtnDecline:setText("Decline (20% penalty next month)")
        end
    end
end

-- ─────────────────────────────────────────────────────────
-- Button callbacks (wired from XML onClick)
-- ─────────────────────────────────────────────────────────
function WCSalaryDialog:onClickPay()
    self:changeScreen()
    if self.onPayCallback then
        self.onPayCallback()
    end
end

function WCSalaryDialog:onClickDecline()
    self:changeScreen()
    if self.onDeclineCallback then
        self.onDeclineCallback()
    end
end

function WCSalaryDialog:onBtnPayFocus()
    if self.btnPayBg then self.btnPayBg:setImageColor(0.18, 0.55, 0.18, 1) end
end
function WCSalaryDialog:onBtnPayLeave()
    if self.btnPayBg then self.btnPayBg:setImageColor(0.12, 0.35, 0.12, 0.95) end
end
function WCSalaryDialog:onBtnDeclineFocus()
    if self.btnDeclineBg then self.btnDeclineBg:setImageColor(0.55, 0.18, 0.18, 1) end
end
function WCSalaryDialog:onBtnDeclineLeave()
    if self.btnDeclineBg then self.btnDeclineBg:setImageColor(0.35, 0.12, 0.12, 0.95) end
end

function WCSalaryDialog:onButtonBack()
    -- ESC/back closes the dialog without invoking the decline callback.
    -- Decline (with its 20% penalty) is only triggered by the explicit Decline button.
    -- However, we must still clear pendingSalary here so the unpaid amount isn't
    -- silently lost. We do NOT set declinedLastMonth — only the Decline button does that.
    self:changeScreen()
    if g_WorkerManager and g_WorkerManager.workerSystem then
        local ws = g_WorkerManager.workerSystem
        -- Pay automatically on ESC — the player cannot indefinitely defer salary
        -- by hitting Escape, as that would be an exploit.
        if ws.pendingSalary then
            ws:executeMonthlySalaryPayment()
        end
    end
    return true
end

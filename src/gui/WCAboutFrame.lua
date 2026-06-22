-- =========================================================
-- FS25 Worker Costs Mod
-- WCAboutFrame.lua  -  Tab 4: About / Help
-- =========================================================
-- Author: TisonK
-- #80: modular tabbed layout (Core / Formulas / Pro-Staff). All three panels
-- are pre-loaded from the XML; switching is a pure index-based visibility
-- toggle (no g_gui:loadGui or file parsing at runtime), per the issue spec.
-- =========================================================

---@class WCAboutFrame
WCAboutFrame = {}
local WCAboutFrame_mt = Class(WCAboutFrame, TabbedMenuFrameElement)

-- Sub-tab indices
WCAboutFrame.TAB_CORE     = 1
WCAboutFrame.TAB_FORMULAS = 2
WCAboutFrame.TAB_STAFF    = 3

-- Tab-button background colours (active / inactive / hover)
local COL_ACTIVE   = { 0.22, 0.50, 0.22, 0.95 }
local COL_INACTIVE = { 0.13, 0.27, 0.13, 0.85 }
local COL_HOVER    = { 0.30, 0.62, 0.30, 0.98 }

function WCAboutFrame.new()
    local self = WCAboutFrame:superClass().new(nil, WCAboutFrame_mt)
    self.name       = "WCAboutFrame"
    self.className   = "WCAboutFrame"
    self.currentTab = WCAboutFrame.TAB_CORE
    return self
end

function WCAboutFrame:onGuiSetupFinished()
    WCAboutFrame:superClass().onGuiSetupFinished(self)
end

function WCAboutFrame:initialize()
    -- nothing extra needed at init time
end

function WCAboutFrame:onFrameOpen()
    WCAboutFrame:superClass().onFrameOpen(self)
    self:selectTab(self.currentTab or WCAboutFrame.TAB_CORE)
    self:refresh()
end

function WCAboutFrame:onFrameClose()
    WCAboutFrame:superClass().onFrameClose(self)
end

-- ── Sub-tab switching ────────────────────────────────────────────────────
-- Index-based visibility toggle: zero runtime allocation, instant switch.
function WCAboutFrame:selectTab(index)
    self.currentTab = index
    if self.paneCore     ~= nil then self.paneCore:setVisible(index == WCAboutFrame.TAB_CORE)        end
    if self.paneFormulas ~= nil then self.paneFormulas:setVisible(index == WCAboutFrame.TAB_FORMULAS) end
    if self.paneStaff    ~= nil then self.paneStaff:setVisible(index == WCAboutFrame.TAB_STAFF)       end
    self:applyTabColors()
end

function WCAboutFrame:applyTabColors()
    self:setBgColor(self.btnTabCoreBg,     self.currentTab == WCAboutFrame.TAB_CORE)
    self:setBgColor(self.btnTabFormulasBg, self.currentTab == WCAboutFrame.TAB_FORMULAS)
    self:setBgColor(self.btnTabStaffBg,    self.currentTab == WCAboutFrame.TAB_STAFF)
end

function WCAboutFrame:setBgColor(el, isActive)
    if el == nil then return end
    local c = isActive and COL_ACTIVE or COL_INACTIVE
    el:setImageColor(c[1], c[2], c[3], c[4])
end

-- Click handlers (wired from XML onClick=)
function WCAboutFrame:onClickTabCore()     self:selectTab(WCAboutFrame.TAB_CORE);     self:refresh() end
function WCAboutFrame:onClickTabFormulas() self:selectTab(WCAboutFrame.TAB_FORMULAS); self:refresh() end
function WCAboutFrame:onClickTabStaff()    self:selectTab(WCAboutFrame.TAB_STAFF);    self:refresh() end

-- Hover highlight. On leave we restore the correct active/inactive colour
-- so hovering never leaves a tab stuck in the wrong state.
function WCAboutFrame:onTabCoreFocus()     self:setBgColor(self.btnTabCoreBg, true);     if self.btnTabCoreBg     then self.btnTabCoreBg:setImageColor(COL_HOVER[1], COL_HOVER[2], COL_HOVER[3], COL_HOVER[4])     end end
function WCAboutFrame:onTabFormulasFocus() if self.btnTabFormulasBg then self.btnTabFormulasBg:setImageColor(COL_HOVER[1], COL_HOVER[2], COL_HOVER[3], COL_HOVER[4]) end end
function WCAboutFrame:onTabStaffFocus()    if self.btnTabStaffBg    then self.btnTabStaffBg:setImageColor(COL_HOVER[1], COL_HOVER[2], COL_HOVER[3], COL_HOVER[4])    end end
function WCAboutFrame:onTabCoreLeave()     self:applyTabColors() end
function WCAboutFrame:onTabFormulasLeave() self:applyTabColors() end
function WCAboutFrame:onTabStaffLeave()    self:applyTabColors() end

-- ── Dynamic data binding ─────────────────────────────────────────────────
function WCAboutFrame:refresh()
    local wm       = g_WorkerManager
    local settings = wm and wm.settings

    -- Core panel: payment interval
    if self.txtPayInterval and wm and wm.workerSystem then
        local min = math.floor(wm.workerSystem.paymentInterval / 60000)
        self.txtPayInterval:setText(string.format("%d min", min))
    end

    -- Core panel: live mod version (modName captured at load, folder-name fallback)
    if self.txtVersion then
        local version = "unknown"
        if g_modManager then
            local modName = (wm and wm.modName) or "FS25_WorkerCosts"
            local mod = g_modManager:getModByName(modName)
            if not (mod and mod.version) then
                mod = g_modManager:getModByName("FS25_WorkerCosts")
            end
            if mod and mod.version then version = mod.version end
        end
        self.txtVersion:setText(version)
    end

    -- Formulas panel: bind the live effective rate / mode to the Settings model
    -- so it always reflects the player's current configuration.
    if settings ~= nil then
        local rate     = settings:getWageRate()
        local isHourly = settings.costMode == Settings.COST_MODE_HOURLY
        if self.txtEffRate then
            self.txtEffRate:setText(string.format(isHourly and "$%d / h" or "$%d / ha", rate))
        end
        if self.txtRateLabel then
            self.txtRateLabel:setText(settings:getWageLevelName())
        end
        if self.txtCostMode then
            self.txtCostMode:setText(g_i18n:getText(isHourly and "wc_cost_mode_hourly" or "wc_cost_mode_hectare"))
        end
    end
end

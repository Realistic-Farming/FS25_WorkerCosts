-- =========================================================
-- FS25 Worker Costs Mod
-- WCGui.lua  -  Inner TabbedMenu (Dashboard + Wage Settings)
-- =========================================================
-- Author: TisonK
-- =========================================================

local MOD_DIR = (WorkerCostsModDirectory or g_currentModDirectory)

---@class WCGui
WCGui = WCGui or {}
local WCGui_mt = Class(WCGui, TabbedMenu)

function WCGui.new(messageCenter, l18n, inputManager)
    local self = TabbedMenu.new(nil, WCGui_mt, messageCenter, l18n, inputManager)
    self.messageCenter = messageCenter
    self.l18n          = l18n
    self.inputManager  = g_inputBinding
    self._refreshTimer = 0
    return self
end

function WCGui:onGuiSetupFinished()
    WCGui:superClass().onGuiSetupFinished(self)

    self.clickBackCallback = self:makeSelfCallback(self.onButtonBack)

    self.pageDashboard:initialize()
    self.pageWageSettings:initialize()
    self.pageWorkerStats:initialize()
    self.pageAbout:initialize()

    self:setupPages(self)
    self:setupMenuButtonInfo()
end

function WCGui:setupPages(gui)
    -- Each tab uses a different quadrant of the tab_icons.dds spritesheet (1024x1024, 2x2 grid).
    -- GuiUtils.getUVs expects { x, y, width, height } in pixels.
    local tabIcons = Utils.getFilename("tab_icons.dds", MOD_DIR)

    -- 4px inset per side to avoid sampling the spritesheet grid lines at quadrant edges
    local pages = {
        { gui.pageDashboard,    GuiUtils.getUVs({   4,   4, 504, 504 }) },  -- top-left:     person + euro
        { gui.pageWageSettings, GuiUtils.getUVs({ 516,   4, 504, 504 }) },  -- top-right:    gear / settings
        { gui.pageWorkerStats,  GuiUtils.getUVs({   4, 516, 504, 504 }) },  -- bottom-left:  stars / trending
        { gui.pageAbout,        GuiUtils.getUVs({ 516, 516, 504, 504 }) },  -- bottom-right: clock + list
    }

    for idx, entry in ipairs(pages) do
        local page, uvs = unpack(entry)
        gui:registerPage(page, idx)
        gui:addPageTab(page, tabIcons, uvs)
    end

    gui:rebuildTabList()
end

function WCGui:setupMenuButtonInfo()
    local onBack = self.clickBackCallback

    self.defaultMenuButtonInfo = {
        {
            inputAction = InputAction.MENU_BACK,
            text        = g_i18n:getText("button_back"),
            callback    = onBack,
        },
    }
    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.defaultMenuButtonInfo[1]
    self.defaultButtonActionCallbacks = { [InputAction.MENU_BACK] = onBack }
end

function WCGui:update(dt)
    WCGui:superClass().update(self, dt)
    self._refreshTimer = self._refreshTimer + dt
    if self._refreshTimer >= 500 then
        self._refreshTimer = 0
        if self.pageDashboard and self.pageDashboard.refreshLive then
            self.pageDashboard:refreshLive()
        end
        if self.pageWorkerStats and self.pageWorkerStats.refreshLive then
            self.pageWorkerStats:refreshLive()
        end
    end
end

function WCGui:onOpen()
    WCGui:superClass().onOpen(self)
    self._refreshTimer = 0
    self.pageDashboard:refresh()
    self.pageWageSettings:refresh()
    self.pageWorkerStats:refresh()
    self.pageAbout:refresh()
end

function WCGui:onClose()
    WCGui:superClass().onClose(self)
end

function WCGui:onButtonBack()
    self:exitMenu()
end

function WCGui:onClickBack()
    self:exitMenu()
end

function WCGui:exitMenu()
    self:changeScreen()
end

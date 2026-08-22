-- =========================================================
-- FS25 Worker Costs Mod
-- WCModGui.lua - Pause menu tab page registration
-- =========================================================
-- Author: TisonK
-- =========================================================

-- Capture the mod directory at source() time.
-- (WorkerCostsModDirectory or g_currentModDirectory) is valid during source() execution.
-- We store it as a module-level local so it's available forever after.
local MOD_DIR = (WorkerCostsModDirectory or g_currentModDirectory)

---@class WCModGui
WCModGui = WCModGui or {}
local WCModGui_mt = Class(WCModGui)

-- ─────────────────────────────────────────────────────────
-- Internal helper: inject a frame into InGameMenu as a tab
-- ─────────────────────────────────────────────────────────
local function addIngameMenuPage(frame, pageName, iconPath, uvs, position, predicateFunc)
    local targetPosition = 0
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then
        Logging.warning("WCModGui: InGameMenu not found.")
        return
    end

    if inGameMenu.pagingElement == nil
            or inGameMenu.pagingElement.elements == nil
            or inGameMenu.pagingElement.pages == nil
            or inGameMenu.pageFrames == nil then
        Logging.warning("WCModGui: InGameMenu not fully initialized.")
        return
    end

    -- Clear any stale controlID so loadGui doesn't collide
    for _, v in pairs({ pageName }) do
        g_inGameMenu.controlIDs[v] = nil
    end

    -- Locate the insertion point (string = after named page, number = absolute)
    if type(position) == "string" then
        for i = 1, #g_inGameMenu.pagingElement.elements do
            local child = g_inGameMenu.pagingElement.elements[i]
            if child == g_inGameMenu[position] then
                targetPosition = i + 1
                break
            end
        end
    elseif type(position) == "number" then
        targetPosition = position
    else
        Logging.warning("WCModGui: Invalid position type.")
        return
    end

    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    inGameMenu:exposeControlsAsFields(pageName)

    -- Move into correct slot in pagingElement.elements
    if position ~= nil then
        for i = #inGameMenu.pagingElement.elements, 1, -1 do
            local child = inGameMenu.pagingElement.elements[i]
            if child == inGameMenu[pageName] then
                table.remove(inGameMenu.pagingElement.elements, i)
                table.insert(inGameMenu.pagingElement.elements, targetPosition, child)
                break
            end
        end

        for i = #inGameMenu.pagingElement.pages, 1, -1 do
            local child = inGameMenu.pagingElement.pages[i]
            if child.element == inGameMenu[pageName] then
                table.remove(inGameMenu.pagingElement.pages, i)
                table.insert(inGameMenu.pagingElement.pages, targetPosition, child)
                break
            end
        end
    end

    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    inGameMenu:registerPage(inGameMenu[pageName], nil, predicateFunc)

    local iconFileName = Utils.getFilename(iconPath, MOD_DIR)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))

    -- Move pageFrames entry
    if position ~= nil then
        for i = 1, #g_inGameMenu.pageFrames do
            local child = inGameMenu.pageFrames[i]
            if child == inGameMenu[pageName] then
                table.remove(inGameMenu.pageFrames, i)
                table.insert(inGameMenu.pageFrames, targetPosition, child)
                break
            end
        end
    end

    inGameMenu:rebuildTabList()
end

-- ─────────────────────────────────────────────────────────
-- Constructor
-- ─────────────────────────────────────────────────────────
function WCModGui.new()
    local self = setmetatable({}, WCModGui_mt)

    if g_client ~= nil then
        addConsoleCommand("wcReloadGui", "Reload Worker Costs GUI", "consoleReloadGui", self)
    end

    return self
end

-- ─────────────────────────────────────────────────────────
-- Load: called from ModController after map is loaded
-- ─────────────────────────────────────────────────────────
function WCModGui:load()
    if g_client == nil then return end

    -- Load our custom profiles first so all WC_ names are available
    g_gui:loadProfiles(MOD_DIR .. "xml/gui/guiProfiles.xml")

    -- RF Esc greenfield: one Realistic Farming door; skip legacy only when door actually exists.
    -- RfEscBootstrap ~= nil means class sourced, not door present — call tryRegister/ensureDoor first.
    if RfEscBootstrap ~= nil then
        local ok = false
        if WcRfPdaGuest ~= nil and type(WcRfPdaGuest.tryRegister) == "function" then
            ok = WcRfPdaGuest.tryRegister()
        end
        if ok and g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil then
            Logging.info("WCModGui: RF Esc door + workerCosts module ready (legacy WCMenuPage skipped)")
        else
            Logging.warning("WCModGui: RF Esc register pending; will retry on update (no legacy until door exists)")
        end
    else
        -- Load the outer InGameMenu page (the icon-tab entry point)
        if not self:loadMenuFrame(WCMenuPage) then
            Logging.warning("WCModGui: WCMenuPage already loaded or failed.")
        end
    end

    -- Load the inner TabbedMenu with its sub-frames (Worker Manager deep desk)
    self:loadTabbedMenu()
end

-- ─────────────────────────────────────────────────────────
-- Register the WCMenuPage icon tab inside InGameMenu
-- ─────────────────────────────────────────────────────────
function WCModGui:loadMenuFrame(class)
    if class == nil then return false end

    local pageName = class.MENU_PAGE_NAME
    if self[pageName] ~= nil then return false end
    if g_gui == nil or g_inGameMenu == nil then return false end

    local pageController = class.new()
    -- Use getXmlFilename() so MOD_DIR is resolved at call-time, not load-time
    local xmlFile = class.getXmlFilename and class.getXmlFilename() or (MOD_DIR .. "xml/gui/" .. class.CLASS_NAME .. ".xml")
    g_gui:loadGui(xmlFile, class.CLASS_NAME, pageController, true)

    -- Icon: top-left quadrant of the tab_icons spritesheet (1024x1024, 2x2 grid).
    -- 4px inset avoids sampling the grid lines at quadrant edges.
    local iconPath = "tab_icons.dds"
    local uvs = { 4, 4, 504, 504 }

    addIngameMenuPage(
        pageController,
        pageName,
        iconPath,
        uvs,
        "pageSettings",   -- insert right after the Settings tab
        function() return true end
    )

    if pageController.initialize ~= nil then
        pageController:initialize()
    end

    self[pageName] = pageController
    return true
end

-- ─────────────────────────────────────────────────────────
-- Inner TabbedMenu: Dashboard + Wage Settings sub-frames
-- ─────────────────────────────────────────────────────────
function WCModGui:loadTabbedMenu()
    local dashFrame    = WCDashboardFrame.new()
    local wageFrame    = WCWageSettingsFrame.new()
    local statsFrame   = WCWorkerStatsFrame.new()
    local aboutFrame   = WCAboutFrame.new()

    g_wcGui = WCGui.new(g_messageCenter, g_i18n, g_inputBinding)

    -- Suite soft-detect: publish the Worker Manager screen on the mission so the
    -- Esc door host (whichever mod built RfPdaMenuPage) can open it from its own
    -- env. g_currentMission is the only table every mod can read; bare g_wcGui is
    -- WorkerCosts-scoped and nil to the host. This is the authoritative publish
    -- site, right where the screen is created (the guest's tryRegister can run
    -- before this and must not rely on g_wcGui existing yet).
    if g_currentMission ~= nil then
        g_currentMission.rfWcGui = g_wcGui
    end

    g_gui:loadGui(MOD_DIR .. "xml/gui/WCDashboardFrame.xml",    "WCDashboardFrame",    dashFrame,  true)
    g_gui:loadGui(MOD_DIR .. "xml/gui/WCWageSettingsFrame.xml", "WCWageSettingsFrame", wageFrame,  true)
    g_gui:loadGui(MOD_DIR .. "xml/gui/WCWorkerStatsFrame.xml",  "WCWorkerStatsFrame",  statsFrame, true)
    g_gui:loadGui(MOD_DIR .. "xml/gui/WCAboutFrame.xml",        "WCAboutFrame",        aboutFrame, true)
    g_gui:loadGui(MOD_DIR .. "xml/gui/WCGui.xml",               "WCGui",               g_wcGui)

    -- Register the salary dialog screen
    WCSalaryDialog.register()

    Logging.info("WCModGui: TabbedMenu loaded successfully.")
end

-- ─────────────────────────────────────────────────────────
-- Map-loaded hook
-- ─────────────────────────────────────────────────────────
function WCModGui:onMapLoaded()
    if g_client ~= nil then
        if g_inGameMenu ~= nil and g_inGameMenu.pagingTabList ~= nil then
            g_inGameMenu.pagingTabList.listItemAlignment = SmoothListElement.ALIGN_START
        end
        self:load()
    end
end

function WCModGui:update(_dt)
    if g_client == nil or RfEscBootstrap == nil or WcRfPdaGuest == nil then
        return
    end
    -- Retry until door exists AND module registered (isRegistered alone is not enough).
    local doorPresent = g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
    if doorPresent and type(WcRfPdaGuest.isRegistered) == "function" and WcRfPdaGuest.isRegistered() then
        return
    end
    if type(WcRfPdaGuest.tryRegister) == "function" then
        local ok = WcRfPdaGuest.tryRegister()
        if ok then
            Logging.info("WCModGui: RF Esc door + workerCosts module ready (legacy WCMenuPage skipped)")
        end
    end
end

-- ─────────────────────────────────────────────────────────
-- Console
-- ─────────────────────────────────────────────────────────
function WCModGui:consoleReloadGui()
    if g_inGameMenu == nil then
        return "Worker Costs GUI: cannot reload before map is loaded"
    end
    self:load()
    return "Worker Costs GUI reloaded"
end

g_wcModGui = WCModGui.new()

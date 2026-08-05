-- =========================================================
-- WcRfPdaGuest
-- Esc RF PDA guest: Worker Costs FULL PORT (4 pages under PF-style subnav).
-- Stage-8 BUILD 2026-07-31 (Samantha DESIGN + George ENGINE ACK + Ash GO).
-- Soft-detects g_currentMission.rfEscModules (NO HOST); registerModule.
-- Soft-detect manager: g_currentMission.workerCostsManager.
-- Hang fences: text / MultiTextOption setState only; no SmoothList reloadData.
-- Farm balance OMIT. Hire/fire/salary dialogs stay deep WCGui.
-- =========================================================

WcRfPdaGuest = {}

-- Capture at source() time — g_currentModDirectory is often nil at deferred/map-load callbacks.
local MOD_DIR = g_currentModDirectory
local WC_RF_MOD_NAME = g_currentModName
local PANEL_ID = "workerCosts"
local PANEL_ORDER = 30

local PAGE_DASHBOARD = 1
local PAGE_WAGES = 2
local PAGE_WORKERS = 3
-- PAGE_ABOUT retired 2026-08-02: consolidated into wcSideInfoShell.

local _registered = false
local _legacyStoodDown = false
local _subnavSeeded = false

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[WC_RF_MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and type(text) == "string" and text ~= "" then
            local lower = text:lower()
            -- Reject unresolved keys (engine often returns "MISSING KEY_NAME").
            if lower ~= tostring(key):lower()
                and text ~= ("$l10n_" .. key)
                and not lower:find("^missing%s")
                and not lower:find("^missing_")
            then
                return text
            end
        end
    end
    return fallback or key
end

local function getMgr()
    if g_currentMission ~= nil and g_currentMission.workerCostsManager ~= nil then
        return g_currentMission.workerCostsManager
    end
    return g_WorkerManager
end

local function getHost()
    -- Shared module registry only (NO HOST). Never rfPdaHost.
    if g_currentMission ~= nil and g_currentMission.rfEscModules ~= nil then
        return g_currentMission.rfEscModules
    end
    local env = getfenv(0)
    if env ~= nil and env.g_rfEscModules ~= nil then
        return env.g_rfEscModules
    end
    if RfEscModules ~= nil then
        return RfEscModules.getOrCreate()
    end
    return nil
end

local function getHostPage()
    if g_inGameMenu == nil then
        return nil
    end
    return g_inGameMenu.menuRealisticFarming
end

local function findDescendant(root, id)
    if root == nil or id == nil then
        return nil
    end
    if root.getDescendantById then
        local el = root:getDescendantById(id)
        if el ~= nil then
            return el
        end
    end
    local page = getHostPage()
    if page and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

local function setText(el, text)
    if el ~= nil and type(el.setText) == "function" then
        el:setText(text or "")
    end
end

local function setVis(el, visible)
    if el ~= nil and type(el.setVisible) == "function" then
        el:setVisible(visible)
    end
end

local function setTextColor(el, r, g, b, a)
    if el ~= nil and type(el.setTextColor) == "function" then
        el:setTextColor(r, g, b, a)
    end
end

local function formatMoney(amount)
    if g_i18n and g_i18n.formatMoney then
        return g_i18n:formatMoney(amount, 0, true, false)
    end
    return string.format("$%d", math.floor(amount + 0.5))
end

local function labeled(label, value)
    -- House style: single colon. Strip trailing ":" from l10n labels that already include one.
    local lbl = tostring(label or ""):gsub(":%s*$", "")
    return string.format("%s: %s", lbl, tostring(value or ""))
end

local function getPageSelector(container)
    local page = getHostPage()
    -- N-1: left rfFilterBox wcSubnavSelector (never title-chrome / content-body).
    local sel = (page and page.wcSubnavSelector) or findDescendant(container, "wcSubnavSelector")
    if sel == nil and page ~= nil and page.getDescendantById then
        sel = page:getDescendantById("wcSubnavSelector")
    end
    if page ~= nil and sel ~= nil then
        page.wcSubnavSelector = sel
    end
    return sel
end

local function clampPageIndex(idx)
    idx = tonumber(idx) or PAGE_DASHBOARD
    if idx < PAGE_DASHBOARD then
        return PAGE_DASHBOARD
    end
    if idx > PAGE_WORKERS then
        return PAGE_WORKERS
    end
    return idx
end

local function getPageIndex(container)
    local page = getHostPage()
    if page ~= nil and page.wcSubPageIndex ~= nil then
        return clampPageIndex(page.wcSubPageIndex)
    end
    local sel = getPageSelector(container)
    if sel ~= nil and sel.getState then
        return clampPageIndex(sel:getState())
    end
    return PAGE_DASHBOARD
end

--- Lower WC side box: page how-to + consolidated About (no Version prefix; no About tab page).
local function paintSideInfo(container)
    local idx = getPageIndex(container)
    local howTo
    if idx == PAGE_WAGES then
        howTo = tr("rf_pda_side_info_wc_wages",
            "Wages\n\nSet AI pay: billing on/off, Hourly (per active hour) or Per hectare (area worked), Wage Level, and notices. Reset restores defaults. Hire/fire in Worker Manager / Farm Tablet; confirm actives on Dashboard afterward.")
    elseif idx == PAGE_WORKERS then
        howTo = tr("rf_pda_side_info_wc_workers",
            "Workers\n\nRoster glance: summary stats and per-worker cost for your wage settings. Read-only hire - use Worker Manager (or Farm Tablet with Pro-Staff). Dashboard shows who is active; Wages if rates look wrong.")
    else
        howTo = tr("rf_pda_side_info_wc_dashboard",
            "Dashboard\n\nLive glance: wage mode (Hourly or Per hectare), rate, active AI workers, next midnight settle. Names = who is on the clock now. Billing on Wages; hire/fire in Worker Manager (or Farm Tablet with Pro-Staff), not here.")
    end
    local about = tr("rf_pda_side_info_wc_about",
        "About: Wages settle at midnight on the in-game clock (fair 1x-120x). Settings save per game; MP follows the host. Hourly or Per hectare both scale with Wage Level. Pro-Staff links appear when loaded.")
    local body = howTo .. "\n\n" .. about
    local shell = findDescendant(container, "wcSideInfoShell")
    local bodyEl = findDescendant(container, "wcSideInfoBody")
    setVis(shell, true)
    setText(bodyEl, body)
end

local function seedSubnav(container)
    -- RESTORE: seed left page MTO once; never setState(..., true).
    if _subnavSeeded then
        return
    end
    local page = getHostPage()
    local sel = getPageSelector(container)
    if sel == nil then
        return
    end
    sel.disableButtonsOnSingleText = false
    sel.hideLeftRightButtons = false
    if sel.setVisible then
        sel:setVisible(true)
    end
    if sel.setCanChangeState then
        sel:setCanChangeState(true)
    end
    if sel.setDisabled then
        sel:setDisabled(false)
    end
    local texts = {
        tr("wc_rf_pda_page_dashboard", "Dashboard"),
        tr("wc_rf_pda_page_wages", "Wages"),
        tr("wc_rf_pda_page_workers", "Workers"),
    }
    local idx = clampPageIndex(page and page.wcSubPageIndex)
    if page ~= nil then
        page.wcSubPageIndex = idx
        page._wcWageRefreshing = true
        page._wcSubnavSeeding = true
    end
    if sel.setTexts then
        sel:setTexts(texts)
    end
    if sel.setState then
        sel:setState(idx, false)
    end
    if sel.updateAbsolutePosition then
        sel:updateAbsolutePosition()
    end
    if page ~= nil then
        page._wcSubnavSeeding = false
        page._wcWageRefreshing = false
        page._wcSubnavSeeded = true
        if page._ensureWcSubnavArrowsVisible then
            page:_ensureWcSubnavArrowsVisible()
        end
        if page._syncWcSubPageVisibility then
            page:_syncWcSubPageVisibility()
        end
    end
    _subnavSeeded = true
end

local function paintDashboard(container, lightOnly)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.workerSystem == nil then
        setText(findDescendant(container, "wcDashStatus"),
            tr("wc_rf_pda_empty", "Worker Costs is not ready yet."))
        return
    end
    local settings = mgr.settings
    local ws = mgr.workerSystem

    if not lightOnly then
        local status = settings.enabled and tr("wc_status_active", "Active") or tr("wc_status_inactive", "Inactive")
        setText(findDescendant(container, "wcDashStatus"),
            labeled(tr("wc_label_mod_enabled", "Status"), status))
        local statusEl = findDescendant(container, "wcDashStatus")
        if settings.enabled then
            setTextColor(statusEl, 0.18, 0.74, 0.22, 1)
        else
            setTextColor(statusEl, 1.0, 0.35, 0.35, 1)
        end
        setText(findDescendant(container, "wcDashMode"),
            labeled(tr("wc_label_cost_mode", "Cost Mode"), settings:getCostModeName()))
        setText(findDescendant(container, "wcDashWage"),
            labeled(tr("wc_label_wage_level", "Wage Level"), settings:getWageLevelName()))
        local rate = settings:getWageRate()
        local rateText = settings.costMode == Settings.COST_MODE_HOURLY
            and (formatMoney(rate) .. " / h") or (formatMoney(rate) .. " / ha")
        setText(findDescendant(container, "wcDashRate"),
            labeled(tr("wc_label_current_rate", "Rate"), rateText))
    end

    local workers = ws:getActiveWorkers()
    local workerCount = #workers
    setText(findDescendant(container, "wcDashWorkers"),
        labeled(tr("wc_label_active_workers", "Active Workers"), tostring(workerCount)))

    local namesEl = findDescendant(container, "wcDashWorkerNames")
    if workerCount > 0 then
        local names = {}
        local roster = mgr.workerRoster
        for _, w in ipairs(workers) do
            local label = w.name
            if w.vehicleName ~= nil and w.vehicleName ~= w.name then
                label = string.format("%s (%s)", w.name, w.vehicleName)
            end
            if roster then
                local rw = roster:getWorkerByVehicle(tostring(w.vehicle))
                if rw and WorkerRoster and WorkerRoster.levelName then
                    label = string.format("[%s] %s", WorkerRoster.levelName(rw.level), label)
                end
            end
            table.insert(names, label)
        end
        setText(namesEl, table.concat(names, "\n"))
    else
        setText(namesEl, tr("wc_no_workers", "No active workers"))
    end

    local remaining = 0
    local env = g_currentMission and g_currentMission.environment
    if env and env.dayTime and WorkerSystem and WorkerSystem.DAY_MS then
        remaining = math.max(0, WorkerSystem.DAY_MS - env.dayTime)
    end
    local hrs = math.floor(remaining / 3600000)
    local mins = math.floor((remaining % 3600000) / 60000)
    setText(findDescendant(container, "wcDashCountdown"),
        labeled(tr("wc_label_next_payment", "Next Payment"), string.format("%d:%02d", hrs, mins)))

    if workerCount > 0 then
        setText(findDescendant(container, "wcDashEstimate"),
            labeled(tr("wc_label_est_cost", "Est. Cost"), formatMoney(ws:getEstimatedIntervalCost(workerCount))))
    else
        setText(findDescendant(container, "wcDashEstimate"),
            labeled(tr("wc_label_est_cost", "Est. Cost"), "-"))
    end
    -- Farm balance intentionally omitted on Esc (Wizard LOCK).
end

local function yesNoTexts()
    return { tr("ui_off", "Off"), tr("ui_on", "On") }
end

local function syncWageWidgets(container)
    local mgr = getMgr()
    local settings = mgr and mgr.settings
    if settings == nil then
        return
    end
    local page = getHostPage()
    if page ~= nil then
        page._wcWageRefreshing = true
    end

    local optEnabled = findDescendant(container, "wcOptEnabled")
    local optCostMode = findDescendant(container, "wcOptCostMode")
    local optWageLevel = findDescendant(container, "wcOptWageLevel")
    local optNotifications = findDescendant(container, "wcOptNotifications")
    local optDebugMode = findDescendant(container, "wcOptDebugMode")
    local optMonthlySalary = findDescendant(container, "wcOptMonthlySalary")

    setText(findDescendant(container, "wcWageLblEnabled"), tr("wc_enabled_short", "Enable Mod"))
    setText(findDescendant(container, "wcWageLblMode"), tr("wc_label_cost_mode", "Cost Mode"))
    setText(findDescendant(container, "wcWageLblLevel"), tr("wc_label_wage_level", "Wage Level"))
    setText(findDescendant(container, "wcWageLblNotify"), tr("wc_notifications_short", "Notifications"))
    setText(findDescendant(container, "wcWageLblDebug"), tr("wc_debug_short", "Debug Mode"))
    setText(findDescendant(container, "wcWageLblSalary"), tr("wc_monthly_salary_short", "Monthly Salary"))

    -- forceEvent=false: never re-raise onClick from Lua sync (arrow-crash FAIL-FIX).
    if optEnabled and optEnabled.setTexts then
        optEnabled:setTexts(yesNoTexts())
        if optEnabled.setState then optEnabled:setState(settings.enabled and 2 or 1, false) end
    end
    if optCostMode and optCostMode.setTexts then
        optCostMode:setTexts({
            tr("wc_costmode_1", "Hourly"),
            tr("wc_costmode_2", "Per Hectare"),
        })
        if optCostMode.setState then optCostMode:setState(settings.costMode, false) end
    end
    if optWageLevel and optWageLevel.setTexts then
        local unit = (settings.costMode == Settings.COST_MODE_PER_HECTARE) and "ha" or "h"
        local rates = { 15, 25, 40 }
        local texts = {}
        for i = 1, 3 do
            local base = tr("wc_diff_" .. i, "Tier " .. i)
            local name = base:gsub("%s*%b()%s*$", "")
            texts[i] = string.format("%s ($%d/%s)", name, rates[i], unit)
        end
        optWageLevel:setTexts(texts)
        if optWageLevel.setState then optWageLevel:setState(settings.wageLevel, false) end
    end
    if optNotifications and optNotifications.setTexts then
        optNotifications:setTexts(yesNoTexts())
        if optNotifications.setState then
            optNotifications:setState(settings.showNotifications and 2 or 1, false)
        end
    end
    if optDebugMode and optDebugMode.setTexts then
        optDebugMode:setTexts(yesNoTexts())
        if optDebugMode.setState then optDebugMode:setState(settings.debugMode and 2 or 1, false) end
    end
    if optMonthlySalary and optMonthlySalary.setTexts then
        optMonthlySalary:setTexts(yesNoTexts())
        if optMonthlySalary.setState then
            optMonthlySalary:setState(settings.monthlySalaryEnabled and 2 or 1, false)
        end
    end

    local rate = settings:getWageRate()
    if settings.costMode == Settings.COST_MODE_HOURLY then
        setText(findDescendant(container, "wcWageBigRate"), string.format("$%d / h", rate))
    else
        setText(findDescendant(container, "wcWageBigRate"), string.format("$%d / ha", rate))
    end
    setText(findDescendant(container, "wcWageRateLabel"), settings:getWageLevelName())
    setText(findDescendant(container, "wcWagePayInterval"),
        labeled(tr("wc_label_pay_interval", "Pay Interval"), "24 h"))
    if settings.costMode == Settings.COST_MODE_HOURLY then
        setText(findDescendant(container, "wcWageHelpBody"), tr("wc_help_body", ""))
    else
        setText(findDescendant(container, "wcWageHelpBody"), tr("wc_help_body_ha", ""))
    end
    local resetBtn = findDescendant(container, "wcBtnWageReset")
    if resetBtn and resetBtn.setText then
        resetBtn:setText(tr("button_reset", "Reset"))
    end

    if page ~= nil then
        page._wcWageRefreshing = false
        if type(page._ensureWcWageArrowsVisible) == "function" then
            page:_ensureWcWageArrowsVisible()
        end
    end
end

--- Same mutate + settings:save path as WCWageSettingsFrame:bindCallbacks.
function WcRfPdaGuest.onWageOptionChanged(container)
    local page = getHostPage()
    if page ~= nil and page._wcWageRefreshing then
        return
    end
    local mgr = getMgr()
    local settings = mgr and mgr.settings
    if settings == nil then
        return
    end

    local optEnabled = findDescendant(container, "wcOptEnabled")
    local optCostMode = findDescendant(container, "wcOptCostMode")
    local optWageLevel = findDescendant(container, "wcOptWageLevel")
    local optNotifications = findDescendant(container, "wcOptNotifications")
    local optDebugMode = findDescendant(container, "wcOptDebugMode")
    local optMonthlySalary = findDescendant(container, "wcOptMonthlySalary")

    if optEnabled and optEnabled.getState then
        settings.enabled = (optEnabled:getState() == 2)
    end
    if optCostMode and optCostMode.getState and settings.setCostMode then
        settings:setCostMode(optCostMode:getState())
    end
    if optWageLevel and optWageLevel.getState and settings.setWageLevel then
        settings:setWageLevel(optWageLevel:getState())
    end
    if optNotifications and optNotifications.getState then
        settings.showNotifications = (optNotifications:getState() == 2)
    end
    if optDebugMode and optDebugMode.getState then
        settings.debugMode = (optDebugMode:getState() == 2)
    end
    if optMonthlySalary and optMonthlySalary.getState then
        settings.monthlySalaryEnabled = (optMonthlySalary:getState() == 2)
    end
    if settings.save then
        settings:save()
    end
    syncWageWidgets(container)
end

function WcRfPdaGuest.onWageReset(container)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.settings.resetToDefaults == nil then
        return
    end
    mgr.settings:resetToDefaults()
    syncWageWidgets(container)
end

local function paintWorkers(container, lightOnly)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.workerSystem == nil then
        setText(findDescendant(container, "wcStatsWorkerList"),
            tr("wc_rf_pda_empty", "Worker Costs is not ready yet."))
        return
    end
    local settings = mgr.settings
    local ws = mgr.workerSystem

    if not lightOnly then
        setText(findDescendant(container, "wcStatsMode"),
            labeled(tr("wc_label_cost_mode", "Cost Mode"), settings:getCostModeName()))
        setText(findDescendant(container, "wcStatsWage"),
            labeled(tr("wc_label_wage_level", "Wage Level"), settings:getWageLevelName()))
        setText(findDescendant(container, "wcStatsInterval"),
            labeled(tr("wc_label_pay_interval", "Pay Interval"), "24 h"))
    end

    local workers = ws:getActiveWorkers()
    local workerCount = #workers
    local rate = settings:getWageRate()
    local intervalHrs = (WorkerSystem and WorkerSystem.BILLED_HOURS_PER_DAY) or 0.5
    local isHourly = (settings.costMode == Settings.COST_MODE_HOURLY)

    setText(findDescendant(container, "wcStatsCount"),
        labeled(tr("wc_label_active_workers", "Active Workers"), tostring(workerCount)))

    if workerCount > 0 then
        local total = ws:getEstimatedIntervalCost(workerCount)
        if isHourly then
            setText(findDescendant(container, "wcStatsCostPer"),
                labeled(tr("wc_label_cost_per_worker", "Cost / Worker"),
                    formatMoney(math.floor(rate * intervalHrs))))
        else
            setText(findDescendant(container, "wcStatsCostPer"),
                labeled(tr("wc_label_cost_per_worker", "Cost / Worker"),
                    formatMoney(math.floor(total / workerCount))))
        end
        setText(findDescendant(container, "wcStatsTotal"),
            labeled(tr("wc_label_total_interval_cost", "Total Interval"), formatMoney(total)))
    else
        setText(findDescendant(container, "wcStatsCostPer"),
            labeled(tr("wc_label_cost_per_worker", "Cost / Worker"), "-"))
        setText(findDescendant(container, "wcStatsTotal"),
            labeled(tr("wc_label_total_interval_cost", "Total Interval"), "-"))
    end

    local listEl = findDescendant(container, "wcStatsWorkerList")
    if workerCount > 0 then
        local lines = {}
        local roster = mgr.workerRoster
        for _, w in ipairs(workers) do
            local cost
            if isHourly then
                cost = math.floor(rate * intervalHrs)
            else
                local hectares = ws.workerHectares and ws.workerHectares[tostring(w.vehicle)] or 0
                cost = math.floor(rate * hectares)
            end
            local tag = ""
            if roster then
                local rw = roster:getWorkerByVehicle(tostring(w.vehicle))
                if rw and WorkerRoster and WorkerRoster.levelName then
                    tag = string.format(" [%s, fatigue %d%%]",
                        WorkerRoster.levelName(rw.level), math.floor((rw.fatigue or 0) * 100))
                end
            end
            table.insert(lines, w.name .. tag .. "   -" .. formatMoney(cost))
        end
        setText(listEl, table.concat(lines, "\n"))
    else
        setText(listEl, tr("wc_no_workers", "No active workers"))
    end
end

---@param container table|nil rfHostPlaceholder from Soil RfPdaMenuPage
---@param lightOnly boolean|nil when true: page switch / live tick (seed once only; no forceEvent)
function WcRfPdaGuest.onShow(container, lightOnly)
    -- Placement polish: page hero is Soil rfPageTitle/rfPageBlurb only — do not second-paint host title/blurb.
    setText(findDescendant(container, "rfHostBody"), "")

    -- Seed only when missing (arrow path must never re-seed / forceEvent).
    if not _subnavSeeded then
        seedSubnav(container)
    end

    local page = getHostPage()
    if page ~= nil then
        page.wcSubPageIndex = clampPageIndex(page.wcSubPageIndex)
    end
    if page ~= nil and page._syncWcSubPageVisibility then
        page:_syncWcSubPageVisibility()
    end
    if page ~= nil and page.wcPageShell ~= nil and page.wcPageShell.updateAbsolutePosition then
        page.wcPageShell:updateAbsolutePosition()
    end

    setVis(findDescendant(container, "wcSideVersion"), false)
    setVis(findDescendant(container, "wcPageAbout"), false)
    paintSideInfo(container)

    local idx = getPageIndex(container)
    -- George: first show of a page = full paint; 500ms tick on same page stays light.
    local fullPaint = true
    if lightOnly and page ~= nil and page._wcLastFullPaintPage == idx then
        fullPaint = false
    elseif page ~= nil then
        page._wcLastFullPaintPage = idx
    end

    if idx == PAGE_WAGES then
        if fullPaint then
            syncWageWidgets(container)
        end
    elseif idx == PAGE_WORKERS then
        paintWorkers(container, not fullPaint)
    else
        paintDashboard(container, not fullPaint)
    end
end

function WcRfPdaGuest.onHide()
    _subnavSeeded = false
    local page = getHostPage()
    if page ~= nil then
        page._wcSubnavSeeded = false
        page._wcLastFullPaintPage = nil
    end
end

function WcRfPdaGuest.standDownLegacyEsc()
    if _legacyStoodDown then
        return true
    end
    if g_gui == nil then
        return false
    end

    local inGameMenu = g_gui.screenControllers and g_gui.screenControllers[InGameMenu] or g_inGameMenu
    if inGameMenu == nil then
        return false
    end

    local pageName = WCMenuPage and WCMenuPage.MENU_PAGE_NAME or "menuWorkerCosts"
    local screen = inGameMenu[pageName]
    if screen == nil then
        _legacyStoodDown = true
        return true
    end

    local ok = pcall(function()
        if inGameMenu.pagingElement ~= nil then
            local pe = inGameMenu.pagingElement
            if pe.elements ~= nil then
                for i = #pe.elements, 1, -1 do
                    if pe.elements[i] == screen then
                        table.remove(pe.elements, i)
                    end
                end
            end
            if pe.pages ~= nil then
                for i = #pe.pages, 1, -1 do
                    local pg = pe.pages[i]
                    if pg ~= nil and pg.element == screen then
                        table.remove(pe.pages, i)
                    end
                end
            end
            if type(pe.updateAbsolutePosition) == "function" then
                pe:updateAbsolutePosition()
            end
            if type(pe.updatePageMapping) == "function" then
                pe:updatePageMapping()
            end
        end

        if inGameMenu.pageFrames ~= nil then
            for i = #inGameMenu.pageFrames, 1, -1 do
                if inGameMenu.pageFrames[i] == screen then
                    table.remove(inGameMenu.pageFrames, i)
                end
            end
        end

        if g_inGameMenu ~= nil and g_inGameMenu.controlIDs ~= nil then
            g_inGameMenu.controlIDs[pageName] = nil
        end

        inGameMenu[pageName] = nil

        if type(inGameMenu.rebuildTabList) == "function" then
            inGameMenu:rebuildTabList()
        end
        if type(inGameMenu.updatePages) == "function" then
            inGameMenu:updatePages()
        end
    end)

    if ok then
        _legacyStoodDown = true
        if g_wcModGui ~= nil then
            g_wcModGui[pageName] = nil
        end
        print("[WorkerCosts] WcRfPdaGuest: stood down legacy Esc menuWorkerCosts (RF host present)")
        return true
    end
    print("[WorkerCosts] WcRfPdaGuest: legacy Esc stand-down failed (will retry)")
    return false
end

function WcRfPdaGuest.tryRegister()
    -- Equal Option B: WC may create menuRealisticFarming when Soil absent.
    -- Always ensureDoor when bootstrap class is sourced; never trust bare g_currentModDirectory at callback time.
    if RfEscBootstrap ~= nil then
        if MOD_DIR == nil then
            print("[WorkerCosts] WcRfPdaGuest: WARNING MOD_DIR nil — cannot ensureDoor (source capture failed)")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            if not doorOk then
                print("[WorkerCosts] WcRfPdaGuest: WARNING ensureDoor failed (will retry)")
            end
        end
    end

    local host = getHost()
    local registerFn = nil
    if host ~= nil then
        if type(host.registerModule) == "function" then
            registerFn = host.registerModule
        elseif type(host.registerPanel) == "function" then
            registerFn = host.registerPanel
        end
    end
    if host == nil or registerFn == nil then
        return false
    end

    if not _registered then
        local ok = registerFn(host, {
            id = PANEL_ID,
            title = tr("wc_rf_pda_module_title", "Worker Costs"),
            blurb = tr("wc_rf_pda_blurb",
                "Wage mode, active workers, next settlement estimate. Open Worker Manager for hire and settings."),
            order = PANEL_ORDER,
            isAvailable = function()
                return getMgr() ~= nil
            end,
            onShow = WcRfPdaGuest.onShow,
            onHide = WcRfPdaGuest.onHide,
            onWageOptionChanged = WcRfPdaGuest.onWageOptionChanged,
            onWageReset = WcRfPdaGuest.onWageReset,
        })
        if ok then
            _registered = true
            print("[WorkerCosts] WcRfPdaGuest: registered module workerCosts on rfEscModules")
        else
            return false
        end
    end

    local doorPresent = g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
    if doorPresent then
        WcRfPdaGuest.standDownLegacyEsc()
    end
    -- Ready only when module registered AND Esc door actually exists.
    return _registered and doorPresent
end

function WcRfPdaGuest.isHostPresent()
    return getHost() ~= nil
end

function WcRfPdaGuest.isRegistered()
    return _registered
end

function WcRfPdaGuest.reset()
    _registered = false
    _legacyStoodDown = false
    _subnavSeeded = false
end

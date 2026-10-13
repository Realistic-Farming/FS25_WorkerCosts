-- =========================================================
-- WcRfPdaGuest
-- Esc RF PDA guest: Worker Costs Dashboard | Wages | Workers (+ side About).
-- Stage-8 densify 2026-08-05: getRosterSnapshot crew/recruits/hires/month/ESC-pays.
-- Soft-detects g_currentMission.rfEscModules (NO HOST); registerModule.
-- Soft-detect manager: g_currentMission.workerCostsManager.
-- Hang fences: text / MultiTextOption setState only; no SmoothList reloadData.
-- Farm balance OMIT. Hire/fire/salary dialogs stay deep WCGui.
-- =========================================================

WcRfPdaGuest = WcRfPdaGuest or {}

-- Capture at source() time - (WorkerCostsModDirectory or g_currentModDirectory) is often nil at deferred/map-load callbacks.
local MOD_DIR = (WorkerCostsModDirectory or g_currentModDirectory)
local WC_RF_MOD_NAME = (WorkerCostsModName or g_currentModName)
local PANEL_ID = "workerCosts"
local PANEL_ORDER = 30

local PAGE_DASHBOARD = 1
local PAGE_WAGES = 2
local PAGE_WORKERS = 3
-- PAGE_ABOUT retired 2026-08-02: consolidated into wcSideInfoShell.

local _registered = false
local _legacyStoodDown = false
local _subnavSeeded = false
-- BUILD 22:42 (George CLOSED DESIGN 21:26): the roster snapshot behind the last paint, so a
-- Hire / Fire click on row n resolves to the entry that was on that row when it was clicked.
local _lastSnap = nil
local CREW_ROWS = 8      -- roster rows 1-8: crew (wcBtnFire1..8)
local RECRUIT_ROWS = 4   -- roster rows 11-14: recruits (wcBtnHire1..4); row 9 blank, row 10 title

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

-- BUILD 00:06: the engine text colour setter, captured BEFORE the element helper below shadows
-- the name (the 20:36 Market crash). The chip draw wrap resets the render colour with this one.
local engineSetTextColor = setTextColor

local function setTextColor(el, r, g, b, a)
    if el ~= nil and type(el.setTextColor) == "function" then
        el:setTextColor(r, g, b, a)
    end
end

local function formatMoney(amount)
    if g_i18n and g_i18n.formatMoney then
        return g_i18n:formatMoney(amount, 0, true, false)
    end
    return tostring(math.floor(amount + 0.5))
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
--- BUILD 18:26 (George CLOSED DESIGN 17:59): one page, one how-to (fallback-only key, like the
--- three per-page keys it replaces; none of them live in the translation files).
local function paintSideInfo(container)
    local howTo = tr("rf_pda_side_info_wc",
        "Worker Costs\n\nLeft: AI pay on/off, Hourly or Per hectare, Wage Level, notices, salary; the rate and Reset under them. Escape on the salary dialog = Pay (not defer).\nRight: status, active AI, next settle, hires left, cost per worker, interval total, month and estimate, crew; the crew board (status, pinned, trusted, level, fatigue) below.\nHire and Fire with the buttons beside the crew and recruit rows. Assign in Farm Tablet.")
    local about = tr("rf_pda_side_info_wc_about",
        "About: Midnight settle (fair 1x-120x). Settings per save; MP follows host.\nClients wait for host sync. Wage Level scales Hourly / Per hectare.\nPro-Staff links show when loaded.")
    local body = howTo .. "\n\n" .. about
    local shell = findDescendant(container, "wcSideInfoShell")
    local bodyEl = findDescendant(container, "wcSideInfoBody")
    setVis(shell, true)
    setText(bodyEl, body)
end

local LIST_MAX_LINES = 14  -- BUILD 12:05: fourteen declared row Texts wcRosterRow1..14 on the chip Ys

local function getRosterSnap(mgr)
    if mgr == nil or type(mgr.getRosterSnapshot) ~= "function" then
        return nil
    end
    local ok, snap = pcall(function() return mgr:getRosterSnapshot() end)
    if ok and type(snap) == "table" then
        return snap
    end
    return nil
end

local function isAuthoritative(snap)
    return snap ~= nil and snap.authoritative == true
end

local function awaitingSyncText()
    return tr("wc_rf_pda_awaiting_sync", "Awaiting host sync")
end

--- Human crew line: Name · Working/Idle · pinned · trusted · Level · fatigue N%
local function formatCrewLine(w)
    if w == nil then
        return ""
    end
    local parts = {}
    table.insert(parts, tostring(w.name or tr("wc_rf_pda_worker_fallback", "Worker")))
    local working = w.working == true
    if type(w.status) == "string" then
        local s = w.status:lower()
        if s:find("working", 1, true) then
            working = true
        elseif s:find("idle", 1, true) then
            working = false
        end
    end
    table.insert(parts, working
        and tr("wc_rf_pda_status_working", "Working")
        or tr("wc_rf_pda_status_idle", "Idle"))
    if w.pinned == true then
        table.insert(parts, tr("wc_rf_pda_token_pinned", "pinned"))
    end
    if w.trusted == true then
        table.insert(parts, tr("wc_rf_pda_token_trusted", "trusted"))
    end
    if w.levelName ~= nil and tostring(w.levelName) ~= "" then
        table.insert(parts, tostring(w.levelName))
    end
    local fatigue = tonumber(w.fatigue) or 0
    if fatigue > 0 then
        table.insert(parts, string.format(tr("wc_rf_pda_fatigue_pct", "fatigue %d%%"), math.floor(fatigue * 100)))
    end
    return table.concat(parts, " · ")
end

local function formatRecruitLine(r)
    if r == nil then
        return ""
    end
    local slot = tonumber(r.slot) or 0
    local name = tostring(r.name or tr("wc_rf_pda_worker_fallback", "Worker"))
    local level = tostring(r.levelName or "")
    local cost = formatMoney(tonumber(r.hireCost) or 0)
    return string.format(tr("wc_rf_pda_recruit_line", "#%d %s · %s · %s"), slot, name, level, cost)
end

-- ============================================================
-- BUILD 00:06 (LAW Wizard Esc overlay-chip buttons 2026-09-05, George CLOSED DESIGN 23:12): every
-- created button on this page paints as a vanilla key chip, the CsRfPdaGuest setPivotBtn /
-- renderPivotChip / wirePivotChipPaint chain vendored. Idle = dark plate, lime text; latched =
-- lime plate, dark text; gated = grey, no lime. The Button keeps its own hit box and onClick
-- (RF_CsPivotBtn: buttonActivate chrome, hideKeyboardGlyph, no global-action trigger, so SPACE
-- never confirms); its TextElement text stays "" so the chip is the only paint.
-- ============================================================
local CHIP_TEXT = { 0.22323, 0.40724, 0.00368 }
local CHIP_BG = { 0.00913, 0.01033, 0.00651 }
local CHIP_GATED_TEXT = { 0.62, 0.64, 0.66 }
local CHIP_GATED_BG = { 0.06, 0.06, 0.065 }

--- Store the chip state on the Button and blank its text. enabled=false paints the grey chip
--- and disables the Button; latched inverts the live chip.
local function setChipBtn(el, label, enabled, latched)
    if el == nil then return end
    if type(el.setText) == "function" then el:setText("") end
    el.rfChipLabel = label
    el.rfChipEnabled = enabled and true or false
    el.rfChipLatched = latched and true or false
    if type(el.setDisabled) == "function" then el:setDisabled(not enabled) end
end

local function renderChip(el, overlay)
    local label = el.rfChipLabel
    if label == nil or label == "" then return end
    if el.absPosition == nil or el.absSize == nil or el.visible == false then return end
    local height = el.absSize[2] * 0.72
    if height <= 0 then return end
    local t, b, ta, ba
    if el.rfChipEnabled and el.rfChipLatched then
        t, b, ta, ba = CHIP_BG, CHIP_TEXT, 1.0, 1.0
    elseif el.rfChipEnabled then
        t, b, ta, ba = CHIP_TEXT, CHIP_BG, 1.0, 1.0
    else
        t, b, ta, ba = CHIP_GATED_TEXT, CHIP_GATED_BG, 0.45, 0.55
    end
    overlay:setColor(t[1], t[2], t[3], ta, b[1], b[2], b[3], ba)
    local width = overlay:getButtonWidth(label, height)
    local x = el.absPosition[1] + (el.absSize[1] - width) * 0.5
    local y = el.absPosition[2] + (el.absSize[2] - height) * 0.5
    overlay:renderButton(label, x, y, height, true)
end

--- Wrap one already-visible parent's draw once (guard flag on the element) so the listed chips
--- repaint every frame the parent draws. lookup(root, id) resolves each Button. The colour reset
--- at the end is the ENGINE global captured above, never an element helper.
local function wireChipPaint(parent, ids, flag, lookup)
    if parent == nil or parent[flag] then return end
    parent[flag] = true
    local prevDraw = parent.draw
    function parent:draw(...)
        if prevDraw ~= nil then prevDraw(self, ...) end
        local idm = g_inputDisplayManager
        if idm == nil or type(idm.getKeyboardKeyOverlay) ~= "function" then return end
        local overlay = idm:getKeyboardKeyOverlay()
        if overlay == nil or type(overlay.renderButton) ~= "function" then return end
        for _, id in ipairs(ids) do
            local el = lookup(self, id)
            if el ~= nil then
                pcall(renderChip, el, overlay)
            end
        end
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        if type(engineSetTextColor) == "function" then
            engineSetTextColor(1, 1, 1, 1)
        end
    end
end

local WC_CHIP_IDS = { "wcBtnWageReset",
    "wcBtnFire1", "wcBtnFire2", "wcBtnFire3", "wcBtnFire4", "wcBtnFire5", "wcBtnFire6", "wcBtnFire7", "wcBtnFire8",
    "wcBtnHire1", "wcBtnHire2", "wcBtnHire3", "wcBtnHire4" }

--- The wrap goes on wcPageDashboard, the page every card and button sits in (visible whenever
--- Worker Costs is the active module); never a new frame over the wage MTOs.
local function wireWcChipPaint(container)
    local page = findDescendant(container, "wcPageDashboard")
    wireChipPaint(page, WC_CHIP_IDS, "_rfWcChipWired", function(root, id)
        return findDescendant(root, id) or findDescendant(container, id)
    end)
end

--- BUILD 22:42 (George CLOSED DESIGN 21:26): fixed rows, so the declared Hire / Fire buttons
--- line up with the text. Rows 1-8 = crew (workers[1..8], blank when short, "Showing 8 of N"
--- when long), row 9 blank, row 10 the recruits title, rows 11-14 = recruits[1..4] (blank when
--- short). crewBudget is CREW_ROWS always; LIST_MAX_LINES 14 = 8 + 1 + 1 + 4.
local function buildWorkersListText(snap)
    local lines = {}
    local workers = (snap and snap.workers) or {}
    local recruits = (snap and snap.recruits) or {}
    local crewTotal = #workers

    local showingClause = nil
    if crewTotal == 0 then
        table.insert(lines, tr("wc_rf_pda_no_staff", "No staff yet"))
    else
        local paintN = math.min(crewTotal, CREW_ROWS)
        if paintN < crewTotal then
            showingClause = string.format(tr("wc_rf_pda_showing_n_of_m", "Showing %d of %d"), paintN, crewTotal)
        end
        for i = 1, paintN do
            table.insert(lines, formatCrewLine(workers[i]))
        end
    end
    while #lines < CREW_ROWS do
        table.insert(lines, "")
    end

    table.insert(lines, "")
    if #recruits > 0 then
        table.insert(lines, tr("wc_rf_pda_recruits_title", "Today's recruits"))
        for s = 1, RECRUIT_ROWS do
            table.insert(lines, recruits[s] ~= nil and formatRecruitLine(recruits[s]) or "")
        end
    else
        table.insert(lines, tr("wc_rf_pda_no_recruits", "No recruits today"))
    end

    while #lines > LIST_MAX_LINES do
        table.remove(lines)
    end

    return lines, showingClause
end

--- BUILD 12:05 (George CLOSED DESIGN 09:45): one declared Text per roster row (wcRosterRow1..14,
--- 460x22, one line, clip no wrap) at the same page Ys as the Hire / Fire chips, so a button
--- always sits on the row it acts on. Rows past the end of lines are blanked.
local function paintRosterRows(container, lines)
    lines = lines or {}
    for i = 1, LIST_MAX_LINES do
        setText(findDescendant(container, "wcRosterRow" .. i), lines[i] or "")
    end
end

--- The twelve declared buttons: Fire i shows when crew row i carries a worker with a uuid, Hire s
--- when recruit row s carries a recruit. Everything hidden when the roster is not authoritative
--- (snap nil). Text is set on show only; RF_FwPagerBtn has no inputAction, so no key chip.
local function paintRosterButtons(container, snap)
    local workers = (snap and snap.workers) or {}
    local recruits = (snap and snap.recruits) or {}
    for i = 1, CREW_ROWS do
        local el = findDescendant(container, "wcBtnFire" .. i)
        local w = workers[i]
        local on = snap ~= nil and w ~= nil and w.uuid ~= nil
        setVis(el, on)
        if on then
            setChipBtn(el, tr("wc_rf_pda_btn_fire", "Fire"), true, false)
        end
    end
    for s = 1, RECRUIT_ROWS do
        local el = findDescendant(container, "wcBtnHire" .. s)
        local on = snap ~= nil and recruits[s] ~= nil
        setVis(el, on)
        if on then
            setChipBtn(el, tr("wc_rf_pda_btn_hire", "Hire"), true, false)
        end
    end
end

-- BUILD 18:26: seedSubnav (the three-page picker seed) is gone; wcSubnavSelector stays hidden.

local function paintDashboard(container, lightOnly)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.workerSystem == nil then
        setText(findDescendant(container, "wcDashStatus"),
            tr("wc_rf_pda_empty", "Worker Costs is not ready yet."))
        return
    end
    local settings = mgr.settings
    local ws = mgr.workerSystem
    local snap = getRosterSnap(mgr)
    local auth = isAuthoritative(snap)

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
        -- BUILD 18:26: mode, wage level and rate are carried by the wage MTOs and wcWageBigRate on
        -- the same page now (wcDashMode / wcDashWage / wcDashRate are gone from the door XML).
    end

    local workers = ws:getActiveWorkers()
    local workerCount = #workers

    if not auth then
        setText(findDescendant(container, "wcDashWorkers"),
            labeled(tr("wc_label_active_workers", "Active Workers"), awaitingSyncText()))
        setText(findDescendant(container, "wcDashEstimate"), awaitingSyncText())
    else
        setText(findDescendant(container, "wcDashWorkers"),
            labeled(tr("wc_label_active_workers", "Active Workers"), tostring(workerCount)))

        local monthAccrued = 0
        local est = 0
        if snap.finance ~= nil then
            monthAccrued = tonumber(snap.finance.monthAccrued) or 0
            est = tonumber(snap.finance.estIntervalCost) or 0
        end
        if workerCount > 0 and (est == 0 or est == nil) and ws.getEstimatedIntervalCost then
            est = ws:getEstimatedIntervalCost(workerCount) or 0
        end
        setText(findDescendant(container, "wcDashEstimate"),
            string.format(tr("wc_rf_pda_month_est", "Month: %s · Est: %s"),
                formatMoney(monthAccrued), formatMoney(est)))
        -- BUILD 18:26: the on-the-clock names list (wcDashWorkerNames) is gone; the full roster
        -- sits on the same page in the wcRosterRow1..14 texts (paintWorkers).
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
            texts[i] = string.format("%s (%s/%s)", name, formatMoney(rates[i]), unit)
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
    -- [MAINTENANCE row 290] The admin options are the server's: locked for a client whose user is not master,
    -- after setTexts/setState (a MultiTextOption may reset its disabled state in updateContentElement).
    local locked = not Settings.canEditAdminSettings()
    for _, opt in ipairs({ optEnabled, optCostMode, optWageLevel, optMonthlySalary }) do
        if opt ~= nil and type(opt.setDisabled) == "function" then opt:setDisabled(locked) end
    end

    local rate = settings:getWageRate()
    if settings.costMode == Settings.COST_MODE_HOURLY then
        setText(findDescendant(container, "wcWageBigRate"), formatMoney(rate) .. " / h")
    else
        setText(findDescendant(container, "wcWageBigRate"), formatMoney(rate) .. " / ha")
    end
    setText(findDescendant(container, "wcWageRateLabel"), settings:getWageLevelName())
    setText(findDescendant(container, "wcWagePayInterval"),
        labeled(tr("wc_label_pay_interval", "Pay Interval"), "24 h"))
    -- Esc MaxLines 5: short densify help + ESC-pays (copy only; no dialog mutate).
    local escPays = tr("wc_rf_pda_esc_pays",
        "Closing the salary dialog with Escape pays the salary (same as Pay). It does not defer.")
    if settings.costMode == Settings.COST_MODE_HOURLY then
        setText(findDescendant(container, "wcWageHelpBody"),
            tr("wc_rf_pda_wage_help",
                "Hourly: fixed rate per active worker hour. Wage Level sets the rate. Settles at midnight.")
                .. "\n" .. escPays)
    else
        setText(findDescendant(container, "wcWageHelpBody"),
            tr("wc_rf_pda_wage_help_ha",
                "Per hectare: billed by area worked since last settle. Wage Level sets the rate. Settles at midnight.")
                .. "\n" .. escPays)
    end
    -- BUILD 00:06: Reset is an overlay chip (RF_CsPivotBtn, no SPACE); the label rides the chip.
    setChipBtn(findDescendant(container, "wcBtnWageReset"), tr("button_reset", "Reset"), true, false)

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

    -- [MAINTENANCE row 290] Where the admin options are locked, only the player's own keys are written: a stale
    -- admin widget must not write over the server's value.
    local canAdmin = Settings.canEditAdminSettings()
    if canAdmin and optEnabled and optEnabled.getState then
        settings.enabled = (optEnabled:getState() == 2)
    end
    if canAdmin and optCostMode and optCostMode.getState and settings.setCostMode then
        settings:setCostMode(optCostMode:getState())
    end
    if canAdmin and optWageLevel and optWageLevel.getState and settings.setWageLevel then
        settings:setWageLevel(optWageLevel:getState())
    end
    if optNotifications and optNotifications.getState then
        settings.showNotifications = (optNotifications:getState() == 2)
    end
    if optDebugMode and optDebugMode.getState then
        settings.debugMode = (optDebugMode:getState() == 2)
    end
    if canAdmin and optMonthlySalary and optMonthlySalary.getState then
        settings.monthlySalaryEnabled = (optMonthlySalary:getState() == 2)
    end
    if settings.save then
        settings:save()
    end
    syncWageWidgets(container)
end

function WcRfPdaGuest.onWageReset(container)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.settings.resetForUser == nil then
        return
    end
    mgr.settings:resetForUser()   -- [MAINTENANCE row 290] the player's own keys only, where locked
    syncWageWidgets(container)
end

local function paintWorkers(container, lightOnly)
    local mgr = getMgr()
    if mgr == nil or mgr.settings == nil or mgr.workerSystem == nil then
        paintRosterRows(container, { tr("wc_rf_pda_empty", "Worker Costs is not ready yet.") })
        _lastSnap = nil
        paintRosterButtons(container, nil)
        return
    end
    local settings = mgr.settings
    local ws = mgr.workerSystem
    local snap = getRosterSnap(mgr)
    local auth = isAuthoritative(snap)

    -- BUILD 18:26: wcStatsMode / wcStatsWage are gone; the wage MTOs on the same page carry them.
    local rate = settings:getWageRate()
    local intervalHrs = (WorkerSystem and WorkerSystem.BILLED_HOURS_PER_DAY) or 0.5
    local isHourly = (settings.costMode == Settings.COST_MODE_HOURLY)
    local activeWorkers = ws:getActiveWorkers()
    local activeCount = #activeWorkers

    if not auth then
        setText(findDescendant(container, "wcStatsInterval"),
            labeled(tr("wc_rf_pda_hires_left_lbl", "Hires left"), awaitingSyncText()))
        setText(findDescendant(container, "wcStatsCount"),
            labeled(tr("wc_rf_pda_crew_lbl", "Crew"), awaitingSyncText()))
        setText(findDescendant(container, "wcStatsCostPer"),
            labeled(tr("wc_label_cost_per_worker", "Cost / Worker"), "-"))
        setText(findDescendant(container, "wcStatsTotal"),
            labeled(tr("wc_label_total_interval_cost", "Total Interval"), "-"))
        paintRosterRows(container, { awaitingSyncText() })
        _lastSnap = nil
        paintRosterButtons(container, nil)
        return
    end

    local hiring = snap.hiring or {}
    local remaining = tonumber(hiring.remaining) or 0
    local limit = tonumber(hiring.limit) or 0
    setText(findDescendant(container, "wcStatsInterval"),
        string.format(tr("wc_rf_pda_hires_left", "Hires left: %d of %d"), remaining, limit))

    local crewN = tonumber(snap.count) or #(snap.workers or {})
    local workingN = tonumber(snap.working) or 0
    local countText = string.format(tr("wc_rf_pda_crew_count", "Crew: %d"), crewN)
    if workingN > 0 then
        countText = countText .. string.format(tr("wc_rf_pda_crew_working", " · %d working"), workingN)
    end
    local listLines, showingClause = buildWorkersListText(snap)
    if showingClause ~= nil then
        countText = countText .. " · " .. showingClause
    end
    setText(findDescendant(container, "wcStatsCount"), countText)

    -- Stage-7 Workers finance: billed actives interval cost (not month; month is Dashboard).
    if activeCount > 0 then
        local total = ws:getEstimatedIntervalCost(activeCount)
        if isHourly then
            setText(findDescendant(container, "wcStatsCostPer"),
                labeled(tr("wc_label_cost_per_worker", "Cost / Worker"),
                    formatMoney(math.floor(rate * intervalHrs))))
        else
            setText(findDescendant(container, "wcStatsCostPer"),
                labeled(tr("wc_label_cost_per_worker", "Cost / Worker"),
                    formatMoney(math.floor(total / activeCount))))
        end
        setText(findDescendant(container, "wcStatsTotal"),
            labeled(tr("wc_label_total_interval_cost", "Total Interval"), formatMoney(total)))
    else
        setText(findDescendant(container, "wcStatsCostPer"),
            labeled(tr("wc_label_cost_per_worker", "Cost / Worker"), "-"))
        setText(findDescendant(container, "wcStatsTotal"),
            labeled(tr("wc_label_total_interval_cost", "Total Interval"), "-"))
    end

    paintRosterRows(container, listLines)
    _lastSnap = snap
    paintRosterButtons(container, snap)
end

--- BUILD 22:42 (George CLOSED DESIGN 21:26): Hire / Fire from the Esc page. n is the roster ROW of
--- the last paint: recruits[n] (rows 11-14, wcBtnHire1..4) or workers[n] (rows 1-8, wcBtnFire1..8).
--- WorkerManager:hireWorker(slot, farmId) / fireWorker(uuid, farmId) are the thin WCNetwork_SendCommand
--- wrappers (SP and MP, src/WorkerManager.lua); farmId nil = the local farm inside them. The server
--- enforces the daily hire limit and the roster snapshot comes back on its own, so the repaint here
--- is a courtesy and the 500ms tick shows the result. Assign / unassign stay off Esc (no vehicle).
---@param container table|nil rfHostPlaceholder from the host
---@param n number recruit row 1..4
function WcRfPdaGuest.onHire(container, n)
    local mgr = getMgr()
    local snap = _lastSnap
    local r = snap ~= nil and snap.recruits ~= nil and snap.recruits[tonumber(n) or 0] or nil
    if mgr == nil or type(mgr.hireWorker) ~= "function" or r == nil then
        return
    end
    pcall(mgr.hireWorker, mgr, tonumber(r.slot) or 1, nil)
    paintDashboard(container, true)
    paintWorkers(container, true)
end

---@param container table|nil rfHostPlaceholder from the host
---@param n number crew row 1..8
function WcRfPdaGuest.onFire(container, n)
    local mgr = getMgr()
    local snap = _lastSnap
    local w = snap ~= nil and snap.workers ~= nil and snap.workers[tonumber(n) or 0] or nil
    if mgr == nil or type(mgr.fireWorker) ~= "function" or w == nil or w.uuid == nil then
        return
    end
    pcall(mgr.fireWorker, mgr, w.uuid, nil)
    paintDashboard(container, true)
    paintWorkers(container, true)
end

---@param container table|nil rfHostPlaceholder from Soil RfPdaMenuPage
---@param lightOnly boolean|nil when true: page switch / live tick (seed once only; no forceEvent)
function WcRfPdaGuest.onShow(container, lightOnly)
    -- Placement polish: page hero is Soil rfPageTitle/rfPageBlurb only - do not second-paint host title/blurb.
    setText(findDescendant(container, "rfHostBody"), "")

    -- BUILD 18:26 (George CLOSED DESIGN 17:59): one page. No subnav seed (the picker is gone,
    -- wcSubnavSelector stays hidden); the page index is pinned to the merged Dashboard.
    local page = getHostPage()
    if page ~= nil then
        page.wcSubPageIndex = PAGE_DASHBOARD
        page._wcSubnavSeeded = true
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
    -- BUILD 00:06: idempotent draw wrap for the Reset / Hire / Fire chips.
    wireWcChipPaint(container)

    local idx = getPageIndex(container)
    -- George: first show of a page = full paint; 500ms tick on same page stays light.
    local fullPaint = true
    if lightOnly and page ~= nil and page._wcLastFullPaintPage == idx then
        fullPaint = false
    elseif page ~= nil then
        page._wcLastFullPaintPage = idx
    end

    -- Merged page: the wage widgets sync on the full paint only (same ids, forceEvent=false,
    -- calls _ensureWcWageArrowsVisible); the stats and the roster repaint on every tick with
    -- lightOnly = live numbers only.
    if fullPaint then
        syncWageWidgets(container)
    end
    paintDashboard(container, not fullPaint)
    paintWorkers(container, not fullPaint)
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

--- BUILD 19:15: the Esc Help footer asks whichever module is showing to open its own guide, so
--- every companion ships and owns its own help instead of borrowing Soil's.
---@param container table|nil
function WcRfPdaGuest.onOpenHelp(container)
    if WcGuideDialog ~= nil and type(WcGuideDialog.show) == "function" then
        WcGuideDialog.show()
    end
end

function WcRfPdaGuest.tryRegister()
    -- Suite soft-detect: publish the Worker Manager screen on the mission so the
    -- Esc door host (whichever mod built RfPdaMenuPage) can open it from its own
    -- env. g_currentMission is the only table every mod can read; bare g_wcGui is
    -- WorkerCosts-scoped and nil to the host.
    if g_currentMission ~= nil and g_wcGui ~= nil then
        g_currentMission.rfWcGui = g_wcGui
    end
    -- BUILD 22:42: the guest handle on the mission is the belt for the host Hire / Fire
    -- forwarders (registry field first, this second), the same channel NPC Favor and Market use.
    if g_currentMission ~= nil then
        g_currentMission.WcRfPdaGuest = WcRfPdaGuest
    end

    -- Equal Option B: WC may create menuRealisticFarming when Soil absent.
    -- Always ensureDoor when bootstrap class is sourced; never trust bare (WorkerCostsModDirectory or g_currentModDirectory) at callback time.
    if RfEscBootstrap ~= nil then
        if MOD_DIR == nil then
            print("[WorkerCosts] WcRfPdaGuest: WARNING MOD_DIR nil - cannot ensureDoor (source capture failed)")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            -- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): load this mod's Field Guide at the
            -- same moment the door itself loads. A GUI loaded from a mod directory later, once the
            -- mod's own file system context has closed, fails to open.
            if WcGuideDialog ~= nil and type(WcGuideDialog.register) == "function" then
                pcall(WcGuideDialog.register, MOD_DIR)
            end
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
                "Wage mode, active workers, next settlement estimate. Hire and fire here; assign on Farm Tablet."),
            order = PANEL_ORDER,
            isAvailable = function()
                return getMgr() ~= nil
            end,
            onShow = WcRfPdaGuest.onShow,
            onHide = WcRfPdaGuest.onHide,
            onWageOptionChanged = WcRfPdaGuest.onWageOptionChanged,
            onWageReset = WcRfPdaGuest.onWageReset,
            -- BUILD 22:42: carried by RfEscModules.registerModule from this build on.
            onHire = WcRfPdaGuest.onHire,
            onFire = WcRfPdaGuest.onFire,
            onOpenHelp = WcRfPdaGuest.onOpenHelp,
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

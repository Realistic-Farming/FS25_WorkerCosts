-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WCRosterPanel — custom-drawn, clickable roster manager (Pro-Staff Phase 5)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- A fully custom-drawn overlay panel (no XML), modelled on SoilFertilizer's
-- SoilSettingsPanel: createImageOverlay + renderOverlay for rectangles, renderText
-- for labels, and a per-frame _clickRects table hit-tested in onMouseEvent. Gives
-- the player clickable Hire / Fire / Assign instead of console commands.
--
-- Open/close: console command `WorkerCostsRoster` (toggle). Draw is driven from an
-- appended FSBaseMission.draw; mouse from addModEventListener (see main.lua).
--
-- LAYOUT: master-detail "dossier". Left = a narrow selectable roster column; right
-- = the selected worker's file (skill + fatigue gauges, lifetime stats, job-history
-- resume, base->effective wage, actions). The whole panel is driven from one cached
-- WorkerManager:getRosterSnapshot() so the wage math is single-sourced, and the
-- HireHallCore reads (lifecycle state, history) are guarded + host-only.
--
-- PRO-STAFF CHECKLIST (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 5 — clickable hire / fire / assign / unassign UI (server/SP)
--   [x] Phase 5+ — master-detail worker dossier (skill/fatigue/history/wage)
--   [ ] Phase 5 — MP-aware actions (route through sync events once the MP layer lands)
-- =========================================================

---@class WCRosterPanel
WCRosterPanel = {}
local WCRosterPanel_mt = Class(WCRosterPanel)

-- ── Palette ── dark grey panel, green text (matches the mod's style) ──
local C = {
    shadow = { 0, 0, 0 },
    bg     = { 0.15, 0.16, 0.17 },     -- dark grey
    title  = { 0.13, 0.30, 0.19 },     -- dark green title bar
    border = { 0.34, 0.70, 0.42 },     -- green border
    row    = { 0.19, 0.20, 0.22 },     -- grey rows (zebra)
    rowAlt = { 0.23, 0.24, 0.26 },
    rowTrust = { 0.26, 0.24, 0.14 },   -- warm-tinted row bg for Trusted workers (#67)
    text   = { 0.64, 0.92, 0.70, 1 },  -- green text
    dim    = { 0.50, 0.70, 0.55, 1 },  -- muted green
    accent = { 0.55, 0.95, 0.62, 1 },
    gold   = { 0.96, 0.80, 0.27, 1 },  -- Trusted star (#67)
    btnHire   = { 0.20, 0.50, 0.28 },  -- green
    btnAssign = { 0.24, 0.42, 0.58 },  -- blue (distinct action)
    btnFire   = { 0.55, 0.24, 0.24 },  -- red (distinct, important)
    btnStar   = { 0.34, 0.32, 0.18 },  -- dim gold seat for the un-trusted star button
    btnTxt    = { 1, 1, 1, 1 },        -- white on coloured buttons stays readable
    -- Dossier additions
    sel       = { 0.20, 0.40, 0.26 },  -- selected roster row (brighter green seat)
    detailBg  = { 0.12, 0.13, 0.14 },  -- right-pane backdrop, a touch darker than bg
    barTrack  = { 0.10, 0.11, 0.12 },  -- empty gauge track
    xpFill    = { 0.40, 0.78, 0.50 },  -- XP progress fill (green)
    fatLow    = { 0.42, 0.80, 0.46 },  -- fatigue gauge: rested
    fatMid    = { 0.92, 0.74, 0.30 },  -- fatigue gauge: tiring
    fatHigh   = { 0.86, 0.34, 0.32 },  -- fatigue gauge: exhausted
    dotWork   = { 0.46, 0.86, 0.54, 1 },  -- working (green)
    dotIdle   = { 0.55, 0.62, 0.58, 1 },  -- idle (grey-green)
    dotLeave  = { 0.92, 0.74, 0.30, 1 },  -- on leave (amber)
    dotHurt   = { 0.86, 0.40, 0.36, 1 },  -- injured (red)
    ok        = { 0.55, 0.90, 0.60, 1 },  -- job-history success glyph
    bad       = { 0.88, 0.46, 0.42, 1 },  -- job-history failure glyph
}

-- ── Geometry (normalized, Y=0 at bottom) ──────────────────
-- Master-detail layout: a narrow selectable roster column on the left, a rich
-- "dossier" for the selected worker on the right.
local PW   = 0.58
local PH   = 0.60
local PX   = (1 - PW) / 2
local PY   = (1 - PH) / 2
local TB_H = 0.050
local IB_H = 0.040
local PAD  = 0.015

-- Left (roster) column.
local LEFT_W        = 0.185   -- content width of the roster list column
local LIST_ROW_H    = 0.045
local ROWS_PER_PAGE = 8
local HIRE_H        = 0.040   -- "+ Hire" button height in the left header

-- Right (dossier) column derives its width from what's left.
local COL_GAP = 0.014

-- Text sizes
local TS_TITLE = 0.018
local TS_NAME  = 0.020   -- dossier worker name
local TS_ROW   = 0.0130
local TS_BTN   = 0.0125
local TS_INFO  = 0.0118
local TS_SMALL = 0.0105

-- Button widths (detail-pane actions)
local BTN_FIRE_W   = 0.075
local BTN_ASSIGN_W = 0.090
local BTN_TRUST_W  = 0.095
local BTN_STAR_W   = 0.022   -- #67 Trusted toggle in the list rows
local BTN_GAP      = 0.010

-- Bar (XP / fatigue gauge) height.
local BAR_H = 0.016

-- Names used when hiring from the panel (no text-input field in an overlay).
local NAME_POOL = {
    "Alex", "Sam", "Jordan", "Casey", "Riley", "Morgan", "Taylor",
    "Jamie", "Drew", "Quinn", "Avery", "Parker", "Reese", "Skyler",
}

function WCRosterPanel.new(roster, workerSystem)
    local self = setmetatable({}, WCRosterPanel_mt)
    self.roster       = roster
    self.workerSystem = workerSystem
    self.fillOverlay  = nil
    self.isVisible    = false
    self.initialized  = false
    self.page         = 0      -- 0-based page index
    self.mouseX       = 0
    self.mouseY       = 0
    self.infoMsg      = nil     -- transient status line shown in the info bar
    self._clickRects  = {}
    self.selectedUuid = nil    -- worker shown in the dossier (right pane)
    self._snapshot    = nil    -- cached getRosterSnapshot result (throttled rebuild)
    self._snapshotAt  = -100000 -- g_currentMission.time of the last snapshot build
    return self
end

function WCRosterPanel:initialize()
    if self.initialized then return end
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    self.initialized = true
end

function WCRosterPanel:delete()
    if self.fillOverlay then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Visibility ────────────────────────────────────────────
function WCRosterPanel:open()
    if not self.initialized then self:initialize() end
    -- #84 Don't open underneath the Farm Tablet — they are mutually-exclusive
    -- overlays. The player closes the tablet first (focus API; absent = nil = allow).
    local ft = g_currentMission and g_currentMission.farmTablet
    if ft and ft.isVisible then
        return
    end
    self.isVisible = true
    self.page      = 0
    self.infoMsg   = nil
    self._snapshotAt = -100000   -- force a fresh snapshot on the first frame
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
end

function WCRosterPanel:close()
    self.isVisible = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
end

function WCRosterPanel:toggle()
    if self.isVisible then self:close() else self:open() end
end

function WCRosterPanel:isOpen()
    return self.isVisible
end

-- Called every frame from WorkerManager:update().
function WCRosterPanel:update()
    if not self.isVisible then return end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    -- Auto-close if a real GUI (menu/dialog) opens on top.
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        self:close()
        return
    end
    -- #84 The Farm Tablet is a custom overlay g_gui cannot see, so use its focus API
    -- (g_currentMission.farmTablet) to step aside when the tablet is showing — two
    -- full-screen overlays must never fight. No-ops cleanly when FarmTablet is absent.
    local ft = g_currentMission and g_currentMission.farmTablet
    if ft and ft.isVisible then
        self:close()
    end
end

-- ── Drawing primitives (mirror SoilSettingsPanel) ─────────
function WCRosterPanel:drawRect(x, y, w, h, col, alpha)
    if not self.fillOverlay then return end
    local a = alpha or col[4] or 1.0
    setOverlayColor(self.fillOverlay, col[1], col[2], col[3], a)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

function WCRosterPanel:drawText(x, y, size, text, col, align, bold)
    setTextColor(col[1], col[2], col[3], col[4] or 1.0)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, size, text)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

function WCRosterPanel:registerClick(id, x, y, w, h, data)
    table.insert(self._clickRects, { id = id, x = x, y = y, w = w, h = h, data = data })
end

function WCRosterPanel:hitTest(rx, ry, rw, rh, mx, my)
    return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
end

function WCRosterPanel:drawButton(id, x, y, w, h, label, col, data)
    self:drawRect(x, y, w, h, col)
    self:drawText(x + w * 0.5, y + h * 0.28, TS_BTN, label, C.btnTxt, RenderText.ALIGN_CENTER)
    self:registerClick(id, x, y, w, h, data)
end

-- A labelled gauge: dark track with a proportional coloured fill. frac is 0..1.
function WCRosterPanel:drawBar(x, y, w, frac, fillCol)
    frac = math.max(0, math.min(1, frac or 0))
    self:drawRect(x, y, w, BAR_H, C.barTrack)
    if frac > 0 then
        self:drawRect(x, y, w * frac, BAR_H, fillCol)
    end
end

-- ── Data helpers ──────────────────────────────────────────
-- One cached snapshot drives both the list and the dossier so the wage math lives
-- in exactly one place (WorkerManager:getServerSnapshot). Rebuilt at most ~3x/sec.
function WCRosterPanel:_getSnapshot()
    local now = (g_currentMission and g_currentMission.time) or 0
    if self._snapshot == nil or (now - self._snapshotAt) > 350 then
        local mgr = g_currentMission and g_currentMission.workerCostsManager
        if mgr and mgr.getRosterSnapshot then
            -- Runs in the draw loop; a throw here would spam every frame. Keep the
            -- last good snapshot on failure rather than crashing the panel.
            local ok, snap = pcall(function() return mgr:getRosterSnapshot() end)
            if ok then
                self._snapshot = snap
            end
        end
        self._snapshotAt = now
    end
    return self._snapshot
end

-- The selected worker's enriched row from the snapshot (nil if none / fired).
function WCRosterPanel:_selectedData(snap)
    if not snap or not snap.workers or self.selectedUuid == nil then
        return nil
    end
    for _, w in ipairs(snap.workers) do
        if w.uuid == self.selectedUuid then
            return w
        end
    end
    return nil
end

-- A bit of flavour over the bare level name for the dossier header.
local LEVEL_TITLE = { Novice = "Field Hand", Experienced = "Seasoned Operator", Master = "Master Operator" }
function WCRosterPanel:_levelTitle(levelName)
    return LEVEL_TITLE[levelName or ""] or (levelName or "Worker")
end

-- Status dot colour + label. The lifecycle state + history resume now ride in the
-- snapshot (#78), so the dossier renders identically on the host and MP clients
-- with no local roster read. A notable lifecycle state wins over working/idle.
local LIFE_LABEL = {
    onLeave  = { label = "On leave", c = "dotLeave" },
    injured  = { label = "Injured",  c = "dotHurt"  },
    training = { label = "Training",  c = "dotLeave" },
    retired  = { label = "Retired",   c = "dotIdle"  },
}
function WCRosterPanel:_status(workerData)
    local m = LIFE_LABEL[workerData.lifecycleState or ""]
    if m then
        return C[m.c], m.label
    end
    if workerData.working then
        return C.dotWork, "Working"
    end
    return C.dotIdle, "Idle"
end

-- ── Main draw ─────────────────────────────────────────────
function WCRosterPanel:draw()
    if not self.isVisible or not self.initialized or not g_currentMission then
        return
    end
    self._clickRects = {}

    -- Dim backdrop + panel
    self:drawRect(0, 0, 1, 1, C.shadow, 0.40)
    self:drawRect(PX + 0.004, PY - 0.004, PW, PH, C.shadow, 0.55)
    self:drawRect(PX, PY, PW, PH, C.bg)

    -- Border
    local bw = 0.0015
    self:drawRect(PX,           PY,            PW, bw, C.border)
    self:drawRect(PX,           PY + PH - bw,  PW, bw, C.border)
    self:drawRect(PX,           PY,            bw, PH, C.border)
    self:drawRect(PX + PW - bw, PY,            bw, PH, C.border)

    local snap = self:_getSnapshot()
    self:drawTitleBar(snap)
    self:drawLeftPane(snap)
    self:drawDetailPane(snap)
    self:drawInfoBar()
end

function WCRosterPanel:drawTitleBar(snap)
    local ty = PY + PH - TB_H
    self:drawRect(PX, ty, PW, TB_H, C.title)

    local count = (snap and snap.count) or (self.roster and self.roster:getCount()) or 0
    self:drawText(PX + PAD, ty + TB_H * 0.30, TS_TITLE,
        "STAFF MANAGEMENT", C.text, RenderText.ALIGN_LEFT, true)

    -- Close [X]
    local xW = 0.04
    local xX = PX + PW - PAD - xW
    self:drawButton("close", xX, ty + (TB_H - 0.034) * 0.5, xW, 0.034, "X", C.btnFire)

    -- KPI strip on the right: head-count + working now + monthly payroll.
    local working = (snap and snap.working) or 0
    local payroll = (snap and snap.finance and snap.finance.monthAccrued) or 0
    local money = (g_i18n and g_i18n:formatMoney(payroll, 0, true, true)) or ("$" .. payroll)
    local kpi = string.format("%d staff  -  %d working  -  %s/mo", count, working, money)
    self:drawText(xX - 0.014, ty + TB_H * 0.34, TS_INFO, kpi, C.dim, RenderText.ALIGN_RIGHT)
end

-- ── Left pane: hire button, daily quota, selectable roster list ──
function WCRosterPanel:drawLeftPane(snap)
    local bodyTop = PY + PH - TB_H
    local bodyBot = PY + IB_H
    local leftX   = PX + PAD
    local leftW   = LEFT_W

    -- "+ Hire" hires slot 1 of the daily pool. The hall now rotates once per day,
    -- so the quota + next candidate ride right under the button.
    local hireY  = bodyTop - PAD - HIRE_H
    local hiring = snap and snap.hiring or nil
    local limit  = (hiring and hiring.limit) or (WorkerManager and WorkerManager.DAILY_HIRE_LIMIT) or 5
    local used   = (hiring and hiring.usedToday) or 0
    local capped = used >= limit
    self:drawButton("hire", leftX, hireY, leftW, HIRE_H,
        capped and "Hire (cap)" or "+ Hire", capped and C.btnStar or C.btnHire)

    local quotaY = hireY - 0.016
    self:drawText(leftX, quotaY, TS_SMALL, string.format("%d/%d today", used, limit),
        capped and C.gold or C.dim, RenderText.ALIGN_LEFT)
    local nextCand = snap and snap.recruits and snap.recruits[1] or nil
    if nextCand then
        local cost = (g_i18n and g_i18n:formatMoney(nextCand.hireCost or 0, 0, true, true))
            or ("$" .. (nextCand.hireCost or 0))
        self:drawText(leftX + leftW, quotaY, TS_SMALL,
            string.format("%s %s", nextCand.name or "?", cost), C.dim, RenderText.ALIGN_RIGHT)
    end

    -- Roster list (already trusted-first, display-ordered, from the snapshot).
    local workers = (snap and snap.workers) or {}
    local total   = #workers

    -- Keep a valid selection: re-home a stale uuid, auto-select the first worker.
    if total > 0 then
        local found = false
        for _, w in ipairs(workers) do
            if w.uuid == self.selectedUuid then found = true; break end
        end
        if not found then self.selectedUuid = workers[1].uuid end
    else
        self.selectedUuid = nil
    end

    local listTop = quotaY - 0.014
    if total == 0 then
        self:drawText(leftX + leftW * 0.5, listTop - 0.06, TS_SMALL,
            "No staff yet", C.dim, RenderText.ALIGN_CENTER)
        return
    end

    local maxPage = math.floor((total - 1) / ROWS_PER_PAGE)
    if self.page > maxPage then self.page = maxPage end
    if self.page < 0 then self.page = 0 end
    local startIdx = self.page * ROWS_PER_PAGE + 1
    local endIdx   = math.min(startIdx + ROWS_PER_PAGE - 1, total)

    local i = 0
    for idx = startIdx, endIdx do
        local w  = workers[idx]
        local ry = listTop - LIST_ROW_H - (i * LIST_ROW_H)
        local rh = LIST_ROW_H - 0.004

        -- Seat colour: selected = green, trusted = warm, else zebra.
        local rowBg = (i % 2 == 0) and C.row or C.rowAlt
        if w.trusted then rowBg = C.rowTrust end
        if w.uuid == self.selectedUuid then rowBg = C.sel end
        self:drawRect(leftX, ry, leftW, rh, rowBg)

        -- Trusted star toggle (registered FIRST so it wins the row-select overlap).
        local starX = leftX + 0.004
        self:drawText(starX + BTN_STAR_W * 0.5, ry + rh * 0.28, TS_ROW, "*",
            w.trusted and C.gold or C.dim, RenderText.ALIGN_CENTER, true)
        self:registerClick("star_" .. w.uuid, starX, ry, BTN_STAR_W, rh,
            { uuid = w.uuid, trusted = w.trusted })

        -- Status dot.
        local dotCol = self:_status(w)
        local dotX = starX + BTN_STAR_W + 0.004
        self:drawRect(dotX, ry + rh * 0.5 - 0.004, 0.008, 0.008, dotCol)

        -- Name (top) + level (under).
        local txtX = dotX + 0.014
        self:drawText(txtX, ry + rh * 0.52, TS_ROW, w.name or "Worker",
            C.text, RenderText.ALIGN_LEFT, true)
        self:drawText(txtX, ry + rh * 0.14, TS_SMALL, w.levelName or "Novice",
            C.dim, RenderText.ALIGN_LEFT)

        -- Whole-row select (registered after the star).
        self:registerClick("select_" .. w.uuid, leftX, ry, leftW, rh, { uuid = w.uuid })

        i = i + 1
    end

    -- Paging.
    if total > ROWS_PER_PAGE then
        local pageY = bodyBot + 0.006
        local pw = 0.040
        self:drawButton("page_prev", leftX, pageY, pw, 0.028, "<", C.row)
        self:drawButton("page_next", leftX + pw + 0.008, pageY, pw, 0.028, ">", C.row)
        self:drawText(leftX + leftW, pageY + 0.005, TS_SMALL,
            string.format("%d/%d", self.page + 1, maxPage + 1), C.dim, RenderText.ALIGN_RIGHT)
    end
end

-- ── Right pane: the selected worker's dossier ──
function WCRosterPanel:drawDetailPane(snap)
    local bodyTop = PY + PH - TB_H
    local bodyBot = PY + IB_H
    local rx = PX + PAD + LEFT_W + COL_GAP
    local rw = (PX + PW - PAD) - rx

    -- Pane backdrop + a thin divider on its left edge.
    self:drawRect(rx, bodyBot, rw, bodyTop - bodyBot, C.detailBg)
    self:drawRect(rx - COL_GAP * 0.5, bodyBot, 0.0012, bodyTop - bodyBot, C.border)

    local d = self:_selectedData(snap)
    if d == nil then
        local msg = (snap and (snap.count or 0) > 0)
            and "Select a worker to view their file."
            or  "No staff yet. Hire from the left,\nor start an AI helper."
        self:drawText(rx + rw * 0.5, (bodyTop + bodyBot) * 0.5, TS_ROW, msg,
            C.dim, RenderText.ALIGN_CENTER)
        return
    end

    local dx = rx + 0.016
    local dw = rw - 0.032
    local fmt = function(v) return (g_i18n and g_i18n:formatMoney(v, 0, true, true)) or ("$" .. math.floor(v or 0)) end
    local labelW, valueW = 0.070, 0.085
    local barX = dx + labelW
    local barW = dw - labelW - valueW

    -- Header: name + a trusted toggle on the right.
    local nameY = bodyTop - 0.036
    self:drawText(dx, nameY, TS_NAME, d.name or "Worker", C.text, RenderText.ALIGN_LEFT, true)
    local starW = BTN_TRUST_W
    self:drawButton("star_" .. d.uuid, dx + dw - starW, nameY - 0.002, starW, 0.030,
        d.trusted and "* Trusted" or "* Mark", d.trusted and C.btnHire or C.btnStar,
        { uuid = d.uuid, trusted = d.trusted })

    -- Subtitle: level title (left) + status (right, in its status colour).
    local subY = nameY - 0.028
    self:drawText(dx, subY, TS_ROW, self:_levelTitle(d.levelName), C.accent, RenderText.ALIGN_LEFT)
    local stCol, stLabel = self:_status(d)
    self:drawText(dx + dw, subY, TS_INFO, stLabel, stCol, RenderText.ALIGN_RIGHT)

    -- SKILL gauge (XP proxied by hours worked; tiers at 40 / 160).
    local hours = d.totalHours or 0
    local skillFrac, nextLabel
    if (d.level or 1) >= WorkerRoster.LEVEL_MASTER then
        skillFrac, nextLabel = 1, "max"
    elseif hours >= WorkerRoster.XP_EXPERIENCED then
        skillFrac = (hours - WorkerRoster.XP_EXPERIENCED) / (WorkerRoster.XP_MASTER - WorkerRoster.XP_EXPERIENCED)
        nextLabel = string.format("next %dh", WorkerRoster.XP_MASTER)
    else
        skillFrac = hours / WorkerRoster.XP_EXPERIENCED
        nextLabel = string.format("next %dh", WorkerRoster.XP_EXPERIENCED)
    end
    local y = subY - 0.036
    self:drawText(dx, y + 0.002, TS_SMALL, "SKILL", C.dim, RenderText.ALIGN_LEFT)
    self:drawBar(barX, y, barW, skillFrac, C.xpFill)
    self:drawText(dx + dw, y + 0.001, TS_SMALL,
        string.format("%.0fh  %s", hours, nextLabel), C.dim, RenderText.ALIGN_RIGHT)

    -- FATIGUE gauge.
    local fat = d.fatigue or 0
    local fatCol = (fat < 0.5) and C.fatLow or (fat < 0.85 and C.fatMid or C.fatHigh)
    y = y - 0.032
    self:drawText(dx, y + 0.002, TS_SMALL, "FATIGUE", C.dim, RenderText.ALIGN_LEFT)
    self:drawBar(barX, y, barW, fat, fatCol)
    self:drawText(dx + dw, y + 0.001, TS_SMALL,
        string.format("%d%%", math.floor(fat * 100 + 0.5)), C.dim, RenderText.ALIGN_RIGHT)

    -- Lifetime line.
    y = y - 0.036
    self:drawText(dx, y, TS_INFO, string.format("Lifetime   %.0f h   -   %d jobs",
        hours, d.totalJobs or 0), C.text, RenderText.ALIGN_LEFT)

    -- Wage line: base -> effective, with the skill delta called out.
    y = y - 0.026
    local base, eff = d.baseRate or 0, d.effRate or (d.baseRate or 0)
    local unit = (snap and snap.finance and snap.finance.isHourly == false) and "/ha" or "/h"
    local wageStr = string.format("Wage   %s -> %s %s", fmt(base), fmt(eff), unit)
    if (eff - base) >= 0.5 then
        wageStr = wageStr .. string.format("  (+%s skill)", fmt(eff - base))
    end
    self:drawText(dx, y, TS_INFO, wageStr, C.text, RenderText.ALIGN_LEFT)

    -- Recent jobs (job-history resume, #66) — synced in the snapshot (#78).
    if (d.histJobs or 0) > 0 then
        y = y - 0.026
        self:drawText(dx, y, TS_INFO, string.format(
            "Recent   %d jobs   -   %d done   %d failed",
            d.histJobs or 0, d.histDone or 0, d.histFailed or 0),
            C.dim, RenderText.ALIGN_LEFT)
    end

    -- Action buttons along the bottom.
    local btnY = bodyBot + 0.012
    local bh = 0.034
    if d.pinned then
        self:drawButton("unassign_" .. d.uuid, dx, btnY, BTN_ASSIGN_W, bh, "Unassign",
            C.btnAssign, { uuid = d.uuid })
    else
        self:drawButton("assign_" .. d.uuid, dx, btnY, BTN_ASSIGN_W, bh, "Assign",
            C.btnAssign, { uuid = d.uuid })
    end
    local sev = d.severance or 0
    self:drawButton("fire_" .. d.uuid, dx + BTN_ASSIGN_W + BTN_GAP, btnY, BTN_FIRE_W + 0.02, bh,
        sev > 0 and ("Fire " .. fmt(sev)) or "Fire", C.btnFire,
        { uuid = d.uuid, name = d.name, level = d.level })
end

function WCRosterPanel:drawInfoBar()
    local iy = PY
    self:drawRect(PX, iy, PW, IB_H, C.title, 0.85)
    local msg = self.infoMsg or "Click a worker to open their file. The hiring hall refreshes each day."
    self:drawText(PX + PW - PAD, iy + IB_H * 0.30, TS_INFO, msg, C.text, RenderText.ALIGN_RIGHT)
end

-- ── Input ─────────────────────────────────────────────────
function WCRosterPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.isVisible then return false end
    self.mouseX = posX
    self.mouseY = posY

    if not isDown then return true end
    if button ~= Input.MOUSE_BUTTON_LEFT then return true end

    for _, r in ipairs(self._clickRects) do
        if self:hitTest(r.x, r.y, r.w, r.h, posX, posY) then
            self:handleClick(r.id, r.data)
            return true
        end
    end

    -- Click outside the panel closes it.
    if not self:hitTest(PX, PY, PW, PH, posX, posY) then
        self:close()
    end
    return true
end

function WCRosterPanel:_isServer()
    return g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer()
end

function WCRosterPanel:_getCurrentVehicle()
    if g_localPlayer and g_localPlayer.getCurrentVehicle then
        local ok, v = pcall(function() return g_localPlayer:getCurrentVehicle() end)
        if ok and v then return v end
    end
    if g_currentMission and g_currentMission.controlledVehicle then
        return g_currentMission.controlledVehicle
    end
    return nil
end

function WCRosterPanel:handleClick(id, data)
    if id == "close" then
        self:close()
        return
    end

    if id == "page_prev" then
        self.page = math.max(0, self.page - 1)
        return
    elseif id == "page_next" then
        self.page = self.page + 1   -- clamped on next draw
        return
    end

    -- Row selection drives the dossier. View-only, so it is allowed before the
    -- host-only mutation guard below (clients can browse the synced snapshot).
    if id:sub(1, 7) == "select_" and data then
        self.selectedUuid = data.uuid
        return
    end

    -- This panel renders from the local roster, which only the host holds, so it
    -- stays server/SP only. MP clients manage workers from the Farm Tablet Personnel
    -- app instead (it reads the synced snapshot). All mutations now route through the
    -- WorkerManager command API so a host action also broadcasts to clients and the
    -- recruit-pool / hire-cost rules apply everywhere (single source of truth).
    if not self:_isServer() then
        self.infoMsg = "Only the host can manage workers from this panel"
        return
    end
    if self.roster == nil then return end

    local mgr = g_currentMission and g_currentMission.workerCostsManager

    if id == "hire" then
        if mgr then
            -- #69 Respect the daily cap with immediate panel feedback (the host also
            -- enforces it server-side, so this is UX, not the security boundary).
            local limit = WorkerManager and WorkerManager.DAILY_HIRE_LIMIT or 5
            if mgr.getHiresUsedToday and mgr:getHiresUsedToday() >= limit then
                self.infoMsg = "Daily hiring limit reached - wait for the next day"
                return
            end
            local pool = mgr:getRecruitPool()
            local cand = pool and pool[1]
            mgr:hireWorker(1)
            if cand then
                local money = g_i18n and g_i18n:formatMoney(cand.hireCost or 0, 0, true, true) or ("$" .. (cand.hireCost or 0))
                local used = (mgr.getHiresUsedToday and mgr:getHiresUsedToday()) or 0
                self.infoMsg = string.format("Hired %s  (signing %s)  -  %d/%d today",
                    cand.name, money, used, limit)
            else
                self.infoMsg = "No recruits available"
            end
        end

    elseif id:sub(1, 5) == "star_" and data then
        -- #67 Toggle the Trusted/favorite flag (routes through the command API so
        -- the host broadcasts and the change persists).
        if mgr then mgr:setTrusted(data.uuid, not data.trusted) end
        self.infoMsg = data.trusted and "Removed from Trusted" or "Marked as Trusted"

    elseif id:sub(1, 5) == "fire_" and data then
        if mgr then
            local severance = (mgr.workerSystem and mgr.workerSystem:computeSeverance(data.level)) or 0
            mgr:fireWorker(data.uuid)
            local money = g_i18n and g_i18n:formatMoney(severance, 0, true, true) or ("$" .. severance)
            self.infoMsg = string.format("Fired %s  (severance %s)", data.name or "Worker", money)
        end

    elseif id:sub(1, 7) == "assign_" and data then
        local vehicle = self:_getCurrentVehicle()
        if vehicle == nil then
            self.infoMsg = "Get in the vehicle first, then click Assign"
            return
        end
        local uniqueId = (vehicle.getUniqueId and vehicle:getUniqueId()) or nil
        if uniqueId == nil or uniqueId == "" then
            self.infoMsg = "That vehicle has no stable id yet - save once, then assign"
            return
        end
        if mgr then mgr:assignWorker(data.uuid, uniqueId) end
        local vname = (vehicle.getFullName and vehicle:getFullName()) or "vehicle"
        self.infoMsg = string.format("Pinned to %s", vname)

    elseif id:sub(1, 9) == "unassign_" and data then
        if mgr then mgr:unassignWorker(data.uuid) end
        self.infoMsg = "Pin removed"
    end
end

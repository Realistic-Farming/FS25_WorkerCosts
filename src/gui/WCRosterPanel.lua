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
-- PRO-STAFF CHECKLIST (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 5 — clickable hire / fire / assign / unassign UI (server/SP)
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
    text   = { 0.64, 0.92, 0.70, 1 },  -- green text
    dim    = { 0.50, 0.70, 0.55, 1 },  -- muted green
    accent = { 0.55, 0.95, 0.62, 1 },
    btnHire   = { 0.20, 0.50, 0.28 },  -- green
    btnAssign = { 0.24, 0.42, 0.58 },  -- blue (distinct action)
    btnFire   = { 0.55, 0.24, 0.24 },  -- red (distinct, important)
    btnTxt    = { 1, 1, 1, 1 },        -- white on coloured buttons stays readable
}

-- ── Geometry (normalized, Y=0 at bottom) ──────────────────
local PW   = 0.50
local PH   = 0.60
local PX   = (1 - PW) / 2
local PY   = (1 - PH) / 2
local TB_H = 0.050
local IB_H = 0.040
local PAD  = 0.015
local ROW_H = 0.050
local ROWS_PER_PAGE = 7

-- Text sizes
local TS_TITLE = 0.018
local TS_ROW   = 0.0135
local TS_BTN   = 0.0125
local TS_INFO  = 0.0120

-- Button widths
local BTN_FIRE_W   = 0.052
local BTN_ASSIGN_W = 0.090
local BTN_GAP      = 0.008

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
    self.isVisible = true
    self.page      = 0
    self.infoMsg   = nil
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

    self:drawTitleBar()
    self:drawHireBar()
    self:drawRosterList()
    self:drawInfoBar()
end

function WCRosterPanel:drawTitleBar()
    local ty = PY + PH - TB_H
    self:drawRect(PX, ty, PW, TB_H, C.title)

    local count = self.roster and self.roster:getCount() or 0
    self:drawText(PX + PAD, ty + TB_H * 0.30, TS_TITLE,
        string.format("Pro-Staff Panel  (%d)", count), C.text, RenderText.ALIGN_LEFT, true)

    -- Close [X]
    local xW = 0.04
    local xX = PX + PW - PAD - xW
    self:drawButton("close", xX, ty + (TB_H - 0.034) * 0.5, xW, 0.034, "X", C.btnFire)
end

function WCRosterPanel:drawHireBar()
    local by = PY + PH - TB_H - 0.052
    local bw = 0.16
    self:drawButton("hire", PX + PAD, by, bw, 0.040, "+ Hire Worker", C.btnHire)

    -- Right-aligned hint about assigning.
    self:drawText(PX + PW - PAD, by + 0.010, TS_INFO,
        "Sit in a vehicle, then Assign", C.dim, RenderText.ALIGN_RIGHT)
end

function WCRosterPanel:drawRosterList()
    local workers = self.roster and self.roster:getAll() or {}
    local total = #workers

    local listTop = PY + PH - TB_H - 0.052 - 0.012   -- below hire bar
    local rowX = PX + PAD
    local rowW = PW - 2 * PAD

    if total == 0 then
        self:drawText(PX + PW * 0.5, listTop - 0.10, TS_ROW,
            "No workers yet. Click '+ Hire Worker', or start an AI helper.",
            C.dim, RenderText.ALIGN_CENTER)
        return
    end

    -- Clamp page
    local maxPage = math.floor((total - 1) / ROWS_PER_PAGE)
    if self.page > maxPage then self.page = maxPage end
    if self.page < 0 then self.page = 0 end

    local startIdx = self.page * ROWS_PER_PAGE + 1
    local endIdx   = math.min(startIdx + ROWS_PER_PAGE - 1, total)

    local fireX   = PX + PW - PAD - BTN_FIRE_W
    local assignX = fireX - BTN_GAP - BTN_ASSIGN_W

    local i = 0
    for idx = startIdx, endIdx do
        local w = workers[idx]
        local ry = listTop - ROW_H - (i * ROW_H)

        -- Row background (zebra)
        self:drawRect(rowX, ry, rowW, ROW_H - 0.004, (i % 2 == 0) and C.row or C.rowAlt)

        -- Status / level color accent dot via level color
        local levelName = WorkerRoster.levelName(w.level)
        local status = w.assignedVehicleId and "working" or "idle"
        if w.assignedVehicleUniqueId then status = status .. ", pinned" end

        -- Line 1: name + level
        self:drawText(rowX + 0.008, ry + ROW_H * 0.50, TS_ROW,
            string.format("%s  -  %s", w.name or "Worker", levelName),
            C.text, RenderText.ALIGN_LEFT, true)
        -- Line 2: stats
        self:drawText(rowX + 0.008, ry + ROW_H * 0.16, TS_INFO,
            string.format("%.1fh  -  %d jobs  -  fat %d%%  -  %s",
                w.totalHours or 0, w.totalJobs or 0,
                math.floor((w.fatigue or 0) * 100), status),
            C.dim, RenderText.ALIGN_LEFT)

        -- Buttons
        local bh = ROW_H - 0.014
        local byBtn = ry + 0.005
        if w.assignedVehicleUniqueId then
            self:drawButton("unassign_" .. w.uuid, assignX, byBtn, BTN_ASSIGN_W, bh,
                "Unassign", C.btnAssign, { uuid = w.uuid })
        else
            self:drawButton("assign_" .. w.uuid, assignX, byBtn, BTN_ASSIGN_W, bh,
                "Assign", C.btnAssign, { uuid = w.uuid })
        end
        self:drawButton("fire_" .. w.uuid, fireX, byBtn, BTN_FIRE_W, bh,
            "Fire", C.btnFire, { uuid = w.uuid, name = w.name, level = w.level })

        i = i + 1
    end

    -- Paging controls
    if total > ROWS_PER_PAGE then
        local py = PY + IB_H + 0.006
        local pw = 0.05
        self:drawButton("page_prev", PX + PAD, py, pw, 0.030, "<", C.row, nil)
        self:drawButton("page_next", PX + PAD + pw + 0.01, py, pw, 0.030, ">", C.row, nil)
        self:drawText(PX + PAD + 2 * pw + 0.03, py + 0.006, TS_INFO,
            string.format("Page %d / %d", self.page + 1, maxPage + 1), C.dim, RenderText.ALIGN_LEFT)
    end
end

function WCRosterPanel:drawInfoBar()
    local iy = PY
    self:drawRect(PX, iy, PW, IB_H, C.title, 0.85)
    local msg = self.infoMsg or "Hire, fire, and pin workers to vehicles. Pins survive save/reload."
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
            local pool = mgr:getRecruitPool()
            local cand = pool and pool[1]
            mgr:hireWorker(1)
            if cand then
                local money = g_i18n and g_i18n:formatMoney(cand.hireCost or 0, 0, true, true) or ("$" .. (cand.hireCost or 0))
                self.infoMsg = string.format("Hired %s  (signing %s)", cand.name, money)
            else
                self.infoMsg = "No recruits available"
            end
        end

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

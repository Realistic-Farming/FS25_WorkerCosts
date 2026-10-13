-- =========================================================
-- Worker Costs Field Guide - Field Guide
-- =========================================================
-- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): every Realistic Farming Esc page gets its own
-- guide, in its own mod, opened from the shared Help footer through this guest's onOpenHelp. The
-- chrome is SoilGuideDialog's so all of them read as one family; only the words differ.
-- Rows are { t = "H" | "B" | "S" | "COL", v = "text" }: header, body, spacer, column break.
-- =========================================================

---@class WcGuideDialog
WcGuideDialog = WcGuideDialog or {}
local WcGuideDialog_mt = Class(WcGuideDialog, ScreenElement)

local GUIDE_MOD_DIR = (WorkerCostsModDirectory or g_currentModDirectory)

WcGuideDialog.INSTANCE = nil
WcGuideDialog.GUI_NAME = "WcGuideDialog"

WcGuideDialog.SUBTITLES = {
    "Overview - what the mod does and the Esc page",
    "Wages - how the bill is worked out and paid",
    "Crew - the roster, hiring and firing",
    "Settings - options and common questions",
}

WcGuideDialog.PAGE1 = {
    { t="H", v="WHAT THIS MOD DOES" },
    { t="B", v="Realistic Worker Costs makes the AI helpers" },
    { t="B", v="you send out cost real money." },
    { t="B", v="While the mod is on, the game's own helper" },
    { t="B", v="fee is switched off and this mod bills you" },
    { t="B", v="instead, on its own schedule." },
    { t="S", v=" " },
    { t="B", v="Wages build up while a helper is working." },
    { t="B", v="The total is taken once per in-game day, at" },
    { t="B", v="midnight. The bill follows the in-game" },
    { t="B", v="clock, so it is fair at any time speed." },
    { t="S", v=" " },
    { t="H", v="THE PAUSE MENU PAGE" },
    { t="B", v="Open the pause menu, go to the Realistic" },
    { t="B", v="Farming page, then pick Worker Costs from" },
    { t="B", v="the list of mods on the left." },
    { t="S", v=" " },
    { t="B", v="The page is one screen made of four cards." },
    { t="COL", v="" },
    { t="H", v="WHAT THE CARDS SHOW" },
    { t="B", v="Left, top: your wage options. Each row has" },
    { t="B", v="arrows you click to change the setting." },
    { t="B", v="Left, lower: the rate you pay now, the pay" },
    { t="B", v="interval, a short how-to and a Reset" },
    { t="B", v="button." },
    { t="S", v=" " },
    { t="B", v="Right, top: the live numbers. Mod status," },
    { t="B", v="helpers working, the countdown to the next" },
    { t="B", v="settlement, hires left today, cost per" },
    { t="B", v="worker, the interval total, and the month" },
    { t="B", v="so far with an estimate." },
    { t="S", v=" " },
    { t="B", v="Right, lower: the roster board. Your staff" },
    { t="B", v="on the upper rows, today's recruits below," },
    { t="B", v="with Hire and Fire buttons beside them." },
    { t="S", v=" " },
    { t="B", v="The narrow box on the far left repeats a" },
    { t="B", v="short how-to for the page." },
    { t="S", v=" " },
    { t="B", v="Your farm balance is left off this page." },
}

WcGuideDialog.PAGE2 = {
    { t="H", v="TWO WAYS TO PAY" },
    { t="B", v="Hourly charges a set rate for every hour a" },
    { t="B", v="helper stays active." },
    { t="B", v="Per hectare charges by the area a helper" },
    { t="B", v="actually covers, so light jobs cost little" },
    { t="B", v="and big fields cost more." },
    { t="S", v=" " },
    { t="B", v="The Wage Level sets the rate for both." },
    { t="B", v="Low is 15, Medium is 25 and High is 40 an" },
    { t="B", v="hour, or per hectare in the other mode." },
    { t="B", v="Medium is the starting choice." },
    { t="S", v=" " },
    { t="H", v="WHAT MAKES A BILL BIGGER" },
    { t="B", v="Night work adds a premium." },
    { t="B", v="Working in the rain adds a premium." },
    { t="B", v="Hours past the daily overtime threshold" },
    { t="B", v="bill at a higher rate." },
    { t="B", v="A tired worker costs more, up to half as" },
    { t="B", v="much again when fully worn out. Master" },
    { t="B", v="hands do not suffer this." },
    { t="COL", v="" },
    { t="B", v="A higher level worker is a little cheaper" },
    { t="B", v="for the same work, so training pays off." },
    { t="B", v="The helper's own skill also nudges the" },
    { t="B", v="price up or down." },
    { t="S", v=" " },
    { t="H", v="WHEN THE MONEY MOVES" },
    { t="B", v="Wages settle once per in-game day, at" },
    { t="B", v="midnight. The countdown on the page shows" },
    { t="B", v="how long is left." },
    { t="S", v=" " },
    { t="B", v="With Monthly Salary on, the daily amounts" },
    { t="B", v="are only stored up, and the whole month is" },
    { t="B", v="settled on the last day of the month. A" },
    { t="B", v="summary window lists every worker and the" },
    { t="B", v="total, with a Pay and a Decline button." },
    { t="S", v=" " },
    { t="B", v="Decline leaves the wages unpaid and adds a" },
    { t="B", v="20 percent late charge next month." },
    { t="B", v="Closing that window with Escape pays it." },
    { t="B", v="It does not put the bill off." },
    { t="S", v=" " },
    { t="B", v="With Monthly Salary off, the money leaves" },
    { t="B", v="your account at each midnight instead." },
}

WcGuideDialog.PAGE3 = {
    { t="H", v="YOUR ROSTER" },
    { t="B", v="Every helper you send out gets a staff file" },
    { t="B", v="the first time they work for you. You do" },
    { t="B", v="not have to hire anyone to use helpers." },
    { t="S", v=" " },
    { t="B", v="A staff line shows the name, working or" },
    { t="B", v="idle, any pinned or trusted mark, the level" },
    { t="B", v="and how tired that worker is." },
    { t="S", v=" " },
    { t="H", v="LEVELS AND FATIGUE" },
    { t="B", v="Workers earn experience for the hours they" },
    { t="B", v="put in and climb from Novice to Experienced" },
    { t="B", v="to Master. A higher rank costs less for the" },
    { t="B", v="same work and is worth keeping." },
    { t="B", v="A fourth rank above Master exists but stays" },
    { t="B", v="locked unless another suite mod opens it." },
    { t="S", v=" " },
    { t="B", v="Hours worked build fatigue. An idle worker" },
    { t="B", v="sheds some fatigue each day off, so" },
    { t="B", v="rotating your staff keeps costs down." },
    { t="COL", v="" },
    { t="H", v="HIRING" },
    { t="B", v="The hiring hall offers four candidates." },
    { t="B", v="They change once per in-game day, so a" },
    { t="B", v="choice you like is safe until tomorrow." },
    { t="B", v="Each recruit line shows a number, a name, a" },
    { t="B", v="level and the signing fee." },
    { t="S", v=" " },
    { t="B", v="Click Hire beside a recruit to sign them." },
    { t="B", v="The signing fee is charged at once and" },
    { t="B", v="rises with the recruit's level." },
    { t="B", v="You can sign five workers per in-game day." },
    { t="B", v="The page shows how many hires are left." },
    { t="S", v=" " },
    { t="B", v="Better recruits only start turning up once" },
    { t="B", v="your staff have some experience between" },
    { t="B", v="them." },
    { t="S", v=" " },
    { t="H", v="FIRING" },
    { t="B", v="Click Fire beside a staff row to let that" },
    { t="B", v="worker go. Severance is charged as they" },
    { t="B", v="leave, and a higher rank costs more." },
    { t="B", v="Their file and their experience are gone" },
    { t="B", v="for good, so think before firing a Master." },
}

WcGuideDialog.PAGE4 = {
    { t="H", v="SETTINGS ON THE PAGE" },
    { t="B", v="The left card holds six settings. Use the" },
    { t="B", v="arrows on a row to change it." },
    { t="S", v=" " },
    { t="B", v="Enable Mod turns the whole thing on or off." },
    { t="B", v="With it off the game charges its own helper" },
    { t="B", v="fee again." },
    { t="B", v="Cost Mode picks Hourly or Per Hectare." },
    { t="B", v="Wage Level picks Low, Medium or High." },
    { t="B", v="Notifications turns the on-screen payment" },
    { t="B", v="messages on or off." },
    { t="B", v="Debug Mode adds extra log lines and only" },
    { t="B", v="helps when reporting a problem." },
    { t="B", v="Monthly Salary switches between the" },
    { t="B", v="end-of-month summary and paying daily." },
    { t="S", v=" " },
    { t="B", v="Reset puts every setting back to default." },
    { t="COL", v="" },
    { t="H", v="OTHER PLACES TO LOOK" },
    { t="B", v="The same settings also appear in the game's" },
    { t="B", v="General Settings, under a Worker Costs Mod" },
    { t="B", v="heading." },
    { t="S", v=" " },
    { t="B", v="There is a fuller roster panel with a" },
    { t="B", v="worker file, gauges and Assign buttons." },
    { t="B", v="It has no key set for you. Look under" },
    { t="B", v="Options then Controls for the action named" },
    { t="B", v="Open Worker Roster and give it a key." },
    { t="B", v="In multiplayer only the host can manage" },
    { t="B", v="staff from that panel." },
    { t="S", v=" " },
    { t="H", v="COMMON QUESTIONS" },
    { t="B", v="Nothing charged? Check that Enable Mod is" },
    { t="B", v="on and that a helper is really running." },
    { t="B", v="In per hectare mode a job that covers no" },
    { t="B", v="ground costs nothing." },
    { t="S", v=" " },
    { t="B", v="Settings are saved with each save game." },
    { t="B", v="In multiplayer everyone follows the host," },
    { t="B", v="and the page shows a waiting message until" },
    { t="B", v="the host has sent the roster." },
}

WcGuideDialog.PAGE_CONTENT = { WcGuideDialog.PAGE1, WcGuideDialog.PAGE2, WcGuideDialog.PAGE3, WcGuideDialog.PAGE4 }

-- -- Constructor ------------------------------------------

function WcGuideDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or WcGuideDialog_mt)
    self._contentLineEls = {}
    self._currentPage = 1
    return self
end

--- Loads the dialog into g_gui once. Safe to call twice, and safe to call when some other path has
--- already registered the same name.
function WcGuideDialog.register(modDirectory)
    if g_gui == nil then return end
    if g_gui.guis ~= nil and g_gui.guis[WcGuideDialog.GUI_NAME] ~= nil then return end
    if modDirectory ~= nil then GUIDE_MOD_DIR = modDirectory end
    if GUIDE_MOD_DIR == nil then return end
    WcGuideDialog.INSTANCE = WcGuideDialog.new()
    local ok, err = pcall(function()
        g_gui:loadGui(GUIDE_MOD_DIR .. "xml/gui/WcGuideDialog.xml", WcGuideDialog.GUI_NAME, WcGuideDialog.INSTANCE)
    end)
    if not ok then
        print("[WorkerCosts] WcGuideDialog: loadGui failed: " .. tostring(err))
        WcGuideDialog.INSTANCE = nil
    end
end

function WcGuideDialog.show()
    if g_gui == nil then return end
    local loaded = g_gui.guis ~= nil and g_gui.guis[WcGuideDialog.GUI_NAME] ~= nil
    if not loaded then
        WcGuideDialog.register(GUIDE_MOD_DIR)
        loaded = g_gui.guis ~= nil and g_gui.guis[WcGuideDialog.GUI_NAME] ~= nil
    end
    if not loaded then return end
    g_gui:showDialog(WcGuideDialog.GUI_NAME)
end

-- -- Lifecycle --------------------------------------------

function WcGuideDialog:onGuiSetupFinished()
    WcGuideDialog:superClass().onGuiSetupFinished(self)
    self._elCol1 = self:getDescendantById("wcGuide_col1")
    self._elCol2 = self:getDescendantById("wcGuide_col2")
    self._elSubtitle = self:getDescendantById("wcGuide_subtitle")
end

function WcGuideDialog:onOpen()
    WcGuideDialog:superClass().onOpen(self)
    self._currentPage = 1
    self:_selectPage(1)
end

function WcGuideDialog:onClose()
    WcGuideDialog:superClass().onClose(self)
    self:_clearContent()
    self._currentPage = 1
end

-- -- Tabs -------------------------------------------------

function WcGuideDialog:onClickTab1() self:_selectPage(1) end
function WcGuideDialog:onClickTab2() self:_selectPage(2) end
function WcGuideDialog:onClickTab3() self:_selectPage(3) end
function WcGuideDialog:onClickTab4() self:_selectPage(4) end

function WcGuideDialog:_selectPage(pageNum)
    if self._currentPage == pageNum and #self._contentLineEls > 0 then return end
    self:_clearContent()
    self._currentPage = pageNum
    if self._elSubtitle ~= nil then
        self._elSubtitle:setText(WcGuideDialog.SUBTITLES[pageNum] or "")
    end
    self:_buildContent(pageNum)
end

-- -- Content ----------------------------------------------

function WcGuideDialog:_buildContent(pageNum)
    local profileH = g_gui:getProfile("wcGuide_colHeader")
    local profileB = g_gui:getProfile("wcGuide_colBody")
    local profileS = g_gui:getProfile("wcGuide_colSpacer")
    if not profileH or not profileB then
        print("[WorkerCosts] WcGuideDialog: column profiles not found")
        return
    end
    local content = WcGuideDialog.PAGE_CONTENT[pageNum]
    if content == nil then return end
    local currentBox = self._elCol1
    for _, row in ipairs(content) do
        if row.t == "COL" then
            if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
            currentBox = self._elCol2
        elseif currentBox ~= nil then
            local profile = (row.t == "H") and profileH
                         or (row.t == "S") and profileS
                         or profileB
            if profile ~= nil then
                local el = TextElement.new()
                el:loadProfile(profile, true)
                el:setText(row.v or "")
                currentBox:addElement(el)
                el:onGuiSetupFinished()
                table.insert(self._contentLineEls, { box = currentBox, el = el })
            end
        end
    end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

function WcGuideDialog:_clearContent()
    for _, entry in ipairs(self._contentLineEls or {}) do
        if entry.box ~= nil then
            entry.box:removeElement(entry.el)
        end
    end
    self._contentLineEls = {}
    if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

-- -- Button -----------------------------------------------

function WcGuideDialog:onClickClose()
    g_gui:closeDialogByName(WcGuideDialog.GUI_NAME)
end

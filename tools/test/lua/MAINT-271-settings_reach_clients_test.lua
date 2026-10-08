-- MAINT-271-settings_reach_clients_test.lua
--
-- MAINTENANCE row 271: WorkerCosts' admin settings reach clients. A client's GUI (the dashboard, menu page,
-- About, Stats, the PDA page, the editing UIs' option states) read the client's own settings, which the
-- roster snapshot never carried, so a client showed its own file's values (the last server it quit) or the
-- defaults. Bob's R-15 (Desk Office/Drafts/BOB-R15-MAINT271-WC-SETTINGS-TO-CLIENTS-2026-10-08.md), option
-- (B): getServerSnapshot carries the five admin keys raw; both wires carry them (the NetworkSync bridge's
-- aggregate, FULL and delta, and the own WCRosterSyncEvent); applyClientSnapshot applies them on a pure
-- client by raw assignment, no setters, no save; and Settings:save, the one choke point every settings writer
-- passes through, sends the roster sync on the server (not during load, not while shutting down).
--
-- THE ENTRY-POINT BAR: each machine enters through WorkerManager:onMissionLoaded, the function main.lua's
-- Mission00.loadMission00Finished hook calls, which loads that machine's own settings file and registers the
-- bridges with that machine's NetworkSync and SettingsHub (nothing registered by hand). The NetworkSync route
-- is FS25_NetworkSync's own code, verbatim at 9e599be (tools/test/lua/networksync_fixture): the server's
-- syncNow (FULL) and its 1 Hz batch (delta), the real RealisticFarmingSyncEvent writeStream into a client's
-- readStream, run, receiveFrames, the bridge's registered _onReadState/_onReadDelta, then the real
-- applyClientSnapshot. The own route is the real WCRosterSyncEvent written and read the same way. The server's
-- settings change through the hub's own applyChange and through the host's own WCWageSettingsFrame click
-- handler, not by hand. The display rows run the real refresh of the dashboard, menu page, About and Stats
-- frames and the PDA page's onShow, on both machines.
--
--   E0  both machines' onMissionLoaded register the bridge with their own NetworkSync, the server's with its hub
--   C0  control: before any snapshot each client display V1 and P1 read shows its own file's values, not the server's
--   F1  a FULL: the client's five admin settings become the server's; its player-local keys stay its own
--   F2  and the derived values every client reader shows (wage rate, cost-mode and wage-level names) match
--   V1  the client's dashboard, menu page, About and Stats show what the server's show
--   P1  the client's PDA page shows the server's status, rate and level, and its option states are the server's
--   D1  the server changes a setting through the hub's applyChange: with no roster change, the next 1 Hz delta
--       carries it and the client follows
--   L1  no "changed to" log line on the client from any of those snapshots
--   H1  the host changes the wage level in its own WCWageSettingsFrame: the next 1 Hz delta carries it
--   G1  a snapshot reaching the server's own applyClientSnapshot changes nothing there (pure client only)
--   X1  the shutdown save sends nothing
--   E1  without NetworkSync, the own WCRosterSyncEvent carries the settings and the client applies them
--
--!load: tools/test/lua/networksync_fixture/engine_stubs.lua, tools/test/lua/networksync_fixture/Logger.lua, tools/test/lua/networksync_fixture/RealisticFarmingSyncEvent.lua, tools/test/lua/networksync_fixture/NetworkSync.lua, src/settings/Settings.lua, src/WorkerRoster.lua, src/WorkerSystem.lua, src/WorkerManager.lua, src/WCNetworkEvents.lua, src/integrations/WorkerNetworkSyncBridge.lua, src/settings/SettingsHubBridge.lua, src/gui/WCDashboardFrame.lua, src/gui/WCMenuPage.lua, src/gui/WCAboutFrame.lua, src/gui/WCWorkerStatsFrame.lua, src/gui/WCWageSettingsFrame.lua, src/gui/WcRfPdaGuest.lua

local INFO = {}
-- The game's Lua 5.1 formats a fraction with %d by truncating it (WorkerSystem:initialize logs the 12.5 custom
-- rate as "$%d"); this harness's Lua 5.3 raises instead, so a line that cannot be formatted keeps its format string.
Logging = { info = function(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    INFO[#INFO + 1] = ok and s or fmt
end, warning = function() end, error = function() end }
NSLogger.warning = function() end
NSLogger.debug = function() end
NSLogger.error = function() end
NSLogger.info = function() end
MoneyType = MoneyType or { OTHER = 3 }
g_i18n.formatMoney = function(_, v) return tostring(v) end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

local function newMission(isServer)
    local m = { _isServer = isServer, isMissionStarted = true,
        getIsServer = function(self) return self._isServer end,
        getIsClient = function(self) return not self._isServer end,
        environment = { currentDay = 5, daysPerPeriod = 1 }, missionInfo = {},
        missionDynamicInfo = { isMultiplayer = true } }
    m.getFarmId = function() return 1 end
    return m
end
--- A manager on the real Settings, WorkerRoster and WorkerSystem. `file` is this machine's own settings file,
--- which the real Settings:load reads through the settings manager's loadSettings.
local function newManager(m, file)
    local settings = Settings.new({ saveSettings = function() end,
        loadSettings = function(_, s) for k, v in pairs(file) do s[k] = v end end })
    local roster = WorkerRoster.new()
    local ms = setmetatable({ mission = m, settings = settings, workerRoster = roster,
                              workerSystem = WorkerSystem.new(settings, roster) }, { __index = WorkerManager })
    ms.saveWorkerData = function() end
    ms.loadWorkerData = function() end
    m.workerCostsManager = ms
    return ms
end

local W = {}
--- One machine context: its mission, NetworkSync, manager, g_server / g_client.
local function on(machine, fn)
    local saved = { g_currentMission, g_networkSync, g_server, g_client, g_WorkerManager }
    g_currentMission, g_networkSync, g_WorkerManager = machine.mission, machine.ns, machine.wm
    g_server, g_client = machine.server, machine.client
    local res = table.pack(pcall(fn))
    g_currentMission, g_networkSync, g_server, g_client, g_WorkerManager = saved[1], saved[2], saved[3], saved[4], saved[5]
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end
local SERVER_FILE = { enabled = false, costMode = 2, wageLevel = 3, customRate = 12.5, monthlySalaryEnabled = false,
                      debugMode = false, showNotifications = false }
local CLIENT_FILE = { debugMode = true, showNotifications = true }   -- the client's own player-local choices
--- A server and one pure client, with or without NetworkSync, each loaded through its own onMissionLoaded.
local function world(withNS)
    W.sent = {}
    local server = { mission = newMission(true), server = { broadcastEvent = function(_, ev) W.sent[#W.sent + 1] = ev end } }
    local client = { mission = newMission(false), client = { getServerConnection = function() return { sendEvent = function() end } end } }
    if withNS then server.ns, client.ns = NetworkSync.new(), NetworkSync.new() end
    server.mission.networkSync, client.mission.networkSync = server.ns, client.ns
    server.mission.settingsHub = { registerModule = function(_, modId, spec) W.hubSpec = spec return true end }
    client.mission.settingsHub = { registerModule = function(_, modId, spec) W.clientHubSpec = spec return true end }
    W.hubSpec, W.clientHubSpec = nil, nil
    on(server, function()
        server.wm = newManager(server.mission, SERVER_FILE)
        g_WorkerManager = server.wm
        server.wm:onMissionLoaded()
    end)
    on(client, function()
        client.wm = newManager(client.mission, CLIENT_FILE)
        g_WorkerManager = client.wm
        client.wm:onMissionLoaded()
    end)
    W.server, W.client = server, client
    return server, client
end
--- The engine's delivery of every event the server sent since `from`: writeStream, then a fresh instance's
--- readStream on the client, which runs.
local function deliverSince(from)
    local n = 0
    for k = from + 1, #W.sent do
        local ev = W.sent[k]
        local s = _sfMockStream()
        on(W.server, function() ev:writeStream(s, nil) end)
        on(W.client, function()
            local rx = getmetatable(ev).__index.emptyNew and getmetatable(ev).__index.emptyNew() or nil
            if rx == nil then error("no emptyNew for the event class") end
            rx:readStream(s, nil)
        end)
        n = n + 1
    end
    return n
end
local function five(s)
    return table.concat({ tostring(s.enabled), tostring(s.costMode), tostring(s.wageLevel), tostring(s.customRate),
        tostring(s.monthlySalaryEnabled) }, "/")
end
local function changedLines()
    local n = 0
    for _, l in ipairs(INFO) do if l:find("changed to", 1, true) then n = n + 1 end end
    return n
end

--- A GUI element that records its text and state; any other element method is inert.
local function el(state)
    return setmetatable({ text = "", state = state or 0 }, { __index = function(_, k)
        if k == "setText" then return function(self, s) self.text = tostring(s) end end
        if k == "getState" then return function(self) return self.state end end
        if k == "setState" then return function(self, s) self.state = s end end
        return function() end
    end })
end
local FRAMES = {
    { "dashboard", function() return WCDashboardFrame end, { "txtModEnabled", "txtCurrentRate", "txtCostMode", "txtWageLevel" } },
    { "menu page", function() return WCMenuPage end,       { "txtModEnabled", "txtCostMode", "txtWageLevel", "txtWageRate" } },
    { "About",     function() return WCAboutFrame end,     { "txtEffRate", "txtRateLabel", "txtCostMode" } },
    { "Stats",     function() return WCWorkerStatsFrame end, { "txtCostMode", "txtWageLevel" } },
}
--- What one frame's real refresh shows on a machine: its text elements, in order.
local function frameShows(machine, cls, fields)
    return on(machine, function()
        local f = { refreshLive = function() end }
        for _, id in ipairs(fields) do f[id] = el() end
        setmetatable(f, { __index = cls })
        f:refresh()
        local out = {}
        for _, id in ipairs(fields) do out[#out + 1] = f[id].text end
        return table.concat(out, " | ")
    end)
end
local PDA_TEXTS = { "wcDashStatus", "wcWageBigRate", "wcWageRateLabel" }
local PDA_OPTS = { "wcOptEnabled", "wcOptCostMode", "wcOptWageLevel", "wcOptMonthlySalary", "wcOptNotifications", "wcOptDebugMode" }
--- What the PDA page's real onShow shows on a machine: its status, rate and level texts, and its option states.
local function pdaShows(machine)
    return on(machine, function()
        local E = {}
        for _, id in ipairs(PDA_TEXTS) do E[id] = el() end
        for _, id in ipairs(PDA_OPTS) do E[id] = el() end
        WcRfPdaGuest.onShow({ getDescendantById = function(_, id) return E[id] end }, false)
        local texts, admin, own = {}, {}, {}
        for _, id in ipairs(PDA_TEXTS) do texts[#texts + 1] = E[id].text end
        for k = 1, 4 do admin[#admin + 1] = tostring(E[PDA_OPTS[k]].state) end
        for k = 5, 6 do own[#own + 1] = tostring(E[PDA_OPTS[k]].state) end
        return table.concat(texts, " | "), table.concat(admin, "/"), table.concat(own, "/")
    end)
end

group("N", function()
    local server, client = world(true)
    T.ok("E0 [entry point] each machine's onMissionLoaded registers the bridge with its own NetworkSync, and the server's with its SettingsHub",
        server.ns.schemas[WorkerNetworkSyncBridge.MODULE_ID] ~= nil and client.ns.schemas[WorkerNetworkSyncBridge.MODULE_ID] ~= nil
        and W.hubSpec ~= nil and W.hubSpec.selfPersisted == true)
    -- C0: every display row below can fail; before any snapshot each client display differs from the server's.
    for _, fr in ipairs(FRAMES) do
        T.ok("C0 control: before any snapshot the client's " .. fr[1] .. " shows its own file's values, not the server's",
            frameShows(client, fr[2](), fr[3]) ~= frameShows(server, fr[2](), fr[3]))
    end
    local s0Texts, s0Admin = pdaShows(server)
    local c0Texts, c0Admin = pdaShows(client)
    T.ok("C0 control: and the client's PDA page shows its own texts and option states", c0Texts ~= s0Texts and c0Admin ~= s0Admin)
    local before = changedLines()
    on(server, function() server.ns:syncNow(WorkerNetworkSyncBridge.MODULE_ID) end)
    local delivered = deliverSince(0)
    local cs = client.wm.settings
    T.eq("F1 [entry point] NAMED (row 271): a FULL through the real NetworkSync event makes the client's five admin settings the server's, and leaves its own player-local keys",
        delivered .. " " .. five(cs) .. " " .. tostring(cs.debugMode) .. "/" .. tostring(cs.showNotifications), "1 false/2/3/12.5/false true/true")
    local sv = server.wm.settings
    T.eq("F2 and the derived values every client reader shows match the server's (wage rate, cost-mode and wage-level names)",
        tostring(cs:getWageRate() == sv:getWageRate()) .. "/" .. tostring(cs:getCostModeName() == sv:getCostModeName())
        .. "/" .. tostring(cs:getWageLevelName() == sv:getWageLevelName()), "true/true/true")
    for _, fr in ipairs(FRAMES) do
        T.eq("V1 the client's " .. fr[1] .. " (its real refresh) shows what the server's shows",
            frameShows(client, fr[2](), fr[3]), frameShows(server, fr[2](), fr[3]))
    end
    local sTexts, sAdmin = pdaShows(server)
    local cTexts, cAdmin, cOwn = pdaShows(client)
    T.eq("P1 the client's PDA page (its real onShow) shows the server's status, rate and wage level", cTexts, sTexts)
    T.eq("P1 its enabled, cost mode, wage level and monthly salary option states are the server's, its notifications and debug its own",
        cAdmin .. " " .. cOwn, sAdmin .. " 2/2")
    -- The server changes the wage level through the hub's own applyChange; no roster change.
    local from = #W.sent
    on(server, function() W.hubSpec.onChange("wageLevel", 1, nil) end)
    on(server, function() server.ns:update(1000) end)
    deliverSince(from)
    T.eq("D1 a server change through the hub's applyChange rides the next 1 Hz delta with no roster change, and the client follows",
        tostring(server.wm.settings.wageLevel) .. "/" .. tostring(cs.wageLevel) .. " " .. (#W.sent - from), "1/1 1")
    T.eq("L1 no 'changed to' log line on the client from any snapshot (raw assignment, not the setters)",
        changedLines() - before, 1)   -- the one line is the server's own setWageLevel in the hub's applyChange
    -- H1: the host's own WCWageSettingsFrame, its real click handler. High (3): neither the client's default nor
    -- the value D1 left, so a client that never applies cannot match it by chance.
    local fromH = #W.sent
    on(server, function()
        local f = setmetatable({ optWageLevel = el(3), refreshRatePreview = function() end }, { __index = WCWageSettingsFrame })
        f:bindCallbacks()
        f.optWageLevel.onClickCallback()
        server.ns:update(1000)
    end)
    deliverSince(fromH)
    T.eq("H1 the host's wage level change in its own WCWageSettingsFrame rides the next 1 Hz delta, and the client follows",
        tostring(server.wm.settings.wageLevel) .. "/" .. tostring(cs.wageLevel) .. " " .. (#W.sent - fromH), "3/3 1")
    -- G1: a snapshot reaching the server's own applyClientSnapshot (a listen host) changes nothing there.
    local snap = on(client, function() return client.wm.clientRosterSnapshot end)
    local other = { settings = { enabled = true, costMode = 1, wageLevel = 1, customRate = 0, monthlySalaryEnabled = true } }
    on(server, function() server.wm:applyClientSnapshot(other) end)
    T.eq("G1 the server's own applyClientSnapshot never changes its settings (pure client only)", five(server.wm.settings), "false/2/3/12.5/false")
    T.ok("G1 (the client mirror was stored)", type(snap) == "table")
    -- X1: the shutdown save sends nothing.
    local fromX = #W.sent
    on(server, function()
        server.wm._shuttingDown = true
        server.wm.settings:save()
        server.ns:update(1000)
    end)
    T.eq("X1 the shutdown save sends nothing", #W.sent - fromX, 0)
end)

group("E", function()
    local server, client = world(false)
    local before = changedLines()
    local from = #W.sent
    on(server, function() W.hubSpec.onChange("costMode", 1, nil) end)
    local delivered = deliverSince(from)
    local cs = client.wm.settings
    T.eq("E1 without NetworkSync, a server change sends the own WCRosterSyncEvent, and the client takes the five admin settings, its own player-local keys untouched",
        delivered .. " " .. five(cs) .. " " .. tostring(cs.debugMode), "1 false/1/3/12.5/false true")
    T.eq("E1 (L) no 'changed to' line on the client: the only one is the server's own setCostMode", changedLines() - before, 1)
end)

g_server, g_client, g_WorkerManager = nil, nil, nil

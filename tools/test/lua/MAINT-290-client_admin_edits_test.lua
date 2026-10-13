-- MAINT-290-client_admin_edits_test.lua
--
-- MAINTENANCE row 290: a client admin's edit of WorkerCosts' admin settings reaches the server. Before, a client's
-- own settings UIs wrote only the client's settings and saved locally; after row 271 the edit reverted at the next
-- snapshot. Bob's R-15 (Desk Office/Drafts/BOB-R15-MAINT290-WC-CLIENT-ADMIN-EDITS-2026-10-08.md, with his reset
-- amendment): Settings:save is the client choke point too (WorkerManager:onSettingsSaved on a pure client, after the
-- mission has started, never while shutting down), sending only the admin keys that differ from the last applied
-- snapshot, and nothing with no snapshot yet; with NetworkSync the action WorkerCosts_SetSettings (adminOnly), without
-- it the own WCSettingsChangeEvent gated on the connection's master user, which answers a refusal with the snapshot;
-- one server apply validates each key, applies through the setters and saves, so every client converges; the three
-- editing UIs lock the admin options for a client that is not master; the user-facing resets (resetForUser) leave
-- the admin keys alone there, while Settings.new still sets all seven.
--
-- THE ENTRY-POINT BAR: three machines (a host, a master client A, a client B that is not master), each entering
-- through WorkerManager:onMissionLoaded, the function main.lua's Mission00.loadMission00Finished hook calls, which
-- loads that machine's own settings file and registers the bridges with that machine's NetworkSync. Every event is
-- written to a stream and read where the engine reads it: client to server with that client's connection (the
-- server's userManager names its user), server to every client or to one connection. FS25_NetworkSync's own code
-- (tools/test/lua/networksync_fixture, verbatim at 9e599be) carries the action and the snapshots. Edits enter through
-- the real writers: the wage settings tab's click handlers and reset, the PDA page's apply and reset, the settings
-- screen rows' refresh.
--
--   K0  a pure client's Settings.new holds all seven defaults (the constructor's reset is unconditional)
--   E0  each machine's onMissionLoaded registers the bridge; the server's SetSettings action is adminOnly
--   N0  a client save before any snapshot sends nothing (no baseline)
--   U1  the wage settings tab locks the four admin options for B only; the host and A see them unlocked
--   U2  the game's settings screen rows, at a later open: refreshed to the synced values and locked for B only
--   U3  the PDA page locks them for B only
--   B1  A changes the wage level in its own wage settings tab: one action carrying only wageLevel, the server applies
--       it and saves, and A and the third machine B converge
--   L0  a Notifications or Debug edit sends nothing
--   S0  A's reset sends only the admin keys that changed, and every machine converges
--   V0  a refused value (customRate 5000) is refused and logged once while the valid key in the same request applies
--   R1  B (not master) edits through NetworkSync: refused, the server unchanged, B reverts at the 30 s resync
--   P0  B's PDA apply with a stale admin widget writes only B's own keys and sends nothing
--   S1  B's reset changes only its own two keys and sends nothing
--   S2  and so do B's three other resets: the PDA page's, the settings screen's reset button, the console's
--   Q0  the quit save sends nothing
--   EB1 without NetworkSync, A's edit rides WCSettingsChangeEvent, the server applies it and A and B converge
--   ER2 B's edit through the own event is refused (not admin) and answered to B alone, so B reverts at once
--   EV0 a refused value through the own event is answered at once
--   EM0 a malformed request (an unknown key index) is refused and answered
--
--!load: tools/test/lua/networksync_fixture/engine_stubs.lua, tools/test/lua/networksync_fixture/Logger.lua, tools/test/lua/networksync_fixture/RealisticFarmingSyncEvent.lua, tools/test/lua/networksync_fixture/NetworkSync.lua, src/settings/Settings.lua, src/settings/WorkerSettingsUI.lua, src/settings/WorkerSettingsGUI.lua, src/WorkerRoster.lua, src/WorkerSystem.lua, src/WorkerManager.lua, src/WCNetworkEvents.lua, src/integrations/WorkerNetworkSyncBridge.lua, src/settings/SettingsHubBridge.lua, src/gui/WCWageSettingsFrame.lua, src/gui/WcRfPdaGuest.lua

local INFO, WARN = {}, {}
-- The game's Lua 5.1 formats a fraction with %d by truncating it; this harness's Lua 5.3 raises instead, so a line
-- that cannot be formatted keeps its format string (WorkerSystem:initialize logs the custom rate as "$%d").
local function fmt(f, ...)
    local ok, s = pcall(string.format, f, ...)
    return ok and s or f
end
Logging = { info = function(f, ...) INFO[#INFO + 1] = fmt(f, ...) end,
            warning = function(f, ...) WARN[#WARN + 1] = fmt(f, ...) end, error = function() end }
NSLogger.warning = function() end
NSLogger.debug = function() end
NSLogger.error = function() end
NSLogger.info = function() end
MoneyType = MoneyType or { OTHER = 3 }
InputAction = InputAction or { MENU_EXTRA_1 = "MENU_EXTRA_1" }
g_i18n.formatMoney = function(_, v) return tostring(v) end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

local function newMission(isServer, isMaster)
    local m = { _isServer = isServer, isMissionStarted = true, isMasterUser = isMaster,
        getIsServer = function(self) return self._isServer end,
        getIsClient = function(self) return not self._isServer end,
        environment = { currentDay = 5, daysPerPeriod = 1 }, missionInfo = {},
        missionDynamicInfo = { isMultiplayer = true } }
    m.getFarmId = function() return 1 end
    return m
end
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
local function on(machine, fn)
    local saved = { g_currentMission, g_networkSync, g_server, g_client, g_WorkerManager }
    g_currentMission, g_networkSync, g_WorkerManager = machine.mission, machine.ns, machine.wm
    g_server, g_client = machine.server, machine.client
    local res = table.pack(pcall(fn))
    g_currentMission, g_networkSync, g_server, g_client, g_WorkerManager = saved[1], saved[2], saved[3], saved[4], saved[5]
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

local SERVER_FILE = { enabled = true, costMode = 2, wageLevel = 1, customRate = 12.5, monthlySalaryEnabled = true,
                      debugMode = false, showNotifications = true }
local A_FILE = { debugMode = false, showNotifications = true }
local B_FILE = { debugMode = true, showNotifications = false }

--- The engine's user for a connection: master or not.
local function newUser(id, name, master)
    return { id = id, name = name, master = master,
        getIsMasterUser = function(self) return self.master end,
        getId = function(self) return self.id end,
        getNickname = function(self) return self.name end }
end

--- A host and two pure clients, with or without NetworkSync, each loaded through its own onMissionLoaded.
local function world(withNS)
    W.up, W.down, W.reads, W.downTo = {}, {}, {}, {}
    local server = { name = "host", mission = newMission(true, true),
                     server = { broadcastEvent = function(_, ev) W.down[#W.down + 1] = { ev = ev } end } }
    server.mission.userManager = { getUserByConnection = function(_, conn) return conn ~= nil and conn.user or nil end }
    local function client(name, master, id)
        local c = { name = name, mission = newMission(false, master) }
        c.client = { getServerConnection = function() return { sendEvent = function(_, ev) W.up[#W.up + 1] = { ev = ev, from = c } end } end }
        -- The server's connection object for this client.
        c.conn = { user = newUser(id, name, master), sendEvent = function(_, ev) W.down[#W.down + 1] = { ev = ev, to = c } end }
        return c
    end
    local A, B = client("A", true, 2), client("B", false, 3)
    if withNS then server.ns, A.ns, B.ns = NetworkSync.new(), NetworkSync.new(), NetworkSync.new() end
    for _, m in ipairs({ server, A, B }) do
        m.mission.networkSync = m.ns
        m.mission.settingsHub = { registerModule = function() return true end }
    end
    on(server, function() server.wm = newManager(server.mission, SERVER_FILE); g_WorkerManager = server.wm; server.wm:onMissionLoaded() end)
    on(A, function() A.wm = newManager(A.mission, A_FILE); g_WorkerManager = A.wm; A.wm:onMissionLoaded() end)
    on(B, function() B.wm = newManager(B.mission, B_FILE); g_WorkerManager = B.wm; B.wm:onMissionLoaded() end)
    W.server, W.clients = server, { A, B }
    return server, A, B
end

local function argsText(args)
    local out = {}
    for i = 1, #(args or {}), 2 do out[#out + 1] = tostring(args[i]) .. "=" .. tostring(args[i + 1]) end
    return table.concat(out, ",")
end
--- Deliver every queued event until both directions are empty. Client to server: written on the client, read on the
--- server with that client's connection (what the server read is kept in W.reads). Server to clients: written on the
--- server, read on every client or on the one connection it was sent to (counted per client in W.downTo).
local function pump()
    for _ = 1, 20 do
        if #W.up == 0 and #W.down == 0 then return end
        local up, down = W.up, W.down
        W.up, W.down = {}, {}
        for _, u in ipairs(up) do
            local s = _sfMockStream()
            on(u.from, function() u.ev:writeStream(s, nil) end)
            on(W.server, function()
                local rx = getmetatable(u.ev).__index.emptyNew()
                rx:readStream(s, u.from.conn)
                local cls = getmetatable(rx).__index
                local kind = rx.actionId or (cls == WCSettingsChangeEvent and "WCSettingsChangeEvent")
                    or (cls == WCRequestRosterSyncEvent and "WCRequestRosterSyncEvent") or "?"
                W.reads[#W.reads + 1] = { from = u.from.name, kind = kind, args = argsText(rx.args) }
            end)
        end
        for _, d in ipairs(down) do
            for _, c in ipairs(W.clients) do
                if d.to == nil or d.to == c then
                    local s = _sfMockStream()
                    on(W.server, function() d.ev:writeStream(s, nil) end)
                    on(c, function() getmetatable(d.ev).__index.emptyNew():readStream(s, nil) end)
                    if d.to ~= nil then W.downTo[c.name] = (W.downTo[c.name] or 0) + 1 end
                end
            end
        end
    end
    error("pump did not settle")
end
--- pump, then the server's 1 Hz NetworkSync batch, then pump again.
local function settle(dt)
    pump()
    if W.server.ns ~= nil then on(W.server, function() W.server.ns:update(dt or 1000) end) end
    pump()
end
local function five(s)
    return table.concat({ tostring(s.enabled), tostring(s.costMode), tostring(s.wageLevel), tostring(s.customRate),
        tostring(s.monthlySalaryEnabled) }, "/")
end
local function readsSince(n)
    local out = {}
    for k = n + 1, #W.reads do out[#out + 1] = W.reads[k].from .. ":" .. W.reads[k].kind .. "(" .. W.reads[k].args .. ")" end
    return table.concat(out, " ; ")
end

--- A GUI element that records its text, state and disabled flag; any other element method is inert.
local function el(state)
    return setmetatable({ text = "", state = state or 0 }, { __index = function(_, k)
        if k == "setText" then return function(self, s) self.text = tostring(s) end end
        if k == "getState" then return function(self) return self.state end end
        if k == "setState" then return function(self, s) self.state = s end end
        if k == "setIsChecked" then return function(self, c) self.state = c and 2 or 1 end end
        if k == "setDisabled" then return function(self, d) rawset(self, "disabled", d) end end
        return function() end
    end })
end
local function locks(...)
    local out = {}
    for _, e in ipairs({ ... }) do out[#out + 1] = tostring(rawget(e, "disabled")) end
    return table.concat(out, "/")
end
--- The wage settings tab on a machine: its six option widgets.
local function wageTab(machine)
    local f = setmetatable({ optEnabled = el(2), optCostMode = el(1), optWageLevel = el(2), optNotifications = el(2),
        optDebugMode = el(1), optMonthlySalary = el(2) }, { __index = WCWageSettingsFrame })
    on(machine, function() f:bindCallbacks() end)
    return f
end
local function tabLocks(machine)
    local f = wageTab(machine)
    on(machine, function() f:refresh() end)
    return locks(f.optEnabled, f.optCostMode, f.optWageLevel, f.optMonthlySalary) .. " own "
        .. locks(f.optNotifications, f.optDebugMode)
end
local PDA_OPTS = { "wcOptEnabled", "wcOptCostMode", "wcOptWageLevel", "wcOptMonthlySalary", "wcOptNotifications", "wcOptDebugMode" }
local function pdaContainer()
    local E = {}
    for _, id in ipairs(PDA_OPTS) do E[id] = el(1) end
    return { getDescendantById = function(_, id) return E[id] end }, E
end
local function pdaLocks(machine)
    local container, E = pdaContainer()
    on(machine, function() WcRfPdaGuest.onShow(container, false) end)
    return locks(E.wcOptEnabled, E.wcOptCostMode, E.wcOptWageLevel, E.wcOptMonthlySalary) .. " own "
        .. locks(E.wcOptNotifications, E.wcOptDebugMode)
end
--- The game's settings screen rows at a later open (inject's already-injected path): its states and locks.
local function rowsAtReopen(machine)
    return on(machine, function()
        local ui = WorkerSettingsUI.new(machine.wm.settings)
        ui.enabledOption, ui.debugOption, ui.costModeOption = el(1), el(1), el(1)
        ui.wageLevelOption, ui.notificationsOption, ui.monthlySalaryOption = el(1), el(1), el(1)
        ui.injected = true
        ui:inject()
        return ui.costModeOption.state .. "/" .. ui.wageLevelOption.state .. " "
            .. locks(ui.enabledOption, ui.costModeOption, ui.wageLevelOption, ui.monthlySalaryOption) .. " own "
            .. locks(ui.notificationsOption, ui.debugOption)
    end)
end

group("K", function()
    local s = on({ mission = newMission(false, false) }, function() return Settings.new({ saveSettings = function() end }) end)
    T.eq("K0 a pure client's Settings.new (g_server nil, not master) holds all seven defaults",
        five(s) .. " " .. tostring(s.showNotifications) .. "/" .. tostring(s.debugMode), "true/1/2/0/true true/false")
end)

group("N", function()
    local server, A, B = world(true)
    local act = server.ns.actions[WorkerNetworkSyncBridge.ACTIONS.SET_SETTINGS]
    T.ok("E0 [entry point] each machine's onMissionLoaded registers the bridge with its own NetworkSync; the server's WorkerCosts_SetSettings is adminOnly",
        A.ns.schemas[WorkerNetworkSyncBridge.MODULE_ID] ~= nil and B.ns.schemas[WorkerNetworkSyncBridge.MODULE_ID] ~= nil
        and act ~= nil and act.adminOnly == true)

    -- N0: no snapshot yet, so no baseline: A's save sends nothing.
    on(A, function() A.wm.settings.wageLevel = 3; A.wm.settings:save() end)
    T.eq("N0 a client save before any snapshot sends nothing (no baseline)", #W.up, 0)

    on(server, function() server.ns:syncNow(WorkerNetworkSyncBridge.MODULE_ID) end)
    settle()
    T.eq("N0 (then the first FULL gives both clients the server's settings)", five(A.wm.settings) .. " " .. five(B.wm.settings),
        "true/2/1/12.5/true true/2/1/12.5/true")

    T.eq("U1 the wage settings tab: the four admin options unlocked on the host", tabLocks(server), "false/false/false/false own nil/nil")
    T.eq("U1 unlocked for a master client", tabLocks(A), "false/false/false/false own nil/nil")
    T.eq("U1 locked for a client that is not master, its own two untouched", tabLocks(B), "true/true/true/true own nil/nil")
    T.eq("U2 the game's settings screen rows at a later open: the synced cost mode and wage level, unlocked on the host",
        rowsAtReopen(server), "2/1 false/false/false/false own nil/nil")
    T.eq("U2 unlocked for a master client", rowsAtReopen(A), "2/1 false/false/false/false own nil/nil")
    T.eq("U2 locked for a client that is not master", rowsAtReopen(B), "2/1 true/true/true/true own nil/nil")
    T.eq("U3 the PDA page: unlocked on the host", pdaLocks(server), "false/false/false/false own nil/nil")
    T.eq("U3 unlocked for a master client", pdaLocks(A), "false/false/false/false own nil/nil")
    T.eq("U3 locked for a client that is not master", pdaLocks(B), "true/true/true/true own nil/nil")

    -- B1: A's own wage settings tab, its real click handler.
    local r0 = #W.reads
    local tabA = wageTab(A)
    on(A, function() tabA.optWageLevel.state = 3; tabA.optWageLevel.onClickCallback() end)
    settle()
    T.eq("B1 [entry point] NAMED (row 290): A's wage level click sends one NetworkSync action carrying only wageLevel",
        readsSince(r0), "A:WorkerCosts_SetSettings(wageLevel=3)")
    T.eq("B1 the server applies it through the setter and saves; A and the third machine B converge",
        server.wm.settings.wageLevel .. "/" .. A.wm.settings.wageLevel .. "/" .. B.wm.settings.wageLevel, "3/3/3")

    -- L0: the player's own keys send nothing.
    local r1 = #W.reads
    on(A, function()
        tabA.optNotifications.state = 1; tabA.optNotifications.onClickCallback()
        tabA.optDebugMode.state = 2; tabA.optDebugMode.onClickCallback()
    end)
    settle()
    T.eq("L0 a Notifications or Debug edit sends nothing", readsSince(r1) .. "|" .. tostring(A.wm.settings.showNotifications)
        .. "/" .. tostring(A.wm.settings.debugMode), "|false/true")

    -- S0: A's reset (the tab's real reset) sends only the admin keys that changed.
    local r2 = #W.reads
    on(A, function() tabA:onClickReset() end)
    settle()
    T.eq("S0 A's reset sends only the admin keys that differ from the server's (enabled and monthly salary are already the defaults)",
        readsSince(r2), "A:WorkerCosts_SetSettings(costMode=1,wageLevel=2,customRate=0)")
    T.eq("S0 and every machine converges on the defaults", five(server.wm.settings) .. " " .. five(B.wm.settings), "true/1/2/0/true true/1/2/0/true")

    -- V0: one refused value and one valid one in the same request.
    local r3, w3 = #W.reads, #WARN
    on(A, function() local s = A.wm.settings; s.customRate = 5000; s.monthlySalaryEnabled = false; s:save() end)
    settle()
    T.eq("V0 a refused value is refused while the valid key in the same request applies, and A converges at the broadcast",
        readsSince(r3) .. " | " .. five(server.wm.settings) .. " " .. five(A.wm.settings),
        "A:WorkerCosts_SetSettings(customRate=5000,monthlySalaryEnabled=false) | true/1/2/0/false true/1/2/0/false")
    local named = tostring(WARN[#WARN]):match("customRate=5000") ~= nil
    T.eq("V0 logged once, naming the refused value", (#WARN - w3) .. " " .. tostring(named), "1 true")

    -- R1: B is not master; NetworkSync refuses before WorkerCosts' handler runs; the 30 s resync reverts B.
    local r4 = #W.reads
    on(B, function() B.wm.settings:setCostMode(2); B.wm.settings:save() end)
    settle()
    local before = B.wm.settings.costMode
    on(server, function() server.ns:update(30000) end)
    pump()
    T.eq("R1 B's edit through NetworkSync is refused: the server unchanged, B keeps its edit until the 30 s resync reverts it",
        readsSince(r4) .. " | " .. server.wm.settings.costMode .. " " .. before .. "->" .. B.wm.settings.costMode,
        "B:WorkerCosts_SetSettings(costMode=2) | 1 2->1")

    -- P0: B's PDA apply with a stale admin widget (cost mode 2 while B's setting is 1) and Notifications switched on.
    local r5 = #W.reads
    local container, E = pdaContainer()
    E.wcOptEnabled.state, E.wcOptCostMode.state, E.wcOptWageLevel.state, E.wcOptMonthlySalary.state = 2, 2, 3, 2
    E.wcOptNotifications.state, E.wcOptDebugMode.state = 2, 2
    on(B, function() WcRfPdaGuest.onWageOptionChanged(container) end)
    settle()
    T.eq("P0 B's PDA apply writes only B's own keys and sends nothing", readsSince(r5) .. "|" .. five(B.wm.settings)
        .. " " .. tostring(B.wm.settings.showNotifications), "|true/1/2/0/false true")

    -- S1: B's reset (the tab's real reset): only its own two keys.
    local r6 = #W.reads
    local tabB = wageTab(B)
    on(B, function() B.wm.settings.debugMode = true; B.wm.settings.showNotifications = false; tabB:onClickReset() end)
    settle()
    T.eq("S1 B's reset changes only its own two keys and sends nothing", readsSince(r6) .. "|" .. five(B.wm.settings) .. " "
        .. tostring(B.wm.settings.showNotifications) .. "/" .. tostring(B.wm.settings.debugMode), "|true/1/2/0/false true/false")

    -- S2: B's three other resets, each through its real caller: the PDA page's, the settings screen's reset
    -- button (as ensureResetButton installs it), the console's. B's monthly salary is off, so a reset of the admin
    -- keys would show.
    local r8 = #W.reads
    local after = {}
    local function mark() B.wm.settings.debugMode = true; B.wm.settings.showNotifications = false end
    local function look() after[#after + 1] = five(B.wm.settings) .. " " .. tostring(B.wm.settings.showNotifications)
        .. "/" .. tostring(B.wm.settings.debugMode) end
    on(B, function()
        mark(); WcRfPdaGuest.onWageReset((pdaContainer())); look()
        mark()
        local ui = WorkerSettingsUI.new(B.wm.settings)
        ui:ensureResetButton({ menuButtonInfo = {}, setMenuButtonInfoDirty = function() end })
        ui._resetButton.callback(); look()
        mark(); WorkerSettingsGUI.consoleCommandResetSettings({}); look()
    end)
    settle()
    T.eq("S2 B's PDA reset, settings screen reset button and console reset each change only its own two keys and send nothing",
        readsSince(r8) .. "|" .. table.concat(after, "; "),
        "|true/1/2/0/false true/false; true/1/2/0/false true/false; true/1/2/0/false true/false")

    -- Q0: the quit save.
    local r7 = #W.reads
    on(A, function() A.wm.settings.wageLevel = 3; A.wm._shuttingDown = true; A.wm.settings:save() end)
    settle()
    T.eq("Q0 the quit save sends nothing", readsSince(r7), "")
end)

group("E", function()
    local server, A, B = world(false)
    -- The join: each pure client asks for the roster (the real request), the server answers that connection.
    on(A, function() WCNetwork_RequestRosterSync() end)
    on(B, function() WCNetwork_RequestRosterSync() end)
    pump()
    local r0 = #W.reads
    local tabA = wageTab(A)
    on(A, function() tabA.optWageLevel.state = 3; tabA.optWageLevel.onClickCallback() end)
    pump()
    T.eq("EB1 without NetworkSync, A's click rides WCSettingsChangeEvent; the server applies it and A and B converge",
        readsSince(r0) .. " | " .. server.wm.settings.wageLevel .. "/" .. A.wm.settings.wageLevel .. "/" .. B.wm.settings.wageLevel,
        "A:WCSettingsChangeEvent(wageLevel=3) | 3/3/3")

    local w1, toA, toB = #WARN, W.downTo.A or 0, W.downTo.B or 0
    on(B, function() B.wm.settings:setCostMode(1); B.wm.settings:save() end)
    pump()
    T.eq("ER2 B's edit is refused (not admin), logged once and answered to B alone, so B reverts at once",
        server.wm.settings.costMode .. " " .. B.wm.settings.costMode .. " " .. (#WARN - w1) .. " " .. ((W.downTo.B or 0) - toB)
        .. "/" .. ((W.downTo.A or 0) - toA), "2 2 1 1/0")

    local w2, toA2 = #WARN, W.downTo.A or 0
    on(A, function() A.wm.settings.customRate = 5000; A.wm.settings:save() end)
    pump()
    T.eq("EV0 a refused value through the own event is answered at once: A reverts, the server unchanged",
        tostring(server.wm.settings.customRate) .. " " .. tostring(A.wm.settings.customRate) .. " " .. (#WARN - w2) .. " " .. ((W.downTo.A or 0) - toA2),
        "12.5 12.5 1 1")

    -- EM0: a request naming an unknown key index (a hand-written stream; this mod never writes one).
    local w3, toA3 = #WARN, W.downTo.A or 0
    local s = _sfMockStream()
    streamWriteUInt8(s, 1)
    streamWriteUInt8(s, 9)
    on(server, function() WCSettingsChangeEvent.emptyNew():readStream(s, A.conn) end)
    pump()
    T.eq("EM0 a malformed request is refused, logged and answered", (#WARN - w3) .. " " .. ((W.downTo.A or 0) - toA3), "1 1")
end)

g_server, g_client, g_WorkerManager = nil, nil, nil

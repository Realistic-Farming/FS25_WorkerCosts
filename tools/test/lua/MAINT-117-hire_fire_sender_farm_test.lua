-- MAINT-117-hire_fire_sender_farm_test.lua
--
-- MAINTENANCE row 117: hire and fire charged whatever farm the client named, on both
-- routes (the NetworkSync bridge read args[2] and ignored the user; the own event read
-- the wire farm and refused only 0). On the server the charged farm now comes from the
-- sender: the farm of the requesting user on the NetworkSync route
-- (FarmManager:getFarmByUserId), the connection's player record on the own-event route
-- (FSBaseMission:getFarmId); nil, 0 and a request naming a different farm are refused.
-- The host's own doors are unchanged. Worker ownership (the roster is one server-wide
-- list) is a Design question and out of scope here.
--
-- THE ENTRY-POINT BAR DRIVES BOTH REAL TRANSPORTS end to end: on the NetworkSync route a
-- pure client's WCNetwork_SendCommand, the bridge's sendCommand, requestAction, the real
-- RealisticFarmingActionEvent writeStream into readStream on the server, run,
-- _applyAction, the registered handler, then the real _applyCommandFromNetwork, _doHire
-- and chargeHireCost into the money book; on the own-event route the same doors, the real
-- WCWorkerCommandEvent writeStream into readStream, run. The transport is
-- FS25_NetworkSync's own code, verbatim at 9e599be (tools/test/lua/networksync_fixture).
-- The world is engine state (users, farms, a player record per connection, a money
-- book); the roster is written by the real hire.
--
--!load: tools/test/lua/networksync_fixture/engine_stubs.lua, tools/test/lua/networksync_fixture/Logger.lua, tools/test/lua/networksync_fixture/RealisticFarmingSyncEvent.lua, tools/test/lua/networksync_fixture/NetworkSync.lua, src/settings/Settings.lua, src/WorkerRoster.lua, src/WorkerSystem.lua, src/WorkerManager.lua, src/WCNetworkEvents.lua, src/integrations/WorkerNetworkSyncBridge.lua

local WARN = {}
Logging = { info = function() end, warning = function(fmt, ...) WARN[#WARN + 1] = string.format(fmt, ...) end, error = function() end }
NSLogger.warning = function() end
NSLogger.debug = function() end
NSLogger.error = function() end
MoneyType = MoneyType or { OTHER = 3 }
-- The hire and severance notifications format money through the engine's i18n; the
-- prelude's has no formatMoney, and a raise there would be swallowed by NetworkSync's
-- pcall around the handler, hiding a charge that happened with no worker created.
g_i18n.formatMoney = function(_, v) return tostring(v) end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end
local function warned(needle)
    local n = 0
    for _, l in ipairs(WARN) do if l:find(needle, 1, true) then n = n + 1 end end
    return n
end

-- ── engine state ────────────────────────────────────────────────────────────
-- Users: 1 in farm 1, 2 in farm 2, 3 a spectator (FarmManager:getFarmByUserId answers
-- the farm-0 object for a user in no farm, FarmManager.lua:192-202). The mission's
-- player records per connection (FSBaseMission:getFarmId, :1067-1085, :1098).
local function user(id, farmId)
    return { id = id, farmId = farmId,
        getId = function(self) return self.id end,
        getIsMasterUser = function() return false end,
        getNickname = function(self) return "user" .. self.id end }
end
local USERS = { [1] = user(1, 1), [2] = user(2, 2), [3] = user(3, 0) }
local function conn(u) return { user = u } end
local FROM_FARM1, FROM_FARM2, FROM_SPECTATOR, UNPLAYERED = conn(USERS[1]), conn(USERS[2]), conn(USERS[3]), conn(nil)

local W = {}
local function farmWorld()
    g_farmManager = {
        getFarmById = function(_, id) return { farmId = id, getBalance = function() return 1000000 end } end,
        getFarmByUserId = function(_, userId) local u = USERS[userId] if u == nil then return nil end return { farmId = u.farmId } end,
    }
end
local function mission(isServer, localFarm)
    local m = {
        _isServer = isServer, getIsServer = function(self) return self._isServer end,
        getIsClient = function(self) return not self._isServer end,
        environment = { currentDay = 5, daysPerPeriod = 1 }, missionInfo = {},
        missionDynamicInfo = { isMultiplayer = true },
        connectionsToPlayer = { [FROM_FARM1] = { farmId = 1 }, [FROM_FARM2] = { farmId = 2 }, [FROM_SPECTATOR] = { farmId = 0 } },
        addMoney = function(_, amount, farmId) W.charges[#W.charges + 1] = { amount = amount, farmId = farmId } end,
        getPlayerByConnection = function(self, c) return self.connectionsToPlayer[c] end,
    }
    m.getFarmId = function(self, connection)   -- FSBaseMission.lua:1067-1085
        if self:getIsServer() then
            if g_localPlayer == nil or connection ~= nil then
                if connection == nil then return nil end
                local player = self:getPlayerByConnection(connection)
                if player == nil then return nil end
                return player.farmId
            else
                return g_localPlayer.farmId
            end
        else
            return g_localPlayer == nil and 0 or g_localPlayer.farmId
        end
    end
    g_localPlayer = { farmId = localFarm }
    return m
end
--- A manager on the real roster, settings and worker system (the constructor's UI and
--- hall bindings are not the subject), its save a no-op.
local function newManager(m)
    local settings = Settings.new(nil)
    local roster = WorkerRoster.new()
    local ms = setmetatable({ mission = m, settings = settings, workerRoster = roster,
                              workerSystem = WorkerSystem.new(settings, roster) }, { __index = WorkerManager })
    ms.saveWorkerData = function() end
    return ms
end
--- The server world, with or without NetworkSync.
local function serverWorld(withNS)
    W.charges, W.sent = {}, {}
    farmWorld()
    g_currentMission = mission(true, 1)
    g_server = { broadcastEvent = function() end }
    g_client = nil
    if withNS then
        W.nsServer = NetworkSync.new()
        g_currentMission.networkSync = W.nsServer
        g_currentMission.userManager = { getUserByConnection = function(_, c) return c and c.user or nil end }
        g_networkSync = W.nsServer
    else
        g_networkSync = nil
    end
    local ms = newManager(g_currentMission)
    g_currentMission.workerCostsManager = ms
    WorkerNetworkSyncBridge.register(ms)   -- registers with NetworkSync when present, else stands down
    W.ms = ms
    return ms
end
--- A pure client of farm `farmId`, on the same route the server world chose.
local function asClient(farmId, fn)
    local saved = { g_currentMission, g_networkSync, g_server, g_client, g_localPlayer }
    local m = mission(false, farmId)
    if W.nsServer ~= nil then m.networkSync = NetworkSync.new() end
    g_currentMission, g_networkSync, g_server = m, m.networkSync, nil
    g_client = { getServerConnection = function() return { sendEvent = function(_, ev) W.sent[#W.sent + 1] = ev end } end }
    local mc = newManager(m)
    m.workerCostsManager = mc
    local ok, err = pcall(fn, mc)
    g_currentMission, g_networkSync, g_server, g_client, g_localPlayer = saved[1], saved[2], saved[3], saved[4], saved[5]
    if not ok then error(err, 0) end
end
--- The engine's delivery: the sender's writeStream into a fresh instance's readStream on
--- the server, which runs. The class is the event's own.
local function deliver(ev, connection)
    local class = ev.actionId ~= nil and RealisticFarmingActionEvent or WCWorkerCommandEvent
    local s = _sfMockStream()
    ev:writeStream(s, nil)
    g_currentMission._isServer = true
    g_networkSync = W.nsServer
    local rx = class.emptyNew()
    rx:readStream(s, connection)
    return rx, s.typeErrors + s.underflows
end
local function charges()
    local out = {}
    for _, ch in ipairs(W.charges) do out[#out + 1] = ch.farmId .. (ch.amount < 0 and "-" or "+") end
    return table.concat(out, ",")
end
-- The roster's workers table is an array (WorkerRoster.new); ids live on the workers.
local function rosterSize() return #(W.ms.workerRoster.workers or {}) end
local function firstUuid() local w = (W.ms.workerRoster.workers or {})[1] return w and w.uuid or nil end

-- ══════════════════════════════════════════════════════════════════════════
-- N. THE NETWORKSYNC ROUTE
-- ══════════════════════════════════════════════════════════════════════════
group("N", function()
    serverWorld(true)
    T.eq("N0 [world] the bridge registered with the real core", tostring(WorkerNetworkSyncBridge.active), "true")
    asClient(1, function(mc) mc:hireWorker(1) end)
    local ev = W.sent[1]
    local _, faults = deliver(ev, FROM_FARM1)
    T.eq("N1 a client of farm 1 hires for its own farm: the action carries { slot, farm 1 }, the worker joins the roster and farm 1 is charged once",
        tostring(ev and ev.actionId) .. "/" .. tostring(ev and ev.args[2]) .. "/" .. rosterSize() .. "/" .. charges() .. "/" .. faults, WorkerNetworkSyncBridge.ACTIONS.HIRE .. "/1/1/1-/0")
    -- A client of farm 2 naming farm 1: the door's own farm is 2, so the naming is the
    -- attacker's edit on the real request.
    asClient(2, function(mc) WCNetwork_SendCommand(WCCommand.HIRE, 0, 1, "", 1) end)
    deliver(W.sent[2], FROM_FARM2)
    T.eq("N2 a client of farm 2 naming farm 1 is refused: no hire, no charge, the mismatch logged",
        rosterSize() .. "/" .. charges() .. "/" .. warned("names farm 1 but is farm 2"), "1/1-/1")
    asClient(2, function(mc) mc:hireWorker(1) end)
    deliver(W.sent[3], FROM_FARM2)
    T.eq("N3 a client of farm 2 hiring for its own farm is charged to farm 2, never farm 1", rosterSize() .. "/" .. charges(), "2/1-,2-")
    asClient(0, function(mc) WCNetwork_SendCommand(WCCommand.HIRE, 0, 1, "", 0) end)
    deliver(W.sent[4], FROM_SPECTATOR)
    T.eq("N4 a spectator (the farm-0 object) is refused", rosterSize() .. "/" .. charges() .. "/" .. warned("in no farm"), "2/1-,2-/1")
    asClient(1, function(mc) mc:hireWorker(1) end)
    deliver(W.sent[5], UNPLAYERED)
    T.eq("N5 a connection with no user is refused (NetworkSync hands the handler no userId)", rosterSize() .. "/" .. charges() .. "/" .. warned("no user for the sender"), "2/1-,2-/1")
    -- Fire: the roster is server-wide (a Design question, not this row), so what the row
    -- pins is the charge: the sender's farm, never the named one.
    local uuid = firstUuid()
    asClient(2, function(mc) WCNetwork_SendCommand(WCCommand.FIRE, uuid, 0, "", 1) end)
    deliver(W.sent[6], FROM_FARM2)
    T.eq("N6 a fire naming farm 1 from farm 2's client is refused", rosterSize() .. "/" .. charges(), "2/1-,2-")
    asClient(2, function(mc) mc:fireWorker(uuid) end)
    deliver(W.sent[7], FROM_FARM2)
    T.eq("N7 a fire from farm 2's client is charged to farm 2 (severance), the worker leaves the roster", rosterSize() .. "/" .. charges(), "1/1-,2-,2-")
    -- The host's own door: local, with its own farm, no event, not through the core.
    W.ms:hireWorker(1)
    T.eq("N8 the host's own hire applies locally for its own farm, sending nothing", rosterSize() .. "/" .. charges() .. "/" .. #W.sent, "2/1-,2-,2-,1-/7")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- E. THE OWN-EVENT ROUTE (NO NETWORKSYNC)
-- ══════════════════════════════════════════════════════════════════════════
group("E", function()
    for k in pairs(WARN) do WARN[k] = nil end
    serverWorld(false)
    T.eq("E0 [world] without NetworkSync the bridge stands down", tostring(WorkerNetworkSyncBridge.active), "false")
    asClient(1, function(mc) mc:hireWorker(1) end)
    local ev = W.sent[1]
    local _, faults = deliver(ev, FROM_FARM1)
    T.eq("E1 a client of farm 1 hires for its own farm through its own event: the worker joins, farm 1 charged once",
        tostring(ev and ev.farmId) .. "/" .. rosterSize() .. "/" .. charges() .. "/" .. faults, "1/1/1-/0")
    asClient(2, function(mc) WCNetwork_SendCommand(WCCommand.HIRE, 0, 1, "", 1) end)
    deliver(W.sent[2], FROM_FARM2)
    T.eq("E2 a client of farm 2 naming farm 1 is refused, the mismatch logged", rosterSize() .. "/" .. charges() .. "/" .. warned("names farm 1 but is farm 2"), "1/1-/1")
    asClient(2, function(mc) mc:hireWorker(1) end)
    deliver(W.sent[3], FROM_FARM2)
    T.eq("E3 a client of farm 2 hiring for its own farm is charged to farm 2", rosterSize() .. "/" .. charges(), "2/1-,2-")
    asClient(1, function(mc) mc:hireWorker(1) end)
    deliver(W.sent[4], UNPLAYERED)
    T.eq("E4 a connection with no player record is refused", rosterSize() .. "/" .. charges() .. "/" .. warned("the sender has no farm"), "2/1-,2-/1")
    asClient(0, function(mc) WCNetwork_SendCommand(WCCommand.HIRE, 0, 1, "", 2) end)
    deliver(W.sent[5], FROM_SPECTATOR)
    T.eq("E5 a spectator's record (farm 0) is refused even when it names a real farm", rosterSize() .. "/" .. charges(), "2/1-,2-")
    local uuid = firstUuid()
    asClient(2, function(mc) mc:fireWorker(uuid) end)
    deliver(W.sent[6], FROM_FARM2)
    T.eq("E6 a fire from farm 2's client is charged to farm 2 (severance)", rosterSize() .. "/" .. charges(), "1/1-,2-,2-")
    W.ms:fireWorker(firstUuid())
    T.eq("E7 the host's own fire applies locally for its own farm, sending nothing", rosterSize() .. "/" .. charges() .. "/" .. #W.sent, "0/1-,2-,2-,1-/6")
    -- A wire farm of 0 is not "the sender's": the writer's billing fallback would have
    -- turned it into the HOST's farm. The sender's record decides.
    asClient(2, function(mc) WCNetwork_SendCommand(WCCommand.HIRE, 0, 1, "", 0) end)
    deliver(W.sent[7], FROM_FARM2)
    T.eq("E8 a client of farm 2 whose event carries farm 0 is charged to farm 2, never to the host's farm through the billing fallback", rosterSize() .. "/" .. charges(), "1/1-,2-,2-,1-,2-")
end)

T.summary()

--!load: tools/test/lua/f201_model_binding.lua, src/WorkerContextInput.lua, src/WorkerManager.lua
-- RSF-F201, WorkerCosts WC_OPEN_ROSTER through the REAL WorkerContextInput +
-- WorkerManager.installRosterInput / catchUpRosterInput / update / delete on a
-- minimal manager instance. Witnesses: a VEHICLE reconcile leaves the PLAYER id
-- intact (the old hook cleared both on every seat change); a complete set opens
-- no begin/end; catch-up is a no-op without a PLAYER context; delete retires
-- without restoring the predecessors. Model binding, not the native InputBinding.

local noop = function() end
local b = F201Model.installEngine({ "WC_OPEN_ROSTER" })
local nativeCalls, nativeEnds = 0, 0
PlayerInputComponent.registerActionEvents = function() nativeCalls = nativeCalls + 1 end
local nativePlayer = PlayerInputComponent.registerActionEvents
local nativeEnd = b.endActionEventsModification
b.endActionEventsModification = function(self, ...) nativeEnds = nativeEnds + 1; return nativeEnd(self, ...) end
local nativeVehicle = b.endActionEventsModification

local mission = { getIsClient = function() return true end, getIsServer = function() return true end }
g_currentMission = mission
local panelToggles = 0
local wm = setmetatable({ rosterPanel = { toggle = function() panelToggles = panelToggles + 1 end, update = noop, delete = noop },
                          mission = mission }, { __index = WorkerManager })
g_WorkerManager = wm

-- GROUP A: install + activate
wm:installRosterInput(mission)
local wPlayer, wVehicle = PlayerInputComponent.registerActionEvents, InputBinding.endActionEventsModification
T.ok("F201 WC A1 PLAYER wrapper installed", wPlayer ~= nativePlayer)
T.ok("F201 WC A2 VEHICLE wrapper installed", wVehicle ~= nativeVehicle)
local record = WorkerManager._f201Input
T.eq("F201 WC A3 record on the class table is active", record.active, true)
T.eq("F201 WC A4 owner bound", record.owner, wm)
wm:installRosterInput(mission)
T.eq("F201 WC A5 second install stacks nothing", PlayerInputComponent.registerActionEvents, wPlayer)

-- GROUP B: PLAYER then VEHICLE, distinct identities, PLAYER survives the cab
wPlayer({ player = { isOwner = true } })
T.eq("F201 WC B1 one PLAYER registration", b.attempts, 1)
local pid = wm.rosterPlayerEventId
T.ok("F201 WC B2 player handle stored", pid ~= nil)
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 WC B3 one VEHICLE registration", b.attempts, 2)
T.ok("F201 WC B4 vehicle handle stored", wm.rosterVehicleEventId ~= nil)
T.ok("F201 WC B5 identities differ", wm.rosterVehicleEventId ~= pid)
T.ok("F201 WC B6 PLAYER event still resident after the VEHICLE reconcile", b.events[pid] ~= nil)
T.eq("F201 WC B7 player handle untouched", wm.rosterPlayerEventId, pid)
local endsBefore, begunBefore = nativeEnds, b.begun
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 WC B8 complete set: no extra bracket", b.begun, begunBefore + 1)
T.eq("F201 WC B9 complete set: only the engine close reached the predecessor", nativeEnds, endsBefore + 1)
T.eq("F201 WC B10 no registration spent", b.attempts, 2)

-- GROUP C: seat change (cab rebuilt), update resets admission, PLAYER intact
b:deleteContext("VEHICLE")
wm:update(16)
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 WC C1 rebuilt cab registers once", b.attempts, 3)
T.ok("F201 WC C2 PLAYER event still resident", b.events[pid] ~= nil)
T.eq("F201 WC C3 player handle still the same", wm.rosterPlayerEventId, pid)
local ev = b:first("VEHICLE", "WC_OPEN_ROSTER")
ev.callback(ev.targetObject, ev.actionName, 1)
T.eq("F201 WC C4 cab key reaches the roster panel", panelToggles, 1)
T.eq("F201 WC C5 cab row hidden as before", ev.displayIsVisible, false)

-- GROUP D: catch-up is a no-op without a PLAYER context, recovers a lost id with one
b:deleteContext("PLAYER")
wm:update(16)
wm:catchUpRosterInput()
T.eq("F201 WC D1 no PLAYER context: nothing registered", b.attempts, 3)
b:context("PLAYER")
wm:catchUpRosterInput()
T.eq("F201 WC D2 PLAYER context present: one registration", b.attempts, 4)
wm.rosterPlayerEventId = nil
wm:update(16)
wm:catchUpRosterInput()
T.ok("F201 WC D3 lost id recovered from the live event", wm.rosterPlayerEventId ~= nil)
T.eq("F201 WC D4 without a registration", b.attempts, 4)

-- GROUP E: delete retires without restoring
wm:delete()
T.eq("F201 WC E1 record inactive", record.active, false)
T.eq("F201 WC E2 PLAYER wrapper not restored", PlayerInputComponent.registerActionEvents, wPlayer)
T.eq("F201 WC E3 VEHICLE wrapper not restored", InputBinding.endActionEventsModification, wVehicle)
panelToggles = 0
ev.callback(ev.targetObject, ev.actionName, 1)
T.eq("F201 WC E4 retired target forwards nothing", panelToggles, 0)
b:deleteContext("VEHICLE")
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 WC E5 retired owner registers nothing", b.attempts, 4)

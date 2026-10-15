--!load: src/settings/Settings.lua, src/WorkerSystem.lua
-- WC sleep/salary dialog: entry-point bar.
--
-- Entry points under test, production's real functions:
--   WorkerSystem:triggerMonthlySalaryDialog(month)  -- issues the monthly bill
--   WorkerSystem:update(dt)                         -- per-frame tick
--
-- Modelled engine surface (not available in this harness):
--   g_sleepManager   - a table with getIsSleeping() returning a flag the row sets
--   g_gui            - a table with showDialog(name) recording every call
--   g_client         - truthy only; the real client object is never touched
--   g_wcSalaryDialog - a table with setData(...) recording its arguments
--   WCSalaryDialog   - a table carrying CLASS_NAME, as the real dialog class does
--   g_currentMission - minimal: environment.currentYear only. No aiSystem (so the
--                      real getActiveWorkers() returns {}), no currentDay/dayTime
--                      (so the real consumeInGameMs()/onDayChange() are no-ops),
--                      and no isMissionStarted = true (so the real checkMonthEnd()
--                      returns immediately and never re-triggers a bill from
--                      inside update() -- each row drives triggerMonthlySalaryDialog
--                      itself, exactly once, so the dialog-count assertions are
--                      unambiguous). addMoney is mocked only for S8, recording
--                      each call.
--   Logging          - info/warning/error no-ops, same as the existing F223 bar.
--
-- The bill itself (entries/total/month) comes from the real _freezeMonthlyBill and
-- _billEntries, fed by one real chargeWage accrual call, so every assertion below
-- compares against a production-computed bill, not a fixture-invented one.

T.ok("entry bar: actual WorkerSystem module loaded", type(WorkerSystem) == "table")
T.ok("entry bar: actual Settings module loaded", type(Settings) == "table")
if type(WorkerSystem) ~= "table" or type(Settings) ~= "table" then
    T.summary()
    return
end

local savedMission, savedSleep, savedGui, savedClient, savedWcSalaryDialog, savedWCSalaryDialogClass, savedLogging =
    g_currentMission, g_sleepManager, g_gui, g_client, g_wcSalaryDialog, WCSalaryDialog, Logging

Logging = { info = function() end, warning = function() end, error = function() end }

local function newMission()
    return {
        -- isMissionStarted deliberately absent (nil): checkMonthEnd() returns
        -- immediately (WorkerSystem.lua:1069), so update() never re-issues a bill
        -- on its own; only our explicit triggerMonthlySalaryDialog calls do.
        environment = { currentYear = 1 },
        addMoney = function() end,
    }
end

local function newShowDialogRecorder()
    local calls = {}
    return calls, function(_self, name) calls[#calls + 1] = name end
end

local function newSetDataRecorder()
    local calls = {}
    return calls, function(_self, entries, total, month, isPenalty, payCb, declineCb)
        calls[#calls + 1] = {
            entries = entries, total = total, month = month,
            isPenalty = isPenalty, pay = payCb, decline = declineCb,
        }
    end
end

local function newSettings()
    local s = Settings.new(nil)
    s.enabled = true
    s.debugMode = false
    s.monthlySalaryEnabled = true
    s.showNotifications = false
    return s
end

-- One real accrual (farm 1, worker "Ann", $100) via the real chargeWage, so the
-- frozen bill that triggerMonthlySalaryDialog builds is a production bill.
local function newAccruedSystem(settings)
    local ws = WorkerSystem.new(settings, nil)
    ws:chargeWage("w1", "Ann", 100, "fixture", true, 1)
    return ws
end

------------------------------------------------------------------
-- S1-S4, S8: one continuous asleep -> wake -> settle -> pay flow.
------------------------------------------------------------------
do
    g_currentMission = newMission()
    local sleeping = true
    g_sleepManager = { getIsSleeping = function() return sleeping end }
    local guiCalls, showDialogFn = newShowDialogRecorder()
    g_gui = { showDialog = showDialogFn }
    g_client = true
    local setDataCalls, setDataFn = newSetDataRecorder()
    g_wcSalaryDialog = { setData = setDataFn }
    WCSalaryDialog = { CLASS_NAME = "WCSalaryDialog" }

    local settings = newSettings()
    local ws = newAccruedSystem(settings)
    ws.isInitialized = true

    -- S1: trigger the monthly dialog while asleep.
    ws:triggerMonthlySalaryDialog(3)
    T.eq("S1 asleep: showDialog is called 0 times", #guiCalls, 0)
    T.ok("S1 asleep: pendingSalary is set", ws.pendingSalary ~= nil)
    local billId = ws.pendingSalary and ws.pendingSalary.billId
    local pendingTotal = ws.pendingSalary and ws.pendingSalary.total
    T.ok("S1 asleep: pendingSalary carries a bill id", billId ~= nil)
    T.eq("S1 asleep: pendingSalary total is the bill's 100", pendingTotal, 100)
    T.ok("S1 asleep: deferredSalaryDialog is held", ws.deferredSalaryDialog ~= nil)
    T.eq("S1 asleep: held entries are the same entries as the bill",
        ws.deferredSalaryDialog and ws.deferredSalaryDialog.entries,
        ws.pendingSalary and ws.pendingSalary.entries)
    T.eq("S1 asleep: held total equals the bill's total",
        ws.deferredSalaryDialog and ws.deferredSalaryDialog.total, pendingTotal)
    T.eq("S1 asleep: held month equals the bill's month",
        ws.deferredSalaryDialog and ws.deferredSalaryDialog.month,
        ws.pendingSalary and ws.pendingSalary.month)

    -- S2: three update() calls while still asleep.
    ws:update(16)
    ws:update(16)
    ws:update(16)
    T.eq("S2 still asleep: showDialog is still called 0 times", #guiCalls, 0)
    T.ok("S2 still asleep: the held dialog is still held", ws.deferredSalaryDialog ~= nil)

    -- S3: wake up, one update() call.
    sleeping = false
    ws:update(16)
    T.eq("S3 wake: showDialog is called exactly once", #guiCalls, 1)
    T.eq("S3 wake: showDialog is called with WCSalaryDialog.CLASS_NAME",
        guiCalls[1], WCSalaryDialog.CLASS_NAME)
    T.eq("S3 wake: setData is called exactly once", #setDataCalls, 1)
    T.eq("S3 wake: setData entries equal the bill's entries",
        setDataCalls[1] and setDataCalls[1].entries, ws.pendingSalary and ws.pendingSalary.entries)
    T.eq("S3 wake: setData total equals the bill's total",
        setDataCalls[1] and setDataCalls[1].total, pendingTotal)
    T.eq("S3 wake: setData month equals the bill's month", setDataCalls[1] and setDataCalls[1].month, 3)
    T.eq("S3 wake: deferredSalaryDialog is nil", ws.deferredSalaryDialog, nil)

    -- S4: two more update() calls while awake; must not repeat.
    ws:update(16)
    ws:update(16)
    T.eq("S4 no repeat: showDialog is still called exactly once (not twice)", #guiCalls, 1)

    -- S8: the pay path still binds to this exact bill.
    g_currentMission.addMoney = function(_self, amount, farmId)
        g_currentMission._lastPay = { amount = amount, farmId = farmId }
    end
    local payCb = setDataCalls[1] and setDataCalls[1].pay
    T.ok("S8 pay path: the Pay callback setData received is a function", type(payCb) == "function")
    T.ok("S8 pay path: the bill is present in salaryBills before paying",
        billId ~= nil and ws.salaryBills[billId] ~= nil)
    if type(payCb) == "function" then
        payCb()
    end
    T.eq("S8 pay path: pendingSalary is cleared after Pay", ws.pendingSalary, nil)
    T.eq("S8 pay path: the paid bill is retired (fully resolved, dropped from salaryBills)",
        billId ~= nil and ws.salaryBills[billId], nil)
    T.ok("S8 pay path: addMoney moved exactly -100 for farm 1",
        g_currentMission._lastPay ~= nil
        and g_currentMission._lastPay.amount == -100
        and g_currentMission._lastPay.farmId == 1)
end

------------------------------------------------------------------
-- S5: awake path unchanged.
------------------------------------------------------------------
do
    g_currentMission = newMission()
    g_sleepManager = { getIsSleeping = function() return false end }
    local guiCalls, showDialogFn = newShowDialogRecorder()
    g_gui = { showDialog = showDialogFn }
    g_client = true
    local setDataCalls, setDataFn = newSetDataRecorder()
    g_wcSalaryDialog = { setData = setDataFn }
    WCSalaryDialog = { CLASS_NAME = "WCSalaryDialog" }

    local settings = newSettings()
    local ws = newAccruedSystem(settings)
    ws.isInitialized = true

    ws:triggerMonthlySalaryDialog(2)
    T.eq("S5 awake: showDialog is called exactly once immediately", #guiCalls, 1)
    T.eq("S5 awake: nothing is held", ws.deferredSalaryDialog, nil)
end

------------------------------------------------------------------
-- S6: no sleep manager at all.
------------------------------------------------------------------
do
    g_currentMission = newMission()
    g_sleepManager = nil
    local guiCalls, showDialogFn = newShowDialogRecorder()
    g_gui = { showDialog = showDialogFn }
    g_client = true
    local setDataCalls, setDataFn = newSetDataRecorder()
    g_wcSalaryDialog = { setData = setDataFn }
    WCSalaryDialog = { CLASS_NAME = "WCSalaryDialog" }

    local settings = newSettings()
    local ws = newAccruedSystem(settings)
    ws.isInitialized = true

    ws:triggerMonthlySalaryDialog(7)
    T.eq("S6 no sleep manager: showDialog is called exactly once immediately", #guiCalls, 1)
    T.eq("S6 no sleep manager: nothing is held", ws.deferredSalaryDialog, nil)
end

------------------------------------------------------------------
-- S7: disabled / not initialized. The held-dialog check must run BEFORE
-- update()'s settings.enabled / isInitialized early return.
------------------------------------------------------------------
do
    g_currentMission = newMission()
    local sleeping = true
    g_sleepManager = { getIsSleeping = function() return sleeping end }
    local guiCalls, showDialogFn = newShowDialogRecorder()
    g_gui = { showDialog = showDialogFn }
    g_client = true
    local setDataCalls, setDataFn = newSetDataRecorder()
    g_wcSalaryDialog = { setData = setDataFn }
    WCSalaryDialog = { CLASS_NAME = "WCSalaryDialog" }

    local settings = newSettings()
    local ws = newAccruedSystem(settings)
    ws.isInitialized = true

    ws:triggerMonthlySalaryDialog(5)
    T.ok("S7 setup: the dialog is held while asleep", ws.deferredSalaryDialog ~= nil)

    -- Disable AFTER the bill is held, then wake: the new block must still fire
    -- ahead of the "not self.settings.enabled or not self.isInitialized" return.
    settings.enabled = false
    ws.isInitialized = false
    sleeping = false
    ws:update(16)
    T.eq("S7 disabled/uninitialized: the held dialog is still shown on the first awake update",
        #guiCalls, 1)
    T.eq("S7 disabled/uninitialized: deferredSalaryDialog is cleared", ws.deferredSalaryDialog, nil)
end

g_currentMission, g_sleepManager, g_gui, g_client, g_wcSalaryDialog, WCSalaryDialog, Logging =
    savedMission, savedSleep, savedGui, savedClient, savedWcSalaryDialog, savedWCSalaryDialogClass, savedLogging

T.summary()

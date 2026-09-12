--!load: src/settings/Settings.lua, src/WorkerSystem.lua
-- RSF-F223 v0.2 / F225: payroll owner contract, Stage 3 proof DRAFT.
-- Authoring only. This file has NOT been run as part of its drafting task.
--
-- Design input:
-- E:/FS25 workspaceC/Engineering Office/mods/FS25_WorkerCosts/build-briefs/
-- RSF-F223-payroll-calendar-and-farm-bills-IMPLEMENTATION-BRIEF.md (v0.2).
-- Source evidence:
-- E:/FS25 workspaceC/Crew Office/Returns/Source Reads/
-- C3-WORKER-BILL-CONTRACT-2026-09-11.md.
--
-- GROUP A calls the actual loaded WorkerSystem methods on controlled fixtures.
-- It witnesses the current short-month miss and shared-worker farm pooling.
-- These are defect witnesses, NOT assertions that the repaired source is built.
-- When the repair changes them, replace the witnesses with production regression
-- calls. Do not loosen a failed witness merely to keep this draft green.
--
-- GROUPS B-D are small REFERENCE CONTRACT MODELS, not WorkerCosts implementation.
-- Calendar, farms, bill state and payment outcomes are synthetic and XML-free.
-- Amount fixtures are already-valued work/final bill amounts. No model calculates
-- a new wage, penalty, fee or refund. Existing Pay/Escape, explicit Decline and
-- pricing policy remain with the owner; these models begin after Pay was chosen.
-- An actor returning "applied" below is a synthetic confirmed outcome, NOT the
-- native addMoney return contract. No native transfer acknowledgement is proved.
--
-- Not covered: native saves, migration of a real XML file, lost historical farm
-- shares, UI/permissions, real multiplayer, Time Guard delivery, live job timing,
-- the final getPayrollObligations schema, or gameplay. No independent review claim.
--
-- Load dependency read: both modules only need the prelude's Class at top level.
-- The logger below is a test-local fixture for Settings.new, not a prelude edit.

T.ok("F223 A0 actual Settings module loaded", type(Settings) == "table")
T.ok("F223 A0 actual WorkerSystem module loaded", type(WorkerSystem) == "table")
if type(Settings) ~= "table" or type(WorkerSystem) ~= "table" then
    T.summary()
    return
end

-- GROUP A: REAL SOURCE, mocked calendar, logger and money destination only.
local savedMission, savedLogging, savedFarmManager = g_currentMission, Logging, FarmManager
Logging = { info = function() end, warning = function() end, error = function() end }
FarmManager = { SPECTATOR_FARM_ID = 0, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }

local sourceSettings = Settings.new(nil)
sourceSettings.enabled = true
sourceSettings.debugMode = false
sourceSettings.monthlySalaryEnabled = true

local sourceMoneyCalls = 0
g_currentMission = {
    environment = {
        currentYear = 1, currentPeriod = 1, currentDay = 3,
        currentMonotonicDay = 3, currentDayInPeriod = 3, daysPerPeriod = 3,
    },
    getFarmId = function() return 9 end,
    getIsServer = function() return true end,
    addMoney = function() sourceMoneyCalls = sourceMoneyCalls + 1 end,
}

-- REPAIRED REGRESSIONS (replacing the pre-repair defect witnesses A1/A2/A8-A10).
-- F130/F223 changed checkMonthEnd to fire on the native last day of any month length
-- and chargeWage to accrue per farm, so the old witnesses must assert the fixed
-- behaviour, not the defect (per the file header: do not loosen, re-point).
local sourceCalendar = WorkerSystem.new(sourceSettings, nil)
local sourceIssues, sourceIssuedMonth = 0, nil
-- Replace only the downstream UI/mutating issue action. checkMonthEnd is REAL.
sourceCalendar.triggerMonthlySalaryDialog = function(_, month)
    sourceIssues = sourceIssues + 1
    sourceIssuedMonth = month
end
sourceCalendar:checkMonthEnd()
T.eq("F223 A1 REPAIRED three-day month issues its bill on the real last day", sourceIssues, 1)
T.eq("F223 A2 REPAIRED short-month issuance records the native ordinal", sourceCalendar.lastIssuedOrdinal, 1 * 12 + 1 - 1)
T.eq("F223 A2b REPAIRED issue receives the actual period", sourceIssuedMonth, 1)

-- The SAME (year, period) re-checked at a different month length does not re-issue.
g_currentMission.environment.currentDay = 28
g_currentMission.environment.currentMonotonicDay = 28
g_currentMission.environment.currentDayInPeriod = 28
g_currentMission.environment.daysPerPeriod = 28
sourceCalendar:checkMonthEnd()
T.eq("F223 A3 REPAIRED repeated same-period check issues once", sourceIssues, 1)

-- A later period issues again (the ordinal marker is not a one-shot lock).
g_currentMission.environment.currentPeriod = 2
g_currentMission.environment.currentDayInPeriod = 28
g_currentMission.environment.daysPerPeriod = 28
sourceCalendar:checkMonthEnd()
T.eq("F223 A4 REPAIRED a new period issues again", sourceIssues, 2)
T.eq("F223 A5 REPAIRED new issue carries the new period", sourceIssuedMonth, 2)
sourceCalendar:checkMonthEnd()
T.eq("F223 A6 REPAIRED repeated new-period check issues once", sourceIssues, 2)

-- chargeWage now keeps each farm's share of a shared worker distinct (no pooling).
local sourcePayroll = WorkerSystem.new(sourceSettings, nil)
local sharedWorker = 77
T.eq("F223 A7 REPAIRED first farm measured wage is accepted",
    sourcePayroll:chargeWage(sharedWorker, "Shared worker", 100, "fixture", true, 1), true)
T.eq("F223 A8 REPAIRED second farm measured wage is accepted",
    sourcePayroll:chargeWage(sharedWorker, "Shared worker", 200, "fixture", true, 2), true)
local farm1Book, farm2Book = sourcePayroll.monthlyCosts[1], sourcePayroll.monthlyCosts[2]
T.ok("F223 A9 REPAIRED farm one holds its own worker entry", farm1Book ~= nil and farm1Book["77"] ~= nil)
T.ok("F223 A10 REPAIRED farm two holds its own worker entry", farm2Book ~= nil and farm2Book["77"] ~= nil)
T.near("F223 A11 REPAIRED farm one keeps exactly its 100", farm1Book and farm1Book["77"] and farm1Book["77"].amount, 100, 0)
T.near("F223 A12 REPAIRED farm two keeps exactly its 200", farm2Book and farm2Book["77"] and farm2Book["77"].amount, 200, 0)
T.eq("F223 A13 REPAIRED no pooled entry lives under the worker id", sourcePayroll.monthlyCosts[sharedWorker], nil)
sourcePayroll:chargeWage(78, "Separate worker", 40, "fixture", true, 2)
T.near("F223 A14 REPAIRED a different worker retains its own farm-two amount",
    sourcePayroll.monthlyCosts[2] and sourcePayroll.monthlyCosts[2]["78"] and sourcePayroll.monthlyCosts[2]["78"].amount, 40, 0)
T.eq("F223 A15 REPAIRED monthly accrual fixtures never invoke addMoney", sourceMoneyCalls, 0)

g_currentMission, Logging, FarmManager = savedMission, savedLogging, savedFarmManager

-- GROUP A2: REAL-SOURCE regression of the repaired bill lifecycle (freeze -> pay) and
-- the pure getPayrollObligations reader. Drives the actual WorkerSystem methods.
do
    local savedM, savedL, savedFM = g_currentMission, Logging, FarmManager
    Logging = { info = function() end, warning = function() end, error = function() end }
    FarmManager = { SPECTATOR_FARM_ID = 0, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }
    local moves = {}
    g_currentMission = {
        environment = { currentYear = 1, currentPeriod = 3, currentDay = 3,
            currentMonotonicDay = 3, currentDayInPeriod = 3, daysPerPeriod = 3, dayTime = 0 },
        getFarmId = function() return 1 end,
        getIsServer = function() return true end,
        addMoney = function(_, amount, farmId) moves[#moves + 1] = { amount = amount, farmId = farmId } end,
    }

    local s = Settings.new(nil)
    s.enabled = true; s.debugMode = false; s.monthlySalaryEnabled = true; s.showNotifications = false
    local ws = WorkerSystem.new(s, nil)
    ws:chargeWage("w1", "Ann", 100, "fixture", true, 1)
    ws:chargeWage("w2", "Bob", 200, "fixture", true, 2)

    -- Pre-freeze: unbilled measured work is placed once at the next payable last day
    -- (FIRST_OWNER_CHECK midnight), and the reader is PARTIAL (future crew work is not
    -- estimated). Mid-period horizon (dayInPeriod 1 of 3) -> offset 2 days.
    local midHorizon = { asOf = { monotonicDay = 3, timeOfDayMs = 0 },
        horizonEnd = { monotonicDay = 6, timeOfDayMs = 0 }, daysPerPeriod = 3, dayInPeriod = 1 }
    local pvPre = ws:getPayrollObligations(1, midHorizon)
    T.near("F223 A2-pre1 unbilled amount is farm one's own 100", pvPre.events[1] and pvPre.events[1].fixedAmount, 100, 0)
    T.eq("F223 A2-pre2 unbilled is placed at the next last day", pvPre.events[1] and pvPre.events[1].dueDay, 5)
    T.eq("F223 A2-pre3 unbilled due time is midnight", pvPre.events[1] and pvPre.events[1].dueTimeMs, 0)
    T.eq("F223 A2-pre4 unbilled timing basis is FIRST_OWNER_CHECK", pvPre.events[1] and pvPre.events[1].timingBasis, "FIRST_OWNER_CHECK")
    T.eq("F223 A2-pre5 reader is PARTIAL when future continuation is unestimated", pvPre.status, "PARTIAL")

    local bill = ws:_freezeMonthlyBill(3)
    T.ok("F223 A2-1 freeze creates a bill with two per-farm parts", bill ~= nil and #bill.parts == 2)
    T.ok("F223 A2-2 accrual is cleared once frozen", not ws:_hasAccrual())

    local horizon = { asOf = { monotonicDay = 3, timeOfDayMs = 0 },
        horizonEnd = { monotonicDay = 6, timeOfDayMs = 0 }, daysPerPeriod = 3, dayInPeriod = 3 }
    local pv1 = ws:getPayrollObligations(1, horizon)
    T.eq("F223 A2-3 reader reports OK with an issued bill", pv1.status, "OK")
    T.eq("F223 A2-4 farm one has exactly one due-now event", #pv1.events, 1)
    T.near("F223 A2-5 farm one due-now amount is its own 100", pv1.events[1].fixedAmount, 100, 0)
    T.eq("F223 A2-6 issued bill is due at asOf day", pv1.events[1].dueDay, 3)
    T.eq("F223 A2-7 issued bill timing basis is due-now", pv1.events[1].timingBasis, "ISSUED_DUE_NOW")
    T.near("F223 A2-8 farm two due-now amount is its own 200",
        ws:getPayrollObligations(2, horizon).events[1].fixedAmount, 200, 0)
    local pvOther = ws:getPayrollObligations(5, horizon)
    T.eq("F223 A2-9 an uninvolved farm gets no payroll event", #pvOther.events, 0)

    -- Pay the frozen bill by its exact id.
    ws.pendingSalary = { billId = bill.id, month = 3 }
    ws:executeMonthlySalaryPayment()
    local paid = {}
    for _, m in ipairs(moves) do paid[m.farmId] = (paid[m.farmId] or 0) + m.amount end
    T.near("F223 A2-10 farm one charged exactly -100", paid[1], -100, 0)
    T.near("F223 A2-11 farm two charged exactly -200", paid[2], -200, 0)
    T.eq("F223 A2-12 a fully paid bill is retired", ws.salaryBills[bill.id], nil)
    T.eq("F223 A2-13 reader reports nothing after payment", #ws:getPayrollObligations(1, horizon).events, 0)

    g_currentMission, Logging, FarmManager = savedM, savedL, savedFM
end

-- GROUP A3: REAL-SOURCE regression of Decline — unpaid base rows return to accrual
-- (pre-penalty), and the next bill applies the floor(base*1.20) penalty exactly once.
do
    local savedM, savedL, savedFM = g_currentMission, Logging, FarmManager
    Logging = { info = function() end, warning = function() end, error = function() end }
    FarmManager = { SPECTATOR_FARM_ID = 0, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }
    g_currentMission = {
        environment = { currentYear = 1, currentPeriod = 3, currentDay = 3,
            currentMonotonicDay = 3, currentDayInPeriod = 3, daysPerPeriod = 3, dayTime = 0 },
        getFarmId = function() return 1 end,
        getIsServer = function() return true end,
        addMoney = function() end,
    }
    local s = Settings.new(nil)
    s.enabled = true; s.debugMode = false; s.monthlySalaryEnabled = true; s.showNotifications = false
    local ws = WorkerSystem.new(s, nil)
    ws:chargeWage("w1", "Ann", 100, "fixture", true, 1)
    local bill = ws:_freezeMonthlyBill(3)
    ws.pendingSalary = { billId = bill.id, total = 100, month = 3 }
    ws:declineMonthlySalary()
    T.ok("F223 A3-1 decline sets the next-bill penalty flag", ws.declinedLastMonth == true)
    T.ok("F223 A3-2 unpaid base rows return to live accrual", ws:_hasAccrual())
    T.near("F223 A3-3 returned amount is the pre-penalty base",
        ws.monthlyCosts[1] and ws.monthlyCosts[1]["w1"] and ws.monthlyCosts[1]["w1"].amount, 100, 0)
    T.eq("F223 A3-4 the declined bill is retired", ws.salaryBills[bill.id], nil)
    local bill2 = ws:_freezeMonthlyBill(4)
    T.near("F223 A3-5 next bill applies floor(base*1.20) once", bill2.parts[1].final, 120, 0)
    T.near("F223 A3-6 next bill keeps the base pre-penalty", bill2.parts[1].base, 100, 0)
    T.ok("F223 A3-7 penalty flag clears after it is baked into a bill", ws.declinedLastMonth == false)
    g_currentMission, Logging, FarmManager = savedM, savedL, savedFM
end

-- GROUP B: REFERENCE ONLY. Last-day issuance on a synthetic 12-period calendar.
-- This deliberately does not replace the real native/TG scheduling proof.
local MODEL_PERIODS_IN_YEAR = 12
local function newOwner()
    return { accrued = {}, bills = {}, lastIssuedOrdinal = nil, serial = 0 }
end

local function accrue(owner, farmId, workerId, amount)
    owner.accrued[farmId] = owner.accrued[farmId] or {}
    local key = tostring(workerId)
    owner.accrued[farmId][key] = (owner.accrued[farmId][key] or 0) + amount
end

local function sumEntries(entries)
    local total = 0
    for _, amount in pairs(entries or {}) do total = total + amount end
    return total
end

local function issueOnLastDay(owner, calendar)
    if calendar.dayInPeriod ~= calendar.daysPerPeriod then return nil end
    local ordinal = calendar.year * MODEL_PERIODS_IN_YEAR + calendar.period - 1
    if owner.lastIssuedOrdinal ~= nil and ordinal <= owner.lastIssuedOrdinal then return nil end
    owner.lastIssuedOrdinal = ordinal
    owner.serial = owner.serial + 1
    local bill = { id = owner.serial, quotedByFarm = {}, remainingByFarm = {} }
    for farmId, entries in pairs(owner.accrued) do
        local amount = sumEntries(entries)
        if amount > 0 then
            bill.quotedByFarm[farmId] = amount
            bill.remainingByFarm[farmId] = amount
        end
    end
    owner.accrued = {} -- Cut only this snapshot; later work starts separately.
    owner.bills[bill.id] = bill
    return bill
end

for _, days in ipairs({ 1, 3, 28 }) do
    local owner = newOwner()
    accrue(owner, 1, 10, 90)
    local issued = 0
    for day = 1, days do
        local calendar = { year = 2, period = 12, dayInPeriod = day, daysPerPeriod = days }
        local bill = issueOnLastDay(owner, calendar)
        if bill then issued = issued + 1 end
        T.eq("F223 B1 MODEL D=" .. days .. " day=" .. day .. " issues only on last day",
            bill ~= nil, day == days)
        T.eq("F223 B2 MODEL D=" .. days .. " day=" .. day .. " repeated check cannot issue again",
            issueOnLastDay(owner, calendar), nil)
    end
    T.eq("F223 B3 MODEL D=" .. days .. " exactly one issuance in the period", issued, 1)
    accrue(owner, 1, 10, 25)
    local nextBill = issueOnLastDay(owner,
        { year = 3, period = 1, dayInPeriod = days, daysPerPeriod = days })
    T.ok("F223 B4 MODEL D=" .. days .. " year rollover allows next due period", nextBill ~= nil)
    T.eq("F223 B5 MODEL D=" .. days .. " rollover quotes only later work",
        nextBill and nextBill.quotedByFarm[1], 25)
    T.eq("F223 B6 MODEL D=" .. days .. " old period cannot replay after rollover",
        issueOnLastDay(owner, { year = 2, period = 12, dayInPeriod = days, daysPerPeriod = days }), nil)
end

-- First observation can be on the due day: no simulated prior tick is required.
local loadedDayOwner = newOwner()
accrue(loadedDayOwner, 2, 10, 17)
local loadedDayBill = issueOnLastDay(loadedDayOwner,
    { year = 4, period = 7, dayInPeriod = 3, daysPerPeriod = 3 })
T.eq("F223 B7 MODEL first authoritative observation on due day can issue",
    loadedDayBill and loadedDayBill.quotedByFarm[2], 17)

-- GROUP C: REFERENCE ONLY. Immutable quotes and per-farm payment consumption.
-- This is an in-memory state cut, not a native transaction/acknowledgement API.
local function copyAmounts(amounts)
    local copy = {}
    for farmId, amount in pairs(amounts) do copy[farmId] = amount end
    return copy
end

local function readBill(owner, billId)
    local bill = owner.bills[billId]
    if not bill then return nil end
    return { id = bill.id, quotedByFarm = copyAmounts(bill.quotedByFarm),
        remainingByFarm = copyAmounts(bill.remainingByFarm) }
end

local function settleChosenBill(owner, billId, actor)
    local bill = owner.bills[billId]
    if not bill then return 0 end
    local farmIds = {}
    for farmId in pairs(bill.remainingByFarm) do farmIds[#farmIds + 1] = farmId end
    table.sort(farmIds) -- Deliberately exercise first-farm success, later-farm failure.
    local consumed = 0
    for _, farmId in ipairs(farmIds) do
        local amount = bill.remainingByFarm[farmId]
        bill.indeterminate = bill.indeterminate or {}
        if not bill.indeterminate[farmId] then
            local outcome = actor(farmId, amount)
            if outcome == "applied" then
                bill.remainingByFarm[farmId] = nil
                consumed = consumed + amount
            elseif outcome == "indeterminate" then
                bill.indeterminate[farmId] = true
            end
        end
    end
    return consumed
end

local owner = newOwner()
accrue(owner, 1, "same-worker", 100)
accrue(owner, 2, "same-worker", 200)
T.eq("F223 C1 MODEL same worker keeps farm one's amount separate", sumEntries(owner.accrued[1]), 100)
T.eq("F223 C2 MODEL same worker keeps farm two's amount separate", sumEntries(owner.accrued[2]), 200)
local bill = issueOnLastDay(owner, { year = 5, period = 4, dayInPeriod = 3, daysPerPeriod = 3 })
accrue(owner, 1, "same-worker", 55)
T.eq("F223 C3 MODEL later wages do not change the displayed farm-one quote", bill.quotedByFarm[1], 100)
T.eq("F223 C4 MODEL later wages remain separate from the issued bill", sumEntries(owner.accrued[1]), 55)
local read = readBill(owner, bill.id)
read.quotedByFarm[1] = 999
read.remainingByFarm[2] = 0
T.eq("F223 C5 MODEL returned quote cannot mutate owner's frozen amount", bill.quotedByFarm[1], 100)
T.eq("F223 C6 MODEL returned quote cannot erase another farm's debt", bill.remainingByFarm[2], 200)
T.eq("F223 C7 MODEL reading has not consumed later accrued work", sumEntries(owner.accrued[1]), 55)

local cash, attempts, failFarmTwo = { [1] = 1000, [2] = 1000 }, {}, true
local function syntheticActor(farmId, amount)
    attempts[farmId] = (attempts[farmId] or 0) + 1
    if farmId == 2 and failFarmTwo then return "failed" end
    cash[farmId] = cash[farmId] - amount
    return "applied"
end
T.eq("F223 C8 MODEL first attempt consumes only successful farm", settleChosenBill(owner, bill.id, syntheticActor), 100)
T.eq("F223 C9 MODEL successful farm's pending portion is removed", bill.remainingByFarm[1], nil)
T.eq("F223 C10 MODEL failed farm's exact amount remains due", bill.remainingByFarm[2], 200)
T.eq("F223 C11 MODEL failed farm has no synthetic cash movement", cash[2], 1000)
T.eq("F223 C12 MODEL first-farm success preserves newly accrued wages", sumEntries(owner.accrued[1]), 55)
failFarmTwo = false
T.eq("F223 C13 MODEL retry consumes only the retained farm", settleChosenBill(owner, bill.id, syntheticActor), 200)
T.eq("F223 C14 MODEL succeeded farm is not attempted again", attempts[1], 1)
T.eq("F223 C15 MODEL failed then succeeded farm is attempted twice", attempts[2], 2)
T.eq("F223 C16 MODEL farm one's exact charge occurs once", cash[1], 900)
T.eq("F223 C17 MODEL farm two's exact charge occurs once", cash[2], 800)
T.eq("F223 C18 MODEL repeat after payment consumes nothing", settleChosenBill(owner, bill.id, syntheticActor), 0)
T.eq("F223 C19 MODEL completed-bill retry does not call successful farm again", attempts[1], 1)
T.eq("F223 C20 MODEL all payment attempts leave later wages untouched", sumEntries(owner.accrued[1]), 55)
T.eq("F223 C21 MODEL immutable displayed quote survives consumption", bill.quotedByFarm[2], 200)

local unknownOwner = newOwner()
accrue(unknownOwner, 1, 1, 31)
local unknownBill = issueOnLastDay(unknownOwner,
    { year = 1, period = 1, dayInPeriod = 1, daysPerPeriod = 1 })
T.eq("F223 C22 MODEL indeterminate outcome does not count as applied",
    settleChosenBill(unknownOwner, unknownBill.id, function() return "indeterminate" end), 0)
T.eq("F223 C23 MODEL indeterminate amount remains retained", unknownBill.remainingByFarm[1], 31)
local unknownRetryCalls=0
settleChosenBill(unknownOwner, unknownBill.id, function()
    unknownRetryCalls=unknownRetryCalls+1
    return "applied"
end)
T.eq("F223 C24 MODEL unknown cash effect prevents automatic retry",unknownRetryCalls,0)
T.eq("F223 C25 MODEL blocked uncertain amount is not treated as paid",unknownBill.remainingByFarm[1],31)

-- GROUP D: REFERENCE ONLY. Preserve raw legacy facts, never reconstruct shares.
-- Rows below are synthetic decoded records. No XML parser or save/load is tested.
local function recordedRealFarm(farmId)
    return type(farmId) == "number" and farmId > 0 and farmId % 1 == 0
        and farmId ~= 14 and farmId ~= 15
end

local function preserveLegacyRows(rows)
    local retained = { byFarm = {}, unattributed = {}, evidence = {} }
    for _, row in ipairs(rows) do
        local copy = { id = row.id, name = row.name, amount = row.amount,
            recordedFarmId = row.farmId, provenance = "legacy-recorded" }
        retained.evidence[#retained.evidence + 1] = copy
        if recordedRealFarm(row.farmId) then
            retained.byFarm[row.farmId] = retained.byFarm[row.farmId] or {}
            local key = tostring(row.id)
            retained.byFarm[row.farmId][key] = (retained.byFarm[row.farmId][key] or 0) + row.amount
        else
            retained.unattributed[#retained.unattributed + 1] = copy
        end
    end
    return retained
end

local legacy = preserveLegacyRows({
    { id = 42, name = "Recorded worker", amount = 90, farmId = 7 },
    { id = "42", name = "Recorded worker", amount = 10, farmId = 7 },
    { id = 42, name = "Recorded worker", amount = 35, farmId = 2 },
    { id = "missing-owner", name = "Unattributed worker", amount = 70 },
    { id = "invalid-owner", name = "Invalid target", amount = 8, farmId = 15 },
})
T.eq("F223 D1 MODEL recorded target survives without today's assignment", sumEntries(legacy.byFarm[7]), 100)
T.eq("F223 D2 MODEL same worker's separately recorded second farm is retained", sumEntries(legacy.byFarm[2]), 35)
T.eq("F223 D3 MODEL numeric/string worker keys preserve both recorded amounts", legacy.byFarm[7]["42"], 100)
T.eq("F223 D4 MODEL no invented share is assigned to farm one", legacy.byFarm[1], nil)
T.eq("F223 D5 MODEL missing and invalid targets both remain unattributed", #legacy.unattributed, 2)
T.eq("F223 D6 MODEL unattributed amount is not discarded", legacy.unattributed[1].amount, 70)
T.eq("F223 D7 MODEL invalid recorded target remains evidence", legacy.unattributed[2].recordedFarmId, 15)
T.eq("F223 D8 MODEL legacy provenance is explicit", legacy.evidence[1].provenance, "legacy-recorded")
T.eq("F223 D9 MODEL all original rows remain evidence", #legacy.evidence, 5)
local preservedTotal = sumEntries(legacy.byFarm[7]) + sumEntries(legacy.byFarm[2])
for _, row in ipairs(legacy.unattributed) do preservedTotal = preservedTotal + row.amount end
T.near("F223 D10 MODEL attributed plus unattributed total conserves all recorded money",
    preservedTotal, 90 + 10 + 35 + 70 + 8, 0)

-- A single historical row may already contain several farms' work. Its original
-- shares are unknowable here: keep the recorded 300 on its recorded target and
-- preserve the uncertainty, rather than inventing a 150/150 reconstruction.
local mixedLegacy = preserveLegacyRows({
    { id = "pooled-before-save", name = "Old pooled worker", amount = 300, farmId = 1 },
})
T.eq("F223 D11 MODEL a previously pooled row keeps its whole recorded amount", sumEntries(mixedLegacy.byFarm[1]), 300)
T.eq("F223 D12 MODEL a previously pooled row does not create a guessed farm-two share", mixedLegacy.byFarm[2], nil)


-- R1 coexistence: real old hook under an unsupported missing-wage-enum fixture.
-- Normal1.23.1.0 supplies AI; this witnesses the conditional heuristic hazard.
do
    local oldMission, oldTypes, oldLogging = g_currentMission, MoneyType, Logging
    MoneyType={OTHER={name="other"}}
    Logging={info=function()end,warning=function()end,error=function()end}
    local actual=0
    g_currentMission={addMoney=function(_,amount) actual=actual+amount end,
        aiSystem={getActiveJobs=function() return {{}} end}}
    local hook=setmetatable({settings={enabled=true},log=function()end},{__index=WorkerSystem})
    hook:installGameHook()
    g_currentMission:addMoney(-100,1,MoneyType.OTHER)
    T.eq("R1 REPAIRED typed OTHER is forwarded through the captured chain, not swallowed",actual,-100)
    -- Small reference predicate is the owner repair, not a bypassed native call.
    local function shouldSuppress(amount,kind,ai,wage,other)
        if kind~=nil and kind==other then return false end
        return amount<0 and ((ai~=nil and kind==ai) or (wage~=nil and kind==wage))
    end
    T.eq("R1 REFERENCE typed OTHER passes with missing wage enums",shouldSuppress(-100,MoneyType.OTHER,nil,nil,MoneyType.OTHER),false)
    local ai={};T.eq("R1 REFERENCE actual AI wage remains suppressed",shouldSuppress(-100,ai,ai,nil,MoneyType.OTHER),true)
    g_currentMission,MoneyType,Logging=oldMission,oldTypes,oldLogging
end


-- Native conversion preserves bill-part status and identity while retargeting.
do
    local parts={{id="bill1/farm1",farm=1,amount=100,status="PAID"},
                 {id="bill1/farm2",farm=2,amount=200,status="UNPAID"},
                 {id="bill2/farm2",farm=2,amount=30,status="INDETERMINATE"}}
    local map={[2]=1}
    for _,part in ipairs(parts) do part.farm=map[part.farm] or part.farm end
    local due=0
    for _,part in ipairs(parts) do if part.farm==1 and part.status=="UNPAID" then due=due+part.amount end end
    T.eq("R1 merge does not revive an already-paid wage part",due,200)
    T.eq("R1 unknown payment status survives farm remap",parts[3].status,"INDETERMINATE")
    T.eq("R1 remapped bill keeps original identity",parts[2].id,"bill1/farm2")
    for _,part in ipairs(parts) do part.farm=map[part.farm] or part.farm end
    T.eq("R1 repeated map does not create more bill parts",#parts,3)
end

-- R3 REFERENCE: producer date fields, missed checks and a rolling horizon.
-- This models retained bill timing only, not the new native producer/Event/XML.
do
    local function payrollView(owner,env,farmId)
        local day,ms,D=env.currentMonotonicDay,env.dayTime,env.daysPerPeriod
        if type(day)~="number" or day<0 or day%1~=0 or type(ms)~="number"
            or ms~=ms or ms<0 or ms>=86400000 then return nil end
        local result={farmId=farmId,asOf={monotonicDay=day,timeOfDayMs=ms},events={}}
        for id,bill in pairs(owner.bills) do
            local amount=bill.remainingByFarm[farmId] or 0
            if amount>0 then
                result.events[#result.events+1]={source="bill:"..id,
                    dueDay=day,dueTimeMs=ms,amount=amount}
            end
        end
        local amount=sumEntries(owner.accrued[farmId])
        if amount>0 then
            local ordinal=env.currentYear*12+env.currentPeriod-1
            local offset=D-env.currentDayInPeriod
            if offset==0 and owner.lastIssuedOrdinal==ordinal then offset=D end
            result.events[#result.events+1]={source="unbilled",dueDay=day+offset,
                dueTimeMs=offset==0 and ms or 0,amount=amount}
        end
        table.sort(result.events,function(a,b)
            if a.dueDay~=b.dueDay then return a.dueDay<b.dueDay end
            return a.dueTimeMs<b.dueTimeMs
        end)
        return result
    end
    local owner=newOwner()
    accrue(owner,7,"worker",90)
    accrue(owner,8,"other-farm",500)
    local env={currentYear=2,currentPeriod=4,currentDayInPeriod=1,daysPerPeriod=3,
        currentMonotonicDay=40,dayTime=64800000}
    local pending=payrollView(owner,env,7)
    T.eq("R3 producer excludes another farm's unbilled work",pending.events[1].amount,90)
    T.eq("R3 producer copies native dayTime into asOf",pending.asOf.timeOfDayMs,64800000)
    T.eq("R3 missed-check unbilled work stays at next supported last day",pending.events[1].dueDay,42)
    T.eq("R3 future FIRST_OWNER_CHECK event declares midnight",pending.events[1].dueTimeMs,0)
    T.eq("R3 missed check does not create a due-now bill",next(owner.bills),nil)
    T.eq("R3 pure producer read leaves accrued work untouched",sumEntries(owner.accrued[7]),90)
    env.currentDayInPeriod=3;env.currentMonotonicDay=42
    issueOnLastDay(owner,{year=2,period=4,dayInPeriod=3,daysPerPeriod=3})
    accrue(owner,7,"worker",25)
    local late=payrollView(owner,env,7)
    T.eq("R3 issued bill and later unbilled work remain distinct",#late.events,2)
    T.eq("R3 issued unpaid bill is due now",late.events[1].dueDay,42)
    T.eq("R3 due-now time clamps to asOf",late.events[1].dueTimeMs,64800000)
    T.eq("R3 later work is payable at the following last day",late.events[2].dueDay,45)
    T.eq("R3 rolling duration can include two distinct payday events",
        (late.events[2].dueDay-42)*86400000+late.events[2].dueTimeMs-64800000<=3*86400000,true)
    T.eq("R3 one old bill is not counted as later work",late.events[1].amount,90)
    T.eq("R3 later work does not repeat the old bill",late.events[2].amount,25)
    env.dayTime=86400000
    T.eq("R3 producer does not fabricate a day at boundary",payrollView(owner,env,7),nil)
end

T.summary()

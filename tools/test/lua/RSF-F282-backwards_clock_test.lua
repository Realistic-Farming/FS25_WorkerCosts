--!load: tools/test/lua/f282_environment_model.lua, src/settings/Settings.lua, src/WorkerRoster.lua, src/WorkerSystem.lua
-- RSF-F282, WorkerCosts half: a clock set backwards inside one day is not worked time.
-- Before this repair consumeInGameMs read any negative span as a midnight wrap and
-- added a day to it, so a set from 20:00 back to 10:00 billed every hired worker for
-- fourteen hours of a day nobody worked. Now, with the monotonic day present, a
-- negative span is a rewind: nothing is billed, the baseline is the new position,
-- the event is logged, and the next forward span bills once. The wrap arithmetic
-- stays for the one case it was written for, a clock with no monotonic counter.
--
-- THE ENTRY-POINT BAR IS GROUP A: the REAL Settings and the REAL WorkerSystem,
-- initialized as production does (WorkerSystem:initialize) and driven through
-- WorkerSystem:update(dt) as the manager drives it each frame, against the engine's
-- own clock (f282_environment_model.lua: updateTimeValues, setEnvironmentTime and
-- consoleCommandSetDayTime verbatim from Environment.lua) and one running AI job read
-- through the real getActiveWorkers. No accrual, baseline or marker is written by
-- hand; the mocks are the mission (money sink, one job) and the log sink.
--
-- Groups:
--   A  a forward hour accrues; the same-day rewind accrues nothing and re-baselines;
--      the next hour accrues once; midnight settles the day's hours once and a
--      multi-day skip settles once, as before (the settlement bills and resets the
--      accumulator, so those rows read the hours the wage formula was handed)
--   L  without the monotonic counter the wrap arithmetic is unchanged
--   G  the log line, once per rewind event

local HOUR, DAY = F282Env.HOUR, F282Env.DAY

local function num(x)
    if type(x) ~= "number" then return tostring(x) end
    local r = math.floor(x * 100000 + 0.5) / 100000
    if r == math.floor(r) then return string.format("%d", math.floor(r)) end
    return tostring(r)
end

-- ── the world: the engine's clock, one running helper job, a log sink ─────────
local logs, billed = {}, {}
-- The hours the wage formula is handed at each settlement (a recording wrapper over the
-- real calculateLaborCost; it changes nothing and delegates).
local realCalc = WorkerSystem.calculateLaborCost
WorkerSystem.calculateLaborCost = function(self, worker, hoursWorked, ...)
    billed[#billed + 1] = hoursWorked
    return realCalc(self, worker, hoursWorked, ...)
end
local function world(opts)
    local env = F282Env.new(opts)
    logs, billed = {}, {}
    local vehicle = { getFullName = function() return "Harvester" end }
    local job = { isRunning = true, startedFarmId = 1, vehicleParameter = { getVehicle = function() return vehicle end } }
    g_currentMission = {
        environment = env,
        isMissionStarted = true,
        getIsServer = function() return true end,
        getFarmId = function() return 1 end,
        addMoney = function() end,
        aiSystem = { getActiveJobs = function() return { job } end },
    }
    -- The log sink never crashes the bar: a mutation that logs a nil value must fail by
    -- assertion, not by a format error (a crash is an unattributable kill).
    Logging = { info = function(msg, ...)
        local ok, line = pcall(string.format, msg, ...)
        logs[#logs + 1] = ok and line or tostring(msg)
    end, warning = function() end, error = function() end }
    -- The midnight settlement formats the bill for its notice; the prelude's i18n has no formatter.
    g_i18n.formatMoney = g_i18n.formatMoney or function(_, v) return tostring(v) end
    FarmManager = FarmManager or { SPECTATOR_FARM_ID = 0, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }
    return env, vehicle
end
local function rewindLines()
    local n = 0
    for _, l in ipairs(logs) do if l:find("Clock moved backwards", 1, true) then n = n + 1 end end
    return n
end
--- The real system as the manager builds it, initialized (which baselines the clock).
local function system()
    local settings = Settings.new(nil)
    settings.enabled = true
    settings.debugMode = false
    settings.monthlySalaryEnabled = false
    local sys = WorkerSystem.new(settings, nil)
    sys:initialize()
    return sys
end
local function hours(sys, vehicle) return num(sys.workerHours[tostring(vehicle)] or 0) end
local function frame(sys, env, ms)
    if ms then F282Env.tick(env, ms) end
    sys:update(16)
end
-- One hour of a helper is 1/24 of a day's billed half hour.
local H = 0.5 / 24

-- ══════════════════════════════════════════════════════════════════════════
-- A. THE ENTRY-POINT BAR
-- ══════════════════════════════════════════════════════════════════════════
do
    local env, vehicle = world({ day = 3, hour = 8 })
    local sys = system()
    frame(sys, env)
    T.eq("A1 [reached] the real system initialized and its first frame only baselined the clock: no hours billed", tostring(sys.isInitialized) .. " " .. hours(sys, vehicle) .. " " .. tostring(sys.lastAbsoluteGameTimeMs ~= nil), "true 0 true")
    frame(sys, env, HOUR)
    T.eq("A2 [world then system] one forward hour accrues one hour's billed share", env.currentHour .. " " .. hours(sys, vehicle), "9 " .. num(H))
    F282Env.consoleCommandSetDayTime(env, 20)
    frame(sys, env)
    T.eq("A3 a forward set to 20:00 accrues the eleven hours it skipped, as before", hours(sys, vehicle), num(12 * H))
    -- THE REWIND: gsSetDayTime 10 at 20:00 on the same day.
    F282Env.consoleCommandSetDayTime(env, 10)
    frame(sys, env)
    T.eq("A4 [world] the console setter held the day and the monotonic day and lowered the hour", env.currentDay .. "[" .. env.currentMonotonicDay .. "]:" .. env.currentHour, "3[3]:10")
    T.eq("A5 the rewind bills NOTHING (before: fourteen hours of a phantom day), the baseline is the new position, and the event is logged once",
        hours(sys, vehicle) .. " " .. num(sys.lastAbsoluteGameTimeMs) .. " " .. rewindLines(), num(12 * H) .. " " .. num(3 * WorkerSystem.DAY_MS + 10 * 3600000) .. " 1")
    frame(sys, env, HOUR)
    T.eq("A6 the next forward hour accrues once from the new position", hours(sys, vehicle), num(13 * H))
    F282Env.consoleCommandSetDayTime(env, 23)
    frame(sys, env)
    frame(sys, env, HOUR)
    T.eq("A7 a genuine midnight crossing (day up, hour 0) settles the day's hours once, the crossing hour included, and resets the accumulator, as before",
        env.currentDay .. "[" .. env.currentMonotonicDay .. "]:" .. env.currentHour .. " " .. #billed .. ":" .. num(billed[1] or -1) .. " " .. hours(sys, vehicle), "4[4]:0 1:" .. num(26 * H) .. " 0")
    F282Env.setEnvironmentTime(env, env.currentMonotonicDay + 2, env.currentDay + 2, env.dayTime, env.daysPerPeriod)
    frame(sys, env)
    T.eq("A8 a two-day forward skip settles two days of hours once, as before", #billed .. ":" .. num(billed[2] or -1) .. " " .. hours(sys, vehicle), "2:" .. num(2 * 0.5) .. " 0")
    T.eq("A9 no rewind was read into any forward movement", rewindLines(), 1)
end

-- ══════════════════════════════════════════════════════════════════════════
-- L. WITHOUT THE MONOTONIC COUNTER
-- ══════════════════════════════════════════════════════════════════════════
do
    local env, vehicle = world({ day = 3, hour = 23 })
    env.currentMonotonicDay = nil
    local sys = system()
    frame(sys, env)
    F282Env.tick(env, HOUR)
    env.currentMonotonicDay = nil
    sys:update(16)
    T.eq("L1 without the counter a midnight wrap still adds a day and the crossing hour is settled at the day change (the wrap arithmetic the brief keeps)", env.currentHour .. " " .. #billed .. ":" .. num(billed[1] or -1) .. " " .. rewindLines(), "0 1:" .. num(H) .. " 0")
end

-- ══════════════════════════════════════════════════════════════════════════
-- G. THE LOG LINE
-- ══════════════════════════════════════════════════════════════════════════
do
    local env, vehicle = world({ day = 3, hour = 20 })
    local sys = system()
    frame(sys, env)
    F282Env.consoleCommandSetDayTime(env, 15)
    frame(sys, env)
    F282Env.consoleCommandSetDayTime(env, 10)
    frame(sys, env)
    T.eq("G1 two rewinds, two lines, each with the span in in-game ms", rewindLines() .. " " .. tostring(logs[#logs]:find("backwards by 18000000 in-game ms", 1, true) ~= nil), "2 true")
    frame(sys, env, HOUR)
    T.eq("G2 a forward hour adds no line and accrues once", rewindLines() .. " " .. hours(sys, vehicle), "2 " .. num(H))
end

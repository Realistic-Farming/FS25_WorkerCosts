-- f282_environment_model.lua
--
-- The engine's clock (environment/Environment.lua in the decompiled scripts), for
-- RSF-F282. The advance of dayTime per frame is MODELED (a tick adds milliseconds);
-- updateTimeValues :322-357 is VERBATIM through the hour and the day (the minute loop
-- abbreviated to its assignment): the monotonic day only ever increments, :356.
-- setEnvironmentTime :494-510 is VERBATIM (isDelta false). consoleCommandSetDayTime
-- :570-583 is modelled through its time arithmetic: it keeps the day and the monotonic
-- day it read (:576-577) and moves only the day time (:583). Its branch for a lower time
-- (:579-581) decompiles EMPTY, so modelling it as holding the day (a set below the current
-- time is a same-day rewind, the one actor the brief names) is the brief's reading of that
-- branch, not something the source shows (MAINTENANCE row 102).
F282Env = {}

function F282Env.new(opts)
    opts = opts or {}
    local day, hour = opts.day or 3, opts.hour or 8
    return { currentDay = day, currentMonotonicDay = day, dayTime = hour * 3600000, daysPerPeriod = 1,
             currentMinute = 0, currentHour = hour, currentSeason = 1, currentPeriod = 1, currentYear = 1, currentDayInPeriod = 1 }
end

--- :322-357 through the hour and the day.
function F282Env.updateTimeValues(env)
    local timeHoursF = env.dayTime / 3600000 + 0.0001
    local timeHours = math.floor(timeHoursF)
    local timeMinutes = math.floor((timeHoursF - timeHours) * 60)
    if timeMinutes ~= env.currentMinute then
        env.currentMinute = timeMinutes
    end
    if timeHours ~= env.currentHour then
        env.currentHour = timeHours
        if env.currentHour == 24 then
            env.currentHour = 0
        end
    end
    if env.dayTime > 86400000 then
        env.dayTime = env.dayTime - 86400000
        env.currentDay = env.currentDay + 1
        -- A clock without the counter (the bar's no-monotonic case) still crosses midnight.
        if env.currentMonotonicDay ~= nil then env.currentMonotonicDay = env.currentMonotonicDay + 1 end
    end
end

--- One frame of Environment:update: the scaled dt lands on dayTime, then the values.
function F282Env.tick(env, ms)
    env.dayTime = env.dayTime + ms
    F282Env.updateTimeValues(env)
end

--- :494-510 VERBATIM, isDelta false.
function F282Env.setEnvironmentTime(env, currentMonotonicDay, currentDay, dayTime, daysPerPeriod)
    env.currentDay = currentDay
    env.currentMonotonicDay = currentMonotonicDay
    env.dayTime = dayTime
    env.daysPerPeriod = daysPerPeriod
    while env.dayTime > 86400000 do
        env.dayTime = env.dayTime - 86400000
        env.currentDay = env.currentDay + 1
        if env.currentMonotonicDay ~= nil then env.currentMonotonicDay = env.currentMonotonicDay + 1 end
    end
    local timeHoursF = env.dayTime / 3600000 + 0.0001
    env.currentHour = math.floor(timeHoursF)
    env.currentMinute = math.floor((timeHoursF - env.currentHour) * 60)
    F282Env.updateTimeValues(env)
end

--- :570-583 through its arithmetic (gsSetDayTime): the day and the monotonic day held,
--- the brief's reading of the empty lower-time branch :579-581 (MAINTENANCE row 102).
function F282Env.consoleCommandSetDayTime(env, dayTime)
    local newDayTime = math.floor(tonumber(dayTime) * 1000 * 60 * 60)
    local newDay = env.currentDay
    local newMonotonicDay = env.currentMonotonicDay
    F282Env.setEnvironmentTime(env, newMonotonicDay, newDay, newDayTime, env.daysPerPeriod)
end

--- An hour of frames that never lands on the exact midnight millisecond (the engine's
--- frame never does either).
F282Env.HOUR = 3600001
F282Env.DAY = 86400001

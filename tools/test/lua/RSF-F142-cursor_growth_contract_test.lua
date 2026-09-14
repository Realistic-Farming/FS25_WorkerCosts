--!load: src/hireHallCore/core/HireHallEvolution.lua
-- RSF-F142 v0.1: Hire-Hall evolution cursor survives roster growth.
--
-- Calls the real Evolution:update on a controlled core/roster fixture. The
-- worker-level transition (_evolveWorker) is replaced by a recorder so the test
-- observes visit ORDER only; Lifecycle/ProStaff are not loaded and no fatigue,
-- XP or state rule is exercised. Host, throttle and error paths use the same
-- fixture. No native game, save or multiplayer claim.

T.ok("F142 A0 Evolution module loaded", type(HireHallCore) == "table"
    and type(HireHallCore.core) == "table" and type(HireHallCore.core.Evolution) == "table")
if not (HireHallCore and HireHallCore.core and HireHallCore.core.Evolution) then
    T.summary()
    return
end

local Evolution = HireHallCore.core.Evolution
HireHallCore.SLICE_SIZE    = HireHallCore.SLICE_SIZE    or 5
HireHallCore.STEP_INTERVAL = HireHallCore.STEP_INTERVAL or 250

local isHost = true
HireHallCore._isHost = function() return isHost end

-- Recorder in place of the lifecycle transition.
local visits = {}
Evolution._evolveWorker = function(_self, _core, worker)
    visits[#visits + 1] = worker and worker.id or "nil"
end

local function makeWorkers(n)
    local list = {}
    for i = 1, n do list[i] = { id = i } end
    return list
end

local function makeCore(workers)
    local core = {
        roster = {
            getAll = function() return workers end,
            getWorker = function(_self, id)
                for _, w in ipairs(workers) do if w.id == id then return w end end
                return nil
            end,
        },
        _stepTimer = 0,
        failCalls = {},
    }
    function core:fail(ctx, err) self.failCalls[#self.failCalls + 1] = { ctx = ctx, err = err } end
    return core
end

local function step(core)
    visits = {}
    Evolution:update(core, HireHallCore.STEP_INTERVAL)   -- exactly one interval
    return visits
end

local function joinVisits(v)
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return table.concat(parts, ",")
end

-- B1: first step after load visits workers 1..SLICE from cursor 0.
Evolution:reset()
local workers = makeWorkers(8)
local core = makeCore(workers)
T.eq("F142 B1 first step visits 1..5", joinVisits(step(core)), "1,2,3,4,5")
T.eq("F142 B1 cursor advanced to 5", Evolution.lastProcessedIndex, 5)
T.eq("F142 B1 count tracked", Evolution.lastRosterCount, 8)

-- B2: growth keeps the cursor; added workers are reached by the wheel.
workers[9]  = { id = 9 }
workers[10] = { id = 10 }
T.eq("F142 B2 growth does not reset cursor", joinVisits(step(core)), "6,7,8,9,10")
T.eq("F142 B2 count tracked on growth", Evolution.lastRosterCount, 10)

-- B3: wrap after growth continues from 1.
T.eq("F142 B3 wrap to start", joinVisits(step(core)), "1,2,3,4,5")

-- B4: shrink resets the cursor to 0 and tracks the new count.
for i = 10, 4, -1 do workers[i] = nil end   -- 3 left
T.eq("F142 B4 shrink resets to worker 1", joinVisits(step(core)), "1,2,3")
T.eq("F142 B4 count tracked on shrink", Evolution.lastRosterCount, 3)
T.eq("F142 B4 cursor wrapped within small roster", Evolution.lastProcessedIndex, 0)

-- B5: shrink then regrow to the same count between steps never indexes past the end.
Evolution:reset()
workers = makeWorkers(7); core = makeCore(workers)
step(core)                                  -- cursor 5, count 7
workers[7] = nil; workers[6] = nil          -- shrink to 5 (cursor 5 would be out of range)
workers[6] = { id = 6 }; workers[7] = { id = 7 }  -- regrow to 7 before the next step
local v = step(core)
T.eq("F142 B5 same count keeps cursor, no nil visit", joinVisits(v), "6,7,1,2,3")
T.eq("F142 B5 no error raised", #core.failCalls, 0)

-- B6: empty roster returns before any visit and tracks count 0.
Evolution:reset()
workers = makeWorkers(0); core = makeCore(workers)
T.eq("F142 B6 empty roster visits nothing", joinVisits(step(core)), "")
T.eq("F142 B6 empty roster count 0", Evolution.lastRosterCount, 0)
T.eq("F142 B6 empty roster no error", #core.failCalls, 0)

-- B7: urgent queue is processed first, then the slice; queue is drained.
Evolution:reset()
workers = makeWorkers(6); core = makeCore(workers)
Evolution:pushUrgent(4)
Evolution:pushUrgent(4)   -- dedupe
T.eq("F142 B7 urgent first then slice", joinVisits(step(core)), "4,1,2,3,4,5")
T.eq("F142 B7 urgent queue drained", #Evolution.urgentQueue, 0)

-- B8: client is a no-op, even with a seeded cursor and count.
Evolution:reset()
workers = makeWorkers(3); core = makeCore(workers)
step(core)                                  -- host seeds count 3, cursor 0 (wrapped)
Evolution.lastProcessedIndex = 2
isHost = false
T.eq("F142 B8 client visits nothing", joinVisits(step(core)), "")
T.eq("F142 B8 client leaves count untouched", Evolution.lastRosterCount, 3)
T.eq("F142 B8 client leaves cursor untouched", Evolution.lastProcessedIndex, 2)
isHost = true

-- B9: throttle: below STEP_INTERVAL nothing runs, timer accumulates.
Evolution:reset()
workers = makeWorkers(3); core = makeCore(workers)
visits = {}
Evolution:update(core, 100)
T.eq("F142 B9 100ms no step", joinVisits(visits), "")
Evolution:update(core, 100)
T.eq("F142 B9 200ms still no step", joinVisits(visits), "")
Evolution:update(core, 50)
T.eq("F142 B9 250ms runs the slice", joinVisits(visits), "1,2,3")
T.eq("F142 B9 timer reset after step", core._stepTimer, 0)

-- B10: an error inside the step reaches core:fail with the evolution context.
Evolution:reset()
workers = makeWorkers(2); core = makeCore(workers)
core.roster.getAll = function() error("boom") end
step(core)
T.eq("F142 B10 fail called once", #core.failCalls, 1)
T.eq("F142 B10 fail context", core.failCalls[1] and core.failCalls[1].ctx, "evolution.update")

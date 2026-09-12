-- =========================================================
-- FS25 Worker Costs Mod (version 1.0.4.0)
-- =========================================================
-- Hourly or per-hectare wages for workers
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================

---@class WorkerSystem
WorkerSystem = WorkerSystem or {}
local WorkerSystem_mt = Class(WorkerSystem)

-- PRO-STAFF BUILD CHECKLIST — work in THIS file (full plan: docs/PRO_STAFF_PLAN.md):
--   [x] Phase 3 — calculateLaborCost pipeline (skill -> level -> fatigue -> night
--                 -> weather -> overtime); daily fatigue recovery + overtime reset
--   [x] Phase 4 — getEstimatedIntervalCost runs the full pipeline (UI accuracy)

-- Pro-Staff Phase 3 wage modifiers (multiplicative pipeline, applied in order).
-- Defined once here so the additive-vs-multiplicative order can't drift.
WorkerSystem.LEVEL_WAGE_FACTOR = { [1] = 1.00, [2] = 0.95, [3] = 0.90, [4] = 0.85 } -- higher level = efficiency discount (perk); [4] Legendary (locked)
WorkerSystem.FATIGUE_SURCHARGE = 0.50   -- up to +50% at full fatigue (Master and Legendary are immune)
WorkerSystem.NIGHT_MULT        = 1.25   -- night-shift / after-hours premium
WorkerSystem.WEATHER_MULT      = 1.15   -- bad-weather (rain) premium
WorkerSystem.OVERTIME_HOURS    = 8      -- billed hours accrued in one in-game day before overtime (same threshold as the old real-time schedule)
WorkerSystem.OVERTIME_MULT     = 1.50   -- premium once a vehicle passes the daily overtime threshold

-- Rule 10 (one time reference across the ecosystem): all billing runs on the
-- in-game calendar. Wages accrue from in-game time worked and settle once per
-- in-game day at midnight.
WorkerSystem.DAY_MS = 24 * 60 * 60 * 1000  -- in-game milliseconds in one in-game day
-- Conversion identity: at 1x speed one in-game day took 30 real minutes, and the
-- old schedule billed one 30-real-minute interval (0.5 hours of wages) per
-- in-game day. One full in-game day of work therefore bills exactly 0.5 hours,
-- keeping every rate setting and 1x wage magnitude identical to the old system.
WorkerSystem.BILLED_HOURS_PER_DAY = 0.5
-- Phase 5 severance: one-off payout when firing. Senior workers cost more to let go.
WorkerSystem.SEVERANCE_HOURS        = 16
WorkerSystem.SEVERANCE_LEVEL_FACTOR = { [1] = 1.0, [2] = 1.5, [3] = 2.0, [4] = 2.5 }  -- [4] Legendary (locked)
-- Pro-Staff Phase 5: one-off signing cost when hiring a recruit. A more experienced
-- recruit commands a bigger signing bonus. Expressed in "hours of base wage" so it
-- scales with the configured wage level, exactly like severance.
WorkerSystem.HIRE_COST_HOURS        = { [1] = 8, [2] = 24, [3] = 60, [4] = 120 }  -- [4] Legendary premium signing (locked)

---@param settings Settings
---@param roster WorkerRoster|nil  Pro-Staff roster for level/fatigue (Phase 3)
---@return WorkerSystem
function WorkerSystem.new(settings, roster)
    local self = setmetatable({}, WorkerSystem_mt)
    self.settings = settings
    self.roster = roster       -- Phase 3: source of level/fatigue for the wage pipeline
    self.activeWorkers = {}
    self.workerHours = {}      -- accumulated billed hours per vehicleId since last settlement (in-game derived, see BILLED_HOURS_PER_DAY)
    self.workerHectares = {}   -- accumulated hectares per vehicleId since last settlement
    self.workerNames = {}      -- last-known display name per vehicleId (for dismissed workers)
    self.workerRosterUuid = {} -- vehicleId -> roster worker uuid (captured while bound; survives unbind at settlement)
    self.workerFarmId = {}     -- vehicleId -> startedFarmId (dedicated-safe billing; survives dismiss)
    self.workerDailyHours = {} -- vehicleId -> billed hours worked this in-game day (Phase 3 overtime); reset on day change
    -- Rule 10: billing follows the in-game calendar. Wages accrue from the
    -- environment clock (currentMonotonicDay * DAY_MS + dayTime) and are settled
    -- once per in-game day at the day change (midnight).
    self.lastSettledDay = -1           -- environment.currentDay marker (change detection only)
    self.lastSettledMonotonicDay = -1  -- environment.currentMonotonicDay marker (day arithmetic)
    self.lastAbsoluteGameTimeMs = nil  -- absolute in-game clock at the previous update (nil = no baseline yet)
    self.workerJobTotal  = {}      -- cumulative amount charged per vehicle since job start
    self.isInitialized = false
    self._isProcessingPayment = false
    self._originalAddMoney = nil   -- stored so we can restore on delete
    self._hookedAddMoney = false

    -- Monthly salary tracking (F223: per-farm, never pooled into the first farm).
    -- Nested accrual so two farms sharing one worker key stay distinct:
    --   monthlyCosts[farmId][workerKey] = { name = displayName, amount = accrued $ }
    -- workerKey is always a canonical string (tostring of the roster uuid / vehicle id).
    self.monthlyCosts   = {}
    -- F223 frozen bills: a month-end issue freezes ONE bill, moving the accrued rows
    -- OUT of live accrual so later wages are distinct. Parts are per-farm and carry
    -- their own payment disposition so a partial/failed farm never loses or repeats.
    --   salaryBills[billId] = {
    --     id, issuedYear, issuedPeriod, penaltyApplied,
    --     parts = { [farmId] = { name, base, final, remaining, status } } }
    -- status is UNPAID / PAID / INDETERMINATE (WorkerSystem.PART_*).
    self.salaryBills    = {}
    self.nextBillId     = 1        -- monotonic, persisted; never reused after payoff
    self.lastDay        = -1       -- last in-game day we checked
    -- F223: issuance is keyed by the native ordinal (year*PERIODS_IN_YEAR+period-1),
    -- kept SEPARATE from any bill's payment state, so a new year's same-named period
    -- can issue again and a repeated same-period check cannot issue twice.
    self.lastIssuedOrdinal = -1
    self.lastMonthPaid  = -1       -- LEGACY schema-1 field; retained only for load seeding
    self.declinedLastMonth = false -- true if player declined last bill (next bill +20%)
    self.pendingSalary  = nil      -- { billId, entries, total, month } while dialog is open
    -- F223: legacy schema-1 rows with no valid recorded farm. Never defaulted to a
    -- farm, never charged to a borrower; retained as inspectable evidence only.
    self.legacyUnattributed = {}

    return self
end

-- F223 bill-part payment disposition.
WorkerSystem.PART_UNPAID        = "UNPAID"
WorkerSystem.PART_PAID          = "PAID"
WorkerSystem.PART_INDETERMINATE = "INDETERMINATE"

-- Periods (months) per native year. Engine constant (Environment.PERIODS_IN_YEAR=12);
-- read the live constant when present so a future engine change cannot silently drift.
function WorkerSystem._periodsInYear()
    if Environment ~= nil and Environment.PERIODS_IN_YEAR ~= nil then
        return Environment.PERIODS_IN_YEAR
    end
    return 12
end

-- The issuance ordinal for a (year, period) pair: a strictly increasing integer so a
-- later period always compares greater and a new year's period 1 follows last year's.
function WorkerSystem._issuanceOrdinal(year, period)
    return year * WorkerSystem._periodsInYear() + period - 1
end

function WorkerSystem:initialize()
    if self.isInitialized then
        -- Re-install the hook in case it was lost (e.g. after WorkerCostsEnable)
        if not self._hookedAddMoney then
            self:installGameHook()
        end
        return
    end

    if g_currentMission then
        -- Reset the in-game clock trackers so the first update after (re)init
        -- only records a baseline instead of billing a stale span.
        self.lastAbsoluteGameTimeMs = nil
        self.lastSettledDay = -1
        self.lastSettledMonotonicDay = -1

        -- Disable the game's built-in worker cost deductions to prevent double-charging
        self:installGameHook()

        self.isInitialized = true
        Logging.info("[Worker Costs] Worker System initialized. Mode: %s, Base Rate: $%d",
            self.settings:getCostModeName(), self.settings:getWageRate())
    end
end

--- Restore the original addMoney function and mark the system as shut down.
-- Called by WorkerManager:delete() during mission unload.
function WorkerSystem:delete()
    if self._originalAddMoney and g_currentMission then
        g_currentMission.addMoney = self._originalAddMoney
    end
    self._originalAddMoney = nil
    self._hookedAddMoney = false
    self.isInitialized = false
    self:log("Worker System shut down")
end

--- Is farmId a real, chargeable farm? The spectator farm (and the invalid/no-farm
-- id) reject money changes in the engine, which logs "Can't change money of spectator
-- farm" every time. Modded AI vehicles (e.g. NPC helper tractors) run on the spectator
-- farm, so the base game's per-frame running-cost charge (Motorized.updateConsumers)
-- targets that farm continuously and spams the log. Treat those ids as non-payable so
-- our addMoney hook can drop the charge cleanly (it would fail in the engine anyway).
-- @param farmId  the farm id a charge is aimed at
-- @return boolean  true if the farm can actually be charged
function WorkerSystem.isPayableFarm(farmId)
    if farmId == nil then return false end
    local fm = FarmManager
    if fm ~= nil then
        if fm.SPECTATOR_FARM_ID ~= nil and farmId == fm.SPECTATOR_FARM_ID then return false end
        if fm.INVALID_FARM_ID  ~= nil and farmId == fm.INVALID_FARM_ID  then return false end
    end
    -- 0 is the conventional "no farm" id (also the spectator fallback used by mods).
    if farmId == 0 then return false end
    return true
end

--- Patch mission.addMoney to zero out the game's own worker-wage deductions.
-- We use _isProcessingPayment as a flag so that OUR payments still pass through.
--
-- IMPORTANT: The game charges helper wages via MoneyType.AI (confirmed from AIJob source).
-- AIJob:updateCost() accumulates pendingCost and flushes whenever it exceeds 25§:
--   g_currentMission:addMoney(-self.pendingCost, self.startedFarmId, MoneyType.AI, true)
-- We intercept exactly MoneyType.AI charges while helpers are active.
function WorkerSystem:installGameHook()
    if not g_currentMission then
        return
    end
    if self._hookedAddMoney then
        return
    end

    local mission = g_currentMission
    local originalAddMoney = mission.addMoney
    if not originalAddMoney then
        return
    end

    -- MoneyType.AI is the type used by AIJob:updateCost() and AIJob:stop().
    -- Log whatever values are available so the diagnostic command can report them.
    local aiMoneyType = MoneyType and MoneyType.AI
    Logging.info("[Worker Costs] MoneyType.AI = %s, MoneyType.WORKER_WAGES = %s",
        tostring(aiMoneyType),
        tostring(MoneyType and MoneyType.WORKER_WAGES))

    if aiMoneyType == nil then
        Logging.warning("[Worker Costs] MoneyType.AI not found — will fall back to active-job heuristic.")
    end

    local capturedSelf      = self
    local capturedAIType    = aiMoneyType
    self._originalAddMoney  = originalAddMoney

    mission.addMoney = function(missionObj, amount, farmId, moneyType, ...)
        -- Let OUR charges pass through unconditionally.
        if capturedSelf._isProcessingPayment then
            return originalAddMoney(missionObj, amount, farmId, moneyType, ...)
        end

        -- Never forward a charge to a non-payable farm (spectator / invalid). The
        -- engine rejects it ("Can't change money of spectator farm") and spams the log;
        -- modded AI vehicles (e.g. NPC helper tractors) run on the spectator farm and
        -- the base game charges their running cost every frame the engine is on.
        -- Dropping it is money-neutral (the engine would refuse anyway) and applies
        -- regardless of our wage-suppression setting.
        if not WorkerSystem.isPayableFarm(farmId) then
            return
        end

        if capturedSelf.settings.enabled and amount < 0 then
            -- Re-read the wage MoneyTypes at call time. The hook installs early in
            -- load, when the enum may still be nil (that is why capturedAIType can be
            -- nil); by the time a wage is actually charged the enum is populated. This
            -- keeps us on the reliable type match and off the magnitude heuristic.
            local aiType   = (MoneyType and MoneyType.AI) or capturedAIType
            local wageType = MoneyType and MoneyType.WORKER_WAGES

            local isHelperWage = (aiType ~= nil and moneyType == aiType)
                              or (wageType ~= nil and moneyType == wageType)

            -- F223/R1: forward every explicit KNOWN non-wage MoneyType (e.g. OTHER)
            -- through the captured chain BEFORE any missing-enum/magnitude heuristic.
            -- Only an unknown/nil type may be guessed at. Previously, when this build
            -- exposed neither AI nor WORKER_WAGES, the heuristic could swallow a typed
            -- OTHER charge <=500 during a job — eating IncomeMod's loan/tax/repayment
            -- deductions. A known OTHER is never a helper wage. (Owner-predicate fix,
            -- not a second money writer; AI/WORKER_WAGES keep their real suppression.)
            local otherType    = MoneyType and MoneyType.OTHER
            local knownNonWage = (otherType ~= nil and moneyType == otherType)

            -- Last-resort heuristic ONLY when this build exposes NEITHER wage MoneyType
            -- AND the charge is not a known non-wage type. Gated on both enums being
            -- absent; warns visibly since suppression here is an informed guess.
            if not isHelperWage and not knownNonWage and aiType == nil and wageType == nil then
                local hasActiveJobs = false
                local aiSystem = g_currentMission and g_currentMission.aiSystem
                if aiSystem and aiSystem.getActiveJobs then
                    local jobs = aiSystem:getActiveJobs()
                    hasActiveJobs = (jobs ~= nil and #jobs > 0)
                end
                if hasActiveJobs and math.abs(amount) <= 500 then
                    isHelperWage = true
                    Logging.warning("[Worker Costs] No wage MoneyType in this build; "
                        .. "suppressing suspected helper wage by heuristic: %d", amount)
                end
            end

            if isHelperWage then
                capturedSelf:log("Suppressed built-in helper wage: %d (moneyType=%s)", amount, tostring(moneyType))
                return
            end
        end

        return originalAddMoney(missionObj, amount, farmId, moneyType, ...)
    end

    self._hookedAddMoney = true
    Logging.info("[Worker Costs] Hook installed — intercepting MoneyType.AI helper wages")
end

function WorkerSystem:log(msg, ...)
    if self.settings.debugMode then
        print(string.format("[Worker Costs] " .. msg, ...))
    end
end

function WorkerSystem:showNotification(title, message)
    if not g_currentMission or not self.settings.showNotifications then
        return
    end

    if g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(message, 4000)
    end

    self:log("%s: %s", title, message)
end

-- Real farm ids only (reject spectator / guided tour / invalid). Dairy F75 shape.
function WorkerSystem:_isRealFarmId(farmId)
    if type(farmId) ~= "number" or farmId <= 0 then return false end
    local fm = FarmManager
    local spectator = (fm ~= nil and fm.SPECTATOR_FARM_ID) or 0
    local tour      = (fm ~= nil and fm.GUIDED_TOUR_FARM_ID) or 14
    local invalid   = (fm ~= nil and fm.INVALID_FARM_ID) or 15
    return farmId ~= spectator and farmId ~= tour and farmId ~= invalid
end

-- Resolve a billing farmId without treating dedicated nil getFarmId() as authority.
function WorkerSystem:_resolveBillingFarmId(explicitFarmId)
    if self:_isRealFarmId(explicitFarmId) then
        return explicitFarmId
    end
    local localId = nil
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            localId = g_currentMission:getFarmId()
        end
    end)
    if self:_isRealFarmId(localId) then
        return localId
    end
    return nil
end

-- Soft-detect ProStaffCoOp wage modifier (neutral 1.0 when absent / pcall fails).
function WorkerSystem:_proStaffWageModifier(farmId)
    local ps = g_currentMission and g_currentMission.proStaffManager
    if ps == nil or type(ps.getWageModifier) ~= "function" then
        return 1.0
    end
    if not self:_isRealFarmId(farmId) then
        return 1.0
    end
    local ok, mod = pcall(function()
        return ps:getWageModifier(farmId)
    end)
    if ok and type(mod) == "number" and mod == mod and mod > 0 then
        return mod
    end
    return 1.0
end

function WorkerSystem:getActiveWorkers()
    local workers = {}

    if not g_currentMission then
        return workers
    end

    local aiSystem = g_currentMission.aiSystem
    if not aiSystem or not aiSystem.getActiveJobs then
        return workers
    end

    local activeJobs = aiSystem:getActiveJobs()
    if not activeJobs then
        return workers
    end

    -- job.isRunning is the correct running-state field (not job.isActive).
    -- Vehicle is accessed via job.vehicleParameter:getVehicle() on field-work jobs,
    -- with a fallback to job.vehicle for any custom job types that set it directly.
    -- job.startedFarmId (set by AIJob:start) identifies the owning farm; skip jobs
    -- started by other farms (e.g. NPC neighbor workers from neighbour mods).
    -- Dedicated: getFarmId() is nil — do NOT treat that as "no farms". Include every
    -- real startedFarmId so helpers are billed; chargeWage uses that explicit id.
    local playerFarmId = nil
    pcall(function()
        playerFarmId = g_currentMission:getFarmId()
    end)
    for _, job in ipairs(activeJobs) do
        if job and job.isRunning then
            local jobFarmId = job.startedFarmId
            local skip = false
            if self:_isRealFarmId(playerFarmId) and self:_isRealFarmId(jobFarmId) and jobFarmId ~= playerFarmId then
                skip = true
            elseif jobFarmId ~= nil and not self:_isRealFarmId(jobFarmId) then
                skip = true
            end
            if not skip then
                local vehicle = nil
                if job.vehicleParameter and job.vehicleParameter.getVehicle then
                    vehicle = job.vehicleParameter:getVehicle()
                elseif job.vehicle then
                    vehicle = job.vehicle
                end

                if vehicle then
                    local vehicleName = (vehicle.getFullName and vehicle:getFullName())
                                     or (vehicle.getName and vehicle:getName())

                    local name = "Worker"
                    if job.getHelperName then
                        local ok, helperName = pcall(function() return job:getHelperName() end)
                        if ok and helperName and helperName ~= "" then
                            name = helperName
                        end
                    end
                    if name == "Worker" then
                        name = vehicleName or "Worker"
                    end

                    if self.roster then
                        local rw = self.roster:getWorkerByVehicle(tostring(vehicle))
                        if rw and rw.name then
                            name = rw.name
                        end
                    end

                    table.insert(workers, {
                        vehicle     = vehicle,
                        job         = job,
                        name        = name,
                        vehicleName = vehicleName,
                        farmId      = jobFarmId,
                    })
                end
            end
        end
    end

    return workers
end

--- Estimated wage bill for the current settlement period (UI display only).
-- Phase 4: now runs each active worker through the same calculateLaborCost
-- pipeline (level / fatigue / night / weather / overtime) so the dashboard
-- estimate matches what will actually be charged.
-- Hourly mode: projects one full settlement period (an in-game day) per worker.
-- Per-hectare mode: uses the area accrued so far this period, so it grows live.
---@param workerCount number  unused; kept for call-site compatibility
---@return number  estimated cost in $ for this settlement period
function WorkerSystem:getEstimatedIntervalCost(workerCount)
    local workers = self:getActiveWorkers()
    -- One settlement period = one in-game day = BILLED_HOURS_PER_DAY billed
    -- hours, the same magnitude the old 30-real-minute interval projected.
    local intervalHours = WorkerSystem.BILLED_HOURS_PER_DAY
    local isHourly = (self.settings.costMode == Settings.COST_MODE_HOURLY)
    local total = 0

    for _, w in ipairs(workers) do
        local vehicleId    = tostring(w.vehicle)
        local rosterWorker = self.roster and self.roster:getWorker(self.workerRosterUuid[vehicleId])
        local dailyHours   = self.workerDailyHours[vehicleId]
        if isHourly then
            total = total + self:calculateLaborCost(w, intervalHours, 0, rosterWorker, dailyHours)
        else
            local hectares = self.workerHectares[vehicleId] or 0
            total = total + self:calculateLaborCost(w, 0, hectares, rosterWorker, dailyHours)
        end
    end

    return math.floor(total)
end

-- Pro-Staff Phase 3: ordered labor-cost pipeline (replaces calculateWorkerWage).
-- base(mode) -> game skill -> roster level -> fatigue -> night -> weather.
-- All multiplicative; the order is fixed here so nothing double-dips.
---@param worker table        billing worker {job=...} (may be a bare pseudo-worker)
---@param hoursWorked number
---@param hectaresWorked number
---@param rosterWorker table|nil  roster entry providing level/fatigue (may be nil)
---@param dailyHours number|nil   hours this vehicle has worked today (overtime axis)
function WorkerSystem:calculateLaborCost(worker, hoursWorked, hectaresWorked, rosterWorker, dailyHours)
    local baseRate = self.settings:getWageRate()

    local cost
    if self.settings.costMode == Settings.COST_MODE_HOURLY then
        cost = baseRate * hoursWorked
    else
        -- Per-hectare mode: 0 when no area was tracked (implement without getLastHa).
        -- The caller checks cost > 0 before deducting, so free-work is the only
        -- consequence — logged in debug mode.
        if hectaresWorked <= 0 then
            self:log("Per-hectare cost skipped for worker with 0 ha tracked (implement may not support getLastHa)")
        end
        cost = baseRate * hectaresWorked
    end

    if cost <= 0 then
        return 0
    end

    -- Game skill multiplier (0.8x..1.2x), unchanged from the original behaviour.
    if worker and worker.job and worker.job.getSkillLevel then
        local skill = worker.job:getSkillLevel() or 0.5
        cost = cost * (0.8 + skill * 0.4)
    end

    local level   = (rosterWorker and rosterWorker.level)   or WorkerRoster.LEVEL_NOVICE
    local fatigue = (rosterWorker and rosterWorker.fatigue) or 0

    -- 1. Level efficiency discount (perk: higher level => cheaper per unit).
    cost = cost * (WorkerSystem.LEVEL_WAGE_FACTOR[level] or 1.0)

    -- 2. Fatigue surcharge. Master and above are immune (Phase 2 perk); a Legendary
    --    worker is never treated worse than a Master.
    if level < WorkerRoster.LEVEL_MASTER and fatigue > 0 then
        cost = cost * (1 + fatigue * WorkerSystem.FATIGUE_SURCHARGE)
    end

    -- 3. Night / after-hours premium.
    if self:_isNight() then
        cost = cost * WorkerSystem.NIGHT_MULT
    end

    -- 4. Bad-weather (rain) premium.
    if self:_isBadWeather() then
        cost = cost * WorkerSystem.WEATHER_MULT
    end

    -- 5. Graduated overtime: only the fraction of hours above the daily
    -- threshold bills at the premium rate (not a step function on the
    -- entire cost).
    if dailyHours and dailyHours > WorkerSystem.OVERTIME_HOURS then
        local overtimeFraction = 1 - (WorkerSystem.OVERTIME_HOURS / dailyHours)
        cost = cost * (1 + overtimeFraction * (WorkerSystem.OVERTIME_MULT - 1))
    end

    -- 6. ProStaffCoOp wage modifier (soft-detect; neutral 1.0 when absent).
    local billingFarm = nil
    if worker and self:_isRealFarmId(worker.farmId) then
        billingFarm = worker.farmId
    end
    cost = cost * self:_proStaffWageModifier(billingFarm)

    return math.floor(cost)
end

-- Night = the engine's own sun flag is off. environment.isSunOn is what the base
-- game keys vehicle lights / solar panels / crop sensors off (verified in source).
function WorkerSystem:_isNight()
    local env = g_currentMission and g_currentMission.environment
    return env ~= nil and env.isSunOn == false
end

-- Bad weather = currently raining. environment.weather:getIsRaining() is the
-- boolean the base game uses (NightlightFlicker, SunAdmirer, BeehiveSystem).
function WorkerSystem:_isBadWeather()
    local env = g_currentMission and g_currentMission.environment
    if not env or not env.weather or not env.weather.getIsRaining then
        return false
    end
    local ok, raining = pcall(function() return env.weather:getIsRaining() end)
    return ok and raining == true
end

-- Pro-Staff Phase 5: severance cost for firing a worker of the given level.
function WorkerSystem:computeSeverance(level)
    local rate = self.settings:getWageRate()
    local factor = WorkerSystem.SEVERANCE_LEVEL_FACTOR[level] or 1.0
    return math.floor(rate * WorkerSystem.SEVERANCE_HOURS * factor)
end

--- Charge severance to a farm. Returns the amount charged (0 if none).
-- farmId is optional — defaults to the local player's farm (SP/host). In multiplayer
-- the command pipeline passes the requesting player's farm so the right account pays.
function WorkerSystem:chargeSeverance(workerName, level, farmId)
    local amount = self:computeSeverance(level)
    if amount <= 0 then
        return 0
    end
    farmId = self:_resolveBillingFarmId(farmId)
    if farmId == nil then
        return 0
    end
    self._isProcessingPayment = true
    local ok = pcall(function()
        g_currentMission:addMoney(-amount, farmId, MoneyType.OTHER, false)
    end)
    self._isProcessingPayment = false
    if ok and self.settings.showNotifications then
        local money = g_i18n and g_i18n:formatMoney(amount, 0, true, true) or tostring(amount)
        self:showNotification("Severance", string.format("%s dismissed - severance %s", workerName, money))
    end
    return ok and amount or 0
end

-- Pro-Staff Phase 5: signing cost for hiring a recruit of the given level.
function WorkerSystem:computeHireCost(level)
    local rate = self.settings:getWageRate()
    local hours = WorkerSystem.HIRE_COST_HOURS[level] or WorkerSystem.HIRE_COST_HOURS[1]
    return math.floor(rate * hours)
end

--- Charge a hiring/signing cost to a farm. Returns the amount charged (0 if none).
-- Same farmId contract as chargeSeverance — defaults to the local farm, overridden
-- by the MP command pipeline so the requesting player's account pays.
function WorkerSystem:chargeHireCost(workerName, level, farmId)
    local amount = self:computeHireCost(level)
    if amount <= 0 then
        return 0
    end
    farmId = self:_resolveBillingFarmId(farmId)
    if farmId == nil then
        return 0
    end
    self._isProcessingPayment = true
    local ok = pcall(function()
        g_currentMission:addMoney(-amount, farmId, MoneyType.OTHER, false)
    end)
    self._isProcessingPayment = false
    if ok and self.settings.showNotifications then
        local money = g_i18n and g_i18n:formatMoney(amount, 0, true, true) or tostring(amount)
        self:showNotification("New Hire", string.format("%s hired - signing cost %s", workerName, money))
    end
    return ok and amount or 0
end

-- Pro-Staff Phase 3: per-in-game-day housekeeping — reset overtime counters and
-- recover idle workers' fatigue.
function WorkerSystem:onDayChange()
    local env = g_currentMission and g_currentMission.environment
    if not env or env.currentDay == nil then
        return
    end
    if self.lastDay == env.currentDay then
        return
    end
    local firstObservation = (self.lastDay == -1)
    self.lastDay = env.currentDay

    -- New day: the overtime counters reset.
    self.workerDailyHours = {}

    if firstObservation or not self.roster then
        return  -- baseline only; no recovery on the first frame after load
    end
    for _, w in ipairs(self.roster:getAll()) do
        if w.assignedVehicleId == nil and (w.fatigue or 0) > 0 then
            WorkerRoster.recoverFatigue(w, 1)
        end
    end
end

-- @param silent  If true, suppresses the per-payment HUD notification.
--                Used when flushing interval payments into the monthly salary
--                summary so the dialog is the single notification, not both.
-- @param farmId  Explicit owning farm (job.startedFarmId). Required on dedicated.
function WorkerSystem:chargeWage(workerId, workerName, amount, workType, silent, farmId)
    if not g_currentMission then
        self:log("Cannot charge wage: No mission")
        return false
    end

    if amount <= 0 then
        self:log("Cannot charge wage: Amount is zero or negative")
        return false
    end

    farmId = self:_resolveBillingFarmId(farmId)
    if farmId == nil then
        -- Dedicated with no explicit farmId: fail-closed (do not pretend farm 1).
        self:log("Cannot charge wage: No valid farm ID (need explicit startedFarmId on dedicated)")
        return false
    end

    -- Monthly salary mode: accrue only, never deduct here. The wage settles ONCE
    -- at month end (executeMonthlySalaryPayment), where the player can accept or
    -- decline it. Deducting per interval AND again in the month-end lump would
    -- double-charge the wage, so in this mode we accumulate and return without
    -- moving any money. The accrual is persisted (saveMonthlyState) so a mid-month
    -- reload cannot drop what is owed.
    if self.settings.monthlySalaryEnabled then
        -- F223: accrue under farmId -> canonical worker key. The same worker working
        -- for two farms keeps two distinct entries (no first-farm pooling), so each
        -- farm is billed exactly its own work.
        local farmBook = self.monthlyCosts[farmId]
        if farmBook == nil then
            farmBook = {}
            self.monthlyCosts[farmId] = farmBook
        end
        local key = tostring(workerId)
        local entry = farmBook[key]
        if entry then
            entry.amount = entry.amount + amount
        else
            farmBook[key] = { name = workerName, amount = amount }
        end
        self:log("%s %s wage accrued for monthly salary: %d (farm %d)", workerName, workType, amount, farmId)
        return true
    end

    -- Immediate mode: deduct the wage now.
    -- Raise the flag so the hook knows this negative addMoney call is ours.
    -- Use pcall so the flag is always cleared even if addMoney throws.
    self._isProcessingPayment = true
    local ok, err = pcall(function()
        g_currentMission:addMoney(-amount, farmId, MoneyType.OTHER, false)
    end)
    self._isProcessingPayment = false

    if not ok then
        self:log("chargeWage: addMoney threw an error: %s", tostring(err))
        return false
    end

    if not silent and self.settings.showNotifications then
        -- g_i18n is client-only; guard for dedicated-server environments
        local formattedAmount
        if g_i18n then
            formattedAmount = g_i18n:formatMoney(amount, 0, true, true)
        else
            formattedAmount = tostring(amount)
        end
        local modeText = self.settings:getCostModeName()
        local message = string.format("%s - %s: -%s", workerName, modeText, formattedAmount)

        self:showNotification("Worker Payment", message)
    end

    self:log("%s %s wage: %d from farm %d", workerName, workType, amount, farmId)
    return true
end

--- In-game milliseconds elapsed since the previous call (rule 10 clock source).
-- Uses the absolute in-game clock currentMonotonicDay * DAY_MS + dayTime:
-- currentMonotonicDay is the counter the base game uses for day arithmetic
-- (AbstractMission), dayTime is in-game ms since midnight (0..DAY_MS). The
-- absolute form survives midnight wraps and multi-day skips. Returns 0 on the
-- first observation (baseline) and while the game is paused (clock frozen).
function WorkerSystem:consumeInGameMs()
    local env = g_currentMission and g_currentMission.environment
    if not env or env.dayTime == nil then
        return 0
    end
    local monotonicDay = env.currentMonotonicDay or 0
    local nowMs = monotonicDay * WorkerSystem.DAY_MS + env.dayTime
    local lastMs = self.lastAbsoluteGameTimeMs
    self.lastAbsoluteGameTimeMs = nowMs
    if lastMs == nil then
        return 0
    end
    local delta = nowMs - lastMs
    if delta < 0 then
        -- Midnight wrap without a monotonic counter (defensive: only possible
        -- when currentMonotonicDay is unavailable and dayTime wrapped).
        delta = delta + WorkerSystem.DAY_MS
        if delta < 0 then
            return 0
        end
    end
    return delta
end

function WorkerSystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then
        return
    end

    if not g_currentMission then
        return
    end

    -- Rule 10: wages accrue from IN-GAME time worked, read from the environment
    -- clock, so billing follows the in-game calendar at every speed setting
    -- (and freezes while the game is paused).
    local inGameMsThisFrame = self:consumeInGameMs()

    local activeWorkers = self:getActiveWorkers()

    -- Accrue billed hours per active worker this frame.
    -- billedHours = inGameMsWorked / DAY_MS * BILLED_HOURS_PER_DAY, i.e. one
    -- full in-game day of work bills 0.5 hours, exactly what the old
    -- 30-real-minute interval billed per in-game day at 1x speed.
    local billedHoursThisFrame = inGameMsThisFrame / WorkerSystem.DAY_MS * WorkerSystem.BILLED_HOURS_PER_DAY

    for _, worker in ipairs(activeWorkers) do
        local vehicleId = tostring(worker.vehicle)

        -- Initialize tracking for newly-detected workers
        if not self.workerHours[vehicleId] then
            self.workerHours[vehicleId] = 0
            self.workerHectares[vehicleId] = 0
            self.workerJobTotal[vehicleId]  = 0
            self:log("Started tracking worker: %s", worker.name)
        end
        -- Always refresh the name so dismissed-worker payments use the latest value
        self.workerNames[vehicleId] = worker.name
        if self:_isRealFarmId(worker.farmId) then
            self.workerFarmId = self.workerFarmId or {}
            self.workerFarmId[vehicleId] = worker.farmId
        end

        -- Phase 3: remember which roster worker this vehicle maps to while the
        -- binding still exists, so the wage pipeline can apply level/fatigue even
        -- at the final (dismissed) settlement after the job ended and unbound it.
        if self.roster then
            local rw = self.roster:getWorkerByVehicle(vehicleId)
            if rw then
                self.workerRosterUuid[vehicleId] = rw.uuid
            end
        end

        self.workerHours[vehicleId] = self.workerHours[vehicleId] + billedHoursThisFrame
        -- Phase 3 overtime: accumulate the day's billed hours (persists across
        -- jobs; reset only on day change, not at per-job settlement).
        self.workerDailyHours[vehicleId] = (self.workerDailyHours[vehicleId] or 0) + billedHoursThisFrame

        -- Track hectares if the job exposes them
        if worker.job and worker.job.getLastHa then
            local hectares = worker.job:getLastHa() or 0
            self.workerHectares[vehicleId] = self.workerHectares[vehicleId] + hectares
        end
    end

    -- Daily settlement: bill all accrued wages once per in-game day, at the
    -- day change (midnight). currentDay is used for change detection only;
    -- currentMonotonicDay is the arithmetic source for how many days elapsed.
    -- Billing is accrual-based, so even if several day transitions pass
    -- between updates the accrued amount is settled exactly once and the
    -- markers jump to the current day (no re-billing of settled accrual).
    -- This runs BEFORE onDayChange() below so the settlement still sees the
    -- outgoing day's overtime counters.
    local env = g_currentMission.environment
    if env and env.currentDay ~= nil then
        local monotonicDay = env.currentMonotonicDay or -1
        if self.lastSettledDay == -1 then
            -- First observation after load: baseline only, nothing to settle.
            self.lastSettledDay = env.currentDay
            self.lastSettledMonotonicDay = monotonicDay
        elseif env.currentDay ~= self.lastSettledDay then
            local daysElapsed = 1
            if monotonicDay >= 0 and self.lastSettledMonotonicDay >= 0 then
                daysElapsed = math.max(1, monotonicDay - self.lastSettledMonotonicDay)
            end
            self.lastSettledDay = env.currentDay
            self.lastSettledMonotonicDay = monotonicDay
            self:processWorkerPayments()
            self:log("Daily wage settlement fired (%d in-game day(s) since last settlement)", daysElapsed)
        end
    end

    -- Phase 3: daily housekeeping (overtime reset + idle fatigue recovery).
    self:onDayChange()

    -- Monthly salary: check if the last day of the month has just been reached
    if self.settings.monthlySalaryEnabled then
        self:checkMonthEnd()
    elseif self:_hasAccrual() or next(self.salaryBills) ~= nil then
        -- Monthly mode was switched off with wages still accrued or a bill still owed:
        -- settle once now so nothing is orphaned (money still moves exactly once).
        self:settlePendingMonthlyAccrual()
    end
end

-- @param silent  If true, suppresses per-payment HUD notifications.
--                Used when flushing before the monthly salary dialog.
function WorkerSystem:processWorkerPayments(silent)
    local activeWorkers = self:getActiveWorkers()
    local totalPaid = 0
    local workersCount = 0

    -- Build a set of currently-active vehicle IDs for the dismissed-worker check below
    local activeIds = {}
    for _, worker in ipairs(activeWorkers) do
        activeIds[tostring(worker.vehicle)] = true
    end

    -- Pay workers that are currently active
    for _, worker in ipairs(activeWorkers) do
        local vehicleId = tostring(worker.vehicle)

        if self.workerHours[vehicleId] then
            local hoursWorked = self.workerHours[vehicleId]
            local hectaresWorked = self.workerHectares[vehicleId] or 0

            if hoursWorked > 0 or hectaresWorked > 0 then
                local rosterWorker = self.roster and self.roster:getWorker(self.workerRosterUuid[vehicleId])
                local wage = self:calculateLaborCost(worker, hoursWorked, hectaresWorked, rosterWorker, self.workerDailyHours[vehicleId])

                if wage > 0 then
                    local workerId = (rosterWorker and rosterWorker.uuid) or vehicleId
                    self:chargeWage(workerId, worker.name, wage, self.settings:getCostModeName(), silent, worker.farmId)
                    totalPaid = totalPaid + wage
                    workersCount = workersCount + 1
                    -- Accumulate into job total for the completion notification
                    self.workerJobTotal[vehicleId] = (self.workerJobTotal[vehicleId] or 0) + wage
                end
            end

            -- Always reset so the next interval starts clean
            self.workerHours[vehicleId] = 0
            self.workerHectares[vehicleId] = 0
        end
    end

    -- Pay workers that were dismissed mid-interval (accumulated time but no longer active).
    -- Without this, any time worked since the last payment tick is silently lost.
    -- NOTE: We construct a minimal pseudo-worker table so we can reuse calculateLaborCost()
    -- and avoid duplicating the wage formula here.
    for vehicleId, hoursWorked in pairs(self.workerHours) do
        if not activeIds[vehicleId] and (hoursWorked > 0 or (self.workerHectares[vehicleId] or 0) > 0) then
            local hectaresWorked = self.workerHectares[vehicleId] or 0
            -- Use a bare pseudo-worker so calculateLaborCost applies the same
            -- formula (including any future changes) as for active workers.
            -- Dismissed workers have no job object, so skill defaults to neutral.
            -- The roster uuid was captured while bound, so level/fatigue still apply.
            local rosterWorker = self.roster and self.roster:getWorker(self.workerRosterUuid[vehicleId])
            local farmId = (self.workerFarmId and self.workerFarmId[vehicleId]) or nil
            local pseudoWorker = { farmId = farmId }
            local wage = self:calculateLaborCost(pseudoWorker, hoursWorked, hectaresWorked, rosterWorker, self.workerDailyHours[vehicleId])

            local name = self.workerNames[vehicleId] or "Dismissed Worker"
            if wage > 0 then
                local workerId = self.workerRosterUuid[vehicleId] or vehicleId
                self:chargeWage(workerId, name, wage, self.settings:getCostModeName(), true, farmId)
                totalPaid = totalPaid + wage
                workersCount = workersCount + 1
            end

            -- Show a job-completion summary (always, regardless of silent flag)
            if not silent and self.settings.showNotifications then
                local jobTotal = (self.workerJobTotal[vehicleId] or 0) + wage
                local totalStr = g_i18n and g_i18n:formatMoney(jobTotal, 0, true, true)
                             or tostring(jobTotal)
                self:showNotification("Job Complete",
                    string.format("%s: job done - Total: -%s", name, totalStr))
            end

            -- Remove stale entries to prevent unbounded table growth
            self.workerHours[vehicleId]      = nil
            self.workerHectares[vehicleId]   = nil
            self.workerNames[vehicleId]      = nil
            self.workerJobTotal[vehicleId]   = nil
            self.workerRosterUuid[vehicleId] = nil
            if self.workerFarmId then
                self.workerFarmId[vehicleId] = nil
            end
        end
    end

    if workersCount > 0 then
        self:log("Paid %d worker(s) a total of $%d", workersCount, totalPaid)
    end
end

function WorkerSystem:testPayment()
    -- chargeWage already handles the notification, so no extra call needed here
    return self:chargeWage("test", "Test Worker", 100, "test")
end

-- ─────────────────────────────────────────────────────────
-- Monthly salary system
-- ─────────────────────────────────────────────────────────

-- F223 accrual helpers (the nested monthlyCosts[farmId][workerKey] book).

--- Total unbilled accrual per farm: { [farmId] = sum of that farm's worker amounts }.
function WorkerSystem:_accrualByFarm()
    local byFarm = {}
    for farmId, farmBook in pairs(self.monthlyCosts or {}) do
        local sum = 0
        for _, entry in pairs(farmBook) do
            if entry and entry.amount and entry.amount > 0 then
                sum = sum + entry.amount
            end
        end
        if sum > 0 then
            byFarm[farmId] = sum
        end
    end
    return byFarm
end

--- Grand total of all unbilled accrual across every farm.
function WorkerSystem:_accrualTotal()
    local total = 0
    for _, sum in pairs(self:_accrualByFarm()) do
        total = total + sum
    end
    return total
end

--- Any unbilled accrual present? (replaces the old `next(monthlyCosts)` test, which
--- is now truthy for an empty per-farm book.)
function WorkerSystem:_hasAccrual()
    for _, farmBook in pairs(self.monthlyCosts or {}) do
        for _, entry in pairs(farmBook) do
            if entry and entry.amount and entry.amount > 0 then
                return true
            end
        end
    end
    return false
end

--- F223 Direction 13: the legacy `monthAccrued` display aggregate — unbilled base
--- accrual plus the unpaid BASE (pre-penalty) portions of frozen bills. It keeps its
--- old "base accrual this month" meaning; the penalised final bill is not summed here.
function WorkerSystem:_baseAccrualAggregate()
    local total = self:_accrualTotal()
    for _, bill in pairs(self.salaryBills or {}) do
        for _, part in ipairs(bill.parts or {}) do
            if part.status == WorkerSystem.PART_UNPAID and (part.remaining or 0) > 0 then
                total = total + (part.base or 0)
            end
        end
    end
    return total
end

--- Re-accrue one worker row under a farm (used by Decline to return unpaid base rows).
function WorkerSystem:_accrueRow(farmId, key, name, amount)
    if farmId == nil or amount == nil or amount <= 0 then return end
    local farmBook = self.monthlyCosts[farmId]
    if farmBook == nil then
        farmBook = {}
        self.monthlyCosts[farmId] = farmBook
    end
    key = tostring(key)
    local entry = farmBook[key]
    if entry then
        entry.amount = entry.amount + amount
    else
        farmBook[key] = { name = name or "Worker", amount = amount }
    end
end

--- Called every update tick when monthlySalaryEnabled is true.
-- F223: issue the monthly bill on the real last day of the period for ANY configured
-- month length, keyed by the native ordinal so it fires once per (year, period). The
-- old `currentDay >= currentPeriod*28` test never reached the last day of a month with
-- daysPerPeriod other than 28 (e.g. a 3-day month), silently skipping the bill.
function WorkerSystem:checkMonthEnd()
    if not g_currentMission or not g_currentMission.environment then
        return
    end
    local env = g_currentMission.environment

    local dayInPeriod   = env.currentDayInPeriod
    local daysPerPeriod = env.daysPerPeriod
    local year          = env.currentYear
    local period        = env.currentPeriod

    -- Validate the native ordinal calendar; an inconsistent/unready sample is not a
    -- due date. (currentDayInPeriod = (currentDay-1) % daysPerPeriod + 1 in the engine.)
    if type(dayInPeriod) ~= "number" or type(daysPerPeriod) ~= "number"
        or type(year) ~= "number" or type(period) ~= "number"
        or daysPerPeriod < 1 or dayInPeriod < 1 or dayInPeriod > daysPerPeriod
        or period < 1 or year < 0 then
        return
    end

    -- The last day of the period (on a one-day month, that one day is the last day).
    if dayInPeriod ~= daysPerPeriod then
        return
    end

    -- Issue once per (year, period): a strictly increasing ordinal lets a new year's
    -- same-named period issue again and blocks a repeated same-period check.
    local ordinal = WorkerSystem._issuanceOrdinal(year, period)
    if self.lastIssuedOrdinal ~= nil and self.lastIssuedOrdinal >= 0
        and ordinal <= self.lastIssuedOrdinal then
        return
    end
    self.lastIssuedOrdinal = ordinal
    self.lastMonthPaid = period  -- legacy mirror only; payment state lives on the bill
    self:triggerMonthlySalaryDialog(period)
end

--- Build the salary summary and show the dialog (or pay silently if no GUI).
---@param month number  in-game month index
function WorkerSystem:triggerMonthlySalaryDialog(month)
    -- Flush any pending interval payments silently — the bill is the single summary.
    self:processWorkerPayments(true)

    -- F223: freeze ONE immutable bill from the current accrual. This moves the accrued
    -- rows OUT of live accrual so wages earned after issuance stay distinct, and bakes
    -- the decline penalty (per-entry floor(base*1.20)) into the frozen final amounts.
    local bill = self:_freezeMonthlyBill(month)
    if bill == nil then
        self:log("Monthly salary: no costs accumulated — skipping dialog")
        self.declinedLastMonth = false
        return
    end

    local entries, total = self:_billEntries(bill)
    self:log("Monthly salary dialog triggered: month=%d, workers=%d, total=$%d", month, #entries, total)

    -- Store the billId so Pay/Decline bind to THIS exact frozen bill, never to
    -- whichever object happens to be pending when the button is clicked.
    self.pendingSalary = { billId = bill.id, entries = entries, total = total, month = month }

    if g_gui and g_client then
        self:showSalaryDialog(entries, total, month)
    else
        -- Dedicated server or no GUI — pay automatically.
        self:executeMonthlySalaryPayment()
    end
end

--- F223: freeze the current accrual into one immutable bill with per-farm parts. Each
--- part keeps its exact base rows (pre-penalty) plus the per-entry priced final, so
--- Pay/Decline bind to frozen amounts and later wages never change a displayed quote.
---@param month number  in-game period index
---@return table|nil bill  the frozen bill, or nil when nothing was accrued
function WorkerSystem:_freezeMonthlyBill(month)
    local env = g_currentMission and g_currentMission.environment
    local year = (env and env.currentYear) or 0
    local penalty = self.declinedLastMonth == true

    -- parts is a LIST (not farm-keyed): an MP->SP conversion can retarget two old
    -- parts onto one surviving farm, and each must still be consumed exactly once.
    local parts = {}
    for farmId, farmBook in pairs(self.monthlyCosts or {}) do
        local baseRows, base, final = {}, 0, 0
        for key, entry in pairs(farmBook) do
            if entry and entry.amount and entry.amount > 0 then
                baseRows[#baseRows + 1] = { key = key, name = entry.name or "Worker", amount = entry.amount }
                base = base + entry.amount
                -- Per-entry penalty floor (never compounded into principal).
                final = final + (penalty and math.floor(entry.amount * 1.20) or entry.amount)
            end
        end
        if base > 0 then
            parts[#parts + 1] = {
                farmId    = farmId,
                baseRows  = baseRows,
                base      = base,
                final     = final,
                remaining = final,
                status    = WorkerSystem.PART_UNPAID,
            }
        end
    end

    if #parts == 0 then
        return nil
    end

    local bill = {
        id             = self.nextBillId,
        issuedYear     = year,
        issuedPeriod   = month,
        penaltyApplied = penalty,
        parts          = parts,
    }
    self.nextBillId = self.nextBillId + 1
    self.salaryBills[bill.id] = bill

    -- Move rows OUT of live accrual; wages after issuance accrue into a fresh book.
    -- The penalty (if any) is now baked into this bill, so clear the carry-over flag.
    self.monthlyCosts = {}
    self.declinedLastMonth = false
    return bill
end

--- Per-worker display rows for a frozen bill (alphabetical), plus the bill total.
function WorkerSystem:_billEntries(bill)
    local entries, total = {}, 0
    local penalty = bill.penaltyApplied == true
    for _, part in ipairs(bill.parts or {}) do
        for _, row in ipairs(part.baseRows or {}) do
            local amount = penalty and math.floor(row.amount * 1.20) or row.amount
            entries[#entries + 1] = { name = row.name, amount = amount, farmId = part.farmId }
            total = total + amount
        end
    end
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)
    return entries, total
end

--- A bill is fully resolved when no part still owes money (UNPAID/INDETERMINATE with a
--- positive remaining). Only then is it safe to drop from the book.
function WorkerSystem:_billFullyResolved(bill)
    for _, part in ipairs(bill.parts or {}) do
        if (part.status == WorkerSystem.PART_UNPAID or part.status == WorkerSystem.PART_INDETERMINATE)
            and (part.remaining or 0) > 0 then
            return false
        end
    end
    return true
end

--- Show the salary summary to the player using the registered WCSalaryDialog screen.
function WorkerSystem:showSalaryDialog(entries, total, month)
    local capturedSelf = self
    local isPenalty    = self.declinedLastMonth

    -- Guard: dialog must be registered (client-side, post map-load)
    if g_wcSalaryDialog == nil or g_gui == nil then
        self:log("showSalaryDialog: WCSalaryDialog not registered — paying automatically")
        self:executeMonthlySalaryPayment()
        return
    end

    -- Inject data before opening
    g_wcSalaryDialog:setData(
        entries,
        total,
        month,
        isPenalty,
        function() capturedSelf:executeMonthlySalaryPayment() end,
        function() capturedSelf:declineMonthlySalary() end
    )

    -- Use showDialog, not showGui.
    -- showGui replaces the entire screen and requires the GUI stack to be idle —
    -- it fails silently when called from the console or mid-update.
    -- showDialog opens an overlay on top of whatever is currently visible,
    -- which is the correct API for popup dialogs (same as NPCFavor's DialogLoader).
    local ok, err = pcall(function()
        g_gui:showDialog(WCSalaryDialog.CLASS_NAME)
    end)

    if not ok then
        self:log("showSalaryDialog: showDialog failed: %s — paying automatically", tostring(err))
        self:executeMonthlySalaryPayment()
    end
end

--- Pay the salary bill the player just confirmed. Binds to the EXACT frozen bill id
--- stored when the dialog opened, never to whatever accrual is current now.
function WorkerSystem:executeMonthlySalaryPayment()
    if not self.pendingSalary then
        return
    end
    local billId = self.pendingSalary.billId
    local month  = self.pendingSalary.month
    self.pendingSalary = nil
    self:paySalaryBill(billId, month)
end

--- Pay the UNPAID parts of one specific frozen bill. Each farm part retires exactly
--- once on success; a native addMoney that throws leaves that part INDETERMINATE
--- (retained, never auto-retried or treated as paid). A farm with no resolvable id
--- this tick keeps its UNPAID part for a later attempt. The bill is dropped from the
--- book only when no part still owes money (Direction 4 / native addMoney has no
--- success boolean, so we validate farm/server before mutating and never fabricate).
---@param billId number|nil
---@param month number|nil  for the log line only
function WorkerSystem:paySalaryBill(billId, month)
    local bill = billId and self.salaryBills[billId]
    if bill == nil then
        return
    end

    local paidTotal, paidFarms = 0, 0
    for _, part in ipairs(bill.parts) do
        if part.status == WorkerSystem.PART_UNPAID and (part.remaining or 0) > 0 then
            local fid = self:_resolveBillingFarmId(part.farmId)
            if fid ~= nil then
                self._isProcessingPayment = true
                local ok, err = pcall(function()
                    g_currentMission:addMoney(-part.remaining, fid, MoneyType.OTHER, false)
                end)
                self._isProcessingPayment = false
                if ok then
                    paidTotal = paidTotal + part.remaining
                    paidFarms = paidFarms + 1
                    part.remaining = 0
                    part.status = WorkerSystem.PART_PAID
                else
                    -- Unknown native effect: retain evidence, do not retry or mark paid.
                    part.status = WorkerSystem.PART_INDETERMINATE
                    self:log("paySalaryBill: addMoney error farm %s: %s", tostring(fid), tostring(err))
                end
            end
        end
    end

    if self:_billFullyResolved(bill) then
        self.salaryBills[billId] = nil
    end

    if paidTotal > 0 then
        self:log("Monthly salary bill %s (month %s): paid %d across %d farm(s)",
            tostring(billId), tostring(month), paidTotal, paidFarms)
        if self.settings.showNotifications then
            local money = g_i18n and g_i18n:formatMoney(paidTotal, 0, true, true) or tostring(paidTotal)
            self:showNotification("Monthly Salary",
                string.format("Monthly salary paid: %s for %d farm(s)", money, paidFarms))
        end
    end
end

--- Called when the player declines to pay the monthly salary. F223: return only the
--- UNPAID frozen BASE rows (pre-penalty) to live accrual, so the next bill re-prices
--- them once with the existing floor(base*1.20) rule — the penalty is never compounded
--- into principal or added as a new fee. Set the global decline flag for the next bill.
function WorkerSystem:declineMonthlySalary()
    if not self.pendingSalary then
        return
    end
    local billId = self.pendingSalary.billId
    local total  = self.pendingSalary.total
    local month  = self.pendingSalary.month
    self.pendingSalary = nil

    local bill = billId and self.salaryBills[billId]
    if bill then
        for _, part in ipairs(bill.parts) do
            if part.status == WorkerSystem.PART_UNPAID then
                for _, row in ipairs(part.baseRows or {}) do
                    self:_accrueRow(part.farmId, row.key, row.name, row.amount)
                end
                -- This part's obligation is back in accrual; it no longer owes on the bill.
                part.remaining = 0
                part.status = WorkerSystem.PART_PAID  -- resolved-off-bill (moved to accrual)
            end
        end
        -- Drop the bill once nothing on it still owes (PAID/returned parts only).
        if self:_billFullyResolved(bill) then
            self.salaryBills[billId] = nil
        end
    end

    self.declinedLastMonth = true
    self:log("Monthly salary DECLINED: month=%s, total=$%d — penalty applies next bill", tostring(month), total)

    if self.settings.showNotifications then
        local money = g_i18n and g_i18n:formatMoney(total, 0, true, true) or tostring(total)
        self:showNotification("Monthly Salary Declined",
            string.format("Warning: %s salary declined — workers will demand 20%% more next month!", money))
    end
end

-- ─────────────────────────────────────────────────────────
-- Monthly salary persistence
-- Monthly mode accrues wages across the month and settles once at month end, so
-- the accrual (monthlyCosts) plus the paid-marker (lastMonthPaid) and the decline
-- carry-over flag must survive a mid-month save/reload, or a reload would silently
-- drop the wages owed so far. Server-side only (wage billing is server-gated) and
-- written to its own isolated file so a bad write can never corrupt the roster.
-- ─────────────────────────────────────────────────────────
WorkerSystem.MONTHLY_SAVE_FILE      = "workerMonthlySalary.xml"
WorkerSystem.MONTHLY_SAVE_ROOT      = "workerMonthlySalary"
-- F223 schema 2: nested per-farm accrual, frozen bills with per-farm parts + base
-- rows, the issuance ordinal and nextBillId, and retained legacy-unattributed rows.
-- Schema 1 (flat worker rows) is migrated on load, never rewritten in place.
WorkerSystem.MONTHLY_SCHEMA_VERSION = "2"

function WorkerSystem:saveMonthlyState(missionInfo)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir then
        return false
    end

    local path = dir .. "/" .. WorkerSystem.MONTHLY_SAVE_FILE
    local xmlFile = XMLFile.create("wc_MonthlyXML", path, WorkerSystem.MONTHLY_SAVE_ROOT)
    if xmlFile == nil then
        self:log("Monthly salary save failed to create file: %s", path)
        return false
    end

    local root = WorkerSystem.MONTHLY_SAVE_ROOT
    xmlFile:setString(root .. "#version", WorkerSystem.MONTHLY_SCHEMA_VERSION)
    xmlFile:setInt(root .. "#lastIssuedOrdinal", self.lastIssuedOrdinal or -1)
    xmlFile:setInt(root .. "#nextBillId", self.nextBillId or 1)
    xmlFile:setInt(root .. "#lastMonthPaid", self.lastMonthPaid or -1)  -- legacy mirror
    xmlFile:setBool(root .. "#declinedLastMonth", self.declinedLastMonth == true)

    -- Unbilled accrual, nested farm -> worker (explicit-empty is a valid save).
    local fi = 0
    for farmId, farmBook in pairs(self.monthlyCosts or {}) do
        local hasRows = false
        for _, e in pairs(farmBook) do
            if e and e.amount and e.amount > 0 then hasRows = true; break end
        end
        if hasRows and self:_isRealFarmId(farmId) then
            local fkey = string.format("%s.accrual.farm(%d)", root, fi)
            xmlFile:setInt(fkey .. "#id", farmId)
            local wi = 0
            for key, entry in pairs(farmBook) do
                if entry and entry.amount and entry.amount > 0 then
                    local wkey = string.format("%s.worker(%d)", fkey, wi)
                    xmlFile:setString(wkey .. "#key", tostring(key))
                    xmlFile:setString(wkey .. "#name", entry.name or "Worker")
                    xmlFile:setInt(wkey .. "#amount", math.floor(entry.amount))
                    wi = wi + 1
                end
            end
            fi = fi + 1
        end
    end

    -- Frozen bills with per-farm parts and their exact base rows.
    local bi = 0
    for _, bill in pairs(self.salaryBills or {}) do
        local bkey = string.format("%s.bills.bill(%d)", root, bi)
        xmlFile:setInt(bkey .. "#id", bill.id)
        xmlFile:setInt(bkey .. "#issuedYear", bill.issuedYear or 0)
        xmlFile:setInt(bkey .. "#issuedPeriod", bill.issuedPeriod or 0)
        xmlFile:setBool(bkey .. "#penaltyApplied", bill.penaltyApplied == true)
        local pi = 0
        for _, part in ipairs(bill.parts or {}) do
            local pkey = string.format("%s.part(%d)", bkey, pi)
            xmlFile:setInt(pkey .. "#farmId", part.farmId or 0)
            xmlFile:setInt(pkey .. "#base", math.floor(part.base or 0))
            xmlFile:setInt(pkey .. "#final", math.floor(part.final or 0))
            xmlFile:setInt(pkey .. "#remaining", math.floor(part.remaining or 0))
            xmlFile:setString(pkey .. "#status", part.status or WorkerSystem.PART_UNPAID)
            local ri = 0
            for _, row in ipairs(part.baseRows or {}) do
                local rkey = string.format("%s.row(%d)", pkey, ri)
                xmlFile:setString(rkey .. "#key", tostring(row.key))
                xmlFile:setString(rkey .. "#name", row.name or "Worker")
                xmlFile:setInt(rkey .. "#amount", math.floor(row.amount or 0))
                ri = ri + 1
            end
            pi = pi + 1
        end
        bi = bi + 1
    end

    -- Retained legacy-unattributed rows (evidence only; never charged or defaulted).
    local li = 0
    for _, row in ipairs(self.legacyUnattributed or {}) do
        local lkey = string.format("%s.legacyUnattributed.row(%d)", root, li)
        xmlFile:setString(lkey .. "#id", tostring(row.id))
        xmlFile:setString(lkey .. "#name", row.name or "Worker")
        xmlFile:setInt(lkey .. "#amount", math.floor(row.amount or 0))
        if row.recordedFarmId ~= nil then
            xmlFile:setInt(lkey .. "#recordedFarmId", row.recordedFarmId)
        end
        li = li + 1
    end

    xmlFile:save()
    xmlFile:delete()
    return true
end

function WorkerSystem:loadMonthlyState(missionInfo)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir then
        return false
    end

    local path = dir .. "/" .. WorkerSystem.MONTHLY_SAVE_FILE
    local xmlFile = XMLFile.loadIfExists("wc_MonthlyXML", path, WorkerSystem.MONTHLY_SAVE_ROOT)
    if xmlFile == nil then
        return false  -- new career or immediate-mode save: nothing to restore
    end

    local root = WorkerSystem.MONTHLY_SAVE_ROOT
    local version = xmlFile:getString(root .. "#version") or "1"

    -- Read everything into temporary state, validate, then install once. Never
    -- overwrite a live book on a repeated load (Direction 7).
    local accrual, bills, legacy = {}, {}, {}
    local declined           = xmlFile:getBool(root .. "#declinedLastMonth", false)
    local legacyLastMonthPaid = xmlFile:getInt(root .. "#lastMonthPaid", -1)
    local nextBillId         = 1
    local lastIssuedOrdinal  = -1

    if version == WorkerSystem.MONTHLY_SCHEMA_VERSION then
        lastIssuedOrdinal = xmlFile:getInt(root .. "#lastIssuedOrdinal", -1)
        nextBillId        = xmlFile:getInt(root .. "#nextBillId", 1)

        xmlFile:iterate(root .. ".accrual.farm", function(_, fkey)
            local farmId = xmlFile:getInt(fkey .. "#id", 0)
            if self:_isRealFarmId(farmId) then
                local book = accrual[farmId] or {}
                xmlFile:iterate(fkey .. ".worker", function(_, wkey)
                    local key    = xmlFile:getString(wkey .. "#key")
                    local name   = xmlFile:getString(wkey .. "#name") or "Worker"
                    local amount = xmlFile:getInt(wkey .. "#amount", 0)
                    if key and amount > 0 then
                        local existing = book[key]
                        if existing then existing.amount = existing.amount + amount
                        else book[key] = { name = name, amount = amount } end
                    end
                end)
                if next(book) ~= nil then accrual[farmId] = book end
            end
        end)

        xmlFile:iterate(root .. ".bills.bill", function(_, bkey)
            local id = xmlFile:getInt(bkey .. "#id", 0)
            if id and id > 0 then
                local bill = {
                    id             = id,
                    issuedYear     = xmlFile:getInt(bkey .. "#issuedYear", 0),
                    issuedPeriod   = xmlFile:getInt(bkey .. "#issuedPeriod", 0),
                    penaltyApplied = xmlFile:getBool(bkey .. "#penaltyApplied", false),
                    parts          = {},
                }
                xmlFile:iterate(bkey .. ".part", function(_, pkey)
                    local part = {
                        farmId    = xmlFile:getInt(pkey .. "#farmId", 0),
                        base      = xmlFile:getInt(pkey .. "#base", 0),
                        final     = xmlFile:getInt(pkey .. "#final", 0),
                        remaining = xmlFile:getInt(pkey .. "#remaining", 0),
                        status    = xmlFile:getString(pkey .. "#status") or WorkerSystem.PART_UNPAID,
                        baseRows  = {},
                    }
                    xmlFile:iterate(pkey .. ".row", function(_, rkey)
                        local k = xmlFile:getString(rkey .. "#key")
                        local n = xmlFile:getString(rkey .. "#name") or "Worker"
                        local a = xmlFile:getInt(rkey .. "#amount", 0)
                        if k then part.baseRows[#part.baseRows + 1] = { key = k, name = n, amount = a } end
                    end)
                    bill.parts[#bill.parts + 1] = part
                end)
                bills[id] = bill
                if id >= nextBillId then nextBillId = id + 1 end
            end
        end)

        xmlFile:iterate(root .. ".legacyUnattributed.row", function(_, lkey)
            local amount = xmlFile:getInt(lkey .. "#amount", 0)
            if amount > 0 then
                local rf = xmlFile:getInt(lkey .. "#recordedFarmId", -1)
                legacy[#legacy + 1] = {
                    id             = xmlFile:getString(lkey .. "#id"),
                    name           = xmlFile:getString(lkey .. "#name") or "Worker",
                    amount         = amount,
                    recordedFarmId = (rf ~= -1) and rf or nil,
                }
            end
        end)
    else
        -- Schema 1 migration: flat worker rows {id, name, amount, farmId}. A valid
        -- recorded farm becomes carried unbilled accrual; a missing/invalid target is
        -- retained as legacy-unattributed evidence, never defaulted to a farm or
        -- charged to a borrower (Direction 8). Old first-farm pooling is NOT undone:
        -- a previously pooled amount keeps its whole recorded target.
        xmlFile:iterate(root .. ".worker", function(_, wkey)
            local id     = xmlFile:getString(wkey .. "#id")
            local name   = xmlFile:getString(wkey .. "#name") or "Worker"
            local amount = xmlFile:getInt(wkey .. "#amount", 0)
            local farmId = xmlFile:getInt(wkey .. "#farmId", 0)
            if amount > 0 then
                if self:_isRealFarmId(farmId) then
                    local book = accrual[farmId] or {}
                    local key  = tostring(id or name)
                    local existing = book[key]
                    if existing then existing.amount = existing.amount + amount
                    else book[key] = { name = name, amount = amount } end
                    accrual[farmId] = book
                else
                    legacy[#legacy + 1] = { id = id or name, name = name, amount = amount,
                        recordedFarmId = (farmId ~= 0) and farmId or nil }
                end
            end
        end)

        -- Direction 9: a legacy lastMonthPaid matching the currently loaded period
        -- seeds this period's issuance ordinal so we do not re-issue it; a nonmatching
        -- marker seeds nothing. New (schema 2) saves carry the exact ordinal, so this
        -- ambiguity cannot recur.
        local env = g_currentMission and g_currentMission.environment
        if env and type(env.currentPeriod) == "number" and type(env.currentYear) == "number"
            and legacyLastMonthPaid >= 1 and env.currentPeriod == legacyLastMonthPaid then
            lastIssuedOrdinal = WorkerSystem._issuanceOrdinal(env.currentYear, legacyLastMonthPaid)
        end
    end

    xmlFile:delete()

    -- Install once.
    self.monthlyCosts       = accrual
    self.salaryBills        = bills
    self.legacyUnattributed = legacy
    self.nextBillId         = math.max(1, nextBillId)
    self.lastIssuedOrdinal  = lastIssuedOrdinal
    self.declinedLastMonth  = declined
    self.lastMonthPaid      = legacyLastMonthPaid
    return true
end

--- Settle any pending monthly accrual immediately, with no dialog. Used when
--- monthly-salary mode is switched OFF mid-month so accrued wages are never
--- orphaned - the money still moves exactly once. Keeps the accrual on failure
--- (e.g. no valid farm yet) so the next update tick retries.
function WorkerSystem:settlePendingMonthlyAccrual()
    -- F223: settle per farm so a farm that cannot be charged this tick keeps its own
    -- state and retries later (money still moves exactly once). Covers both unbilled
    -- accrual and any still-owed frozen bill parts, so switching monthly mode off never
    -- orphans money. Accrual farm ids are always real (stored at accrual time).
    local paidTotal, paidFarms = 0, 0

    -- 1) Unbilled accrual, per farm.
    for farmId, farmBook in pairs(self.monthlyCosts or {}) do
        local sum = 0
        for _, entry in pairs(farmBook) do
            if entry and entry.amount and entry.amount > 0 then
                sum = sum + entry.amount
            end
        end
        if sum > 0 and self:_isRealFarmId(farmId) then
            self._isProcessingPayment = true
            local ok, err = pcall(function()
                g_currentMission:addMoney(-sum, farmId, MoneyType.OTHER, false)
            end)
            self._isProcessingPayment = false
            if ok then
                self.monthlyCosts[farmId] = nil
                paidTotal = paidTotal + sum
                paidFarms = paidFarms + 1
            else
                self:log("settlePendingMonthlyAccrual: addMoney error farm %s: %s", tostring(farmId), tostring(err))
            end
        end
    end

    -- 2) Still-owed frozen bill parts, per farm.
    for billId, bill in pairs(self.salaryBills or {}) do
        for _, part in ipairs(bill.parts) do
            if part.status == WorkerSystem.PART_UNPAID and (part.remaining or 0) > 0
                and self:_isRealFarmId(part.farmId) then
                self._isProcessingPayment = true
                local ok = pcall(function()
                    g_currentMission:addMoney(-part.remaining, part.farmId, MoneyType.OTHER, false)
                end)
                self._isProcessingPayment = false
                if ok then
                    paidTotal = paidTotal + part.remaining
                    part.remaining = 0
                    part.status = WorkerSystem.PART_PAID
                end
            end
        end
        if self:_billFullyResolved(bill) then
            self.salaryBills[billId] = nil
        end
    end

    if paidTotal > 0 then
        self.declinedLastMonth = false
        self:log("Settled pending monthly accrual after mode switch: %d (%d farm(s))", paidTotal, paidFarms)
        if self.settings.showNotifications then
            local money = g_i18n and g_i18n:formatMoney(paidTotal, 0, true, true) or tostring(paidTotal)
            self:showNotification("Worker Salary Settled",
                string.format("Pending monthly wages settled: -%s", money))
        end
    end
end

-- ─────────────────────────────────────────────────────────
-- F223: native MP-to-SP farm conversion remap
-- ─────────────────────────────────────────────────────────

--- Apply the native g_farmManager.mergedFarms (old -> surviving id) map to OUR own
--- obligations exactly once, before the owner is considered ready. Native cash/loan
--- pooling already happened in the engine; this remaps only WorkerCosts' attributed
--- accrual and frozen bill parts. Part identity and paid/indeterminate markers survive,
--- so a repeated map (or reload) cannot pool the same amount twice. Only genuinely
--- mapped origins with a real surviving target move; a missing farm alone is not a map.
---@param mergedFarms table|nil  { [oldFarmId] = survivingFarmId }
function WorkerSystem:remapMergedFarms(mergedFarms)
    if type(mergedFarms) ~= "table" then return end

    -- Accrual: move a mapped farm's worker rows onto the surviving farm. Equal worker
    -- keys (same pricing/consumption identity) combine additively; distinct keys stay
    -- distinct. Legacy-unassigned money is NOT made attributable by this map.
    local moves = {}
    for oldFarmId in pairs(self.monthlyCosts or {}) do
        local target = mergedFarms[oldFarmId]
        if target ~= nil and target ~= oldFarmId and self:_isRealFarmId(target) then
            moves[oldFarmId] = target
        end
    end
    for oldFarmId, target in pairs(moves) do
        local src = self.monthlyCosts[oldFarmId]
        self.monthlyCosts[oldFarmId] = nil
        local dst = self.monthlyCosts[target] or {}
        for key, entry in pairs(src or {}) do
            if entry and entry.amount and entry.amount > 0 then
                local existing = dst[key]
                if existing then existing.amount = existing.amount + entry.amount
                else dst[key] = { name = entry.name, amount = entry.amount } end
            end
        end
        self.monthlyCosts[target] = dst
    end

    -- Bill parts: retarget each part's farmId. Because parts are a list, two parts now
    -- belonging to one farm simply coexist and are each consumed exactly once; a PAID
    -- part keeps its status and is never revived. Original id is preserved as provenance.
    for _, bill in pairs(self.salaryBills or {}) do
        for _, part in ipairs(bill.parts or {}) do
            local target = mergedFarms[part.farmId]
            if target ~= nil and target ~= part.farmId and self:_isRealFarmId(target) then
                part.originFarmId = part.originFarmId or part.farmId
                part.farmId = target
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────
-- F223 / C3: pure payroll obligation reader (for the emergency-loan forecast)
-- ─────────────────────────────────────────────────────────

WorkerSystem.PAYROLL_CONTRACT_VERSION = 1

--- Pure, server-only reader. Returns a COPIED version-1 snapshot of this farm's dated
--- payroll cash obligations inside the supplied one-period horizon. It NEVER mutates
--- payroll state, issues, pays, flushes open work or migrates (Direction 10/12). Issued
--- unpaid bills are due-now cash events (clamped to asOf); unbilled measured work is
--- placed once at its next payable last-day boundary (FIRST_OWNER_CHECK midnight), and
--- future continuation is declared a coverage gap rather than invented. The shared date
--- contract: dueDay = native monotonic day, dueTimeMs = ms since midnight.
---@param farmId number
---@param horizon table  { asOf = {monotonicDay, timeOfDayMs}, horizonEnd = {monotonicDay, timeOfDayMs}, daysPerPeriod, dayInPeriod }
---@return table  version-1 payroll obligations snapshot (copied; never aliases live state)
function WorkerSystem:getPayrollObligations(farmId, horizon)
    local enabled = (self.settings and self.settings.monthlySalaryEnabled) == true
    local result = {
        version         = WorkerSystem.PAYROLL_CONTRACT_VERSION,
        status          = "UNAVAILABLE",
        farmId          = farmId,
        asOf            = nil,
        enabled         = enabled,
        settlementMode  = enabled and "MONTHLY" or "IMMEDIATE",
        coverageReasons = {},
        events          = {},
    }
    local function gap(reason) result.coverageReasons[#result.coverageReasons + 1] = reason end

    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        gap("NOT_SERVER")
        return result
    end
    if not self:_isRealFarmId(farmId) then
        gap("INVALID_FARM")
        return result
    end

    -- Validate the supplied date contract; an invalid clock is unavailable, not zero.
    local asOf = horizon and horizon.asOf
    if type(asOf) ~= "table" or type(asOf.monotonicDay) ~= "number" or type(asOf.timeOfDayMs) ~= "number"
        or asOf.monotonicDay < 0 or asOf.monotonicDay % 1 ~= 0
        or asOf.timeOfDayMs < 0 or asOf.timeOfDayMs >= 86400000 then
        gap("INVALID_ASOF")
        return result
    end
    result.asOf = { monotonicDay = asOf.monotonicDay, timeOfDayMs = asOf.timeOfDayMs }

    local daysPerPeriod = horizon.daysPerPeriod
    local dayInPeriod   = horizon.dayInPeriod
    local endDay        = horizon.horizonEnd and horizon.horizonEnd.monotonicDay
    local endTimeMs     = horizon.horizonEnd and horizon.horizonEnd.timeOfDayMs

    local function withinHorizon(dueDay, dueTimeMs)
        if type(endDay) ~= "number" then return true end
        if dueDay < endDay then return true end
        if dueDay > endDay then return false end
        return dueTimeMs <= (endTimeMs or 0)
    end

    -- 1) Issued unpaid bills for this farm: due now, clamped to asOf.
    for _, bill in pairs(self.salaryBills or {}) do
        local sum, indeterminate = 0, false
        for _, part in ipairs(bill.parts or {}) do
            if part.farmId == farmId then
                if part.status == WorkerSystem.PART_UNPAID and (part.remaining or 0) > 0 then
                    sum = sum + part.remaining
                elseif part.status == WorkerSystem.PART_INDETERMINATE then
                    indeterminate = true
                end
            end
        end
        if indeterminate then gap("BILL_INDETERMINATE") end
        if sum > 0 and withinHorizon(asOf.monotonicDay, asOf.timeOfDayMs) then
            result.events[#result.events + 1] = {
                sourceKey       = "payroll:bill:" .. tostring(bill.id),
                dueDay          = asOf.monotonicDay,
                dueTimeMs       = asOf.timeOfDayMs,
                timingBasis     = "ISSUED_DUE_NOW",
                fixedAmount     = sum,
                estimatedAmount = 0,
                basis           = "ISSUED_BILL",
                componentIds    = { "bill:" .. tostring(bill.id) },
            }
        end
    end

    -- 2) Unbilled measured accrual for this farm: one event at the next payable last day
    -- (or due-now at asOf if today is the last day and this period has not yet issued).
    local accruedNow = 0
    local farmBook = self.monthlyCosts[farmId]
    if farmBook then
        for _, entry in pairs(farmBook) do
            if entry and entry.amount and entry.amount > 0 then accruedNow = accruedNow + entry.amount end
        end
    end
    if accruedNow > 0 then
        if type(daysPerPeriod) == "number" and type(dayInPeriod) == "number"
            and daysPerPeriod >= 1 and dayInPeriod >= 1 and dayInPeriod <= daysPerPeriod then
            local offset = daysPerPeriod - dayInPeriod
            if offset == 0 then
                -- Today is the last day; if this period already issued, the next payable
                -- boundary is a full period out, not another due-now bill.
                local env = g_currentMission.environment
                if env and type(env.currentYear) == "number" and type(env.currentPeriod) == "number" then
                    local ordinal = WorkerSystem._issuanceOrdinal(env.currentYear, env.currentPeriod)
                    if self.lastIssuedOrdinal == ordinal then
                        offset = daysPerPeriod
                    end
                end
            end
            local dueDay    = asOf.monotonicDay + offset
            local dueTimeMs = (offset == 0) and asOf.timeOfDayMs or 0  -- FIRST_OWNER_CHECK midnight
            if withinHorizon(dueDay, dueTimeMs) then
                result.events[#result.events + 1] = {
                    sourceKey       = "payroll:unbilled:" .. tostring(farmId),
                    dueDay          = dueDay,
                    dueTimeMs       = dueTimeMs,
                    timingBasis     = (offset == 0) and "DUE_NOW" or "FIRST_OWNER_CHECK",
                    fixedAmount     = accruedNow,
                    estimatedAmount = 0,
                    basis           = "UNBILLED_MEASURED",
                    componentIds    = { "unbilled" },
                }
            end
            -- Future crew continuation needs live job area; declare the gap, never invent.
            gap("FUTURE_CONTINUATION_UNESTIMATED")
        else
            gap("NO_CALENDAR_FOR_UNBILLED")
        end
    end

    -- Sort events by due day/time for a stable consumer view.
    table.sort(result.events, function(a, b)
        if a.dueDay ~= b.dueDay then return a.dueDay < b.dueDay end
        return a.dueTimeMs < b.dueTimeMs
    end)

    result.status = (#result.coverageReasons > 0) and "PARTIAL" or "OK"
    return result
end

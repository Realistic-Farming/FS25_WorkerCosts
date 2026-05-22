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
WorkerSystem = {}
local WorkerSystem_mt = Class(WorkerSystem)

---@param settings Settings
---@return WorkerSystem
function WorkerSystem.new(settings)
    local self = setmetatable({}, WorkerSystem_mt)
    self.settings = settings
    self.activeWorkers = {}
    self.workerHours = {}      -- accumulated real hours per vehicleId since last payment
    self.workerHectares = {}   -- accumulated hectares per vehicleId since last payment
    self.workerNames = {}      -- last-known display name per vehicleId (for dismissed workers)
    -- Use real-time dt for ALL timing, NOT environment.dayTime.
    -- dayTime advances ~48x faster than real time at speed x1, which caused
    -- wages to be ~20x too high before this fix.
    self.realTimeAccumulator = 0   -- real ms accumulated since last payment
    self.paymentInterval = 300000  -- 5 real-world minutes in real milliseconds
    self.isInitialized = false
    self._isProcessingPayment = false
    self._originalAddMoney = nil   -- stored so we can restore on delete
    self._hookedAddMoney = false

    -- Monthly salary tracking
    -- monthlyCosts[workerName] = accumulated amount for this month
    self.monthlyCosts   = {}
    self.lastDay        = -1       -- last in-game day we checked
    self.lastMonthPaid  = -1       -- last in-game month that triggered the salary dialog
    self.declinedLastMonth = false -- true if player skipped last month's payment
    self.pendingSalary  = nil      -- { entries, total, month } stored while dialog is open

    return self
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
        self.realTimeAccumulator = 0

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

        if capturedSelf.settings.enabled and amount < 0 then
            -- Primary: MoneyType.AI is what AIJob uses for helper wages.
            local isHelperWage = (capturedAIType ~= nil and moneyType == capturedAIType)

            -- Also catch MoneyType.WORKER_WAGES in case some FS25 builds use it.
            if not isHelperWage and MoneyType and MoneyType.WORKER_WAGES ~= nil then
                isHelperWage = (moneyType == MoneyType.WORKER_WAGES)
            end

            -- Fallback when MoneyType enum is unavailable: intercept small negative
            -- charges that coincide with active AI jobs (AIJob flushes at >25§ chunks).
            if not isHelperWage and capturedAIType == nil then
                local hasActiveJobs = false
                local aiSystem = g_currentMission and g_currentMission.aiSystem
                if aiSystem and aiSystem.getActiveJobs then
                    local jobs = aiSystem:getActiveJobs()
                    hasActiveJobs = (jobs ~= nil and #jobs > 0)
                end
                isHelperWage = hasActiveJobs and math.abs(amount) <= 500
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
    local playerFarmId = g_currentMission:getFarmId()
    for _, job in ipairs(activeJobs) do
        if job and job.isRunning then
            if playerFarmId and job.startedFarmId and job.startedFarmId ~= playerFarmId then
                -- skip: job belongs to a different farm
            else
                -- Get vehicle: prefer the official vehicleParameter API
                local vehicle = nil
                if job.vehicleParameter and job.vehicleParameter.getVehicle then
                    vehicle = job.vehicleParameter:getVehicle()
                elseif job.vehicle then
                    vehicle = job.vehicle
                end

                if vehicle then
                    -- Helper name: job:getHelperName() is defined on AIJob base class
                    local name = "Worker"
                    if job.getHelperName then
                        local ok, helperName = pcall(function() return job:getHelperName() end)
                        if ok and helperName and helperName ~= "" then
                            name = helperName
                        end
                    end
                    -- Fall back to vehicle name if helper name unavailable
                    if name == "Worker" then
                        name = (vehicle.getFullName and vehicle:getFullName())
                           or (vehicle.getName and vehicle:getName())
                           or "Worker"
                    end

                    table.insert(workers, {
                        vehicle = vehicle,
                        job     = job,
                        name    = name
                    })
                end
            end
        end
    end

    return workers
end

function WorkerSystem:calculateWorkerWage(worker, hoursWorked, hectaresWorked)
    local baseRate = self.settings:getWageRate()

    -- Apply skill multiplier (0.8x to 1.2x based on skill level)
    local skillMultiplier = 1.0

    -- Try to get skill from worker/job
    if worker.job and worker.job.getSkillLevel then
        local skill = worker.job:getSkillLevel() or 0.5
        skillMultiplier = 0.8 + (skill * 0.4) -- Range: 0.8 to 1.2
    end

    local wage = 0
    if self.settings.costMode == Settings.COST_MODE_HOURLY then
        wage = baseRate * hoursWorked * skillMultiplier
    else
        -- Per-hectare mode: fall back to 0 when no area was tracked.
        -- This can happen for implements that don't expose getLastHa().
        -- The caller checks wage > 0 before deducting, so free-work is the
        -- only consequence — but we log it so it's visible in debug mode.
        if hectaresWorked <= 0 then
            self:log("Per-hectare wage skipped for worker with 0 ha tracked (implement may not support getLastHa)")
        end
        wage = baseRate * hectaresWorked * skillMultiplier
    end

    return math.floor(wage)
end

-- @param silent  If true, suppresses the per-payment HUD notification.
--                Used when flushing interval payments into the monthly salary
--                summary so the dialog is the single notification, not both.
function WorkerSystem:chargeWage(workerName, amount, workType, silent)
    if not g_currentMission then
        self:log("Cannot charge wage: No mission")
        return false
    end

    if amount <= 0 then
        self:log("Cannot charge wage: Amount is zero or negative")
        return false
    end

    local farmId = g_currentMission:getFarmId()
    if not farmId or farmId == 0 then
        -- farmId 0 = spectator in multiplayer; cannot deduct from an unowned farm
        self:log("Cannot charge wage: No valid farm ID (spectator or uninitialized farm)")
        return false
    end

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
            formattedAmount = string.format("$%d", amount)
        end
        local modeText = self.settings:getCostModeName()
        local message = string.format("%s - %s: -%s", workerName, modeText, formattedAmount)

        self:showNotification("Worker Payment", message)
    end

    -- Accumulate into monthly totals for the end-of-month salary dialog
    if self.settings.monthlySalaryEnabled then
        self.monthlyCosts[workerName] = (self.monthlyCosts[workerName] or 0) + amount
    end

    self:log("%s %s wage: $%d from farm %d", workerName, workType, amount, farmId)
    return true
end

function WorkerSystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then
        return
    end

    if not g_currentMission then
        return
    end

    -- dt is real elapsed milliseconds this frame. Using it (instead of
    -- environment.dayTime) means wages scale with real time regardless of
    -- the in-game time-speed setting, which fixes the ~20x overcharge bug.
    local activeWorkers = self:getActiveWorkers()

    -- Accumulate real hours worked per active worker this frame.
    -- 1 real hour = 3,600,000 real ms.
    local realHoursThisFrame = dt / 3600000

    for _, worker in ipairs(activeWorkers) do
        local vehicleId = tostring(worker.vehicle)

        -- Initialize tracking for newly-detected workers
        if not self.workerHours[vehicleId] then
            self.workerHours[vehicleId] = 0
            self.workerHectares[vehicleId] = 0
            self:log("Started tracking worker: %s", worker.name)
        end
        -- Always refresh the name so dismissed-worker payments use the latest value
        self.workerNames[vehicleId] = worker.name

        self.workerHours[vehicleId] = self.workerHours[vehicleId] + realHoursThisFrame

        -- Track hectares if the job exposes them
        if worker.job and worker.job.getLastHa then
            local hectares = worker.job:getLastHa() or 0
            self.workerHectares[vehicleId] = self.workerHectares[vehicleId] + hectares
        end
    end

    -- Payment timer: fire every paymentInterval real milliseconds.
    -- Subtract rather than reset so we don't drift over time.
    self.realTimeAccumulator = self.realTimeAccumulator + dt
    if self.realTimeAccumulator >= self.paymentInterval then
        self:processWorkerPayments()
        self.realTimeAccumulator = self.realTimeAccumulator - self.paymentInterval
    end

    -- Monthly salary: check if the last day of the month has just been reached
    if self.settings.monthlySalaryEnabled then
        self:checkMonthEnd()
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
                local wage = self:calculateWorkerWage(worker, hoursWorked, hectaresWorked)

                if wage > 0 then
                    self:chargeWage(worker.name, wage, self.settings:getCostModeName(), silent)
                    totalPaid = totalPaid + wage
                    workersCount = workersCount + 1
                end
            end

            -- Always reset so the next interval starts clean
            self.workerHours[vehicleId] = 0
            self.workerHectares[vehicleId] = 0
        end
    end

    -- Pay workers that were dismissed mid-interval (accumulated time but no longer active).
    -- Without this, any time worked since the last payment tick is silently lost.
    -- NOTE: We construct a minimal pseudo-worker table so we can reuse calculateWorkerWage()
    -- and avoid duplicating the wage formula here.
    for vehicleId, hoursWorked in pairs(self.workerHours) do
        if not activeIds[vehicleId] and (hoursWorked > 0 or (self.workerHectares[vehicleId] or 0) > 0) then
            local hectaresWorked = self.workerHectares[vehicleId] or 0
            -- Use a bare pseudo-worker so calculateWorkerWage applies the same
            -- formula (including any future changes) as for active workers.
            -- Dismissed workers have no job object, so skillMultiplier defaults to 1.0.
            local pseudoWorker = {}
            local wage = self:calculateWorkerWage(pseudoWorker, hoursWorked, hectaresWorked)

            if wage > 0 then
                local name = self.workerNames[vehicleId] or "Dismissed Worker"
                self:chargeWage(name, wage, self.settings:getCostModeName(), silent)
                totalPaid = totalPaid + wage
                workersCount = workersCount + 1
            end

            -- Remove stale entries to prevent unbounded table growth
            self.workerHours[vehicleId]    = nil
            self.workerHectares[vehicleId] = nil
            self.workerNames[vehicleId]    = nil
        end
    end

    if workersCount > 0 then
        self:log("Paid %d worker(s) a total of $%d", workersCount, totalPaid)
    end
end

function WorkerSystem:testPayment()
    -- chargeWage already handles the notification, so no extra call needed here
    return self:chargeWage("Test Worker", 100, "test")
end

-- ─────────────────────────────────────────────────────────
-- Monthly salary system
-- ─────────────────────────────────────────────────────────

--- Called every update tick when monthlySalaryEnabled is true.
-- Detects the transition to the last day of the month (day 28 in FS25
-- which uses 28-day months) and triggers the salary dialog once.
function WorkerSystem:checkMonthEnd()
    if not g_currentMission or not g_currentMission.environment then
        return
    end
    local env = g_currentMission.environment

    -- FS25 months have 28 in-game days (1..28).
    -- We trigger on day 28 so that the player pays before the month rolls over.
    local currentDay   = env.currentDay         -- 1-based day within the current year
    local currentMonth = env.currentPeriod      -- 1-based period/month index

    if currentDay == nil or currentMonth == nil then
        return
    end

    -- Only fire once per month
    if currentMonth == self.lastMonthPaid then
        return
    end

    -- Days per month in FS25 = 28 (7 periods × 28 days each → 196-day year).
    -- env.currentDay is the absolute day of the year (1-196).
    -- Last day of each period = period * 28.
    local lastDayOfThisMonth = currentMonth * 28

    -- Fire once when the last day of the period is reached.
    -- The outer `currentMonth == self.lastMonthPaid` check above already
    -- prevents re-entry for the same month, so no inner guard is needed.
    if currentDay >= lastDayOfThisMonth then
        self.lastMonthPaid = currentMonth
        self:triggerMonthlySalaryDialog(currentMonth)
    end
end

--- Build the salary summary and show the dialog (or pay silently if no GUI).
---@param month number  in-game month index
function WorkerSystem:triggerMonthlySalaryDialog(month)
    -- Flush any pending interval payments silently — the monthly dialog is
    -- the single summary notification. Per-payment alerts here would be noise.
    self:processWorkerPayments(true)

    -- Build the entry list
    local entries = {}
    local total   = 0

    for workerName, amount in pairs(self.monthlyCosts) do
        if amount > 0 then
            -- Apply 20 % late-payment penalty if player declined last month
            local finalAmount = amount
            if self.declinedLastMonth then
                finalAmount = math.floor(amount * 1.20)
                self:log("Late-pay penalty applied to %s: $%d -> $%d", workerName, amount, finalAmount)
            end
            table.insert(entries, { name = workerName, amount = finalAmount })
            total = total + finalAmount
        end
    end

    -- Sort alphabetically for consistent display
    table.sort(entries, function(a, b) return a.name < b.name end)

    if total == 0 then
        self:log("Monthly salary: no costs accumulated — skipping dialog")
        self.monthlyCosts = {}
        self.declinedLastMonth = false
        return
    end

    self:log("Monthly salary dialog triggered: month=%d, workers=%d, total=$%d", month, #entries, total)

    -- Store for the callbacks
    self.pendingSalary = { entries = entries, total = total, month = month }

    -- Try to show the in-game GUI dialog; fall back to silent payment on dedicated/headless
    if g_gui and g_client then
        self:showSalaryDialog(entries, total, month)
    else
        -- Dedicated server or no GUI — pay automatically
        self:executeMonthlySalaryPayment()
    end
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

--- Deduct the monthly salary from the farm balance.
function WorkerSystem:executeMonthlySalaryPayment()
    if not self.pendingSalary then
        return
    end

    local entries = self.pendingSalary.entries
    local total   = self.pendingSalary.total
    local month   = self.pendingSalary.month
    self.pendingSalary = nil

    if total <= 0 then
        self.monthlyCosts      = {}
        self.declinedLastMonth = false
        return
    end

    -- Charge as a single lump sum (using OTHER so our hook passes it through)
    local farmId = g_currentMission and g_currentMission:getFarmId()
    if not farmId or farmId == 0 then
        self:log("executeMonthlySalaryPayment: no valid farmId, skipping")
        self.monthlyCosts      = {}
        self.declinedLastMonth = false
        return
    end

    self._isProcessingPayment = true
    local ok, err = pcall(function()
        g_currentMission:addMoney(-total, farmId, MoneyType.OTHER, false)
    end)
    self._isProcessingPayment = false

    if not ok then
        self:log("executeMonthlySalaryPayment: addMoney error: %s", tostring(err))
    else
        self:log("Monthly salary paid: month=%d, workers=%d, total=$%d", month, #entries, total)

        if self.settings.showNotifications then
            local msg = string.format("Monthly salary paid: $%d for %d worker(s)", total, #entries)
            self:showNotification("Monthly Salary", msg)
        end
    end

    -- Reset for next month
    self.monthlyCosts      = {}
    self.declinedLastMonth = false
end

--- Called when the player declines to pay the monthly salary.
function WorkerSystem:declineMonthlySalary()
    if not self.pendingSalary then
        return
    end

    local total = self.pendingSalary.total
    local month = self.pendingSalary.month
    self.pendingSalary = nil

    self:log("Monthly salary DECLINED: month=%d, total=$%d — penalty will apply next month", month, total)

    if self.settings.showNotifications then
        self:showNotification("Monthly Salary Declined",
            string.format("Warning: $%d salary declined — workers will demand 20%% more next month!", total))
    end

    -- Keep monthlyCosts so the unpaid amounts carry over and are penalised next month
    self.declinedLastMonth = true
end

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
---@class WorkerSettingsGUI

WorkerSettingsGUI = {}
local WorkerSettingsGUI_mt = Class(WorkerSettingsGUI)

function WorkerSettingsGUI.new()
    local self = setmetatable({}, WorkerSettingsGUI_mt)
    return self
end

function WorkerSettingsGUI:registerConsoleCommands()
    addConsoleCommand("WorkerCostsSetWageLevel", "Set wage level (1=Low, 2=Medium, 3=High)", "consoleCommandSetWageLevel", self)
    
    addConsoleCommand("WorkerCostsEnable", "Enable Worker Costs Mod", "consoleCommandWorkerCostsEnable", self)
    addConsoleCommand("WorkerCostsDisable", "Disable Worker Costs Mod", "consoleCommandWorkerCostsDisable", self)
    addConsoleCommand("WorkerCostsSetCostMode", "Set cost mode (1=Hourly, 2=Per Hectare)", "consoleCommandSetCostMode", self)
    addConsoleCommand("WorkerCostsSetNotifications", "Enable/disable notifications (true/false)", "consoleCommandSetNotifications", self)
    addConsoleCommand("WorkerCostsSetCustomRate", "Set custom wage rate (0 = use wage level)", "consoleCommandSetCustomRate", self)
    addConsoleCommand("WorkerCostsTestPayment", "Test wage payment system", "consoleCommandTestPayment", self)
    addConsoleCommand("WorkerCostsDebug", "Enable/disable debug mode (true/false)", "consoleCommandSetDebug", self)

    addConsoleCommand("WorkerCostsMonthlySalary", "Enable/disable monthly salary dialog (true/false)", "consoleCommandSetMonthlySalary", self)
    addConsoleCommand("WorkerCostsTestMonthlySalary", "Trigger monthly salary dialog right now (for testing)", "consoleCommandTestMonthlySalary", self)
    
    addConsoleCommand("WorkerCostsShowSettings", "Show current settings", "consoleCommandShowSettings", self)
    addConsoleCommand("WorkerCostsShowRoster", "Show the Pro-Staff worker roster (id, name, level, hours, jobs, XP)", "consoleCommandShowRoster", self)
    addConsoleCommand("WorkerCostsHallState", "Show each worker's HireHallCore lifecycle state + dispatch availability", "consoleCommandHallState", self)
    addConsoleCommand("WorkerCostsRoster", "Open/close the clickable roster panel (hire/fire/assign)", "consoleCommandRosterPanel", self)
    addConsoleCommand("WorkerCostsGrantXP", "TESTING: add XP (=hours) to all roster workers; recomputes level (Experienced=40, Master=160)", "consoleCommandGrantXP", self)
    addConsoleCommand("WorkerCostsHire", "Hire a worker by name (Pro-Staff)", "consoleCommandHire", self)
    addConsoleCommand("WorkerCostsFire", "Fire a worker by id; pays severance (Pro-Staff)", "consoleCommandFire", self)
    addConsoleCommand("WorkerCostsAssign", "Pin worker <id> to the vehicle you are seated in (Pro-Staff)", "consoleCommandAssign", self)
    addConsoleCommand("WorkerCostsUnassign", "Remove worker <id>'s vehicle pin (Pro-Staff)", "consoleCommandUnassign", self)
    addConsoleCommand("WorkerCostsDiagnostic", "Run full diagnostic report", "consoleCommandDiagnostic", self)
    
    addConsoleCommand("WorkerCostsResetSettings", "Reset all settings to defaults", "consoleCommandResetSettings", self)
    
    addConsoleCommand("workerCosts", "Show all worker costs commands", "consoleCommandHelp", self)
    addConsoleCommand("workerCostsStatus", "Show current mod status", "consoleCommandShowSettings", self)

    Logging.info("Worker Costs Mod console commands registered")
end

function WorkerSettingsGUI:consoleCommandHelp()
    print("=== Worker Costs Mod Console Commands ===")
    print("workerCosts - Show this help")
    print("WorkerCostsEnable/Disable - Toggle mod")
    print("WorkerCostsSetWageLevel 1|2|3 - Set wage level")
    print("WorkerCostsSetCostMode 1|2 - Set payment mode")
    print("WorkerCostsSetNotifications true|false - Toggle notifications")
    print("WorkerCostsSetCustomRate <rate> - Set custom rate (0 for default)")
    print("WorkerCostsTestPayment - Test payment system")
    print("WorkerCostsDebug true|false - Toggle debug logging")
    print("WorkerCostsShowSettings - Show current settings")
    print("WorkerCostsShowRoster - Show the worker roster")
    print("WorkerCostsRoster - Open the clickable roster panel (or press ALT+H)")
    print("WorkerCostsGrantXP <xp> - TESTING: grant XP to all workers")
    print("WorkerCostsHire <name> - Hire a worker")
    print("WorkerCostsFire <id> - Fire a worker (pays severance)")
    print("WorkerCostsAssign <id> - Pin worker to your current vehicle")
    print("WorkerCostsUnassign <id> - Remove a worker's vehicle pin")
    print("WorkerCostsDiagnostic - Run full diagnostic report")
    print("WorkerCostsResetSettings - Reset to defaults")
    print("===========================================")
    return "Type 'workerCosts' for more info"
end

function WorkerSettingsGUI:consoleCommandSetWageLevel(wageLevel)
    local level = tonumber(wageLevel)
    if not level or level < 1 or level > 3 then
        Logging.warning("Invalid wage level. Use 1 (Low), 2 (Medium), or 3 (High)")
        return "Invalid wage level"
    end
    
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings:setWageLevel(level)
        g_WorkerManager.settings:save()
        return string.format("Wage level set to: %s ($%d/h)", 
            g_WorkerManager.settings:getWageLevelName(),
            g_WorkerManager.settings:getWageRate())
    end
    
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandWorkerCostsEnable()
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings.enabled = true
        g_WorkerManager.settings:save()
        
        if g_WorkerManager.workerSystem then
            g_WorkerManager.workerSystem:initialize()
        end
        
        return "Worker Costs Mod enabled"
    end
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandWorkerCostsDisable()
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings.enabled = false
        g_WorkerManager.settings:save()
        return "Worker Costs Mod disabled"
    end
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandSetCostMode(mode)
    local costMode = tonumber(mode)
    if not costMode or (costMode ~= 1 and costMode ~= 2) then
        return "Invalid cost mode. Use 1 (Hourly) or 2 (Per Hectare)"
    end
    
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings:setCostMode(costMode)
        g_WorkerManager.settings:save()
        return string.format("Cost mode set to: %s", g_WorkerManager.settings:getCostModeName())
    end
    
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandSetNotifications(enabled)
    if enabled == nil then
        return "Usage: WorkerCostsSetNotifications true|false"
    end
    
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then
        return "Invalid value. Use 'true' or 'false'"
    end
    
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings.showNotifications = (enable == "true")
        g_WorkerManager.settings:save()
        return string.format("Notifications %s", g_WorkerManager.settings.showNotifications and "enabled" or "disabled")
    end
    
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandSetCustomRate(rate)
    local customRate = tonumber(rate)
    if not customRate or customRate < 0 then
        return "Invalid rate. Use a positive number or 0 to use wage level setting"
    end
    
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings.customRate = customRate
        g_WorkerManager.settings:save()
        if customRate > 0 then
            local unit = (g_WorkerManager.settings.costMode == Settings.COST_MODE_HOURLY) and "/h" or "/ha"
            return string.format("Custom rate set to: $%d%s", customRate, unit)
        else
            return "Custom rate disabled, using wage level setting"
        end
    end
    
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandTestPayment()
    if g_WorkerManager and g_WorkerManager.settings then
        if g_WorkerManager.workerSystem then
            local success = g_WorkerManager.workerSystem:testPayment()
            if success then
                return "Test payment executed (-$100)"
            else
                return "Test payment failed"
            end
        end
    end
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandShowSettings()
    if g_WorkerManager and g_WorkerManager.settings then
        local settings = g_WorkerManager.settings
        local unit = settings.costMode == Settings.COST_MODE_HOURLY and "/h" or "/ha"
        local info = string.format(
            "=== Worker Costs Mod Settings ===\n" ..
            "Enabled: %s\n" ..
            "Debug Mode: %s\n" ..
            "Cost Mode: %s\n" ..
            "Wage Level: %s\n" ..
            "Wage Rate: $%d%s\n" ..
            "Notifications: %s\n" ..
            "Custom Rate: %s\n" ..
            "Monthly Salary: %s\n" ..
            "================================",
            tostring(settings.enabled),
            tostring(settings.debugMode),
            settings:getCostModeName(),
            settings:getWageLevelName(),
            settings:getWageRate(), unit,
            tostring(settings.showNotifications),
            settings.customRate > 0 and string.format("$%d%s", settings.customRate, unit) or "off (use wage level)",
            tostring(settings.monthlySalaryEnabled)
        )
        print(info)
        return info
    end

    return "Error: Worker Costs Mod not initialized"
end

-- Pro-Staff (Phase 0/1) read-only roster dump. Server/SP holds the authoritative
-- roster; on an MP client this prints whatever has been synced (nothing until
-- Phase 5). A handy way to verify auto-hire + hours/jobs/XP accrual.
function WorkerSettingsGUI:consoleCommandShowRoster()
    if g_WorkerManager == nil or g_WorkerManager.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end

    local roster = g_WorkerManager.workerRoster
    local workers = roster:getAll()
    local lines = { string.format("=== Worker Roster (%d) ===", #workers) }

    if #workers == 0 then
        table.insert(lines, "(empty — start an AI helper to auto-hire one)")
    else
        for _, w in ipairs(workers) do
            local status = w.assignedVehicleId and "[working]" or "[idle]"
            if w.assignedVehicleUniqueId then
                status = status .. " pinned"
            end
            table.insert(lines, string.format(
                "#%d  %-16s  %-11s  hrs=%.2f  jobs=%d  XP=%.1f  fat=%d%%  %s",
                w.uuid, w.name or "Worker", WorkerRoster.levelName(w.level),
                w.totalHours or 0, w.totalJobs or 0, w.totalXP or 0,
                math.floor((w.fatigue or 0) * 100),
                status
            ))
        end
    end
    table.insert(lines, "==========================")

    local out = table.concat(lines, "\n")
    print(out)
    return out
end

-- HireHallCore (Phase 1) has no UI until Phase 4, so this is how you SEE it working:
-- per-worker lifecycle state plus the availability broker's verdict + reason code.
function WorkerSettingsGUI:consoleCommandHallState()
    if g_WorkerManager == nil or g_WorkerManager.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    if HireHallCore == nil then
        return "Error: HireHallCore not loaded"
    end

    local roster = g_WorkerManager.workerRoster
    local workers = roster:getAll()
    local lines = { string.format("=== HireHallCore Lifecycle (%d) %s===",
        #workers, HireHallCore.isCorrupted and "[CORRUPTED] " or "") }

    if not HireHallCore._isHost() then
        table.insert(lines, "(client — lifecycle is host-authoritative; run this on the host)")
    elseif #workers == 0 then
        table.insert(lines, "(empty — start an AI helper to auto-hire one)")
    else
        local API = HireHallCore.core.API
        for _, w in ipairs(workers) do
            local state = HireHallCore.core.Lifecycle:getState(w)
            local available, reason = API:isWorkerAvailable(w.uuid)
            table.insert(lines, string.format(
                "#%d  %-16s  state=%-10s  fatigue=%d%%  dispatch=%s (%s)",
                w.uuid, w.name or "Worker", state,
                math.floor((w.fatigue or 0) * 100),
                available and "YES" or "no", reason
            ))
        end
    end
    table.insert(lines, "==========================")

    local out = table.concat(lines, "\n")
    print(out)
    return out
end

-- TESTING aid: grant XP to every roster worker so levels (and the wage discount /
-- fatigue immunity that ride on them) can be exercised without 40+ hours of work.
function WorkerSettingsGUI:consoleCommandGrantXP(amountStr)
    if g_WorkerManager == nil or g_WorkerManager.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    local amount = tonumber(amountStr)
    if amount == nil then
        return "Usage: WorkerCostsGrantXP <xp>   (xp == hours; Experienced=40, Master=160)"
    end
    local roster = g_WorkerManager.workerRoster
    local workers = roster:getAll()
    if #workers == 0 then
        return "Roster is empty - start an AI helper first to auto-hire a worker"
    end
    local promoted = {}
    for _, w in ipairs(workers) do
        w.totalXP = (w.totalXP or 0) + amount
        local newLevel = roster:recomputeLevel(w)
        if newLevel then
            table.insert(promoted, string.format("%s -> %s", w.name or "Worker", WorkerRoster.levelName(newLevel)))
        end
    end
    local msg = string.format("Granted %g XP to %d worker(s).", amount, #workers)
    if #promoted > 0 then
        msg = msg .. " Promotions: " .. table.concat(promoted, ", ")
    end
    print(msg)
    return msg
end

-- ---------------------------------------------------------------------------
-- Phase 5: hire / fire / assign (server/SP; MP sync is a separate sub-batch).
-- ---------------------------------------------------------------------------

function WorkerSettingsGUI:_getCurrentVehicle()
    if g_localPlayer and g_localPlayer.getCurrentVehicle then
        local ok, v = pcall(function() return g_localPlayer:getCurrentVehicle() end)
        if ok and v then return v end
    end
    if g_currentMission and g_currentMission.controlledVehicle then
        return g_currentMission.controlledVehicle
    end
    return nil
end

function WorkerSettingsGUI:consoleCommandHire(name)
    if g_WorkerManager == nil or g_WorkerManager.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    if name == nil or name == "" then
        return "Usage: WorkerCostsHire <name>"
    end
    local w = g_WorkerManager.workerRoster:createWorker(name)
    local msg = string.format("Hired '%s' (id=%d)", w.name, w.uuid)
    print(msg)
    return msg
end

function WorkerSettingsGUI:consoleCommandFire(idStr)
    local mgr = g_WorkerManager
    if mgr == nil or mgr.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    local uuid = tonumber(idStr)
    if uuid == nil then
        return "Usage: WorkerCostsFire <id>   (see WorkerCostsShowRoster)"
    end
    local w = mgr.workerRoster:getWorker(uuid)
    if w == nil then
        return string.format("No worker with id=%d", uuid)
    end
    local severance = 0
    if mgr.workerSystem then
        severance = mgr.workerSystem:chargeSeverance(w.name, w.level)
    end
    mgr.workerRoster:removeWorker(uuid)
    local money = g_i18n and g_i18n:formatMoney(severance, 0, true, true) or ("$" .. severance)
    local msg = string.format("Fired '%s' (id=%d); severance %s", w.name, uuid, money)
    print(msg)
    return msg
end

function WorkerSettingsGUI:consoleCommandAssign(idStr)
    local mgr = g_WorkerManager
    if mgr == nil or mgr.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    local uuid = tonumber(idStr)
    if uuid == nil then
        return "Usage: WorkerCostsAssign <id>   (run while seated in the vehicle)"
    end
    local w = mgr.workerRoster:getWorker(uuid)
    if w == nil then
        return string.format("No worker with id=%d", uuid)
    end
    local vehicle = self:_getCurrentVehicle()
    if vehicle == nil then
        return "Get in the vehicle you want to assign, then run this again"
    end
    local uniqueId = (vehicle.getUniqueId and vehicle:getUniqueId()) or nil
    if uniqueId == nil or uniqueId == "" then
        return "That vehicle has no stable id yet - save the game once, then assign"
    end
    mgr.workerRoster:assignVehiclePersistent(uuid, uniqueId)
    local vname = (vehicle.getFullName and vehicle:getFullName()) or "the vehicle"
    local msg = string.format("Pinned '%s' (id=%d) to %s", w.name, uuid, vname)
    print(msg)
    return msg
end

function WorkerSettingsGUI:consoleCommandUnassign(idStr)
    local mgr = g_WorkerManager
    if mgr == nil or mgr.workerRoster == nil then
        return "Error: Worker Costs Mod not initialized"
    end
    local uuid = tonumber(idStr)
    if uuid == nil then
        return "Usage: WorkerCostsUnassign <id>"
    end
    if not mgr.workerRoster:unassignPersistent(uuid) then
        return string.format("No worker with id=%d", uuid)
    end
    local msg = string.format("Unpinned worker id=%d", uuid)
    print(msg)
    return msg
end

-- Open/close the clickable roster panel (same as the ALT+H hotkey).
function WorkerSettingsGUI:consoleCommandRosterPanel()
    if g_WorkerManager == nil or g_WorkerManager.rosterPanel == nil then
        return "Roster panel not available (client only)"
    end
    g_WorkerManager.rosterPanel:toggle()
    return g_WorkerManager.rosterPanel:isOpen() and "Roster panel opened" or "Roster panel closed"
end

function WorkerSettingsGUI:consoleCommandSetDebug(valueStr)
    if g_WorkerManager and g_WorkerManager.settings then
        local value = (valueStr == "true" or valueStr == "1")
        g_WorkerManager.settings.debugMode = value
        g_WorkerManager.settings:save()
        return string.format("Debug mode %s", value and "ENABLED — check log.txt for [Worker Costs] entries" or "DISABLED")
    end
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandDiagnostic()
    local lines = { "=== Worker Costs Mod Diagnostic ===" }

    -- 1. Manager
    if g_WorkerManager == nil then
        table.insert(lines, "FAIL: g_WorkerManager is nil — mod did not initialize!")
        print(table.concat(lines, "\n"))
        return table.concat(lines, "\n")
    end
    table.insert(lines, "OK:   g_WorkerManager exists")

    -- 2. Settings
    local settings = g_WorkerManager.settings
    if settings == nil then
        table.insert(lines, "FAIL: settings is nil")
    else
        table.insert(lines, string.format("OK:   settings — enabled=%s, mode=%s, rate=$%d, debug=%s",
            tostring(settings.enabled), settings:getCostModeName(),
            settings:getWageRate(), tostring(settings.debugMode)))
    end

    -- 3. WorkerSystem
    local ws = g_WorkerManager.workerSystem
    if ws == nil then
        table.insert(lines, "FAIL: workerSystem is nil")
    else
        table.insert(lines, string.format("OK:   workerSystem — initialized=%s, hookInstalled=%s",
            tostring(ws.isInitialized), tostring(ws._hookedAddMoney)))
    end

    -- 4. Mission / addMoney hook
    if g_currentMission then
        local isHooked = ws and ws._hookedAddMoney
        table.insert(lines, string.format("%s:  addMoney hook — %s",
            isHooked and "OK  " or "WARN",
            isHooked and "installed" or "NOT installed (built-in wages may still run!)"))
    else
        table.insert(lines, "WARN: g_currentMission is nil — not in a game?")
    end

    -- 5. MoneyType check
    local aiType  = MoneyType and MoneyType.AI
    local wageType = MoneyType and MoneyType.WORKER_WAGES
    table.insert(lines, string.format("%s:  MoneyType.AI = %s (this is what the game uses for helper wages)",
        aiType ~= nil and "OK  " or "WARN", tostring(aiType)))
    table.insert(lines, string.format("INFO: MoneyType.WORKER_WAGES = %s", tostring(wageType)))

    -- 6. Active workers
    if ws then
        local workers = ws:getActiveWorkers()
        table.insert(lines, string.format("INFO: Active workers detected: %d", #workers))
        for _, w in ipairs(workers) do
            table.insert(lines, string.format("      - %s", w.name))
        end
    end

    -- 7. GUI
    table.insert(lines, string.format("INFO: g_wcModGui=%s, g_wcGui=%s, g_inGameMenu=%s",
        tostring(g_wcModGui ~= nil), tostring(g_wcGui ~= nil), tostring(g_inGameMenu ~= nil)))

    table.insert(lines, "=== End Diagnostic ===")
    local report = table.concat(lines, "\n")
    print(report)
    return report
end

function WorkerSettingsGUI:consoleCommandResetSettings()
    if g_WorkerManager and g_WorkerManager.settings then
        g_WorkerManager.settings:resetToDefaults()

        -- Refresh UI widgets to reflect restored defaults
        if g_WorkerManager.WorkerSettingsUI then
            g_WorkerManager.WorkerSettingsUI:refreshUI()
        end

        return "Worker Costs Mod settings reset to defaults"
    end

    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandSetMonthlySalary(valueStr)
    if g_WorkerManager and g_WorkerManager.settings then
        local settings = g_WorkerManager.settings
        local value = valueStr == "true" or valueStr == "1"
        settings.monthlySalaryEnabled = value
        settings:save()
        return string.format("Monthly salary dialog %s", value and "ENABLED" or "DISABLED")
    end
    return "Error: Worker Costs Mod not initialized"
end

function WorkerSettingsGUI:consoleCommandTestMonthlySalary()
    if g_WorkerManager and g_WorkerManager.workerSystem then
        local ws = g_WorkerManager.workerSystem
        -- Add a fake entry so the dialog has something to show
        ws.monthlyCosts["Test Worker A"] = (ws.monthlyCosts["Test Worker A"] or 0) + 1200
        ws.monthlyCosts["Test Worker B"] = (ws.monthlyCosts["Test Worker B"] or 0) + 850
        -- Force trigger
        local month = 1
        if g_currentMission and g_currentMission.environment then
            month = g_currentMission.environment.currentPeriod or 1
        end
        ws:triggerMonthlySalaryDialog(month)
        return "Monthly salary dialog triggered (test mode)"
    end
    return "Error: Worker Costs Mod not initialized"
end
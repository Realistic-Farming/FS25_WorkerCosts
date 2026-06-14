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
        local levelNames = { [1] = "Novice", [2] = "Experienced", [3] = "Master" }
        for _, w in ipairs(workers) do
            local levelName = levelNames[w.level] or tostring(w.level)
            table.insert(lines, string.format(
                "#%d  %-16s  %-11s  hrs=%.2f  jobs=%d  XP=%.1f  %s",
                w.uuid, w.name or "Worker", levelName,
                w.totalHours or 0, w.totalJobs or 0, w.totalXP or 0,
                w.assignedVehicleId and ("[working]") or "[idle]"
            ))
        end
    end
    table.insert(lines, "==========================")

    local out = table.concat(lines, "\n")
    print(out)
    return out
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
-- =========================================================
-- FS25 Realistic Worker Costs Mod (version 1.0.9.5)
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
local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- Load all source files in correct order
source(modDirectory .. "src/settings/SettingsManager.lua")
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/WorkerSettingsGUI.lua") 
source(modDirectory .. "src/utils/UIHelper.lua")
source(modDirectory .. "src/settings/WorkerSettingsUI.lua")
source(modDirectory .. "src/WorkerSystem.lua")
source(modDirectory .. "src/WorkerManager.lua")

-- GUI: pause-menu tab + inner tabbed manager
source(modDirectory .. "src/gui/WCDashboardFrame.lua")
source(modDirectory .. "src/gui/WCWageSettingsFrame.lua")
source(modDirectory .. "src/gui/WCWorkerStatsFrame.lua")
source(modDirectory .. "src/gui/WCAboutFrame.lua")
source(modDirectory .. "src/gui/WCSalaryDialog.lua")
source(modDirectory .. "src/gui/WCGui.lua")
source(modDirectory .. "src/gui/WCMenuPage.lua")
source(modDirectory .. "src/gui/WCModGui.lua")

local wm

local function isEnabled()
    return wm ~= nil
end

local function loadedMission(mission, node)
    if not isEnabled() then
        return
    end
    
    if mission.cancelLoading then
        return
    end
    
    wm:onMissionLoaded()

    -- Trigger GUI tab registration after map load
    if g_wcModGui ~= nil then
        g_wcModGui:onMapLoaded()
    end
end

local function load(mission)
    if wm == nil then
        Logging.info("[Worker Costs] Initializing...")
        wm = WorkerManager.new(mission, modDirectory, modName)
        getfenv(0)["g_WorkerManager"] = wm
        -- Cross-mod bridge: g_currentMission is a shared C++ object visible to all mods.
        mission.workerCostsManager = wm
        Logging.info("[Worker Costs] Initialized successfully")
    end
end

local function unload()
    if wm ~= nil then
        wm:delete()
        wm = nil
        getfenv(0)["g_WorkerManager"] = nil
        if g_currentMission then g_currentMission.workerCostsManager = nil end
    end
end

-- Hook into Mission lifecycle
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

-- Update hook
FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if wm then
        wm:update(dt)
    end
end)

-- Pre-initialization safety shims for `workerCosts` / `workerCostsStatus`.
-- Once WorkerSettingsGUI:registerConsoleCommands() runs, the real implementations
-- (which call into g_WorkerManager) are registered via addConsoleCommand() and take
-- precedence in the console.  These plain-global fallbacks exist so that typing either
-- command *before* the mod is fully initialized prints something useful instead of a
-- Lua error.

function workerCosts()
    -- If the mod initialized normally, WorkerSettingsGUI has already registered a
    -- proper addConsoleCommand handler.  This function is only reached if someone
    -- calls it as a plain Lua global before WorkerManager.new() ran.
    if g_WorkerManager and g_WorkerManager.WorkerSettingsGUI then
        return g_WorkerManager.WorkerSettingsGUI:consoleCommandHelp()
    end
    print("=== Worker Costs Mod Commands ===")
    print("Type these commands in console (~):")
    print("WorkerCostsShowSettings - Show current settings")
    print("WorkerCostsEnable/Disable - Enable/disable mod")
    print("WorkerCostsSetWageLevel 1|2|3 - Set wage level")
    print("WorkerCostsSetCostMode 1|2 - Set cost mode")
    print("WorkerCostsSetNotifications true|false - Toggle notifications")
    print("WorkerCostsTestPayment - Test wage payment")
    print("WorkerCostsResetSettings - Reset to defaults")
    print("==================================")
    return "Worker Costs Mod commands listed above"
end

function workerCostsStatus()
    if g_WorkerManager and g_WorkerManager.settings then
        local settings = g_WorkerManager.settings
        local status = string.format(
            "=== Worker Costs Mod Status ===\n" ..
            "Enabled: %s\n" ..
            "Mode: %s\n" ..
            "Wage Level: %s\n" ..
            "Base Rate: %s%s\n" ..
            "Notifications: %s\n" ..
            "================================",
            tostring(settings.enabled),
            settings:getCostModeName(),
            settings:getWageLevelName(),
            g_i18n and g_i18n:formatMoney(settings:getWageRate(), 0, true, false) or tostring(settings:getWageRate()),
            settings.costMode == Settings.COST_MODE_HOURLY and "/h" or "/ha",
            tostring(settings.showNotifications)
        )
        print(status)
        return status
    end
    print("Worker Costs Mod not initialized")
    return "Worker Costs Mod not initialized"
end

-- Expose as globals so other mods can call them directly if needed.
-- The console uses addConsoleCommand-registered handlers (registered inside
-- WorkerSettingsGUI), so these globals are supplementary, not the primary path.
getfenv(0)["workerCosts"]       = workerCosts
getfenv(0)["workerCostsStatus"] = workerCostsStatus

Logging.info("[Worker Costs] v1.0.9.5 loaded — type 'workerCosts' in console for help")

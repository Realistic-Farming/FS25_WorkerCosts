-- =========================================================
-- FS25 Realistic Worker Costs Mod - SettingsHub bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_SettingsHub. Safe if SettingsHub is not
-- installed (register() just no-ops). Purpose: let the FarmTablet
-- System Settings app list Worker Costs' settings.
--
-- Same scope as the Income Mod / Tax Mod bridges: WorkerManager's own
-- Settings object and its save()/load() path stay the source of truth.
-- This only mirrors current values into SettingsHub at mission load and
-- applies edits made *through* SettingsHub back onto that same object.
-- =========================================================

WorkerSettingsHubBridge = WorkerSettingsHubBridge or {}

local function applyChange(key, value)
    local wm = g_WorkerManager
    if wm == nil or wm.settings == nil then return end
    local s = wm.settings

    if key == "wageLevel" then
        s:setWageLevel(value)
    elseif key == "costMode" then
        s:setCostMode(value)
    else
        s[key] = value
    end

    s:save()
    if wm.WorkerSettingsUI then
        wm.WorkerSettingsUI:refreshUI()
    end
end

function WorkerSettingsHubBridge.register(wm)
    -- The reliable cross-mod handle is g_currentMission.settingsHub (the same one
    -- FarmTablet reads). The bare g_settingsHub global is only visible inside
    -- SettingsHub's own mod environment, so it reads back nil from here.
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    if hub == nil then return end
    if wm == nil or wm.settings == nil then return end
    local s = wm.settings

    local defs = {
        { id = "enabled",             type = "bool", default = s.enabled,             adminOnly = true,  label = "Worker Costs Enabled" },
        { id = "costMode",            type = "enum", default = s.costMode,            adminOnly = true,  values = { 1, 2 }, label = "Cost Mode (1=Hourly, 2=Per Hectare)" },
        { id = "wageLevel",           type = "enum", default = s.wageLevel,           adminOnly = true,  values = { 1, 2, 3 }, label = "Wage Level (1=Low, 2=Medium, 3=High)" },
        { id = "customRate",          type = "float", default = s.customRate,         adminOnly = true,  min = 0, max = 1000, label = "Custom Wage Rate" },
        { id = "monthlySalaryEnabled",type = "bool", default = s.monthlySalaryEnabled,adminOnly = true,  label = "Monthly Salary Summary" },
        { id = "showNotifications",   type = "bool", default = s.showNotifications,   adminOnly = false, label = "Show Notifications" },
        { id = "debugMode",           type = "bool", default = s.debugMode,           adminOnly = false, label = "Debug Mode" },
    }

    local ok, err = pcall(function()
        hub:registerModule("WorkerCosts", {
            adminSettings = defs,
            onChange      = function(key, value, playerId) applyChange(key, value) end,
            -- We own our persistence (WorkerManager's Settings save()/load()) and load it
            -- before this registration runs, so the hub must mirror-for-display only: never
            -- restore its own stale copy and replay it back through onChange on load. Without
            -- this the hub can push a stale value over our real setting every load (the
            -- SoilFertilizer `enabled=false` reset-on-load bug class).
            selfPersisted = true,
        })
    end)

    if ok then
        Logging.info("Worker Costs Mod: Registered with SettingsHub (%d setting(s))", #defs)
    else
        Logging.warning("Worker Costs Mod: SettingsHub registration failed: %s", tostring(err))
    end
end

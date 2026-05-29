-- =========================================================
-- FS25 Worker Costs Mod
-- WCAboutFrame.lua  -  Tab 4: About / Help
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class WCAboutFrame
WCAboutFrame = {}
local WCAboutFrame_mt = Class(WCAboutFrame, TabbedMenuFrameElement)

function WCAboutFrame.new()
    local self = WCAboutFrame:superClass().new(nil, WCAboutFrame_mt)
    self.name      = "WCAboutFrame"
    self.className = "WCAboutFrame"
    return self
end

function WCAboutFrame:onGuiSetupFinished()
    WCAboutFrame:superClass().onGuiSetupFinished(self)
end

function WCAboutFrame:initialize()
    -- nothing extra needed at init time
end

function WCAboutFrame:onFrameOpen()
    WCAboutFrame:superClass().onFrameOpen(self)
    self:refresh()
end

function WCAboutFrame:onFrameClose()
    WCAboutFrame:superClass().onFrameClose(self)
end

function WCAboutFrame:refresh()
    -- Pay interval from workerSystem
    if self.txtPayInterval and g_WorkerManager and g_WorkerManager.workerSystem then
        local min = math.floor(g_WorkerManager.workerSystem.paymentInterval / 60000)
        self.txtPayInterval:setText(string.format("%d min", min))
    end

    -- Mod version: try the stored modName (captured at load time), then the folder name fallback
    if self.txtVersion then
        local version = "unknown"
        if g_modManager then
            local modName = (g_WorkerManager and g_WorkerManager.modName) or "FS25_WorkerCosts"
            local mod = g_modManager:getModByName(modName)
            -- Some FS25 builds key by folder name rather than <modName>; try both
            if not (mod and mod.version) then
                mod = g_modManager:getModByName("FS25_WorkerCosts")
            end
            if mod and mod.version then
                version = mod.version
            end
        end
        self.txtVersion:setText(version)
    end
end

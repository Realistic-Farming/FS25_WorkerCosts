-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- WorkerMasterHUDBridge — optional bridge to FS25_MasterHUD (bedrock)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- Strictly delegate-when-present, mirroring SoilFertilizer's MasterHUD bridge:
--   * MasterHUD installed -> WorkerCosts registers its self-drawn roster panel as a
--     subscribe() element. MasterHUD then owns the single draw loop, the menu/dialog
--     suspend, and cross-mod ordering, so the panel stacks cleanly with the rest of
--     the ecosystem instead of every mod hooking FSBaseMission.draw independently.
--   * MasterHUD absent -> WorkerCosts' own FSBaseMission.draw hook runs the exact
--     same body, exactly as before.
--
-- subscribe() is MasterHUD's path for self-drawn content: the element draws its own
-- positioned overlay each frame, MasterHUD only owns ordering + suspend, it does not
-- lay it out, so nothing about the panel's own layout changes. drawStack() is the
-- single source of the draw body, shared with the fallback hook so the two paths can
-- never diverge. The subscribe id is a runtime registration (not persisted), so it
-- carries no naming lock, but it is kept on the WorkerCosts_<Thing> scheme anyway.
--
-- The fullscreen tabbed pause-menu GUI (WCGui / WCModGui, g_gui:loadGui) is NOT a HUD
-- overlay and stays g_gui-managed; only the self-drawn roster panel goes to MasterHUD.
--
-- The cross-mod handle is g_currentMission.masterHUD (published in Mission00.load).
-- =========================================================

WorkerMasterHUDBridge = {}

WorkerMasterHUDBridge.HUD_ID = "WorkerCosts_RosterPanel"
WorkerMasterHUDBridge.active = false   -- MasterHUD present and we registered

-- The roster panel draw body. Resolves the manager from the canonical global so it
-- can be driven either by MasterHUD's loop or by WorkerCosts' own draw hook. The
-- panel self-guards on isVisible, so calling it every frame is a no-op when closed.
function WorkerMasterHUDBridge.drawStack()
    local wm = g_WorkerManager
    if wm ~= nil and wm.rosterPanel ~= nil then
        wm.rosterPanel:draw()
    end
end

-- Register with MasterHUD if present. Called at loadMission00Finished, after the
-- HUD has published its g_currentMission handle (Mission00.load).
function WorkerMasterHUDBridge.register(mgr)
    WorkerMasterHUDBridge.active = false

    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if hud == nil then
        Logging.info("[Worker Costs] MasterHUD not detected; roster panel uses its own draw hook")
        return
    end

    local ok, err = pcall(function()
        hud:subscribe(WorkerMasterHUDBridge.HUD_ID, {
            draw = WorkerMasterHUDBridge.drawStack,
        })
    end)

    if ok then
        WorkerMasterHUDBridge.active = true
        Logging.info("[Worker Costs] Registered roster panel with MasterHUD (single draw loop + menu-suspend)")
    else
        Logging.warning("[Worker Costs] MasterHUD registration failed: %s (using own draw hook)", tostring(err))
    end
end

-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.integration.ProStaff — safe internal telemetry accessor (FR2)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
--
-- WHAT THIS IS
--   The single, type-guarded boundary through which HireHallCore reads Pro-Staff
--   indicators (fatigue, XP, level). HireHallCore is a READ-ONLY consumer of this
--   data (FR0 boundary) — it never writes these fields.
--
--   In this mod the "Pro-Staff" telemetry lives directly on the roster worker
--   record (worker.fatigue is 0..1, worker.totalXP, worker.level), NOT under a
--   worker.proStaff.* namespace as the FR text assumes. This accessor is exactly
--   the indirection FR2 asks for: if that schema ever changes, only this file
--   updates, and every read degrades to a SAFE DEFAULT instead of crashing the
--   broker (FR3 schema-drift rule: a failed telemetry read must never lock the
--   workforce).
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.integration = HireHallCore.integration or {}
HireHallCore.integration.ProStaff = HireHallCore.integration.ProStaff or {}
local ProStaff = HireHallCore.integration.ProStaff

local function num(v, default)
    if type(v) == "number" then
        return v
    end
    return default
end

--- Fatigue as a 0..100 percentage. The roster stores 0..1; we normalize so broker
--- code reads like the spec ("getFatigue(worker) < 95"). Safe default 0 (rested).
function ProStaff:getFatigue(worker)
    if type(worker) ~= "table" then
        return 0
    end
    return num(worker.fatigue, 0) * 100
end

--- Total accrued XP. Safe default 0.
function ProStaff:getXP(worker)
    if type(worker) ~= "table" then
        return 0
    end
    return num(worker.totalXP, 0)
end

--- Level tier (1 Novice / 2 Experienced / 3 Master). Safe default 1.
function ProStaff:getLevel(worker)
    if type(worker) ~= "table" then
        return 1
    end
    return num(worker.level, 1)
end

--- True when the telemetry looks structurally valid. The broker/evolution engine
--- use this to apply the FR3 "treat as available on drift" rule rather than
--- trusting a coerced default.
function ProStaff:isReadable(worker)
    return type(worker) == "table" and type(worker.fatigue) == "number"
end

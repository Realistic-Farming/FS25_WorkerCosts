-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.Schema — versioned save persistence & migration (FR0 / FR14)
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
--   All HireHallCore persistent state, segregated into its OWN savegame file
--   (hireHallCore.xml) under a <hireHallCore version="1"> root with a
--   <hireHallCoreGlobal> block. A separate file is the strongest form of the FR14
--   "schema isolation / prevent file corruption" directive: a bad HireHallCore
--   write can never damage the roster's workerData.xml.
--
--   Per-worker rows are keyed by the roster's stable uuid, so on load we re-attach
--   lifecycle state onto the matching roster worker. Workers no longer on the
--   roster are skipped. Mirrors the proven XMLFile.create / iterate / delete
--   pattern used by WorkerRoster (no new API surface).
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.Schema = HireHallCore.Schema or {}
local Schema = HireHallCore.Schema

Schema.SAVE_FILE = "hireHallCore.xml"
Schema.ROOT      = "hireHallCore"

--- Write lifecycle state for every worker that has a meta block.
function Schema:save(missionInfo, roster)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir or roster == nil then
        return false
    end

    local path = dir .. "/" .. Schema.SAVE_FILE
    local xmlFile = XMLFile.create("wc_HireHallCoreXML", path, Schema.ROOT)
    if xmlFile == nil then
        Logging.warning("[HireHallCore] Failed to create save file: " .. path)
        return false
    end

    local root = Schema.ROOT
    xmlFile:setInt(root .. "#version", HireHallCore.SCHEMA_VERSION)
    -- Protected global block (FR0 <hireHallCoreGlobal>) — reserved for hall-level
    -- state (recruitment seed, rotation clock) added in Phase 3 (FR9/FR10).
    xmlFile:setInt(root .. ".hireHallCoreGlobal#schemaVersion", HireHallCore.SCHEMA_VERSION)

    local i = 0
    for _, w in ipairs(roster:getAll()) do
        local meta = w.hireHallMeta
        if meta then
            local key = string.format("%s.worker(%d)", root, i)
            xmlFile:setInt(key .. "#uuid", w.uuid)
            xmlFile:setString(key .. "#lifecycleState",
                meta.lifecycleState or HireHallCore.STATE.AVAILABLE)
            xmlFile:setInt(key .. "#enteredDay", meta.enteredDay or 0)
            if meta.cooldownEnd ~= nil then
                xmlFile:setInt(key .. "#cooldownEnd", meta.cooldownEnd)
            end

            -- FR5 (#66): persist the job-history circular buffer (schema v2). Rows are
            -- numbers/strings only, already capped to HISTORY_CAP at write time.
            local hist = meta.history
            if type(hist) == "table" then
                for j = 1, #hist do
                    local e = hist[j]
                    local hk = string.format("%s.h(%d)", key, j - 1)
                    xmlFile:setInt(hk .. "#day",        e.day or 0)
                    xmlFile:setFloat(hk .. "#hours",    e.hours or 0)
                    xmlFile:setString(hk .. "#outcome", e.outcome or "completed")
                    xmlFile:setString(hk .. "#cause",   e.cause or "")
                    xmlFile:setInt(hk .. "#startLevel", e.startLevel or 1)
                    xmlFile:setInt(hk .. "#endLevel",   e.endLevel or 1)
                    xmlFile:setInt(hk .. "#wage",       e.wage or 0)
                    xmlFile:setInt(hk .. "#seq",        e.seq or 0)
                end
            end

            i = i + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
    Logging.info("[HireHallCore] Saved lifecycle state (%d workers) -> %s", i, path)
    return true
end

--- Read lifecycle state back and re-attach it to roster workers by uuid.
function Schema:loadIfExists(missionInfo, roster)
    local dir = missionInfo and missionInfo.savegameDirectory
    if not dir or roster == nil then
        return false
    end

    local path = dir .. "/" .. Schema.SAVE_FILE
    local xmlFile = XMLFile.loadIfExists("wc_HireHallCoreXML", path, Schema.ROOT)
    if xmlFile == nil then
        Logging.info("[HireHallCore] No save found (new/first run) — lifecycle defaults to available")
        return false
    end

    local root = Schema.ROOT
    local version = xmlFile:getInt(root .. "#version", 1)
    version = Schema:migrateLegacy(version)

    local applied = 0
    xmlFile:iterate(root .. ".worker", function(_, key)
        local uuid = xmlFile:getInt(key .. "#uuid")
        if uuid == nil then
            return
        end
        local w = roster:getWorker(uuid)
        if w == nil then
            return   -- worker no longer on the roster; drop the stale row
        end
        local meta = HireHallCore.core.Lifecycle:ensureMeta(w)
        local state = xmlFile:getString(key .. "#lifecycleState", HireHallCore.STATE.AVAILABLE)
        if HireHallCore.VALID_STATE[state] then
            meta.lifecycleState = state
        end
        meta.enteredDay  = xmlFile:getInt(key .. "#enteredDay", meta.enteredDay or 0)
        meta.cooldownEnd = xmlFile:getInt(key .. "#cooldownEnd", nil)

        -- FR5 (#66): restore the job-history buffer (schema v2; absent in v1 saves,
        -- which simply load an empty resume). Already capped on write, but the cap is
        -- re-applied defensively on the next record().
        local hist = {}
        xmlFile:iterate(key .. ".h", function(_, hk)
            hist[#hist + 1] = {
                day        = xmlFile:getInt(hk .. "#day", 0),
                hours      = xmlFile:getFloat(hk .. "#hours", 0),
                outcome    = xmlFile:getString(hk .. "#outcome", "completed"),
                cause      = xmlFile:getString(hk .. "#cause", ""),
                startLevel = xmlFile:getInt(hk .. "#startLevel", 1),
                endLevel   = xmlFile:getInt(hk .. "#endLevel", 1),
                wage       = xmlFile:getInt(hk .. "#wage", 0),
                seq        = xmlFile:getInt(hk .. "#seq", 0),
            }
        end)
        if #hist > 0 then
            meta.history = hist
        end

        applied = applied + 1
    end)

    xmlFile:delete()
    Logging.info("[HireHallCore] Loaded lifecycle state (%d workers, schema v%d)", applied, version)
    return true
end

--- FR0 / FR14 — iterative forward migration. Each loop turn upgrades one schema
--- version until current. v1 -> v2 is additive (per-worker history, #66): a v1 save
--- simply has no <h> rows and loads an empty resume, so no transform is required.
function Schema:migrateLegacy(version)
    local v = version or 1
    while v < HireHallCore.SCHEMA_VERSION do
        -- if v == 1 then ... (v1 -> v2: history is additive, nothing to transform) end
        v = v + 1
    end
    return v
end

-- =========================================================
-- FS25 Realistic Worker Costs Mod
-- =========================================================
-- HireHallCore.core.History — per-worker job history circular buffer (FR8)
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
--   The historical buffer the Internal Job Termination Monitor (FR5) writes to. It
--   keeps a small, FIFO-capped "professional resume" of recent jobs on each roster
--   worker's hireHallMeta.history (the slot Lifecycle:ensureMeta already reserves).
--
--   The spec (FR5) calls this "HireHallCoreHistory" and asks for "circular buffer
--   management". A fixed-cap FIFO array IS that: once HISTORY_CAP entries exist, the
--   oldest is evicted as the newest is appended, so memory is bounded no matter how
--   many jobs a worker runs over a career.
--
-- ENGINEERING CONSTRAINTS HONORED (FR5 checklist)
--   * Memory: entries store ONLY numbers/strings (day, hours, outcome token, levels,
--     wage, seq). No vehicle/tool/job table references are ever retained.
--   * Persistence: the buffer rides along in hireHallCore.xml via HireHallCore.Schema
--     (segregated file — a bad history write can never corrupt workerData.xml).
--   * The monitor wraps every record() in HireHallCore:guard(), so a write failure
--     trips the one corruption flag + single System Error toast rather than throwing.
-- =========================================================

HireHallCore = HireHallCore or {}
HireHallCore.core = HireHallCore.core or {}
HireHallCore.core.History = HireHallCore.core.History or {}
local History = HireHallCore.core.History

-- Valid outcome tokens (stored as short strings, never localized text).
History.OUTCOME_COMPLETED = "completed"
History.OUTCOME_DISMISSED = "dismissed"
History.OUTCOME_FAILED    = "failed"

History.VALID_OUTCOME = {
    [History.OUTCOME_COMPLETED] = true,
    [History.OUTCOME_DISMISSED] = true,
    [History.OUTCOME_FAILED]    = true,
}

--- Append a job-result entry to a worker's history, evicting the oldest once the
--- buffer is full (FIFO circular-buffer behaviour). Sets the HISTORY dirty bit so a
--- future sync/UI knows the resume changed. Returns the stored entry.
--- Callers run this under HireHallCore:guard() — keep it allocation-light and pure.
function History:record(worker, entry)
    local meta = HireHallCore.core.Lifecycle:ensureMeta(worker)
    if meta == nil or type(entry) ~= "table" then
        return nil
    end

    if meta.history == nil then
        meta.history = {}
    end
    local buf = meta.history

    -- Normalize: keep only the documented numeric/string fields (defensive against a
    -- caller accidentally passing a richer table that holds object references).
    local outcome = entry.outcome
    if not History.VALID_OUTCOME[outcome] then
        outcome = History.OUTCOME_COMPLETED
    end
    local stored = {
        day        = math.floor(entry.day or 0),
        hours      = entry.hours or 0,
        outcome    = outcome,
        cause      = tostring(entry.cause or ""),
        startLevel = math.floor(entry.startLevel or 1),
        endLevel   = math.floor(entry.endLevel or 1),
        wage       = math.floor(entry.wage or 0),
        seq        = math.floor(entry.seq or 0),
    }

    buf[#buf + 1] = stored

    -- Trim from the front until we are at/under the cap. A while-loop (not a single
    -- remove) self-heals a buffer that was hand-edited oversized in the save file.
    local cap = HireHallCore.HISTORY_CAP or 20
    while #buf > cap do
        table.remove(buf, 1)
    end

    if meta.dirtyMask ~= nil then
        meta.dirtyMask = HireHallCore.maskSet(meta.dirtyMask, HireHallCore.DIRTY_HISTORY)
    end

    return stored
end

--- The worker's history buffer (oldest first). Always returns a table.
function History:get(worker)
    local meta = worker and worker.hireHallMeta
    return (meta and meta.history) or {}
end

--- Cheap aggregate over a worker's recorded jobs — the numbers a "resume" panel or
--- the FarmTablet would show. Pure read; allocates one small result table.
function History:summarize(worker)
    local result = { jobs = 0, completed = 0, dismissed = 0, failed = 0, hours = 0, wage = 0 }
    local buf = self:get(worker)
    for i = 1, #buf do
        local e = buf[i]
        result.jobs  = result.jobs + 1
        result.hours = result.hours + (e.hours or 0)
        result.wage  = result.wage + (e.wage or 0)
        if e.outcome == History.OUTCOME_DISMISSED then
            result.dismissed = result.dismissed + 1
        elseif e.outcome == History.OUTCOME_FAILED then
            result.failed = result.failed + 1
        else
            result.completed = result.completed + 1
        end
    end
    return result
end

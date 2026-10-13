-- =========================================================
-- FS25_NetworkSync - network event classes (v2)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Three event classes carry the ecosystem's multiplayer sync:
--
--   RealisticFarmingSyncEvent         server -> client(s): a batch of per-module
--     frames. Used for the 1Hz dirty batch, syncNow, the join snapshot, and the
--     slow drift-floor full resync. v2 wraps each module's value array in a frame:
--
--       frame: modId (string), chunkIndex (int32), chunkCount (int32),
--              mode (UInt8: 0 FULL / 1 DELTA), subLength (int32), sub-values...
--
--     A module that fits one event is a single frame (chunkIndex 0, chunkCount 1),
--     so small and large modules use the exact same frame. A module larger than the
--     event budget is split into ordered chunks that reassemble on the client. The
--     value encoding inside a frame is byte-for-byte the v1 typed encoding below:
--     no new value types were introduced, so a module that never sends a delta and
--     never splits carries the same value bytes it did in v1.
--
--   RealisticFarmingSyncRequestEvent  client -> server: "send me a full snapshot"
--     on join. The server answers with a SyncEvent (FULL frames) to that connection.
--
--   RealisticFarmingActionEvent       client -> server: a validated request for a
--     server-authoritative action (Path 3). The server authorizes the requester
--     (master user, or the action's own gate) and applies it; the resulting state
--     change flags its module dirty and the normal sync path carries the result down.
--
-- Per-value type tagging (unchanged from v1): each value is a UInt8 tag then the
-- typed value. Integers that fit int32 are sent as int32 (exact); fractional or
-- out-of-range numbers fall back to float32; booleans and strings have their own tags.
-- =========================================================

RealisticFarmingSyncEvent = RealisticFarmingSyncEvent or {}
local RealisticFarmingSyncEvent_mt = Class(RealisticFarmingSyncEvent, Event)
InitEventClass(RealisticFarmingSyncEvent, "RealisticFarmingSyncEvent")

-- Value type tags (UInt8).
RealisticFarmingSyncEvent.T_BOOL   = 0
RealisticFarmingSyncEvent.T_INT    = 1
RealisticFarmingSyncEvent.T_FLOAT  = 2
RealisticFarmingSyncEvent.T_STRING = 3

local INT32_MIN = -2147483648
local INT32_MAX = 2147483647

-- Write a single tagged value (shared by sync frames and action args).
local function writeValue(streamId, v)
    local t = type(v)
    if t == "boolean" then
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_BOOL)
        streamWriteBool(streamId, v)
    elseif t == "number" then
        if v == v and v ~= math.huge and v ~= -math.huge
            and math.floor(v) == v and v >= INT32_MIN and v <= INT32_MAX then
            streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_INT)
            streamWriteInt32(streamId, v)
        else
            streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_FLOAT)
            streamWriteFloat32(streamId, (v == v) and v or 0)
        end
    elseif t == "string" then
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_STRING)
        streamWriteString(streamId, v)
    else
        NSLogger.warning("sync: unsupported value of type %s, sending 0", t)
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_FLOAT)
        streamWriteFloat32(streamId, 0)
    end
end

local function readValue(streamId)
    local tag = streamReadUInt8(streamId)
    if tag == RealisticFarmingSyncEvent.T_BOOL then
        return streamReadBool(streamId)
    elseif tag == RealisticFarmingSyncEvent.T_INT then
        return streamReadInt32(streamId)
    elseif tag == RealisticFarmingSyncEvent.T_STRING then
        return streamReadString(streamId)
    else
        return streamReadFloat32(streamId)
    end
end

-- Exposed so the core and tests can reuse the exact encoding.
RealisticFarmingSyncEvent.writeValue = writeValue
RealisticFarmingSyncEvent.readValue  = readValue

function RealisticFarmingSyncEvent.emptyNew()
    return Event.new(RealisticFarmingSyncEvent_mt)
end

---@param frames table  array of { modId, chunkIndex, chunkCount, mode, values }
function RealisticFarmingSyncEvent.new(frames)
    local self = RealisticFarmingSyncEvent.emptyNew()
    self.frames = frames or {}
    return self
end

function RealisticFarmingSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, #self.frames)
    for _, f in ipairs(self.frames) do
        streamWriteString(streamId, f.modId)
        streamWriteInt32(streamId, f.chunkIndex or 0)
        streamWriteInt32(streamId, f.chunkCount or 1)
        streamWriteUInt8(streamId, f.mode or 0)
        local values = f.values or {}
        local n = #values
        streamWriteInt32(streamId, n)
        for i = 1, n do
            writeValue(streamId, values[i])
        end
    end
end

function RealisticFarmingSyncEvent:readStream(streamId, connection)
    self.frames = {}
    local count = streamReadInt32(streamId)
    for _ = 1, count do
        local modId      = streamReadString(streamId)
        local chunkIndex = streamReadInt32(streamId)
        local chunkCount = streamReadInt32(streamId)
        local mode       = streamReadUInt8(streamId)
        local n          = streamReadInt32(streamId)
        local values = {}
        for i = 1, n do
            values[i] = readValue(streamId)
        end
        self.frames[#self.frames + 1] = {
            modId = modId, chunkIndex = chunkIndex, chunkCount = chunkCount,
            mode = mode, values = values,
        }
    end
    self:run(connection)
end

function RealisticFarmingSyncEvent:run(connection)
    -- Only a pure client applies received state. On a listen server (host)
    -- getIsServer() is true and the host already holds authoritative state.
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:receiveFrames(self.frames)
    end
end

-- =========================================================
-- Full-sync request (client -> server, on join)
-- =========================================================

RealisticFarmingSyncRequestEvent = RealisticFarmingSyncRequestEvent or {}
local RealisticFarmingSyncRequestEvent_mt = Class(RealisticFarmingSyncRequestEvent, Event)
InitEventClass(RealisticFarmingSyncRequestEvent, "RealisticFarmingSyncRequestEvent")

function RealisticFarmingSyncRequestEvent.emptyNew()
    return Event.new(RealisticFarmingSyncRequestEvent_mt)
end

function RealisticFarmingSyncRequestEvent.new()
    return RealisticFarmingSyncRequestEvent.emptyNew()
end

function RealisticFarmingSyncRequestEvent:writeStream(streamId, connection)
    -- no payload; the request itself is the signal
end

function RealisticFarmingSyncRequestEvent:readStream(streamId, connection)
    self:run(connection)
end

function RealisticFarmingSyncRequestEvent:run(connection)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:sendFullSnapshotTo(connection)
    end
end

-- =========================================================
-- Action channel (client -> server, validated) - Path 3
-- =========================================================
-- Modeled exactly on the request event above: a working client-to-server event
-- whose run(connection) guards on getIsServer. We add a typed-arg payload and route
-- to the server-side authorization + dispatch in NetworkSync:_applyAction, which
-- resolves the connection to its user and enforces the action's admin gate. A
-- rejected or unknown action applies nothing (a plain early return), matching the
-- request event's no-op-on-non-server pattern.

RealisticFarmingActionEvent = RealisticFarmingActionEvent or {}
local RealisticFarmingActionEvent_mt = Class(RealisticFarmingActionEvent, Event)
InitEventClass(RealisticFarmingActionEvent, "RealisticFarmingActionEvent")

function RealisticFarmingActionEvent.emptyNew()
    return Event.new(RealisticFarmingActionEvent_mt)
end

---@param actionId string  registered action id
---@param args table       typed arg array (int/float/bool/string), may be nil
function RealisticFarmingActionEvent.new(actionId, args)
    local self = RealisticFarmingActionEvent.emptyNew()
    self.actionId = actionId or ""
    self.args = args or {}
    return self
end

function RealisticFarmingActionEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.actionId)
    local n = #self.args
    streamWriteInt32(streamId, n)
    for i = 1, n do
        writeValue(streamId, self.args[i])
    end
end

function RealisticFarmingActionEvent:readStream(streamId, connection)
    self.actionId = streamReadString(streamId)
    local n = streamReadInt32(streamId)
    self.args = {}
    for i = 1, n do
        self.args[i] = readValue(streamId)
    end
    self:run(connection)
end

function RealisticFarmingActionEvent:run(connection)
    -- Server-only, same guard as the request event. Authorization + dispatch lives
    -- in the core so it can resolve the connection to its user.
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:_applyAction(self.actionId, self.args, connection)
    end
end

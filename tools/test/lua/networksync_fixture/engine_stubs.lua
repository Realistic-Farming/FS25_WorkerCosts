-- networksync_fixture/engine_stubs.lua
--
-- The engine surface NetworkSync's own two files need to load and run under this
-- bench: the event scaffolding (Event.new, InitEventClass), a TYPED stream (each write
-- tags its cell; a read of the wrong type or past the end is counted, never silently
-- zero) and the mission side flag. Defined only where this repo's prelude does not
-- already define them, so a prelude that carries its own stays in charge.
--
-- The three files beside this one are VERBATIM copies of FS25_NetworkSync's
-- src/Logger.lua, src/RealisticFarmingSyncEvent.lua and src/NetworkSync.lua at
-- 9e599be (2026-09-24), unchanged: the bar drives the real transport, not a model of
-- it. When NetworkSync moves, refresh the copies and this note together.

if Event == nil then
    Event = { new = function(mt) return setmetatable({}, mt) end }
end
if Event.new == nil then Event.new = function(mt) return setmetatable({}, mt) end end
if InitEventClass == nil then
    function InitEventClass(class, name) class.className = name end
end

if streamWriteInt32 == nil then
    --- A typed FIFO: q holds { t = tag, v = value }; r is the read cursor.
    function NewTypedStream()
        return { q = {}, r = 1, typeErrors = 0, underflows = 0 }
    end
    local function push(s, tag, v) s.q[#s.q + 1] = { t = tag, v = v } end
    local function pull(s, tag)
        local e = s.q[s.r]
        if e == nil then s.underflows = s.underflows + 1 return nil end
        s.r = s.r + 1
        if e.t ~= tag then s.typeErrors = s.typeErrors + 1 end
        return e.v
    end
    function streamWriteInt32(s, v)   push(s, "i32", v) end
    function streamReadInt32(s)        return pull(s, "i32") end
    function streamWriteFloat32(s, v) push(s, "f32", v) end
    function streamReadFloat32(s)      return pull(s, "f32") end
    function streamWriteUInt8(s, v)   push(s, "u8", v) end
    function streamReadUInt8(s)        return pull(s, "u8") end
    function streamWriteString(s, v)  push(s, "str", v) end
    function streamReadString(s)       return pull(s, "str") end
    function streamWriteBool(s, v)    push(s, "bool", v and true or false) end
    function streamReadBool(s)         return pull(s, "bool") end
    function streamWriteUInt16(s, v)  push(s, "u16", v) end
    function streamReadUInt16(s)       return pull(s, "u16") end
    function streamWriteUIntN(s, v, n) push(s, "uN", v) end
    function streamReadUIntN(s, n)     return pull(s, "uN") end
    function streamGetWriteOffset(s)   return #s.q * 8 end
    --- Faults on a stream: wrong-type reads plus reads past the end.
    function TypedStreamFaults(s) return s.typeErrors + s.underflows end
end

if g_currentMission == nil then
    g_currentMission = { _isServer = true, getIsServer = function(self) return self._isServer end }
end

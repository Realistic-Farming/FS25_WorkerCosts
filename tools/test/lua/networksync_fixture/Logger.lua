-- =========================================================
-- FS25_NetworkSync - Logger
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Mod-prefixed logging so lines are greppable by "[NetworkSync]".
-- =========================================================

NSLogger = NSLogger or {}
NSLogger.PREFIX = "[NetworkSync] "
NSLogger.debugEnabled = false

function NSLogger.info(msg, ...)
    if select("#", ...) > 0 then
        Logging.info(NSLogger.PREFIX .. msg, ...)
    else
        Logging.info(NSLogger.PREFIX .. msg)
    end
end

function NSLogger.warning(msg, ...)
    if select("#", ...) > 0 then
        Logging.warning(NSLogger.PREFIX .. msg, ...)
    else
        Logging.warning(NSLogger.PREFIX .. msg)
    end
end

function NSLogger.error(msg, ...)
    if select("#", ...) > 0 then
        Logging.error(NSLogger.PREFIX .. msg, ...)
    else
        Logging.error(NSLogger.PREFIX .. msg)
    end
end

function NSLogger.debug(msg, ...)
    if not NSLogger.debugEnabled then
        return
    end
    if select("#", ...) > 0 then
        Logging.info(NSLogger.PREFIX .. "[debug] " .. msg, ...)
    else
        Logging.info(NSLogger.PREFIX .. "[debug] " .. msg)
    end
end

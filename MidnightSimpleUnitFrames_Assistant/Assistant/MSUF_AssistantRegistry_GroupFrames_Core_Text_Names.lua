-- Assistant GroupFrames text name-shortening helpers.
-- Loaded before MSUF_AssistantRegistry_GroupFrames_Core_Text.lua; consumed by the text core context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildTextNameContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local EnsureDB = ctx.EnsureDB
    local GeneralDB = ctx.GeneralDB
    local GroupDB = ctx.GroupDB
    if type(GroupDB) ~= "function" then return nil end

    local function ClearGroupNameShorteningLegacyFlags(conf)
        if type(conf) ~= "table" then return end
        conf.nameShortenOverride = nil
        conf._msufGFNameTruncationOverride = nil
    end

    local function SharedNameShorteningEnabled()
        local db = EnsureDB and EnsureDB() or _G.MSUF_DB
        return db and db.shortenNames == true
    end

    local function SharedNameShorteningMax()
        local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
        return tonumber(g and g.shortenNameMaxChars) or 6
    end

    local function SharedNameShorteningSide()
        local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
        local side = g and g.shortenNameClipSide
        return side == "RIGHT" and "RIGHT" or "LEFT"
    end

    local function SharedNameShorteningNoEllipsis()
        local g = GeneralDB and GeneralDB() or (_G.MSUF_DB and _G.MSUF_DB.general)
        return not (g and g.shortenNameShowDots ~= false)
    end

    local function CopyGroupNameShorteningFromShared(conf)
        if type(conf) ~= "table" then return end
        -- A disabled override can retain stale local values. Copy the complete
        -- *effective* Shared state on the transition instead of filling only
        -- nil fields; changing one detail must not resurrect an older length,
        -- side, or enabled state.
        conf.nameShortenEnabled = SharedNameShorteningEnabled()
        conf.nameClipSide = SharedNameShorteningSide()
        conf.nameNoEllipsis = SharedNameShorteningNoEllipsis()
        conf.nameMaxChars = SharedNameShorteningMax()
        ClearGroupNameShorteningLegacyFlags(conf)
    end

    local function SetGroupFontOverrideValue(scope, key, value)
        local conf = GroupDB(scope)
        if conf.fontOverride ~= true then CopyGroupNameShorteningFromShared(conf) end
        conf.fontOverride = true
        conf[key] = value
        ClearGroupNameShorteningLegacyFlags(conf)
    end

    local function GroupNameShorteningEnabled(scope)
        local conf = GroupDB(scope)
        if conf.fontOverride == true then
            local value = conf.nameShortenEnabled
            if value == nil then return (tonumber(conf.nameMaxChars) or 0) > 0 end
            return value == true
        end
        return SharedNameShorteningEnabled()
    end

    local function GroupNameShorteningMax(scope)
        local conf = GroupDB(scope)
        if conf.fontOverride == true then
            local value = tonumber(conf.nameMaxChars)
            if value ~= nil then return value end
            return conf.nameShortenEnabled == true and 6 or 0
        end
        return SharedNameShorteningMax()
    end

    local function GroupNameShorteningSide(scope)
        local conf = GroupDB(scope)
        if conf.fontOverride == true then
            return conf.nameClipSide == "LEFT" and "LEFT" or "RIGHT"
        end
        return SharedNameShorteningSide()
    end

    local function GroupNameShorteningNoEllipsis(scope)
        local conf = GroupDB(scope)
        if conf.fontOverride == true then return conf.nameNoEllipsis == true end
        return SharedNameShorteningNoEllipsis()
    end

    return {
        GroupNameShorteningEnabled = GroupNameShorteningEnabled,
        GroupNameShorteningMax = GroupNameShorteningMax,
        GroupNameShorteningSide = GroupNameShorteningSide,
        GroupNameShorteningNoEllipsis = GroupNameShorteningNoEllipsis,
        SetGroupFontOverrideValue = SetGroupFontOverrideValue,
    }
end

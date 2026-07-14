local addonName, addonNS = ...
local MSUF = (_G.MSUF_NS) or addonNS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

--- State/MSUF_Defaults.lua
---
--- Owns the saved-variable schema bootstrap for MSUF_DB. This file is allowed
--- to be large because it is coldpath: it runs at login, profile creation,
--- profile switch, import, and explicit default repair. Runtime modules should
--- consume the normalized DB or compiled config, not read migration rules from
--- here during gameplay events.
---
--- Rules for future changes:
--- * Add new saved fields here with nil-preserving defaults.
--- * Put one-shot profile repairs in this file, guarded by migration flags.
--- * Keep factory-profile seeding separate from normal default filling so
---   existing users are never overwritten by a new shipped baseline.

--- MSUF default class-resource colors
--- Keep this tiny and global so:
--- 1) class power fallback colors use the new defaults
--- 2) reset-to-default in the Colors menu also lands on these defaults
--- 3) no runtime overhead in hot paths (one-time table write at load)
do
    local pbc = _G.PowerBarColor
    if type(pbc) == "table" then
        pbc.RUNES = pbc.RUNES or {}
        pbc.RUNES.r, pbc.RUNES.g, pbc.RUNES.b = 128/255, 0, 17/255      --- #800011

        pbc.SOUL_SHARDS = pbc.SOUL_SHARDS or {}
        pbc.SOUL_SHARDS.r, pbc.SOUL_SHARDS.g, pbc.SOUL_SHARDS.b = 135/255, 136/255, 238/255 --- #8788EE
    end
end

--- MSUF Defaults / DB initialization
--- ---
--- Factory default profile (MSUF compact string)
---
--- If MSUF_DB is NEW (fresh install / full reset), we seed it from this payload
--- so the addon boots with your preferred baseline.
---
--- Existing installs are NOT overwritten. This only runs when MSUF_DB was
--- created empty in this session.
--- ---
--- Current factory default profile.
local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = [[MSUF3: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]]

--- Expose the factory compact string for diagnostics and future tooling.
if type(MSUF) == "table" then
    MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
end
ExportPublic("MSUF_FACTORY_DEFAULT_PROFILE_COMPACT", MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)

local function MSUF_Defaults_TryDecodeCompactString(str)
    if type(str) ~= "string" then  return nil end
    local E = _G.C_EncodingUtil
    if not E then  return nil end
    if type(E.DeserializeCBOR) ~= "function" then  return nil end
    if type(E.DecodeBase64) ~= "function" then  return nil end
    local ok, prefix, b64 = pcall(string.match, str, "^%s*(MSUF%d+):%s*(.-)%s*$")
    if not ok or (prefix ~= "MSUF2" and prefix ~= "MSUF3" and prefix ~= "MSUF4") or type(b64) ~= "string" or b64 == "" then  return nil end
    local ok2, cleaned = pcall(string.gsub, b64, "%s+", "")
    if not ok2 or type(cleaned) ~= "string" or cleaned == "" then  return nil end
    local rem = #cleaned % 4
    if rem == 1 then
        return nil
    elseif rem == 2 then
        cleaned = cleaned .. "=="
    elseif rem == 3 then
        cleaned = cleaned .. "="
    end
    local ok3, blob = pcall(E.DecodeBase64, cleaned)
    if not ok3 or type(blob) ~= "string" then  return nil end
    local function TryDeserialize(payload)
        if type(payload) ~= "string" then  return nil end
        local okD, tbl = pcall(E.DeserializeCBOR, payload)
        if okD and type(tbl) == "table" then  return tbl end
        return nil
    end
    local tbl = TryDeserialize(blob)
    if tbl then  return tbl end
    if type(E.DecompressString) ~= "function" then  return nil end
    local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil
    local ok4, plain
    if method ~= nil then
        ok4, plain = pcall(E.DecompressString, blob, method)
        tbl = ok4 and TryDeserialize(plain) or nil
        if tbl then  return tbl end
    end
    ok4, plain = pcall(E.DecompressString, blob)
    tbl = ok4 and TryDeserialize(plain) or nil
    return tbl
end
local function MSUF_Defaults_WipeInPlace(t)
    if not t then  return end
    for k in pairs(t) do t[k] = nil end
 end
local function MSUF_Defaults_DeepCopy(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then  return end
    for k, v in pairs(src) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local tv = type(v)
            if tv == "table" then
                local d = dst[k]
                if type(d) ~= "table" then
                    d = {}
                    dst[k] = d
                else
                    MSUF_Defaults_WipeInPlace(d)
                end
                MSUF_Defaults_DeepCopy(d, v)
            elseif tv == "string" or tv == "number" or tv == "boolean" then
                dst[k] = v
            end
        end
    end
 end
local function MSUF_Defaults_GetProfilePayload(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    --- Current exports wrap profile data as a snapshot. Older/tooling exports may
    --- decode directly to the profile table; keep both valid for factory defaults.
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" then
        return tbl.payload
    end
    return tbl
end

--- Portrait values have changed names more than once. Normalize them before
--- any frame/compiler code sees the DB so downstream modules only need to
--- understand the current enum set.
local function MSUF_Defaults_NormalizePortraitRenderValue(v)
    if v == "CLASS" then return "CLASS" end
    return "2D"
end

local function MSUF_Defaults_NormalizePortraitClassStyleValue(v)
    if v == "class_colored_border" or v == "colored" then return "RONDO_COLOR" end
    if v == "wow_icon_border" or v == "wow" then return "RONDO_WOW" end
    if v == "RONDO_COLOR" or v == "RONDO_WOW" or v == "BLIZZARD" then return v end
    return "BLIZZARD"
end
ExportPublic("MSUF_NormalizePortraitClassStyleValue", MSUF_Defaults_NormalizePortraitClassStyleValue)

local function MSUF_Defaults_NormalizePortraitRenderDB(db)
    if type(db) ~= "table" then return end
    local g = type(db.general) == "table" and db.general or nil
    if g and g._portraitSharedRender ~= nil then
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    if g and g.portraitClassStyle ~= nil then
        g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    end
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss" }) do
        local u = db[unitKey]
        if type(u) == "table" and u.portraitRender ~= nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        if type(u) == "table" and u.portraitClassStyle ~= nil then
            u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        end
    end
end
ExportPublic("MSUF_NormalizePortraitRenderDB", MSUF_Defaults_NormalizePortraitRenderDB)

local MSUF_DEFAULTS_TEXT_SCOPE_KEYS = { "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss" }
local MSUF_DEFAULTS_GROUP_SCOPE_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
local MSUF_DEFAULTS_STATUS_PREFIXES = {
    "leaderIcon", "raidMarker", "levelIndicator", "eliteIcon", "statusText",
    "combatStateIndicator", "restedStateIndicator", "restingStateIndicator",
    "incomingResIndicator", "pvpIndicator", "raidGroupName",
}
local MSUF_DEFAULTS_AURA_NUMERIC_KEYS = {
    offsetX = { -4096, 4096 }, offsetY = { -4096, 4096 },
    buffOffsetX = { -4096, 4096 }, buffOffsetY = { -4096, 4096 },
    debuffOffsetX = { -4096, 4096 }, debuffOffsetY = { -4096, 4096 },
    buffGroupOffsetX = { -4096, 4096 }, buffGroupOffsetY = { -4096, 4096 },
    debuffGroupOffsetX = { -4096, 4096 }, debuffGroupOffsetY = { -4096, 4096 },
    iconSize = { 1, 256 }, buffIconSize = { 1, 256 }, debuffIconSize = { 1, 256 },
    buffGroupIconSize = { 1, 256 }, debuffGroupIconSize = { 1, 256 },
    spacing = { 0, 128 }, splitSpacing = { 0, 256 },
    perRow = { 1, 80 }, buffPerRow = { 1, 80 }, debuffPerRow = { 1, 80 },
    maxIcons = { 0, 80 }, maxBuffs = { 0, 80 }, maxDebuffs = { 0, 80 },
    stackTextSize = { 1, 128 }, cooldownTextSize = { 1, 128 },
    stackTextOffsetX = { -2000, 2000 }, stackTextOffsetY = { -2000, 2000 },
    cooldownTextOffsetX = { -2000, 2000 }, cooldownTextOffsetY = { -2000, 2000 },
    cooldownDecimalSeconds = { 0, 30 }, buffLayer = { 1, 15 }, debuffLayer = { 1, 15 },
}
local MSUF_DEFAULTS_AURA_STRING_KEYS = {
    "growth", "rowWrap", "buffGrowth", "debuffGrowth",
    "buffGrowthX", "buffGrowthY", "debuffGrowthX", "debuffGrowthY",
    "buffRowWrap", "debuffRowWrap", "layoutMode", "buffDebuffAnchor",
    "stackCountAnchor", "cooldownTextAnchor", "buffAnchor", "debuffAnchor",
    "debuffTypeBorderMode", "dispelBorderMode", "pandemicMode",
}
local MSUF_DEFAULTS_AURA_GROWTH_PARTS = {
    RIGHTDOWN = { "RIGHT", "DOWN" }, LEFTDOWN = { "LEFT", "DOWN" },
    RIGHTUP = { "RIGHT", "UP" }, LEFTUP = { "LEFT", "UP" },
    RIGHT = { "RIGHT", nil }, LEFT = { "LEFT", nil },
    UP = { "UP", "UP" }, DOWN = { "DOWN", "DOWN" },
}

local function MSUF_Defaults_ToNumber(value)
    return tonumber(value)
end

local function MSUF_Defaults_CopyIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    tbl[toKey] = tbl[fromKey]
    return true
end

local function MSUF_Defaults_CopyInverseBoolIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    if type(tbl[fromKey]) ~= "boolean" then return false end
    tbl[toKey] = not tbl[fromKey]
    return true
end

local function MSUF_Defaults_CopyNumberAliasIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    local n = MSUF_Defaults_ToNumber(tbl[fromKey])
    if n == nil then return false end
    tbl[toKey] = n
    return true
end

local function MSUF_Defaults_NormalizeNumberField(tbl, key, minValue, maxValue)
    if type(tbl) ~= "table" or tbl[key] == nil then return false end
    local n = MSUF_Defaults_ToNumber(tbl[key])
    if n == nil then return false end
    if minValue ~= nil and n < minValue then
        n = minValue
    elseif maxValue ~= nil and n > maxValue then
        n = maxValue
    end
    if tbl[key] ~= n then
        tbl[key] = n
        return true
    end
    return false
end

local function MSUF_Defaults_UpperStringField(tbl, key)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "string" then return false end
    local upper = string.upper(tbl[key])
    if upper ~= tbl[key] then
        tbl[key] = upper
        return true
    end
    return false
end

local function MSUF_Defaults_TableHasAnyValue(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end

local function MSUF_Defaults_CopyAuraGrowthAlias(tbl, fromKey, toGrowthKey, toWrapKey)
    if type(tbl) ~= "table" or tbl[fromKey] == nil then return false end
    local parts = MSUF_DEFAULTS_AURA_GROWTH_PARTS[tostring(tbl[fromKey] or ""):upper()]
    if not parts then return false end
    local changed = false
    if tbl[toGrowthKey] == nil then
        tbl[toGrowthKey] = parts[1]
        changed = true
    end
    if parts[2] ~= nil and tbl[toWrapKey] == nil then
        tbl[toWrapKey] = parts[2]
        changed = true
    end
    return changed
end

local MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE = {
    player = { 275, 40 },
    target = { 276, 40 },
    focus = { 216, 30 },
    targettarget = { 170, 36 },
    focustarget = { 170, 30 },
    boss = { 264, 35 },
}

local function MSUF_Defaults_A2AuraFrameKey(unit)
    if unit == "tot" or unit == "targetoftarget" then return "targettarget" end
    if unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function MSUF_Defaults_A2AuraFrameSize(profile, unit)
    local key = MSUF_Defaults_A2AuraFrameKey(unit)
    local conf = type(profile) == "table" and type(profile[key]) == "table" and profile[key] or nil
    local defaults = MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE[key] or MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE.player
    local width = MSUF_Defaults_ToNumber(conf and (conf.width or conf.frameWidth)) or defaults[1]
    local height = MSUF_Defaults_ToNumber(conf and (conf.height or conf.frameHeight)) or defaults[2]
    if width < 1 then width = defaults[1] end
    if height < 1 then height = defaults[2] end
    return width, height
end

local function MSUF_Defaults_A2AuraReadNumber(primary, secondary, key, fallback)
    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
    if n ~= nil then return n end
    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
    if n ~= nil then return n end
    return fallback or 0
end

local function MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, profile)
    if type(auras) ~= "table" or auras._msufAuras3LegacyGeometry_v2 == true then return false end
    local shared = type(auras.shared) == "table" and auras.shared or {}
    auras.shared = shared
    local repairV1 = auras._msufAuras3LegacyGeometry_v1 == true
    local changed = false
    if type(auras.perUnit) == "table" then
        for unit, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                local layout = type(unitCfg.layout) == "table" and unitCfg.layout or {}
                unitCfg.layout = layout
                local width, height = MSUF_Defaults_A2AuraFrameSize(profile, unit)
                local baseX = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetX", 0)
                local baseY = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetY", 0)
                local function ReadLaneNumber(primary, secondary, key, aliasKey, fallback)
                    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
                    if n ~= nil then return n end
                    n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[aliasKey]) or nil
                    if n ~= nil then return n end
                    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
                    if n ~= nil then return n end
                    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[aliasKey]) or nil
                    if n ~= nil then return n end
                    return fallback or 0
                end
                for _, lane in ipairs({
                    { "buffGroupOffsetX", "buffGroupOffsetY", "buffAnchor", "buffOffsetX", "buffOffsetY" },
                    { "debuffGroupOffsetX", "debuffGroupOffsetY", "debuffAnchor", "debuffOffsetX", "debuffOffsetY" },
                }) do
                    local anchor = "BOTTOMLEFT"
                    local x
                    local y
                    if repairV1 then
                        x = ReadLaneNumber(layout, nil, lane[1], lane[4], 0)
                        y = ReadLaneNumber(layout, nil, lane[2], lane[5], 0)
                        local oldAnchor = tostring(layout[lane[3]] or ""):upper()
                        if oldAnchor == "TOPRIGHT" or oldAnchor == "BOTTOMRIGHT" then
                            x = x + width
                        end
                        if oldAnchor == "TOPLEFT" or oldAnchor == "TOPRIGHT" then
                            y = y + height
                        end
                    else
                        x = baseX + ReadLaneNumber(layout, shared, lane[1], lane[4], 0)
                        y = height + baseY + ReadLaneNumber(layout, shared, lane[2], lane[5], 0)
                    end
                    if layout[lane[3]] ~= anchor then layout[lane[3]] = anchor; changed = true end
                    if layout[lane[1]] ~= x then layout[lane[1]] = x; changed = true end
                    if layout[lane[2]] ~= y then layout[lane[2]] = y; changed = true end
                end
                if unitCfg.overrideLayout ~= true then unitCfg.overrideLayout = true; changed = true end
            end
        end
    end
    auras._msufAuras3LegacyGeometry_v1 = true
    auras._msufAuras3LegacyGeometry_v2 = true
    return true
end

local function MSUF_Defaults_NormalizeNameShorteningScope(scope, groupScope)
    if type(scope) ~= "table" then return false end
    local changed = false
    if groupScope then
        changed = MSUF_Defaults_CopyIfMissing(scope, "nameShortenEnabled", "shortenNames") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "nameMaxChars", "shortenNameMaxChars") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "nameClipSide", "shortenNameClipSide") or changed
        changed = MSUF_Defaults_CopyInverseBoolIfMissing(scope, "nameNoEllipsis", "shortenNameShowDots") or changed
    else
        changed = MSUF_Defaults_CopyIfMissing(scope, "shortenNames", "nameShortenEnabled") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "shortenNameMaxChars", "nameMaxChars") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "shortenNameClipSide", "nameClipSide") or changed
        changed = MSUF_Defaults_CopyInverseBoolIfMissing(scope, "shortenNameShowDots", "nameNoEllipsis") or changed
    end
    changed = MSUF_Defaults_NormalizeNumberField(scope, "shortenNameMaxChars", 0, 256) or changed
    changed = MSUF_Defaults_NormalizeNumberField(scope, "nameMaxChars", 0, 256) or changed
    changed = MSUF_Defaults_NormalizeNumberField(scope, "shortenNameFrontMaskPx", 0, 128) or changed
    changed = MSUF_Defaults_UpperStringField(scope, "shortenNameClipSide") or changed
    changed = MSUF_Defaults_UpperStringField(scope, "nameClipSide") or changed
    return changed
end

local function MSUF_Defaults_NormalizeTextScope(scope, groupScope)
    if type(scope) ~= "table" then return false end
    local changed = false
    if groupScope then
        changed = MSUF_Defaults_CopyIfMissing(scope, "nameAnchor", "nameTextAnchor") or changed
    else
        changed = MSUF_Defaults_CopyIfMissing(scope, "nameTextAnchor", "nameAnchor") or changed
    end
    changed = MSUF_Defaults_CopyIfMissing(scope, "nameOffsetX", "nameTextOffsetX") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "nameOffsetY", "nameTextOffsetY") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "hpOffsetX", "hpTextOffsetX") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "hpOffsetY", "hpTextOffsetY") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "powerOffsetX", "powerTextOffsetX") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "powerOffsetY", "powerTextOffsetY") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "textLeft", "hpTextLeft") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "textCenter", "hpTextCenter") or changed
    changed = MSUF_Defaults_CopyIfMissing(scope, "textRight", "hpTextRight") or changed
    if groupScope then
        changed = MSUF_Defaults_CopyIfMissing(scope, "textDelimiter", "hpTextSeparator") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "powerTextDelimiter", "powerTextSeparator") or changed
    else
        changed = MSUF_Defaults_CopyIfMissing(scope, "hpTextSeparator", "textDelimiter") or changed
        changed = MSUF_Defaults_CopyIfMissing(scope, "powerTextSeparator", "powerTextDelimiter") or changed
    end
    for _, key in ipairs({ "nameOffsetX", "nameOffsetY", "hpOffsetX", "hpOffsetY", "powerOffsetX", "powerOffsetY" }) do
        changed = MSUF_Defaults_NormalizeNumberField(scope, key, -500, 500) or changed
    end
    changed = MSUF_Defaults_UpperStringField(scope, "nameTextAnchor") or changed
    changed = MSUF_Defaults_UpperStringField(scope, "nameAnchor") or changed
    changed = MSUF_Defaults_NormalizeNameShorteningScope(scope, groupScope == true) or changed
    return changed
end

local function MSUF_Defaults_NormalizeStatusScope(scope, groupScope)
    if type(scope) ~= "table" then return false end
    local changed = false
    local boolAliases = groupScope and {
        { "roleIcon", "showRoleIcon" }, { "leaderIcon", "showLeaderIcon" },
        { "assistIcon", "showAssistIcon" }, { "raidMarker", "showRaidMarker" },
        { "statusText", "statusTextEnabled" }, { "statusGhostText", "statusGhostTextEnabled" },
        { "statusAFKText", "statusAFKTextEnabled" }, { "showGroupNumber", "showRaidGroupInName" },
    } or {
        { "showLeaderIcon", "leaderIcon" }, { "showRaidMarker", "raidMarker" },
        { "showLevelIndicator", "levelIndicator" }, { "showEliteIcon", "eliteIcon" },
        { "statusTextEnabled", "statusText" }, { "showCombatStateIndicator", "combatStateIndicator" },
        { "showRestingIndicator", "restedStateIndicator" }, { "showRestingIndicator", "restingStateIndicator" },
        { "showIncomingResIndicator", "incomingResIndicator" }, { "showPvpIndicator", "pvpIndicator" },
        { "showRaidGroupInName", "raidGroupName" },
    }
    for i = 1, #boolAliases do
        changed = MSUF_Defaults_CopyIfMissing(scope, boolAliases[i][1], boolAliases[i][2]) or changed
    end
    local offsetAliases = groupScope and {
        { "roleIconX", "roleIconOffsetX" }, { "roleIconY", "roleIconOffsetY" },
        { "leaderIconX", "leaderIconOffsetX" }, { "leaderIconY", "leaderIconOffsetY" },
        { "assistIconX", "assistIconOffsetX" }, { "assistIconY", "assistIconOffsetY" },
        { "raidMarkerX", "raidMarkerOffsetX" }, { "raidMarkerY", "raidMarkerOffsetY" },
        { "statusOffsetX", "statusTextOffsetX" }, { "statusOffsetY", "statusTextOffsetY" },
        { "statusGhostOffsetX", "statusGhostTextOffsetX" }, { "statusGhostOffsetY", "statusGhostTextOffsetY" },
        { "statusAFKOffsetX", "statusAFKTextOffsetX" }, { "statusAFKOffsetY", "statusAFKTextOffsetY" },
        { "groupNumberX", "raidGroupNameOffsetX" }, { "groupNumberY", "raidGroupNameOffsetY" },
    } or {
        { "leaderIconOffsetX", "leaderIconX" }, { "leaderIconOffsetY", "leaderIconY" },
        { "raidMarkerOffsetX", "raidMarkerX" }, { "raidMarkerOffsetY", "raidMarkerY" },
        { "statusTextOffsetX", "statusOffsetX" }, { "statusTextOffsetY", "statusOffsetY" },
        { "raidGroupNameOffsetX", "groupNumberX" }, { "raidGroupNameOffsetY", "groupNumberY" },
    }
    for i = 1, #offsetAliases do
        changed = MSUF_Defaults_CopyIfMissing(scope, offsetAliases[i][1], offsetAliases[i][2]) or changed
    end
    for i = 1, #MSUF_DEFAULTS_STATUS_PREFIXES do
        local prefix = MSUF_DEFAULTS_STATUS_PREFIXES[i]
        changed = MSUF_Defaults_NormalizeNumberField(scope, prefix .. "Size", 1, 256) or changed
        changed = MSUF_Defaults_NormalizeNumberField(scope, prefix .. "OffsetX", -500, 500) or changed
        changed = MSUF_Defaults_NormalizeNumberField(scope, prefix .. "OffsetY", -500, 500) or changed
        changed = MSUF_Defaults_NormalizeNumberField(scope, prefix .. "Layer", 0, 30) or changed
        changed = MSUF_Defaults_UpperStringField(scope, prefix .. "Anchor") or changed
    end
    if groupScope then
        for _, key in ipairs({
            "roleIconX", "roleIconY", "raidMarkerX", "raidMarkerY",
            "leaderIconX", "leaderIconY", "assistIconX", "assistIconY",
            "statusOffsetX", "statusOffsetY", "statusGhostOffsetX", "statusGhostOffsetY",
            "statusAFKOffsetX", "statusAFKOffsetY", "groupNumberX", "groupNumberY",
        }) do
            changed = MSUF_Defaults_NormalizeNumberField(scope, key, -500, 500) or changed
        end
        for _, key in ipairs({ "roleIconAnchor", "raidMarkerAnchor", "leaderIconAnchor", "assistIconAnchor", "statusTextAnchor", "statusGhostTextAnchor", "statusAFKTextAnchor", "groupNumberAnchor" }) do
            changed = MSUF_Defaults_UpperStringField(scope, key) or changed
        end
    end
    return changed
end

local function MSUF_Defaults_NormalizeAuraLayoutTable(tbl)
    if type(tbl) ~= "table" then return false end
    local changed = false
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "maxBuffs", "maxIcons") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "maxDebuffs", "maxIcons") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "buffIconSize") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "debuffIconSize") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "iconSize") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "iconSize") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "buffOffsetX") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "buffOffsetY") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "debuffOffsetX") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "debuffOffsetY") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "offsetX") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "offsetY") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "offsetX") or changed
    changed = MSUF_Defaults_CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "offsetY") or changed
    changed = MSUF_Defaults_CopyAuraGrowthAlias(tbl, "buffGrowth", "buffGrowthX", "buffGrowthY") or changed
    changed = MSUF_Defaults_CopyAuraGrowthAlias(tbl, "debuffGrowth", "debuffGrowthX", "debuffGrowthY") or changed
    changed = MSUF_Defaults_CopyIfMissing(tbl, "buffGrowthY", "buffRowWrap") or changed
    changed = MSUF_Defaults_CopyIfMissing(tbl, "debuffGrowthY", "debuffRowWrap") or changed
    changed = MSUF_Defaults_CopyIfMissing(tbl, "buffGrowthY", "rowWrap") or changed
    changed = MSUF_Defaults_CopyIfMissing(tbl, "debuffGrowthY", "rowWrap") or changed
    for key, limits in pairs(MSUF_DEFAULTS_AURA_NUMERIC_KEYS) do
        changed = MSUF_Defaults_NormalizeNumberField(tbl, key, limits[1], limits[2]) or changed
    end
    for i = 1, #MSUF_DEFAULTS_AURA_STRING_KEYS do
        changed = MSUF_Defaults_UpperStringField(tbl, MSUF_DEFAULTS_AURA_STRING_KEYS[i]) or changed
    end
    return changed
end

local function MSUF_Defaults_NormalizeAuras3Profile(db)
    if type(db) ~= "table" then return false end
    local changed = false
    local fromLegacyAuras2 = false
    if db.auras ~= nil then
        db.auras = nil
        changed = true
    end
    if type(db.auras2) == "table" and (type(db.auras3) ~= "table" or tonumber(db._msufProfileSchema) ~= 600) then
        db.auras3 = {}
        MSUF_Defaults_DeepCopy(db.auras3, db.auras2)
        db.auras3._msufAuras3TranslatedFromLegacyAuras2 = true
        fromLegacyAuras2 = true
        changed = true
    end
    if db.auras2 ~= nil then
        db.auras2 = nil
        changed = true
    end
    local auras = db.auras3
    if type(auras) ~= "table" then return changed end
    if fromLegacyAuras2 or (auras._msufAuras3TranslatedFromLegacyAuras2 == true and auras._msufAuras3LegacyGeometry_v2 ~= true) then
        changed = MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, db) or changed
    end
    changed = MSUF_Defaults_NormalizeAuraLayoutTable(auras.shared) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = MSUF_Defaults_NormalizeAuraLayoutTable(unitCfg.layout) or changed
                changed = MSUF_Defaults_NormalizeAuraLayoutTable(unitCfg.layoutShared) or changed
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout ~= true then
                    unitCfg.overrideLayout = true
                    changed = true
                end
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout ~= true then
                    unitCfg.overrideSharedLayout = true
                    changed = true
                end
            end
        end
    end
    return changed
end

local function MSUF_Defaults_NormalizeUnitPositionAliases(db)
    if type(db) ~= "table" then return false end
    local changed = false
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        local u = db[key]
        if type(u) == "table" then
            changed = MSUF_Defaults_CopyIfMissing(u, "point", "anchorMyPoint") or changed
            changed = MSUF_Defaults_CopyIfMissing(u, "relativePoint", "anchorRelPoint") or changed
            changed = MSUF_Defaults_UpperStringField(u, "point") or changed
            changed = MSUF_Defaults_UpperStringField(u, "relativePoint") or changed
            changed = MSUF_Defaults_NormalizeNumberField(u, "offsetX", -10000, 10000) or changed
            changed = MSUF_Defaults_NormalizeNumberField(u, "offsetY", -10000, 10000) or changed
        end
    end
    return changed
end

local function MSUF_Defaults_NormalizeProfileTo60Defaults(db)
    if type(db) ~= "table" then return false end
    local sharedTranslator = _G.MSUF_ProfileIO_TranslateProfileToCurrent
    if type(sharedTranslator) ~= "function" and type(MSUF) == "table" then
        sharedTranslator = MSUF.MSUF_ProfileIO_TranslateProfileToCurrent
    end
    if type(sharedTranslator) == "function" then
        local _, changed = sharedTranslator(db, { source = "defaults", markProfile = true })
        if db.auras ~= nil then
            db.auras = nil
            changed = true
        end
        if db.auras2 ~= nil then
            db.auras2 = nil
            changed = true
        end
        return changed == true
    end
    local changed = false
    changed = MSUF_Defaults_NormalizeUnitPositionAliases(db) or changed
    changed = MSUF_Defaults_NormalizeAuras3Profile(db) or changed
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        changed = MSUF_Defaults_NormalizeTextScope(db[key], false) or changed
        changed = MSUF_Defaults_NormalizeStatusScope(db[key], false) or changed
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        changed = MSUF_Defaults_NormalizeTextScope(db[key], true) or changed
        changed = MSUF_Defaults_NormalizeStatusScope(db[key], true) or changed
    end
    return changed
end
ExportPublic("MSUF_NormalizeProfileTo60Defaults", MSUF_Defaults_NormalizeProfileTo60Defaults)

local MSUF_DEFAULT_BOSS_OFFSET_X = 360
local MSUF_DEFAULT_BOSS_OFFSET_Y = 230

local function MSUF_Defaults_DisableFactoryNameShortening(db)
    if type(db) ~= "table" then return false end
    local changed = false
    if db.shortenNames ~= false then
        db.shortenNames = false
        changed = true
    end
    if db.nameShortenEnabled ~= nil and db.nameShortenEnabled ~= false then
        db.nameShortenEnabled = false
        changed = true
    end
    if type(db.general) == "table" then
        local g = db.general
        if g.shortenNames ~= nil and g.shortenNames ~= false then
            g.shortenNames = false
            changed = true
        end
        if g.nameShortenEnabled ~= nil and g.nameShortenEnabled ~= false then
            g.nameShortenEnabled = false
            changed = true
        end
    end
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        local scope = db[key]
        if type(scope) == "table" then
            if scope.shortenNames ~= nil and scope.shortenNames ~= false then
                scope.shortenNames = false
                changed = true
            end
            if scope.nameShortenEnabled ~= nil and scope.nameShortenEnabled ~= false then
                scope.nameShortenEnabled = false
                changed = true
            end
        end
    end
    return changed
end

--- Default position offsets per unit, mirrored from the fill() defaults below.
--- Exposed so Edit Mode popups can offer a "Reset position" action that only
--- touches the frame's position, not its size or other settings.
local MSUF_DEFAULT_UNIT_OFFSETS = {
    player       = { -256, -180 },
    target       = { 320, -180 },
    focus        = { -260, -300 },
    targettarget = { 220, -300 },
    focustarget  = { 260, 180 },
    pet          = { -275, -250 },
    boss         = { MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y },
}
local function MSUF_GetDefaultUnitOffsets(unit)
    local o = unit and MSUF_DEFAULT_UNIT_OFFSETS[unit]
    if o then return o[1], o[2] end
    return 0, 0
end
ExportPublic("MSUF_GetDefaultUnitOffsets", MSUF_GetDefaultUnitOffsets)

local MSUF_DEFAULT_EXPRESSWAY_LOCALES = {
    enUS = true,
    enGB = true,
    deDE = true,
}
local MSUF_DEFAULT_EXPRESSWAY_FONT =
    "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf"

local function MSUF_Defaults_GetEffectiveLocale()
    if type(MSUF) == "table" and type(MSUF.GetEffectiveLocale) == "function" then
        local ok, locale = pcall(MSUF.GetEffectiveLocale)
        if ok and type(locale) == "string" and locale ~= "" then
            return locale
        end
    end
    if type(_G.GetLocale) == "function" then
        local ok, locale = pcall(_G.GetLocale)
        if ok and type(locale) == "string" and locale ~= "" then
            return locale
        end
    end
    return (type(MSUF) == "table" and MSUF.CLIENT_LOCALE) or "enUS"
end

local function MSUF_Defaults_UseExpresswayByDefault()
    return MSUF_DEFAULT_EXPRESSWAY_LOCALES[MSUF_Defaults_GetEffectiveLocale()] == true
end

local function MSUF_Defaults_GetBlizzardFontPath()
    local fontObject = _G.GameFontNormal
    if fontObject and type(fontObject.GetFont) == "function" then
        local ok, path = pcall(fontObject.GetFont, fontObject)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    if type(_G.STANDARD_TEXT_FONT) == "string" and _G.STANDARD_TEXT_FONT ~= "" then
        return _G.STANDARD_TEXT_FONT
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function MSUF_Defaults_GetGlobalFontDefault()
    if MSUF_Defaults_UseExpresswayByDefault() then
        return MSUF_DEFAULT_EXPRESSWAY_FONT
    end
    return MSUF_Defaults_GetBlizzardFontPath()
end

local function MSUF_Defaults_GetMenuFontDefault()
    --- Empty means: preserve the locale-aware Blizzard font inherited by each
    --- menu font object instead of replacing it with a Latin-only font file.
    if MSUF_Defaults_UseExpresswayByDefault() then
        return MSUF_DEFAULT_EXPRESSWAY_FONT
    end
    return ""
end

local MSUF_DEFAULT_PREDICTION_BAR_VALUES = {
    enableAbsorbBar = true,
    healAbsorbEnabled = true,
    absorbTextMode = 2,
    absorbAnchorMode = 5,
    healPredAnchorMode = 3,
    absorbBarOpacity = 1,
    absorbBarTexture = "MSUF Smooth v2",
    healAbsorbBarOpacity = 1,
    healAbsorbBarTexture = "Solid",
    overAbsorbOverlay = true,
}

local function MSUF_Defaults_ApplyPredictionBarBaseline(db)
    if type(db) ~= "table" then return end
    db.general = db.general or {}

    local function Apply(conf)
        if type(conf) ~= "table" then return end
        for key, value in pairs(MSUF_DEFAULT_PREDICTION_BAR_VALUES) do
            conf[key] = value
        end
    end

    Apply(db.general)
    db.general.showSelfHealPrediction = true

    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss",
    }) do
        Apply(db[key])
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local conf = db[key]
        Apply(conf)
        if type(conf) == "table" then
            conf.healPredEnabled = true
        end
    end
end

--- Fresh-install completion (applied only when the factory profile payload is seeded).
--- The compact factory export is the visual source of truth; this pass completes
--- structural fields and locale/runtime-dependent product defaults.
local function MSUF_Defaults_ApplyFreshInstallOverrides(db)
    if not db then  return end
    local function SetDefault(tbl, key, value)
        if type(tbl) == "table" and tbl[key] == nil then
            tbl[key] = value
        end
    end

    MSUF_Defaults_ApplyPredictionBarBaseline(db)

    --- Unified alpha defaults: HP fill opacity, power fill opacity, background
    --- texture opacity, and a toggle to keep text + portrait opaque while bars dim.
    --- Group frames still use the HP/background subset.
    local function EnsureUnitAlphaDefaults(conf)
        if not conf then  return end
        if conf.hpBarAlpha == nil then conf.hpBarAlpha = 1 end
        if conf.powerBarAlpha == nil then conf.powerBarAlpha = 1 end
        if conf.hpBgAlpha == nil then conf.hpBgAlpha = 0.85 end
        if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
        if conf.alphaExcludeTextPortrait == nil then conf.alphaExcludeTextPortrait = false end
    end
    local function EnsureFreshUnitframeScreenPosition(conf, x, y)
        if type(conf) ~= "table" then return end
        if conf.anchorFrameName == nil and conf.anchorToUnitframe == nil then
            conf.anchorToUnitframe = "GLOBAL"
        end
        SetDefault(conf, "offsetX", x)
        SetDefault(conf, "offsetY", y)
    end
    local function EnsureFreshGroupAuraNativeRenderer(conf)
        if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
        local auras = conf.auras
        SetDefault(auras, "renderer", "NATIVE_12_1")
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        local types = auras.blizzardTypes
        SetDefault(types, "buffs", true)
        SetDefault(types, "debuffs", true)
        SetDefault(types, "dispels", true)
        SetDefault(types, "externals", true)
        SetDefault(auras, "blizzardIconSize", 20)
        SetDefault(auras, "blizzardShowCooldownText", true)
        SetDefault(auras, "blizzardOrganizationType", "default")
        SetDefault(auras, "blizzardDispelMode", "allDispellable")
        SetDefault(auras, "blizzardDispelBorder", false)
        SetDefault(auras, "blizzardContainerAnchor", "FRAME")
        SetDefault(auras, "blizzardContainerX", 0)
        SetDefault(auras, "blizzardContainerY", 0)
        for _, key in ipairs({ "buff", "debuff", "externals" }) do
            if type(auras[key]) ~= "table" then auras[key] = {} end
            SetDefault(auras[key], "strata", "AUTO")
            if key == "buff" then SetDefault(auras[key], "trackedStrata", "AUTO") end
            SetDefault(auras[key], "cooldownSwipeReverse", false)
            SetDefault(auras[key], "sortMethod", "DEFAULT")
            SetDefault(auras[key], "sortReverse", false)
            SetDefault(auras[key], "showDurationBar", false)
            SetDefault(auras[key], "durationBarHeight", 2)
            SetDefault(auras[key], "durationBarDisplay", "BAR_ONLY")
            SetDefault(auras[key], "durationBarPosition", "BOTTOM")
            SetDefault(auras[key], "durationBarDirection", "REMAINING")
            if type(auras[key].blacklist) ~= "table" then auras[key].blacklist = {} end
            if type(auras[key].blacklist.spells) ~= "table" then auras[key].blacklist.spells = {} end
            SetDefault(auras[key].blacklist, "hidePermanent", false)
        end
    end
    EnsureUnitAlphaDefaults(db.player)
    --- Fresh-install default: player name hidden
    if type(db.player) == "table" then
        SetDefault(db.player, "showName", false)
    end
    EnsureUnitAlphaDefaults(db.target)
    EnsureUnitAlphaDefaults(db.focus)
    EnsureUnitAlphaDefaults(db.focustarget)
    EnsureUnitAlphaDefaults(db.pet)
    EnsureUnitAlphaDefaults(db.boss)
    EnsureUnitAlphaDefaults(db.targettarget)
    EnsureUnitAlphaDefaults(db.tot)
    --- Older exports may omit screen positions; in that case provide stable
    --- center anchors without touching positions included by the compact export.
    EnsureFreshUnitframeScreenPosition(db.player, -260, 80)
    EnsureFreshUnitframeScreenPosition(db.target, 260, 80)
    EnsureFreshUnitframeScreenPosition(db.focus, 260, 135)
    EnsureFreshUnitframeScreenPosition(db.focustarget, 260, 180)
    EnsureFreshUnitframeScreenPosition(db.pet, -260, 135)
    EnsureFreshUnitframeScreenPosition(db.targettarget or db.tot, 260, 225)
    EnsureFreshUnitframeScreenPosition(db.boss, MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y)
    EnsureFreshGroupAuraNativeRenderer(db.gf_party)
    EnsureFreshGroupAuraNativeRenderer(db.gf_raid)
    EnsureFreshGroupAuraNativeRenderer(db.gf_mythicraid)
    db.bars = db.bars or {}
    SetDefault(db.bars, "showAltMana", false)
    SetDefault(db.bars, "roundedFramesEnabled", false)
    SetDefault(db.bars, "roundedUnitFrames", true)
    SetDefault(db.bars, "roundedGroupFrames", true)
    SetDefault(db.bars, "roundedPowerBars", true)
    SetDefault(db.bars, "roundedMouseover", true)
    --- Fresh-install defaults: status indicators (AFK/DND) off by default
    local g = db.general
    if type(g) == 'table' then
        g.statusIndicators = g.statusIndicators or {}
        local si = g.statusIndicators
        SetDefault(si, "showAFK", false)
        SetDefault(si, "showDND", false)

        --- Fresh-install scaling defaults:
        --- Match Unhalted-style global UI scale: disabled until the user enables it.
        SetDefault(g, "anchorToCooldown", false)
        SetDefault(g, "anchorName", "UIParent")
        SetDefault(g, "disableScaling", false)
        SetDefault(g, "globalUiScalePreset", "auto")
        if type(g.UIScale) ~= "table" then
            g.UIScale = { Enabled = false, Scale = 1.0 }
        else
            SetDefault(g.UIScale, "Enabled", false)
            SetDefault(g.UIScale, "Scale", 1.0)
        end
        SetDefault(g, "msufUiScale", 1.0)
        --- English/German use MSUF's highly readable UI face. Other locales
        --- retain Blizzard's locale-specific glyph coverage.
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
        SetDefault(g, "unitTooltipProvider", "GAME")
        SetDefault(g, "unitTooltipAnchor", "EXTERNAL")
        SetDefault(g, "unitTooltipMode", "ALWAYS")
        SetDefault(g, "unitTooltipModifier", "ALT")
        SetDefault(g, "disableUnitInfoTooltips", true)
        SetDefault(g, "unitInfoTooltipStyle", "classic")
        SetDefault(g, "showGameMenuButton", true)
        SetDefault(g, "navHoverScale", 1.05)
        g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
        g._msufFactoryNameShorteningFixed_v1 = true
        g._msufFactoryScopedNameShorteningFixed_v1 = true
    end
    MSUF_Defaults_NormalizePortraitRenderDB(db)
end

--- Factory profile flow:
--- The embedded compact string is a product baseline for brand-new installs.
--- It is decoded only when MSUF_DB is empty or contains only early bootstrap
--- buckets created before the UnitFrame factory runs, then normal defaults
--- and migrations still run afterward to fill fields added after the snapshot.
local function MSUF_Defaults_CreateFactoryProfile()
    local tbl = MSUF_Defaults_TryDecodeCompactString(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if not tbl then  return nil end
    local payload = MSUF_Defaults_GetProfilePayload(tbl)
    if type(payload) ~= "table" then  return nil end

    local out = {}
    MSUF_Defaults_DeepCopy(out, payload)
    MSUF_Defaults_ApplyFreshInstallOverrides(out)
    MSUF_Defaults_NormalizeProfileTo60Defaults(out)
    out.general = out.general or {}
    out.general._msufFactoryProfileApplied = true
    return out
end
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS = {
    gameplay = true,
    general = true,
    _msufProfileSchema = true,
    _msufProfileNormalizationRevision = true,
}
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS = {
    fontBaselineOffset = true,
    minimapIconDB = true,
    navHoverScale = true,
    showGameMenuButton = true,
    showMinimapIcon = true,
}
local function MSUF_Defaults_TableHasOnlyAllowedKeys(tbl, allowed)
    if type(tbl) ~= "table" then return false end
    for key in pairs(tbl) do
        if not allowed[key] then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_IsFreshInstallProfileDB(db)
    if type(db) ~= "table" then return false end
    if next(db) == nil then return true end

    local g = (type(db.general) == "table") and db.general or nil
    if g and g._msufFactoryProfileApplied then
        return false
    end

    --- On a true first login, startup modules registered before the UF factory
    --- may create harmless roots such as gameplay/general before EnsureDB runs.
    --- Treat only that pre-seed shape as fresh; any unit/config root means this
    --- profile already has real saved data and must not be overwritten.
    for key, value in pairs(db) do
        if not MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS[key] then
            return false
        end
        if key == "general"
            and not MSUF_Defaults_TableHasOnlyAllowedKeys(value, MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS) then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()
    if type(MSUF_DB) ~= "table" then  return end
    local g = (type(MSUF_DB.general) == "table") and MSUF_DB.general or nil
    if g and g._msufFactoryProfileApplied then
         return
    end
    if not MSUF_Defaults_IsFreshInstallProfileDB(MSUF_DB) then return end
    local payload = MSUF_Defaults_CreateFactoryProfile()
    if type(payload) ~= "table" then  return end
    --- Overlay the fresh DB with the decoded payload. DeepCopy replaces known
    --- payload tables and leaves unrelated future bootstrap buckets intact.
    MSUF_Defaults_DeepCopy(MSUF_DB, payload)
end
local function MSUF_Defaults_RepairFactoryNameShortening(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufFactoryProfileApplied == true) then return false end
    local looksLikeFactoryShortening = db.shortenNames == true
        and tonumber(g.shortenNameMaxChars) == 8
        and tostring(g.shortenNameClipSide or ""):upper() == "RIGHT"
        and g.shortenNameShowDots == false
    local hasScopedFactoryShortening = false
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        local scope = db[key]
        if type(scope) == "table" and (scope.shortenNames == true or scope.nameShortenEnabled == true) then
            hasScopedFactoryShortening = true
            break
        end
    end
    if g._msufFactoryNameShorteningFixed_v1 == true
        and g._msufFactoryScopedNameShorteningFixed_v1 == true
        and not looksLikeFactoryShortening
        and not hasScopedFactoryShortening then
        return false
    end
    local changed = false
    if g._msufFactoryNameShorteningFixed_v1 ~= true or looksLikeFactoryShortening then
        if looksLikeFactoryShortening then
            db.shortenNames = false
            changed = true
        end
        g._msufFactoryNameShorteningFixed_v1 = true
    end
    if g._msufFactoryScopedNameShorteningFixed_v1 ~= true or hasScopedFactoryShortening then
        changed = MSUF_Defaults_DisableFactoryNameShortening(db) or changed
        g._msufFactoryScopedNameShorteningFixed_v1 = true
    end
    return changed
end
local MSUF_DB_LastHeavyRun
local MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = 600
--- Persisted completion marker for the broad default-fill/repair pass below.
--- Bump this whenever MSUF_EnsureDB_Heavy gains a new mandatory default or
--- one-shot repair; current profiles can then be repaired exactly once again.
local MSUF_DEFAULTS_CURRENT_REVISION = 1

--- Root tables are the contract every other module assumes after EnsureDB.
--- Add new top-level SavedVariables buckets here before modules start reading
--- them, then fill nested defaults later in MSUF_EnsureDB_Heavy.
local MSUF_DEFAULTS_ROOT_TABLE_KEYS = {
    "general",
    "classColors",
    "npcColors",
    "bars",
    "gameplay",
    "player",
    "target",
    "targettarget",
    "focustarget",
    "focus",
    "pet",
    "boss",
}
local function MSUF_Defaults_EnsureRootTables()
    for _, key in ipairs(MSUF_DEFAULTS_ROOT_TABLE_KEYS) do
        if type(MSUF_DB[key]) ~= "table" then
            MSUF_DB[key] = {}
        end
    end
end

--- Migration helpers live above MSUF_EnsureDB_Heavy so the heavy function reads
--- as "ensure roots, migrate old profile shapes, then fill missing defaults".
--- Keep migrations idempotent: EnsureDB can be forced after imports/profile
--- switches and must be safe to run repeatedly on the same profile table.
local MSUF_DEFAULTS_FONT_KEY_ALIASES = {
    ["Friz Quadrata TT"]        = "FRIZQT",
    ["Arial Narrow"]            = "ARIALN",
    ["Morpheus"]                = "MORPHEUS",
    ["Skurri"]                  = "SKURRI",
    ["Friz Quadrata (default)"] = "FRIZQT",
    ["Arial (default)"]         = "ARIALN",
    ["Morpheus (default)"]      = "MORPHEUS",
    ["Skurri (default)"]        = "SKURRI",
    ["Expressway Regular (MSUF)"] = "EXPRESSWAY",
    ["Expressway (MSUF)"]         = "EXPRESSWAY",
    ["Expressway Bold (MSUF)"]    = "EXPRESSWAY_BOLD",
    ["Expressway SemiBold (MSUF)"] = "EXPRESSWAY_SEMIBOLD",
    ["Expressway ExtraBold (MSUF)"] = "EXPRESSWAY_EXTRABOLD",
    ["Expressway Condensed Light (MSUF)"] = "EXPRESSWAY_CONDENSED_LIGHT",
}

local function MSUF_Defaults_NormalizeFontKey(key)
    if type(key) ~= "string" or key == "" then return key end
    return MSUF_DEFAULTS_FONT_KEY_ALIASES[key] or key
end

local function MSUF_Defaults_NormalizeFontField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_Defaults_NormalizeFontKey(tbl.fontKey)
    local resolveKeyPath = _G.MSUF_ResolveFontKeyPath
    if type(resolveKeyPath) == "function" then
        local resolved = resolveKeyPath(normalized)
        if type(resolved) == "string" and resolved ~= "" then
            normalized = resolved
        end
    end
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

local MSUF_DISPEL_PRIORITY_MIGRATION = 3
local MSUF_DISPEL_TYPE_PRIORITY_KEYS = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
}
local MSUF_PRIORITY_KEY_ALIAS = {
    Dispel = "dispel",
    DISPEL = "dispel",
    Magic = "magic",
    MAGIC = "magic",
    Curse = "curse",
    CURSE = "curse",
    Disease = "disease",
    DISEASE = "disease",
    Poison = "poison",
    POISON = "poison",
    Bleed = "bleed",
    BLEED = "bleed",
    Aggro = "aggro",
    AGGRO = "aggro",
    Purge = "purge",
    PURGE = "purge",
    BossTarget = "bossTarget",
    Boss_Target = "bossTarget",
    ["Boss Target"] = "bossTarget",
    ["boss target"] = "bossTarget",
    boss_target = "bossTarget",
    bosstarget = "bossTarget",
    BOSS_TARGET = "bossTarget",
    Target = "target",
    TARGET = "target",
    Focus = "focus",
    FOCUS = "focus",
}

local function MSUF_Defaults_NormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return MSUF_PRIORITY_KEY_ALIAS[key] or key
end

local function MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    if includeTargetFocus then
        return { "dispel", "aggro", "purge", "bossTarget", "target", "focus" }
    end
    return { "dispel", "aggro", "purge", "bossTarget" }
end

local function MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
    local defaults = MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    local allowed = {}
    for i = 1, #defaults do allowed[defaults[i]] = true end
    local out, used = {}, {}
    if type(raw) == "table" then
        for i = 1, #raw do
            local key = MSUF_Defaults_NormalizePriorityKey(raw[i])
            if MSUF_DISPEL_TYPE_PRIORITY_KEYS[key] then key = "dispel" end
            if allowed[key] and not used[key] then
                out[#out + 1] = key
                used[key] = true
            end
        end
    end
    for i = 1, #defaults do
        local key = defaults[i]
        if not used[key] then
            out[#out + 1] = key
            used[key] = true
        end
    end
    return out
end

local function MSUF_Defaults_MigratePriorityScope(scope, includeTargetFocus)
    if type(scope) ~= "table" then return end
    local raw = type(scope.hlPrioOrder) == "table" and scope.hlPrioOrder
        or (type(scope.highlightPrioOrder) == "table" and scope.highlightPrioOrder)
        or nil
    if raw then
        local visual = MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
        scope.hlPrioOrder = visual
        if type(scope.highlightPrioOrder) == "table" then
            scope.highlightPrioOrder = visual
        end
    end

    --- Debuff-type custom sorting was removed from the visible model. Old
    --- profiles are force-collapsed into the single Dispel layer and all old
    --- overlay/type priority switches are disabled so no hidden state survives.
    scope.hlDispelTypePrioEnabled = nil
    scope.hlDispelTypePrioOrder = nil
    scope.unitDispelOverlayPrioEnabled = nil
    scope.unitDispelOverlayPrioOrder = nil
    scope.unitDispelOverlayUseHighlightPriority = nil
    scope.dispelOverlayPrioEnabled = nil
    scope.dispelOverlayPrioOrder = nil
    scope.dispelOverlayUseHighlightPriority = nil
end

local function MSUF_Defaults_MigrateDispelPriorityProfile(db, force)
    if type(db) ~= "table" then return false end
    if force ~= true and tonumber(db._msufDispelPriorityMigration) == MSUF_DISPEL_PRIORITY_MIGRATION then
        return false
    end
    MSUF_Defaults_MigratePriorityScope(db.general, true)
    for _, key in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], false)
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], true)
    end
    db._msufDispelPriorityMigration = MSUF_DISPEL_PRIORITY_MIGRATION
    return true
end

local function MSUF_Defaults_MigrateDispelPriorityProfiles()
    local changed = false
    if not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_MigrateDispelPriorityProfile(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_MigrateDispelPriorityProfile(MSUF_DB) or changed
    end
    return changed
end

ExportPublic("MSUF_MigrateDispelPriorityProfile", MSUF_Defaults_MigrateDispelPriorityProfile)
ExportPublic("MSUF_MigrateDispelPriorityProfiles", MSUF_Defaults_MigrateDispelPriorityProfiles)

local function MSUF_Defaults_MigrateGroupTooltipProfile(db)
    if type(db) ~= "table" then return false end
    local changed = false
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local scope = db[key]
        if type(scope) == "table" and (scope.tooltipMode ~= nil or scope.tooltipModifier ~= nil) then
            scope.tooltipMode = nil
            scope.tooltipModifier = nil
            changed = true
        end
    end
    return changed
end

local function MSUF_Defaults_MigrateGroupTooltipProfiles()
    local changed = false
    if not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_MigrateGroupTooltipProfile(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_MigrateGroupTooltipProfile(MSUF_DB) or changed
    end
    return changed
end

local function MSUF_Defaults_HasScopedFontOverrideValue(scope)
    if type(scope) ~= "table" then return false end
    if scope.fontOutline ~= nil or scope.noOutline ~= nil or scope.boldText ~= nil then return true end
    if scope.fontMonochrome ~= nil or scope.fontTextAlpha ~= nil or scope.fontBaselineOffset ~= nil then return true end
    if scope.textBackdrop ~= nil or scope.fontShadowStrength ~= nil or scope.colorPowerTextByType ~= nil or scope.colorHealthTextByHealth ~= nil then return true end
    if scope.nameClassColor ~= nil or scope.npcNameRed ~= nil or scope.nameNpcClassColor ~= nil then return true end
    if scope.useGlobalFontColor == false then return true end
    if scope.fontR ~= nil or scope.fontG ~= nil or scope.fontB ~= nil then return true end
    local mode = scope.nameColorMode
    if mode ~= nil and mode ~= "" and mode ~= "DEFAULT" then return true end
    if scope.nameShortenEnabled ~= nil then return true end
    if (tonumber(scope.nameMaxChars) or 0) > 0 then return true end
    if scope.nameClipSide ~= nil or scope.nameNoEllipsis == true then return true end
    if scope.shortenNames ~= nil or scope.shortenNameMaxChars ~= nil then return true end
    if scope.shortenNameClipSide ~= nil or scope.shortenNameFrontMaskPx ~= nil then return true end
    if scope.shortenNameShowDots ~= nil then return true end
    return false
end

local function MSUF_Defaults_ClearScopedFontKeys()
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        local scope = MSUF_DB and MSUF_DB[key]
        if type(scope) == "table" then
            scope.fontKey = nil
            scope.nameShortenOverride = nil
            scope._msufGFNameTruncationOverride = nil
            if scope.fontOverride == true and not MSUF_Defaults_HasScopedFontOverrideValue(scope) then
                scope.fontOverride = false
            end
        end
    end
end

--- Main DB repair pass. This is deliberately broad and cold: it may normalize
--- several systems in one run, but it is protected by MSUF_DB_LastHeavyRun in
--- the public wrapper below so normal callers do not pay for it repeatedly.
local function MSUF_EnsureDB_Heavy()
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    --- Seed brand-new installs / hard-resets from the factory profile payload.
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()
    MSUF_Defaults_EnsureRootTables()
    local g = MSUF_DB.general
    MSUF_Defaults_RepairFactoryNameShortening(MSUF_DB)
    MSUF_Defaults_MigrateDispelPriorityProfiles()
    MSUF_Defaults_MigrateGroupTooltipProfiles()
    MSUF_Defaults_NormalizePortraitRenderDB(MSUF_DB)
    if MSUF_DB._msufNativeDispelTriggerMigration ~= 1 then
        if g.dispelBorderTrigger == nil or g.dispelBorderTrigger == "BY_ME" then
            g.dispelBorderTrigger = "DISPEL_TYPE"
        end
        MSUF_DB._msufNativeDispelTriggerMigration = 1
    end
    local legacyPortraitOverrideState = false
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss" }) do
        local u = MSUF_DB[unitKey]
        if type(u) == "table" and u.portraitDecoOverride ~= nil then
            legacyPortraitOverrideState = true
            break
        end
    end
    if type(MSUF_DB.classColors) ~= "table" then MSUF_DB.classColors = {} end
    if type(MSUF_DB.npcColors) ~= "table" then MSUF_DB.npcColors = {} end
    if g.fontKey == nil then
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
    end
    MSUF_Defaults_NormalizeFontField(g)
    if g.hardKillBlizzardPlayerFrame == nil then
        --- Default: Hard-hide Blizzard PlayerFrame (compat mode OFF).
        g.hardKillBlizzardPlayerFrame = true
    end
if g.anchorName == nil then
    g.anchorName = "UIParent"
end
if g.anchorToCooldown == nil then
    g.anchorToCooldown = false
end
--- New install defaults (UI scale + Flash menu anchor)
--- Default: Unhalted-style global UI scale disabled; local MSUF scales remain independent.
if g.disableScaling == nil then
    g.disableScaling = false
end
if g.globalUiScalePreset == nil then
    g.globalUiScalePreset = "auto"
end
--- Migrate global UI scale storage to the Unhalted-style table:
--- General.UIScale.Enabled + General.UIScale.Scale. Keep the legacy preset keys
--- populated so older exports/tools can still reason about the profile.
do
    local legacyScalingDisabled = (g.disableScaling == true)
    local function PresetScale(preset, fallback)
        if preset == "1080p" then return 768 / 1080 end
        if preset == "1440p" then return 768 / 1440 end
        if preset == "4k" then return 768 / 2160 end
        if preset == "pixel" and type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return 768 / h end
        end
        return tonumber(fallback)
    end
    local ui = (type(g.UIScale) == "table") and g.UIScale or nil
    if not ui then
        ui = {}
        g.UIScale = ui
        local preset = g.globalUiScalePreset
        local scale = PresetScale(preset, g.globalUiScaleValue) or 1.0
        local enabled = (not legacyScalingDisabled)
            and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
        ui.Enabled = enabled and true or false
        ui.Scale = scale
        ui._migratedFromGlobalPreset_v1 = true
    end
    if ui.Enabled == nil then
        local preset = g.globalUiScalePreset
        ui.Enabled = (not legacyScalingDisabled)
            and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
    end
    ui.Enabled = (ui.Enabled == true)
    ui.Scale = tonumber(ui.Scale) or PresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0
    if ui.Scale < 0.3 then ui.Scale = 0.3 elseif ui.Scale > 1.5 then ui.Scale = 1.5 end
    if legacyScalingDisabled then
        ui.Enabled = false
    end
    g.disableScaling = false
    if ui.Enabled then
        g.globalUiScaleValue = ui.Scale
        if g.globalUiScalePreset ~= "1080p" and g.globalUiScalePreset ~= "1440p"
            and g.globalUiScalePreset ~= "4k" and g.globalUiScalePreset ~= "pixel" and g.globalUiScalePreset ~= "custom" then
            g.globalUiScalePreset = "custom"
        end
    elseif g.globalUiScalePreset == nil then
        g.globalUiScalePreset = "auto"
    end
end
--- Nil value = Off (Unhalted-style global UI scale disabled)
--- (Do NOT seed a default globalUiScaleValue on fresh installs.)
if g.msufUiScale == nil then
    g.msufUiScale = 1.0
end
if g.flashFullPoint == nil then g.flashFullPoint = "CENTER" end
if g.flashFullRelPoint == nil then g.flashFullRelPoint = "CENTER" end
if g.flashFullX == nil then g.flashFullX = -60 end
if g.flashFullY == nil then g.flashFullY = 10 end
if g.flashFullW == nil then g.flashFullW = 900 end
if g.flashFullH == nil then g.flashFullH = 700 end
if g.flashFullXpx == nil then g.flashFullXpx = -60 end
if g.flashFullYpx == nil then g.flashFullYpx = 10 end
if g.tipCycleIndex == nil then
    g.tipCycleIndex = 11
end
--- Minimap icon (LibDBIcon) defaults
if g.showMinimapIcon == nil then
    g.showMinimapIcon = true
end
if g.dropdownStyleMode == nil then
    g.dropdownStyleMode = "msuf"
elseif g.dropdownStyleMode ~= "old" and g.dropdownStyleMode ~= "msuf" and g.dropdownStyleMode ~= "blizzard" and g.dropdownStyleMode ~= "legacy" then
    g.dropdownStyleMode = "msuf"
end
if g.pendingDropdownStyleMode ~= nil and g.pendingDropdownStyleMode ~= "old" and g.pendingDropdownStyleMode ~= "msuf" and g.pendingDropdownStyleMode ~= "blizzard" and g.pendingDropdownStyleMode ~= "legacy" then
    g.pendingDropdownStyleMode = nil
end
if type(g.minimapIconDB) ~= "table" then
    g.minimapIconDB = { hide = false, minimapPos = 220, radius = 80 }
else
    if g.minimapIconDB.hide == nil then g.minimapIconDB.hide = false end
    if g.minimapIconDB.minimapPos == nil then g.minimapIconDB.minimapPos = 220 end
    if g.minimapIconDB.radius == nil then g.minimapIconDB.radius = 80 end
end
--- Target select / target lost sounds (opt-in; matches default Blizzard UI behavior)
--- Default OFF to avoid changing behavior for existing users.
if g.playTargetSelectLostSounds == nil then
    g.playTargetSelectLostSounds = false
end
--- Fonts: optionally color the *power text* by the unit's current power type (mana/rage/energy/etc).
--- Default OFF to preserve existing behavior.
if g.colorPowerTextByType == nil then
    g.colorPowerTextByType = false
end
--- Fonts: optionally color the *health text* by current health percentage.
--- Default OFF to preserve existing behavior.
if g.colorHealthTextByHealth == nil then
    g.colorHealthTextByHealth = false
end
if g.slashMenuSnapEnabled == nil then
    g.slashMenuSnapEnabled = true
end
if g.hideAdvancedMenu == nil then
    g.hideAdvancedMenu = true
end
if g.showNavigationIcons == nil then
    g.showNavigationIcons = false
end
if g.showGameMenuButton == nil then
    g.showGameMenuButton = true
end
if g.navHoverScale == nil then
    g.navHoverScale = 1.05
end
if g.menuFontKey == nil then
    g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
end
    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = false --- Default: Snap OFF
    end
    if g.editModeGridStep == nil then
        g.editModeGridStep = 20
    end
    if g.editModeGridEnabled == nil then
        g.editModeGridEnabled = true
    end
if g.editModeSnapEnabled == nil then
    g.editModeSnapEnabled = false
end
if g.editModeSnapMode == nil then
    g.editModeSnapMode = "grid"
end
if g.editModeSnapModeGrid == nil then
    g.editModeSnapModeGrid = true
end
if g.editModeSnapModeFrames == nil then
    g.editModeSnapModeFrames = false
end
if g.editModeHideWhiteArrows == nil then
    g.editModeHideWhiteArrows = true
end
    if g.linkEditModes == nil then
        g.linkEditModes = true
    end
 if g.darkMode == nil then
        g.darkMode = false
    end
    if g.darkBarTone == nil then
        g.darkBarTone = "black"
    end
    if g.darkBgBrightness == nil then
        g.darkBgBrightness = 0.25      --- 25% Grau als Standard
    end
    --- When true, dark mode uses the bar-background tint color directly (no brightness dimming).
    --- Allows fully custom background colors (including white) in dark mode.
    if g.darkBgCustomColor == nil then
        g.darkBgCustomColor = false
    end
    if g.classBarBgR == nil or g.classBarBgG == nil or g.classBarBgB == nil then
        g.classBarBgR = 0.0   --- default: black background
        g.classBarBgG = 0.0
        g.classBarBgB = 0.0
    end
    --- If enabled, bar background tint color follows the current HP bar color (class/reaction/unified),
    --- instead of using the custom tint swatch.
    if g.barBgMatchHPColor == nil then
        g.barBgMatchHPColor = false
    end
    --- If enabled, the HP background uses the unit's class color while the HP
    --- foreground can stay in Dark/Unified/Gradient mode.
    if g.barBgClassColor == nil then
        g.barBgClassColor = false
    end
    if g.enableGradient == nil then
        g.enableGradient = false
    end
    if g.enableHealthGradient == nil then
        g.enableHealthGradient = true
    end
    if g.healthGradientLowR == nil or g.healthGradientLowG == nil or g.healthGradientLowB == nil then
        g.healthGradientLowR = 1
        g.healthGradientLowG = 0
        g.healthGradientLowB = 0
    end
    if g.healthGradientMidR == nil or g.healthGradientMidG == nil or g.healthGradientMidB == nil then
        g.healthGradientMidR = 1
        g.healthGradientMidG = 1
        g.healthGradientMidB = 0
    end
    if g.healthGradientHighR == nil or g.healthGradientHighG == nil or g.healthGradientHighB == nil then
        g.healthGradientHighR = 0
        g.healthGradientHighG = 1
        g.healthGradientHighB = 0
    end
    if g.enablePowerGradient == nil then
        g.enablePowerGradient = false
    end
    --- Bars: Aggro highlight overlay (Target/Focus/Boss)
    --- Aggro indicator: re-uses the HP outline border as an orange warning when YOU have aggro (target/focus/boss).
    if g.aggroIndicatorMode == nil then
        if g.enableAggroHighlight == true then
            g.aggroIndicatorMode = "border" --- legacy migrate
        else
            g.aggroIndicatorMode = "off"
        end
    end
    if g.aggroIndicatorMode ~= "border" then
        g.aggroIndicatorMode = "off"
    end

    if g.gradientStrength == nil then
        g.gradientStrength = 0.45
    end
do
    local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
    if not hasNew then
        local dir = g.gradientDirection
        if type(dir) ~= "string" or dir == "" then
            dir = "RIGHT"
        else
            dir = string.upper(dir)
        end
        if dir == "LEFT" then
            g.gradientDirLeft = true
        elseif dir == "UP" then
            g.gradientDirUp = true
        elseif dir == "DOWN" then
            g.gradientDirDown = true
        else
            g.gradientDirRight = true
        end
    end
    if g.gradientDirLeft == nil then g.gradientDirLeft = false end
    if g.gradientDirRight == nil then g.gradientDirRight = false end
    if g.gradientDirUp == nil then g.gradientDirUp = false end
    if g.gradientDirDown == nil then g.gradientDirDown = false end
    if (not g.gradientDirLeft) and (not g.gradientDirRight) and (not g.gradientDirUp) and (not g.gradientDirDown) then
        g.gradientDirRight = true
    end
    --- Keep legacy key as a reasonable fallback for older builds/tools.
    if type(g.gradientDirection) ~= "string" or g.gradientDirection == "" then
        g.gradientDirection = "RIGHT"
    end
end
    if g.editModeBgAlpha == nil or type(g.editModeBgAlpha) ~= "number" then
        g.editModeBgAlpha = 0.75
    else
        if g.editModeBgAlpha < 0.1 then
            g.editModeBgAlpha = 0.1
        elseif g.editModeBgAlpha > 0.8 then
            g.editModeBgAlpha = 0.8
        end
    end
    if g.useClassColors == nil then
        g.useClassColors = true
    end
    if g.barMode == nil then
        if g.useClassColors then
            g.barMode = "class"
        elseif g.darkMode then
            g.barMode = "dark"
        else
            g.barMode = "dark"
            g.darkMode = true
            g.useClassColors = false
        end
    end
    --- Normalize Bar mode (supports: dark / class / unified / gradient) and keep legacy flags in sync
    if g.barMode ~= "dark" and g.barMode ~= "class" and g.barMode ~= "unified" and g.barMode ~= "gradient" then
        g.barMode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end
    if g.barMode == "dark" then
        g.darkMode = true
        g.useClassColors = false
    elseif g.barMode == "class" then
        g.darkMode = false
        g.useClassColors = true
    elseif g.barMode == "gradient" then
        --- Gradient mode is HP-derived; neither legacy flag applies.
        g.darkMode = false
        g.useClassColors = false
    else --- unified
        g.darkMode = false
        g.useClassColors = false
    end
    --- NPC Color Mode: "reaction" (classic friendly/neutral/enemy) or "type" (boss/miniboss/caster/melee/regular).
    --- When "type", enemy NPC health bars in barMode "class" show classification-based colors.
    if g.npcColorMode == nil then
        g.npcColorMode = "reaction"
    end
    if g.npcColorMode ~= "reaction" and g.npcColorMode ~= "type" then
        g.npcColorMode = "reaction"
    end
    if g.npcTypeColorBar == nil then
        g.npcTypeColorBar = true
    end
    if g.npcTypeColorText == nil then
        g.npcTypeColorText = true
    end
    if g.npcClassColorBar == nil then
        g.npcClassColorBar = false
    end
    --- Per-unit NPC Type enable (nil/true = on, false = off)
    if g.npcTypeTarget == nil then g.npcTypeTarget = true end
    if g.npcTypeFocus  == nil then g.npcTypeFocus  = true end
    if g.npcTypeBoss   == nil then g.npcTypeBoss   = true end
    if g.npcTypeToT    == nil then g.npcTypeToT    = true end
        if type(g.unifiedBarR) ~= "number" then g.unifiedBarR = 0.10 end
        if type(g.unifiedBarG) ~= "number" then g.unifiedBarG = 0.60 end
        if type(g.unifiedBarB) ~= "number" then g.unifiedBarB = 0.90 end
    if g.useBarBorder == nil then
        g.useBarBorder = true
    end
    local function NormalizeStaticOutlineColor(tbl)
        if type(tbl) ~= "table" then return end
        if tbl.barOutlineColorMode ~= nil then
            local mode = type(tbl.barOutlineColorMode) == "string" and tbl.barOutlineColorMode:upper() or "BLACK"
            local hasStaticColor = type(tbl.barOutlineColorR) == "number"
                and type(tbl.barOutlineColorG) == "number"
                and type(tbl.barOutlineColorB) == "number"
                and (tbl.barOutlineColorR ~= 0 or tbl.barOutlineColorG ~= 0 or tbl.barOutlineColorB ~= 0)
            if mode == "CLASS" or (mode ~= "CUSTOM" and not hasStaticColor) then
                tbl.barOutlineColorR = 0
                tbl.barOutlineColorG = 0
                tbl.barOutlineColorB = 0
            end
            tbl.barOutlineColorMode = nil
        end
        if tbl.barOutlineColorR ~= nil or tbl.barOutlineColorG ~= nil or tbl.barOutlineColorB ~= nil then
            tbl.barOutlineColorA = 1
        end
    end
    NormalizeStaticOutlineColor(g)
    for _, key in ipairs({ "player", "target", "focus", "boss", "pet", "targettarget", "focustarget", "gf_party", "gf_raid", "gf_mythicraid" }) do
        NormalizeStaticOutlineColor(MSUF_DB[key])
    end
    if g.barBorderStyle == nil then
        g.barBorderStyle = "THIN"
    end
    if g.boldText == nil then
        g.boldText = false
    end
    if g.noOutline == nil then
        g.noOutline = false
    end
    if g.nameClassColor == nil then
        g.nameClassColor = false
    end
    if g.npcNameRed == nil then
        g.npcNameRed = false
    end
    if g.nameNpcClassColor == nil then
        g.nameNpcClassColor = false
    end
    if g.fontColor == nil then
        g.fontColor = "white"
    end
    if g.shortenNameMaxChars == nil then
        g.shortenNameMaxChars = 6
    end
    if g.shortenNameClipSide == nil then
        g.shortenNameClipSide = "LEFT" --- default: clip LEFT, keep name end (R41z0r-style)
    end
    if g.shortenNameFrontMaskPx == nil then
        g.shortenNameFrontMaskPx = 8 --- px eaten from the clipped side (secret-safe, viewport inset)
    end
    if g.shortenNameShowDots == nil then
        g.shortenNameShowDots = true --- show '...' on the clipped edge (secret-safe)
    end
    if g.useCustomFontColor == nil then
        g.useCustomFontColor = false
    end
    if g.useCustomFontColor and (g.fontColorCustomR == nil or g.fontColorCustomG == nil or g.fontColorCustomB == nil) then
        g.useCustomFontColor = false
        g.fontColorCustomR = nil
        g.fontColorCustomG = nil
        g.fontColorCustomB = nil
    end
    if g.textBackdrop == nil then
        g.textBackdrop = true
    end
    if g.fontMonochrome == nil then
        g.fontMonochrome = false
    end
    if g.fontShadowStrength ~= "SOFT" and g.fontShadowStrength ~= "DEEP" then
        g.fontShadowStrength = "NORMAL"
    end
    if type(g.fontTextAlpha) ~= "number" then
        g.fontTextAlpha = 1
    elseif g.fontTextAlpha < 0.7 then
        g.fontTextAlpha = 0.7
    elseif g.fontTextAlpha > 1 then
        g.fontTextAlpha = 1
    end
    if type(g.fontBaselineOffset) ~= "number" then
        g.fontBaselineOffset = 0
    elseif g.fontBaselineOffset < -4 then
        g.fontBaselineOffset = -4
    elseif g.fontBaselineOffset > 4 then
        g.fontBaselineOffset = 4
    end
    if g.highlightEnabled == nil then
        g.highlightEnabled = true
    end
    local fontColors = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
    if type(g.highlightColor) ~= "string" then
        g.highlightColor = "white"
    else
        g.highlightColor = string.lower(g.highlightColor)
        if not (fontColors and fontColors[g.highlightColor]) then
            g.highlightColor = "white"
        end
    end
    --- Status indicators (AFK/DND/Dead/Ghost toggles)
    if g.statusIndicators == nil then
        g.statusIndicators = {}
    end

    --- Boss Target Highlight: colored border on the boss unitframe you currently target
    if g.bossTargetHighlightEnabled == nil then
        g.bossTargetHighlightEnabled = true
    end
    if type(g.bossTargetHighlightColor) ~= "table" then
        g.bossTargetHighlightColor = { 1, 0.82, 0 }   --- gold
    end
    --- Border system integration (0=off, 1=on; synced with bossTargetHighlightEnabled)
    if g.bossTargetOutlineMode == nil then
        g.bossTargetOutlineMode = g.bossTargetHighlightEnabled and 1 or 0
    end
    --- UnitFrame dispel overlay (health-bar tint driven by native 12.1 aura visual state)
    if g.dispelOutlineMode == nil then g.dispelOutlineMode = 1 end
    if g.dispelBorderTrigger == nil then g.dispelBorderTrigger = "DISPEL_TYPE" end
    if g.unitDispelOverlayEnabled == nil then g.unitDispelOverlayEnabled = false end
    if g.unitDispelOverlayStyle == nil then g.unitDispelOverlayStyle = "FULL" end
    if g.unitDispelOverlayOnHealth == nil then g.unitDispelOverlayOnHealth = true end
    if g.unitDispelOverlayAlpha == nil then g.unitDispelOverlayAlpha = 0.35 end
    if g.unitDispelOverlayTrigger == nil then g.unitDispelOverlayTrigger = "BORDER" end
    local si = g.statusIndicators
    if si.showAFK == nil then si.showAFK = false end
    if si.showDND == nil then si.showDND = false end
    if si.showDead == nil then si.showDead = true end
    if si.showGhost == nil then si.showGhost = true end
    --- Drop obsolete update tuning keys. The 6.0 runtime is event-driven and no
    --- longer reads these values.
    g.miscUpdatesPreset = nil
    g.frameUpdateInterval = nil
    g.castbarUpdateInterval = nil
    g.ufcoreFlushBudgetMs = nil
    g.ufcoreUrgentMaxPerFlush = nil
    MSUF_FrameUpdateInterval = nil
    MSUF_CastbarUpdateInterval = nil
    local hadLegacyTooltipDisable = (g.disableUnitInfoTooltips ~= nil)
    local hadLegacyTooltipStyle = (g.unitInfoTooltipStyle ~= nil)
    local hadTooltipProvider = (g.unitTooltipProvider ~= nil)
    local hadTooltipAnchor = (g.unitTooltipAnchor ~= nil)
    if g.disableUnitInfoTooltips == nil then
        g.disableUnitInfoTooltips = true
    end
    if g.unitInfoTooltipStyle == nil then
        g.unitInfoTooltipStyle = "classic"
    end
    if (not hadTooltipProvider) and (not hadTooltipAnchor)
        and (not hadLegacyTooltipDisable) and (not hadLegacyTooltipStyle)
        and g.tooltipPosX == nil and g.tooltipPosY == nil then
        g.unitTooltipProvider = "GAME"
        g.unitTooltipAnchor = "EXTERNAL"
    end
    if g.unitTooltipProvider == nil then
        if g.disableUnitInfoTooltips == false then
            g.unitTooltipProvider = "MSUF"
        else
            g.unitTooltipProvider = "GAME"
        end
    elseif g.unitTooltipProvider ~= "GAME" and g.unitTooltipProvider ~= "MSUF" then
        g.unitTooltipProvider = "GAME"
    end
    if g.unitTooltipAnchor == nil then
        if g.unitTooltipProvider == "MSUF" then
            g.unitTooltipAnchor = (g.unitInfoTooltipStyle == "modern") and "CURSOR" or "FIXED"
        elseif (type(g.tooltipPosX) == "number") and (type(g.tooltipPosY) == "number") then
            g.unitTooltipAnchor = "FIXED"
        elseif g.unitInfoTooltipStyle == "modern" then
            g.unitTooltipAnchor = "CURSOR"
        elseif g.disableUnitInfoTooltips == true then
            g.unitTooltipAnchor = "EXTERNAL"
        else
            g.unitTooltipAnchor = "EXTERNAL"
        end
    elseif g.unitTooltipAnchor ~= "EXTERNAL" and g.unitTooltipAnchor ~= "FIXED" and g.unitTooltipAnchor ~= "CURSOR" then
        g.unitTooltipAnchor = "EXTERNAL"
    end
    if g.unitTooltipProvider == "MSUF" and g.unitTooltipAnchor == "EXTERNAL" then
        g.unitTooltipAnchor = "FIXED"
    end
    if g.unitTooltipMode == nil then
        g.unitTooltipMode = "ALWAYS"
    elseif g.unitTooltipMode == "OFF" then
        g.unitTooltipMode = "NEVER"
    elseif g.unitTooltipMode ~= "ALWAYS" and g.unitTooltipMode ~= "OOC"
        and g.unitTooltipMode ~= "MODIFIER" and g.unitTooltipMode ~= "NEVER" then
        g.unitTooltipMode = "ALWAYS"
    end
    if g.unitTooltipModifier == nil then
        g.unitTooltipModifier = "ALT"
    elseif g.unitTooltipModifier ~= "ALT" and g.unitTooltipModifier ~= "CTRL" and g.unitTooltipModifier ~= "SHIFT" then
        g.unitTooltipModifier = "ALT"
    end
    g.disableUnitInfoTooltips = (g.unitTooltipProvider ~= "MSUF")
    g.unitInfoTooltipStyle = (g.unitTooltipAnchor == "CURSOR") and "modern" or "classic"
    --- Tooltip custom position (set via Edit Mode drag).
    --- nil / false = use default style-based positioning (classic/modern).
    --- When set, these are BOTTOMLEFT-relative pixel coordinates on UIParent.
    --- Intentionally NOT defaulted: absence means "no custom position".
    if g.tooltipPosX ~= nil and type(g.tooltipPosX) ~= "number" then g.tooltipPosX = nil end
    if g.tooltipPosY ~= nil and type(g.tooltipPosY) ~= "number" then g.tooltipPosY = nil end
    if g.castbarInterruptibleColor == nil then
        g.castbarInterruptibleColor = "turquoise"
    end
    if g.castbarNonInterruptibleColor == nil then
        g.castbarNonInterruptibleColor = "red"
    end
    if g.castbarInterruptColor == nil then
        g.castbarInterruptColor = "red"
    end
    if g.playerCastbarOverrideEnabled == nil then
        g.playerCastbarOverrideEnabled = true
    end
    if g.playerCastbarOverrideMode == nil then
        g.playerCastbarOverrideMode = "CLASS" --- "CLASS" or "CUSTOM"
    end
    if g.playerCastbarOverrideR == nil then g.playerCastbarOverrideR = 1 end
    if g.playerCastbarOverrideG == nil then g.playerCastbarOverrideG = 1 end
    if g.playerCastbarOverrideB == nil then g.playerCastbarOverrideB = 1 end
    if g.castbarFillDirection == nil then
        g.castbarFillDirection = "RTL"
    end
if g.castbarUnifiedFillDirection ~= nil then
        if g.castbarUnifiedDirection == nil then
            g.castbarUnifiedDirection = (g.castbarUnifiedFillDirection == true)
        end
        g.castbarUnifiedFillDirection = nil
    end
    if g.castbarUnifiedDirection == nil then
        g.castbarUnifiedDirection = false
    end
    --- Channeled casts: show 5 tick lines (channel tick markers)
    if g.castbarShowChannelTicks == nil then
        g.castbarShowChannelTicks = false
    end
    --- Opposite fill-direction for enemy castbar
    if g.castbarOpositeDirectionTarget == nil then
        g.castbarOpositeDirectionTarget = false
    end
    --- Removed GCD/instant-cast bar. Force-disable legacy profiles that had it enabled.
    g.showGCDBar = false
    if g.empowerColorStages == nil then
        g.empowerColorStages = true
    end
    if g.empowerStageBlink == nil then
        g.empowerStageBlink = true
    end
    if g.empowerStageBlinkTime == nil or type(g.empowerStageBlinkTime) ~= "number" then
        g.empowerStageBlinkTime = 0.25
    end
    if g.enableTargetCastbar == nil then
        g.enableTargetCastbar = true
    end
    if g.enableFocusCastbar == nil then
        g.enableFocusCastbar = true
    end
    if g.enablePlayerCastbar == nil then
        g.enablePlayerCastbar = true
    end
    if g.enableBossCastbar == nil then
        g.enableBossCastbar = true
    end
    local function _NormalizeCastbarBackendDefault(value)
        if value == true then return "MSUF" end
        if value == false then return "BLIZZARD" end
        if type(value) ~= "string" then return nil end
        local v = value:upper()
        if v == "MSUF" then return "MSUF" end
        if v == "BLIZZARD" or v == "BLIZZ" or v == "DEFAULT" or v == "SHOW" then return "BLIZZARD" end
        if v == "HIDE" or v == "HIDDEN" or v == "NONE" or v == "DISABLED" then return "HIDE" end
        return nil
    end
    local function _InitCastbarBackend(unit, backendKey, enableKey)
        local backend = _NormalizeCastbarBackendDefault(g[backendKey])
        if not backend then
            backend = (g[enableKey] == false) and ((unit == "player") and "BLIZZARD" or "HIDE") or "MSUF"
        elseif backend == "BLIZZARD" and unit ~= "player" then
            backend = "HIDE"
        end
        g[backendKey] = backend
        g[enableKey] = (backend == "MSUF")
    end
    _InitCastbarBackend("player", "castbarPlayerBackend", "enablePlayerCastbar")
    _InitCastbarBackend("target", "castbarTargetBackend", "enableTargetCastbar")
    _InitCastbarBackend("focus", "castbarFocusBackend", "enableFocusCastbar")
    _InitCastbarBackend("boss", "bossCastbarBackend", "enableBossCastbar")
if g.showPlayerCastTime == nil then
    g.showPlayerCastTime = true
end
if g.showTargetCastTime == nil then
    g.showTargetCastTime = true
end
if g.showFocusCastTime == nil then
    g.showFocusCastTime = true
end
if g.showBossCastTime == nil then
    g.showBossCastTime = true
end
if g.castbarPlayerTimeFormat == nil then
    g.castbarPlayerTimeFormat = "CURRENT"
end
if g.castbarTargetTimeFormat == nil then
    g.castbarTargetTimeFormat = "CURRENT"
end
if g.castbarFocusTimeFormat == nil then
    g.castbarFocusTimeFormat = "CURRENT"
end
if g.bossCastTimeFormat == nil then
    g.bossCastTimeFormat = "CURRENT"
end
if g.bossCastbarOffsetX == nil then
    g.bossCastbarOffsetX = 2
end
if g.bossCastbarOffsetY == nil then
    g.bossCastbarOffsetY = -46
end
if g.bossCastbarWidth == nil then
    g.bossCastbarWidth = 176
end
if g.bossCastbarHeight == nil then
    g.bossCastbarHeight = 12
end
    if g.castbarShowIcon == nil then
        g.castbarShowIcon = true
    end
    if g.castbarShowSpellName == nil then
        g.castbarShowSpellName = true
    end
    if g.castbarShakeStrength == nil then
        g.castbarShakeStrength = 8   --- pixels; 0 = no movement
    end
    if g.castbarSpellNameFontSize == nil then
        g.castbarSpellNameFontSize = 0
    end
    if g.castbarTimeFontSize == nil then
        g.castbarTimeFontSize = 0
    end
    if g.castbarIconOffsetX == nil then
        g.castbarIconOffsetX = 0
    end
    if g.castbarIconOffsetY == nil then
        g.castbarIconOffsetY = 0
    end
    if g.castbarTargetOffsetX == nil then
        g.castbarTargetOffsetX = 0
    end
    if g.castbarTargetOffsetY == nil then
        g.castbarTargetOffsetY = -60
    end
    if g.castbarFocusOffsetX == nil then
        g.castbarFocusOffsetX = 2
    end
    if g.castbarFocusOffsetY == nil then
        g.castbarFocusOffsetY = -50
    end
    if g.castbarPlayerOffsetX == nil then
        g.castbarPlayerOffsetX = -2
    end
    if g.castbarPlayerOffsetY == nil then
        g.castbarPlayerOffsetY = -59
    end
    if g.castbarPlayerTimeOffsetX == nil then
        g.castbarPlayerTimeOffsetX = -2
    end
    if g.castbarPlayerTimeOffsetY == nil then
        g.castbarPlayerTimeOffsetY = 0
    end
    if g.castbarFocusTimeOffsetX == nil then
        g.castbarFocusTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarFocusTimeOffsetY == nil then
        g.castbarFocusTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarTargetTimeOffsetX == nil then
        g.castbarTargetTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarTargetTimeOffsetY == nil then
        g.castbarTargetTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarGlobalWidth == nil then
        g.castbarGlobalWidth = 200   --- Standardbreite
    end
    if g.castbarGlobalHeight == nil then
        g.castbarGlobalHeight = 18   --- Standardhöhe
    end
    --- Per-castbar default sizes (match Edit Mode preview defaults)
    if g.castbarPlayerBarWidth == nil then g.castbarPlayerBarWidth = 271 end
    if g.castbarPlayerBarHeight == nil then g.castbarPlayerBarHeight = 18 end
    if g.castbarTargetBarWidth == nil then g.castbarTargetBarWidth = 272 end
    if g.castbarTargetBarHeight == nil then g.castbarTargetBarHeight = 18 end
    if g.castbarFocusBarWidth == nil then g.castbarFocusBarWidth = 175 end
    if g.castbarFocusBarHeight == nil then g.castbarFocusBarHeight = 18 end
    if g.castbarPlayerPreviewEnabled == nil then
        g.castbarPlayerPreviewEnabled = true
    end
--- Legacy Auras 1.x DB cleanup (Patch 6D Step 2)
g.targetAuraFilter = nil
g.targetAuraWidth = nil
g.targetAuraHeight = nil
g.targetAuraScale = nil
g.targetAuraAlpha = nil
g.targetAuraOffsetX = nil
g.targetAuraOffsetY = nil
g.targetAuraDisplay = nil
if g.fontSize == nil then
        g.fontSize = 14
    end
    --- Per-text font sizes (0 means "use global" in some menus, but these are explicit defaults)
    if g.nameFontSize == nil then g.nameFontSize = 14 end
    if g.hpFontSize == nil then g.hpFontSize = 14 end
    if g.powerFontSize == nil then g.powerFontSize = 14 end
    if g.auraFontSize == nil then g.auraFontSize = 25 end
    if g.castbarBackgroundTexture == nil then
        g.castbarBackgroundTexture = "Solid"
    end
--- Textures (explicit defaults)
if g.castbarTexture == nil then
    g.castbarTexture = "Solid"
end
--- Castbar visuals
if g.castbarShowGlow == nil then
    g.castbarShowGlow = false
end
if g.castbarShowSpark == nil then
    g.castbarShowSpark = false
end
if g.castbarSparkOverflow == nil then
    g.castbarSparkOverflow = true
end
--- Unit castbar width matching:
--- nil/"manual" = manual, "unitframe" = own MSUF unitframe,
--- "essential" = CDM essential row, "utility" = CDM utility bar.
local function NormalizeCastbarWidthSourceKey(key, legacyUnitWidthKey, aliasKey)
    if aliasKey and g[key] == nil and g[aliasKey] ~= nil then
        g[key] = g[aliasKey]
    end
    if g[key] == nil and legacyUnitWidthKey and g[legacyUnitWidthKey] == true then
        g[key] = "unitframe"
    end
    if g[key] == "manual" then
        g[key] = nil
    elseif g[key] ~= nil
        and g[key] ~= "unitframe"
        and g[key] ~= "essential"
        and g[key] ~= "utility"
    then
        g[key] = nil
    end
end
NormalizeCastbarWidthSourceKey("castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth")
NormalizeCastbarWidthSourceKey("castbarTargetMatchWidth", "castbarTargetMatchUnitWidth")
NormalizeCastbarWidthSourceKey("castbarFocusMatchWidth", "castbarFocusMatchUnitWidth")
NormalizeCastbarWidthSourceKey("bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth")
--- Interrupt Ready Indicator
if g.kickReadyShowTarget == nil then g.kickReadyShowTarget = false end
if g.kickReadyShowFocus  == nil then g.kickReadyShowFocus  = false end
if g.kickReadyShowBoss   == nil then g.kickReadyShowBoss   = false end
if g.kickReadyStyle      == nil then g.kickReadyStyle      = "border" end
if g.kickReadySize       == nil then g.kickReadySize       = 8 end
if g.kickReadyAnchor     == nil then g.kickReadyAnchor     = "RIGHT" end
if g.kickReadyOffsetX    == nil then g.kickReadyOffsetX    = 4 end
if g.kickReadyOffsetY    == nil then g.kickReadyOffsetY    = 0 end
if g.kickReadyColor      == nil then g.kickReadyColor      = { ["1"] = 0, ["2"] = 1, ["3"] = 0 } end
if g.kickNotReadyColor   == nil then g.kickNotReadyColor   = { ["1"] = 1, ["2"] = 0, ["3"] = 0 } end
--- Aura highlight colors (used by Auras 2.0 highlight pipeline)
if g.aurasOwnBuffHighlightColor == nil then
    g.aurasOwnBuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasOwnDebuffHighlightColor == nil then
    g.aurasOwnDebuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasStackCountColor == nil then
    g.aurasStackCountColor = { ["1"] = 1, ["2"] = 1, ["3"] = 1 }
end
    --- Per-castbar toggles + offsets
    if g.castbarTargetShowIcon == nil then g.castbarTargetShowIcon = true end
    if g.castbarFocusShowIcon == nil then g.castbarFocusShowIcon = true end
    if g.castbarPlayerShowIcon == nil then g.castbarPlayerShowIcon = true end
    if g.castbarTargetShowSpellName == nil then g.castbarTargetShowSpellName = true end
    if g.castbarFocusShowSpellName == nil then g.castbarFocusShowSpellName = true end
    if g.castbarPlayerShowSpellName == nil then g.castbarPlayerShowSpellName = true end
    if g.castbarTargetShowTargetName == nil then g.castbarTargetShowTargetName = false end
    if g.castbarFocusShowTargetName == nil then g.castbarFocusShowTargetName = false end
    if g.showBossCastTargetName == nil then g.showBossCastTargetName = false end
    local function InitCastTargetTextDefaults(prefix)
        if g[prefix .. "TargetNamePosition"] == nil then g[prefix .. "TargetNamePosition"] = "BELOW" end
        if g[prefix .. "TargetNameFontSize"] == nil then g[prefix .. "TargetNameFontSize"] = 10 end
        if g[prefix .. "TargetNameAlign"] == nil then g[prefix .. "TargetNameAlign"] = "RIGHT" end
        if g[prefix .. "TargetNameOffsetX"] == nil then g[prefix .. "TargetNameOffsetX"] = 0 end
        if g[prefix .. "TargetNameOffsetY"] == nil then g[prefix .. "TargetNameOffsetY"] = 1 end
    end
    InitCastTargetTextDefaults("castbarTarget")
    InitCastTargetTextDefaults("castbarFocus")
    InitCastTargetTextDefaults("bossCast")
    if g.castbarTargetTextOffsetX == nil then g.castbarTargetTextOffsetX = 0 end
    if g.castbarTargetTextOffsetY == nil then g.castbarTargetTextOffsetY = 0 end
    if g.castbarFocusTextOffsetX == nil then g.castbarFocusTextOffsetX = 0 end
    if g.castbarFocusTextOffsetY == nil then g.castbarFocusTextOffsetY = 0 end
    if g.castbarPlayerTextOffsetX == nil then g.castbarPlayerTextOffsetX = 0 end
    if g.castbarPlayerTextOffsetY == nil then g.castbarPlayerTextOffsetY = 0 end
    if g.castbarTargetIconOffsetX == nil then g.castbarTargetIconOffsetX = 0 end
    if g.castbarTargetIconOffsetY == nil then g.castbarTargetIconOffsetY = 0 end
    if g.castbarFocusIconOffsetX == nil then g.castbarFocusIconOffsetX = 0 end
    if g.castbarFocusIconOffsetY == nil then g.castbarFocusIconOffsetY = 0 end
    if g.castbarPlayerIconOffsetX == nil then g.castbarPlayerIconOffsetX = 0 end
    if g.castbarPlayerIconOffsetY == nil then g.castbarPlayerIconOffsetY = 0 end
    local function InitCastbarDetailDefaults(prefix)
        if g[prefix .. "IconPosition"] == nil then g[prefix .. "IconPosition"] = "LEFT" end
        if g[prefix .. "IconSpacing"] == nil then g[prefix .. "IconSpacing"] = 1 end
        if g[prefix .. "IconBorderStyle"] == nil then g[prefix .. "IconBorderStyle"] = "NONE" end
        if g[prefix .. "SpellNamePosition"] == nil then g[prefix .. "SpellNamePosition"] = "LEFT" end
        if g[prefix .. "SpellNameFont"] == nil then g[prefix .. "SpellNameFont"] = "GLOBAL" end
        if g[prefix .. "SpellNameOutline"] == nil then g[prefix .. "SpellNameOutline"] = "GLOBAL" end
        if g[prefix .. "SpellNameAlign"] == nil then g[prefix .. "SpellNameAlign"] = "LEFT" end
        if g[prefix .. "SpellNameMaxWidth"] == nil then g[prefix .. "SpellNameMaxWidth"] = 0 end
        if g[prefix .. "SpellNameTruncate"] == nil then g[prefix .. "SpellNameTruncate"] = "AUTO" end
        if g[prefix .. "TimePosition"] == nil then g[prefix .. "TimePosition"] = "RIGHT" end
        if g[prefix .. "TimeFont"] == nil then g[prefix .. "TimeFont"] = "GLOBAL" end
        if g[prefix .. "TimeOutline"] == nil then g[prefix .. "TimeOutline"] = "GLOBAL" end
    end
    InitCastbarDetailDefaults("castbarPlayer")
    InitCastbarDetailDefaults("castbarTarget")
    InitCastbarDetailDefaults("castbarFocus")
    --- Boss castbar UI bits (BossCastbars module reads these from general)
    if g.showBossCastIcon == nil then g.showBossCastIcon = true end
    if g.showBossCastName == nil then g.showBossCastName = true end
    if g.bossPreviewEnabled == nil then g.bossPreviewEnabled = true end
    if g.bossCastIconOffsetX == nil then g.bossCastIconOffsetX = 0 end
    if g.bossCastIconOffsetY == nil then g.bossCastIconOffsetY = 0 end
    if g.bossCastTextOffsetX == nil then g.bossCastTextOffsetX = 0 end
    if g.bossCastTextOffsetY == nil then g.bossCastTextOffsetY = 0 end
    if g.bossCastTimeOffsetX == nil then g.bossCastTimeOffsetX = 0 end
    if g.bossCastTimeOffsetY == nil then g.bossCastTimeOffsetY = 0 end
    InitCastbarDetailDefaults("bossCast")
    --- Focus Kick Icon defaults
    if g.enableFocusKickIcon == nil then g.enableFocusKickIcon = false end
    if g.focusKickIconWidth == nil then g.focusKickIconWidth = 40 end
    if g.focusKickIconHeight == nil then g.focusKickIconHeight = 40 end
    if g.focusKickIconOffsetX == nil then g.focusKickIconOffsetX = 300 end
    if g.focusKickIconOffsetY == nil then g.focusKickIconOffsetY = 0 end
    if g.barTexture == nil then
        g.barTexture = "Solid"
    end
    if g.barBackgroundTexture == nil then
        g.barBackgroundTexture = "Solid"
    end
    --- Prediction opacity defaults. Texture nil/"" remains a valid explicit
    --- request to follow the foreground texture outside the factory profile.
    if g.absorbBarOpacity == nil then g.absorbBarOpacity = 1 end
    if g.healAbsorbBarOpacity == nil then g.healAbsorbBarOpacity = 1 end
    if g.absorbBarTexture ~= nil and type(g.absorbBarTexture) ~= "string" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and type(g.healAbsorbBarTexture) ~= "string" then
        g.healAbsorbBarTexture = nil
    end
    if g.absorbBarTexture == "" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture == "" then
        g.healAbsorbBarTexture = nil
    end
    --- Best-effort validation: if we can confidently resolve a statusbar key and it fails,
    --- fall back to nil ("follow foreground") so users don't get broken textures after removing SharedMedia packs.
    local function _MSUF_IsValidStatusbarKey(key)
        if type(key) ~= "string" or key == "" then  return false end
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
            local tex = _G.MSUF_ResolveStatusbarTextureKey(key)
            if type(tex) == "string" and tex ~= "" then
                 return true
            end
             return false
        end
        local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
        if LSM and type(LSM.Fetch) == "function" then
            local tex = LSM:Fetch("statusbar", key, true)
            if type(tex) == "string" and tex ~= "" then
                 return true
            end
             return false
        end
        --- Can't validate in this session (no resolver/LSM yet): keep the value to avoid unintended resets.
         return true
    end
    if g.absorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.absorbBarTexture) then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.healAbsorbBarTexture) then
        g.healAbsorbBarTexture = nil
    end
    if g.hpTextMode == nil then
        g.hpTextMode = "FULL_PLUS_PERCENT"
    end
    if g.hpTextSeparator == nil then
        g.hpTextSeparator = "-"
    end
    if g.powerTextSeparator == nil then
        g.powerTextSeparator = g.hpTextSeparator
    end
    --- Bar settings scope: always default to Shared so users edit globally first.
    if g.hpPowerTextSelectedKey == nil then
        g.hpPowerTextSelectedKey = "shared"
    end
    --- Legacy portrait baseline. Kept only as a migration source for older profiles;
    --- runtime and Unit Frame options use per-unit portrait fields directly.
    if g.portraitShape == nil then g.portraitShape = "SQUARE" end
    if g.portraitSizeOverride == nil then g.portraitSizeOverride = 0 end
    if g.portraitOffsetX == nil then g.portraitOffsetX = 0 end
    if g.portraitOffsetY == nil then g.portraitOffsetY = 0 end
    if g.portraitZoom == nil then g.portraitZoom = 100 end
    if g.portraitBorderStyle == nil then g.portraitBorderStyle = "NONE" end
    if g.portraitBorderThickness == nil then g.portraitBorderThickness = 2 end
    if g.portraitBorderColorR == nil then g.portraitBorderColorR = 1 end
    if g.portraitBorderColorG == nil then g.portraitBorderColorG = 1 end
    if g.portraitBorderColorB == nil then g.portraitBorderColorB = 1 end
    if g.portraitBorderColorA == nil then g.portraitBorderColorA = 1 end
    if g.portraitBgEnabled == nil then g.portraitBgEnabled = false end
    if g.portraitBgColorR == nil then g.portraitBgColorR = 0.05 end
    if g.portraitBgColorG == nil then g.portraitBgColorG = 0.05 end
    if g.portraitBgColorB == nil then g.portraitBgColorB = 0.05 end
    if g.portraitBgColorA == nil then g.portraitBgColorA = 0.85 end
    if g.portraitClassStyle == nil then g.portraitClassStyle = "BLIZZARD" end
    g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    if g.portraitFillBorder == nil then g.portraitFillBorder = false end
    --- Retired Portrait panel UI state / old shared render value. Kept for imports only.
    if g._portraitScopeKey == nil then g._portraitScopeKey = "shared" end
    --- Initialize _portraitSharedRender from player's actual render type (migration from old layout)
    if g._portraitSharedRender == nil then
        local pConf = MSUF_DB.player
        if pConf and pConf.portraitRender then
            g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(pConf.portraitRender)
        else
            g._portraitSharedRender = "2D"
        end
    else
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    --- Which unit's portrait settings are currently shown in the Portraits menu (UI state only).
    --- Moved from positional tabs to scope dropdown (Bars pattern).

    --- Power text mode: migrate legacy modes to EQoL-style keys.
    local function _MSUF_MigratePowerMode(v)
        if v == nil then return nil end
        if v == "FULL_SLASH_MAX" then return "CURMAX" end
        if v == "FULL_ONLY" then return "CURRENT" end
        if v == "PERCENT_ONLY" then return "PERCENT" end
        if v == "FULL_PLUS_PERCENT" or v == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return v
    end

    g.powerTextMode = _MSUF_MigratePowerMode(g.powerTextMode)
    for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","boss"}) do
        local u = MSUF_DB[unitKey]
        if type(u) == "table" then
            u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode)
        end
    end

    if g.powerTextMode == nil then
        g.powerTextMode = "CURPERCENT"
    end

    --- Unit Frame text is per-unit as of the Unit Frame UX refactor.
    --- Older profiles could inherit HP/Power pattern settings from general.* unless
    --- hpPowerTextOverride was enabled. Flatten that inherited value once so saved
    --- profiles keep their exact look while the new UI edits only the selected unit.
    do
        local function _MSUF_MigrateHpMode(v)
            if v == nil then return nil end
            if v == "FULL_ONLY" then return "CURRENT" end
            if v == "PERCENT_ONLY" then return "PERCENT" end
            if v == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
            if v == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
            return v
        end
        g.hpTextMode = _MSUF_MigrateHpMode(g.hpTextMode) or "CURPERCENT"
        local defaults = {
            hpTextMode = g.hpTextMode or "CURPERCENT",
            textLeft = "NONE",
            textCenter = "NONE",
            textRight = g.hpTextMode or "CURPERCENT",
            hpTextReverse = (g.hpTextReverse == true),
            powerTextMode = g.powerTextMode or "CURPERCENT",
            powerTextLeft = "NONE",
            powerTextCenter = "NONE",
            powerTextRight = g.powerTextMode or "CURPERCENT",
            hpTextLeftOffsetX = 0,
            hpTextLeftOffsetY = 0,
            hpTextCenterOffsetX = 0,
            hpTextCenterOffsetY = 0,
            hpTextRightOffsetX = 0,
            hpTextRightOffsetY = 0,
            powerTextLeftOffsetX = 0,
            powerTextLeftOffsetY = 0,
            powerTextCenterOffsetX = 0,
            powerTextCenterOffsetY = 0,
            powerTextRightOffsetX = 0,
            powerTextRightOffsetY = 0,
            hpTextSeparator = (g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-",
            powerTextSeparator = (g.powerTextSeparator ~= nil) and g.powerTextSeparator or ((g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-"),
            nameTextLayer = tonumber(g.nameTextLayer) or 5,
            hpTextLayer = tonumber(g.hpTextLayer) or tonumber(g.textLayer) or 5,
            powerTextLayer = tonumber(g.powerTextLayer) or 2,
        }
        for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","boss"}) do
            MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
            local u = MSUF_DB[unitKey]
            if type(u) == "table" then
                for field, fallback in pairs(defaults) do
                    if field ~= "textLeft" and field ~= "textCenter" and field ~= "textRight"
                        and field ~= "powerTextLeft" and field ~= "powerTextCenter" and field ~= "powerTextRight"
                        and u[field] == nil
                    then
                        u[field] = fallback
                    end
                end
                u.hpTextMode = _MSUF_MigrateHpMode(u.hpTextMode) or defaults.hpTextMode
                u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode) or defaults.powerTextMode
                if u.textLeft == nil and u.textCenter == nil and u.textRight == nil then
                    u.textLeft = "NONE"
                    u.textCenter = "NONE"
                    u.textRight = u.hpTextMode or defaults.textRight
                else
                    if u.textLeft == nil then u.textLeft = defaults.textLeft end
                    if u.textCenter == nil then u.textCenter = defaults.textCenter end
                    if u.textRight == nil then u.textRight = defaults.textRight end
                end
                if u.powerTextLeft == nil and u.powerTextCenter == nil and u.powerTextRight == nil then
                    u.powerTextLeft = "NONE"
                    u.powerTextCenter = "NONE"
                    u.powerTextRight = u.powerTextMode or defaults.powerTextRight
                else
                    if u.powerTextLeft == nil then u.powerTextLeft = defaults.powerTextLeft end
                    if u.powerTextCenter == nil then u.powerTextCenter = defaults.powerTextCenter end
                    if u.powerTextRight == nil then u.powerTextRight = defaults.powerTextRight end
                end
                u.hpPowerTextOverride = nil
            end
        end
        g._msufUFTextPerUnitMigrated_v4325 = true
    end
    if g.enableAbsorbBar == nil then
        g.enableAbsorbBar = true
    end
    g.showTotalAbsorbAmount = false
    if g.showSelfHealPrediction == nil then
        g.showSelfHealPrediction = true
    end
    if g.healPredAnchorMode == nil then
        g.healPredAnchorMode = 3
    end
    if g.healAbsorbEnabled == nil then
        g.healAbsorbEnabled = true
    end

    --- Absorb display is bar-only in 6.0; collapse legacy text modes on load.
    if g.absorbTextMode == nil then
        g.absorbTextMode = 2
        g.enableAbsorbBar = true
    else
        local mode = tonumber(g.absorbTextMode)
        if mode == 1 or mode == 4 then
            g.absorbTextMode = 1
            g.enableAbsorbBar = false
        else
            g.absorbTextMode = 2
            g.enableAbsorbBar = true
        end
    end
    if g.absorbAnchorMode == nil then
	        --- 1 = Left Absorb, Right Heal-Absorb; 2 = Right Absorb, Left Heal-Absorb; 3 = Follow HP; 5 = Reverse from max (default)
        g.absorbAnchorMode = 5
    end
    if g.overAbsorbOverlay == nil then
        g.overAbsorbOverlay = true
    end

    --- v2 absorb-colour cleanup. Pre-v2 the picker in MSUF_ColorsCore wrote to
    --- absorbColor* / healAbsorbColor*, but every reader (UF, GF, Reset) used
    --- the absorbBarColor* / healAbsorbBarColor* keys - so the picker had no
    --- visible effect. The v1 patch tried to migrate by copying old - new,
    --- which surfaced picker-default white into now-live keys and made
    --- absorbs blend into the HP bar. v2 wipes both key sets once, so the
    --- defaults render again until the user explicitly picks a colour via
    --- the (now functional) picker. The marker keeps this idempotent and
    --- preserves any choices made AFTER the marker is set.
    if g.absorbBarColorMigrationV2 ~= true then
        g.absorbBarColorMigrationV2 = true
        g.absorbColorR,        g.absorbColorG,        g.absorbColorB,        g.absorbColorA        = nil, nil, nil, nil
        g.healAbsorbColorR,    g.healAbsorbColorG,    g.healAbsorbColorB,    g.healAbsorbColorA    = nil, nil, nil, nil
        g.absorbBarColorR,     g.absorbBarColorG,     g.absorbBarColorB,     g.absorbBarColorA     = nil, nil, nil, nil
        g.healAbsorbBarColorR, g.healAbsorbBarColorG, g.healAbsorbBarColorB, g.healAbsorbBarColorA = nil, nil, nil, nil
    end
    if g.showLeaderIcon == nil then
        g.showLeaderIcon = true
    end
    if g.leaderIconStyle == nil then
        g.leaderIconStyle = "BLIZZARD"
    end
    if g.leaderIconOffsetX == nil then
        g.leaderIconOffsetX = 0
    end
    if g.leaderIconOffsetY == nil then
        g.leaderIconOffsetY = 3
    end
    if g.leaderIconLayer == nil then
        g.leaderIconLayer = 7
    end
    --- Level indicator offset (global)
    if g.levelIndicatorOffsetX == nil then
        g.levelIndicatorOffsetX = 0
    end
    if g.levelIndicatorOffsetY == nil then
        g.levelIndicatorOffsetY = 0
    end
    if g.levelIndicatorAnchor == nil then
        g.levelIndicatorAnchor = 'NAMERIGHT'
    end
    if g.levelIndicatorLayer == nil then
        g.levelIndicatorLayer = 7
    end
    if g.showRaidGroupInName == nil then
        g.showRaidGroupInName = false
    end
    if g.raidGroupNameAnchor == nil then
        g.raidGroupNameAnchor = 'NAMERIGHT'
    end
    if g.raidGroupNameOffsetX == nil then
        g.raidGroupNameOffsetX = 3
    end
    if g.raidGroupNameOffsetY == nil then
        g.raidGroupNameOffsetY = 0
    end
    if g.raidGroupNameStyle == nil then
        g.raidGroupNameStyle = 'PAREN'
    end
    --- Misc -> Indicators
    if g.showIncomingResIndicator == nil then
        g.showIncomingResIndicator = true
    end
    if g.incomingResIndicatorPos == nil then
        g.incomingResIndicatorPos = 'TOPRIGHT'
    end
    if g.incomingResIndicatorLayer == nil then
        g.incomingResIndicatorLayer = 7
    end
    if g.showCombatStateIndicator == nil then
        g.showCombatStateIndicator = true
    end
    if g.combatStateIndicatorPos == nil then
        g.combatStateIndicatorPos = 'TOPLEFT'
    end
    if g.combatStateIndicatorLayer == nil then
        g.combatStateIndicatorLayer = 7
    end
    if g.showPvpIndicator == nil then
        g.showPvpIndicator = true
    end
    if g.pvpIndicatorAnchor == nil then
        g.pvpIndicatorAnchor = "TOPRIGHT"
    end
    if g.pvpIndicatorOffsetX == nil then
        g.pvpIndicatorOffsetX = 0
    end
    if g.pvpIndicatorOffsetY == nil then
        g.pvpIndicatorOffsetY = 0
    end
    if g.pvpIndicatorSize == nil then
        g.pvpIndicatorSize = 18
    end
    if g.pvpIndicatorLayer == nil then
        g.pvpIndicatorLayer = 7
    end
    --- Status Icons (Summon / Resting)
    --- These are used by the Unitframe Status element (player/target) and can be overridden per-unit in the Frames menu.
    if g.showRestingIndicator == nil then
        g.showRestingIndicator = true
    end
	--- Rested icon defaults ("Moon Zzzz")
	--- Requirement: default size 30 and anchored TOPLEFT.
	--- Only apply when the profile does not already carry explicit values (no regression for users who moved it).
	if g.restedStateIndicatorSymbol == nil then
		g.restedStateIndicatorSymbol = "rested_moonzzz"
	end
	if g.restedStateIndicatorAnchor == nil then
		g.restedStateIndicatorAnchor = "TOPLEFT"
	end
	if g.restedStateIndicatorOffsetX == nil or type(g.restedStateIndicatorOffsetX) ~= "number" then
		g.restedStateIndicatorOffsetX = 0
	end
	if g.restedStateIndicatorOffsetY == nil or type(g.restedStateIndicatorOffsetY) ~= "number" then
		g.restedStateIndicatorOffsetY = 0
	end
	if g.restedStateIndicatorSize == nil or type(g.restedStateIndicatorSize) ~= "number" or g.restedStateIndicatorSize <= 0 then
		g.restedStateIndicatorSize = 30
	end
    if g.restedStateIndicatorLayer == nil then
        g.restedStateIndicatorLayer = 7
    end
    if g.stateIconsTestMode == nil then
        g.stateIconsTestMode = false
    end
    --- Player indicators (Frames -> Player)
    if g.showLevel == nil then
        g.showLevel = true
    end
    if g.showRaidMarker == nil then
        g.showRaidMarker = true
    end
    local legacyShowRaidMarker = g.showRaidMarker
    for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet","boss"}) do
        MSUF_DB[key] = MSUF_DB[key] or {}
        if MSUF_DB[key].showRaidMarker == nil and legacyShowRaidMarker ~= nil then
            MSUF_DB[key].showRaidMarker = legacyShowRaidMarker
        end
        if MSUF_DB[key].showRaidMarker == nil then
            MSUF_DB[key].showRaidMarker = true
        end
end
local legacyRaidMarkerOffsetX = g.raidMarkerOffsetX
local legacyRaidMarkerOffsetY = g.raidMarkerOffsetY
local legacyRaidMarkerAnchor  = g.raidMarkerAnchor
local legacyRaidMarkerSize    = g.raidMarkerSize
for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet","boss"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]
    if conf.raidMarkerOffsetX == nil and legacyRaidMarkerOffsetX ~= nil then
        conf.raidMarkerOffsetX = legacyRaidMarkerOffsetX
    end
    if conf.raidMarkerOffsetY == nil and legacyRaidMarkerOffsetY ~= nil then
        conf.raidMarkerOffsetY = legacyRaidMarkerOffsetY
    end
    if conf.raidMarkerAnchor == nil and legacyRaidMarkerAnchor ~= nil then
        conf.raidMarkerAnchor = legacyRaidMarkerAnchor
    end
    if conf.raidMarkerSize == nil and legacyRaidMarkerSize ~= nil then
        conf.raidMarkerSize = legacyRaidMarkerSize
    end
    if conf.raidMarkerOffsetX == nil then
        if key == "player" then
            conf.raidMarkerOffsetX = 21
        elseif key == "target" then
            conf.raidMarkerOffsetX = -15
        else
            conf.raidMarkerOffsetX = 16
        end
    end
    if conf.raidMarkerOffsetY == nil then conf.raidMarkerOffsetY = 3 end
    if conf.raidMarkerAnchor == nil then
        if key == "target" then
            conf.raidMarkerAnchor = "TOPRIGHT"
        else
            conf.raidMarkerAnchor = "TOPLEFT"
        end
    end
    if conf.raidMarkerSize == nil then conf.raidMarkerSize = 14 end
    if conf.raidMarkerLayer == nil then conf.raidMarkerLayer = 7 end
end
--- PvP flag defaults (per-unit)
for _, key in ipairs({"player","target","focus","targettarget","focustarget"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]
    if conf.showPvpIndicator == nil then conf.showPvpIndicator = true end
    if conf.pvpIndicatorSize == nil then conf.pvpIndicatorSize = 18 end
    if conf.pvpIndicatorAnchor == nil then conf.pvpIndicatorAnchor = "TOPRIGHT" end
    if conf.pvpIndicatorOffsetX == nil then conf.pvpIndicatorOffsetX = 0 end
    if conf.pvpIndicatorOffsetY == nil then conf.pvpIndicatorOffsetY = 0 end
    if conf.pvpIndicatorLayer == nil then conf.pvpIndicatorLayer = 7 end
end
--- Elite / Rare icon defaults (per-unit)
for _, key in ipairs({"target","focus","targettarget","focustarget","boss"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local u = MSUF_DB[key]
    if u.showEliteIcon    == nil then u.showEliteIcon    = true       end
    if u.eliteIconSize    == nil then u.eliteIconSize    = 20         end
    if u.eliteIconAnchor  == nil then u.eliteIconAnchor  = "TOPRIGHT" end
    if u.eliteIconOffsetX == nil then u.eliteIconOffsetX = 2          end
    if u.eliteIconOffsetY == nil then u.eliteIconOffsetY = 2          end
    if u.eliteIconLayer   == nil then u.eliteIconLayer   = 7          end
end
if MSUF_DB.bars == nil then
        MSUF_DB.bars = {}
    end
    if MSUF_DB.bars.showTargetPowerBar == nil then
        MSUF_DB.bars.showTargetPowerBar = true
    end
        if MSUF_DB.bars.showBossPowerBar == nil then
        MSUF_DB.bars.showBossPowerBar = true
    end
    if MSUF_DB.bars.showFocusPowerBar == nil then
        MSUF_DB.bars.showFocusPowerBar = true
    end
    if MSUF_DB.bars.showPlayerPowerBar == nil then
        MSUF_DB.bars.showPlayerPowerBar = true
    end
    if MSUF_DB.bars.showBarBorder == nil then
        MSUF_DB.bars.showBarBorder = true
    end
    if MSUF_DB.bars.powerBarHeight == nil then
        MSUF_DB.bars.powerBarHeight = 3
    end
    if MSUF_DB.bars.smoothPowerBar == nil then
        MSUF_DB.bars.smoothPowerBar = true
    end
    if MSUF_DB.bars.classPowerSmoothFill == nil then
        MSUF_DB.bars.classPowerSmoothFill = MSUF_DB.bars.smoothPowerBar ~= false
    end
    if MSUF_DB.bars.altManaSmoothFill == nil then
        MSUF_DB.bars.altManaSmoothFill = MSUF_DB.bars.smoothPowerBar ~= false
    end
    if MSUF_DB.bars.classPowerComboPointColorMode == nil then
        MSUF_DB.bars.classPowerComboPointColorMode = "default"
    end
    if MSUF_DB.bars.classPowerShape == nil then
        MSUF_DB.bars.classPowerShape = "BAR"
    end
    if MSUF_DB.bars.classPowerShapeAlign == nil then
        MSUF_DB.bars.classPowerShapeAlign = "CENTER"
    end
    if MSUF_DB.bars.detachedPowerBarTexture == nil then
        MSUF_DB.bars.detachedPowerBarTexture = ""
    end
    if MSUF_DB.bars.detachedPowerBarBgTexture == nil then
        MSUF_DB.bars.detachedPowerBarBgTexture = ""
    end
    if MSUF_DB.bars.detachedPowerBarOutline == nil then
        MSUF_DB.bars.detachedPowerBarOutline = 1
    end
    if MSUF_DB.bars.playerHPBarEnabled == nil then
        MSUF_DB.bars.playerHPBarEnabled = false
    end
    if MSUF_DB.bars.playerHPBarAnchor == nil then
        MSUF_DB.bars.playerHPBarAnchor = "CLASS_TOP"
    end
    if MSUF_DB.bars.playerHPBarWidthMode == nil then
        MSUF_DB.bars.playerHPBarWidthMode = "class"
    end
    if MSUF_DB.bars.playerHPBarWidth == nil then
        MSUF_DB.bars.playerHPBarWidth = 0
    end
    if MSUF_DB.bars.playerHPBarHeight == nil then
        MSUF_DB.bars.playerHPBarHeight = 6
    end
    if MSUF_DB.bars.playerHPBarGap == nil then
        MSUF_DB.bars.playerHPBarGap = 2
    end
    if MSUF_DB.bars.playerHPBarOffsetX == nil then
        MSUF_DB.bars.playerHPBarOffsetX = 0
    end
    if MSUF_DB.bars.playerHPBarOffsetY == nil then
        MSUF_DB.bars.playerHPBarOffsetY = 0
    end
    if MSUF_DB.bars.playerHPBarFrameLevelOffset == nil then
        MSUF_DB.bars.playerHPBarFrameLevelOffset = 7
    end
    if MSUF_DB.bars.playerHPBarShape == nil then
        MSUF_DB.bars.playerHPBarShape = "BAR"
    end
    if MSUF_DB.bars.playerHPBarOrbSize == nil then
        MSUF_DB.bars.playerHPBarOrbSize = 54
    end
    if MSUF_DB.bars.playerHPBarTexture == nil then
        MSUF_DB.bars.playerHPBarTexture = ""
    end
    if MSUF_DB.bars.playerHPBarBgTexture == nil then
        MSUF_DB.bars.playerHPBarBgTexture = ""
    end
    if MSUF_DB.bars.playerHPBarBgAlpha == nil then
        MSUF_DB.bars.playerHPBarBgAlpha = 0.35
    end
    if MSUF_DB.bars.playerHPBarOutline == nil then
        MSUF_DB.bars.playerHPBarOutline = 1
    end
    if MSUF_DB.bars.playerHPBarColorMode == nil then
        MSUF_DB.bars.playerHPBarColorMode = "GLOBAL"
    end
    if MSUF_DB.bars.playerHPBarSmoothFill == nil then
        MSUF_DB.bars.playerHPBarSmoothFill = false
    end
    if MSUF_DB.bars.playerHPBarTextEnabled == nil then
        MSUF_DB.bars.playerHPBarTextEnabled = true
    end
    if MSUF_DB.bars.playerHPBarUsePlayerText == nil then
        MSUF_DB.bars.playerHPBarUsePlayerText = true
    end
    if MSUF_DB.bars.playerHPBarTextLeft == nil then
        MSUF_DB.bars.playerHPBarTextLeft = "NONE"
    end
    if MSUF_DB.bars.playerHPBarTextCenter == nil then
        MSUF_DB.bars.playerHPBarTextCenter = "NONE"
    end
    if MSUF_DB.bars.playerHPBarTextRight == nil then
        MSUF_DB.bars.playerHPBarTextRight = "CURPERCENT"
    end
    if MSUF_DB.bars.playerHPBarTextSeparator == nil then
        MSUF_DB.bars.playerHPBarTextSeparator = ""
    end
    if MSUF_DB.bars.playerHPBarTextReverse == nil then
        MSUF_DB.bars.playerHPBarTextReverse = false
    end
    if MSUF_DB.bars.playerHPBarTextSize == nil then
        MSUF_DB.bars.playerHPBarTextSize = 14
    end
    if MSUF_DB.bars.playerHPBarTextOffsetX == nil then
        MSUF_DB.bars.playerHPBarTextOffsetX = 0
    end
    if MSUF_DB.bars.playerHPBarTextOffsetY == nil then
        MSUF_DB.bars.playerHPBarTextOffsetY = 0
    end
    if MSUF_DB.bars.realtimePowerText == nil then
        MSUF_DB.bars.realtimePowerText = true
    end
    if MSUF_DB.bars.roundedFramesEnabled == nil then
        MSUF_DB.bars.roundedFramesEnabled = false
    end
    if MSUF_DB.bars.roundedUnitFrames == nil then
        MSUF_DB.bars.roundedUnitFrames = true
    end
    if MSUF_DB.bars.roundedGroupFrames == nil then
        MSUF_DB.bars.roundedGroupFrames = true
    end
    if MSUF_DB.bars.roundedPowerBars == nil then
        MSUF_DB.bars.roundedPowerBars = true
    end
    if MSUF_DB.bars.roundedMouseover == nil then
        MSUF_DB.bars.roundedMouseover = true
    end
    if MSUF_DB.bars.embedPowerBarIntoHealth == nil then
        --- Pixel-perfect default: keep the power bar *inside* the unitframe bounds.
        --- This prevents the power bar from extending below the frame and breaking
        --- pixel-accurate layouts when toggling power bars on.
        --- Users who want the legacy behavior can disable this in Bars.
        MSUF_DB.bars.embedPowerBarIntoHealth = true
    end
if MSUF_DB.bars.barOutlineThickness == nil then
    --- New slider-based bar outline. Backwards compatible default:
    --- - If legacy border is off -> 0
    --- - Else map legacy style to a sensible thickness
    local enabled = true
    if MSUF_DB.general and MSUF_DB.general.useBarBorder == false then
        enabled = false
    end
    if MSUF_DB.bars.showBarBorder ~= nil then
        enabled = (MSUF_DB.bars.showBarBorder ~= false)
    end
    if not enabled then
        MSUF_DB.bars.barOutlineThickness = 0
    else
        local style = (MSUF_DB.general and MSUF_DB.general.barBorderStyle) or "THIN"
        local map = { THIN = 2, THICK = 3, SHADOW = 4, GLOW = 4 }
        MSUF_DB.bars.barOutlineThickness = map[style] or 2
    end
end
--- Bar background alpha (0..100). Independent from unit alpha in/out of combat.
if MSUF_DB.bars.barBackgroundAlpha == nil then
    MSUF_DB.bars.barBackgroundAlpha = 90
end
    --- Gameplay defaults (module-safe: some modules expect MSUF_DB.gameplay to exist)
    if MSUF_DB.gameplay == nil then
        MSUF_DB.gameplay = {}
    end
    local gp = MSUF_DB.gameplay
    if gp.enableCombatTimer == nil then gp.enableCombatTimer = false end
    if gp.lockCombatTimer == nil then gp.lockCombatTimer = false end
    if gp.combatFontSize == nil then gp.combatFontSize = 24 end
    if gp.combatOffsetX == nil then gp.combatOffsetX = 0 end
    if gp.combatOffsetY == nil then gp.combatOffsetY = -200 end
    if gp.enableCombatStateText == nil then gp.enableCombatStateText = false end
    if gp.lockCombatState == nil then gp.lockCombatState = false end
    if gp.combatStateFontSize == nil then gp.combatStateFontSize = 24 end
    if gp.combatStateOffsetX == nil then gp.combatStateOffsetX = 0 end
    if gp.combatStateOffsetY == nil then gp.combatStateOffsetY = 80 end
    if gp.combatStateDuration == nil then gp.combatStateDuration = 1.5 end
    if gp.enableCombatCrosshair == nil then gp.enableCombatCrosshair = false end
    if gp.enableCombatCrosshairMeleeRangeColor == nil then gp.enableCombatCrosshairMeleeRangeColor = false end
    if gp.crosshairSize == nil then gp.crosshairSize = 40 end
    if gp.crosshairThickness == nil then gp.crosshairThickness = 2 end
    if gp.cooldownIcons == nil then gp.cooldownIcons = false end
    if gp.nameplateMeleeSpellID == nil then gp.nameplateMeleeSpellID = 0 end
    --- Unitframe range-fade defaults are assigned with the unitframe defaults below.
--- Gameplay: Crosshair melee range spell can optionally be stored per class.
    --- This lets users run a single profile across multiple characters without
    --- having to swap the spell whenever they change class.
    if gp.meleeSpellPerClass == nil then gp.meleeSpellPerClass = false end
    if gp.meleeSpellPerSpec == nil then gp.meleeSpellPerSpec = false end
    if gp.nameplateMeleeSpellIDByClass == nil then gp.nameplateMeleeSpellIDByClass = {} end
    if gp.nameplateMeleeSpellIDBySpec == nil then gp.nameplateMeleeSpellIDBySpec = {} end
    --- 5.6 -> 6.0 shape repair for existing DBs and factory defaults.
    MSUF_Defaults_NormalizeProfileTo60Defaults(MSUF_DB)
--- Root toggle: Shorten unit names (Frames -> General)
if MSUF_DB.shortenNames == nil then
    MSUF_DB.shortenNames = false
end
--- Auras3 defaults (new installs / reset profile)
    if MSUF_DB.auras3 == nil then
        MSUF_DB.auras3 = {
            enabled = true,
            showTarget = true,
            showFocus = true,
            showBoss = true,
            bossHealAuras = {
                highlightOwn = false,
                hideOthers = false,
            },
            customDisplays = {
                serial = 0,
                shared = { items = {} },
                perUnit = {},
            },
            customContainers = {
                perUnit = {},
            },
            shared = {
                _msufA3_migrated_v11f = true,
                bossEditTogether = true,
                buffGroupOffsetX = 0,
                buffGroupOffsetY = 36,
                debuffGroupOffsetX = 0,
                debuffGroupOffsetY = 6,
                buffGroupIconSize = 26,
                debuffGroupIconSize = 26,
                cooldownTextSize = 14,
                iconSize = 26,
                spacing = 2,
                stackTextSize = 14,
                growth = "RIGHT",
                buffGrowthX = "RIGHT",
                buffGrowthY = "DOWN",
                debuffGrowthX = "RIGHT",
                debuffGrowthY = "DOWN",
                layoutMode = "SEPARATE",
                perRow = 12,
                maxIcons = 12,
                maxBuffs = 12,
                maxDebuffs = 12,
                showBuffs = true,
                showDebuffs = true,
                showCooldownText = true,
                showCooldownSwipe = true,
                cooldownSwipeReverse = false,
                buffSortMethod = "DEFAULT",
                buffSortReverse = false,
                debuffSortMethod = "DEFAULT",
                debuffSortReverse = false,
                showDurationBar = false,
                durationBarHeight = 2,
                durationBarDisplay = "BAR_ONLY",
                durationBarPosition = "BOTTOM",
                durationBarDirection = "REMAINING",
                showStackCount = true,
                debuffTypeBorderMode = "OFF",
                useDebuffTypeBorders = false,
                showTooltip = true,
                showInEditMode = true,
                stackCountAnchor = "TOPRIGHT",
                stackTextOffsetX = -1,
                stackTextOffsetY = 1,
                cooldownTextAnchor = "CENTER",
                cooldownTextOffsetX = 0,
                cooldownTextOffsetY = 0,
                cooldownDecimalSeconds = 3,
                buffAnchor = "BOTTOMRIGHT",
                debuffAnchor = "TOPLEFT",
                buffLayer = 5,
                debuffLayer = 6,
                hidePermanent = false,
                onlyMyBuffs = false,
                onlyMyDebuffs = false,
                masqueEnabled = false,
                pandemicMode = "OFF",
                pandemicR = 0.0, pandemicG = 0.4, pandemicB = 1.0,
highlightOwnBuffs = false,
                highlightOwnDebuffs = false,
filters = {
                    _msufA3_sharedFiltersMigrated_v1 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    onlyImportantAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        includeNameplateOnly = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        includeNameplateOnly = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                },
            },
            perUnit = {
                target = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        buffGroupOffsetX = -3,
                        buffGroupOffsetY = 0,
                        debuffGroupOffsetX = 230,
                        debuffGroupOffsetY = 2,
                        buffGroupIconSize = 34,
                        debuffGroupIconSize = 34,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    overrideSharedLayout = true,
                    layoutShared = {
                        maxBuffs = 4,
                        maxDebuffs = 3,
                        perRow = 8,
                        rowWrap = "UP",
                        buffGrowthX = "RIGHT",
                        buffGrowthY = "UP",
                        debuffGrowthX = "UP",
                        debuffGrowthY = "UP",
                    },
                    filters = {
                        _msufA3_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        onlyImportantAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            includeNameplateOnly = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            includeNameplateOnly = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                    },
                },
                focus = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        buffGroupOffsetX = -1,
                        buffGroupOffsetY = 0,
                        debuffGroupOffsetX = 125,
                        debuffGroupOffsetY = 1,
                        buffGroupIconSize = 30,
                        debuffGroupIconSize = 26,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    filters = {
                        _msufA3_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        onlyImportantAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            includeNameplateOnly = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            includeNameplateOnly = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                    },
                },
            },
        }
        --- Boss per-unit defaults (1-5)
        for i = 1, 5 do
            local key = "boss" .. i
            MSUF_DB.auras3.perUnit[key] = {
                overrideLayout = true,
                overrideFilters = false,
                layout = {
                    cooldownTextSize = 14,
                    iconSize = 26,
                    buffGroupOffsetX = -1,
                    buffGroupOffsetY = -3,
                    debuffGroupOffsetX = 234,
                    debuffGroupOffsetY = -45,
                    buffGroupIconSize = 40,
                    debuffGroupIconSize = 26,
                    spacing = 2,
                    stackTextSize = 14,
                },
                filters = {
                    _msufA3_filtersMigrated_v2 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    onlyImportantAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        includeNameplateOnly = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        includeNameplateOnly = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                },
            }
        end
    end
    --- Auras3: keep legacy Important filter keys inert for existing profiles.
    --- 12.1 native AuraContainers do not expose an IMPORTANT filter token.
    if MSUF_DB and MSUF_DB.auras3 then
        local a3 = MSUF_DB.auras3
        if type(a3.customDisplays) ~= "table" then a3.customDisplays = {} end
        if type(a3.customDisplays.shared) ~= "table" then a3.customDisplays.shared = { items = {} } end
        if type(a3.customDisplays.shared.items) ~= "table" then a3.customDisplays.shared.items = {} end
        if type(a3.customDisplays.perUnit) ~= "table" then a3.customDisplays.perUnit = {} end
        if type(a3.customDisplays.serial) ~= "number" then a3.customDisplays.serial = 0 end
        if type(a3.customContainers) ~= "table" then a3.customContainers = {} end
        if type(a3.customContainers.perUnit) ~= "table" then a3.customContainers.perUnit = {} end
        if type(a3.bossHealAuras) ~= "table" then a3.bossHealAuras = {} end
        if a3.bossHealAuras.highlightOwn == nil then a3.bossHealAuras.highlightOwn = false end
        if a3.bossHealAuras.hideOthers == nil then a3.bossHealAuras.hideOthers = false end
        if type(a3.shared) == "table" and a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
            if a3.shared.useDebuffTypeBorders == true then
                a3.shared.debuffTypeBorderMode = "SYMBOL"
            elseif a3.shared.debuffTypeBorderMode == nil then
                a3.shared.debuffTypeBorderMode = "OFF"
            end
            a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
        end

        local function EnsureImportantSplit(f)
            if not f then return end
            f.buffs = (type(f.buffs) == "table") and f.buffs or {}
            f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
            local b, d = f.buffs, f.debuffs

            --- One-time migration: legacy onlyImportantAuras is retired.
            if f._msufA3_onlyImportantSplitMigrated_v1 ~= true then
                f.onlyImportantAuras = false
                f._msufA3_onlyImportantSplitMigrated_v1 = true
            end

            f.onlyImportantAuras = false
            b.onlyImportant = false
            d.onlyImportant = false
        end

        if a3.shared and a3.shared.filters then
            EnsureImportantSplit(a3.shared.filters)
        end
        if a3.perUnit then
            for _, pu in pairs(a3.perUnit) do
                if pu and pu.filters then
                    EnsureImportantSplit(pu.filters)
                end
            end
        end
    end

--- Legacy/unit defaults live in the long fill() section below. The helper only
--- fills nil fields, so saved user choices survive even when new defaults are
--- added for later versions.
local function fill(key, defaults)
        MSUF_DB[key] = MSUF_DB[key] or {}
        local t = MSUF_DB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
    end
    local textDefaults = {
        nameTextAnchor = "LEFT",
        nameOffsetX   = 7,
        nameOffsetY   = -4,
        hpOffsetX     = -2,
        hpOffsetY     = -18,
        powerOffsetX  = -2,
        powerOffsetY  = -2,
        textLeft      = "NONE",
        textCenter    = "NONE",
        textRight     = "CURPERCENT",
        hpTextMode    = "CURPERCENT",
        healthTextDecimals = false,
        hpTextLeftOffsetX = 0,
        hpTextLeftOffsetY = 0,
        hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0,
        hpTextRightOffsetX = 0,
        hpTextRightOffsetY = 0,
        powerTextLeft   = "NONE",
        powerTextCenter = "NONE",
        powerTextRight  = "CURPERCENT",
        powerTextLeftOffsetX = 0,
        powerTextLeftOffsetY = 0,
        powerTextCenterOffsetX = 0,
        powerTextCenterOffsetY = 0,
        powerTextRightOffsetX = 0,
        powerTextRightOffsetY = 0,
        nameTextLayer = 5,
        hpTextLayer = 5,
        powerTextLayer = 2,
        showRaidGroupInName = false,
        raidGroupNameAnchor = "NAMERIGHT",
        raidGroupNameOffsetX = 3,
        raidGroupNameOffsetY = 0,
        raidGroupNameStyle = "PAREN",
    }
    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -256,
        offsetY   = -180,
        portraitMode = "LEFT",
        portraitClassStyle = "BLIZZARD",
        showName  = false,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        --- (false = normal left->right fill)
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.player[k] == nil then MSUF_DB.player[k] = v end
    end
    --- Player castbar: custom channel tick markers (PLAYER ONLY)
    --- Stored under MSUF_DB.player.castbar.* so it does not touch general castbar settings.
    MSUF_DB.player.castbar = MSUF_DB.player.castbar or {}
    do
        local pc = MSUF_DB.player.castbar
        if pc.channelTickUseCustom == nil then pc.channelTickUseCustom = false end
        if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
        -- Retired preview-only keys are intentionally neither seeded nor
        -- cleared: fresh profiles stay clean and existing profiles remain
        -- losslessly compatible with older builds and exports.
        if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
    end
    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 320,
        offsetY   = -180,
        portraitMode = "RIGHT",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.target[k] == nil then MSUF_DB.target[k] = v end
    end
    fill("focus", {
        width     = 180,
        height    = 30,
        offsetX   = -260,
        offsetY   = -300,
        portraitMode = "OFF",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showInterrupt = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Focus-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focus[k] == nil then MSUF_DB.focus[k] = v end
    end
    fill("targettarget", {
        width     = 180,
        height    = 30,
        offsetX   = 220,
        offsetY   = -300,
        showName  = false,
        showLevelIndicator = true,
        showHP    = true,
        showPower = false,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    if MSUF_DB.targettarget.showToTInTargetName == nil then MSUF_DB.targettarget.showToTInTargetName = false end
    --- Target-of-Target inline-in-Target separator token (rendered with spaces around it).
    --- Keep the default as the legacy behavior (" | ") by storing the token "|".
    if MSUF_DB.targettarget.totInlineSeparator == nil then MSUF_DB.targettarget.totInlineSeparator = "|" end
    if MSUF_DB.targettarget.totInlineCustomSeparator == nil then MSUF_DB.targettarget.totInlineCustomSeparator = "" end
    if MSUF_DB.targettarget.totInlineColorMode == nil then MSUF_DB.targettarget.totInlineColorMode = "AUTO" end
    for k, v in pairs(textDefaults) do
        if MSUF_DB.targettarget[k] == nil then MSUF_DB.targettarget[k] = v end
    end
    fill("focustarget", {
        enabled   = false,
        width     = 180,
        height    = 30,
        offsetX   = 260,
        offsetY   = 180,
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = false,
        --- Focus Target is a lightweight child-style frame: no castbar or auras.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focustarget[k] == nil then MSUF_DB.focustarget[k] = v end
    end
    fill("pet", {
        width     = 220,
        height    = 30,
        offsetX   = -275,
        offsetY   = -250,
        --- Pet-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.pet[k] == nil then MSUF_DB.pet[k] = v end
    end
    fill("boss", {
        width        = 180,
        height       = 30,
        offsetX      = MSUF_DEFAULT_BOSS_OFFSET_X,
        offsetY      = MSUF_DEFAULT_BOSS_OFFSET_Y,
        spacing      = -96,
        --- Layout mode: "VERTICAL_DOWN" | "VERTICAL_UP" | "HORIZONTAL_RIGHT" | "HORIZONTAL_LEFT"
        --- Kept invertBossOrder for one-shot migration (see below).
        bossLayoutMode = "VERTICAL_DOWN",
        invertBossOrder = false,
        showName     = true,
        showLevelIndicator = false,
        showHP       = true,
        showPower    = false,
        showInterrupt = true,
        portraitMode = "OFF",
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.boss[k] == nil then MSUF_DB.boss[k] = v end
    end
    --- One-shot migration: old invertBossOrder checkbox - new bossLayoutMode dropdown.
    --- Runs once on first login with v4.0 Beta 5+; converts legacy saved setting.
    if MSUF_DB.boss._bossLayoutMigrated ~= true then
        if MSUF_DB.boss.invertBossOrder == true then
            MSUF_DB.boss.bossLayoutMode = "VERTICAL_UP"
        end
        MSUF_DB.boss._bossLayoutMigrated = true
    end
    --- Range fade: also fade castbar / auras when boss is out of range (off by default).
    if MSUF_DB.boss.rangeFadeCastbar == nil then MSUF_DB.boss.rangeFadeCastbar = false end
    if MSUF_DB.boss.rangeFadeAuras   == nil then MSUF_DB.boss.rangeFadeAuras   = false end
    if MSUF_DB.general.rangeFadeEnabled == nil then MSUF_DB.general.rangeFadeEnabled = true end
    for _, unitKey in ipairs({ "target", "targettarget", "focustarget", "focus", "pet", "boss" }) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        if MSUF_DB[unitKey].rangeFadeEnabled == nil then MSUF_DB[unitKey].rangeFadeEnabled = true end
        if MSUF_DB[unitKey].rangeFadeAlpha == nil then MSUF_DB[unitKey].rangeFadeAlpha = 0.4 end
        if MSUF_DB[unitKey].rangeFadeLayerMode == nil then MSUF_DB[unitKey].rangeFadeLayerMode = "frame" end
    end
    do
        local bars = MSUF_DB.bars or {}
        local showKeys = {
            player = "showPlayerPowerBar",
            target = "showTargetPowerBar",
            focus  = "showFocusPowerBar",
            boss   = "showBossPowerBar",
        }
        for _, unitKey in ipairs({"player", "target", "focus", "targettarget", "focustarget", "pet", "boss"}) do
            MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
            local u = MSUF_DB[unitKey]
            local legacyShowKey = showKeys[unitKey]
            if u.showPowerBar == nil then
                local legacyShow = legacyShowKey and bars[legacyShowKey]
                if legacyShow ~= nil then
                    u.showPowerBar = legacyShow ~= false
                else
                    u.showPowerBar = u.showPower ~= false
                end
            end
            if u.powerBarHeight == nil then
                u.powerBarHeight = tonumber(bars.powerBarHeight) or 3
            end
            if u.embedPowerBarIntoHealth == nil then
                u.embedPowerBarIntoHealth = (bars.embedPowerBarIntoHealth == true)
            end
            if u.powerBarBorderEnabled == nil then
                u.powerBarBorderEnabled = (bars.powerBarBorderEnabled == true)
            end
            if u.powerBarBorderThickness == nil then
                u.powerBarBorderThickness = tonumber(bars.powerBarBorderThickness or bars.powerBarBorderSize) or 1
            end
            if u.powerSmoothFill == nil then
                u.powerSmoothFill = (unitKey == "player") and (bars.smoothPowerBar ~= false) or false
            end
            if unitKey == "player" then
                local legacyShape = tostring(u.detachedPowerBarShape or "FOLLOW_CLASS"):upper()
                if legacyShape == "FOLLOW_CLASS" then
                    local classShape = tostring(bars.classPowerShape or "BAR"):upper()
                    if classShape == "CIRCLE" then
                        u.detachedPowerBarShape = "ROUND"
                    elseif classShape == "DIAMOND" or classShape == "HEX" then
                        u.detachedPowerBarShape = "CRYSTAL"
                    else
                        u.detachedPowerBarShape = "BAR"
                    end
                elseif u.detachedPowerBarShape == nil then
                    u.detachedPowerBarShape = "BAR"
                end
                u.detachedPowerBarSeparateShape = nil
            end
            if unitKey == "player" and u.detachedPowerOrbSize == nil then
                u.detachedPowerOrbSize = 54
            end
            if u.powerBarDetached == true and u.detachedPowerBarWidth == nil then
                local syncedClassWidth = unitKey == "player"
                    and u.detachedPowerBarSyncClassPower ~= false
                    and bars.classPowerWidthMode == "custom"
                    and tonumber(bars.classPowerWidth)
                    or nil
                local detachedWidth = (syncedClassWidth and syncedClassWidth >= 20 and syncedClassWidth)
                    or tonumber(u.width)
                    or (unitKey == "focus" and 180 or 275)
                if detachedWidth < 20 then
                    detachedWidth = 20
                elseif detachedWidth > 800 then
                    detachedWidth = 800
                end
                u.detachedPowerBarWidth = detachedWidth
            end
        end
    end
    for _, unitKey in ipairs({"player", "target", "targettarget", "focustarget", "focus", "pet", "boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local u = MSUF_DB[unitKey]
        if u.enabled == nil then
            u.enabled = true
        end
        --- Per-unitframe: smooth health fill animation (matches Group Frames default).
        if u.smoothFill == nil then
            u.smoothFill = true
        end
        --- Unified alpha: HP fill opacity + power fill opacity + background texture
        --- opacity + a toggle to keep text/portrait opaque. Legacy combat/layered keys
        --- are wiped once by the _msufAlphaUnified_v1 migration below.
        if u.hpBarAlpha == nil then u.hpBarAlpha = 1 end
        if u.powerBarAlpha == nil then u.powerBarAlpha = 1 end
        if u.hpBgAlpha == nil then u.hpBgAlpha = 0.85 end
        if u.powerBarBgAlpha == nil then u.powerBarBgAlpha = u.hpBgAlpha or 0.85 end
        if u.alphaExcludeTextPortrait == nil then u.alphaExcludeTextPortrait = false end
        --- Portrait defaults used by the clean UF Portrait element.
        --- v4.324+: portraits are always per-unit. Older shared/override profiles
        --- are flattened once: override=true keeps unit values, non-overrides adopt
        --- the old baseline, then the override marker is retired.
        local flattenLegacyPortrait = legacyPortraitOverrideState and g._msufPortraitPerUnitMigrated_v4324 ~= true
        local useLegacyBaseline = flattenLegacyPortrait and u.portraitDecoOverride ~= true
        local function PortraitDefault(field, fallback)
            local shared = g[field]
            if shared == nil then shared = fallback end
            if useLegacyBaseline then
                u[field] = shared
            elseif u[field] == nil then
                u[field] = shared
            end
        end
        if useLegacyBaseline then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender or g.portraitRender)
        elseif u.portraitRender == nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
        else
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        PortraitDefault("portraitClassStyle", "BLIZZARD")
        u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        PortraitDefault("portraitShape", "SQUARE")
        PortraitDefault("portraitSizeOverride", 0)
        PortraitDefault("portraitOffsetX", 0)
        PortraitDefault("portraitOffsetY", 0)
        PortraitDefault("portraitZoom", 100)
        PortraitDefault("portraitBorderStyle", "NONE")
        PortraitDefault("portraitBorderThickness", 2)
        PortraitDefault("portraitBorderColorR", 1)
        PortraitDefault("portraitBorderColorG", 1)
        PortraitDefault("portraitBorderColorB", 1)
        PortraitDefault("portraitBorderColorA", 1)
        PortraitDefault("portraitBgEnabled", false)
        PortraitDefault("portraitBgColorR", 0.05)
        PortraitDefault("portraitBgColorG", 0.05)
        PortraitDefault("portraitBgColorB", 0.05)
        PortraitDefault("portraitBgColorA", 0.85)
        PortraitDefault("portraitFillBorder", false)
        u.portraitDecoOverride = nil
    end
    g._msufPortraitPerUnitMigrated_v4324 = true
    --- Unified alpha migration (hard reset): the old combat/layered alpha model was
    --- replaced by hpBarAlpha (HP fill) + powerBarAlpha (power fill) + hpBgAlpha
    --- (health background) + powerBarBgAlpha (resource background) +
    --- alphaExcludeTextPortrait.
    --- Wipe every retired key once across all unit and group confs and seed the new
    --- defaults. dead/offline tint (deadBg*) and background RGB (bgR/bgG/bgB) are kept.
    if g._msufAlphaUnified_v1 ~= true then
        local RETIRED_ALPHA_KEYS = {
            "alphaInCombat", "alphaOutOfCombat", "alphaSync", "alphaSyncBoth",
            "alphaLayerMode", "alphaFGInCombat", "alphaFGOutOfCombat",
            "alphaBGInCombat", "alphaBGOutOfCombat", "alphaHPInCombat",
            "alphaHPOutOfCombat", "alphaPreserveHPColor", "bgA", "hpTextIgnoreAlpha",
        }
        for _, key in ipairs({
            "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
            "gf_party", "gf_raid", "gf_mythicraid",
        }) do
            local conf = MSUF_DB[key]
            if type(conf) == "table" then
                for i = 1, #RETIRED_ALPHA_KEYS do
                    conf[RETIRED_ALPHA_KEYS[i]] = nil
                end
                if conf.hpBarAlpha == nil then conf.hpBarAlpha = 1 end
                if conf.powerBarAlpha == nil then conf.powerBarAlpha = 1 end
                if conf.hpBgAlpha == nil then conf.hpBgAlpha = 0.85 end
                if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
                if conf.alphaExcludeTextPortrait == nil then conf.alphaExcludeTextPortrait = false end
            end
        end
        g._msufAlphaUnified_v1 = true
    end
    for _, key in ipairs({
        "general",
        "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        MSUF_Defaults_NormalizeFontField(MSUF_DB[key])
    end
    MSUF_Defaults_ClearScopedFontKeys()
    if g._msufUFLocalFontKeyMigration_v407 ~= true then
        for _, key in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }) do
            local u = MSUF_DB[key]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
        g._msufUFLocalFontKeyMigration_v407 = true
    end
    if g._msufSharedGlobalFontFamilyMigration_v501 ~= true then
        g._msufSharedGlobalFontFamilyMigration_v501 = true
    end
    MSUF_DB._msufProfileSchema = MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
    MSUF_DB._msufDefaultsRevision = MSUF_DEFAULTS_CURRENT_REVISION
    MSUF_DB_LastHeavyRun = MSUF_DB
 end

local function MSUF_Defaults_IsCurrentProfileDB(db)
    if type(db) ~= "table"
        or tonumber(db._msufProfileSchema) ~= MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
        or tonumber(db._msufDefaultsRevision) ~= MSUF_DEFAULTS_CURRENT_REVISION then
        return false
    end
    --- Keep the fast path safe for truncated/malformed SavedVariables. Nested
    --- value validation belongs to imports (which force EnsureDB), while these
    --- root tables are the minimum runtime contract for a stored profile.
    for i = 1, #MSUF_DEFAULTS_ROOT_TABLE_KEYS do
        if type(db[MSUF_DEFAULTS_ROOT_TABLE_KEYS[i]]) ~= "table" then
            return false
        end
    end
    local g = db.general
    if type(g.fontKey) ~= "string" or g.fontKey == ""
        or g.hardKillBlizzardPlayerFrame == nil
        or db.shortenNames == nil
        or db.bars.barBackgroundAlpha == nil
        or db.gameplay.enableCombatTimer == nil then
        return false
    end
    return true
end

--- Cheap public guard used by the rest of the addon. Pass force=true only after
--- changing profile tables or importing data, when the full repair/migration
--- pass must be allowed to run again on the active MSUF_DB reference.
--- allowPersistedFastPath is intentionally reserved for profile initialization
--- and private export copies. Normal profile switches retain the old behavior
--- of repairing the newly selected table even when its revision is current.
--- temporaryProfile keeps export materialization from evicting the real active
--- profile from the session-local last-heavy-run cache.
local function MSUF_EnsureDB(force, allowPersistedFastPath, temporaryProfile)
    if force ~= true and type(MSUF_DB) == "table" then
        if MSUF_DB_LastHeavyRun == MSUF_DB then
            return MSUF_DB
        end
        if allowPersistedFastPath == true and MSUF_Defaults_IsCurrentProfileDB(MSUF_DB) then
            if temporaryProfile ~= true then
                MSUF_DB_LastHeavyRun = MSUF_DB
            end
            return MSUF_DB
        end
    end
    local previousHeavyRun = MSUF_DB_LastHeavyRun
    MSUF_EnsureDB_Heavy()
    if temporaryProfile == true then
        MSUF_DB_LastHeavyRun = previousHeavyRun
    end
    return MSUF_DB
 end
ExportPublic("MSUF_EnsureDB", MSUF_EnsureDB)
_G.EnsureDB = _G.EnsureDB or MSUF_EnsureDB
--- Optional exports for other modules
MSUF.MSUF_CreateFactoryDefaultProfile = MSUF_Defaults_CreateFactoryProfile
MSUF.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
MSUF.MSUF_EnsureDB = MSUF_EnsureDB
MSUF.EnsureDB = MSUF.EnsureDB or MSUF_EnsureDB
ExportPublic("MSUF_CreateFactoryDefaultProfile", MSUF_Defaults_CreateFactoryProfile)

local _, MSUF = ...
local Settings = { version = 1 }
MSUF.NameplateSettings = Settings
local IsSecret = MSUF.Util.IsSecret

-- Portable settings are restricted to nameplate text and the nameplate switch
-- of the interrupt-ready indicator. A missing section leaves its owner unchanged.
-- Nameplates draw readiness with the castbar menu's own look (MSUF_DB.general),
-- so every other general field is validated for older exports and never stored.
local SCHEMA = {
    general = {
        kickReadyShowNameplates = { "boolean" },
        kickReadyStyle = { "enum", { border = true, box = true, fill = true } },
        kickReadyAutoSize = { "boolean" },
        kickReadySize = { "number", 8, 80 },
        kickReadyAnchor = { "enum", { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true,
            TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, CENTER = true } },
        kickReadyOffsetX = { "number", -2000, 2000 },
        kickReadyOffsetY = { "number", -2000, 2000 },
        kickReadyTimeMarker = { "boolean" },
        kickReadyTimeSegment = { "boolean" },
        kickReadyColor = { "color" },
        kickNotReadyColor = { "color" },
        castbarOutlineThickness = { "number", 0, 12 },
        castbarTexture = { "string", 256 },
        castbarInterruptibleColor = { "string", 128 },
        castbarNonInterruptibleColor = { "string", 128 },
        castbarInterruptUnavailableColor = { "string", 128 },
        castbarInterruptibleR = { "number", 0, 1 },
        castbarInterruptibleG = { "number", 0, 1 },
        castbarInterruptibleB = { "number", 0, 1 },
        castbarNonInterruptibleR = { "number", 0, 1 },
        castbarNonInterruptibleG = { "number", 0, 1 },
        castbarNonInterruptibleB = { "number", 0, 1 },
        castbarInterruptUnavailableR = { "number", 0, 1 },
        castbarInterruptUnavailableG = { "number", 0, 1 },
        castbarInterruptUnavailableB = { "number", 0, 1 },
    },
    nameplates = {
        fontOverride = { "boolean" },
        fontKey = { "string", 256 },
        fontSize = { "number", 1, 200 },
        nameFontSize = { "number", 1, 200 },
        noOutline = { "boolean" },
        boldText = { "boolean" },
        fontMonochrome = { "boolean" },
        fontSlug = { "boolean" },
        textBackdrop = { "boolean" },
        fontShadowOpacity = { "number", 0.2, 1 },
        fontShadowDistance = { "number", 1, 2 },
        fontShadowStrength = { "enum", { SOFT = true, NORMAL = true, DEEP = true } },
        fontTextAlpha = { "number", 0.7, 1 },
        fontBaselineOffset = { "number", -4, 4 },
        nameFormat = { "enum", { FULL = true, CUT = true, ABBREV = true, ABBREV_CUT = true } },
        shortenNames = { "boolean" },
        shortenNameClipSide = { "enum", { LEFT = true, RIGHT = true } },
        shortenNameMaxChars = { "number", 4, 40 },
        shortenNameShowDots = { "boolean" },
        nameColorMode = { "enum", { DEFAULT = true, CLASS = true, CUSTOM = true } },
        nameClassColor = { "boolean" },
        npcNameRed = { "boolean" },
        nameNpcClassColor = { "boolean" },
        nameColorR = { "number", 0, 1 },
        nameColorG = { "number", 0, 1 },
        nameColorB = { "number", 0, 1 },
        fontColorR = { "number", 0, 1 },
        fontColorG = { "number", 0, 1 },
        fontColorB = { "number", 0, 1 },
    },
}

local COLOR_KEYS = { [1] = true, [2] = true, [3] = true, [4] = true,
    ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, r = true, g = true, b = true, a = true }
local COLOR_CHANNELS = { "r", "g", "b", "a" }

local function PlainTable(value)
    return not IsSecret(value) and type(value) == "table" and getmetatable(value) == nil
end

local function NumberInRange(value, minimum, maximum)
    return not IsSecret(value) and type(value) == "number" and value >= minimum and value <= maximum
end

local function NormalizeColor(value)
    if not PlainTable(value) then return nil end
    for key in pairs(value) do
        if IsSecret(key) or not COLOR_KEYS[key] then return nil end
    end
    local out = {}
    for index = 1, 4 do
        local channel = value[index]
        if IsSecret(channel) then return nil end
        if channel == nil then channel = value[tostring(index)] end
        if IsSecret(channel) then return nil end
        if channel == nil then channel = value[COLOR_CHANNELS[index]] end
        if IsSecret(channel) then return nil end
        if channel == nil and index == 4 then channel = 1 end
        if not NumberInRange(channel, 0, 1) then return nil end
        out[index] = channel
    end
    return out
end

local function NormalizeField(value, spec)
    if IsSecret(value) then return nil end
    local kind = spec[1]
    if kind == "boolean" then
        if type(value) == "boolean" then return value end
    elseif kind == "number" then
        if NumberInRange(value, spec[2], spec[3]) then return value end
    elseif kind == "string" then
        if type(value) == "string" and #value > 0 and #value <= spec[2] and not value:find("%c") then return value end
    elseif kind == "enum" then
        if type(value) == "string" and spec[2][value] then return value end
    elseif kind == "color" then
        return NormalizeColor(value)
    end
end

local function NormalizeSection(section, schema)
    if not PlainTable(section) then return nil end
    local out = {}
    for key, value in pairs(section) do
        if IsSecret(key) or type(key) ~= "string" or not schema[key] then return nil end
        local normalized = NormalizeField(value, schema[key])
        if normalized == nil then return nil end
        out[key] = normalized
    end
    return out
end

local function NormalizeClear(clear, out)
    if not PlainTable(clear) then return nil end
    local result, seen, count = {}, {}, 0
    for index, path in pairs(clear) do
        if not NumberInRange(index, 1, 80) or index % 1 ~= 0 then return nil end
        if IsSecret(path) or type(path) ~= "string" then return nil end
        local section, key = path:match("^(%a+)%.(%w+)$")
        if not section or not SCHEMA[section] or not SCHEMA[section][key] or seen[path] then return nil end
        if out[section] and out[section][key] ~= nil then return nil end
        seen[path], count = true, count + 1
        result[index] = path
    end
    if count ~= #result then return nil end
    table.sort(result)
    return result
end

function Settings.Normalize(payload)
    if IsSecret(payload) then return nil, "invalid" end
    if payload == nil then return nil end
    if not PlainTable(payload) then return nil, "invalid" end
    local version = payload.version
    if IsSecret(version) or version ~= nil and version ~= 1 then return nil, "invalid" end
    local out = { version = 1 }
    for key, value in pairs(payload) do
        if IsSecret(key) or type(key) ~= "string" then return nil, "invalid" end
        if SCHEMA[key] then
            out[key] = NormalizeSection(value, SCHEMA[key])
            if not out[key] then return nil, "invalid" end
        elseif key ~= "version" and key ~= "clear" then
            return nil, "invalid"
        end
    end
    local clear = payload.clear
    if IsSecret(clear) then return nil, "invalid" end
    if clear ~= nil then
        out.clear = NormalizeClear(clear, out)
        if not out.clear then return nil, "invalid" end
    end
    return out
end

local FILE = "Runtime/MSUF_NameplateSettings.lua"
local TEXT_DEFAULTS = {
    fontOverride = true, fontKey = "FRIZQT", fontSize = 12, nameFontSize = 12,
    noOutline = false, boldText = false, fontMonochrome = false, fontSlug = false,
    textBackdrop = true, fontShadowOpacity = 1, fontShadowDistance = 1,
    fontTextAlpha = 1, fontBaselineOffset = 0, nameFormat = "FULL",
    shortenNames = false, shortenNameClipSide = "LEFT", shortenNameMaxChars = 6,
    shortenNameShowDots = true, nameColorMode = "DEFAULT", nameClassColor = false,
    npcNameRed = false, nameNpcClassColor = false,
    nameColorR = 1, nameColorG = 1, nameColorB = 1,
    fontColorR = 1, fontColorG = 1, fontColorB = 1,
}

function Settings.HasFontScope()
    local config = MSUF.UF and MSUF.UF.Config
    return config ~= nil and type(config.ResolveNameplateFont) == "function"
end

-- The only general field this owner stores; the rest of that section is the
-- castbar menu's.
local SWITCH = "kickReadyShowNameplates"

local function Stored(section, key, fonts)
    if section == "general" then return key == SWITCH end
    return fonts
end

local function Profile(name)
    if IsSecret(name) then return nil end
    if name == nil or name == _G.MSUF_ActiveProfile then return _G.MSUF_DB end
    if type(name) ~= "string" then return nil end
    local root = _G.MSUF_GlobalDB
    local profiles = type(root) == "table" and root.profiles
    return type(profiles) == "table" and profiles[name] or nil
end

local function Snapshot(db, fonts)
    local fields, snapshot = MSUF.ProfileFields, { version = 1, clear = {} }
    for section, schema in pairs(SCHEMA) do
        local values
        for key in pairs(schema) do
            if Stored(section, key, fonts) then
                values = values or {}
                local value = fields.Read(db, { section, key })
                if value == nil then
                    snapshot.clear[#snapshot.clear + 1] = section .. "." .. key
                else
                    local copy, valid = fields.Copy(value)
                    if not valid then return nil end
                    values[key] = copy
                end
            end
        end
        snapshot[section] = values
    end
    table.sort(snapshot.clear)
    return snapshot
end

local function CaptureInterrupt(db)
    local general = type(db.general) == "table" and db.general or {}
    return { [SWITCH] = general[SWITCH] == true }
end

local function TextSourceValue(general, scoped, key, fallback)
    local value = scoped[key]
    if value == nil then value = general[key] end
    local normalized = NormalizeField(value, SCHEMA.nameplates[key])
    if normalized == nil then return fallback end
    return normalized
end

local function CaptureTextColors(out, general, scoped)
    local palette = MSUF.MSUF_FONT_COLORS
    local key = type(general.fontColor) == "string" and general.fontColor:lower() or "white"
    local color = palette and palette[key]
    local custom = general.useCustomFontColor == true
    local channels = { "R", "G", "B" }
    for index = 1, 3 do
        local suffix = channels[index]
        local value = custom and general["fontColorCustom" .. suffix] or color and color[index]
        if scoped.fontColorR ~= nil then value = scoped["fontColor" .. suffix] end
        out["fontColor" .. suffix] = NormalizeField(value, SCHEMA.nameplates["fontColor" .. suffix]) or 1
    end
    local nameSource = scoped.fontOverride == true and scoped or general
    out.nameColorMode = nameSource.nameColorMode == "CUSTOM" and "CUSTOM" or (out.nameClassColor and "CLASS" or "DEFAULT")
    if out.nameColorMode == "CUSTOM" then
        for index = 1, 3 do
            local field = "nameColor" .. channels[index]
            out[field] = NormalizeField(nameSource[field], SCHEMA.nameplates[field]) or 1
        end
        out.nameClassColor, out.npcNameRed, out.nameNpcClassColor = false, false, false
    end
end

local function CaptureText(db, fonts, overrides)
    local general = type(db.general) == "table" and db.general or {}
    local scoped = overrides or (fonts and type(db.nameplates) == "table" and db.nameplates or {})
    if scoped.fontOverride ~= true then scoped = {} end
    local out = {}
    for key, fallback in pairs(TEXT_DEFAULTS) do out[key] = TextSourceValue(general, scoped, key, fallback) end
    out.fontOverride = true
    if scoped.noOutline ~= nil or scoped.boldText ~= nil then
        out.noOutline, out.boldText = scoped.noOutline == true, scoped.noOutline ~= true and scoped.boldText == true
    end
    out.nameFontSize = TextSourceValue(general, scoped, "nameFontSize", out.fontSize)
    local shorten = scoped.shortenNames
    if shorten == nil then shorten = scoped.nameShortenEnabled end
    if shorten == nil then shorten = db.shortenNames end
    out.shortenNames = shorten == true
    local format = scoped.nameFormat
    if format == nil then format = general.nameFormat end
    out.nameFormat = NormalizeField(format, SCHEMA.nameplates.nameFormat) or (out.shortenNames and "CUT" or "FULL")
    out.shortenNameMaxChars = TextSourceValue(general, scoped, "shortenNameMaxChars", 6)
    if scoped.shortenNameMaxChars == nil and scoped.nameMaxChars ~= nil then
        out.shortenNameMaxChars = NormalizeField(scoped.nameMaxChars, SCHEMA.nameplates.shortenNameMaxChars) or 6
    end
    if scoped.shortenNameClipSide == nil and scoped.nameClipSide ~= nil then
        out.shortenNameClipSide = NormalizeField(scoped.nameClipSide, SCHEMA.nameplates.shortenNameClipSide) or "LEFT"
    end
    if scoped.shortenNameShowDots == nil and scoped.nameNoEllipsis ~= nil then
        out.shortenNameShowDots = scoped.nameNoEllipsis ~= true
    end
    if fonts then
        local method, maximum, dots, side = MSUF.UFText.DescribeNameFormat(format or out.nameFormat,
            out.shortenNameMaxChars, out.shortenNameShowDots, out.shortenNameClipSide)
        if method then
            out.nameFormat, out.shortenNameShowDots, out.shortenNameClipSide = method, dots, side
            if maximum > 0 then out.shortenNameMaxChars = maximum end
        end
    end
    local metrics = MSUF.Require("MSUF_ResolveFontShadowMetrics", FILE)
    local alpha, distance = metrics(general.fontShadowOpacity, general.fontShadowDistance, general.fontShadowStrength)
    if scoped.fontShadowOpacity ~= nil or scoped.fontShadowDistance ~= nil or scoped.fontShadowStrength ~= nil then
        alpha, distance = metrics(scoped.fontShadowOpacity, scoped.fontShadowDistance, scoped.fontShadowStrength, alpha, distance)
    end
    out.fontShadowOpacity, out.fontShadowDistance = alpha, distance
    CaptureTextColors(out, general, scoped)
    return out
end

-- Resolve a portable override against this profile's live shared typography.
-- This read-only path gives older hosts the same grouped inheritance rules.
function Settings.ResolveTypography(overrides, name)
    local normalized, reason = Settings.Normalize({ nameplates = overrides })
    if not normalized or not normalized.nameplates then return nil, reason or "invalid" end
    local db = Profile(name)
    if type(db) ~= "table" then return nil, "unavailable" end
    overrides = normalized.nameplates
    if overrides.fontOverride == nil then overrides.fontOverride = true end
    local resolved = CaptureText(db, Settings.HasFontScope(), overrides)
    for key, value in pairs(resolved) do resolved[key] = NormalizeField(value, SCHEMA.nameplates[key]) end
    return resolved
end

-- The third result is the exact scoped storage snapshot for caller rollback.
-- Capture never activates the requested profile or mutates its defaults.
function Settings.Capture(name)
    local db = Profile(name)
    if type(db) ~= "table" then return nil, "unavailable" end
    local fonts = Settings.HasFontScope()
    local snapshot = Snapshot(db, fonts)
    if not snapshot then return nil, "invalid" end
    local payload = { version = 1, general = CaptureInterrupt(db), nameplates = CaptureText(db, fonts) }
    for section, values in pairs(payload) do
        if SCHEMA[section] then
            for key, value in pairs(values) do values[key] = NormalizeField(value, SCHEMA[section][key]) end
        end
    end
    return payload, nil, snapshot
end

local function WritePayload(db, payload, fonts)
    local fields = MSUF.ProfileFields
    for section in pairs(SCHEMA) do
        for key, value in pairs(payload[section] or {}) do
            if Stored(section, key, fonts) then fields.Write(db, { section, key }, fields.Copy(value)) end
        end
    end
    for _, path in ipairs(payload.clear or {}) do
        local section, key = path:match("^(%a+)%.(%w+)$")
        if Stored(section, key, fonts) then fields.Write(db, { section, key }, nil) end
    end
    local scoped = db.nameplates
    if type(scoped) == "table" and next(scoped) == nil then fields.Write(db, { "nameplates" }, nil) end
end

-- Earlier 7.0 builds kept a nameplate-only interrupt look in nameplates.interrupt.
-- Nothing reads it now; a successful apply drops it from the active profile.
local function DropLegacyInterrupt(db)
    local scoped = db.nameplates
    if type(scoped) ~= "table" or scoped.interrupt == nil then return end
    local fields = MSUF.ProfileFields
    fields.Write(db, { "nameplates", "interrupt" }, nil)
    if next(scoped) == nil then fields.Write(db, { "nameplates" }, nil) end
end

local function Refresh(payload, fonts)
    local general, text = payload.general ~= nil and payload.general[SWITCH] ~= nil, fonts and payload.nameplates ~= nil
    for _, path in ipairs(payload.clear or {}) do
        if path:sub(1, 8) ~= "general." then text = fonts elseif path == "general." .. SWITCH then general = true end
    end
    if general then
        MSUF.Require("MSUF_Castbars_OnSettingsChanged", FILE)("NAMEPLATE_SETTINGS")
        MSUF.Require("MSUF_ApplyAllCastbarsAndSync", FILE)()
    end
    if text then MSUF.SuiteLink.ApplyFonts(true) end
end

local function ApplyStep(db, payload, fonts)
    WritePayload(db, payload, fonts)
    Refresh(payload, fonts)
end

local applying = false
function Settings.Apply(payload)
    if applying then return false, "busy" end
    if MSUF.HostAPIPlayerInCombat() then return false, "combat" end
    local normalized, reason = Settings.Normalize(payload)
    if not normalized then return false, reason or "invalid" end
    local db = Profile()
    if type(db) ~= "table" or type(db.general) ~= "table" then return false, "unavailable" end
    local fonts = Settings.HasFontScope()
    local snapshot = Snapshot(db, fonts)
    if not snapshot then return false, "invalid" end
    local originalNameplates = db.nameplates
    applying = true
    local ok = MSUF.RunHostAPIStep("Nameplate settings", ApplyStep, db, normalized, fonts)
    if not ok then
        WritePayload(db, snapshot, fonts)
        MSUF.RunHostAPIStep("Nameplate settings restore", Refresh, snapshot, fonts)
        WritePayload(db, snapshot, fonts)
        if originalNameplates == nil then MSUF.ProfileFields.Write(db, { "nameplates" }, nil) end
    end
    applying = false
    if not ok then return false, "failed" end
    DropLegacyInterrupt(db)
    return true, { snapshot = snapshot, fontFallback = not fonts and normalized.nameplates ~= nil }
end

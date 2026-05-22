-- MSUF_UFCore_ToTInline.lua
-- Target-of-target inline text owned by UFCore, isolated from dirty queue and
-- unit-event orchestration so the target-swap hot path remains readable.

local _, addon = ...
addon = addon or {}

local type, tostring, tonumber = type, tostring, tonumber
local string_byte, string_gsub, string_sub = string.byte, string.gsub, string.sub
local UnitExists, UnitName = UnitExists, UnitName
local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass
local UnitIsDeadOrGhost, UnitReaction = UnitIsDeadOrGhost, UnitReaction
local UnitClassification, UnitEffectiveLevel = UnitClassification, UnitEffectiveLevel
local UnitIsLieutenant, UnitClassBase = UnitIsLieutenant, UnitClassBase
local CreateFrame = CreateFrame

local CUSTOM_SEPARATOR = "__CUSTOM__"
local CUSTOM_SEPARATOR_MAX = 5
local COLOR_AUTO = "AUTO"
local COLOR_TOT_NAME = "TOT_NAME"
local COLOR_TARGET_NAME = "TARGET_NAME"
local COLOR_NPC = "NPC"
local COLOR_DEFAULT = "DEFAULT"
local VALID_COLOR_MODE = {
    [COLOR_AUTO] = true,
    [COLOR_TOT_NAME] = true,
    [COLOR_TARGET_NAME] = true,
    [COLOR_NPC] = true,
    [COLOR_DEFAULT] = true,
}
local PRESET_SEPARATOR = {
    [" "] = true,
    ["-"] = true,
    ["/"] = true,
    ["\\"] = true,
    ["|"] = true,
    ["<"] = true,
    [">"] = true,
    ["~"] = true,
    [":"] = true,
}

local State = {
    db = nil,
    conf = nil,
    migrated = nil,
}

local GetClassColor, GetReactionColor

local function EnsureDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end
    return _G.MSUF_DB
end

local function SetShown(obj, show)
    if not obj then return end
    if show then
        if obj.Show then obj:Show() end
    else
        if obj.Hide then obj:Hide() end
    end
end

local function SetText(fs, text)
    if not fs then return end
    local fn = _G.MSUF_SetTextIfChanged
    if type(fn) == "function" then
        fn(fs, text or "")
    elseif fs.SetText then
        fs:SetText(text or "")
    end
end

local function TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end

    local bytePos = 1
    local valueLen = #value
    local chars = 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string_byte(value, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return string_sub(value, 1, bytePos - 1)
end

local function CleanCustomSeparator(value)
    value = string_gsub(tostring(value or ""), "[%c]", " ")
    return TruncateUtf8Chars(value, CUSTOM_SEPARATOR_MAX)
end

local function ResolveSeparator(conf)
    local token = conf and conf.totInlineSeparator
    if token == CUSTOM_SEPARATOR then
        token = conf and conf.totInlineCustomSeparator
        if type(token) ~= "string" or token == "" then token = " " end
    elseif type(token) ~= "string" or token == "" then
        token = "|"
    end
    return token
end

local function NormalizeColorMode(value)
    value = tostring(value or "")
    if VALID_COLOR_MODE[value] then return value end
    return COLOR_AUTO
end

local function GetConfiguredFontColor()
    local fn = _G.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    local db = _G.MSUF_DB
    local general = db and db.general
    if general and general.useCustomFontColor
        and type(general.fontColorCustomR) == "number"
        and type(general.fontColorCustomG) == "number"
        and type(general.fontColorCustomB) == "number" then
        return general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB
    end

    local colors = _G.MSUF_FONT_COLORS
    local key = tostring((general and general.fontColor) or "white"):lower()
    local color = colors and (colors[key] or colors.white)
    return (color and color[1]) or 1, (color and color[2]) or 1, (color and color[3]) or 1
end

local function EffectiveNameColorFlags(unitKey)
    local db = _G.MSUF_DB
    local gen = db and db.general
    local wantClass = gen and gen.nameClassColor
    local wantNpc = gen and gen.npcNameRed

    local uconf = db and unitKey and db[unitKey]
    if uconf and uconf.fontOverride then
        if uconf.nameClassColor ~= nil then wantClass = uconf.nameClassColor end
        if uconf.npcNameRed ~= nil then wantNpc = uconf.npcNameRed end
    end

    return wantClass == true, wantNpc == true
end

local function GetSettingsCache()
    local fn = _G.MSUF_UFCore_GetSettingsCache
    return (type(fn) == "function" and fn()) or nil
end

local function ConfiguredNPCTypeTextAllowedForToT()
    local db = _G.MSUF_DB
    local g = db and db.general
    if not g then return false end
    if g.npcColorMode ~= "type" then return false end
    if g.npcTypeColorText == false then return false end
    if g.npcTypeToT == false then return false end
    return true
end

local function NPCTypeTextAllowed(unitKey)
    local cache = GetSettingsCache()
    if not (cache and cache.npcColorMode == "type" and cache.npcTypeColorText) then return false end
    if unitKey == "targettarget" or unitKey == "tot" or unitKey == "focustarget" then
        return cache.npcTypeToT ~= false
    end
    if unitKey == "target" then return cache.npcTypeTarget ~= false end
    if unitKey == "focus" then return cache.npcTypeFocus ~= false end
    if unitKey == "boss" then return cache.npcTypeBoss ~= false end
    return true
end

local function ResolveNPCReactionKind(unit)
    if not (unit and UnitExists and UnitExists(unit)) then return "enemy" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return "dead" end

    local reaction = tonumber(UnitReaction and UnitReaction("player", unit))
    if reaction and reaction >= 5 then
        return "friendly"
    elseif reaction and reaction == 4 then
        return "neutral"
    end
    return "enemy"
end

local function ResolveNPCKind(unit, unitKey)
    local kind = ResolveNPCReactionKind(unit)

    if kind ~= "enemy" or not NPCTypeTextAllowed(unitKey) then return kind end

    local cls = UnitClassification and UnitClassification(unit)
    if cls == "worldboss" or cls == "boss" then
        return "npcBoss"
    elseif cls == "elite" or cls == "rareelite" then
        local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or 0
        if level == -1 then
            return "npcBoss"
        elseif UnitIsLieutenant and UnitIsLieutenant(unit) then
            return "npcMiniboss"
        end
        local uclass = UnitClassBase and UnitClassBase(unit)
        return (uclass == "PALADIN") and "npcCaster" or "npcMelee"
    elseif cls == "rare" then
        return "npcMiniboss"
    end

    return "npcRegular"
end

local function IsNPCColorModeAvailable()
    local _, wantNpc = EffectiveNameColorFlags("targettarget")
    return wantNpc == true and ConfiguredNPCTypeTextAllowedForToT()
end

local function ResolveNameColor(unit, unitKey, fallbackR, fallbackG, fallbackB, legacyNpcAlways)
    if not (unit and UnitExists and UnitExists(unit)) then
        return fallbackR or 1, fallbackG or 1, fallbackB or 1
    end

    local wantClass, wantNpc = EffectiveNameColorFlags(unitKey)
    if UnitIsPlayer and UnitIsPlayer(unit) then
        if wantClass then
            local _, classToken = UnitClass(unit)
            return GetClassColor(classToken)
        end
    elseif legacyNpcAlways or wantNpc then
        return GetReactionColor(ResolveNPCKind(unit, unitKey))
    end

    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end

local function ResolveLegacyAutoColor(targetFrame, fallbackR, fallbackG, fallbackB)
    if not (UnitExists and UnitExists("targettarget")) then
        return fallbackR or 1, fallbackG or 1, fallbackB or 1
    end

    if UnitIsPlayer and UnitIsPlayer("targettarget") then
        local unitKey = (targetFrame and targetFrame.msufConfigKey) or "target"
        local wantClass = EffectiveNameColorFlags(unitKey)
        if wantClass then
            local _, classToken = UnitClass("targettarget")
            return GetClassColor(classToken)
        end
        return fallbackR or 1, fallbackG or 1, fallbackB or 1
    end

    return GetReactionColor(ResolveNPCReactionKind("targettarget"))
end

local function ResolveTextColor(targetFrame, conf, inEdit)
    local mode = NormalizeColorMode(conf and conf.totInlineColorMode)

    if not inEdit and mode == COLOR_AUTO then
        return ResolveLegacyAutoColor(targetFrame, 1, 1, 1)
    end

    if not inEdit and mode == COLOR_TARGET_NAME then
        local name = targetFrame and targetFrame.nameText
        if name and name.GetTextColor then
            local r, g, b = name:GetTextColor()
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end

    local fr, fg, fb = GetConfiguredFontColor()

    if mode == COLOR_DEFAULT or inEdit then
        return fr, fg, fb
    end

    if mode == COLOR_TARGET_NAME then
        return ResolveNameColor("target", "target", fr, fg, fb, false)
    end

    if mode == COLOR_TOT_NAME then
        return ResolveNameColor("targettarget", "targettarget", fr, fg, fb, false)
    end

    if mode == COLOR_NPC then
        if IsNPCColorModeAvailable() and not (UnitIsPlayer and UnitIsPlayer("targettarget")) then
            return GetReactionColor(ResolveNPCKind("targettarget", "targettarget"))
        end
        return ResolveLegacyAutoColor(targetFrame, 1, 1, 1)
    end

    return ResolveLegacyAutoColor(targetFrame, 1, 1, 1)
end

local function GetTargetToTInlineConf()
    local db = EnsureDB()
    if type(db) ~= "table" then return nil end

    if State.db ~= db then
        State.db = db
        State.conf = nil
        State.migrated = nil
    end

    local tt = State.conf
    if type(tt) ~= "table" then
        tt = db.targettarget
        if type(tt) ~= "table" then
            tt = {}
            db.targettarget = tt
        end
        State.conf = tt
    end

    if not State.migrated then
        local target = db.target
        if tt.showToTInTargetName == nil and type(target) == "table" then
            local v = target.showToTInTargetName
            if v == 1 or v == "1" then v = true end
            if v == 0 or v == "0" then v = false end
            if v ~= nil then tt.showToTInTargetName = (v == true) end
        end
        if tt.totInlineSeparator == nil and type(target) == "table" and type(target.totInlineSeparator) == "string" then
            tt.totInlineSeparator = target.totInlineSeparator
        end
        if type(tt.totInlineSeparator) ~= "string" or tt.totInlineSeparator == "" then
            tt.totInlineSeparator = "|"
        end
        if tt.totInlineCustomSeparator == nil and type(target) == "table" and type(target.totInlineCustomSeparator) == "string" then
            tt.totInlineCustomSeparator = target.totInlineCustomSeparator
        end
        tt.totInlineCustomSeparator = CleanCustomSeparator(tt.totInlineCustomSeparator)
        if tt.totInlineSeparator ~= CUSTOM_SEPARATOR and not PRESET_SEPARATOR[tt.totInlineSeparator] then
            tt.totInlineCustomSeparator = CleanCustomSeparator(tt.totInlineSeparator)
            tt.totInlineSeparator = CUSTOM_SEPARATOR
        end
        if tt.showToTInTargetName == nil then
            tt.showToTInTargetName = false
        end
        State.migrated = true
    end

    tt.totInlineColorMode = NormalizeColorMode(tt.totInlineColorMode)
    if tt.totInlineColorMode == COLOR_NPC and not IsNPCColorModeAvailable() then
        tt.totInlineColorMode = COLOR_AUTO
    end

    return tt
end

local function IsToTInlineEnabled()
    local conf = GetTargetToTInlineConf()
    return (conf and conf.showToTInTargetName == true) and true or false
end

GetClassColor = function(classToken)
    local fn = _G.MSUF_UFCore_GetClassBarColorFast
    if type(fn) == "function" then
        return fn(classToken)
    end
    return 1, 1, 1
end

GetReactionColor = function(token)
    local fn = _G.MSUF_UFCore_GetNPCReactionColorFast
    if type(fn) == "function" then
        return fn(token)
    end
    if token == "friendly" then return 0, 1, 0 end
    if token == "neutral" then return 1, 1, 0 end
    if token == "dead" then return 0.4, 0.4, 0.4 end
    return 0.85, 0.1, 0.1
end

local function EnsureWidgets(f, conf)
    if not conf or not conf.showToTInTargetName then return end

    local name = f and f.nameText
    if not name then return end

    local overlay = f._msufToTInlineOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, f)
        f._msufToTInlineOverlay = overlay
        overlay:SetAllPoints(f)
        overlay:SetFrameLevel((f:GetFrameLevel() or 0) + 80)
    else
        if overlay:GetParent() ~= f then
            overlay:SetParent(f)
            overlay:SetAllPoints(f)
        end
        local desiredLevel = (f:GetFrameLevel() or 0) + 80
        if overlay:GetFrameLevel() < desiredLevel then
            overlay:SetFrameLevel(desiredLevel)
        end
    end

    local created = false

    local sep = f._msufToTInlineSep
    if not sep then
        sep = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineSep = sep
        sep:SetFontObject(GameFontNormalSmall)
        sep:SetJustifyH("LEFT")
        sep:SetJustifyV("MIDDLE")
        created = true
    elseif sep:GetParent() ~= overlay then
        sep:SetParent(overlay)
    end

    local tt = f._msufToTInlineText
    if not tt then
        tt = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineText = tt
        tt:SetFontObject(GameFontNormalSmall)
        tt:SetJustifyH("LEFT")
        tt:SetJustifyV("MIDDLE")
        created = true
    elseif tt:GetParent() ~= overlay then
        tt:SetParent(overlay)
    end

    sep:SetDrawLayer("OVERLAY", 7)
    tt:SetDrawLayer("OVERLAY", 7)

    sep:ClearAllPoints()
    local inlineAnchor = name
    if f.raidGroupNameText and f.raidGroupNameText.IsShown and f.raidGroupNameText:IsShown()
        and f._msufRaidGroupNameAnchor == "NAMERIGHT" then
        inlineAnchor = f.raidGroupNameText
    end
    sep:SetPoint("LEFT", inlineAnchor, "RIGHT", 0, 0)

    tt:ClearAllPoints()
    tt:SetPoint("LEFT", sep, "RIGHT", 0, 0)

    if created and name.GetFont then
        local font, size, flags = name:GetFont()
        if font then
            sep:SetFont(font, size, flags)
            tt:SetFont(font, size, flags)
            sep._msufFontRev = nil
            tt._msufFontRev = nil
        end
    end
end

local function UpdateToTInline(f)
    if not f or not f._msufIsTarget then return end

    if not IsToTInlineEnabled() then
        SetShown(f._msufToTInlineSep, false)
        SetShown(f._msufToTInlineText, false)
        return
    end

    if (not f._msufToTInlineSep) or (not f._msufToTInlineText) then
        if type(_G.MSUF_UFCore_RequestLayout) == "function" then
            _G.MSUF_UFCore_RequestLayout(f, "ToTInlineWidgetsMissing", true)
        end
        return
    end

    local show = false
    local inEdit = false
    if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode then
        inEdit = addon.EditModeLib:IsInEditMode() and true or false
    end

    if inEdit then
        show = true
        SetText(f._msufToTInlineText, "ToT")
    elseif UnitExists and UnitExists("targettarget") then
        show = true
        local nm = UnitName and UnitName("targettarget") or nil
        SetText(f._msufToTInlineText, nm or "")
    end

    local conf = GetTargetToTInlineConf()
    local token = ResolveSeparator(conf)
    SetText(f._msufToTInlineSep, " " .. token .. " ")

    if show then
        local txt = f._msufToTInlineText
        local frameWidth = (f.GetWidth and f:GetWidth()) or 0
        local maxW = 120
        if frameWidth > 0 then
            maxW = math.floor(frameWidth * 0.32)
            if maxW < 80 then maxW = 80 end
            if maxW > 180 then maxW = 180 end
        end
        txt:SetWidth(maxW)

        local r, g, b = ResolveTextColor(f, conf, inEdit)

        f._msufToTInlineSep:SetTextColor(0.7, 0.7, 0.7)
        txt:SetTextColor(r, g, b)
        SetShown(f._msufToTInlineSep, true)
        SetShown(txt, true)
    else
        SetShown(f._msufToTInlineSep, false)
        SetShown(f._msufToTInlineText, false)
    end
end

local function ReanchorTargetToTInline(f)
    if not (f and f._msufIsTarget and f._msufToTInlineSep and f._msufToTInlineText) then return end
    local conf = GetTargetToTInlineConf()
    if conf and conf.showToTInTargetName then
        EnsureWidgets(f, conf)
    end
end

_G.MSUF_UFCore_GetTargetToTInlineConf = GetTargetToTInlineConf
_G.MSUF_UFCore_IsToTInlineEnabled = IsToTInlineEnabled
_G.MSUF_UFCore_UpdateToTInline = UpdateToTInline
_G.MSUF_UFCore_EnsureToTInlineWidgets = EnsureWidgets
_G.MSUF_UFCore_ReanchorTargetToTInline = ReanchorTargetToTInline
_G.MSUF_UFCore_ResolveToTInlineTextColor = ResolveTextColor
_G.MSUF_UFCore_IsToTInlineNPCColorModeAvailable = IsNPCColorModeAvailable

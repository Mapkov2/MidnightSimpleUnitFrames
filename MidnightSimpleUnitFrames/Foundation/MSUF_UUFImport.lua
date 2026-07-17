-- MSUF_UUFImport.lua
-- Native UnhaltedUnitFrames 12.1 -> MSUF 5.7 profile converter.
--
-- The converter writes settings understood by the MSUF 5.7 runtime. Source
-- features which cannot be represented by that schema are reported as
-- approximated or skipped; no import-only renderer or hot-path branch is
-- required.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}

local Import = {}
ns.MSUF_UUFImport = Import

local PREFIX = "!UUF_"
local MAX_ENCODED_BYTES = 64 * 1024
local MAX_IMPORT_STRING_BYTES = MAX_ENCODED_BYTES + #PREFIX + 256
local MAX_DECOMPRESSED_BYTES = 1024 * 1024
local MAX_TABLE_DEPTH = 64
local MAX_TABLE_NODES = 250000

local VALID_ANCHOR = {
    TOPLEFT=true, TOP=true, TOPRIGHT=true,
    LEFT=true, CENTER=true, RIGHT=true,
    BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true,
}

local VALID_STRATA = {
    BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true,
    DIALOG=true, FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true,
}

local ANCHOR_FRACTION = {
    TOPLEFT={-0.5,0.5}, TOP={0,0.5}, TOPRIGHT={0.5,0.5},
    LEFT={-0.5,0}, CENTER={0,0}, RIGHT={0.5,0},
    BOTTOMLEFT={-0.5,-0.5}, BOTTOM={0,-0.5}, BOTTOMRIGHT={0.5,-0.5},
}

local function DeepCopy(value, seen, depth)
    if type(value) ~= "table" then return value end
    depth = (depth or 0) + 1
    if depth > MAX_TABLE_DEPTH then return nil end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        local copiedKey = DeepCopy(key, seen, depth)
        local copiedValue = DeepCopy(child, seen, depth)
        if copiedKey ~= nil then out[copiedKey] = copiedValue end
    end
    return out
end

local function ValidateTableGraph(root)
    local seen = {}
    local nodes = 0

    local function Walk(value, depth)
        if type(value) ~= "table" then return true end
        if seen[value] then return true end
        if depth > MAX_TABLE_DEPTH then
            return false, "UUF table nesting is too deep"
        end

        seen[value] = true
        nodes = nodes + 1
        if nodes > MAX_TABLE_NODES then
            return false, "UUF table is too large"
        end

        for key, child in pairs(value) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
                return false, "UUF table contains an unsupported key type"
            end

            local childType = type(child)
            if childType == "function" or childType == "thread" or childType == "userdata" then
                return false, "UUF table contains an unsupported value type"
            end

            local ok, why = Walk(child, depth + 1)
            if not ok then return false, why end
        end
        return true
    end

    return Walk(root, 1)
end

local function SafeNumber(value, fallback, minimum, maximum)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

local function Bool(value, fallback)
    if value == nil then return fallback == true end
    return value == true
end

local function Anchor(value, fallback)
    value = type(value) == "string" and value:upper():gsub("%s+", "") or nil
    if value and VALID_ANCHOR[value] then return value end
    return fallback or "CENTER"
end

local function FrameStrata(value, fallback)
    value = type(value) == "string" and value:upper():gsub("%s+", "_") or nil
    if value and VALID_STRATA[value] then return value end
    return fallback or "MEDIUM"
end

local function Layout(value, fallback)
    value = type(value) == "table" and value or {}
    fallback = type(fallback) == "table" and fallback or {"CENTER", "CENTER", 0, 0, 1}
    return {
        Anchor(value[1], fallback[1]),
        Anchor(value[2], fallback[2] or fallback[1]),
        SafeNumber(value[3], fallback[3] or 0, -16384, 16384),
        SafeNumber(value[4], fallback[4] or 0, -16384, 16384),
        SafeNumber(value[5], fallback[5] or 1, -128, 128),
    }
end

local function Color(value, fallback)
    value = type(value) == "table" and value or fallback
    if type(value) ~= "table" then return nil end

    local r = SafeNumber(value.r or value[1], nil, 0, 1)
    local g = SafeNumber(value.g or value[2], nil, 0, 1)
    local b = SafeNumber(value.b or value[3], nil, 0, 1)
    local a = SafeNumber(value.a or value[4], 1, 0, 1)
    if r == nil or g == nil or b == nil then return nil end
    return {r, g, b, a}
end

local function Merge(source, defaults)
    source = type(source) == "table" and source or {}
    defaults = type(defaults) == "table" and defaults or {}
    local out = {}

    for key, fallback in pairs(defaults) do
        if type(fallback) == "table" then
            out[key] = Merge(source[key], fallback)
        elseif source[key] == nil then
            out[key] = fallback
        else
            out[key] = source[key]
        end
    end

    for key, value in pairs(source) do
        if out[key] == nil then out[key] = DeepCopy(value) end
    end
    return out
end

local function Assign(target, values)
    for key, value in pairs(values) do target[key] = value end
end

local function Clear(target, keys)
    for i = 1, #keys do target[keys[i]] = nil end
end

local function AddUnique(list, value)
    if type(list) ~= "table" or type(value) ~= "string" then return end
    for i = 1, #list do
        if list[i] == value then return end
    end
    list[#list + 1] = value
end

local function NewReport()
    return {mapped={}, approximated={}, skipped={}, families={}}
end

local function Mark(report, bucket, value)
    if type(report) ~= "table" then return end
    report[bucket] = type(report[bucket]) == "table" and report[bucket] or {}
    AddUnique(report[bucket], value)
end

local function SetRGB(target, prefix, value)
    local color = Color(value)
    if not color then return false end
    target[prefix .. "R"] = color[1]
    target[prefix .. "G"] = color[2]
    target[prefix .. "B"] = color[3]
    return true
end

local function SetRGBA(target, prefix, value)
    local color = Color(value)
    if not color then return false end
    target[prefix .. "R"] = color[1]
    target[prefix .. "G"] = color[2]
    target[prefix .. "B"] = color[3]
    target[prefix .. "A"] = color[4]
    return true
end

local function SameColor(left, right)
    local a = Color(left)
    local b = Color(right)
    if not a or not b then return a == b end
    return a[1] == b[1] and a[2] == b[2]
        and a[3] == b[3] and a[4] == b[4]
end

local function Fraction(anchor)
    local pair = ANCHOR_FRACTION[Anchor(anchor, "CENTER")]
    return pair[1], pair[2]
end

function Import.IsImportString(value)
    return type(value) == "string" and value:match("^%s*!UUF_") ~= nil
end

function Import.IsAddonLoaded()
    if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
        return _G.C_AddOns.IsAddOnLoaded("UnhaltedUnitFrames") == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded("UnhaltedUnitFrames") == true
    end
    return type(_G.UUF) == "table"
end

function Import.Decode(value)
    if type(value) ~= "string" then
        return nil, "not an UnhaltedUnitFrames string"
    end
    if #value > MAX_IMPORT_STRING_BYTES then
        return nil, "UUF payload is too large"
    end

    local first = value:find("%S")
    if not first or value:sub(first, first + #PREFIX - 1) ~= PREFIX then
        return nil, "not an UnhaltedUnitFrames string"
    end

    local last = value:find("%S%s*$", first)
    local encodedStart = first + #PREFIX
    local encodedLength = last and (last - encodedStart + 1) or 0
    if encodedLength <= 0 then return nil, "empty UUF payload" end
    if encodedLength > MAX_ENCODED_BYTES then return nil, "UUF payload is too large" end

    if not (_G.LibStub and type(_G.LibStub.GetLibrary) == "function") then
        return nil, "LibStub unavailable"
    end

    local deflate = _G.LibStub:GetLibrary("MSUF-LibDeflate-Bounded", true)
    local serializer = _G.LibStub:GetLibrary("AceSerializer-3.0", true)
    if not (deflate and type(deflate.DecodeForPrint) == "function"
        and type(deflate.DecompressDeflateLimited) == "function"
        and type(deflate.DECOMPRESS_OUTPUT_LIMIT_EXCEEDED) == "number")
    then
        return nil, "bounded LibDeflate unavailable"
    end
    if not (serializer and type(serializer.Deserialize) == "function") then
        return nil, "AceSerializer unavailable"
    end

    local encoded = value:sub(encodedStart, last)
    local ok, decoded = pcall(deflate.DecodeForPrint, deflate, encoded)
    if not ok or type(decoded) ~= "string" then
        return nil, "print-safe decode failed"
    end

    local status
    ok, decoded, status = pcall(
        deflate.DecompressDeflateLimited,
        deflate,
        decoded,
        MAX_DECOMPRESSED_BYTES
    )
    if not ok then return nil, "deflate decode failed" end
    if type(decoded) ~= "string" then
        if status == deflate.DECOMPRESS_OUTPUT_LIMIT_EXCEEDED then
            return nil, "decompressed UUF payload is too large"
        end
        return nil, "deflate decode failed"
    end
    if #decoded > MAX_DECOMPRESSED_BYTES then
        return nil, "decompressed UUF payload is too large"
    end

    local success, data
    ok, success, data = pcall(serializer.Deserialize, serializer, decoded)
    if not ok or success ~= true or type(data) ~= "table" then
        return nil, "AceSerializer decode failed"
    end

    local graphOK, graphWhy = ValidateTableGraph(data)
    if not graphOK then return nil, graphWhy end

    local profile = data
    local wrapped = false
    for _ = 1, 4 do
        if type(profile.General) == "table" or type(profile.Units) == "table" then break end
        if type(profile.profile) ~= "table" then break end
        profile = profile.profile
        wrapped = true
    end

    if type(profile) ~= "table"
        or (type(profile.General) ~= "table" and type(profile.Units) ~= "table"
            and (next(profile) ~= nil or not wrapped))
    then
        return nil, "UUF payload has no recognized profile table"
    end
    return profile
end

local DEFAULT_HEALTH = {
    ColourByClass=true,
    ColourBackgroundByClass=false,
    ColourWhenTapped=true,
    ColourWhenDisconnected=true,
    Inverse=false,
    Smooth=false,
    Foreground={0.10196079313755, 0.10196079313755, 0.10196079313755, 1},
    ForegroundOpacity=1,
    Background={0.078431375324726, 0.078431375324726, 0.078431375324726, 1},
    BackgroundOpacity=1,
    DispelHighlight={Enabled=true, Style="HEALTHBAR"},
}

local DEFAULT_POWER = {
    Enabled=false,
    Height=3,
    Position="BOTTOM",
    Foreground={0.031372549019608, 0.031372549019608, 0.031372549019608, 1},
    Background={0.50196078431373, 0.50196078431373, 0.50196078431373, 1},
    ColourByType=true,
    ColourBackgroundByType=false,
    ColourByClass=false,
    Smooth=true,
    Inverse=false,
    BackgroundMultiplier=0.75,
}

local DEFAULT_SECONDARY_POWER = {
    Enabled=false,
    Height=3,
    Position="TOP",
    ColourByType=true,
    Foreground={0.031372549019608, 0.031372549019608, 0.031372549019608, 1},
    Background={0.50196078431373, 0.50196078431373, 0.50196078431373, 1},
}

local DEFAULT_ALT_POWER = {
    Enabled=false,
    Height=5,
    Width=100,
    Layout={"LEFT", "BOTTOMLEFT", 3, 1},
    Foreground={0.031372549019608, 0.031372549019608, 0.031372549019608, 1},
    Background={0.13333333333333, 0.13333333333333, 0.13333333333333, 1},
    ColourByType=true,
    Inverse=false,
}

local DEFAULT_PORTRAIT = {
    Enabled=false,
    Width=42,
    Height=42,
    Layout={"RIGHT", "LEFT", -1, 0},
    Zoom=0.3,
    UseClassPortrait=false,
    Style="2D",
}

local DEFAULT_CASTBAR = {
    Enabled=false,
    Width=244,
    Height=24,
    Layout={"TOPLEFT", "BOTTOMLEFT", 0, -1},
    Foreground={0.50196078431373, 0.50196078431373, 1, 1},
    Background={0.13333333333333, 0.13333333333333, 0.13333333333333, 1},
    NotInterruptibleColour={1, 0.25098039215686, 0.25098039215686, 1},
    InterruptCooldownColour={0.8, 0.8, 0.8, 1},
    InterruptedFailedColour={0.25098039215686, 1, 0.25098039215686, 1},
    MatchParentWidth=true,
    ColourByClass=false,
    Inverse=false,
    HoldTime=0.5,
    ShowTarget=false,
    FrameStrata="MEDIUM",
    Icon={Enabled=true, Position="LEFT"},
    Text={
        SpellName={Enabled=true, FontSize=12, Layout={"LEFT", "LEFT", 3, 0}, Colour={1,1,1,1}, MaxChars=15},
        Duration={Enabled=true, FontSize=12, Layout={"RIGHT", "RIGHT", -3, 0}, Colour={1,1,1,1}},
    },
}

local DEFAULT_HEAL = {
    IncomingHeal={Enabled=false, UseStripedTexture=false, MatchParentHeight=true, Colour={0.25098039215686,1,0.25098039215686,1}, Position="RIGHT", Height=40},
    Absorbs={Enabled=true, ShowOverAbsorb=true, UseStripedTexture=false, MatchParentHeight=true, Colour={0.50196081399918,0.75294125080109,1,0.80000007152557}, Position="ATTACH", Height=40},
    HealAbsorbs={Enabled=true, UseStripedTexture=false, MatchParentHeight=true, Colour={0.50196078431373,0.25098039215686,1,1}, Position="ATTACH", Height=40},
}

local COMPACT_HEAL = {
    IncomingHeal={Enabled=false, UseStripedTexture=false, MatchParentHeight=true, Colour={0.25098039215686,1,0.25098039215686,1}, Position="RIGHT", Height=40},
    Absorbs={Enabled=true, ShowOverAbsorb=false, UseStripedTexture=true, MatchParentHeight=true, Colour={1,0.8,0,1}, Position="LEFT", Height=20},
    HealAbsorbs={Enabled=true, UseStripedTexture=false, MatchParentHeight=true, Colour={0.50196078431373,0.25098039215686,1,1}, Position="RIGHT", Height=20},
}

local function Tag(token, point, relativePoint, x, y)
    return {
        Tag=token or "",
        FontSize=12,
        Layout={point or "CENTER", relativePoint or point or "CENTER", x or 0, y or 0},
        Colour={1,1,1,1},
    }
end

local function AuraLane(enabled, size, layout, count, wrap, growth, rowWrap, parent, blacklist)
    return {
        Enabled=enabled,
        AnchorParent=parent or "Frame",
        OnlyShowPlayer=false,
        Size=size,
        Layout=layout,
        Num=count,
        Wrap=wrap,
        GrowthDirection=growth,
        WrapDirection=rowWrap,
        ShowType=false,
        Blacklist=blacklist == true,
        Sorting="BLIZZARD",
        Count={HideStacks=false, Layout={"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 2}, FontSize=12, Colour={1,1,1,1}},
    }
end

local EMPTY_TAGS = {Tag(), Tag(), Tag(), Tag(), Tag()}

local UNIT_SPECS = {
    player={
        enabled=true, width=272, height=42, layout={"RIGHT","LEFT",-20,0}, cooldown=true,
        power=false, powerHeight=3, powerPosition="BOTTOM", cast=false,
        portrait={"RIGHT","LEFT",-1,0}, portraitSize=42,
        heal={false,true,true},
        tags={Tag(),Tag("[curhpperhp:abbr]","RIGHT","RIGHT",-3,0),Tag("","RIGHT","BOTTOMRIGHT",-3,2),Tag(),Tag()},
        buffs=AuraLane(true,42,{"RIGHT","LEFT",-1,0,1},3,3,"LEFT","UP"),
        debuffs=AuraLane(true,48,{"BOTTOMRIGHT","TOPRIGHT",0,83,1},6,6,"LEFT","UP","Frame",true),
    },
    target={
        enabled=true, width=272, height=42, layout={"LEFT","RIGHT",20,0}, cooldown=true,
        power=true, powerHeight=1, powerPosition="BOTTOM", cast=true, castTarget=true,
        castDefaults={Background={0.10196079313755,0.10196079313755,0.10196079313755,1}},
        portrait={"LEFT","RIGHT",1,0}, portraitSize=42,
        heal={false,true,true},
        tags={Tag("[name]","LEFT","LEFT",3,0),Tag("[curhpperhp:abbr]","RIGHT","RIGHT",-3,0),Tag("","RIGHT","BOTTOMRIGHT",-3,2),Tag(),Tag()},
        buffs=AuraLane(true,38,{"BOTTOMLEFT","TOPLEFT",0,1,1},7,7,"RIGHT","UP"),
        debuffs=AuraLane(false,34,{"BOTTOMRIGHT","TOPRIGHT",0,1,1},4,4,"LEFT","UP"),
    },
    targettarget={
        enabled=false, width=122, height=22, layout={"TOPRIGHT","BOTTOMRIGHT",0,-26.1}, parent="UUF_Target",
        power=false, cast=false, portrait={"RIGHT","LEFT",-1,0}, portraitSize=22,
        heal={false,true,true}, healDefaults=COMPACT_HEAL, tags={Tag("[name]"),Tag(),Tag(),Tag(),Tag()},
        buffs=AuraLane(false,22,{"RIGHT","LEFT",-1,0,1},3,3,"LEFT","UP"),
        debuffs=AuraLane(false,22,{"LEFT","RIGHT",1,0,1},3,3,"RIGHT","UP"),
    },
    focus={
        enabled=true, width=180, height=28, layout={"BOTTOM","TOPLEFT",0,110.1}, parent="UUF_Player",
        power=false, cast=false, portrait={"LEFT","RIGHT",1,0}, portraitSize=22,
        castDefaults={Layout={"BOTTOMLEFT","TOPLEFT",0,1}, Icon={Enabled=false}},
        heal={false,false,false}, healDefaults=COMPACT_HEAL, tags={Tag("[name]","LEFT","LEFT",3,0),Tag(),Tag(),Tag(),Tag()},
        buffs=AuraLane(false,22,{"RIGHT","LEFT",-1,0,1},1,1,"LEFT","UP"),
        debuffs=AuraLane(false,22,{"LEFT","RIGHT",1,0,1},3,3,"RIGHT","UP"),
    },
    focustarget={
        enabled=false, width=122, height=22, layout={"LEFT","RIGHT",1,0}, parent="UUF_Focus",
        power=false, cast=false, portrait={"RIGHT","LEFT",-1,0}, portraitSize=22,
        heal={false,true,true}, healDefaults=COMPACT_HEAL, tags={Tag("[name]"),Tag(),Tag(),Tag(),Tag()},
        buffs=AuraLane(false,22,{"RIGHT","LEFT",-1,0,1},3,3,"LEFT","UP"),
        debuffs=AuraLane(false,22,{"LEFT","RIGHT",1,0,1},3,3,"RIGHT","UP"),
    },
    pet={
        enabled=true, width=265, height=3, layout={"TOPLEFT","BOTTOMLEFT",0,-1}, parent="UUF_Player",
        power=false, cast=false, portrait={"LEFT","RIGHT",1,0}, portraitSize=22,
        heal={false,false,false}, healDefaults=COMPACT_HEAL, tags=EMPTY_TAGS,
        buffs=AuraLane(false,22,{"LEFT","RIGHT",1,0,1},1,1,"RIGHT","UP"),
        debuffs=AuraLane(false,22,{"RIGHT","LEFT",-1,0,1},3,3,"LEFT","UP"),
    },
    boss={
        enabled=true, width=252, height=52, layout={"CENTER","CENTER",550.1,-0.1,26}, growth="DOWN",
        power=true, powerHeight=1, powerPosition="BOTTOM", cast=true,
        portrait={"RIGHT","LEFT",-1,0}, portraitSize=42,
        heal={false,true,true},
        tags={Tag("[name]","LEFT","LEFT",3,0),Tag("[curhpperhp:abbr]","RIGHT","RIGHT",-3,0),Tag("","RIGHT","BOTTOMRIGHT",-3,2),Tag(),Tag()},
        buffs=AuraLane(true,52,{"LEFT","RIGHT",1,0,1},3,3,"RIGHT","UP"),
        debuffs=AuraLane(false,34,{"BOTTOMRIGHT","TOPRIGHT",0,1,1},4,4,"LEFT","UP"),
    },
}

local function Indicator(enabled, size, point, relativePoint, x, y)
    return {Enabled=enabled, Size=size, Layout={point, relativePoint, x or 0, y or 0}}
end

local GROUP_PRIVATE_DEFAULT = {
    Enabled=true,
    Size=32,
    Num=1,
    Layout={"CENTER", "CENTER", 0, 0},
    InitialAnchor="CENTER",
    GrowthX="LEFT",
    GrowthY="UP",
    Spacing=1,
    DisableCooldown=false,
    DisableCooldownText=false,
}

local GROUP_INDICATOR_DEFAULTS = {
    party={
        RaidTargetMarker=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        LeaderAssistantIndicator=Indicator(false, 16, "RIGHT", "TOPRIGHT", -3, 0),
        Role=Merge({ShowTank=true, ShowHealer=true, ShowDamager=true, Texture="White"},
            Indicator(true, 16, "TOPLEFT", "TOPLEFT", 1, 0)),
        Phase=Indicator(false, 16, "CENTER", "CENTER", 0, 0),
        Summon=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        ReadyCheckIndicator=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        ResurrectIndicator=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        Target={Enabled=false, Style="Glow", Colour={1, 1, 1, 1}},
        Threat={Enabled=false},
    },
    raid={
        RaidTargetMarker=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        LeaderAssistantIndicator=Indicator(false, 14, "TOPRIGHT", "TOPRIGHT", -3, -3),
        Role=Merge({ShowTank=true, ShowHealer=true, ShowDamager=false, Texture="White"},
            Indicator(false, 12, "TOPRIGHT", "TOPRIGHT", -3, -3)),
        Phase=Indicator(false, 12, "CENTER", "CENTER", 0, 0),
        Summon=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        ReadyCheckIndicator=Indicator(true, 24, "CENTER", "CENTER", 0, 0),
        ResurrectIndicator=Indicator(true, 18, "CENTER", "CENTER", 0, 0),
        Target={Enabled=false, Style="Glow", Colour={1, 1, 1, 1}},
        Threat={Enabled=false},
    },
}

local GROUP_SPECS = {
    party={
        width=252, height=52, layout={"CENTER","CENTER",-550.1,-0.1,1}, growth="DOWN", sort="ROLE", showPlayer=false,
        tags={Tag("[name]","TOPLEFT","TOPLEFT",16,-3),Tag("[perhp-with-sign]","TOPRIGHT","TOPRIGHT",-3,-3),Tag(),Tag(),Tag()},
        buffs=AuraLane(true,30,{"BOTTOMLEFT","BOTTOMLEFT",1,1,1},3,3,"RIGHT","UP","Health"),
        debuffs=AuraLane(true,30,{"BOTTOMRIGHT","BOTTOMRIGHT",-1,1,1},3,3,"LEFT","UP","Health",true),
        private=GROUP_PRIVATE_DEFAULT,
        indicators=GROUP_INDICATOR_DEFAULTS.party,
    },
    raid={
        width=90, height=52, layout={"LEFT","LEFT",1.1,0.1,1}, growth="LEFT_DOWN", sort="GROUP", showPlayer=true,
        groups={true,true,true,true,true,true,false,false},
        tags={Tag("[name]","TOPLEFT","TOPLEFT",3,-3),Tag("[status]","TOPRIGHT","TOPRIGHT",-3,-3),Tag(),Tag(),Tag()},
        buffs=AuraLane(true,30,{"BOTTOMLEFT","BOTTOMLEFT",1,1,1},1,1,"RIGHT","UP","Health"),
        debuffs=AuraLane(true,28,{"BOTTOMRIGHT","BOTTOMRIGHT",-1,1,-1},2,2,"LEFT","UP","Health",true),
        private=GROUP_PRIVATE_DEFAULT,
        indicators=GROUP_INDICATOR_DEFAULTS.raid,
    },
}

local UNIT_ORDER = {"player", "targettarget", "target", "focus", "focustarget", "pet", "boss"}
local GROUP_ORDER = {"party", "raid"}
local TAG_KEYS = {"TagOne", "TagTwo", "TagThree", "TagFour", "TagFive"}

local DEFAULT_GENERAL = {
    Separator="•",
    ToTSeparator="»",
    UseCustomAbbreviations=true,
    UIScale={Enabled=true, Scale=0.53333333333333},
    Textures={Foreground="Better Blizzard", Background="Better Blizzard"},
    Range={Enabled=true, InRange=1, OutOfRange=0.5},
    Fonts={Font="Friz Quadrata TT", FontFlag="OUTLINE, SLUG", Shadow={Enabled=false, Colour={0,0,0,1}, XPos=0, YPos=0}},
    CooldownText={Advanced=false, Layout={"CENTER","CENTER",0,0}, FontSize=12, ScaleByIconSize=false, CooldownBreakpoints={}},
    Colours={
        Reaction={
            [1]={1,0.25098040699959,0.25098040699959}, [2]={1,0.25098040699959,0.25098040699959},
            [3]={1,0.50196081399918,0.25098040699959}, [4]={1,1,0.25098040699959},
            [5]={0.25098040699959,1,0.25098040699959}, [6]={0.25098040699959,1,0.25098040699959},
            [7]={0.25098040699959,1,0.25098040699959}, [8]={0.25098040699959,1,0.25098040699959},
        },
        Power={
            [0]={0.25098040699959,0.50196081399918,1}, [1]={1,0,0}, [2]={1,0.5,0.25},
            [3]={1,1,0}, [6]={0,0.82,1}, [8]={0.75,0.52,0.9}, [11]={0,0.5,1},
            [13]={0.4,0,0.8}, [17]={0.79,0.26,0.99}, [18]={1,0.61,0},
        },
        SecondaryPower={
            [4]={1,0.96,0.41}, [5]={0.5,0.5,0.5}, [7]={0.58,0.51,0.79},
            [9]={0.95,0.9,0.6}, [12]={0.71,1,0.92}, [16]={0.41,0.8,0.94},
            [19]={0.3921568627451,0.67843137254902,0.8078431372549},
        },
        Dispel={
            Magic={0.2,0.6,1}, Curse={0.6,0,1}, Disease={0.6,0.4,0},
            Poison={0,0.6,0}, Bleed={0.6,0,0.1},
        },
        Status={Tapped={0.6,0.6,0.6}, Disconnected={0.6,0.6,0.6}, DeadBackdrop={1,0.25,0.25}},
        Threat={[0]={0.69,0.69,0.69}, [1]={1,1,0.47}, [2]={1,0.6,0}, [3]={1,0,0}},
    },
}

local POWER_TOKENS = {
    [0]="MANA", [1]="RAGE", [2]="FOCUS", [3]="ENERGY", [6]="RUNIC_POWER",
    [8]="LUNAR_POWER", [11]="MAELSTROM", [13]="INSANITY", [17]="FURY", [18]="PAIN",
}

local SECONDARY_TOKENS = {
    [4]="COMBO_POINTS", [5]="RUNES", [7]="SOUL_SHARDS", [9]="HOLY_POWER",
    [12]="CHI", [16]="ARCANE_CHARGES", [19]="ESSENCE",
}

local UUF_ONLY_STATUSBAR = {
    dragonflight=true, skyline=true, stripes=true, ["thin stripes"]=true,
}

local UUF_FONT_MAP = {
    ["friz quadrata tt"]="FRIZQT",
    ["friz quadrata (default)"]="FRIZQT",
    ["arial narrow"]="ARIALN",
    ["arial (default)"]="ARIALN",
    morpheus="MORPHEUS",
    skurri="SKURRI",
    expressway="EXPRESSWAY",
}

local UUF_PRIVATE_FONTS = {
    avante=true,
    ["avantgarde (book)"]=true,
    ["avantgarde (book oblique)"]=true,
    ["avantgarde (demi)"]=true,
    ["avantgarde (regular)"]=true,
}

local function SafeMedia(value, fallback, report, label, mediaType)
    if type(value) ~= "string" or value == "" then return fallback end
    local normalized = value:gsub("/", "\\"):lower():match("^%s*(.-)%s*$")
    if normalized:find("interface\\addons\\unhaltedunitframes", 1, true) then
        Mark(report, "approximated", label .. ": UUF-bundled media replaced with " .. tostring(fallback))
        return fallback
    end
    if mediaType == "statusbar" and UUF_ONLY_STATUSBAR[normalized] then
        Mark(report, "approximated", label .. ": UUF-only texture " .. value .. " replaced with " .. tostring(fallback))
        return fallback
    end
    if mediaType == "font" then
        if UUF_FONT_MAP[normalized] then return UUF_FONT_MAP[normalized] end
        if UUF_PRIVATE_FONTS[normalized] then
            Mark(report, "approximated", label .. ": UUF-only font " .. value .. " replaced with " .. tostring(fallback))
            return fallback
        end
    end
    return value
end

local function MapAnchorParent(value)
    if type(value) ~= "string" or value == "" or value == "UIParent" or value == "WorldFrame" then
        return nil, "GLOBAL"
    end
    local token = value:gsub("^UUF_", ""):gsub("^UnhaltedUnitFrames_", ""):gsub("Frame$", ""):lower()
    local map = {
        player="player", target="target", targettarget="targettarget", targetoftarget="targettarget", tot="targettarget",
        focus="focus", focustarget="focustarget", focus_target="focustarget", pet="pet", boss="boss",
        party="gf_party", raid="gf_raid",
    }
    if map[token] then return nil, map[token] end
    return value, "GLOBAL"
end

local function RoleOrder(value)
    local out = {}
    local seen = {}

    local function Add(role)
        role = type(role) == "string" and role:upper() or nil
        if role == "DPS" then role = "DAMAGER" end
        if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" and role ~= "NONE" then return end
        if seen[role] then return end
        seen[role] = true
        out[#out + 1] = role
    end

    if type(value) == "table" then
        local defaults = {"TANK", "HEALER", "DAMAGER"}
        for i = 1, 3 do Add(value[i] or defaults[i]) end
    elseif type(value) == "string" then
        for role in value:gmatch("[^,%s]+") do Add(role) end
    end
    Add("TANK")
    Add("HEALER")
    Add("DAMAGER")
    return table.concat(out, ",")
end

local function PointSlot(point)
    point = Anchor(point, "CENTER")
    if point:find("LEFT", 1, true) then return "Left" end
    if point:find("RIGHT", 1, true) then return "Right" end
    return "Center"
end

-- Convert a UUF FontString point/relativePoint pair into the offset expected
-- by one of MSUF's fixed native text anchors. The source region is expressed
-- in frame-centered coordinates; nativeCenter describes MSUF's target region
-- (for example the health region above a group power bar).
local function FoldAnchor(layout, frameWidth, frameHeight, fontSize, nativeSelf, nativeRelative,
    nativeWidth, nativeHeight, nativeCenterX, nativeCenterY, padX, padY)
    layout = Layout(layout)
    frameWidth = SafeNumber(frameWidth, 1, 1, 4096)
    frameHeight = SafeNumber(frameHeight, 1, 1, 4096)
    nativeWidth = SafeNumber(nativeWidth, frameWidth, 1, 4096)
    nativeHeight = SafeNumber(nativeHeight, frameHeight, 1, 4096)
    fontSize = SafeNumber(fontSize, 12, 1, 256)

    local sourceSelfX, sourceSelfY = Fraction(layout[1])
    local sourceRelativeX, sourceRelativeY = Fraction(layout[2])
    local nativeSelfX, nativeSelfY = Fraction(nativeSelf)
    local nativeRelativeX, nativeRelativeY = Fraction(nativeRelative)

    local desiredX = sourceRelativeX * frameWidth + layout[3] - sourceSelfX * fontSize
    local desiredY = sourceRelativeY * frameHeight + layout[4] - sourceSelfY * fontSize
    local nativeX = (nativeCenterX or 0) + nativeRelativeX * nativeWidth - nativeSelfX * fontSize
    local nativeY = (nativeCenterY or 0) + nativeRelativeY * nativeHeight - nativeSelfY * fontSize
    return desiredX - nativeX - (padX or 0), desiredY - nativeY - (padY or 0)
end

local function ParseTag(token)
    if type(token) ~= "string" or token == "" then return nil end
    local inner = token:match("^%[([^%[%]]+)%]%%?$")
    if not inner then return "composite", nil, {token=token} end
    inner = inner:lower()

    if inner == "status" then return "status" end
    if inner:match("^name:target") then
        return "targetname", nil, {
            dynamic=inner:find(":colour", 1, true) ~= nil,
            maxChars=SafeNumber(inner:match(":short:(%d+)"), nil, 1, 25),
        }
    end
    if inner == "name" or inner == "name:colour" then
        return "name", nil, {dynamic=inner:find(":colour", 1, true) ~= nil}
    end
    local nameChars = inner:match("^name:short:(%d+)")
    if nameChars then
        return "name", nil, {
            dynamic=inner:find(":colour", 1, true) ~= nil,
            maxChars=SafeNumber(nameChars, 6, 1, 25),
        }
    end
    if inner:match("^absorbs") then return "absorbs" end

    if inner == "curhp" or inner == "curhp:abbr" then
        return "health", "CURRENT", {abbreviated=inner:find(":abbr", 1, true) ~= nil}
    end
    if inner:match("^maxhp") then
        return "health", "MAX", {
            abbreviated=inner:find(":abbr", 1, true) ~= nil,
            dynamic=inner:find(":colour", 1, true) ~= nil,
        }
    end
    if inner == "missinghp" then return "health", "DEFICIT", {missing=true} end
    if inner:match("^perhp") then
        return "health", "PERCENT", {
            precision=SafeNumber(inner:match(":([123])$"), 0, 0, 3),
            sign=inner:find("with%-sign") ~= nil,
        }
    end
    if inner:match("^curhpperhp") then
        return "health", "CURPERCENT", {
            precision=SafeNumber(inner:match(":([123])$"), 0, 0, 3),
            abbreviated=inner:find(":abbr", 1, true) ~= nil,
        }
    end

    if inner:match("^curpp:manapercent") then
        return "power", "PERCENT", {
            conditional=inner:find(":healer", 1, true) == nil,
            healer=inner:find(":healer", 1, true) ~= nil,
            dynamic=inner:find(":colour", 1, true) ~= nil,
            precision=SafeNumber(inner:match(":([123])$"), 0, 0, 3),
        }
    end
    if inner == "curpp" or inner:match("^curpp:") then
        return "power", "CURRENT", {
            abbreviated=inner:find(":abbr", 1, true) ~= nil,
            dynamic=inner:find(":colour", 1, true) ~= nil,
        }
    end
    if inner == "maxpp" or inner:match("^maxpp:") then
        return "power", "MAX", {
            abbreviated=inner:find(":abbr", 1, true) ~= nil,
            dynamic=inner:find(":colour", 1, true) ~= nil,
        }
    end
    if inner == "missingpp" then return "power", nil, {missing=true} end
    if inner:match("^perpp") then
        return "power", "PERCENT", {precision=SafeNumber(inner:match(":([123])$"), 0, 0, 3)}
    end
    return nil
end

local function ParseComposite(token)
    local prefix, remainder = token:match("^%[([^%[%]]+)%](.+)$")
    local colorPrefix = prefix and prefix:lower()
    if colorPrefix == "powercolor" or colorPrefix == "raidcolor" or colorPrefix == "reactioncolour" then
        local kind, mode, meta = ParseTag(remainder)
        if kind == "composite" then kind, mode, meta = ParseComposite(remainder) end
        if kind and kind ~= "composite" then
            meta = meta or {}
            if kind == "name_health" then
                if not meta.nameToken:lower():find(":colour", 1, true) then
                    meta.nameToken = meta.nameToken .. ":colour"
                end
            elseif kind == "name_target_inline" then
                meta.name = meta.name or {}
                meta.target = meta.target or {}
                meta.name.dynamic = true
                meta.target.dynamic = true
            else
                meta.dynamic = true
            end
            return kind, mode, meta
        end
    end

    local first, literal, second = token:match("^%[([^%[%]]+)%](.-)%[([^%[%]]+)%]%%?$")
    if not first then return nil end
    local firstKind, firstMode, firstMeta = ParseTag("[" .. first .. "]")
    local secondKind, secondMode, secondMeta = ParseTag("[" .. second .. "]")
    colorPrefix = first:lower()
    if (colorPrefix == "powercolor" or colorPrefix == "raidcolor" or colorPrefix == "reactioncolour")
        and literal == "" and secondKind
    then
        secondMeta = secondMeta or {}
        secondMeta.dynamic = true
        return secondKind, secondMode, secondMeta
    end
    if firstKind == "health" and secondKind == "health" then
        if firstMode == "CURRENT" and secondMode == "PERCENT" then
            return "health", "CURPERCENT", {composite=true, separator=literal}
        end
    end
    if firstKind == "name" and secondKind == "health" then
        return "name_health", nil, {
            nameToken=first,
            healthToken=second,
            separator=literal,
            nameFirst=true,
        }
    end
    if firstKind == "health" and secondKind == "name" then
        return "name_health", nil, {
            nameToken=second,
            healthToken=first,
            separator=literal,
            nameFirst=false,
        }
    end
    if firstKind == "name" and secondKind == "targetname" and literal:match("^%s*$") then
        return "name_target_inline", nil, {name=firstMeta, target=secondMeta}
    end
    return "composite", nil, {token=token}
end

local function StripLegacyImportFields(root, seen)
    if type(root) ~= "table" then return end
    seen = seen or {}
    if seen[root] then return end
    seen[root] = true
    for key, value in pairs(root) do
        local lower = type(key) == "string" and key:lower() or ""
        if lower:match("^uuf") or lower:match("^_uuf") then
            root[key] = nil
        elseif type(value) == "table" then
            StripLegacyImportFields(value, seen)
        end
    end
end

local function CopyGeneral(source, out, report)
    local src = Merge(source, DEFAULT_GENERAL)
    local general = type(out.general) == "table" and out.general or {}
    out.general = general
    out.bars = type(out.bars) == "table" and out.bars or {}

    local uiScaleEnabled = src.UIScale.Enabled == true
    local uiScaleValue = SafeNumber(src.UIScale.Scale, 0.53333333333333, 0.3, 1.5)
    general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
    general.UIScale.Enabled = uiScaleEnabled
    general.UIScale.Scale = uiScaleValue
    general.globalUiScalePreset = uiScaleEnabled and "custom" or "auto"
    general.globalUiScaleValue = uiScaleEnabled and uiScaleValue or nil
    general.msufUiScale = 1

    general.barTexture = SafeMedia(src.Textures.Foreground, "Better Blizzard", report, "general texture", "statusbar")
    general.barBackgroundTexture = SafeMedia(src.Textures.Background, general.barTexture, report, "general background texture", "statusbar")
    general.castbarTexture = general.barTexture
    general.castbarBackgroundTexture = general.barBackgroundTexture
    general.fontKey = SafeMedia(src.Fonts.Font, "FRIZQT", report, "general font", "font")

    local rawFlag = type(src.Fonts.FontFlag) == "string" and src.Fonts.FontFlag:upper() or ""
    local compactFlag = rawFlag:gsub("[%s,_%-]", "")
    general.noOutline = compactFlag:find("OUTLINE", 1, true) == nil
    general.boldText = compactFlag:find("THICKOUTLINE", 1, true) ~= nil
    general.fontMonochrome = nil
    if compactFlag:find("MONOCHROME", 1, true) then
        Mark(report, "skipped", "general font: UUF MONOCHROME font flag has no native MSUF 5.7 equivalent")
    end
    if rawFlag:find("SLUG", 1, true) then
        Mark(report, "skipped", "general font: UUF SLUG font flag has no native MSUF 5.7 equivalent")
    end

    local shadow = src.Fonts.Shadow
    local shadowColor = Color(shadow.Colour, {0,0,0,1})
    local shadowX = SafeNumber(shadow.XPos, 0, -32, 32)
    local shadowY = SafeNumber(shadow.YPos, 0, -32, 32)
    general.textBackdrop = shadow.Enabled == true
    general.fontShadowStrength = nil
    if shadow.Enabled == true then
        if shadowColor[1] ~= 0 or shadowColor[2] ~= 0 or shadowColor[3] ~= 0
            or shadowColor[4] ~= 1 or shadowX ~= 1 or shadowY ~= -1
        then
            Mark(report, "approximated", "general font: arbitrary UUF shadow RGBA/offset uses the nearest native shadow preset")
        end
    end

    local rangeEnabled = src.Range.Enabled ~= false
    local rangeInAlpha = SafeNumber(src.Range.InRange, 1, 0, 1)
    local rangeOutAlpha = SafeNumber(src.Range.OutOfRange, 0.5, 0, 1)
    local rangeFadeAlpha = rangeOutAlpha
    if rangeInAlpha > 0 then
        rangeFadeAlpha = rangeOutAlpha / rangeInAlpha
        if rangeFadeAlpha > 1 then rangeFadeAlpha = 1 end
    elseif rangeOutAlpha > 0 then
        rangeFadeAlpha = 1
        Mark(report, "approximated", "general range: native range fade cannot make an invisible in-range frame brighter out of range")
    end

    general.rangeFadeEnabled = rangeEnabled
    general.rangeFadeAlpha = rangeFadeAlpha
    general.rangeFadePortrait = true
    report._rangeEnabled = rangeEnabled
    report._rangeInAlpha = rangeInAlpha
    report._rangeOutAlpha = rangeOutAlpha

    general.hpTextSeparator = tostring(src.Separator or "•"):gsub("||", "|")
    general.powerTextSeparator = general.hpTextSeparator
    general.useShortNumbers = src.UseCustomAbbreviations ~= false
    Mark(report, "approximated", "general numbers: UUF custom breakpoints/Blizzard-short mode uses the closest native abbreviation toggle")

    out.targettarget = type(out.targettarget) == "table" and out.targettarget or {}
    out.targettarget.showToTInTargetName = false
    out.targettarget.totInlineColorMode = "AUTO"
    local toTSeparator = tostring(src.ToTSeparator or "»")
    local toTPresets = { [" "]=true, ["-"]=true, ["/"]=true, ["\\"]=true, ["|"]=true }
    if toTPresets[toTSeparator] then
        out.targettarget.totInlineSeparator = toTSeparator
        out.targettarget.totInlineCustomSeparator = ""
    else
        out.targettarget.totInlineSeparator = "__CUSTOM__"
        out.targettarget.totInlineCustomSeparator = toTSeparator
    end

    out.npcColors = {}
    local reactions = src.Colours.Reaction or {}
    local reactionMap = {
        enemy=reactions[2] or reactions[1],
        neutral=reactions[4] or reactions[3],
        friendly=reactions[5] or reactions[6],
    }
    for key, value in pairs(reactionMap) do
        local color = Color(value)
        if color then out.npcColors[key] = {r=color[1], g=color[2], b=color[3]} end
    end
    if out.npcColors.enemy then out.npcColors.dead = DeepCopy(out.npcColors.enemy) end
    out.classColors = {}
    Mark(report, "approximated", "general reactions: eight UUF reaction colors collapse to native enemy/neutral/friendly colors")

    general.powerColorOverrides = {}
    for index, value in pairs(src.Colours.Power or {}) do
        local color = Color(value)
        local token = POWER_TOKENS[tonumber(index)]
        if color and token then
            general.powerColorOverrides[token] = {r=color[1], g=color[2], b=color[3]}
        end
    end

    general.classPowerColorOverrides = {}
    for index, value in pairs(src.Colours.SecondaryPower or {}) do
        local color = Color(value)
        local token = SECONDARY_TOKENS[tonumber(index)]
        if color and token then
            general.classPowerColorOverrides[token] = {r=color[1], g=color[2], b=color[3]}
        end
    end

    local dispel = src.Colours.Dispel or {}
    local dispelKeys = {
        Magic="dispelTypeMagic", Curse="dispelTypeCurse", Disease="dispelTypeDisease",
        Poison="dispelTypePoison", Bleed="dispelTypeBleed",
    }
    for sourceKey, targetKey in pairs(dispelKeys) do
        SetRGB(general, targetKey, dispel[sourceKey])
    end
    general.hlDispelColorMode = "TYPE"
    SetRGB(general, "hlAggroColor", src.Colours.Threat and (src.Colours.Threat[3] or src.Colours.Threat[2]))
    if type(src.Colours.Threat) == "table" and next(src.Colours.Threat) then
        Mark(report, "approximated", "general threat: four UUF threat-state colors use one native aggro color")
    end
    if type(src.Colours.Status) == "table" and next(src.Colours.Status) then
        Mark(report, "skipped", "general status: custom UUF tapped/disconnected/dead-backdrop bar colors are unavailable natively")
    end

    general.useBarBorder = true
    general.barOutlineColorR = 0
    general.barOutlineColorG = 0
    general.barOutlineColorB = 0
    general.enableGradient = false
    general.enablePowerGradient = false
    out.bars.showBarBorder = true
    out.bars.barOutlineThickness = 1
    out.bars.powerBarBorderEnabled = true
    out.bars.powerBarBorderThickness = 1
    out.bars.powerBarBorderSize = 1
    out.bars.roundedFramesEnabled = false

    local cooldown = Merge(src.CooldownText, DEFAULT_GENERAL.CooldownText)
    if cooldown.Advanced == true or type(cooldown.CooldownBreakpoints) == "table" then
        Mark(report, "approximated", "general cooldown text: UUF breakpoints use native cooldown formatting")
    end

    Mark(report, "mapped", "general appearance, scale, media, range and colors")
    Mark(report, "families", "general")
    return src
end

local function SourceUnitSize(unitKey, sources)
    local parentSpec = UNIT_SPECS[unitKey]
    if not parentSpec then return nil, nil end
    local parentSource = type(sources) == "table" and sources[unitKey] or nil
    local parentFrame = type(parentSource) == "table" and parentSource.Frame or nil
    parentFrame = type(parentFrame) == "table" and parentFrame or {}
    return SafeNumber(parentFrame.Width, parentSpec.width, 20, 1200),
        SafeNumber(parentFrame.Height, parentSpec.height, 3, 600)
end

local function ConvertFrameGeometry(unitKey, source, spec, dst, report, sources)
    local frame = type(source.Frame) == "table" and source.Frame or {}
    local layout = Layout(frame.Layout, spec.layout)
    dst.enabled = Bool(source.Enabled, spec.enabled)
    dst.width = SafeNumber(frame.Width, spec.width, 20, 1200)
    dst.height = SafeNumber(frame.Height, spec.height, 3, 600)
    dst.point = nil
    dst.relativePoint = nil
    dst.offsetX = layout[3]
    dst.offsetY = layout[4]
    dst.anchorFrameName = nil
    dst.anchorToUnitframe = "GLOBAL"

    local health = type(source.HealthBar) == "table" and source.HealthBar or {}
    local cooldown = health.AnchorToCooldownViewer
    if cooldown == nil then cooldown = spec.cooldown end
    if cooldown == true and (unitKey == "player" or unitKey == "target") then
        local baseX = unitKey == "player" and -20 or 20
        dst.anchorFrameName = "EssentialCooldownViewer"
        dst.offsetX = layout[3] - baseX
        local expectedPoint = unitKey == "player" and "RIGHT" or "LEFT"
        local expectedRelative = unitKey == "player" and "LEFT" or "RIGHT"
        if layout[1] ~= expectedPoint or layout[2] ~= expectedRelative then
            Mark(report, "approximated", unitKey .. ": non-standard cooldown-viewer anchor uses the native ECV rule")
        end
    else
        local custom, unit = MapAnchorParent(frame.AnchorParent or spec.parent)
        dst.anchorFrameName = custom
        dst.anchorToUnitframe = unit or "GLOBAL"

        local selfX, selfY = Fraction(layout[1])
        local relativeX, relativeY = Fraction(layout[2])
        local parentWidth, parentHeight = SourceUnitSize(unit, sources)
        dst.offsetX = layout[3] - selfX * dst.width
        dst.offsetY = layout[4] - selfY * dst.height
        if parentWidth and parentHeight then
            dst.offsetX = dst.offsetX + relativeX * parentWidth
            dst.offsetY = dst.offsetY + relativeY * parentHeight
        elseif relativeX ~= 0 or relativeY ~= 0 then
            Mark(
                report,
                "approximated",
                unitKey .. ": non-center UUF point on an unknown-size anchor uses the native anchor center"
            )
        end
    end

    if frame.FrameStrata and FrameStrata(frame.FrameStrata, "LOW") ~= "LOW" then
        Mark(report, "skipped", unitKey .. ": UUF frame strata is unavailable in the native unit-frame schema")
    end

    if unitKey == "boss" then
        local gap = SafeNumber(layout[5], spec.layout[5], 0, 200)
        local total = (dst.height + gap) * 5 - gap
        local point = layout[1]
        local multiplier = point:find("BOTTOM", 1, true) and 1
            or ((point == "CENTER" or point == "LEFT" or point == "RIGHT") and 0.5 or 0)
        local firstY = total * multiplier
        if multiplier == 0.5 then firstY = firstY - dst.height * 0.5 end
        local growsUp = type(frame.GrowthDirection) == "string" and frame.GrowthDirection:upper() == "UP"
        if growsUp then firstY = firstY - 4 * (dst.height + gap) end
        dst.offsetY = layout[4] + firstY
        dst.spacing = -(dst.height + gap)
        dst.bossLayoutMode = growsUp and "VERTICAL_UP" or "VERTICAL_DOWN"
    end
end

local UNIT_VISUAL_RESET = {
    loadCondActive=false,
    showLevelIndicator=false,
    showRaidGroupInName=false,
    statusTextEnabled=false,
    showIncomingResIndicator=false,
    showClassificationIndicator=false,
    showEliteIcon=false,
    showCombatStateIndicator=false,
    showRestingIndicator=false,
    showLeaderIcon=false,
    showRaidMarker=false,
    bossTargetOutlineMode=0,
    aggroOutlineMode=0,
    hlAggroEnabled=false,
    powerBarDetached=false,
    embedPowerBarIntoHealth=true,
    detachedPowerBarAnchorToClassPower=false,
    portraitShape="SQUARE",
    portraitBorderStyle="SOLID",
    portraitBorderThickness=1,
    portraitBorderColorR=0,
    portraitBorderColorG=0,
    portraitBorderColorB=0,
    portraitBorderColorA=1,
    portraitFillBorder=false,
    portraitBgEnabled=false,
}

local function ApplyHealthAndPower(unitKey, source, spec, dst, out, report)
    local health = Merge(source.HealthBar, DEFAULT_HEALTH)
    local powerDefaults = DeepCopy(DEFAULT_POWER)
    powerDefaults.Enabled = spec.power == true
    powerDefaults.Height = spec.powerHeight or 3
    powerDefaults.Position = spec.powerPosition or "BOTTOM"
    local power = Merge(source.PowerBar, powerDefaults)

    local healthForegroundAlpha = SafeNumber(health.ForegroundOpacity, 1, 0, 1)
    local healthBackgroundAlpha = SafeNumber(health.BackgroundOpacity, 1, 0, 1)
    local rangeInAlpha = 1
    if unitKey ~= "player" and report._rangeEnabled == true then
        rangeInAlpha = SafeNumber(report._rangeInAlpha, 1, 0, 1)
    end

    dst.reverseFillBars = health.Inverse == true
    dst.smoothFill = health.Smooth == true

    -- UUF health opacity is static. Reset every native alpha key so values from
    -- the selected MSUF base profile cannot leak into the converted profile.
    -- Only enable MSUF's layered alpha path when the UUF health fill actually
    -- needs it; the normal path keeps UUF's whole-frame range fade intact.
    dst.alphaInCombat = rangeInAlpha
    dst.alphaOutOfCombat = rangeInAlpha
    dst.alphaSync = true
    dst.alphaSyncBoth = true
    dst.alphaExcludeTextPortrait = healthForegroundAlpha ~= 1
    dst.alphaLayerMode = healthForegroundAlpha ~= 1 and 2 or 0
    dst.alphaFGInCombat = rangeInAlpha
    dst.alphaFGOutOfCombat = rangeInAlpha
    dst.alphaBGInCombat = rangeInAlpha
    dst.alphaBGOutOfCombat = rangeInAlpha
    dst.alphaHPInCombat = healthForegroundAlpha * rangeInAlpha
    dst.alphaHPOutOfCombat = dst.alphaHPInCombat
    dst.alphaPreserveHPColor = false

    local general = out.general
    local baseline = report._unitHealthBaseline
    if not baseline then
        baseline = {
            label=unitKey,
            class=health.ColourByClass ~= false,
            foreground=DeepCopy(health.Foreground),
            background=DeepCopy(health.Background),
            foregroundAlpha=healthForegroundAlpha,
            backgroundAlpha=healthBackgroundAlpha,
        }
        report._unitHealthBaseline = baseline
        if baseline.class then
            general.barMode = "class"
            general.useClassColors = true
            general.darkMode = false
        else
            general.barMode = "unified"
            general.useClassColors = false
            general.darkMode = false
            SetRGB(general, "unifiedBar", health.Foreground)
        end
        SetRGB(general, "classBarBg", health.Background)
        out.bars.barBackgroundAlpha = healthBackgroundAlpha * 100
    elseif baseline.class ~= (health.ColourByClass ~= false)
        or not SameColor(baseline.foreground, health.Foreground)
        or not SameColor(baseline.background, health.Background)
        or baseline.foregroundAlpha ~= healthForegroundAlpha
        or baseline.backgroundAlpha ~= healthBackgroundAlpha
    then
        Mark(report, "approximated", unitKey .. ": per-unit UUF health colors/background opacity use the native " .. baseline.label .. " shared bar palette")
    end
    if healthForegroundAlpha ~= 1 and report._rangeEnabled == true
        and (rangeInAlpha ~= 1 or SafeNumber(report._rangeOutAlpha, rangeInAlpha, 0, 1) ~= rangeInAlpha)
    then
        Mark(report, "approximated", unitKey .. ": combined UUF health-fill opacity and range alpha use the closest native layered fade")
    end
    if health.ColourBackgroundByClass == true then
        Mark(report, "skipped", unitKey .. ": UUF class-colored health background is unavailable for native unit frames")
    end
    if health.ColourWhenTapped == false or health.ColourWhenDisconnected == false then
        Mark(report, "skipped", unitKey .. ": per-frame UUF tapped/disconnected health coloring is unavailable natively")
    end

    dst.showPowerBar = power.Enabled ~= false
    dst.powerBarHeight = SafeNumber(power.Height, powerDefaults.Height, 1, 100)
    dst.powerSmoothFill = power.Smooth == true
    dst.powerBarBorderEnabled = true
    dst.powerBarBorderThickness = 1
    if power.Inverse == true ~= (health.Inverse == true) then
        Mark(report, "skipped", unitKey .. ": independent UUF health/power reverse-fill directions share one native direction")
    end
    if type(power.Position) == "string" and power.Position:upper() ~= "BOTTOM" and power.Enabled ~= false then
        Mark(report, "approximated", unitKey .. ": top-positioned UUF primary power uses the native bottom stack")
    end
    if power.ColourByType == false or power.ColourByClass == true then
        Mark(report, "approximated", unitKey .. ": static/class UUF power foreground uses native power-type colors")
    end
    if power.ColourBackgroundByType == true or not SameColor(power.Background, DEFAULT_POWER.Background) then
        Mark(report, "approximated", unitKey .. ": per-frame UUF power background uses the native shared power background")
    end

    if unitKey == "player" then
        local secondary = Merge(source.SecondaryPowerBar, DEFAULT_SECONDARY_POWER)
        local bars = out.bars
        bars.showClassPower = secondary.Enabled == true
        bars.classPowerHeight = SafeNumber(secondary.Height, 3, 1, 100)
        bars.classPowerColorByType = secondary.ColourByType ~= false
        bars.classPowerWidthMode = "player"
        bars.classPowerOffsetX = 0
        bars.classPowerOffsetY = 0
        bars.classPowerAnchorToCooldown = false
        bars.classPowerTickWidth = 1
        bars.classPowerOutline = 1
        bars.classPowerGap = 0
        bars.classPowerFillReverse = false
        bars.classPowerShowText = false
        bars.classPowerShowPrediction = false
        bars.classPowerHideOOC = false
        bars.classPowerHideWhenFull = false
        bars.classPowerHideWhenEmpty = false
        bars.classPowerFilledAlpha = 1
        bars.classPowerEmptyAlpha = 1
        bars.smoothPowerBar = false
        bars.showChargedComboPoints = false
        bars.runeShowTime = false
        local secondaryColor = Color(secondary.Foreground)
        local secondaryBg = Color(secondary.Background)
        if secondary.ColourByType == false and secondaryColor then
            for _, token in pairs(SECONDARY_TOKENS) do
                general.classPowerColorOverrides[token] = {r=secondaryColor[1], g=secondaryColor[2], b=secondaryColor[3]}
            end
        end
        if secondaryBg then
            general.classPowerBgColorOverrides = type(general.classPowerBgColorOverrides) == "table"
                and general.classPowerBgColorOverrides or {}
            for _, token in pairs(SECONDARY_TOKENS) do
                general.classPowerBgColorOverrides[token] = {r=secondaryBg[1], g=secondaryBg[2], b=secondaryBg[3]}
            end
            bars.classPowerBgAlpha = secondaryBg[4]
        end
        if secondary.Enabled == true and tostring(secondary.Position or "TOP"):upper() ~= "TOP" then
            Mark(report, "skipped", "player: bottom-positioned UUF secondary power uses native top placement")
        end

        local alt = Merge(source.AlternativePowerBar, DEFAULT_ALT_POWER)
        local altLayout = Layout(alt.Layout, DEFAULT_ALT_POWER.Layout)
        bars.showAltMana = alt.Enabled == true
        bars.altManaHeight = SafeNumber(alt.Height, 5, 2, 30)
        bars.altManaOffsetY = altLayout[4]
        local altColor = Color(alt.Foreground)
        if altColor then
            bars.altManaColorR, bars.altManaColorG, bars.altManaColorB = altColor[1], altColor[2], altColor[3]
            general.classPowerColorOverrides.MANA = {r=altColor[1], g=altColor[2], b=altColor[3]}
        end
        if alt.Enabled == true then
            if SafeNumber(alt.Width, 100) ~= dst.width - 4 or altLayout[1] ~= "TOPLEFT"
                or altLayout[2] ~= "BOTTOMLEFT" or altLayout[3] ~= 2
            then
                Mark(report, "approximated", "player: UUF alternative-power width/X/anchor uses the native player-width bottom bar")
            end
            if alt.Inverse == true then
                Mark(report, "skipped", "player: UUF alternative-power reverse fill is unavailable natively")
            end
            Mark(report, "skipped", "player: custom UUF alternative-power background color is fixed by the native bar")
        end
    end
    return health, power
end

local UNIT_SLOT_PAD = {Left=4, Center=0, Right=-4}
local UNIT_TOP_ANCHOR = {Left="TOPLEFT", Center="TOP", Right="TOPRIGHT"}
local UNIT_BOTTOM_ANCHOR = {Left="BOTTOMLEFT", Center="BOTTOM", Right="BOTTOMRIGHT"}

local function ResetUnitText(dst)
    Assign(dst, {
        showName=false,
        showHP=false,
        showHPText=false,
        showPower=false,
        showPowerText=false,
        textLeft="NONE",
        textCenter="NONE",
        textRight="NONE",
        powerTextLeft="NONE",
        powerTextCenter="NONE",
        powerTextRight="NONE",
        statusTextEnabled=false,
        fontOverride=true,
        nameClassColor=false,
        npcNameRed=false,
        colorPowerTextByType=false,
    })
    Clear(dst, {
        "hpTextLeftOffsetX", "hpTextLeftOffsetY", "hpTextCenterOffsetX", "hpTextCenterOffsetY",
        "hpTextRightOffsetX", "hpTextRightOffsetY", "powerTextLeftOffsetX", "powerTextLeftOffsetY",
        "powerTextCenterOffsetX", "powerTextCenterOffsetY", "powerTextRightOffsetX", "powerTextRightOffsetY",
    })
    dst.hpOffsetX, dst.hpOffsetY = 0, 0
    dst.powerOffsetX, dst.powerOffsetY = 0, 0
end

local function ApplyUnitStaticTagColor(tag, out, report, label)
    local color = Color(tag and tag.Colour, {1, 1, 1, 1})
    if not color then return end
    local baseline = report._fontColorBaseline
    if not baseline then
        baseline = {color[1], color[2], color[3], label=label}
        report._fontColorBaseline = baseline
        out.general.useCustomFontColor = true
        out.general.fontColorCustomR = color[1]
        out.general.fontColorCustomG = color[2]
        out.general.fontColorCustomB = color[3]
    elseif baseline[1] ~= color[1] or baseline[2] ~= color[2] or baseline[3] ~= color[3] then
        Mark(
            report,
            "approximated",
            label .. ": static UUF tag color shares the native global text color selected from " .. baseline.label
        )
    end
    if color[4] ~= 1 then
        Mark(report, "approximated", label .. ": UUF tag alpha is unavailable in the native text palette")
    end
end

local function ApplyUnitTag(dst, tag, unitKey, out, report)
    if type(tag) ~= "table" or type(tag.Tag) ~= "string" or tag.Tag == "" then return end
    local kind, mode, meta = ParseTag(tag.Tag)
    if kind == "composite" then kind, mode, meta = ParseComposite(tag.Tag) end
    local layout = Layout(tag.Layout)
    local fontSize = SafeNumber(tag.FontSize, 12, 6, 72)
    local slot = PointSlot(layout[1])
    local width, height = dst.width, dst.height

    if kind == "name_health" then
        local function SplitPoint(point, side)
            point = Anchor(point, "CENTER")
            if point:find("TOP", 1, true) then return "TOP" .. side end
            if point:find("BOTTOM", 1, true) then return "BOTTOM" .. side end
            return side
        end

        local nameLayout = {
            SplitPoint(layout[1], "LEFT"),
            SplitPoint(layout[2], "LEFT"),
            layout[3] + 3,
            layout[4],
        }
        local healthLayout = {
            SplitPoint(layout[1], "RIGHT"),
            SplitPoint(layout[2], "RIGHT"),
            layout[3] - 3,
            layout[4],
        }
        local nameTag = {
            Tag="[" .. meta.nameToken .. "]",
            FontSize=fontSize,
            Layout=nameLayout,
            Colour=tag.Colour,
        }
        local healthTag = {
            Tag="[" .. meta.healthToken .. "]",
            FontSize=fontSize,
            Layout=healthLayout,
            Colour=tag.Colour,
        }

        if meta.nameFirst == false then
            ApplyUnitTag(dst, healthTag, unitKey, out, report)
            ApplyUnitTag(dst, nameTag, unitKey, out, report)
        else
            ApplyUnitTag(dst, nameTag, unitKey, out, report)
            ApplyUnitTag(dst, healthTag, unitKey, out, report)
        end
        Mark(
            report,
            "approximated",
            unitKey .. ": combined UUF name/health text uses native left-name and right-HP slots"
        )
        return
    end

    if kind == "name_target_inline" and unitKey == "target" then
        local compositeMeta = meta
        kind, meta = "name", compositeMeta and compositeMeta.name or nil
        out.targettarget = type(out.targettarget) == "table" and out.targettarget or {}
        out.targettarget.showToTInTargetName = true
        out.targettarget.totInlineColorMode = compositeMeta and compositeMeta.target
            and compositeMeta.target.dynamic and "TOT_NAME" or "DEFAULT"
        Mark(report, "approximated", "target: UUF name/target-name composite uses native target-of-target inline text")
    end

    if kind == "name" then
        local nativeAnchor = UNIT_TOP_ANCHOR[slot]
        local x, y = FoldAnchor(layout, width, height, fontSize, nativeAnchor, nativeAnchor,
            width, height, 0, 0, 0, 0)
        dst.showName = true
        dst.nameTextAnchor = slot:upper()
        dst.nameOffsetX = slot == "Right" and -x or x
        dst.nameOffsetY = y
        dst.nameFontSize = fontSize
        if meta and meta.dynamic then
            dst.nameClassColor = true
            dst.npcNameRed = true
        else
            ApplyUnitStaticTagColor(tag, out, report, unitKey .. " name")
        end
        if meta and meta.maxChars then
            dst.shortenNames = true
            dst.nameShortenEnabled = true
            dst.shortenNameMaxChars = meta.maxChars
            dst.shortenNameShowDots = false
            Mark(report, "approximated", unitKey .. ": UUF character truncation uses native secret-safe width shortening")
        end
        Mark(report, "mapped", unitKey .. ": name tag and folded native position")
        return
    end

    if kind == "targetname" then
        if unitKey == "target" then
            out.targettarget = type(out.targettarget) == "table" and out.targettarget or {}
            out.targettarget.showToTInTargetName = true
            out.targettarget.totInlineColorMode = meta and meta.dynamic and "TOT_NAME" or "DEFAULT"
            if not (meta and meta.dynamic) then
                ApplyUnitStaticTagColor(tag, out, report, unitKey .. " target name")
            end
            Mark(report, "approximated", "target: standalone target-name tag uses native inline target-of-target text")
        else
            Mark(report, "skipped", unitKey .. ": target-name tag has no native unit-frame equivalent")
        end
        return
    end

    if kind == "status" then
        local nativeAnchor = Anchor(layout[1], "CENTER")
        local x, y = FoldAnchor(layout, width, height, fontSize, nativeAnchor, nativeAnchor,
            width, height, 0, 0, 0, 0)
        dst.statusTextEnabled = true
        dst.statusTextAnchor = nativeAnchor
        dst.statusTextOffsetX, dst.statusTextOffsetY = x, y
        dst.statusTextSize = fontSize
        ApplyUnitStaticTagColor(tag, out, report, unitKey .. " status")
        Mark(report, "approximated", unitKey .. ": UUF combined status tag uses native Dead/Ghost/Offline status text")
        return
    end

    if kind == "health" or kind == "power" then
        local power = kind == "power"
        if power and not mode then
            Mark(report, "skipped", unitKey .. ": UUF missing-power text has no native power-text mode")
            return
        end
        local anchorMap = power and UNIT_BOTTOM_ANCHOR or UNIT_TOP_ANCHOR
        local nativeAnchor = anchorMap[slot]
        local x, y = FoldAnchor(layout, width, height, fontSize, nativeAnchor, nativeAnchor,
            width, height, 0, 0, UNIT_SLOT_PAD[slot], 0)
        local modeKey = power and ("powerText" .. slot) or ("text" .. slot)
        local xKey = power and ("powerText" .. slot .. "OffsetX") or ("hpText" .. slot .. "OffsetX")
        local yKey = power and ("powerText" .. slot .. "OffsetY") or ("hpText" .. slot .. "OffsetY")
        if dst[modeKey] and dst[modeKey] ~= "NONE" then
            Mark(report, "approximated", unitKey .. ": multiple UUF tags share one native " .. slot:lower() .. " slot; the later tag wins")
        end
        dst[modeKey] = mode
        dst[xKey], dst[yKey] = x, y
        if power then
            dst.showPowerText = true
            dst.showPower = true
            dst.powerFontSize = fontSize
            if meta and meta.dynamic then dst.colorPowerTextByType = true end
        else
            dst.showHP = true
            dst.showHPText = true
            dst.hpFontSize = fontSize
        end
        if not (meta and meta.dynamic) then
            ApplyUnitStaticTagColor(tag, out, report, unitKey .. " " .. kind)
        end
        if meta and meta.precision and meta.precision ~= (power and 0 or 1) then
            Mark(report, "approximated", unitKey .. ": UUF percentage precision uses native fixed precision")
        end
        if meta and meta.missing then
            Mark(report, "approximated", unitKey .. ": UUF missing-value sign/abbreviation uses native deficit formatting")
        end
        if meta and (meta.conditional or meta.healer) then
            Mark(report, "approximated", unitKey .. ": conditional/healer-only UUF mana tag uses native displayed-power percent")
        end
        if meta and meta.composite and meta.separator and meta.separator ~= "" then
            dst.hpTextSeparator = tostring(meta.separator):gsub("||", "|")
        end
        Mark(report, "mapped", unitKey .. ": " .. kind .. " tag and folded native slot position")
        return
    end

    if kind == "absorbs" then
        Mark(report, "skipped", unitKey .. ": UUF absorb amount text has no native unit text slot")
    elseif kind == "composite" then
        Mark(report, "skipped", unitKey .. ": unsupported composite UUF tag " .. tostring(meta and meta.token or tag.Tag))
    else
        Mark(report, "skipped", unitKey .. ": unsupported UUF tag " .. tag.Tag)
    end
end

local ICON_SELF_POINT = {
    TOPLEFT="LEFT",
    TOPRIGHT="RIGHT",
    BOTTOMLEFT="LEFT",
    BOTTOMRIGHT="RIGHT",
}

local STATUS_ICON_INSET = {
    TOPLEFT={2, -2}, TOP={0, -2}, TOPRIGHT={-2, -2},
    LEFT={2, 0}, CENTER={0, 0}, RIGHT={-2, 0},
    BOTTOMLEFT={2, 2}, BOTTOM={0, 2}, BOTTOMRIGHT={-2, 2},
}
local UUF_CUSTOM_STATUS_ICON_SCALE = 2
local MAX_IMPORTED_STATUS_ICON_SIZE = 256

local function ApplyIcon(dst, source, fields, fallback, family)
    source = type(source) == "table" and source or fallback
    if type(source) ~= "table" then return false end
    local layout = Layout(source.Layout, fallback and fallback.Layout)
    local size = SafeNumber(source.Size, fallback and fallback.Size or 16, 8, 256)
    if family == "status" then
        size = math.min(size * UUF_CUSTOM_STATUS_ICON_SCALE, MAX_IMPORTED_STATUS_ICON_SIZE)
    end
    local sourcePointX, sourcePointY = Fraction(layout[1])
    local anchor = Anchor(layout[2])
    local nativePoint = family == "status" and anchor or (ICON_SELF_POINT[anchor] or anchor)
    local nativePointX, nativePointY = Fraction(nativePoint)
    local inset = family == "status" and STATUS_ICON_INSET[anchor] or nil
    dst[fields[1]] = source.Enabled ~= false
    dst[fields[2]] = size
    dst[fields[3]] = anchor
    dst[fields[4]] = layout[3] + (nativePointX - sourcePointX) * size - (inset and inset[1] or 0)
    dst[fields[5]] = layout[4] + (nativePointY - sourcePointY) * size - (inset and inset[2] or 0)
    if fields[6] then dst[fields[6]] = 7 end
    return source.Enabled ~= false
end

local DEFAULT_UNIT_INDICATORS = {
    RaidTargetMarker={Enabled=true, Size=24, Layout={"CENTER","CENTER",0,0}},
    LeaderAssistantIndicator={Enabled=false, Size=16, Layout={"TOPLEFT","TOPLEFT",3,-3}},
    Resting={Enabled=false, Size=16, Layout={"LEFT","TOPLEFT",3,0}},
    Combat={Enabled=false, Size=16, Layout={"CENTER","TOP",0,0}},
    Classification={Enabled=false, Size=24, Layout={"RIGHT","TOPRIGHT",-3,0}, Texture="CLASSIFICATION2"},
    Target={Enabled=false, Style="Border", Colour={1,1,1,1}},
    Threat={Enabled=false},
}

local UNIT_INDICATOR_OVERRIDES = {
    player={
        Totems={Enabled=false, Size=42, Layout={"RIGHT","LEFT",-1,0,1}, GrowthDirection="LEFT"},
    },
    target={
        LeaderAssistantIndicator={Enabled=false, Size=16, Layout={"TOPRIGHT","TOPRIGHT",-3,-3}},
        Classification={Enabled=true, Size=24, Layout={"RIGHT","TOPRIGHT",-3,0}, Texture="CLASSIFICATION2"},
        Quest={Enabled=true},
    },
    targettarget={
        RaidTargetMarker={Enabled=true, Size=16, Layout={"LEFT","TOPLEFT",3,0}},
    },
    focus={
        RaidTargetMarker={Enabled=true, Size=16, Layout={"RIGHT","RIGHT",-3,0}},
        Target={Enabled=true, Style="Border", Colour={1,1,1,1}},
    },
    focustarget={
        RaidTargetMarker={Enabled=true, Size=16, Layout={"LEFT","TOPLEFT",3,0}},
    },
    pet={
        RaidTargetMarker={Enabled=false, Size=16, Layout={"LEFT","TOPLEFT",3,0}},
    },
    boss={
        Target={Enabled=true, Style="Border", Colour={1,1,1,1}},
    },
}

local function ApplyUnitIndicators(dst, source, unitKey, out, report)
    local defaults = Merge(UNIT_INDICATOR_OVERRIDES[unitKey], DEFAULT_UNIT_INDICATORS)
    local indicators = Merge(source, defaults)
    ApplyIcon(dst, indicators.RaidTargetMarker,
        {"showRaidMarker","raidMarkerSize","raidMarkerAnchor","raidMarkerOffsetX","raidMarkerOffsetY","raidMarkerLayer"},
        defaults.RaidTargetMarker)
    ApplyIcon(dst, indicators.LeaderAssistantIndicator,
        {"showLeaderIcon","leaderIconSize","leaderIconAnchor","leaderIconOffsetX","leaderIconOffsetY","leaderIconLayer"},
        defaults.LeaderAssistantIndicator)
    ApplyIcon(dst, indicators.Resting,
        {"showRestingIndicator","restedStateIndicatorSize","restedStateIndicatorAnchor","restedStateIndicatorOffsetX","restedStateIndicatorOffsetY","restedStateIndicatorLayer"},
        defaults.Resting, "status")
    ApplyIcon(dst, indicators.Combat,
        {"showCombatStateIndicator","combatStateIndicatorSize","combatStateIndicatorAnchor","combatStateIndicatorOffsetX","combatStateIndicatorOffsetY","combatStateIndicatorLayer"},
        defaults.Combat, "status")

    dst.showClassificationIndicator = false
    local classification = indicators.Classification
    local eligible = unitKey == "target" or unitKey == "focus" or unitKey == "targettarget"
        or unitKey == "focustarget" or unitKey == "boss"
    if eligible and type(classification) == "table" then
        local enabled = ApplyIcon(dst, classification,
            {"showEliteIcon","eliteIconSize","eliteIconAnchor","eliteIconOffsetX","eliteIconOffsetY","eliteIconLayer"},
            defaults.Classification)
        if enabled then
            Mark(report, "approximated", unitKey .. ": UUF classification texture uses native gold/silver elite atlases")
        end
    end

    if type(indicators.Target) == "table" and indicators.Target.Enabled == true then
        if unitKey == "boss" then
            dst.hlOverride = true
            dst.bossTargetOutlineMode = 1
            local color = Color(indicators.Target.Colour)
            if color then out.general.bossTargetHighlightColor = {color[1], color[2], color[3]} end
        else
            Mark(report, "skipped", unitKey .. ": UUF current-target glow has no native unit-frame equivalent")
        end
    end
    if type(indicators.Threat) == "table" and indicators.Threat.Enabled == true then
        dst.hlOverride = true
        dst.aggroOutlineMode = 1
        dst.hlAggroEnabled = true
    end
    if type(indicators.PvP) == "table" and indicators.PvP.Enabled == true then
        Mark(report, "skipped", unitKey .. ": UUF PvP indicator has no native unit-frame equivalent")
    end
    if type(indicators.Quest) == "table" and indicators.Quest.Enabled == true then
        Mark(report, "skipped", unitKey .. ": UUF quest indicator has no native unit-frame equivalent")
    end
    if unitKey == "player" and type(indicators.Totems) == "table" then
        local totems = indicators.Totems
        local layout = Layout(totems.Layout, {"RIGHT","LEFT",-1,0,1})
        out.gameplay.enablePlayerTotems = totems.Enabled == true
        out.gameplay.playerTotemsIconSize = SafeNumber(totems.Size, 42, 8, 128)
        out.gameplay.playerTotemsAnchorFrom = layout[1]
        out.gameplay.playerTotemsAnchorTo = layout[2]
        out.gameplay.playerTotemsOffsetX, out.gameplay.playerTotemsOffsetY = layout[3], layout[4]
        out.gameplay.playerTotemsGrowth = tostring(totems.GrowthDirection or "LEFT"):upper()
    end
end

local function PredictionColor(value)
    local color = Color(value)
    if not color then return nil end

    local defaults = {
        {{0.25098039215686,1,0.25098039215686,1}, {0.25,1,0.25,1}},
        {{0.50196081399918,0.75294125080109,1,0.80000007152557}, {0.5,0.75,1,0.8}},
        {{0.50196078431373,0.25098039215686,1,1}, {0.5,0.25,1,1}},
    }
    for index = 1, #defaults do
        local serialized, canonical = defaults[index][1], defaults[index][2]
        if math.abs(color[1] - serialized[1]) < 0.002
            and math.abs(color[2] - serialized[2]) < 0.002
            and math.abs(color[3] - serialized[3]) < 0.002
            and math.abs(color[4] - serialized[4]) < 0.002
        then
            return canonical
        end
    end
    return color
end

local function ConvertHealPrediction(source, spec, dst, general, report, label, group)
    local defaults = DeepCopy(spec.healDefaults or DEFAULT_HEAL)
    defaults.IncomingHeal.Enabled = spec.heal[1]
    defaults.Absorbs.Enabled = spec.heal[2]
    defaults.HealAbsorbs.Enabled = spec.heal[3]
    local prediction = Merge(source, defaults)
    local incoming, absorb, healAbsorb = prediction.IncomingHeal, prediction.Absorbs, prediction.HealAbsorbs
    local function AnchorMode(position, over)
        position = tostring(position or ""):upper()
        if position == "ATTACH" then return over and 4 or 3 end
        return position:find("RIGHT", 1, true) and 2 or 1
    end
    dst.hlOverride = true
    dst.absorbTextMode = absorb.Enabled ~= false and 2 or 1
    dst.healPredAnchorMode = AnchorMode(incoming.Position)
    dst.absorbAnchorMode = AnchorMode(absorb.Position, absorb.ShowOverAbsorb == true)
    local incomingColor = PredictionColor(incoming.Colour)
    local absorbColor = PredictionColor(absorb.Colour)
        or PredictionColor(DEFAULT_HEAL.Absorbs.Colour)
    local healAbsorbColor = PredictionColor(healAbsorb.Colour)
        or PredictionColor(DEFAULT_HEAL.HealAbsorbs.Colour)
    dst.absorbBarOpacity = absorbColor[4]
    dst.healAbsorbBarOpacity = healAbsorbColor[4]
    if group then
        dst.healPredEnabled = incoming.Enabled == true
        dst.enableAbsorbBar = absorb.Enabled ~= false
        dst.healAbsorbEnabled = healAbsorb.Enabled ~= false
    end
    if not report._predictionSource and label == report._predictionPreferred then
        report._predictionSource = label
        general.enableHealPrediction = incoming.Enabled == true
        general.showSelfHealPrediction = incoming.Enabled == true
        general.enableAbsorbBar = absorb.Enabled ~= false
        general.healAbsorbEnabled = healAbsorb.Enabled ~= false
        general.healPredAnchorMode = dst.healPredAnchorMode
        general.absorbAnchorMode = dst.absorbAnchorMode
        general.absorbBarOpacity = dst.absorbBarOpacity
        general.healAbsorbBarOpacity = dst.healAbsorbBarOpacity
        SetRGB(general, "healPredColor", incomingColor)
        SetRGBA(general, "absorbBarColor", absorbColor)
        SetRGBA(general, "healAbsorbBarColor", healAbsorbColor)
    else
        Mark(report, "approximated", label .. ": UUF prediction colors share native global prediction colors")
    end
    for _, part in pairs({incoming, absorb, healAbsorb}) do
        if part.Enabled == true and part.UseStripedTexture == true then
            Mark(report, "skipped", label .. ": striped UUF prediction texture has no native equivalent")
        end
        if part.Enabled == true and part.MatchParentHeight == false then
            Mark(report, "approximated", label .. ": custom UUF prediction height uses native full-height prediction")
        end
    end
    Mark(report, "mapped", label .. ": heal prediction and absorbs")
end

local function ConvertPortrait(source, spec, dst, report, unitKey)
    local defaults = DeepCopy(DEFAULT_PORTRAIT)
    defaults.Width, defaults.Height = spec.portraitSize, spec.portraitSize
    defaults.Layout = DeepCopy(spec.portrait)
    local portrait = Merge(source, defaults)
    local layout = Layout(portrait.Layout, defaults.Layout)
    local left = layout[1]:find("RIGHT", 1, true) and layout[2]:find("LEFT", 1, true)
    dst.portraitMode = portrait.Enabled == true and (left and "LEFT" or "RIGHT") or "OFF"
    dst.portraitRender = portrait.UseClassPortrait == true and "CLASS" or "2D"
    dst.portraitClassStyle = "BLIZZARD"
    dst.portraitSizeOverride = SafeNumber(portrait.Size or portrait.Width or portrait.Height, spec.portraitSize, 1, 1200)
    dst.portraitOffsetX, dst.portraitOffsetY = layout[3], layout[4]
    if portrait.Enabled == true and (tostring(portrait.Style):upper() == "3D" or SafeNumber(portrait.Zoom, 0.3) ~= 0) then
        Mark(report, "approximated", unitKey .. ": UUF portrait style/zoom uses native 2D crop")
    end
    if portrait.Enabled == true and SafeNumber(portrait.Width, defaults.Width) ~= SafeNumber(portrait.Height, defaults.Height) then
        Mark(report, "approximated", unitKey .. ": rectangular UUF portrait uses native square portrait")
    end
end

local CAST_KEYS = {
    player={"enablePlayerCastbar","castbarPlayerBarWidth","castbarPlayerBarHeight","castbarPlayerOffsetX","castbarPlayerOffsetY","castbarPlayerMatchWidth","castbarPlayerShowIcon","castbarPlayerShowSpellName","showPlayerCastTime","castbarPlayerDetached","castbarPlayerIconSize","castbarPlayerTextOffsetX","castbarPlayerTextOffsetY","castbarPlayerTimeOffsetX","castbarPlayerTimeOffsetY","castbarPlayerSpellNameFontSize","castbarPlayerTimeFontSize"},
    target={"enableTargetCastbar","castbarTargetBarWidth","castbarTargetBarHeight","castbarTargetOffsetX","castbarTargetOffsetY","castbarTargetMatchWidth","castbarTargetShowIcon","castbarTargetShowSpellName","showTargetCastTime","castbarTargetDetached","castbarTargetIconSize","castbarTargetTextOffsetX","castbarTargetTextOffsetY","castbarTargetTimeOffsetX","castbarTargetTimeOffsetY","castbarTargetSpellNameFontSize","castbarTargetTimeFontSize"},
    focus={"enableFocusCastbar","castbarFocusBarWidth","castbarFocusBarHeight","castbarFocusOffsetX","castbarFocusOffsetY","castbarFocusMatchWidth","castbarFocusShowIcon","castbarFocusShowSpellName","showFocusCastTime","castbarFocusDetached","castbarFocusIconSize","castbarFocusTextOffsetX","castbarFocusTextOffsetY","castbarFocusTimeOffsetX","castbarFocusTimeOffsetY","castbarFocusSpellNameFontSize","castbarFocusTimeFontSize"},
    boss={"enableBossCastbar","bossCastbarWidth","bossCastbarHeight","bossCastbarOffsetX","bossCastbarOffsetY","bossCastbarMatchWidth","showBossCastIcon","showBossCastName","showBossCastTime","bossCastbarDetached","bossCastIconSize","bossCastTextOffsetX","bossCastTextOffsetY","bossCastTimeOffsetX","bossCastTimeOffsetY","bossCastSpellNameFontSize","bossCastTimeFontSize"},
}

local function ConvertCastbar(source, spec, dst, general, report, unitKey)
    local keys = CAST_KEYS[unitKey]
    if not keys then
        if type(source) == "table" and source.Enabled == true then Mark(report, "skipped", unitKey .. ": no native castbar") end
        return
    end
    local defaults = Merge(spec.castDefaults, DEFAULT_CASTBAR)
    defaults.Enabled = spec.cast == true
    defaults.ShowTarget = spec.castTarget == true
    local cast = Merge(source, defaults)
    local layout = Layout(cast.Layout, defaults.Layout)
    local width = SafeNumber(cast.Width, 244, 1, 1200)
    local height = SafeNumber(cast.Height, 24, 1, 600)
    local effectiveWidth = cast.MatchParentWidth == true and dst.width or width
    local selfX, selfY = Fraction(layout[1])
    local relX, relY = Fraction(layout[2])
    local left = relX * dst.width + layout[3] - selfX * effectiveWidth - effectiveWidth * 0.5
    local bottom = relY * dst.height + layout[4] - selfY * height - height * 0.5
    general[keys[1]], general[keys[2]], general[keys[3]] = cast.Enabled ~= false, width, height
    general[keys[4]] = unitKey == "player" and left + effectiveWidth * 0.5 or left + dst.width * 0.5
    general[keys[5]] = bottom - dst.height * 0.5 - (unitKey == "boss" and 2 or 0)
    general[keys[6]] = cast.MatchParentWidth == true and "unitframe" or nil
    general[keys[7]] = cast.Icon.Enabled ~= false
    general[keys[8]], general[keys[9]], general[keys[10]] = cast.Text.SpellName.Enabled ~= false, cast.Text.Duration.Enabled ~= false, false
    general[keys[11]] = math.max(6, height - 2)
    local nameLayout = Layout(cast.Text.SpellName.Layout, defaults.Text.SpellName.Layout)
    local timeLayout = Layout(cast.Text.Duration.Layout, defaults.Text.Duration.Layout)
    general[keys[12]], general[keys[13]] = nameLayout[3] - (unitKey == "boss" and 2 or 4), nameLayout[4]
    general[keys[14]], general[keys[15]] = timeLayout[3], timeLayout[4]
    general[keys[16]] = SafeNumber(cast.Text.SpellName.FontSize, 12, 6, 72)
    general[keys[17]] = SafeNumber(cast.Text.Duration.FontSize, 12, 6, 72)
    if not report._castbarSource and cast.Enabled ~= false then
        report._castbarSource = unitKey
        SetRGB(general, "castbarInterruptible", cast.Foreground)
        SetRGBA(general, "castbarBg", cast.Background)
        SetRGB(general, "castbarNonInterruptible", cast.NotInterruptibleColour)
        SetRGB(general, "castbarFont", cast.Text.SpellName.Colour)
        general.castbarFillDirection = cast.Inverse == true and "RTL" or "LTR"
        general.castbarUnifiedDirection = true
        general.castbarSpellNameShortening = 1
        general.castbarSpellNameMaxLen = SafeNumber(cast.Text.SpellName.MaxChars, 15, 0, 128)
    elseif cast.Enabled ~= false then
        Mark(report, "approximated", unitKey .. ": per-unit UUF castbar colors/direction use native shared castbar styling")
    end
    if cast.ShowTarget == true then Mark(report, "skipped", unitKey .. ": UUF cast-target text is unavailable natively") end
    if tostring(cast.Icon.Position or "LEFT"):upper() ~= "LEFT" then Mark(report, "approximated", unitKey .. ": right cast icon uses native left icon") end
    if FrameStrata(cast.FrameStrata, "MEDIUM") ~= "MEDIUM" then Mark(report, "skipped", unitKey .. ": castbar frame strata is fixed natively") end
    Mark(report, "mapped", unitKey .. ": castbar geometry and text")
end

local function AuraGrowth(lane)
    local growth = tostring(lane.GrowthDirection or "RIGHT"):upper()
    local wrap = tostring(lane.WrapDirection or "UP"):upper()
    if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    if growth == "LEFT" or growth == "RIGHT" then
        if wrap ~= "UP" and wrap ~= "DOWN" then wrap = "UP" end
    elseif wrap ~= "LEFT" and wrap ~= "RIGHT" then
        wrap = "RIGHT"
    end
    return growth, wrap
end

local function AuraFilter(lane, harmful, report, label)
    if lane.OnlyShowPlayer == true then return "PLAYER", true end
    local selected = {}
    for key, enabled in pairs(type(lane.Filters) == "table" and lane.Filters or {}) do
        if enabled == true then selected[#selected + 1] = key end
    end
    if #selected > 1 then
        Mark(report, "approximated", label .. ": multiple UUF OR filters fall back to native ALL")
        return "ALL", false
    end
    local key = selected[1]
    if not key then return "ALL", false end
    local map = {Player="PLAYER", Raid="RAID", RaidPlayer="RAID_PLAYER", RaidInCombat="RAID_IN_COMBAT",
        CrowdControl="CROWD_CONTROL", BigDefensive="BIG_DEFENSIVE", ExternalDefensive="EXTERNAL_DEFENSIVE",
        Cancelable="CANCELABLE", NotCancelable="NOT_CANCELABLE", RaidPlayerDispellable="DISPELLABLE"}
    if key == "Typed" then return harmful and "DISPELLABLE" or "ALL", false end
    local mine = key:sub(-6) == "Player"
    local base = mine and key:sub(1, -7) or key
    local token = map[key] or map[base]
    if not token then Mark(report, "approximated", label .. ": unknown UUF filter falls back to native ALL") end
    return token or "ALL", mine
end

local function HealthRect(width, height, power, secondary)
    local top, bottom = 0, 0
    for _, bar in pairs({power, secondary}) do
        if type(bar) == "table" and bar.Enabled == true then
            local depth = SafeNumber(bar.Height, 1, 0, height) + 1
            if tostring(bar.Position or "BOTTOM"):upper() == "TOP" then top = top + depth else bottom = bottom + depth end
        end
    end
    return width - 2, math.max(1, height - 2 - top - bottom), 1, 1 + bottom
end

local function AuraOffset(lane, parentWidth, parentHeight, originX, originY)
    local layout = Layout(lane.Layout, {"BOTTOMLEFT","TOPLEFT",0,1,1})
    local size = SafeNumber(lane.Size, 26, 2, 256)
    local pointX, pointY = Fraction(layout[1])
    local relativeX, relativeY = Fraction(layout[2])
    local x = (originX or 0) + (relativeX + 0.5) * parentWidth + layout[3] - (pointX + 0.5) * size
    local y = (originY or 0) + (relativeY + 0.5) * parentHeight + layout[4] - (pointY + 0.5) * size
    local growth = AuraGrowth(lane)
    if growth == "LEFT" then x = x + size - 1 end
    if growth == "DOWN" then y = y + size - 1 end
    return x, y, layout, size
end

local function ConvertUnitAuras(unitKey, source, spec, frame, out, report, cooldown, power, secondary)
    if unitKey ~= "player" and unitKey ~= "target" and unitKey ~= "focus" and unitKey ~= "boss" then
        if type(source) == "table" then Mark(report, "skipped", unitKey .. ": native Auras2 does not render this unit") end
        return
    end
    source = type(source) == "table" and source or {}
    local buff = Merge(source.Buffs, spec.buffs)
    local debuff = Merge(source.Debuffs, spec.debuffs)
    local root = out.auras2
    root.shared, root.perUnit = root.shared or {}, root.perUnit or {}
    local enabled = buff.Enabled ~= false or debuff.Enabled ~= false
    root["show" .. unitKey:sub(1,1):upper() .. unitKey:sub(2)] = enabled
    root.enabled = root.enabled == true or enabled
    root.shared.showBuffs, root.shared.showDebuffs = true, true
    root.shared.showCooldownText, root.shared.showCooldownSwipe = true, true
    local targets = unitKey == "boss" and {"boss1","boss2","boss3","boss4","boss5"} or {unitKey}
    local healthW, healthH, healthX, healthY = HealthRect(frame.width, frame.height, power, secondary)
    local function Lane(lane, fallback, harmful)
        local parentHealth = lane.AnchorParent == "Health"
        local x, y, layout, size = AuraOffset(lane, parentHealth and healthW or frame.width,
            parentHealth and healthH or frame.height, parentHealth and healthX or 0, parentHealth and healthY or 0)
        y = y - frame.height
        local growth, wrap = AuraGrowth(lane)
        local token, mine = AuraFilter(lane, harmful, report, unitKey .. (harmful and " debuffs" or " buffs"))
        return {x=x,y=y,size=size,spacing=math.max(0,layout[5]),growth=growth,wrap=wrap,
            max=lane.Enabled ~= false and SafeNumber(lane.Num,fallback.Num,0,80) or 0,
            perRow=SafeNumber(lane.Wrap,fallback.Wrap,1,40),token=token,mine=mine}
    end
    local b, d = Lane(buff, spec.buffs, false), Lane(debuff, spec.debuffs, true)
    for i = 1, #targets do
        local pu = root.perUnit[targets[i]] or {}
        root.perUnit[targets[i]] = pu
        pu.overrideLayout, pu.overrideSharedLayout, pu.overrideFilters = true, true, true
        pu.layout, pu.layoutShared, pu.filters = pu.layout or {}, pu.layoutShared or {}, pu.filters or {}
        pu.layout.buffGroupOffsetX, pu.layout.buffGroupOffsetY, pu.layout.buffGroupIconSize = b.x, b.y, b.size
        pu.layout.debuffGroupOffsetX, pu.layout.debuffGroupOffsetY, pu.layout.debuffGroupIconSize = d.x, d.y, d.size
        pu.layout.offsetX, pu.layout.offsetY = 0, 0
        pu.layout.spacing = math.max(b.spacing,d.spacing)
        pu.layoutShared.maxBuffs, pu.layoutShared.maxDebuffs = b.max, d.max
        pu.layoutShared.buffPerRow, pu.layoutShared.debuffPerRow = nil, nil
        pu.layoutShared.perRow = math.max(b.perRow, d.perRow)
        pu.layoutShared.buffGrowth, pu.layoutShared.debuffGrowth = b.growth, d.growth
        pu.layoutShared.buffRowWrap, pu.layoutShared.debuffRowWrap = b.wrap, d.wrap
        pu.filters.enabled = true
        pu.filters.buffs = {onlyMine=b.mine, filterToken=b.token, includeBoss=false, includeStealable=false}
        pu.filters.debuffs = {onlyMine=d.mine, filterToken=d.token, includeBoss=false, includeDispellable=false}
    end
    if b.perRow ~= d.perRow then
        Mark(report, "approximated", unitKey .. ": separate UUF buff/debuff wrap counts share native Auras2 per-row")
    end
    if source.FrameStrata and FrameStrata(source.FrameStrata,"LOW") ~= "LOW" then Mark(report,"skipped",unitKey .. ": aura frame strata unavailable") end
    if buff.Blacklist == true or debuff.Blacklist == true then Mark(report,"approximated",unitKey .. ": UUF aura blacklist uses native filters") end
    Mark(report, "mapped", unitKey .. ": Auras2 lanes, filters and geometry")
    Mark(report, "families", "Auras2")
end

local RAID_GROWTH = {
    RIGHT_DOWN="RIGHT", RIGHT_UP="RIGHT",
    LEFT_DOWN="LEFT", LEFT_UP="LEFT",
    UP_RIGHT="UP", UP_LEFT="UP",
    DOWN_RIGHT="DOWN", DOWN_LEFT="DOWN",
}

local RAID_EXACT_GROWTH = {
    RIGHT_DOWN=true,
    LEFT_DOWN=true,
    UP_RIGHT=true,
    DOWN_RIGHT=true,
}

local function FoldSameAnchor(layout, frameWidth, frameHeight, parentWidth, parentHeight, centerX, centerY)
    layout = Layout(layout)
    local selfX, selfY = Fraction(layout[1])
    local relativeX, relativeY = Fraction(layout[2])
    local x = (centerX or 0) + relativeX * parentWidth + layout[3] - selfX * frameWidth
    local y = (centerY or 0) + relativeY * parentHeight + layout[4] - selfY * frameHeight
    return Anchor(layout[1]), x, y
end

local function GroupAuraLane(lane, fallback, frame, power, harmful, cooldown, report, label)
    lane = Merge(lane, fallback)
    local parentWidth, parentHeight = frame.width, frame.height
    local parentCenterX, parentCenterY = 0, 0

    if lane.AnchorParent == "Health" then
        local healthWidth, healthHeight, healthX, healthY = HealthRect(frame.width, frame.height, power)
        parentWidth, parentHeight = healthWidth, healthHeight
        parentCenterX = healthX + healthWidth * 0.5 - frame.width * 0.5
        parentCenterY = healthY + healthHeight * 0.5 - frame.height * 0.5
    end

    local anchor, x, y = FoldSameAnchor(
        lane.Layout,
        frame.width,
        frame.height,
        parentWidth,
        parentHeight,
        parentCenterX,
        parentCenterY
    )
    local growth, wrap = AuraGrowth(lane)
    local filterToken = AuraFilter(lane, harmful, report, label)
    local duration = Merge(lane.Duration, cooldown)
    local durationLayout = Layout(duration.Layout, {"CENTER", "CENTER", 0, 0})
    local count = Merge(lane.Count, {
        HideStacks=false,
        Layout={"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 2},
        FontSize=12,
    })
    local countLayout = Layout(count.Layout, {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 2})

    if lane.Blacklist == true then
        Mark(report, "approximated", label .. ": UUF blacklist categories use the native base filter")
    end

    return {
        enabled=lane.Enabled ~= false,
        anchor=anchor,
        growth=growth .. wrap,
        x=x,
        y=y,
        size=SafeNumber(lane.Size, fallback.Size, 2, 256),
        perRow=SafeNumber(lane.Wrap, fallback.Wrap, 1, 40),
        max=SafeNumber(lane.Num, fallback.Num, 0, 80),
        spacing=SafeNumber(Layout(lane.Layout)[5], 1, 0, 200),
        layer=harmful and 6 or 5,
        filterToken=filterToken,
        showDispelBorder=harmful and lane.ShowType == true,
        showCooldownSwipe=lane.DisableCooldown ~= true,
        showCooldown=lane.DisableCooldownText ~= true,
        cooldownAnchor=Anchor(durationLayout[1]),
        cooldownOffsetX=durationLayout[3],
        cooldownOffsetY=durationLayout[4],
        cooldownSize=SafeNumber(duration.FontSize, 12, 6, 72),
        showStacks=count.HideStacks ~= true,
        stackAnchor=Anchor(countLayout[1]),
        stackOffsetX=countLayout[3],
        stackOffsetY=countLayout[4],
        stackSize=SafeNumber(count.FontSize, 12, 6, 72),
    }
end

local function ConvertGroupAuras(kind, source, spec, dst, power, cooldown, report)
    source = type(source) == "table" and source or {}
    local duration = Merge(source.AuraDuration, cooldown)
    local buff = GroupAuraLane(source.Buffs, spec.buffs, dst, power, false, duration, report, kind .. " buffs")
    local debuff = GroupAuraLane(source.Debuffs, spec.debuffs, dst, power, true, duration, report, kind .. " debuffs")

    dst.auras = type(dst.auras) == "table" and dst.auras or {}
    dst.auras.enabled = buff.enabled or debuff.enabled
    dst.auras.renderer = "CUSTOM"
    dst.auras.buff = buff
    dst.auras.debuff = debuff

    local private = Merge(source.PrivateAuras, spec.private)
    if type(private) == "table" then
        local anchor, x, y = FoldSameAnchor(
            private.Layout,
            dst.width,
            dst.height,
            dst.width,
            dst.height,
            0,
            0
        )
        local direction = tostring(private.GrowthX or "LEFT"):upper()
        if direction ~= "LEFT" and direction ~= "RIGHT" then
            direction = tostring(private.GrowthY or "UP"):upper()
        end
        dst.privateAuras = type(dst.privateAuras) == "table" and dst.privateAuras or {}
        dst.privateAuras.enabled = private.Enabled ~= false
        dst.privateAuras.max = SafeNumber(private.Num, 1, 0, 12)
        dst.privateAuras.size = SafeNumber(private.Size, 32, 8, 256)
        dst.privateAuras.anchor = Anchor(private.InitialAnchor or anchor)
        dst.privateAuras.direction = direction
        dst.privateAuras.spacing = SafeNumber(private.Spacing, 1, 0, 200)
        dst.privateAuras.x = x
        dst.privateAuras.y = y
        dst.privateAuras.showCountdown = private.DisableCooldown ~= true
        dst.privateAuras.showNumbers = private.DisableCooldownText ~= true
        dst.privateAuras.showDuration = private.DisableCooldownText ~= true
        dst.privateAuras.layer = 8
        dst.auras.enabled = dst.auras.enabled or dst.privateAuras.enabled
    end

    Mark(report, "mapped", kind .. ": native group aura lanes and private auras")
    Mark(report, "families", "group auras")
end

local function ApplyGroupIcon(dst, source, keys)
    if type(source) ~= "table" then return end
    local layout = Layout(source.Layout)
    local size = SafeNumber(source.Size, keys.defaultSize, 4, 256)
    if keys.doubleSize == true then
        size = math.min(size * UUF_CUSTOM_STATUS_ICON_SCALE, MAX_IMPORTED_STATUS_ICON_SIZE)
    end
    local sourceX, sourceY = Fraction(layout[1])
    local anchor = Anchor(layout[2])
    local nativeX, nativeY = Fraction(anchor)
    dst[keys.enabled] = source.Enabled == true
    dst[keys.size] = size
    dst[keys.anchor] = anchor
    dst[keys.x] = layout[3] + (nativeX - sourceX) * size
    dst[keys.y] = layout[4] + (nativeY - sourceY) * size
end

local function ConvertGroupIndicators(kind, source, defaults, dst, report)
    local rawSource = type(source) == "table" and source or {}
    source = Merge(rawSource, defaults)

    -- Older UUF profiles used shorter SavedVariables keys for two oUF status
    -- elements. Prefer the current V12.1 keys when both exist, but do not let
    -- converter defaults hide an explicitly configured legacy size/layout.
    local function ResolveIndicator(primary, aliasOne, aliasTwo)
        local value = rawSource[primary]
        if type(value) == "table" then return value end
        value = aliasOne and rawSource[aliasOne]
        if type(value) == "table" then return value end
        value = aliasTwo and rawSource[aliasTwo]
        if type(value) == "table" then return value end
        return source[primary]
    end

    local iconMaps = {
        {ResolveIndicator("RaidTargetMarker"), {enabled="raidMarker", size="raidMarkerSize", anchor="raidMarkerAnchor", x="raidMarkerX", y="raidMarkerY", defaultSize=14}},
        {ResolveIndicator("Role"), {enabled="roleIcon", size="roleIconSize", anchor="roleIconAnchor", x="roleIconX", y="roleIconY", defaultSize=12}},
        {ResolveIndicator("ReadyCheckIndicator", "ReadyCheck"), {enabled="readyCheckIcon", size="readyCheckSize", anchor="readyCheckAnchor", x="readyCheckX", y="readyCheckY", defaultSize=16}},
        {ResolveIndicator("Summon"), {enabled="summonIcon", size="summonIconSize", anchor="summonAnchor", x="summonX", y="summonY", defaultSize=16}},
        {ResolveIndicator("ResurrectIndicator", "Resurrection", "Resurrect"), {enabled="resurrectIcon", size="resurrectIconSize", anchor="resurrectAnchor", x="resurrectX", y="resurrectY", defaultSize=16, doubleSize=true}},
        {ResolveIndicator("Phase"), {enabled="phaseIcon", size="phaseIconSize", anchor="phaseAnchor", x="phaseX", y="phaseY", defaultSize=14, doubleSize=true}},
    }
    for i = 1, #iconMaps do
        local entry = iconMaps[i]
        ApplyGroupIcon(dst, entry[1], entry[2])
    end

    local leader = ResolveIndicator("LeaderAssistantIndicator")
    if type(leader) == "table" then
        ApplyGroupIcon(dst, leader, {enabled="leaderIcon", size="leaderIconSize", anchor="leaderIconAnchor", x="leaderIconX", y="leaderIconY", defaultSize=12})
        ApplyGroupIcon(dst, leader, {enabled="assistIcon", size="assistIconSize", anchor="assistIconAnchor", x="assistIconX", y="assistIconY", defaultSize=12})
    end

    local role = ResolveIndicator("Role")
    if type(role) == "table" then
        dst.roleIconShowTank = role.ShowTank ~= false
        dst.roleIconShowHealer = role.ShowHealer ~= false
        dst.roleIconShowDPS = role.ShowDamager ~= false
    end

    local target = source.Target
    if type(target) == "table" then
        dst.targetIndicator = target.Enabled == true
        SetRGB(dst, "target", target.Colour)
    end
    local threat = source.Threat
    if type(threat) == "table" then dst.aggroEnabled = threat.Enabled == true end

    Mark(report, "mapped", kind .. ": native group status indicators")
end

local function ResolveGroupFilters(frame, spec, destination)
    local groups = {}
    local count = 0
    local configured = type(frame.Groups) == "table" and frame.Groups or nil

    for index = 1, 8 do
        local enabled
        if frame.AutoAdjustGroups == true then
            enabled = destination ~= "gf_mythicraid" or index <= 4
        else
            local configuredValue = configured and configured[index]
            if configuredValue == nil and configured then
                configuredValue = configured[tostring(index)]
            end
            if configuredValue == nil then configuredValue = spec.groups[index] end
            enabled = configuredValue == true
            if destination == "gf_mythicraid" and index > 4 then enabled = false end
        end
        groups[index] = enabled
        if enabled then count = count + 1 end
    end
    return groups, math.max(count, 1)
end

local function PositionGroupContainer(kind, frame, spec, destination, layout, dst, groupCount)
    local spacing = dst.spacing
    local totalWidth, totalHeight

    if kind == "party" then
        local count = dst.showPlayer and 5 or 4
        local horizontal = dst.growth == "LEFT" or dst.growth == "RIGHT"
        totalWidth = horizontal and ((dst.width + spacing) * count - spacing) or dst.width
        totalHeight = horizontal and dst.height or ((dst.height + spacing) * count - spacing)
    else
        local sourceGrowth = tostring(frame.GrowthDirection or spec.growth):upper()
        local unitGrowth, groupGrowth = sourceGrowth:match("^(%a+)_(%a+)$")
        unitGrowth, groupGrowth = unitGrowth or "LEFT", groupGrowth or "DOWN"
        local unitVertical = unitGrowth == "UP" or unitGrowth == "DOWN"
        local headerWidth = unitVertical and dst.width or ((dst.width + spacing) * 5 - spacing)
        local headerHeight = unitVertical and ((dst.height + spacing) * 5 - spacing) or dst.height
        local groupsHorizontal = groupGrowth == "LEFT" or groupGrowth == "RIGHT"
        totalWidth = groupsHorizontal and ((headerWidth + spacing) * groupCount - spacing) or headerWidth
        totalHeight = groupsHorizontal and headerHeight or ((headerHeight + spacing) * groupCount - spacing)
    end

    local pointX, pointY = Fraction(layout[1])
    dst.offsetX = layout[3] - pointX * totalWidth
    dst.offsetY = layout[4] - pointY * totalHeight
    dst.point = Anchor(layout[2])
    dst.anchorPoint = dst.point
    dst.positionMode = "GRID_CENTER_V1"
end

local function ApplyGroupTags(kind, source, spec, dst, report)
    dst.showName, dst.showHPText, dst.showPowerText = false, false, false
    dst.textLeft, dst.textCenter, dst.textRight = "NONE", "NONE", "NONE"
    dst.powerTextLeft, dst.powerTextCenter, dst.powerTextRight = "NONE", "NONE", "NONE"

    local tags = type(source.Tags) == "table" and source.Tags or {}
    local powerHeight = dst.powerBarEnabled and dst.powerHeight or 0
    local healthHeight = math.max(1, dst.height - powerHeight)
    local healthCenterY = powerHeight * 0.5

    for index = 1, #TAG_KEYS do
        local tag = Merge(tags[TAG_KEYS[index]], spec.tags[index])
        if tag.Tag ~= "" then
            local tagKind, mode, metadata = ParseTag(tag.Tag)
            if tagKind == "composite" then
                tagKind, mode, metadata = ParseComposite(tag.Tag)
            end

            local fontSize = SafeNumber(tag.FontSize, 12, 6, 72)
            local slot = PointSlot(Layout(tag.Layout)[1])
            local nativeAnchor = slot == "Left" and "LEFT" or slot == "Right" and "RIGHT" or "CENTER"
            local pad = slot == "Left" and 3 or slot == "Right" and -3 or 0

            if tagKind == "name" then
                local x, y = FoldAnchor(
                    tag.Layout, dst.width, dst.height, fontSize,
                    nativeAnchor, nativeAnchor, dst.width, healthHeight,
                    0, healthCenterY, pad, 0
                )
                dst.showName = true
                dst.nameAnchor = slot:upper()
                dst.nameOffsetX, dst.nameOffsetY = x, y
                dst.nameFontSize = fontSize
                dst.nameColorMode = "CUSTOM"
                SetRGB(dst, "nameColor", tag.Colour)
            elseif tagKind == "status" then
                local anchor = Anchor(Layout(tag.Layout)[1])
                local x, y = FoldAnchor(
                    tag.Layout, dst.width, dst.height, fontSize,
                    anchor, anchor, dst.width, healthHeight,
                    0, healthCenterY, 0, 0
                )
                dst.statusText, dst.statusGhostText, dst.statusAFKText = true, true, true
                dst.statusTextAnchor = anchor
                dst.statusOffsetX, dst.statusOffsetY = x, y
                dst.statusTextSize = fontSize
            elseif tagKind == "health" or (tagKind == "power" and mode) then
                local isPower = tagKind == "power"
                local nativeHeight = isPower and math.max(powerHeight, 1) or healthHeight
                local nativeCenterY = isPower and (-dst.height * 0.5 + nativeHeight * 0.5) or healthCenterY
                local nativePad = slot == "Left" and (isPower and 2 or 3)
                    or slot == "Right" and (isPower and -2 or -3)
                    or 0
                local x, y = FoldAnchor(
                    tag.Layout, dst.width, dst.height, fontSize,
                    nativeAnchor, nativeAnchor, dst.width, nativeHeight,
                    0, nativeCenterY, nativePad, 0
                )
                local modeKey = (isPower and "powerText" or "text") .. slot
                local offsetPrefix = (isPower and "powerText" or "hpText") .. slot
                dst[modeKey] = mode
                dst[offsetPrefix .. "OffsetX"] = x
                dst[offsetPrefix .. "OffsetY"] = y
                dst.useGlobalFontColor = false
                SetRGB(dst, "font", tag.Colour)
                if isPower then
                    dst.showPowerText = true
                    dst.powerFontSize = fontSize
                else
                    dst.showHPText = true
                    dst.hpFontSize = fontSize
                end
            else
                Mark(report, "skipped", kind .. ": unsupported UUF group tag " .. tostring(tag.Tag))
            end
        end
    end
end

local function ConvertGroup(kind, source, out, report, cooldown, destination)
    source = type(source) == "table" and source or {}
    local spec = GROUP_SPECS[kind]
    local key = destination or (kind == "party" and "gf_party" or "gf_raid")
    local dst = type(out[key]) == "table" and out[key] or {}
    out[key] = dst

    local frame = type(source.Frame) == "table" and source.Frame or {}
    local layout = Layout(frame.Layout, spec.layout)
    dst.enabled = Bool(source.Enabled, true)
    dst.width = SafeNumber(frame.Width, spec.width, 20, 1200)
    dst.height = SafeNumber(frame.Height, spec.height, 3, 600)
    dst.spacing = SafeNumber(layout[5], 1, 0, 200)
    dst.showPlayer = Bool(frame.ShowPlayer, spec.showPlayer)
    dst.sortMode = tostring(frame.SortBy or frame.SortMethod or frame.Sorting or spec.sort):upper()
    dst.roleOrder = RoleOrder(frame.RoleOrder)

    local groupCount = 1
    if kind == "party" then
        dst.growth = tostring(frame.GrowthDirection or spec.growth):upper()
        dst.unitsPerColumn = dst.showPlayer and 5 or 4
        dst.maxColumns = 1
    else
        local sourceGrowth = tostring(frame.GrowthDirection or spec.growth):upper()
        local mappedGrowth = RAID_GROWTH[sourceGrowth] or RAID_GROWTH.LEFT_DOWN
        dst.growth = mappedGrowth
        dst.groupGrowth = nil
        if not RAID_EXACT_GROWTH[sourceGrowth] then
            Mark(report, "approximated", kind .. ": UUF secondary raid-group direction uses the closest native layout")
        end
        dst.unitsPerColumn = 5
        dst.preserveRaidGroups = true
        dst.groupFilter, groupCount = ResolveGroupFilters(frame, spec, destination)
        dst.maxColumns = groupCount
    end
    PositionGroupContainer(kind, frame, spec, destination, layout, dst, groupCount)

    local health = Merge(source.HealthBar, DEFAULT_HEALTH)
    local powerDefaults = DeepCopy(DEFAULT_POWER)
    powerDefaults.Enabled, powerDefaults.Height, powerDefaults.OnlyShowHealers = true, 1, true
    local power = Merge(source.PowerBar, powerDefaults)

    dst.reverseFill = health.Inverse == true
    dst.smoothFill = health.Smooth == true
    dst.hpBarAlpha = SafeNumber(health.ForegroundOpacity, 1, 0, 1)
    dst.hpBgAlpha = SafeNumber(health.BackgroundOpacity, 1, 0, 1)
    local rangeInAlpha = report._rangeEnabled == true
        and SafeNumber(report._rangeInAlpha, 1, 0, 1) or 1
    dst.alphaInCombat = rangeInAlpha
    dst.alphaOutOfCombat = rangeInAlpha
    dst.alphaSync = true
    dst.alphaSyncBoth = true
    dst.alphaExcludeTextPortrait = false
    dst.alphaLayerMode = 0
    dst.alphaFGInCombat = rangeInAlpha
    dst.alphaFGOutOfCombat = rangeInAlpha
    dst.alphaBGInCombat = rangeInAlpha
    dst.alphaBGOutOfCombat = rangeInAlpha
    dst.alphaHPInCombat = rangeInAlpha
    dst.alphaHPOutOfCombat = rangeInAlpha
    dst.alphaPreserveHPColor = false
    if health.ColourByClass == false then
        dst.healthColorMode = "CUSTOM"
        SetRGB(dst, "healthCustom", health.Foreground)
    else
        dst.healthColorMode = "CLASS"
    end
    SetRGB(dst, "bg", health.Background)

    dst.powerBarEnabled = power.Enabled ~= false
    dst.powerHeight = SafeNumber(power.Height, 1, 1, 100)
    dst.powerSmoothFill = power.Smooth == true
    dst.powerShowHealer = true
    dst.powerShowTank = power.OnlyShowHealers ~= true
    dst.powerShowDamager = dst.powerShowTank
    dst.borderEnabled, dst.borderSize = true, 1
    dst.borderR, dst.borderG, dst.borderB, dst.borderA = 0, 0, 0, 1

    local dispel = type(health.DispelHighlight) == "table" and health.DispelHighlight or nil
    if dispel then
        dst.dispelEnabled = dispel.Enabled ~= false
        dst.dispelOverlayEnabled = dispel.Enabled ~= false
        dst.dispelOverlayStyle = tostring(dispel.Style or "FULL"):upper() == "HEALTHBAR" and "FULL"
            or tostring(dispel.Style or "FULL"):upper()
    end

    ConvertHealPrediction(source.HealPrediction, {heal={false, true, true}}, dst, out.general, report, kind, true)
    ApplyGroupTags(kind, source, spec, dst, report)
    ConvertGroupIndicators(kind, source.Indicators, spec.indicators, dst, report)
    ConvertGroupAuras(kind, source.Auras, spec, dst, power, cooldown, report)

    dst.rangeFadeEnabled = out.general.rangeFadeEnabled
    dst.rangeFadeAlpha = out.general.rangeFadeAlpha
    dst.rangeFadeLayerMode = "frame"
    Mark(report, "mapped", kind .. ": native group geometry, bars and folded text")
    Mark(report, "families", "group frames")
end

local function ConvertMouseover(units, out, report)
    local indicators = type(units.player) == "table" and units.player.Indicators or {}
    local mouse = type(indicators) == "table" and indicators.Mouseover or nil
    mouse = Merge(mouse, {Enabled=true, Colour={1, 1, 1, 1}, Style="BORDER", HighlightOpacity=1})
    local color = Color(mouse.Colour, {1, 1, 1, 1})
    out.general.highlightEnabled = mouse.Enabled ~= false
    out.general.highlightColor = {color[1], color[2], color[3]}
    if tostring(mouse.Style):upper() ~= "BORDER" or SafeNumber(mouse.HighlightOpacity, 1) ~= 1 then
        Mark(report, "approximated", "mouseover: UUF style/opacity uses native global border")
    end
end

local function ConvertBlizzardPolicy(sources, out, report)
    for index = 1, #UNIT_ORDER do
        local unitKey = UNIT_ORDER[index]
        local source = sources[unitKey]
        out[unitKey] = type(out[unitKey]) == "table" and out[unitKey] or {}
        -- UUF's ForceHideBlizzard toggle is editable only while its own unit
        -- frame is disabled. An enabled UUF frame owns that unit regardless of
        -- the stale toggle value stored in the profile. Mirror that effective
        -- behavior instead of translating the raw flag in isolation.
        local useBlizzardFrame = type(source) == "table"
            and out[unitKey].enabled ~= true
            and source.ForceHideBlizzard == false
        out[unitKey].useBlizzardFrame = useBlizzardFrame
        if useBlizzardFrame then
            Mark(report, "mapped", unitKey .. ": Blizzard frame kept active")
        end
    end

    -- Keep the global suppression policy active; the per-unit flags above are
    -- explicit exemptions.  This avoids bringing back every Blizzard frame
    -- when a UUF profile requests only one native frame.
    out.general.disableBlizzardUnitFrames = true
    out.general.hardKillBlizzardPlayerFrame = true

    if out.targettarget.useBlizzardFrame and not out.target.useBlizzardFrame then
        Mark(report, "approximated", "targettarget: Blizzard child also requires Blizzard Target")
    end
    if out.focustarget.useBlizzardFrame and not out.focus.useBlizzardFrame then
        Mark(report, "approximated", "focustarget: Blizzard child also requires Blizzard Focus")
    end
end

function Import.Convert(profile, baseProfile)
    if type(profile) ~= "table" then return nil, "UUF profile is not a table" end
    local ok, why = ValidateTableGraph(profile)
    if not ok then return nil, why end
    if type(baseProfile) == "table" then
        ok, why = ValidateTableGraph(baseProfile)
        if not ok then return nil, "MSUF base profile is invalid: " .. tostring(why) end
    end

    local out = type(baseProfile) == "table" and DeepCopy(baseProfile) or {}
    if type(out) ~= "table" then return nil, "MSUF base profile is too deeply nested" end
    StripLegacyImportFields(out)
    out.general = type(out.general) == "table" and out.general or {}
    out.bars = type(out.bars) == "table" and out.bars or {}
    out.gameplay = type(out.gameplay) == "table" and out.gameplay or {}
    out.auras2 = type(out.auras2) == "table" and out.auras2 or {}

    local report = NewReport()
    out.general.anchorToCooldown = false
    local general = CopyGeneral(profile.General, out, report)
    local units = type(profile.Units) == "table" and profile.Units or {}
    local sources = {
        player=units.player,
        target=units.target,
        targettarget=units.targettarget or units.targetoftarget or units.tot,
        focus=units.focus,
        focustarget=units.focustarget or units.focus_target,
        pet=units.pet,
        boss=units.boss,
    }

    report._predictionPreferred = "player"
    local foundPredictionSource = false
    for index = 1, #UNIT_ORDER do
        local key = UNIT_ORDER[index]
        local unit = sources[key]
        local prediction = type(unit) == "table" and unit.HealPrediction or nil
        if type(prediction) == "table" and (
            type(prediction.IncomingHeal) == "table"
            or type(prediction.Absorbs) == "table"
            or type(prediction.HealAbsorbs) == "table"
        ) then
            report._predictionPreferred = key
            foundPredictionSource = true
            break
        end
    end
    if not foundPredictionSource then
        for _, key in ipairs({"party", "raid"}) do
            local unit = units[key]
            local prediction = type(unit) == "table" and unit.HealPrediction or nil
            if type(prediction) == "table" and (
                type(prediction.IncomingHeal) == "table"
                or type(prediction.Absorbs) == "table"
                or type(prediction.HealAbsorbs) == "table"
            ) then
                report._predictionPreferred = key
                break
            end
        end
    end

    ConvertMouseover(units, out, report)
    for index = 1, #UNIT_ORDER do
        local key = UNIT_ORDER[index]
        local source = type(sources[key]) == "table" and sources[key] or {}
        local spec = UNIT_SPECS[key]
        local dst = type(out[key]) == "table" and out[key] or {}
        out[key] = dst

        Assign(dst, UNIT_VISUAL_RESET)
        ConvertFrameGeometry(key, source, spec, dst, report, sources)
        local _, power = ApplyHealthAndPower(key, source, spec, dst, out, report)
        ConvertHealPrediction(source.HealPrediction, spec, dst, out.general, report, key, false)
        ConvertPortrait(source.Portrait, spec, dst, report, key)
        ConvertCastbar(source.CastBar or source.Castbar, spec, dst, out.general, report, key)
        ResetUnitText(dst)

        local tags = type(source.Tags) == "table" and source.Tags or {}
        for tagIndex = 1, #TAG_KEYS do
            ApplyUnitTag(dst, Merge(tags[TAG_KEYS[tagIndex]], spec.tags[tagIndex]), key, out, report)
        end
        ApplyUnitIndicators(dst, source.Indicators, key, out, report)
        dst.hpTextSeparator = out.general.hpTextSeparator
        dst.powerTextSeparator = out.general.powerTextSeparator
        if key ~= "player" then
            dst.rangeFadeEnabled = out.general.rangeFadeEnabled
            dst.rangeFadeAlpha = out.general.rangeFadeAlpha
            dst.rangeFadeLayerMode = "foreground"
        end

        local secondary = key == "player" and Merge(source.SecondaryPowerBar, DEFAULT_SECONDARY_POWER) or nil
        ConvertUnitAuras(key, source.Auras, spec, dst, out, report, general.CooldownText, power, secondary)
        Mark(report, "families", "unit frames")
    end

    -- Apply ownership only after the native unit conversion has established
    -- every destination table. Creating empty unit tables before that pass
    -- changes legacy/base-profile fallback detection in unrelated converters.
    ConvertBlizzardPolicy(sources, out, report)

    ConvertGroup("party", units.party, out, report, general.CooldownText)
    ConvertGroup("raid", units.raid, out, report, general.CooldownText)
    ConvertGroup("raid", units.raid, out, report, general.CooldownText, "gf_mythicraid")

    local augmentation = type(units.raid) == "table" and units.raid.augmentation or nil
    if type(augmentation) == "table" and (
        augmentation.Enabled == true
        or type(augmentation.Names) == "string" and augmentation.Names:match("%S")
    ) then
        Mark(report, "skipped", "raid augmentation roster has no native group-frame equivalent")
    end

    report._unitHealthBaseline = nil
    report._predictionSource = nil
    report._predictionPreferred = nil
    report._castbarSource = nil
    report._rangeEnabled = nil
    report._rangeInAlpha = nil
    report._rangeOutAlpha = nil
    report.counts = {
        mapped=#report.mapped,
        approximated=#report.approximated,
        skipped=#report.skipped,
        families=#report.families,
    }
    return out, report
end

function Import.ConvertString(value, baseProfile)
    local profile, why = Import.Decode(value)
    if not profile then return nil, why end
    return Import.Convert(profile, baseProfile)
end

function Import.ReportSummary(report)
    report = type(report) == "table" and report or {}
    local counts = type(report.counts) == "table" and report.counts or {}
    return string.format(
        "mapped %d; approximated %d; skipped %d",
        tonumber(counts.mapped) or #(report.mapped or {}),
        tonumber(counts.approximated) or #(report.approximated or {}),
        tonumber(counts.skipped) or #(report.skipped or {})
    )
end

function Import.PrintReport(report)
    if type(print) ~= "function" then return end
    print("|cff00ff00MSUF:|r UUF -> MSUF 5.7 conversion: " .. Import.ReportSummary(report) .. ".")
    if type(report) ~= "table" then return end
    if #report.approximated > 0 then
        print("|cffffd700MSUF:|r Best-effort approximations: " .. table.concat(report.approximated, "; "))
    end
    if #report.skipped > 0 then
        print("|cffff8040MSUF:|r UUF-only settings without a native 5.7 equivalent: " .. table.concat(report.skipped, "; "))
    end
end

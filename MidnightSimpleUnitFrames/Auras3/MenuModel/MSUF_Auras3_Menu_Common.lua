-- Small value, scope, and table helpers shared by the cold-path model.
-- These are cached as locals by consumers: crossing a file boundary adds no
-- dispatch wrapper, live event handler, or per-read dependency-table lookup.
-- Spell queries remain lazy because item/spell data can arrive after login.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Common(Schema)
    local type = type
    local tonumber = tonumber
    local tostring = tostring
    local pairs = pairs
    local math_floor = math.floor
    local C_Spell = _G.C_Spell
    local GetSpellInfo = _G.GetSpellInfo
    local BOSS_LOOKUP = Schema.BOSS_LOOKUP
    local BOSS_UNITS = Schema.BOSS_UNITS

    local function DeepCopy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = DeepCopy(v) end
        return out
    end

    local function Default(tbl, key, value)
        if tbl[key] == nil then tbl[key] = DeepCopy(value) end
    end

    local function DefaultsInto(tbl, defaults)
        if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
        for key, value in pairs(defaults) do
            if type(value) == "table" then
                if type(tbl[key]) ~= "table" then tbl[key] = {} end
                DefaultsInto(tbl[key], value)
            else
                Default(tbl, key, value)
            end
        end
    end

    local function ClampNumber(value, defaultValue, minValue, maxValue)
        value = tonumber(value)
        if value == nil then value = defaultValue end
        if minValue and value < minValue then value = minValue end
        if maxValue and value > maxValue then value = maxValue end
        return value
    end

    local function Round(value)
        value = tonumber(value) or 0
        if value < 0 then return -math_floor((-value) + 0.5) end
        return math_floor(value + 0.5)
    end

    local function Clamp01(value, defaultValue)
        value = tonumber(value)
        if value == nil then value = defaultValue end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    local function ReadRGB(tbl, key, defaultR, defaultG, defaultB)
        local c = tbl and tbl[key]
        if type(c) ~= "table" then return defaultR, defaultG, defaultB end
        return Clamp01(c[1] or c["1"] or c.r, defaultR),
            Clamp01(c[2] or c["2"] or c.g, defaultG),
            Clamp01(c[3] or c["3"] or c.b, defaultB)
    end

    local function NormalizeUnit(unit)
        unit = tostring(unit or "player")
        if unit == "boss" or BOSS_LOOKUP[unit] then return "boss" end
        if unit == "target" or unit == "focus" then return unit end
        return "player"
    end

    local function RuntimeUnit(unit)
        unit = tostring(unit or "player")
        if BOSS_LOOKUP[unit] then return unit end
        unit = NormalizeUnit(unit)
        return unit == "boss" and "boss1" or unit
    end

    local function EachRuntimeUnit(unit, fn)
        unit = NormalizeUnit(unit)
        if unit == "boss" then
            for i = 1, #BOSS_UNITS do fn(BOSS_UNITS[i]) end
        else
            fn(unit)
        end
    end

    local function NormalizeScope(scope)
        scope = tostring(scope or "shared")
        if scope == "shared" then return "shared" end
        return NormalizeUnit(scope)
    end

    local function NormalizeKind(kind)
        kind = tostring(kind or "buff"):lower()
        if kind == "buffs" then return "buff" end
        if kind == "debuffs" then return "debuff" end
        if kind ~= "debuff" then return "buff" end
        return kind
    end

    local function NormalizeDebuffTypeBorderMode(value, fallback)
        if value == true then return "SYMBOL" end
        if value == false then return "OFF" end
        value = tostring(value or ""):upper()
        if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
        if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
            or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
            return "SYMBOL"
        end
        if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
        return fallback or "OFF"
    end

    local function NormalizeGroupScope(scope)
        scope = tostring(scope or "raid"):lower()
        if scope == "party" then return "party" end
        return "raid"
    end

    local function GroupScopeKinds(scope)
        scope = NormalizeGroupScope(scope)
        if scope == "party" then return "party" end
        return "raid", "mythicraid"
    end

    local function AuraFilter()
        return _G.MSUF_GF_AuraFilter
    end

    local function CompactKey(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function SpellInfo(spellID)
        spellID = tonumber(spellID)
        if not spellID then return nil end
        local name, icon
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local info = C_Spell.GetSpellInfo(spellID)
            if type(info) == "table" then
                name = info.name
                icon = info.iconID or info.icon
                spellID = tonumber(info.spellID) or spellID
            end
        end
        if not icon and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            icon = C_Spell.GetSpellTexture(spellID)
        end
        if not name and type(GetSpellInfo) == "function" then
            local oldName, _, oldIcon, _, _, _, oldID = GetSpellInfo(spellID)
            name = oldName
            icon = icon or oldIcon
            spellID = tonumber(oldID) or spellID
        end
        return spellID, name, icon
    end

    local function SpellIDFromInput(value)
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if value == "" then return nil end
        local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
        if id then return math_floor(id + 0.5) end
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local info = C_Spell.GetSpellInfo(value)
            if type(info) == "table" and tonumber(info.spellID) then
                return math_floor(tonumber(info.spellID) + 0.5)
            end
        end
        if type(GetSpellInfo) == "function" then
            local _, _, _, _, _, _, spellID = GetSpellInfo(value)
            if tonumber(spellID) then return math_floor(tonumber(spellID) + 0.5) end
        end
        return nil
    end

    local function SpellLabel(spellID)
        local id, name = SpellInfo(spellID)
        id = id or tonumber(spellID) or 0
        if type(name) ~= "string" or name == "" then name = "Spell" end
        return name .. " (#" .. tostring(id) .. ")"
    end

    local function CountBlacklistSpells(spells)
        if type(spells) ~= "table" then return 0 end
        local count = 0
        for _, enabled in pairs(spells) do
            if enabled == true then count = count + 1 end
        end
        return count
    end


    -- Private dependency API; public menu methods remain on A3.MenuModel.
    return {
        AuraFilter = AuraFilter,
        Clamp01 = Clamp01,
        ClampNumber = ClampNumber,
        CompactKey = CompactKey,
        CountBlacklistSpells = CountBlacklistSpells,
        DeepCopy = DeepCopy,
        Default = Default,
        DefaultsInto = DefaultsInto,
        EachRuntimeUnit = EachRuntimeUnit,
        GroupScopeKinds = GroupScopeKinds,
        NormalizeDebuffTypeBorderMode = NormalizeDebuffTypeBorderMode,
        NormalizeGroupScope = NormalizeGroupScope,
        NormalizeKind = NormalizeKind,
        NormalizeScope = NormalizeScope,
        NormalizeUnit = NormalizeUnit,
        ReadRGB = ReadRGB,
        Round = Round,
        RuntimeUnit = RuntimeUnit,
        SpellIDFromInput = SpellIDFromInput,
        SpellInfo = SpellInfo,
        SpellLabel = SpellLabel,
    }
end

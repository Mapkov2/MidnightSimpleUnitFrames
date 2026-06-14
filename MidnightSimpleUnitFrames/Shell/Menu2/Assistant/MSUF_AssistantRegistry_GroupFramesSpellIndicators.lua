local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames spell/corner indicator assistant domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for shared group helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.SpellIndicators
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
MSUF = ctx.MSUF or MSUF
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local AddAliasesForUnit = ctx.AddAliasesForUnit
local GroupDB = ctx.GroupDB
local ClampNumber = ctx.ClampNumber
local ApplyGroup = ctx.ApplyGroup

if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return end
if type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return end
do
local SCOPES = { "party", "raid", "mythicraid" }
local SPEC_VALUES = {
    "auto", "multi",
    "PreservationEvoker", "AugmentationEvoker", "RestorationDruid", "DisciplinePriest", "HolyPriest",
    "ShadowPriest", "MistweaverMonk", "RestorationShaman", "HolyPaladin", "ProtectionPaladin", "RetributionPaladin",
}
local SPEC_ALIASES = {
    auto = "auto", automatic = "auto", autodetect = "auto", ["auto detect"] = "auto", current = "auto", player = "auto",
    multi = "multi", multispec = "multi", ["multi spec"] = "multi",
    preservation = "PreservationEvoker", preservationevoker = "PreservationEvoker", ["preservation evoker"] = "PreservationEvoker", prevoker = "PreservationEvoker",
    augmentation = "AugmentationEvoker", augmentationevoker = "AugmentationEvoker", ["augmentation evoker"] = "AugmentationEvoker", aug = "AugmentationEvoker", auggie = "AugmentationEvoker",
    restorationdruid = "RestorationDruid", ["restoration druid"] = "RestorationDruid", restodruid = "RestorationDruid", ["resto druid"] = "RestorationDruid", rdruid = "RestorationDruid",
    discipline = "DisciplinePriest", disciplinepriest = "DisciplinePriest", ["discipline priest"] = "DisciplinePriest", disc = "DisciplinePriest", discpriest = "DisciplinePriest", ["disc priest"] = "DisciplinePriest",
    holypriest = "HolyPriest", ["holy priest"] = "HolyPriest", shadowpriest = "ShadowPriest", ["shadow priest"] = "ShadowPriest",
    mistweaver = "MistweaverMonk", mistweavermonk = "MistweaverMonk", ["mistweaver monk"] = "MistweaverMonk", mwmonk = "MistweaverMonk", ["mw monk"] = "MistweaverMonk",
    restorationshaman = "RestorationShaman", ["restoration shaman"] = "RestorationShaman", restoshaman = "RestorationShaman", ["resto shaman"] = "RestorationShaman", rshaman = "RestorationShaman",
    holy = "HolyPaladin", holypaladin = "HolyPaladin", ["holy paladin"] = "HolyPaladin", hpal = "HolyPaladin", hpaladin = "HolyPaladin",
    protectionpaladin = "ProtectionPaladin", ["protection paladin"] = "ProtectionPaladin", protpaladin = "ProtectionPaladin", ["prot paladin"] = "ProtectionPaladin",
    retributionpaladin = "RetributionPaladin", ["retribution paladin"] = "RetributionPaladin", retpaladin = "RetributionPaladin", ["ret paladin"] = "RetributionPaladin",
}
local PLACED_VALUES = { "none", "icon", "square", "bar", "number" }
local FRAME_VALUES = { "none", "healthtint", "border", "glow", "pulse", "namecolor" }
local GROWTH_VALUES = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }
local ANCHOR_VALUES = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" }
local CI_CATEGORY_VALUES = { "none", "dispel", "aggro", "custom" }
local CI_MODE_VALUES = { "present", "missing" }
local CI_FILTER_VALUES = { "HELPFUL|PLAYER", "HELPFUL", "HARMFUL|PLAYER", "HARMFUL" }
local PLACED_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", icon = "icon", icons = "icon", square = "square", dot = "square", bar = "bar", number = "number", text = "number" }
local FRAME_ALIASES = { none = "none", off = "none", disabled = "none", hide = "none", healthtint = "healthtint", ["health tint"] = "healthtint", tint = "healthtint", border = "border", outline = "border", glow = "glow", pulse = "pulse", namecolor = "namecolor", ["name color"] = "namecolor", name = "namecolor" }
local GROWTH_ALIASES = { rightdown = "RIGHTDOWN", ["right down"] = "RIGHTDOWN", ["right then down"] = "RIGHTDOWN", leftdown = "LEFTDOWN", ["left down"] = "LEFTDOWN", ["left then down"] = "LEFTDOWN", rightup = "RIGHTUP", ["right up"] = "RIGHTUP", ["right then up"] = "RIGHTUP", leftup = "LEFTUP", ["left up"] = "LEFTUP", ["left then up"] = "LEFTUP" }
local ANCHOR_ALIASES = { topleft = "TOPLEFT", ["top left"] = "TOPLEFT", topright = "TOPRIGHT", ["top right"] = "TOPRIGHT", bottomleft = "BOTTOMLEFT", ["bottom left"] = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT", ["bottom right"] = "BOTTOMRIGHT", center = "CENTER", centre = "CENTER", middle = "CENTER", top = "TOP", bottom = "BOTTOM", left = "LEFT", right = "RIGHT" }
local CI_CATEGORY_ALIASES = { none = "none", off = "none", empty = "none", disabled = "none", dispel = "dispel", dispellable = "dispel", ["dispellable debuff"] = "dispel", aggro = "aggro", threat = "aggro", ["aggro threat"] = "aggro", custom = "custom", ["custom spell"] = "custom", spell = "custom" }
local CI_MODE_ALIASES = { present = "present", shown = "present", active = "present", ["when present"] = "present", missing = "missing", absent = "missing", ["when missing"] = "missing" }
local CI_FILTER_ALIASES = { helpfulplayer = "HELPFUL|PLAYER", ["helpful player"] = "HELPFUL|PLAYER", ["buff by me"] = "HELPFUL|PLAYER", ["my buff"] = "HELPFUL|PLAYER", ["own buff"] = "HELPFUL|PLAYER", helpful = "HELPFUL", buff = "HELPFUL", ["any buff"] = "HELPFUL", harmfulplayer = "HARMFUL|PLAYER", ["harmful player"] = "HARMFUL|PLAYER", ["debuff by me"] = "HARMFUL|PLAYER", ["my debuff"] = "HARMFUL|PLAYER", ["own debuff"] = "HARMFUL|PLAYER", harmful = "HARMFUL", debuff = "HARMFUL", ["any debuff"] = "HARMFUL" }
local CI_SLOTS = {
    { key = "TL", label = "Top Left", default = "dispel", terms = { "top left corner", "top left dot", "top left corner indicator", "tl corner" } },
    { key = "TR", label = "Top Right", default = "aggro", terms = { "top right corner", "top right dot", "top right corner indicator", "tr corner" } },
    { key = "BL", label = "Bottom Left", default = "none", terms = { "bottom left corner", "bottom left dot", "bottom left corner indicator", "bl corner" } },
    { key = "BR", label = "Bottom Right", default = "none", terms = { "bottom right corner", "bottom right dot", "bottom right corner indicator", "br corner" } },
    { key = "C", label = "Center", default = "none", terms = { "center corner", "middle corner", "center dot", "middle dot", "center indicator" } },
}

local function LookupKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function Scope(scope)
    return (scope == "raid" or scope == "mythicraid") and scope or "party"
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ColorSame(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    local ar, ag, ab = tonumber(a.r or a[1]) or 0, tonumber(a.g or a[2]) or 0, tonumber(a.b or a[3]) or 0
    local br, bg, bb = tonumber(b.r or b[1]) or 0, tonumber(b.g or b[2]) or 0, tonumber(b.b or b[3]) or 0
    return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
end

local function SpellRuntime()
    local gf = MSUF and MSUF.GF
    return (gf and gf.SpellIndicators) or _G.MSUF_GF_SpellIndicators
end

local function SpellDB(scope)
    local conf = GroupDB(scope)
    if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
    local si = conf.spellIndicators
    if si.spec == nil or si.spec == "" then si.spec = "auto" end
    if type(si.specs) ~= "table" then si.specs = {} end
    if si.layer == nil then si.layer = 9 end
    return si
end

local function SpecDisplay(specKey)
    if specKey == "auto" then return "Auto-Detect" end
    if specKey == "multi" then return "Multi-Spec" end
    local info = SpellRuntime() and SpellRuntime().SpecInfo and SpellRuntime().SpecInfo[specKey]
    return (info and info.display) or tostring(specKey or "")
end

local function ResolveSpec(value)
    local compact = LookupKey(value)
    if compact == "" then return nil end
    for alias, specKey in pairs(SPEC_ALIASES) do
        local aliasKey = LookupKey(alias)
        if compact == aliasKey or (#aliasKey >= 5 and compact:find(aliasKey, 1, true)) then return specKey end
    end
    for i = 1, #SPEC_VALUES do
        local specKey = SPEC_VALUES[i]
        if compact == LookupKey(specKey) or compact == LookupKey(SpecDisplay(specKey)) then return specKey end
    end
    local specs = SpellRuntime() and SpellRuntime().SpecInfo
    if type(specs) == "table" then
        for specKey, info in pairs(specs) do
            local displayKey = LookupKey(info and info.display)
            if compact == LookupKey(specKey) or compact == displayKey or (#displayKey >= 5 and compact:find(displayKey, 1, true)) then return specKey end
        end
    end
    return nil
end

local function FindAuraInSpec(specKey, text)
    text = tostring(text or "")
    local compact = LookupKey(text)
    local runtime = SpellRuntime()
    local list = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    local bestName, bestDisplay, bestScore
    if type(list) == "table" then
        for i = 1, #list do
            local info = list[i]
            local name = info and info.name
            if name then
                local display = info.display or name
                local nameKey = LookupKey(name)
                local displayKey = LookupKey(display)
                local score
                if compact == nameKey or compact == displayKey then score = math.max(#nameKey, #displayKey)
                elseif #nameKey >= 4 and compact:find(nameKey, 1, true) then score = #nameKey
                elseif #displayKey >= 4 and compact:find(displayKey, 1, true) then score = #displayKey end
                if score and (not bestScore or score > bestScore) then bestName, bestDisplay, bestScore = name, display, score end
            end
        end
    end
    local ids = runtime and runtime.SpellIDs and runtime.SpellIDs[specKey]
    local numberText = text:match("%d+")
    if type(ids) == "table" and numberText then
        for auraName, spellID in pairs(ids) do
            if tostring(spellID) == numberText then return auraName, auraName end
        end
    end
    return bestName, bestDisplay
end

local function ResolveAura(specKey, text)
    specKey = ResolveSpec(specKey) or specKey
    if specKey then
        local aura, display = FindAuraInSpec(specKey, text)
        return aura, specKey, display
    end
    local trackable = SpellRuntime() and SpellRuntime().TrackableAuras
    local bestAura, bestSpec, bestDisplay, bestScore
    if type(trackable) == "table" then
        for key in pairs(trackable) do
            local aura, display = FindAuraInSpec(key, text)
            if aura then
                local score = #LookupKey(display or aura)
                if not bestScore or score > bestScore then
                    bestAura, bestSpec, bestDisplay, bestScore = aura, key, display, score
                elseif score == bestScore and aura ~= bestAura then
                    bestAura, bestSpec, bestDisplay = nil, nil, nil
                end
            end
        end
    end
    return bestAura, bestSpec, bestDisplay
end

A.ResolveGroupSpellSpec = ResolveSpec
A.ResolveGroupSpellAura = ResolveAura
A.GroupSpellSpecDisplay = SpecDisplay

local function EnsureSpec(scope, specKey)
    local si = SpellDB(scope)
    if not specKey or specKey == "auto" or specKey == "multi" then return si end
    local runtime = SpellRuntime()
    if runtime and type(runtime.EnsureSpecConfig) == "function" then runtime.EnsureSpecConfig(si, specKey) else si.specs[specKey] = si.specs[specKey] or {} end
    return si
end

local function SpellEntry(scope, specKey, auraName, create)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local si = EnsureSpec(scope, specKey)
    si.specs[specKey] = si.specs[specKey] or {}
    if create and type(si.specs[specKey][auraName]) ~= "table" then si.specs[specKey][auraName] = { enabled = true, onlyOwn = true } end
    return si.specs[specKey][auraName], si.specs[specKey]
end

local function Placed(entry, create)
    if not entry then return nil end
    if create and type(entry.placed) ~= "table" then entry.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true } end
    return type(entry.placed) == "table" and entry.placed or nil
end

local function FrameEffect(entry, create)
    if not entry then return nil end
    if create and type(entry.frame) ~= "table" then entry.frame = { type = "none" } end
    return type(entry.frame) == "table" and entry.frame or nil
end

local function ApplySpell(scope)
    local runtime = SpellRuntime()
    if runtime and type(runtime.InvalidateRuntimeCaches) == "function" then runtime.InvalidateRuntimeCaches() end
    ApplyGroup(scope, "visual")
end

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do out[k] = CopyTable(v) end
    return out
end

local function CustomConfig(scope, slotKey, create)
    local conf = GroupDB(scope)
    local key = "ciCustom" .. tostring(slotKey or "")
    if create and type(conf[key]) ~= "table" then conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 } end
    return type(conf[key]) == "table" and conf[key] or nil
end

local function ActivateCustom(scope, slotKey)
    GroupDB(scope)["ciSlot" .. tostring(slotKey or "")] = "custom"
end

local SLOT_LOOKUP = {}
for i = 1, #CI_SLOTS do
    local slot = CI_SLOTS[i]
    SLOT_LOOKUP[LookupKey(slot.key)] = slot
    SLOT_LOOKUP[LookupKey(slot.label)] = slot
    for j = 1, #(slot.terms or {}) do SLOT_LOOKUP[LookupKey(slot.terms[j])] = slot end
end

local function ResolveSlot(value)
    local compact = LookupKey(value)
    if SLOT_LOOKUP[compact] then return SLOT_LOOKUP[compact] end
    for key, slot in pairs(SLOT_LOOKUP) do if #key >= 3 and compact:find(key, 1, true) then return slot end end
    return nil
end

A.ResolveGroupCornerSlot = ResolveSlot

local function AddSlotAliases(out, scope, slot, suffix)
    for i = 1, #(slot.terms or {}) do
        local term = slot.terms[i]
        AddAliasesForUnit(out, scope, suffix and (term .. " " .. suffix) or term)
        if suffix then AddAliasesForUnit(out, scope, suffix .. " " .. term) end
    end
end

local function RegisterGroupNested(scope, suffix, attr, label, typeName, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. "." .. suffix,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Frames",
        unit = scope,
        frameType = "group",
        attribute = attr,
        type = typeName,
        aliases = aliases,
        values = opts.values,
        valueAliases = opts.valueAliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        percent = opts.percent == true,
        description = opts.description,
        get = opts.get,
        set = opts.set,
        sameValue = opts.sameValue,
        apply = function() (opts.apply or ApplyGroup)(scope, opts.mode or "visual") end,
        combatSafe = false,
    })
end

for _, scope in ipairs(SCOPES) do
    local aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicators")
    AddAliasesForUnit(aliases, scope, "spell indicator")
    AddAliasesForUnit(aliases, scope, "tracked spells")
    RegisterGroupNested(scope, "spellIndicators.enabled", "spellIndicators", "Spell Indicators", "boolean", aliases, {
        get = function() return SpellDB(scope).enabled == true end,
        set = function(value)
            local si = SpellDB(scope)
            si.enabled = value and true or false
            local specKey = ResolveSpec(si.spec)
            if specKey and specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator layer")
    AddAliasesForUnit(aliases, scope, "spell indicators layer")
    AddAliasesForUnit(aliases, scope, "tracked spell layer")
    RegisterGroupNested(scope, "spellIndicators.layer", "spellIndicatorLayer", "Spell Indicator Layer", "number", aliases, {
        min = 1, max = 15, step = 1,
        get = function() return tonumber(SpellDB(scope).layer) or 9 end,
        set = function(value) SpellDB(scope).layer = ClampNumber(value, 1, 15, 1) end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spell indicator spec")
    AddAliasesForUnit(aliases, scope, "spell indicators spec")
    AddAliasesForUnit(aliases, scope, "tracked spell spec")
    RegisterGroupNested(scope, "spellIndicators.spec", "spellIndicatorSpec", "Spell Indicator Spec", "enum", aliases, {
        values = SPEC_VALUES, valueAliases = SPEC_ALIASES,
        get = function() return ResolveSpec(SpellDB(scope).spec) or "auto" end,
        set = function(value)
            local specKey = ResolveSpec(value) or "auto"
            SpellDB(scope).spec = specKey
            if specKey ~= "auto" and specKey ~= "multi" then EnsureSpec(scope, specKey) end
        end,
        apply = ApplySpell,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicators")
    AddAliasesForUnit(aliases, scope, "corner indicator")
    AddAliasesForUnit(aliases, scope, "corner dots")
    RegisterGroupNested(scope, "ciEnabled", "cornerIndicators", "Corner Indicators", "boolean", aliases, {
        get = function()
            local value = GroupDB(scope).ciEnabled
            if value == nil then return false end
            return value and true or false
        end,
        set = function(value) GroupDB(scope).ciEnabled = value and true or false end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicator size")
    AddAliasesForUnit(aliases, scope, "corner dot size")
    RegisterGroupNested(scope, "ciSize", "cornerIndicatorSize", "Corner Indicator Size", "number", aliases, {
        min = 4, max = 24, step = 1,
        get = function() return tonumber(GroupDB(scope).ciSize) or 8 end,
        set = function(value) GroupDB(scope).ciSize = ClampNumber(value, 4, 24, 1) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "corner indicator alpha")
    AddAliasesForUnit(aliases, scope, "corner indicator opacity")
    AddAliasesForUnit(aliases, scope, "corner dot opacity")
    RegisterGroupNested(scope, "ciAlpha", "cornerIndicatorAlpha", "Corner Indicator Opacity", "number", aliases, {
        min = 0.1, max = 1, step = 0.05, percent = true,
        get = function() return tonumber(GroupDB(scope).ciAlpha) or 1 end,
        set = function(value) GroupDB(scope).ciAlpha = ClampNumber(value, 0.1, 1, 0.05) end,
    })

    for _, slot in ipairs(CI_SLOTS) do
        local slotKey, slotLabel, slotDefault = slot.key, slot.label, slot.default
        aliases = {}
        AddSlotAliases(aliases, scope, slot)
        AddSlotAliases(aliases, scope, slot, "indicator")
        AddSlotAliases(aliases, scope, slot, "category")
        RegisterGroupNested(scope, "ciSlot" .. slotKey, "cornerIndicator" .. slotKey, slotLabel .. " Corner Indicator", "enum", aliases, {
            values = CI_CATEGORY_VALUES, valueAliases = CI_CATEGORY_ALIASES,
            get = function() return GroupDB(scope)["ciSlot" .. slotKey] or slotDefault end,
            set = function(value) GroupDB(scope)["ciSlot" .. slotKey] = value or "none" end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom spells")
        AddSlotAliases(aliases, scope, slot, "custom spell ids")
        AddSlotAliases(aliases, scope, slot, "spell ids")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".spells", "cornerIndicator" .. slotKey .. "CustomSpells", slotLabel .. " Corner Custom Spells", "string", aliases, {
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.spells or ""
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.spells = tostring(value or "")
                ActivateCustom(scope, slotKey)
            end,
            description = "Comma-separated spell IDs for this corner custom spell slot.",
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom mode")
        AddSlotAliases(aliases, scope, slot, "custom when")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".mode", "cornerIndicator" .. slotKey .. "CustomMode", slotLabel .. " Corner Custom Mode", "enum", aliases, {
            values = CI_MODE_VALUES, valueAliases = CI_MODE_ALIASES,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.mode or "present"
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.mode = value == "missing" and "missing" or "present"
                ActivateCustom(scope, slotKey)
            end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom filter")
        AddSlotAliases(aliases, scope, slot, "custom aura filter")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".filter", "cornerIndicator" .. slotKey .. "CustomFilter", slotLabel .. " Corner Custom Filter", "enum", aliases, {
            values = CI_FILTER_VALUES, valueAliases = CI_FILTER_ALIASES,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return cfg and cfg.filter or "HELPFUL|PLAYER"
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                local ok = { ["HELPFUL|PLAYER"] = true, HELPFUL = true, ["HARMFUL|PLAYER"] = true, HARMFUL = true }
                cfg.filter = ok[value] and value or "HELPFUL|PLAYER"
                ActivateCustom(scope, slotKey)
            end,
        })

        aliases = {}
        AddSlotAliases(aliases, scope, slot, "custom color")
        AddSlotAliases(aliases, scope, slot, "spell color")
        RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".color", "cornerIndicator" .. slotKey .. "CustomColor", slotLabel .. " Corner Custom Color", "color", aliases, {
            sameValue = ColorSame,
            get = function()
                local cfg = CustomConfig(scope, slotKey, false)
                return { r = (cfg and tonumber(cfg.r)) or 0.40, g = (cfg and tonumber(cfg.g)) or 1.00, b = (cfg and tonumber(cfg.b)) or 0.40 }
            end,
            set = function(value)
                local cfg = CustomConfig(scope, slotKey, true)
                cfg.r = Clamp01(type(value) == "table" and (value.r or value[1]) or 0.40, 0.40)
                cfg.g = Clamp01(type(value) == "table" and (value.g or value[2]) or 1.00, 1.00)
                cfg.b = Clamp01(type(value) == "table" and (value.b or value[3]) or 0.40, 0.40)
                ActivateCustom(scope, slotKey)
            end,
        })
    end
end

Registry:RegisterAction({
    key = "clear_group_custom_anchor",
    label = "Clear Group Custom Anchor",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "clear group custom anchor", "clear group custom anchor frame", "reset group custom anchor", "remove group custom anchor" },
    run = function(args)
        local scope = Scope(args and args.scope)
        GroupDB(scope).anchorToFrame = nil
        ApplyGroup(scope, "rebuild")
        return true, "Done. Cleared " .. tostring(UNIT_LABELS[scope] or scope) .. " custom anchor."
    end,
})

local function ActionTarget(args)
    local scope = Scope(args and args.scope)
    local specKey = ResolveSpec(args and args.spec)
    local auraName, resolvedSpec, display = ResolveAura(specKey, tostring(args and (args.aura or args.text) or ""))
    return scope, specKey or resolvedSpec, auraName, display or auraName
end

local function SetSpellField(scope, specKey, auraName, field, value)
    local entry = SpellEntry(scope, specKey, auraName, true)
    if not entry then return false end
    if field == "enabled" then entry.enabled = value and true or false
    elseif field == "onlyOwn" then entry.onlyOwn = value and true or false
    elseif field == "placedType" then
        if value == "none" then entry.placed = false else Placed(entry, true).type = value or "icon" end
    elseif field == "placedAnchor" then Placed(entry, true).anchor = value or "TOPLEFT"
    elseif field == "placedSize" then Placed(entry, true).size = ClampNumber(value, 6, 48, 1)
    elseif field == "placedX" then Placed(entry, true).x = ClampNumber(value, -100, 100, 1)
    elseif field == "placedY" then Placed(entry, true).y = ClampNumber(value, -100, 100, 1)
    elseif field == "placedBarWidth" then Placed(entry, true).barWidth = ClampNumber(value, 8, 120, 1)
    elseif field == "placedGrowth" then Placed(entry, true).growth = value or "RIGHTDOWN"
    elseif field == "placedMissing" then Placed(entry, true).missing = value and true or false
    elseif field == "placedCooldownSwipe" then Placed(entry, true).showCooldownSwipe = value and true or false
    elseif field == "placedCooldown" then Placed(entry, true).showCooldown = value and true or false
    elseif field == "placedCooldownSize" then Placed(entry, true).cooldownSize = ClampNumber(value, 6, 24, 1)
    elseif field == "frameType" then
        if value == "none" then entry.frame = false else
            local frame = FrameEffect(entry, true)
            frame.type = value or "border"
            frame.priority = frame.priority or 5
            frame.color = frame.color or { 1, 1, 1, 0.8 }
        end
    elseif field == "framePriority" then FrameEffect(entry, true).priority = ClampNumber(value, 1, 10, 1)
    elseif field == "frameAlpha" then
        local frame = FrameEffect(entry, true)
        local alpha = Clamp01(value, 0.8)
        frame.alpha = alpha
        if type(frame.color) == "table" then frame.color[4] = alpha end
    elseif field == "frameThickness" then FrameEffect(entry, true).thickness = ClampNumber(value, 1, 8, 1)
    elseif field == "frameColor" then
        local frame = FrameEffect(entry, true)
        local alpha = (type(frame.color) == "table" and frame.color[4]) or frame.alpha or 0.8
        frame.color = { Clamp01(type(value) == "table" and (value.r or value[1]) or 1, 1), Clamp01(type(value) == "table" and (value.g or value[2]) or 1, 1), Clamp01(type(value) == "table" and (value.b or value[3]) or 1, 1), alpha }
    else return false end
    ApplySpell(scope)
    return true
end

Registry:RegisterAction({
    key = "set_group_spell_indicator_aura",
    label = "Set Group Spell Indicator Aura",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec, such as Holy Paladin or Restoration Druid." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        if not SetSpellField(scope, specKey, auraName, args and args.field, args and args.value) then return false, "That spell indicator field is not available." end
        return true, "Done. " .. tostring(UNIT_LABELS[scope]) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator updated."
    end,
})

Registry:RegisterAction({
    key = "reset_group_spell_indicator_aura",
    label = "Reset Group Spell Indicator Aura",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec to reset." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        local _, specCfg = SpellEntry(scope, specKey, auraName, true)
        local defaults = SpellRuntime() and SpellRuntime().SpecDefaults and SpellRuntime().SpecDefaults[specKey]
        specCfg[auraName] = type(defaults) == "table" and type(defaults[auraName]) == "table" and CopyTable(defaults[auraName]) or nil
        ApplySpell(scope)
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator."
    end,
})

Registry:RegisterAction({
    key = "set_group_spell_indicator_multi_spec",
    label = "Set Group Spell Indicator Multi-Spec Entry",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey = Scope(args and args.scope), ResolveSpec(args and args.spec)
        if not specKey or specKey == "auto" or specKey == "multi" then return false, "I need a concrete spell-indicator spec to track in Multi-Spec mode." end
        local si = SpellDB(scope)
        si.spec = "multi"
        si.multiSpecs = type(si.multiSpecs) == "table" and si.multiSpecs or {}
        si.multiSpecs[specKey] = args and args.value and true or nil
        EnsureSpec(scope, specKey)
        ApplySpell(scope)
        return true, "Done. " .. tostring(UNIT_LABELS[scope]) .. " Multi-Spec tracking for " .. SpecDisplay(specKey) .. " " .. ((args and args.value) and "enabled." or "disabled.")
    end,
})

Registry:RegisterAction({
    key = "move_group_spell_indicator_order",
    label = "Move Group Spell Indicator Order",
    type = "configure",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, specKey, auraName, display = ActionTarget(args)
        if not specKey then return false, "I need a supported spell-indicator spec to reorder." end
        if not auraName then return false, "I need a supported spell indicator aura for " .. SpecDisplay(specKey) .. "." end
        EnsureSpec(scope, specKey)
        local trackable = SpellRuntime() and SpellRuntime().TrackableAuras and SpellRuntime().TrackableAuras[specKey]
        if type(trackable) ~= "table" or #trackable == 0 then return false, "That spell-indicator spec has no ordered spell list." end
        local si = SpellDB(scope)
        si.sortOrder = type(si.sortOrder) == "table" and si.sortOrder or {}
        local order = si.sortOrder[specKey]
        if type(order) ~= "table" or #order == 0 then
            order = {}
            for i = 1, #trackable do order[#order + 1] = trackable[i].name end
            si.sortOrder[specKey] = order
        end
        local from
        for i = 1, #order do if order[i] == auraName then from = i; break end end
        if not from then return false, "That aura is not in the current spell indicator order." end
        local target = tonumber(args and args.position) or from
        if target < 1 then target = 1 end
        if target > #order then target = #order end
        table.remove(order, from)
        if target > from then target = target - 1 end
        table.insert(order, target, auraName)
        ApplySpell(scope)
        return true, "Done. Moved " .. tostring(display or auraName) .. " to spell indicator slot " .. tostring(target) .. "."
    end,
})

Registry:RegisterAction({
    key = "reset_group_corner_indicator_slot",
    label = "Reset Group Corner Indicator Slot",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope, slot = Scope(args and args.scope), ResolveSlot(args and args.slot)
        if not slot then return false, "I need a corner slot, such as top left or bottom right." end
        local conf = GroupDB(scope)
        conf["ciSlot" .. slot.key] = slot.default or "none"
        conf["ciCustom" .. slot.key] = nil
        ApplyGroup(scope, "visual")
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " " .. tostring(slot.label) .. " corner indicator."
    end,
})

Registry:RegisterAction({
    key = "reset_group_corner_indicators",
    label = "Reset Group Corner Indicators",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = Scope(args and args.scope)
        local conf = GroupDB(scope)
        conf.ciEnabled, conf.ciSize, conf.ciAlpha = false, 8, 1
        for i = 1, #CI_SLOTS do
            local slot = CI_SLOTS[i]
            conf["ciSlot" .. slot.key] = slot.default or "none"
            conf["ciCustom" .. slot.key] = nil
        end
        ApplyGroup(scope, "visual")
        return true, "Done. Reset " .. tostring(UNIT_LABELS[scope]) .. " corner indicators."
    end,
})
end

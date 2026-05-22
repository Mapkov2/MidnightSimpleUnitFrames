local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme

local floor = math.floor

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return pcall(fn, ...) end
    return false
end

local function DB()
    return M.EnsureDB()
end

local function G()
    return M.GetGeneralDB()
end

local function Bars()
    local db = DB()
    db.bars = db.bars or {}
    return db.bars
end

local function Unit(key)
    local db = DB()
    db[key] = db[key] or {}
    return db[key]
end

local function ReadG(key, default)
    local value = G()[key]
    if value == nil then return default end
    return value
end

local function Targeted(opts)
    opts = opts or { preview = true }
    opts.applyAll = false
    return opts
end

local function SetG(key, value, reason, opts)
    M.SetGeneralValue(key, value, reason, Targeted(opts))
end

local function ReadGBool(key, default)
    local value = ReadG(key, default and true or false)
    return value and true or false
end

local function SetGBool(key, value, reason, opts)
    SetG(key, value and true or false, reason, opts)
end

local function ReadB(key, default)
    local value = Bars()[key]
    if value == nil then return default end
    return value
end

local function SetB(key, value, reason, opts)
    local b = Bars()
    if b[key] == value then return end
    b[key] = value
    M.RequestGeneralApply(reason or ("MSUF2_BARS_" .. tostring(key)), Targeted(opts))
end

local function SetUBool(unit, key, value, reason, opts)
    local u = Unit(unit)
    if u[key] == (value and true or false) then return end
    u[key] = value and true or false
    M.RequestUnitApply(unit, reason or "MSUF2_UNIT_GLOBAL", opts or { preview = true, alpha = true })
end

local UNIT_SCOPE_KEYS = {
    player = true,
    target = true,
    targettarget = true,
    focustarget = true,
    focus = true,
    pet = true,
    boss = true,
}

local TEXT_SCOPE_KEYS = {
    hpTextMode = true,
    textLeft = true,
    textCenter = true,
    textRight = true,
    hpTextReverse = true,
    hpTextSeparator = true,
    powerTextMode = true,
    powerTextLeft = true,
    powerTextCenter = true,
    powerTextRight = true,
    powerTextSeparator = true,
}

local POWER_BAR_SCOPE_UNITS = {
    player = true,
    target = true,
    focus = true,
    boss = true,
}

local function NormalizeScopeKey(scope)
    scope = tostring(scope or "shared"):lower()
    scope = scope:gsub("%s+", "")
    scope = scope:gsub("%-", "_")
    if scope == "party" or scope == "groupparty" or scope == "group_party" or scope == "gfparty" then return "gf_party" end
    if scope == "focus_target" or scope == "focustargettarget" then return "focustarget" end
    if scope == "raid" or scope == "mythic" or scope == "mythicraid"
        or scope == "groupraid" or scope == "group_raid" or scope == "gfraid" or scope == "gf_mythicraid" then
        return "gf_raid"
    end
    if scope == "" then return "shared" end
    return scope
end

local function ScopeDBKeys(scope)
    scope = NormalizeScopeKey(scope)
    if scope == "gf_party" then return { "gf_party" } end
    if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
    if UNIT_SCOPE_KEYS[scope] then return { scope } end
    return nil
end

local function ScopeHasOverride(scope, flag)
    local keys = ScopeDBKeys(scope)
    if not keys then return false end
    local db = DB()
    for i = 1, #keys do
        local entry = db[keys[i]]
        if entry and entry[flag] == true then return true end
    end
    return false
end

local function ScopeSetOverride(scope, flag, enabled)
    local keys = ScopeDBKeys(scope)
    if not keys then return end
    local db = DB()
    for i = 1, #keys do
        local key = keys[i]
        db[key] = db[key] or {}
        db[key][flag] = enabled and true or false
    end
end

local function ScopeRead(scope, flag, sharedTable, key, default)
    scope = NormalizeScopeKey(scope)
    if scope ~= "shared" and ScopeHasOverride(scope, flag) then
        local db = DB()
        local keys = ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if entry and entry[key] ~= nil then return entry[key] end
        end
    end
    local value = sharedTable and sharedTable[key]
    if value == nil then return default end
    return value
end

local function ScopeWrite(scope, flag, sharedTable, key, value)
    scope = NormalizeScopeKey(scope)
    if scope == "shared" then
        sharedTable[key] = value
        return
    end
    ScopeSetOverride(scope, flag, true)
    local db = DB()
    local keys = ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        db[keys[i]][key] = value
    end
end

local function CurrentFontScope()
    local g = G()
    local raw = g._fontScopeKey
    local scope = NormalizeScopeKey(raw or "shared")
    if raw ~= scope then g._fontScopeKey = scope end
    return scope
end

local function CurrentBarsScope()
    local g = G()
    local raw = g.hpPowerTextSelectedKey
    local scope = NormalizeScopeKey(raw or "shared")
    if raw ~= scope then g.hpPowerTextSelectedKey = scope end
    return scope
end

local function IsGFScope(scope)
    scope = NormalizeScopeKey(scope)
    return scope == "gf_party" or scope == "gf_raid"
end

local function IsTextScopeKey(key)
    return TEXT_SCOPE_KEYS[key] == true
end

local function BarsFlagForKey(scope, key)
    if IsTextScopeKey(key) and not IsGFScope(scope) then
        return "hpPowerTextOverride"
    end
    return "hlOverride"
end

local function FontScopeGet(key, default, rootKey)
    local shared = rootKey and DB() or G()
    return ScopeRead(CurrentFontScope(), "fontOverride", shared, rootKey or key, default)
end

local function FontScopeSet(key, value, reason, rootKey)
    local shared = rootKey and DB() or G()
    ScopeWrite(CurrentFontScope(), "fontOverride", shared, rootKey or key, value)
    M.RequestGeneralApply(reason or "MSUF2_FONTS_SCOPE", { preview = true, applyAll = false })
end

local function BarScopeGet(key, default)
    local scope = CurrentBarsScope()
    return ScopeRead(scope, BarsFlagForKey(scope, key), G(), key, default)
end

local function BarScopeSet(key, value, reason)
    local scope = CurrentBarsScope()
    ScopeWrite(scope, BarsFlagForKey(scope, key), G(), key, value)
    M.RequestGeneralApply(reason or "MSUF2_BARS_SCOPE_VALUE", { preview = true, applyAll = false })
end

local function BarScopeGetBars(key, default)
    return ScopeRead(CurrentBarsScope(), "hlOverride", Bars(), key, default)
end

local function BarScopeSetBars(key, value, reason)
    ScopeWrite(CurrentBarsScope(), "hlOverride", Bars(), key, value)
    M.RequestGeneralApply(reason or "MSUF2_BARS_SCOPE_BAR_VALUE", { preview = true, applyAll = false })
end

local function NormalizeFontKey(key)
    local fn = _G.MSUF_NormalizeFontKey or (ns and ns.MSUF_NormalizeFontKey)
    if type(fn) == "function" then return fn(key) end
    return key
end

local function FontSelectionValue(key, path)
    key = NormalizeFontKey(key)
    local normalizePath = _G.MSUF_NormalizeFontPath
    if type(normalizePath) == "function" then
        path = normalizePath(path)
        local direct = normalizePath(key)
        if type(direct) == "string" and direct ~= "" and direct:find("\\", 1, true) then
            return direct
        end
    end
    if type(path) == "string" and path ~= "" then return path end
    if type(key) == "string" and key ~= "" then
        local resolveKeyPath = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (ns and ns.MSUF_GetFontPathForKey)
        if type(resolveKeyPath) == "function" then
            local resolved = resolveKeyPath(key, 14, "")
            if type(resolved) == "string" and resolved ~= "" then return resolved end
        end
    end
    return key
end

local function FontValues(includeGlobalDefault)
    local out, used = {}, {}
    if includeGlobalDefault then
        out[#out + 1] = { value = "", text = "(Global Default)" }
        used[""] = true
    end
    local usedKeys = {}
    for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
        local key = NormalizeFontKey(info.key)
        local value = FontSelectionValue(key, info.path)
        if value and not used[value] then
            out[#out + 1] = { value = value, text = info.name or key, fontKey = key, fontPath = value }
            used[value] = true
            if key then usedKeys[key] = true end
        end
    end
    local LSM = (ns and ns.LSM) or _G.MSUF_LSM
    if LSM and type(LSM.List) == "function" then
        local names = LSM:List("font")
        local hash = type(LSM.HashTable) == "function" and LSM:HashTable("font") or nil
        if type(names) == "table" then
            table.sort(names)
            for i = 1, #names do
                local name = names[i]
                local key = NormalizeFontKey(name)
                local path = type(hash) == "table" and hash[name] or nil
                local value = FontSelectionValue(key, path)
                if value and not used[value] and not usedKeys[key] then
                    out[#out + 1] = { value = value, text = name, fontKey = key, fontPath = value }
                    used[value] = true
                    if key then usedKeys[key] = true end
                end
            end
        end
    end
    if #out == 0 then
        local value = FontSelectionValue("FRIZQT", "Fonts\\FRIZQT___CYR.TTF")
        out[1] = { value = value or "FRIZQT", text = "Friz Quadrata", fontKey = "FRIZQT", fontPath = value }
    end
    return out
end

local function ClearUFFontKeyOverrides()
    local db = DB()
    for key in pairs(UNIT_SCOPE_KEYS) do
        if type(db[key]) == "table" then db[key].fontKey = nil end
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        if type(db[key]) == "table" then db[key].fontKey = nil end
    end
end

local function FontKeyGet()
    return FontSelectionValue(ReadG("fontKey", "FRIZQT"))
end

local function FontKeySet(value)
    value = FontSelectionValue(value)
    G().fontKey = value or FontSelectionValue("FRIZQT", "Fonts\\FRIZQT___CYR.TTF")
    ClearUFFontKeyOverrides()
end

local function TextureValues(followText)
    local ui = ns and ns.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems(followText)
    end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end

local function BarsScopeHasOverride(scope)
    scope = NormalizeScopeKey(scope)
    if scope == "shared" then return false end
    if IsGFScope(scope) then return ScopeHasOverride(scope, "hlOverride") end
    return ScopeHasOverride(scope, "hlOverride") or ScopeHasOverride(scope, "hpPowerTextOverride")
end

local function BarsScopeSetOverride(scope, enabled)
    scope = NormalizeScopeKey(scope)
    if scope == "shared" then return end
    if IsGFScope(scope) then
        ScopeSetOverride(scope, "hlOverride", enabled)
        return
    end
    ScopeSetOverride(scope, "hlOverride", enabled)
    ScopeSetOverride(scope, "hpPowerTextOverride", enabled)
end

local function CurrentPowerBarScopeUnit()
    local key = CurrentBarsScope()
    return POWER_BAR_SCOPE_UNITS[key] and key or nil
end

local function SmoothPowerGet()
    local key = CurrentPowerBarScopeUnit()
    if key then
        local u = Unit(key)
        if u.powerSmoothFill ~= nil then return u.powerSmoothFill == true end
        if key == "player" then return ReadB("smoothPowerBar", true) ~= false end
        return false
    end
    return ReadB("smoothPowerBar", true) ~= false
end

local function SmoothPowerSet(enabled, reason)
    enabled = enabled and true or false
    local key = CurrentPowerBarScopeUnit()
    if key then
        Unit(key).powerSmoothFill = enabled
        M.RequestUnitApply(key, reason or "MSUF2_BARS_SMOOTH_POWER", { preview = true, power = true })
        return
    end
    SetB("smoothPowerBar", enabled, reason or "MSUF2_BARS_SMOOTH_POWER", { preview = true })
end

local function NormalizeHpMode(mode)
    if type(_G.MSUF_NormalizeHpTextMode) == "function" then return _G.MSUF_NormalizeHpTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end

local function NormalizePowerMode(mode)
    if type(_G.MSUF_NormalizePowerTextMode) == "function" then return _G.MSUF_NormalizePowerTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end

local ApplyBars

local GRADIENT_DIRECTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}

local GRADIENT_DIR_KEYS = {
    RIGHT = "gradientDirRight",
    LEFT = "gradientDirLeft",
    UP = "gradientDirUp",
    DOWN = "gradientDirDown",
}

local function CurrentGradientDirection()
    for i = 1, #GRADIENT_DIRECTIONS do
        local dir = GRADIENT_DIRECTIONS[i].value
        if BarScopeGet(GRADIENT_DIR_KEYS[dir], false) == true then return dir end
    end
    local legacy = BarScopeGet("gradientDirection", "RIGHT")
    if GRADIENT_DIR_KEYS[legacy] then return legacy end
    return "RIGHT"
end

local function CurrentGradientDirections()
    local directions = {}
    local any = false
    for i = 1, #GRADIENT_DIRECTIONS do
        local dir = GRADIENT_DIRECTIONS[i].value
        local on = BarScopeGet(GRADIENT_DIR_KEYS[dir], false) == true
        directions[dir] = on
        if on then any = true end
    end
    if not any then
        local legacy = BarScopeGet("gradientDirection", "RIGHT")
        if not GRADIENT_DIR_KEYS[legacy] then legacy = "RIGHT" end
        directions[legacy] = true
    end
    return directions
end

local function SetGradientDirection(direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    for dir, key in pairs(GRADIENT_DIR_KEYS) do
        BarScopeSet(key, dir == direction, "MSUF2_GRADIENT_DIRECTION")
    end
    BarScopeSet("gradientDirection", direction, "MSUF2_GRADIENT_DIRECTION")
end

local function ToggleGradientDirection(direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    local directions = CurrentGradientDirections()
    directions[direction] = not directions[direction]
    local any = false
    for dir in pairs(GRADIENT_DIR_KEYS) do
        if directions[dir] == true then
            any = true
            break
        end
    end
    if not any then directions[direction] = true end
    for dir, key in pairs(GRADIENT_DIR_KEYS) do
        BarScopeSet(key, directions[dir] == true, "MSUF2_GRADIENT_DIRECTION")
    end
    BarScopeSet("gradientDirection", direction, "MSUF2_GRADIENT_DIRECTION")
end

local PRIORITY_SINGLE = { "dispel", "aggro", "purge", "bossTarget" }
local PRIORITY_TYPE = { "dispel", "aggro", "purge", "bossTarget" }
local DISPEL_TYPE_PRIORITY_ALLOWED = { magic = true, curse = true, disease = true, poison = true, bleed = true }
local PRIORITY_LABELS = {
    dispel = "Dispel",
    aggro = "Aggro",
    purge = "Purge",
    bossTarget = "Boss Target",
    magic = "Magic",
    curse = "Curse",
    disease = "Disease",
    poison = "Poison",
    bleed = "Bleed",
}
local PRIORITY_COLORS = {
    dispel = { 0.25, 0.75, 1.00 },
    aggro = { 1.00, 0.50, 0.00 },
    purge = { 1.00, 0.85, 0.00 },
    bossTarget = { 1.00, 0.82, 0.00 },
    magic = { 0.20, 0.60, 1.00 },
    curse = { 0.60, 0.00, 1.00 },
    disease = { 0.60, 0.40, 0.00 },
    poison = { 0.00, 0.60, 0.00 },
    bleed = { 0.80, 0.10, 0.10 },
}
local PRIORITY_KEY_ALIAS = {
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
}

local function NormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return PRIORITY_KEY_ALIAS[key] or key
end

local function PriorityDefaults()
    return PRIORITY_SINGLE
end

local function PriorityAllowed(defaults)
    local allowed = {}
    for i = 1, #defaults do allowed[defaults[i]] = true end
    return allowed
end

local function PriorityOrder()
    local defaults = PriorityDefaults()
    local allowed = PriorityAllowed(defaults)
    local raw = BarScopeGet("hlPrioOrder", nil)
    if type(raw) ~= "table" and CurrentBarsScope() == "shared" then
        raw = G().highlightPrioOrder
    end
    local order = {}
    if type(raw) == "table" then
        local rawUsed = {}
        for i = 1, #raw do
            local value = NormalizePriorityKey(raw[i])
            if DISPEL_TYPE_PRIORITY_ALLOWED[value] then value = "dispel" end
            if allowed[value] and not rawUsed[value] then
                order[#order + 1] = value
                rawUsed[value] = true
            end
        end
    end
    local used = {}
    for i = 1, #order do used[order[i]] = true end
    for i = 1, #defaults do
        local value = defaults[i]
        if not used[value] then order[#order + 1] = value end
    end
    while #order > #defaults do order[#order] = nil end
    return order
end

local function PriorityColor(key)
    local fallback = PRIORITY_COLORS[key] or { 1, 1, 1 }
    local r, g, b = fallback[1], fallback[2], fallback[3]
    if key == "aggro" then
        r = BarScopeGet("hlAggroColorR", ReadG("aggroBorderColorR", ReadG("aggroBorderR", r)))
        g = BarScopeGet("hlAggroColorG", ReadG("aggroBorderColorG", ReadG("aggroBorderG", g)))
        b = BarScopeGet("hlAggroColorB", ReadG("aggroBorderColorB", ReadG("aggroBorderB", b)))
    elseif key == "purge" then
        r = BarScopeGet("hlPurgeColorR", ReadG("purgeBorderColorR", r))
        g = BarScopeGet("hlPurgeColorG", ReadG("purgeBorderColorG", g))
        b = BarScopeGet("hlPurgeColorB", ReadG("purgeBorderColorB", b))
    elseif key == "dispel" then
        r = BarScopeGet("hlDispelColorR", ReadG("dispelBorderColorR", r))
        g = BarScopeGet("hlDispelColorG", ReadG("dispelBorderColorG", g))
        b = BarScopeGet("hlDispelColorB", ReadG("dispelBorderColorB", b))
    end
    return tonumber(r) or fallback[1], tonumber(g) or fallback[2], tonumber(b) or fallback[3]
end

local function SetPriorityOrder(order)
    BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER")
    if CurrentBarsScope() == "shared" then
        G().highlightPrioOrder = order
    end
end

local GF_RENDERER_CONFLICT_SCOPES = {
    { kind = "party", db = "gf_party", label = "Party" },
    { kind = "raid", db = "gf_raid", label = "Raid" },
    { kind = "mythicraid", db = "gf_mythicraid", label = "Mythic Raid" },
}

local function GroupScopeConf(info)
    local gf = ns and ns.GF
    local conf = gf and gf.GetConf and gf.GetConf(info.kind)
    if not conf then
        local db = DB()
        conf = db and db[info.db]
    end
    return conf, gf
end

local function GroupScopeUsesBlizzardRenderer(info)
    local conf, gf = GroupScopeConf(info)
    if not conf then return false end
    if gf and type(gf.GetBlizzardAuraTypeFlags) == "function" then
        local buffs, debuffs, dispels, externals, privateAuras = gf.GetBlizzardAuraTypeFlags(conf)
        return buffs or debuffs or dispels or externals or privateAuras
    end
    local auras = conf.auras
    if not auras or auras.enabled == false then return false end
    return (auras.renderer or "BLIZZARD") ~= "CUSTOM"
end

local function GroupScopeBlocksDispelGlow(info)
    local conf, gf = GroupScopeConf(info)
    if not conf or conf.dispelEnabled == false then return false end
    local auras = conf.auras
    if not auras or auras.enabled == false or auras.blizzardDispelBorder == true then return false end
    if gf and type(gf.GetBlizzardAuraTypeFlags) == "function" then
        local _, _, dispels = gf.GetBlizzardAuraTypeFlags(conf)
        return dispels == true
    end
    if gf and type(gf.IsBlizzardAuraTypeEnabled) == "function" then
        return gf.IsBlizzardAuraTypeEnabled(conf, "dispels") == true
    end
    if (auras.renderer or "BLIZZARD") == "CUSTOM" then return false end
    local types = auras.blizzardTypes
    return type(types) ~= "table" or types.dispels ~= false
end

local function GroupBlizzardRendererActiveForKind(kind)
    kind = tostring(kind or ""):lower()
    if kind == "gf_party" then kind = "party" end
    if kind == "gf_raid" then kind = "raid" end
    if kind == "gf_mythicraid" then kind = "mythicraid" end
    for i = 1, #GF_RENDERER_CONFLICT_SCOPES do
        local info = GF_RENDERER_CONFLICT_SCOPES[i]
        if info.kind == kind or info.db == kind then
            return GroupScopeUsesBlizzardRenderer(info)
        end
    end
    return false
end

local function GroupBlizzardRendererBlocksDispelGlowForKind(kind)
    kind = tostring(kind or ""):lower()
    if kind == "gf_party" then kind = "party" end
    if kind == "gf_raid" then kind = "raid" end
    if kind == "gf_mythicraid" then kind = "mythicraid" end
    for i = 1, #GF_RENDERER_CONFLICT_SCOPES do
        local info = GF_RENDERER_CONFLICT_SCOPES[i]
        if info.kind == kind or info.db == kind then
            return GroupScopeBlocksDispelGlow(info)
        end
    end
    return false
end

local function GroupBlizzardRendererConflictLabels(scope)
    scope = NormalizeScopeKey(scope or "shared")
    local labels = {}
    for i = 1, #GF_RENDERER_CONFLICT_SCOPES do
        local info = GF_RENDERER_CONFLICT_SCOPES[i]
        if scope == "gf_party" and info.db ~= "gf_party" then
            -- skip
        elseif scope == "gf_raid" and info.db == "gf_party" then
            -- skip
        elseif scope ~= "shared" and scope ~= "gf_party" and scope ~= "gf_raid" then
            -- UnitFrame scopes are not blocked by GroupFrame Blizzard rendering.
        elseif GroupScopeBlocksDispelGlow(info) then
            labels[#labels + 1] = info.label
        end
    end
    return labels
end

local function HasGroupBlizzardRendererConflict(scope)
    return #GroupBlizzardRendererConflictLabels(scope) > 0
end

local function GroupBlizzardRendererConflictText(scope)
    scope = NormalizeScopeKey(scope or "shared")
    local labels = GroupBlizzardRendererConflictLabels(scope)
    if #labels == 0 then return nil end
    if scope == "gf_party" or scope == "gf_raid" then
        return "Dispel Glow is unavailable for this Group Frame scope while Blizzard owns dispel icons (" .. table.concat(labels, ", ") .. "). Enable Group Frames > Auras > MSUF Dispel Highlights or switch the renderer to Custom."
    end
    return "Unit Frames and Custom Group Frames can still use Dispel Glow. Group Frames where Blizzard owns dispel icons (" .. table.concat(labels, ", ") .. ") need Group Frames > Auras > MSUF Dispel Highlights enabled, or a Custom renderer."
end

local function NotifyDispelGlowBlizzardConflict(scope)
    local text = GroupBlizzardRendererConflictText(scope)
    if print and text then print("|cffffd700MSUF:|r " .. text) end
end

local function StopGroupDispelGlowForBlizzardConflict(scope)
    if not HasGroupBlizzardRendererConflict(scope) then return false end
    local gf = ns and ns.GF
    local stopGlow = _G.MSUF_GF_StopDispelGlow
    if gf and gf.frames and type(stopGlow) == "function" then
        for frame in pairs(gf.frames) do
            local kind = frame and frame._msufGFKind
            if GroupBlizzardRendererBlocksDispelGlowForKind(kind) then
                stopGlow(frame)
            end
        end
    end
    return true
end

local function RefreshBorderTestModes()
    if _G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown()) then
        return
    end
    local scope = CurrentBarsScope()
    if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
    if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
        _G.MSUF_SetDispelBorderTestMode(true, scope)
    end
    if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
        _G.MSUF_SetAggroBorderTestMode(true, scope)
    end
    if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
        _G.MSUF_SetPurgeBorderTestMode(true, scope)
    end
end

local function SetAbsorbTextureTest(enabled)
    if enabled and (_G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown())) then
        enabled = false
    end
    local scope = CurrentBarsScope()
    if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
    if type(_G.MSUF_SetAbsorbTextureTestMode) == "function" then
        _G.MSUF_SetAbsorbTextureTestMode(enabled and true or false, scope)
    else
        _G.MSUF_AbsorbTextureTestMode = enabled and true or false
        _G.MSUF_AbsorbTextureTestScope = enabled and scope or nil
    end
    if type(_G.MSUF_Bars_RefreshAbsorbTextureTestPreview) == "function" then
        _G.MSUF_Bars_RefreshAbsorbTextureTestPreview()
    else
        ApplyBars("MSUF2_ABSORB_TEST")
    end
end

local function ClearAbsorbTextureTest()
    local wasEnabled = _G.MSUF_AbsorbTextureTestMode and true or false
    if type(_G.MSUF_ClearAbsorbTextureTestMode) == "function" then
        _G.MSUF_ClearAbsorbTextureTestMode()
    elseif wasEnabled then
        _G.MSUF_AbsorbTextureTestMode = false
        _G.MSUF_AbsorbTextureTestScope = nil
    end
    if wasEnabled then
        if type(_G.MSUF_Bars_RefreshAbsorbTextureTestPreview) == "function" then
            _G.MSUF_Bars_RefreshAbsorbTextureTestPreview()
        else
            ApplyBars("MSUF2_ABSORB_TEST_CLEAR")
        end
    end
end

local function NormalizeGlowStyle(value)
    value = tostring(value or "PIXEL")
    if value == "pixel" then return "PIXEL" end
    if value == "auto" then return "AUTOCAST" end
    if value == "button" then return "PROC" end
    if value == "AUTOCAST" or value == "PROC" then return value end
    return "PIXEL"
end

local function SetControlEnabled(control, enabled)
    W.SetControlEnabled(control, enabled)
end

local function SetControlsEnabled(controls, enabled)
    W.SetControlsEnabled(controls, enabled)
end

local function ApplyFonts(reason)
    M.RequestGeneralApply(reason or "MSUF2_FONTS", { preview = true, applyAll = false })
    Call("MSUF_UpdateAllFonts_Immediate")
    Call("MSUF_RefreshAllIdentityColors")
    Call("MSUF_RefreshAllPowerTextColors")
    Call("MSUF_RefreshAllFrames")
    local gf = ns and ns.GF
    if gf then
        if type(gf.RefreshFonts) == "function" then pcall(gf.RefreshFonts) end
        if type(gf.MarkAllDirty) == "function" then pcall(gf.MarkAllDirty, (gf.DIRTY_FONT or 4) + (gf.DIRTY_LAYOUT or 32)) end
    end
end

function ApplyBars(reason)
    M.RequestGeneralApply(reason or "MSUF2_BARS", { preview = true, applyAll = false })
    Call("MSUF_UpdateAllBarTextures_Immediate")
    Call("MSUF_UpdateAllBarTextures")
    Call("MSUF_UpdateAbsorbBarTextures")
    Call("MSUF_InvalidateAbsorbCache")
    Call("MSUF_RefreshAllFrames")
    local gf = ns and ns.GF
    if gf then
        if type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
        if type(gf.MarkAllDirty) == "function" then pcall(gf.MarkAllDirty, (gf.DIRTY_VISUAL or 2) + (gf.DIRTY_LAYOUT or 32)) end
    end
end

local function ApplyCastbars(reason)
    M.RequestGeneralApply(reason or "MSUF2_CASTBARS", { castbar = true, preview = true, applyAll = false })
    Call("MSUF_UpdateCastbarVisuals")
    Call("MSUF_UpdateCastbarTextures_Immediate")
end

local GlobalPage = M.GlobalPage or {}
M.GlobalPage = GlobalPage
GlobalPage.UNIT_SCOPE_KEYS = UNIT_SCOPE_KEYS
GlobalPage.TEXT_SCOPE_KEYS = TEXT_SCOPE_KEYS
GlobalPage.POWER_BAR_SCOPE_UNITS = POWER_BAR_SCOPE_UNITS
GlobalPage.GRADIENT_DIRECTIONS = GRADIENT_DIRECTIONS
GlobalPage.GRADIENT_DIR_KEYS = GRADIENT_DIR_KEYS
GlobalPage.PRIORITY_SINGLE = PRIORITY_SINGLE
GlobalPage.PRIORITY_TYPE = PRIORITY_TYPE
GlobalPage.PRIORITY_LABELS = PRIORITY_LABELS
GlobalPage.PRIORITY_COLORS = PRIORITY_COLORS
GlobalPage.NormalizePriorityKey = NormalizePriorityKey
GlobalPage.Call = Call
GlobalPage.DB = DB
GlobalPage.G = G
GlobalPage.Bars = Bars
GlobalPage.Unit = Unit
GlobalPage.ReadG = ReadG
GlobalPage.Targeted = Targeted
GlobalPage.SetG = SetG
GlobalPage.ReadGBool = ReadGBool
GlobalPage.SetGBool = SetGBool
GlobalPage.ReadB = ReadB
GlobalPage.SetB = SetB
GlobalPage.SetUBool = SetUBool
GlobalPage.NormalizeScopeKey = NormalizeScopeKey
GlobalPage.ScopeDBKeys = ScopeDBKeys
GlobalPage.ScopeHasOverride = ScopeHasOverride
GlobalPage.ScopeSetOverride = ScopeSetOverride
GlobalPage.ScopeRead = ScopeRead
GlobalPage.ScopeWrite = ScopeWrite
GlobalPage.CurrentFontScope = CurrentFontScope
GlobalPage.CurrentBarsScope = CurrentBarsScope
GlobalPage.IsGFScope = IsGFScope
GlobalPage.IsTextScopeKey = IsTextScopeKey
GlobalPage.BarsFlagForKey = BarsFlagForKey
GlobalPage.FontScopeGet = FontScopeGet
GlobalPage.FontScopeSet = FontScopeSet
GlobalPage.BarScopeGet = BarScopeGet
GlobalPage.BarScopeSet = BarScopeSet
GlobalPage.BarScopeGetBars = BarScopeGetBars
GlobalPage.BarScopeSetBars = BarScopeSetBars
GlobalPage.NormalizeFontKey = NormalizeFontKey
GlobalPage.FontValues = FontValues
GlobalPage.ClearUFFontKeyOverrides = ClearUFFontKeyOverrides
GlobalPage.FontKeyGet = FontKeyGet
GlobalPage.FontKeySet = FontKeySet
GlobalPage.TextureValues = TextureValues
GlobalPage.BarsScopeHasOverride = BarsScopeHasOverride
GlobalPage.BarsScopeSetOverride = BarsScopeSetOverride
GlobalPage.CurrentPowerBarScopeUnit = CurrentPowerBarScopeUnit
GlobalPage.SmoothPowerGet = SmoothPowerGet
GlobalPage.SmoothPowerSet = SmoothPowerSet
GlobalPage.NormalizeHpMode = NormalizeHpMode
GlobalPage.NormalizePowerMode = NormalizePowerMode
GlobalPage.CurrentGradientDirection = CurrentGradientDirection
GlobalPage.CurrentGradientDirections = CurrentGradientDirections
GlobalPage.SetGradientDirection = SetGradientDirection
GlobalPage.ToggleGradientDirection = ToggleGradientDirection
GlobalPage.PriorityDefaults = PriorityDefaults
GlobalPage.PriorityAllowed = PriorityAllowed
GlobalPage.PriorityOrder = PriorityOrder
GlobalPage.PriorityColor = PriorityColor
GlobalPage.SetPriorityOrder = SetPriorityOrder
GlobalPage.GroupBlizzardRendererConflictLabels = GroupBlizzardRendererConflictLabels
GlobalPage.GroupBlizzardRendererActiveForKind = GroupBlizzardRendererActiveForKind
GlobalPage.GroupBlizzardRendererBlocksDispelGlowForKind = GroupBlizzardRendererBlocksDispelGlowForKind
GlobalPage.HasGroupBlizzardRendererConflict = HasGroupBlizzardRendererConflict
GlobalPage.GroupBlizzardRendererConflictText = GroupBlizzardRendererConflictText
GlobalPage.NotifyDispelGlowBlizzardConflict = NotifyDispelGlowBlizzardConflict
GlobalPage.StopGroupDispelGlowForBlizzardConflict = StopGroupDispelGlowForBlizzardConflict
GlobalPage.RefreshBorderTestModes = RefreshBorderTestModes
GlobalPage.SetAbsorbTextureTest = SetAbsorbTextureTest
GlobalPage.ClearAbsorbTextureTest = ClearAbsorbTextureTest
GlobalPage.NormalizeGlowStyle = NormalizeGlowStyle
GlobalPage.SetControlEnabled = SetControlEnabled
GlobalPage.SetControlsEnabled = SetControlsEnabled
GlobalPage.ApplyFonts = ApplyFonts
GlobalPage.ApplyBars = ApplyBars
GlobalPage.ApplyCastbars = ApplyCastbars

_G.MSUF_HasGroupBlizzardAuraRenderingConflict = HasGroupBlizzardRendererConflict
_G.MSUF_GroupBlizzardAuraRenderingBlocksDispelGlow = GroupBlizzardRendererBlocksDispelGlowForKind
_G.MSUF_StopGroupDispelGlowForBlizzardRendererConflict = StopGroupDispelGlowForBlizzardConflict

local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- GlobalPage helper module.
-- Provides DB readers/writers, scope override helpers, and apply fanout used by the global
-- fonts/bars/castbars/misc pages. Page files should reuse these helpers for consistent state.
local W = M.Widgets
local T = M.Theme
local VTP = M.ValueTextPairs
local function NormalizeControlPath(value)
    local path = tostring(value or "")
    path = path:gsub("([%l%d])([%u])", "%1_%2"):lower()
    path = path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return path
end
local function ControlMeta(pageKey, domain, semanticPath, classification, exact)
    local identity = table.concat({
        NormalizeControlPath(pageKey),
        NormalizeControlPath(domain),
        NormalizeControlPath(semanticPath),
    }, ".")
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local function RegisterControl(widget, meta, label, kind, values)
    if not (widget and type(meta) == "table" and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = {}
    for key, value in pairs(meta) do payload[key] = value end
    payload.label = label or payload.label
    payload.kind = kind or payload.kind
    payload.values = values or payload.values
    M.RegisterSearchWidget(widget, payload)
    return widget
end
local function Call(name, ...)
    local apply = M.ApplyService
    if apply and type(apply.CallGlobal) == "function" then return apply.CallGlobal(name, ...) end
    local fn = _G[name]
    if type(fn) == "function" then fn(...); return true end
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
local UNIT_SCOPE_KEYS = M.KeySetFromWords "player target targettarget focustarget focus pet boss"
local TEXT_SCOPE_KEYS = M.KeySetFromWords "hpTextMode textLeft textCenter textRight hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol hpTextReverse hpTextSeparator powerTextMode powerTextLeft powerTextCenter powerTextRight powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextSeparator"
local POWER_BAR_SCOPE_UNITS = M.KeySetFromWords "player target focus boss"
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
local CurrentBarsScope
local function GradientKeyActive(entry, key)
    if not (entry and entry.hlOverride == true and entry.gradientOverride == true) then return false end
    if entry.gradientOverrideVersion ~= 2 then return entry[key] ~= nil end
    return type(entry.gradientOverrideKeys) == "table" and entry.gradientOverrideKeys[key] == true
end
local function MarkGradientKey(entry, key)
    if not entry then return end
    entry.hlOverride, entry.gradientOverride, entry.gradientOverrideVersion = true, true, 2
    if type(entry.gradientOverrideKeys) ~= "table" then entry.gradientOverrideKeys = {} end
    entry.gradientOverrideKeys[key] = true
end
local function GradientScopeEntryValue(scope, key)
    if scope == "shared" or not ScopeHasOverride(scope, "hlOverride") then return nil, false end
    local db, keys = DB(), ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        local entry = db[keys[i]]
        if entry and entry[key] ~= nil and not GradientKeyActive(entry, key)
            and entry[key] ~= G()[key]
        then
            MarkGradientKey(entry, key)
        end
        if GradientKeyActive(entry, key) and entry[key] ~= nil then return entry[key], true end
    end
    return nil, false
end
local function GradientScopeGet(key, defaultValue, legacyKey)
    local scope = CurrentBarsScope()
    local value, found = GradientScopeEntryValue(scope, key)
    if found then return value end
    if legacyKey then
        value, found = GradientScopeEntryValue(scope, legacyKey)
        if found then return value end
    end
    value = G()[key]
    if value ~= nil then return value end
    if legacyKey then
        value = G()[legacyKey]
        if value ~= nil then return value end
    end
    return defaultValue
end
local function GradientScopeHasExplicit(key)
    local scope = CurrentBarsScope()
    if scope == "shared" then return G()[key] ~= nil end
    local _, found = GradientScopeEntryValue(scope, key)
    return found
end
local function GradientScopeSet(key, value)
    local scope = CurrentBarsScope()
    if scope == "shared" then
        G()[key] = value
        return
    end
    local db, keys = DB(), ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        local entryKey = keys[i]
        db[entryKey] = db[entryKey] or {}
        MarkGradientKey(db[entryKey], key)
        db[entryKey][key] = value
    end
end
local function CurrentFontScope()
    local g = G()
    local raw = g._fontScopeKey
    local scope = NormalizeScopeKey(raw or "shared")
    if raw ~= scope then g._fontScopeKey = scope end
    return scope
end
CurrentBarsScope = function()
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
    if IsTextScopeKey(key) and not IsGFScope(scope) then return "hpPowerTextOverride" end
    return "hlOverride"
end
local function ApplyFontsFor(scope, reason)
    scope = NormalizeScopeKey(scope)
    M.RequestGeneralApply(reason or "MSUF2_FONTS", {
        preview = true,
        applyAll = false,
        fonts = true,
        fontScope = scope,
    })
end
local function FontScopeGetFor(scope, key, default, rootKey)
    local shared = rootKey and DB() or G()
    return ScopeRead(NormalizeScopeKey(scope), "fontOverride", shared, rootKey or key, default)
end
local function FontScopeSetFor(scope, key, value, reason, rootKey, suppressApply)
    scope = NormalizeScopeKey(scope)
    local shared = rootKey and DB() or G()
    ScopeWrite(scope, "fontOverride", shared, rootKey or key, value)
    if suppressApply ~= true then ApplyFontsFor(scope, reason or "MSUF2_FONTS_SCOPE") end
end
local function FontOverrideGetFor(scope)
    scope = NormalizeScopeKey(scope)
    return scope ~= "shared" and ScopeHasOverride(scope, "fontOverride")
end
local function SeedGFFontOverride(scope)
    if not IsGFScope(scope) then return end
    local db, general = DB(), G()
    local enabled = db.shortenNames == true
    local side = general.shortenNameClipSide or "LEFT"
    local maxChars = tonumber(general.shortenNameMaxChars) or 6
    local noEllipsis = general.shortenNameShowDots == false
    local keys = ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        local scopeKey = keys[i]
        db[scopeKey] = db[scopeKey] or {}
        local entry = db[scopeKey]
        if entry.nameShortenEnabled == nil then entry.nameShortenEnabled = enabled end
        if entry.nameClipSide == nil then entry.nameClipSide = side end
        if entry.nameNoEllipsis == nil then entry.nameNoEllipsis = noEllipsis end
        if (tonumber(entry.nameMaxChars) or 0) <= 0 then entry.nameMaxChars = maxChars end
        entry.nameShortenOverride = nil
        entry._msufGFNameTruncationOverride = nil
    end
end
local function FontOverrideSetFor(scope, enabled, reason)
    scope = NormalizeScopeKey(scope)
    if scope == "shared" then return false end
    enabled = enabled and true or false
    ScopeSetOverride(scope, "fontOverride", enabled)
    if enabled then SeedGFFontOverride(scope) end
    ApplyFontsFor(scope, reason or "MSUF2_FONT_OVERRIDE")
    return enabled
end
local function FontOutlineGetFor(scope)
    scope = NormalizeScopeKey(scope)
    if IsGFScope(scope) then
        if ScopeHasOverride(scope, "fontOverride") then
            local db, keys = DB(), ScopeDBKeys(scope)
            for i = 1, #(keys or {}) do
                local entry = db[keys[i]]
                local value = entry and entry.fontOutline
                if value ~= nil then
                    if value == "" then return "NONE" end
                    if value == "NONE" or value == "THICKOUTLINE" then return value end
                    return "OUTLINE"
                end
            end
        end
        if G().noOutline == true then return "NONE" end
        if G().boldText == true then return "THICKOUTLINE" end
        return "OUTLINE"
    end
    if FontScopeGetFor(scope, "noOutline", false) then return "NONE" end
    if FontScopeGetFor(scope, "boldText", false) then return "THICKOUTLINE" end
    return "OUTLINE"
end
local function FontOutlineSetFor(scope, value, reason)
    scope = NormalizeScopeKey(scope)
    value = tostring(value or "OUTLINE"):upper()
    if value ~= "NONE" and value ~= "THICKOUTLINE" then value = "OUTLINE" end
    if value == "THICKOUTLINE" and FontScopeGetFor(scope, "fontSlug", false) == true then
        value = "OUTLINE"
    end
    if IsGFScope(scope) then
        ScopeWrite(scope, "fontOverride", G(), "fontOutline", value)
        ApplyFontsFor(scope, reason or "MSUF2_GF_FONT_OUTLINE")
        return value
    end
    ScopeWrite(scope, "fontOverride", G(), "boldText", value == "THICKOUTLINE")
    ScopeWrite(scope, "fontOverride", G(), "noOutline", value == "NONE")
    ApplyFontsFor(scope, reason or "MSUF2_FONT_OUTLINE")
    return value
end
local function FontShadowMetricsFor(scope)
    scope = NormalizeScopeKey(scope)
    local opacity = FontScopeGetFor(scope, "fontShadowOpacity", nil)
    local distance = FontScopeGetFor(scope, "fontShadowDistance", nil)
    local strength = FontScopeGetFor(scope, "fontShadowStrength", nil)
    local resolve = _G.MSUF_ResolveFontShadowMetrics
    if type(resolve) == "function" then return resolve(opacity, distance, strength) end
    local alpha = tonumber(opacity) or 1
    local pixels = tonumber(distance) or 1
    return alpha, pixels, -pixels
end
local function NormalizeFontTextColorKind(scope, kind)
    kind = tostring(kind or "name"):lower():gsub("[%s%-]+", "_")
    if kind == "group" or kind == "group_name" then return "group" end
    if kind == "name" or kind == "player" or kind == "player_name" then
        return IsGFScope(scope) and "group" or "player"
    end
    if kind == "npc" or kind == "npc_name" or kind == "boss" or kind == "boss_name" then return "npc" end
    if kind == "hp" or kind == "health" or kind == "health_text" then return "hp" end
    if kind == "power" or kind == "resource" or kind == "power_text" then return "power" end
    return nil
end
local function FontTextColorModeGetFor(scope, kind)
    scope = NormalizeScopeKey(scope)
    kind = NormalizeFontTextColorKind(scope, kind)
    if kind == "group" then
        if not ScopeHasOverride(scope, "fontOverride") then
            return G().nameClassColor == true and "CLASS" or "DEFAULT"
        end
        local value = tostring(FontScopeGetFor(scope, "nameColorMode", "DEFAULT") or "DEFAULT"):upper()
        if value == "CLASS" or value == "CUSTOM" then return value end
        return "DEFAULT"
    elseif kind == "player" then
        -- CUSTOM is stored in nameColorMode, the same key group frames use. The
        -- legacy nameClassColor boolean stays in sync on write, so the engine's
        -- fallback and older profiles keep resolving CLASS/DEFAULT correctly.
        if tostring(FontScopeGetFor(scope, "nameColorMode", "") or ""):upper() == "CUSTOM" then return "CUSTOM" end
        return FontScopeGetFor(scope, "nameClassColor", false) and "CLASS" or "DEFAULT"
    elseif kind == "npc" then
        if FontScopeGetFor(scope, "nameNpcClassColor", false) then return "CLASS" end
        return FontScopeGetFor(scope, "npcNameRed", false) and "NPC" or "DEFAULT"
    elseif kind == "hp" then
        local value = FontScopeGetFor(scope, "colorHealthTextByHealth", false)
        if value == "CLASS" then return "CLASS" end
        return (value == true or value == "HEALTH") and "HEALTH" or "DEFAULT"
    elseif kind == "power" then
        return FontScopeGetFor(scope, "colorPowerTextByType", false) and "RESOURCE" or "DEFAULT"
    end
    return "DEFAULT"
end
local function FontTextColorModeSetFor(scope, kind, value, reason)
    scope = NormalizeScopeKey(scope)
    kind = NormalizeFontTextColorKind(scope, kind)
    value = tostring(value or "DEFAULT"):upper()
    if kind == "group" then
        if value ~= "CLASS" and value ~= "CUSTOM" then value = "DEFAULT" end
        ScopeWrite(scope, "fontOverride", G(), "nameColorMode", value)
        ApplyFontsFor(scope, reason or "MSUF2_GF_NAME_COLOR")
    elseif kind == "player" then
        if value ~= "CLASS" and value ~= "CUSTOM" then value = "DEFAULT" end
        ScopeWrite(scope, "fontOverride", G(), "nameColorMode", value)
        ScopeWrite(scope, "fontOverride", G(), "nameClassColor", value == "CLASS")
        ApplyFontsFor(scope, reason or "MSUF2_NAME_CLASS_COLOR")
    elseif kind == "npc" then
        if value ~= "CLASS" and value ~= "NPC" then value = "DEFAULT" end
        ScopeWrite(scope, "fontOverride", G(), "nameNpcClassColor", value == "CLASS")
        ScopeWrite(scope, "fontOverride", G(), "npcNameRed", value == "NPC")
        ApplyFontsFor(scope, reason or "MSUF2_NPC_NAME_COLOR")
    elseif kind == "hp" then
        if value ~= "CLASS" and value ~= "HEALTH" then value = "DEFAULT" end
        ScopeWrite(scope, "fontOverride", G(), "colorHealthTextByHealth",
            value == "CLASS" and "CLASS" or (value == "HEALTH"))
        ApplyFontsFor(scope, reason or "MSUF2_HP_TEXT_COLOR")
    elseif kind == "power" then
        value = value == "RESOURCE" and "RESOURCE" or "DEFAULT"
        ScopeWrite(scope, "fontOverride", G(), "colorPowerTextByType", value == "RESOURCE")
        ApplyFontsFor(scope, reason or "MSUF2_POWER_TEXT_COLOR")
    else
        return nil
    end
    return value
end
local function FontScopeGet(key, default, rootKey)
    return FontScopeGetFor(CurrentFontScope(), key, default, rootKey)
end
local function FontScopeSet(key, value, reason, rootKey)
    FontScopeSetFor(CurrentFontScope(), key, value, reason, rootKey)
end
local function BarScopeGet(key, default)
    local scope = CurrentBarsScope()
    return ScopeRead(scope, BarsFlagForKey(scope, key), G(), key, default)
end
local function BarScopeSet(key, value, reason, suppressApply)
    local scope = CurrentBarsScope()
    ScopeWrite(scope, BarsFlagForKey(scope, key), G(), key, value)
    if suppressApply ~= true then
        M.RequestGeneralApply(reason or "MSUF2_BARS_SCOPE_VALUE", { preview = true, applyAll = false, bars = true, barsScope = scope })
    end
end
local function BarScopeGetBars(key, default)
    return ScopeRead(CurrentBarsScope(), "hlOverride", Bars(), key, default)
end
local function BarScopeSetBars(key, value, reason, suppressApply)
    local scope = CurrentBarsScope()
    ScopeWrite(scope, "hlOverride", Bars(), key, value)
    if suppressApply ~= true then
        M.RequestGeneralApply(reason or "MSUF2_BARS_SCOPE_BAR_VALUE", { preview = true, applyAll = false, bars = true, barsScope = scope })
    end
end
local function NormalizeFontKey(key)
    local fn = _G.MSUF_NormalizeFontKey or (MSUF and MSUF.MSUF_NormalizeFontKey)
    if type(fn) == "function" then return fn(key) end
    return key
end
local function FontSelectionValue(key, path)
    key = NormalizeFontKey(key)
    local normalizePath = _G.MSUF_NormalizeFontPath
    if type(normalizePath) == "function" then
        path = normalizePath(path)
        local direct = normalizePath(key)
        if type(direct) == "string" and direct ~= "" and direct:find("\\", 1, true) then return direct end
    end
    if type(path) == "string" and path ~= "" then return path end
    if type(key) == "string" and key ~= "" then
        local resolveKeyPath = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
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
    local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
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
local function MenuFontValues()
    local out = {
        { value = "", text = "Blizzard default" },
    }
    local fonts = FontValues(false)
    for i = 1, #(fonts or {}) do
        out[#out + 1] = fonts[i]
    end
    return out
end
local function MenuFontKeyGet()
    local value = ReadG("menuFontKey", "")
    if value == nil or value == "" then return "" end
    return FontSelectionValue(value)
end
local function MenuFontKeySet(value)
    if value == nil or value == "" then
        G().menuFontKey = ""
        return
    end
    G().menuFontKey = FontSelectionValue(value) or ""
end
local TextureValues = M.StatusBarTextureItems
local GLOBAL_SCOPE_VALUES = VTP "shared=Shared|player=Player|target=Target|targettarget=ToT|focustarget=Focus Target|focus=Focus|pet=Pet|boss=Boss|gf_party=Party|gf_raid=Raid"
local function CurrentPowerBarScopeUnit()
    local key = CurrentBarsScope()
    return POWER_BAR_SCOPE_UNITS[key] and key or nil
end
local function ScopeOverrideLabels(values, hasOverride)
    local active = {}
    if type(values) ~= "table" or type(hasOverride) ~= "function" then return active end
    for i = 1, #values do
        local item = values[i]
        if item.value ~= "shared" and hasOverride(item.value) then active[#active + 1] = M.Tr(item.text or "") end
    end
    return active
end
local function BuildScopeOverrideSection(ctx, builder, opts)
    if not (W and T and ctx and builder and type(opts) == "table") then return nil end
    local values = opts.values or GLOBAL_SCOPE_VALUES
    local scopeOpts = {
        values = values,
        width = ctx.width,
        getValue = opts.getValue,
        setValue = opts.setValue,
        hasOverride = opts.hasOverride,
    }
    local metrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, scopeOpts)
    local overrideY = math.min(-58, ((metrics and metrics.bottomY) or -40) - 18)
    local hintY = overrideY - 34
    local scope = builder:Section("", math.max(opts.minHeight or 128, math.abs(hintY) + (opts.heightPad or 42)))
    if scope.title then scope.title:Hide() end
    local segment = W.ScopeOverrideBar(ctx, scope, scopeOpts)
    RegisterControl(segment, opts.selectorMeta, opts.selectorLabel or "Editing:", "segment", values)
    local override = W.ToggleAt(scope, opts.toggleLabel or "Use custom settings for this scope", 14, overrideY, opts.toggleWidth or 260)
    M.BindBoolWidget(ctx, override, opts.getOverride or function()
        local current = scopeOpts.getValue and scopeOpts.getValue()
        return current ~= "shared" and opts.hasOverride and opts.hasOverride(current)
    end, opts.setOverride or M.Noop, opts.overrideMeta)
    local overrideInfo = W.Text(scope, "", 14, overrideY, ctx.width - 130, T.colors.text)
    local reset = T.Button(scope, opts.resetLabel or "Reset", opts.resetWidth or 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -16, overrideY + 8)
    T.CenterButtonLabel(reset)
    if type(opts.reset) == "function" then reset:SetScript("OnClick", opts.reset) end
    RegisterControl(reset, opts.resetMeta, opts.resetLabel or "Reset", "button")
    local hint = W.Text(scope, opts.hint or "", 14, hintY, ctx.width - 28, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local current = scopeOpts.getValue and scopeOpts.getValue() or "shared"
        local active = (type(opts.activeLabels) == "function" and opts.activeLabels()) or ScopeOverrideLabels(values, opts.hasOverride)
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        overrideInfo:SetText("|cffffffff" .. M.Tr("Overrides:") .. "|r " .. (#active > 0 and table.concat(active, ", ") or M.Tr("None")))
        if type(opts.updateHint) == "function" then opts.updateHint(hint, current, active, shared) end
        if segment and segment.Refresh then segment:Refresh() end
        hint:SetWidth(ctx.width - 28)
    end)
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(scope, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = builder,
            ctx = ctx,
            flowGap = 12,
        })
    end
    return {
        section = scope,
        segment = segment,
        override = override,
        overrideInfo = overrideInfo,
        reset = reset,
        hint = hint,
        metrics = metrics,
        overrideY = overrideY,
        hintY = hintY,
    }
end
local function SmoothPowerGet()
    local key = CurrentPowerBarScopeUnit()
    if key then
        local u = Unit(key)
        if u.powerSmoothFill ~= nil then return u.powerSmoothFill == true end
        if key == "player" then return ReadB("smoothPowerBar", false) == true end
        return false
    end
    return ReadB("smoothPowerBar", false) == true
end
local function SmoothPowerSet(enabled, reason)
    enabled = enabled and true or false
    reason = reason or "MSUF2_BARS_SMOOTH_POWER"
    local key = CurrentPowerBarScopeUnit()
    if key then
        local conf = Unit(key)
        if conf.powerSmoothFill == enabled and (not enabled or conf.powerChunkedFill == false) then return end
        conf.powerSmoothFill = enabled
        if enabled then conf.powerChunkedFill = false end
        M.RequestUnitApply(key, reason, { preview = true, power = true })
        return
    end
    local bars = Bars()
    if bars.smoothPowerBar == enabled and (not enabled or bars.chunkedPowerBar == false) then return end
    bars.smoothPowerBar = enabled
    if enabled then bars.chunkedPowerBar = false end
    -- Shared smooth power is a Player fallback. A targeted Player apply is
    -- required to recompile the spec and update StatusBar interpolation live.
    M.RequestUnitApply("player", reason, { preview = true, power = true })
end
local function ChunkedPowerGet()
    local key = CurrentPowerBarScopeUnit()
    if key then
        local u = Unit(key)
        if u.powerChunkedFill ~= nil then return u.powerChunkedFill == true end
        if key == "player" then return ReadB("chunkedPowerBar", false) == true end
        return false
    end
    return ReadB("chunkedPowerBar", false) == true
end
local function ChunkedPowerSet(enabled, reason)
    enabled = enabled and true or false
    reason = reason or "MSUF2_BARS_CHUNKED_POWER"
    local key = CurrentPowerBarScopeUnit()
    if key then
        local conf = Unit(key)
        if conf.powerChunkedFill == enabled and (not enabled or conf.powerSmoothFill == false) then return end
        conf.powerChunkedFill = enabled
        if enabled then conf.powerSmoothFill = false end
        M.RequestUnitApply(key, reason, { preview = true, power = true })
        return
    end
    local bars = Bars()
    if bars.chunkedPowerBar == enabled and (not enabled or bars.smoothPowerBar == false) then return end
    bars.chunkedPowerBar = enabled
    if enabled then bars.smoothPowerBar = false end
    M.RequestUnitApply("player", reason, { preview = true, power = true })
end
local NormalizeHpMode = M.NormalizeHpMode
local NormalizePowerMode = M.NormalizePowerMode
local ApplyBars
local GRADIENT_DIR_KEYS = {
    RIGHT = "gradientDirRight",
    LEFT = "gradientDirLeft",
    UP = "gradientDirUp",
    DOWN = "gradientDirDown",
}
local PRIORITY_SINGLE = { "dispel", "aggro", "purge", "bossTarget" }
local DISPEL_TYPE_PRIORITY_ALLOWED = M.KeySetFromWords "magic curse disease poison bleed"
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
    if type(raw) ~= "table" then raw = BarScopeGet("highlightPrioOrder", nil) end
    if type(raw) ~= "table" and CurrentBarsScope() == "shared" then raw = G().highlightPrioOrder end
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
        r = ReadG("hlAggroColorR", ReadG("aggroBorderColorR", ReadG("aggroBorderR", r)))
        g = ReadG("hlAggroColorG", ReadG("aggroBorderColorG", ReadG("aggroBorderG", g)))
        b = ReadG("hlAggroColorB", ReadG("aggroBorderColorB", ReadG("aggroBorderB", b)))
    elseif key == "purge" then
        r = ReadG("hlPurgeColorR", ReadG("purgeBorderColorR", r))
        g = ReadG("hlPurgeColorG", ReadG("purgeBorderColorG", g))
        b = ReadG("hlPurgeColorB", ReadG("purgeBorderColorB", b))
    end
    return tonumber(r) or fallback[1], tonumber(g) or fallback[2], tonumber(b) or fallback[3]
end
local function SetPriorityOrder(order)
    BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER")
    if CurrentBarsScope() == "shared" then
        G().hlPrioOrder = order
        G().highlightPrioOrder = order
    end
end
local function RefreshBorderTestModes()
    if _G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown()) then return end
    local scope = CurrentBarsScope()
    if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" or scope == "gf_mythicraid" then scope = "raid" end
    if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(true, scope) end
    if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then _G.MSUF_SetAggroBorderTestMode(true, scope) end
    if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(true, scope) end
end
local function CurrentAbsorbTestScope()
    local scope = CurrentBarsScope()
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" or scope == "gf_mythicraid" then return "raid" end
    return scope
end
local function IsAbsorbTextureTestEnabled(category)
    local scope = CurrentAbsorbTestScope()
    if type(_G.MSUF_ShouldShowAbsorbTextureTest) == "function" then
        return _G.MSUF_ShouldShowAbsorbTextureTest(nil, scope, category) == true
    end
    return _G.MSUF_AbsorbTextureTestMode == true
end
local function SetAbsorbTextureTest(enabled, category)
    if enabled and (_G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown())) then enabled = false end
    local scope = CurrentAbsorbTestScope()
    if type(_G.MSUF_SetAbsorbTextureTestMode) == "function" then
        _G.MSUF_SetAbsorbTextureTestMode(enabled and true or false, scope, category)
    else
        ExportPublic("MSUF_AbsorbTextureTestMode", enabled and true or false)
        ExportPublic("MSUF_AbsorbTextureTestScope", enabled and scope or nil)
    end
    if category == "tempMaxHealth" and type(_G.MSUF_RefreshTempMaxHealth) == "function" then
        _G.MSUF_RefreshTempMaxHealth(scope, "MSUF2_TEMP_MAX_HEALTH_TEST")
        if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh("MSUF2_TEMP_MAX_HEALTH_TEST")
        end
        if type(M.RefreshGFNativePreviews) == "function" then
            M.RefreshGFNativePreviews("MSUF2_TEMP_MAX_HEALTH_TEST")
        end
        return
    elseif type(_G.MSUF_RefreshPredictionBars) == "function" then
        _G.MSUF_RefreshPredictionBars(scope, "MSUF2_PREDICTION_TEST")
    end
    if type(_G.MSUF_Bars_RefreshAbsorbTextureTestPreview) == "function" then
        _G.MSUF_Bars_RefreshAbsorbTextureTestPreview()
    else
        ApplyBars("MSUF2_PREDICTION_TEST")
    end
end
local function ClearAbsorbTextureTest()
    local wasEnabled = _G.MSUF_AbsorbTextureTestMode and true or false
    if type(_G.MSUF_ClearAbsorbTextureTestMode) == "function" then
        _G.MSUF_ClearAbsorbTextureTestMode()
    elseif wasEnabled then
        ExportPublic("MSUF_AbsorbTextureTestMode", false)
        ExportPublic("MSUF_AbsorbTextureTestScope", nil)
    end
    if wasEnabled then
        if type(_G.MSUF_RefreshPredictionBars) == "function" then
            _G.MSUF_RefreshPredictionBars(nil, "MSUF2_ABSORB_TEST_CLEAR")
        end
        if type(_G.MSUF_RefreshTempMaxHealth) == "function" then
            _G.MSUF_RefreshTempMaxHealth(nil, "MSUF2_TEMP_MAX_HEALTH_TEST")
        end
        if type(_G.MSUF_Bars_RefreshAbsorbTextureTestPreview) == "function" then
            _G.MSUF_Bars_RefreshAbsorbTextureTestPreview()
        else
            ApplyBars("MSUF2_ABSORB_TEST_CLEAR")
        end
    end
end
local SetControlEnabled = W.SetControlEnabled
local SetControlsEnabled = W.SetControlsEnabled
local function ApplyFonts(reason)
    ApplyFontsFor(CurrentFontScope(), reason)
end
function ApplyBars(reason)
    M.RequestGeneralApply(reason or "MSUF2_BARS", { preview = true, applyAll = false, bars = true, barsScope = CurrentBarsScope() })
end
local function ApplyCastbars(reason)
    M.RequestGeneralApply(reason or "MSUF2_CASTBARS", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
end
local GlobalPage = M.GlobalPage or {}
M.GlobalPage = GlobalPage
M.Assign(GlobalPage, {
    UNIT_SCOPE_KEYS = UNIT_SCOPE_KEYS, GRADIENT_DIR_KEYS = GRADIENT_DIR_KEYS, PRIORITY_LABELS = PRIORITY_LABELS,
    NormalizePriorityKey = NormalizePriorityKey, Call = Call, DB = DB, G = G, Bars = Bars, Unit = Unit,
    ReadG = ReadG, Targeted = Targeted, SetG = SetG, ReadGBool = ReadGBool, SetGBool = SetGBool,
    ReadB = ReadB, SetB = SetB, NormalizeScopeKey = NormalizeScopeKey, ScopeDBKeys = ScopeDBKeys,
    ScopeHasOverride = ScopeHasOverride, ScopeSetOverride = ScopeSetOverride, ScopeRead = ScopeRead, ScopeWrite = ScopeWrite,
    GradientKeyActive = GradientKeyActive, MarkGradientKey = MarkGradientKey,
    GradientScopeGet = GradientScopeGet, GradientScopeSet = GradientScopeSet, GradientScopeHasExplicit = GradientScopeHasExplicit,
    CurrentFontScope = CurrentFontScope, CurrentBarsScope = CurrentBarsScope, IsGFScope = IsGFScope, BarsFlagForKey = BarsFlagForKey,
    ApplyFontsFor = ApplyFontsFor, FontScopeGetFor = FontScopeGetFor, FontScopeSetFor = FontScopeSetFor,
    FontOverrideGetFor = FontOverrideGetFor, FontOverrideSetFor = FontOverrideSetFor,
    FontOutlineGetFor = FontOutlineGetFor, FontOutlineSetFor = FontOutlineSetFor,
    FontShadowMetricsFor = FontShadowMetricsFor,
    FontTextColorModeGetFor = FontTextColorModeGetFor, FontTextColorModeSetFor = FontTextColorModeSetFor,
    FontScopeGet = FontScopeGet, FontScopeSet = FontScopeSet, BarScopeGet = BarScopeGet, BarScopeSet = BarScopeSet,
    BarScopeGetBars = BarScopeGetBars, BarScopeSetBars = BarScopeSetBars, NormalizeFontKey = NormalizeFontKey,
    FontValues = FontValues, FontKeyGet = FontKeyGet, FontKeySet = FontKeySet,
    MenuFontValues = MenuFontValues, MenuFontKeyGet = MenuFontKeyGet, MenuFontKeySet = MenuFontKeySet,
    TextureValues = TextureValues,
    ControlMeta = ControlMeta, RegisterControl = RegisterControl,
    SCOPE_VALUES = GLOBAL_SCOPE_VALUES, CurrentPowerBarScopeUnit = CurrentPowerBarScopeUnit,
    BuildScopeOverrideSection = BuildScopeOverrideSection, SmoothPowerGet = SmoothPowerGet, SmoothPowerSet = SmoothPowerSet,
    ChunkedPowerGet = ChunkedPowerGet, ChunkedPowerSet = ChunkedPowerSet,
    NormalizeHpMode = NormalizeHpMode, NormalizePowerMode = NormalizePowerMode,
    PriorityOrder = PriorityOrder, PriorityColor = PriorityColor, SetPriorityOrder = SetPriorityOrder,
    RefreshBorderTestModes = RefreshBorderTestModes, SetAbsorbTextureTest = SetAbsorbTextureTest,
    IsAbsorbTextureTestEnabled = IsAbsorbTextureTestEnabled,
    ClearAbsorbTextureTest = ClearAbsorbTextureTest, SetControlEnabled = SetControlEnabled, SetControlsEnabled = SetControlsEnabled,
    ApplyFonts = ApplyFonts, ApplyBars = ApplyBars, ApplyCastbars = ApplyCastbars,
})

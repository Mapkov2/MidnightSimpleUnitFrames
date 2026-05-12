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
    focus = true,
    pet = true,
    boss = true,
}

local TEXT_SCOPE_KEYS = {
    hpTextMode = true,
    hpTextReverse = true,
    hpTextSeparator = true,
    hpTextSpacerEnabled = true,
    hpTextSpacerX = true,
    hpTextAnchor = true,
    powerTextMode = true,
    powerTextSeparator = true,
    powerTextSpacerEnabled = true,
    powerTextSpacerX = true,
    powerTextAnchor = true,
}

local POWER_BAR_SCOPE_UNITS = {
    player = true,
    target = true,
    focus = true,
    boss = true,
}

local function NormalizeScopeKey(scope)
    scope = tostring(scope or "shared")
    if scope == "party" then return "gf_party" end
    if scope == "raid" or scope == "mythic" or scope == "mythicraid" then return "gf_raid" end
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
    return NormalizeScopeKey(ReadG("_fontScopeKey", "shared"))
end

local function CurrentBarsScope()
    return NormalizeScopeKey(ReadG("hpPowerTextSelectedKey", "shared"))
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

local function FontValues(includeGlobalDefault)
    local out, used = {}, {}
    if includeGlobalDefault then
        out[#out + 1] = { value = "", text = "(Global Default)" }
        used[""] = true
    end
    for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
        local key = NormalizeFontKey(info.key)
        if key and not used[key] then
            out[#out + 1] = { value = key, text = info.name or key }
            used[key] = true
        end
    end
    local LSM = (ns and ns.LSM) or _G.MSUF_LSM
    if LSM and type(LSM.List) == "function" then
        local names = LSM:List("font")
        table.sort(names)
        for i = 1, #names do
            local key = NormalizeFontKey(names[i])
            if key and not used[key] then
                out[#out + 1] = { value = names[i], text = names[i] }
                used[key] = true
            end
        end
    end
    if #out == 0 then
        out[1] = { value = "FRIZQT", text = "Friz Quadrata" }
    end
    return out
end

local function ClearUFFontKeyOverrides()
    local db = DB()
    for key in pairs(UNIT_SCOPE_KEYS) do
        if type(db[key]) == "table" then db[key].fontKey = nil end
    end
end

local function FontKeyGet()
    local scope = CurrentFontScope()
    if IsGFScope(scope) then
        local keys = ScopeDBKeys(scope)
        local db = DB()
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if entry and entry.fontKey ~= nil then return NormalizeFontKey(entry.fontKey) end
        end
        return ""
    end
    return NormalizeFontKey(ReadG("fontKey", "FRIZQT"))
end

local function FontKeySet(value)
    local scope = CurrentFontScope()
    if IsGFScope(scope) then
        ScopeWrite(scope, "fontOverride", {}, "fontKey", NormalizeFontKey(value or ""))
        return
    end
    G().fontKey = NormalizeFontKey(value or "FRIZQT")
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

local function SetGradientDirection(direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    for dir, key in pairs(GRADIENT_DIR_KEYS) do
        BarScopeSet(key, dir == direction, "MSUF2_GRADIENT_DIRECTION")
    end
    BarScopeSet("gradientDirection", direction, "MSUF2_GRADIENT_DIRECTION")
end

local PRIORITY_SINGLE = { "dispel", "aggro", "purge", "bossTarget" }
local PRIORITY_TYPE = { "magic", "curse", "disease", "poison", "bleed", "aggro", "purge", "bossTarget" }
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

local function PriorityDefaults()
    return tostring(BarScopeGet("hlDispelColorMode", "SINGLE")) == "TYPE" and PRIORITY_TYPE or PRIORITY_SINGLE
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
        for i = 1, #raw do
            local value = raw[i]
            if allowed[value] then
                order[#order + 1] = value
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
        r = BarScopeGet("hlAggroColorR", ReadG("aggroBorderColorR", r))
        g = BarScopeGet("hlAggroColorG", ReadG("aggroBorderColorG", g))
        b = BarScopeGet("hlAggroColorB", ReadG("aggroBorderColorB", b))
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

local function RefreshBorderTestModes()
    local scope = CurrentBarsScope()
    if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
    if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
        _G.MSUF_SetDispelBorderTestMode(true, scope)
    end
    if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
        _G.MSUF_SetAggroBorderTestMode(true, scope)
    end
end

local function SetAbsorbTextureTest(enabled)
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
    if type(_G.MSUF_ClearAbsorbTextureTestMode) == "function" then
        _G.MSUF_ClearAbsorbTextureTestMode()
    elseif _G.MSUF_AbsorbTextureTestMode then
        _G.MSUF_AbsorbTextureTestMode = false
        _G.MSUF_AbsorbTextureTestScope = nil
        ApplyBars("MSUF2_ABSORB_TEST_CLEAR")
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
    if not control then return end
    enabled = enabled and true or false
    if control.EnableMouse then control:EnableMouse(enabled) end
    if control.SetEnabled then control:SetEnabled(enabled) end
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    if control._msuf2Title and control._msuf2Title.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        control._msuf2Title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if control.editBox then
        if control.editBox.EnableMouse then control.editBox:EnableMouse(enabled) end
        if control.editBox.SetAlpha then control.editBox:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            if btn.SetEnabled then btn:SetEnabled(enabled) end
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
    if control.buttons then
        for i = 1, #control.buttons do
            local btn = control.buttons[i]
            if btn.SetEnabled then btn:SetEnabled(enabled) end
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
end

local function SetControlsEnabled(controls, enabled)
    for i = 1, #(controls or {}) do
        SetControlEnabled(controls[i], enabled)
    end
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

local function BuildFonts(ctx)
    local b = W.PageBuilder(ctx)

    local scopeValues = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "targettarget", text = "ToT" },
        { value = "focus", text = "Focus" },
        { value = "pet", text = "Pet" },
        { value = "boss", text = "Boss" },
        { value = "gf_party", text = "Party" },
        { value = "gf_raid", text = "Raid" },
    }

    local scope = b:Section("", 128)
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, {
        values = scopeValues,
        getValue = function() return CurrentFontScope() end,
        setValue = function(v)
            G()._fontScopeKey = NormalizeScopeKey(v)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "fontOverride")
        end,
    })

    local override = W.ToggleAt(scope, "Override shared settings", 14, -58, 220)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentFontScope()
            return key ~= "shared" and ScopeHasOverride(key, "fontOverride")
        end,
        function(v)
            local key = CurrentFontScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "fontOverride", v)
                ApplyFonts("MSUF2_FONT_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    local overrideInfo = W.Text(scope, "", 14, -58, ctx.width - 130, T.colors.text)
    local reset = T.Button(scope, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -14, -50)
    reset._msuf2Label:ClearAllPoints()
    reset._msuf2Label:SetPoint("CENTER", reset, "CENTER", 0, 0)
    reset._msuf2Label:SetJustifyH("CENTER")
    reset:SetScript("OnClick", function()
        for i = 1, #scopeValues do
            local key = scopeValues[i].value
            if key ~= "shared" then ScopeSetOverride(key, "fontOverride", false) end
        end
        ApplyFonts("MSUF2_FONT_RESET_OVERRIDES")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)
    local hint = W.Text(scope, "Shared baseline plus per-unit and group-frame font overrides.", 14, -92, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentFontScope()
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared" and ScopeHasOverride(item.value, "fontOverride") then active[#active + 1] = item.text end
        end
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        overrideInfo:SetText("|cffffffffOverrides:|r " .. (#active > 0 and table.concat(active, ", ") or "None"))
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local font = b:CollapsibleSection("fonts_global_font", "Global Font", 112, true)
    local fontDrop = W.Dropdown(font, "Font (SharedMedia)", function() return FontValues(IsGFScope(CurrentFontScope())) end, 340)
    M.BindDropdown(ctx, fontDrop,
        function() return FontKeyGet() end,
        function(v)
            FontKeySet(v)
            M.RequestGeneralApply("MSUF2_FONT_KEY", { preview = true, applyAll = false })
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then _G.MSUF_NormalizeStoredFontKeys() end
            ApplyFonts("MSUF2_FONT_KEY")
        end)

    local text = b:CollapsibleSection("fonts_text_style", "Text Style", 212, true)
    local fontSize = W.Slider(text, "Font size", 6, 32, 1, 300)
    M.BindSlider(ctx, fontSize,
        function() return tonumber(FontScopeGet("fontSize", 14)) or 14 end,
        function(v)
            FontScopeSet("fontSize", floor((tonumber(v) or 14) + 0.5), "MSUF2_FONT_SIZE")
            ApplyFonts("MSUF2_FONT_SIZE")
        end)

    local outline = W.Segment(text, "Outline", {
        { value = "OUTLINE", text = "Outline" },
        { value = "THICKOUTLINE", text = "Thick Outline" },
        { value = "NONE", text = "None" },
    }, 420)
    M.BindSegment(ctx, outline,
        function()
            if IsGFScope(CurrentFontScope()) then
                local v = FontScopeGet("fontOutline", "OUTLINE")
                if v == "" then return "OUTLINE" end
                return v or "OUTLINE"
            end
            if FontScopeGet("noOutline", false) then return "NONE" end
            if FontScopeGet("boldText", false) then return "THICKOUTLINE" end
            return "OUTLINE"
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then
                FontScopeSet("fontOutline", v or "OUTLINE", "MSUF2_GF_FONT_OUTLINE")
                ApplyFonts("MSUF2_GF_FONT_OUTLINE")
                return
            end
            FontScopeSet("boldText", v == "THICKOUTLINE", "MSUF2_FONT_OUTLINE")
            FontScopeSet("noOutline", v == "NONE", "MSUF2_FONT_OUTLINE")
            ApplyFonts("MSUF2_FONT_OUTLINE")
        end)

    local shadow = W.Segment(text, "Text shadow", {
        { value = "ON", text = "On" },
        { value = "OFF", text = "Off" },
    }, 260)
    M.BindSegment(ctx, shadow,
        function() return FontScopeGet("textBackdrop", true) and "ON" or "OFF" end,
        function(v)
            FontScopeSet("textBackdrop", v == "ON", "MSUF2_FONT_SHADOW")
            ApplyFonts("MSUF2_FONT_SHADOW")
        end)

    local colors = b:CollapsibleSection("fonts_name_power_colors", "Name & Power Colors", 220, true)
    local nameColor = W.Dropdown(colors, "Player Name Color", {
        { value = "DEFAULT", text = "Default (Font Color)" },
        { value = "CLASS", text = "Class Color" },
    }, 280)
    M.BindDropdown(ctx, nameColor,
        function()
            if IsGFScope(CurrentFontScope()) then
                return FontScopeGet("nameColorMode", "DEFAULT") == "CLASS" and "CLASS" or "DEFAULT"
            end
            return FontScopeGet("nameClassColor", false) and "CLASS" or "DEFAULT"
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then
                FontScopeSet("nameColorMode", v == "CLASS" and "CLASS" or "DEFAULT", "MSUF2_GF_NAME_COLOR")
                ApplyFonts("MSUF2_GF_NAME_COLOR")
                return
            end
            FontScopeSet("nameClassColor", v == "CLASS", "MSUF2_NAME_CLASS_COLOR")
            ApplyFonts("MSUF2_NAME_CLASS_COLOR")
        end)
    local npcColor = W.Dropdown(colors, "NPC / Boss Name Color", {
        { value = "DEFAULT", text = "Default (Font Color)" },
        { value = "NPC", text = "NPC / Reaction Color" },
    }, 280)
    M.BindDropdown(ctx, npcColor,
        function() return FontScopeGet("npcNameRed", false) and "NPC" or "DEFAULT" end,
        function(v)
            FontScopeSet("npcNameRed", v == "NPC", "MSUF2_NPC_RED")
            ApplyFonts("MSUF2_NPC_RED")
        end)
    local powerColor = W.Dropdown(colors, "Power Text Color", {
        { value = "DEFAULT", text = "Default (Font Color)" },
        { value = "RESOURCE", text = "By Power Type" },
    }, 280)
    M.BindDropdown(ctx, powerColor,
        function() return FontScopeGet("colorPowerTextByType", false) and "RESOURCE" or "DEFAULT" end,
        function(v)
            FontScopeSet("colorPowerTextByType", v == "RESOURCE", "MSUF2_POWER_TEXT_COLOR")
            ApplyFonts("MSUF2_POWER_TEXT_COLOR")
        end)

    local names = b:CollapsibleSection("fonts_name_shortening", "Name Shortening", 250, true)
    local shorten = W.Toggle(names, "Shorten names")
    M.BindToggle(ctx, shorten,
        function()
            if IsGFScope(CurrentFontScope()) then return false end
            return FontScopeGet("shortenNames", false, "shortenNames") and true or false
        end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNames", v and true or false, "MSUF2_SHORTEN_NAMES", "shortenNames")
            ApplyFonts("MSUF2_SHORTEN_NAMES")
        end)

    local side = W.Segment(names, "Clip side", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, 260)
    M.BindSegment(ctx, side,
        function() return FontScopeGet("shortenNameClipSide", "LEFT") end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameClipSide", v or "LEFT", "MSUF2_SHORTEN_SIDE")
            ApplyFonts("MSUF2_SHORTEN_SIDE")
        end)

    local chars = W.Slider(names, "Max characters", 2, 64, 1, 300)
    M.BindSlider(ctx, chars,
        function() return tonumber(FontScopeGet("shortenNameMaxChars", 6)) or 6 end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameMaxChars", floor((tonumber(v) or 6) + 0.5), "MSUF2_SHORTEN_MAX")
            ApplyFonts("MSUF2_SHORTEN_MAX")
        end)

    local dots = W.Toggle(names, "Show ellipsis")
    M.BindToggle(ctx, dots,
        function() return FontScopeGet("shortenNameShowDots", true) and true or false end,
        function(v)
            if IsGFScope(CurrentFontScope()) then return end
            FontScopeSet("shortenNameShowDots", v and true or false, "MSUF2_SHORTEN_DOTS")
            ApplyFonts("MSUF2_SHORTEN_DOTS")
        end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)

    local scopeValues = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "targettarget", text = "ToT" },
        { value = "focus", text = "Focus" },
        { value = "pet", text = "Pet" },
        { value = "boss", text = "Boss" },
        { value = "gf_party", text = "Party" },
        { value = "gf_raid", text = "Raid" },
    }

    local scope = b:Section("", 128)
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, {
        values = scopeValues,
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            if _G.MSUF_AbsorbTextureTestMode then SetAbsorbTextureTest(true) end
            RefreshBorderTestModes()
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and BarsScopeHasOverride(value)
        end,
    })
    local override = W.ToggleAt(scope, "Override shared settings", 14, -58, 220)
    M.BindToggle(ctx, override,
        function()
            local key = CurrentBarsScope()
            return BarsScopeHasOverride(key)
        end,
        function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                BarsScopeSetOverride(key, v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local overrideInfo = W.Text(scope, "", 14, -58, ctx.width - 130, T.colors.text)
    local reset = T.Button(scope, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -14, -50)
    reset._msuf2Label:ClearAllPoints()
    reset._msuf2Label:SetPoint("CENTER", reset, "CENTER", 0, 0)
    reset._msuf2Label:SetJustifyH("CENTER")
    reset:SetScript("OnClick", function()
        for i = 1, #scopeValues do
            local key = scopeValues[i].value
            if key ~= "shared" then BarsScopeSetOverride(key, false) end
        end
        ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local hint = W.Text(scope, "Group Frames inherit Shared textures and gradients by default. Raid also applies to Mythic Raid.", 14, -92, ctx.width - 28, T.colors.muted)
    M.AddRefresher(ctx, function()
        local current = CurrentBarsScope()
        local active = {}
        for i = 1, #scopeValues do
            local item = scopeValues[i]
            if item.value ~= "shared" and BarsScopeHasOverride(item.value) then active[#active + 1] = item.text end
        end
        local shared = current == "shared"
        W.SetControlShown(override, not shared)
        overrideInfo:SetShown(shared)
        reset:SetShown(shared and #active > 0)
        if #active > 0 then
            overrideInfo:SetText("|cffffffffOverrides:|r " .. table.concat(active, ", "))
        else
            overrideInfo:SetText("|cffffffffOverrides:|r None")
        end
        scopeSeg:Refresh()
        hint:SetWidth(ctx.width - 28)
    end)

    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", 214, true)
    local leftX, topY = 14, -42
    local rightX = math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = math.min(300, math.max(220, rightX - 48))

    local barTexture = W.Dropdown(textures, "Bar textures (SharedMedia)", function() return TextureValues(nil) end, 280)
    if barTexture._msuf2Title then
        barTexture._msuf2Title:ClearAllPoints()
        barTexture._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY)
    end
    barTexture:ClearAllPoints()
    barTexture:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 22)
    barTexture:SetWidth(leftW)
    M.BindDropdown(ctx, barTexture,
        function() return ReadG("barTexture", "Blizzard") end,
        function(v) SetG("barTexture", v or "Blizzard", "MSUF2_BAR_TEXTURE", { preview = true }); ApplyBars("MSUF2_BAR_TEXTURE") end)
    local bgTexture = W.Dropdown(textures, "Background texture", function() return TextureValues("Use foreground texture") end, 280)
    if bgTexture._msuf2Title then
        bgTexture._msuf2Title:ClearAllPoints()
        bgTexture._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 54)
    end
    bgTexture:ClearAllPoints()
    bgTexture:SetPoint("TOPLEFT", textures, "TOPLEFT", leftX, topY - 76)
    bgTexture:SetWidth(leftW)
    M.BindDropdown(ctx, bgTexture,
        function() return ReadG("barBackgroundTexture", "") end,
        function(v) SetG("barBackgroundTexture", v or "", "MSUF2_BAR_BG_TEXTURE", { preview = true }); ApplyBars("MSUF2_BAR_BG_TEXTURE") end)

    local gradLabel = T.Font(textures, "GameFontHighlightSmall", "Gradient", T.colors.muted)
    gradLabel:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY)
    local hpGradient = W.ToggleAt(textures, "HP bar gradient", rightX, topY - 24, 180)
    M.BindToggle(ctx, hpGradient,
        function() return BarScopeGet("enableGradient", true) ~= false end,
        function(v) BarScopeSet("enableGradient", v and true or false, "MSUF2_HP_GRADIENT"); ApplyBars("MSUF2_HP_GRADIENT") end)
    local powerGradient = W.ToggleAt(textures, "Power bar gradient", rightX, topY - 54, 190)
    M.BindToggle(ctx, powerGradient,
        function() return BarScopeGet("enablePowerGradient", false) == true end,
        function(v) BarScopeSet("enablePowerGradient", v and true or false, "MSUF2_POWER_GRADIENT"); ApplyBars("MSUF2_POWER_GRADIENT") end)
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    if strength._msuf2Title then
        strength._msuf2Title:ClearAllPoints()
        strength._msuf2Title:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY - 90)
        strength._msuf2Title:SetWidth(220)
    end
    strength:ClearAllPoints()
    strength:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, topY - 112)
    strength:SetWidth(220)
    if strength._msuf2UpdateFill then strength:_msuf2UpdateFill() end
    M.BindSlider(ctx, strength,
        function() return tonumber(BarScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v) BarScopeSet("gradientStrength", tonumber(v) or 0.45, "MSUF2_GRADIENT_STRENGTH"); ApplyBars("MSUF2_GRADIENT_STRENGTH") end)

    local padX = math.min(rightX + 238, (ctx.width or 720) - 104)
    local pad = T.Panel(textures, nil, { 0.020, 0.024, 0.046, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, topY - 18)
    pad:SetSize(84, 64)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", pad, "CENTER", 0, 0)
    center:SetSize(10, 10)
    center:SetColorTexture(0.23, 0.25, 0.34, 0.95)
    local directionButtons = {}
    local function PadButton(text, value, x, y)
        local btn = T.Button(pad, text, 22, 18)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, y)
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn._msuf2Label:SetJustifyH("CENTER")
        btn:SetScript("OnClick", function()
            SetGradientDirection(value or "RIGHT")
            ApplyBars("MSUF2_GRADIENT_DIRECTION")
        end)
        directionButtons[value] = btn
        return btn
    end
    PadButton("^", "UP", 31, -5)
    PadButton("<", "LEFT", 8, -27)
    PadButton(">", "RIGHT", 54, -27)
    PadButton("v", "DOWN", 31, -49)
    M.AddRefresher(ctx, function()
        local current = CurrentGradientDirection()
        local scopeKey = CurrentBarsScope()
        local controlsActive = scopeKey == "shared" or BarsScopeHasOverride(scopeKey)
        local valueControlsActive = controlsActive and ((BarScopeGet("enableGradient", true) ~= false) or (BarScopeGet("enablePowerGradient", false) == true))
        SetControlEnabled(hpGradient, controlsActive)
        SetControlEnabled(powerGradient, controlsActive)
        SetControlEnabled(strength, valueControlsActive)
        pad:SetAlpha(valueControlsActive and 1 or 0.45)
        for value, btn in pairs(directionButtons) do
            btn:SetActive(value == current)
            SetControlEnabled(btn, valueControlsActive)
        end
    end)

    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 470, true)
    local absorbMode = W.Dropdown(absorb, "Display mode", {
        { value = 1, text = "Absorb off" },
        { value = 2, text = "Absorb bar" },
        { value = 3, text = "Absorb bar + text" },
        { value = 4, text = "Absorb text only" },
    }, 280)
    M.BindDropdown(ctx, absorbMode,
        function() return tonumber(BarScopeGet("absorbTextMode", 2)) or 2 end,
        function(v) BarScopeSet("absorbTextMode", tonumber(v) or 2, "MSUF2_ABSORB_MODE"); ApplyBars("MSUF2_ABSORB_MODE") end)
    local absorbAnchor = W.Dropdown(absorb, "Absorb bar anchoring", {
        { value = 1, text = "Anchor to left side" },
        { value = 2, text = "Anchor to right side" },
        { value = 3, text = "Follow HP bar" },
        { value = 4, text = "Follow HP bar (overflow)" },
        { value = 5, text = "Reverse from max" },
    }, 280)
    M.BindDropdown(ctx, absorbAnchor,
        function() return tonumber(BarScopeGet("absorbAnchorMode", 2)) or 2 end,
        function(v) BarScopeSet("absorbAnchorMode", tonumber(v) or 2, "MSUF2_ABSORB_ANCHOR"); ApplyBars("MSUF2_ABSORB_ANCHOR") end)
    local absorbTex = W.Dropdown(absorb, "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, 280)
    M.BindDropdown(ctx, absorbTex,
        function() return ReadG("absorbBarTexture", "") end,
        function(v) SetG("absorbBarTexture", v or "", "MSUF2_ABSORB_TEXTURE", { preview = true }); Call("MSUF_UpdateAbsorbBarTextures"); ApplyBars("MSUF2_ABSORB_TEXTURE") end)
    local healAbsorbTex = W.Dropdown(absorb, "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, 280)
    M.BindDropdown(ctx, healAbsorbTex,
        function() return ReadG("healAbsorbBarTexture", "") end,
        function(v) SetG("healAbsorbBarTexture", v or "", "MSUF2_HEAL_ABSORB_TEXTURE", { preview = true }); Call("MSUF_UpdateAbsorbBarTextures"); ApplyBars("MSUF2_HEAL_ABSORB_TEXTURE") end)
    local selfHeal = W.Toggle(absorb, "Heal prediction")
    M.BindToggle(ctx, selfHeal,
        function() return ReadGBool("showSelfHealPrediction", true) end,
        function(v) SetGBool("showSelfHealPrediction", v, "MSUF2_SELF_HEAL", { preview = true }); ApplyBars("MSUF2_SELF_HEAL") end)
    local absorbTest = W.Toggle(absorb, "Test absorb textures")
    M.BindToggle(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end)
    absorbTest:HookScript("OnHide", function() ClearAbsorbTextureTest() end)
    local absorbOpacity = W.Slider(absorb, "Absorb bar opacity", 0, 1, 0.05, 300)
    M.BindSlider(ctx, absorbOpacity,
        function() return tonumber(BarScopeGet("absorbBarOpacity", 0.75)) or 0.75 end,
        function(v) BarScopeSet("absorbBarOpacity", tonumber(v) or 0.75, "MSUF2_ABSORB_OPACITY"); ApplyBars("MSUF2_ABSORB_OPACITY") end)
    local healAbsorbOpacity = W.Slider(absorb, "Heal-absorb bar opacity", 0, 1, 0.05, 300)
    M.BindSlider(ctx, healAbsorbOpacity,
        function() return tonumber(BarScopeGet("healAbsorbBarOpacity", 1)) or 1 end,
        function(v) BarScopeSet("healAbsorbBarOpacity", tonumber(v) or 1, "MSUF2_HEAL_ABSORB_OPACITY"); ApplyBars("MSUF2_HEAL_ABSORB_OPACITY") end)

    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 126, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindSlider(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v) BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE"); ApplyBars("MSUF2_BAR_OUTLINE") end)

    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 790, true)
    local highlight = W.Slider(highlights, "Highlight border thickness", 1, 30, 1, 300)
    M.BindSlider(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER")
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER")
            ApplyBars("MSUF2_HIGHLIGHT_BORDER")
        end)
    local borderModes = {
        { value = 0, text = "Off" },
        { value = 1, text = "On" },
    }
    local aggro = W.Dropdown(highlights, "Aggro border on", borderModes, 190)
    M.BindDropdown(ctx, aggro,
        function() return tonumber(BarScopeGet("aggroOutlineMode", 1)) or 1 end,
        function(v) BarScopeSet("aggroOutlineMode", tonumber(v) or 1, "MSUF2_AGGRO_BORDER"); ApplyBars("MSUF2_AGGRO_BORDER") end)
    local aggroTest = W.Toggle(highlights, "Test aggro border")
    M.BindToggle(ctx, aggroTest,
        function() return _G.MSUF_AggroBorderTestMode and true or false end,
        function(v)
            local scope = CurrentBarsScope()
            if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
            if type(_G.MSUF_SetAggroBorderTestMode) == "function" then _G.MSUF_SetAggroBorderTestMode(v and true or false, scope) end
        end)
    aggroTest:HookScript("OnHide", function(self)
        if _G.MSUF_AggroBorderTestMode and type(_G.MSUF_SetAggroBorderTestMode) == "function" then
            _G.MSUF_SetAggroBorderTestMode(false)
            self:SetChecked(false)
        end
    end)
    local dispelBorder = W.Dropdown(highlights, "Dispel border on", borderModes, 190)
    M.BindDropdown(ctx, dispelBorder,
        function() return tonumber(BarScopeGet("dispelOutlineMode", 1)) or 1 end,
        function(v) BarScopeSet("dispelOutlineMode", tonumber(v) or 1, "MSUF2_DISPEL_BORDER"); ApplyBars("MSUF2_DISPEL_BORDER") end)
    local dispelTest = W.Toggle(highlights, "Test dispel border")
    M.BindToggle(ctx, dispelTest,
        function() return _G.MSUF_DispelBorderTestMode and true or false end,
        function(v)
            local scope = CurrentBarsScope()
            if scope == "gf_party" then scope = "party" elseif scope == "gf_raid" then scope = "raid" end
            if type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(v and true or false, scope) end
        end)
    dispelTest:HookScript("OnHide", function(self)
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then
            _G.MSUF_SetDispelBorderTestMode(false)
            self:SetChecked(false)
        end
    end)
    _G.MSUF_DispelBorderTestType = _G.MSUF_DispelBorderTestType or "Magic"
    local dispelType = W.Dropdown(highlights, "Dispel test type", {
        { value = "Magic", text = "Magic" },
        { value = "Curse", text = "Curse" },
        { value = "Disease", text = "Disease" },
        { value = "Poison", text = "Poison" },
        { value = "Bleed", text = "Bleed" },
    }, 190)
    M.BindDropdown(ctx, dispelType,
        function() return _G.MSUF_DispelBorderTestType or "Magic" end,
        function(v)
            _G.MSUF_DispelBorderTestType = v or "Magic"
            RefreshBorderTestModes()
        end)
    local purge = W.Dropdown(highlights, "Purge border on", borderModes, 190)
    M.BindDropdown(ctx, purge,
        function() return tonumber(BarScopeGet("purgeOutlineMode", 0)) or 0 end,
        function(v) BarScopeSet("purgeOutlineMode", tonumber(v) or 0, "MSUF2_PURGE_BORDER"); ApplyBars("MSUF2_PURGE_BORDER") end)
    local purgeTest = W.Toggle(highlights, "Test purge border")
    M.BindToggle(ctx, purgeTest,
        function() return _G.MSUF_PurgeBorderTestMode and true or false end,
        function(v)
            if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(v and true or false) end
        end)
    purgeTest:HookScript("OnHide", function(self)
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
            _G.MSUF_SetPurgeBorderTestMode(false)
            self:SetChecked(false)
        end
    end)
    local bossTarget = W.Dropdown(highlights, "Boss target border on", borderModes, 190)
    M.BindDropdown(ctx, bossTarget,
        function() return tonumber(BarScopeGet("bossTargetOutlineMode", 1)) or 1 end,
        function(v) BarScopeSet("bossTargetOutlineMode", tonumber(v) or 1, "MSUF2_BOSS_TARGET_BORDER"); ApplyBars("MSUF2_BOSS_TARGET_BORDER") end)
    local bossTargetTest = W.Toggle(highlights, "Test boss target border")
    M.BindToggle(ctx, bossTargetTest,
        function() return _G.MSUF_BossTargetBorderTestMode and true or false end,
        function(v)
            if type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then _G.MSUF_SetBossTargetBorderTestMode(v and true or false) end
        end)
    bossTargetTest:HookScript("OnHide", function(self)
        if _G.MSUF_BossTargetBorderTestMode and type(_G.MSUF_SetBossTargetBorderTestMode) == "function" then
            _G.MSUF_SetBossTargetBorderTestMode(false)
            self:SetChecked(false)
        end
    end)
    local enabled = W.Toggle(highlights, "Dispel glow effect")
    M.BindToggle(ctx, enabled,
        function() return BarScopeGet("hlDispelGlowEnabled", true) ~= false end,
        function(v) BarScopeSet("hlDispelGlowEnabled", v and true or false, "MSUF2_DISPEL_GLOW"); ApplyBars("MSUF2_DISPEL_GLOW") end)
    local style = W.Segment(highlights, "Glow style", {
        { value = "PIXEL", text = "Pixel" },
        { value = "AUTOCAST", text = "AutoCast" },
        { value = "PROC", text = "Proc" },
    }, 420)
    M.BindSegment(ctx, style,
        function() return NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) end,
        function(v) BarScopeSet("hlDispelGlowStyle", NormalizeGlowStyle(v), "MSUF2_DISPEL_STYLE"); ApplyBars("MSUF2_DISPEL_STYLE") end)
    local lines = W.Slider(highlights, "Glow lines / particles", 2, 16, 1, 300)
    M.BindSlider(ctx, lines,
        function() return tonumber(BarScopeGet("hlDispelGlowLines", 8)) or 8 end,
        function(v) BarScopeSet("hlDispelGlowLines", floor((tonumber(v) or 8) + 0.5), "MSUF2_DISPEL_GLOW_LINES"); ApplyBars("MSUF2_DISPEL_GLOW_LINES") end)
    local speed = W.Slider(highlights, "Glow speed", 0.05, 1, 0.05, 300)
    M.BindSlider(ctx, speed,
        function() return tonumber(BarScopeGet("hlDispelGlowFrequency", 0.25)) or 0.25 end,
        function(v) BarScopeSet("hlDispelGlowFrequency", tonumber(v) or 0.25, "MSUF2_DISPEL_GLOW_SPEED"); ApplyBars("MSUF2_DISPEL_GLOW_SPEED") end)
    local thickness = W.Slider(highlights, "Glow thickness (Pixel)", 1, 5, 1, 300)
    M.BindSlider(ctx, thickness,
        function() return tonumber(BarScopeGet("hlDispelGlowThickness", 2)) or 2 end,
        function(v) BarScopeSet("hlDispelGlowThickness", floor((tonumber(v) or 2) + 0.5), "MSUF2_DISPEL_THICKNESS"); ApplyBars("MSUF2_DISPEL_THICKNESS") end)
    M.AddRefresher(ctx, function()
        local glowOn = BarScopeGet("hlDispelGlowEnabled", true) ~= false
        SetControlEnabled(style, glowOn)
        SetControlEnabled(lines, glowOn)
        SetControlEnabled(speed, glowOn)
        SetControlEnabled(thickness, glowOn and NormalizeGlowStyle(BarScopeGet("hlDispelGlowStyle", "PIXEL")) == "PIXEL")
    end)

    local priority = b:CollapsibleSection("bars_priority", "Highlight Priority", 280, false)
    local prio = W.ToggleAt(priority, "Custom highlight priority", 14, -8, 240)
    M.BindToggle(ctx, prio,
        function() return BarScopeGet("hlPrioEnabled", false) == true end,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY")
            if CurrentBarsScope() == "shared" then G().highlightPrioEnabled = on and 1 or 0 end
            ApplyBars("MSUF2_HIGHLIGHT_PRIORITY")
        end)

    local rowH, rowGap, rowMax = 22, 4, 8
    local prioContainer = CreateFrame("Frame", nil, priority)
    prioContainer:SetPoint("TOPLEFT", prio, "BOTTOMLEFT", -2, -4)
    prioContainer:SetSize(200, rowMax * (rowH + rowGap))

    local prioRows, prioCount = {}, 0
    local function PrioritySlotY(slot)
        return -((slot - 1) * (rowH + rowGap))
    end
    local function SnapPriorityRows()
        for i = 1, prioCount do
            local row = prioRows[i]
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", prioContainer, "TOPLEFT", 0, PrioritySlotY(row.slotIndex))
            row.frame:Show()
        end
        for i = prioCount + 1, rowMax do
            if prioRows[i] then prioRows[i].frame:Hide() end
        end
        prioContainer:SetHeight(prioCount * (rowH + rowGap))
    end
    local function SavePriorityRows()
        local sorted = {}
        for i = 1, prioCount do sorted[i] = prioRows[i] end
        table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
        local order = {}
        for i = 1, prioCount do order[i] = sorted[i].key end
        SetPriorityOrder(order)
        ApplyBars("MSUF2_HIGHLIGHT_PRIORITY_ORDER")
    end
    local function SetPriorityRowsEnabled(enabled)
        enabled = enabled and true or false
        for i = 1, prioCount do
            local frame = prioRows[i].frame
            frame:SetAlpha(enabled and 1 or 0.4)
            frame:EnableMouse(enabled)
        end
    end

    for i = 1, rowMax do
        local rowFrame = CreateFrame("Frame", nil, prioContainer, T.Template and T.Template() or nil)
        rowFrame:SetSize(190, rowH)
        rowFrame:SetMovable(true)
        rowFrame:EnableMouse(true)
        rowFrame:RegisterForDrag("LeftButton")
        if rowFrame.SetBackdrop then
            rowFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            rowFrame:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
            rowFrame:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.60)
        end
        local stripe = rowFrame:CreateTexture(nil, "ARTWORK")
        stripe:SetSize(4, rowH - 2)
        stripe:SetPoint("LEFT", rowFrame, "LEFT", 2, 0)
        rowFrame._stripe = stripe
        local label = T.Font(rowFrame, "GameFontHighlightSmall", "", T.colors.text)
        label:SetPoint("LEFT", stripe, "RIGHT", 6, 0)
        rowFrame._label = label
        local num = T.Font(rowFrame, "GameFontNormalSmall", "", T.colors.dim)
        num:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        rowFrame._numText = num
        rowFrame:SetScript("OnDragStart", function(self)
            if not (BarScopeGet("hlPrioEnabled", false) == true) then return end
            if GameTooltip then GameTooltip:Hide() end
            self._msuf2OldStrata = self:GetFrameStrata()
            self:StartMoving()
            self:SetFrameStrata("TOOLTIP")
        end)
        rowFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetFrameStrata(self._msuf2OldStrata or prioContainer:GetFrameStrata() or "MEDIUM")
            local _, selfY = self:GetCenter()
            local contTop = prioContainer:GetTop()
            if not (selfY and contTop) then
                SnapPriorityRows()
                return
            end
            local bestSlot, bestDist = 1, math.huge
            for slot = 1, prioCount do
                local slotY = contTop + PrioritySlotY(slot) - (rowH / 2)
                local dist = math.abs(selfY - slotY)
                if dist < bestDist then
                    bestDist = dist
                    bestSlot = slot
                end
            end
            local thisRow
            for idx = 1, prioCount do
                if prioRows[idx].frame == self then
                    thisRow = prioRows[idx]
                    break
                end
            end
            if thisRow and thisRow.slotIndex ~= bestSlot then
                for idx = 1, prioCount do
                    if prioRows[idx].slotIndex == bestSlot then
                        prioRows[idx].slotIndex = thisRow.slotIndex
                        break
                    end
                end
                thisRow.slotIndex = bestSlot
            end
            for idx = 1, prioCount do
                prioRows[idx].frame._numText:SetText(tostring(prioRows[idx].slotIndex))
            end
            SnapPriorityRows()
            SavePriorityRows()
        end)
        rowFrame:Hide()
        prioRows[i] = { frame = rowFrame, key = "", slotIndex = i }
    end

    local function RefreshPriorityRows()
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(PRIORITY_LABELS[key] or key)
            row.frame._numText:SetText(tostring(i))
        end
        SnapPriorityRows()
        SetPriorityRowsEnabled(BarScopeGet("hlPrioEnabled", false) == true)
    end
    RefreshPriorityRows()
    M.AddRefresher(ctx, RefreshPriorityRows)

    local text = b:CollapsibleSection("bars_text", "HP / Power Text", 340, false)
    local hpModeOptions = {
        { value = "PERCENT", text = "Percent" },
        { value = "CURRENT", text = "Current" },
        { value = "MAX", text = "Max" },
        { value = "DEFICIT", text = "Deficit" },
        { value = "CURMAX", text = "Current / Max" },
        { value = "CURPERCENT", text = "Current / Percent" },
        { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
        { value = "MAXPERCENT", text = "Max / Percent" },
        { value = "PERCENTCUR", text = "Percent / Current" },
        { value = "PERCENTMAX", text = "Percent / Max" },
        { value = "PERCENTCURMAX", text = "Percent / Current / Max" },
        { value = "NONE", text = "None" },
    }
    local powerModeOptions = {
        { value = "CURRENT", text = "Current" },
        { value = "MAX", text = "Max" },
        { value = "CURMAX", text = "Cur/Max" },
        { value = "PERCENT", text = "Percent" },
        { value = "CURPERCENT", text = "Cur + Percent" },
        { value = "CURMAXPERCENT", text = "Cur/Max + Percent" },
    }
    local separatorOptions = {
        { value = "", text = " " },
        { value = "-", text = "-" },
        { value = "/", text = "/" },
        { value = "\\", text = "\\" },
        { value = "|", text = "|" },
        { value = "<", text = "<" },
        { value = ">", text = ">" },
        { value = "~", text = "~" },
        { value = "\194\183", text = "\194\183" },
        { value = "\226\128\162", text = "\226\128\162" },
        { value = ":", text = ":" },
        { value = "\194\187", text = "\194\187" },
        { value = "\194\171", text = "\194\171" },
    }
    local hpMode = W.Dropdown(text, "HP text mode", hpModeOptions, 260)
    M.BindDropdown(ctx, hpMode,
        function() return NormalizeHpMode(BarScopeGet("hpTextMode", "FULL_PLUS_PERCENT")) end,
        function(v) BarScopeSet("hpTextMode", v or "CURPERCENT", "MSUF2_HP_TEXT_MODE"); ApplyBars("MSUF2_HP_TEXT_MODE") end)
    local powerMode = W.Dropdown(text, "Power text mode", powerModeOptions, 260)
    M.BindDropdown(ctx, powerMode,
        function() return NormalizePowerMode(BarScopeGet("powerTextMode", "CURPERCENT")) end,
        function(v) BarScopeSet("powerTextMode", v or "CURPERCENT", "MSUF2_POWER_TEXT_MODE"); ApplyBars("MSUF2_POWER_TEXT_MODE") end)
    local hpReverse = W.Toggle(text, "Reverse HP text order")
    M.BindToggle(ctx, hpReverse,
        function() return BarScopeGet("hpTextReverse", false) == true end,
        function(v) BarScopeSet("hpTextReverse", v and true or false, "MSUF2_HP_TEXT_REVERSE"); ApplyBars("MSUF2_HP_TEXT_REVERSE") end)
    local hpSep = W.Dropdown(text, "HP separator", separatorOptions, 120)
    M.BindDropdown(ctx, hpSep,
        function() return BarScopeGet("hpTextSeparator", "") or "" end,
        function(v) BarScopeSet("hpTextSeparator", v or "", "MSUF2_HP_TEXT_SEPARATOR"); ApplyBars("MSUF2_HP_TEXT_SEPARATOR") end)
    local powerSep = W.Dropdown(text, "Power separator", separatorOptions, 120)
    M.BindDropdown(ctx, powerSep,
        function() return BarScopeGet("powerTextSeparator", BarScopeGet("hpTextSeparator", "")) or "" end,
        function(v) BarScopeSet("powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR"); ApplyBars("MSUF2_POWER_TEXT_SEPARATOR") end)

    local spacers = b:CollapsibleSection("bars_text_spacers", "Text Spacers", 300, false)
    local hpSpacer = W.Toggle(spacers, "HP Spacer on/off")
    M.BindToggle(ctx, hpSpacer,
        function() return BarScopeGet("hpTextSpacerEnabled", false) == true end,
        function(v) BarScopeSet("hpTextSpacerEnabled", v and true or false, "MSUF2_HP_TEXT_SPACER"); ApplyBars("MSUF2_HP_TEXT_SPACER") end)
    local hpSpacerX = W.Slider(spacers, "HP Spacer (X)", 0, 2000, 1, 300)
    M.BindSlider(ctx, hpSpacerX,
        function() return tonumber(BarScopeGet("hpTextSpacerX", 0)) or 0 end,
        function(v) BarScopeSet("hpTextSpacerX", floor((tonumber(v) or 0) + 0.5), "MSUF2_HP_TEXT_SPACER_X"); ApplyBars("MSUF2_HP_TEXT_SPACER_X") end)
    local powerSpacer = W.Toggle(spacers, "Power Spacer on/off")
    M.BindToggle(ctx, powerSpacer,
        function() return BarScopeGet("powerTextSpacerEnabled", false) == true end,
        function(v) BarScopeSet("powerTextSpacerEnabled", v and true or false, "MSUF2_POWER_TEXT_SPACER"); ApplyBars("MSUF2_POWER_TEXT_SPACER") end)
    local powerSpacerX = W.Slider(spacers, "Power Spacer (X)", 0, 1000, 1, 300)
    M.BindSlider(ctx, powerSpacerX,
        function() return tonumber(BarScopeGet("powerTextSpacerX", 0)) or 0 end,
        function(v) BarScopeSet("powerTextSpacerX", floor((tonumber(v) or 0) + 0.5), "MSUF2_POWER_TEXT_SPACER_X"); ApplyBars("MSUF2_POWER_TEXT_SPACER_X") end)

    local power = b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 152, false)
    local smoothPower = W.Toggle(power, "Smooth power bar")
    M.BindToggle(ctx, smoothPower,
        function() return SmoothPowerGet() end,
        function(v) SmoothPowerSet(v, "MSUF2_BARS_SMOOTH_POWER"); ApplyBars("MSUF2_BARS_SMOOTH_POWER") end)
    local realtimePower = W.Toggle(power, "Realtime power text")
    M.BindToggle(ctx, realtimePower,
        function() return ReadB("realtimePowerText", true) ~= false end,
        function(v) SetB("realtimePowerText", v and true or false, "MSUF2_BARS_REALTIME_POWER", { preview = true }); ApplyBars("MSUF2_BARS_REALTIME_POWER") end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)

    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then
            pcall(_G.MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
            pcall(C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
        end
    end

    local function ApplyCastbarTextures(reason)
        EnsureCastbars()
        Call("MSUF_UpdateCastbarTextures_Immediate")
        Call("MSUF_UpdateCastbarTextures")
        Call("MSUF_UpdateCastbarVisuals_Immediate")
        Call("MSUF_UpdateCastbarVisuals")
        Call("MSUF_UpdateBossCastbarPreview")
        ApplyCastbars(reason or "MSUF2_CASTBAR_TEXTURES")
    end

    local behavior = b:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 260, true)
    local shake = W.Toggle(behavior, "Shake on interrupt")
    M.BindToggle(ctx, shake,
        function() return ReadGBool("castbarInterruptShake", false) end,
        function(v) SetGBool("castbarInterruptShake", v, "MSUF2_CASTBAR_SHAKE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_SHAKE") end)

    local strength = W.Slider(behavior, "Shake strength", 0, 30, 1, 300)
    M.BindSlider(ctx, strength,
        function() return tonumber(ReadG("castbarShakeStrength", 8)) or 8 end,
        function(v) SetG("castbarShakeStrength", floor((tonumber(v) or 8) + 0.5), "MSUF2_CASTBAR_SHAKE_STRENGTH", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_SHAKE_STRENGTH") end)

    local unified = W.Toggle(behavior, "Always use fill direction for all casts")
    M.BindToggle(ctx, unified,
        function() return ReadGBool("castbarUnifiedDirection", false) end,
        function(v) SetGBool("castbarUnifiedDirection", v, "MSUF2_CASTBAR_UNIFIED_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_UNIFIED_DIRECTION") end)

    local direction = W.Dropdown(behavior, "Castbar fill direction", {
        { value = "RTL", text = "Right to left (default)" },
        { value = "LTR", text = "Left to right" },
    }, 260)
    M.BindDropdown(ctx, direction,
        function() return ReadG("castbarFillDirection", "RTL") end,
        function(v) SetG("castbarFillDirection", v or "RTL", "MSUF2_CASTBAR_FILL_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_FILL_DIRECTION") end)

    local opposite = W.Toggle(behavior, "Use opposite fill direction for target")
    M.BindToggle(ctx, opposite,
        function() return ReadGBool("castbarOpositeDirectionTarget", true) end,
        function(v) SetGBool("castbarOpositeDirectionTarget", v, "MSUF2_CASTBAR_TARGET_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TARGET_DIRECTION") end)

    local ticks = W.Toggle(behavior, "Show channel tick lines (5)")
    M.BindToggle(ctx, ticks,
        function() return ReadGBool("castbarShowChannelTicks", true) end,
        function(v) SetGBool("castbarShowChannelTicks", v, "MSUF2_CASTBAR_TICKS", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TICKS") end)

    local gcd = b:CollapsibleSection("castbar_gcd", "GCD Bar", 150, false)
    local syncGCDSubs
    local gcdShow = W.Toggle(gcd, "Show GCD bar for instant casts")
    M.BindToggle(ctx, gcdShow,
        function() return ReadGBool("showGCDBar", true) end,
        function(v)
            SetGBool("showGCDBar", v, "MSUF2_CASTBAR_GCD", { castbar = true, preview = true })
            EnsureCastbars()
            if type(_G.MSUF_SetGCDBarEnabled) == "function" then pcall(_G.MSUF_SetGCDBarEnabled, v) end
            ApplyCastbars("MSUF2_CASTBAR_GCD")
            if syncGCDSubs then syncGCDSubs() end
        end)
    local gcdTime = W.Toggle(gcd, "GCD bar: show time text")
    M.BindToggle(ctx, gcdTime,
        function() return ReadGBool("showGCDBarTime", true) end,
        function(v) SetGBool("showGCDBarTime", v, "MSUF2_CASTBAR_GCD_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_TIME") end)
    local gcdSpell = W.Toggle(gcd, "GCD bar: show spell name + icon")
    M.BindToggle(ctx, gcdSpell,
        function() return ReadGBool("showGCDBarSpell", true) end,
        function(v) SetGBool("showGCDBarSpell", v, "MSUF2_CASTBAR_GCD_SPELL", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_SPELL") end)
    syncGCDSubs = function()
        SetControlsEnabled({ gcdTime, gcdSpell }, ReadGBool("showGCDBar", true))
    end
    M.AddRefresher(ctx, syncGCDSubs)
    syncGCDSubs()

    local textures = b:CollapsibleSection("castbar_textures", "Textures & Outline", 330, false)
    local tex = W.Dropdown(textures, "Castbar texture", function() return TextureValues(nil) end, 280)
    M.BindDropdown(ctx, tex,
        function() return ReadG("castbarTexture", "Blizzard") end,
        function(v) SetG("castbarTexture", v or "Blizzard", "MSUF2_CASTBAR_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_TEXTURE") end)
    local bgTex = W.Dropdown(textures, "Castbar background texture", function() return TextureValues(nil) end, 280)
    M.BindDropdown(ctx, bgTex,
        function()
            local v = ReadG("castbarBackgroundTexture", nil)
            if type(v) ~= "string" or v == "" then v = ReadG("castbarTexture", "Blizzard") end
            return v
        end,
        function(v) SetG("castbarBackgroundTexture", v or "Blizzard", "MSUF2_CASTBAR_BG_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_BG_TEXTURE") end)
    local outline = W.Slider(textures, "Outline thickness", 0, 6, 1, 300)
    M.BindSlider(ctx, outline,
        function() return tonumber(ReadG("castbarOutlineThickness", 1)) or 1 end,
        function(v)
            SetG("castbarOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_CASTBAR_OUTLINE", { castbar = true, preview = true })
            Call("MSUF_ApplyCastbarOutlineToAll", true)
            ApplyCastbarTextures("MSUF2_CASTBAR_OUTLINE")
        end)
    for _, spec in ipairs({
        { "castbarShowGlow", "Show castbar glow effect", true, "MSUF2_CASTBAR_GLOW" },
        { "castbarShowLatency", "Show latency indicator", true, "MSUF2_CASTBAR_LATENCY" },
        { "castbarShowSpark", "Show spark (leading edge highlight)", false, "MSUF2_CASTBAR_SPARK" },
        { "castbarSparkOverflow", "Spark extends beyond bar", true, "MSUF2_CASTBAR_SPARK_OVERFLOW" },
    }) do
        local toggle = W.Toggle(textures, spec[2])
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], spec[3]) end,
            function(v) SetGBool(spec[1], v, spec[4], { castbar = true, preview = true }); ApplyCastbarTextures(spec[4]) end)
    end

    local empowered = b:CollapsibleSection("castbar_empowered", "Empowered Casts", 170, false)
    local empColor = W.Toggle(empowered, "Add color to stages (Empowered casts)")
    M.BindToggle(ctx, empColor,
        function() return ReadGBool("empowerColorStages", true) end,
        function(v) SetGBool("empowerColorStages", v, "MSUF2_CASTBAR_EMPOWER_COLOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_COLOR") end)
    local empBlink = W.Toggle(empowered, "Add stage blink (Empowered casts)")
    M.BindToggle(ctx, empBlink,
        function() return ReadGBool("empowerStageBlink", true) end,
        function(v) SetGBool("empowerStageBlink", v, "MSUF2_CASTBAR_EMPOWER_BLINK", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_BLINK") end)
    local blinkTime = W.Slider(empowered, "Stage blink time (sec)", 0.05, 1.00, 0.01, 300)
    M.BindSlider(ctx, blinkTime,
        function() return tonumber(ReadG("empowerStageBlinkTime", 0.25)) or 0.25 end,
        function(v) SetG("empowerStageBlinkTime", tonumber(v) or 0.25, "MSUF2_CASTBAR_EMPOWER_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_TIME") end)

    local text = b:CollapsibleSection("castbar_name_shortening", "Name Shortening", 250, false)
    local shorten = W.Segment(text, "Spell name shortening", {
        { value = 0, text = "Off" },
        { value = 1, text = "On" },
    }, 220)
    M.BindSegment(ctx, shorten,
        function() return tonumber(ReadG("castbarSpellNameShortening", 0)) or 0 end,
        function(v) SetG("castbarSpellNameShortening", tonumber(v) or 0, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_SHORTEN") end)

    local maxLen = W.Slider(text, "Max name length", 6, 30, 1, 300)
    M.BindSlider(ctx, maxLen,
        function() return tonumber(ReadG("castbarSpellNameMaxLen", 30)) or 30 end,
        function(v) SetG("castbarSpellNameMaxLen", floor((tonumber(v) or 30) + 0.5), "MSUF2_CASTBAR_NAME_MAX", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_MAX") end)
    local reserved = W.Slider(text, "Reserved space", 0, 30, 1, 300)
    M.BindSlider(ctx, reserved,
        function() return tonumber(ReadG("castbarSpellNameReservedSpace", 8)) or 8 end,
        function(v) SetG("castbarSpellNameReservedSpace", floor((tonumber(v) or 8) + 0.5), "MSUF2_CASTBAR_NAME_RESERVED", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_RESERVED") end)

    local focusKick = b:CollapsibleSection("castbar_focus_kick", "Focus Kick", 470, false)
    W.Text(focusKick, "Track interrupts on your focus without showing the focus castbar.", 14, -38, ctx.width - 28, T.colors.muted)
    focusKick._msuf2CursorY = -68
    local syncFocusKick
    local focusEnable = W.Toggle(focusKick, "Enable focus interrupt tracker")
    M.BindToggle(ctx, focusEnable,
        function() return ReadGBool("enableFocusKickIcon", false) end,
        function(v)
            SetGBool("enableFocusKickIcon", v, "MSUF2_FOCUS_KICK_ENABLE", { castbar = true, preview = true })
            Call("MSUF_UpdateFocusKickIconOptions")
            if not v then Call("MSUF_FocusKick_SetPreviewEnabled", false) end
            if syncFocusKick then syncFocusKick() end
        end)
    local focusPreview = W.Toggle(focusKick, "Show on-screen preview")
    M.BindToggle(ctx, focusPreview,
        function()
            local fn = _G.MSUF_FocusKick_IsPreviewEnabled
            return type(fn) == "function" and fn() or false
        end,
        function(v) Call("MSUF_FocusKick_SetPreviewEnabled", v and true or false) end)
    local focusW = W.Slider(focusKick, "Width", 16, 128, 1, 300)
    M.BindSlider(ctx, focusW,
        function() return tonumber(ReadG("focusKickIconWidth", 40)) or 40 end,
        function(v) SetG("focusKickIconWidth", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_WIDTH", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusH = W.Slider(focusKick, "Height", 16, 128, 1, 300)
    M.BindSlider(ctx, focusH,
        function() return tonumber(ReadG("focusKickIconHeight", 40)) or 40 end,
        function(v) SetG("focusKickIconHeight", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_HEIGHT", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusText = W.Slider(focusKick, "Text size", 8, 24, 1, 300)
    M.BindSlider(ctx, focusText,
        function()
            local v = tonumber(ReadG("focusKickTextSize", nil))
            if v then return v end
            return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
        end,
        function(v)
            SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
            Call("MSUF_FocusKick_ApplyTimeTextFont")
            Call("MSUF_UpdateFocusKickIconOptions")
        end)
    local focusX = W.Slider(focusKick, "X offset", -500, 500, 1, 300)
    M.BindSlider(ctx, focusX,
        function() return tonumber(ReadG("focusKickIconOffsetX", 300)) or 300 end,
        function(v) SetG("focusKickIconOffsetX", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_X", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusY = W.Slider(focusKick, "Y offset", -500, 500, 1, 300)
    M.BindSlider(ctx, focusY,
        function() return tonumber(ReadG("focusKickIconOffsetY", 0)) or 0 end,
        function(v) SetG("focusKickIconOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_Y", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local resetFocus = W.Button(focusKick, "Reset Position", 150)
    resetFocus:SetScript("OnClick", function()
        SetG("focusKickIconOffsetX", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        SetG("focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        Call("MSUF_UpdateFocusKickIconOptions")
        if ctx.refreshers then
            for i = 1, #ctx.refreshers do
                local fn = ctx.refreshers[i]
                if type(fn) == "function" then pcall(fn) end
            end
        end
    end)
    syncFocusKick = function()
        SetControlsEnabled({ focusPreview, focusW, focusH, focusText, focusX, focusY, resetFocus }, ReadGBool("enableFocusKickIcon", false))
    end
    M.AddRefresher(ctx, syncFocusKick)
    syncFocusKick()

    local kick = b:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 560, false)
    W.Text(kick, "Shows a colored indicator on castbars when your interrupt is ready or on cooldown.", 14, -38, ctx.width - 28, T.colors.muted)
    kick._msuf2CursorY = -68
    for _, spec in ipairs({
        { "kickReadyShowTarget", "Show on Target castbar" },
        { "kickReadyShowFocus", "Show on Focus castbar" },
        { "kickReadyShowBoss", "Show on Boss castbars" },
    }) do
        local toggle = W.Toggle(kick, spec[2])
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], false) end,
            function(v) SetGBool(spec[1], v, "MSUF2_KICK_READY_ENABLE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_ENABLE") end)
    end
    local style = W.Dropdown(kick, "Indicator style", {
        { value = "border", text = "Castbar border" },
        { value = "box", text = "Color box next to cast" },
    }, 260)
    M.BindDropdown(ctx, style,
        function() return ReadG("kickReadyStyle", "border") end,
        function(v) SetG("kickReadyStyle", v or "border", "MSUF2_KICK_READY_STYLE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_STYLE") end)
    local size = W.Slider(kick, "Indicator size", 8, 32, 1, 300)
    M.BindSlider(ctx, size,
        function() return tonumber(ReadG("kickReadySize", 16)) or 16 end,
        function(v) SetG("kickReadySize", floor((tonumber(v) or 16) + 0.5), "MSUF2_KICK_READY_SIZE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_SIZE") end)
    local auto = W.Toggle(kick, "Auto-size to castbar height")
    M.BindToggle(ctx, auto,
        function() return ReadGBool("kickReadyAutoSize", true) end,
        function(v) SetGBool("kickReadyAutoSize", v, "MSUF2_KICK_READY_AUTO", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_AUTO") end)
    W.Text(kick, "Ready / cooldown colors: Colors menu > Interrupt Ready Indicator", 14, -300, ctx.width - 28, T.colors.muted)
    kick._msuf2CursorY = -330
    local anchor = W.Dropdown(kick, "Anchor", {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "TOP", text = "Top" },
        { value = "BOTTOM", text = "Bottom" },
    }, 180)
    M.BindDropdown(ctx, anchor,
        function() return ReadG("kickReadyAnchor", "RIGHT") end,
        function(v) SetG("kickReadyAnchor", v or "RIGHT", "MSUF2_KICK_READY_ANCHOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_ANCHOR") end)
    local offX = W.Slider(kick, "X offset", -50, 50, 1, 300)
    M.BindSlider(ctx, offX,
        function() return tonumber(ReadG("kickReadyOffsetX", 4)) or 4 end,
        function(v) SetG("kickReadyOffsetX", floor((tonumber(v) or 4) + 0.5), "MSUF2_KICK_READY_X", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_X") end)
    local offY = W.Slider(kick, "Y offset", -50, 50, 1, 300)
    M.BindSlider(ctx, offY,
        function() return tonumber(ReadG("kickReadyOffsetY", 0)) or 0 end,
        function(v) SetG("kickReadyOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_KICK_READY_Y", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_Y") end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildMisc(ctx)
    local b = W.PageBuilder(ctx)

    local function RefreshRangeFadeRuntime()
        Call("MSUF_RangeFade_Reset")
        if not Call("MSUF_RangeFade_EvaluateActive", true) then
            Call("MSUF_RangeFade_ApplyCurrent", true)
        end
        Call("MSUF_RangeFadeFB_Reset")
        if not Call("MSUF_RangeFadeFB_EvaluateActive", true) then
            Call("MSUF_RangeFadeFB_ApplyCurrent", true)
        end
    end

    local function RefreshTargetRangeFade()
        Call("MSUF_RangeFade_Reset")
        if not Call("MSUF_RangeFade_EvaluateActive", true) then
            Call("MSUF_RangeFade_RebuildSpells")
        end
    end

    local function RefreshFocusBossRangeFade()
        Call("MSUF_RangeFadeFB_Reset")
        if not Call("MSUF_RangeFadeFB_EvaluateActive", true) then
            Call("MSUF_RangeFadeFB_RebuildSpells")
            Call("MSUF_RangeFadeFB_ApplyCurrent", true)
        end
    end

    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nA UI reload is required.",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local unitInterval, castInterval, budget, urgent
    local updates = b:CollapsibleSection("misc_updates", "Update intervals", 402, true)
    local preset = W.Segment(updates, "Preset", {
        { value = "perf", text = "Performance" },
        { value = "balanced", text = "Balanced" },
        { value = "accurate", text = "Accurate" },
    }, 336)
    M.BindSegment(ctx, preset,
        function() return ReadG("miscUpdatesPreset", "balanced") end,
        function(v)
            v = v or "balanced"
            SetG("miscUpdatesPreset", v, "MSUF2_UPDATE_PRESET", { preview = false })
            local values = {
                perf = { 0.12, 0.06, 1.0, 6 },
                balanced = { 0.05, 0.02, 2.0, 10 },
                accurate = { 0.01, 0.01, 5.0, 50 },
            }
            local p = values[v] or values.balanced
            if unitInterval then unitInterval:SetValue(p[1]) end
            if castInterval then castInterval:SetValue(p[2]) end
            if budget then budget:SetValue(p[3]) end
            if urgent then urgent:SetValue(p[4]) end
        end)

    unitInterval = W.Slider(updates, "Unit update interval", 0.01, 0.30, 0.01, 300)
    M.BindSlider(ctx, unitInterval,
        function() return tonumber(ReadG("frameUpdateInterval", _G.MSUF_FrameUpdateInterval or 0.05)) or 0.05 end,
        function(v)
            v = tonumber(v) or 0.05
            SetG("frameUpdateInterval", v, "MSUF2_UPDATE_INTERVAL", { preview = false })
            _G.MSUF_FrameUpdateInterval = v
        end)
    _G.MSUF2_MiscUnitIntervalSlider = unitInterval

    castInterval = W.Slider(updates, "Castbar update interval", 0.01, 0.30, 0.01, 300)
    M.BindSlider(ctx, castInterval,
        function() return tonumber(ReadG("castbarUpdateInterval", _G.MSUF_CastbarUpdateInterval or 0.02)) or 0.02 end,
        function(v)
            v = tonumber(v) or 0.02
            SetG("castbarUpdateInterval", v, "MSUF2_CASTBAR_UPDATE_INTERVAL", { castbar = true, preview = false })
            _G.MSUF_CastbarUpdateInterval = v
        end)

    budget = W.Slider(updates, "UFCore flush budget", 0.5, 5.0, 0.1, 300)
    M.BindSlider(ctx, budget,
        function() return tonumber(ReadG("ufcoreFlushBudgetMs", 2.0)) or 2.0 end,
        function(v) SetG("ufcoreFlushBudgetMs", tonumber(v) or 2.0, "MSUF2_UFCORE_BUDGET", { preview = false }) end)

    urgent = W.Slider(updates, "UFCore urgent cap", 1, 50, 1, 300)
    M.BindSlider(ctx, urgent,
        function() return tonumber(ReadG("ufcoreUrgentMaxPerFlush", 10)) or 10 end,
        function(v) SetG("ufcoreUrgentMaxPerFlush", floor((tonumber(v) or 10) + 0.5), "MSUF2_UFCORE_URGENT", { preview = false }) end)

    local welcome = W.Toggle(updates, "Show welcome message")
    M.BindToggle(ctx, welcome,
        function() return ReadGBool("showWelcomeMessage", true) end,
        function(v) SetGBool("showWelcomeMessage", v, "MSUF2_WELCOME", { preview = false }) end)

    local version = W.Toggle(updates, "Enable version check (peer-to-peer)")
    M.BindToggle(ctx, version,
        function() return ReadGBool("versionCheckEnabled", true) end,
        function(v) SetGBool("versionCheckEnabled", v, "MSUF2_VERSION_CHECK", { preview = false }) end)

    local tooltips = b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", 166, false)
    local disable = W.Toggle(tooltips, "Disable MSUF unitframe tooltips")
    M.BindToggle(ctx, disable,
        function() return ReadGBool("disableUnitInfoTooltips", false) end,
        function(v) SetGBool("disableUnitInfoTooltips", v, "MSUF2_TOOLTIPS", { preview = false }) end)
    local tooltipStyle = W.Dropdown(tooltips, "MSUF unitframe tooltip position", {
        { value = "classic", text = "Blizzard Classic" },
        { value = "modern", text = "Modern (under cursor)" },
    }, 240)
    M.BindDropdown(ctx, tooltipStyle,
        function() return ReadG("unitInfoTooltipStyle", "classic") end,
        function(v) SetG("unitInfoTooltipStyle", v or "classic", "MSUF2_TOOLTIP_STYLE", { preview = false }) end)

    local blizzard = b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", 190, false)
    local blizzUF = W.Toggle(blizzard, "Disable Blizzard unitframes")
    M.BindToggle(ctx, blizzUF,
        function() return ReadGBool("disableBlizzardUnitFrames", true) end,
        function(v)
            SetGBool("disableBlizzardUnitFrames", v, "MSUF2_DISABLE_BLIZZARD_UF", { preview = false })
            if print then print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.") end
        end)
    local hardKill = W.Toggle(blizzard, "Fully Hide Blizzard PlayerFrame - resource bar compatibility")
    M.BindToggle(ctx, hardKill,
        function() return ReadGBool("hardKillBlizzardPlayerFrame", false) end,
        function(v)
            SetGBool("hardKillBlizzardPlayerFrame", v, "MSUF2_HARDKILL_PLAYERFRAME", { preview = false })
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end)
    local minimap = W.Toggle(blizzard, "Show MSUF minimap icon")
    M.BindToggle(ctx, minimap,
        function() return ReadGBool("showMinimapIcon", true) end,
        function(v)
            SetGBool("showMinimapIcon", v, "MSUF2_MINIMAP_ICON", { preview = false })
            if type(_G.MSUF_SetMinimapIconEnabled) == "function" then
                pcall(_G.MSUF_SetMinimapIconEnabled, v)
            else
                local g = G()
                g.minimapIconDB = g.minimapIconDB or {}
                g.minimapIconDB.hide = not v
            end
        end)
    local sounds = W.Toggle(blizzard, "Play sound on Target/Target Lost")
    M.BindToggle(ctx, sounds,
        function() return ReadGBool("playTargetSelectLostSounds", false) end,
        function(v)
            SetGBool("playTargetSelectLostSounds", v, "MSUF2_TARGET_SOUNDS", { preview = false })
            Call("MSUF_TargetSoundDriver_ResetState")
            if v then Call("MSUF_TargetSoundDriver_Ensure") end
        end)

    local range = b:CollapsibleSection("misc_range_fade", "Range Fade", 300, false)
    for _, spec in ipairs({
        { unit = "target", key = "rangeFadeEnabled", label = "Target range fade" },
        { unit = "focus", key = "rangeFadeEnabled", label = "Focus range fade" },
        { unit = "boss", key = "rangeFadeEnabled", label = "Boss range fade" },
        { unit = "boss", key = "rangeFadeCastbar", label = "Boss castbar range fade" },
        { unit = "boss", key = "rangeFadeAuras", label = "Boss auras range fade" },
    }) do
        local toggle = W.Toggle(range, spec.label)
        M.BindToggle(ctx, toggle,
            function() return Unit(spec.unit)[spec.key] == true end,
            function(v)
                SetUBool(spec.unit, spec.key, v, "MSUF2_RANGE_FADE", { alpha = true, preview = true })
                if spec.unit == "target" then
                    RefreshTargetRangeFade()
                else
                    RefreshFocusBossRangeFade()
                end
            end)
    end

    local alpha = W.Slider(range, "Out of range alpha", 0, 60, 5, 300)
    M.BindSlider(ctx, alpha,
        function()
            local value = tonumber(Unit("target").rangeFadeAlpha or Unit("focus").rangeFadeAlpha or Unit("boss").rangeFadeAlpha or 0.6) or 0.6
            if value < 0 then value = 0 elseif value > 0.6 then value = 0.6 end
            return floor(value * 100 + 0.5)
        end,
        function(v)
            v = (tonumber(v) or 60) / 100
            if v < 0 then v = 0 elseif v > 0.6 then v = 0.6 end
            Unit("target").rangeFadeAlpha = v
            Unit("focus").rangeFadeAlpha = v
            Unit("boss").rangeFadeAlpha = v
            RefreshRangeFadeRuntime()
            M.RequestGeneralApply("MSUF2_RANGE_FADE_ALPHA", { alpha = true, preview = true, applyAll = false })
        end)

    local portrait = W.Toggle(range, "Fade portrait too")
    M.BindToggle(ctx, portrait,
        function() return ReadGBool("rangeFadePortrait", false) end,
        function(v)
            SetGBool("rangeFadePortrait", v, "MSUF2_RANGE_FADE_PORTRAIT", { alpha = true, preview = true })
            RefreshRangeFadeRuntime()
            Call("MSUF_RefreshAllUnitAlphas")
        end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_fonts", { title = "MSUF Fonts", build = BuildFonts, version = 2 })
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 4 })
M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 2 })
M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc })

local addonName, ns = ...
ns = ns or {}
ns.Core   = ns.Core   or {}
ns.UF     = ns.UF     or {}
ns.Bars   = ns.Bars   or {}
ns.Text   = ns.Text   or {}
ns.Icons  = ns.Icons  or {}
ns.Util   = ns.Util   or {}
ns.Cache  = ns.Cache  or {}
ns.Compat = ns.Compat or {}
-- Patch M: table-driven hide helpers (safe, no string compares)
ns.Bars._outlineParts = ns.Bars._outlineParts or { "top", "bottom", "left", "right", "tl", "tr", "bl", "br" }
ns.Util.HideKeys = ns.Util.HideKeys or function(t, keys, extraKey)
    if not t or not keys then return end
    for i = 1, #keys do
        local obj = t[keys[i]]
        if obj and obj.Hide then obj:Hide() end
    end
    if extraKey then
        local obj = t[extraKey]
        if obj and obj.Hide then obj:Hide() end
    end
end
-- Patch N: DB helpers (SavedVariables only; not F.UnitName/etc)
ns.Util.Val = ns.Util.Val or function(conf, g, key, default)
    local v = conf and conf[key]; if v == nil and g then v = g[key] end; if v == nil then v = default end; return v
end
ns.Util.Num = ns.Util.Num or function(conf, g, key, default)
    local v = tonumber(ns.Util.Val(conf, g, key, nil)); return (v == nil) and default or v
end
ns.Util.Enabled = ns.Util.Enabled or function(conf, g, key, defaultEnabled)
    local v = ns.Util.Val(conf, g, key, nil); if v == nil then return (defaultEnabled ~= false) end; return (v ~= false)
end
ns.Util.SetShown = ns.Util.SetShown or function(obj, show)
    if not obj then return end; if show then if obj.Show then obj:Show() end else if obj.Hide then obj:Hide() end end
end
ns.Util.Offset = ns.Util.Offset or function(v, default) return (v == nil) and default or v end

local F = ns.Cache.F or {}; ns.Cache.F = F
if not F._msufInit then
    F._msufInit = true
    local G = _G; F.UnitHealth, F.UnitHealthMax, F.UnitPower, F.UnitPowerMax = G.UnitHealth, G.UnitHealthMax, G.UnitPower, G.UnitPowerMax; F.UnitExists, F.UnitIsConnected, F.UnitIsDeadOrGhost = G.UnitExists, G.UnitIsConnected, G.UnitIsDeadOrGhost; F.UnitName, F.UnitClass, F.UnitReaction, F.UnitIsPlayer = G.UnitName, G.UnitClass, G.UnitReaction, G.UnitIsPlayer; F.CreateFrame, F.InCombatLockdown, F.GetTime = G.CreateFrame, G.InCombatLockdown, G.GetTime
end

-- Patch T: unified stamp cache (layout/indicator/portrait) to avoid per-call string stamps
ns.Cache.StampChanged = ns.Cache.StampChanged or function(o, k, ...)
    if not o then return true end
    local c = o._msufStampCache; if not c then c = {}; o._msufStampCache = c end
    local r = c[k]; local n = select("#", ...)
    if not r then r = { n = n }; c[k] = r; for i = 1, n do r[i] = select(i, ...) end; return true end
    if r.n ~= n then r.n = n; for i = 1, n do r[i] = select(i, ...) end; for i = n + 1, #r do r[i] = nil end; return true end
    for i = 1, n do local v = select(i, ...); if r[i] ~= v then for j = 1, n do r[j] = select(j, ...) end; return true end end
    return false
end
ns.Cache.ClearStamp = ns.Cache.ClearStamp or function(o, k) local c = o and o._msufStampCache; if c then c[k] = nil end end


-- Patch Y: Unitframe element factories (build-time scaffolding; no runtime behavior change)
-- Goal: remove copy/paste in unitframe creation by providing tiny, reusable constructors.
-- NOTE: Keep secret-safe: only operate on addon-owned keys/names; no comparisons on unit API strings.
ns.UF._ResolveParent = ns.UF._ResolveParent or function(self, parentKey)
    if not self then return nil end
    if (not parentKey) or (parentKey == "self") then return self end
    local t = type(parentKey)
    if t == "table" or t == "userdata" then return parentKey end
    if parentKey == "UIParent" and UIParent then return UIParent end
    local p = self[parentKey]
    return p or self
end
ns.UF._MakeChildName = ns.UF._MakeChildName or function(self, suffix)
    if not suffix then return nil end
    local base = (self and self.GetName) and self:GetName() or nil
    if base and base ~= "" then return base .. suffix end
    return nil
end
ns.UF.MakeFrame = ns.UF.MakeFrame or function(self, key, frameType, parentKey, inherits, nameSuffix, strata, level)
    if not self or not key then return nil end
    local o = self[key]
    if o then return o end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent then return nil end
    local name = ns.UF._MakeChildName(self, nameSuffix)
    local cf = (ns.Cache and ns.Cache.F and ns.Cache.F.CreateFrame) or CreateFrame
    o = cf(frameType or "Frame", name, parent, inherits)
    if strata and o.SetFrameStrata then o:SetFrameStrata(strata) end
    if level and o.SetFrameLevel then o:SetFrameLevel(level) end
    self[key] = o
    return o
end
ns.UF.MakeBar = ns.UF.MakeBar or function(self, key, parentKey, inherits, nameSuffix)
    return ns.UF.MakeFrame(self, key, "StatusBar", parentKey, inherits, nameSuffix)
end
ns.UF.MakeTex = ns.UF.MakeTex or function(self, key, parentKey, layer, sublayer, nameSuffix)
    if not self or not key then return nil end
    local t = self[key]
    if t then return t end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent or not parent.CreateTexture then return nil end
    local name = ns.UF._MakeChildName(self, nameSuffix)
    t = parent:CreateTexture(name, layer or "ARTWORK", nil, sublayer)
    self[key] = t
    return t
end
ns.UF.MakeFont = ns.UF.MakeFont or function(self, key, parentKey, template, layer, sublayer, nameSuffix)
    if not self or not key then return nil end
    local fs = self[key]
    if fs then return fs end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent or not parent.CreateFontString then return nil end
    local name = ns.UF._MakeChildName(self, nameSuffix)
    fs = parent:CreateFontString(name, layer or "OVERLAY", template, sublayer)
    self[key] = fs
    return fs
end
-- - Secret-safe (no string comparisons)
function ns.UF.RequestUpdate(frame, forceFull, wantLayout, reason, urgentNow)
    if not frame then return end
    return _G.MSUF_RequestUnitframeUpdate(frame, forceFull, wantLayout, reason, urgentNow)
end
--   - Keep secret-safe: no text comparisons; only API calls / boolean checks
function ns.UF.IsDisabled(conf)
    return (conf and conf.enabled == false) and true or false
end
function ns.UF.ResolveKeyAndConf(self, unit, db)
    local key = self and self.msufConfigKey
    if not key then
        key = (unit and GetConfigKeyForUnit and GetConfigKeyForUnit(unit)) or unit
        self.msufConfigKey = key
    end
    local conf = self and self.cachedConfig
    if not conf then
        conf = (key and db and db[key]) or nil
        self.cachedConfig = conf
    end
    return key, conf
end

function ns.UF.EnsureStatusIndicatorOverlays(f, unit, fontPath, flags, fr, fg, fb)
    if not f or (unit ~= "player" and unit ~= "target") then return end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local size = ((g and (g.nameFontSize or g.fontSize)) or 14) + 2
    local ov = ns.UF.MakeFrame(f, "statusIndicatorOverlayFrame", "Frame", UIParent, nil, nil, "HIGH", 999)
    if ov then ov:ClearAllPoints(); ov:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); ov:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); ov:Hide() end
    local defs = { { "statusIndicatorText", "textFrame", 0.95 }, { "statusIndicatorOverlayText", "statusIndicatorOverlayFrame", 1 } }
    for i = 1, #defs do
        local key, parentKey, a = defs[i][1], defs[i][2], defs[i][3]
        local fs = ns.UF.MakeFont(f, key, parentKey, "GameFontHighlightLarge", "OVERLAY")
        if fs then
            fs:SetFont(fontPath, size, flags); fs:SetJustifyH("CENTER"); if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
            fs:SetTextColor(fr, fg, fb, a); fs:ClearAllPoints(); fs:SetPoint("CENTER", f, "CENTER", 0, 0); fs:SetText(""); fs:Hide()
    end
    end
end

-- Shared text object creation (unitframes)
-- Keep behavior identical: same templates, justify, alpha, and hidden defaults.
local MSUF_UF_TEXT_CREATE_DEFS = {
    { key = "nameText",      template = "GameFontHighlight",      justify = "LEFT",  a = 1 },
    { key = "levelText",     template = "GameFontHighlightSmall", justify = "LEFT",  a = 1,   hide = true },
    { key = "hpText",        template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9 },
    { key = "hpTextPct",     template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9, hide = true },
    { key = "powerTextPct",  template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9, hide = true },
    { key = "powerText",     template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9 },
}
function ns.UF.EnsureTextObjects(f, fontPath, flags, fr, fg, fb)
    local tf = f and f.textFrame
    if not tf then return end
    flags = flags or ""
    for i = 1, #MSUF_UF_TEXT_CREATE_DEFS do
        local d = MSUF_UF_TEXT_CREATE_DEFS[i]
        local fs = ns.UF.MakeFont(f, d.key, "textFrame", d.template, "OVERLAY")
        if fs then
            if fs.SetFont and fontPath then fs:SetFont(fontPath, 14, flags) end
            if d.justify and fs.SetJustifyH then fs:SetJustifyH(d.justify) end
            if fs.SetTextColor and fr and fg and fb then fs:SetTextColor(fr, fg, fb, d.a or 1) end
            if d.hide then fs:SetText(""); fs:Hide() end
    end
    end
end

ns.UF.HpSpacerSelect_OnMouseDown = ns.UF.HpSpacerSelect_OnMouseDown or function(self)
    local k = self and (self.msufConfigKey or ((self.unit and GetConfigKeyForUnit) and GetConfigKeyForUnit(self.unit))) or nil
    if k and type(_G.MSUF_SetHpSpacerSelectedUnitKey) == "function" then _G.MSUF_SetHpSpacerSelectedUnitKey(k) end
end
ns.UF.UpdateHighlightColor = ns.UF.UpdateHighlightColor or function(self)
    if not self then return end
    if type(EnsureDB) == "function" then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or {}; local hr, hg, hb = 1, 1, 1; local hc = g.highlightColor
    if type(hc) == "table" then hr, hg, hb = hc[1] or 1, hc[2] or 1, hc[3] or 1
    else
        local key = (type(hc) == "string" and string.lower(hc)) or "white"
        local col = (type(MSUF_FONT_COLORS) == "table" and (MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white)) or nil
        if col then hr, hg, hb = col[1] or 1, col[2] or 1, col[3] or 1 end
    end
    local s = tostring(hr) .. "|" .. tostring(hg) .. "|" .. tostring(hb)
    if self._msufHighlightColorStamp ~= s then self._msufHighlightColorStamp = s; local b = self.highlightBorder; if b and b.SetBackdropBorderColor then b:SetBackdropBorderColor(hr, hg, hb, 1) end end
end
ns.UF.Unitframe_OnEnter = ns.UF.Unitframe_OnEnter or function(self)
    if not self then return end
    if type(EnsureDB) == "function" then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hb = self.highlightBorder
    if hb then
        -- Use the canonical DB key (highlightEnabled). Keep backward-compat with older profiles.
        local enabled = (g.highlightEnabled ~= false)
        if g.highlightEnabled == nil and g.enableHighlightOnHover ~= nil then
            enabled = (g.enableHighlightOnHover == true)
        end
        if enabled then
            if self.UpdateHighlightColor then self:UpdateHighlightColor() end
            hb:Show()
        else
            hb:Hide()
        end
    end
    if g.disableUnitInfoTooltips then
        if GameTooltip and self.unit and F.UnitExists and F.UnitExists(self.unit) then
            if (g.unitInfoTooltipStyle or "classic") == "modern" then GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR", 0, -100)
            else GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:ClearAllPoints(); GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 16) end
            GameTooltip:SetUnit(self.unit); GameTooltip:Show()
    end
        return
    end
    local u = self.unit
    local fnName = u and MSUF_UNIT_TIP_FUNCS and MSUF_UNIT_TIP_FUNCS[u]
    if fnName and F.UnitExists and F.UnitExists(u) and _G[fnName] then return (_G[fnName])() end
    if u and string.sub(u, 1, 4) == "boss" and F.UnitExists and F.UnitExists(u) and type(MSUF_ShowBossInfoTooltip) == "function" then MSUF_ShowBossInfoTooltip(u) end
end
ns.UF.Unitframe_OnLeave = ns.UF.Unitframe_OnLeave or function(self)
    if self and self.highlightBorder then self.highlightBorder:Hide() end
    local u = self and self.unit
    if u and ((MSUF_UNIT_TIP_FUNCS and MSUF_UNIT_TIP_FUNCS[u]) or string.sub(u, 1, 4) == "boss") and type(MSUF_HidePlayerInfoTooltip) == "function" then MSUF_HidePlayerInfoTooltip() end
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

function ns.UF.HideLeaderAndRaidMarker(self)
    if not self then return end
    ns.Util.SetShown(self.leaderIcon, false)
    ns.Util.SetShown(self.raidMarkerIcon, false)
end
function ns.UF.HandleDisabledFrame(self, conf)
    if not ns.UF.IsDisabled(conf) then return false end
    if not F.InCombatLockdown() then
        if self and self.Hide then self:Hide() end
        if self and self.portrait and self.portrait.Hide then self.portrait:Hide() end
        if self and self.isFocus and type(MSUF_ReanchorFocusCastBar) == "function" then
            MSUF_ReanchorFocusCastBar()
    end
    end
    if type(MSUF_ClearUnitFrameState) == "function" then
        MSUF_ClearUnitFrameState(self, true)
    end
    ns.UF.HideLeaderAndRaidMarker(self)
    return true
end
function ns.UF.ForceVisibilityHidden(frame)
    if not frame then return end
    local rsd = _G and _G.RegisterStateDriver
    local usd = _G and _G.UnregisterStateDriver
    if type(rsd) == "function" and type(usd) == "function" then
        usd(frame, "visibility")
        rsd(frame, "visibility", "hide")
    end
    frame._msufVisibilityForced = "disabled"
end

function ns.UF.ShouldRunHeavyVisual(self, key, exists)
    if not self or not exists then return false end
    if self._msufLayoutWhy or self._msufVisualQueuedUFCore or self._msufPortraitDirty or self._msufNeedsBorderVisual then
        return true
    end
    local tokenFlags = _G.MSUF_UnitTokenChanged
    if tokenFlags and key and tokenFlags[key] then
        return true
    end
    if self.IsShown and not self:IsShown() then
        return false
    end
    local now = (F.GetTime and F.GetTime()) or 0
    local nextAt = self._msufHeavyVisualNextAt or 0
    if nextAt == 0 then
        return true
    end
    if now >= nextAt then
        return true
    end
    return false
end

ns.__msuf_patchF = ns.__msuf_patchF or { version = "F1", note = "compact locals + secret-safe clear text" }
local ROOT_G = (getfenv and getfenv(0)) or _G
do
    local realG = _G
    if type(realG.MSUF_GetCastbarTexture) ~= "function" then
        function realG.MSUF_GetCastbarTexture()
            return "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    end
    ROOT_G.MSUF_GetCastbarTexture = realG.MSUF_GetCastbarTexture
end
local pairs, ipairs, unpack, tonumber, type = pairs, ipairs, unpack or table.unpack, tonumber, type
local math_floor, math_max = math.floor, math.max
local UnitFramesList = {}

-- Patch AA2: move shared helpers earlier (used by early functions) + keep deterministic iteration
local UnitFrames = _G.MSUF_UnitFrames
if type(UnitFrames) ~= "table" then
    UnitFrames = {}
    _G.MSUF_UnitFrames = UnitFrames
end

local function MSUF_ForEachUnitFrame(fn)
    if not fn then return end
    local list = UnitFramesList
    if list and #list > 0 then
        for i = 1, #list do
            local f = list[i]
            if f then fn(f) end
    end
        return
    end
    for unitKey, f in pairs(UnitFrames) do
        if f then fn(f, unitKey) end
    end
end

local function MSUF_Export2(key, fn, aliasKey, forceAlias)
    if ns then ns[key] = fn end
    _G[key] = fn
    if aliasKey then
        if forceAlias then
            _G[aliasKey] = fn
        else
            _G[aliasKey] = _G[aliasKey] or fn
    end
    end
    return fn
end

local function MSUF_EnsureUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    local bi = u and u:match("^boss(%d+)$")
    f._msufBossIndex = bi and tonumber(bi) or nil
    f._msufUnitFlagsInited = true
end
local function MSUF_IsTargetLikeFrame(f)
    return (f and (f.isBoss or f._msufIsPlayer or f._msufIsTarget or f._msufIsFocus)) and true or false
end
local function MSUF_ResetBarZero(bar, hide)
    if not bar then return end
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if hide then bar:Hide() end
end
local function MSUF_ClearText(fs, hide)
    if not fs then return end
    fs:SetText("")
    if hide then fs:Hide() end
end
ns.Bars._msufPatchB = ns.Bars._msufPatchB or { version = "B1" }
function ns.Bars.HidePowerBarOnly(bar)
    if not bar then return true end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    return true
end
function ns.Bars.HideAndResetPowerBar(bar)
    if not bar then return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    MSUF_ResetBarZero(bar, true)
end
function ns.Bars.ApplyPowerGradientOnce(frame)
    if not frame then return end
    if frame.powerGradients then
        if MSUF_ApplyPowerGradient then MSUF_ApplyPowerGradient(frame) end
    elseif frame.powerGradient then
        if MSUF_ApplyPowerGradient then MSUF_ApplyPowerGradient(frame.powerGradient) end
    end
end
function ns.Bars.PowerBarAllowed(barsConf, isBoss, isPlayer, isTarget, isFocus)
    if not barsConf then return true end
    if isPlayer then
        return (barsConf.showPlayerPowerBar ~= false)
    end
    if isFocus then
        return (barsConf.showFocusPowerBar ~= false)
    end
    if isTarget then
        return (barsConf.showTargetPowerBar ~= false)
    end
    if isBoss then
        return (barsConf.showBossPowerBar ~= false)
    end
    return true
end
function ns.Bars.ApplyPowerBarVisual(frame, bar, pType, pTok)
    if not bar then return end
    local pr, pg, pb = MSUF_GetPowerBarColor(pType, pTok)
    if not pr then
        local colPB = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
        pr, pg, pb = colPB.r, colPB.g, colPB.b
    end
    bar:SetStatusBarColor(pr, pg, pb)
    ns.Bars.ApplyPowerGradientOnce(frame)
end
function ns.Bars.SetOverlayBarTexture(bar, texGetter)
    if not bar or not bar.SetStatusBarTexture or not texGetter then return end
    local tex = texGetter()
    if tex then
        bar:SetStatusBarTexture(tex)
        bar.MSUF_cachedStatusbarTexture = tex
    end
end

-- Patch Q2: Bars spec-driven Apply (Health/Power/Absorb/HealAbsorb + Reset/Hide)
ns.Bars._msufPatchQ = ns.Bars._msufPatchQ or { version = "Q2" }
ns.Bars.Spec = ns.Bars.Spec or {}

function ns.Bars.ApplySpec(frame, unit, key, ...)
    local fn = ns.Bars.Spec and ns.Bars.Spec[key]
    if not fn then return nil end
    return fn(frame, unit, ...)
end

ns.Bars.Spec.health = ns.Bars.Spec.health or function(frame, unit)
    if not frame or not unit or not frame.hpBar then return nil, nil, false end
    if not (F.UnitExists and F.UnitExists(unit)) then
        ns.Bars.ResetHealthAndOverlays(frame, true)
        return 0, 1, false
    end
    local maxHP = (F.UnitHealthMax and F.UnitHealthMax(unit)) or 1
    local hp = (F.UnitHealth and F.UnitHealth(unit)) or 0
    ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
    return hp, maxHP, true
end

local function _MSUF_Bars_HidePower(bar, hardReset)
    if not bar then return true end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    if hardReset then MSUF_ResetBarZero(bar, true) end
    return true
end

local function _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, wantPercent)
    if not (frame and bar and unit) then return false end
    if not (F.UnitExists and F.UnitExists(unit)) then
        return _MSUF_Bars_HidePower(bar, not wantPercent)
    end
    if not MSUF_IsTargetLikeFrame(frame) then
        return _MSUF_Bars_HidePower(bar, not wantPercent)
    end
    if not ns.Bars.PowerBarAllowed(barsConf, isBoss, isPlayer, isTarget, isFocus) then
        return _MSUF_Bars_HidePower(bar, not wantPercent)
    end

    local pType, pTok
    if wantPercent then
        local okPT; okPT, pType, pTok = MSUF_FastCall(UnitPowerType, unit)
        if not okPT then return _MSUF_Bars_HidePower(bar, false) end

        local okPct, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            okPct, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, CurveConstants.ScaleTo100)
        else
            okPct, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, true)
    end
        if not okPct then return _MSUF_Bars_HidePower(bar, false) end

        ns.Bars.ApplyPowerBarVisual(frame, bar, pType, pTok)
        MSUF_SetBarMinMax(bar, 0, 100)
        bar:SetScript("OnUpdate", nil)
        MSUF_SetBarValue(bar, pct, true)
        bar:Show()
        return true
    end

    pType, pTok = UnitPowerType(unit)
    local cur = F.UnitPower(unit, pType)
    local max = F.UnitPowerMax(unit, pType)
    if cur == nil or max == nil then
        return _MSUF_Bars_HidePower(bar, true)
    end

    ns.Bars.ApplyPowerBarVisual(frame, bar, pType, pTok)
    bar:SetMinMaxValues(0, max)
    bar:SetScript("OnUpdate", nil)
    MSUF_SetBarValue(bar, cur)
    bar:Show()
    return true
end

ns.Bars.Spec.power_abs = ns.Bars.Spec.power_abs or function(frame, unit)
    if not frame or not unit then return end
    local bar = frame.targetPowerBar
    if not bar then return end
    local barsConf = (MSUF_DB and MSUF_DB.bars) or {}
    MSUF_EnsureUnitFlags(frame)
    _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, frame.isBoss, frame._msufIsPlayer, frame._msufIsTarget, frame._msufIsFocus, false)
end

ns.Bars.Spec.power_pct = ns.Bars.Spec.power_pct or function(frame, unit, barsConf, isBoss, isPlayer, isTarget, isFocus)
    local bar = frame and frame.targetPowerBar
    if not (frame and unit and bar) then return false end
    barsConf = barsConf or ((MSUF_DB and MSUF_DB.bars) or {})
    return _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, true)
end
ns.Bars._msufPatchC = ns.Bars._msufPatchC or { version = "C1" }
function ns.Bars.ResetHealthAndOverlays(frame, clearAbsorbs)
    if not frame then return end
    MSUF_ResetBarZero(frame.hpBar)
    if clearAbsorbs then
        MSUF_ResetBarZero(frame.absorbBar, true)
        MSUF_ResetBarZero(frame.healAbsorbBar, true)
    end
end
function ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
    if not frame or not unit or not frame.hpBar then return nil, nil end
    if maxHP == nil and F.UnitHealthMax then
        maxHP = F.UnitHealthMax(unit)
    end
    if maxHP then
        frame.hpBar:SetMinMaxValues(0, maxHP)
    end
    if hp == nil and F.UnitHealth then
        hp = F.UnitHealth(unit)
    end
    if hp ~= nil then
        MSUF_SetBarValue(frame.hpBar, hp)
    end
    if frame.absorbBar then
        MSUF_UpdateAbsorbBar(frame, unit, maxHP)
    end
    if frame.healAbsorbBar then
        MSUF_UpdateHealAbsorbBar(frame, unit, maxHP)
    end
    return hp, maxHP
end
ns.Text._msufPatchD = ns.Text._msufPatchD or { version = "D1" }
function ns.Text.Set(fs, text, show)
    -- Secret-safe: do NOT compare strings. Pass-through to API only.
    if not fs then return end
    if not show then
        if fs.Hide then fs:Hide() end
        -- Clearing to empty string is safe (non-secret).
        if fs.SetText then fs:SetText("") end
        return
    end
    if text == nil then text = "" end
    if fs.SetText then fs:SetText(text) end
    if fs.Show then fs:Show() end
end
ns.Text._msufPatchE = ns.Text._msufPatchE or { version = "E1" }
-- Secret-safe: numeric clamps only; no text comparisons.
ns.Text._msufPatchG = ns.Text._msufPatchG or { version = "G1" }
function ns.Text.ClampSpacerValue(value, maxValue, enabled)
    if not enabled then return 0 end
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    local m = tonumber(maxValue) or 0
    if m < 0 then m = 0 end
    if v > m then v = m end
    return v
end
_G.MSUF_TEXTLAYOUT_VALID_KEYS = _G.MSUF_TEXTLAYOUT_VALID_KEYS or { player=true, target=true, focus=true, targettarget=true, pet=true, boss=true }
function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, fallbackKey)
    local k = unitKey
    if not k or k == "" then k = fallbackKey or (MSUF_DB and MSUF_DB.general and MSUF_DB.general.hpSpacerSelectedUnitKey) or "player" end
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" then local ok, m = MSUF_FastCall(string.match, k, "^boss%d+$"); if ok and m then k = "boss" end end
    if not _G.MSUF_TEXTLAYOUT_VALID_KEYS[k] then k = "player" end
    return k
end
function ns.Text.SetFormatted(fs, show, fmt, ...)
    -- Secret-safe: do NOT compare results. Pass-through to FontString API.
    if not fs then return end
    if not show then
        if fs.Hide then fs:Hide() end
        if fs.SetText then fs:SetText("") end
        return
    end
    if fs.SetFormattedText then
        fs:SetFormattedText(fmt, ...)
    else
        -- Fallback: avoid string.format on potentially secret args; just clear.
        if fs.SetText then fs:SetText("") end
    end
    if fs.Show then fs:Show() end
end
function ns.Text.Clear(fs, hide)
    -- Secret-safe: do NOT compare strings.
    if not fs then return end
    if fs.SetText then fs:SetText("") end
    if hide and fs.Hide then fs:Hide() end
end
function ns.Text.ClearField(self, field)
    if not self then return end
    local fs = self[field]
    if not fs then return end
    ns.Text.Clear(fs, true)
end

-- Patch O: central text renderers (HP/Power/Pct/ToT inline) - secret-safe (no string compares)
function ns.Text._SepToken(raw, fallback)
    local sep = raw
    if sep == nil then sep = fallback end
    if sep == nil then sep = "" end
    if sep == "" then
        return " "
    end
    return " " .. sep .. " "
end
function ns.Text._ShouldSplitHP(self, conf, g, hpMode)
    if not self or not self.hpTextPct then return false end
    if hpMode ~= "FULL_PLUS_PERCENT" and hpMode ~= "PERCENT_PLUS_FULL" then return false end
    local on = (conf and conf.hpTextSpacerEnabled == true) or (not conf and g and g.hpTextSpacerEnabled == true)
    if not on then return false end
    local x = (conf and tonumber(conf.hpTextSpacerX)) or (g and tonumber(g.hpTextSpacerX)) or 0
    x = tonumber(x) or 0
    return (x > 0)
end
function ns.Text.RenderHpMode(self, show, hpStr, hpPct, hasPct, conf, g, absorbText, absorbStyle)
    if not self or not self.hpText then return end
    if not show then
        ns.Text.Set(self.hpText, "", false)
        ns.Text.ClearField(self, "hpTextPct")
        return
    end
    local hpMode = (g and g.hpTextMode) or "FULL_PLUS_PERCENT"
    local sep = ns.Text._SepToken(g and g.hpTextSeparator, nil)
    local split = (hasPct == true) and ns.Text._ShouldSplitHP(self, conf, g, hpMode) or false
    local function SetWithAbsorb(fmtNo, fmtSpace, fmtParen, ...)
        -- IMPORTANT: Never put `...` before another argument in a call.
        -- In Lua, varargs only expand fully in the last position.
        local n = select('#', ...)
        local a1, a2, a3 = ...
        if absorbText then
            local fmt = (absorbStyle == "PAREN") and fmtParen or fmtSpace
            if n <= 0 then
                ns.Text.SetFormatted(self.hpText, true, fmt, absorbText)
            elseif n == 1 then
                ns.Text.SetFormatted(self.hpText, true, fmt, a1, absorbText)
            elseif n == 2 then
                ns.Text.SetFormatted(self.hpText, true, fmt, a1, a2, absorbText)
            else
                ns.Text.SetFormatted(self.hpText, true, fmt, a1, a2, a3, absorbText)
            end
        else
            if n <= 0 then
                ns.Text.SetFormatted(self.hpText, true, fmtNo)
            elseif n == 1 then
                ns.Text.SetFormatted(self.hpText, true, fmtNo, a1)
            elseif n == 2 then
                ns.Text.SetFormatted(self.hpText, true, fmtNo, a1, a2)
            else
                ns.Text.SetFormatted(self.hpText, true, fmtNo, a1, a2, a3)
            end
        end
    end

    if split then
        SetWithAbsorb("%s", "%s %s", "%s (%s)", hpStr or "")
        ns.Text.SetFormatted(self.hpTextPct, true, "%.1f%%", hpPct)
        return
    end

    ns.Text.ClearField(self, "hpTextPct")
    if not hasPct then
        SetWithAbsorb("%s", "%s %s", "%s (%s)", hpStr or "")
        return
    end

    if hpMode == "FULL_ONLY" then
        SetWithAbsorb("%s", "%s %s", "%s (%s)", hpStr or "")
    elseif hpMode == "PERCENT_ONLY" then
        SetWithAbsorb("%.1f%%", "%.1f%% %s", "%.1f%% (%s)", hpPct)
    elseif hpMode == "PERCENT_PLUS_FULL" then
        SetWithAbsorb("%.1f%%%s%s", "%.1f%%%s%s %s", "%.1f%%%s%s (%s)", hpPct, sep, hpStr or "")
    else
        SetWithAbsorb("%s%s%.1f%%", "%s%s%.1f%% %s", "%s%s%.1f%% (%s)", hpStr or "", sep, hpPct)
    end
end

function ns.Text.GetUnitPowerPercent(unit)
    if type(UnitPowerPercent) == "function" then
        -- Secret-safe: avoid computing percent in Lua; use API pass-through if available.
        local pType
        if type(UnitPowerType) == "function" then
            local okType, pt = MSUF_FastCall(UnitPowerType, unit)
            if okType then pType = pt end
    end
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, CurveConstants.ScaleTo100)
        else
            ok, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, true)
    end
        if ok then return pct end
    end
    return nil
end
_G.MSUF_GetUnitPowerPercent = _G.MSUF_GetUnitPowerPercent or ns.Text.GetUnitPowerPercent

function ns.Text._ShouldSplitPower(self, pMode, hasPct)
    if not self or not hasPct or not self.powerTextPct then return false end
    if pMode ~= "FULL_PLUS_PERCENT" and pMode ~= "PERCENT_PLUS_FULL" then return false end
    if type(EnsureDB) == "function" then EnsureDB() end
    local key = self.msufConfigKey
    local udb = (key and MSUF_DB and MSUF_DB[key]) or nil
    local gen = (MSUF_DB and MSUF_DB.general) or nil
    local on = (udb and udb.powerTextSpacerEnabled == true) or (not udb and gen and gen.powerTextSpacerEnabled == true)
    if not on then return false end
    local x = (udb and tonumber(udb.powerTextSpacerX)) or ((gen and tonumber(gen.powerTextSpacerX)) or 0)
    x = tonumber(x) or 0
    if x <= 0 then return false end
    if key then
        local maxP = tonumber(_G.MSUF_GetPowerSpacerMaxForUnitKey(key)) or 0
        if x < 0 then x = 0 end
        if x > maxP then x = maxP end
    end
    return (x > 0)
end
function ns.Text.RenderPowerText(self)
    if not self or not self.unit or not self.powerText then return end
    local unit = self.unit
    local showPower = self.showPowerText
    if showPower == nil then showPower = true end
    if not showPower then
        ns.Text.Set(self.powerText, "", false)
        ns.Text.ClearField(self, "powerTextPct")
        return
    end
    local gPower = (MSUF_DB and MSUF_DB.general) or {}
    local colorByType = (gPower.colorPowerTextByType == true)
    local pMode = gPower.powerTextMode or "FULL_SLASH_MAX"
    local powerSep = ns.Text._SepToken(gPower.powerTextSeparator, gPower.hpTextSeparator)
    MSUF_EnsureUnitFlags(self)
    local isPlayer = self._msufIsPlayer
    local isFocus  = self._msufIsFocus
    if isPlayer or isFocus or F.UnitIsPlayer(unit) then
        local curText, maxText
        local okCur, curValue = MSUF_FastCall(F.UnitPower, unit)
        local okMax, maxValue = MSUF_FastCall(F.UnitPowerMax, unit)
        if okCur and curValue ~= nil then
            curText = (AbbreviateLargeNumbers and AbbreviateLargeNumbers(curValue)) or tostring(curValue)
    end
        if okMax and maxValue ~= nil then
            maxText = (AbbreviateLargeNumbers and AbbreviateLargeNumbers(maxValue)) or tostring(maxValue)
    end
        local powerPct = ns.Text.GetUnitPowerPercent(unit)
        local hasPct = (type(powerPct) == "number")
        local split = ns.Text._ShouldSplitPower(self, pMode, hasPct)
        if pMode == "FULL_ONLY" then
            ns.Text.Set(self.powerText, curText or "", true)
            ns.Text.ClearField(self, "powerTextPct")
        elseif pMode == "PERCENT_ONLY" then
            ns.Text.ClearField(self, "powerTextPct")
            if hasPct then
                ns.Text.SetFormatted(self.powerText, true, "%.1f%%", powerPct)
            else
                ns.Text.Set(self.powerText, curText or "", true)
            end
        elseif pMode == "FULL_PLUS_PERCENT" then
            if hasPct then
                if split then
                    ns.Text.Set(self.powerText, curText or "", true)
                    ns.Text.SetFormatted(self.powerTextPct, true, "%.1f%%", powerPct)
                else
                    ns.Text.ClearField(self, "powerTextPct")
                    ns.Text.SetFormatted(self.powerText, true, "%s%s%.1f%%", curText or "", powerSep, powerPct)
                end
            else
                ns.Text.ClearField(self, "powerTextPct")
                ns.Text.Set(self.powerText, curText or "", true)
            end
        elseif pMode == "PERCENT_PLUS_FULL" then
            if hasPct and split then
                ns.Text.Set(self.powerText, curText or "", true)
                ns.Text.SetFormatted(self.powerTextPct, true, "%.1f%%", powerPct)
            else
                ns.Text.ClearField(self, "powerTextPct")
                if hasPct then
                    ns.Text.SetFormatted(self.powerText, true, "%.1f%%%s%s", powerPct, powerSep, curText or "")
                else
                    ns.Text.Set(self.powerText, curText or "", true)
                end
            end
        else
            ns.Text.ClearField(self, "powerTextPct")
            if curText and maxText then
                ns.Text.SetFormatted(self.powerText, true, "%s%s%s", curText, powerSep, maxText)
            elseif curText then
                ns.Text.Set(self.powerText, curText, true)
            elseif maxText then
                ns.Text.Set(self.powerText, maxText, true)
            else
                ns.Text.Set(self.powerText, "", true)
            end
    end
        ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
        return
    elseif self.isBoss and C_StringUtil and C_StringUtil.TruncateWhenZero then
        local okCur, curText2 = MSUF_FastCall(function() return C_StringUtil.TruncateWhenZero(F.UnitPower(unit)) end)
        local okMax, maxText2 = MSUF_FastCall(function() return C_StringUtil.TruncateWhenZero(F.UnitPowerMax(unit)) end)
        ns.Text.ClearField(self, "powerTextPct")
        if okCur and curText2 and okMax and maxText2 then
            ns.Text.SetFormatted(self.powerText, true, "%s%s%s", curText2, powerSep, maxText2)
            ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
        elseif okCur and curText2 then
            ns.Text.Set(self.powerText, curText2, true)
            ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
        elseif okMax and maxText2 then
            ns.Text.Set(self.powerText, maxText2, true)
            ns.Text.ApplyPowerTextColorByType(self, unit, colorByType)
        else
            ns.Text.Set(self.powerText, "", false)
    end
        return
    end
    ns.Text.ClearField(self, "powerTextPct")
    ns.Text.Set(self.powerText, "", false)
end
function ns.Text.RenderToTInline(targetFrame, totConf)
    if not targetFrame or not targetFrame.nameText then return end
    local sep = targetFrame._msufToTInlineSep
    local txt = targetFrame._msufToTInlineText
    if not sep or not txt then return end
    local enabled = (totConf and totConf.showToTInTargetName) and true or false
    if not enabled or not (F.UnitExists and F.UnitExists("target")) or not (F.UnitExists and F.UnitExists("targettarget")) then
        ns.Util.SetShown(sep, false)
        ns.Util.SetShown(txt, false)
        return
    end
    local sepToken = (totConf and totConf.totInlineSeparator) or "|"
    if type(sepToken) ~= "string" or sepToken == "" then sepToken = "|" end
    sep:SetText(" " .. sepToken .. " ")
    -- Match target name font (no secret ops).
    local font, size, flags = targetFrame.nameText:GetFont()
    if font and sep.SetFont then
        sep:SetFont(font, size, flags)
        txt:SetFont(font, size, flags)
    end
    -- Clamp ToT inline width (secret-safe, no string width math).
    local frameWidth = (targetFrame.GetWidth and targetFrame:GetWidth()) or 0
    local maxW = 120
    if frameWidth and frameWidth > 0 then
        maxW = math.floor(frameWidth * 0.32)
        if maxW < 80 then maxW = 80 end
        if maxW > 180 then maxW = 180 end
    end
    txt:SetWidth(maxW)
    local r, gCol, b = 1, 1, 1
    if F.UnitIsPlayer and F.UnitIsPlayer("targettarget") then
        local useClass = false
        local g = MSUF_DB and MSUF_DB.general
        if g and g.nameClassColor then useClass = true end
        if useClass then
            local _, classToken = F.UnitClass("targettarget")
            r, gCol, b = MSUF_GetClassBarColor(classToken)
        else
            r, gCol, b = 1, 1, 1
    end
    else
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost("targettarget") then
            r, gCol, b = MSUF_GetNPCReactionColor("dead")
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", "targettarget")
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                end
            else
                r, gCol, b = MSUF_GetNPCReactionColor("enemy")
            end
    end
    end
    sep:SetTextColor(0.7, 0.7, 0.7)
    txt:SetTextColor(r, gCol, b)
    local totName = F.UnitName and F.UnitName("targettarget")
    txt:SetText(totName or "")
    ns.Util.SetShown(sep, true)
    ns.Util.SetShown(txt, true)
end
function ns.Text.ApplyPowerTextColorByType(self, unit, enabled)
    -- Secret-safe & pass-through: avoid extra comparisons/caching; just apply resolved color.
    if not enabled then return end
    if not (self and self.powerText and UnitPowerType) then return end
    local okPT, pType, pTok = MSUF_FastCall(UnitPowerType, unit)
    if not okPT then return end
    if type(MSUF_GetResolvedPowerColor) ~= "function" then return end
    local pr, pg, pb = MSUF_GetResolvedPowerColor(pType, pTok)
    if not pr then return end
    self.powerText:SetTextColor(pr, pg, pb, 1)
    self._msufPTColorByPower = true
    self._msufPTColorType = pType
    self._msufPTColorTok = pTok
end
function ns.Text.ApplyName(frame, unit, overrideText)
    -- Secret-safe: do NOT compare name strings. Use API pass-through only.
    if not frame or not frame.nameText then return end
    local show = (frame.showName ~= false)
    local txt = overrideText
    if txt == nil and show and unit and F.UnitName then
        txt = F.UnitName(unit)
    end
    if txt == nil then
        show = false
        txt = ""
    end
    ns.Text.Set(frame.nameText, txt, show)
end
function ns.Text.ApplyLevel(frame, unit, conf, overrideText, forceShow)
    -- Secret-safe: do NOT compare strings for emptiness.
    if not frame or not frame.levelText then return end
    local showLevel = true
    if conf and conf.showLevelIndicator == false then
        showLevel = false
    end
    if forceShow ~= nil then
        showLevel = (forceShow == true)
    end
    local txt = ""
    if overrideText ~= nil then
        txt = overrideText
    elseif showLevel and unit and F.UnitExists and F.UnitExists(unit) then
        txt = (MSUF_GetUnitLevelText and MSUF_GetUnitLevelText(unit)) or ""
    end
    ns.Text.Set(frame.levelText, txt, showLevel)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
end
function ns.Text.ApplyBossTestName(frame, unit)
    if not frame then return end
    local txt = "Test Boss"
    local idx
    if type(unit) == "string" then
        idx = unit:match("boss(%d+)")
    end
    if idx then
        txt = "Test Boss " .. idx
    end
    ns.Text.ApplyName(frame, unit, txt)
end
function ns.Text.ApplyBossTestLevel(frame, conf)
    if not frame or not frame.levelText then return end
    local show = (frame.showName ~= false)
    ns.Text.Set(frame.levelText, "??", show)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
end
local MSUF_BarBorderCache = { stamp = nil, thickness = 0 }
local function MSUF_GetBarBorderStyleId(style)
    if style == "THICK" then return 2 end
    if style == "SHADOW" then return 3 end
    if style == "GLOW" then return 4 end
    return 1 -- THIN/default
end
local function MSUF_GetDesiredBarBorderThicknessAndStamp()
    local barsDB = MSUF_DB and MSUF_DB.bars
    local gDB    = MSUF_DB and MSUF_DB.general
    local raw = barsDB and barsDB.barOutlineThickness
    local rawNum = (type(raw) == "number") and raw or tonumber(raw)
    local rawToken = rawNum and math_floor(rawNum * 10 + 0.5) or -999
    local useBit = 1
    if gDB and gDB.useBarBorder == false then useBit = 0 end
    local showToken = 1 -- nil/unspecified
    if barsDB and barsDB.showBarBorder ~= nil then
        if barsDB.showBarBorder == false then showToken = 0 else showToken = 2 end
    end
    local styleId = MSUF_GetBarBorderStyleId(gDB and gDB.barBorderStyle)
    local stamp = rawToken * 10000 + useBit * 1000 + showToken * 10 + styleId
    if MSUF_BarBorderCache.stamp ~= stamp then
        local thickness = rawNum
        if type(thickness) ~= "number" then
            local enabled = (useBit == 1)
            if barsDB and barsDB.showBarBorder ~= nil then
                enabled = (barsDB.showBarBorder ~= false)
            end
            if not enabled then
                thickness = 0
            else
                local map = { THIN = 1, THICK = 2, SHADOW = 3, GLOW = 3 }
                local style = (gDB and gDB.barBorderStyle) or "THIN"
                thickness = map[style] or 1
            end
    end
        thickness = tonumber(thickness) or 0
        thickness = math_floor(thickness + 0.5)
        if thickness < 0 then thickness = 0 end
        if thickness > 6 then thickness = 6 end
        MSUF_BarBorderCache.stamp = stamp
        MSUF_BarBorderCache.thickness = thickness
    end
    return MSUF_BarBorderCache.thickness, MSUF_BarBorderCache.stamp
end
local function MSUF_ApplyPoint(frame, point, relFrame, relPoint, x, y)
    if not frame then return end
    frame:ClearAllPoints()
    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if type(x) == "number" then x = snap(frame, x) end
        if type(y) == "number" then y = snap(frame, y) end
    end
    frame:SetPoint(point, relFrame, relPoint, x, y)
end
local function MSUF_SetStatusBarColor(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then return end
    if a ~= nil then
        bar:SetStatusBarColor(r, g, b, a)
    else
        bar:SetStatusBarColor(r, g, b)
    end
end
local function MSUF_CreateOverlayStatusBar(parent, baseBar, frameLevel, r, g, b, a, reverseFill)
    if not parent or not baseBar then return nil end
    local bar = F.CreateFrame("StatusBar", nil, parent)
    bar:SetAllPoints(baseBar)
    bar:SetStatusBarTexture(MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if frameLevel then
        bar:SetFrameLevel(frameLevel)
    end
    if r and g and b then
        bar:SetStatusBarColor(r, g, b, a or 1)
    end
    if reverseFill ~= nil and bar.SetReverseFill then
        bar:SetReverseFill(reverseFill and true or false)
    end
    bar:Hide()
    return bar
end
local function MSUF_GetAbsorbOverlayColor()
    local r, g, b, a = 0.8, 0.9, 1.0, 0.6
    local gen = MSUF_DB and MSUF_DB.general
    if gen then
        local ar, ag, ab = gen.absorbBarColorR, gen.absorbBarColorG, gen.absorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            if ar < 0 then ar = 0 elseif ar > 1 then ar = 1 end
            if ag < 0 then ag = 0 elseif ag > 1 then ag = 1 end
            if ab < 0 then ab = 0 elseif ab > 1 then ab = 1 end
            r, g, b = ar, ag, ab
    end
    end
    return r, g, b, a
end
local function MSUF_GetHealAbsorbOverlayColor()
    local r, g, b, a = 1.0, 0.4, 0.4, 0.7
    local gen = MSUF_DB and MSUF_DB.general
    if gen then
        local ar, ag, ab = gen.healAbsorbBarColorR, gen.healAbsorbBarColorG, gen.healAbsorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            if ar < 0 then ar = 0 elseif ar > 1 then ar = 1 end
            if ag < 0 then ag = 0 elseif ag > 1 then ag = 1 end
            if ab < 0 then ab = 0 elseif ab > 1 then ab = 1 end
            r, g, b = ar, ag, ab
    end
    end
    return r, g, b, a
end
local function MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then return end
    if bar.MSUF_overlayR == r and bar.MSUF_overlayG == g and bar.MSUF_overlayB == b and bar.MSUF_overlayA == a then
        return
    end
    MSUF_SetStatusBarColor(bar, r, g, b, a)
    bar.MSUF_overlayR, bar.MSUF_overlayG, bar.MSUF_overlayB, bar.MSUF_overlayA = r, g, b, a
end
local function MSUF_ApplyAbsorbOverlayColor(bar)
    local r, g, b, a = MSUF_GetAbsorbOverlayColor()
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
end
local function MSUF_ApplyHealAbsorbOverlayColor(bar)
    local r, g, b, a = MSUF_GetHealAbsorbOverlayColor()
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
end
local function MSUF_NormalizeUnitKeyForDB(key)
    if not key or type(key) ~= "string" then return nil end
    if key == "tot" then
        return "targettarget"
    end
    if key:match("^boss%d+$") then
        return "boss"
    end
    return key
end
local function MSUF_ResolveFrameDBKey(f)
    local key = f and (f.unitKey or f.unit or f.msufConfigKey)
    return MSUF_NormalizeUnitKeyForDB(key or "player") or "player"
end
local function MSUF_ApplyLevelIndicatorLayout_Internal(f, conf)
    if not f or not f.levelText or not f.nameText then return end
    conf = conf or {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local lx = (type(conf.levelIndicatorOffsetX) == "number") and conf.levelIndicatorOffsetX
        or ((type(g.levelIndicatorOffsetX) == "number") and g.levelIndicatorOffsetX or 0)
    local ly = (type(conf.levelIndicatorOffsetY) == "number") and conf.levelIndicatorOffsetY
        or ((type(g.levelIndicatorOffsetY) == "number") and g.levelIndicatorOffsetY or 0)
    local anchor = (type(conf.levelIndicatorAnchor) == "string") and conf.levelIndicatorAnchor
        or ((type(g.levelIndicatorAnchor) == "string") and g.levelIndicatorAnchor or "NAMERIGHT")
    f._msufLevelAnchor = anchor
    if not ns.Cache.StampChanged(f, "LevelLayout", anchor, lx, ly) then return end
    f._msufLevelLayoutStamp = 1
    f.levelText:ClearAllPoints()
    if anchor == "NAMELEFT" then
        f.levelText:SetPoint("RIGHT", f.nameText, "LEFT", -6 + lx, ly)
    elseif anchor == "NAMERIGHT" then
        f.levelText:SetPoint("LEFT", f.nameText, "RIGHT", 6 + lx, ly)
    else
        local af = f.textFrame or f
        f.levelText:SetPoint(anchor, af, anchor, lx, ly)
    end
end
if not _G.MSUF_ApplyLevelIndicatorLayout then
    function _G.MSUF_ApplyLevelIndicatorLayout(f)
        if not f or not f.levelText or not f.nameText then return end
        local key = MSUF_ResolveFrameDBKey(f)
        local conf = (MSUF_DB and MSUF_DB[key]) or {}
        if key == "targettarget" and MSUF_DB and MSUF_DB.tot and
           (conf.levelIndicatorAnchor == nil and conf.levelIndicatorOffsetX == nil and conf.levelIndicatorOffsetY == nil) then
            conf = MSUF_DB.tot
    end
        MSUF_ApplyLevelIndicatorLayout_Internal(f, conf)
    end
end
local MSUF_ECV_ANCHORS = {
    player       = { "RIGHT", "LEFT",  -20,   0 },
    target       = { "LEFT",  "RIGHT",  20,   0 },
    focus        = { "TOP",   "LEFT",    0,   0 },
    targettarget = { "TOP",   "RIGHT",   0, -40 },
}
local MSUF_MAX_BOSS_FRAMES = 5          -- how many boss frames MSUF creates/handles
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local MSUF_BORDER_BACKDROPS = {
    THIN  = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 },
    THICK = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16 },
    SHADOW = { edgeFile = "Interface\\GLUES\\COMMON\\TextPanel-Border", edgeSize = 14 },
    GLOW  = { edgeFile = MSUF_TEX_WHITE8, edgeSize = 8 },
}
local MSUF_BORDER_DEFAULT = MSUF_BORDER_BACKDROPS.THIN
local floor  = math.floor
local max    = math.max
local min    = math.min
local format = string.format
local MSUF_Transactions = {}  -- scopeKey -> { snapshot=table, restore=function|nil, active=true }
function MSUF_BeginTransaction(scopeKey, snapshot, restoreFunc)
    if not scopeKey then
        return
    end
    MSUF_Transactions[scopeKey] = {
        snapshot = MSUF_DeepCopy(snapshot) or {},
        restore = restoreFunc,
        active = true,
    }
end
function MSUF_HasTransaction(scopeKey)
    local t = scopeKey and MSUF_Transactions[scopeKey]
    return not not (t and t.active and t.snapshot)
end
function MSUF_GetTransactionSnapshot(scopeKey)
    local t = scopeKey and MSUF_Transactions[scopeKey]
    return t and t.snapshot
end
function MSUF_CommitTransaction(scopeKey)
    if not scopeKey then
        return
    end
    MSUF_Transactions[scopeKey] = nil
end
function MSUF_RollbackTransaction(scopeKey)
    if not scopeKey then
        return
    end
    local t = MSUF_Transactions[scopeKey]
    if not (t and t.active) then
        return
    end
    if type(t.restore) == "function" then
        local ok, err = MSUF_FastCall(t.restore, MSUF_DeepCopy(t.snapshot))
        if not ok then
            if type(print) == "function" then
                print("MSUF: rollback failed for scope", scopeKey, err)
            end
    end
    end
    return t.snapshot
end
ns.MSUF_DeepCopy = MSUF_DeepCopy
ns.MSUF_CaptureKeys = MSUF_CaptureKeys
ns.MSUF_RestoreKeys = MSUF_RestoreKeys
ns.MSUF_Transactions = MSUF_Transactions
local MSUF_SMOOTH_INTERPOLATION = (type(Enum) == "table"
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil
-- Performance/Secret-safe (no MSUF_FastCall): NEVER compare (numbers can be "secret"). Always apply the value.
-- This avoids secret-compare crashes entirely and removes tostring/tonumber churn from hotpaths.
function MSUF_SetBarValue(bar, value, smooth)
    if not bar or value == nil then return end
    if type(value) == "string" then
        local n = tonumber(value)
        if type(n) ~= "number" then
            return
    end
        value = n
    end
    if smooth and MSUF_SMOOTH_INTERPOLATION then
        bar:SetValue(value, MSUF_SMOOTH_INTERPOLATION)
    else
        bar:SetValue(value)
    end
end
function MSUF_SetBarMinMax(bar, minValue, maxValue)
    if not bar or minValue == nil or maxValue == nil then
        return
    end
    if type(minValue) == "string" then
        minValue = tonumber(minValue)
    end
    if type(maxValue) == "string" then
        maxValue = tonumber(maxValue)
    end
    if type(minValue) ~= "number" or type(maxValue) ~= "number" then
        return
    end
    -- No caching/compare here either (secret-safe, no MSUF_FastCall).
    bar:SetMinMaxValues(minValue, maxValue)
end
MSUF_UnitEditModeActive = (MSUF_UnitEditModeActive == true)
MSUF_CurrentOptionsKey = MSUF_CurrentOptionsKey
MSUF_CurrentEditUnitKey = MSUF_CurrentEditUnitKey
MSUF_EditModeSizing = (MSUF_EditModeSizing == true)
if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
    MSUF_SyncBossUnitframePreviewWithUnitEdit()
end
local LSM = (ns and ns.LSM) or _G.MSUF_LSM or (LibStub and LibStub("LibSharedMedia-3.0", true))
_G.MSUF_OnLSMReady = function(lsm)
    LSM = lsm
end
if LSM and not _G.MSUF_LSM_CallbacksRegistered and not MSUF_LSM_FontCallbackRegistered then
    MSUF_LSM_FontCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype ~= "font" then return end
        if MSUF_RebuildFontChoices then
            MSUF_RebuildFontChoices()
    end
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.fontKey == key then
            C_Timer.After(0, function() if UpdateAllFonts then UpdateAllFonts() end end)
    end
    end)
end
local FONT_LIST = {
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT__.TTF",
    },
{
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARIALN.TTF",
    },
    {
        key  = "MORPHEUS",
        name = "Morpheus (default)",
        path = "Fonts\\MORPHEUS.TTF",
    },
    {
        key  = "SKURRI",
        name = "Skurri (default)",
        path = "Fonts\\SKURRI.TTF",
    },
}
do
    local base = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Fonts\\"
    local bundled = {
        { key = "EXPRESSWAY",                 name = "Expressway Regular (MSUF)",          file = "Expressway Regular.ttf" },
        { key = "EXPRESSWAY_BOLD",            name = "Expressway Bold (MSUF)",             file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD",        name = "Expressway SemiBold (MSUF)",         file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD",       name = "Expressway ExtraBold (MSUF)",        file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)",  file = "Expressway Condensed Light.otf" },
    }
    local function HasFontKey(list, key)
        if type(key) ~= "string" or key == "" then return false end
        if type(list) ~= "table" then return false end
        for i = 1, #list do
            local t = list[i]
            if t and t.key == key then
                return true
            end
    end
        return false
    end
    for _, info in ipairs(bundled) do
        if not HasFontKey(FONT_LIST, info.key) then
            table.insert(FONT_LIST, {
                key  = info.key,
                name = info.name,
                path = base .. info.file,
            })
    end
    end
end
_G.MSUF_FONT_LIST = _G.MSUF_FONT_LIST or FONT_LIST
local MSUF_FONT_COLORS = {
    white     = {1.0, 1.0, 1.0},
    black     = {0.0, 0.0, 0.0},
    red       = {1.0, 0.0, 0.0},
    green     = {0.0, 1.0, 0.0},
    blue      = {0.0, 0.0, 1.0},
    yellow    = {1.0, 1.0, 0.0},
    cyan      = {0.0, 1.0, 1.0},
    magenta   = {1.0, 0.0, 1.0},
    orange    = {1.0, 0.5, 0.0},
    purple    = {0.6, 0.0, 0.8},
    pink      = {1.0, 0.6, 0.8},
    turquoise = {0.0, 0.9, 0.8},
    grey      = {0.5, 0.5, 0.5},
    brown     = {0.6, 0.3, 0.1},
    gold      = {1.0, 0.85, 0.1},
}
ns.MSUF_FONT_COLORS = MSUF_FONT_COLORS
_G.MSUF_FONT_COLORS = _G.MSUF_FONT_COLORS or MSUF_FONT_COLORS
local function MSUF_GetNPCReactionColor(kind)
    local defaultR, defaultG, defaultB
    if kind == "friendly" then
        defaultR, defaultG, defaultB = 0, 1, 0           -- grün
    elseif kind == "neutral" then
        defaultR, defaultG, defaultB = 1, 1, 0           -- gelb
    elseif kind == "enemy" then
        defaultR, defaultG, defaultB = 0.85, 0.10, 0.10  -- rot
    elseif kind == "dead" then
        defaultR, defaultG, defaultB = 0.4, 0.4, 0.4     -- grau (tote NPCs)
    else
        defaultR, defaultG, defaultB = 1, 1, 1
    end
    if not MSUF_DB or not EnsureDB then
        return defaultR, defaultG, defaultB
    end
    EnsureDB()
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}
    local t = MSUF_DB.npcColors[kind]
    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end
    return defaultR, defaultG, defaultB
end
local function MSUF_GetClassBarColor(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
        return defaultR, defaultG, defaultB
    end
    EnsureDB()
    MSUF_DB.classColors = MSUF_DB.classColors or {}
    local override = MSUF_DB.classColors[classToken]
    if type(override) == "table" and override.r and override.g and override.b then
        return override.r, override.g, override.b
    end
    if type(override) == "string" and MSUF_FONT_COLORS and MSUF_FONT_COLORS[override] then
        local c = MSUF_FONT_COLORS[override]
        return c[1], c[2], c[3]
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then
        return color.r, color.g, color.b
    end
    return defaultR, defaultG, defaultB
end
local function MSUF_GetPowerBarColor(powerType, powerToken)
    if not powerToken or powerToken == "" then
        return nil
    end
    if not MSUF_DB or not EnsureDB then
        return nil
    end
    EnsureDB()
    local g = MSUF_DB.general
    local ov = g and g.powerColorOverrides
    if type(ov) ~= "table" then
        return nil
    end
    local c = ov[powerToken]
    if type(c) ~= "table" then
        return nil
    end
    local r, gg, b
    if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        r, gg, b = c.r, c.g, c.b
    else
        r, gg, b = c[1], c[2], c[3]
    end
    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        return r, gg, b
    end
    return nil
end
_G.MSUF_GetPowerBarColor = MSUF_GetPowerBarColor
local function MSUF_GetResolvedPowerColor(powerType, powerToken)
    if type(MSUF_GetPowerBarColor) == "function" then
        local r, g, b = MSUF_GetPowerBarColor(powerType, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
    end
    end
    local pbc = _G.PowerBarColor
    if type(powerToken) == "string" and pbc and pbc[powerToken] then
        local c = pbc[powerToken]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
    end
    end
    if type(powerType) == "number" and pbc and pbc[powerType] then
        local c = pbc[powerType]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
    end
    end
    return nil
end
_G.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor
ns.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor
local function MSUF_GetConfiguredFontColor()
    EnsureDB()
    local g = MSUF_DB.general or {}
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    local key   = (g.fontColor or "white"):lower()
    local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
    return color[1], color[2], color[3]
end
ns.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor
local MSUF_FontPreviewObjects = {}
local function MSUF_GetFontPreviewObject(key)
    if not key or key == "" then
        return GameFontHighlightSmall
    end
    local obj = MSUF_FontPreviewObjects[key]
    if not obj then
        obj = CreateFont("MSUF_FontPreview_" .. tostring(key))
        MSUF_FontPreviewObjects[key] = obj
    end
    local path
    if LSM then
        -- IMPORTANT: use noDefault=true so internal (non-LSM) keys like "FRIZQT"/"ARIALN"/"MORPHEUS"
        local p = LSM:Fetch("font", key, true)
        if p then
            path = p
    end
    end
    if not path then
        path = GetInternalFontPathByKey(key) or FONT_LIST[1].path
    end
    obj:SetFont(path, 14, "")
    return obj
end
ns.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
_G.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
local function MSUF_GetColorFromKey(key, fallbackColor)
    if type(key) ~= "string" then
        if fallbackColor then
            return fallbackColor
    end
        return CreateColor(1, 1, 1, 1)
    end
    local normalized = string.lower(key)
    local rgb = MSUF_FONT_COLORS[normalized]
    if rgb then
        local r, g, b = rgb[1], rgb[2], rgb[3]
        return CreateColor(r or 1, g or 1, b or 1, 1)
    end
    if fallbackColor then
        return fallbackColor
    end
    return CreateColor(1, 1, 1, 1)
end
ns.MSUF_GetColorFromKey = MSUF_GetColorFromKey
_G.MSUF_GetColorFromKey = MSUF_GetColorFromKey
MSUF_DARK_TONES = {
    black    = {0.0, 0.0, 0.0},
    darkgray = {0.08, 0.08, 0.08},
    softgray = {0.16, 0.16, 0.16},
}
function GetInternalFontPathByKey(key)
    if not key then return nil end
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.name == key then
            return info.path
    end
    end
    return nil
end
MSUF_BossTestMode = MSUF_BossTestMode or false
local MSUF_CooldownWarningFrame
_G.MSUF_CastbarUnitInfo = _G.MSUF_CastbarUnitInfo or {
    player = { label = "Player Castbar", prefix = "castbarPlayer", defaultX = 0,  defaultY = 5,   showTimeKey = "showPlayerCastTime", isBoss = false },
    target = { label = "Target Castbar", prefix = "castbarTarget", defaultX = 65, defaultY = -15, showTimeKey = "showTargetCastTime", isBoss = false },
    focus  = { label = "Focus Castbar",  prefix = "castbarFocus",  defaultX = 65, defaultY = -15, showTimeKey = "showFocusCastTime",  isBoss = false },
    boss   = { label = "Boss Castbar",   prefix = nil,             defaultX = 0,  defaultY = 0,   showTimeKey = "showBossCastTime",   isBoss = true  },
}
function MSUF_GetCastbarUnitInfo(unitKey)
    local m = _G.MSUF_CastbarUnitInfo
    return m and m[unitKey] or nil
end
function MSUF_IsBossCastbarUnit(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return (i and i.isBoss) and true or false
end
function MSUF_GetCastbarPrefix(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return i and i.prefix or nil
end
function MSUF_GetCastbarLabel(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return (i and i.label) or tostring(unitKey or "")
end
function MSUF_GetCastbarDefaultOffsets(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    if not i then return 0, 0 end
    return i.defaultX or 0, i.defaultY or 0
end
function MSUF_GetCastbarShowTimeKey(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return i and i.showTimeKey or nil
end
function MSUF_GetCastbarShowNameKey(unitKey)
    if MSUF_IsBossCastbarUnit(unitKey) then
        return "showBossCastName"
    end
    local p = MSUF_GetCastbarPrefix(unitKey)
    return p and (p .. "ShowSpellName") or nil
end
function MSUF_GetCastbarShowIconKey(unitKey)
    if MSUF_IsBossCastbarUnit(unitKey) then
        return "showBossCastIcon"
    end
    local p = MSUF_GetCastbarPrefix(unitKey)
    return p and (p .. "ShowIcon") or nil
end
function MSUF_GetCastbarUnitFromFrame(frame)
    if not frame then return nil end
    if _G.MSUF_BossCastbarPreview and frame == _G.MSUF_BossCastbarPreview then
        return "boss"
    end
    if (MSUF_PlayerCastbar and frame == MSUF_PlayerCastbar) or (MSUF_PlayerCastbarPreview and frame == MSUF_PlayerCastbarPreview) then
        return "player"
    end
    if (MSUF_TargetCastbar and frame == MSUF_TargetCastbar) or (MSUF_TargetCastbarPreview and frame == MSUF_TargetCastbarPreview) then
        return "target"
    end
    if (MSUF_FocusCastbar and frame == MSUF_FocusCastbar) or (MSUF_FocusCastbarPreview and frame == MSUF_FocusCastbarPreview) then
        return "focus"
    end
    return nil
end
function MSUF_ApplyUnitframeKeyAndSync(key, changedFonts)
    if not key then return end
    EnsureDB()
    if ApplySettingsForKey then
        ApplySettingsForKey(key)
    elseif ApplyAllSettings then
        ApplyAllSettings()
    end
    if changedFonts then
        if _G.MSUF_UpdateAllFonts then
            _G.MSUF_UpdateAllFonts()
        elseif ns and ns.MSUF_UpdateAllFonts then
            ns.MSUF_UpdateAllFonts()
    end
    end
if (key == "target" or key == "targettarget") and ns and ns.MSUF_ToTInline_RequestRefresh then
    ns.MSUF_ToTInline_RequestRefresh("UF_APPLY")
end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
function MSUF_ApplyCastbarUnitAndSync(unitKey)
    if not unitKey then return end
    EnsureDB()
    if MSUF_IsBossCastbarUnit(unitKey) then
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            _G.MSUF_ApplyBossCastbarPositionSetting()
    end
        if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then
            _G.MSUF_ApplyBossCastbarTimeSetting()
    end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
    end
        if type(MSUF_SyncCastbarPositionPopup) == "function" then
            MSUF_SyncCastbarPositionPopup("boss")
    end
        return
    end
    if unitKey == "player" and type(MSUF_ReanchorPlayerCastBar) == "function" then
        MSUF_ReanchorPlayerCastBar()
    elseif unitKey == "target" and type(MSUF_ReanchorTargetCastBar) == "function" then
        MSUF_ReanchorTargetCastBar()
    elseif unitKey == "focus" and type(MSUF_ReanchorFocusCastBar) == "function" then
        MSUF_ReanchorFocusCastBar()
    end
    MSUF_UpdateCastbarVisuals()
    if type(MSUF_UpdateCastbarEditInfo) == "function" then
        MSUF_UpdateCastbarEditInfo(unitKey)
    end
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup(unitKey)
    end
end
local function MSUF_GetFontPath()
    if type(EnsureDB) == "function" then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local key = MSUF_DB.general.fontKey
    if LSM and key and key ~= "" then
        local p = LSM:Fetch("font", key, true)
        if p then
            return p
    end
    end
    local internalPath = GetInternalFontPathByKey(key)
    if internalPath then
        return internalPath
    end
    return FONT_LIST[1].path
end
local function MSUF_GetFontFlags()
    if type(EnsureDB) == "function" then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if g.noOutline then
        return ""              -- kein OUTLINE / THICKOUTLINE
    elseif g.boldText then
        return "THICKOUTLINE"  -- fetter schwarzer Rand
    else
        return "OUTLINE"       -- normaler dünner Rand
    end
end
function ns.MSUF_GetGlobalFontSettings()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    local baseSize  = g.fontSize or 14
    local useShadow = g.textBackdrop and true or false
    return path, flags, fr, fg, fb, baseSize, useShadow
end
function MSUF_GetGlobalFontSettings()
    if ns and ns.MSUF_GetGlobalFontSettings then
        return ns.MSUF_GetGlobalFontSettings()
    end
    return "Fonts\\FRIZQT__.TTF", "OUTLINE", 1, 1, 1, 14, false
end
function MSUF_GetCastbarTexture()
    if not MSUF_DB then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local castKey = g and g.castbarTexture or nil
    local barKey  = g and g.barTexture or nil

    local cache = ROOT_G.MSUF_CastbarTextureCache
    if not cache then
        cache = {}
        ROOT_G.MSUF_CastbarTextureCache = cache
    end

    local ck = tostring(castKey or "") .. "|" .. tostring(barKey or "")
    local cached = cache[ck]
    if cached ~= nil then
        return cached
    end

    local function TryResolve(key)
        if type(key) ~= "string" or key == "" then
            return nil
        end

        local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
        if type(builtins) == "table" then
            local t = builtins[key]
            if type(t) == "string" and t ~= "" then
                return t
            end
        end

        if key:find("\\") or key:find("/") then
            return key
        end

        if LSM and LSM.Fetch then
            local tex = LSM:Fetch("statusbar", key)
            if tex and tex ~= "" then
                return tex
            end
        end

        return nil
    end

    local tex = TryResolve(castKey) or TryResolve(barKey) or "Interface\\TARGETINGFRAME\\UI-StatusBar"
    cache[ck] = tex
    return tex
end
ROOT_G.MSUF_GetCastbarTexture = MSUF_GetCastbarTexture
_G.MSUF_GetCastbarTexture = MSUF_GetCastbarTexture

function MSUF_GetCastbarBackgroundTexture()
    if not MSUF_DB then
        EnsureDB()
    end
    local g = MSUF_DB and MSUF_DB.general
    local bgKey = g and g.castbarBackgroundTexture or nil
    local castKey = g and g.castbarTexture or nil
    local barKey = g and g.barTexture or nil

    local key = bgKey
    if key == nil or key == "" then
        key = castKey
    end
    if key == nil or key == "" then
        key = barKey
    end

    local cache = ROOT_G.MSUF_CastbarBackgroundTextureCache
    if not cache then
        cache = {}
        ROOT_G.MSUF_CastbarBackgroundTextureCache = cache
    end

    local ck = tostring(key or "")
    local cached = cache[ck]
    if cached then
        return cached
    end

    local tex
    if type(MSUF_ResolveStatusbarTextureKey) == "function" then
        tex = MSUF_ResolveStatusbarTextureKey(key)
    end
    if not tex or tex == "" then
        tex = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end

    cache[ck] = tex
    return tex
end
ROOT_G.MSUF_GetCastbarBackgroundTexture = MSUF_GetCastbarBackgroundTexture
_G.MSUF_GetCastbarBackgroundTexture = MSUF_GetCastbarBackgroundTexture

local function MSUF_IsCastTimeEnabled(frame)
    local g = MSUF_DB and MSUF_DB.general
    if not (frame and frame.unit and g) then return true end
    local u = frame.unit
    local key = (u == "player" and "showPlayerCastTime") or (u == "target" and "showTargetCastTime") or (u == "focus" and "showFocusCastTime")
    return (not key) and true or ns.Util.Enabled(nil, g, key, true)
end
function MSUF_GetCastbarReverseFill(isChanneled)
    if not MSUF_DB then
        EnsureDB()
    end
    local g = MSUF_DB and MSUF_DB.general
    local dir = g and g.castbarFillDirection or "RTL"
    local uni = g and g.castbarUnifiedDirection or false
    if dir == "LEFT" then
        dir = "RTL"
    elseif dir == "RIGHT" then
        dir = "LTR"
    end
    if dir ~= "RTL" and dir ~= "LTR" then
        dir = "RTL"
    end
    local cache = _G.MSUF_CastbarReverseFillCache
    if not cache then
        cache = {}
        _G.MSUF_CastbarReverseFillCache = cache
    end
    local ck = tostring(dir) .. "|" .. tostring(uni) .. "|" .. tostring(isChanneled and 1 or 0)
    local cached = cache[ck]
    if cached ~= nil then
        return cached
    end
    local reverseNormal = (dir == "RTL")
    local reverse
    if uni then
        reverse = reverseNormal
    else
        if isChanneled then
            reverse = not reverseNormal
        else
            reverse = reverseNormal
    end
    end
    cache[ck] = reverse and true or false
    return cache[ck]
end
if not _G.MSUF_CastbarStyleRevision then
    _G.MSUF_CastbarStyleRevision = 1
end
function MSUF_BumpCastbarStyleRevision()
    local r = _G.MSUF_CastbarStyleRevision or 1
    _G.MSUF_CastbarStyleRevision = r + 1
    return _G.MSUF_CastbarStyleRevision
end
function MSUF_GetGlobalCastbarStyleCache()
    local rev = _G.MSUF_CastbarStyleRevision or 1
    local cache = _G.MSUF_GlobalCastbarStyleCache
    if cache and cache.rev == rev then
        return cache
    end
    cache = cache or {}
    cache.rev = rev
    if not MSUF_DB then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    cache.unifiedDirection = (g.castbarUnifiedDirection == true)
    local tex
    if type(MSUF_GetCastbarTexture) == "function" then
        tex = MSUF_GetCastbarTexture()
    end
    if not tex or tex == "" then
        tex = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    cache.texture = tex
    local bgTex
    if type(MSUF_GetCastbarBackgroundTexture) == "function" then
        bgTex = MSUF_GetCastbarBackgroundTexture()
    end
    if not bgTex or bgTex == "" then
        bgTex = tex
    end
    cache.bgTexture = bgTex
    if type(MSUF_GetCastbarReverseFill) == "function" then
        cache.reverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
        cache.reverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
    else
        cache.reverseFillNormal    = false
        cache.reverseFillChanneled = false
    end
    _G.MSUF_GlobalCastbarStyleCache = cache
    return cache
end
function MSUF_RefreshCastbarStyleCache(frame)
    if not frame then return end
    local rev = _G.MSUF_CastbarStyleRevision or 1
    if frame.MSUF_castbarStyleRev == rev then
        return
    end
    local c = MSUF_GetGlobalCastbarStyleCache and MSUF_GetGlobalCastbarStyleCache() or nil
    frame.MSUF_castbarStyleRev = rev
    if c then
        frame.MSUF_cachedUnifiedDirection     = (c.unifiedDirection == true)
        frame.MSUF_cachedCastbarTexture       = c.texture
        frame.MSUF_cachedCastbarBackgroundTexture = c.bgTexture or c.texture
        frame.MSUF_cachedReverseFillNormal    = (c.reverseFillNormal == true)
        frame.MSUF_cachedReverseFillChanneled = (c.reverseFillChanneled == true)
    end
end
local function MSUF_GetCastbarReverseFillForFrame(frame, isChanneled)
    MSUF_RefreshCastbarStyleCache(frame)
    local base
    if frame then
        if isChanneled then
            base = (frame.MSUF_cachedReverseFillChanneled == true)
        else
            base = (frame.MSUF_cachedReverseFillNormal == true)
        end
    else
        base = (type(MSUF_GetCastbarReverseFill) == "function" and MSUF_GetCastbarReverseFill(isChanneled)) or false
    end
    return base and true or false
end
_G.MSUF_GetCastbarReverseFillForFrame = MSUF_GetCastbarReverseFillForFrame
local function MSUF_ForMainCastbars(fn)
    fn(MSUF_PlayerCastbar)
    fn(MSUF_TargetCastbar)
    fn(MSUF_FocusCastbar)
    fn(MSUF_PlayerCastbarPreview)
    fn(MSUF_TargetCastbarPreview)
    fn(MSUF_FocusCastbarPreview)
end
function MSUF_UpdateCastbarTextures()
MSUF_BumpCastbarStyleRevision()
    local __msufStyleRev = _G.MSUF_CastbarStyleRevision or 1
    local tex = MSUF_GetCastbarTexture()
    if not tex then return end
    local bgTex = tex
    if type(MSUF_GetCastbarBackgroundTexture) == "function" then
        local t2 = MSUF_GetCastbarBackgroundTexture()
        if t2 and t2 ~= "" then
            bgTex = t2
        end
    end
    local function Apply(frame)
        if frame and frame.statusBar then
            frame.statusBar:SetStatusBarTexture(tex)
            local sbt = frame.statusBar:GetStatusBarTexture()
            if sbt then sbt:SetHorizTile(true) end
            frame.MSUF_castbarStyleRev = __msufStyleRev
            frame.MSUF_cachedCastbarTexture = tex
            if type(MSUF_GetCastbarReverseFill) == "function" then
                frame.MSUF_cachedReverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
                frame.MSUF_cachedReverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
            end
            EnsureDB(); frame.MSUF_cachedUnifiedDirection = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarUnifiedDirection) == true
    end
        if frame and frame.backgroundBar then
            frame.backgroundBar:SetTexture(bgTex)
            frame.MSUF_cachedCastbarBackgroundTexture = bgTex
    end
    end
    MSUF_ForMainCastbars(Apply)

    -- Boss castbars (LoD module)
    local bossBars = _G.MSUF_BossCastbars
    if bossBars and type(bossBars) == "table" then
        for i = 1, #bossBars do
            local f = bossBars[i]
            if f and f.statusBar then
                f.statusBar:SetStatusBarTexture(tex)
                local sbt = f.statusBar:GetStatusBarTexture()
                if sbt then sbt:SetHorizTile(true) end
                f.MSUF_cachedCastbarTexture = tex
            end
            if f and f.backgroundBar then
                f.backgroundBar:SetTexture(bgTex)
                f.MSUF_cachedCastbarBackgroundTexture = bgTex
            end
        end
    end
end
function MSUF_UpdateCastbarFillDirection()
        MSUF_BumpCastbarStyleRevision()
    local function Apply(frame)
        if frame and frame.statusBar and frame.statusBar.SetReverseFill then
            local isChanneled = false
            if frame.isEmpower then
                isChanneled = true
            elseif frame.MSUF_isChanneled then
                isChanneled = true
            elseif frame.unit and (frame.unit == "player" or frame.unit == "target" or frame.unit == "focus") then
                if UnitChannelInfo and UnitChannelInfo(frame.unit) then
                    isChanneled = true
                end
            end
                MSUF_RefreshCastbarStyleCache(frame)
            local rf = MSUF_GetCastbarReverseFillForFrame(frame, isChanneled)
            MSUF_FastCall(frame.statusBar.SetReverseFill, frame.statusBar, rf and true or false)
    end
    end
    MSUF_ForMainCastbars(Apply)
end
function MSUF_ResolveStatusbarTextureKey(key)
    local defaultTex = "Interface\\TargetingFrame\\UI-StatusBar"
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" and type(key) == "string" then
        local t = builtins[key]
        if type(t) == "string" and t ~= "" then
            return t
    end
    end
    if type(key) == "string" then
        if key:find("\\") or key:find("/") then
            return key
    end
    end
    if LSM and type(LSM.Fetch) == "function" and type(key) == "string" and key ~= "" then
        local tex = LSM:Fetch("statusbar", key, true)
        if tex then
            return tex
    end
    end
    return defaultTex
end
_G.MSUF_ResolveStatusbarTextureKey = MSUF_ResolveStatusbarTextureKey
_G.MSUF_BUILTIN_BAR_TEXTURES = _G.MSUF_BUILTIN_BAR_TEXTURES or {
    Blizzard   = "Interface\\TargetingFrame\\UI-StatusBar",
    Flat       = "Interface\\Buttons\\WHITE8x8",
    RaidHP     = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    RaidPower  = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill",
    Skills     = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Outline        = "Interface\\Tooltips\\UI-Tooltip-Background",
    TooltipBorder  = "Interface\\Tooltips\\UI-Tooltip-Border",
    DialogBG       = "Interface\\DialogFrame\\UI-DialogBox-Background",
    Parchment      = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground",
}
function MSUF_GetBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barTexture
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetBarBackgroundTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barBackgroundTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetAbsorbBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.absorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetHealAbsorbBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.healAbsorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end
local function MSUF_Clamp01(v)
    v = tonumber(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end
function MSUF_GetBarBackgroundTintRGBA()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local r = MSUF_Clamp01(g.classBarBgR)
    local gg = MSUF_Clamp01(g.classBarBgG)
    local b = MSUF_Clamp01(g.classBarBgB)
    local a = 0.9
    if g.darkMode then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        r, gg, b = r * br, gg * br, b * br
    end
    return r, gg, b, a
end
function MSUF_GetPowerBarBackgroundTintRGBA()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local ar, ag, ab = g.powerBarBgColorR, g.powerBarBgColorG, g.powerBarBgColorB
    if type(ar) ~= "number" or type(ag) ~= "number" or type(ab) ~= "number" then
        return MSUF_GetBarBackgroundTintRGBA()
    end
    local r = MSUF_Clamp01(ar)
    local gg = MSUF_Clamp01(ag)
    local b = MSUF_Clamp01(ab)
    local a = 0.9
    if g.darkMode then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        r, gg, b = r * br, gg * br, b * br
    end
    return r, gg, b, a
end
function MSUF_ApplyBarBackgroundVisual(frame)
    if not frame then return end
    local tex = MSUF_GetBarBackgroundTexture()
    local r, gg, b, a = MSUF_GetBarBackgroundTintRGBA()
    local gen = MSUF_DB and MSUF_DB.general
    if gen and gen.barBgMatchHPColor and frame.hpBar and frame.hpBar.GetStatusBarColor then
        local fr, fg, fb = frame.hpBar:GetStatusBarColor()
        if type(fr) == "number" and type(fg) == "number" and type(fb) == "number" then
            if gen.darkMode then
                local br = gen.darkBgBrightness
                if type(br) == "number" then
                    if br < 0 then br = 0 elseif br > 1 then br = 1 end
                    fr, fg, fb = fr * br, fg * br, fb * br
                end
            end
            r, gg, b = MSUF_Clamp01(fr), MSUF_Clamp01(fg), MSUF_Clamp01(fb)
    end
    end
    local alphaPct = 90
    if MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.barBackgroundAlpha) == 'number' then
        alphaPct = MSUF_DB.bars.barBackgroundAlpha
    end
    if alphaPct < 0 then alphaPct = 0 elseif alphaPct > 100 then alphaPct = 100 end
    local alphaMul = alphaPct / 100
    if type(a) == 'number' then a = a * alphaMul end
    local function ApplyToTexture(t, cachePrefix, cr, cg, cb, ca)
        if not t then return end
        local kTex = "_msuf" .. cachePrefix .. "BgTex"
        local kR   = "_msuf" .. cachePrefix .. "BgR"
        local kG   = "_msuf" .. cachePrefix .. "BgG"
        local kB   = "_msuf" .. cachePrefix .. "BgB"
        local kA   = "_msuf" .. cachePrefix .. "BgA"
        if frame[kTex] ~= tex then
            t:SetTexture(tex)
            frame[kTex] = tex
    end
        if frame[kR] ~= cr or frame[kG] ~= cg or frame[kB] ~= cb or frame[kA] ~= ca then
            t:SetVertexColor(cr, cg, cb, ca)
            frame[kR], frame[kG], frame[kB], frame[kA] = cr, cg, cb, ca
    end
    end
    ApplyToTexture(frame.hpBarBG, "HP", r, gg, b, a)
    local pr, pg, pb, pa = MSUF_GetPowerBarBackgroundTintRGBA()
    if type(pa) == 'number' then pa = pa * alphaMul end
    local bars = MSUF_DB and MSUF_DB.bars
    local matchHP = (gen and gen.powerBarBgMatchHPColor) or (bars and bars.powerBarBgMatchBarColor)
    if matchHP and frame.hpBar and frame.hpBar.GetStatusBarColor then
        local fr, fg, fb = frame.hpBar:GetStatusBarColor()
        if type(fr) == "number" and type(fg) == "number" and type(fb) == "number" then
            if gen and gen.darkMode then
                local br = gen.darkBgBrightness
                if type(br) == "number" then
                    if br < 0 then br = 0 elseif br > 1 then br = 1 end
                    fr, fg, fb = fr * br, fg * br, fb * br
                end
            end
            pr, pg, pb = MSUF_Clamp01(fr), MSUF_Clamp01(fg), MSUF_Clamp01(fb)
    end
    end
    ApplyToTexture(frame.powerBarBG, "Power", pr, pg, pb, pa)
    if (not frame.hpBarBG) and (not frame.powerBarBG) and frame.bg then
        ApplyToTexture(frame.bg, "Frame", r, gg, b, a)
    end
end
local function GetConfigKeyForUnit(unit)
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "pet"
    then
        return unit
    elseif unit and unit:match("^boss%d+$") then
        return "boss"
    end
    return nil
end
function _G.MSUF_GetHpSpacerSelectedUnitKey()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(g.hpSpacerSelectedUnitKey, "player")
    g.hpSpacerSelectedUnitKey = k
    return k
end
function _G.MSUF_SetHpSpacerSelectedUnitKey(unitKey, suppressUIRefresh)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, "player")
    g.hpSpacerSelectedUnitKey = k
    if not suppressUIRefresh and type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then
        _G.MSUF_Options_RefreshHPSpacerControls()
    end
    if not suppressUIRefresh and type(_G.MSUF_Options_RefreshPowerSpacerControls) == "function" then
        _G.MSUF_Options_RefreshPowerSpacerControls()
    end
end
function _G.MSUF_GetDesiredUnitAlpha(key)
    EnsureDB()
    local conf = key and MSUF_DB and MSUF_DB[key]
    if not conf then
        return 1
    end
    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1
    local aIn, aOut = aInLegacy, aOutLegacy
    if conf.alphaExcludeTextPortrait == true then
        local mode = conf.alphaLayerMode
        if mode == true or mode == 1 or mode == "background" then
            mode = "background"
        else
            mode = "foreground"
    end
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        else
            aIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
    end
    end
    local sync = conf.alphaSyncBoth
    if sync == nil then
        sync = conf.alphaSync
    end
    if sync then
        aOut = aIn
    end
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil then
        inCombat = (F.InCombatLockdown and F.InCombatLockdown()) or false
    end
    local a = inCombat and aIn or aOut
    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end
    return a
end
local function MSUF_Alpha_SetTextureAlpha(tex, a)
    if tex and tex.SetAlpha and type(a) == "number" then
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        tex:SetAlpha(a)
    end
end
local function MSUF_Alpha_SetStatusTextureAlpha(sb, a)
    if not sb or not sb.GetStatusBarTexture then return end
    local t = sb:GetStatusBarTexture()
    MSUF_Alpha_SetTextureAlpha(t, a)
end
local function MSUF_Alpha_SetGradientAlphaArray(grads, a)
    if not grads or type(grads) ~= "table" then return end
    for i = 1, #grads do
        MSUF_Alpha_SetTextureAlpha(grads[i], a)
    end
end
local function MSUF_Alpha_SetTextAlpha(fs, a)
    if fs and fs.SetAlpha then
        MSUF_Alpha_SetTextureAlpha(fs, a)
    end
end
local function MSUF_Alpha_ResetLayered(frame)
    if not frame or not frame._msufAlphaLayeredMode then
        return
    end
    local unitAlpha = frame._msufAlphaUnitAlpha or 1
    frame._msufAlphaLayeredMode = nil
    frame._msufAlphaLayerMode = nil
    frame._msufAlphaUnitAlpha = nil
    if frame.SetAlpha then
        frame:SetAlpha(unitAlpha)
    end
    local one = 1
    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, one)
    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.bg, one)
    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, one)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, one)
    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
end
local function MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, mode)
    if not frame then return end
    if mode == true or mode == 1 or mode == "background" then
        mode = "background"
    else
        mode = "foreground"
    end
    frame._msufAlphaLayeredMode = true
    frame._msufAlphaLayerMode = mode
    frame._msufAlphaUnitAlphaFG = alphaFG
    frame._msufAlphaUnitAlphaBG = alphaBG
    if frame.SetAlpha then
        frame:SetAlpha(1)
    end
    local fg = type(alphaFG) == "number" and alphaFG or 1
    local bg = type(alphaBG) == "number" and alphaBG or 1
    if fg < 0 then fg = 0 elseif fg > 1 then fg = 1 end
    if bg < 0 then bg = 0 elseif bg > 1 then bg = 1 end
    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.bg, bg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, fg)
    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, fg)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, fg)
    local one = 1
    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
end

function _G.MSUF_ApplyUnitAlpha(frame, key)
    EnsureDB()
    if not frame or not frame.SetAlpha then return end

    local conf = (MSUF_DB and key) and MSUF_DB[key] or nil
    if ns and ns.UF and ns.UF.IsDisabled and ns.UF.IsDisabled(conf) then return end

    local unit = frame.unit or key
    if not unit then return end

    -- Do not fade the local player by range; also keep existing "dead/disconnected" behavior.
    if unit ~= "player" and (not UnitExists(unit)) then
        frame:SetAlpha(1)
        return
    end

    if unit ~= "player" and UnitIsDeadOrGhost(unit) then
        frame:SetAlpha(0.5)
        return
    end

    if unit ~= "player" and UnitIsConnected and (UnitIsConnected(unit) == false) then
        frame:SetAlpha(0.5)
        return
    end

    -- Layered alpha mode: foreground/background alphas (e.g. bars dim) without dimming text/portrait.
    local layered = _G.MSUF_Alpha_IsLayeredModeEnabled and _G.MSUF_Alpha_IsLayeredModeEnabled(key)
    if layered and frame._msufAlphaSupportsLayered then
        local layerMode = _G.MSUF_Alpha_GetLayerMode and _G.MSUF_Alpha_GetLayerMode(key) or "fgbg"
        local inCombat = (_G.MSUF_InCombat == true)

        local fgIn  = _G.MSUF_Alpha_GetAlphaInCombat and _G.MSUF_Alpha_GetAlphaInCombat(key) or 1
        local fgOut = _G.MSUF_Alpha_GetAlphaOOC and _G.MSUF_Alpha_GetAlphaOOC(key) or 1
        local bgIn  = _G.MSUF_Alpha_GetBgAlphaInCombat and _G.MSUF_Alpha_GetBgAlphaInCombat(key) or 1
        local bgOut = _G.MSUF_Alpha_GetBgAlphaOOC and _G.MSUF_Alpha_GetBgAlphaOOC(key) or 1

        local alphaFG = inCombat and fgIn or fgOut
        local alphaBG = inCombat and bgIn or bgOut

        -- Range-fade multiplier (Target/Focus). Defaults to 1.
        local rm = _G.MSUF_GetRangeFadeMul
        if type(rm) == "function" then
            local m = rm(key, unit, frame)
            if type(m) == "number" then
                if m < 0 then m = 0 elseif m > 1 then m = 1 end
                alphaFG = alphaFG * m
                alphaBG = alphaBG * m
            end
        end

        MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, layerMode)
        return
    end

    -- Non-layered alpha mode: apply one alpha to the frame.
    local a = _G.MSUF_GetDesiredUnitAlpha and _G.MSUF_GetDesiredUnitAlpha(key) or 1
    if type(a) ~= "number" then a = 1 end
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    -- Range-fade multiplier (Target/Focus). Defaults to 1.
    local rm = _G.MSUF_GetRangeFadeMul
    if type(rm) == "function" then
        local m = rm(key, unit, frame)
        if type(m) == "number" then
            if m < 0 then m = 0 elseif m > 1 then m = 1 end
            a = a * m
        end
    end

    if frame._msufAlphaLayeredMode then
        MSUF_Alpha_ResetLayered(frame)
    end

    if frame.GetAlpha then
        local cur = frame:GetAlpha() or 1
        if math.abs(cur - a) > 0.001 then
            frame:SetAlpha(a)
        end
    else
        frame:SetAlpha(a)
    end
end

function _G.MSUF_RefreshAllUnitAlphas()
    EnsureDB()
    local UnitFrames = _G.MSUF_UnitFrames
    if not UnitFrames then return end

    for unit, f in pairs(UnitFrames) do
        if f and f.SetAlpha and f.conf then
            _G.MSUF_ApplyUnitAlpha(f, f.conf)
        end
    end
end

local function MSUF_DoAlphaRefresh()
    if _G.MSUF_RefreshAllUnitAlphas then
        _G.MSUF_RefreshAllUnitAlphas()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if _G.MSUF_RefreshAllUnitAlphas then
                    _G.MSUF_RefreshAllUnitAlphas()
                end
            end)
        end
    end
end

if not _G.MSUF_AlphaEventFrame then
    _G.MSUF_AlphaEventFrame = CreateFrame("Frame")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _G.MSUF_AlphaEventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
        end
        MSUF_DoAlphaRefresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Range Fade (Target/Focus)
-- Uses UnitInRange for party/raid members when possible; falls back to bundled
-- LibRangeCheck-3.0 smart checkers (spell/item DB) for everything else.
-- Default ON (no config needed).
-- ---------------------------------------------------------------------------
do
    if not _G.MSUF_RangeFadeMul then
        -- Per-unit multipliers used by MSUF_GetRangeFadeMul().
        -- target/focus use their config key; bosses use unit ids (boss1..boss5).
        _G.MSUF_RangeFadeMul = { target = 1, focus = 1, boss1 = 1, boss2 = 1, boss3 = 1, boss4 = 1, boss5 = 1 }
    end

    if type(_G.MSUF_GetRangeFadeMul) ~= "function" then
        -- key: config key (e.g. "target", "focus", "boss")
        -- unit/frame: optional, used to disambiguate boss unitframes (boss1..boss5 share config key "boss").
        function _G.MSUF_GetRangeFadeMul(key, unit, frame)
            local t = _G.MSUF_RangeFadeMul
            if type(t) ~= "table" then return 1 end

            if key == "boss" then
                local u = unit or (frame and frame.unit) or nil
                local v = u and t[u] or nil
                return (type(v) == "number") and v or 1
            end

            local v = t[key]
            return (type(v) == "number") and v or 1
        end
    end

    if not _G.MSUF_RangeFadeEventFrame then
        local RF = _G.MSUF_RangeFade or {}
        _G.MSUF_RangeFade = RF

        local UnitInRange = _G.UnitInRange
        local UnitIsPlayer = _G.UnitIsPlayer
        local UnitCanAttack = _G.UnitCanAttack
        local UnitIsUnit = _G.UnitIsUnit
        local UnitExists = _G.UnitExists
        local IsInGroup = _G.IsInGroup
        local IsInRaid = _G.IsInRaid
        local GetNumGroupMembers = _G.GetNumGroupMembers
        local InCombatLockdown = _G.InCombatLockdown
        local NotSecretValue = _G.NotSecretValue

        -- Midnight/Beta: some restricted APIs return "secret" values that cannot be
        -- used in boolean tests / comparisons. Blizzard may provide _G.NotSecretValue;
        -- if not present, we polyfill a cheap detector via pcall.
        if not NotSecretValue then
            NotSecretValue = function(v)
                -- Any benign operation that errors indicates a secret value.
                local ok = pcall(function() return v == v end)
                return ok
            end
        end

        local LibStub = _G.LibStub

        local state = _G.MSUF_RangeFadeMul
        local groupMap = _G.MSUF_RangeFadeGroupUnit or { target = nil, focus = nil }
        _G.MSUF_RangeFadeGroupUnit = groupMap

        local ticker = nil
        local checkerIC, checkerOOC = nil, nil
        local lastRange = nil



        -- RangeFade: clamp the max-checker selection to the *player class/spec* so
        -- short-range specs (Evoker 25y, DH Devourer 25y) don’t accidentally use
        -- item-based 40y checkers from LibRangeCheck.
        local function RF_PlayerKnowsSpell(spellID)
            if not spellID then return false end
            if IsPlayerSpell then
                return IsPlayerSpell(spellID)
            end
            if C_Spell and C_Spell.IsSpellKnown then
                return C_Spell.IsSpellKnown(spellID)
            end
            return false
        end

        local function RF_GetEffectiveMaxRange()
            EnsureDB()
            local gp = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
            local range = gp and tonumber(gp.rangeFadeMaxRange) or 40
            if not range or range <= 0 then range = 40 end

            local class = nil
            if UnitClass then
                class = select(2, UnitClass("player"))
            end

            local override = nil
            if class == "EVOKER" then
                override = 25
            elseif class == "DEMONHUNTER" then
                -- Midnight/Beta: Devourer/Void DH is effectively 25y (detect via Devour spells)
                if RF_PlayerKnowsSpell(473662) or RF_PlayerKnowsSpell(1226019) then
                    override = 25
                else
                    override = 30
                end
            end

            if override and range > override then
                range = override
            end
            return range
        end
        local function Clamp01(x)
            if type(x) ~= "number" then return 1 end
            if x < 0 then return 0 end
            if x > 1 then return 1 end
            return x
        end

        local function SafeBool(v)
            if NotSecretValue and not NotSecretValue(v) then return nil end
            if v == true or v == 1 then return true end
            if v == false or v == 0 then return false end
            return nil
        end
        local function IsOutOfRange(v)
            -- LibRangeCheck checkers often return `true` when IN range and `nil` when OUT of range.
            -- (Some return 1/0, others true/false.)
            -- For range-fade we want: out-of-range => true, in-range => false.
            -- If the value is "secret" (NotSecretValue fails), treat it as unknown (nil) so we DON'T fade.
            if NotSecretValue and not NotSecretValue(v) then return nil end
            if v == true or v == 1 then return false end
            if v == false or v == 0 then return true end
            -- nil / any other non-true return is treated as out-of-range for LRC max-checkers.
            return true
        end

        
        local function GetLib()
            if not LibStub then LibStub = _G.LibStub end
            if not LibStub then return nil end
            return LibStub("LibRangeCheck-3.0", true)
        end


        local function RefreshCheckers(force)
                    local range = RF_GetEffectiveMaxRange()

                    if (not force) and (lastRange == range) and checkerOOC and checkerIC then
                        return
                    end

                    local rc = GetLib()
                    if rc and rc.GetSmartMaxChecker then
                        checkerOOC = rc:GetSmartMaxChecker(range, false)
                        checkerIC  = rc:GetSmartMaxChecker(range, true)
                    else
                        checkerOOC, checkerIC = nil, nil
                    end
                    lastRange = range
                end
        local function ResolveGroupUnit(realUnit)
            if not realUnit or not UnitExists or not UnitExists(realUnit) then return nil end
            if not UnitIsPlayer or not UnitIsPlayer(realUnit) then return nil end
            if not UnitCanAttack or UnitCanAttack("player", realUnit) then return nil end
            if not IsInGroup or not IsInGroup() then return nil end

            if UnitIsUnit and UnitIsUnit(realUnit, "player") then
                return "player"
            end

            local n = GetNumGroupMembers and GetNumGroupMembers() or 0
            if IsInRaid and IsInRaid() then
                for i = 1, n do
                    local u = "raid" .. i
                    if UnitIsUnit and UnitIsUnit(realUnit, u) then
                        return u
                    end
                end
            else
                for i = 1, 4 do
                    local u = "party" .. i
                    if UnitExists and UnitExists(u) and UnitIsUnit and UnitIsUnit(realUnit, u) then
                        return u
                    end
                end
            end

            return nil
        end

        local function FriendlyInRange(realUnit, groupUnit, checker)
            if not realUnit or not UnitExists or not UnitExists(realUnit) then return true end

            if UnitIsPlayer and UnitIsPlayer(realUnit) then
                if _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE and _G.UnitPhaseReason and _G.UnitPhaseReason(realUnit) then
                    return false
                end

                if UnitInRange and groupUnit then
                    local inRange, checked = UnitInRange(groupUnit)
                    -- Secret-safe: never boolean-test `checked`/`inRange` directly.
                    local c = SafeBool(checked)
                    if c == true then
                        local b = SafeBool(inRange)
                        if b == false then return false end
                        if b == true then return true end
                    end
                end
            end

            if checker then
                local ok = checker(realUnit)
                local oor = IsOutOfRange(ok)
                if oor == true then
                    return false
                end
            end

            return true
        end

        local function UnitOutOfRangeMul(unitKey)
            EnsureDB()
            local gp = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
            if not gp or gp.rangeFadeEnabled == false then
                return 1
            end

            local alpha = gp.rangeFadeAlpha
            if type(alpha) ~= "number" then
                alpha = tonumber(alpha) or 0.5
            end
            alpha = Clamp01(alpha)

            if not UnitExists or not UnitExists(unitKey) then
                return 1
            end

            local range = RF_GetEffectiveMaxRange()
            if lastRange ~= range or (checkerOOC == nil and checkerIC == nil) then
                RefreshCheckers(true)
            end

            local inCombat = (_G.MSUF_InCombat == true)
            if inCombat == nil then
                inCombat = (InCombatLockdown and InCombatLockdown()) or false
            end
            local checker = inCombat and checkerIC or checkerOOC

            local gUnit = groupMap[unitKey]
            if not gUnit and UnitIsPlayer and UnitIsPlayer(unitKey) and UnitCanAttack and (not UnitCanAttack("player", unitKey)) then
                gUnit = ResolveGroupUnit(unitKey)
                groupMap[unitKey] = gUnit
            end

            local inRange = true
            if UnitCanAttack and UnitCanAttack("player", unitKey) then
                if checker then
                    local ok = checker(unitKey)
                    local oor = IsOutOfRange(ok)
                    if oor == true then
                        inRange = false
                    end
                end
            else
                inRange = FriendlyInRange(unitKey, gUnit, checker)
            end

            return inRange and 1 or alpha
        end

        local function ApplyKey(unitKey)
            local frames = _G.MSUF_UnitFrames
            local f = frames and frames[unitKey] or nil
            local ApplyUnitAlpha = _G.MSUF_ApplyUnitAlpha
            if f and ApplyUnitAlpha then
                -- Most frames use config key == unitKey; boss frames share config key "boss".
                local cfgKey = f.msufConfigKey or f.conf or (GetConfigKeyForUnit and GetConfigKeyForUnit(f.unit or unitKey)) or unitKey
                ApplyUnitAlpha(f, cfgKey)
            end
        end

        function RF:StopTicker()
            if ticker and ticker.Cancel then
                ticker:Cancel()
            end
            ticker = nil
        end

        function RF:EnsureTicker()
            EnsureDB()
            local gp = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
            local enabled = (gp and gp.rangeFadeEnabled ~= false) or (gp == nil)
            local bossEnabled = enabled and (_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled ~= false)
            local bossNeed = false
            if bossEnabled and UnitExists then
                for i = 1, 5 do
                    if UnitExists("boss" .. i) then
                        bossNeed = true
                        break
                    end
                end
            end
            local need = enabled and (((UnitExists and UnitExists("target")) or (UnitExists and UnitExists("focus"))) or bossNeed)

            if need then
                if not ticker and C_Timer and C_Timer.NewTicker then
                    local tick = gp and tonumber(gp.rangeFadeTick) or 0.25
                    if not tick or tick < 0.1 then tick = 0.25 end
                    ticker = C_Timer.NewTicker(tick, function() RF:Tick() end)
                end
            else
                self:StopTicker()
            end
        end

        function RF:Tick()
            EnsureDB()
            local gp = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
            local enabled = (gp and gp.rangeFadeEnabled ~= false) or (gp == nil)

            local bossEnabled = enabled and (_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled ~= false)
            local bossNeed = false
            if bossEnabled and UnitExists then
                for i = 1, 5 do
                    if UnitExists("boss" .. i) then
                        bossNeed = true
                        break
                    end
                end
            end

            if not enabled then
                if state.target ~= 1 then state.target = 1; ApplyKey("target") end
                if state.focus  ~= 1 then state.focus  = 1; ApplyKey("focus") end
                for i = 1, 5 do
                    local u = "boss" .. i
                    if state[u] ~= 1 then
                        state[u] = 1
                        ApplyKey(u)
                    end
                end
                self:StopTicker()
                return
            end

            local need = ((UnitExists and UnitExists("target")) or (UnitExists and UnitExists("focus"))) or bossNeed
            if not need then
                if state.target ~= 1 then state.target = 1; ApplyKey("target") end
                if state.focus  ~= 1 then state.focus  = 1; ApplyKey("focus") end
                for i = 1, 5 do
                    local u = "boss" .. i
                    if state[u] ~= 1 then
                        state[u] = 1
                        ApplyKey(u)
                    end
                end
                self:StopTicker()
                return
            end

            -- Target / Focus
            local mt = UnitOutOfRangeMul("target")
            if state.target ~= mt then
                state.target = mt
                ApplyKey("target")
            end

            local mf = UnitOutOfRangeMul("focus")
            if state.focus ~= mf then
                state.focus = mf
                ApplyKey("focus")
            end

            -- Boss frames (boss1..boss5) use per-unit multipliers stored under the unit id.
            -- We only compute them when boss frames are enabled.
            if bossEnabled then
                for i = 1, 5 do
                    local u = "boss" .. i
                    local m = UnitOutOfRangeMul(u)
                    if state[u] ~= m then
                        state[u] = m
                        ApplyKey(u)
                    end
                end
            else
                for i = 1, 5 do
                    local u = "boss" .. i
                    if state[u] ~= 1 then
                        state[u] = 1
                        ApplyKey(u)
                    end
                end
            end
        end
        function RF:UpdateGroupMap()
            groupMap.target = ResolveGroupUnit("target")
            groupMap.focus  = ResolveGroupUnit("focus")
        end

        function RF:OnEvent(event)
            if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
                self:UpdateGroupMap()
                self:EnsureTicker()
                self:Tick()
            elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                self:EnsureTicker()
                self:Tick()

            elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
                            RefreshCheckers(true)
                            self:EnsureTicker()
                            self:Tick()
            end
        end

        local f = CreateFrame("Frame")
        _G.MSUF_RangeFadeEventFrame = f
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterEvent("PLAYER_FOCUS_CHANGED")
        f:RegisterEvent("GROUP_ROSTER_UPDATE")
        f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("SPELLS_CHANGED")
        f:RegisterEvent("TRAIT_CONFIG_UPDATED")
        f:SetScript("OnEvent", function(_, event) RF:OnEvent(event) end)

        -- If LRC is present, refresh when it reports new checker sets.
        local rc = GetLib()
        if rc and rc.RegisterCallback and rc.CHECKERS_CHANGED then
            rc.RegisterCallback(RF, rc.CHECKERS_CHANGED, function()
                RefreshCheckers(true)
                RF:EnsureTicker()
                RF:Tick()
            end)
        end

        RefreshCheckers()
        RF:EnsureTicker()
    end
end

local function MSUF_InitPlayerCastbarPreviewToggle()
    if not MSUF_DB or not MSUF_DB.general then
        return
    end
    local playerGroup = _G["MSUF_CastbarPlayerGroup"]
    if not playerGroup then
        return
    end
    local castbarGroup = playerGroup:GetParent() or playerGroup
    local anchorParent = castbarGroup
    local function MSUF_GetLastCastbarSubTabButton()
        return _G["MSUF_CastbarBossButton"]
            or _G["MSUF_CastbarFocusButton"]
            or _G["MSUF_CastbarTargetButton"]
            or _G["MSUF_CastbarPlayerButton"]
            or _G["MSUF_CastbarEnemyButton"]
    end
    local oldCB = _G["MSUF_CastbarPlayerPreviewCheck"]
    if oldCB then
        oldCB:Hide()
        oldCB:SetScript("OnClick", nil)
        oldCB:SetScript("OnShow", nil)
    end
    local btn = _G["MSUF_CastbarEditModeButton"]
    if not btn then
        btn = F.CreateFrame("Button", "MSUF_CastbarEditModeButton", anchorParent, "UIPanelButtonTemplate")
        btn:SetSize(160, 21)
        local fs = btn:GetFontString()
        if fs then
            fs:SetFontObject("GameFontNormal")
    end
    end
    if btn and not btn.__msufMidnightActionSkinned then
        btn.__msufMidnightActionSkinned = true
        if btn.Left then btn.Left:SetAlpha(0) end
        if btn.Middle then btn.Middle:SetAlpha(0) end
        if btn.Right then btn.Right:SetAlpha(0) end
        local n = btn.GetNormalTexture and btn:GetNormalTexture()
        if n then n:SetAlpha(0) end
        local p = btn.GetPushedTexture and btn:GetPushedTexture()
        if p then p:SetAlpha(0) end
        local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if h then h:SetAlpha(0) end
        local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
        if d then d:SetAlpha(0) end
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        bg:SetVertexColor(0.06, 0.06, 0.06, 0.92)
        btn.__msufBg = bg
        local bd = btn:CreateTexture(nil, "BORDER")
        bd:SetTexture("Interface\\Buttons\\WHITE8x8")
        bd:SetAllPoints(btn)
        bd:SetVertexColor(0, 0, 0, 0.85)
        btn.__msufBorder = bd
        local fs = btn.GetFontString and btn:GetFontString()
        if fs then
            fs:SetTextColor(1, 0.82, 0)
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
    end
    end
    btn:ClearAllPoints()
    local lastTab = MSUF_GetLastCastbarSubTabButton()
    if lastTab then
        btn:SetParent(lastTab:GetParent() or anchorParent)
        btn:SetPoint("LEFT", lastTab, "RIGHT", 8, 0)
    else
        btn:SetPoint("TOPRIGHT", anchorParent, "TOPRIGHT", -175, -152)
    end
    local function UpdateButtonLabel()
        EnsureDB()
        local g       = MSUF_DB.general or {}
        local active  = g.castbarPlayerPreviewEnabled and true or false
        if active then
            btn:SetText("Castbar Edit Mode: ON")
        else
            btn:SetText("Castbar Edit Mode: OFF")
    end
    end
    btn:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local wasActive = g.castbarPlayerPreviewEnabled and true or false
        if wasActive then
            local bf = _G and _G.MSUF_BossCastbarPreview
            if bf and bf.GetWidth and bf.GetHeight then
                g.bossCastbarWidth  = math.floor((bf:GetWidth()  or (tonumber(g.bossCastbarWidth)  or 240)) + 0.5)
                g.bossCastbarHeight = math.floor((bf:GetHeight() or (tonumber(g.bossCastbarHeight) or 18)) + 0.5)
                bf.isDragging = false
                if bf.SetScript then
                    bf:SetScript("OnUpdate", nil)
                end
            end
            if type(MSUF_SyncBossCastbarSliders) == "function" then
                MSUF_SyncBossCastbarSliders()
            end
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
    end
        g.castbarPlayerPreviewEnabled = not (g.castbarPlayerPreviewEnabled and true or false)
        if g.castbarPlayerPreviewEnabled then
            print("|cffffd700MSUF:|r Castbar Edit Mode |cff00ff00ON|r – drag player/target/focus castbars with the mouse.")
        else
            print("|cffffd700MSUF:|r Castbar Edit Mode |cffff0000OFF|r.")
    end
        if MSUF_UpdatePlayerCastbarPreview then
            MSUF_UpdatePlayerCastbarPreview()
    end
        if g.castbarPlayerPreviewEnabled then
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
            if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                _G.MSUF_SetupBossCastbarPreviewEditMode()
            end
            C_Timer.After(0, function()
                    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                        _G.MSUF_UpdateBossCastbarPreview()
                    end
                    if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                        _G.MSUF_SetupBossCastbarPreviewEditMode()
                    end
                end)
    end
        UpdateButtonLabel()
    end)
    btn:SetScript("OnShow", UpdateButtonLabel)
    UpdateButtonLabel()
    btn:Show()
end
local function KillFrame(frame, allowInEditMode)
    if not frame then return end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    frame:Hide()
    local isProtected = frame.IsProtected and frame:IsProtected()
    if isProtected then
        if RegisterStateDriver and not frame.MSUF_StateDriverHidden then
            if not (F.InCombatLockdown and F.InCombatLockdown()) then
                RegisterStateDriver(frame, "visibility", "hide")
                frame.MSUF_StateDriverHidden = true
            end
    end
    elseif frame.SetScript then
        frame:SetScript("OnShow", function(f)
            if allowInEditMode and MSUF_IsInEditMode and MSUF_IsInEditMode() then
                return
            end
            f:Hide()
        end)
    end
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
end
local function MSUF_GetMSUFPlayerFrame()
    if _G and _G.MSUF_player then return _G.MSUF_player end
    local list = _G and _G.MSUF_UnitFrames
    if list and list.player then return list.player end
    return nil
end
local MSUF_CompatAnchorEventFrame
local MSUF_CompatAnchorPending
local function MSUF_ApplyCompatAnchor_PlayerFrame()
    if not PlayerFrame then return end
    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general
    if g.disableBlizzardUnitFrames == false then return end
    if g.hardKillBlizzardPlayerFrame == true then
        PlayerFrame.MSUF_CompatAnchorActive = nil
        return
    end
    PlayerFrame.MSUF_CompatAnchorActive = true
    if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
    if PlayerFrame.Show then PlayerFrame:Show() end
    if F.InCombatLockdown and F.InCombatLockdown() then
        MSUF_CompatAnchorPending = true
        if not MSUF_CompatAnchorEventFrame then
            MSUF_CompatAnchorEventFrame = F.CreateFrame("Frame")
            MSUF_CompatAnchorEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            MSUF_CompatAnchorEventFrame:SetScript("OnEvent", function()
                if MSUF_CompatAnchorPending then
                    MSUF_CompatAnchorPending = nil
                    MSUF_ApplyCompatAnchor_PlayerFrame()
                end
            end)
    end
        return
    end
    local anchor = MSUF_GetMSUFPlayerFrame()
    if anchor and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
        PlayerFrame:ClearAllPoints()
        PlayerFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    if PlayerFrame.SetScale then PlayerFrame:SetScale(0.05) end
    if PlayerFrame.SetFrameStrata then PlayerFrame:SetFrameStrata("BACKGROUND") end
    if PlayerFrame.SetFrameLevel then PlayerFrame:SetFrameLevel(0) end
    if PlayerFrame.HookScript and not PlayerFrame.MSUF_CompatAnchorHooked then
        PlayerFrame.MSUF_CompatAnchorHooked = true
        PlayerFrame:HookScript("OnShow", function()
            if not PlayerFrame or not PlayerFrame.MSUF_CompatAnchorActive then return end
            if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
            if F.InCombatLockdown and F.InCombatLockdown() then
                MSUF_CompatAnchorPending = true
                return
            end
            local a = MSUF_GetMSUFPlayerFrame()
            if a and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
                PlayerFrame:ClearAllPoints()
                PlayerFrame:SetPoint("CENTER", a, "CENTER", 0, 0)
            end
        end)
    end
end
_G.MSUF_ApplyCompatAnchor_PlayerFrame = MSUF_ApplyCompatAnchor_PlayerFrame
local function HideDefaultFrames()
    EnsureDB()
    local g = MSUF_DB.general or {}
    if g.disableBlizzardUnitFrames == false then
        return
    end
    if g.hardKillBlizzardPlayerFrame == true then
        KillFrame(PlayerFrame)
    else
            _G.MSUF_ApplyCompatAnchor_PlayerFrame()
    end
    KillFrame(TargetFrameToT)
    KillFrame(PetFrame)
    KillFrame(TargetFrame)
    KillFrame(FocusFrame)
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local bossFrame = _G["Boss"..i.."TargetFrame"]
        KillFrame(bossFrame) -- kein allowInEditMode: immer tot, auch im Blizzard Edit Mode
    end
    if BossTargetFrameContainer then
        KillFrame(BossTargetFrameContainer)
        if BossTargetFrameContainer.Selection then
            local sel = BossTargetFrameContainer.Selection
            if sel.UnregisterAllEvents then
                sel:UnregisterAllEvents()
            end
            if sel.EnableMouse then
                sel:EnableMouse(false)
            end
            sel:Hide()
            if sel.SetScript then
                sel:SetScript("OnShow", function(f) f:Hide() end)
                sel:SetScript("OnEnter", nil)
                sel:SetScript("OnLeave", nil)
            end
    end
    end
end
local function MSUF_GetVisibilityDriverForUnit(unit)
    if unit == "target" then
        return "[@target,exists] show; hide"
    elseif unit == "focus" then
        return "[@focus,exists] show; hide"
    elseif unit == "pet" then
        return "[@pet,exists] show; hide"
    elseif unit == "targettarget" then
        return "[@targettarget,exists] show; hide"
    elseif type(unit) == "string" and unit:match("^boss%d+$") then
        return ("[@" .. unit .. ",exists] show; hide")
    end
    return nil
end
local function MSUF_ApplyUnitVisibilityDriver(frame, forceShow)
    if not frame or not frame.unit then return end
    if frame.unit == "player" then return end
if type(EnsureDB) == "function" then
    EnsureDB()
end
local confKey
if frame.isBoss or (type(frame.unit) == "string" and frame.unit:match("^boss%d+$")) then
    confKey = "boss"
else
    confKey = frame.unit
end
local conf = (type(MSUF_DB) == "table" and confKey and MSUF_DB[confKey]) or nil
if ns.UF.IsDisabled(conf) then
    ns.UF.ForceVisibilityHidden(frame)
    return
end
    local drv = frame._msufVisibilityDriver
    if not drv then
        drv = MSUF_GetVisibilityDriverForUnit(frame.unit)
        frame._msufVisibilityDriver = drv
    end
    if not drv then return end
    local rsd = _G and _G.RegisterStateDriver
    local usd = _G and _G.UnregisterStateDriver
    if type(rsd) ~= "function" or type(usd) ~= "function" then return end
    if not forceShow and frame.isBoss and MSUF_BossTestMode then
        forceShow = true
    end
    if frame._msufVisibilityForced == (forceShow and true or false) then
        return
    end
    frame._msufVisibilityForced = (forceShow and true or false)
    usd(frame, "visibility")
    if forceShow then
        rsd(frame, "visibility", "show")
    else
        rsd(frame, "visibility", drv)
    end
end
local function MSUF_RefreshAllUnitVisibilityDrivers(forceShow)
    MSUF_ForEachUnitFrame(function(f)
        MSUF_ApplyUnitVisibilityDriver(f, forceShow)
    end)
end
_G.MSUF_RefreshAllUnitVisibilityDrivers = MSUF_RefreshAllUnitVisibilityDrivers
local MSUF_GridFrame
function ns.MSUF_RefreshAllFrames()
    MSUF_ForEachUnitFrame(function(f)
        if f and f.unit and f.hpBar then
            ns.UF.RequestUpdate(f, true, false, "RefreshAllFrames")
    end
    end)
end
function _G.__MSUF_UFREQ_Flush()
    local co = _G.__MSUF_UFREQ_CO
    if not co then return end

    co.queued = false

    local frames = co.frames
    local force = co.force
    local layout = co.layout
    local reason = co.reason

    co.frames = {}
    co.force = {}
    co.layout = {}
    co.reason = nil

    local reqLayout = _G.MSUF_UFCore_RequestLayout
    local q = _G.MSUF_QueueUnitframeUpdate

    for f in pairs(frames) do
        if f then
            if layout[f] then
                reqLayout(f, reason or "MSUF_RequestUnitframeUpdate", false)
            end
            q(f, force[f] and true or false)
    end
    end
end

function _G.MSUF_RequestUnitframeUpdate(frame, forceFull, wantLayout, reason, urgentNow)
    if not frame then return end

        local reqLayout = _G.MSUF_UFCore_RequestLayout
    if urgentNow == true then
        if wantLayout then
            reqLayout(frame, reason or "MSUF_RequestUnitframeUpdate", true)
    end
        _G.MSUF_QueueUnitframeUpdate(frame, forceFull and true or false)
        return
    end

    local co = _G.__MSUF_UFREQ_CO
    if not co then
        co = {
            queued = false,
            frames = {},
            force = {},
            layout = {},
            reason = nil,
        }
        _G.__MSUF_UFREQ_CO = co
    end

    co.frames[frame] = true
    if forceFull then
        co.force[frame] = true
    end
    if wantLayout then
        co.layout[frame] = true
    end
    if co.queued then
        return
    end

    co.queued = true
    co.reason = reason

    C_Timer.After(0, _G.__MSUF_UFREQ_Flush)
end

local function MSUF_GetUnitLabelForKey(key)
    if key == "player" then
        return "Player"
    elseif key == "target" then
        return "Target"
    elseif key == "targettarget" then
        return "Target of Target"
    elseif key == "focus" then
        return "Focus"
    elseif key == "pet" then
        return "Pet"
    elseif key == "boss" then
        return "Boss"
    else
        return key or "Unknown"
    end
end
_G.MSUF_GetUnitLabelForKey = MSUF_GetUnitLabelForKey
local MSUF_POPUP_LABEL_W = 88
local MSUF_POPUP_BOX_W   = 92
local MSUF_POPUP_BOX_H   = 20
local MSUF_PositionPopup
local MSUF_CastbarPositionPopup
local function MSUF_OpenOptionsToKey(tabKey)
    tabKey = (type(tabKey) == "string" and tabKey ~= "" and tabKey) or "home"
    local OpenPage = _G and _G.MSUF_OpenPage
    if type(OpenPage) ~= "function" then return end
    OpenPage("options")
    C_Timer.After(0, function()
        local p = _G and _G.MSUF_OptionsPanel
        if not p or type(MSUF_GetTabButtonHelpers) ~= "function" then return end
        local _, setKey = MSUF_GetTabButtonHelpers(p)
        if type(setKey) == "function" then
            setKey(tabKey)
            if p.LoadFromDB then p:LoadFromDB() end
    end
    end)
end
local function MSUF_OpenOptionsToUnitMenu(unitKey)
    if not unitKey then return end
    local OpenPage = _G and _G.MSUF_OpenPage
    if type(OpenPage) ~= "function" then return end
    local k = string.lower(tostring(unitKey))
    if string.match(k, "^boss%d+$") then k = "boss" end
    OpenPage("uf_" .. k)
end
_G.MSUF_OpenOptionsToUnitMenu = MSUF_OpenOptionsToUnitMenu
local function MSUF_OpenOptionsToCastbarMenu(unitKey)
    if not unitKey then return end
    local OpenPage = _G and _G.MSUF_OpenPage
    if type(OpenPage) ~= "function" then return end
    OpenPage("opt_castbar")
    C_Timer.After(0, function()
        local k = string.lower(tostring(unitKey))
        if string.match(k, "^boss%d+$") then k = "boss" end
        local setSub = _G and _G.MSUF_SetActiveCastbarSubPage
        if type(setSub) == "function" then
            setSub(k)
    end
        local p = _G and _G.MSUF_OptionsPanel
        if p and p.LoadFromDB then p:LoadFromDB() end
    end)
end
_G.MSUF_OpenOptionsToCastbarMenu = MSUF_OpenOptionsToCastbarMenu
local function MSUF_OpenOptionsToBossCastbarMenu()
    MSUF_OpenOptionsToCastbarMenu("boss")
end
_G.MSUF_OpenOptionsToBossCastbarMenu = MSUF_OpenOptionsToBossCastbarMenu
function MSUF_UpdateCastbarVisuals()
MSUF_BumpCastbarStyleRevision()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local showIcon    = ns.Util.Enabled(nil, g, "castbarShowIcon", true)
    local showName    = ns.Util.Enabled(nil, g, "castbarShowSpellName", true)
    local fontSize    = tonumber(g.castbarSpellNameFontSize) or 0
    local iconOffsetX = tonumber(g.castbarIconOffsetX) or 0
    local iconOffsetY = tonumber(g.castbarIconOffsetY) or 0
    local fontPath    = MSUF_GetFontPath()
    local fontFlags   = MSUF_GetFontFlags()
    local fr, fg, fb = 1, 1, 1
    if type(MSUF_GetCastbarTextColor) == "function" then
        fr, fg, fb = MSUF_GetCastbarTextColor()
    elseif type(MSUF_GetConfiguredFontColor) == "function" then
        fr, fg, fb = MSUF_GetConfiguredFontColor()
    else
        local colorKey = (g.fontColor or "white"):lower()
        local colorDef = (MSUF_FONT_COLORS and (MSUF_FONT_COLORS[colorKey] or MSUF_FONT_COLORS.white)) or { 1, 1, 1 }
        fr, fg, fb = colorDef[1], colorDef[2], colorDef[3]
    end
    local useShadow = g.textBackdrop and true or false
    local baseSize = g.fontSize or 14
    local effectiveSize = (fontSize > 0) and fontSize or baseSize
    local function ApplyFontColor(fs, size)
        fs:SetFont(fontPath, size, fontFlags)
        fs:SetTextColor(fr, fg, fb, 1)
    end
    local function ApplyShadow(fs)
        if useShadow then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
    end
    end
    local function ApplyBlizzard(frame)
        if not frame then return end
        local icon = frame.Icon or frame.icon or (frame.IconFrame and frame.IconFrame.Icon)
        if icon then icon:SetShown(showIcon) end
        local text = frame.Text or frame.text
        if text then
            text:SetShown(showName)
            ApplyFontColor(text, effectiveSize)
            ApplyShadow(text)
    end
    end
    ApplyBlizzard(TargetFrameSpellBar)
    ApplyBlizzard(PetCastingBarFrame)
    local function ApplyMSUF(frame)
        if not frame or not frame.statusBar then return end
        local statusBar = frame.statusBar
        local icon      = frame.icon or frame.Icon or (frame.IconFrame and (frame.IconFrame.Icon or frame.IconFrame.icon)) or frame.iconTexture or frame.IconTexture
        local width     = frame:GetWidth()  or statusBar:GetWidth()  or 250
        local height    = frame:GetHeight() or statusBar:GetHeight() or 18
        local cfg = MSUF_DB and MSUF_DB.general
        local unitKey, prefix
        if cfg then
            local gw = tonumber(cfg.castbarGlobalWidth)
            local gh = tonumber(cfg.castbarGlobalHeight)
            if gw and gw > 0 then width = gw; frame:SetWidth(width) end
            if gh and gh > 0 then height = gh; frame:SetHeight(gh) end
            unitKey = MSUF_GetCastbarUnitFromFrame(frame)
            prefix = unitKey and MSUF_GetCastbarPrefix(unitKey) or nil
            if prefix then
                local bw = tonumber(cfg[prefix .. "BarWidth"])
                local bh = tonumber(cfg[prefix .. "BarHeight"])
                if bw and bw > 0 then width = bw; frame:SetWidth(width) end
                if bh and bh > 0 then height = bh; frame:SetHeight(bh) end
            end
    end
        local showIconLocal = showIcon
        local iconOXLocal   = iconOffsetX
        local iconOYLocal   = iconOffsetY
        local iconSizeLocal = height
        local cfgR = cfg
        if cfgR then
            if prefix then
                local v = cfgR[prefix .. "ShowIcon"]
                if v ~= nil then showIconLocal = (v ~= false) end
                v = cfgR[prefix .. "IconOffsetX"]; if v ~= nil then iconOXLocal = tonumber(v) or 0 end
                v = cfgR[prefix .. "IconOffsetY"]; if v ~= nil then iconOYLocal = tonumber(v) or 0 end
                v = cfgR[prefix .. "IconSize"]
                if v ~= nil then
                    iconSizeLocal = tonumber(v) or iconSizeLocal
                else
                    local gv = tonumber(cfgR.castbarIconSize) or 0
                    if gv and gv > 0 then iconSizeLocal = gv end
                end
            else
                local gv = tonumber(cfgR.castbarIconSize) or 0
                if gv and gv > 0 then iconSizeLocal = gv end
            end
    end
        if iconSizeLocal < 6 then iconSizeLocal = 6 end
        if iconSizeLocal > 128 then iconSizeLocal = 128 end
        local isPlayerCastbar = (frame == MSUF_PlayerCastbar or frame == MSUF_PlayerCastbarPreview)
        local iconDetached = (iconOXLocal ~= 0)
        local backgroundBar = frame.backgroundBar
        if isPlayerCastbar and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
            _G.MSUF_ApplyPlayerCastbarIconLayout(frame, g, -1, 1)
            if backgroundBar and frame.statusBar then
                backgroundBar:ClearAllPoints()
                backgroundBar:SetAllPoints(frame.statusBar)
            end
        else
            if icon and statusBar and icon.GetParent and icon.SetParent then
                local desiredParent = iconDetached and statusBar or frame
                if icon:GetParent() ~= desiredParent then icon:SetParent(desiredParent) end
            end
            if icon then
                icon:SetShown(showIconLocal)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", frame, "LEFT", iconOXLocal, iconOYLocal)
                icon:SetSize(iconSizeLocal, iconSizeLocal)
                if icon.SetDrawLayer then icon:SetDrawLayer("OVERLAY", 7) end
            end
            statusBar:ClearAllPoints()
            if showIconLocal and icon and not iconDetached then
                statusBar:SetPoint("LEFT", frame, "LEFT", iconSizeLocal + 1, 0)
                statusBar:SetWidth(width - (iconSizeLocal + 1))
            else
                statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
                statusBar:SetWidth(width)
            end
            statusBar:SetHeight(height - 2)
            if backgroundBar then
                backgroundBar:ClearAllPoints()
                backgroundBar:SetAllPoints(statusBar)
            end
    end
        local cfg2 = cfg or {}
        local showNameLocal = showName
        local effectiveSizeLocal = effectiveSize
        local textOX, textOY = 0, 0
        local timeSizeLocal = effectiveSizeLocal
        if prefix then
            local v = cfg2[prefix .. "ShowSpellName"]
            if v ~= nil then showNameLocal = (v ~= false) end
            textOX = tonumber(cfg2[prefix .. "TextOffsetX"]) or 0
            textOY = tonumber(cfg2[prefix .. "TextOffsetY"]) or 0
            local ov = tonumber(cfg2[prefix .. "SpellNameFontSize"]) or 0
            if ov and ov > 0 then effectiveSizeLocal = ov end
            local tov = tonumber(cfg2[prefix .. "TimeFontSize"]) or 0
            if tov and tov > 0 then
                timeSizeLocal = tov
            else
                timeSizeLocal = effectiveSizeLocal
            end
    end
        local text = frame.castText or frame.Text or frame.text
        if text then
            text:SetShown(showNameLocal)
            ApplyFontColor(text, effectiveSizeLocal)
            if text.SetPoint then
                text:ClearAllPoints()
                text:SetPoint("LEFT", statusBar, "LEFT", 2 + textOX, 0 + textOY)
            end
            ApplyShadow(text)
    end
        local tt = frame.timeText
        if tt and MSUF_IsCastTimeEnabled(frame) then
            ApplyFontColor(tt, timeSizeLocal or effectiveSize)
            ApplyShadow(tt)
    end
    end
    ApplyMSUF(MSUF_PlayerCastbar)
    ApplyMSUF(MSUF_TargetCastbar)
    ApplyMSUF(MSUF_FocusCastbar)
    ApplyMSUF(MSUF_PlayerCastbarPreview)
    ApplyMSUF(MSUF_TargetCastbarPreview)
    ApplyMSUF(MSUF_FocusCastbarPreview)
    if _G.MSUF_BossCastbarPreview then
        ApplyMSUF(_G.MSUF_BossCastbarPreview)
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" and not _G.MSUF_BossPreviewRefreshLock then
        _G.MSUF_BossPreviewRefreshLock = true
        _G.MSUF_UpdateBossCastbarPreview()
        if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
            _G.MSUF_SetupBossCastbarPreviewEditMode()
    end
        _G.MSUF_BossPreviewRefreshLock = false
    end
    local bossN = _G.MSUF_MAX_BOSS_FRAMES or 5
    for i = 1, bossN do
        local bf = _G["MSUF_boss" .. i .. "CastBar"]
        if bf then ApplyMSUF(bf) end
    end
end
local function MSUF_UpdateNameColor(frame)
    if not frame or not frame.nameText then return end
    EnsureDB()
    local g = MSUF_DB.general
    local r, gCol, b
    if g.nameClassColor and frame.unit and F.UnitIsPlayer(frame.unit) then
        local _, classToken = F.UnitClass(frame.unit)
        if classToken then
            r, gCol, b = MSUF_GetClassBarColor(classToken)
    end
    end
    if (not (r and gCol and b)) and g.npcNameRed and frame.unit and not F.UnitIsPlayer(frame.unit) then
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost(frame.unit) then
            r, gCol, b = MSUF_GetNPCReactionColor("dead")
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", frame.unit)
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                end
            end
    end
    end
    if not (r and gCol and b) then
        r, gCol, b = MSUF_GetConfiguredFontColor()
    end
    frame.nameText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    if frame.levelText then
        frame.levelText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    end
end
_G.MSUF_RefreshAllIdentityColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
    local UpdateNameColor = MSUF_UpdateNameColor
    local UnitExists = F.UnitExists
    if type(UpdateNameColor) ~= "function" or type(UnitExists) ~= "function" then return end
    MSUF_ForEachUnitFrame(function(f)
        if f and f.nameText and f.unit and UnitExists(f.unit) then
            UpdateNameColor(f)
    end
    end)
end
_G.MSUF_RefreshAllPowerTextColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local enabled = (g and g.colorPowerTextByType == true)
    local UnitExists = F.UnitExists
    local UpdatePowerFast = _G.MSUF_UFCore_UpdatePowerTextFast
    local GetFontColor = MSUF_GetConfiguredFontColor
    if type(UnitExists) ~= "function" then return end
    MSUF_ForEachUnitFrame(function(f)
        if f and f.powerText and f.unit and UnitExists(f.unit) then
            if enabled then
                if type(UpdatePowerFast) == "function" then
                    UpdatePowerFast(f)
                end
            else
                local fr, fg, fb = 1, 1, 1
                if type(GetFontColor) == "function" then
                    fr, fg, fb = GetFontColor()
                end
                if f.powerText.SetTextColor then
                    f.powerText:SetTextColor(fr, fg, fb, 1)
                    f.powerText._msufColorStamp = nil
                end
                if f.powerTextPct and f.powerTextPct.SetTextColor then
                    f.powerTextPct:SetTextColor(fr, fg, fb, 1)
                    f.powerTextPct._msufColorStamp = nil
                end
            end
    end
    end)
end
local function MSUF_HideTex(t) if t then t:Hide() end end
local _MSUF_GRAD_HIDE_KEYS = { "left", "right", "up", "down", "left2", "right2", "up2", "down2" }
local function MSUF_HideGradSet(grads, startIdx)
    if not grads then return end
    for i = startIdx or 1, 8 do
        local t = grads[_MSUF_GRAD_HIDE_KEYS[i]]
        if t then t:Hide() end
    end
end
local function MSUF_SetGrad(tex, orientation, a1, a2, strength)
    if not tex then return end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
    elseif tex.SetGradient then
        tex:SetGradient(orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    else
        tex:SetColorTexture(0, 0, 0, (a1 > a2) and a1 or a2)
    end
    if strength > 0 then tex:Show() else tex:Hide() end
end
local function MSUF_ApplyBarGradient(frameOrTex, isPower)
    if not frameOrTex then return end
    EnsureDB()
    local g = MSUF_DB.general or {}
    local strength = g.gradientStrength or 0.45
    if isPower then
        if g.enablePowerGradient == false then strength = 0 end
    else
        if g.enableGradient == false then strength = 0 end
    end
    -- Allow applying to a standalone texture (used by some indicators).
    if frameOrTex.SetGradientAlpha and not (isPower and frameOrTex.powerGradients or frameOrTex.hpGradients) then
        local tex = frameOrTex
        local dir = g.gradientDirection
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT'; g.gradientDirection = dir end
        local orientation, a1, a2 = 'HORIZONTAL', 0, strength
        if dir == 'LEFT' then a1, a2 = strength, 0
        elseif dir == 'UP' then orientation = 'VERTICAL'; a1, a2 = 0, strength
        elseif dir == 'DOWN' then orientation = 'VERTICAL'; a1, a2 = strength, 0 end
        MSUF_SetGrad(tex, orientation, a1, a2, strength)
        return
    end
    local frame = frameOrTex
    local bar = isPower and (frame.targetPowerBar or frame.powerBar) or frame.hpBar
    local grads = isPower and frame.powerGradients or frame.hpGradients
    if not bar or not grads then return end
    -- Migrate old single-direction setting to the new per-edge toggles once.
    local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
    if not hasNew then
        local dir = g.gradientDirection
        if type(dir) ~= 'string' or dir == '' then dir = 'RIGHT' end
        dir = string.upper(dir)
        g.gradientDirLeft = (dir == 'LEFT')
        g.gradientDirRight = (dir == 'RIGHT')
        g.gradientDirUp = (dir == 'UP')
        g.gradientDirDown = (dir == 'DOWN')
    end
    local left = (g.gradientDirLeft == true)
    local right = (g.gradientDirRight == true)
    local up = (g.gradientDirUp == true)
    local down = (g.gradientDirDown == true)
    if not left and not right and not up and not down then right = true; g.gradientDirRight = true end
    if strength <= 0 then
        MSUF_HideGradSet(grads)
        return
    end
    if left then
        local useHalf = (right == true)
        local tex = grads.left
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('RIGHT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.left) end
    if right then
        local useHalf = (left == true)
        local tex = grads.right
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('LEFT', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'HORIZONTAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.right) end
    if up then
        local useHalf = (down == true)
        local tex = grads.up
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('TOPLEFT', bar, 'TOPLEFT'); tex:SetPoint('TOPRIGHT', bar, 'TOPRIGHT'); tex:SetPoint('BOTTOM', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', 0, strength, strength)
        tex:Show()
    else MSUF_HideTex(grads.up) end
    if down then
        local useHalf = (up == true)
        local tex = grads.down
        tex:ClearAllPoints()
        if useHalf then tex:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT'); tex:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT'); tex:SetPoint('TOP', bar, 'CENTER')
        else tex:SetAllPoints(bar) end
        MSUF_SetGrad(tex, 'VERTICAL', strength, 0, strength)
        tex:Show()
    else MSUF_HideTex(grads.down) end
    MSUF_HideGradSet(grads, 5)
end
local function MSUF_ApplyHPGradient(frameOrTex) return MSUF_ApplyBarGradient(frameOrTex, false) end
local function MSUF_ApplyPowerGradient(frameOrTex) return MSUF_ApplyBarGradient(frameOrTex, true) end
function _G.MSUF_ApplyPowerBarBorder(bar)
    if not bar then return end
    local bdb = (MSUF_DB and MSUF_DB.bars) or nil
    local enabled = bdb and (bdb.powerBarBorderEnabled == true) or false
    local size = bdb and tonumber(bdb.powerBarBorderSize) or 1
    if type(size) ~= 'number' then size = 1 end
    if size < 1 then size = 1 elseif size > 10 then size = 10 end
    local border = bar._msufPowerBorder
    if not border then
        border = F.CreateFrame('Frame', nil, bar)
        border:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 2)
        border:EnableMouse(false)
        bar._msufPowerBorder = border
    end
    if not enabled then
        if border.Hide then border:Hide() end
        return
    end
    if border.SetBackdrop then
        border:SetBackdrop(nil)
    end
    border:ClearAllPoints()
    border:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
    border:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', 0, 0)
    border:SetHeight(size)
    local line = border._msufSeparatorLine
    if not line and border.CreateTexture then
        line = border:CreateTexture(nil, 'OVERLAY')
        line:SetTexture('Interface\\Buttons\\WHITE8x8')
        line:SetVertexColor(0, 0, 0, 1)
        line:SetAllPoints(border)
        border._msufSeparatorLine = line
    elseif line and line.SetAllPoints then
        line:SetAllPoints(border)
    end
    border:Show()
end
function _G.MSUF_ApplyPowerBarBorder_All()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= 'table' then return end
    for _, f in pairs(frames) do
        local bar = f and (f.targetPowerBar or f.powerBar)
        if bar then
            _G.MSUF_ApplyPowerBarBorder(bar)
    end
    end
end
local function MSUF_PreCreateHPGradients(hpBar)
    if not hpBar or not hpBar.CreateTexture then return nil end
    local function MakeTex()
        local t = hpBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("BLEND")
        t:Hide()
        return t
    end
    return {
        left  = MakeTex(),
        right = MakeTex(),
        up    = MakeTex(),
        down  = MakeTex(),
    }
end
local function MSUF_UpdateAbsorbBars(self, unit, maxHP, isHeal)
    local bar = isHeal and self and self.healAbsorbBar or self and self.absorbBar
    local api = isHeal and UnitGetTotalHealAbsorbs or UnitGetTotalAbsorbs
    if not self or not bar or type(api) ~= 'function' then return end
    local apply = _G.MSUF_ApplyAbsorbAnchorMode
    if type(apply) == 'function' then apply(self) end
    if isHeal then
        MSUF_ApplyHealAbsorbOverlayColor(bar)
    else
        EnsureDB()
        MSUF_ApplyAbsorbOverlayColor(bar)
        local g = MSUF_DB.general or {}
        if g.enableAbsorbBar == false then
            MSUF_ResetBarZero(bar, true)
            return
    end
    end
    if _G.MSUF_AbsorbTextureTestMode then
        local max = maxHP or F.UnitHealthMax(unit) or 1
        bar:SetMinMaxValues(0, max)
        MSUF_SetBarValue(bar, max * (isHeal and 0.15 or 0.25))
        bar:Show()
        return
    end
    local total = api(unit)
    if not total then
        MSUF_ResetBarZero(bar, true)
        return
    end
    local max = maxHP or F.UnitHealthMax(unit) or 1
    bar:SetMinMaxValues(0, max)
    MSUF_SetBarValue(bar, total)
    bar:Show()
end
local function MSUF_UpdateAbsorbBar(self, unit, maxHP) return MSUF_UpdateAbsorbBars(self, unit, maxHP, false) end
local function MSUF_UpdateHealAbsorbBar(self, unit, maxHP) return MSUF_UpdateAbsorbBars(self, unit, maxHP, true) end
ROOT_G.MSUF_UpdateAbsorbBar = ROOT_G.MSUF_UpdateAbsorbBar or MSUF_UpdateAbsorbBar
ROOT_G.MSUF_UpdateHealAbsorbBar = ROOT_G.MSUF_UpdateHealAbsorbBar or MSUF_UpdateHealAbsorbBar
-- Secret-safe: pure layout change via StatusBar:SetReverseFill.
local function MSUF_ApplyAbsorbAnchorMode(self)
    if not self then return end
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local mode = g.absorbAnchorMode or 2
    if self._msufAbsorbAnchorModeStamp == mode then
        return
    end
    self._msufAbsorbAnchorModeStamp = mode
    local absorbReverse = (mode ~= 1)
    local healReverse   = not absorbReverse
    if self.absorbBar and self.absorbBar.SetReverseFill then
        self.absorbBar:SetReverseFill(absorbReverse and true or false)
    end
    if self.healAbsorbBar and self.healAbsorbBar.SetReverseFill then
        self.healAbsorbBar:SetReverseFill(healReverse and true or false)
    end
end
_G.MSUF_ApplyAbsorbAnchorMode = MSUF_ApplyAbsorbAnchorMode
local function PositionUnitFrame(f, unit)
    if not f or not unit then return end
    if f._msufDragActive then return end
    local key = f.msufConfigKey
    if not key then
        key = GetConfigKeyForUnit(unit)
        f.msufConfigKey = key
    end
    if not key then return end
    if F.InCombatLockdown() then
        return
    end
    local conf = f.cachedConfig
    if not conf then
        EnsureDB()
        conf = MSUF_DB and MSUF_DB[key]
        f.cachedConfig = conf
    end
    if not conf then return end
    local anchor = MSUF_GetAnchorFrame()
    local ecv = _G["EssentialCooldownViewer"]
    if MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown and ecv and anchor == ecv then
        local rule = MSUF_ECV_ANCHORS[key]
        if rule then
            local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3], rule[4]
            local gapY = (conf.offsetY ~= nil) and conf.offsetY or -20
            local x = baseX + (conf.offsetX or 0)
            local y = gapY + (extraY or 0)
            MSUF_ApplyPoint(f, point, ecv, relPoint, x, y)
            return
    end
    end
    if key == "boss" then
        local index = tonumber(unit:match("^boss(%d+)$")) or 1
        local x = conf.offsetX
        local spacing = conf.spacing or -36
        local y = conf.offsetY + (index - 1) * spacing
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", x, y)
    else
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
    end
end
local function MSUF_GetApproxPercentTextWidth(templateFS)
    if not templateFS or not templateFS.GetFont then
        return 0
    end
    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_PctWidthCache = _G.MSUF_PctWidthCache or {}
    local cache = _G.MSUF_PctWidthCache
    local cached = cache[fontKey]
    if cached then
        return cached
    end
    local fs = _G.MSUF_PctMeasureFS
    if not fs then
        local holder = F.CreateFrame("Frame", "MSUF_PctMeasureFrame", UIParent)
        holder:Hide()
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs:Hide()
        _G.MSUF_PctMeasureFS = fs
    end
    fs:SetFont(font, size, flags)
    fs:SetText("100.0%")
    local w = 0
    if fs.GetStringWidth then
        w = fs:GetStringWidth() or 0
    end
    w = tonumber(w) or 0
    if w < 0 then w = 0 end
    w = math.ceil(w + 2)
    cache[fontKey] = w
    return w
end
-- Approximate width for a "full HP" value text (secret-safe).
local function MSUF_GetApproxHpFullTextWidth(templateFS)
    if not templateFS or not templateFS.GetFont then
        return 0
    end
    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_HPFullWidthCache = _G.MSUF_HPFullWidthCache or {}
    local cache = _G.MSUF_HPFullWidthCache
    local cached = cache[fontKey]
    if cached then
        return cached
    end
    local fs = _G.MSUF_HPFullMeasureFS
    if not fs then
        local holder = F.CreateFrame("Frame", "MSUF_HPFullMeasureFrame", UIParent)
        holder:Hide()
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs:Hide()
        _G.MSUF_HPFullMeasureFS = fs
    end
    fs:SetFont(font, size, flags)
    -- (We avoid any secret arithmetic/string ops by using a constant.)
    fs:SetText("999.9M")
    local w = 0
    if fs.GetStringWidth then
        w = fs:GetStringWidth() or 0
    end
    w = tonumber(w) or 0
    if w < 0 then w = 0 end
    w = math.ceil(w + 2)
    cache[fontKey] = w
    return w
end
local MSUF_HP_SPACER_SCALE = 1.15
local MSUF_HP_SPACER_MAXCAP = 2000
function _G.MSUF_GetHPSpacerMaxForUnitKey(unitKey)
    EnsureDB()
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey)
    local frameName
    if k == "boss" then
        frameName = "MSUF_boss1"
    else
        frameName = "MSUF_" .. k
    end
    local f = _G[frameName]
    local tf = f and f.textFrame
    local w = 0
    if f and f.GetWidth then
        w = f:GetWidth() or 0
    elseif tf and tf.GetWidth then
        w = tf:GetWidth() or 0
    end
    w = tonumber(w) or 0
    if w <= 0 then
        local confFallback = MSUF_DB[k]
        w = tonumber(confFallback and confFallback.width) or tonumber(MSUF_DB.general and MSUF_DB.general.frameWidth) or 0
    end
    local conf = MSUF_DB[k] or {}
    local hX = ns.Util.Offset(conf.hpOffsetX, -4)
    local leftPad = 8
    local pctW = 0
    if f and f.hpTextPct then
        pctW = MSUF_GetApproxPercentTextWidth(f.hpTextPct)
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"
    local movingW = pctW
    if hpMode == "FULL_PLUS_PERCENT" then
        if f and f.hpText then
            movingW = MSUF_GetApproxHpFullTextWidth(f.hpText)
        elseif f and f.hpTextPct then
            movingW = MSUF_GetApproxHpFullTextWidth(f.hpTextPct)
        else
            movingW = 0
    end
    end
    local maxSpacer = (tonumber(w) or 0) + (tonumber(hX) or 0) - (leftPad + (tonumber(movingW) or 0))
    maxSpacer = tonumber(maxSpacer) or 0
    if maxSpacer < 0 then maxSpacer = 0 end
    maxSpacer = maxSpacer * MSUF_HP_SPACER_SCALE
    maxSpacer = math.floor(maxSpacer + 0.5)
    if maxSpacer > MSUF_HP_SPACER_MAXCAP then maxSpacer = MSUF_HP_SPACER_MAXCAP end
    return maxSpacer
end
local MSUF_POWER_SPACER_SCALE = 1.15
local MSUF_POWER_SPACER_MAXCAP = 2000
function _G.MSUF_GetPowerSpacerMaxForUnitKey(unitKey)
    EnsureDB()
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey)
    local frameName
    if k == "boss" then
        frameName = "MSUF_boss1"
    else
        frameName = "MSUF_" .. k
    end
    local f = _G[frameName]
    local tf = f and f.textFrame
    local w = 0
    if f and f.GetWidth then
        w = f:GetWidth() or 0
    elseif tf and tf.GetWidth then
        w = tf:GetWidth() or 0
    end
    w = tonumber(w) or 0
    if w <= 0 then
        local confFallback = MSUF_DB[k]
        w = tonumber(confFallback and confFallback.width) or tonumber(MSUF_DB.general and MSUF_DB.general.frameWidth) or 0
    end
    local conf = MSUF_DB[k] or {}
    local pX = ns.Util.Offset(conf.powerOffsetX, -4)
    local leftPad = 8
    local pctW = 0
    if f and f.powerTextPct then
        pctW = MSUF_GetApproxPercentTextWidth(f.powerTextPct)
    elseif f and f.powerText then
        pctW = MSUF_GetApproxPercentTextWidth(f.powerText)
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local pMode = g.powerTextMode or "FULL_PLUS_PERCENT"
    local movingW = pctW
    if pMode == "FULL_PLUS_PERCENT" then
        if f and f.powerText then
            movingW = MSUF_GetApproxHpFullTextWidth(f.powerText)
        elseif f and f.powerTextPct then
            movingW = MSUF_GetApproxHpFullTextWidth(f.powerTextPct)
        else
            movingW = 0
    end
    end
    local maxSpacer = (tonumber(w) or 0) + (tonumber(pX) or 0) - (leftPad + (tonumber(movingW) or 0))
    maxSpacer = tonumber(maxSpacer) or 0
    if maxSpacer < 0 then maxSpacer = 0 end
    maxSpacer = maxSpacer * MSUF_POWER_SPACER_SCALE
    maxSpacer = math.floor(maxSpacer + 0.5)
    if maxSpacer > MSUF_POWER_SPACER_MAXCAP then maxSpacer = MSUF_POWER_SPACER_MAXCAP end
    return maxSpacer
end
local MSUF_TEXT_LAYOUT_HP  = { full="hpText",    pct="hpTextPct",    point="TOPRIGHT",    relPoint="TOPRIGHT",
    xKey="hpOffsetX",    yKey="hpOffsetY",    defX=-4, defY=-4, spacerOn="hpTextSpacerEnabled",    spacerX="hpTextSpacerX",    maxFn=_G.MSUF_GetHPSpacerMaxForUnitKey,    limitMode=false }
local MSUF_TEXT_LAYOUT_PWR = { full="powerText", pct="powerTextPct", point="BOTTOMRIGHT", relPoint="BOTTOMRIGHT",
    xKey="powerOffsetX", yKey="powerOffsetY", defX=-4, defY= 4, spacerOn="powerTextSpacerEnabled", spacerX="powerTextSpacerX", maxFn=_G.MSUF_GetPowerSpacerMaxForUnitKey, limitMode=true }

local function MSUF_TextLayout_GetSpacer(key, udb, g, hasPct, spec)
    if not hasPct then return false, 0 end
    local on = ((udb and udb[spec.spacerOn] == true) or (not udb and g and g[spec.spacerOn] == true)) or false
    local x  = (udb and tonumber(udb[spec.spacerX])) or ((g and tonumber(g[spec.spacerX])) or 0)
    local max = (key and spec.maxFn and spec.maxFn(key)) or 0
    return on, ns.Text.ClampSpacerValue(x, max, on)
end

local function MSUF_TextLayout_ApplyGroup(f, tf, conf, spec, mode, hasPct, on, eff)
    local fullObj, pctObj = f[spec.full], f[spec.pct]
    if not (fullObj or hasPct) then return end
    local baseX = ns.Util.Offset(conf[spec.xKey], spec.defX)
    local baseY = ns.Util.Offset(conf[spec.yKey], spec.defY)
    local fullX, pctX = baseX, baseX
    local canSplit = hasPct and on and eff ~= 0 and (not spec.limitMode or mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL")
    if canSplit then if mode == "FULL_PLUS_PERCENT" then fullX = baseX - eff else pctX = baseX - eff end end
    if fullObj then MSUF_ApplyPoint(fullObj, spec.point, tf, spec.relPoint, fullX, baseY) end
    if hasPct  then MSUF_ApplyPoint(pctObj,  spec.point, tf, spec.relPoint, pctX,  baseY) end
end

local function ApplyTextLayout(f, conf)
    if not f or not f.textFrame or not conf then return end
    local tf = f.textFrame
    local nX = ns.Util.Offset(conf.nameOffsetX,  4)
    local nY = ns.Util.Offset(conf.nameOffsetY, -4)

    local key = f.msufConfigKey
    if not key and f.unit and GetConfigKeyForUnit then key = GetConfigKeyForUnit(f.unit) end
    local udb = (MSUF_DB and key and MSUF_DB[key]) or nil
    local g = (MSUF_DB and MSUF_DB.general) or nil

    local hpMode = (g and g.hpTextMode) or "FULL_PLUS_PERCENT"
    local pMode  = (g and g.powerTextMode) or "FULL_PLUS_PERCENT"

    local hpHasPct = (f[MSUF_TEXT_LAYOUT_HP.pct] ~= nil)
    local pHasPct  = (f[MSUF_TEXT_LAYOUT_PWR.pct] ~= nil)
    local hpOn, hpEff = MSUF_TextLayout_GetSpacer(key, udb, g, hpHasPct, MSUF_TEXT_LAYOUT_HP)
    local pOn,  pEff  = MSUF_TextLayout_GetSpacer(key, udb, g, pHasPct,  MSUF_TEXT_LAYOUT_PWR)

    local hX = ns.Util.Offset(conf.hpOffsetX,    -4)
    local hY = ns.Util.Offset(conf.hpOffsetY,    -4)
    local pX = ns.Util.Offset(conf.powerOffsetX, -4)
    local pY = ns.Util.Offset(conf.powerOffsetY,  4)

    local wUsed = (f and f.GetWidth and f:GetWidth()) or 0
    if (not wUsed or wUsed == 0) and tf and tf.GetWidth then wUsed = tf:GetWidth() or 0 end
    if (not wUsed or wUsed == 0) and conf then wUsed = tonumber(conf.width) or wUsed end
    wUsed = tonumber(wUsed) or 0

    if not ns.Cache.StampChanged(f, "TextLayout", tf, nX, nY, hX, hY, pX, pY, hpHasPct, hpOn, hpEff, wUsed, (key or ""), (hpMode or ""), pHasPct, pOn, pEff, (pMode or "")) then return end
    f._msufTextLayoutStamp = 1

    if f.nameText then
        MSUF_ApplyPoint(f.nameText, "TOPLEFT", tf, "TOPLEFT", nX, nY)
        f._msufNameAnchorPoint, f._msufNameAnchorRel, f._msufNameAnchorRelPoint, f._msufNameAnchorX, f._msufNameAnchorY = "TOPLEFT", tf, "TOPLEFT", nX, nY
        f._msufNameClipSideApplied, f._msufNameClipReservedRight, f._msufNameClipTextStamp, f._msufNameClipAnchorStamp, f._msufClampStamp = nil, nil, nil, nil, nil
    end
    if f.levelText and f.nameText then MSUF_ApplyLevelIndicatorLayout_Internal(f, conf) end

    -- HP group uses hpMode (shifts pct side for any non FULL_PLUS_PERCENT, matching legacy behavior).
    MSUF_TextLayout_ApplyGroup(f, tf, conf, MSUF_TEXT_LAYOUT_HP,  hpMode, hpHasPct, hpOn, hpEff)
    MSUF_TextLayout_ApplyGroup(f, tf, conf, MSUF_TEXT_LAYOUT_PWR, pMode,  pHasPct,  pOn,  pEff)
end

function _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey)
    local function ApplyForFrame(f)
        if not f then return end
        f._msufTextLayoutStamp = nil
        ns.Cache.ClearStamp(f, "TextLayout")
        local key = f.msufConfigKey
        if not key and f.unit and type(GetConfigKeyForUnit) == "function" then
            key = GetConfigKeyForUnit(f.unit)
            f.msufConfigKey = key
    end
        local conf = f.cachedConfig
        if (not conf) and key and MSUF_DB then
            conf = MSUF_DB[key]
            f.cachedConfig = conf
    end
        if (not conf) and MSUF_DB and k and MSUF_DB[k] then
            conf = MSUF_DB[k]
            f.cachedConfig = conf
    end
        if not conf then return end
        if type(ApplyTextLayout) == "function" then
            ApplyTextLayout(f, conf)
    end
            MSUF_ClampNameWidth(f, conf)
        -- IMPORTANT: Spacer changes do not necessarily trigger a UNIT_HEALTH event.
        if conf.showHP ~= nil then
            f.showHPText = (conf.showHP ~= false)
    end
        local unit = f.unit
        local hasUnit = false
        if unit and F.UnitExists then
            local okExists, exists = MSUF_FastCall(F.UnitExists, unit)
            hasUnit = okExists and exists
    end
        if hasUnit and F.UnitHealth then
            local okHp, hp = MSUF_FastCall(F.UnitHealth, unit)
            if okHp then
                f._msufLastHpValue = nil
                _G.MSUF_UFCore_UpdateHpTextFast(f, hp)
            end
            if conf.showPower ~= nil then
                f.showPowerText = (conf.showPower ~= false)
            end
                _G.MSUF_UFCore_UpdatePowerTextFast(f, unit)
        else
            if not (F.InCombatLockdown and F.InCombatLockdown()) and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
                if f.isBoss and MSUF_BossTestMode then
                    _G.MSUF_ApplyBossTestHpPreviewText(f, conf)
                else
                    f._msufLastHpValue = nil
                    ns.UF.RequestUpdate(f, true, false, "HPSpacer")
                end
            elseif f.isBoss and MSUF_BossTestMode then
                _G.MSUF_ApplyBossTestHpPreviewText(f, conf)
            end
    end
    end
    if k == "boss" then
        for i = 1, 5 do
            ApplyForFrame(_G["MSUF_boss" .. i])
    end
    else
        ApplyForFrame(_G["MSUF_" .. k])
    end
end
function MSUF_UpdateBossPortraitLayout(f, conf)
    if not f or not f.portrait or not conf then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, h - 4)
    local portrait = f.portrait
    portrait:ClearAllPoints()
    portrait:SetSize(size, size)
    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then
        anchor = f
    end
    if mode == "LEFT" then
        portrait:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        portrait:Show()
    elseif mode == "RIGHT" then
        portrait:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
        portrait:Show()
    else
        portrait:Hide()
    end
end
local MSUF_PORTRAIT_MIN_INTERVAL = 0.06 -- seconds; small enough to feel instant
local MSUF_PORTRAIT_BUDGET_USED = false
local MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
local function MSUF_ResetPortraitBudgetNextFrame()
    if MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED then return end
    MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = true
    C_Timer.After(0, function()
        MSUF_PORTRAIT_BUDGET_USED = false
        MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
    end)
end
local function MSUF_ApplyPortraitLayoutIfNeeded(f, conf)
    if not f or not conf then return end
    local portrait = f.portrait
    if not portrait then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    if ns.Cache.StampChanged(f, "PortraitLayout", mode, h) then
        f._msufPortraitLayoutStamp = 1
        MSUF_UpdateBossPortraitLayout(f, conf)
    end
end

local function MSUF_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end
    local mode = conf.portraitMode or "OFF"
    if f._msufPortraitModeStamp ~= mode then
        f._msufPortraitModeStamp = mode
        if mode ~= "OFF" then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
    end
    end
    if mode == "OFF" or not existsForPortrait then
        f.portrait:Hide()
        return
    end
    MSUF_ApplyPortraitLayoutIfNeeded(f, conf)
    if f._msufPortraitDirty then
        local now = (F.GetTime and F.GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        if (now >= nextAt) and (not MSUF_PORTRAIT_BUDGET_USED) then
            if SetPortraitTexture then
                SetPortraitTexture(f.portrait, unit)
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + MSUF_PORTRAIT_MIN_INTERVAL
            MSUF_PORTRAIT_BUDGET_USED = true
            MSUF_ResetPortraitBudgetNextFrame()
        else
            if not f._msufPortraitRetryScheduled and C_Timer and C_Timer.After then
                f._msufPortraitRetryScheduled = true
                local delay = 0
                if now < nextAt then
                    delay = nextAt - now
                    if delay < 0 then delay = 0 end
                end
                C_Timer.After(delay, function()
                    if not f then return end
                    f._msufPortraitRetryScheduled = nil
                    if not f._msufPortraitDirty then return end
                    ns.UF.RequestUpdate(f, false, false, "PortraitRetry")
                end)
            end
            MSUF_ResetPortraitBudgetNextFrame()
    end
    end
    f.portrait:Show()
end
-- then multiplies by maxChars to get a clip width. Never measures secret unit names. to get a clip width. Never measures secret unit names.
local function MSUF_GetApproxNameWidthForChars(templateFS, maxChars)
    if not templateFS or not templateFS.GetFont then return nil end
    maxChars = tonumber(maxChars) or 16
    if maxChars < 1 then maxChars = 1 end
    if maxChars > 60 then maxChars = 60 end
    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_NameWidthAvgCache = _G.MSUF_NameWidthAvgCache or {}
    local cache = _G.MSUF_NameWidthAvgCache
    local avg = cache[fontKey]
    if not avg then
        local fs = _G.MSUF_NameMeasureFS
        if not fs then
            local holder = F.CreateFrame("Frame", "MSUF_NameMeasureFrame", UIParent)
            holder:Hide()
            fs = holder:CreateFontString(nil, "OVERLAY")
            fs:Hide()
            _G.MSUF_NameMeasureFS = fs
    end
        if font and size then
            fs:SetFont(font, size, flags)
    end
        local sample = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        fs:SetText(sample)
        local w = fs:GetStringWidth()
        if type(w) == "number" and w > 0 then
            avg = w / #sample
        else
            avg = (tonumber(size) or 12) * 0.55
    end
        cache[fontKey] = avg
    end
    return avg * maxChars
end
function MSUF_ClampNameWidth(f, conf)
    if not f or not f.nameText then return end
    f.nameText:SetWordWrap(false)
    if f.nameText.SetNonSpaceWrap then
        f.nameText:SetNonSpaceWrap(false)
    end
    local shorten = (MSUF_DB and MSUF_DB.shortenNames) and true or false
    local unitKey = f and (f.unitKey or f.unit or f.msufConfigKey)
    if unitKey == "player" or unitKey == "Player" or unitKey == "PLAYER" then
        shorten = false
    end
    if not shorten then
        local tf = f.textFrame or f
        local ap  = f._msufNameAnchorPoint or "TOPLEFT"
        local rel = f._msufNameAnchorRel or tf
        local arp = f._msufNameAnchorRelPoint or "TOPLEFT"
        local ax  = (type(f._msufNameAnchorX) == "number") and f._msufNameAnchorX or 4
        local ay  = (type(f._msufNameAnchorY) == "number") and f._msufNameAnchorY or -4
        local stamp = "OFF|"..tostring(ap).."|"..tostring(arp).."|"..tostring(ax).."|"..tostring(ay)
        if f._msufClampStamp == stamp then
            return
    end
        f._msufClampStamp = stamp
        if f._msufNameClipAnchorMode ~= nil then
            f.nameText:ClearAllPoints()
            f.nameText:SetPoint(ap, rel, arp, ax, ay)
            f._msufNameClipAnchorMode = nil
            f._msufNameClipSideApplied = nil
            f._msufNameClipAnchorX = nil
            f._msufNameClipAnchorY = nil
    end
        if f.nameText.SetJustifyH then
            f.nameText:SetJustifyH("LEFT")
    end
        if f._msufNameClipFrame then
            local clip = f._msufNameClipFrame
            if clip.Hide then clip:Hide() end
            if f.nameText and f.nameText.GetParent and f.nameText:GetParent() == clip then
                local p = f._msufNameTextOrigParent or (f.textFrame or f)
                f.nameText:SetParent(p)
            end
    end
        f._msufNameClipAnchorStamp = nil
        f._msufNameClipTextStamp = nil
        if f._msufNameDotsFS then
            if f._msufNameDotsFS.Hide then f._msufNameDotsFS:Hide() end
    end
        f.nameText:SetWidth(0)
        return
    end
    -- Secret-safe: avoid measuring real (secret) unit names. We only compute a pixel clamp width.
    local frameWidth = 0
    if conf and type(conf.width) == "number" then
        frameWidth = conf.width
    elseif type(f._msufW) == "number" then
        frameWidth = f._msufW
    elseif f.GetWidth then
        local w = f:GetWidth()
        if type(w) == "number" then
            frameWidth = w
    end
    end
    if frameWidth <= 0 then
        frameWidth = 220
    end
    -- Hard cap budget: ~80% of frame width (still secret-safe and prevents overlaps)
    local baseWidth = math.floor((frameWidth * 0.80) + 0.5)
    if baseWidth < 80 then baseWidth = 80 end
    -- Fixed reservations (secret-safe; never derived from unit names)
    local reservedRight = 0
    local lvlShown = false
    local lvlAnchor = f._msufLevelAnchor or "NAMERIGHT"
    if lvlAnchor == "NAMERIGHT" and f.levelText and f.levelText.IsShown and f.levelText:IsShown() then
        reservedRight = reservedRight + 26
        lvlShown = true
    end
    local nameWidth = baseWidth - reservedRight
    if nameWidth < 40 then nameWidth = 40 end
    local maxChars = 16
    local g = MSUF_DB and MSUF_DB.general
    if g and type(g.shortenNameMaxChars) == "number" then
        maxChars = g.shortenNameMaxChars
    end
    if maxChars < 4 then maxChars = 4 end
    if maxChars > 40 then maxChars = 40 end
    if MSUF_GetApproxNameWidthForChars then
        local approx = MSUF_GetApproxNameWidthForChars(f.nameText, maxChars)
        if type(approx) == "number" and approx > 0 then
            local w = math.floor(approx + 0.5) - reservedRight
            if w < nameWidth then
                nameWidth = w
                if nameWidth < 40 then nameWidth = 40 end
            end
    end
    end
    -- Name shortening mode (secret-safe).
    local mode = (g and g.shortenNameClipSide) or "LEFT"
    if mode ~= "LEFT" and mode ~= "RIGHT" then
        mode = "LEFT"
    end
    local legacyEndClip = (mode == "RIGHT")
    local clipSide = "LEFT"
    local maskPx = 0
    if not legacyEndClip then
        if g and g.shortenNameFrontMaskPx ~= nil then
            maskPx = tonumber(g.shortenNameFrontMaskPx) or 0
    end
        maskPx = math.floor(maskPx + 0.5)
        if maskPx < 0 then maskPx = 0 end
        if maskPx > 80 then maskPx = 80 end
    end
    local showDots = true
    if g and g.shortenNameShowDots ~= nil then
        showDots = (g.shortenNameShowDots and true or false)
    end
    if legacyEndClip then
        showDots = false
    end
    local tf = f.textFrame or f
    local ap  = f._msufNameAnchorPoint or "TOPLEFT"
    local rel = f._msufNameAnchorRel or tf
    local arp = f._msufNameAnchorRelPoint or "TOPLEFT"
    local ax  = (type(f._msufNameAnchorX) == "number") and f._msufNameAnchorX or 4
    local ay  = (type(f._msufNameAnchorY) == "number") and f._msufNameAnchorY or -4
    local stamp = "ON|"..tostring(frameWidth).."|"..tostring(baseWidth).."|"..tostring(reservedRight).."|"..tostring(nameWidth).."|"..tostring(maxChars).."|"..tostring(lvlShown and 1 or 0).."|"..tostring(ap).."|"..tostring(arp).."|"..tostring(ax).."|"..tostring(ay).."|"..tostring(mode).."|"..tostring(maskPx).."|"..tostring(showDots and 1 or 0)
    if f._msufClampStamp == stamp then
        return
    end
    f._msufClampStamp = stamp
    if legacyEndClip then
        if f._msufNameClipFrame then
            local clip = f._msufNameClipFrame
            if clip.Hide then clip:Hide() end
            if f.nameText and f.nameText.GetParent and f.nameText:GetParent() == clip then
                local p = f._msufNameTextOrigParent or (f.textFrame or f)
                f.nameText:SetParent(p)
            end
    end
        if f._msufNameDotsFS then
            if f._msufNameDotsFS.Hide then f._msufNameDotsFS:Hide() end
    end
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint(ap, rel, arp, ax, ay)
        f._msufNameClipAnchorStamp = nil
        f._msufNameClipTextStamp = nil
        if f.nameText.SetJustifyH then
            f.nameText:SetJustifyH("LEFT")
    end
        f.nameText:SetWidth(nameWidth)
        f._msufNameClipSideApplied = "RIGHT"
        return
    end
    local clipW = nameWidth - maskPx
    if clipW < 10 then clipW = 10 end
    local clip = f._msufNameClipFrame
    if not clip then
        clip = F.CreateFrame("Frame", nil, tf)
        clip:SetClipsChildren(true)
        clip:Show()
        f._msufNameClipFrame = clip
        if not f._msufNameTextOrigParent then
            f._msufNameTextOrigParent = f.nameText:GetParent()
    end
        if tf and tf.GetFrameStrata then
            clip:SetFrameStrata(tf:GetFrameStrata())
    end
        if tf and tf.GetFrameLevel then
            clip:SetFrameLevel(tf:GetFrameLevel() + 1)
    end
    else
        if clip.GetParent and clip:GetParent() ~= tf then
            clip:SetParent(tf)
    end
        clip:Show()
    end
    if f.nameText:GetParent() ~= clip then
        if not f._msufNameTextOrigParent then
            f._msufNameTextOrigParent = tf
    end
        f.nameText:SetParent(clip)
    end
    local fontH = 0
    if f.nameText.GetFont then
        local _, sz = f.nameText:GetFont()
        if type(sz) == "number" then
            fontH = sz
    end
    end
    local clipH = math.floor(((fontH > 0 and fontH or 12) * 1.6) + 0.5)
    if conf and type(conf.height) == "number" then
        local hh = math.floor((conf.height * 0.80) + 0.5)
        if hh > clipH then
            clipH = hh
    end
    end
    if clipH < 12 then clipH = 12 end
    if clipH > 48 then clipH = 48 end
    clip:SetSize(clipW, clipH)
    local anchorStamp = tostring(ap) .. "|" .. tostring(arp) .. "|" .. tostring(ax) .. "|" .. tostring(ay)
        .. "|" .. tostring(clipSide) .. "|" .. tostring(maskPx) .. "|" .. tostring(clipW) .. "|" .. tostring(clipH)
    if f._msufNameClipAnchorStamp ~= anchorStamp then
        f._msufNameClipAnchorStamp = anchorStamp
        clip:ClearAllPoints()
        if clipSide == "LEFT" and ap == "TOPLEFT" and arp == "TOPLEFT" then
            clip:SetPoint("TOPRIGHT", rel, "TOPLEFT", ax + nameWidth, ay)
        elseif clipSide == "RIGHT" and ap == "TOPLEFT" and arp == "TOPLEFT" then
            clip:SetPoint("TOPLEFT", rel, "TOPLEFT", ax, ay)
        else
            clip:SetPoint(ap, rel, arp, ax, ay)
    end
    end
    -- IMPORTANT: this must be resilient against other code (e.g. font/apply passes) resetting justify/anchors.
    local textStamp = tostring(clipSide)
    local desiredJustify = (clipSide == "LEFT") and "RIGHT" or "LEFT"
    local needTextReanchor = (f._msufNameClipTextStamp ~= textStamp)
    if not needTextReanchor then
        if f.nameText and f.nameText.GetParent and f.nameText:GetParent() ~= clip then
            needTextReanchor = true
        elseif f.nameText and f.nameText.GetJustifyH and f.nameText:GetJustifyH() ~= desiredJustify then
            needTextReanchor = true
    end
    end
    if needTextReanchor then
        f._msufNameClipTextStamp = textStamp
        f.nameText:ClearAllPoints()
        if clipSide == "LEFT" then
            f.nameText:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        else
            f.nameText:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    end
        if f.nameText and f.nameText.SetJustifyH then
            f.nameText:SetJustifyH(desiredJustify)
    end
        if f.nameText and f.nameText.SetParent then
            f.nameText:SetParent(clip)
    end
    end
    -- Optional ellipsis/dots indicator (secret-safe: never inspects the actual name text)
    if showDots and maskPx > 0 then
        local dots = f._msufNameDotsFS
        if not dots then
	            -- IMPORTANT: FontStrings without a template may have no font assigned.
	            dots = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	            if f.nameText and f.nameText.GetFont and dots and dots.SetFont then
	                local ff, sz, fl = f.nameText:GetFont()
	                if ff and sz then
	                    dots:SetFont(ff, sz, fl)
	                end
	            end
	            if dots and dots.GetFont and dots.SetFontObject then
	                local ff = dots:GetFont()
	                if not ff and GameFontNormalSmall then
	                    dots:SetFontObject(GameFontNormalSmall)
	                end
	            end
	            dots:SetText("...")
            dots:Hide()
            f._msufNameDotsFS = dots
            if tf and tf.GetFrameLevel then
                dots:SetDrawLayer("OVERLAY", 7)
            end
    end
        if f.nameText and f.nameText.GetFont and dots.SetFont then
            local ff, sz, fl = f.nameText:GetFont()
            if ff and sz then
                dots:SetFont(ff, sz, fl)
            end
    end
        local dotStamp = tostring(clipSide) .. "|" .. tostring(maskPx) .. "|" .. tostring(ap) .. "|" .. tostring(arp) .. "|" .. tostring(ax) .. "|" .. tostring(ay) .. "|" .. tostring(nameWidth)
        if f._msufNameDotsStamp ~= dotStamp then
            f._msufNameDotsStamp = dotStamp
            dots:ClearAllPoints()
            if clipSide == "LEFT" then
                dots:SetPoint("TOPLEFT", clip, "TOPLEFT", -maskPx, 0)
            else
                dots:SetPoint("TOPRIGHT", clip, "TOPRIGHT", maskPx, 0)
            end
    end
        dots:Show()
    else
        if f._msufNameDotsFS then
            f._msufNameDotsFS:Hide()
    end
    end
    f.nameText:SetWidth(0)
    f._msufNameClipSideApplied = clipSide
end
local function MSUF_GetUnitLevelText(unit)
    if not unit or not UnitLevel then return "" end
    local lvl = UnitLevel(unit)
    if not lvl then return "" end
    if lvl == -1 then
        return "??"
    end
    if lvl <= 0 then
        return ""
    end
    return tostring(lvl)
end

-- Export for legacy paths (some earlier helpers reference this as a global).
-- Keeping this avoids blank/missing level text when a legacy full update runs.
_G.MSUF_GetUnitLevelText = MSUF_GetUnitLevelText

local function MSUF_GetUnitHealthPercent(unit)
    if type(UnitHealthPercent) == "function" then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            -- Secret-safe + snappy: usePredicted=true (avoid Lua arithmetic on secret values)
            ok, pct = MSUF_FastCall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        else
            ok, pct = MSUF_FastCall(UnitHealthPercent, unit, true, true)
    end
        -- Secret-safe: avoid comparing returned values in Lua (pct may be a "secret" number).
        if ok then
            return pct
    end
        return nil
    end
    -- 12.0+: If UnitHealthPercent is unavailable, avoid computing percent in Lua (secret-safe).
    return nil
end
local function MSUF_NumberToTextFast(v)
    if type(v) ~= "number" then
        return nil
    end
    -- Prefer Blizzard/C-side abbreviators (K/M/B). Treat returned text as opaque (secret-safe).
    local abbr = _G.ShortenNumber or _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers
    if abbr then
        local ok, s = MSUF_FastCall(abbr, v)
        if ok then
            return s
    end
    end
    return tostring(v)
end
ns.Icons._layout = ns.Icons._layout or {}
function ns.Icons._layout.GetConf(f)
    if (not MSUF_DB) and type(EnsureDB) == "function" then EnsureDB() end
    local db = MSUF_DB
    if not db then return nil, nil, nil end
    local g = db.general or {}
    local key = (f and f.unit and type(GetConfigKeyForUnit) == "function") and GetConfigKeyForUnit(f.unit) or nil
    return g, key, (key and db[key]) or nil
end
function ns.Icons._layout.Resolve(anchor, allowCenter)
    if allowCenter and anchor == "CENTER" then return "CENTER", "CENTER"
    elseif anchor == "TOPRIGHT" then return "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then return "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then return "RIGHT", "BOTTOMRIGHT" end
    return "LEFT", "TOPLEFT"
end
function ns.Icons._layout.Apply(icon, owner, size, point, relPoint, ox, oy)
    icon:SetSize(size, size); icon:ClearAllPoints(); icon:SetPoint(point, owner, relPoint, ox, oy)
end
function MSUF_ApplyLeaderIconLayout(f)
    if not f or not f.leaderIcon then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end
    local size = ns.Util.Num(conf, g, "leaderIconSize", 14)
size = math.floor(size + 0.5); if size < 8 then size = 8 elseif size > 64 then size = 64 end
local ox = ns.Util.Num(conf, g, "leaderIconOffsetX", 0)
local oy = ns.Util.Num(conf, g, "leaderIconOffsetY", 3)
local anchor = ns.Util.Val(conf, g, "leaderIconAnchor", "TOPLEFT")
    if not ns.Cache.StampChanged(f, "LeaderIconLayout", size, ox, oy, anchor, (key or "")) then return end
f._msufLeaderIconLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, false)
    ns.Icons._layout.Apply(f.leaderIcon, f, size, point, relPoint, ox, oy)
    if f.assistantIcon then
        ns.Icons._layout.Apply(f.assistantIcon, f, size, point, relPoint, ox, oy - (size - 1))
    end
end
function MSUF_ApplyRaidMarkerLayout(f)
    if not f or not f.raidMarkerIcon then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end
    if g.raidMarkerSize == nil then g.raidMarkerSize = 14 end
    local size = ns.Util.Num(conf, g, "raidMarkerSize", 14)
size = math.floor(size + 0.5); if size < 8 then size = 8 elseif size > 64 then size = 64 end
local ox = ns.Util.Num(conf, g, "raidMarkerOffsetX", 16)
local oy = ns.Util.Num(conf, g, "raidMarkerOffsetY", 3)
local anchor = ns.Util.Val(conf, g, "raidMarkerAnchor", "TOPLEFT")
    if not ns.Cache.StampChanged(f, "RaidMarkerLayout", size, ox, oy, anchor, (key or "")) then return end
f._msufRaidMarkerLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, true)
    ns.Icons._layout.Apply(f.raidMarkerIcon, f, size, point, relPoint, ox, oy)
end
function _G.MSUF_UFCore_UpdateHealthFast(self)
    if not self then return nil, nil, false end
    return ns.Bars.ApplySpec(self, self.unit, "health")
end
function _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    if not self or not self.unit or not self.hpText then return end
    local unit = self.unit
    local conf = self.cachedConfig
    if self.showHPText == false or hp == nil then
        ns.Text.RenderHpMode(self, false)
        return
    end
    local hpStr = MSUF_NumberToTextFast(hp)
    local hpPct = MSUF_GetUnitHealthPercent(unit)
    local hasPct = (type(hpPct) == "number")
    local g = MSUF_DB.general or {}
    local absorbText, absorbStyle = nil, nil
    if g.showTotalAbsorbAmount and UnitGetTotalAbsorbs then
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            local ok, txt = MSUF_FastCall(function()
                return C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(unit))
            end)
            if ok and txt then
                absorbText = txt
                absorbStyle = "SPACE"
            end
        else
            -- Secret-safe fallback: only pass through text (no comparisons or formatting ops).
            local absorbValue = UnitGetTotalAbsorbs(unit)
            if absorbValue ~= nil then
                local abbr = _G.AbbreviateLargeNumbers or _G.ShortenNumber or _G.AbbreviateNumbers
                if abbr then
                    local ok, txt = MSUF_FastCall(abbr, absorbValue)
                    if ok and txt then
                        absorbText = txt
                        absorbStyle = "PAREN"
                    end
                else
                    local ok, txt = MSUF_FastCall(tostring, absorbValue)
                    if ok and txt then
                        absorbText = txt
                        absorbStyle = "PAREN"
                    end
                end
            end
    end
    end
    ns.Text.RenderHpMode(self, true, hpStr, hpPct, hasPct, conf, g, absorbText, absorbStyle)
end

function _G.MSUF_ApplyBossTestHpPreviewText(self, conf)
    if not self or not self.hpText then return end
    local show = (self.showHPText ~= false)
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hpStr = MSUF_NumberToTextFast(750000)
    local hpPct = 75.0
    ns.Text.RenderHpMode(self, show, hpStr, hpPct, true, conf, g)
end

function _G.MSUF_UFCore_UpdatePowerTextFast(self)
    return ns.Text.RenderPowerText(self)
end

function _G.MSUF_UFCore_UpdatePowerBarFast(self)
    if not self then return end
    ns.Bars.ApplySpec(self, self.unit, "power_abs")
end
local function MSUF_ClearUnitFrameState(self, clearAbsorbs)
    ns.Bars.ResetHealthAndOverlays(self, clearAbsorbs)
    if self.nameText then self.nameText:SetText("") end
    MSUF_ClearText(self.levelText, true)
    if self.hpText then self.hpText:SetText("") end
    ns.Text.ClearField(self, "hpTextPct")
    MSUF_ClearText(self.powerText, true)
    ns.Text.ClearField(self, "powerTextPct")
end
local function MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus)
    if not self then return false end
    MSUF_EnsureUnitFlags(self)
    return ns.Bars.ApplySpec(self, unit, "power_pct", barsConf, self.isBoss, isPlayer, isTarget, isFocus) and true or false
end
local function MSUF_UFStep_BasicHealth(self, unit)
    local hp = ns.Bars.ApplyHealthBars(self, unit)
    return hp
end
local function MSUF_UFStep_HeavyVisual(self, unit, key)
        local doHeavyVisual = true
        local forceHeavy = false
        local tokenFlags = _G.MSUF_UnitTokenChanged
        if tokenFlags and key and tokenFlags[key] then
            tokenFlags[key] = nil
            forceHeavy = true
    end
        local now = F.GetTime()
        if not forceHeavy then
            local nextAt = self._msufHeavyVisualNextAt or 0
            if now < nextAt then
                doHeavyVisual = false
            else
                self._msufHeavyVisualNextAt = now + 0.15 -- ~6-7 Hz (rare/heavy visuals)
            end
        else
            self._msufHeavyVisualNextAt = now
    end
        if doHeavyVisual then
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
            mode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end
        local darkR, darkG, darkB = 0, 0, 0
        local _gray = g.darkBarGray
        if type(_gray) == "number" then
            if _gray < 0 then _gray = 0 end
            if _gray > 1 then _gray = 1 end
            darkR, darkG, darkB = _gray, _gray, _gray
        else
            local toneKey = g.darkBarTone or "black"
            local tone = MSUF_DARK_TONES and MSUF_DARK_TONES[toneKey]
            if tone then
                darkR, darkG, darkB = tone[1], tone[2], tone[3]
            end
    end
        local barR, barG, barB
        if mode == "dark" then
            barR, barG, barB = darkR, darkG, darkB
        elseif mode == "unified" then
            local ur, ug, ub = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
            if type(ur) ~= "number" then ur = 0.10 end
            if type(ug) ~= "number" then ug = 0.60 end
            if type(ub) ~= "number" then ub = 0.90 end
            if ur < 0 then ur = 0 elseif ur > 1 then ur = 1 end
            if ug < 0 then ug = 0 elseif ug > 1 then ug = 1 end
            if ub < 0 then ub = 0 elseif ub > 1 then ub = 1 end
            barR, barG, barB = ur, ug, ub
        else
            local isPlayerUnit = F.UnitIsPlayer(unit)
            if isPlayerUnit then
                local _, class = F.UnitClass(unit)
                barR, barG, barB = MSUF_GetClassBarColor(class)
            else
                if F.UnitIsDeadOrGhost(unit) then
                    barR, barG, barB = MSUF_GetNPCReactionColor("dead")
                else
                    local reaction = F.UnitReaction("player", unit)
                    if reaction and reaction >= 5 then
                        barR, barG, barB = MSUF_GetNPCReactionColor("friendly")
                    elseif reaction == 4 then
                        barR, barG, barB = MSUF_GetNPCReactionColor("neutral")
                    else
                        barR, barG, barB = MSUF_GetNPCReactionColor("enemy")
                    end
                end
            end
    end
        if mode == "class" and self._msufIsPet then
            local pr, pg, pb = g.petFrameColorR, g.petFrameColorG, g.petFrameColorB
            if type(pr) == "number" and type(pg) == "number" and type(pb) == "number" then
                if pr < 0 then pr = 0 elseif pr > 1 then pr = 1 end
                if pg < 0 then pg = 0 elseif pg > 1 then pg = 1 end
                if pb < 0 then pb = 0 elseif pb > 1 then pb = 1 end
                barR, barG, barB = pr, pg, pb
            end
    end
        self.hpBar:SetStatusBarColor(barR, barG, barB, 1)
        if self.hpGradients then
            MSUF_ApplyHPGradient(self)
        elseif self.hpGradient then
            MSUF_ApplyHPGradient(self.hpGradient)
    end
        if self.bg then
            MSUF_ApplyBarBackgroundVisual(self)
    end
    end
end
local function MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus)
  local pb = self.targetPowerBar or self.powerBar
  if not (pb and pb.IsShown and pb:IsShown()) then return false end
  local flag = (self.isBoss and "showBossPowerBar")
            or (isPlayer and "showPlayerPowerBar")
            or (isTarget and "showTargetPowerBar")
            or (isFocus and "showFocusPowerBar")
  if flag and barsConf and barsConf[flag] == false then return false end
  if MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus) then return true end
  return false
end
local function MSUF_UFStep_Border(self)
        do
            if self.border then
                self.border:Hide()
            end
            local thickness, stamp = MSUF_GetDesiredBarBorderThicknessAndStamp()
            local pb = self.targetPowerBar
            local bottomIsPower = (pb and pb.IsShown and pb:IsShown()) and true or false
            local need = false
            if self._msufBarBorderStamp ~= stamp then
                self._msufBarBorderStamp = stamp
                need = true
            end
            if self._msufBarOutlineThickness ~= thickness then
                need = true
            end
            if self._msufBarOutlineBottomIsPower ~= bottomIsPower then
                need = true
            end
            if need and type(_G.MSUF_QueueUnitframeVisual) == "function" then
                _G.MSUF_QueueUnitframeVisual(self)
            end
    end
end
local function MSUF_UFStep_NameLevelLeaderRaid(self, unit, conf, g)
    ns.Text.ApplyName(self, unit)
    ns.Text.ApplyLevel(self, unit, conf)
        MSUF_UpdateNameColor(self)

if self.leaderIcon then
    if not ns.Util.Enabled(conf, g, "showLeaderIcon", true) then
        ns.Util.SetShown(self.leaderIcon, false)
    else
        -- NOTE: use escaped backslashes in lua strings (otherwise the path becomes invalid).
        local tex = (UnitIsGroupLeader and UnitIsGroupLeader(unit) and "Interface\\GroupFrame\\UI-Group-LeaderIcon")
            or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit) and "Interface\\GroupFrame\\UI-Group-AssistantIcon")
        if tex and self.leaderIcon.SetTexture then self.leaderIcon:SetTexture(tex); ns.Util.SetShown(self.leaderIcon, true) else ns.Util.SetShown(self.leaderIcon, false) end
    end
end
if self.leaderIcon and _G.MSUF_ApplyLeaderIconLayout then _G.MSUF_ApplyLeaderIconLayout(self) end
if self.raidMarkerIcon then
    if not ns.Util.Enabled(conf, g, "showRaidMarker", true) then
        ns.Util.SetShown(self.raidMarkerIcon, false)
    else
        local idx = (GetRaidTargetIndex and GetRaidTargetIndex(unit)) or nil
        -- Midnight/Beta can return idx as a "secret value"; never compare / do math on it.
        if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode() then idx = idx or 8 end
        if idx and SetRaidTargetIconTexture then SetRaidTargetIconTexture(self.raidMarkerIcon, idx); ns.Util.SetShown(self.raidMarkerIcon, true) else ns.Util.SetShown(self.raidMarkerIcon, false) end
    end
end
if self.raidMarkerIcon and _G.MSUF_ApplyRaidMarkerLayout then _G.MSUF_ApplyRaidMarkerLayout(self) end
end
local function MSUF_UFStep_Finalize(self, hp, didPowerBarSync)
    _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    _G.MSUF_UFCore_UpdatePowerTextFast(self)
    if not didPowerBarSync then
        _G.MSUF_UFCore_UpdatePowerBarFast(self)
    end
    MSUF_UpdateStatusIndicatorForFrame(self)
end
function UpdateSimpleUnitFrame(self)
	    if (not MSUF_DB) and type(EnsureDB) == "function" then
	        EnsureDB()
	    end
	    local db = MSUF_DB
	    local g = (db and db.general) or {}
	    local barsConf = (db and db.bars) or {}
    local unit   = self.unit
    MSUF_EnsureUnitFlags(self)
    local isPlayer = self._msufIsPlayer
    local isTarget = self._msufIsTarget
    local isFocus  = self._msufIsFocus
    local isPet    = self._msufIsPet
    local isToT    = self._msufIsToT
    local unitValid = (type(unit) == "string" and unit ~= "") and true or false
    local exists = (unitValid and F.UnitExists and F.UnitExists(unit)) and true or false
local key, conf = ns.UF.ResolveKeyAndConf(self, unit, db)
if ns.UF.HandleDisabledFrame(self, conf) then
    return
end
if conf then
    local sn = (conf.showName  ~= false)
    local sh = (conf.showHP    ~= false)
    local sp = (conf.showPower ~= false)
    self.showName      = sn
    self.showHPText    = sh
    self.showPowerText = sp
end
        if self.portrait then
    if exists then
        if not self._msufHadUnit then
            self._msufHadUnit = true
            self._msufPortraitDirty = true
            self._msufPortraitNextAt = 0
    end
    else
        if self._msufHadUnit then
            self._msufHadUnit = nil
            self._msufPortraitDirty = true
            self._msufPortraitNextAt = 0
    end
    end
end
    local didPowerBarSync = false
    if self.isBoss and MSUF_BossTestMode then
        if not F.InCombatLockdown() then
            self:Show()
            _G.MSUF_ApplyUnitAlpha(self, key)
    end
    if self.bg then
        MSUF_ApplyBarBackgroundVisual(self)
    end
               if self.targetPowerBar then
            if (barsConf.showBossPowerBar == false) then
                self.targetPowerBar:SetScript("OnUpdate", nil)
                self.targetPowerBar:Hide()
                MSUF_ResetBarZero(self.targetPowerBar, true)
            else
                self.targetPowerBar:SetMinMaxValues(0, 100)
                MSUF_SetBarValue(self.targetPowerBar, 40, false)
                self.targetPowerBar.MSUF_lastValue = 40
                do
                    local tok = "MANA"
                    local pr, pg, pb = MSUF_GetPowerBarColor(nil, tok)
                    if not pr then pr, pg, pb = 0.6, 0.2, 1.0 end
                    self.targetPowerBar:SetStatusBarColor(pr, pg, pb)
                    ns.Bars.ApplyPowerGradientOnce(self)
                end
                self.targetPowerBar:Show()
            end
    end
        ns.Text.ApplyBossTestName(self, unit)
        ns.Text.ApplyBossTestLevel(self, conf)
        if self.hpText then
    local show = (self.showHPText ~= false)
    if show then
        _G.MSUF_ApplyBossTestHpPreviewText(self, conf)
    else
        MSUF_SetTextIfChanged(self.hpText, "")
    ns.Text.ClearField(self, "hpTextPct")
    end
    ns.Util.SetShown(self.hpText, show)
end
if self.powerText then
            local showPower = self.showPowerText
            if showPower == nil then
                showPower = true
            end
            if showPower then
                MSUF_SetTextIfChanged(self.powerText, "40 / 100")
            else
                MSUF_SetTextIfChanged(self.powerText, "")
            end
            ns.Util.SetShown(self.powerText, showPower)
    end
        return
    end
if self.isBoss then
    if not exists then
        if self._msufNoUnitCleared and (self.GetAlpha and self:GetAlpha() or 0) <= 0.01 then
            return
    end
        self:SetAlpha(0)
        MSUF_ClearUnitFrameState(self, false)
        if self.portrait then
            self.portrait:Hide()
    end
        self._msufNoUnitCleared = true
        return
    else
        self._msufNoUnitCleared = nil
    end
end
if not exists then
    if unit ~= "player" and self._msufNoUnitCleared and (self.GetAlpha and self:GetAlpha() or 0) <= 0.01 then
        return
    end
    if unit ~= "player" then
        self:SetAlpha(0)
    end
    if self.portrait then self.portrait:Hide() end
    MSUF_ClearUnitFrameState(self, true)
    self._msufNoUnitCleared = true
    return
else
    _G.MSUF_ApplyUnitAlpha(self, key)
    self._msufNoUnitCleared = nil
    MSUF_UpdatePortraitIfNeeded(self, unit, conf, exists)
end
    local hp = MSUF_UFStep_BasicHealth(self, unit)

    if MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus) then
        didPowerBarSync = true
    end

    MSUF_UFStep_NameLevelLeaderRaid(self, unit, conf, g)
    MSUF_UFStep_Finalize(self, hp, didPowerBarSync)

    -- Rare/Heavy visuals are gated to reduce work in the frequent update path.
    -- We still force a visual pass when the "bottom bar" (power vs health) changes.
    do
        local pb = self.targetPowerBar
        local pbWanted = (pb ~= nil) and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
        local bottomIsPower = pbWanted and true or false
        if self._msufBarOutlineBottomIsPower ~= (bottomIsPower and true or false) then
            self._msufNeedsBorderVisual = true
    end
    end

    local doHeavy = true
    if ns.UF.ShouldRunHeavyVisual then
        doHeavy = ns.UF.ShouldRunHeavyVisual(self, key, true)
    end
    if doHeavy then
        MSUF_UFStep_HeavyVisual(self, unit, key)
        MSUF_UFStep_Border(self)
        self._msufLayoutWhy = nil
        self._msufVisualQueuedUFCore = nil
        self._msufNeedsBorderVisual = nil
    end
    -- IMPORTANT: layered alpha uses per-texture alpha, which visual steps reset.
    if conf and conf.alphaExcludeTextPortrait == true then
        _G.MSUF_ApplyUnitAlpha(self, key)
    end
    if _G then
        _G.MSUF_TPA_SyncAnchors(self)
    end
end
do
    local function MSUF_TPA_GetOrCreate(name)
        if not _G or not name then return nil end
        local f = _G[name]
        if f then return f end
        f = F.CreateFrame("Frame", name, UIParent)
        f:SetSize(1, 1)
        if f.SetAlpha then f:SetAlpha(0) end
        if f.Show then f:Show() end
        _G[name] = f
        return f
    end
    local function MSUF_TPA_Snap(anchorName, target)
        local a = MSUF_TPA_GetOrCreate(anchorName)
        if not a or not a.ClearAllPoints or not a.SetPoint then return end
        a:ClearAllPoints()
        a:SetPoint("CENTER", target or UIParent, "CENTER", 0, 0)
    end
    local function MSUF_TPA_SyncFromUnitFrame(uf)
        if not uf or not uf.unit then return end
        local unit = uf.unit
        if unit ~= "player" and unit ~= "target" then return end
        if unit == "player" then
            MSUF_TPA_Snap("MSUF_TPA_PlayerFrame", uf)
            local pb = uf.targetPowerBar or uf.powerBar or uf
            MSUF_TPA_Snap("MSUF_TPA_PlayerPowerBar", pb)
            local sp = pb
            MSUF_TPA_Snap("MSUF_TPA_PlayerSecondaryPower", sp)
        else
            MSUF_TPA_Snap("MSUF_TPA_TargetFrame", uf)
            local pb = uf.targetPowerBar or uf.powerBar or uf
            MSUF_TPA_Snap("MSUF_TPA_TargetPowerBar", pb)
            MSUF_TPA_Snap("MSUF_TPA_TargetSecondaryPower", pb)
    end
    end
    _G.MSUF_TPA_SyncAnchors = function(uf)
        MSUF_TPA_SyncFromUnitFrame(uf)
    end
    _G.MSUF_UpdateThirdPartyAnchors_All = function()
        if not _G or not _G.MSUF_UnitFrames then return end
        MSUF_TPA_SyncFromUnitFrame(_G.MSUF_UnitFrames.player)
        MSUF_TPA_SyncFromUnitFrame(_G.MSUF_UnitFrames.target)
    end
_G.MSUF_TPA_EnsureAllAnchors = function()
    MSUF_TPA_GetOrCreate("MSUF_TPA_PlayerFrame")
    MSUF_TPA_GetOrCreate("MSUF_TPA_TargetFrame")
    MSUF_TPA_GetOrCreate("MSUF_TPA_PlayerPowerBar")
    MSUF_TPA_GetOrCreate("MSUF_TPA_TargetPowerBar")
    MSUF_TPA_GetOrCreate("MSUF_TPA_PlayerSecondaryPower")
    MSUF_TPA_GetOrCreate("MSUF_TPA_TargetSecondaryPower")
end
end
do
    local function MSUF_TryRegisterBCDMAnchors()
        if _G and _G.MSUF_BCDM_AnchorsRegistered then return true end
        if not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.IsAddOnLoaded("BetterCooldownManager") then return false end
        if not _G or not _G.BCDMG or type(_G.BCDMG.AddAnchors) ~= "function" then return false end
        local function MSUF_BCDM_AddAnchors(addOnName, addToTypes, anchorTable)
            local api = _G and _G.BCDMG
            if not api then return false end
            local fn = api.AddAnchors
            if type(fn) ~= "function" then return false end
            local ok = MSUF_FastCall(fn, api, addOnName, addToTypes, anchorTable)
            if ok then return true end
            ok = MSUF_FastCall(fn, addOnName, addToTypes, anchorTable)
            return ok and true or false
    end
            _G.MSUF_TPA_EnsureAllAnchors()
        local msufColor = "|cFFFFD700Midnight|rSimpleUnitFrames"
        local anchors = {
            ["MSUF_player"] = msufColor .. ": Player Frame",
            ["MSUF_target"] = msufColor .. ": Target Frame",
            ["MSUF_TPA_PlayerFrame"]          = msufColor .. ": Player Frame (Proxy)",
            ["MSUF_TPA_TargetFrame"]          = msufColor .. ": Target Frame (Proxy)",
            ["MSUF_TPA_PlayerPowerBar"]       = msufColor .. ": Player Power Bar",
            ["MSUF_TPA_TargetPowerBar"]       = msufColor .. ": Target Power Bar",
            ["MSUF_TPA_PlayerSecondaryPower"] = msufColor .. ": Player Secondary Power",
            ["MSUF_TPA_TargetSecondaryPower"] = msufColor .. ": Target Secondary Power",
        }
        MSUF_BCDM_AddAnchors("MidnightSimpleUnitFrames", { "Power", "SecondaryPower", "CastBar" }, anchors)
        MSUF_BCDM_AddAnchors("MidnightSimpleUnitFrames", { "Utility", "Buffs", "BuffBar", "Custom", "AdditionalCustom", "Item", "Trinket", "ItemSpell" }, anchors)
        _G.MSUF_BCDM_AnchorsRegistered = true
            _G.MSUF_UpdateThirdPartyAnchors_All()
        return true
    end
    if not MSUF_TryRegisterBCDMAnchors() then
        local f = F.CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(_, _, addon)
            if addon == "BetterCooldownManager" then
                MSUF_TryRegisterBCDMAnchors()
                if f.UnregisterEvent then f:UnregisterEvent("ADDON_LOADED") end
                if f.SetScript then f:SetScript("OnEvent", nil) end
            end
        end)
    end
end
local MSUF_ApplyRareVisuals
MSUF_ApplyRareVisuals = function(self)
    if not self or not self.unit then return end
    if self.border then
        self.border:Hide()
    end
    local thickness = 0
    if type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        thickness = select(1, MSUF_GetDesiredBarBorderThicknessAndStamp())
    end
    thickness = tonumber(thickness) or 0
    local o = self._msufBarOutline
    if thickness <= 0 then
        if o then
            ns.Util.HideKeys(o, ns.Bars._outlineParts, "frame")
    end
        self._msufBarOutlineThickness = 0
        self._msufBarOutlineEdgeSize = 0
        self._msufBarOutlineBottomIsPower = false
        return
    end
    if not o then
        o = {}
        self._msufBarOutline = o
    end
    ns.Util.HideKeys(o, ns.Bars._outlineParts)
    if not o.frame then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        local f = F.CreateFrame("Frame", nil, self, template)
        f:EnableMouse(false)
        f:SetFrameStrata(self:GetFrameStrata())
        local baseLevel = self:GetFrameLevel() + 2
        if self.hpBar and self.hpBar.GetFrameLevel then
            baseLevel = self.hpBar:GetFrameLevel() + 2
    end
        f:SetFrameLevel(baseLevel)
        o.frame = f
        o._msufLastEdgeSize = -1
    end
    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbWanted = (pb ~= nil) and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false
    local f = o.frame
    local snap = _G.MSUF_Snap
    local edge = (type(snap) == "function") and snap(f, thickness) or thickness
    if o._msufLastEdgeSize ~= edge then
        f:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = edge })
        f:SetBackdropBorderColor(0, 0, 0, 1)
        o._msufLastEdgeSize = edge
        self._msufBarOutlineEdgeSize = -1
    end
    if (self._msufBarOutlineThickness ~= thickness) or (self._msufBarOutlineEdgeSize ~= edge) or (self._msufBarOutlineBottomIsPower ~= (bottomIsPower and true or false)) then
        f:ClearAllPoints()
        if hb then
            f:SetPoint("TOPLEFT", hb, "TOPLEFT", -edge, edge)
    end
        if bottomBar then
            f:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", edge, -edge)
    end
        self._msufBarOutlineThickness = thickness
        self._msufBarOutlineEdgeSize = edge
        self._msufBarOutlineBottomIsPower = bottomIsPower and true or false
    end
    f:Show()
end
_G.MSUF_RefreshRareBarVisuals = MSUF_ApplyRareVisuals
do
    local f = F.CreateFrame("Frame")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function()
        if type(_G.MSUF_UpdatePixelPerfect) == "function" then
            _G.MSUF_UpdatePixelPerfect()
    end
        if MSUF_BarBorderCache then
            MSUF_BarBorderCache.stamp = nil
    end
        
        MSUF_ForEachUnitFrame(function(uf)
            if uf and uf.unit then
                uf._msufBarBorderStamp = nil
                uf._msufBarOutlineEdgeSize = -1
                if type(_G.MSUF_QueueUnitframeVisual) == "function" then
                    _G.MSUF_QueueUnitframeVisual(uf)
                end
            end
        end)
_G.MSUF_UpdateCastbarVisuals()
    end)
end
local function MSUF_ApplyUnitFrameKey_Immediate(key)
    EnsureDB()
    local conf = MSUF_DB[key]
    if not conf then return end
	    -- Ensure UnitframeCore refreshes event masks + option caches for this unit so
	    -- changes apply immediately without requiring /reload or a unit swap.
	    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
	        if key == "boss" then
	            _G.MSUF_UFCore_NotifyConfigChanged(nil, false, true, "ApplyUnitKey:boss")
	        else
	            _G.MSUF_UFCore_NotifyConfigChanged(key, false, true, "ApplyUnitKey:" .. tostring(key))
	        end
	    end
    local function hideFrame(unit)
        local f = UnitFrames[unit]
        if f then
if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
    MSUF_ApplyUnitVisibilityDriver(f, false)
end
f:Hide()
    end
    end
    if ns.UF.IsDisabled(conf) then
        if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
            hideFrame(key)
        elseif key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                hideFrame("boss" .. i)
            end
    end
        return
    end
    local function applyToFrame(unit)
        local f = UnitFrames[unit]
        if not f then return end
        f.cachedConfig = conf
        if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
            if f._msufVisibilityForced == "disabled" then
                f._msufVisibilityForced = nil
            end
            MSUF_ApplyUnitVisibilityDriver(f, (MSUF_UnitEditModeActive and true or false))
    end
        local w = tonumber(conf.width)  or (f.GetWidth and f:GetWidth())  or 275
        local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 40
        conf.width, conf.height = w, h
        f:SetSize(w, h)
        if f.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(f)
    end
        local showName  = (conf.showName  ~= false)
        local showHP    = (conf.showHP    ~= false)
        local showPower = (conf.showPower ~= false)
        f.showName      = showName
        f.showHPText    = showHP
        f.showPowerText = showPower
        if unit == "player" then
            f:Show()
        elseif MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode) then
            f:Show()
        else
            if F.UnitExists and F.UnitExists(unit) then
                f:Show()
            else
                f:Hide()
            end
    end
        PositionUnitFrame(f, unit)
        if f.portrait then
            MSUF_UpdateBossPortraitLayout(f, conf)
    end
        ApplyTextLayout(f, conf)
        MSUF_ClampNameWidth(f, conf)
        -- Do NOT force a legacy full update here.
        -- UFCore handles Identity/Indicators etc. Forcing a full update can overwrite
        -- level + leader/assist state and makes settings appear to apply only after unit swaps.
        ns.UF.RequestUpdate(f, false, true, "ApplyUnitKey")
    end
    if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
        applyToFrame(key)
    elseif key == "boss" then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            applyToFrame("boss" .. i)
    end
    end
    if key == "player" and MSUF_ReanchorPlayerCastBar then
        MSUF_ReanchorPlayerCastBar()
    elseif key == "target" and MSUF_ReanchorTargetCastBar then
        MSUF_ReanchorTargetCastBar()
    elseif key == "focus" and MSUF_ReanchorFocusCastBar then
        MSUF_ReanchorFocusCastBar()
    end
end
_G.MSUF_ApplyUnitFrameKey_Immediate = MSUF_ApplyUnitFrameKey_Immediate
_G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
function MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_UnitFrameApplyState
    st.dirty[key] = true
end
function MSUF_ApplyDirtyUnitFrames()
    local st = _G.MSUF_UnitFrameApplyState
    if not st or not st.dirty then return end
    if F.InCombatLockdown and F.InCombatLockdown() then
        st.queued = true
        return
    end
    for key in pairs(st.dirty) do
        if MSUF_ApplyUnitFrameKey_Immediate then
            MSUF_ApplyUnitFrameKey_Immediate(key)
    end
        st.dirty[key] = nil
    end
    st.queued = false
end
function MSUF_OnRegenEnabled_ApplyDirty(event)
    local st = _G.MSUF_UnitFrameApplyState
    if st and st.queued then
        MSUF_ApplyDirtyUnitFrames()
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
end
_G.MSUF_ApplyCommitState = _G.MSUF_ApplyCommitState or {
    pending = false,
    queued = false,
    fonts = false,
    bars = false,
    castbars = false,
    tickers = false,
    bossPreview = false,
}
local function MSUF_CommitApplyDirty_Scheduled()
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
    end
        MSUF_CommitApplyDirty()
end
local function MSUF_ScheduleApplyCommit()
    local st = _G.MSUF_ApplyCommitState
    if not st or st.pending then
        return
    end
    st.pending = true
    C_Timer.After(0, MSUF_CommitApplyDirty_Scheduled)
end
function MSUF_OnRegenEnabled_ApplyCommit(event)
    local st = _G.MSUF_ApplyCommitState
    if st and st.queued then
        st.queued = false
            MSUF_CommitApplyDirty()
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
end
function ApplySettingsForKey(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_ApplyCommitState
    if key == "boss" then
        st.bossPreview = true
    end
    MSUF_ScheduleApplyCommit()
end
function ApplyAllSettings()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end
    MSUF_MarkUnitFrameDirty("player")
    MSUF_MarkUnitFrameDirty("target")
    MSUF_MarkUnitFrameDirty("focus")
    MSUF_MarkUnitFrameDirty("targettarget")
    MSUF_MarkUnitFrameDirty("pet")
    MSUF_MarkUnitFrameDirty("boss")
    st.fonts = true
    st.bars = true
    st.castbars = true
    st.tickers = true
    st.bossPreview = true
    MSUF_ScheduleApplyCommit()
end
_G.MSUF_ApplySettingsForKey_Immediate = _G.MSUF_ApplySettingsForKey_Immediate or function(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)
    if F.InCombatLockdown and F.InCombatLockdown() then
        local stUF = _G.MSUF_UnitFrameApplyState
        if stUF then
            stUF.queued = true
    end
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
    end
        return
    end
    if MSUF_ApplyUnitFrameKey_Immediate then
        MSUF_ApplyUnitFrameKey_Immediate(key)
    end
    local stUF = _G.MSUF_UnitFrameApplyState
    if stUF and stUF.dirty then
        stUF.dirty[key] = nil
    end
end
_G.MSUF_ApplyAllSettings_Immediate = _G.MSUF_ApplyAllSettings_Immediate or function()
    EnsureDB()
    -- Keep UnitframeCore caches + event masks in sync so settings apply immediately
    -- (fixes level/leader indicators and other cached-option regressions).
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged(nil, false, true, "ApplyAllSettings_Immediate")
    end
    MSUF_ApplyUnitFrameKey_Immediate("player")
    MSUF_ApplyUnitFrameKey_Immediate("target")
    MSUF_ApplyUnitFrameKey_Immediate("focus")
    MSUF_ApplyUnitFrameKey_Immediate("targettarget")
    MSUF_ApplyUnitFrameKey_Immediate("pet")
    MSUF_ApplyUnitFrameKey_Immediate("boss")
    local fnFonts = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts
    if type(fnFonts) == "function" then fnFonts() end
    local fnBars = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
    if type(fnBars) == "function" then fnBars() end
    local fnCBTex = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
    if type(fnCBTex) == "function" then fnCBTex() end
    local fnCBVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
    if type(fnCBVis) == "function" then fnCBVis() end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
    end
    if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then
        _G.MSUF_EnsureStatusIndicatorTicker()
    end
    if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then
        _G.MSUF_EnsureToTFallbackTicker()
    end
    if _G.MSUF_UnitFrameApplyState and _G.MSUF_UnitFrameApplyState.dirty then
        for k in pairs(_G.MSUF_UnitFrameApplyState.dirty) do
            _G.MSUF_UnitFrameApplyState.dirty[k] = nil
    end
        _G.MSUF_UnitFrameApplyState.queued = false
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
end
function MSUF_CommitApplyDirty()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end
    if F.InCombatLockdown and F.InCombatLockdown() then
        st.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT", MSUF_OnRegenEnabled_ApplyCommit)
    end
        return
    end
        MSUF_ApplyDirtyUnitFrames()
    if st.fonts then
        local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts
        if type(fn) == "function" then fn() end
    end
    if st.bars then
        local fn = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
        if type(fn) == "function" then fn() end
    end
    if st.castbars then
        local fnTex = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
        if type(fnTex) == "function" then fnTex() end
        local fnVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
        if type(fnVis) == "function" then fnVis() end
    end
    if st.bossPreview then
        if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
    end
    end
    if st.tickers then
        if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then _G.MSUF_EnsureStatusIndicatorTicker() end
        if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then _G.MSUF_EnsureToTFallbackTicker() end
    end
    st.fonts = false
    st.bars = false
    st.castbars = false
    st.tickers = false
    st.bossPreview = false
    st.queued = false
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
end
local function UpdateAllFonts()
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize
local useShadow = g.textBackdrop and true or false
local colorPowerTextByType = (g.colorPowerTextByType == true)
        -- UnitFramesList iteration handled by MSUF_ForEachUnitFrame()
        local UpdateNameColor = MSUF_UpdateNameColor
        local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb, useShadow)
            if not fs then return end
            local stamp = tostring(path) .. "|" .. tostring(size) .. "|" .. tostring(flags)
            if fs._msufFontStamp ~= stamp then
                fs:SetFont(path, size, flags)
                fs._msufFontStamp = stamp
                fs._msufShadowOn = nil
            end
            if setColor then
                local cstamp = tostring(cr) .. "|" .. tostring(cg) .. "|" .. tostring(cb)
                if fs._msufColorStamp ~= cstamp then
                    fs:SetTextColor(cr, cg, cb, 1)
                    fs._msufColorStamp = cstamp
                end
            end
            local sh = useShadow and 1 or 0
            if fs._msufShadowOn ~= sh then
                if sh == 1 then
                    fs:SetShadowColor(0, 0, 0, 1)
                    fs:SetShadowOffset(1, -1)
                else
                    fs:SetShadowOffset(0, 0)
                end
                fs._msufShadowOn = sh
            end
    end
        local function ApplyFontsToFrame(f)
            if not f then return end
            local conf
            if f.unit and MSUF_DB then
                local key = f.msufConfigKey
                if not key then
                    local fn = GetConfigKeyForUnit
                    if type(fn) == "function" then
                        key = fn(f.unit)
                    end
                end
                if key then
                    conf = MSUF_DB[key]
                end
            end
            local nameSize  = (conf and conf.nameFontSize)  or globalNameSize
            local hpSize    = (conf and conf.hpFontSize)    or globalHPSize
            local powerSize = (conf and conf.powerFontSize) or globalPowSize
            local nameText = f.nameText
            if nameText then
                _MSUF_ApplyFontCached(nameText, nameSize, false, 0,0,0, useShadow)
            end
            local levelText = f.levelText
            if levelText then
                local levelSize = (conf and conf.levelIndicatorSize) or nameSize
                                _MSUF_ApplyFontCached(levelText, levelSize, false, 0,0,0, useShadow)
            end
            local statusSize = nameSize + 2
            local st = f.statusIndicatorText
            if st then
                _MSUF_ApplyFontCached(st, statusSize, true, fr, fg, fb, useShadow)
            end
            local st2 = f.statusIndicatorOverlayText
            if st2 then
                _MSUF_ApplyFontCached(st2, statusSize, true, fr, fg, fb, useShadow)
            end
            if nameText and UpdateNameColor then
                UpdateNameColor(f)
            end
            local hpText = f.hpText
            if hpText then
                _MSUF_ApplyFontCached(hpText, hpSize, true, fr, fg, fb, useShadow)
            end
            local hpTextPct = f.hpTextPct
            if hpTextPct then
                _MSUF_ApplyFontCached(hpTextPct, hpSize, true, fr, fg, fb, useShadow)
            end
            local powerTextPct = f.powerTextPct
            if powerTextPct then
                if colorPowerTextByType then
                    _MSUF_ApplyFontCached(powerTextPct, powerSize, false, 0, 0, 0, useShadow)
                else
                    _MSUF_ApplyFontCached(powerTextPct, powerSize, true, fr, fg, fb, useShadow)
                end
            end
            local powerText = f.powerText
            if powerText then
                if colorPowerTextByType then
                    _MSUF_ApplyFontCached(powerText, powerSize, false, 0, 0, 0, useShadow)
                else
                    _MSUF_ApplyFontCached(powerText, powerSize, true, fr, fg, fb, useShadow)
                end
            end
    end
        MSUF_ForEachUnitFrame(ApplyFontsToFrame)
    if _G.MSUF_UpdateCastbarVisuals_Immediate then
        _G.MSUF_UpdateCastbarVisuals_Immediate()
    elseif MSUF_UpdateCastbarVisuals then
        MSUF_UpdateCastbarVisuals()
    end
    if ns and ns.MSUF_ApplyGameplayFontFromGlobal then
        ns.MSUF_ApplyGameplayFontFromGlobal()
    end
    if type(MSCB_ApplyFontsFromMSUF) == "function" then
        MSUF_FastCall(MSCB_ApplyFontsFromMSUF)
    end
    if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then
        _G.MSUF_Auras2_ApplyFontsFromGlobal()
    end
if ns and ns.MSUF_ToTInline_RequestRefresh then
    ns.MSUF_ToTInline_RequestRefresh("FONTS")
end
end
MSUF_Export2("MSUF_UpdateAllFonts", UpdateAllFonts, "UpdateAllFonts")
if type(MSUF_UpdateCastbarVisuals) == "function" and not _G.MSUF_UpdateCastbarVisuals_Immediate then
    _G.MSUF_UpdateCastbarVisuals_Immediate = MSUF_UpdateCastbarVisuals
    MSUF_UpdateCastbarVisuals = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        MSUF_ScheduleApplyCommit()
    end
end
if type(MSUF_UpdateCastbarTextures) == "function" and not _G.MSUF_UpdateCastbarTextures_Immediate then
    _G.MSUF_UpdateCastbarTextures_Immediate = MSUF_UpdateCastbarTextures
    MSUF_UpdateCastbarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        MSUF_ScheduleApplyCommit()
    end
end
if not _G.MSUF_UpdateAllFonts_Immediate then
    _G.MSUF_UpdateAllFonts_Immediate = _G.MSUF_UpdateAllFonts
    _G.MSUF_UpdateAllFonts = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.fonts = true end
        MSUF_ScheduleApplyCommit()
    end
    _G.UpdateAllFonts = _G.MSUF_UpdateAllFonts
end
local function UpdateAllBarTextures()
    local texHP = MSUF_GetBarTexture()
    if not texHP then return end
    local texAbs  = MSUF_GetAbsorbBarTexture()
    local texHeal = MSUF_GetHealAbsorbBarTexture()
    texAbs  = texAbs  or texHP
    texHeal = texHeal or texHP
    local function ApplyTex(sb, tex)
        if not sb or not tex then return end
        if sb.MSUF_cachedStatusbarTexture ~= tex then
            sb:SetStatusBarTexture(tex)
            sb.MSUF_cachedStatusbarTexture = tex
    end
    end
    local applyBg = MSUF_ApplyBarBackgroundVisual
    MSUF_ForEachUnitFrame(function(f)
        ApplyTex(f.hpBar, texHP)
        ApplyTex(f.absorbBar, texAbs)
        ApplyTex(f.healAbsorbBar, texHeal)
        if applyBg then
            applyBg(f)
    end
        ApplyTex(f.targetPowerBar, texHP)
    end)

    -- Keep castbars in sync when they inherit from the global bar texture.
    if type(_G.MSUF_UpdateCastbarTextures_Immediate) == "function" then
        _G.MSUF_UpdateCastbarTextures_Immediate()
    elseif type(MSUF_UpdateCastbarTextures) == "function" then
        MSUF_UpdateCastbarTextures()
    end
end
local function UpdateAbsorbBarTextures()
    local texAbs  = MSUF_GetAbsorbBarTexture()
    local texHeal = MSUF_GetHealAbsorbBarTexture()
    if not texAbs or not texHeal then
        local texHP = MSUF_GetBarTexture()
        texAbs  = texAbs  or texHP
        texHeal = texHeal or texHP
        if not texAbs or not texHeal then return end
    end
    local function ApplyTex(sb, tex)
        if not sb or not tex then return end
        if sb.MSUF_cachedStatusbarTexture ~= tex then
            sb:SetStatusBarTexture(tex)
            sb.MSUF_cachedStatusbarTexture = tex
    end
    end
    MSUF_ForEachUnitFrame(function(f)
        ApplyTex(f.absorbBar, texAbs)
        ApplyTex(f.healAbsorbBar, texHeal)
    end)
end
MSUF_Export2("MSUF_UpdateAbsorbBarTextures", UpdateAbsorbBarTextures)
MSUF_Export2("MSUF_UpdateAllBarTextures", UpdateAllBarTextures, "UpdateAllBarTextures", true)
if not _G.MSUF_UpdateAllBarTextures_Immediate then
    _G.MSUF_UpdateAllBarTextures_Immediate = _G.MSUF_UpdateAllBarTextures
    _G.MSUF_UpdateAllBarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.bars = true end
        MSUF_ScheduleApplyCommit()
    end
    _G.UpdateAllBarTextures = _G.MSUF_UpdateAllBarTextures
end
if ns then
    ns.MSUF_UpdateAllBarTextures = UpdateAllBarTextures
end

-- Absorb display mode (Options -> Bars: "Absorb display")
-- The dropdown stores `general.absorbTextMode`, but runtime uses these flags:
--   general.enableAbsorbBar
--   general.showTotalAbsorbAmount
local function MSUF_UpdateAbsorbTextMode()
    if type(EnsureDB) == "function" then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if not g then return end
    local mode = tonumber(g.absorbTextMode)
    if not mode then return end

    if mode == 1 then
        g.enableAbsorbBar = false
        g.showTotalAbsorbAmount = false
    elseif mode == 2 then
        g.enableAbsorbBar = true
        g.showTotalAbsorbAmount = false
    elseif mode == 3 then
        g.enableAbsorbBar = true
        g.showTotalAbsorbAmount = true
    elseif mode == 4 then
        g.enableAbsorbBar = false
        g.showTotalAbsorbAmount = true
    end
end
MSUF_Export2("MSUF_UpdateAbsorbTextMode", MSUF_UpdateAbsorbTextMode, "MSUF_UpdateAbsorbTextMode")

local function MSUF_NudgeUnitFrameOffset(unit, parent, deltaX, deltaY)
    if not unit or not parent then return end
    EnsureDB()
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key]
    if not conf then return end
    local STEP = 1
    deltaX = (deltaX or 0) * STEP
    deltaY = (deltaY or 0) * STEP
    if MSUF_EditModeSizing then
        local w = conf.width  or parent:GetWidth()  or 250
        local h = conf.height or parent:GetHeight() or 40
        w = w + deltaX
        h = h + deltaY
        if w < 80  then w = 80  end
        if w > 600 then w = 600 end
        if h < 20  then h = 20  end
        if h > 220 then h = 220 end
        conf.width  = w
        conf.height = h
        if key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    frame:SetSize(w, h)
                    ns.UF.RequestUpdate(frame, true, true, "EditModeSizing")
                end
            end
        else
            parent:SetSize(w, h)
            ns.UF.RequestUpdate(parent, true, true, "EditModeSizing")
    end
    else
        conf.offsetX = (conf.offsetX or 0) + deltaX
        conf.offsetY = (conf.offsetY or 0) + deltaY
        if key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    PositionUnitFrame(frame, bossUnit)
                end
            end
        else
            PositionUnitFrame(parent, unit)
    end
        if MSUF_CurrentOptionsKey == key then
            local xSlider = _G["MSUF_OffsetXSlider"]
            local ySlider = _G["MSUF_OffsetYSlider"]
            if xSlider and xSlider.SetValue then
                xSlider:SetValue(conf.offsetX or 0)
            end
            if ySlider and ySlider.SetValue then
                ySlider:SetValue(conf.offsetY or 0)
            end
    end
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
local function MSUF_EnableUnitFrameDrag(f, unit)
    if not f or not unit then return end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(false)
    if f.RegisterForDrag then
        f:RegisterForDrag("LeftButton", "RightButton")
    end
    local function _DisableClicks(self)
        if not self or not self.GetAttribute or not self.SetAttribute then return end
        if not self._msufSavedClickAttrs then
            self._msufSavedClickAttrs = {
                type1 = self:GetAttribute("*type1"),
                type2 = self:GetAttribute("*type2"),
            }
    end
        self:SetAttribute("*type1", nil)
        self:SetAttribute("*type2", nil)
    end
    local function _RestoreClicks(self)
        local saved = self and self._msufSavedClickAttrs
        if not saved or not self.SetAttribute then return end
        self:SetAttribute("*type1", saved.type1)
        self:SetAttribute("*type2", saved.type2)
        self._msufSavedClickAttrs = nil
    end
    local function _GetConfAndKey()
        EnsureDB()
        local key = GetConfigKeyForUnit(unit)
        local conf = key and MSUF_DB and MSUF_DB[key]
        return key, conf
    end
    local function _ApplySnapAndClamp(key, conf)
        if not conf then return end
        local g = MSUF_DB and MSUF_DB.general or nil
        if not MSUF_EditModeSizing then
            if g and g.editModeSnapToGrid then
                local gridStep = g.editModeGridStep or 20
                if gridStep < 1 then gridStep = 1 end
                local half = gridStep / 2
                local x = conf.offsetX or 0
                local y = conf.offsetY or 0
                conf.offsetX = math.floor((x + half) / gridStep) * gridStep
                conf.offsetY = math.floor((y + half) / gridStep) * gridStep
            end
        else
            local w = conf.width  or (f.GetWidth and f:GetWidth()) or 250
            local h = conf.height or (f.GetHeight and f:GetHeight()) or 40
            if w < 80  then w = 80  end
            if w > 600 then w = 600 end
            if h < 20  then h = 20  end
            if h > 600 then h = 600 end
            conf.width, conf.height = w, h
    end
    end
    local function _UpdateDBFromFrame(self, key, conf)
        if not self or not conf or not key then return end
        if MSUF_EditModeSizing then
            local w, h = self:GetSize()
            if w and h then
                conf.width = w
                conf.height = h
            end
            if MSUF_SyncUnitPositionPopup then
                MSUF_SyncUnitPositionPopup(unit, conf)
            end
            if key == "boss" then
                for i = 1, MSUF_MAX_BOSS_FRAMES do
                    local bossUnit = "boss" .. i
                    local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                    if frame then
                        frame:SetSize(conf.width, conf.height)
                        ns.UF.RequestUpdate(frame, true, true, "EditModeDrag")
                    end
                end
            else
                ns.UF.RequestUpdate(self, true, true, "EditModeDrag")
            end
            return
    end
        local anchor = MSUF_GetAnchorFrame and MSUF_GetAnchorFrame() or UIParent
        if not anchor or not anchor.GetCenter or not self.GetCenter then return end
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown then
            local ecv = _G and _G["EssentialCooldownViewer"]
            if ecv and anchor == ecv then
                local rule = MSUF_ECV_ANCHORS and MSUF_ECV_ANCHORS[key]
                if rule then
                    local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3] or 0, rule[4] or 0
                    local function _PointXY(fr, p)
                        if not fr or not p then return nil, nil end
                        if p == "CENTER" then
                            return fr:GetCenter()
                        end
                        local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
                        if not (l and r and t and b) then
                            return nil, nil
                        end
                        local cx = (l + r) * 0.5
                        local cy = (t + b) * 0.5
                        if p == "TOPLEFT" then return l, t end
                        if p == "TOP" then return cx, t end
                        if p == "TOPRIGHT" then return r, t end
                        if p == "LEFT" then return l, cy end
                        if p == "RIGHT" then return r, cy end
                        if p == "BOTTOMLEFT" then return l, b end
                        if p == "BOTTOM" then return cx, b end
                        if p == "BOTTOMRIGHT" then return r, b end
                        return fr:GetCenter()
                    end
                    local ax2, ay2 = _PointXY(ecv, relPoint)
                    local fx2, fy2 = _PointXY(self, point)
                    if ax2 and ay2 and fx2 and fy2 then
                        local x = fx2 - ax2
                        local y = fy2 - ay2
                        conf.offsetX = floor((x - baseX) + 0.5)
                        conf.offsetY = floor((y - extraY) + 0.5)
                        if MSUF_SyncUnitPositionPopup then
                            MSUF_SyncUnitPositionPopup(unit, conf)
                        end
                        if MSUF_UpdateEditModeInfo then
                            MSUF_UpdateEditModeInfo()
                        end
                        return
                    end
                end
            end
    end
        local ax, ay = anchor:GetCenter()
        local fx, fy = self:GetCenter()
        if not ax or not ay or not fx or not fy then return end
        local newX = fx - ax
        local newY = fy - ay
        if key == "boss" then
            local index = tonumber(unit:match("^boss(%d+)$")) or 1
            local spacing = conf.spacing or -36
            newY = newY - ((index - 1) * spacing)
    end
        conf.offsetX = newX
        conf.offsetY = newY
        if MSUF_SyncUnitPositionPopup then
            MSUF_SyncUnitPositionPopup(unit, conf)
    end
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
    end
    end
    f:SetScript("OnMouseDown", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if F.InCombatLockdown and F.InCombatLockdown() then return end
        self._msufClickButton = button
        self._msufDragDidStart = false
    end)
    f:SetScript("OnDragStart", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if F.InCombatLockdown and F.InCombatLockdown() then return end
        local key, conf = _GetConfAndKey()
        if not key or not conf then return end
        self._msufDragDidStart = true
        self._msufDragActive = true
        self._msufDragKey = key
        self._msufDragConf = conf
        _DisableClicks(self)
        if MSUF_EditModeSizing then
            self:SetResizable(true)
            self:StartSizing("BOTTOMRIGHT")
        else
            self:StartMoving()
    end
        self._msufDragAccum = 0
            _G.MSUF_UnregisterBucketUpdate(self, "EditDrag")
        if _G.MSUF_RegisterBucketUpdate then
            _G.MSUF_RegisterBucketUpdate(self, 0.02, function(s, dt)
                if not s._msufDragActive then return end
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
            end, "EditDrag")
        else
            self:SetScript("OnUpdate", function(s, elapsed)
                if not s._msufDragActive then
                    s:SetScript("OnUpdate", nil)
                    return
                end
                s._msufDragAccum = (s._msufDragAccum or 0) + (elapsed or 0)
                if s._msufDragAccum < 0.02 then return end
                s._msufDragAccum = 0
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
            end)
    end
    end)
    f:SetScript("OnDragStop", function(self, button)
        if not self._msufDragActive then return end
        self:StopMovingOrSizing()
        local key = self._msufDragKey
        local conf = self._msufDragConf
        self._msufDragActive = false
        self._msufDragKey = nil
        self._msufDragConf = nil
            _G.MSUF_UnregisterBucketUpdate(self, "EditDrag")
        self:SetScript("OnUpdate", nil)
        _RestoreClicks(self)
        if key and conf then
            _UpdateDBFromFrame(self, key, conf)
            _ApplySnapAndClamp(key, conf)
            if key == "boss" then
                for i = 1, MSUF_MAX_BOSS_FRAMES do
                    local bossUnit = "boss" .. i
                    local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                    if frame then
                        PositionUnitFrame(frame, bossUnit)
                    end
                end
            else
                PositionUnitFrame(self, unit)
            end
    end
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if F.InCombatLockdown and F.InCombatLockdown() then return end
        if self._msufDragDidStart then
            return
    end
        if not MSUF_EditModeSizing and MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, self)
    end
    end)
end
local function MSUF_CreateEditArrowButton(name, parent, unit, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
    local btn = F.CreateFrame("Button", name, parent)
    btn:SetSize(18, 18)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    btn._bg = bg
    local symbols = {
        LEFT  = "<",
        RIGHT = ">",
        UP    = "^",
        DOWN  = "v",
    }
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(symbols[direction] or "")
    label:SetTextColor(0, 0, 0, 1)
    btn._label = label
    btn:SetScript("OnEnter", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if F.InCombatLockdown and F.InCombatLockdown() then return end
            if MSUF_OpenPositionPopup then
                MSUF_OpenPositionPopup(unit, parent)
            end
            return
    end
        if button ~= "LeftButton" then
            return
    end
        if not MSUF_UnitEditModeActive then return end
        if F.InCombatLockdown and F.InCombatLockdown() then return end
        if MSUF_NudgeUnitFrameOffset then
            MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
    end
    end)
    return btn
end
local function MSUF_AttachEditArrowsToFrame(f, unit, baseName)
    local pad = 8
    f.MSUF_ArrowLeft  = MSUF_CreateEditArrowButton(baseName .. "Left",  f, unit, "LEFT",  "RIGHT",  f, "LEFT",   -pad,  0, -1,  0)
    f.MSUF_ArrowRight = MSUF_CreateEditArrowButton(baseName .. "Right", f, unit, "RIGHT", "LEFT",   f, "RIGHT",   pad,  0,  1,  0)
    f.MSUF_ArrowUp    = MSUF_CreateEditArrowButton(baseName .. "Up",    f, unit, "UP",    "BOTTOM", f, "TOP",      0,  pad, 0,  1)
    f.MSUF_ArrowDown  = MSUF_CreateEditArrowButton(baseName .. "Down",  f, unit, "DOWN",  "TOP",    f, "BOTTOM",   0, -pad, 0, -1)
    if not f.UpdateEditArrows then
        function f:UpdateEditArrows()
            if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
                return
            end
            local show = MSUF_UnitEditModeActive and (not F.InCombatLockdown or not F.InCombatLockdown())
            if show then
                self.MSUF_ArrowLeft:Show()
                self.MSUF_ArrowRight:Show()
                self.MSUF_ArrowUp:Show()
                self.MSUF_ArrowDown:Show()
            else
                self.MSUF_ArrowLeft:Hide()
                self.MSUF_ArrowRight:Hide()
                self.MSUF_ArrowUp:Hide()
                self.MSUF_ArrowDown:Hide()
            end
    end
    end
    f:UpdateEditArrows()
end
local MSUF_EDIT_ARROW_BASENAMES = {
    player       = "MSUF_PlayerArrow",
    target       = "MSUF_TargetArrow",
    focus        = "MSUF_FocusArrow",
    pet          = "MSUF_PetArrow",
    targettarget = "MSUF_TargetTargetArrow",
}
local function MSUF_CreateEditArrowsForUnit(f, unit)
    if not f or f.MSUF_ArrowsCreated then return end
    local baseName = MSUF_EDIT_ARROW_BASENAMES[unit]
    if not baseName then
        if type(unit) == "string" and unit:match("^boss%d+$") then
            baseName = "MSUF_" .. unit .. "_Arrow"
        else
            return
    end
    end
    f.MSUF_ArrowsCreated = true
    MSUF_AttachEditArrowsToFrame(f, unit, baseName)
end
local function MSUF_ConfBool(conf, field, default)
    local v = conf and conf[field]
    if v == nil then
        return default and true or false
    end
    return v and true or false
end
local MSUF_UNIT_CREATE_DEFS = {
    player =      { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    target =      { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    focus =       { w = 220, h = 30, showName = true,  showHP = false, showPower = false, isBoss = false, startHidden = false },
    targettarget ={ w = 220, h = 30, showName = true,  showHP = true,  showPower = false, isBoss = false, startHidden = false },
    pet =         { w = 220, h = 30, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
}
local MSUF_UNIT_CREATE_DEF_BOSS = { w = 220, h = 30, showName = true, showHP = true, showPower = true, isBoss = true, startHidden = true }
local MSUF_UNIT_TIP_FUNCS = {
    player = "MSUF_ShowPlayerInfoTooltip",
    target = "MSUF_ShowTargetInfoTooltip",
    focus = "MSUF_ShowFocusInfoTooltip",
    targettarget = "MSUF_ShowTargetTargetInfoTooltip",
    pet = "MSUF_ShowPetInfoTooltip",
}
local function MSUF_ApplyPowerBarEmbedLayout(f)
    if not f or not f.hpBar then return end
    local pb = f.targetPowerBar
    if not pb then
        f._msufPowerBarReserved = nil
        f._msufPBLayoutStamp = nil
        ns.Cache.ClearStamp(f, "PBEmbedLayout")
        return
    end
    EnsureDB()
    local b = (MSUF_DB and MSUF_DB.bars) or {}
    local h = tonumber(b.powerBarHeight) or 3
    h = math.floor(h + 0.5)
    if h < 1 then h = 1 elseif h > 80 then h = 80 end
    local embed = (b.embedPowerBarIntoHealth == true)
    local enabled = false
    local unit = f.unit
    if unit == 'player' then
        enabled = (b.showPlayerPowerBar ~= false)
    elseif unit == 'target' then
        enabled = (b.showTargetPowerBar ~= false)
    elseif unit == 'focus' then
        enabled = (b.showFocusPowerBar ~= false)
    elseif type(unit) == 'string' and string.sub(unit, 1, 4) == 'boss' then
        enabled = (b.showBossPowerBar ~= false)
    end
        local reserve = (embed and enabled and h > 0)
    if not ns.Cache.StampChanged(f, "PBEmbedLayout", (reserve and 1 or 0), h) then return end

    f._msufPBLayoutStamp = 1
    f._msufPowerBarReserved = reserve and true or nil
    local hb = f.hpBar
    hb:ClearAllPoints()
    hb:SetPoint('TOPLEFT', f, 'TOPLEFT', 2, -2)
    if reserve then
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2 + h)
    else
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    end
    pb:ClearAllPoints()
    pb:SetHeight(h)
    if reserve then
        pb:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 2, 2)
        pb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    else
        pb:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', 0, 0)
        pb:SetPoint('TOPRIGHT', hb, 'BOTTOMRIGHT', 0, 0)
    end
    f._msufBarOutlineThickness = -1
end
_G.MSUF_ApplyPowerBarEmbedLayout = MSUF_ApplyPowerBarEmbedLayout
_G.MSUF_ApplyPowerBarEmbedLayout_All = function()
    if not UnitFrames then return end
    for _, fr in pairs(UnitFrames) do
        if fr and fr.hpBar and fr.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(fr)
    end
    end
end
local function CreateSimpleUnitFrame(unit)
    EnsureDB()
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key] or {}
    local f = F.CreateFrame("Button", "MSUF_" .. unit, UIParent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    f.unit = unit
    MSUF_EnsureUnitFlags(f)
    f.msufConfigKey = key
    f.cachedConfig = conf -- Step 5: cache config on creation as well
    f:SetClampedToScreen(true)
    local isBossUnit = (f._msufBossIndex ~= nil)
    local def = MSUF_UNIT_CREATE_DEFS[unit] or (isBossUnit and MSUF_UNIT_CREATE_DEF_BOSS) or nil
    if def then
        f:SetSize(conf.width or def.w, conf.height or def.h)
        f.showName      = MSUF_ConfBool(conf, "showName",  def.showName)
        f.showHPText    = MSUF_ConfBool(conf, "showHP",    def.showHP)
        f.showPowerText = MSUF_ConfBool(conf, "showPower", def.showPower)
        f.isBoss = def.isBoss and true or false
        if def.startHidden then f:Hide() end
        if f.isBoss and MSUF_ApplyUnitVisibilityDriver then MSUF_ApplyUnitVisibilityDriver(f, false) end
    end
    PositionUnitFrame(f, unit)
    MSUF_EnableUnitFrameDrag(f, unit)
    MSUF_CreateEditArrowsForUnit(f, unit)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    if ClickCastFrames then ClickCastFrames[f] = true end
    if not f._msufHpSpacerSelectHooked then
        f._msufHpSpacerSelectHooked = true
        f:HookScript("OnMouseDown", ns.UF.HpSpacerSelect_OnMouseDown)
    end
    local bg = ns.UF.MakeTex(f, "bg", "self", "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    local hpBar = ns.UF.MakeBar(f, "hpBar", "self")
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2); hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture(MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(hpBar, 0, false); hpBar.MSUF_lastValue = 0
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
    local bgTex = ns.UF.MakeTex(f, "hpBarBG", "hpBar", "BACKGROUND"); bgTex:SetAllPoints(hpBar)
    MSUF_ApplyBarBackgroundVisual(f)
    local portrait = ns.UF.MakeTex(f, "portrait", "self", "ARTWORK")
    portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    portrait:Hide()
    local grads = f.hpGradients
    if not grads then
        grads = MSUF_PreCreateHPGradients(hpBar)
        f.hpGradients = grads
        f.hpGradient = grads and grads.right or nil
    end
    MSUF_ApplyHPGradient(f)
    f.absorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 2, MSUF_GetAbsorbOverlayColor(), true)
    f.healAbsorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 3, MSUF_GetHealAbsorbOverlayColor(), false)
    ns.Bars.SetOverlayBarTexture(f.absorbBar, MSUF_GetAbsorbBarTexture)
    ns.Bars.SetOverlayBarTexture(f.healAbsorbBar, MSUF_GetHealAbsorbBarTexture)

    if unit == "player" or unit == "focus" or unit == "target" or isBossUnit then
        local pBar = ns.UF.MakeBar(f, "targetPowerBar", "self")
        pBar:SetStatusBarTexture(MSUF_GetBarTexture())
        local h = ((MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.powerBarHeight) == "number" and MSUF_DB.bars.powerBarHeight > 0) and MSUF_DB.bars.powerBarHeight) or 3
        pBar:SetHeight(h)
        pBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, 0); pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetMinMaxValues(0, 1)
        MSUF_SetBarValue(pBar, 0, false); pBar.MSUF_lastValue = 0
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        local pbg = ns.UF.MakeTex(f, "powerBarBG", "targetPowerBar", "BACKGROUND"); pbg:SetAllPoints(pBar)
        MSUF_ApplyBarBackgroundVisual(f)
        local pgrads = f.powerGradients
        if not pgrads then
            pgrads = MSUF_PreCreateHPGradients(pBar)
            f.powerGradients = pgrads
            f.powerGradient = pgrads and pgrads.right or nil
    end
        MSUF_ApplyPowerGradient(f)
        if _G.MSUF_ApplyPowerBarBorder then _G.MSUF_ApplyPowerBarBorder(pBar) end
        pBar:Hide()
    end
    local textFrame = ns.UF.MakeFrame(f, "textFrame", "Frame", "self")
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    local fontPath = MSUF_GetFontPath()
    local flags    = MSUF_GetFontFlags()
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    ns.UF.EnsureTextObjects(f, fontPath, flags, fr, fg, fb)
    ns.UF.EnsureStatusIndicatorOverlays(f, unit, fontPath, flags, fr, fg, fb)
    ApplyTextLayout(f, conf)
    MSUF_ClampNameWidth(f, conf)
    MSUF_UpdateNameColor(f)
    -- Indicators / icons (spec-driven)
    do
        local isPlayer = (unit == "player")
        local isPT = isPlayer or (unit == "target")
        local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
        local defs = {
            { "leaderIcon", isPT, "self", "OVERLAY", nil, 16, "Interface\\GroupFrame\\UI-Group-LeaderIcon", { "LEFT", f, "TOPLEFT", 0, 3 }, nil, _G.MSUF_ApplyLeaderIconLayout },
            { "raidMarkerIcon", true, "textFrame", "OVERLAY", 7, 16, "Interface\\TargetingFrame\\UI-RaidTargetingIcons", { "LEFT", textFrame, "TOPLEFT", 16, 3 }, nil, _G.MSUF_ApplyRaidMarkerLayout },
            { "combatStateIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\CharacterFrame\\UI-StateIcon", nil, { "UI-HUD-UnitFrame-Player-PortraitCombatIcon", 0.5, 1, 0, 0.5 } },
            { "incomingResIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\RaidFrame\\Raid-Icon-Rez" },
            { "summonIndicatorIcon", isPT, "textFrame", "OVERLAY", 7, 18, "Interface\\RaidFrame\\Raid-Icon-Summon", nil, { "Raid-Icon-SummonPending" } },
            { "restingIndicatorIcon", isPlayer, "textFrame", "OVERLAY", 7, 18, "Interface\\CharacterFrame\\UI-StateIcon", nil, { "UI-HUD-UnitFrame-Player-PortraitRestingIcon", 0, 0.5, 0, 0.5 } },
        }
        for i = 1, #defs do
            local key, ok, parentKey, layer, sub, size, file, pt, atlas, apply = unpack(defs[i])
            if ok then
                local tex = ns.UF.MakeTex(f, key, parentKey, layer, sub)
                if size then tex:SetSize(size, size) end
                if pt then tex:ClearAllPoints(); tex:SetPoint(unpack(pt)) end
                if atlas and getAtlasInfo and getAtlasInfo(atlas[1]) then
                    tex:SetAtlas(atlas[1], true)
                else
                    tex:SetTexture(file)
                    if atlas and atlas[2] then tex:SetTexCoord(atlas[2], atlas[3], atlas[4], atlas[5]) end
                end
                tex:Hide()
                if apply then apply(f) end
            end
    end
    end

    -- NOTE: Unitframe events are now registered centrally by MSUF_UnitframeCore.lua.
    if _G.MSUF_UFCore_AttachFrame then _G.MSUF_UFCore_AttachFrame(f) end
    f:EnableMouse(true)
        local highlight = ns.UF.MakeFrame(f, "highlightBorder", "Frame", "self", (BackdropTemplateMixin and "BackdropTemplate") or nil)
    highlight:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    highlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    do
        local baseLevel = 0
        if f.GetFrameLevel then baseLevel = f:GetFrameLevel() or 0 end
        if f.hpBar and f.hpBar.GetFrameLevel then
            local hb = f.hpBar:GetFrameLevel() or 0
            if hb > baseLevel then baseLevel = hb end
    end
        highlight:SetFrameLevel(baseLevel + 10)
    end
    highlight:EnableMouse(false)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    highlight:Hide()
    f.UpdateHighlightColor = ns.UF.UpdateHighlightColor
    f:SetScript("OnEnter", ns.UF.Unitframe_OnEnter)
    f:SetScript("OnLeave", ns.UF.Unitframe_OnLeave)
    if f.targetPowerBar and f.hpBar then
        MSUF_ApplyPowerBarEmbedLayout(f)
    end
    ns.UF.RequestUpdate(f, true, true, "F.CreateFrame")
    if unit == "target" then MSUF_UpdateTargetAuras(f) end
    UnitFrames[unit] = f
    if not f._msufInUnitFramesList then
        f._msufInUnitFramesList = true
        table.insert(UnitFramesList, f)
    end
    MSUF_ApplyUnitVisibilityDriver(f, MSUF_UnitEditModeActive)
end
-- IMPORTANT (Midnight): do NOT compare UnitGUID values (they can be "secret").
do
    local _msufTargetSoundFrame
    local _msufHadTarget
    local function MSUF_TargetSoundDriver_ResetState()
        _msufHadTarget = F.UnitExists and F.UnitExists("target") or false
    end
    local function MSUF_TargetSoundDriver_OnTargetChanged()
        if type(EnsureDB) == "function" then EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local hasTarget = (F.UnitExists and F.UnitExists("target")) or false
        local hadTarget = _msufHadTarget
        _msufHadTarget = hasTarget
        if g.playTargetSelectLostSounds ~= true then
            return
    end
        if (not hasTarget) and hadTarget then
            if type(_G.IsTargetLoose) == "function" and _G.IsTargetLoose() then
                return
            end
            if _G.SOUNDKIT and _G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT and PlaySound then
                local forceNoDuplicates = true
                PlaySound(_G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT, nil, forceNoDuplicates)
            end
            return
    end
        if hasTarget then
            if _G.C_PlayerInteractionManager
                and _G.C_PlayerInteractionManager.IsReplacingUnit
                and _G.C_PlayerInteractionManager.IsReplacingUnit() then
                return
            end
            local sk = _G.SOUNDKIT
            if not (sk and PlaySound) then return end
            local id
            if UnitIsEnemy and UnitIsEnemy("player", "target") then
                id = sk.IG_CREATURE_AGGRO_SELECT
            elseif UnitIsFriend and UnitIsFriend("player", "target") then
                id = sk.IG_CHARACTER_NPC_SELECT
            else
                id = sk.IG_CREATURE_NEUTRAL_SELECT
            end
            if id then
                PlaySound(id)
            end
    end
    end
    local function MSUF_TargetSoundDriver_Ensure()
        if _msufTargetSoundFrame then
            return
    end
        _msufTargetSoundFrame = F.CreateFrame("Frame")
        _msufTargetSoundFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        _msufTargetSoundFrame:SetScript("OnEvent", MSUF_TargetSoundDriver_OnTargetChanged)
        MSUF_TargetSoundDriver_ResetState()
    end
    _G.MSUF_TargetSoundDriver_Ensure = MSUF_TargetSoundDriver_Ensure
    _G.MSUF_TargetSoundDriver_ResetState = MSUF_TargetSoundDriver_ResetState
end
MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_STARTUP", function(event)
    MSUF_InitProfiles()
    EnsureDB()
    do
        local g = (MSUF_DB and MSUF_DB.general) or {}
        if g.playTargetSelectLostSounds == true and _G.MSUF_TargetSoundDriver_Ensure then
            _G.MSUF_TargetSoundDriver_Ensure()
    end
    end
    HideDefaultFrames()
    CreateSimpleUnitFrame("player")
        _G.MSUF_ApplyCompatAnchor_PlayerFrame()
    CreateSimpleUnitFrame("target")
if ns and ns.MSUF_CreateSecureTargetAuraHeaders then
    local targetFrame = UnitFrames and (UnitFrames.target or UnitFrames["target"])
    if targetFrame then
        ns.MSUF_CreateSecureTargetAuraHeaders(targetFrame)
    else
        print("MSUF: Target frame not found, cannot attach secure auras.")
    end
end
    CreateSimpleUnitFrame("targettarget")
    CreateSimpleUnitFrame("focus")
    CreateSimpleUnitFrame("pet")
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        CreateSimpleUnitFrame("boss" .. i)
    end
    if MSUF_ApplyUnitVisibilityDriver and UnitFrames then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            local bf = UnitFrames["boss" .. i]
            if bf and bf.isBoss then
                MSUF_ApplyUnitVisibilityDriver(bf, false)
            end
    end
    end
    do
        local function MSUF_MarkToTDirty()
            local tot = UnitFrames and UnitFrames["targettarget"]
            if tot then
                tot._msufToTDirty = true
            end
    end
        local function MSUF_TryUpdateToT(force)
            local tot = UnitFrames and UnitFrames["targettarget"]
            if not tot or not tot.IsShown or not tot:IsShown() then
                return
            end
            local key = GetConfigKeyForUnit and GetConfigKeyForUnit("targettarget")
            local conf = key and MSUF_DB and MSUF_DB[key]
            if ns.UF.IsDisabled(conf) then return end
            if not (F.UnitExists and F.UnitExists("targettarget")) then
                return
            end
            if not force and not tot._msufToTDirty then
                return
            end
            tot._msufToTDirty = false
            ns.UF.RequestUpdate(tot, true, false, "ToTDirty")
    end
-- Target name: optional inline "ToT" text (secret-safe)
local function MSUF_EnsureTargetToTInlineFS(targetFrame)
    if not targetFrame or not targetFrame.nameText then return end
    if targetFrame._msufToTInlineText and targetFrame._msufToTInlineSep then return end
    local parent = targetFrame.textFrame or targetFrame
    local sep = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sep:SetJustifyH("LEFT")
    sep:SetJustifyV("MIDDLE")
    sep:SetWordWrap(false)
    if sep.SetNonSpaceWrap then sep:SetNonSpaceWrap(false) end
    sep:SetText(" | ")
    local txt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetJustifyH("LEFT")
    txt:SetJustifyV("MIDDLE")
    txt:SetWordWrap(false)
    if txt.SetNonSpaceWrap then txt:SetNonSpaceWrap(false) end
    sep:ClearAllPoints()
    sep:SetPoint("LEFT", targetFrame.nameText, "RIGHT", 0, 0)
    txt:ClearAllPoints()
    txt:SetPoint("LEFT", sep, "RIGHT", 0, 0)
    targetFrame._msufToTInlineSep = sep
    targetFrame._msufToTInlineText = txt
end
function MSUF_RuntimeUpdateTargetToTInline(targetFrame)
    if not targetFrame or not targetFrame.nameText then return end
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    if not MSUF_DB then return end
    if type(MSUF_DB.targettarget) ~= "table" then
        MSUF_DB.targettarget = {}
    end
    if MSUF_DB.targettarget.showToTInTargetName == nil and type(MSUF_DB.target) == "table" and MSUF_DB.target.showToTInTargetName ~= nil then
        MSUF_DB.targettarget.showToTInTargetName = (MSUF_DB.target.showToTInTargetName and true) or false
    end
    if MSUF_DB.targettarget.totInlineSeparator == nil and type(MSUF_DB.target) == "table" and type(MSUF_DB.target.totInlineSeparator) == "string" then
        MSUF_DB.targettarget.totInlineSeparator = MSUF_DB.target.totInlineSeparator
    end
    if type(MSUF_DB.targettarget.totInlineSeparator) ~= "string" or MSUF_DB.targettarget.totInlineSeparator == "" then
        MSUF_DB.targettarget.totInlineSeparator = "|"
    end
    MSUF_EnsureTargetToTInlineFS(targetFrame)
    local totConf = MSUF_DB.targettarget
    ns.Text.RenderToTInline(targetFrame, totConf)
end
function MSUF_UpdateTargetToTInlineNow()
    local targetFrame = UnitFrames and (UnitFrames.target or UnitFrames["target"])
    if not targetFrame then return end
    MSUF_RuntimeUpdateTargetToTInline(targetFrame)
end
_G.MSUF_RuntimeUpdateTargetToTInline = MSUF_RuntimeUpdateTargetToTInline
_G.MSUF_UpdateTargetToTInlineNow = MSUF_UpdateTargetToTInlineNow
do
    local _msufToTInlineQueued = false
    local function _MSUF_ToTInline_Flush()
        _msufToTInlineQueued = false
            _G.MSUF_UpdateTargetToTInlineNow()
    end
    function ns.MSUF_ToTInline_RequestRefresh(_reason)
        if _msufToTInlineQueued then return end
        _msufToTInlineQueued = true
        C_Timer.After(0, _MSUF_ToTInline_Flush)
    end
    _G.MSUF_ToTInline_RequestRefresh = ns.MSUF_ToTInline_RequestRefresh
end
        if not _G.MSUF_UFCore_HasToTInlineDriver then
        local f = F.CreateFrame("Frame")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        if f.RegisterUnitEvent then
            f:RegisterUnitEvent("UNIT_TARGET", "target")
            f:RegisterUnitEvent("UNIT_HEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_MAXHEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_POWER_UPDATE", "targettarget")
            f:RegisterUnitEvent("UNIT_MAXPOWER", "targettarget")
            f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "targettarget")
            f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "targettarget")
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "targettarget")
            f:RegisterUnitEvent("UNIT_NAME_UPDATE", "targettarget")
            f:RegisterUnitEvent("UNIT_LEVEL", "targettarget")
            f:RegisterUnitEvent("UNIT_CONNECTION", "targettarget")
        else
            f:RegisterEvent("UNIT_TARGET")
            f:RegisterEvent("UNIT_HEALTH")
            f:RegisterEvent("UNIT_MAXHEALTH")
            f:RegisterEvent("UNIT_POWER_UPDATE")
            f:RegisterEvent("UNIT_MAXPOWER")
            f:RegisterEvent("UNIT_DISPLAYPOWER")
            f:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
            f:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            f:RegisterEvent("UNIT_NAME_UPDATE")
            f:RegisterEvent("UNIT_LEVEL")
            f:RegisterEvent("UNIT_CONNECTION")
    end
        local MSUF_ToTEventFramePending = nil
        local function MSUF_ToTFlushScheduled()
            local frm = MSUF_ToTEventFramePending
            MSUF_ToTEventFramePending = nil
            if frm then
                frm._msufPending = false
            end
            MSUF_TryUpdateToT(false)
                _G.MSUF_UpdateTargetToTInlineNow()
    end
        f._msufPending = false
        f:SetScript("OnEvent", function(self, event, unit)
            if unit and unit ~= "target" and unit ~= "targettarget" then
                return
            end
            MSUF_MarkToTDirty()
            if not self._msufPending and C_Timer and C_Timer.After then
                self._msufPending = true
                MSUF_ToTEventFramePending = self
                C_Timer.After(0, MSUF_ToTFlushScheduled)
            else
                MSUF_TryUpdateToT(false)
            end
        end)
        local function MSUF_StopToTFallbackTicker()
            local t = _G.MSUF_ToTFallbackTicker
            if t and t.Cancel then
                t:Cancel()
            end
            _G.MSUF_ToTFallbackTicker = nil
    end
        _G.MSUF_EnsureToTFallbackTicker = function()
            MSUF_StopToTFallbackTicker()
    end
        MSUF_StopToTFallbackTicker()
    end
    end
if type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
    _G.MSUF_ApplyAllSettings_Immediate()
else
    ApplyAllSettings()
end
    if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
        _G.MSUF_ReanchorTargetCastBar()
    end
    if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
        _G.MSUF_ReanchorFocusCastBar()
    end
    if MSUF_InitFocusKickIcon then
        MSUF_InitFocusKickIcon()
    end
    if TargetFrameSpellBar and not TargetFrameSpellBar.MSUF_Hooked then
        TargetFrameSpellBar.MSUF_Hooked = true
        TargetFrameSpellBar:HookScript("OnShow", function()
            if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
                _G.MSUF_ReanchorTargetCastBar()
            end
        end)
        TargetFrameSpellBar:HookScript("OnEvent", function()
            if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
                _G.MSUF_ReanchorTargetCastBar()
            end
        end)
    end
    if FocusFrameSpellBar and not FocusFrameSpellBar.MSUF_Hooked then
        FocusFrameSpellBar.MSUF_Hooked = true
        FocusFrameSpellBar:HookScript("OnShow", function()
            if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
                _G.MSUF_ReanchorFocusCastBar()
            end
        end)
        FocusFrameSpellBar:HookScript("OnEvent", function()
            if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
                _G.MSUF_ReanchorFocusCastBar()
            end
        end)
    end
if PetCastingBarFrame then
    if not PetCastingBarFrame.MSUF_HideHooked then
        PetCastingBarFrame.MSUF_HideHooked = true
        hooksecurefunc(PetCastingBarFrame, "Show", function(self)
            self:Hide()
        end)
    end
    PetCastingBarFrame:Hide()
end
    C_Timer.After(0.5, MSUF_MakeBlizzardOptionsMovable)
    if type(_G.MSUF_RegisterOptionsCategoryLazy) == "function" then
        _G.MSUF_RegisterOptionsCategoryLazy()
    elseif type(_G.CreateOptionsPanel) ~= "function" then
        if not _G.MSUF_OptionsPanelMissingWarned then
            _G.MSUF_OptionsPanelMissingWarned = true
            print("|cffff0000MSUF:|r Options panel not loaded (CreateOptionsPanel missing). Check your .toc includes MSUF_Options_Core.lua.")
    end
    end
    if _G.MSUF_CheckAndRunFirstSetup then _G.MSUF_CheckAndRunFirstSetup() end
    if _G.MSUF_HookCooldownViewer then C_Timer.After(1, _G.MSUF_HookCooldownViewer) end
    C_Timer.After(1.1, MSUF_InitPlayerCastbarPreviewToggle)
    print("|cff7aa2f7MSUF|r: |cffc0caf5/msuf|r |cff565f89to open options|r  |cff565f89•|r  |cff9ece6a Beta Build 1.9rc3  |cff565f89•|r  |cffc0caf5 Huge background changes -|r  |cfff7768eReport bugs in the Discord.|r")
end, nil, true)
do
    if not _G.MSUF__BucketUpdateManager then
        _G.MSUF__BucketUpdateManager = {
            buckets = {},
        }
    end
    local M = _G.MSUF__BucketUpdateManager
    local function _GetBucket(interval)
        local key = tostring(interval or 0)
        local bucket = M.buckets[key]
        if bucket then return bucket end
        bucket = {
            interval = interval or 0,
            accum = 0,
            jobs = {},   -- [ownerFrame] = { [tag] = job }
            frame = F.CreateFrame("Frame"),
        }
        bucket._onUpdate = function(_, elapsed)
            elapsed = elapsed or 0
            bucket.accum = (bucket.accum or 0) + elapsed
            if bucket.accum < bucket.interval then return end
            local tick = bucket.accum
            bucket.accum = 0
            for owner, tagMap in pairs(bucket.jobs) do
                if owner and owner.GetObjectType then
                    local visible = owner.IsVisible and owner:IsVisible()
                    for _, job in pairs(tagMap) do
                        if job then
                            if job.allowHidden or visible then
                                local cb = job.cb
                                if cb then
                                    cb(owner, tick)
                                end
                            end
                        end
                    end
                end
            end
            local hasAny = false
            for _, tagMap in pairs(bucket.jobs) do
                if tagMap and next(tagMap) then
                    hasAny = true
                    break
                end
            end
            if not hasAny then
                bucket.frame:SetScript("OnUpdate", nil)
                bucket.active = false
            end
    end
        bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
        bucket.active = true
        M.buckets[key] = bucket
        return bucket
    end
    _G.MSUF_RegisterBucketUpdate = function(owner, interval, cb, tag, allowHidden)
        if not owner or not cb then return end
        interval = tonumber(interval) or 0
        if interval <= 0 then interval = 0.02 end
        tag = tag or "_"
        local bucket = _GetBucket(interval)
        if not bucket.active then
            bucket.accum = 0
            bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
            bucket.active = true
    end
        bucket.jobs[owner] = bucket.jobs[owner] or {}
        bucket.jobs[owner][tag] = {
            cb = cb,
            allowHidden = allowHidden and true or false,
        }
        owner._msufBucketJobs = owner._msufBucketJobs or {}
        owner._msufBucketJobs[tag] = interval
        if not bucket.frame:GetScript("OnUpdate") then
            bucket.accum = 0
            bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
            bucket.active = true
    end
    end
    _G.MSUF_UnregisterBucketUpdate = function(owner, tag)
        if not owner then return end
        tag = tag or "_"
        local jobs = owner._msufBucketJobs
        local interval = jobs and jobs[tag]
        if not interval then return end
        local bucket = M.buckets[tostring(interval)]
        if bucket and bucket.jobs and bucket.jobs[owner] then
            bucket.jobs[owner][tag] = nil
            if not next(bucket.jobs[owner]) then
                bucket.jobs[owner] = nil
            end
    end
        jobs[tag] = nil
        if not next(jobs) then
            owner._msufBucketJobs = nil
    end
    end
end
do
    ns.__msuf_refactor_scaffold = ns.__msuf_refactor_scaffold or { version = "A1" }
    ns.__msuf_refactor_scaffold.patchB = "B1"
    ns.__msuf_refactor_scaffold.patchN = "N1"
    ns.Util.EnsureUnitFlags  = ns.Util.EnsureUnitFlags  or MSUF_EnsureUnitFlags
    ns.Util.IsTargetLikeFrame= ns.Util.IsTargetLikeFrame or MSUF_IsTargetLikeFrame
    ns.Bars.ResetBarZero     = ns.Bars.ResetBarZero     or MSUF_ResetBarZero
    ns.Text.ClearText        = ns.Text.ClearText        or MSUF_ClearText
end

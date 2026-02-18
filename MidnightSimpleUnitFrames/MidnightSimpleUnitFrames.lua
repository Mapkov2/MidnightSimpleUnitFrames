local addonName, ns = ...
ns = ns or {}
_G.MSUF_NS = ns
ns.Core   = ns.Core   or {}
ns.UF     = ns.UF     or {}
ns.Bars   = ns.Bars   or {}
ns.Text   = ns.Text   or {}
ns.Icons  = ns.Icons  or {}
ns.Util   = ns.Util   or {}
ns.Cache  = ns.Cache  or {}
ns.Compat = ns.Compat or {}
-- =========================================================================
-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next, unpack = pairs, ipairs, next, unpack or table.unpack
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent
local InCombatLockdown = InCombatLockdown
local CreateFrame, GetTime = CreateFrame, GetTime

-- ---------------------------------------------------------------------------
-- Localization (minimal, translator-friendly)
-- - ns.L is a key->string map with fallback to the key itself.
-- - ns.AddLocale(locale, dict) merges translations for the active locale.
-- NOTE: Full scaffold lives in Locales/MSUF_Localization.lua, but this fallback
-- keeps MSUF safe even if localization files are missing or load-order changes.
-- ---------------------------------------------------------------------------
ns.LOCALE = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local _L = ns.L
if not getmetatable(_L) then
    setmetatable(_L, { __index = function(t, k) return k end })
end
if _G then _G.MSUF_L = _L end
ns.AddLocale = ns.AddLocale or function(locale, dict)
    if type(dict) ~= "table" then return end
    local active = ns.LOCALE or "enUS"
    if locale ~= active then return end
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            _L[k] = v
        end
    end
end

-- Patch M: table-driven hide helpers (safe, no string compares)
ns.Bars._outlineParts = ns.Bars._outlineParts or { "top", "bottom", "left", "right", "tl", "tr", "bl", "br" }
ns.Util.HideKeys = ns.Util.HideKeys or function(t, keys, extraKey)
    if not t or not keys then  return end
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
    local v = conf and conf[key]; if v == nil and g then v = g[key] end; if v == nil then v = default end;  return v
end
ns.Util.Num = ns.Util.Num or function(conf, g, key, default)
    local v = tonumber(ns.Util.Val(conf, g, key, nil)); return (v == nil) and default or v
end
ns.Util.Enabled = ns.Util.Enabled or function(conf, g, key, defaultEnabled)
    local v = ns.Util.Val(conf, g, key, nil); if v == nil then return (defaultEnabled ~= false) end; return (v ~= false)
end
ns.Util.SetShown = ns.Util.SetShown or function(obj, show)
    if not obj then  return end; if show then if obj.Show then obj:Show() end else if obj.Hide then obj:Hide() end end
 end
ns.Util.Offset = ns.Util.Offset or function(v, default)  return (v == nil) and default or v end

-- Patch: ensure this helper exists before any core code needs it.
-- Used by text-layout + spacer logic. Must be available during core init.
if _G and type(_G.MSUF_NormalizeTextLayoutUnitKey) ~= "function" then
    function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, defaultKey)
        if unitKey == nil then return defaultKey or "player" end
        if unitKey == "shared" then return defaultKey or "player" end
        if unitKey == "tot" or unitKey == "targetoftarget" then return "targettarget" end
        if unitKey == "boss1" or unitKey == "boss2" or unitKey == "boss3" or unitKey == "boss4" or unitKey == "boss5" then return "boss" end
        return unitKey
    end
end

local F = ns.Cache.F or {}; ns.Cache.F = F
if not F._msufInit then
    F._msufInit = true
    local G = _G; F.UnitHealth, F.UnitHealthMax, F.UnitPower, F.UnitPowerMax = G.UnitHealth, G.UnitHealthMax, G.UnitPower, G.UnitPowerMax; F.UnitExists, F.UnitIsConnected, F.UnitIsDeadOrGhost = G.UnitExists, G.UnitIsConnected, G.UnitIsDeadOrGhost; F.UnitName, F.UnitClass, F.UnitReaction, F.UnitIsPlayer = G.UnitName, G.UnitClass, G.UnitReaction, G.UnitIsPlayer; F.CreateFrame, F.InCombatLockdown, F.GetTime = G.CreateFrame, G.InCombatLockdown, G.GetTime
end
-- Patch T: unified stamp cache (layout/indicator/portrait) to avoid per-call string stamps
ns.Cache.StampChanged = ns.Cache.StampChanged or function(o, k, ...)
    if not o then  return true end
    local c = o._msufStampCache; if not c then c = {}; o._msufStampCache = c end
    local r = c[k]; local n = select("#", ...)
    if not r then r = { n = n }; c[k] = r; for i = 1, n do r[i] = select(i, ...) end;  return true end
    if r.n ~= n then r.n = n; for i = 1, n do r[i] = select(i, ...) end; for i = n + 1, #r do r[i] = nil end;  return true end
    for i = 1, n do local v = select(i, ...); if r[i] ~= v then for j = 1, n do r[j] = select(j, ...) end;  return true end end
     return false
end
ns.Cache.ClearStamp = ns.Cache.ClearStamp or function(o, k)  local c = o and o._msufStampCache; if c then c[k] = nil end  end
-- Patch Y: Unitframe element factories (build-time scaffolding; no runtime behavior change)
-- Goal: remove copy/paste in unitframe creation by providing tiny, reusable constructors.
-- NOTE: Keep secret-safe: only operate on addon-owned keys/names; no comparisons on unit API strings.
ns.UF._ResolveParent = ns.UF._ResolveParent or function(self, parentKey)
    if not self then  return nil end
    if (not parentKey) or (parentKey == "self") then  return self end
    local t = type(parentKey)
    if t == "table" or t == "userdata" then  return parentKey end
    if parentKey == "UIParent" and UIParent then return UIParent end
    local p = self[parentKey]
    return p or self
end
ns.UF._MakeChildName = ns.UF._MakeChildName or function(self, suffix)
    if not suffix then  return nil end
    local base = (self and self.GetName) and self:GetName() or nil
    if base and base ~= "" then return base .. suffix end
     return nil
end
ns.UF.MakeFrame = ns.UF.MakeFrame or function(self, key, frameType, parentKey, inherits, nameSuffix, strata, level)
    if not self or not key then  return nil end
    local o = self[key]
    if o then  return o end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent then  return nil end
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
    if not self or not key then  return nil end
    local t = self[key]
    if t then  return t end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent or not parent.CreateTexture then  return nil end
    local name = ns.UF._MakeChildName(self, nameSuffix)
    t = parent:CreateTexture(name, layer or "ARTWORK", nil, sublayer)
    self[key] = t
     return t
end
ns.UF.MakeFont = ns.UF.MakeFont or function(self, key, parentKey, template, layer, sublayer, nameSuffix)
    if not self or not key then  return nil end
    local fs = self[key]
    if fs then  return fs end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent or not parent.CreateFontString then  return nil end
    local name = ns.UF._MakeChildName(self, nameSuffix)
    fs = parent:CreateFontString(name, layer or "OVERLAY", template, sublayer)
    self[key] = fs
     return fs
end
-- - Secret-safe (no string comparisons)
function ns.UF.RequestUpdate(frame, forceFull, wantLayout, reason, urgentNow)
    if not frame then  return end
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
    if not f or (unit ~= "player" and unit ~= "target") then  return end
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
    if not tf then  return end
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
ns.UF.HpSpacerSelect_OnMouseDown = ns.UF.HpSpacerSelect_OnMouseDown or function(self, button)
    -- Selection is driven primarily by the Bars menu dropdown. This click helper only runs while the MSUF settings UI is open.
    local p = _G and _G.MSUF_OptionsPanel
    if not (p and p.IsShown and p:IsShown()) then  return end
    if button and button ~= "LeftButton" then  return end
    local k = self and (self.msufConfigKey or self._msufConfigKey or self._msufUnitKey or self.unitKey) or nil
    if k and type(_G.MSUF_SetHpSpacerSelectedUnitKey) == "function" then
        _G.MSUF_SetHpSpacerSelectedUnitKey(k)
    end
 end

ns.UF.UpdateHighlightColor = ns.UF.UpdateHighlightColor or function(self)
    if not self then  return end
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or {}; local hr, hg, hb = 1, 1, 1; local hc = g.highlightColor
    if type(hc) == "table" then hr, hg, hb = hc[1] or 1, hc[2] or 1, hc[3] or 1
    else
        local key = (type(hc) == "string" and string.lower(hc)) or "white"
        local col = (type(MSUF_FONT_COLORS) == "table" and (MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white)) or nil
        if col then hr, hg, hb = col[1] or 1, col[2] or 1, col[3] or 1 end
    end
    local s = math_floor(hr * 1000) * 1000000 + math_floor(hg * 1000) * 1000 + math_floor(hb * 1000)
    if self._msufHighlightColorStamp ~= s then self._msufHighlightColorStamp = s; local b = self.highlightBorder; if b and b.SetBackdropBorderColor then b:SetBackdropBorderColor(hr, hg, hb, 1) end end
 end
ns.UF.Unitframe_OnEnter = ns.UF.Unitframe_OnEnter or function(self)
    if not self then  return end
    if not MSUF_DB then EnsureDB() end
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
            else
                GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:ClearAllPoints()
                -- Use custom position from Edit Mode drag if available
                local cx = g.tooltipPosX
                local cy = g.tooltipPosY
                if type(cx) == "number" and type(cy) == "number" then
                    GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx, cy)
                else
                    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 16)
                end
            end
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
    if not self then  return end
    ns.Util.SetShown(self.leaderIcon, false)
    ns.Util.SetShown(self.raidMarkerIcon, false)
 end
function ns.UF.HandleDisabledFrame(self, conf)
    if not ns.UF.IsDisabled(conf) then  return false end

    -- In MSUF Edit Mode, keep a persistent preview for frames that are disabled,
    -- so they can still be positioned/edited. Boss frames remain hard-hidden when disabled.
    if MSUF_UnitEditModeActive and (not (F.InCombatLockdown and F.InCombatLockdown())) and self and not self.isBoss then
        local fn = _G and _G.MSUF_ApplyUnitframeEditPreview
        if type(fn) == "function" then
            fn(self, self.msufConfigKey or self.unit, conf)
        else
            if self.Show then self:Show() end
        end
        ns.UF.HideLeaderAndRaidMarker(self)
        return true
    end

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
    if not frame then  return end
    local rsd = _G and _G.RegisterStateDriver
    local usd = _G and _G.UnregisterStateDriver
    if type(rsd) == "function" and type(usd) == "function" then
        usd(frame, "visibility")
        rsd(frame, "visibility", "hide")
    end
    frame._msufVisibilityForced = "disabled"
 end
function ns.UF.ShouldRunHeavyVisual(self, key, exists)
    if not self or not exists then  return false end
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
local ROOT_G = _G
do
    local realG = _G
    if type(realG.MSUF_GetCastbarTexture) ~= "function" then
        function realG.MSUF_GetCastbarTexture()
             return "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    end
    ROOT_G.MSUF_GetCastbarTexture = realG.MSUF_GetCastbarTexture
end
local UnitFramesList = {}
-- Patch AA2: move shared helpers earlier (used by early functions) + keep deterministic iteration
local UnitFrames = _G.MSUF_UnitFrames
if type(UnitFrames) ~= "table" then
    UnitFrames = {}
    _G.MSUF_UnitFrames = UnitFrames
end
local function MSUF_ForEachUnitFrame(fn)
    if not fn then  return end
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
_G.MSUF_ForEachUnitFrame = MSUF_ForEachUnitFrame
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
    if not f or f._msufUnitFlagsInited then  return end
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
_G.MSUF_EnsureUnitFlags = MSUF_EnsureUnitFlags
local function MSUF_IsTargetLikeFrame(f)
    return (f and (f.isBoss or f._msufIsPlayer or f._msufIsTarget or f._msufIsFocus)) and true or false
end
local function MSUF_ResetBarZero(bar, hide)
    if not bar then  return end
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if hide then bar:Hide() end
 end
local function MSUF_ClearText(fs, hide)
    if not fs then  return end
    fs:SetText("")
    if hide then fs:Hide() end
 end
ns.Bars._msufPatchB = ns.Bars._msufPatchB or { version = "B1" }
function ns.Bars.HidePowerBarOnly(bar)
    if not bar then  return true end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
     return true
end
function ns.Bars.HideAndResetPowerBar(bar)
    if not bar then  return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    MSUF_ResetBarZero(bar, true)
 end
function ns.Bars.ApplyPowerGradientOnce(frame)
    if not frame then  return end
    if frame.powerGradients then
        if ns.Bars._ApplyPowerGradient then ns.Bars._ApplyPowerGradient(frame) end
    elseif frame.powerGradient then
        if ns.Bars._ApplyPowerGradient then ns.Bars._ApplyPowerGradient(frame.powerGradient) end
    end
 end
function ns.Bars.PowerBarAllowed(barsConf, isBoss, isPlayer, isTarget, isFocus)
    if not barsConf then  return true end
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
    if not bar then  return end
    local pr, pg, pb = MSUF_GetPowerBarColor(pType, pTok)
    if not pr then
        local colPB = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
        pr, pg, pb = colPB.r, colPB.g, colPB.b
    end
    bar:SetStatusBarColor(pr, pg, pb)
    ns.Bars.ApplyPowerGradientOnce(frame)
 end
function ns.Bars.SetOverlayBarTexture(bar, texGetter)
    if not bar or not bar.SetStatusBarTexture or not texGetter then  return end
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
    if not fn then  return nil end
    return fn(frame, unit, ...)
end
ns.Bars.Spec.health = ns.Bars.Spec.health or function(frame, unit)
    if not frame or not unit or not frame.hpBar then  return nil, nil, false end
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
    if not bar then  return true end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    if hardReset then MSUF_ResetBarZero(bar, true) end
     return true
end
local function _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, wantPercent)
    if not (frame and bar and unit) then  return false end
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
    if not frame or not unit then  return end
    local bar = frame.targetPowerBar
    if not bar then  return end
    local barsConf = (MSUF_DB and MSUF_DB.bars) or {}
    MSUF_EnsureUnitFlags(frame)
    _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, frame.isBoss, frame._msufIsPlayer, frame._msufIsTarget, frame._msufIsFocus, false)
 end
ns.Bars.Spec.power_pct = ns.Bars.Spec.power_pct or function(frame, unit, barsConf, isBoss, isPlayer, isTarget, isFocus)
    local bar = frame and frame.targetPowerBar
    if not (frame and unit and bar) then  return false end
    barsConf = barsConf or ((MSUF_DB and MSUF_DB.bars) or {})
    return _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, true)
end
ns.Bars._msufPatchC = ns.Bars._msufPatchC or { version = "C1" }
-- Player self-heal prediction (own incoming heals only).
-- Implemented as a behind-the-HP statusbar so the additional segment only appears past current HP.

-- Self-heal prediction system moved to MSUF_SelfHealPred.lua

function ns.Bars.ResetHealthAndOverlays(frame, clearAbsorbs)
    if not frame then  return end
    MSUF_ResetBarZero(frame.hpBar)
    if frame.selfHealPredBar then
        MSUF_ResetBarZero(frame.selfHealPredBar, true)
    end
    if clearAbsorbs then
        MSUF_ResetBarZero(frame.absorbBar, true)
        MSUF_ResetBarZero(frame.healAbsorbBar, true)
    end
 end
function ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
    if not frame or not unit or not frame.hpBar then  return nil, nil end
    if maxHP == nil and F.UnitHealthMax then
        maxHP = F.UnitHealthMax(unit)
    end
    if type(maxHP) == "number" then
        frame.hpBar:SetMinMaxValues(0, maxHP)
    end
    if hp == nil and F.UnitHealth then
        hp = F.UnitHealth(unit)
    end
    if type(hp) == "number" then
        MSUF_SetBarValue(frame.hpBar, hp)
    end
    -- Absorb overlays: only update when marked dirty (absorb/maxHP events),
    -- not on every UNIT_HEALTH. Dirty flags set by FrameOnEvent + OnShow + AttachFrame.
    if frame.absorbBar and frame._msufAbsorbDirty then
        frame._msufAbsorbDirty = false
        ns.Bars._UpdateAbsorbBar(frame, unit, maxHP)
    end
    if frame.healAbsorbBar and frame._msufHealAbsorbDirty then
        frame._msufHealAbsorbDirty = false
        ns.Bars._UpdateHealAbsorbBar(frame, unit, maxHP)
    end
    if frame.selfHealPredBar then
        if ns.Bars._UpdateSelfHealPrediction then ns.Bars._UpdateSelfHealPrediction(frame, unit, maxHP, hp) end
    end
     return hp, maxHP
end

-- ns.Text core rendering moved to MSUF_Text.lua

local MSUF_BarBorderCache = { stamp = nil, thickness = 0 }
local function MSUF_GetBarBorderStyleId(style)
    if style == "THICK" then  return 2 end
    if style == "SHADOW" then  return 3 end
    if style == "GLOW" then  return 4 end
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
_G.MSUF_BarBorderCache = MSUF_BarBorderCache
_G.MSUF_GetDesiredBarBorderThicknessAndStamp = MSUF_GetDesiredBarBorderThicknessAndStamp
local function MSUF_ApplyPoint(frame, point, relFrame, relPoint, x, y)
    if not frame then  return end
    frame:ClearAllPoints()
    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if type(x) == "number" then x = snap(frame, x) end
        if type(y) == "number" then y = snap(frame, y) end
    end
    frame:SetPoint(point, relFrame, relPoint, x, y)
 end
local function MSUF_SetStatusBarColor(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then  return end
    if a ~= nil then
        bar:SetStatusBarColor(r, g, b, a)
    else
        bar:SetStatusBarColor(r, g, b)
    end
 end
local function MSUF_CreateOverlayStatusBar(parent, baseBar, frameLevel, r, g, b, a, reverseFill)
    if not parent or not baseBar then  return nil end
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
    if not bar or not bar.SetStatusBarColor then  return end
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
ns.Bars._ApplyAbsorbOverlayColor = MSUF_ApplyAbsorbOverlayColor
ns.Bars._ApplyHealAbsorbOverlayColor = MSUF_ApplyHealAbsorbOverlayColor
ns.Bars._ResetBarZero = MSUF_ResetBarZero
local function MSUF_NormalizeUnitKeyForDB(key)
    if not key or type(key) ~= "string" then  return nil end
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
    if not f or not f.levelText or not f.nameText then  return end
    conf = conf or {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local lx = (type(conf.levelIndicatorOffsetX) == "number") and conf.levelIndicatorOffsetX
        or ((type(g.levelIndicatorOffsetX) == "number") and g.levelIndicatorOffsetX or 0)
    local ly = (type(conf.levelIndicatorOffsetY) == "number") and conf.levelIndicatorOffsetY
        or ((type(g.levelIndicatorOffsetY) == "number") and g.levelIndicatorOffsetY or 0)
    local anchor = (type(conf.levelIndicatorAnchor) == "string") and conf.levelIndicatorAnchor
        or ((type(g.levelIndicatorAnchor) == "string") and g.levelIndicatorAnchor or "NAMERIGHT")
    f._msufLevelAnchor = anchor
    if not ns.Cache.StampChanged(f, "LevelLayout", anchor, lx, ly) then  return end
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
        if not f or not f.levelText or not f.nameText then  return end
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
    if not bar or value == nil then  return end
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
MSUF_EditModeSizing = false
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
        if mediatype ~= "font" then  return end
        if MSUF_RebuildFontChoices then
            MSUF_RebuildFontChoices()
    end
        local _g = MSUF_DB and MSUF_DB.general
        if _g and _g.fontKey == key then
            C_Timer.After(0, function()  if UpdateAllFonts then UpdateAllFonts() end  end)
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
        if type(key) ~= "string" or key == "" then  return false end
        if type(list) ~= "table" then  return false end
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
MSUF_GetNPCReactionColor = function(kind)
    local defaultR, defaultG, defaultB
    if kind == "friendly" then
        defaultR, defaultG, defaultB = 0, 1, 0           -- 
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
    if not MSUF_DB then EnsureDB() end
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}
    local t = MSUF_DB.npcColors[kind]
    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end
     return defaultR, defaultG, defaultB
end
MSUF_GetClassBarColor = function(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
         return defaultR, defaultG, defaultB
    end
    if not MSUF_DB then EnsureDB() end
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
    if not MSUF_DB then EnsureDB() end
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
    if not MSUF_DB then EnsureDB() end
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
    if not key then  return nil end
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.name == key then
            return info.path
    end
    end
     return nil
end

-- Castbar utilities moved to MSUF_Castbars.lua

local function MSUF_Clamp01(v)
    v = tonumber(v)
    if not v then  return 0 end
    if v < 0 then  return 0 end
    if v > 1 then  return 1 end
     return v
end
function MSUF_GetBarBackgroundTintRGBA()
    if not MSUF_DB then EnsureDB() end
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
    if not MSUF_DB then EnsureDB() end
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
    if not frame then  return end
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
        if not t then  return end
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
    if not MSUF_DB then EnsureDB() end
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(g.hpSpacerSelectedUnitKey, "player")
    g.hpSpacerSelectedUnitKey = k
     return k
end
function _G.MSUF_SetHpSpacerSelectedUnitKey(unitKey, suppressUIRefresh)
    if not MSUF_DB then EnsureDB() end
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, "player")
    g.hpSpacerSelectedUnitKey = k
    
    -- Keep the Bars menu scope dropdown in sync.
    if k and k ~= "shared" then
        g.hpPowerTextSelectedKey = k
    end
    if not suppressUIRefresh and type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then
        _G.MSUF_Options_RefreshHPSpacerControls()
    end
    if not suppressUIRefresh and type(_G.MSUF_Options_RefreshPowerSpacerControls) == "function" then
        _G.MSUF_Options_RefreshPowerSpacerControls()
    end
 end

-- Alpha system moved to MSUF_Alpha.lua


-- Castbar preview toggle moved to MSUF_Castbars.lua

local function KillFrame(frame, allowInEditMode)
    if not frame then  return end
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
    if not PlayerFrame then  return end
    if not MSUF_DB or not MSUF_DB.general then  return end
    local g = MSUF_DB.general
    if g.disableBlizzardUnitFrames == false then  return end
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
            if not PlayerFrame or not PlayerFrame.MSUF_CompatAnchorActive then  return end
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
    if not MSUF_DB then EnsureDB() end
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
                sel:SetScript("OnShow", function(f)  f:Hide()  end)
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
    if not frame or not frame.unit then  return end
    if frame.unit == "player" then  return end
if not MSUF_DB then EnsureDB() end
local confKey
if frame.isBoss or (type(frame.unit) == "string" and frame.unit:match("^boss%d+$")) then
    confKey = "boss"
else
    confKey = frame.unit
end
local conf = (type(MSUF_DB) == "table" and confKey and MSUF_DB[confKey]) or nil
if ns.UF.IsDisabled(conf) then
    -- In MSUF Edit Mode, keep disabled frames editable by allowing forceShow previews.
    -- Boss frames remain hard-hidden when disabled (see Boss preview invariants).
    if not (forceShow and MSUF_UnitEditModeActive and (not (F.InCombatLockdown and F.InCombatLockdown())) and frame and not frame.isBoss) then
        ns.UF.ForceVisibilityHidden(frame)
        return
    end
end
    local drv = frame._msufVisibilityDriver
    if not drv then
        drv = MSUF_GetVisibilityDriverForUnit(frame.unit)
        frame._msufVisibilityDriver = drv
    end
    if not drv then  return end
    local rsd = _G and _G.RegisterStateDriver
    local usd = _G and _G.UnregisterStateDriver
    if type(rsd) ~= "function" or type(usd) ~= "function" then  return end
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
local _iterState = {}

local function _Iter_ApplyVisDriver(f)
    MSUF_ApplyUnitVisibilityDriver(f, _iterState.forceShow)
end
local function MSUF_RefreshAllUnitVisibilityDrivers(forceShow)
    _iterState.forceShow = forceShow
    MSUF_ForEachUnitFrame(_Iter_ApplyVisDriver)
 end
_G.MSUF_RefreshAllUnitVisibilityDrivers = MSUF_RefreshAllUnitVisibilityDrivers
local MSUF_GridFrame
local function _Iter_RefreshFrame(f)
    if f and f.unit and f.hpBar then
        ns.UF.RequestUpdate(f, true, false, "RefreshAllFrames")
    end
end
function ns.MSUF_RefreshAllFrames()
    MSUF_ForEachUnitFrame(_Iter_RefreshFrame)
 end
function _G.__MSUF_UFREQ_Flush()
    local co = _G.__MSUF_UFREQ_CO
    if not co then  return end
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
    -- Accept both frame objects and unit tokens ("target", "focus", "boss1", ...).
    -- Several callers (eg. RangeFade) operate on unit tokens; UFCore expects actual frame objects.
    if type(frame) == "string" then
        frame = _G["MSUF_" .. frame]
    end
    if not frame then  return end
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
    if type(OpenPage) ~= "function" then  return end
    OpenPage("options")
    C_Timer.After(0, function()
        local p = _G and _G.MSUF_OptionsPanel
        if not p or type(MSUF_GetTabButtonHelpers) ~= "function" then  return end
        local _, setKey = MSUF_GetTabButtonHelpers(p)
        if type(setKey) == "function" then
            setKey(tabKey)
            if p.LoadFromDB then p:LoadFromDB() end
    end
     end)
 end
local function MSUF_OpenOptionsToUnitMenu(unitKey)
    if not unitKey then  return end
    local OpenPage = _G and _G.MSUF_OpenPage
    if type(OpenPage) ~= "function" then  return end
    local k = string.lower(tostring(unitKey))
    if string.match(k, "^boss%d+$") then k = "boss" end
    OpenPage("uf_" .. k)
 end
_G.MSUF_OpenOptionsToUnitMenu = MSUF_OpenOptionsToUnitMenu
local function MSUF_OpenOptionsToCastbarMenu(unitKey)
    if not unitKey then  return end
    local OpenPage = _G and _G.MSUF_OpenPage
    if type(OpenPage) ~= "function" then  return end
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

-- UpdateCastbarVisuals moved to MSUF_Castbars.lua

local function MSUF_UpdateNameColor(frame)
    if not frame or not frame.nameText then  return end

    local cache
    local getCache = ns and ns.Cache and ns.Cache._UFCoreGetSettingsCache
    if not getCache then
        getCache = _G.MSUF_UFCore_GetSettingsCache
        if type(getCache) == "function" and ns and ns.Cache then
            ns.Cache._UFCoreGetSettingsCache = getCache
        else
            getCache = nil
        end
    end
    if getCache then
        cache = getCache()
    end

    local g = (cache and cache.generalRef) or ((MSUF_DB and MSUF_DB.general) or nil)
    if not g then
        if not MSUF_DB then EnsureDB() end
        g = (MSUF_DB and MSUF_DB.general) or nil
    end

    local nameClassColor = (cache and cache.nameClassColor) or (g and g.nameClassColor)
    local npcNameRed = (cache and cache.npcNameRed) or (g and g.npcNameRed)

    local r, gCol, b
    if nameClassColor and frame.unit and F.UnitIsPlayer(frame.unit) then
        local _, classToken = F.UnitClass(frame.unit)
        if classToken then
            local fast = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fast) == "function" then
                r, gCol, b = fast(classToken)
            else
                r, gCol, b = MSUF_GetClassBarColor(classToken)
            end
        end
    end
    if (not (r and gCol and b)) and npcNameRed and frame.unit and not F.UnitIsPlayer(frame.unit) then
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost(frame.unit) then
            do
                local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                if type(fastNPC) == "function" then
                    r, gCol, b = fastNPC("dead")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("dead")
                end
            end
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", frame.unit)
            if reaction then
                if reaction >= 5 then
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("friendly")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                        end
                    end
                elseif reaction == 4 then
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("neutral")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                        end
                    end
                else
                    do
                        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
                        if type(fastNPC) == "function" then
                            r, gCol, b = fastNPC("enemy")
                        else
                            r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                        end
                    end
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
local function _Iter_RefreshNameColor(f)
    if f and f.nameText and f.unit and F.UnitExists(f.unit) then
        MSUF_UpdateNameColor(f)
    end
end
_G.MSUF_RefreshAllIdentityColors = function()
    if type(_G.MSUF_DB) ~= "table" then  return end
    if type(MSUF_UpdateNameColor) ~= "function" or type(F.UnitExists) ~= "function" then  return end
    MSUF_ForEachUnitFrame(_Iter_RefreshNameColor)
 end
local function _Iter_RefreshPowerColor(f)
    local S = _iterState
    if f and f.powerText and f.unit and F.UnitExists(f.unit) then
        if S.colorByType then
            if S.updatePowerFast then
                S.updatePowerFast(f)
            end
        else
            local fr, fg, fb = S.fr, S.fg, S.fb
            if f.powerText.SetTextColor then
                f.powerText:SetTextColor(fr, fg, fb, 1)
                f.powerText._msufColorRev = nil
            end
            if f.powerTextPct and f.powerTextPct.SetTextColor then
                f.powerTextPct:SetTextColor(fr, fg, fb, 1)
                f.powerTextPct._msufColorRev = nil
            end
        end
    end
end
_G.MSUF_RefreshAllPowerTextColors = function()
    if type(_G.MSUF_DB) ~= "table" then  return end
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local enabled = (g and g.colorPowerTextByType == true)
    if type(F.UnitExists) ~= "function" then  return end
    _iterState.colorByType = enabled
    _iterState.updatePowerFast = _G.MSUF_UFCore_UpdatePowerTextFast
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    _iterState.fr = fr
    _iterState.fg = fg
    _iterState.fb = fb
    MSUF_ForEachUnitFrame(_Iter_RefreshPowerColor)
 end

-- Gradient system + Absorb bars moved to MSUF_Gradients.lua

local function PositionUnitFrame(f, unit)
    if not f or not unit then  return end
    if f._msufDragActive then  return end
    local key = f.msufConfigKey
    if not key then
        key = GetConfigKeyForUnit(unit)
        f.msufConfigKey = key
    end
    if not key then  return end
    if F.InCombatLockdown() then
         return
    end
    local conf = f.cachedConfig
    if not conf then
        if not MSUF_DB then EnsureDB() end
        conf = MSUF_DB and MSUF_DB[key]
        f.cachedConfig = conf
    end
    if not conf then  return end
    local anchor = MSUF_GetAnchorFrame()
    -- Pet-only: allow anchoring the pet frame relative to Player/Target.
    -- This is a pure anchor swap; offsets remain the same (measured from the chosen anchor).
    if key == "pet" and conf and (conf.anchorToUnitframe == "player" or conf.anchorToUnitframe == "target") then
        local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
        if conf.anchorToUnitframe == "player" then
            anchor = (uf and (uf.player or uf["player"])) or _G.MSUF_player or anchor
        elseif conf.anchorToUnitframe == "target" then
            anchor = (uf and (uf.target or uf["target"])) or _G.MSUF_target or anchor
        end
    end
    local ecv = _G["EssentialCooldownViewer"]
    local _g = MSUF_DB and MSUF_DB.general
    if _g and _g.anchorToCooldown and ecv and anchor == ecv then
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
        if conf.invertBossOrder then spacing = -spacing end
        local y = conf.offsetY + (index - 1) * spacing
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", x, y)
    else
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
    end
 end
local _MSUF_MeasureCache = {}
local _MSUF_MeasureFS

local function MSUF_MeasureTextWidth(templateFS, sampleText)
    if not templateFS or not templateFS.GetFont then return 0 end
    local font, size, flags = templateFS:GetFont()
    if not font then return 0 end
    local cacheKey = tostring(font) .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "") .. "|" .. sampleText
    local cached = _MSUF_MeasureCache[cacheKey]
    if cached then return cached end
    if not _MSUF_MeasureFS then
        local holder = F.CreateFrame("Frame", "MSUF_MeasureFrame", UIParent)
        holder:Hide()
        _MSUF_MeasureFS = holder:CreateFontString(nil, "OVERLAY")
        _MSUF_MeasureFS:Hide()
    end
    _MSUF_MeasureFS:SetFont(font, size, flags)
    _MSUF_MeasureFS:SetText(sampleText)
    local w = _MSUF_MeasureFS:GetStringWidth() or 0
    w = tonumber(w) or 0
    if w < 0 then w = 0 end
    w = math.ceil(w + 2)
    _MSUF_MeasureCache[cacheKey] = w
    return w
end

local function MSUF_GetApproxPercentTextWidth(templateFS)
    return MSUF_MeasureTextWidth(templateFS, "100.0%")
end

local function MSUF_GetApproxHpFullTextWidth(templateFS)
    return MSUF_MeasureTextWidth(templateFS, "999.9M")
end
local MSUF_HP_SPACER_SCALE = 1.15
local MSUF_HP_SPACER_MAXCAP = 2000
function _G.MSUF_GetHPSpacerMaxForUnitKey(unitKey)
    if not MSUF_DB then EnsureDB() end
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
    local g = MSUF_DB.general or {}
    local conf = MSUF_DB[k] or {}
    local hX = ns.Util.Offset(conf.hpOffsetX, -4)
    local leftPad = 8
    local pctW = 0
    if f and f.hpTextPct then
        pctW = MSUF_GetApproxPercentTextWidth(f.hpTextPct)
    end
    local useOverride = (conf and conf.hpPowerTextOverride == true)
    local hpMode = (useOverride and conf.hpTextMode) or g.hpTextMode or "FULL_PLUS_PERCENT"
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
    if not MSUF_DB then EnsureDB() end
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
    local g = MSUF_DB.general or {}
    local conf = MSUF_DB[k] or {}
    local pX = ns.Util.Offset(conf.powerOffsetX, -4)
    local leftPad = 8
    local pctW = 0
    if f and f.powerTextPct then
        pctW = MSUF_GetApproxPercentTextWidth(f.powerTextPct)
    elseif f and f.powerText then
        pctW = MSUF_GetApproxPercentTextWidth(f.powerText)
    end
    local useOverride = (conf and conf.hpPowerTextOverride == true)
    local pMode = (useOverride and conf.powerTextMode) or g.powerTextMode or "FULL_PLUS_PERCENT"
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
-- Resolve a text anchor setting ("RIGHT"/"LEFT"/"CENTER") into layout params.
-- isTop: true for HP (top row), false for Power (bottom row)
local function MSUF_ResolveTextAnchor(anchor, isTop)
    if anchor == "LEFT" then
        local pt = isTop and "TOPLEFT" or "BOTTOMLEFT"
        return pt, pt, 4, "LEFT", 1    -- defX, justifyH, spacerSign (+1 = grow right)
    elseif anchor == "CENTER" then
        local pt = isTop and "TOP" or "BOTTOM"
        return pt, pt, 0, "CENTER", 1  -- spacer grows right from center
    else -- "RIGHT" (default)
        local pt = isTop and "TOPRIGHT" or "BOTTOMRIGHT"
        return pt, pt, -4, "RIGHT", -1 -- spacerSign (-1 = grow left)
    end
end
local function MSUF_TextLayout_GetSpacer(key, udb, g, hasPct, spec)
    if not hasPct then  return false, 0 end
    -- One-time seed: make Shared spacers start like Player (if Shared keys are missing).
    if g and _G.MSUF_TextSpacersSeeded ~= true then
        local p = (MSUF_DB and MSUF_DB.player) or nil
        if p then
            if g.hpTextSpacerEnabled == nil and p.hpTextSpacerEnabled ~= nil then g.hpTextSpacerEnabled = p.hpTextSpacerEnabled end
            if g.hpTextSpacerX == nil and p.hpTextSpacerX ~= nil then g.hpTextSpacerX = p.hpTextSpacerX end
            if g.powerTextSpacerEnabled == nil and p.powerTextSpacerEnabled ~= nil then g.powerTextSpacerEnabled = p.powerTextSpacerEnabled end
            if g.powerTextSpacerX == nil and p.powerTextSpacerX ~= nil then g.powerTextSpacerX = p.powerTextSpacerX end
        end
        _G.MSUF_TextSpacersSeeded = true
    end
    local on = ((udb and udb[spec.spacerOn] == true) or (not udb and g and g[spec.spacerOn] == true)) or false
    local x  = (udb and tonumber(udb[spec.spacerX])) or ((g and tonumber(g[spec.spacerX])) or 0)
    local max = (key and spec.maxFn and spec.maxFn(key)) or 0
    return on, ns.Text.ClampSpacerValue(x, max, on)
end
local function MSUF_TextLayout_ApplyGroup(f, tf, conf, spec, mode, hasPct, on, eff, anchorPt, anchorRelPt, anchorDefX, anchorJustify, anchorSign)
    local fullObj, pctObj = f[spec.full], f[spec.pct]
    if not (fullObj or hasPct) then  return end
    local pt    = anchorPt or spec.point
    local relPt = anchorRelPt or spec.relPoint
    local dX    = anchorDefX or spec.defX
    local sign  = anchorSign or -1
    local baseX = ns.Util.Offset(conf[spec.xKey], dX)
    local baseY = ns.Util.Offset(conf[spec.yKey], spec.defY)
    local fullX, pctX = baseX, baseX
    local canSplit = hasPct and on and eff ~= 0 and (not spec.limitMode or mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL")
    if canSplit then if mode == "FULL_PLUS_PERCENT" then fullX = baseX + sign * eff else pctX = baseX + sign * eff end end
    if fullObj then
        MSUF_ApplyPoint(fullObj, pt, tf, relPt, fullX, baseY)
        if anchorJustify and fullObj.SetJustifyH then fullObj:SetJustifyH(anchorJustify) end
    end
    if hasPct then
        MSUF_ApplyPoint(pctObj, pt, tf, relPt, pctX, baseY)
        if anchorJustify and pctObj and pctObj.SetJustifyH then pctObj:SetJustifyH(anchorJustify) end
    end
 end
local function ApplyTextLayout(f, conf)
    if not f or not f.textFrame or not conf then  return end
    local tf = f.textFrame
    local nX = ns.Util.Offset(conf.nameOffsetX,  4)
    local nY = ns.Util.Offset(conf.nameOffsetY, -4)
    local key = f.msufConfigKey
    if not key and f.unit and GetConfigKeyForUnit then key = GetConfigKeyForUnit(f.unit) end
    local udb = (MSUF_DB and key and MSUF_DB[key]) or nil
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local useOverride = (udb and udb.hpPowerTextOverride == true)
    local hpMode = (useOverride and udb.hpTextMode) or (g and g.hpTextMode) or "FULL_PLUS_PERCENT"
    local pMode  = (useOverride and udb.powerTextMode) or (g and g.powerTextMode) or "FULL_PLUS_PERCENT"
    -- Text anchors: per-unit  general  default RIGHT (no override gate; set per-unit via EditMode popup)
    local hpAnchor    = (udb and udb.hpTextAnchor)    or (g and g.hpTextAnchor)    or "RIGHT"
    local powerAnchor = (udb and udb.powerTextAnchor) or (g and g.powerTextAnchor) or "RIGHT"
    local nameAnchor  = (udb and udb.nameTextAnchor)  or "LEFT"
    local hpPt, hpRelPt, hpDefX, hpJustify, hpSign       = MSUF_ResolveTextAnchor(hpAnchor, true)
    local pwrPt, pwrRelPt, pwrDefX, pwrJustify, pwrSign   = MSUF_ResolveTextAnchor(powerAnchor, false)
    local hpHasPct = (f[MSUF_TEXT_LAYOUT_HP.pct] ~= nil)
    local pHasPct  = (f[MSUF_TEXT_LAYOUT_PWR.pct] ~= nil)
    -- Spacers inherit Shared unless per-unit override is enabled.
    local spacerDB = useOverride and udb or nil
    local hpOn, hpEff = MSUF_TextLayout_GetSpacer(key, spacerDB, g, hpHasPct, MSUF_TEXT_LAYOUT_HP)
    local pOn,  pEff  = MSUF_TextLayout_GetSpacer(key, spacerDB, g, pHasPct,  MSUF_TEXT_LAYOUT_PWR)
    local hX = ns.Util.Offset(conf.hpOffsetX,    -4)
    local hY = ns.Util.Offset(conf.hpOffsetY,    -4)
    local pX = ns.Util.Offset(conf.powerOffsetX, -4)
    local pY = ns.Util.Offset(conf.powerOffsetY,  4)
    local wUsed = (f and f.GetWidth and f:GetWidth()) or 0
    if (not wUsed or wUsed == 0) and tf and tf.GetWidth then wUsed = tf:GetWidth() or 0 end
    if (not wUsed or wUsed == 0) and conf then wUsed = tonumber(conf.width) or wUsed end
    wUsed = tonumber(wUsed) or 0
    if not ns.Cache.StampChanged(f, "TextLayout", tf, nX, nY, hX, hY, pX, pY, hpHasPct, hpOn, hpEff, wUsed, (key or ""), (hpMode or ""), pHasPct, pOn, pEff, (pMode or ""), (hpAnchor or ""), (powerAnchor or ""), (nameAnchor or "")) then  return end
    f._msufTextLayoutStamp = 1
    if f.nameText then
        -- Resolve name anchor: LEFT (default), CENTER, RIGHT
        local namePt, nameRelPt, nameDefX
        if nameAnchor == "RIGHT" then
            namePt, nameRelPt, nameDefX = "TOPRIGHT", "TOPRIGHT", -nX
        elseif nameAnchor == "CENTER" then
            namePt, nameRelPt, nameDefX = "TOP", "TOP", 0
        else
            namePt, nameRelPt, nameDefX = "TOPLEFT", "TOPLEFT", nX
        end
        MSUF_ApplyPoint(f.nameText, namePt, tf, nameRelPt, nameDefX, nY)
        if f.nameText.SetJustifyH then f.nameText:SetJustifyH(nameAnchor == "RIGHT" and "RIGHT" or nameAnchor == "CENTER" and "CENTER" or "LEFT") end
        f._msufNameAnchorPoint, f._msufNameAnchorRel, f._msufNameAnchorRelPoint, f._msufNameAnchorX, f._msufNameAnchorY = namePt, tf, nameRelPt, nameDefX, nY
        f._msufNameClipSideApplied, f._msufNameClipReservedRight, f._msufNameClipTextStamp, f._msufNameClipAnchorStamp, f._msufClampStamp = nil, nil, nil, nil, nil
    end
    if f.levelText and f.nameText then MSUF_ApplyLevelIndicatorLayout_Internal(f, conf) end
    -- HP group uses hpMode (shifts pct side for any non FULL_PLUS_PERCENT, matching legacy behavior).
    MSUF_TextLayout_ApplyGroup(f, tf, conf, MSUF_TEXT_LAYOUT_HP,  hpMode, hpHasPct, hpOn, hpEff, hpPt, hpRelPt, hpDefX, hpJustify, hpSign)
    MSUF_TextLayout_ApplyGroup(f, tf, conf, MSUF_TEXT_LAYOUT_PWR, pMode,  pHasPct,  pOn,  pEff, pwrPt, pwrRelPt, pwrDefX, pwrJustify, pwrSign)
 end
function _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
    if not MSUF_DB then EnsureDB() end
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey)
    local function ApplyForFrame(f)
        if not f then  return end
        f._msufTextLayoutStamp = nil
        ns.Cache.ClearStamp(f, "TextLayout")
        local key = f.msufConfigKey
        if not key and f.unit then
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
        if not conf then  return end
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
            hasUnit = F.UnitExists(unit) and true or false
    end
        if hasUnit and F.UnitHealth then
            local hp = F.UnitHealth(unit)
            if hp ~= nil then
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

-- Portrait system moved to MSUF_Portraits.lua

local function MSUF_GetApproxNameWidthForChars(templateFS, maxChars)
    if not templateFS or not templateFS.GetFont then return nil end
    maxChars = tonumber(maxChars) or 16
    if maxChars < 1 then maxChars = 1 end
    if maxChars > 60 then maxChars = 60 end
    local font, size, flags = templateFS:GetFont()
    if not font then return nil end
    local fontKey = tostring(font) .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_NameWidthAvgCache = _G.MSUF_NameWidthAvgCache or {}
    local avg = _G.MSUF_NameWidthAvgCache[fontKey]
    if not avg then
        if not _MSUF_MeasureFS then
            local holder = F.CreateFrame("Frame", "MSUF_MeasureFrame", UIParent)
            holder:Hide()
            _MSUF_MeasureFS = holder:CreateFontString(nil, "OVERLAY")
            _MSUF_MeasureFS:Hide()
        end
        _MSUF_MeasureFS:SetFont(font, size, flags)
        local sample = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        _MSUF_MeasureFS:SetText(sample)
        local w = _MSUF_MeasureFS:GetStringWidth()
        avg = (type(w) == "number" and w > 0) and (w / #sample) or ((tonumber(size) or 12) * 0.55)
        _G.MSUF_NameWidthAvgCache[fontKey] = avg
    end
    return avg * maxChars
end
local _AP_HASH = { TOPLEFT=1, TOP=2, TOPRIGHT=3, LEFT=4, CENTER=5, RIGHT=6, BOTTOMLEFT=7, BOTTOM=8, BOTTOMRIGHT=9 }
function MSUF_ClampNameWidth(f, conf)
    if not f or not f.nameText then  return end
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
        local stamp = (_AP_HASH[ap] or 0) * 100003 + (_AP_HASH[arp] or 0) * 10007 + math_floor((ax + 200) * 100) * 101 + math_floor((ay + 200) * 100)
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
    local stamp = 1000000000
              + frameWidth * 1000003
              + baseWidth * 100003
              + reservedRight * 10007
              + nameWidth * 1009
              + maxChars * 101
              + (lvlShown and 70001 or 0)
              + (_AP_HASH[ap] or 0) * 7000003
              + (_AP_HASH[arp] or 0) * 700003
              + math_floor((ax + 200) * 100) * 71
              + math_floor((ay + 200) * 100) * 7
              + (mode == "LEFT" and 3 or 0)
              + maskPx * 17
              + (showDots and 1 or 0)
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
    local anchorStamp = (_AP_HASH[ap] or 0) * 100000007
        + (_AP_HASH[arp] or 0) * 10000019
        + math_floor((ax + 200) * 100) * 100003
        + math_floor((ay + 200) * 100) * 10007
        + (clipSide == "LEFT" and 1000003 or 0)
        + maskPx * 1009
        + clipW * 101
        + clipH
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
    local textStamp = (clipSide == "LEFT") and 1 or 2
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
        local dotStamp = (clipSide == "LEFT" and 10000019 or 0)
            + maskPx * 100003
            + (_AP_HASH[ap] or 0) * 10007
            + (_AP_HASH[arp] or 0) * 1009
            + math_floor((ax + 200) * 100) * 101
            + math_floor((ay + 200) * 100) * 7
            + nameWidth
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
    if not unit or not UnitLevel then  return "" end
    local lvl = UnitLevel(unit)
    if not lvl then  return "" end
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
    if not MSUF_DB then EnsureDB() end
    local db = MSUF_DB
    if not db then  return nil, nil, nil end
    local g = db.general or {}
    local key = (f and f.unit) and GetConfigKeyForUnit(f.unit) or nil
    return g, key, (key and db[key]) or nil
end
function ns.Icons._layout.Resolve(anchor, allowCenter)
    if allowCenter and anchor == "CENTER" then  return "CENTER", "CENTER"
    elseif anchor == "TOPRIGHT" then  return "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then  return "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then  return "RIGHT", "BOTTOMRIGHT" end
     return "LEFT", "TOPLEFT"
end
function ns.Icons._layout.Apply(icon, owner, size, point, relPoint, ox, oy)
    icon:SetSize(size, size); icon:ClearAllPoints(); icon:SetPoint(point, owner, relPoint, ox, oy)
 end
function MSUF_ApplyLeaderIconLayout(f)
    if not f or not f.leaderIcon then  return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then  return end
    local size = ns.Util.Num(conf, g, "leaderIconSize", 14)
size = math.floor(size + 0.5); if size < 8 then size = 8 elseif size > 64 then size = 64 end
local ox = ns.Util.Num(conf, g, "leaderIconOffsetX", 0)
local oy = ns.Util.Num(conf, g, "leaderIconOffsetY", 3)
local anchor = ns.Util.Val(conf, g, "leaderIconAnchor", "TOPLEFT")
    if not ns.Cache.StampChanged(f, "LeaderIconLayout", size, ox, oy, anchor, (key or "")) then  return end
f._msufLeaderIconLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, false)
    ns.Icons._layout.Apply(f.leaderIcon, f, size, point, relPoint, ox, oy)
    if f.assistantIcon then
        ns.Icons._layout.Apply(f.assistantIcon, f, size, point, relPoint, ox, oy - (size - 1))
    end
 end
function MSUF_ApplyRaidMarkerLayout(f)
    if not f or not f.raidMarkerIcon then  return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then  return end
    if g.raidMarkerSize == nil then g.raidMarkerSize = 14 end
    local size = ns.Util.Num(conf, g, "raidMarkerSize", 14)
size = math.floor(size + 0.5); if size < 8 then size = 8 elseif size > 64 then size = 64 end
local ox = ns.Util.Num(conf, g, "raidMarkerOffsetX", 16)
local oy = ns.Util.Num(conf, g, "raidMarkerOffsetY", 3)
local anchor = ns.Util.Val(conf, g, "raidMarkerAnchor", "TOPLEFT")
    if not ns.Cache.StampChanged(f, "RaidMarkerLayout", size, ox, oy, anchor, (key or "")) then  return end
f._msufRaidMarkerLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, true)
    ns.Icons._layout.Apply(f.raidMarkerIcon, f, size, point, relPoint, ox, oy)
 end
function _G.MSUF_UFCore_UpdateHealthFast(self)
    if not self then  return nil, nil, false end
    return ns.Bars.ApplySpec(self, self.unit, "health")
end
function _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    if not self or not self.unit or not self.hpText then  return end
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
    -- Per-unit absorb text display: resolve from unit override or fall back to general.
    local _showAbsorbText = false
    local _resolveAbsorb = ns.Bars and ns.Bars._ResolveAbsorbDisplay
    if type(_resolveAbsorb) == "function" then
        local _, showText = _resolveAbsorb(unit)
        _showAbsorbText = showText
    else
        _showAbsorbText = (g.showTotalAbsorbAmount == true)
    end
    if _showAbsorbText and UnitGetTotalAbsorbs then
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
    if not self or not self.hpText then  return end
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
    if not self then  return end
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

-- Edit Mode unitframe preview:
-- When a unitframe has no unit (or is disabled) we still want a persistent, simple preview
-- so it can be positioned/edited. This is intentionally a "dark bar" placeholder and
-- must never run in combat.
local function MSUF_ApplyUnitframeEditPreview(self, key, conf, g)
    if not self or self.isBoss then  return end
    if F.InCombatLockdown and F.InCombatLockdown() then  return end
    if not MSUF_DB then EnsureDB() end
    g = g or ((MSUF_DB and MSUF_DB.general) or {})

    if self.Show then self:Show() end
    if type(_G.MSUF_ApplyUnitAlpha) == "function" then
        _G.MSUF_ApplyUnitAlpha(self, key or self.unit)
    end

    -- Clear any sticky state from previously shown units.
    MSUF_ClearUnitFrameState(self, true)

    if self.portrait and self.portrait.Hide then self.portrait:Hide() end

    -- Use stable, constant fake values so text/offsets can be edited visually.
    -- (No secret-value interaction, no unit API reads.)
    local fakeHp = 0.73
    local fakePower = 0.52

    local hb = self.hpBar
    if hb then
        MSUF_SetBarMinMax(hb, 0, 1)
        MSUF_SetBarValue(hb, fakeHp, false)

        -- Use the configured dark tone (defaults to black) for a consistent placeholder.
        local darkR, darkG, darkB = 0, 0, 0
        local _gray = g.darkBarGray
        if type(_gray) == "number" then
            if _gray < 0 then _gray = 0 elseif _gray > 1 then _gray = 1 end
            darkR, darkG, darkB = _gray, _gray, _gray
        else
            local toneKey = g.darkBarTone or "black"
            local tone = MSUF_DARK_TONES and MSUF_DARK_TONES[toneKey]
            if tone then
                darkR, darkG, darkB = tone[1] or 0, tone[2] or 0, tone[3] or 0
            end
        end
        if hb.SetStatusBarColor then hb:SetStatusBarColor(darkR, darkG, darkB, 1) end
        if self.bg then
            MSUF_ApplyBarBackgroundVisual(self)
        end
        if self.hpGradients then
            ns.Bars._ApplyHPGradient(self)
        elseif self.hpGradient then
            ns.Bars._ApplyHPGradient(self.hpGradient)
        end
    end

    -- Show a fake power bar + fake power text so offsets can be edited.
    local pb = self.targetPowerBar or self.powerBar
    if pb then
        if pb.Show then pb:Show() end
        MSUF_SetBarMinMax(pb, 0, 1)
        MSUF_SetBarValue(pb, fakePower, false)
        if pb.SetStatusBarColor then
            -- Simple, readable "mana-like" placeholder.
            pb:SetStatusBarColor(0.20, 0.60, 1.00, 1)
        end
        -- If the bar has its own background texture, keep it visible.
        if pb.bg and pb.bg.Show then pb.bg:Show() end
    end

    -- If both a "main" powerBar and a "targetPowerBar" exist, make sure only one is shown.
    if self.targetPowerBar and self.powerBar and self.powerBar ~= self.targetPowerBar then
        if pb == self.targetPowerBar then
            if self.powerBar.Hide then self.powerBar:Hide() end
        else
            if self.targetPowerBar.Hide then self.targetPowerBar:Hide() end
        end
    end

    local SetShown = (ns and ns.Util and ns.Util.SetShown) or nil

    -- Placeholder label (safe constant).
    local label = key or self.unit or "unit"
    if label == "targettarget" then label = "ToT" end
    if type(label) ~= "string" then label = tostring(label) end
    local upper = (string and string.upper and string.upper(label)) or label

    if self.nameText and self.nameText.SetText then
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.nameText, upper)
        else
            self.nameText:SetText(upper)
        end
        if SetShown then SetShown(self.nameText, true) end
    end

    if self.hpText and self.hpText.SetText then
        -- Fake HP text (constant) so users can position/size text reliably.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.hpText, "73% 123.4k")
        else
            self.hpText:SetText("73% 123.4k")
        end
        if SetShown then SetShown(self.hpText, true) end
    end

    if self.powerText and self.powerText.SetText then
        -- Fake power text for edit positioning.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.powerText, "52% 65")
        else
            self.powerText:SetText("52% 65")
        end
        if SetShown then SetShown(self.powerText, true) end
    end

    if self.levelText and self.levelText.SetText then
        -- Show a stable fake level value.
        if type(MSUF_SetTextIfChanged) == "function" then
            MSUF_SetTextIfChanged(self.levelText, "70")
        else
            self.levelText:SetText("70")
        end
        if SetShown then SetShown(self.levelText, true) end
    end

    -- Portrait preview (2D/3D placeholder + Class Icon mode)
    if self.portrait and conf then
        local pm = conf.portraitMode or "OFF"
        if pm ~= "OFF" then
            if type(_G.MSUF_UpdateBossPortraitLayout) == "function" then
                _G.MSUF_UpdateBossPortraitLayout(self, conf)
            end

            local pr = conf.portraitRender
            if pr == "CLASS" then
                local class = (F.UnitClassBase and F.UnitClassBase("player")) or (F.UnitClass and select(2, F.UnitClass("player")))
                local coords = (class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]) or nil
                if coords and self.portrait.SetTexture and self.portrait.SetTexCoord then
                    self.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    self.portrait:SetTexCoord(coords[1] or 0, coords[2] or 1, coords[3] or 0, coords[4] or 1)
                elseif self.portrait.SetTexture then
                    self.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                    if self.portrait.SetTexCoord then
                        self.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    end
                end
            else
                -- Placeholder portrait (question mark) so the portrait position/size can be edited.
                if self.portrait.SetTexture then
                    self.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end
                if self.portrait.SetTexCoord then
                    self.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                end
            end

            if self.portrait.Show then self.portrait:Show() end
        else
            if self.portrait.Hide then self.portrait:Hide() end
        end
    end

    ns.UF.HideLeaderAndRaidMarker(self)
    self._msufNoUnitCleared = nil
end
_G.MSUF_ApplyUnitframeEditPreview = MSUF_ApplyUnitframeEditPreview

-- =========================================================================
-- HOT-PATH LOCAL CACHE
-- Resolve _G function references once; avoids hash lookup on every call.
-- Functions are defined above this point or in files loaded earlier (TOC).
-- Mutable state (_G.MSUF_UnitTokenChanged, _G.MSUF_UFCORE_FLUSH_SERIAL)
-- stays on _G since the values change every flush.
-- =========================================================================
local _MSUF_ApplyUnitAlpha  -- resolved lazily (Core/MSUF_Alpha.lua loads after main)
local _MSUF_MaybeUpdatePortrait  -- resolved lazily (Core/MSUF_Portraits.lua loads after main)
local _MSUF_ApplyUnitframeEditPreview  -- resolved lazily
local _MSUF_UFCore_UpdateHpTextFast    = _G.MSUF_UFCore_UpdateHpTextFast
local _MSUF_UFCore_UpdatePowerTextFast = _G.MSUF_UFCore_UpdatePowerTextFast
local _MSUF_UFCore_UpdatePowerBarFast  = _G.MSUF_UFCore_UpdatePowerBarFast
local _MSUF_ApplyBossTestHpPreviewText = _G.MSUF_ApplyBossTestHpPreviewText
local _MSUF_QueueUnitframeVisual       = _G.MSUF_QueueUnitframeVisual
local _MSUF_ApplyLeaderIconLayout      = MSUF_ApplyLeaderIconLayout
local _MSUF_ApplyRaidMarkerLayout      = MSUF_ApplyRaidMarkerLayout
local _MSUF_TPA_SyncAnchors            -- forward decl: assigned after definition below

local function MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus)
    if not self then  return false end
    MSUF_EnsureUnitFlags(self)
    return ns.Bars.ApplySpec(self, unit, "power_pct", barsConf, self.isBoss, isPlayer, isTarget, isFocus) and true or false
end
local function MSUF_UFStep_BasicHealth(self, unit)
    local hp = ns.Bars.ApplyHealthBars(self, unit)
     return hp
end
local function MSUF_UFStep_HeavyVisual(self, unit, key, g_opt)
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
        local g = g_opt or ((MSUF_DB and MSUF_DB.general) or {})
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
            ns.Bars._ApplyHPGradient(self)
        elseif self.hpGradient then
            ns.Bars._ApplyHPGradient(self.hpGradient)
    end
        if self.bg then
            MSUF_ApplyBarBackgroundVisual(self)
    end
    end
 end
local function MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus)
  local pb = self.targetPowerBar or self.powerBar
  if not (pb and pb.IsShown and pb:IsShown()) then  return false end
  local flag = (self.isBoss and "showBossPowerBar")
            or (isPlayer and "showPlayerPowerBar")
            or (isTarget and "showTargetPowerBar")
            or (isFocus and "showFocusPowerBar")
  if flag and barsConf and barsConf[flag] == false then  return false end
  if MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus) then  return true end
   return false
end
local function MSUF_UFStep_Border(self)
        do
            if self.border then
                self.border:Hide()
            end
            local thickness, stamp = MSUF_GetDesiredBarBorderThicknessAndStamp()
            local pb = self.targetPowerBar
            local pbDetached = self._msufPowerBarDetached
            local bottomIsPower = (pb and not pbDetached and pb.IsShown and pb:IsShown()) and true or false
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
            if need and _MSUF_QueueUnitframeVisual then
                _MSUF_QueueUnitframeVisual(self)
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
if self.leaderIcon and _MSUF_ApplyLeaderIconLayout then _MSUF_ApplyLeaderIconLayout(self) end
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
if self.raidMarkerIcon and _MSUF_ApplyRaidMarkerLayout then _MSUF_ApplyRaidMarkerLayout(self) end
 end
local function MSUF_UFStep_Finalize(self, hp, didPowerBarSync)
    -- Secret-safe text gating + per-flush coalesce (no compares on hp/power values)
    local showHPText = (self.showHPText ~= false)
    local showPowerText = (self.showPowerText ~= false)
    local textStamp = self._msufTextLayoutStamp or 0
    -- Coalesce within the same millisecond-bucket (approx "per-flush" when multiple updates burst)
    local now = GetTime()
    local nowMs = math_floor(now * 1000)
    -- Text state sub-table: reduces hash lookups on the frame object (10 long-key writes ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ short keys on small table)
    local ts = self._msufTS
    if not ts then ts = {}; self._msufTS = ts end
    -- HP text: force when layout/toggle changed, otherwise rate-limit
    local forceHP = (ts[1] ~= textStamp) or (ts[2] ~= showHPText) -- [1]=hpStamp, [2]=showHP
    if showHPText then
        if forceHP or (ts[3] == nil) or ((now - (ts[3] or 0)) >= 0.10) then -- [3]=hpAt
            if forceHP or (ts[4] ~= nowMs) then -- [4]=hpMs
                _MSUF_UFCore_UpdateHpTextFast(self, hp)
                ts[3] = now
                ts[4] = nowMs
            end
        end
    else
        -- still call once on toggle-off so the fast path can hide/clear
        if forceHP then
            _MSUF_UFCore_UpdateHpTextFast(self, hp)
            ts[3] = now
            ts[4] = nowMs
        end
    end
    ts[1] = textStamp
    ts[2] = showHPText
    -- Power text: same gating (no power value reads here)
    local forcePower = (ts[5] ~= textStamp) or (ts[6] ~= showPowerText) -- [5]=pwStamp, [6]=showPw
    if showPowerText then
        if forcePower or (ts[7] == nil) or ((now - (ts[7] or 0)) >= 0.10) then -- [7]=pwAt
            if forcePower or (ts[8] ~= nowMs) then -- [8]=pwMs
                _MSUF_UFCore_UpdatePowerTextFast(self)
                ts[7] = now
                ts[8] = nowMs
            end
        end
    else
        if forcePower then
            _MSUF_UFCore_UpdatePowerTextFast(self)
            ts[7] = now
            ts[8] = nowMs
        end
    end
    ts[5] = textStamp
    ts[6] = showPowerText
    if not didPowerBarSync then
        _MSUF_UFCore_UpdatePowerBarFast(self)
    end
    MSUF_UpdateStatusIndicatorForFrame(self)
 end
function UpdateSimpleUnitFrame(self)
        -- Lazy-resolve split-module upvalues (Core/ files load after main)
        if not _MSUF_ApplyUnitAlpha then _MSUF_ApplyUnitAlpha = _G.MSUF_ApplyUnitAlpha end
        if not _MSUF_MaybeUpdatePortrait then _MSUF_MaybeUpdatePortrait = _G.MSUF_MaybeUpdatePortrait end
        if not _MSUF_ApplyUnitframeEditPreview then _MSUF_ApplyUnitframeEditPreview = _G.MSUF_ApplyUnitframeEditPreview end
        local _flushSerial = _G.MSUF_UFCORE_FLUSH_SERIAL  -- cache once per call

        -- Hot path: prefer UFCore's settings snapshot (avoids repeated deep MSUF_DB traversals).
        local db, g, barsConf

        local getCache = ns and ns.Cache and ns.Cache._UFCoreGetSettingsCache
        if not getCache then
            getCache = _G.MSUF_UFCore_GetSettingsCache
            if type(getCache) == "function" and ns and ns.Cache then
                ns.Cache._UFCoreGetSettingsCache = getCache
            else
                getCache = nil
            end
        end

        if getCache then
            local cache = getCache()
            if cache then
                db = cache.dbRef or _G.MSUF_DB
                g = cache.generalRef
                barsConf = cache.barsRef
            end
        end

        if not db then
            if not MSUF_DB then EnsureDB() end
            db = MSUF_DB
        end

        g = g or ((db and db.general) or {})
        barsConf = barsConf or ((db and db.bars) or {})
    local unit   = self.unit
    MSUF_EnsureUnitFlags(self)
    local isPlayer = self._msufIsPlayer
    local isTarget = self._msufIsTarget
    local isFocus  = self._msufIsFocus
    local isPet    = self._msufIsPet
    local isToT    = self._msufIsToT
    local unitValid = (type(unit) == "string" and unit ~= "") and true or false
    -- Cache UnitExists per UFCore flush (avoid repeated C-calls for same frame).
    local UnitExists = F.UnitExists
    local exists = false
    if unitValid and UnitExists then
        local s = _flushSerial
        if s and self._msufExistsSerial == s and self._msufExistsUnit == unit then
            exists = (self._msufCachedExists == true)
        else
            exists = UnitExists(unit) and true or false
            self._msufCachedExists = exists
            self._msufExistsUnit = unit
            self._msufExistsSerial = s
        end
    else
        -- Keep cache coherent (useful for callers that read the cached fields).
        self._msufCachedExists = false
        self._msufExistsUnit = unit
        self._msufExistsSerial = _flushSerial
    end
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
    ns.Bars._ApplyReverseFillBars(self, conf)
    local didPowerBarSync = false
    if self.isBoss and MSUF_BossTestMode then
        if not F.InCombatLockdown() then
            self:Show()
            _MSUF_ApplyUnitAlpha(self, key)
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
        _MSUF_ApplyBossTestHpPreviewText(self, conf)
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
    -- In MSUF Edit Mode, keep a persistent placeholder for missing units
    -- (so frames stay visible while editing, even when the unit doesn't exist).
    if MSUF_UnitEditModeActive and (not (F.InCombatLockdown and F.InCombatLockdown())) and unit ~= "player" and self and not self.isBoss then
        if _MSUF_ApplyUnitframeEditPreview then
            _MSUF_ApplyUnitframeEditPreview(self, key, conf, g)
        else
            if self.Show then self:Show() end
        end
        return
    end
    if unit ~= "player" and (not MSUF_UnitEditModeActive) and self._msufNoUnitCleared and (self.GetAlpha and self:GetAlpha() or 0) <= 0.01 then
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
    _MSUF_ApplyUnitAlpha(self, key)
    self._msufNoUnitCleared = nil
    if _MSUF_MaybeUpdatePortrait then _MSUF_MaybeUpdatePortrait(self, unit, conf, exists) end
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
        local pbDetached = self._msufPowerBarDetached
        local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
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
        MSUF_UFStep_HeavyVisual(self, unit, key, g)
        MSUF_UFStep_Border(self)
        self._msufLayoutWhy = nil
        self._msufVisualQueuedUFCore = nil
        self._msufNeedsBorderVisual = nil
    end
    -- IMPORTANT: layered alpha uses per-texture alpha, which visual steps reset.
    if conf and conf.alphaExcludeTextPortrait == true then
        _MSUF_ApplyUnitAlpha(self, key)
    end
    if _MSUF_TPA_SyncAnchors then
        _MSUF_TPA_SyncAnchors(self)
    end
 end
do
    local function MSUF_TPA_GetOrCreate(name)
        if not _G or not name then  return nil end
        local f = _G[name]
        if f then  return f end
        f = F.CreateFrame("Frame", name, UIParent)
        f:SetSize(1, 1)
        if f.SetAlpha then f:SetAlpha(0) end
        if f.Show then f:Show() end
        _G[name] = f
         return f
    end
    local function MSUF_TPA_Snap(anchorName, target)
        local a = MSUF_TPA_GetOrCreate(anchorName)
        if not a or not a.ClearAllPoints or not a.SetPoint then  return end
        a:ClearAllPoints()
        a:SetPoint("CENTER", target or UIParent, "CENTER", 0, 0)
     end
    local function MSUF_TPA_SyncFromUnitFrame(uf)
        if not uf or not uf.unit then  return end
        local unit = uf.unit
        if unit ~= "player" and unit ~= "target" then  return end
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
        if not _G or not _G.MSUF_UnitFrames then  return end
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
-- Resolve forward-declared hot-path local (TPA defined above)
_MSUF_TPA_SyncAnchors = _G.MSUF_TPA_SyncAnchors
do
    local function MSUF_TryRegisterBCDMAnchors()
        if _G and _G.MSUF_BCDM_AnchorsRegistered then  return true end
        if not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.IsAddOnLoaded("BetterCooldownManager") then  return false end
        if not _G or not _G.BCDMG or type(_G.BCDMG.AddAnchors) ~= "function" then  return false end
        local function MSUF_BCDM_AddAnchors(addOnName, addToTypes, anchorTable)
            local api = _G and _G.BCDMG
            if not api then  return false end
            local fn = api.AddAnchors
            if type(fn) ~= "function" then  return false end
            local ok = MSUF_FastCall(fn, api, addOnName, addToTypes, anchorTable)
            if ok then  return true end
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

-- Borders system (aggro/dispel/purge outlines + UI_SCALE handler) moved to MSUF_Borders.lua

local function MSUF_ApplyUnitFrameKey_Immediate(key)
    if not MSUF_DB then EnsureDB() end
    local conf = MSUF_DB[key]
    if not conf then  return end
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
        -- In MSUF Edit Mode, keep disabled frames visible as previews so edits remain persistent.
        -- Boss frames must remain hard-hidden when disabled.
        if MSUF_UnitEditModeActive and (not (F.InCombatLockdown and F.InCombatLockdown())) and key ~= "boss" then
            local function previewFrame(unit)
                local f = UnitFrames[unit]
                if not f then  return end
                f.cachedConfig = conf
                if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
                    if f._msufVisibilityForced == "disabled" then
                        f._msufVisibilityForced = nil
                    end
                    MSUF_ApplyUnitVisibilityDriver(f, true)
                end
                if f.Show then f:Show() end
                ns.UF.RequestUpdate(f, true, false, "ApplyUnitKey:DisabledEditPreview")
            end
            if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
                previewFrame(key)
            end
            return
        end

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
        if not f then  return end
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
        -- Live-apply per-unit reverse fill (HP/Power) when applying settings from Options.
        -- This used to require /reload because ApplyUnitKey is a layout-only path.
        ns.Bars._ApplyReverseFillBars(f, conf)
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
    if not st or not st.dirty then  return end
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
    fontKey = nil,
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
    if not key then  return end
    MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_ApplyCommitState
    if key == "boss" then
        st.bossPreview = true
    end
    MSUF_ScheduleApplyCommit()
 end
function ApplyAllSettings()
    local st = _G.MSUF_ApplyCommitState
    if not st then  return end
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
    if not key then  return end
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
    if not MSUF_DB then EnsureDB() end
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
if type(_G.MSUF_RefreshSelfHealPredUnitEvent) == "function" then
    _G.MSUF_RefreshSelfHealPredUnitEvent()
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
    if not st then  return end
    if F.InCombatLockdown and F.InCombatLockdown() then
        st.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT", MSUF_OnRegenEnabled_ApplyCommit)
    end
         return
    end
        MSUF_ApplyDirtyUnitFrames()    if st.fonts then
        local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts
        if type(fn) == "function" then
            local fk = st.fontKey
            if fk and fk ~= false then
                fn(fk)
            else
                fn()
            end
        end
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
        -- Reanchor boss castbar position BEFORE updating the preview.
        -- Without this, boss castbar previews lose their anchor when boss
        -- frames reposition (e.g. spacing slider) and disappear.
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            MSUF_FastCall(_G.MSUF_ApplyBossCastbarPositionSetting)
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
    end
        -- Keep the castbar position popup synced if it is currently open.
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
            MSUF_FastCall(_G.MSUF_SyncCastbarPositionPopup, "boss")
        end
    end
    if st.tickers then
        if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then _G.MSUF_EnsureStatusIndicatorTicker() end
        if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then _G.MSUF_EnsureToTFallbackTicker() end
    end
if type(_G.MSUF_RefreshSelfHealPredUnitEvent) == "function" then
    _G.MSUF_RefreshSelfHealPredUnitEvent()
end
    st.fonts = false
    st.fontKey = nil
    st.bars = false
    st.castbars = false
    st.tickers = false
    st.bossPreview = false
    st.queued = false
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
 end
-- Changes:
-- 1. Numeric hash replaces string concat stamps (cheaper comparison)
-- 2. Inner closures hoisted to file-level (no re-creation per call)
-- 3. 3-stamp-layer collapsed to 2 (global + per-key)

-- Module-local font state (populated once per UpdateAllFonts call, read by hoisted helpers)
local _fontState = {}

local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb)
    if not fs then return end
    local S = _fontState
    -- Content-based: only call SetFont when path/flags (serial) or size actually changed
    local rev = S.pathSerial + size * 1000003
    if fs._msufFontRev ~= rev then
        fs:SetFont(S.path, size, S.flags)
        fs._msufFontRev = rev
        fs._msufShadowOn = nil
    end
    if setColor then
        local crev = cr * 1000000 + cg * 1000 + cb
        if fs._msufColorRev ~= crev then
            fs:SetTextColor(cr, cg, cb, 1)
            fs._msufColorRev = crev
        end
    end
    local sh = S.useShadow and 1 or 0
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

local function _MSUF_ApplyFontsToFrame(f)
    if not f then return end
    local S = _fontState
    local key = f.msufConfigKey
    if (not key) and f.unit then
        key = GetConfigKeyForUnit(f.unit)
    end
    if S.onlyKey and key ~= S.onlyKey then return end

    local conf
    if key and MSUF_DB then conf = MSUF_DB[key] end
    local nameSize  = (conf and conf.nameFontSize)  or S.globalNameSize
    local hpSize    = (conf and conf.hpFontSize)    or S.globalHPSize
    local powerSize = (conf and conf.powerFontSize) or S.globalPowSize

    if f.nameText then
        _MSUF_ApplyFontCached(f.nameText, nameSize, false, 0, 0, 0)
    end
    -- ToT inline text (target frame only): inherit same font + shadow as nameText.
    if f._msufToTInlineSep then
        _MSUF_ApplyFontCached(f._msufToTInlineSep, nameSize, false, 0, 0, 0)
    end
    if f._msufToTInlineText then
        _MSUF_ApplyFontCached(f._msufToTInlineText, nameSize, false, 0, 0, 0)
    end
    if f.levelText then
        _MSUF_ApplyFontCached(f.levelText, (conf and conf.levelIndicatorSize) or nameSize, false, 0, 0, 0)
    end
    if f.classificationIndicatorText then
        _MSUF_ApplyFontCached(f.classificationIndicatorText, (conf and conf.classificationIndicatorSize) or nameSize, true, S.fr, S.fg, S.fb)
    end
    local statusSize = nameSize + 2
    if f.statusIndicatorText then
        _MSUF_ApplyFontCached(f.statusIndicatorText, statusSize, true, S.fr, S.fg, S.fb)
    end
    if f.statusIndicatorOverlayText then
        _MSUF_ApplyFontCached(f.statusIndicatorOverlayText, statusSize, true, S.fr, S.fg, S.fb)
    end
    if f.nameText and S.UpdateNameColor then
        S.UpdateNameColor(f)
    end
    if f.hpText then
        _MSUF_ApplyFontCached(f.hpText, hpSize, true, S.fr, S.fg, S.fb)
    end
    if f.hpTextPct then
        _MSUF_ApplyFontCached(f.hpTextPct, hpSize, true, S.fr, S.fg, S.fb)
    end
    local pwSetColor = not S.colorPowerByType
    local pCr, pCg, pCb = pwSetColor and S.fr or 0, pwSetColor and S.fg or 0, pwSetColor and S.fb or 0
    if f.powerTextPct then
        _MSUF_ApplyFontCached(f.powerTextPct, powerSize, pwSetColor, pCr, pCg, pCb)
    end
    if f.powerText then
        _MSUF_ApplyFontCached(f.powerText, powerSize, pwSetColor, pCr, pCg, pCb)
    end
end

local function UpdateAllFonts(onlyKey)
    local path  = ns.Castbars._GetFontPath()
    local flags = ns.Castbars._GetFontFlags()
    if not MSUF_DB then EnsureDB() end
    local g = MSUF_DB.general or {}
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize
    local useShadow      = g.textBackdrop and true or false
    local colorPowerByType = (g.colorPowerTextByType == true)

    if onlyKey == "tot" or onlyKey == "targetoftarget" then onlyKey = "targettarget" end
    if type(onlyKey) == "string" and onlyKey:match("^boss%d+$") then onlyKey = "boss" end

    -- Build numeric global hash (cheap to compare)
    -- Include path+flags via their string hash (changes rarely)
    local pathKey = tostring(path) .. "|" .. tostring(flags) .. "|" .. tostring(fr) .. "|" .. tostring(fg) .. "|" .. tostring(fb)
    if _G.MSUF_FontPathKey ~= pathKey then
        _G.MSUF_FontPathKey = pathKey
        _G.MSUF_FontPathSerial = (_G.MSUF_FontPathSerial or 0) + 1
    end

    -- Populate shared state for hoisted helpers
    _fontState.path = path
    _fontState.flags = flags
    _fontState.pathSerial = _G.MSUF_FontPathSerial or 0
    _fontState.fr = fr
    _fontState.fg = fg
    _fontState.fb = fb
    _fontState.globalNameSize = globalNameSize
    _fontState.globalHPSize = globalHPSize
    _fontState.globalPowSize = globalPowSize
    _fontState.useShadow = useShadow
    _fontState.colorPowerByType = colorPowerByType
    _fontState.onlyKey = onlyKey
    _fontState.UpdateNameColor = MSUF_UpdateNameColor

    MSUF_ForEachUnitFrame(_MSUF_ApplyFontsToFrame)

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
    _G.MSUF_UpdateAllFonts = function(onlyKey)
        local st = _G.MSUF_ApplyCommitState
        if st then
            st.fonts = true
            if onlyKey then
                if st.fontKey == nil then
                    st.fontKey = onlyKey
                elseif st.fontKey == false then
                    -- already a full refresh queued
                elseif st.fontKey ~= onlyKey then
                    -- multiple keys requested -> fall back to a full refresh (still stamp-gated)
                    st.fontKey = false
                end
            else
                -- explicit full refresh
                st.fontKey = false
            end
        end
        MSUF_ScheduleApplyCommit()
     end
    _G.UpdateAllFonts = _G.MSUF_UpdateAllFonts
end
local function _ApplyTexCached(sb, tex)
    if not sb or not tex then return end
    if sb.MSUF_cachedStatusbarTexture ~= tex then
        sb:SetStatusBarTexture(tex)
        sb.MSUF_cachedStatusbarTexture = tex
    end
end
local function _Iter_ApplyAllBarTex(f)
    local S = _iterState
    _ApplyTexCached(f.hpBar, S.texHP)
    _ApplyTexCached(f.absorbBar, S.texAbs)
    _ApplyTexCached(f.healAbsorbBar, S.texHeal)
    _ApplyTexCached(f.selfHealPredBar, S.texHP)
    if S.applyBg then S.applyBg(f) end
    _ApplyTexCached(f.targetPowerBar, S.texHP)
end
local function _Iter_ApplyAbsorbTex(f)
    local S = _iterState
    _ApplyTexCached(f.absorbBar, S.texAbs)
    _ApplyTexCached(f.healAbsorbBar, S.texHeal)
end
local function UpdateAllBarTextures()
    local texHP = MSUF_GetBarTexture()
    if not texHP then  return end
    local texAbs  = MSUF_GetAbsorbBarTexture()
    local texHeal = MSUF_GetHealAbsorbBarTexture()
    _iterState.texHP   = texHP
    _iterState.texAbs  = texAbs  or texHP
    _iterState.texHeal = texHeal or texHP
    _iterState.applyBg = MSUF_ApplyBarBackgroundVisual
    MSUF_ForEachUnitFrame(_Iter_ApplyAllBarTex)
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
        if not texAbs or not texHeal then  return end
    end
    _iterState.texAbs  = texAbs
    _iterState.texHeal = texHeal
    MSUF_ForEachUnitFrame(_Iter_ApplyAbsorbTex)
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
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if not g then  return end
    local mode = tonumber(g.absorbTextMode)
    if not mode then  return end
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
    if not unit or not parent then  return end
    if not MSUF_DB then EnsureDB() end
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key]
    if not conf then  return end

    local STEP = 1
    deltaX = (deltaX or 0) * STEP
    deltaY = (deltaY or 0) * STEP

    -- MSUF Edit Mode: always MOVE with arrow keys (no sizing mode)
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

    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
local function MSUF_EnableUnitFrameDrag(f, unit)
    if not f or not unit then  return end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(false)
    if f.RegisterForDrag then
        f:RegisterForDrag("LeftButton", "RightButton")
    end
    local function _DisableClicks(self)
        if not self or not self.GetAttribute or not self.SetAttribute then  return end
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
        if not saved or not self.SetAttribute then  return end
        self:SetAttribute("*type1", saved.type1)
        self:SetAttribute("*type2", saved.type2)
        self._msufSavedClickAttrs = nil
     end
    local function _GetConfAndKey()
        if not MSUF_DB then EnsureDB() end
        local key = GetConfigKeyForUnit(unit)
        local conf = key and MSUF_DB and MSUF_DB[key]
         return key, conf
    end
    local function _ApplySnapAndClamp(key, conf)
        if not conf then  return end
        local g = MSUF_DB and MSUF_DB.general or nil
        if g and g.editModeSnapToGrid then
            local gridStep = g.editModeGridStep or 20
            if gridStep < 1 then gridStep = 1 end
            local half = gridStep / 2
            local x = conf.offsetX or 0
            local y = conf.offsetY or 0
            conf.offsetX = math.floor((x + half) / gridStep) * gridStep
            conf.offsetY = math.floor((y + half) / gridStep) * gridStep
        end
    end
    local function _UpdateDBFromFrame(self, key, conf)
        if not self or not conf or not key then  return end
        local anchor = MSUF_GetAnchorFrame and MSUF_GetAnchorFrame() or UIParent
        if not anchor or not anchor.GetCenter or not self.GetCenter then  return end
        local _g = MSUF_DB and MSUF_DB.general
        if _g and _g.anchorToCooldown then
            local ecv = _G and _G["EssentialCooldownViewer"]
            if ecv and anchor == ecv then
                local rule = MSUF_ECV_ANCHORS and MSUF_ECV_ANCHORS[key]
                if rule then
                    local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3] or 0, rule[4] or 0
                    local function _PointXY(fr, p)
                        if not fr or not p then  return nil, nil end
                        if p == "CENTER" then
                            return fr:GetCenter()
                        end
                        local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
                        if not (l and r and t and b) then
                             return nil, nil
                        end
                        local cx = (l + r) * 0.5
                        local cy = (t + b) * 0.5
                        if p == "TOPLEFT" then  return l, t end
                        if p == "TOP" then  return cx, t end
                        if p == "TOPRIGHT" then  return r, t end
                        if p == "LEFT" then  return l, cy end
                        if p == "RIGHT" then  return r, cy end
                        if p == "BOTTOMLEFT" then  return l, b end
                        if p == "BOTTOM" then  return cx, b end
                        if p == "BOTTOMRIGHT" then  return r, b end
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
        if not ax or not ay or not fx or not fy then  return end
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
        if not MSUF_UnitEditModeActive then  return end
        if F.InCombatLockdown and F.InCombatLockdown() then  return end
        self._msufClickButton = button
        self._msufDragDidStart = false
     end)
    f:SetScript("OnDragStart", function(self, button)
        if not MSUF_UnitEditModeActive then  return end
        if F.InCombatLockdown and F.InCombatLockdown() then  return end
        local key, conf = _GetConfAndKey()
        if not key or not conf then  return end
        self._msufDragDidStart = true
        self._msufDragActive = true
        self._msufDragKey = key
        self._msufDragConf = conf
        _DisableClicks(self)
        self:StartMoving()
        self._msufDragAccum = 0
            _G.MSUF_UnregisterBucketUpdate(self, "EditDrag")
        if _G.MSUF_RegisterBucketUpdate then
            _G.MSUF_RegisterBucketUpdate(self, 0.02, function(s, dt)
                if not s._msufDragActive then  return end
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
             end, "EditDrag")
        else
            self:SetScript("OnUpdate", function(s, elapsed)
                if not s._msufDragActive then
                    s:SetScript("OnUpdate", nil)
                     return
                end
                s._msufDragAccum = (s._msufDragAccum or 0) + (elapsed or 0)
                if s._msufDragAccum < 0.02 then  return end
                s._msufDragAccum = 0
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
             end)
    end
     end)
    f:SetScript("OnDragStop", function(self, button)
        if not self._msufDragActive then  return end
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
        if not MSUF_UnitEditModeActive then  return end
        if F.InCombatLockdown and F.InCombatLockdown() then  return end
        if self._msufDragDidStart then
             return
    end
        if MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, self)
    end
     end)
 end
-- Edit-mode mouse arrows removed (hard delete; arrow-key nudging remains via MSUF_EditMode)
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
    if not f or not f.hpBar then  return end
    local pb = f.targetPowerBar
    if not pb then
        f._msufPowerBarReserved = nil
        f._msufPBLayoutStamp = nil
        ns.Cache.ClearStamp(f, "PBEmbedLayout")
         return
    end
    if not MSUF_DB then EnsureDB() end
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

    -- Detach: per-unit config for player/target/focus (detach overrides embed)
    local detached = false
    local dW, dH, dX, dY = 0, 0, 0, 0
    if (unit == 'player' or unit == 'target' or unit == 'focus') then
        local key = f.msufConfigKey
        if not key and GetConfigKeyForUnit then key = GetConfigKeyForUnit(unit) end
        local conf = (key and MSUF_DB and MSUF_DB[key]) or nil
        if conf and conf.powerBarDetached == true then
            detached = true
            dW = tonumber(conf.detachedPowerBarWidth) or math.floor((conf.width or 250) + 0.5)
            dH = tonumber(conf.detachedPowerBarHeight) or 6
            dX = tonumber(conf.detachedPowerBarOffsetX) or 0
            dY = tonumber(conf.detachedPowerBarOffsetY) or -4
        end
    end

    local reserve = (embed and not detached and enabled and h > 0)
    if not ns.Cache.StampChanged(f, "PBEmbedLayout", (reserve and 1 or 0), h, (detached and 1 or 0), dW, dH, dX, dY) then  return end
    f._msufPBLayoutStamp = 1
    f._msufPowerBarReserved = reserve and true or nil
    f._msufPowerBarDetached = detached and true or nil
    -- Force border system to re-evaluate when detach state changes
    f._msufBarOutlineThickness = -1
    f._msufBarOutlineBottomIsPower = nil
    f._msufHighlightBottomIsPower = nil
    -- Re-anchor mouseover highlight (it was set up at init and doesn't auto-update)
    if type(_G.MSUF_FixHighlightForFrame) == "function" then
        _G.MSUF_FixHighlightForFrame(f)
    end
    local hb = f.hpBar
    hb:ClearAllPoints()
    hb:SetPoint('TOPLEFT', f, 'TOPLEFT', 2, -2)
    if reserve then
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2 + h)
    else
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    end
    pb:ClearAllPoints()
    if detached then
        -- Detached: freely positioned relative to parent frame (overrides embed)
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        if dH < 2 then dH = 2 elseif dH > 80 then dH = 80 end
        pb:SetSize(dW, dH)
        pb:SetPoint('TOPLEFT', f, 'BOTTOMLEFT', dX, dY)
    elseif reserve then
        pb:SetHeight(h)
        pb:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 2, 2)
        pb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    else
        pb:SetHeight(h)
        pb:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', 0, 0)
        pb:SetPoint('TOPRIGHT', hb, 'BOTTOMRIGHT', 0, 0)
    end
 end

_G.MSUF_ApplyPowerBarEmbedLayout = MSUF_ApplyPowerBarEmbedLayout
_G.MSUF_ApplyPowerBarEmbedLayout_All = function()
    if not UnitFrames then  return end
    for _, fr in pairs(UnitFrames) do
        if fr and fr.hpBar and fr.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(fr)
    end
    end
 end

local function _CreateSelfHealPredBar(f, hpBar)
    -- Own-heals-only prediction segment (player incoming heals only).
    -- Secret-safe: no arithmetic/comparisons on heal values.
    local clip = _G.CreateFrame("Frame", nil, hpBar)
    clip:SetAllPoints(hpBar)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    f.selfHealPredClip = clip
    local bar = _G.CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture(MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    bar:SetFrameLevel(clip:GetFrameLevel())
    bar:SetStatusBarColor(0.0, 1.0, 0.4, 0.35)
    bar:Hide()
    f.selfHealPredBar = bar
    if hpBar and hpBar.GetReverseFill and bar.SetReverseFill then
        local okRF, rf = pcall(hpBar.GetReverseFill, hpBar)
        if okRF and rf ~= nil then pcall(bar.SetReverseFill, bar, rf and true or false) end
    end
end

local function _CreateClassificationText(f, textFrame, conf, fontPath, flags, fr, fg, fb)
    if not textFrame or not textFrame.CreateFontString then return end
    if f.classificationIndicatorText then return end
    local fs = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    if not fs then return end
    fs:SetAlpha(1)
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    local g2 = (type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general) or {}
    local baseSize = (type(g2) == "table" and g2.fontSize) or 14
    local nameSize = (type(g2) == "table" and g2.nameFontSize) or baseSize
    local clsSize = (conf and conf.classificationIndicatorSize) or (conf and conf.nameFontSize) or nameSize
    if type(clsSize) ~= "number" then clsSize = nameSize end
    clsSize = math.floor(math.max(8, math.min(64, clsSize)) + 0.5)
    if fs.SetFont and type(fontPath) == "string" and fontPath ~= "" then
        fs:SetFont(fontPath, clsSize, flags)
    end
    if fs.SetTextColor then fs:SetTextColor(fr or 1, fg or 1, fb or 1, 1) end
    if (type(g2) == "table" and g2.textBackdrop == true) and fs.SetShadowColor and fs.SetShadowOffset then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    elseif fs.SetShadowOffset then
        fs:SetShadowOffset(0, 0)
    end
    fs:Hide()
    f.classificationIndicatorText = fs
end

local function CreateSimpleUnitFrame(unit)
    if not MSUF_DB then EnsureDB() end
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key] or {}
    local f = F.CreateFrame("Button", "MSUF_" .. unit, UIParent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    f.unit = unit
    MSUF_EnsureUnitFlags(f)
    f.msufConfigKey = key
    f.cachedConfig = conf
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
        grads = ns.Bars._PreCreateHPGradients(hpBar)
        f.hpGradients = grads
        f.hpGradient = grads and grads.right or nil
    end
    ns.Bars._ApplyHPGradient(f)
    if unit == "player" then
        _CreateSelfHealPredBar(f, hpBar)
    end
    f.absorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 2, MSUF_GetAbsorbOverlayColor(), true)
    f.healAbsorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 3, MSUF_GetHealAbsorbOverlayColor(), false)
    ns.Bars.SetOverlayBarTexture(f.absorbBar, MSUF_GetAbsorbBarTexture)
    ns.Bars.SetOverlayBarTexture(f.healAbsorbBar, MSUF_GetHealAbsorbBarTexture)
    -- Layered alpha requires per-texture alpha; MSUF unitframes support it.
    f._msufAlphaSupportsLayered = true
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
            pgrads = ns.Bars._PreCreateHPGradients(pBar)
            f.powerGradients = pgrads
            f.powerGradient = pgrads and pgrads.right or nil
    end
        ns.Bars._ApplyPowerGradient(f)
        if _G.MSUF_ApplyPowerBarBorder then _G.MSUF_ApplyPowerBarBorder(pBar) end
        pBar:Hide()
    end
    local textFrame = ns.UF.MakeFrame(f, "textFrame", "Frame", "self")
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    local fontPath = ns.Castbars._GetFontPath()
    local flags    = ns.Castbars._GetFontFlags()
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
            { "classificationIndicatorIcon", (unit == "target"), "textFrame", "OVERLAY", 7, 18, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
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
        -- Classification indicator text (Target only)
        if unit == "target" then
            _CreateClassificationText(f, textFrame, conf, fontPath, flags, fr, fg, fb)
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
    ns.Bars._ApplyReverseFillBars(f, conf)
    ns.UF.RequestUpdate(f, true, true, "F.CreateFrame")
    -- Auras2 must be primed on unitframe creation; do NOT rely on a later UNIT_AURA burst.
    -- This prevents the "auras only start after Edit Mode / toggle" regression.
    if type(_G.MSUF_A2_RequestUnit) == "function" then
        _G.MSUF_A2_RequestUnit(unit)
    elseif unit == "target" and type(_G.MSUF_UpdateTargetAuras) == "function" then
        -- Legacy fallback (older builds): only target was supported.
        MSUF_UpdateTargetAuras(f)
    end
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
        if not MSUF_DB then EnsureDB() end
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
            if not (sk and PlaySound) then  return end
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
        -- Use EventBus instead of dedicated frame
        _msufTargetSoundFrame = true -- sentinel to prevent re-entry
        MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND", function()
            MSUF_TargetSoundDriver_OnTargetChanged()
        end)
        MSUF_TargetSoundDriver_ResetState()
     end
    _G.MSUF_TargetSoundDriver_Ensure = MSUF_TargetSoundDriver_Ensure
    _G.MSUF_TargetSoundDriver_ResetState = MSUF_TargetSoundDriver_ResetState
end
MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_STARTUP", function(event)
    MSUF_InitProfiles()
    if not MSUF_DB then EnsureDB() end
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

    -- Auras2 bootstrap: build cache + register events + render once.
    -- Without this, auras can appear to be "dead" until an external trigger (Edit Mode / manual toggle / first UNIT_AURA).
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end

-- Player self-heal prediction: request a Player frame update when heal prediction changes
-- (this can change without UNIT_HEALTH firing).
-- MAX performance path: register UNIT_* directly with RegisterUnitEvent (oUF-style).
-- Secret-safe: no comparisons/arithmetic on potential secret values.
if type(_G.MSUF_RefreshSelfHealPredUnitEvent) ~= "function" then
    _G.MSUF_RefreshSelfHealPredUnitEvent = function()
        local g = (MSUF_DB and MSUF_DB.general) or nil
        local want = (g and g.showSelfHealPrediction) and true or false

        local fr = _G.MSUF_SelfHealPredUnitFrame
        if not fr and not want then
            return
        end
        if not fr then
            fr = F.CreateFrame("Frame")
            fr:Hide()
            fr._msufReg = false
            fr:SetScript("OnEvent", function(self, event, unit)
                local isSecret = _G.issecretvalue
                if isSecret and isSecret(unit) then return end
                if unit ~= "player" then return end
                local gg = (MSUF_DB and MSUF_DB.general) or nil
                if not (gg and gg.showSelfHealPrediction) then return end
                local uf = UnitFrames and UnitFrames.player
                if not uf or (uf.IsShown and not uf:IsShown()) then return end
                local req = ns and ns.UF and ns.UF.RequestUpdate
                if req then
                    req(uf, true, false, "UNIT_HEAL_PREDICTION")
                end
            end)
            _G.MSUF_SelfHealPredUnitFrame = fr
        end

        if want then
            if not fr._msufReg then
                fr:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "player")
                fr._msufReg = true
            end
        else
            if fr._msufReg then
                fr:UnregisterEvent("UNIT_HEAL_PREDICTION")
                fr._msufReg = false
            end
        end
    end
end
if type(_G.MSUF_RefreshSelfHealPredUnitEvent) == "function" then
    _G.MSUF_RefreshSelfHealPredUnitEvent()
end

    if type(_G.MSUF_RangeFade_InitPostLogin) == "function" then
        _G.MSUF_RangeFade_InitPostLogin()
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
            if ns.UF.IsDisabled(conf) then  return end
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
    if not targetFrame or not targetFrame.nameText then  return end
    if targetFrame._msufToTInlineText and targetFrame._msufToTInlineSep then  return end
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
    if not targetFrame or not targetFrame.nameText then  return end
    if not MSUF_DB then EnsureDB() end
    if not MSUF_DB then  return end
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
    if not targetFrame then  return end
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
        if _msufToTInlineQueued then  return end
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
    if type(MSUF_MakeBlizzardOptionsMovable) == "function" then
        C_Timer.After(0.5, MSUF_MakeBlizzardOptionsMovable)
    end
    if type(_G.MSUF_RegisterOptionsCategoryLazy) == "function" then
        _G.MSUF_RegisterOptionsCategoryLazy()
    elseif type(_G.CreateOptionsPanel) ~= "function" then
        if not _G.MSUF_OptionsPanelMissingWarned then
            _G.MSUF_OptionsPanelMissingWarned = true
            print("|cffff0000MSUF:|r Options panel not loaded (CreateOptionsPanel missing). Check your .toc includes MSUF_Options_Core.lua.")
    end
    end
	    if type(_G.MSUF_CheckAndRunFirstSetup) == "function" then
	        _G.MSUF_CheckAndRunFirstSetup()
	    end
	    if type(_G.MSUF_HookCooldownViewer) == "function" then
	        C_Timer.After(1, _G.MSUF_HookCooldownViewer)
	    end
    if type(ns.Castbars._InitPlayerCastbarPreviewToggle) == "function" then
        C_Timer.After(1.1, ns.Castbars._InitPlayerCastbarPreviewToggle)
    end
    print("|cff7aa2f7MSUF|r: |cffc0caf5/msuf|r |cff565f89to open options|r  |cff565f89|r  |cff9ece6a Beta Build 2.0 Beta 11 |cff565f89|r  |cffc0caf5 Thank you for using MSUF -|r  |cfff7768eReport bugs in the Discord.|r")
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
        if bucket then  return bucket end
        bucket = {
            interval = interval or 0,
            accum = 0,
            jobs = {},   -- [ownerFrame] = { [tag] = job }
            frame = F.CreateFrame("Frame"),
        }
        bucket._onUpdate = function(_, elapsed)
            elapsed = elapsed or 0
            bucket.accum = (bucket.accum or 0) + elapsed
            if bucket.accum < bucket.interval then  return end
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
        if not owner or not cb then  return end
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
        if not owner then  return end
        tag = tag or "_"
        local jobs = owner._msufBucketJobs
        local interval = jobs and jobs[tag]
        if not interval then  return end
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

-- ---------------------------------------------------------------------------
-- Swap Recolor Driver (event-only, ultra cheap)
-- Fixes: HP bar color/gradient/background sticking after target/focus/ToT swap.
-- This bypasses rare/heavy-visual gating by forcing the HeavyVisual step once
-- per swap event (coalesced next frame). No layout, no full refresh.
-- ---------------------------------------------------------------------------
do
    -- Force a one-shot HeavyVisual pass for the given frame/unit.
    -- Exposed globally so other files/modules may reuse it if needed.
    _G.MSUF_ForceReapplyHPBarColor = _G.MSUF_ForceReapplyHPBarColor or function(frame, unit)
        if not (frame and unit and frame.hpBar) then return end
        local key = frame.msufConfigKey
        local flags = _G.MSUF_UnitTokenChanged
        if not flags then
            flags = {}
            _G.MSUF_UnitTokenChanged = flags
        end
        if key then
            flags[key] = true -- consumed inside MSUF_UFStep_HeavyVisual
        end
        frame._msufHeavyVisualNextAt = 0 -- allow immediate run
        -- Call the local HeavyVisual step directly (no layout / no other steps)
        MSUF_UFStep_HeavyVisual(frame, unit, key)
    end

    local function _MSUF_SwapRecolor_Do()
        local f = _G.MSUF_target
        if f and f.unit == "target" then
            _G.MSUF_ForceReapplyHPBarColor(f, "target")
        end
        local tot = _G.MSUF_targettarget
        if tot and tot.unit == "targettarget" then
            _G.MSUF_ForceReapplyHPBarColor(tot, "targettarget")
        end
        local fo = _G.MSUF_focus
        if fo and fo.unit == "focus" then
            _G.MSUF_ForceReapplyHPBarColor(fo, "focus")
        end
    end

    local function _MSUF_SwapRecolor_Schedule(driver)
        if driver._msufSwapRecolorQueued then return end
        driver._msufSwapRecolorQueued = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                driver._msufSwapRecolorQueued = false
                _MSUF_SwapRecolor_Do()
            end)
        else
            driver._msufSwapRecolorQueued = false
            _MSUF_SwapRecolor_Do()
        end
    end

    _G.MSUF_EnsureSwapRecolorDriver = _G.MSUF_EnsureSwapRecolorDriver or function()
        if _G.MSUF_SwapRecolorDriver then return _G.MSUF_SwapRecolorDriver end
        local d = CreateFrame("Frame", "MSUF_SwapRecolorDriver", UIParent)
        d._msufSwapRecolorQueued = false
        -- TARGET/FOCUS via EventBus, keep UNIT_TARGET on frame
        d:RegisterEvent("UNIT_TARGET")
        d:SetScript("OnEvent", function(self, event, arg1)
            if event == "UNIT_TARGET" then
                if arg1 ~= "target" then return end -- ToT updates from target only
            end
            _MSUF_SwapRecolor_Schedule(self)
        end)
        _G.MSUF_SwapRecolorDriver = d

        MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_SWAP_RECOLOR", function()
            _MSUF_SwapRecolor_Schedule(d)
        end)
        MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_SWAP_RECOLOR_FOCUS", function()
            _MSUF_SwapRecolor_Schedule(d)
        end)

        return d
    end
end

-- Start the driver immediately (safe: does nothing until frames exist).
if _G.MSUF_EnsureSwapRecolorDriver then
    _G.MSUF_EnsureSwapRecolorDriver()
end

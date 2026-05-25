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
-- Blizzard/Clique click-casting discovery.
-- This table is a one-time frame registry, not a runtime poller. Keep it
-- present so Blizzard's click-casting and Clique can discover MSUF frames.
if type(_G.ClickCastFrames) ~= "table" then _G.ClickCastFrames = {} end
local MSUF_ClickCastFrames = _G.ClickCastFrames
ns.ClickCastEnabled = true

ns.UF.CallCliqueMethod = ns.UF.CallCliqueMethod or function(clique, methodName, ...)
    local method = clique and clique[methodName]
    if type(method) ~= "function" then return false end
    local ok = pcall(method, clique, ...)
    return ok == true
end

ns.UF.RegisterClickCastFrame = ns.UF.RegisterClickCastFrame or function(f, refreshEnterLeave)
    if not (f and f.RegisterForClicks) then return end

    MSUF_ClickCastFrames[f] = true

    local clique = _G.Clique
    if type(clique) ~= "table" or type(clique.ccframes) ~= "table" then return end

    ns.UF.CallCliqueMethod(clique, "RegisterUnitFrame", f)

    if not refreshEnterLeave or (_G.InCombatLockdown and _G.InCombatLockdown()) then return end
    if clique.ccframes and clique.ccframes[f] then
        if type(clique.UnwrapOnEnterOnLeave) == "function" and type(clique.WrapOnEnterOnLeave) == "function" then
            ns.UF.CallCliqueMethod(clique, "UnwrapOnEnterOnLeave", f)
            ns.UF.CallCliqueMethod(clique, "WrapOnEnterOnLeave", f)
        elseif type(clique.ApplyAttributes) == "function" then
            ns.UF.CallCliqueMethod(clique, "ApplyAttributes")
        end
    end
end

-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
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
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame, GetTime = CreateFrame, GetTime
-- P0: issecretvalue upvalue for event handlers (secret-safe unit filtering)
local _MSUF_issecretvalue = _G.issecretvalue
local _msuf_inCombat = false        -- P0: cached combat state (no C-call in hot paths)

local MSUF_LEADER_ICON_TEX = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local MSUF_ASSIST_ICON_TEX = "Interface\\GroupFrame\\UI-Group-AssistantIcon"

local function MSUF_GetLeaderAssistTexture(conf, g, isAssist)
    local fallback = isAssist and MSUF_ASSIST_ICON_TEX or MSUF_LEADER_ICON_TEX
    local style = conf and conf.leaderIconStyle
    if type(style) ~= "string" or style == "" then style = g and g.leaderIconStyle end
    if type(style) ~= "string" or style == "" or style == "DEFAULT" or style == "BLIZZARD" then
        return fallback, 0, 1, 0, 1
    end

    local resolver = isAssist and _G.MSUF_GetAssistStatusIconTexture or _G.MSUF_GetLeaderStatusIconTexture
    if type(resolver) == "function" then
        local tex, l, r, t, b = resolver(style, false)
        if type(tex) == "string" and tex ~= "" then
            return tex, l or 0, r or 1, t or 0, b or 1
        end
    end
    return fallback, 0, 1, 0, 1
end

local function MSUF_SetLeaderAssistTexture(texture, conf, g, isAssist)
    if not (texture and texture.SetTexture) then return end
    local tex, l, r, t, b = MSUF_GetLeaderAssistTexture(conf, g, isAssist)
    texture:SetTexture(tex)
    if texture.SetTexCoord then texture:SetTexCoord(l or 0, r or 1, t or 0, b or 1) end
end

local function MSUF_OptionsApplyCombatLocked()
    return _msuf_inCombat == true
        or _G.MSUF_InCombat == true
        or ((InCombatLockdown and InCombatLockdown()) and true or false)
end

local function MSUF_ClearRuntimeTestModesForCombat()
    if type(_G.MSUF_ClearAbsorbTextureTestMode) == "function" then
        _G.MSUF_ClearAbsorbTextureTestMode()
    else
        _G.MSUF_AbsorbTextureTestMode = false
        _G.MSUF_AbsorbTextureTestScope = nil
    end

    if type(_G.MSUF_ClearBorderTestModesForCombat) == "function" then
        _G.MSUF_ClearBorderTestModesForCombat()
    else
        _G.MSUF_AggroBorderTestMode = false
        _G.MSUF_DispelBorderTestMode = false
        _G.MSUF_PurgeBorderTestMode = false
        _G.MSUF_BossTargetBorderTestMode = false
        _G.MSUF_BorderTestModesActive = false
    end

    _G.MSUF_UnitPreviewActive = false
    _G.MSUF_PreviewTestMode = false
    _G.MSUF2_BossUnitframePreviewActive = false
    _G.MSUF_BossTestMode = false
    MSUF_BossTestMode = false

    for _, fnName in ipairs({
        "MSUF_SetPlayerCastbarTestMode",
        "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode",
        "MSUF_SetBossCastbarTestMode",
    }) do
        local fn = rawget(_G, fnName)
        if type(fn) == "function" then
            fn(false, true)
        end
    end

    for _, frameName in ipairs({
        "MSUF_PlayerCastbar", "MSUF_PlayerCastbarPreview",
        "MSUF_TargetCastbarPreview", "MSUF_FocusCastbarPreview",
        "MSUF_BossCastbarPreview",
    }) do
        local f = rawget(_G, frameName)
        if f and f.SetScript and (f.MSUF_testMode or f._msufTestActive or f.MSUF_bossTestMode) then
            f.MSUF_testMode = nil
            f._msufTestActive = nil
            f.MSUF_bossTestMode = nil
            f:SetScript("OnUpdate", nil)
        end
    end
    for i = 2, 12 do
        local f = rawget(_G, "MSUF_BossCastbarPreview" .. i)
        if f and f.SetScript and f.MSUF_bossTestMode then
            f.MSUF_bossTestMode = nil
            f:SetScript("OnUpdate", nil)
        end
    end
end
_G.MSUF_ClearRuntimeTestModesForCombat = MSUF_ClearRuntimeTestModesForCombat
-- P0: Snapshot PowerBarColor at load time. Blizzard mutates entries during
-- gameplay (Eclipse changes LUNAR_POWER color). MSUF reads the frozen snapshot
-- so the power bar color stays stable. User overrides (Colors panel) checked first.
do
    local snap = {}
    local pbc = PowerBarColor
    if pbc then
        for k, v in pairs(pbc) do
            if type(v) == "table" and type(v.r) == "number" then
                snap[k] = { r = v.r, g = v.g, b = v.b }
            end
        end
    end
    ns._PBCSnap = snap
end
-- P0: Single event frame maintains _msuf_inCombat + _G.MSUF_InCombat.
-- All modules read _G.MSUF_InCombat instead of calling InCombatLockdown() in event handlers.
-- Only ONE InCombatLockdown() C-call total: the sync on PLAYER_ENTERING_WORLD.
-- Secret-safe: boolean assignment only; no secret values involved.
do
    local _p0Frame = CreateFrame("Frame")
    _p0Frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _p0Frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _p0Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _p0Frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _msuf_inCombat = true
            _G.MSUF_InCombat = true
            MSUF_ClearRuntimeTestModesForCombat()
        else
            -- PLAYER_REGEN_ENABLED or PLAYER_ENTERING_WORLD: sync once with C-API
            _msuf_inCombat = ((InCombatLockdown and InCombatLockdown())
                or (UnitAffectingCombat and UnitAffectingCombat("player"))) and true or false
        end
        _G.MSUF_InCombat = _msuf_inCombat
    end)
end


-- P0: Absorb text path in UpdateHpTextFast (100-500x/sec)
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local C_StringUtil = C_StringUtil

-- Localization (minimal, translator-friendly)
-- - ns.L is a key->string map with fallback to the key itself.
-- - ns.AddLocale(locale, dict) merges translations for the active locale.
-- NOTE: Full scaffold lives in Locales/MSUF_Localization.lua, but this fallback
-- keeps MSUF safe even if localization files are missing or load-order changes.
ns.LOCALE = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
ns.L = ns.L or (_G.MSUF_L) or {}
local _L = ns.L
if not getmetatable(_L) then
    setmetatable(_L, { __index = function(t, k) return k end })
end
if _G then _G.MSUF_L = _L end
ns.AddLocale = ns.AddLocale or function(locale, dict)
    if not dict then return end
    local active = ns.LOCALE or "enUS"
    if locale ~= active then return end
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            _L[k] = v
        end
    end
end

-- Table-driven hide helpers (safe, no string compares).
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
-- SavedVariables access helpers (not live unit API values).
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
-- Used by text-layout helpers. Must be available during core init.
if _G and type(_G.MSUF_NormalizeTextLayoutUnitKey) ~= "function" then
    function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, defaultKey)
        if unitKey == nil then return defaultKey or "player" end
        if unitKey == "shared" then return defaultKey or "player" end
        if unitKey == "tot" or unitKey == "targetoftarget" then return "targettarget" end
        if unitKey == "focus_target" or unitKey == "focustargettarget" then return "focustarget" end
        if unitKey == "boss1" or unitKey == "boss2" or unitKey == "boss3" or unitKey == "boss4" or unitKey == "boss5" then return "boss" end
        return unitKey
    end
end

local F = ns.Cache.F or {}; ns.Cache.F = F
if not F._msufInit then
    F._msufInit = true
    local G = _G; F.UnitHealth, F.UnitHealthMax, F.UnitPower, F.UnitPowerMax = G.UnitHealth, G.UnitHealthMax, G.UnitPower, G.UnitPowerMax; F.UnitExists, F.UnitIsConnected, F.UnitIsDeadOrGhost = G.UnitExists, G.UnitIsConnected, G.UnitIsDeadOrGhost; F.UnitName, F.UnitClass, F.UnitReaction, F.UnitIsPlayer = G.UnitName, G.UnitClass, G.UnitReaction, G.UnitIsPlayer; F.CreateFrame, F.InCombatLockdown, F.GetTime = G.CreateFrame, G.InCombatLockdown, G.GetTime
end
-- Unified stamp cache (layout/indicator/portrait) to avoid per-call string stamps.
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
-- Unitframe element factories (build-time scaffolding; no runtime behavior change).
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
-- Unitframe indicator texture with a dedicated frame-level parent.
-- This makes the unitframe indicator "Layer" sliders behave like Group Frames:
-- higher layer = higher frame level, not just a texture sublevel.
ns.UF.MakeLayeredTex = ns.UF.MakeLayeredTex or function(self, key, parentKey, layer, sublayer, nameSuffix)
    if not self or not key then return nil end
    local parent = ns.UF._ResolveParent(self, parentKey)
    if not parent then return nil end

    local layerKey = key .. "LayerFrame"
    local layerFrame = self[layerKey]
    if not layerFrame then
        layerFrame = ns.UF.MakeFrame(self, layerKey, "Frame", parentKey)
        if layerFrame and layerFrame.SetAllPoints then layerFrame:SetAllPoints(parent) end
    end
    if not layerFrame then
        return ns.UF.MakeTex(self, key, parentKey, layer, sublayer, nameSuffix)
    end

    local t = self[key]
    if not t then
        if not layerFrame.CreateTexture then return nil end
        local name = ns.UF._MakeChildName(self, nameSuffix)
        t = layerFrame:CreateTexture(name, layer or "OVERLAY", nil, sublayer)
        self[key] = t
    elseif t.SetParent and t:GetParent() ~= layerFrame then
        t:SetParent(layerFrame)
    end

    t._msufLayerFrame = layerFrame
    t._msufLayerOwner = self
    t._msufLayerParent = parent
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
    if not frame then return end
    return _G.MSUF_RequestUnitframeUpdate(frame, forceFull, wantLayout, reason, urgentNow)
end
--   - Keep secret-safe: no text comparisons; only API calls / boolean checks
function ns.UF.IsDisabled(conf)
    return (conf and conf.enabled == false) and true or false
end

local function MSUF_IsBossUnitframePreviewActive()
    if _msuf_inCombat then return false end
    if not MSUF_BossTestMode then return false end
    if _G.MSUF2_BossUnitframePreviewActive == true then return true end

    local editState = _G.MSUF_EditState
    local editActive = (_G.MSUF_UnitEditModeActive == true)
        or (type(editState) == "table" and editState.active == true)
    if not editActive then return false end

    return (_G.MSUF_UnitPreviewActive == true or _G.MSUF_PreviewTestMode == true)
end
_G.MSUF_IsBossUnitframePreviewActive = MSUF_IsBossUnitframePreviewActive

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
    if not f then return end
    local isStatusUnit = (unit == "player" or unit == "target" or unit == "focus" or unit == "focustarget" or unit == "pet" or unit == "targettarget" or unit == "tot")
        or (type(unit) == "string" and unit:match("^boss"))
    if not isStatusUnit then return end
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
            if ns.Icons and ns.Icons._layout and ns.Icons._layout.EnsureLayerFrame then
                local layerParent = (key == "statusIndicatorOverlayText") and ov or (f.textFrame or f)
                ns.Icons._layout.EnsureLayerFrame(f, fs, key, layerParent)
            end
        end
    end
    if _G.MSUF_ApplyStatusTextLayout then
        _G.MSUF_ApplyStatusTextLayout(f)
    end
 end
-- Shared text object creation (unitframes)
-- Keep behavior identical: same templates, justify, alpha, and hidden defaults.
local MSUF_UF_TEXT_CREATE_DEFS = {
    { key = "nameText",      template = "GameFontHighlight",      justify = "LEFT",  a = 1 },
    { key = "raidGroupNameText", template = "GameFontHighlightSmall", justify = "LEFT",  a = 1, hide = true },
    { key = "levelText",     template = "GameFontHighlightSmall", justify = "LEFT",  a = 1,   hide = true },
    { key = "hpTextLeft",    template = "GameFontHighlightSmall", justify = "LEFT",  a = 0.9, hide = true },
    { key = "hpTextCenter",  template = "GameFontHighlightSmall", justify = "CENTER", a = 0.9, hide = true },
    { key = "hpText",        template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9 },
    { key = "hpTextPct",     template = "GameFontHighlightSmall", justify = "RIGHT", a = 0.9, hide = true },
    { key = "powerTextLeft", template = "GameFontHighlightSmall", justify = "LEFT",  a = 0.9, hide = true },
    { key = "powerTextCenter", template = "GameFontHighlightSmall", justify = "CENTER", a = 0.9, hide = true },
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
    f.hpTextRight = f.hpText
    f.powerTextRight = f.powerText
 end
ns.UF.UpdateHighlightColor = ns.UF.UpdateHighlightColor or function(self)
    if not self then  return end
    if not MSUF_DB then MSUF_EnsureDB() end
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
    if not MSUF_DB then MSUF_EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hb = self.highlightBorder
    if hb then
        -- Use the canonical DB key (highlightEnabled). Keep backward-compat with older profiles.
        local enabled = (g.highlightEnabled ~= false)
        if g.highlightEnabled == nil and g.enableHighlightOnHover ~= nil then
            enabled = (g.enableHighlightOnHover == true)
        end
        if enabled then
            local roundedHandled = false
            if _G.MSUF_RoundedUF_Active == true and self._msufRUF_SuppressMouseover == true then
                local roundedHover = _G.MSUF_RoundedUF_OnUnitMouseover
                if type(roundedHover) == "function" then
                    roundedHandled = roundedHover(self, true) and true or false
                end
            end
            if roundedHandled then
                hb:Hide()
            else
                if self.UpdateHighlightColor then self:UpdateHighlightColor() end
                if _G.MSUF_FixHighlightForFrame then _G.MSUF_FixHighlightForFrame(self) end
                hb:Show()
            end
        else
            hb:Hide()
        end
    end
    local u = self.unit
    if not (u and F.UnitExists and F.UnitExists(u)) then return end
    local tips = ns.Tooltips
    if tips and type(tips.ShowUnit) == "function" then
        tips.ShowUnit(self, u)
        return
    end
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnit(u)
        GameTooltip:Show()
    end
end
ns.UF.Unitframe_OnLeave = ns.UF.Unitframe_OnLeave or function(self)
    if _G.MSUF_RoundedUF_Active == true and self and self._msufRUF_SuppressMouseover == true then
        local roundedHover = _G.MSUF_RoundedUF_OnUnitMouseover
        if type(roundedHover) == "function" then roundedHover(self, false) end
    end
    if self and self.highlightBorder then self.highlightBorder:Hide() end
    local tips = ns.Tooltips
    if tips and type(tips.HideUnit) == "function" then
        tips.HideUnit(self)
    elseif GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
end
function ns.UF.HideLeaderAndRaidMarker(self)
    if not self then return end
    ns.Util.SetShown(self.leaderIcon, false)
    ns.Util.SetShown(self.raidMarkerIcon, false)
 end
local MSUF_QueueVisibilityDriverRefresh
function ns.UF.HandleDisabledFrame(self, conf)
    if not ns.UF.IsDisabled(conf) then return false end

    if self and self.isBoss and MSUF_IsBossUnitframePreviewActive() then
        return false
    end

    -- In MSUF Edit Mode, keep a persistent preview for frames that are disabled,
    -- so they can still be positioned/edited. Boss frames use the shared boss
    -- preview gate above and remain hard-hidden outside preview/test mode.
    if MSUF_UnitEditModeActive and (not _msuf_inCombat) and self and not self.isBoss then
        local fn = _G.MSUF_ApplyUnitframeEditPreview
        if type(fn) == "function" then
            fn(self, self.msufConfigKey or self.unit, conf)
        else
            if self.Show then self:Show() end
        end
        ns.UF.HideLeaderAndRaidMarker(self)
        return true
    end

    if not _msuf_inCombat then
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
    if _msuf_inCombat or (InCombatLockdown and InCombatLockdown()) then
        MSUF_QueueVisibilityDriverRefresh(false)
        return
    end
    local rsd = _G.RegisterStateDriver
    local usd = _G.UnregisterStateDriver
    if type(rsd) == "function" and type(usd) == "function" then
        usd(frame, "visibility")
        rsd(frame, "visibility", "hide")
    end
    frame._msufVisibilityForced = "disabled"
    frame._msufVisibilityAppliedDriver = "hide"
 end
-- P0: Centralized UFCore settings cache resolver (eliminates 4x copy/paste lazy-resolve blocks).
-- Returns the getter function (or nil). File-scope upvalue after first successful resolve.
local _MSUF_CachedGetCache = nil
local function _MSUF_ResolveGetCache()
    if _MSUF_CachedGetCache then return _MSUF_CachedGetCache end
    local fn = _G.MSUF_UFCore_GetSettingsCache
    if type(fn) == "function" then
        _MSUF_CachedGetCache = fn
        ns.Cache._UFCoreGetSettingsCache = fn
        return fn
    end
    return nil
end
local function _MSUF_GetUFCoreSettingsSerial()
    local getCache = _MSUF_ResolveGetCache()
    if getCache then
        local cache = getCache()
        if cache and type(cache.settingsSerial) == "number" then
            return cache.settingsSerial
        end
    end
    return (_G.MSUF_UFCORE_SETTINGS_SERIAL) or 0
end

local function _MSUF_IsVisualLiveApplyContext()
    if _G.MSUF_UnitEditModeActive then return true end
    local p = _G.MSUF_OptionsPanel
    if p and p.IsShown and p:IsShown() then return true end
    local sp = _G.SettingsPanel
    if sp and sp.IsShown and sp:IsShown() then return true end
    return false
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
    local settingsSerial = _MSUF_GetUFCoreSettingsSerial()
    if self._msufHeavyVisualSettingsSerial ~= settingsSerial or not self._msufHeavyVisualApplied then
        return true
    end
    if self.IsShown and not self:IsShown() then
        return false
    end
    if _msuf_inCombat then
        return false
    end
    if not _MSUF_IsVisualLiveApplyContext() then
        return false
    end
    local now = (F.GetTime and F.GetTime()) or 0
    local nextAt = self._msufHeavyVisualNextAt or 0
    if nextAt == 0 or now >= nextAt then
        return true
    end
    return false
end
do
    local realG = _G
    if type(realG.MSUF_GetCastbarTexture) ~= "function" then
        function realG.MSUF_GetCastbarTexture()
             return "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    end
end
local UnitFramesList = {}
-- Shared helpers used by early setup; keep deterministic iteration.
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
local _msufVisibilityDriverRefreshPending = false
local _msufVisibilityDriverRefreshForceShow = false
local _msufVisibilityDriverRegenFrame = (_G.CreateFrame and _G.CreateFrame("Frame")) or nil
function MSUF_QueueVisibilityDriverRefresh(forceShow)
    _msufVisibilityDriverRefreshPending = true
    _msufVisibilityDriverRefreshForceShow = forceShow and true or false
    if _msufVisibilityDriverRegenFrame then
        _msufVisibilityDriverRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end
if _msufVisibilityDriverRegenFrame then
    _msufVisibilityDriverRegenFrame:SetScript("OnEvent", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not _msufVisibilityDriverRefreshPending then return end
        local forceShow = _msufVisibilityDriverRefreshForceShow
        _msufVisibilityDriverRefreshPending = false
        _msufVisibilityDriverRefreshForceShow = false
        _msuf_inCombat = false
        _G.MSUF_InCombat = false
        local fn = _G.MSUF_RefreshAllUnitVisibilityDrivers
        if type(fn) == "function" then fn(forceShow) end
    end)
end
local function MSUF_EnsureUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsFocusTarget = (u == "focustarget")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    -- Perf: avoid pattern matching.
    local bi = (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(u))
    f._msufBossIndex = bi or nil
    f._msufUnitFlagsInited = true
 end
_G.MSUF_EnsureUnitFlags = MSUF_EnsureUnitFlags
local function MSUF_IsTargetLikeFrame(f)
    return (f and (f.isBoss or f._msufIsPlayer or f._msufIsTarget or f._msufIsFocus or f._msufIsFocusTarget)) and true or false
end
local function MSUF_ResetBarZero(bar, hide)
    if not bar then return end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.MSUF_lastValue = 0
    if hide then bar:Hide() end
 end
local function MSUF_ClearText(fs, hide)
    if not fs then return end
    fs:SetText("")
    if hide then fs:Hide() end
 end
function ns.Bars.ApplyPowerGradientOnce(frame)
    if not frame then return end
    local bar = frame.targetPowerBar or frame.powerBar
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local resolve = ns.Bars and ns.Bars._ResolveGradientValue
    local enabled = resolve and (resolve(frame, "enablePowerGradient", false) == true) or (g.enablePowerGradient == true)
    local strength = resolve and (tonumber(resolve(frame, "gradientStrength", 0.45)) or 0.45) or (tonumber(g.gradientStrength) or 0.45)
    local left = resolve and (resolve(frame, "gradientDirLeft", false) == true) or (g.gradientDirLeft == true)
    local right = resolve and (resolve(frame, "gradientDirRight", false) == true) or (g.gradientDirRight == true)
    local up = resolve and (resolve(frame, "gradientDirUp", false) == true) or (g.gradientDirUp == true)
    local down = resolve and (resolve(frame, "gradientDirDown", false) == true) or (g.gradientDirDown == true)
    local serial = _MSUF_GetUFCoreSettingsSerial()
    local w = bar and bar.GetWidth and bar:GetWidth() or nil
    local h = bar and bar.GetHeight and bar:GetHeight() or nil
    if frame._msufPowerGradEnabled == enabled
        and frame._msufPowerGradStrength == strength
        and frame._msufPowerGradLeft == left
        and frame._msufPowerGradRight == right
        and frame._msufPowerGradUp == up
        and frame._msufPowerGradDown == down
        and frame._msufPowerGradSerial == serial
        and frame._msufPowerGradW == w
        and frame._msufPowerGradH == h then
        return
    end
    frame._msufPowerGradEnabled = enabled
    frame._msufPowerGradStrength = strength
    frame._msufPowerGradLeft = left
    frame._msufPowerGradRight = right
    frame._msufPowerGradUp = up
    frame._msufPowerGradDown = down
    frame._msufPowerGradSerial = serial
    frame._msufPowerGradW = w
    frame._msufPowerGradH = h
    if frame.powerGradients then
        if ns.Bars._ApplyPowerGradient then ns.Bars._ApplyPowerGradient(frame) end
    elseif frame.powerGradient then
        if ns.Bars._ApplyPowerGradient then ns.Bars._ApplyPowerGradient(frame.powerGradient) end
    end
 end
function ns.Bars.PowerBarAllowed(barsConf, isBoss, isPlayer, isTarget, isFocus)
    local readEnabled = _G.MSUF_ReadUnitPowerBarEnabled
    if type(readEnabled) == "function" then
        if isPlayer then return readEnabled("player") end
        if isFocus then return readEnabled("focus") end
        if isTarget then return readEnabled("target") end
        if isBoss then return readEnabled("boss") end
    end
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
        local snap = ns._PBCSnap
        local colPB = (pTok and snap[pTok]) or snap[pType]
        if not colPB then
            colPB = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
        end
        pr, pg, pb = colPB.r, colPB.g, colPB.b
    end
    local s = bar._msufPwrCS
    if s then
        if s[1] == pr and s[2] == pg and s[3] == pb then
            ns.Bars.ApplyPowerGradientOnce(frame)
            return
        end
        s[1], s[2], s[3] = pr, pg, pb
    else
        bar._msufPwrCS = { pr, pg, pb }
    end
    bar:SetStatusBarColor(pr, pg, pb)
    ns.Bars.ApplyPowerGradientOnce(frame)
 end
local function MSUF_ApplyOverlayTextureAlpha(bar, alpha)
    if not bar then return end
    if type(alpha) == "number" then
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        bar._msufOverlayTextureAlpha = alpha
    else
        alpha = bar._msufOverlayTextureAlpha
    end
    local mul = tonumber(bar._msufAlphaTextureMul) or 1
    if type(alpha) ~= "number" then
        if mul == 1 then return end
        alpha = 1
    end
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and tex.SetAlpha then tex:SetAlpha(alpha * mul) end
end
ns.Bars._ApplyOverlayTextureAlpha = MSUF_ApplyOverlayTextureAlpha
_G.MSUF_ApplyOverlayTextureAlpha = MSUF_ApplyOverlayTextureAlpha
function ns.Bars.SetOverlayBarTexture(bar, texGetter)
    if not bar or not bar.SetStatusBarTexture or not texGetter then return end
    local tex = texGetter()
    if tex then
        bar:SetStatusBarTexture(tex)
        bar.MSUF_cachedStatusbarTexture = tex
        MSUF_ApplyOverlayTextureAlpha(bar)
    end
 end
-- Spec-driven bar apply (Health/Power/Absorb/HealAbsorb plus reset/hide).
-- 12.0: ApplySpec dispatcher eliminated. Callers use ns.Bars.Spec.* directly.
ns.Bars.Spec = ns.Bars.Spec or {}
ns.Bars.Spec.health = ns.Bars.Spec.health or function(frame, unit)
    if not frame or not unit or not frame.hpBar then  return nil, nil, false end
    if not (F.UnitExists and F.UnitExists(unit)) then
        ns.Bars.ResetHealthAndOverlays(frame, true)
         return 0, 1, false
    end
    -- 12.0: Unified calculator update â€” one C-side call for health + absorbs + prediction.
    -- Test mode path still uses legacy ApplyHealthBars for faked values.
    local absorbTestActive = (_G.MSUF_AbsorbTextureTestMode == true)
        and not (_G.MSUF_InCombat or (InCombatLockdown and InCombatLockdown()))
    local testFn = absorbTestActive and _G.MSUF_ShouldShowAbsorbTextureTest or nil
    if (type(testFn) == "function" and testFn(frame))
        or (absorbTestActive and type(testFn) ~= "function") then
        local maxHP = (F.UnitHealthMax and F.UnitHealthMax(unit)) or 1
        local hp = (F.UnitHealth and F.UnitHealth(unit)) or 0
        ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
        return hp, maxHP, true
    end
    local calcFn = ns.Bars.HealthCalcUpdate
    if calcFn then
        local hp, maxHP = calcFn(frame, unit)
        return hp, maxHP, true
    end
    -- Fallback: pre-12.0 path
    local maxHP = (F.UnitHealthMax and F.UnitHealthMax(unit)) or 1
    local hp = (F.UnitHealth and F.UnitHealth(unit)) or 0
    ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
     return hp, maxHP, true
end
local function _MSUF_Bars_HidePower(bar, hardReset)
    if not bar then return true end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    if bar._msufPowerBorder and bar._msufPowerBorder.Hide then
        bar._msufPowerBorder:Hide()
    end
    if hardReset then MSUF_ResetBarZero(bar, true) end
     return true
end
local function _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, wantPercent)
    if not (frame and bar and unit) then return false end
    if not (F.UnitExists and F.UnitExists(unit)) then
        return _MSUF_Bars_HidePower(bar, true)
    end
    if not MSUF_IsTargetLikeFrame(frame) then
        return _MSUF_Bars_HidePower(bar, true)
    end
    if not ns.Bars.PowerBarAllowed(barsConf, isBoss, isPlayer, isTarget, isFocus) then
        return _MSUF_Bars_HidePower(bar, true)
    end
    local pType, pTok
    pType, pTok = UnitPowerType(unit)
    if pType == nil then return _MSUF_Bars_HidePower(bar, false) end

    -- Ele Shaman: when Maelstrom is shown as class power, main bar shows Mana.
    -- Flag set by MSUF_ClassPower FullRefresh â€” zero-cost boolean check.
    if isPlayer and _G.MSUF_EleMaelstromActive then
        pType = 0   -- Enum.PowerType.Mana
        pTok  = "MANA"
    end
    -- Aug Evoker: when Ebon Might is shown as class power, main bar shows Essence.
    -- Mana moves to AltMana bar. Same flag pattern as Ele Shaman.
    if isPlayer and _G.MSUF_AugEvokerActive then
        pType = 19  -- Enum.PowerType.Essence
        pTok  = "ESSENCE"
    end
    -- Shadow Priest: class power shows Insanity â†’ main bar shows Mana.
    if isPlayer and _G.MSUF_ShadowManaActive then
        pType = 0   -- Enum.PowerType.Mana
        pTok  = "MANA"
    end

    ns.Bars.ApplyPowerBarVisual(frame, bar, pType, pTok)
    bar:SetScript("OnUpdate", nil)

    -- Smooth interpolation ONLY for player frame â€” target/focus/boss always snap.
    -- SECRET-SAFE: UnitPower/UnitPowerMax may return secret values in 12.0.
    -- Never call type()/tonumber()/comparisons on these â€” pass directly to C-side
    -- SetMinMaxValues/SetValue which handle secrets natively.
    local cur = UnitPower(unit, pType)
    local mx  = UnitPowerMax(unit, pType)
    if cur == nil then cur = 0 end
    if mx  == nil then mx  = 100 end

    local _interp = nil
    local getPowerSmooth = _G.MSUF_UFCore_GetPowerSmoothInterp
    if getPowerSmooth then
        _interp = getPowerSmooth(frame)
    elseif isPlayer then
        _interp = (not (MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.smoothPowerBar == false)) and MSUF_SMOOTH_INTERPOLATION or nil
    end
    if _interp then
        bar:SetMinMaxValues(0, mx, _interp)
        bar:SetValue(cur, _interp)
    else
        bar:SetMinMaxValues(0, mx)
        bar:SetValue(cur)
    end

    bar:Show()
     return true
end
ns.Bars.Spec.power_pct = ns.Bars.Spec.power_pct or function(frame, unit, barsConf, isBoss, isPlayer, isTarget, isFocus)
    local bar = frame and frame.targetPowerBar
    if not (frame and unit and bar) then  return false end
    barsConf = barsConf or ((MSUF_DB and MSUF_DB.bars) or {})
    return _MSUF_Bars_SyncPower(frame, bar, unit, barsConf, isBoss, isPlayer, isTarget, isFocus, true)
end

-- Global: force-refresh player power bar (called by ClassPower when Ele Maelstrom flag changes)
_G.MSUF_RefreshPlayerPowerBar = function()
    local pf = _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player)
    if pf and pf.targetPowerBar then
        local barsConf = (MSUF_DB and MSUF_DB.bars) or {}
        MSUF_EnsureUnitFlags(pf)
        _MSUF_Bars_SyncPower(pf, pf.targetPowerBar, "player", barsConf, false, true, false, false, false)
        -- Invalidate power text caches so text + color update immediately
        pf._msufPTColorType = nil    -- forces color re-apply
        pf._msufLastPwrC = nil       -- forces text re-render
        pf._msufLastPwrM = nil
        pf._msufLastPwrP = nil
        pf._msufPwrTextConf = nil    -- forces config re-read (mode may differ)
    end
end
-- Incoming heal prediction.
-- Implemented as a behind-the-HP statusbar so the additional segment only appears past current HP.

-- Self-heal prediction system moved to MSUF_SelfHealPred.lua

function ns.Bars.ResetHealthAndOverlays(frame, clearAbsorbs)
    if not frame then return end
    MSUF_ResetBarZero(frame.hpBar)
    local syncMissing = _G.MSUF_Alpha_UpdatePreserveMissingHP
    if type(syncMissing) == "function" then
        syncMissing(frame, 1, 1)
    end
    local healPredBar = frame.incomingHealBar or frame.selfHealPredBar
    if healPredBar then
        MSUF_ResetBarZero(healPredBar, true)
    end
    if clearAbsorbs then
        MSUF_ResetBarZero(frame.absorbBar, true)
        MSUF_ResetBarZero(frame.healAbsorbBar, true)
    end
 end
function ns.Bars.ApplyHealthBars(frame, unit, maxHP, hp)
    if not frame or not unit or not frame.hpBar then return nil, nil end
    -- 12.0: maxHP/hp may be secret values. SetMinMaxValues/SetValue handle them C-side.
    if maxHP == nil and F.UnitHealthMax then maxHP = F.UnitHealthMax(unit) end
    if hp == nil and F.UnitHealth then hp = F.UnitHealth(unit) end
    if maxHP ~= nil then frame.hpBar:SetMinMaxValues(0, maxHP) end
    if hp ~= nil then
        local setHealth = _G.MSUF_UFCore_SetHealthBarValue
        if setHealth then setHealth(frame, frame.hpBar, hp) else frame.hpBar:SetValue(hp) end
    end
    -- Test mode: show faked absorb values.
    local absorbTestActive = (_G.MSUF_AbsorbTextureTestMode == true)
        and not (_G.MSUF_InCombat or (InCombatLockdown and InCombatLockdown()))
    local testFn = absorbTestActive and _G.MSUF_ShouldShowAbsorbTextureTest or nil
    local absorbTestMode = type(testFn) == "function" and testFn(frame) or (absorbTestActive and type(testFn) ~= "function")
    local wasTestMode = frame._msufAbsorbTestActive
    if absorbTestMode then
        frame._msufAbsorbTestActive = true
        frame.hpBar:SetMinMaxValues(0, 100)
        frame.hpBar:SetValue(60)
    end
    local wasHealPredTestMode = frame._msufHealPredTestActive
    local healPredTestEnabled = false
    if absorbTestMode and ns.Bars._IsHealPredictionEnabled and ns.Bars._IsHealPredictionEnabled() then
        local setHealPredTest = ns.Bars._SetSelfHealPredictionTestValue
        if type(setHealPredTest) == "function" then
            frame._msufHealPredTestActive = true
            healPredTestEnabled = true
            setHealPredTest(frame, 100, 18)
        end
    end
    if wasHealPredTestMode and not healPredTestEnabled then
        frame._msufHealPredTestActive = nil
        local hideHealPred = ns.Bars._HideSelfHealPrediction
        if type(hideHealPred) == "function" then hideHealPred(frame) end
    end
    if frame.absorbBar and (absorbTestMode or wasTestMode) then
        ns.Bars._UpdateAbsorbBar(frame, unit, absorbTestMode and 100 or maxHP)
    end
    if frame.healAbsorbBar and (absorbTestMode or wasTestMode) then
        ns.Bars._UpdateHealAbsorbBar(frame, unit, absorbTestMode and 100 or maxHP)
    end
    if wasTestMode and not absorbTestMode then frame._msufAbsorbTestActive = nil end
     return hp, maxHP
end

-- ns.Text core rendering moved to MSUF_Text.lua

local MSUF_BarBorderCache = { stamp = nil, thickness = 0, byScope = {} }
local MSUF_BarBorderScopeIds = {
    shared = 0, player = 1, target = 2, focus = 3,
    targettarget = 4, focustarget = 5, pet = 6, boss = 7, party = 8, raid = 9,
}
local function MSUF_GetBarBorderStyleId(style)
    if style == "THICK" then return 2 end
    if style == "SHADOW" then return 3 end
    if style == "GLOW" then return 4 end
     return 1 -- THIN/default
end
local function MSUF_NormalizeBarBorderScope(frameOrUnit)
    local unit = frameOrUnit
    if type(frameOrUnit) == "table" then unit = frameOrUnit.unit end
    if type(unit) ~= "string" or unit == "" then return "shared" end
    if unit == "boss" or unit:sub(1, 4) == "boss" then return "boss" end
    return unit
end
local function MSUF_GetScopedBarBorderThicknessDB(scopeKey)
    if scopeKey == "shared" or not MSUF_DB then return nil end
    local db = MSUF_DB[scopeKey]
    if type(db) == "table" and db.hlOverride and db.barOutlineThickness ~= nil then
        return db
    end
    return nil
end
local function MSUF_GetDesiredBarBorderThicknessAndStamp(frameOrUnit)
    local scopeKey = MSUF_NormalizeBarBorderScope(frameOrUnit)
    local scopeCache = MSUF_BarBorderCache.byScope
    if type(scopeCache) ~= "table" then
        scopeCache = {}
        MSUF_BarBorderCache.byScope = scopeCache
    end

    local barsDB = MSUF_DB and MSUF_DB.bars
    local gDB    = MSUF_DB and MSUF_DB.general
    local scopedDB = MSUF_GetScopedBarBorderThicknessDB(scopeKey)
    local raw = (scopedDB and scopedDB.barOutlineThickness) or (barsDB and barsDB.barOutlineThickness)
    local rawNum = (type(raw) == "number") and raw or tonumber(raw)
    local rawToken = rawNum and math_floor(rawNum * 10 + 0.5) or -999
    local useBit = 1
    if gDB and gDB.useBarBorder == false then useBit = 0 end
    local showToken = 1 -- nil/unspecified
    if barsDB and barsDB.showBarBorder ~= nil then
        if barsDB.showBarBorder == false then showToken = 0 else showToken = 2 end
    end
    local styleId = MSUF_GetBarBorderStyleId(gDB and gDB.barBorderStyle)
    local scopeId = MSUF_BarBorderScopeIds[scopeKey] or 99
    local scopeBit = scopedDB and 1 or 0
    local stamp = scopeId * 10000000 + scopeBit * 1000000 + rawToken * 10000 + useBit * 1000 + showToken * 10 + styleId

    local cache = scopeCache[scopeKey]
    if not cache or cache.stamp ~= stamp then
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
        if thickness > 8 then thickness = 8 end
        cache = cache or {}
        cache.stamp = stamp
        cache.thickness = thickness
        scopeCache[scopeKey] = cache
        if scopeKey == "shared" then
            MSUF_BarBorderCache.stamp = stamp
            MSUF_BarBorderCache.thickness = thickness
        end
    end
    return cache.thickness, cache.stamp
end
_G.MSUF_BarBorderCache = MSUF_BarBorderCache
_G.MSUF_GetDesiredBarBorderThicknessAndStamp = MSUF_GetDesiredBarBorderThicknessAndStamp
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
    bar:SetValue(0)
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
-- Shared overlay color resolver (absorb + heal-absorb were identical except defaults + DB keys)
local function _MSUF_GetOverlayColor(defR, defG, defB, defA, keyR, keyG, keyB)
    local r, g, b, a = defR, defG, defB, defA
    local gen = MSUF_DB and MSUF_DB.general
    if gen then
        local ar, ag, ab = gen[keyR], gen[keyG], gen[keyB]
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            r = (ar < 0 and 0) or (ar > 1 and 1) or ar
            g = (ag < 0 and 0) or (ag > 1 and 1) or ag
            b = (ab < 0 and 0) or (ab > 1 and 1) or ab
    end
    end
     return r, g, b, a
end
local function MSUF_GetAbsorbOverlayColor()
    return _MSUF_GetOverlayColor(0.8, 0.9, 1.0, 0.6, "absorbBarColorR", "absorbBarColorG", "absorbBarColorB")
end
local function MSUF_GetHealAbsorbOverlayColor()
    return _MSUF_GetOverlayColor(1.0, 0.4, 0.4, 0.7, "healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB")
end
local function MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then return end
    if bar.MSUF_overlayR == r and bar.MSUF_overlayG == g and bar.MSUF_overlayB == b and bar.MSUF_overlayA == a then
         return
    end
    MSUF_SetStatusBarColor(bar, r, g, b, 1)
    MSUF_ApplyOverlayTextureAlpha(bar, a)
    bar.MSUF_overlayR, bar.MSUF_overlayG, bar.MSUF_overlayB, bar.MSUF_overlayA = r, g, b, a
 end
local function MSUF_ApplyAbsorbOverlayColor(bar, unit)
    local r, g, b, a = MSUF_GetAbsorbOverlayColor()
    local resolve = ns.Bars._ResolveAbsorbOpacity
    local op = resolve and resolve(unit) or nil
    if type(op) == "number" then
        if op < 0 then op = 0 elseif op > 1 then op = 1 end
        a = op
    end
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
 end
local function MSUF_ApplyHealAbsorbOverlayColor(bar, unit)
    local r, g, b, a = MSUF_GetHealAbsorbOverlayColor()
    local resolve = ns.Bars._ResolveHealAbsorbOpacity
    local op = resolve and resolve(unit) or nil
    if type(op) == "number" then
        if op < 0 then op = 0 elseif op > 1 then op = 1 end
        a = op
    end
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
 end
ns.Bars._ApplyAbsorbOverlayColor = MSUF_ApplyAbsorbOverlayColor
ns.Bars._ApplyHealAbsorbOverlayColor = MSUF_ApplyHealAbsorbOverlayColor
ns.Bars._ResetBarZero = MSUF_ResetBarZero
local function MSUF_NormalizeUnitKeyForDB(key)
    if not key or type(key) ~= "string" then return nil end
    if key == "tot" then
         return "targettarget"
    end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(key) then
         return "boss"
    end
     return key
end
local function MSUF_RaidGroupNameAllowedForKey(key)
    key = MSUF_NormalizeUnitKeyForDB(key)
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
end
local function MSUF_NormalizeRaidGroupNameAnchor(anchor)
    if anchor == "NAMELEFT" or anchor == "NAMERIGHT"
        or anchor == "TOPLEFT" or anchor == "TOPRIGHT"
        or anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
        or anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM"
        or anchor == "LEFT" or anchor == "RIGHT" then
        return anchor
    end
    return "NAMERIGHT"
end
local function MSUF_RaidGroupNamePreviewText(conf)
    local style = conf and conf.raidGroupNameStyle
    if style == "BRACKET" then return "[2]" end
    if style == "NONE" then return "2" end
    return "(2)"
end
_G.MSUF_RaidGroupNameAllowedForKey = _G.MSUF_RaidGroupNameAllowedForKey or MSUF_RaidGroupNameAllowedForKey
_G.MSUF_RaidGroupNamePreviewText = _G.MSUF_RaidGroupNamePreviewText or MSUF_RaidGroupNamePreviewText
local function MSUF_ResolveFrameDBKey(f)
    local key = f and (f.unitKey or f.unit or f.msufConfigKey)
    return MSUF_NormalizeUnitKeyForDB(key or "player") or "player"
end
local function MSUF_ApplyRaidGroupNameLayout_Internal(f, conf)
    if not f or not f.raidGroupNameText or not f.nameText then return end
    conf = conf or {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local layer = tonumber(conf.nameTextLayer)
    if layer == nil then layer = tonumber(g.nameTextLayer) end
    layer = math_floor((layer or 5) + 0.5)
    if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
    local anchor = MSUF_NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor or g.raidGroupNameAnchor)
    if conf.showName == false and (anchor == "NAMERIGHT" or anchor == "NAMELEFT") then
        anchor = "CENTER"
    end
    local x = (type(conf.raidGroupNameOffsetX) == "number") and conf.raidGroupNameOffsetX
        or ((type(g.raidGroupNameOffsetX) == "number") and g.raidGroupNameOffsetX or 3)
    local y = (type(conf.raidGroupNameOffsetY) == "number") and conf.raidGroupNameOffsetY
        or ((type(g.raidGroupNameOffsetY) == "number") and g.raidGroupNameOffsetY or 0)
    local anchorTo = f.nameText
    if f._msufNameClipFrame and f._msufNameClipFrame.IsShown and f._msufNameClipFrame:IsShown() then
        anchorTo = f._msufNameClipFrame
    end
    f._msufRaidGroupNameAnchor = anchor
    if not ns.Cache.StampChanged(f, "RaidGroupNameLayout", anchorTo, layer, anchor, x, y) then return end
    f.raidGroupNameText:ClearAllPoints()
    if anchor == "NAMERIGHT" then
        f.raidGroupNameText:SetPoint("LEFT", anchorTo, "RIGHT", x, y)
    elseif anchor == "NAMELEFT" then
        f.raidGroupNameText:SetPoint("RIGHT", anchorTo, "LEFT", x, y)
    else
        local af = f.textFrame or f
        f.raidGroupNameText:SetPoint(anchor, af, anchor, x, y)
    end
    if f.raidGroupNameText.SetJustifyH then f.raidGroupNameText:SetJustifyH("LEFT") end
    if f.raidGroupNameText.SetJustifyV then f.raidGroupNameText:SetJustifyV("MIDDLE") end
end
if not _G.MSUF_ApplyRaidGroupNameLayout then
    function _G.MSUF_ApplyRaidGroupNameLayout(f)
        if not f or not f.raidGroupNameText or not f.nameText then return end
        local key = MSUF_ResolveFrameDBKey(f)
        local conf = (MSUF_DB and MSUF_DB[key]) or {}
        MSUF_ApplyRaidGroupNameLayout_Internal(f, conf)
    end
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
    if conf.showName == false and (anchor == "NAMERIGHT" or anchor == "NAMELEFT") then
        anchor = "CENTER"
    end
    local layer = (ns.Icons and ns.Icons._layout and ns.Icons._layout.Layer and ns.Icons._layout.Layer(conf, g, "levelIndicatorLayer", 7)) or 7
    local raidGroupShown = f.raidGroupNameText and f.raidGroupNameText.IsShown and f.raidGroupNameText:IsShown()
        and f._msufRaidGroupNameAnchor == "NAMERIGHT"
    f._msufLevelAnchor = anchor
    if not ns.Cache.StampChanged(f, "LevelLayout", anchor, lx, ly, layer, raidGroupShown and 1 or 0) then return end
    if ns.Icons and ns.Icons._layout then
        if ns.Icons._layout.EnsureLayerFrame then ns.Icons._layout.EnsureLayerFrame(f, f.levelText, "levelText", f.textFrame or f) end
        if ns.Icons._layout.ApplyLayer then ns.Icons._layout.ApplyLayer(f.levelText, layer, f) end
    end
    f.levelText:ClearAllPoints()
    if anchor == "NAMELEFT" then
        f.levelText:SetPoint("RIGHT", f.nameText, "LEFT", -6 + lx, ly)
    elseif anchor == "NAMERIGHT" then
        local rel = raidGroupShown and f.raidGroupNameText or f.nameText
        local gap = raidGroupShown and 4 or 6
        f.levelText:SetPoint("LEFT", rel, "RIGHT", gap + lx, ly)
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
        if f.isBoss and MSUF_BossTestMode and not _msuf_inCombat and ns.Text and ns.Text.ApplyBossTestLevel then
            ns.Text.ApplyBossTestLevel(f, conf)
        end
     end
end
function _G.MSUF_RefreshLevelIndicatorFrames()
    local applyFn = _G.MSUF_ApplyLevelIndicatorLayout
    if type(applyFn) ~= "function" then return end

    local each = _G.MSUF_ForEachUnitFrame
    if type(each) == "function" then
        each(function(frame)
            if frame and frame.levelText then
                applyFn(frame)
            end
        end)
        return
    end

    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame and frame.levelText then
            applyFn(frame)
        end
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
local MSUF_SMOOTH_INTERPOLATION = (type(Enum) == "table"
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil
-- Performance/Secret-safe (no MSUF_FastCall): NEVER compare (numbers can be "secret"). Always apply the value.
-- This avoids secret-compare crashes entirely and removes tostring/tonumber churn from hotpaths.
-- 12.0: bar:SetValue handles secrets natively. Thin compat wrapper.
function MSUF_SetBarValue(bar, value) if bar and value ~= nil then bar:SetValue(value) end end
-- 12.0: bar:SetMinMaxValues handles secrets natively. Thin compat wrapper.
function MSUF_SetBarMinMax(bar, minValue, maxValue) if bar then bar:SetMinMaxValues(minValue, maxValue) end end
MSUF_UnitEditModeActive = (MSUF_UnitEditModeActive == true)
MSUF_CurrentOptionsKey = MSUF_CurrentOptionsKey
MSUF_CurrentEditUnitKey = MSUF_CurrentEditUnitKey
MSUF_EditModeSizing = false
if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
    MSUF_SyncBossUnitframePreviewWithUnitEdit()
end
-- Font registry moved to Core\MSUF_FontRegistry.lua
-- Castbar utilities moved to MSUF_Castbars.lua

-- Bar background runtime moved to Core/MSUF_BarBackgroundRuntime.lua.
local function GetConfigKeyForUnit(unit)
    if unit == "tot" then unit = "targettarget" end
    if unit == "focus_target" or unit == "focustargettarget" then unit = "focustarget" end
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "focustarget"
        or unit == "pet"
    then
         return unit
    elseif _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit) then
         return "boss"
    end
     return nil
end
_G.MSUF_GetConfigKeyForUnit = GetConfigKeyForUnit
-- Alpha system moved to MSUF_Alpha.lua

-- Castbar preview toggle moved to MSUF_Castbars.lua


-- Blizzard Frame Kill System + Compat Anchors + HideDefaultFrames
-- Extracted to Foundation/MSUF_BlizzKill.lua for maintainability.
-- Exports: _G.MSUF_KillFrame, _G.MSUF_HideDefaultFrames,
--          _G.MSUF_ApplyCompatAnchor_PlayerFrame, _G.MSUF_SafeDisableMouse
-- Called from init: _G.MSUF_HideDefaultFrames()

local function MSUF_GetVisibilityDriverForUnit(unit)
    if unit == "target" then
         return "[@target,exists] show; hide"
    elseif unit == "focus" then
         return "[@focus,exists] show; hide"
    elseif unit == "focustarget" then
         return "[@focustarget,exists] show; hide"
    elseif unit == "pet" then
         return "[@pet,exists] show; hide"
    elseif unit == "targettarget" then
         return "[@targettarget,exists] show; hide"
    elseif _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit) then
        return ("[@" .. unit .. ",exists] show; hide")
    end
     return nil
end
local function MSUF_ApplyUnitVisibilityDriver(frame, forceShow)
    if not frame or not frame.unit then return end
    if frame.unit == "player" then return end
if not MSUF_DB then MSUF_EnsureDB() end
local confKey
if frame.isBoss or (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(frame.unit)) then
    confKey = "boss"
else
    confKey = frame.unit
end
local conf = (type(MSUF_DB) == "table" and confKey and MSUF_DB[confKey]) or nil
local focusTargetDisabled = frame.unit == "focustarget"
    and type(_G.MSUF_IsFocusTargetEffectiveEnabled) == "function"
    and not _G.MSUF_IsFocusTargetEffectiveEnabled()
if ns.UF.IsDisabled(conf) or focusTargetDisabled then
    -- In MSUF Edit Mode, keep disabled frames editable by allowing forceShow previews.
    -- Boss frames use their dedicated preview gate, shared by Edit Mode and the
    -- Boss menu on-screen preview.
    local allowBossPreview = frame and frame.isBoss and MSUF_IsBossUnitframePreviewActive()
    if not ((forceShow and MSUF_UnitEditModeActive and (not _msuf_inCombat) and frame and not frame.isBoss)
        or allowBossPreview) then
        ns.UF.ForceVisibilityHidden(frame)
        return
    end
end
    local drv = frame._msufVisibilityDriver
    if not drv then
        drv = MSUF_GetVisibilityDriverForUnit(frame.unit)
        frame._msufVisibilityDriver = drv
    end
    if not drv then return end
    local rsd = _G.RegisterStateDriver
    local usd = _G.UnregisterStateDriver
    if type(rsd) ~= "function" or type(usd) ~= "function" then  return end
    if not forceShow and frame.isBoss and MSUF_BossTestMode and not _msuf_inCombat then
        forceShow = true
    end
    if not forceShow and not frame.isBoss and not frame._msufIsPlayer and _G.MSUF_PreviewTestMode and not _msuf_inCombat then
        forceShow = true
    end
    local forced = (forceShow and true or false)
    local driverToApply = forced and "show" or drv
    if forced and frame.isBoss and MSUF_BossTestMode and not _msuf_inCombat then
        driverToApply = "[combat] hide; show"
    end
    if frame._msufVisibilityForced == forced and frame._msufVisibilityAppliedDriver == driverToApply then
          return
    end
    if _msuf_inCombat or (InCombatLockdown and InCombatLockdown()) then
        MSUF_QueueVisibilityDriverRefresh(forced)
        return
    end
    frame._msufVisibilityForced = forced
    frame._msufVisibilityAppliedDriver = driverToApply
    usd(frame, "visibility")
    rsd(frame, "visibility", driverToApply)
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
    if not co then return end
    co.queued = false
    local frames = co.frames
    local force = co.force
    local layout = co.layout
    local reason = co.reason
    co.reason = nil
    local wipe = table.wipe
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
    if wipe then
        wipe(frames)
        wipe(force)
        wipe(layout)
    end
 end
function _G.MSUF_RequestUnitframeUpdate(frame, forceFull, wantLayout, reason, urgentNow)
    -- Accept both frame objects and unit tokens ("target", "focus", "boss1", ...).
    -- Several callers (eg. RangeFade) operate on unit tokens; UFCore expects actual frame objects.
    if type(frame) == "string" then
        frame = _G["MSUF_" .. frame]
    end
    if not frame then return end

    local reqLayout = _G.MSUF_UFCore_RequestLayout
    local queueUF = _G.MSUF_QueueUnitframeUpdate
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local directLite = (not g or g.perfLiteDirectUFReq ~= false)

    -- Phase 1 / Patch 3:
    -- Bypass the extra main-file next-frame coalescer and hand work directly to UFCore.
    -- UFCore already dedupes dirty masks, coalesces layout, and owns the real flush lifecycle,
    -- so keeping a second timer-based queue here just adds another wakeup/merge layer in combat.
    if directLite then
        if wantLayout and type(reqLayout) == "function" then
            reqLayout(frame, reason or "MSUF_RequestUnitframeUpdate", urgentNow == true)
        end
        if type(queueUF) == "function" then
            queueUF(frame, forceFull and true or false)
        end
        return
    end

    if urgentNow == true then
        if wantLayout and type(reqLayout) == "function" then
            reqLayout(frame, reason or "MSUF_RequestUnitframeUpdate", true)
        end
        if type(queueUF) == "function" then
            queueUF(frame, forceFull and true or false)
        end
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
    -- Legacy fallback coalescer: keep as an escape hatch only.
    if co.frames[frame] then
        if (not forceFull or co.force[frame]) and (not wantLayout or co.layout[frame]) then return end
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
    if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("UF_REQUEST_FLUSH", _G.__MSUF_UFREQ_Flush) else C_Timer.After(0, _G.__MSUF_UFREQ_Flush) end
 end
local function MSUF_GetUnitLabelForKey(key)
    if key == "player" then
         return "Player"
    elseif key == "target" then
         return "Target"
    elseif key == "targettarget" then
         return "Target of Target"
    elseif key == "focustarget" then
         return "Focus Target"
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
-- Options openers removed (dead code)

-- UpdateCastbarVisuals moved to MSUF_Castbars.lua

local function MSUF_UpdateNameColor(frame)
    if not frame or not frame.nameText then return end

    local getCache = _MSUF_CachedGetCache or _MSUF_ResolveGetCache()
    local cache = getCache and getCache() or nil

    local g = (cache and cache.generalRef) or ((MSUF_DB and MSUF_DB.general) or nil)
    if not g then
        if not MSUF_DB then MSUF_EnsureDB() end
        g = (MSUF_DB and MSUF_DB.general) or nil
    end

    -- Read name color flags from DB directly (settings cache can be stale after
    -- options-UI toggles; its validity is keyed on table-reference identity).
    local nameClassColor = g and g.nameClassColor
    local npcNameRed = g and g.npcNameRed

    -- Per-unit font override: read from unit config if fontOverride active
    do
        local ck = frame.msufConfigKey
        local fc = ck and MSUF_DB and MSUF_DB[ck]
        if fc and fc.fontOverride then
            if fc.nameClassColor ~= nil then nameClassColor = fc.nameClassColor end
            if fc.npcNameRed ~= nil then npcNameRed = fc.npcNameRed end
        end
    end

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
        -- Resolve NPC color helper once (eliminates 4x identical lookup)
        local fastNPC = _G.MSUF_UFCore_GetNPCReactionColorFast
        local _npcColor = (type(fastNPC) == "function") and fastNPC or MSUF_GetNPCReactionColor
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost(frame.unit) then
            r, gCol, b = _npcColor("dead")
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", frame.unit)
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = _npcColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = _npcColor("neutral")
                else
                    r, gCol, b = _npcColor("enemy")
                end
            end
    end
    end
    if not (r and gCol and b) then
        r, gCol, b = MSUF_GetConfiguredFontColor()
    end
    r, gCol, b = r or 1, gCol or 1, b or 1
    if frame._msufNameColorR == r and frame._msufNameColorG == gCol and frame._msufNameColorB == b then return end
    frame._msufNameColorR, frame._msufNameColorG, frame._msufNameColorB = r, gCol, b
    frame.nameText:SetTextColor(r, gCol, b, 1)
    if frame.raidGroupNameText then
        frame.raidGroupNameText:SetTextColor(r, gCol, b, 1)
    end
    if frame.levelText then
        frame.levelText:SetTextColor(r, gCol, b, 1)
    end
 end
_G.MSUF_UpdateNameColor = MSUF_UpdateNameColor
local function _Iter_RefreshNameColor(f)
    if f and f.nameText and f.unit and F.UnitExists(f.unit) then
        MSUF_UpdateNameColor(f)
    end
end
_G.MSUF_RefreshAllIdentityColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
    if type(MSUF_UpdateNameColor) ~= "function" or type(F.UnitExists) ~= "function" then  return end
    MSUF_ForEachUnitFrame(_Iter_RefreshNameColor)
 end
local function _Iter_RefreshPowerColor(f)
    local S = _iterState
    if f and f.powerText and f.unit and F.UnitExists(f.unit) then
        -- Force RenderPowerText to re-resolve config/color state on every manual
        -- UI toggle flip. This is not a hot path; it only runs from the options UI.
        f._msufPwrTextConf = nil
        f._msufPTColorType = nil
        f._msufPTColorTok = nil
        f._msufPTColorByPower = nil
        if f.powerText then
            f.powerText._msufColorRev = nil
        end
        if f.powerTextLeft then
            f.powerTextLeft._msufColorRev = nil
        end
        if f.powerTextCenter then
            f.powerTextCenter._msufColorRev = nil
        end
        if f.powerTextPct then
            f.powerTextPct._msufColorRev = nil
        end

        -- Per-unit font override: resolve colorByType per frame
        local frameColorByType = S.colorByType
        do
            local ck = f.msufConfigKey
            local fc = ck and MSUF_DB and MSUF_DB[ck]
            if fc and fc.fontOverride and fc.colorPowerTextByType ~= nil then
                frameColorByType = fc.colorPowerTextByType and true or false
            end
        end

        if frameColorByType then
            if S.updatePowerFast then
                S.updatePowerFast(f)
            end
        else
            local fr, fg, fb = S.fr, S.fg, S.fb
            if f.powerText.SetTextColor then
                f.powerText:SetTextColor(fr, fg, fb, 1)
            end
            if f.powerTextLeft and f.powerTextLeft.SetTextColor then
                f.powerTextLeft:SetTextColor(fr, fg, fb, 1)
            end
            if f.powerTextCenter and f.powerTextCenter.SetTextColor then
                f.powerTextCenter:SetTextColor(fr, fg, fb, 1)
            end
            if f.powerTextPct and f.powerTextPct.SetTextColor then
                f.powerTextPct:SetTextColor(fr, fg, fb, 1)
            end
        end
    end
end
_G.MSUF_RefreshAllPowerTextColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
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

local function MSUF_ResolveConfiguredAnchorFrame(key, conf, fallbackAnchor)
    local anchor = fallbackAnchor or (MSUF_GetAnchorFrame and MSUF_GetAnchorFrame()) or UIParent
    if not conf then return anchor end

    local customName = conf.anchorFrameName
    if type(customName) == "string" and customName ~= "" then
        local custom = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and customName == "EssentialCooldownViewer") and _G.MSUF_GetEffectiveCooldownFrame(customName) or (_G and _G[customName])
        if custom and custom ~= UIParent and custom ~= WorldFrame and (not custom.IsForbidden or not custom:IsForbidden()) then
            return custom
        end
        return anchor, customName
    end

    local atv = conf.anchorToUnitframe
    if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "FREE" and atv ~= "global" then
        local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
        local rel = uf and uf[atv] or nil
        if not rel then rel = _G and _G["MSUF_" .. atv] or nil end
        if rel and rel ~= UIParent and rel ~= WorldFrame and (not rel.IsForbidden or not rel:IsForbidden()) then
            return rel
        end
        return anchor, atv
    end

    return anchor
end

local function MSUF_IsUnitFrameAnchor(anchor)
    if not anchor then return false end
    local uf = UnitFrames or _G.MSUF_UnitFrames or _G.UnitFrames
    if not uf then return false end
    for _, frame in pairs(uf) do
        if frame == anchor then
            return true
        end
    end
    return false
end

local function MSUF_ShouldSnapshotExternalAnchor(anchor)
    return anchor and anchor ~= UIParent and anchor ~= WorldFrame and not anchor._msufStableAnchorProxy and not MSUF_IsUnitFrameAnchor(anchor)
end

function _G.MSUF_IsSecretValue(v)
    local isv = _MSUF_issecretvalue
    if not isv then
        isv = _G.issecretvalue
        if isv then _MSUF_issecretvalue = isv end
    end
    if not isv then return false end
    return isv(v) == true
end

function _G.MSUF_CallFrameMethod(frame, methodName)
    if not frame then return false end
    local fn = frame[methodName]
    if not fn then return false end
    return pcall(fn, frame)
end

function _G.MSUF_FrameMethodIsTrue(frame, methodName, secretDefault)
    local ok, value = _G.MSUF_CallFrameMethod(frame, methodName)
    if not ok then return false end
    if _G.MSUF_IsSecretValue(value) then return secretDefault == true end
    return value == true
end

function _G.MSUF_FrameMethodIsFalse(frame, methodName)
    local ok, value = _G.MSUF_CallFrameMethod(frame, methodName)
    if not ok then return false end
    if _G.MSUF_IsSecretValue(value) then return false end
    return value == false
end

function _G.MSUF_IsPlainNumber(v)
    if _G.MSUF_IsSecretValue(v) then return false end
    return type(v) == "number"
end

local function MSUF_IsLayoutEditingActive()
    if _G.MSUF_UnitEditModeActive == true then return true end
    local editState = _G.MSUF_EditState
    if type(editState) == "table" and editState.active == true then return true end
    local options = _G.MSUF_StandaloneOptionsWindow
    if options and options.IsShown and options:IsShown() then return true end
    return false
end
_G.MSUF_IsLayoutEditingActive = MSUF_IsLayoutEditingActive

local function MSUF_IsExternalAnchorUsable(anchor)
    if not MSUF_ShouldSnapshotExternalAnchor(anchor) then return true end
    if _G.MSUF_FrameMethodIsTrue(anchor, "IsForbidden", true) then return false end
    if not anchor.GetCenter then return false end

    local okCenter, ax, ay = _G.MSUF_CallFrameMethod(anchor, "GetCenter")
    if not (okCenter and _G.MSUF_IsPlainNumber(ax) and _G.MSUF_IsPlainNumber(ay)) then return false end

    if anchor.GetWidth and anchor.GetHeight then
        local okW, w = _G.MSUF_CallFrameMethod(anchor, "GetWidth")
        local okH, h = _G.MSUF_CallFrameMethod(anchor, "GetHeight")
        if not (okW and okH and _G.MSUF_IsPlainNumber(w) and _G.MSUF_IsPlainNumber(h) and w > 1 and h > 1) then return false end
    end

    if UIParent and UIParent.GetWidth and anchor.GetLeft and anchor.GetRight and anchor.GetTop and anchor.GetBottom then
        local okUIW, uiW = _G.MSUF_CallFrameMethod(UIParent, "GetWidth")
        local okUIH, uiH = _G.MSUF_CallFrameMethod(UIParent, "GetHeight")
        local okBounds, l, r, t, b = pcall(function()
            return anchor:GetLeft(), anchor:GetRight(), anchor:GetTop(), anchor:GetBottom()
        end)
        if okUIW and okUIH and okBounds
            and _G.MSUF_IsPlainNumber(uiW) and _G.MSUF_IsPlainNumber(uiH)
            and _G.MSUF_IsPlainNumber(l) and _G.MSUF_IsPlainNumber(r)
            and _G.MSUF_IsPlainNumber(t) and _G.MSUF_IsPlainNumber(b)
        then
            if r < -8 or l > (uiW + 8) or t < -8 or b > (uiH + 8) then
                return false
            end
        end
    end

    return true
end
_G.MSUF_IsExternalAnchorUsable = MSUF_IsExternalAnchorUsable

function _G.MSUF_GetProfileScopedCache(rootKey)
    MSUF_GlobalDB = MSUF_GlobalDB or {}
    MSUF_GlobalDB[rootKey] = MSUF_GlobalDB[rootKey] or {}
    local charKey = "global"
    if type(MSUF_GetCharKey) == "function" then
        local ok, v = pcall(MSUF_GetCharKey)
        if ok and type(v) == "string" and v ~= "" then charKey = v end
    end
    local profile = tostring(_G.MSUF_ActiveProfile or MSUF_ActiveProfile or "Default")
    local byChar = MSUF_GlobalDB[rootKey][charKey]
    if type(byChar) ~= "table" then
        byChar = {}
        MSUF_GlobalDB[rootKey][charKey] = byChar
    end
    local bucket = byChar[profile]
    if type(bucket) ~= "table" then
        bucket = {}
        byChar[profile] = bucket
    end
    return bucket
end

function _G.MSUF_GetExternalAnchorCacheKey(anchorOrName)
    if type(anchorOrName) == "string" and anchorOrName ~= "" then
        return anchorOrName
    end
    local anchor = anchorOrName
    if not anchor then return nil end
    if anchor.GetName then
        local name = anchor:GetName()
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(anchor)
end

function _G.MSUF_GetExternalAnchorCacheBucket()
    return _G.MSUF_GetProfileScopedCache("externalAnchorCache")
end

function _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local k = tostring(key or "")
    local u = tostring(unit or "")
    if k == "" then return u ~= "" and u or nil end
    if k == "boss" and u ~= "" then return k .. ":" .. u end
    return k
end

function _G.MSUF_GetUnitFrameScreenCacheBucket()
    return _G.MSUF_GetProfileScopedCache("unitFrameScreenCache")
end

function _G.MSUF_GetSavedFrameScale()
    local g = MSUF_DB and MSUF_DB.general
    local v = tonumber(g and g.msufUiScale) or tonumber(g and g.uiScale) or 1
    if v < 0.25 then v = 0.25 elseif v > 1.5 then v = 1.5 end
    return v
end

local function MSUF_GetFramePoint(frame, point)
    if not frame then return nil, nil, nil end
    point = point or "CENTER"
    if point == "CENTER" and frame.GetCenter then
        local x, y = frame:GetCenter()
        return x, y, "CENTER"
    end
    if not frame.GetLeft or not frame.GetRight or not frame.GetTop or not frame.GetBottom then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not l or not r or not t or not b then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end
    local cx = (l + r) * 0.5
    local cy = (t + b) * 0.5
    if point == "TOPLEFT" then return l, t, point end
    if point == "TOP" then return cx, t, point end
    if point == "TOPRIGHT" then return r, t, point end
    if point == "LEFT" then return l, cy, point end
    if point == "RIGHT" then return r, cy, point end
    if point == "BOTTOMLEFT" then return l, b, point end
    if point == "BOTTOM" then return cx, b, point end
    if point == "BOTTOMRIGHT" then return r, b, point end
    return cx, cy, "CENTER"
end

function _G.MSUF_ApplyInitialFrameScale(frame)
    if not frame or not frame.SetScale then return false end
    local scale = (_G.MSUF_GetSavedFrameScale and _G.MSUF_GetSavedFrameScale()) or 1
    local ok = pcall(frame.SetScale, frame, scale)
    if ok then frame._msufInitialScaleApplied = scale end
    return ok == true
end

local function MSUF_GetDirectCooldownLockPoint(key, frame)
    if key == "classpower" then return "TOP" end
    local rule = key and MSUF_ECV_ANCHORS and MSUF_ECV_ANCHORS[key]
    if rule and rule[1] then return rule[1] end
    if frame and frame._msufHardLockPoint then return frame._msufHardLockPoint end
    return "CENTER"
end

function _G.MSUF_CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
    if not frame or not key or not UIParent then return false end
    if allowLocked ~= true and InCombatLockdown and InCombatLockdown() then return false end
    if not UIParent.GetCenter then return false end
    point = point or ((frame._msufDirectCooldownAnchor or frame._msufHardLockedToUIParent) and frame._msufHardLockPoint) or "CENTER"
    local fx, fy, usedPoint = MSUF_GetFramePoint(frame, point)
    point = usedPoint or "CENTER"
    local ux, uy = UIParent:GetCenter()
    if not fx or not fy or not ux or not uy then return false end

    local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local us = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if fs == 0 then fs = 1 end
    if us == 0 then us = 1 end
    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    if not id then return false end
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    if not bucket then return false end

    local x = math_floor(((fx * fs - ux * us) / us) + 0.5)
    local y = math_floor(((fy * fs - uy * us) / us) + 0.5)
    local w = frame.GetWidth and frame:GetWidth() or nil
    local h = frame.GetHeight and frame:GetHeight() or nil
    local visW = w and (w * fs / us) or nil
    local visH = h and (h * fs / us) or nil
    local scale = frame.GetScale and frame:GetScale() or nil
    bucket[id] = { v = 3, x = x, y = y, w = w, h = h, visW = visW, visH = visH, scale = scale, point = point }
    return true
end

function _G.MSUF_ApplyCachedUnitFrameScreenPosition(frame, key, unit)
    if not frame or not key or not UIParent then return false end
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local cached = bucket and id and bucket[id]
    if type(cached) ~= "table" then return false end
    if cached.v ~= 2 and cached.v ~= 3 then return false end
    local x, y = tonumber(cached.x), tonumber(cached.y)
    if not x or not y then return false end
    if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
        pcall(frame.SetScale, frame, tonumber(cached.scale))
    elseif _G.MSUF_ApplyInitialFrameScale then
        _G.MSUF_ApplyInitialFrameScale(frame)
    end
    local point = cached.point
    if type(point) ~= "string" or point == "" then point = "CENTER" end
    if point == "CENTER" then
        local savedVisW = tonumber(cached.visW)
        if not savedVisW and tonumber(cached.w) then
            local savedScale = tonumber(cached.scale) or ((_G.MSUF_GetSavedFrameScale and _G.MSUF_GetSavedFrameScale()) or 1)
            savedVisW = tonumber(cached.w) * savedScale
        end
        if savedVisW and frame.GetWidth and frame.GetEffectiveScale and UIParent.GetEffectiveScale then
            local fs = frame:GetEffectiveScale() or 1
            local us = UIParent:GetEffectiveScale() or 1
            if fs == 0 then fs = 1 end
            if us == 0 then us = 1 end
            local curVisW = (frame:GetWidth() or 0) * fs / us
            if curVisW > 0 then
                local rule = MSUF_ECV_ANCHORS and MSUF_ECV_ANCHORS[key]
                local rulePoint = rule and rule[1] or nil
                if rulePoint == "RIGHT" or key == "player" then
                    x = x + ((savedVisW - curVisW) * 0.5)
                elseif rulePoint == "LEFT" or key == "target" then
                    x = x + ((curVisW - savedVisW) * 0.5)
                end
            end
        end
    end
    x = math_floor(x + 0.5)
    y = math_floor(y + 0.5)
    local ok = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, "CENTER", x, y)
    end)
    if not ok then return false end
    frame._msufPositionInitialized = true
    frame._msufHardLockedToUIParent = true
    frame._msufHardLockPoint = point
    frame._msufStableExternalAnchor = nil
    frame._msufStableExternalSig = nil
    frame._msufLoadedFromScreenCache = true
    return true
end

function _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key)
    if not proxy or not key or not UIParent then return false end
    local bucket = _G.MSUF_GetExternalAnchorCacheBucket()
    local cached = bucket and bucket[key]
    if type(cached) ~= "table" then return false end
    if cached.v ~= 2 then return false end
    local x, y = tonumber(cached.x), tonumber(cached.y)
    if not x or not y then return false end
    local w = tonumber(cached.w) or 1
    local h = tonumber(cached.h) or 1
    local ok = pcall(function()
        proxy:ClearAllPoints()
        proxy:SetSize(math.max(1, w), math.max(1, h))
        proxy:SetPoint("CENTER", UIParent, "CENTER", x, y)
        if proxy.Show then proxy:Show() end
    end)
    if ok then
        proxy._msufExternalAnchorCacheKey = key
        proxy._msufExternalAnchorFromCache = true
        proxy._msufProxyInitialized = true
    end
    return ok == true
end

function _G.MSUF_IsCooldownExternalAnchorKey(key, source)
    if key == "EssentialCooldownViewer" or key == "UtilityCooldownViewer" or key == "BuffIconCooldownViewer" then
        return true
    end
    if source and source.GetName then
        local name = source:GetName()
        if type(name) == "string" and string.find(name, "CooldownViewer", 1, true) then
            return true
        end
    end
    return false
end

function _G.MSUF_AccumulateScaledFrameBounds(frame, bounds, depth, uiScale, uiW, uiH)
    if not frame or depth < 0 then return bounds end
    if _G.MSUF_FrameMethodIsTrue(frame, "IsForbidden", true) then return bounds end
    if _G.MSUF_FrameMethodIsFalse(frame, "IsShown") then return bounds end

    if frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom then
        local okBounds, l, r, t, b = pcall(function()
            return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        end)
        if okBounds
            and _G.MSUF_IsPlainNumber(l) and _G.MSUF_IsPlainNumber(r)
            and _G.MSUF_IsPlainNumber(t) and _G.MSUF_IsPlainNumber(b)
            and r > l and t > b
        then
            local w, h = r - l, t - b
            local hasUIW = _G.MSUF_IsPlainNumber(uiW)
            local hasUIH = _G.MSUF_IsPlainNumber(uiH)
            if w >= 2 and h >= 2 and (not hasUIW or w <= uiW) and (not hasUIH or h <= uiH) then
                local s = 1
                local okScale, scaleValue = _G.MSUF_CallFrameMethod(frame, "GetEffectiveScale")
                if okScale and _G.MSUF_IsPlainNumber(scaleValue) and scaleValue ~= 0 then
                    s = scaleValue
                end
                if not _G.MSUF_IsPlainNumber(uiScale) or uiScale == 0 then uiScale = 1 end
                local scale = s / uiScale
                local sl, sr = l * scale, r * scale
                local st, sb = t * scale, b * scale
                if not bounds then
                    bounds = { l = sl, r = sr, t = st, b = sb, count = 1 }
                else
                    if sl < bounds.l then bounds.l = sl end
                    if sr > bounds.r then bounds.r = sr end
                    if st > bounds.t then bounds.t = st end
                    if sb < bounds.b then bounds.b = sb end
                    bounds.count = (bounds.count or 0) + 1
                end
            end
        end
    end

    if depth > 0 and frame.GetNumChildren and frame.GetChildren then
        local okChildren, children = pcall(function()
            return { frame:GetChildren() }
        end)
        if okChildren and type(children) == "table" then
            for i = 1, #children do
                bounds = _G.MSUF_AccumulateScaledFrameBounds(children[i], bounds, depth - 1, uiScale, uiW, uiH)
            end
        end
    end
    return bounds
end

function _G.MSUF_GetExternalAnchorVisualBounds(source, key)
    if not source or not UIParent or not UIParent.GetCenter then return nil end
    local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale == 0 then uiScale = 1 end
    local uiW = UIParent.GetWidth and UIParent:GetWidth() or nil
    local uiH = UIParent.GetHeight and UIParent:GetHeight() or nil

    local bounds
    if _G.MSUF_IsCooldownExternalAnchorKey(key, source) and source.GetChildren then
        local okChildren, children = pcall(function()
            return { source:GetChildren() }
        end)
        if okChildren and type(children) == "table" then
            for i = 1, #children do
                bounds = _G.MSUF_AccumulateScaledFrameBounds(children[i], bounds, 3, uiScale, uiW, uiH)
            end
        end
    end
    if not bounds then
        bounds = _G.MSUF_AccumulateScaledFrameBounds(source, nil, 0, uiScale, uiW, uiH)
    end
    if not bounds or not bounds.l or not bounds.r or not bounds.t or not bounds.b then return nil end
    local ux, uy = UIParent:GetCenter()
    if not ux or not uy then return nil end
    local centerX = ((bounds.l + bounds.r) * 0.5) - ux
    local centerY = ((bounds.t + bounds.b) * 0.5) - uy
    return centerX, centerY, bounds.r - bounds.l, bounds.t - bounds.b
end

function _G.MSUF_UpdateExternalAnchorProxy(proxy, source)
    if not proxy then return false end
    local key = _G.MSUF_GetExternalAnchorCacheKey(source) or proxy._msufExternalAnchorCacheKey
    if not key then return false end
    proxy._msufExternalAnchorCacheKey = key
    if type(source) == "string" then source = nil end
    if source then
        proxy._msufExternalAnchorSource = source
    end
    if _G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked() then
        if proxy._msufProxyInitialized then
            return true
        end
        if _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key) == true then
            return true
        end
        source = source or proxy._msufExternalAnchorSource
        if not source then
            return false
        end
        if not _G.MSUF_IsCooldownExternalAnchorKey(key, source) and not MSUF_IsExternalAnchorUsable(source) then
            return false
        end
    end
    source = source or proxy._msufExternalAnchorSource
    if not source then
        return _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key) or (proxy.GetCenter and proxy:GetCenter() ~= nil)
    end
    if not _G.MSUF_IsCooldownExternalAnchorKey(key, source) and not MSUF_IsExternalAnchorUsable(source) then
        return _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key) or (proxy.GetCenter and proxy:GetCenter() ~= nil)
    end

    local x, y, w, h = _G.MSUF_GetExternalAnchorVisualBounds(source, key)
    if not x or not y or not w or not h or w <= 1 or h <= 1 then
        return _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key) or (proxy.GetCenter and proxy:GetCenter() ~= nil)
    end
    x = math_floor(x + 0.5)
    y = math_floor(y + 0.5)
    local ok = pcall(function()
        proxy:ClearAllPoints()
        proxy:SetSize(math.max(1, w), math.max(1, h))
        proxy:SetPoint("CENTER", UIParent, "CENTER", x, y)
        if proxy.Show then proxy:Show() end
    end)
    if not ok then
        return _G.MSUF_ApplyExternalAnchorProxyCache(proxy, key) or (proxy.GetCenter and proxy:GetCenter() ~= nil)
    end

    local bucket = _G.MSUF_GetExternalAnchorCacheBucket()
    if bucket then
        bucket[key] = { v = 2, x = x, y = y, w = math.max(1, w), h = math.max(1, h) }
    end
    proxy._msufExternalAnchorFromCache = nil
    proxy._msufProxyInitialized = true
    return true
end

function _G.MSUF_GetExternalAnchorProxy(anchorOrName, sourceOverride)
    local key = _G.MSUF_GetExternalAnchorCacheKey(anchorOrName)
    if not key then return nil end
    _G.MSUF_ExternalAnchorProxies = _G.MSUF_ExternalAnchorProxies or {}
    local proxy = _G.MSUF_ExternalAnchorProxies[key]
    if not proxy then
        proxy = CreateFrame("Frame", nil, UIParent)
        proxy._msufStableAnchorProxy = true
        proxy._msufExternalAnchorCacheKey = key
        proxy:SetSize(1, 1)
        if proxy.SetAlpha then proxy:SetAlpha(0) end
        if proxy.Show then proxy:Show() end
        _G.MSUF_ExternalAnchorProxies[key] = proxy
    end
    local source = sourceOverride or (type(anchorOrName) ~= "string" and anchorOrName or proxy._msufExternalAnchorSource)
    if _G.MSUF_UpdateExternalAnchorProxy(proxy, source) then
        return proxy
    end
    return nil
end

function _G.MSUF_UpdateAllExternalAnchorProxies()
    local proxies = _G.MSUF_ExternalAnchorProxies
    if type(proxies) ~= "table" then return false end
    if _G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked() then return false end
    local changed = false
    for _, proxy in pairs(proxies) do
        changed = (_G.MSUF_UpdateExternalAnchorProxy(proxy, proxy._msufExternalAnchorSource) == true) or changed
    end
    return changed
end

_G.MSUF_LateAnchorReanchorState = _G.MSUF_LateAnchorReanchorState or {
    pending = false,
    attempts = 0,
}
local MSUF_LATE_ANCHOR_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }
local MSUF_LATE_ANCHOR_UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function MSUF_HasLateAnchorConfig()
    local db = MSUF_DB
    if type(db) ~= "table" then return false end
    local g = db.general
    if g and g.anchorToCooldown == true then return true end
    local bars = db.bars
    if bars and bars.classPowerAnchorToCooldown == true then return true end
    for i = 1, #MSUF_LATE_ANCHOR_UNIT_KEYS do
        local conf = db[MSUF_LATE_ANCHOR_UNIT_KEYS[i]]
        if type(conf) == "table" then
            if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" then return true end
            local atv = conf.anchorToUnitframe
            if type(atv) == "string" and atv ~= "" and atv ~= "GLOBAL" and atv ~= "FREE" and atv ~= "global" then
                return true
            end
        end
    end
    return false
end

local function MSUF_LateAnchorReanchorFlush()
    if InCombatLockdown and InCombatLockdown() then
        if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return false
    end
    if type(_G.MSUF_PositionLegacyCooldownViewerAnchor) == "function" then
        pcall(_G.MSUF_PositionLegacyCooldownViewerAnchor)
    end
    _G.MSUF_CDMBridgeDirty = true
    if type(_G.MSUF_FlushCDMBridgeRefresh) == "function" then
        _G.MSUF_FlushCDMBridgeRefresh()
    elseif type(_G.MSUF_OnCDMExtensionChanged) == "function" then
        _G.MSUF_OnCDMExtensionChanged()
    end
    return true
end

_G.MSUF_ScheduleLateAnchorReanchor = function()
    _G.MSUF_CDMBridgeDirty = true
    if InCombatLockdown and InCombatLockdown() then
        if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return false
    end

    local state = _G.MSUF_LateAnchorReanchorState
    if type(state) ~= "table" then
        state = { pending = false, attempts = 0 }
        _G.MSUF_LateAnchorReanchorState = state
    end
    if state.pending then return false end
    state.pending = true
    state.attempts = 0

    if not (C_Timer and C_Timer.After) then
        MSUF_LateAnchorReanchorFlush()
        state.pending = false
        return true
    end

    for i = 1, #MSUF_LATE_ANCHOR_RETRY_DELAYS do
        C_Timer.After(MSUF_LATE_ANCHOR_RETRY_DELAYS[i], function()
            if not state.pending then return end
            state.attempts = i
            MSUF_LateAnchorReanchorFlush()
            if i == #MSUF_LATE_ANCHOR_RETRY_DELAYS then
                state.pending = false
            end
        end)
    end
    return true
end

do
    local function ScheduleLateAnchorFromEvent()
        local function run()
            if MSUF_HasLateAnchorConfig() and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
                _G.MSUF_ScheduleLateAnchorReanchor()
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, run)
        else
            run()
        end
    end

    local lateAnchorEvents = CreateFrame("Frame")
    lateAnchorEvents:RegisterEvent("PLAYER_LOGIN")
    lateAnchorEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    lateAnchorEvents:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    lateAnchorEvents:RegisterEvent("ADDON_LOADED")
    lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" then
            if type(addon) ~= "string" then return end
            if addon ~= "Blizzard_EditMode" and not string.find(addon, "Cooldown", 1, true) then return end
        end
        ScheduleLateAnchorFromEvent()
    end)
end

function _G.MSUF_IsUnitFramePositionLocked()
    local affectingCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
    if InCombatLockdown then
        local locked = (InCombatLockdown() or affectingCombat or _msuf_inCombat) and true or false
        if not locked and _msuf_inCombat then
            _msuf_inCombat = false
            _G.MSUF_InCombat = false
        end
        return locked
    end
    return _msuf_inCombat == true or affectingCombat
end

function _G.MSUF_RunPostCombatReanchorPass()
    if InCombatLockdown and InCombatLockdown() then return false end
    _msuf_inCombat = false
    _G.MSUF_InCombat = false
    if type(_G.MSUF_UpdateAllExternalAnchorProxies) == "function" then
        _G.MSUF_UpdateAllExternalAnchorProxies()
    end
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
    _G.MSUF_ClassPowerLayoutDirty = nil
    _G.MSUF_PowerBarLayoutDirty = nil
    local force = _G.MSUF_ForceReanchorAllUnitFrames_Once
    if type(force) == "function" then
        local prev = _G.MSUF_ExternalAnchorForceReanchor
        _G.MSUF_ExternalAnchorForceReanchor = true
        force(true)
        _G.MSUF_ExternalAnchorForceReanchor = prev
    end
    return true
end

function _G.MSUF_RequestUnitFrameReanchorAfterCombat()
    _G.MSUF_UnitFramePositionDirty = true
    if _G.MSUF_UnitFramePositionRegenFrame then return end
    local fr = CreateFrame("Frame")
    _G.MSUF_UnitFramePositionRegenFrame = fr
    fr:RegisterEvent("PLAYER_REGEN_ENABLED")
    fr:SetScript("OnEvent", function()
        if InCombatLockdown and InCombatLockdown() then return end
        _msuf_inCombat = false
        _G.MSUF_InCombat = false
        if _G.MSUF_UnitFramePositionDirty then
            _G.MSUF_UnitFramePositionDirty = false
            if type(_G.MSUF_RunPostCombatReanchorPass) == "function" then
                _G.MSUF_RunPostCombatReanchorPass()
            end
            if C_Timer and C_Timer.After then
                local delays = { 0.05, 0.25, 0.75, 1.5 }
                for i = 1, #delays do
                    C_Timer.After(delays[i], function()
                        if type(_G.MSUF_RunPostCombatReanchorPass) == "function" then
                            _G.MSUF_RunPostCombatReanchorPass()
                        end
                    end)
                end
            end
        end
    end)
end

-- Legacy fallback for raw external anchors. The normal path uses stable UIParent
-- proxy anchors so unitframes do not follow combat-time CDM/bridge resizing.
local function MSUF_SnapshotFrameToUIParentCenter(frame, point)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not frame or not UIParent or not UIParent.GetCenter then return false end

    local fx, fy, usedPoint = MSUF_GetFramePoint(frame, point or "CENTER")
    local ux, uy = UIParent:GetCenter()
    if not fx or not fy or not ux or not uy then return false end
    usedPoint = usedPoint or "CENTER"

    local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local us = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if fs == 0 then fs = 1 end
    if us == 0 then us = 1 end

    local x = math_floor(((fx * fs - ux * us) / us) + 0.5)
    local y = math_floor(((fy * fs - uy * us) / us) + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint(usedPoint, UIParent, "CENTER", x, y)
    frame._msufHardLockPoint = usedPoint
    return true
end
_G.MSUF_SnapshotFrameToUIParentCenter = MSUF_SnapshotFrameToUIParentCenter

function _G.MSUF_ExternalPointSignature(point, relPoint, x, y)
    return tostring(point or "") .. "|" .. tostring(relPoint or "") .. "|"
        .. tostring(math_floor((tonumber(x) or 0) + 0.5)) .. "|"
        .. tostring(math_floor((tonumber(y) or 0) + 0.5))
end

function _G.MSUF_ShouldKeepStableExternalPoint(frame, anchor, sig)
    if not frame or not anchor or not sig then return false end
    if _G.MSUF_ExternalAnchorForceReanchor == true then return false end
    if MSUF_IsLayoutEditingActive() then return false end
    return frame._msufStableExternalAnchor == anchor
        and frame._msufStableExternalSig == sig
        and frame._msufHardLockedToUIParent == true
end

local function MSUF_ApplyStableUnitFramePoint(frame, point, anchor, relPoint, x, y)
    local isExternal = MSUF_ShouldSnapshotExternalAnchor(anchor)
    local sig = isExternal and _G.MSUF_ExternalPointSignature(point, relPoint, x, y) or nil
    if isExternal then
        local hook = _G.MSUF_HookExternalAnchorForReanchor
        if type(hook) == "function" then hook(anchor) end
        if not MSUF_IsExternalAnchorUsable(anchor) then
            anchor._msufHookNeedsFirstUsableReanchor = true
            _G.MSUF_ScheduleLateAnchorReanchor()
            if frame and frame._msufStableExternalAnchor == anchor and not MSUF_IsLayoutEditingActive() then
                return true
            end
            return false
        end
    end

    local ok = pcall(MSUF_ApplyPoint, frame, point, anchor, relPoint, x, y)
    if not ok then
        if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return false
    end
    if isExternal and not MSUF_IsLayoutEditingActive() and MSUF_SnapshotFrameToUIParentCenter(frame) then
        local state = _G.MSUF_LateAnchorReanchorState
        if state then state.attempts = 0 end
        frame._msufPositionInitialized = true
        frame._msufHardLockedToUIParent = true
        frame._msufStableExternalAnchor = anchor
        frame._msufStableExternalSig = sig
        frame._msufDirectCooldownAnchor = nil
        frame._msufHardLockPoint = "CENTER"
    elseif frame then
        frame._msufPositionInitialized = true
        frame._msufHardLockedToUIParent = nil
        frame._msufStableExternalAnchor = nil
        frame._msufStableExternalSig = nil
        frame._msufDirectCooldownAnchor = nil
        frame._msufHardLockPoint = nil
    end
    return true
end

local function PositionUnitFrame(f, unit, refreshConfig)
    if not f or not unit then return end
    if f._msufDragActive then return end
    local inLockdown = (_G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked()) or false
    local initialized = f._msufPositionInitialized == true
    if inLockdown and initialized then
        if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return
    end
    local key = f.msufConfigKey
    if not key then
        key = GetConfigKeyForUnit(unit)
        f.msufConfigKey = key
    end
    if not key then return end
    if inLockdown and initialized then return end
    local conf = refreshConfig and nil or f.cachedConfig
    if not conf then
        if not MSUF_DB then MSUF_EnsureDB() end
        conf = MSUF_DB and MSUF_DB[key]
        f.cachedConfig = conf
    end
    if not conf then return end
    local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer")) or _G["EssentialCooldownViewer"]
    local _g = MSUF_DB and MSUF_DB.general
    local anchor, missingAnchorName = MSUF_ResolveConfiguredAnchorFrame(key, conf, MSUF_GetAnchorFrame())
    local isCooldownAnchor = false
    local usesExternalAnchor = false
    local unresolvedConfiguredAnchor = missingAnchorName ~= nil
    if _g and _g.anchorToCooldown then
        usesExternalAnchor = true
    elseif type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" then
        usesExternalAnchor = true
    elseif MSUF_ShouldSnapshotExternalAnchor(anchor) then
        usesExternalAnchor = true
    end
    if (_g and _g.anchorToCooldown and not ecv) or unresolvedConfiguredAnchor then
        unresolvedConfiguredAnchor = true
        if type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
            _G.MSUF_ScheduleLateAnchorReanchor()
        end
        if inLockdown then
            if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end
        local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
        if type(applyCached) == "function" and applyCached(f, key, unit) then
            return
        end
        if initialized then
            return
        end
    end
    if inLockdown and not initialized and usesExternalAnchor then
        local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
        if type(applyCached) == "function" and applyCached(f, key, unit) then
            if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end
    end
    if _g and _g.anchorToCooldown then
        if ecv and anchor == ecv then
            isCooldownAnchor = true
        elseif not ecv then
            if inLockdown then
                if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                    _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                end
                return
            end
        end
    end

    if (not isCooldownAnchor) and MSUF_ShouldSnapshotExternalAnchor(anchor) then
        local hook = _G.MSUF_HookExternalAnchorForReanchor
        if type(hook) == "function" then hook(anchor) end
        if type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
            _G.MSUF_ScheduleLateAnchorReanchor()
        end
        local proxy
        if _G.MSUF_GetExternalAnchorProxy then
            if anchor == ecv then
                proxy = _G.MSUF_GetExternalAnchorProxy("EssentialCooldownViewer", anchor)
            else
                proxy = _G.MSUF_GetExternalAnchorProxy(anchor)
            end
        end
        if proxy then
            if anchor == ecv then isCooldownAnchor = true end
            anchor = proxy
        elseif not MSUF_IsExternalAnchorUsable(anchor) then
            anchor._msufHookNeedsFirstUsableReanchor = true
            if inLockdown then
                if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                    _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                end
                return
            end
            if f._msufStableExternalAnchor == anchor and not MSUF_IsLayoutEditingActive() then
                return
            end
            anchor = UIParent
        end
    end
    if _g and _g.anchorToCooldown and isCooldownAnchor then
        local rule = MSUF_ECV_ANCHORS[key]
        if rule then
            local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3], rule[4]
            local gapY = (conf.offsetY ~= nil) and conf.offsetY or -20
            local x = baseX + (conf.offsetX or 0)
            local y = gapY + (extraY or 0)
            if inLockdown then
                if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                    _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                end
                return
            end
            MSUF_ApplyPoint(f, point, anchor, relPoint, x, y)
            f._msufPositionInitialized = true
            f._msufHardLockedToUIParent = nil
            f._msufStableExternalAnchor = nil
            f._msufStableExternalSig = nil
            f._msufDirectCooldownAnchor = true
            f._msufHardLockPoint = point
            if not unresolvedConfiguredAnchor and _G.MSUF_CacheUnitFrameScreenPosition then
                _G.MSUF_CacheUnitFrameScreenPosition(f, key, unit, point)
            end
            return
        end
    end
    if key == "boss" then
        local index = (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit)) or 1
        local step = index - 1
        local spacing = conf.spacing or -36
        local mode = conf.bossLayoutMode
        local baseX = conf.offsetX or 0
        local baseY = conf.offsetY or 0
        local x, y = baseX, baseY
        if mode == "HORIZONTAL_RIGHT" then
            -- boss1 at anchor, subsequent to the right. spacing is negative by default â†’ invert for rightward travel.
            x = baseX + step * -spacing
        elseif mode == "HORIZONTAL_LEFT" then
            x = baseX + step * spacing
        elseif mode == "VERTICAL_UP" then
            y = baseY + step * -spacing
        else
            -- VERTICAL_DOWN (default) and any legacy/unknown value (including pre-migration invertBossOrder==false)
            y = baseY + step * spacing
        end
        if _g and _g.anchorToCooldown and isCooldownAnchor and inLockdown then
            if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end
        if _g and _g.anchorToCooldown and isCooldownAnchor then
            MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", x, y)
            f._msufPositionInitialized = true
            f._msufHardLockedToUIParent = nil
            f._msufStableExternalAnchor = nil
            f._msufStableExternalSig = nil
            f._msufDirectCooldownAnchor = true
            f._msufHardLockPoint = "CENTER"
            if not unresolvedConfiguredAnchor and _G.MSUF_CacheUnitFrameScreenPosition then
                _G.MSUF_CacheUnitFrameScreenPosition(f, key, unit, "CENTER")
            end
            return
        end
        if MSUF_ShouldSnapshotExternalAnchor(anchor)
            and _G.MSUF_ShouldKeepStableExternalPoint(f, anchor, _G.MSUF_ExternalPointSignature("CENTER", "CENTER", x, y))
        then
            return
        end
        if MSUF_ApplyStableUnitFramePoint(f, "CENTER", anchor, "CENTER", x, y)
            and not unresolvedConfiguredAnchor
            and _G.MSUF_CacheUnitFrameScreenPosition
        then
            _G.MSUF_CacheUnitFrameScreenPosition(f, key, unit)
        end
    else
        if _g and _g.anchorToCooldown and isCooldownAnchor and inLockdown then
            if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end
        if _g and _g.anchorToCooldown and isCooldownAnchor then
            MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", conf.offsetX or 0, conf.offsetY or 0)
            f._msufPositionInitialized = true
            f._msufHardLockedToUIParent = nil
            f._msufStableExternalAnchor = nil
            f._msufStableExternalSig = nil
            f._msufDirectCooldownAnchor = true
            f._msufHardLockPoint = "CENTER"
            if not unresolvedConfiguredAnchor and _G.MSUF_CacheUnitFrameScreenPosition then
                _G.MSUF_CacheUnitFrameScreenPosition(f, key, unit, "CENTER")
            end
            return
        end
        if MSUF_ShouldSnapshotExternalAnchor(anchor)
            and _G.MSUF_ShouldKeepStableExternalPoint(f, anchor, _G.MSUF_ExternalPointSignature("CENTER", "CENTER", conf.offsetX, conf.offsetY))
        then
            return
        end
        if MSUF_ApplyStableUnitFramePoint(f, "CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
            and not unresolvedConfiguredAnchor
            and _G.MSUF_CacheUnitFrameScreenPosition
        then
            _G.MSUF_CacheUnitFrameScreenPosition(f, key, unit)
        end
    end
 end
MSUF_ForceReanchorAllUnitFrames_Once = function(refreshConfig)
    if _G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked() then
        if _G.MSUF_RequestUnitFrameReanchorAfterCombat then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return
    end
    local uf = UnitFrames or _G.MSUF_UnitFrames or _G.UnitFrames
    if not uf then return end
    if _G.MSUF_UpdateAllExternalAnchorProxies then
        _G.MSUF_UpdateAllExternalAnchorProxies()
    end

    local ordered = {
        "player",
        "target",
        "targettarget",
        "focus",
        "focustarget",
        "pet",
        "boss1", "boss2", "boss3", "boss4", "boss5", "boss6", "boss7", "boss8",
    }

    for i = 1, #ordered do
        local unit = ordered[i]
        local frame = uf[unit]
        if frame then
            PositionUnitFrame(frame, unit, refreshConfig ~= false)
        end
    end
end
_G.MSUF_ForceReanchorAllUnitFrames_Once = MSUF_ForceReanchorAllUnitFrames_Once

local function MSUF_FrameShouldHardLockPosition(frame)
    if not frame then return false end
    if frame._msufStableExternalAnchor or frame._msufDirectCooldownAnchor then return true end

    local key = frame.msufConfigKey
    if not key and frame.unit then
        key = GetConfigKeyForUnit(frame.unit)
        frame.msufConfigKey = key
    end
    local conf = key and MSUF_DB and MSUF_DB[key]
    if not conf then return false end

    local g = MSUF_DB and MSUF_DB.general
    if g and g.anchorToCooldown == true then return true end
    if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" then return true end

    local anchor = MSUF_ResolveConfiguredAnchorFrame(key, conf, MSUF_GetAnchorFrame and MSUF_GetAnchorFrame() or UIParent)
    return MSUF_ShouldSnapshotExternalAnchor(anchor)
end

local function MSUF_HardLockFramePosition(frame, cacheKey, cacheUnit)
    if not frame or frame._msufDragActive then return false end
    if not MSUF_FrameShouldHardLockPosition(frame) then return false end
    if not frame.GetCenter or not frame.ClearAllPoints or not frame.SetPoint then return false end
    local point = (frame._msufDirectCooldownAnchor and MSUF_GetDirectCooldownLockPoint(cacheKey, frame)) or frame._msufHardLockPoint or "CENTER"
    local locked = MSUF_SnapshotFrameToUIParentCenter(frame, point)
    if locked and cacheKey and _G.MSUF_CacheUnitFrameScreenPosition then
        _G.MSUF_CacheUnitFrameScreenPosition(frame, cacheKey, cacheUnit or cacheKey, frame._msufHardLockPoint or point)
    end
    if locked then
        frame._msufPositionInitialized = true
        frame._msufHardLockedToUIParent = true
    end
    return locked == true
end

local function MSUF_CacheExternalAnchorFrameScreenPosition(frame, cacheKey, cacheUnit)
    if not frame or frame._msufDragActive then return false end
    if not MSUF_FrameShouldHardLockPosition(frame) then return false end
    local point = (frame._msufDirectCooldownAnchor and MSUF_GetDirectCooldownLockPoint(cacheKey, frame))
        or frame._msufHardLockPoint
        or "CENTER"
    return _G.MSUF_CacheUnitFrameScreenPosition(frame, cacheKey, cacheUnit or cacheKey, point, true)
end

function _G.MSUF_CacheExternalAnchorFrameScreenPositions()
    local cached = false
    for i = 1, #UnitFramesList do
        local frame = UnitFramesList[i]
        local unit = frame and frame.unit
        local key = frame and (frame.msufConfigKey or (unit and GetConfigKeyForUnit(unit)))
        cached = MSUF_CacheExternalAnchorFrameScreenPosition(frame, key, unit) or cached
    end

    local named = {
        { "MSUF_ClassPowerContainer", "classpower" },
        { "MSUF_PlayerCastbar", "playercastbar" },
        { "MSUF_TargetCastbar", "targetcastbar" },
        { "MSUF_FocusCastbar", "focuscastbar" },
    }
    for i = 1, #named do
        local def = named[i]
        cached = MSUF_CacheExternalAnchorFrameScreenPosition(_G[def[1]], def[2], def[2]) or cached
    end

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for i = 1, #bossCastbars do
            cached = MSUF_CacheExternalAnchorFrameScreenPosition(bossCastbars[i], "bosscastbar" .. i, "bosscastbar" .. i) or cached
        end
    end
    return cached
end

local function MSUF_HardLockAllFramePositions(reason)
    if _msuf_inCombat or (InCombatLockdown and InCombatLockdown()) then return false end
    if reason ~= "PLAYER_REGEN_DISABLED" and MSUF_IsLayoutEditingActive() then return false end

    local locked = false
    for i = 1, #UnitFramesList do
        local frame = UnitFramesList[i]
        local unit = frame and frame.unit
        local key = frame and (frame.msufConfigKey or (unit and GetConfigKeyForUnit(unit)))
        locked = MSUF_HardLockFramePosition(frame, key, unit) or locked
    end

    local named = {
        { "MSUF_ClassPowerContainer", "classpower" },
        { "MSUF_PlayerCastbar", "playercastbar" },
        { "MSUF_TargetCastbar", "targetcastbar" },
        { "MSUF_FocusCastbar", "focuscastbar" },
    }
    for i = 1, #named do
        local def = named[i]
        locked = MSUF_HardLockFramePosition(_G[def[1]], def[2], def[2]) or locked
    end

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for i = 1, #bossCastbars do
            locked = MSUF_HardLockFramePosition(bossCastbars[i], "bosscastbar" .. i, "bosscastbar" .. i) or locked
        end
    end

    if locked then
        _G.MSUF_UnitFramePositionDirty = true
    end
    return locked
end
_G.MSUF_HardLockAllFramePositions = MSUF_HardLockAllFramePositions

_G.MSUF_CDMBridgeDirty = false
_G.MSUF_CDMBridgeFlushScheduled = false

function _G.MSUF_MarkExternalAnchorForReanchor()
    _G.MSUF_CDMBridgeDirty = true
end

function _G.MSUF_OnCDMExtensionChanged()
    _G.MSUF_CDMBridgeDirty = true
    if _G.MSUF_CDMBridgeFlushScheduled then return end
    _G.MSUF_CDMBridgeFlushScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, _G.MSUF_FlushCDMBridgeRefresh)
    else
        _G.MSUF_FlushCDMBridgeRefresh()
    end
end

function _G.MSUF_HookExternalAnchorForReanchor(frame)
    return false
end

function _G.MSUF_FlushCDMBridgeRefresh()
    _G.MSUF_CDMBridgeFlushScheduled = false
    if not _G.MSUF_CDMBridgeDirty then return end
    if InCombatLockdown and InCombatLockdown() then return end
    _G.MSUF_CDMBridgeDirty = false
    if type(_G.MSUF_PositionLegacyCooldownViewerAnchor) == "function" then
        pcall(_G.MSUF_PositionLegacyCooldownViewerAnchor)
    end
    if _G.MSUF_UpdateAllExternalAnchorProxies then
        _G.MSUF_UpdateAllExternalAnchorProxies()
    end
    if _G.MSUF_ClassPower_Refresh then
        _G.MSUF_ClassPower_Refresh()
    end
    if _G.MSUF_ApplyPowerBarEmbedLayout_All then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
    _G.MSUF_ClassPowerLayoutDirty = nil
    _G.MSUF_PowerBarLayoutDirty = nil
    local prev = _G.MSUF_ExternalAnchorForceReanchor
    _G.MSUF_ExternalAnchorForceReanchor = true
    MSUF_ForceReanchorAllUnitFrames_Once()
    _G.MSUF_ExternalAnchorForceReanchor = prev
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

local function MSUF_ResolveNameAnchor(anchor, x)
    x = tonumber(x) or 0
    if anchor == "RIGHT" then
        return "TOPRIGHT", "TOPRIGHT", -x, "RIGHT"
    elseif anchor == "CENTER" then
        return "TOP", "TOP", x, "CENTER"
    end
    return "TOPLEFT", "TOPLEFT", x, "LEFT"
end
local function MSUF_ClampTextLayer(v, fallback)
    v = math_floor((tonumber(v) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end
local function MSUF_TextLayerValue(udb, g, key, fallback)
    local v = udb and udb[key]
    if v == nil and g then v = g[key] end
    return MSUF_ClampTextLayer(v, fallback)
end
local function MSUF_EnsureTextLayerFrame(f, frameKey, parent, layer)
    if not f or not parent then return nil end
    local layerFrame = f[frameKey]
    if not layerFrame then
        layerFrame = CreateFrame("Frame", nil, parent)
        f[frameKey] = layerFrame
    elseif layerFrame.GetParent and layerFrame:GetParent() ~= parent then
        layerFrame:SetParent(parent)
    end
    if layerFrame.ClearAllPoints then layerFrame:ClearAllPoints() end
    if layerFrame.SetAllPoints then layerFrame:SetAllPoints(parent) end
    if layerFrame.SetFrameLevel then
        local base = (f.GetFrameLevel and f:GetFrameLevel()) or (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
        local want = base + 10 + MSUF_ClampTextLayer(layer, 0)
        if layerFrame._msufTextLayerLevel ~= want then
            layerFrame._msufTextLayerLevel = want
            layerFrame:SetFrameLevel(want)
        end
    end
    if layerFrame.Show then layerFrame:Show() end
    return layerFrame
end
local function MSUF_SetTextParentIfNeeded(fs, parent)
    if fs and parent and fs.SetParent and (not fs.GetParent or fs:GetParent() ~= parent) then
        fs:SetParent(parent)
    end
end
local function MSUF_EnsureUnitTextLayers(f, tf, nameLayer, hpLayer, powerLayer)
    if not f or not tf then return end
    local nl = MSUF_EnsureTextLayerFrame(f, "_msufNameTextLayer", tf, nameLayer)
    local hl = MSUF_EnsureTextLayerFrame(f, "_msufHPTextLayer", tf, hpLayer)
    local pl = MSUF_EnsureTextLayerFrame(f, "_msufPowerTextLayer", tf, powerLayer)
    if f._msufNameClipFrame and f._msufNameClipFrame.SetFrameLevel and nl and nl.GetFrameLevel then
        f._msufNameClipFrame:SetFrameLevel(nl:GetFrameLevel() or 0)
    end
    if f.nameText and nl and (not f._msufNameClipFrame or f.nameText:GetParent() ~= f._msufNameClipFrame) then
        MSUF_SetTextParentIfNeeded(f.nameText, nl)
    end
    MSUF_SetTextParentIfNeeded(f.raidGroupNameText, nl)
    MSUF_SetTextParentIfNeeded(f.hpTextLeft, hl)
    MSUF_SetTextParentIfNeeded(f.hpTextCenter, hl)
    MSUF_SetTextParentIfNeeded(f.hpText, hl)
    MSUF_SetTextParentIfNeeded(f.hpTextPct, hl)
    if not (f._msufPowerBarDetached and f.targetPowerBar) then
        MSUF_SetTextParentIfNeeded(f.powerTextLeft, pl)
        MSUF_SetTextParentIfNeeded(f.powerTextCenter, pl)
        MSUF_SetTextParentIfNeeded(f.powerText, pl)
        MSUF_SetTextParentIfNeeded(f.powerTextPct, pl)
    end
end
local function MSUF_TextLayout_ApplyGroup(f, tf, conf, spec, mode, hasPct, on, eff, anchorPt, anchorRelPt, anchorDefX, anchorJustify, anchorSign)
    local fullObj, pctObj = f[spec.full], f[spec.pct]
    if not (fullObj or hasPct) then return end
    local pt    = anchorPt or spec.point
    local relPt = anchorRelPt or spec.relPoint
    local dX    = anchorDefX or spec.defX
    local sign  = anchorSign or -1
    local baseX = ns.Util.Offset(conf[spec.xKey], dX)
    local baseY = ns.Util.Offset(conf[spec.yKey], spec.defY)
    local fullX, pctX = baseX, baseX
    local canSplit = hasPct and on and eff ~= 0 and (not spec.limitMode
        or mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL"
        or mode == "CURPERCENT" or mode == "CURMAXPERCENT")
    if canSplit then
        if mode == "FULL_PLUS_PERCENT" or mode == "CURPERCENT" or mode == "CURMAXPERCENT" or mode == "MAXPERCENT" then
            fullX = baseX + sign * eff
        else
            pctX = baseX + sign * eff
        end
    end
    if fullObj then
        MSUF_ApplyPoint(fullObj, pt, tf, relPt, fullX, baseY)
        if anchorJustify and fullObj.SetJustifyH then fullObj:SetJustifyH(anchorJustify) end
    end
    if hasPct then
        MSUF_ApplyPoint(pctObj, pt, tf, relPt, pctX, baseY)
        if anchorJustify and pctObj and pctObj.SetJustifyH then pctObj:SetJustifyH(anchorJustify) end
    end
 end
local function MSUF_NormalizeHpLayoutMode(mode)
    if type(_G.MSUF_NormalizeHpTextMode) == "function" then
        return _G.MSUF_NormalizeHpTextMode(mode)
    end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end
local function MSUF_NormalizePowerLayoutMode(mode)
    if type(_G.MSUF_NormalizePowerTextMode) == "function" then
        return _G.MSUF_NormalizePowerTextMode(mode)
    end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end
local function MSUF_ReverseHpLayoutMode(mode)
    local rev = {
        FULL_PLUS_PERCENT = "PERCENTCUR", PERCENT_PLUS_FULL = "CURPERCENT",
        CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT",
        CURMAX = "MAXCUR", MAXCUR = "CURMAX",
        CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT",
        MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT",
        PERCENTCURMAX = "CURMAXPERCENT",
    }
    return rev[mode] or mode
end
local function MSUF_TextLayout_HasSlots(udb, g, leftKey, centerKey, rightKey)
    return (udb and (udb[leftKey] ~= nil or udb[centerKey] ~= nil or udb[rightKey] ~= nil))
        or (g and (g[leftKey] ~= nil or g[centerKey] ~= nil or g[rightKey] ~= nil))
end
local function MSUF_TextLayout_ReadRaw(udb, g, key, fallback)
    local value = udb and udb[key]
    if value == nil and g then value = g[key] end
    if value == nil or value == "" then value = fallback end
    return value
end
local function MSUF_TextLayout_ReadSlot(udb, g, key, fallback, normalizer)
    local value = MSUF_TextLayout_ReadRaw(udb, g, key, fallback or "NONE")
    if normalizer then value = normalizer(value) end
    return value or fallback or "NONE"
end
local function MSUF_TextLayout_ResolveSlots(udb, g, leftKey, centerKey, rightKey, legacyKey, fallbackRight, normalizer, reverse)
    local left, center, right
    if MSUF_TextLayout_HasSlots(udb, g, leftKey, centerKey, rightKey) then
        left = MSUF_TextLayout_ReadSlot(udb, g, leftKey, "NONE", normalizer)
        center = MSUF_TextLayout_ReadSlot(udb, g, centerKey, "NONE", normalizer)
        right = MSUF_TextLayout_ReadSlot(udb, g, rightKey, fallbackRight or "NONE", normalizer)
    else
        local legacy = (udb and udb[legacyKey]) or (g and g[legacyKey]) or fallbackRight or "NONE"
        left, center, right = "NONE", "NONE", normalizer and normalizer(legacy) or legacy
    end
    if reverse then
        left = MSUF_ReverseHpLayoutMode(left)
        center = MSUF_ReverseHpLayoutMode(center)
        right = MSUF_ReverseHpLayoutMode(right)
    end
    return left, center, right
end
local function MSUF_TextLayout_Place(fs, parent, point, relPoint, x, y, justify)
    if not (fs and parent) then return end
    fs:ClearAllPoints()
    fs:SetPoint(point, parent, relPoint, x or 0, y or 0)
    if fs.SetJustifyH then fs:SetJustifyH(justify or "CENTER") end
end
local function MSUF_TextLayout_ReparentPower(f, parent)
    if not (f and parent) then return end
    MSUF_SetTextParentIfNeeded(f.powerTextLeft, parent)
    MSUF_SetTextParentIfNeeded(f.powerTextCenter, parent)
    MSUF_SetTextParentIfNeeded(f.powerText, parent)
    MSUF_SetTextParentIfNeeded(f.powerTextPct, parent)
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
    local nameLayer = MSUF_TextLayerValue(udb, g, "nameTextLayer", 5)
    local hpLayer = MSUF_TextLayerValue(udb, g, "hpTextLayer", 5)
    local powerLayer = MSUF_TextLayerValue(udb, g, "powerTextLayer", 2)
    MSUF_EnsureUnitTextLayers(f, tf, nameLayer, hpLayer, powerLayer)
    local nameAnchor  = (udb and udb.nameTextAnchor)  or "LEFT"
    local hpReverse = (udb and udb.hpTextReverse)
    if hpReverse == nil and g then hpReverse = g.hpTextReverse end
    local hpLeftMode, hpCenterMode, hpRightMode = MSUF_TextLayout_ResolveSlots(
        udb, g, "textLeft", "textCenter", "textRight", "hpTextMode", "CURPERCENT",
        MSUF_NormalizeHpLayoutMode, hpReverse)
    local pLeftMode, pCenterMode, pRightMode = MSUF_TextLayout_ResolveSlots(
        udb, g, "powerTextLeft", "powerTextCenter", "powerTextRight", "powerTextMode", "CURPERCENT",
        MSUF_NormalizePowerLayoutMode, false)
    local hX = ns.Util.Offset(conf.hpOffsetX,    -4)
    local hY = ns.Util.Offset(conf.hpOffsetY,    -4)
    local pX = ns.Util.Offset(conf.powerOffsetX, -4)
    local pY = ns.Util.Offset(conf.powerOffsetY,  4)
    local hLeftX = ns.Util.Offset(conf.hpTextLeftOffsetX, 0)
    local hLeftY = ns.Util.Offset(conf.hpTextLeftOffsetY, 0)
    local hCenterX = ns.Util.Offset(conf.hpTextCenterOffsetX, 0)
    local hCenterY = ns.Util.Offset(conf.hpTextCenterOffsetY, 0)
    local hRightX = ns.Util.Offset(conf.hpTextRightOffsetX, 0)
    local hRightY = ns.Util.Offset(conf.hpTextRightOffsetY, 0)
    local pLeftX = ns.Util.Offset(conf.powerTextLeftOffsetX, 0)
    local pLeftY = ns.Util.Offset(conf.powerTextLeftOffsetY, 0)
    local pCenterX = ns.Util.Offset(conf.powerTextCenterOffsetX, 0)
    local pCenterY = ns.Util.Offset(conf.powerTextCenterOffsetY, 0)
    local pRightX = ns.Util.Offset(conf.powerTextRightOffsetX, 0)
    local pRightY = ns.Util.Offset(conf.powerTextRightOffsetY, 0)
    local wUsed = (f and f.GetWidth and f:GetWidth()) or 0
    if (not wUsed or wUsed == 0) and tf and tf.GetWidth then wUsed = tf:GetWidth() or 0 end
    if (not wUsed or wUsed == 0) and conf then wUsed = tonumber(conf.width) or wUsed end
    wUsed = tonumber(wUsed) or 0
    -- Include detached power bar width in stamp ONLY when text-on-bar is active.
    -- Avoids a C API GetWidth() call for every non-detached frame.
    local pbW = 0
    local _textOnBarActive = f._msufPowerBarDetached and f.targetPowerBar
        and udb and udb.detachedPowerBarTextOnBar == true
    if _textOnBarActive then
        pbW = math_floor((f.targetPowerBar.GetWidth and f.targetPowerBar:GetWidth() or 0) + 0.5)
    end
    if not ns.Cache.StampChanged(f, "TextLayout", tf, nX, nY, hX, hY, pX, pY,
        hLeftX, hLeftY, hCenterX, hCenterY, hRightX, hRightY,
        pLeftX, pLeftY, pCenterX, pCenterY, pRightX, pRightY,
        wUsed, (key or ""),
        (hpLeftMode or ""), (hpCenterMode or ""), (hpRightMode or ""),
        (pLeftMode or ""), (pCenterMode or ""), (pRightMode or ""),
        (nameAnchor or ""), nameLayer, hpLayer, powerLayer,
        (f._msufPowerBarDetached and 1 or 0), (_textOnBarActive and 1 or 0), pbW)
    then return end
    f._msufTextLayoutStamp = 1
    if f.nameText then
        local namePt, nameRelPt, nameDefX, nameJustify = MSUF_ResolveNameAnchor(nameAnchor, nX)
        MSUF_ApplyPoint(f.nameText, namePt, tf, nameRelPt, nameDefX, nY)
        if f.nameText.SetJustifyH then f.nameText:SetJustifyH(nameJustify) end
        f._msufNameAnchorPoint, f._msufNameAnchorRel, f._msufNameAnchorRelPoint, f._msufNameAnchorX, f._msufNameAnchorY = namePt, tf, nameRelPt, nameDefX, nY
        f._msufNameAnchorMode, f._msufNameJustifyH = nameAnchor, nameJustify
        f._msufNameClipSideApplied, f._msufNameClipReservedRight, f._msufNameClipTextStamp, f._msufNameClipAnchorStamp, f._msufClampStamp = nil, nil, nil, nil, nil
    end
    if f.raidGroupNameText and f.nameText then MSUF_ApplyRaidGroupNameLayout_Internal(f, conf) end
    if f._msufIsTarget and _G.MSUF_UFCore_ReanchorTargetToTInline then
        _G.MSUF_UFCore_ReanchorTargetToTInline(f)
    end
    if f.levelText and f.nameText then MSUF_ApplyLevelIndicatorLayout_Internal(f, conf) end
    MSUF_TextLayout_Place(f.hpTextLeft, tf, "TOPLEFT", "TOPLEFT", 4 + hX + hLeftX, hY + hLeftY, "LEFT")
    MSUF_TextLayout_Place(f.hpTextCenter, tf, "TOP", "TOP", hX + hCenterX, hY + hCenterY, "CENTER")
    MSUF_TextLayout_Place(f.hpText, tf, "TOPRIGHT", "TOPRIGHT", -4 + hX + hRightX, hY + hRightY, "RIGHT")
    MSUF_TextLayout_Place(f.hpTextPct, tf, "TOPRIGHT", "TOPRIGHT", -4 + hX + hRightX, hY + hRightY, "RIGHT")
    -- Power text: anchor to detached power bar when option enabled.
    -- FontStrings render at their parent's frame level, so we must reparent
    -- them to an overlay frame on the power bar to keep text on top.
    if _textOnBarActive then
        local pb = f.targetPowerBar
        -- Create/reuse text overlay frame on the power bar (high frame level)
        if not f._msufDPBTextOverlay then
            local ov = CreateFrame("Frame", nil, pb)
            ov:SetAllPoints(pb)
            f._msufDPBTextOverlay = ov
        end
        local ov = f._msufDPBTextOverlay
        ov:SetParent(pb)
        ov:SetAllPoints(pb)
        ov:SetFrameLevel((pb.GetFrameLevel and pb:GetFrameLevel() or 0) + 5)
        ov:Show()
        MSUF_TextLayout_ReparentPower(f, ov)
        MSUF_TextLayout_Place(f.powerTextLeft, pb, "LEFT", "LEFT", 2 + pX + pLeftX, pY + pLeftY, "LEFT")
        MSUF_TextLayout_Place(f.powerTextCenter, pb, "CENTER", "CENTER", pX + pCenterX, pY + pCenterY, "CENTER")
        MSUF_TextLayout_Place(f.powerText, pb, "RIGHT", "RIGHT", -2 + pX + pRightX, pY + pRightY, "RIGHT")
        MSUF_TextLayout_Place(f.powerTextPct, pb, "RIGHT", "RIGHT", -2 + pX + pRightX, pY + pRightY, "RIGHT")
    else
        -- Restore power text back to textFrame if previously reparented
        if f._msufDPBTextOverlay then
            f._msufDPBTextOverlay:Hide()
        end
        local pwrParent = f._msufPowerTextLayer or tf
        MSUF_TextLayout_ReparentPower(f, pwrParent)
        MSUF_TextLayout_Place(f.powerTextLeft, tf, "BOTTOMLEFT", "BOTTOMLEFT", 4 + pX + pLeftX, pY + pLeftY, "LEFT")
        MSUF_TextLayout_Place(f.powerTextCenter, tf, "BOTTOM", "BOTTOM", pX + pCenterX, pY + pCenterY, "CENTER")
        MSUF_TextLayout_Place(f.powerText, tf, "BOTTOMRIGHT", "BOTTOMRIGHT", -4 + pX + pRightX, pY + pRightY, "RIGHT")
        MSUF_TextLayout_Place(f.powerTextPct, tf, "BOTTOMRIGHT", "BOTTOMRIGHT", -4 + pX + pRightX, pY + pRightY, "RIGHT")
    end
 end
function _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
    if not MSUF_DB then MSUF_EnsureDB() end
    local k = _G.MSUF_NormalizeTextLayoutUnitKey(unitKey)
    local function ApplyForFrame(f)
        if not f then return end
        f._msufTextLayoutStamp = nil
        f._msufTextSpec = nil
        f._msufLastH = nil
        f._msufLastPctS = nil
        f._msufLastMaxS = nil
        f._msufLastPwrC = nil
        f._msufLastPwrM = nil
        f._msufLastPwrP = nil
        f._msufRawPwrC = nil
        f._msufRawPwrM = nil
        f._msufRawPwrP = nil
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
        if not conf then return end
        if type(ApplyTextLayout) == "function" then
            ApplyTextLayout(f, conf)
    end
            MSUF_ClampNameWidth(f, conf)
        -- IMPORTANT: text option changes do not necessarily trigger a UNIT_HEALTH event.
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
            if (not _msuf_inCombat) and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
                if f.isBoss and MSUF_BossTestMode then
                    _G.MSUF_ApplyBossTestHpPreviewText(f, conf)
                else
                    f._msufLastHpValue = nil
                    ns.UF.RequestUpdate(f, true, false, "TextLayout")
                end
            elseif f.isBoss and MSUF_BossTestMode and not _msuf_inCombat then
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
    if not f or not f.nameText then return end
    f.nameText:SetWordWrap(false)
    if f.nameText.SetNonSpaceWrap then
        f.nameText:SetNonSpaceWrap(false)
    end
    local shorten = (MSUF_DB and MSUF_DB.shortenNames) and true or false
    local unitKey = f and (f.msufConfigKey or f._msufConfigKey or f.unitKey or f.unit)
    -- Per-unit font override: allow per-unit shorten toggle
    local _fontConf = unitKey and MSUF_DB and MSUF_DB[unitKey]
    if _fontConf and _fontConf.fontOverride and _fontConf.shortenNames ~= nil then
        shorten = _fontConf.shortenNames and true or false
    end
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
        local parentIsClip = f._msufNameClipFrame and f.nameText.GetParent and f.nameText:GetParent() == f._msufNameClipFrame
        local stamp = (_AP_HASH[ap] or 0) * 100003 + (_AP_HASH[arp] or 0) * 10007 + math_floor((ax + 200) * 100) * 101 + math_floor((ay + 200) * 100)
        if f._msufClampStamp == stamp and not parentIsClip then
             return
    end
        f._msufClampStamp = stamp
        if parentIsClip then
            local p = f._msufNameTextOrigParent or (f.textFrame or f)
            f.nameText:SetParent(p)
        end
        if parentIsClip or f._msufNameClipAnchorMode ~= nil then
            f.nameText:ClearAllPoints()
            f.nameText:SetPoint(ap, rel, arp, ax, ay)
            f._msufNameClipAnchorMode = nil
            f._msufNameClipSideApplied = nil
            f._msufNameClipAnchorX = nil
            f._msufNameClipAnchorY = nil
    end
        if f.nameText.SetJustifyH then
            f.nameText:SetJustifyH(f._msufNameJustifyH or "LEFT")
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
    local raidGroupShown = false
    if f.raidGroupNameText and f.raidGroupNameText.IsShown and f.raidGroupNameText:IsShown()
        and f._msufRaidGroupNameAnchor == "NAMERIGHT" then
        reservedRight = reservedRight + 24
        raidGroupShown = true
    end
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
    if _fontConf and _fontConf.fontOverride and type(_fontConf.shortenNameMaxChars) == "number" then
        maxChars = _fontConf.shortenNameMaxChars
    elseif g and type(g.shortenNameMaxChars) == "number" then
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
    local mode
    if _fontConf and _fontConf.fontOverride and _fontConf.shortenNameClipSide ~= nil then
        mode = _fontConf.shortenNameClipSide
    else
        mode = (g and g.shortenNameClipSide) or "LEFT"
    end
    if mode ~= "LEFT" and mode ~= "RIGHT" then
        mode = "LEFT"
    end
    local clipSide = mode
    local maskPx = 0
    if _fontConf and _fontConf.fontOverride and _fontConf.shortenNameFrontMaskPx ~= nil then
        maskPx = tonumber(_fontConf.shortenNameFrontMaskPx) or 0
    elseif g and g.shortenNameFrontMaskPx ~= nil then
        maskPx = tonumber(g.shortenNameFrontMaskPx) or 0
    end
    maskPx = math.floor(maskPx + 0.5)
    if maskPx < 0 then maskPx = 0 end
    if maskPx > 80 then maskPx = 80 end
    local showDots = true
    if _fontConf and _fontConf.fontOverride and _fontConf.shortenNameShowDots ~= nil then
        showDots = (_fontConf.shortenNameShowDots and true or false)
    elseif g and g.shortenNameShowDots ~= nil then
        showDots = (g.shortenNameShowDots and true or false)
    end
    local nameAnchorMode = f._msufNameAnchorMode or "LEFT"
    f._msufNameClipAnchorMode = nameAnchorMode
    if nameAnchorMode ~= "LEFT" then
        showDots = false
    end
    if not showDots then
        maskPx = 0
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
              + (raidGroupShown and 50021 or 0)
              + (mode == "LEFT" and 3 or 0)
              + maskPx * 17
              + (showDots and 1 or 0)
    if f._msufClampStamp == stamp then
         return
    end
    f._msufClampStamp = stamp
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
    local textStamp = ((clipSide == "LEFT") and 1 or 2) * 10 + ((nameAnchorMode == "RIGHT" and 3) or (nameAnchorMode == "CENTER" and 2) or 1)
    local desiredJustify = (nameAnchorMode == "RIGHT" and "RIGHT")
        or (nameAnchorMode == "CENTER" and "CENTER")
        or ((clipSide == "LEFT") and "RIGHT" or "LEFT")
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
        if f.nameText and f.nameText.SetParent then
            f.nameText:SetParent(clip)
    end
        if nameAnchorMode == "RIGHT" then
            f.nameText:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        elseif nameAnchorMode == "CENTER" then
            f.nameText:SetPoint("TOP", clip, "TOP", 0, 0)
        elseif clipSide == "LEFT" then
            f.nameText:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        else
            f.nameText:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    end
        if f.nameText and f.nameText.SetJustifyH then
            f.nameText:SetJustifyH(desiredJustify)
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
    if not unit or not UnitLevel then return "" end
    local lvl = UnitLevel(unit)
    local n = tonumber(lvl)
    if not n then return "" end
    if n == -1 then return "??" end
    if n <= 0 then return "" end
    return tostring(n)
end
-- Export for legacy paths (some earlier helpers reference this as a global).
-- Keeping this avoids blank/missing level text when a legacy full update runs.
_G.MSUF_GetUnitLevelText = MSUF_GetUnitLevelText
-- PERF: Cache function refs + constants at file scope (called 70-350x/sec in combat).
local _MSUF_UnitHealthPercent = (type(UnitHealthPercent) == "function") and UnitHealthPercent or nil
local _MSUF_ScaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) or nil
local function MSUF_GetUnitHealthPercent(unit)
    local fn = _MSUF_UnitHealthPercent
    if not fn then return nil end
    if _MSUF_ScaleTo100 then
        return fn(unit, true, _MSUF_ScaleTo100)
    end
    return fn(unit, true, true)
end
-- PERF: Cache abbreviation function at file scope (called 70-350x/sec).
local _MSUF_AbbrNumFn = _G.ShortenNumber or _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers
local function MSUF_NumberToTextFast(v)
    if v == nil then return nil end
    local isv = _MSUF_issecretvalue
    if isv and isv(v) then
        local abbr = _MSUF_AbbrNumFn
        if abbr then return abbr(v) end
        return nil
    end
    if type(v) ~= "number" then
         return nil
    end
    local abbr = _MSUF_AbbrNumFn
    if abbr then return abbr(v) end
    return tostring(v)
end
local function MSUF_ClearHpTextFastSignature(self)
    self._msufHpTextFastReady = nil
    self._msufHpTextFastSpec = nil
    self._msufHpTextFastH = nil
    self._msufHpTextFastMax = nil
    self._msufHpTextFastPctKey = nil
    self._msufHpTextFastHasPct = nil
    self._msufHpTextFastAbsorb = nil
    self._msufHpTextFastAbsorbStyle = nil
    self._msufHpTextFastShowAbsorb = nil
end
local function MSUF_HpPctFastKey(pct)
    local isv = _MSUF_issecretvalue
    if pct == nil or (isv and isv(pct)) or type(pct) ~= "number" then return nil end
    return math_floor(pct * 10 + 0.5)
end
local function MSUF_HpTextFastComparable(v)
    local isv = _MSUF_issecretvalue
    return not (v ~= nil and isv and isv(v))
end
local function MSUF_ShouldSkipHpTextFastRender(self, spec, hpStr, hpPct, hasPct, hpMaxStr, absorbText, absorbStyle, showAbsorb)
    if not self or not spec then return false end
    if spec.hpNeedsDeficit == true then return false end
    if not MSUF_HpTextFastComparable(hpStr)
        or not MSUF_HpTextFastComparable(hpMaxStr)
        or not MSUF_HpTextFastComparable(absorbText)
    then
        return false
    end

    local pctKey
    if hasPct then
        pctKey = MSUF_HpPctFastKey(hpPct)
        if pctKey == nil and spec.hpNeedsPct == true then return false end
    elseif spec.hpNeedsPct == true then
        return false
    end

    if self._msufHpTextFastReady
        and self._msufHpTextFastSpec == spec
        and self._msufHpTextFastH == hpStr
        and self._msufHpTextFastMax == hpMaxStr
        and self._msufHpTextFastPctKey == pctKey
        and self._msufHpTextFastHasPct == hasPct
        and self._msufHpTextFastAbsorb == absorbText
        and self._msufHpTextFastAbsorbStyle == absorbStyle
        and self._msufHpTextFastShowAbsorb == showAbsorb
    then
        return true
    end

    self._msufHpTextFastReady = true
    self._msufHpTextFastSpec = spec
    self._msufHpTextFastH = hpStr
    self._msufHpTextFastMax = hpMaxStr
    self._msufHpTextFastPctKey = pctKey
    self._msufHpTextFastHasPct = hasPct
    self._msufHpTextFastAbsorb = absorbText
    self._msufHpTextFastAbsorbStyle = absorbStyle
    self._msufHpTextFastShowAbsorb = showAbsorb
    return false
end
-- Icon layout runtime moved to Core/MSUF_IconLayoutRuntime.lua.
-- 12.0: UFCore now resolves directly to ns.Bars.HealthCalcUpdate. Thin compat wrapper.
local _cachedSpecHealth = nil
function _G.MSUF_UFCore_UpdateHealthFast(self)
    if not self then return nil, nil, false end
    local fn = _cachedSpecHealth or ns.Bars.HealthCalcUpdate or (ns.Bars.Spec and ns.Bars.Spec.health)
    if not fn then return nil, nil, false end
    _cachedSpecHealth = fn
    return fn(self, self.unit)
end
function _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    if not self or not self.unit or not self.hpText then return end
    local unit = self.unit
    local conf = self.cachedConfig
    if self.showHPText == false or hp == nil then
        MSUF_ClearHpTextFastSignature(self)
        ns.Text.RenderHpMode(self, false)
         return
    end
    local spec = self._msufTextSpec
    if not spec and ns.Text and ns.Text.EnsureSpec then
        spec = ns.Text.EnsureSpec(self)
    end
    local hpNeedsCurrent = not spec or spec.hpNeedsCurrent ~= false
    local hpNeedsMax = not spec or spec.hpNeedsMax == true
    local hpNeedsPct = not spec or spec.hpNeedsPct == true
    local hpStr = hpNeedsCurrent and MSUF_NumberToTextFast(hp) or nil
    -- PERF: Cache hpMax + hpMaxStr â€” hpMax only changes on UNIT_MAXHEALTH (~0.5/s)
    -- but UNIT_HEALTH fires 10-50Ã—/s. Saves UnitHealthMax + NumberToTextFast per tick.
    -- _msufAbsorbTextDirty is already set on UNIT_MAXHEALTH by FrameOnEvent.
    local absorbTextDirty = self._msufAbsorbTextDirty == true
    local hpMaxValue
    local hpMaxStr
    if hpNeedsMax or hpNeedsPct then
        hpMaxValue = self._msufCachedHpMaxValue
        if hpMaxValue == nil or absorbTextDirty then
            hpMaxValue = UnitHealthMax(unit)
            self._msufCachedHpMaxValue = hpMaxValue
        end
    elseif absorbTextDirty then
        self._msufCachedHpMaxValue = nil
    end
    if hpNeedsMax then
        hpMaxStr = self._msufCachedHpMaxStr
        if not hpMaxStr or absorbTextDirty then
            hpMaxStr = MSUF_NumberToTextFast(hpMaxValue)
            self._msufCachedHpMaxStr = hpMaxStr
        end
    elseif absorbTextDirty then
        self._msufCachedHpMaxStr = nil
    end
    local hpPct
    if hpNeedsPct then
        local isv = _MSUF_issecretvalue
        if type(hp) == "number" and type(hpMaxValue) == "number"
            and not (isv and (isv(hp) or isv(hpMaxValue)))
            and hpMaxValue > 0
        then
            hpPct = (hp / hpMaxValue) * 100
        else
            hpPct = MSUF_GetUnitHealthPercent(unit)
        end
    end
    local hasPct = hpNeedsPct and (type(hpPct) == "number") or false
    local absorbText, absorbStyle = nil, nil
    -- PERF: Cache absorb text display flag per-frame. Invalidated when cachedConfig is cleared
    -- (config change). Most users have absorb text disabled â†’ skip all absorb work entirely.
    local showAbsorbCached = self._msufCachedShowAbsorbText
    if showAbsorbCached == nil then
        local g = MSUF_DB and MSUF_DB.general or {}
        local _resolveAbsorb = ns.Bars and ns.Bars._ResolveAbsorbDisplay
        if type(_resolveAbsorb) == "function" then
            local _, showText = _resolveAbsorb(unit)
            showAbsorbCached = showText and true or false
        else
            showAbsorbCached = (g.showTotalAbsorbAmount == true) and true or false
        end
        self._msufCachedShowAbsorbText = showAbsorbCached
    end
    -- PERF: Absorb text only changes on UNIT_ABSORB_AMOUNT_CHANGED / UNIT_MAXHEALTH / unit swap.
    -- Reuse cached result on plain UNIT_HEALTH (fires 10-50x/sec vs absorb 1-5x/sec).
    -- Saves 2 C-API calls (UnitGetTotalAbsorbs + TruncateWhenZero) per HP text update.
    if showAbsorbCached and UnitGetTotalAbsorbs then
        if self._msufAbsorbTextDirty or self._msufAbsorbTextDirty == nil then
            self._msufAbsorbTextDirty = false
            if C_StringUtil and C_StringUtil.TruncateWhenZero then
                local txt = C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(unit))
                if txt ~= nil then
                    self._msufCachedAbsorbText = txt
                    self._msufCachedAbsorbStyle = "SPACE"
                else
                    self._msufCachedAbsorbText = nil
                    self._msufCachedAbsorbStyle = nil
                end
            else
                local absorbValue = UnitGetTotalAbsorbs(unit)
                if absorbValue ~= nil then
                    local abbr = _MSUF_AbbrNumFn or _G.AbbreviateLargeNumbers or _G.ShortenNumber or _G.AbbreviateNumbers
                    if abbr then
                        self._msufCachedAbsorbText = abbr(absorbValue)
                    else
                        self._msufCachedAbsorbText = tostring(absorbValue)
                    end
                    self._msufCachedAbsorbStyle = "PAREN"
                else
                    self._msufCachedAbsorbText = nil
                    self._msufCachedAbsorbStyle = nil
                end
            end
        end
        absorbText = self._msufCachedAbsorbText
        absorbStyle = self._msufCachedAbsorbStyle
    elseif absorbTextDirty then
        self._msufAbsorbTextDirty = false
    end
    if MSUF_ShouldSkipHpTextFastRender(self, spec, hpStr, hpPct, hasPct, hpMaxStr, absorbText,
        absorbStyle, showAbsorbCached)
    then
        return
    end
    ns.Text.RenderHpMode(self, true, hpStr, hpPct, hasPct, conf, nil, absorbText, absorbStyle,
        hpMaxStr)
 end
function _G.MSUF_ApplyBossTestHpPreviewText(self, conf)
    if not self or not self.hpText then return end
    local show = (self.showHPText ~= false)
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hpStr = MSUF_NumberToTextFast(750000)
    local hpMaxStr = MSUF_NumberToTextFast(1000000)
    local hpDeficitStr = MSUF_NumberToTextFast(250000)
    local hpPct = 75.0
    ns.Text.RenderHpMode(self, show, hpStr, hpPct, true, conf, g, nil, nil, hpMaxStr, hpDeficitStr)
 end
function _G.MSUF_UFCore_UpdatePowerTextFast(self)
    return ns.Text.RenderPowerText(self)
end
function _G.MSUF_UFCore_UpdatePowerBarFast(self)
    if not self then return end
    local bar = self.targetPowerBar
    if not (bar and self.unit) then return end
    -- Raw UnitPower/UnitPowerMax + ExponentialEaseOut (MidnightRogueBars approach).
    MSUF_EnsureUnitFlags(self)
    local barsConf = (MSUF_DB and MSUF_DB.bars) or {}
    ns.Bars.Spec.power_pct(self, self.unit, barsConf, self.isBoss, self._msufIsPlayer, self._msufIsTarget, self._msufIsFocus)
 end
local function MSUF_ClearUnitFrameState(self, clearAbsorbs)
    ns.Bars.ResetHealthAndOverlays(self, clearAbsorbs)
    if self.nameText then self.nameText:SetText("") end
    MSUF_ClearText(self.raidGroupNameText, true)
    MSUF_ClearText(self.levelText, true)
    MSUF_ClearText(self.hpTextLeft, true)
    MSUF_ClearText(self.hpTextCenter, true)
    MSUF_ClearText(self.hpText, true)
    ns.Text.ClearField(self, "hpTextPct")
    MSUF_ClearText(self.powerTextLeft, true)
    MSUF_ClearText(self.powerTextCenter, true)
    MSUF_ClearText(self.powerText, true)
    ns.Text.ClearField(self, "powerTextPct")
 end

-- Edit-mode unitframe preview lives in Core\MSUF_FramePreview.lua.
-- Keep thin local wrappers for existing UpdateSimpleUnitFrame call sites.
local function MSUF_ApplyUnitframePreviewOverlays(self, unit, maxHP)
    local fn = _G.MSUF_ApplyUnitframePreviewOverlays
    if type(fn) == "function" then return fn(self, unit, maxHP) end
end
-- HOT-PATH LOCAL CACHE
-- Resolve _G function references once; avoids hash lookup on every call.
-- Functions are defined above this point or in files loaded earlier (TOC).
-- Mutable state (_G.MSUF_UnitTokenChanged, _G.MSUF_UFCORE_FLUSH_SERIAL)
-- stays on _G since the values change every flush.
-- Lazy-resolved unit-frame function refs (single table = 1 local instead of 11).
local _UF = {
    Alpha      = nil,  -- MSUF_ApplyUnitAlpha (Alpha.lua loads after main)
    Portrait   = nil,  -- MSUF_MaybeUpdatePortrait (Portraits.lua loads after main)
    EditPrev   = nil,  -- MSUF_ApplyUnitframeEditPreview
    HpText     = _G.MSUF_UFCore_UpdateHpTextFast,
    PwrText    = _G.MSUF_UFCore_UpdatePowerTextFast,
    PwrBar     = _G.MSUF_UFCore_UpdatePowerBarFast,
    BossPrev   = _G.MSUF_ApplyBossTestHpPreviewText,
    QueueVis   = _G.MSUF_QueueUnitframeVisual,
    LeaderIcon = MSUF_ApplyLeaderIconLayout,
    RaidMarker = MSUF_ApplyRaidMarkerLayout,
    TPASync    = nil,  -- forward decl: assigned after definition below
}

local function MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus)
    if not self then return false end
    MSUF_EnsureUnitFlags(self)
    return ns.Bars.Spec.power_pct(self, unit, barsConf, self.isBoss, isPlayer, isTarget, isFocus) and true or false
end
local function MSUF_UFStep_BasicHealth(self, unit)
    local hp = ns.Bars.ApplyHealthBars(self, unit)
     return hp
end
local function MSUF_UFStep_HeavyVisual(self, unit, key, g_opt)
    -- Rate-limit: 0.15s between heavy visual passes (options live-apply safety).
    local forceHeavy = false
    local tokenFlags = _G.MSUF_UnitTokenChanged
    if tokenFlags and key and tokenFlags[key] then
        tokenFlags[key] = nil
        forceHeavy = true
    end
    local now = F.GetTime()
    if not forceHeavy then
        local nextAt = self._msufHeavyVisualNextAt or 0
        if now < nextAt then return end
        self._msufHeavyVisualNextAt = now + 0.15
    else
        self._msufHeavyVisualNextAt = now
    end
    -- Delegate bar-mode color resolution to UFCore (dark/class/unified + NPC type).
    local fn = _G.MSUF_UFCore_RefreshHealthBarColor
    if fn then
        -- Clear diff-gate so color always re-applies on options change.
        self._msufLastHPBarR = nil
        fn(self)
    end
    -- Gradients + bar background (not exported to _G, call via ns.Bars directly).
    if self.hpGradients then
        ns.Bars._ApplyHPGradient(self)
    elseif self.hpGradient then
        ns.Bars._ApplyHPGradient(self.hpGradient)
    end
    if self.bg then
        MSUF_ApplyBarBackgroundVisual(self)
    end
    self._msufHeavyVisualApplied = true
    self._msufHeavyVisualSettingsSerial = _MSUF_GetUFCoreSettingsSerial()
end
local function MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus)
  local pb = self.targetPowerBar or self.powerBar
  if not (pb and pb.IsShown and pb:IsShown()) then return false end
  local flag = (self.isBoss and "showBossPowerBar")
            or (isPlayer and "showPlayerPowerBar")
            or (isTarget and "showTargetPowerBar")
            or (isFocus and "showFocusPowerBar")
  local readEnabled = _G.MSUF_ReadUnitPowerBarEnabled
  if type(readEnabled) == "function" then
      local unitKey = (self.isBoss and "boss") or (isPlayer and "player") or (isTarget and "target") or (isFocus and "focus") or nil
      if unitKey and readEnabled(unitKey) == false then return _MSUF_Bars_HidePower(pb, true) end
  elseif flag and barsConf and barsConf[flag] == false then
      return _MSUF_Bars_HidePower(pb, true)
  end
  if MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus) then  return true end
   return false
end
local function MSUF_FrameHasRuntimeBorderState(self)
    if not self then return false end
    if self._msufAggroOutlineOn or self._msufDispelOutlineOn or self._msufPurgeOutlineOn or self._msufBossTargetHLOn then
        return true
    end
    if _G.MSUF_BorderTestModesActive == true then
        return true
    end
    local hl = self._msufHighlightOutline
    return (hl and hl.IsShown and hl:IsShown()) and true or false
end

local function MSUF_UFStep_Border(self)
    if not MSUF_FrameHasRuntimeBorderState(self) then return end
    local fn = _G.MSUF_RefreshRareBarVisuals
    if type(fn) == "function" then
        fn(self)
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
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit) and true or false
            local isAssist = (not isLeader) and UnitIsGroupAssistant and UnitIsGroupAssistant(unit) and true or false
            if isLeader or isAssist then
                MSUF_SetLeaderAssistTexture(self.leaderIcon, conf, g, isAssist)
                ns.Util.SetShown(self.leaderIcon, true)
            else
                ns.Util.SetShown(self.leaderIcon, false)
            end
        end
    end
    if self.leaderIcon and _UF.LeaderIcon then _UF.LeaderIcon(self) end
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
    if self.raidMarkerIcon and _UF.RaidMarker then _UF.RaidMarker(self) end
    if self.eliteIcon and _G.MSUF_UpdateEliteIcon then _G.MSUF_UpdateEliteIcon(self) end
end
local function MSUF_UFStep_Finalize(self, hp, didPowerBarSync)
    -- Secret-safe text gating + per-flush coalesce (no compares on hp/power values)
    local showHPText = (self.showHPText ~= false)
    local showPowerText = (self.showPowerText ~= false)
    local textStamp = self._msufTextLayoutStamp or 0
    -- Coalesce within the same millisecond-bucket (approx "per-flush" when multiple updates burst)
    local now = GetTime()
    local nowMs = math_floor(now * 1000)
    -- Text state sub-table: reduces hash lookups on the frame object (10 long-key writes ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ short keys on small table)
    local ts = self._msufTS
    if not ts then ts = {}; self._msufTS = ts end
    -- HP text: force when layout/toggle changed, otherwise rate-limit
    local forceHP = (ts[1] ~= textStamp) or (ts[2] ~= showHPText) -- [1]=hpStamp, [2]=showHP
    if showHPText then
        if forceHP or (ts[3] == nil) or ((now - (ts[3] or 0)) >= 0.10) then -- [3]=hpAt
            if forceHP or (ts[4] ~= nowMs) then -- [4]=hpMs
                _UF.HpText(self, hp)
                ts[3] = now
                ts[4] = nowMs
            end
        end
    else
        -- still call once on toggle-off so the fast path can hide/clear
        if forceHP then
            _UF.HpText(self, hp)
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
                _UF.PwrText(self)
                ts[7] = now
                ts[8] = nowMs
            end
        end
    else
        if forcePower then
            _UF.PwrText(self)
            ts[7] = now
            ts[8] = nowMs
        end
    end
    ts[5] = textStamp
    ts[6] = showPowerText
    if not didPowerBarSync then
        _UF.PwrBar(self)
    end
    -- PERF: Rate-limit StatusIndicator to 4Hz (0.25s) during combat.
    -- DEAD/GHOST/AFK/DND text and Combat/Rest/Rez icons don't change at 60fps.
    -- Out of combat: always run (responsive to config changes).
    local forceStatus = (ts[9] == nil)  -- [9] = statusAt
    if forceStatus or (not _msuf_inCombat) or ((now - (ts[9] or 0)) >= 0.25) then
        ts[9] = now
        MSUF_UpdateStatusIndicatorForFrame(self)
    end
 end
local function _MSUF_ShouldRunStaticVisualPass(self, key, exists)
    if not self or not exists then return false end
    if self._msufLayoutWhy or self._msufVisualQueuedUFCore or self._msufPortraitDirty or self._msufNeedsBorderVisual then
        return true
    end
    local tokenFlags = _G.MSUF_UnitTokenChanged
    if tokenFlags and key and tokenFlags[key] then
        return true
    end
    local settingsSerial = _MSUF_GetUFCoreSettingsSerial()
    if self._msufStaticVisualSettingsSerial ~= settingsSerial or not self._msufStaticVisualApplied then
        return true
    end
    return _MSUF_IsVisualLiveApplyContext() and (not _msuf_inCombat)
end

function MSUF_UpdateSimpleUnitFrame(self)
        -- P0: _UF.Alpha / Portrait / EditPrev pre-resolved at PLAYER_LOGIN.
        -- Zero per-call overhead (was: 3 branches + 3 _G hash lookups per frame update).
        local _flushSerial = _G.MSUF_UFCORE_FLUSH_SERIAL  -- cache once per call

        -- Hot path: prefer UFCore's settings snapshot (avoids repeated deep MSUF_DB traversals).
        local db, g, barsConf

        local getCache = _MSUF_ResolveGetCache()

        if getCache then
            local cache = getCache()
            if cache then
                db = cache.dbRef or _G.MSUF_DB
                g = cache.generalRef
                barsConf = cache.barsRef
            end
        end

        if not db then
            if not MSUF_DB then MSUF_EnsureDB() end
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
_G.UpdateSimpleUnitFrame = _G.UpdateSimpleUnitFrame or MSUF_UpdateSimpleUnitFrame
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
    if self.isBoss and MSUF_BossTestMode and not _msuf_inCombat then
        self:Show()
        if _UF.Alpha then _UF.Alpha(self, key) end
    if self.bg then
        MSUF_ApplyBarBackgroundVisual(self)
    end
               if self.targetPowerBar then
            local bossPowerEnabled = true
            local readPowerEnabled = _G.MSUF_ReadUnitPowerBarEnabled
            if type(readPowerEnabled) == "function" then
                bossPowerEnabled = readPowerEnabled("boss")
            else
                bossPowerEnabled = not (barsConf.showBossPowerBar == false)
            end
            if not bossPowerEnabled then
                self.targetPowerBar:SetScript("OnUpdate", nil)
                self.targetPowerBar:Hide()
                MSUF_ResetBarZero(self.targetPowerBar, true)
            else
                self.targetPowerBar:SetMinMaxValues(0, 100)
                self.targetPowerBar:SetValue(40)
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
        -- Boss preview: invalidate diff-gates so font/shortening changes render immediately
        self._msufClampStamp = nil
        self._msufNameClipAnchorStamp = nil
        self._msufNameClipTextStamp = nil
        if self.nameText then self.nameText._msufLastSetT = nil end
        ns.Text.ApplyBossTestName(self, unit)
        if type(MSUF_ApplyLevelIndicatorLayout) == "function" then
            MSUF_ApplyLevelIndicatorLayout(self)
        end
        ns.Text.ApplyBossTestLevel(self, conf)
        if self.portrait and conf then
            if _G.MSUF_UpdateBossPortraitLayout then
                _G.MSUF_UpdateBossPortraitLayout(self, conf)
            end
            local portraitMode = conf.portraitMode or "OFF"
            local portraitRender = (conf.portraitRender == "CLASS") and "CLASS" or "2D"
            local portraitStyle = conf.portraitClassStyle or "BLIZZARD"
            local portraitHidden = self.portrait.IsShown and (not self.portrait:IsShown())
            if self._msufBossPreviewPortraitMode ~= portraitMode
                or self._msufBossPreviewPortraitRender ~= portraitRender
                or self._msufBossPreviewPortraitStyle ~= portraitStyle
                or portraitHidden
                or self._msufPortraitDirty
            then
                self._msufBossPreviewPortraitMode = portraitMode
                self._msufBossPreviewPortraitRender = portraitRender
                self._msufBossPreviewPortraitStyle = portraitStyle
                self._msufPortraitDirty = true
                self._msufPortraitNextAt = 0
            end
            local fnP = _UF.Portrait or _G.MSUF_MaybeUpdatePortrait
            if type(fnP) == "function" then
                fnP(self, unit, conf, false)
            end
        end
        if self.hpText then
    local show = (self.showHPText ~= false)
    if show then
        _UF.BossPrev(self, conf)
    else
        MSUF_SetTextIfChanged(self.hpText, "")
        MSUF_ClearText(self.hpTextLeft, true)
        MSUF_ClearText(self.hpTextCenter, true)
    ns.Text.ClearField(self, "hpTextPct")
    end
    ns.Util.SetShown(self.hpText, show)
    ns.Util.SetShown(self.hpTextLeft, show and self.hpTextLeft and self.hpTextLeft:GetText() ~= "")
    ns.Util.SetShown(self.hpTextCenter, show and self.hpTextCenter and self.hpTextCenter:GetText() ~= "")
end
if self.powerText then
            local showPower = self.showPowerText
            if showPower == nil then
                showPower = true
            end
            if showPower then
                MSUF_SetTextIfChanged(self.powerText, "40 / 100")
                MSUF_ClearText(self.powerTextLeft, true)
                MSUF_ClearText(self.powerTextCenter, true)
            else
                MSUF_SetTextIfChanged(self.powerText, "")
                MSUF_ClearText(self.powerTextLeft, true)
                MSUF_ClearText(self.powerTextCenter, true)
            end
            ns.Util.SetShown(self.powerText, showPower)
    end
         return
    end
-- â”€â”€ Preview Test Mode (non-boss, non-player, no unit) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Mirrors BossTestMode block above. Full control over bars/text/visibility.
if not self.isBoss and not self._msufIsPlayer and _G.MSUF_PreviewTestMode and not _msuf_inCombat and not exists then
    self:Show()
    if _UF.Alpha then _UF.Alpha(self, key) end
    if self.bg then
        MSUF_ApplyBarBackgroundVisual(self)
    end
    -- HP bar: visible placeholder (class-colored or green, not black)
    local hb = self.hpBar
    if hb then
        MSUF_SetBarMinMax(hb, 0, 1)
        hb:SetValue(0.73)
        if hb.SetStatusBarColor then hb:SetStatusBarColor(0.20, 0.80, 0.20, 1) end
        if self.hpGradients then ns.Bars._ApplyHPGradient(self)
        elseif self.hpGradient then ns.Bars._ApplyHPGradient(self.hpGradient) end
    end
    MSUF_ApplyUnitframePreviewOverlays(self, key or self.msufConfigKey or self.unit, 1)
    -- Power bar
    local pb = self.targetPowerBar or self.powerBar
    if pb then
        local showPB = (conf and conf.showPower ~= false)
        if showPB then
            pb:SetMinMaxValues(0, 100)
            pb:SetValue(52)
            pb.MSUF_lastValue = 52
            if pb.SetStatusBarColor then pb:SetStatusBarColor(0.20, 0.60, 1.00, 1) end
            ns.Bars.ApplyPowerGradientOnce(self)
            pb:Show()
            if pb.bg and pb.bg.Show then pb.bg:Show() end
        else
            pb:Hide()
        end
    end
    -- Ensure only one power bar visible (targetPowerBar vs powerBar)
    if self.targetPowerBar and self.powerBar and self.powerBar ~= self.targetPowerBar then
        if pb == self.targetPowerBar then
            self.powerBar:Hide()
        else
            self.targetPowerBar:Hide()
        end
    end
    -- Power bar border/separator line (reads config live)
    if pb and type(_G.MSUF_ApplyPowerBarBorder) == "function" then
        _G.MSUF_ApplyPowerBarBorder(pb)
    end
    -- Invalidate diff-gates (same as boss path)
    self._msufClampStamp = nil
    self._msufNameClipAnchorStamp = nil
    self._msufNameClipTextStamp = nil
    if self.nameText then self.nameText._msufLastSetT = nil end
    -- Name text (respects showName toggle)
    if self.nameText then
        local showN = (self.showName ~= false)
        if showN then
            local label = self.msufConfigKey or unit or "unit"
            if label == "targettarget" then label = "ToT" end
            MSUF_SetTextIfChanged(self.nameText, string.upper(label))
        else
            MSUF_SetTextIfChanged(self.nameText, "")
        end
        ns.Util.SetShown(self.nameText, showN)
    end
    if self.raidGroupNameText then
        local showRG = (conf and conf.showRaidGroupInName == true)
            and MSUF_RaidGroupNameAllowedForKey(self.msufConfigKey or unit or self.unit)
        if showRG then
            MSUF_SetTextIfChanged(self.raidGroupNameText, MSUF_RaidGroupNamePreviewText(conf))
        else
            MSUF_SetTextIfChanged(self.raidGroupNameText, "")
        end
        ns.Util.SetShown(self.raidGroupNameText, showRG)
        if _G.MSUF_ApplyRaidGroupNameLayout then _G.MSUF_ApplyRaidGroupNameLayout(self) end
    end
    MSUF_UpdateNameColor(self)
    -- Level text (showLevelIndicator is the actual config key)
    if self.levelText then
        local showLvl = (conf and conf.showLevelIndicator ~= false)
        if showLvl then
            MSUF_SetTextIfChanged(self.levelText, "70")
        else
            MSUF_SetTextIfChanged(self.levelText, "")
        end
        ns.Util.SetShown(self.levelText, showLvl)
        if MSUF_ClampNameWidth then MSUF_ClampNameWidth(self, conf) end
    end
    -- HP text (respects showHP toggle)
    if self.hpText then
        local showHP = (self.showHPText ~= false)
        if showHP then
            MSUF_SetTextIfChanged(self.hpText, "73% 123.4k")
            MSUF_ClearText(self.hpTextLeft, true)
            MSUF_ClearText(self.hpTextCenter, true)
        else
            MSUF_SetTextIfChanged(self.hpText, "")
            MSUF_ClearText(self.hpTextLeft, true)
            MSUF_ClearText(self.hpTextCenter, true)
            ns.Text.ClearField(self, "hpTextPct")
        end
        ns.Util.SetShown(self.hpText, showHP)
    end
    -- Power text (respects showPower toggle)
    if self.powerText then
        local showPwr = (self.showPowerText ~= false)
        if showPwr then
            MSUF_SetTextIfChanged(self.powerText, "52% 65")
            MSUF_ClearText(self.powerTextLeft, true)
            MSUF_ClearText(self.powerTextCenter, true)
        else
            MSUF_SetTextIfChanged(self.powerText, "")
            MSUF_ClearText(self.powerTextLeft, true)
            MSUF_ClearText(self.powerTextCenter, true)
        end
        ns.Util.SetShown(self.powerText, showPwr)
    end
    -- Leader icon (fake leader for preview)
    if self.leaderIcon then
        local showLeader = ns.Util.Enabled(conf, g, "showLeaderIcon", true)
        -- Invalidate layout stamp so position/size re-applies from config
        ns.Cache.ClearStamp(self, "LeaderIconLayout")
        if _UF.LeaderIcon then _UF.LeaderIcon(self) end
        -- Set texture + visibility AFTER layout (layout only does position/size)
        if showLeader then
            MSUF_SetLeaderAssistTexture(self.leaderIcon, conf, g, false)
            self.leaderIcon:Show()
        else
            self.leaderIcon:Hide()
        end
    end
    -- Raid marker icon (fake star marker for preview)
    if self.raidMarkerIcon then
        local showMarker = ns.Util.Enabled(conf, g, "showRaidMarker", true)
        ns.Cache.ClearStamp(self, "RaidMarkerLayout")
        if _UF.RaidMarker then _UF.RaidMarker(self) end
        if showMarker then
            if SetRaidTargetIconTexture then SetRaidTargetIconTexture(self.raidMarkerIcon, 1) end
            self.raidMarkerIcon:Show()
        else
            self.raidMarkerIcon:Hide()
        end
    end
    -- Status indicators (combat, rest, rez icons â€” live-apply config changes)
    if type(MSUF_UpdateStatusIndicatorForFrame) == "function" then
        MSUF_UpdateStatusIndicatorForFrame(self)
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
    if MSUF_UnitEditModeActive and (not _msuf_inCombat) and unit ~= "player" and self and not self.isBoss then
        if _UF.EditPrev then
            _UF.EditPrev(self, key, conf, g)
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
    if _UF.Alpha then _UF.Alpha(self, key) end
    self._msufNoUnitCleared = nil
    if _UF.Portrait then _UF.Portrait(self, unit, conf, exists) end
end
    local hp = MSUF_UFStep_BasicHealth(self, unit)
    if MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus) then
        didPowerBarSync = true
    end
    local doStaticVisual = _MSUF_ShouldRunStaticVisualPass(self, key, exists)
    if doStaticVisual then
        MSUF_UFStep_NameLevelLeaderRaid(self, unit, conf, g)
        self._msufStaticVisualApplied = true
        self._msufStaticVisualSettingsSerial = _MSUF_GetUFCoreSettingsSerial()
    end
    MSUF_UFStep_Finalize(self, hp, didPowerBarSync)
    -- Rare/Heavy visuals are gated to reduce work in the frequent update path.
    -- We still force a visual pass when the "bottom bar" (power vs health) changes.
    do
        local pb = self.targetPowerBar
        local pbDetached = self._msufPowerBarDetached
        local pbWanted = (pb ~= nil) and not pbDetached and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
        local bottomIsPower = pbWanted and true or false
        if MSUF_FrameHasRuntimeBorderState(self) and self._msufHighlightBottomIsPower ~= (bottomIsPower and true or false) then
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
        self._msufHeavyVisualSettingsSerial = _MSUF_GetUFCoreSettingsSerial()
        self._msufHeavyVisualApplied = true
    end
    -- IMPORTANT: layered/range alpha uses per-texture alpha, which visual steps reset.
    if conf and (conf.alphaExcludeTextPortrait == true or self._msufAlphaLayeredMode) then
        local applyAlpha = _UF.Alpha or _G.MSUF_ApplyUnitAlpha
        self._msufAlphaLayeredFastValid = nil
        self._msufAlphaLayeredFastHits = nil
        if applyAlpha then applyAlpha(self, key) end
    end
    if _UF.TPASync then
        _UF.TPASync(self)
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
-- Resolve forward-declared hot-path local (TPA defined above)
_UF.TPASync = _G.MSUF_TPA_SyncAnchors
do
    local function MSUF_TryRegisterBCDMAnchors()
        if _G.MSUF_BCDM_AnchorsRegistered then return true end
        if not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.IsAddOnLoaded("BetterCooldownManager") then return false end
        if not _G or not _G.BCDMG or type(_G.BCDMG.AddAnchors) ~= "function" then  return false end
        local function MSUF_BCDM_AddAnchors(addOnName, addToTypes, anchorTable)
            local api = _G.BCDMG
            if not api then return false end
            local fn = api.AddAnchors
            if type(fn) ~= "function" then  return false end
            local ok = true; fn(api, addOnName, addToTypes, anchorTable)
            if ok then return true end
            fn(addOnName, addToTypes, anchorTable)
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

-- Hoisted helpers for ApplyUnitFrameKey_Immediate (avoid closure allocation per call)
local function _MSUF_HideUnitFrame(unit)
    local f = UnitFrames[unit]
    if not f then return end
    if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
        MSUF_ApplyUnitVisibilityDriver(f, false)
    end
    f:Hide()
end

local function _MSUF_PreviewUnitFrame(unit, conf)
    local f = UnitFrames[unit]
    if not f then return end
    f.cachedConfig = conf
    if _G.MSUF_UFCore_GetHealthSmoothInterp then
        _G.MSUF_UFCore_GetHealthSmoothInterp(f, conf)
    end
    if _G.MSUF_UFCore_GetPowerSmoothInterp then
        _G.MSUF_UFCore_GetPowerSmoothInterp(f, conf)
    end
    if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
        if f._msufVisibilityForced == "disabled" then
            f._msufVisibilityForced = nil
        end
        MSUF_ApplyUnitVisibilityDriver(f, true)
    end
    if f.Show then f:Show() end
    ns.UF.RequestUpdate(f, true, false, "ApplyUnitKey:DisabledEditPreview")
end

local function _MSUF_ApplyToUnitFrame(unit, conf)
    local f = UnitFrames[unit]
    if not f then return end
    f.cachedConfig = conf
    if _G.MSUF_UFCore_GetHealthSmoothInterp then
        _G.MSUF_UFCore_GetHealthSmoothInterp(f, conf)
    end
    if _G.MSUF_UFCore_GetPowerSmoothInterp then
        _G.MSUF_UFCore_GetPowerSmoothInterp(f, conf)
    end
    if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
        if f._msufVisibilityForced == "disabled" then
            f._msufVisibilityForced = nil
        end
        MSUF_ApplyUnitVisibilityDriver(f, (MSUF_UnitEditModeActive and true or false))
    end
    local focusTargetInactive = unit == "focustarget"
        and type(_G.MSUF_IsFocusTargetEffectiveEnabled) == "function"
        and not _G.MSUF_IsFocusTargetEffectiveEnabled()
    if focusTargetInactive and not (MSUF_UnitEditModeActive and not _msuf_inCombat) then
        if f.Hide then f:Hide() end
        return
    end
    local w = tonumber(conf.width)  or (f.GetWidth and f:GetWidth())  or 275
    local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 40
    conf.width, conf.height = w, h
    f:SetSize(w, h)
    if f.targetPowerBar then
        MSUF_ApplyPowerBarEmbedLayout(f)
    end
    do
        local fnStaticOutlines = _G.MSUF_RefreshStaticUnitFrameOutlines
        if type(fnStaticOutlines) == "function" then
            fnStaticOutlines(f)
        end
    end
    ns.Bars._ApplyReverseFillBars(f, conf)
    local showName  = (conf.showName  ~= false)
    local showHP    = (conf.showHP    ~= false)
    local showPower = (conf.showPower ~= false)
    f.showName      = showName
    f.showHPText    = showHP
    f.showPowerText = showPower
    if unit == "player" then
        f:Show()
    elseif (not _msuf_inCombat) and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
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
        -- Force full portrait render â€” layout alone only positions the widget
        -- but doesn't set the texture. MaybeUpdatePortrait â†’ global UpdatePortraitIfNeeded
        -- â†’ hooksecurefunc fires PortraitDecoration (offsets, borders, size override).
        f._msufPortraitDirty = true
        f._msufPortraitNextAt = 0
        local fnP = _G.MSUF_MaybeUpdatePortrait
        if type(fnP) == "function" then
            local exists = (F.UnitExists and F.UnitExists(unit)) and true or false
            fnP(f, unit, conf, exists)
        end
    end
    ApplyTextLayout(f, conf)
    MSUF_ClampNameWidth(f, conf)
    -- Indicator layout is not part of UFCore's hot element update.
    -- Apply it on the cold options/apply path so layer/anchor/size changes
    -- live-update immediately without waiting for a roster/unit event.
    if type(MSUF_ApplyLeaderIconLayout) == "function" then MSUF_ApplyLeaderIconLayout(f) end
    if type(MSUF_ApplyRaidMarkerLayout) == "function" then MSUF_ApplyRaidMarkerLayout(f) end
    if type(MSUF_ApplyLevelIndicatorLayout) == "function" then MSUF_ApplyLevelIndicatorLayout(f) end
    if type(_G.MSUF_ApplyEliteIconLayout) == "function" then _G.MSUF_ApplyEliteIconLayout(f) end
    if type(MSUF_UpdateStatusIndicatorForFrame) == "function" then MSUF_UpdateStatusIndicatorForFrame(f) end
    ns.UF.RequestUpdate(f, false, true, "ApplyUnitKey")
end

function _G.MSUF_ApplyBossUnitframePreviewState(active, reason)
    if not MSUF_DB then MSUF_EnsureDB() end
    if _msuf_inCombat then
        MSUF_BossTestMode = false
        _G.MSUF_BossTestMode = false
        return
    end
    active = active and true or false
    if not active then
        local editState = _G.MSUF_EditState
        local editActive = (_G.MSUF_UnitEditModeActive == true)
            or (type(editState) == "table" and editState.active == true)
        local editPreviewActive = editActive
            and (_G.MSUF_UnitPreviewActive == true or _G.MSUF_PreviewTestMode == true)
        if editPreviewActive or _G.MSUF2_BossUnitframePreviewActive == true then
            active = true
        end
    end
    MSUF_BossTestMode = active
    _G.MSUF_BossTestMode = active

    local conf = (MSUF_DB and MSUF_DB.boss) or {}
    local anyFrame = false
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local unit = "boss" .. i
        local f = UnitFrames[unit] or _G["MSUF_" .. unit]
        if f then
            anyFrame = true
            f.cachedConfig = conf
            if active then
                if f._msufVisibilityForced == "disabled" then
                    f._msufVisibilityForced = nil
                    f._msufVisibilityAppliedDriver = nil
                end
                if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
                    MSUF_ApplyUnitVisibilityDriver(f, true)
                end
                _MSUF_ApplyToUnitFrame(unit, conf)
                if type(MSUF_UpdateSimpleUnitFrame) == "function" then
                    MSUF_UpdateSimpleUnitFrame(f)
                end
                if f.Show then f:Show() end
                if f.SetAlpha then f:SetAlpha(1) end
                if f.EnableMouse then f:EnableMouse(true) end
            else
                f._msufBossPreviewPortraitMode = nil
                f._msufBossPreviewPortraitRender = nil
                f._msufBossPreviewPortraitStyle = nil
                if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
                    MSUF_ApplyUnitVisibilityDriver(f, false)
                end
                if type(MSUF_UpdateSimpleUnitFrame) == "function" and F.UnitExists and F.UnitExists(unit) then
                    MSUF_UpdateSimpleUnitFrame(f)
                elseif f.Hide then
                    f:Hide()
                end
            end
        end
    end

    if not active and not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end

    if active and not anyFrame and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if _G.MSUF2_BossUnitframePreviewActive == true and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
                _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_RETRY")
            end
        end)
    end

    if active then
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            _G.MSUF_ApplyBossCastbarPositionSetting()
        end
        if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
            and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
        then
            _G.MSUF_UpdateBossCastbarPreview()
        end
    end
end

function _G.MSUF_SyncBossUnitframePreviewWithUnitEdit(reason)
    if MSUF_OptionsApplyCombatLocked() then return end

    local editState = _G.MSUF_EditState
    local editActive = (_G.MSUF_UnitEditModeActive == true)
        or (type(editState) == "table" and editState.active == true)

    local editPreviewActive = editActive and not _msuf_inCombat
        and (_G.MSUF_UnitPreviewActive == true or _G.MSUF_PreviewTestMode == true)
    local pagePreviewActive = (_G.MSUF2_BossUnitframePreviewActive == true)
    local active = (editPreviewActive or pagePreviewActive) and true or false

    _G.MSUF_ApplyBossUnitframePreviewState(active, reason or "MSUF_BOSS_PREVIEW_SYNC")
end

local function MSUF_ApplyUnitFrameKey_Immediate(key)
    if not key then return end
    if MSUF_OptionsApplyCombatLocked() then
        _G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
        _G.MSUF_UnitFrameApplyState.dirty[key] = true
        _G.MSUF_UnitFrameApplyState.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
        end
        return
    end
    if not MSUF_DB then MSUF_EnsureDB() end
    local conf = MSUF_DB[key]
    if not conf then return end
    if _G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked() then
        _G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
        _G.MSUF_UnitFrameApplyState.dirty[key] = true
        _G.MSUF_UnitFrameApplyState.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
        end
        return
    end
	    -- Ensure UnitframeCore refreshes event masks + option caches for this unit so
	    -- changes apply immediately without requiring /reload or a unit swap.
	    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
	        if key == "boss" then
	            _G.MSUF_UFCore_NotifyConfigChanged(nil, false, true, "ApplyUnitKey:boss")
	        else
	            _G.MSUF_UFCore_NotifyConfigChanged(key, false, true, "ApplyUnitKey:" .. tostring(key))
	        end
	    end
    if ns.UF.IsDisabled(conf) then
        if MSUF_UnitEditModeActive and (not _msuf_inCombat) and key ~= "boss" then
            if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "pet" then
                _MSUF_PreviewUnitFrame(key, conf)
            end
            return
        end
        if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "pet" then
            _MSUF_HideUnitFrame(key)
        elseif key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                _MSUF_HideUnitFrame("boss" .. i)
            end
        end
        if (key == "focus" or key == "focustarget") and type(_G.MSUF_RefreshFocusTargetLifecycle) == "function" then
            _G.MSUF_RefreshFocusTargetLifecycle("ApplyUnitFrameKeyDisabled")
        end
        return
    end
    if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "pet" then
        _MSUF_ApplyToUnitFrame(key, conf)
    elseif key == "boss" then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            _MSUF_ApplyToUnitFrame("boss" .. i, conf)
    end
    end
    if key == "player" and MSUF_ReanchorPlayerCastBar then
        MSUF_ReanchorPlayerCastBar()
    elseif key == "target" and MSUF_ReanchorTargetCastBar then
        MSUF_ReanchorTargetCastBar()
    elseif key == "focus" and MSUF_ReanchorFocusCastBar then
        MSUF_ReanchorFocusCastBar()
    end
    if (key == "focus" or key == "focustarget") and type(_G.MSUF_RefreshFocusTargetLifecycle) == "function" then
        _G.MSUF_RefreshFocusTargetLifecycle("ApplyUnitFrameKey")
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
    if MSUF_OptionsApplyCombatLocked() then
        st.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
        end
        return
    end
    if _G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked() then
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
local MSUF_APPLY_ALL_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local function MSUF_RegisterApplyDirtyAfterCombat()
    if type(MSUF_EventBus_Register) == "function" then
        MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
    end
end
local function MSUF_RegisterApplyCommitAfterCombat()
    if type(MSUF_EventBus_Register) == "function" then
        MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT", MSUF_OnRegenEnabled_ApplyCommit)
    end
end
local function MSUF_QueueUnitFrameApplyAfterCombat(markAll)
    _G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
    local stUF = _G.MSUF_UnitFrameApplyState
    if markAll then
        for i = 1, #MSUF_APPLY_ALL_KEYS do
            stUF.dirty[MSUF_APPLY_ALL_KEYS[i]] = true
        end
    end
    stUF.queued = true
    MSUF_RegisterApplyDirtyAfterCombat()
end
local function MSUF_QueueApplyCommitAfterCombat()
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
        st.queued = true
    end
    MSUF_RegisterApplyCommitAfterCombat()
end
local function MSUF_QueueApplyAllAfterCombat()
    MSUF_QueueUnitFrameApplyAfterCombat(true)
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
        st.queued = true
        st.fonts = true
        st.bars = true
        st.castbars = true
        st.tickers = true
        st.bossPreview = true
    end
    MSUF_RegisterApplyCommitAfterCombat()
end
local function MSUF_CommitApplyDirty_Scheduled()
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
    end
        MSUF_CommitApplyDirty()
 end
local function MSUF_ScheduleApplyCommit()
    local st = _G.MSUF_ApplyCommitState
    if not st or st.pending then return end
    if MSUF_OptionsApplyCombatLocked() then
        MSUF_QueueApplyCommitAfterCombat()
        return
    end
    st.pending = true
    if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", MSUF_CommitApplyDirty_Scheduled) else C_Timer.After(0, MSUF_CommitApplyDirty_Scheduled) end
 end
_G.MSUF_ScheduleApplyCommit = MSUF_ScheduleApplyCommit
function MSUF_OnRegenEnabled_ApplyCommit(event)
    local st = _G.MSUF_ApplyCommitState
    if st and st.queued then
        st.queued = false
            MSUF_CommitApplyDirty()
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
 end
function MSUF_ApplySettingsForKey(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_ApplyCommitState
    if key == "boss" then
        st.bossPreview = true
    end
    MSUF_ScheduleApplyCommit()
 end
_G.ApplySettingsForKey = _G.ApplySettingsForKey or MSUF_ApplySettingsForKey

function MSUF_ApplyAllSettings()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end
    MSUF_MarkUnitFrameDirty("player")
    MSUF_MarkUnitFrameDirty("target")
    MSUF_MarkUnitFrameDirty("focus")
    MSUF_MarkUnitFrameDirty("targettarget")
    MSUF_MarkUnitFrameDirty("focustarget")
    MSUF_MarkUnitFrameDirty("pet")
    MSUF_MarkUnitFrameDirty("boss")
    st.fonts = true
    st.bars = true
    st.castbars = true
    st.tickers = true
    st.bossPreview = true
     MSUF_ScheduleApplyCommit()
 end
_G.ApplyAllSettings = _G.ApplyAllSettings or MSUF_ApplyAllSettings
_G.MSUF_ApplySettingsForKey_Immediate = _G.MSUF_ApplySettingsForKey_Immediate or function(key)
    if not key then  return end
    MSUF_MarkUnitFrameDirty(key)
    if MSUF_OptionsApplyCombatLocked() or (_G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked()) then
        local stUF = _G.MSUF_UnitFrameApplyState
        if stUF then
            stUF.queued = true
    end
        MSUF_RegisterApplyDirtyAfterCombat()
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
    if not MSUF_DB then MSUF_EnsureDB() end
    if MSUF_OptionsApplyCombatLocked() or (_G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked()) then
        MSUF_QueueApplyAllAfterCombat()
        return
    end
    -- Keep UnitframeCore caches + event masks in sync so settings apply immediately
    -- (fixes level/leader indicators and other cached-option regressions).
    if _G.MSUF_UFCore_NotifyConfigChanged then
        _G.MSUF_UFCore_NotifyConfigChanged(nil, false, true, "ApplyAllSettings_Immediate")
    end
    MSUF_ApplyUnitFrameKey_Immediate("player")
    MSUF_ApplyUnitFrameKey_Immediate("target")
    MSUF_ApplyUnitFrameKey_Immediate("focus")
    MSUF_ApplyUnitFrameKey_Immediate("targettarget")
    MSUF_ApplyUnitFrameKey_Immediate("focustarget")
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
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    if _G.MSUF_EnsureStatusIndicatorTicker then
        _G.MSUF_EnsureStatusIndicatorTicker()
    end
    if _G.MSUF_EnsureToTFallbackTicker then
        _G.MSUF_EnsureToTFallbackTicker()
    end
if _G.MSUF_RefreshSelfHealPredUnitEvent then
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
    if not st then return end
    if MSUF_OptionsApplyCombatLocked() or (_G.MSUF_IsUnitFramePositionLocked and _G.MSUF_IsUnitFramePositionLocked()) then
        MSUF_QueueApplyCommitAfterCombat()
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
            _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end
        -- Reanchor boss castbar position BEFORE updating the preview.
        -- Without this, boss castbar previews lose their anchor when boss
        -- frames reposition (e.g. spacing slider) and disappear.
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            _G.MSUF_ApplyBossCastbarPositionSetting()
        end
        if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
            and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
        then
            _G.MSUF_UpdateBossCastbarPreview()
    end
        -- Keep the castbar position popup synced if it is currently open.
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
            _G.MSUF_SyncCastbarPositionPopup("boss")
        end
    end
    if st.tickers then
        if _G.MSUF_EnsureStatusIndicatorTicker then _G.MSUF_EnsureStatusIndicatorTicker() end
        if _G.MSUF_EnsureToTFallbackTicker then _G.MSUF_EnsureToTFallbackTicker() end
    end
if _G.MSUF_RefreshSelfHealPredUnitEvent then
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
-- Font runtime moved to Core/MSUF_FontRuntime.lua.
-- Texture runtime moved to Core/MSUF_TextureRuntime.lua.
-- NudgeUnitFrameOffset removed (dead code)
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
        if not MSUF_DB then MSUF_EnsureDB() end
        local key = GetConfigKeyForUnit(unit)
        local conf = key and MSUF_DB and MSUF_DB[key]
         return key, conf
    end
    local function _ApplySnapAndClamp(key, conf)
        if not conf then return end
        local g = MSUF_DB and MSUF_DB.general or nil
        if g and g.editModeSnapToGrid == true then
            local gridStep = tonumber(g.editModeGridStep) or 20
            if gridStep < 8 then gridStep = 8 end
            if gridStep > 64 then gridStep = 64 end
            local half = gridStep / 2
            local x = tonumber(conf.offsetX) or 0
            local y = tonumber(conf.offsetY) or 0
            conf.offsetX = math.floor((x + half) / gridStep) * gridStep
            conf.offsetY = math.floor((y + half) / gridStep) * gridStep
        end
    end
    local function _UpdateDBFromFrame(self, key, conf)
        if not self or not conf or not key then return end
        local anchor = MSUF_ResolveConfiguredAnchorFrame(key, conf, MSUF_GetAnchorFrame and MSUF_GetAnchorFrame() or UIParent)
        if MSUF_ShouldSnapshotExternalAnchor(anchor) and not MSUF_IsExternalAnchorUsable(anchor) then
            anchor = UIParent
        end
        if not anchor or not anchor.GetCenter or not self.GetCenter then return end
        local _g = MSUF_DB and MSUF_DB.general
        if _g and _g.anchorToCooldown then
            local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer")) or (_G and _G["EssentialCooldownViewer"])
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
                        local fs = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
                        local as = (ecv.GetEffectiveScale and ecv:GetEffectiveScale()) or 1
                        if fs == 0 then fs = 1 end
                        if as == 0 then as = 1 end
                        local x = (fx2 * fs - ax2 * as) / as
                        local y = (fy2 * fs - ay2 * as) / as
                        conf.offsetX = math_floor(((x - baseX)) + 0.5)
                        conf.offsetY = math_floor(((y - extraY)) + 0.5)
                        if _G.MSUF_CacheUnitFrameScreenPosition then
                            _G.MSUF_CacheUnitFrameScreenPosition(self, key, unit, point)
                        end
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
        local fs = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
        local as = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
        if fs == 0 then fs = 1 end
        if as == 0 then as = 1 end
        local newX = (fx * fs - ax * as) / as
        local newY = (fy * fs - ay * as) / as
        if key == "boss" then
            local index = (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit)) or 1
            local spacing = conf.spacing or -36
            newY = newY - ((index - 1) * spacing)
    end
        conf.offsetX = math_floor((newX) + 0.5)
        conf.offsetY = math_floor((newY) + 0.5)
        if _G.MSUF_CacheUnitFrameScreenPosition then
            _G.MSUF_CacheUnitFrameScreenPosition(self, key, unit)
        end
        if MSUF_SyncUnitPositionPopup then
            MSUF_SyncUnitPositionPopup(unit, conf)
    end
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
    end
     end
    f:SetScript("OnMouseDown", function(self, button)
        if not MSUF_UnitEditModeActive then  return end
        if _msuf_inCombat then  return end
        self._msufClickButton = button
        self._msufDragDidStart = false
     end)
    f:SetScript("OnDragStart", function(self, button)
        if not MSUF_UnitEditModeActive then  return end
        if _msuf_inCombat then  return end
        local key, conf = _GetConfAndKey()
        if not key or not conf then  return end

        -- Undo: capture state BEFORE drag moves the frame
        if _G.MSUF_EM_UndoBeforeChange then
            _G.MSUF_EM_UndoBeforeChange("unit", key)
        end

        self._msufDragDidStart = true
        self._msufDragActive = true
        self._msufDragKey = key
        self._msufDragConf = conf
        _DisableClicks(self)
        self:StartMoving()
        self._msufDragAccum = 0
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
     end)
    f:SetScript("OnDragStop", function(self, button)
        if not self._msufDragActive then  return end
        self:StopMovingOrSizing()
        local key = self._msufDragKey
        local conf = self._msufDragConf
        self._msufDragActive = false
        self._msufDragKey = nil
        self._msufDragConf = nil
        self:SetScript("OnUpdate", nil)
        _RestoreClicks(self)
        if key and conf then
            _UpdateDBFromFrame(self, key, conf)
            _ApplySnapAndClamp(key, conf)
            -- Keep cachedConfig in sync so PositionUnitFrame reads the live DB
            -- table, not a stale ref from before a profile import/switch.
            self.cachedConfig = conf
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
        if _msuf_inCombat then  return end
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
    focustarget = { w = 180, h = 30, showName = true,  showHP = true,  showPower = false, isBoss = false, startHidden = false },
    pet =         { w = 220, h = 30, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
}
local MSUF_UNIT_CREATE_DEF_BOSS = { w = 220, h = 30, showName = true, showHP = true, showPower = true, isBoss = true, startHidden = true }
local MSUF_UNIT_TIP_FUNCS = {
    player = "MSUF_ShowPlayerInfoTooltip",
    target = "MSUF_ShowTargetInfoTooltip",
    focus = "MSUF_ShowFocusInfoTooltip",
    targettarget = "MSUF_ShowTargetTargetInfoTooltip",
    focustarget = "MSUF_ShowFocusTargetInfoTooltip",
    pet = "MSUF_ShowPetInfoTooltip",
}
local function MSUF_IsClassPowerAnchorUsable(cpContainer)
    if not cpContainer then return false end
    local bars = MSUF_DB and MSUF_DB.bars
    if bars and bars.showClassPower == false then return false end
    if cpContainer.IsShown and cpContainer:IsShown() then return true end
    if cpContainer._msufLayoutInitialized ~= true then return false end
    if cpContainer.GetNumPoints and cpContainer:GetNumPoints() <= 0 then return false end
    local w = (cpContainer.GetWidth and cpContainer:GetWidth()) or 0
    local h = (cpContainer.GetHeight and cpContainer:GetHeight()) or 0
    return w > 0 and h > 0
end

local function MSUF_ApplyPowerBarEmbedLayout(f)
    if not f or not f.hpBar then return end
    local pb = f.targetPowerBar
    if not pb then
        f._msufPowerBarReserved = nil
        ns.Cache.ClearStamp(f, "PBEmbedLayout")
         return
    end
    if not MSUF_DB then MSUF_EnsureDB() end
    local b = (MSUF_DB and MSUF_DB.bars) or {}
    local unit = f.unit
    local key = f.msufConfigKey
    if not key and GetConfigKeyForUnit then key = GetConfigKeyForUnit(unit) end
    if key then f.msufConfigKey = key end
    local inLockdown = (type(_G.MSUF_IsUnitFramePositionLocked) == "function" and _G.MSUF_IsUnitFramePositionLocked())
        or (InCombatLockdown and InCombatLockdown())
        or false
    if inLockdown and f._msufPowerBarLayoutInitialized == true then
        f._msufPowerBarLayoutDirty = true
        _G.MSUF_PowerBarLayoutDirty = true
        if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return
    end
    local layoutCache = type(_G.MSUF_GetProfileScopedCache) == "function" and _G.MSUF_GetProfileScopedCache("detachedPowerBarLayoutCache") or nil
    local readHeight = _G.MSUF_ReadUnitPowerBarHeight
    local h = (type(readHeight) == "function" and readHeight(key or unit)) or tonumber(b.powerBarHeight) or 3
    h = math.floor(h + 0.5)
    if h < 1 then h = 1 elseif h > 80 then h = 80 end
    local readEmbed = _G.MSUF_ReadUnitPowerBarEmbed
    local embed
    if type(readEmbed) == "function" then
        embed = readEmbed(key or unit)
    else
        embed = (b.embedPowerBarIntoHealth == true)
    end
    local readEnabled = _G.MSUF_ReadUnitPowerBarEnabled
    local enabled = false
    if type(readEnabled) == "function" then
        enabled = readEnabled(key or unit)
    elseif unit == 'player' then
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
    local dW, dH, dX, dY, dLevel = 0, 0, 0, 0, 6
    local anchorToCP = false
    if (unit == 'player' or unit == 'target' or unit == 'focus') then
        local conf = (key and MSUF_DB and MSUF_DB[key]) or nil
        if conf and conf.powerBarDetached == true then
            detached = true
            -- Manual width: DB â†’ actual unit frame width â†’ 250
            local fW = (f and f.GetWidth and math_floor(f:GetWidth() + 0.5)) or 0
            if fW < 30 then fW = math_floor((conf.width or 250) + 0.5) end
            dW = tonumber(conf.detachedPowerBarWidth) or fW
            dH = tonumber(conf.detachedPowerBarHeight) or 6
            dX = tonumber(conf.detachedPowerBarOffsetX) or 0
            dY = tonumber(conf.detachedPowerBarOffsetY) or -4
            dLevel = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
            if dLevel < 0 then dLevel = 0 elseif dLevel > 30 then dLevel = 30 end
            if unit == 'player' and conf.detachedPowerBarAnchorToClassPower == true then
                anchorToCP = true
            end
            -- CDM width sync (global setting overrides manual width)
            -- Per-unit sync flag takes precedence: when explicitly OFF, keep manual width.
            -- CDM override only meaningful for player (target/focus have no class resources).
            if unit == 'player' and conf.detachedPowerBarSyncClassPower ~= false then
                local dpbWMode = b.detachedPowerBarWidthMode
                local dpb = ns.Bars and ns.Bars._DetachedPowerBarTextures
                local cdmName = dpbWMode and dpb and dpb.CDM and dpb.CDM[dpbWMode]
                if cdmName then
                    local cacheKey = tostring(unit or "player") .. ":width:" .. cdmName
                    local cachedW = tonumber(f._msufDetachedPowerBarStableW) or (layoutCache and tonumber(layoutCache[cacheKey]))
                    if inLockdown and cachedW and cachedW >= 30 then
                        dW = cachedW
                    else
                        local cdm = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(cdmName)) or _G[cdmName]
                    -- Scale-compensated width (Sensei pattern): convert CDM coords â†’ our bar coords
                        if cdm and cdm.IsShown and cdm:IsShown() then
                            local scaledW = _G.MSUF_CDM_GetScaledWidth and _G.MSUF_CDM_GetScaledWidth(cdm, pb)
                            if scaledW and scaledW >= 30 then dW = scaledW end
                        end
                    end
                    -- If CDM hidden/unavailable, keep manual dW (from DB or frame width)
                end
            end
        end
    end

    local activeDetached = detached and enabled
    local reserve = (embed and not activeDetached and enabled and h > 0)
    local dpbWMode = (b.detachedPowerBarWidthMode or "")
    if activeDetached and dW and dW >= 20 then
        local stableW = math.floor(dW + 0.5)
        f._msufDetachedPowerBarStableW = stableW
        if not inLockdown and layoutCache then
            local dpb = ns.Bars and ns.Bars._DetachedPowerBarTextures
            local cdmName = dpb and dpb.CDM and dpb.CDM[dpbWMode]
            if cdmName then
                layoutCache[tostring(unit or "player") .. ":width:" .. cdmName] = stableW
            end
        end
    end
    local cpContainer = anchorToCP and _G["MSUF_ClassPowerContainer"] or nil
    local cpAnchorUsable = anchorToCP and MSUF_IsClassPowerAnchorUsable(cpContainer) or false
    if not ns.Cache.StampChanged(f, "PBEmbedLayout", (enabled and 1 or 0), (embed and 1 or 0), (reserve and 1 or 0), h, (activeDetached and 1 or 0), dW, dH, dX, dY, dLevel, (anchorToCP and 1 or 0), (cpAnchorUsable and 1 or 0), dpbWMode) then
        if not enabled then _MSUF_Bars_HidePower(pb, true) end
        if _G.MSUF_ApplyPowerBarBorder then
            _G.MSUF_ApplyPowerBarBorder(pb)
        end
        if _G.MSUF_FixHighlightForFrame then
            _G.MSUF_FixHighlightForFrame(f)
        end
        f._msufPowerBarLayoutInitialized = true
        f._msufPowerBarLayoutDirty = nil
        return
    end
    f._msufPowerBarReserved = reserve and true or nil
    f._msufPowerBarDetached = activeDetached and true or nil
    -- Force text layout to re-evaluate (power text may reparent to detached bar)
    f._msufTextLayoutStamp = nil
    ns.Cache.ClearStamp(f, "TextLayout")
    -- Force border system to re-evaluate when detach state changes
    f._msufBarOutlineThickness = -1
    f._msufBarOutlineBottomIsPower = nil
    f._msufHighlightBottomIsPower = nil
    local hb = f.hpBar
    hb:ClearAllPoints()
    hb:SetPoint('TOPLEFT', f, 'TOPLEFT', 2, -2)
    if reserve then
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2 + h)
    else
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    end
    pb:ClearAllPoints()
    if activeDetached then
        -- Detached: freely positioned relative to parent frame (overrides embed)
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        if dH < 2 then dH = 2 elseif dH > 80 then dH = 80 end
        pb:SetSize(dW, dH)
        if pb.SetFrameLevel and f.GetFrameLevel then
            pb:SetFrameLevel((f:GetFrameLevel() or 0) + dLevel)
        end
        -- Anchor to class power container (MRB energyâ†’combo pattern) or to unit frame
        if anchorToCP then
            if cpAnchorUsable and cpContainer then
                pb:SetPoint('TOP', cpContainer, 'BOTTOM', dX, dY)
            else
                -- Fallback: anchor to unit frame when CP not visible
                pb:SetPoint('TOPLEFT', f, 'BOTTOMLEFT', dX, dY)
            end
        else
            pb:SetPoint('TOPLEFT', f, 'BOTTOMLEFT', dX, dY)
        end
        -- Re-anchor power text on the resized bar when "text on bar" is active.
        -- Without this, CDM / edit-mode width changes wouldn't update text position
        -- because ApplyTextLayout only runs during full frame updates.
        local uKey = f.msufConfigKey
        local uConf = uKey and MSUF_DB and MSUF_DB[uKey]
        if uConf and uConf.detachedPowerBarTextOnBar == true then
            ApplyTextLayout(f, uConf)
        end
    elseif reserve then
        if pb.SetFrameLevel and hb.GetFrameLevel then pb:SetFrameLevel(hb:GetFrameLevel()) end
        pb:SetHeight(h)
        pb:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 2, 2)
        pb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    else
        if pb.SetFrameLevel and hb.GetFrameLevel then pb:SetFrameLevel(hb:GetFrameLevel()) end
        pb:SetHeight(h)
        pb:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', 0, 0)
        pb:SetPoint('TOPRIGHT', hb, 'BOTTOMRIGHT', 0, 0)
    end
    if not enabled then
        _MSUF_Bars_HidePower(pb, true)
    end
    if _G.MSUF_ApplyPowerBarBorder then
        _G.MSUF_ApplyPowerBarBorder(pb)
    end
    -- Re-anchor mouseover highlight after HP/power bars have their final points.
    if _G.MSUF_FixHighlightForFrame then
        _G.MSUF_FixHighlightForFrame(f)
    end

    -- Cold styling refresh after layout changes. Static outlines/borders are
    -- intentionally kept out of the power/health update path.
    local fnStaticOutlines = _G.MSUF_RefreshStaticUnitFrameOutlines
    if type(fnStaticOutlines) == "function" then
        fnStaticOutlines(f)
    end
    local fnRare = _G.MSUF_RefreshRareBarVisuals
    if type(fnRare) == "function" then
        fnRare(f)
    end
    f._msufPowerBarLayoutInitialized = true
    f._msufPowerBarLayoutDirty = nil
 end

_G.MSUF_ApplyPowerBarEmbedLayout = MSUF_ApplyPowerBarEmbedLayout
_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function(unitKey, refreshPower)
    if not UnitFrames then return end
    if _G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown()) then
        _G.MSUF_PowerBarLayoutDirty = true
        if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
            _G.MSUF_RequestUnitFrameReanchorAfterCombat()
        end
        return
    end
    local function applyOne(fr)
        if not (fr and fr.hpBar and fr.targetPowerBar) then return end
        if ns.Cache and ns.Cache.ClearStamp then ns.Cache.ClearStamp(fr, "PBEmbedLayout") end
        MSUF_ApplyPowerBarEmbedLayout(fr)
        if refreshPower and _G.MSUF_UFCore_UpdatePowerBarFast then
            _G.MSUF_UFCore_UpdatePowerBarFast(fr)
        end
        local fnStaticOutlines = _G.MSUF_RefreshStaticUnitFrameOutlines
        if type(fnStaticOutlines) == "function" then
            fnStaticOutlines(fr)
        end
    end
    if unitKey == "boss" then
        for i = 1, (MSUF_MAX_BOSS_FRAMES or 5) do applyOne(UnitFrames["boss" .. i]) end
    else
        applyOne(UnitFrames[unitKey])
    end
end
_G.MSUF_ApplyPowerBarEmbedLayout_All = function()
    if not UnitFrames then return end
    for _, fr in pairs(UnitFrames) do
        if fr and fr.hpBar and fr.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(fr)
    end
    end
    if type(_G.MSUF_ClassPower_RefreshCDMWidthBindings) == "function" then
        _G.MSUF_ClassPower_RefreshCDMWidthBindings(false)
    end
 end

local function _CreateSelfHealPredBar(f, hpBar)
    if not f or not hpBar or f.selfHealPredBar or f.incomingHealBar then return end
    -- Incoming heal prediction segment. Keep the old selfHealPred names as
    -- aliases because texture/reverse-fill runtime code still references them.
    local clip = _G.CreateFrame("Frame", nil, hpBar)
    clip:SetAllPoints(hpBar)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    f.selfHealPredClip = clip
    f.incomingHealClip = clip
    local bar = _G.CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture(MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.MSUF_lastValue = 0
    bar:SetFrameLevel(clip:GetFrameLevel())
    bar:SetStatusBarColor(0.0, 1.0, 0.4, 0.35)
    bar:Hide()
    f.selfHealPredBar = bar
    f.incomingHealBar = bar
    if hpBar and hpBar.GetReverseFill and bar.SetReverseFill then
        local rf = hpBar:GetReverseFill()
        if rf ~= nil then bar:SetReverseFill(rf and true or false) end
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
    local baseSize = (g2 and g2.fontSize) or 14
    local nameSize = (g2 and g2.nameFontSize) or baseSize
    local clsSize = (conf and conf.classificationIndicatorSize) or (conf and conf.nameFontSize) or nameSize
    if type(clsSize) ~= "number" then clsSize = nameSize end
    clsSize = math.floor(math.max(8, math.min(64, clsSize)) + 0.5)
    if fs.SetFont and type(fontPath) == "string" and fontPath ~= "" then
        fs:SetFont(fontPath, clsSize, flags)
    end
    if fs.SetTextColor then fs:SetTextColor(fr or 1, fg or 1, fb or 1, 1) end
    if (g2 and g2.textBackdrop == true) and fs.SetShadowColor and fs.SetShadowOffset then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    elseif fs.SetShadowOffset then
        fs:SetShadowOffset(0, 0)
    end
    fs:Hide()
    f.classificationIndicatorText = fs
end

local function CreateSimpleUnitFrame(unit)
    if not MSUF_DB then MSUF_EnsureDB() end
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
    if _G.MSUF_ApplyInitialFrameScale then
        _G.MSUF_ApplyInitialFrameScale(f)
    end
    PositionUnitFrame(f, unit)
    MSUF_EnableUnitFrameDrag(f, unit)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    local bg = ns.UF.MakeTex(f, "bg", "self", "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    local hpBar = ns.UF.MakeBar(f, "hpBar", "self")
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2); hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture(MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(0); hpBar.MSUF_lastValue = 0
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
    _CreateSelfHealPredBar(f, hpBar)
    f.absorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 2, MSUF_GetAbsorbOverlayColor(), true)
    f.healAbsorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 3, MSUF_GetHealAbsorbOverlayColor(), false)
    ns.Bars.SetOverlayBarTexture(f.absorbBar, MSUF_GetAbsorbBarTexture)
    ns.Bars.SetOverlayBarTexture(f.healAbsorbBar, MSUF_GetHealAbsorbBarTexture)
    -- Layered alpha requires per-texture alpha; MSUF unitframes support it.
    f._msufAlphaSupportsLayered = true
    if unit == "player" or unit == "focus" or unit == "target" or isBossUnit then
        local pBar = ns.UF.MakeBar(f, "targetPowerBar", "self")
        pBar:SetStatusBarTexture(MSUF_GetBarTexture())
        local readHeight = _G.MSUF_ReadUnitPowerBarHeight
        local h = (type(readHeight) == "function" and readHeight(key)) or ((MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.powerBarHeight) == "number" and MSUF_DB.bars.powerBarHeight > 0) and MSUF_DB.bars.powerBarHeight) or 3
        pBar:SetHeight(h)
        pBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, 0); pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetMinMaxValues(0, 1)
        pBar:SetValue(0); pBar.MSUF_lastValue = 0
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
                local tex = (ns.UF.MakeLayeredTex or ns.UF.MakeTex)(f, key, parentKey, layer, sub)
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
        -- Elite / Rare icon (target, focus, targettarget, boss)
        local _eliteUnitKey = (type(unit) == "string" and unit:sub(1,4) == "boss") and "boss" or unit
        local _eliteValidUnits = ns.MSUF_EliteValidUnits
        if _eliteValidUnits and _eliteValidUnits[_eliteUnitKey] and not f.eliteIcon then
            local tex = (ns.UF.MakeLayeredTex or ns.UF.MakeTex)(f, "eliteIcon", "textFrame", "OVERLAY", 7)
            tex:SetSize(20, 20)
            tex:Hide()
            if _G.MSUF_ApplyEliteIconLayout then
                _G.MSUF_ApplyEliteIconLayout(f)
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
    highlight:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    highlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    highlight._msufHoverEdgeSize = 1
    do
        local baseLevel = 0
        if f.GetFrameLevel then baseLevel = f:GetFrameLevel() or 0 end
        if f.hpBar and f.hpBar.GetFrameLevel then
            local hb = f.hpBar:GetFrameLevel() or 0
            if hb > baseLevel then baseLevel = hb end
    end
        highlight:SetFrameLevel(baseLevel + 2)
    end
    highlight:EnableMouse(false)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    if _G.MSUF_FixHighlightForFrame then
        _G.MSUF_FixHighlightForFrame(f)
    end
    highlight:Hide()
    f.UpdateHighlightColor = ns.UF.UpdateHighlightColor
    f:SetScript("OnEnter", ns.UF.Unitframe_OnEnter)
    f:SetScript("OnLeave", ns.UF.Unitframe_OnLeave)
    -- Clique / click-casting: register AFTER OnEnter/OnLeave are set.
    -- Clique wraps these scripts; if we register before they exist, Clique
    -- has nothing to wrap and our later SetScript overwrites its hooks.
    ns.UF.RegisterClickCastFrame(f, true)
    if f.targetPowerBar and f.hpBar then
        MSUF_ApplyPowerBarEmbedLayout(f)
    end
    ns.Bars._ApplyReverseFillBars(f, conf)
    ns.UF.RequestUpdate(f, true, true, "F.CreateFrame")
    -- Auras2 must be primed on unitframe creation; do NOT rely on a later UNIT_AURA burst.
    -- This prevents the "auras only start after Edit Mode / toggle" regression.
    if _G.MSUF_A2_RequestUnit then
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
        if not MSUF_DB then MSUF_EnsureDB() end
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
    local function _MSUF_TargetSound_OnTargetChanged_Bus()
        MSUF_TargetSoundDriver_OnTargetChanged()
    end
    local function MSUF_TargetSoundDriver_Ensure()
        if _msufTargetSoundFrame then
             return
    end
        -- Use EventBus instead of dedicated frame
        _msufTargetSoundFrame = true -- sentinel to prevent re-entry
        MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_TARGET_SOUND", _MSUF_TargetSound_OnTargetChanged_Bus)
        MSUF_TargetSoundDriver_ResetState()
     end
    _G.MSUF_TargetSoundDriver_Ensure = MSUF_TargetSoundDriver_Ensure
    _G.MSUF_TargetSoundDriver_ResetState = MSUF_TargetSoundDriver_ResetState
end
MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_STARTUP", function(event)
    MSUF_InitProfiles()
    if not MSUF_DB then MSUF_EnsureDB() end
    do
        local g = (MSUF_DB and MSUF_DB.general) or {}
        if g.playTargetSelectLostSounds == true and _G.MSUF_TargetSoundDriver_Ensure then
            _G.MSUF_TargetSoundDriver_Ensure()
    end
    end
    HideDefaultFrames = _G.MSUF_HideDefaultFrames
    if HideDefaultFrames then HideDefaultFrames() end
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
    CreateSimpleUnitFrame("focus")
    CreateSimpleUnitFrame("targettarget")
    CreateSimpleUnitFrame("focustarget")
    CreateSimpleUnitFrame("pet")
    if type(_G.MSUF_RefreshFocusTargetLifecycle) == "function" then
        _G.MSUF_RefreshFocusTargetLifecycle("PLAYER_LOGIN")
    end
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        CreateSimpleUnitFrame("boss" .. i)
    end
    MSUF_ForceReanchorAllUnitFrames_Once()
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
    if _G.MSUF_Auras2_RefreshAll then
        _G.MSUF_Auras2_RefreshAll()
    end

-- Heal prediction: refresh UnitFrame event registration when prediction toggles
-- change, and keep a small player event bridge for legacy update paths.
-- MAX performance path: register UNIT_* directly with RegisterUnitEvent (oUF-style).
-- Secret-safe: no comparisons/arithmetic on potential secret values.
if type(_G.MSUF_RefreshSelfHealPredUnitEvent) ~= "function" then
    _G.MSUF_RefreshSelfHealPredUnitEvent = function()
        local g = (MSUF_DB and MSUF_DB.general) or nil
        local want = false
        if g then
            if g.showSelfHealPrediction ~= nil then
                want = g.showSelfHealPrediction == true
            elseif g.enableHealPrediction ~= nil then
                want = g.enableHealPrediction ~= false
            end
        end

        local fr = _G.MSUF_SelfHealPredUnitFrame
        if not fr and not want then return end
        if not fr then
            fr = F.CreateFrame("Frame")
            fr:Hide()
            fr._msufReg = false
            fr:SetScript("OnEvent", function(self, event, unit)
                -- P0: Use file-scope upvalue; issecretvalue resolved at load
                local isSecret = _MSUF_issecretvalue
                if not isSecret then
                    isSecret = _G.issecretvalue
                    if isSecret then _MSUF_issecretvalue = isSecret end
                end
                if isSecret and isSecret(unit) then return end
                if unit ~= "player" then return end
                local gg = (MSUF_DB and MSUF_DB.general) or nil
                local enabled = false
                if gg then
                    if gg.showSelfHealPrediction ~= nil then
                        enabled = gg.showSelfHealPrediction == true
                    elseif gg.enableHealPrediction ~= nil then
                        enabled = gg.enableHealPrediction ~= false
                    end
                end
                if not enabled then return end
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
        if UnitFrames then
            local hideHealPred = ns and ns.Bars and ns.Bars._HideSelfHealPrediction
            for _, uf in pairs(UnitFrames) do
                if uf and (uf.incomingHealBar or uf.selfHealPredBar) then
                    uf._msufHealPredEnCached = want and true or false
                    if not want and type(hideHealPred) == "function" then
                        hideHealPred(uf)
                    end
                end
            end
        end
        local refreshEvents = _G.MSUF_UFCore_RefreshAllUnitEvents
        if type(refreshEvents) == "function" then
            refreshEvents(true)
        end
    end
end
if _G.MSUF_RefreshSelfHealPredUnitEvent then
    _G.MSUF_RefreshSelfHealPredUnitEvent()
end

    if _G.MSUF_RangeFade_InitPostLogin then
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
            if not tot or not tot.IsShown or not tot:IsShown() then return end
            local key = GetConfigKeyForUnit and GetConfigKeyForUnit("targettarget")
            local conf = key and MSUF_DB and MSUF_DB[key]
            if ns.UF.IsDisabled(conf) then return end
            if not (F.UnitExists and F.UnitExists("targettarget")) then return end
            if not force and not tot._msufToTDirty then return end
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
    -- Immediately inherit font from nameText (master) so ToT inline never
    -- displays with the wrong GameFontHighlight size.  Invalidate _msufFontRev
    -- so the central font cache re-applies cleanly on the next pass.
    local nameFS = targetFrame.nameText
    if nameFS and nameFS.GetFont then
        local font, size, flags = nameFS:GetFont()
        if font then
            sep:SetFont(font, size, flags)
            txt:SetFont(font, size, flags)
            local sr, sg, sb, sa = nameFS:GetShadowColor()
            local sox, soy = nameFS:GetShadowOffset()
            sep:SetShadowColor(sr or 0, sg or 0, sb or 0, sa or 0)
            sep:SetShadowOffset(sox or 0, soy or 0)
            txt:SetShadowColor(sr or 0, sg or 0, sb or 0, sa or 0)
            txt:SetShadowOffset(sox or 0, soy or 0)
            sep._msufFontRev = nil
            txt._msufFontRev = nil
            sep._msufShadowOn = nil
            txt._msufShadowOn = nil
        end
    end
    targetFrame._msufToTInlineSep = sep
    targetFrame._msufToTInlineText = txt
 end
local MSUF_TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local MSUF_TOT_INLINE_CUSTOM_SEPARATOR_MAX = 5
local MSUF_TOT_INLINE_PRESET_SEPARATOR = {
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
local function MSUF_TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end

    local bytePos = 1
    local valueLen = #value
    local chars = 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string.byte(value, bytePos)
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
    return string.sub(value, 1, bytePos - 1)
end
local function MSUF_CleanToTInlineCustomSeparator(value)
    value = tostring(value or ""):gsub("[%c]", " ")
    return MSUF_TruncateUtf8Chars(value, MSUF_TOT_INLINE_CUSTOM_SEPARATOR_MAX)
end
local MSUF_ToTInlineSanitizedConf
local MSUF_ToTInlineSanitizedSeparator
local MSUF_ToTInlineSanitizedCustom
local function MSUF_SanitizeToTInlineConf(conf)
    if not conf then return end
    local separator = conf.totInlineSeparator
    local custom = conf.totInlineCustomSeparator
    if MSUF_ToTInlineSanitizedConf == conf
        and MSUF_ToTInlineSanitizedSeparator == separator
        and MSUF_ToTInlineSanitizedCustom == custom
    then
        return
    end

    conf.totInlineCustomSeparator = MSUF_CleanToTInlineCustomSeparator(custom)
    if separator ~= MSUF_TOT_INLINE_CUSTOM_SEPARATOR and not MSUF_TOT_INLINE_PRESET_SEPARATOR[separator] then
        conf.totInlineCustomSeparator = MSUF_CleanToTInlineCustomSeparator(separator)
        conf.totInlineSeparator = MSUF_TOT_INLINE_CUSTOM_SEPARATOR
    end

    MSUF_ToTInlineSanitizedConf = conf
    MSUF_ToTInlineSanitizedSeparator = conf.totInlineSeparator
    MSUF_ToTInlineSanitizedCustom = conf.totInlineCustomSeparator
end
function MSUF_RuntimeUpdateTargetToTInline(targetFrame)
    if not targetFrame or not targetFrame.nameText then return end
    if not MSUF_DB then MSUF_EnsureDB() end
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
    if MSUF_DB.targettarget.totInlineCustomSeparator == nil and type(MSUF_DB.target) == "table" and type(MSUF_DB.target.totInlineCustomSeparator) == "string" then
        MSUF_DB.targettarget.totInlineCustomSeparator = MSUF_DB.target.totInlineCustomSeparator
    end
    MSUF_SanitizeToTInlineConf(MSUF_DB.targettarget)
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
        if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("TOT_INLINE_FLUSH", _MSUF_ToTInline_Flush) else C_Timer.After(0, _MSUF_ToTInline_Flush) end
     end
    _G.MSUF_ToTInline_RequestRefresh = ns.MSUF_ToTInline_RequestRefresh
end
        if not _G.MSUF_UFCore_HasToTInlineDriver then
        local f = F.CreateFrame("Frame")
        -- PLAYER_TARGET_CHANGED removed: consolidated in UFCore handler
        if f.RegisterUnitEvent then
            f:RegisterUnitEvent("UNIT_TARGET", "target")
            f:RegisterUnitEvent("UNIT_HEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_MAXHEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_POWER_UPDATE", "targettarget")
            -- Smooth power updates (energy/rage/etc.)
            f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "targettarget")
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
            f:RegisterEvent("UNIT_POWER_FREQUENT")
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
        -- Export for consolidated TARGET_CHANGED handler in UFCore
        _G.MSUF_ToT_OnTargetChanged = function()
            MSUF_MarkToTDirty()
            if C_Timer and C_Timer.After then
                if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("TOT_EVENT_FLUSH", MSUF_ToTFlushScheduled) else C_Timer.After(0, MSUF_ToTFlushScheduled) end
            else
                MSUF_TryUpdateToT(false)
            end
        end
        f:SetScript("OnEvent", function(self, event, unit)
            if unit and unit ~= "target" and unit ~= "targettarget" then
                 return
            end
            MSUF_MarkToTDirty()
            if not self._msufPending and C_Timer and C_Timer.After then
                self._msufPending = true
                MSUF_ToTEventFramePending = self
                if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("TOT_EVENT_FLUSH", MSUF_ToTFlushScheduled) else C_Timer.After(0, MSUF_ToTFlushScheduled) end
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
if _G.MSUF_ApplyAllSettings_Immediate then
    _G.MSUF_ApplyAllSettings_Immediate()
else
    MSUF_ApplyAllSettings()
end
-- P0: Pre-resolve split-module function refs for UpdateSimpleUnitFrame.
-- After PLAYER_LOGIN all Core/ files have loaded. Eliminates branches
-- + _G hash lookups per frame update (300-1500 branches/sec in combat).
do
    _UF.Alpha    = _G.MSUF_ApplyUnitAlpha              or _UF.Alpha
    _UF.Portrait = _G.MSUF_MaybeUpdatePortrait          or _UF.Portrait
    _UF.EditPrev = _G.MSUF_ApplyUnitframeEditPreview    or _UF.EditPrev
    _UF.BossPrev = _G.MSUF_ApplyBossTestHpPreviewText   or _UF.BossPrev
    _UF.HpText   = _G.MSUF_UFCore_UpdateHpTextFast      or _UF.HpText
    _UF.PwrText  = _G.MSUF_UFCore_UpdatePowerTextFast   or _UF.PwrText
    _UF.PwrBar   = _G.MSUF_UFCore_UpdatePowerBarFast    or _UF.PwrBar
    _UF.QueueVis = _G.MSUF_QueueUnitframeVisual         or _UF.QueueVis
    _UF.LeaderIcon = _G.MSUF_ApplyLeaderIconLayout      or _UF.LeaderIcon
    _UF.RaidMarker = _G.MSUF_ApplyRaidMarkerLayout      or _UF.RaidMarker
    -- Frames can be drawn before this local is resolved; repair load-time HP alpha.
    if _G.MSUF_RefreshAllUnitAlphas then _G.MSUF_RefreshAllUnitAlphas() end
end
    if _G.MSUF_ReanchorTargetCastBar then
        _G.MSUF_ReanchorTargetCastBar()
    end
    if _G.MSUF_ReanchorFocusCastBar then
        _G.MSUF_ReanchorFocusCastBar()
    end
    if type(_G.MSUF_FocusKick_EnsureInitialized) == "function" then
        local gg = (MSUF_DB and MSUF_DB.general) or nil
        if gg and gg.enableFocusKickIcon == true then
            _G.MSUF_FocusKick_EnsureInitialized(true)
        end
    elseif MSUF_InitFocusKickIcon then
        MSUF_InitFocusKickIcon()
    end

    local _msufTargetReanchorPending = false
    local _msufFocusReanchorPending = false
    local function _MSUF_TargetReanchorFlush()
        _msufTargetReanchorPending = false
        local fn = _G.MSUF_ReanchorTargetCastBar
        if type(fn) == "function" then
            fn()
        end
    end
    local function _MSUF_FocusReanchorFlush()
        _msufFocusReanchorPending = false
        local fn = _G.MSUF_ReanchorFocusCastBar
        if type(fn) == "function" then
            fn()
        end
    end
    local function _MSUF_ScheduleTargetReanchor()
        if _msufTargetReanchorPending then return end
        _msufTargetReanchorPending = true
        C_Timer.After(0, _MSUF_TargetReanchorFlush)
    end
    local function _MSUF_ScheduleFocusReanchor()
        if _msufFocusReanchorPending then return end
        _msufFocusReanchorPending = true
        C_Timer.After(0, _MSUF_FocusReanchorFlush)
    end

    if TargetFrameSpellBar and not TargetFrameSpellBar.MSUF_Hooked then
        TargetFrameSpellBar.MSUF_Hooked = true
        TargetFrameSpellBar:HookScript("OnShow", function()
            _MSUF_ScheduleTargetReanchor()
         end)
        TargetFrameSpellBar:HookScript("OnEvent", function(_, event, unit)
            if unit and unit ~= "target" then return end
            if event == "UNIT_SPELLCAST_START"
                or event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_CHANNEL_START"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP"
                or event == "UNIT_SPELLCAST_INTERRUPTED"
                or event == "PLAYER_TARGET_CHANGED" then
                _MSUF_ScheduleTargetReanchor()
            end
         end)
    end
    if FocusFrameSpellBar and not FocusFrameSpellBar.MSUF_Hooked then
        FocusFrameSpellBar.MSUF_Hooked = true
        FocusFrameSpellBar:HookScript("OnShow", function()
            _MSUF_ScheduleFocusReanchor()
         end)
        FocusFrameSpellBar:HookScript("OnEvent", function(_, event, unit)
            if unit and unit ~= "focus" then return end
            if event == "UNIT_SPELLCAST_START"
                or event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_CHANNEL_START"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP"
                or event == "UNIT_SPELLCAST_INTERRUPTED"
                or event == "PLAYER_FOCUS_CHANGED" then
                _MSUF_ScheduleFocusReanchor()
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
    if type(_G.MSUF_OpenStandaloneOptionsWindow) ~= "function" and type(_G.MSUF2_Open) ~= "function" then
        if not _G.MSUF_OptionsPanelMissingWarned then
            _G.MSUF_OptionsPanelMissingWarned = true
            print("|cffff0000MSUF:|r Menu2 options are not loaded. Check your .toc includes Menu2/MSUF_Menu2_Core.lua.")
    end
    end
	    if _G.MSUF_CheckAndRunFirstSetup then
	        _G.MSUF_CheckAndRunFirstSetup()
	    end
	    if type(_G.MSUF_HookCooldownViewer) == "function" then
	        C_Timer.After(1, _G.MSUF_HookCooldownViewer)
	    end
    if type(ns.Castbars._InitPlayerCastbarPreviewToggle) == "function" then
        C_Timer.After(1.1, ns.Castbars._InitPlayerCastbarPreviewToggle)
    end
    local postLoginFullApplied = false
    local function MSUF_PostLoginReconcile(fullAllowed)
        if MSUF_OptionsApplyCombatLocked() then return end
        if fullAllowed ~= false and not postLoginFullApplied then
            local didFullWork = false
            if type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
                _G.MSUF_ApplyAllSettings_Immediate()
                didFullWork = true
            end
            if type(_G.MSUF_RefreshAllUnitAlphas) == "function" then
                _G.MSUF_RefreshAllUnitAlphas()
                didFullWork = true
            end
            if type(_G.MSUF_RangeFade_EvaluateActive) == "function" then
                _G.MSUF_RangeFade_EvaluateActive(true)
                didFullWork = true
            end
            if type(_G.MSUF_RangeFadeFB_EvaluateActive) == "function" then
                _G.MSUF_RangeFadeFB_EvaluateActive(true)
                didFullWork = true
            end
            postLoginFullApplied = didFullWork
        end
        if type(_G.MSUF_GF_ReconcileLiveFrames) == "function" then
            _G.MSUF_GF_ReconcileLiveFrames()
        elseif type(_G.MSUF_GF_RebuildAll) == "function" then
            _G.MSUF_GF_RebuildAll()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() MSUF_PostLoginReconcile(false) end)
        C_Timer.After(0.20, function() MSUF_PostLoginReconcile(true) end)
        C_Timer.After(0.80, function() MSUF_PostLoginReconcile(true) end)
    end
    if not MSUF_DB or not MSUF_DB.general or MSUF_DB.general.showWelcomeMessage ~= false then
        print("|cff7aa2f7MSUF|r: |cffc0caf5/msuf|r |cff565f89to open options|r  |cff565f89|r |cffc0caf5 Thank you for using MSUF -|r  |cfff7768eReport bugs in the Discord.|r")
    end
 end, nil, true)
-- BucketUpdate system removed (was only used for EditDrag, now uses direct OnUpdate).
-- Keep no-op stubs in case any external addon references these.
_G.MSUF_RegisterBucketUpdate = _G.MSUF_RegisterBucketUpdate or function() end
_G.MSUF_UnregisterBucketUpdate = _G.MSUF_UnregisterBucketUpdate or function() end
do
    ns.Util.EnsureUnitFlags  = ns.Util.EnsureUnitFlags  or MSUF_EnsureUnitFlags
    ns.Util.IsTargetLikeFrame= ns.Util.IsTargetLikeFrame or MSUF_IsTargetLikeFrame
    ns.Bars.ResetBarZero     = ns.Bars.ResetBarZero     or MSUF_ResetBarZero
    ns.Text.ClearText        = ns.Text.ClearText        or MSUF_ClearText
end

-- Swap Recolor hook. The event driver lives in Core/MSUF_SwapRecolor.lua; this
-- tiny bridge stays here because it needs the local MSUF_UFStep_HeavyVisual.
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
    MSUF_UFStep_HeavyVisual(frame, unit, key)
end

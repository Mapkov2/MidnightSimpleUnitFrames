-- Core/MSUF_Castbars.lua — Castbar utility functions, textures, and visuals
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, ipairs, pairs = type, tonumber, ipairs, pairs
local string_format = string.format
local LSM = (ns and ns.LSM) or _G.MSUF_LSM or (LibStub and LibStub("LibSharedMedia-3.0", true))
local FONT_LIST = _G.MSUF_FONT_LIST

-- ══════════════════════════════════════════════════════════════
-- Castbar unit info, textures, style cache, font helpers
-- ══════════════════════════════════════════════════════════════
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
    if not i then  return 0, 0 end
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
    if not frame then  return nil end
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
    if not key then  return end
    if not MSUF_DB then EnsureDB() end
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
    if not unitKey then  return end
    if not MSUF_DB then EnsureDB() end
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
    if not MSUF_DB then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    local g = MSUF_DB.general or {}
    MSUF_DB.general = g
    local key = g.fontKey
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
    if not MSUF_DB then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if g.noOutline then
         return ""              -- kein OUTLINE / THICKOUTLINE
    elseif g.boldText then
         return "THICKOUTLINE"  -- fetter schwarzer Rand
    else
         return "OUTLINE"       -- normaler dÃƒÆ’Ã‚Â¼nner Rand
    end
 end
function ns.MSUF_GetGlobalFontSettings()
    if not MSUF_DB then EnsureDB() end
    local g = MSUF_DB.general or {}
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()
    local fr, fg, fb = ns.MSUF_GetConfiguredFontColor()
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
    local cache = _G.MSUF_CastbarTextureCache
    if not cache then
        cache = {}
        _G.MSUF_CastbarTextureCache = cache
    end
    local ck = (castKey or "") .. "|" .. (barKey or "")
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
_G.MSUF_GetCastbarTexture = MSUF_GetCastbarTexture
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
    local cache = _G.MSUF_CastbarBackgroundTextureCache
    if not cache then
        cache = {}
        _G.MSUF_CastbarBackgroundTextureCache = cache
    end
    local ck = key or ""
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
_G.MSUF_GetCastbarBackgroundTexture = MSUF_GetCastbarBackgroundTexture
_G.MSUF_GetCastbarBackgroundTexture = MSUF_GetCastbarBackgroundTexture
local function MSUF_IsCastTimeEnabled(frame)
    local g = MSUF_DB and MSUF_DB.general
    if not (frame and frame.unit and g) then  return true end
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
    local ck = (dir == "RTL" and 4 or 0) + (uni and 2 or 0) + (isChanneled and 1 or 0)
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
    local tex = MSUF_GetCastbarTexture()
    if not tex or tex == "" then
        tex = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    cache.texture = tex
    local bgTex = MSUF_GetCastbarBackgroundTexture()
    if not bgTex or bgTex == "" then
        bgTex = tex
    end
    cache.bgTexture = bgTex
    cache.reverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
    cache.reverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
    _G.MSUF_GlobalCastbarStyleCache = cache
     return cache
end
function MSUF_RefreshCastbarStyleCache(frame)
    if not frame then  return end
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
        base = MSUF_GetCastbarReverseFill(isChanneled) or false
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
    if not tex then  return end
    local bgTex = tex
    local t2 = MSUF_GetCastbarBackgroundTexture()
    if t2 and t2 ~= "" then
        bgTex = t2
    end
    local function Apply(frame)
        if frame and frame.statusBar then
            frame.statusBar:SetStatusBarTexture(tex)
            local sbt = frame.statusBar:GetStatusBarTexture()
            if sbt then sbt:SetHorizTile(true) end
            frame.MSUF_castbarStyleRev = __msufStyleRev
            frame.MSUF_cachedCastbarTexture = tex
            frame.MSUF_cachedReverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
            frame.MSUF_cachedReverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
            if not MSUF_DB then EnsureDB() end; local _g = MSUF_DB and MSUF_DB.general; frame.MSUF_cachedUnifiedDirection = (_g and _g.castbarUnifiedDirection) == true
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
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barTexture
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetBarBackgroundTexture()
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barBackgroundTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetAbsorbBarTexture()
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.absorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetHealAbsorbBarTexture()
    if not MSUF_DB then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.healAbsorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end

-- ══════════════════════════════════════════════════════════════
-- Castbar preview toggle
-- ══════════════════════════════════════════════════════════════
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
        if not MSUF_DB then EnsureDB() end
        local g       = MSUF_DB.general or {}
        local active  = g.castbarPlayerPreviewEnabled and true or false
        if active then
            btn:SetText("Castbar Edit Mode: ON")
        else
            btn:SetText("Castbar Edit Mode: OFF")
    end
     end
    btn:SetScript("OnClick", function(self)
        if not MSUF_DB then EnsureDB() end
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
            print("|cffffd700MSUF:|r Castbar Edit Mode |cff00ff00ON|r drag player/target/focus castbars with the mouse.")
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

-- ══════════════════════════════════════════════════════════════
-- UpdateCastbarVisuals (global font/icon/texture refresh)
-- ══════════════════════════════════════════════════════════════
function MSUF_UpdateCastbarVisuals()
MSUF_BumpCastbarStyleRevision()
    if not MSUF_DB then EnsureDB() end
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
    elseif type(ns.MSUF_GetConfiguredFontColor) == "function" then
        fr, fg, fb = ns.MSUF_GetConfiguredFontColor()
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
        if not frame then  return end
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
        if not frame or not frame.statusBar then  return end
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

-- Export font helpers for main file (UpdateAllFonts, etc.)
ns.Castbars = ns.Castbars or {}
ns.Castbars._GetFontPath = MSUF_GetFontPath
ns.Castbars._GetFontFlags = MSUF_GetFontFlags
ns.Castbars._InitPlayerCastbarPreviewToggle = MSUF_InitPlayerCastbarPreviewToggle

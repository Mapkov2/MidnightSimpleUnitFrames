-- MSUF_GF_Render.lua — Group Frames Phase 3: Visual Pipeline
-- Coalesced dirty-flag refresh: multiple DB writes → 1 visual update per frame per tick.
-- Bar textures, backgrounds, borders, fonts, text layout, geometry, health colors.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local C_Timer = _G.C_Timer
local UnitExists = _G.UnitExists
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local bor  = (bit and bit.bor)  or function(a, b) return a + b - (a % (b + b) >= b and b or 0) end
local band = (bit and bit.band) or function(a, b) if a % (b + b) >= b then return b else return 0 end end
local pairs = pairs
local type = type
local tonumber = tonumber
local math_max = math.max

------------------------------------------------------------------------
-- Dirty bits (bitmask, combinable via bor)
------------------------------------------------------------------------
local DIRTY_GEOMETRY = 0x01   -- size, powerHeight
local DIRTY_TEXTURE  = 0x02   -- bar texture / background
local DIRTY_FONT     = 0x04   -- font path / size / outline / color
local DIRTY_COLOR    = 0x08   -- health color mode, bg, power color
local DIRTY_BORDER   = 0x10   -- border enable / size / color, aggro/target border style
local DIRTY_LAYOUT   = 0x20   -- text anchors, icon positions
local DIRTY_ALL      = 0x3F

GF.DIRTY_GEOMETRY = DIRTY_GEOMETRY
GF.DIRTY_TEXTURE  = DIRTY_TEXTURE
GF.DIRTY_FONT     = DIRTY_FONT
GF.DIRTY_COLOR    = DIRTY_COLOR
GF.DIRTY_BORDER   = DIRTY_BORDER
GF.DIRTY_LAYOUT   = DIRTY_LAYOUT
GF.DIRTY_ALL      = DIRTY_ALL

------------------------------------------------------------------------
-- Dirty queue + coalesced flush
------------------------------------------------------------------------
local _dirtyFrames = {}   -- [frame] = bitfield
local _flushScheduled = false

local function _DoFlush()
    _flushScheduled = false
    GF._FlushDirty()
end
local function ScheduleFlush()
    if _flushScheduled then return end
    _flushScheduled = true
    C_Timer.After(0, _DoFlush)
end

------------------------------------------------------------------------
-- Apply: bar textures + gradient overlays
------------------------------------------------------------------------
local ApplyGradient   -- forward decl (defined after ApplyBarTexture)
local function ApplyBarTexture(f, kind)
    local tex   = GF.ResolveBarTexture(kind)
    local bgTex = GF.ResolveBarBgTexture(kind)

    if f.health and f.health.SetStatusBarTexture then
        if f._msufGFCachedHTex ~= tex then
            f.health:SetStatusBarTexture(tex)
            f._msufGFCachedHTex = tex
        end
    end
    if f.healthBg then
        if f._msufGFCachedHBgTex ~= bgTex then
            f.healthBg:SetTexture(bgTex)
            f._msufGFCachedHBgTex = bgTex
        end
    end
    if f.power and f.power.SetStatusBarTexture then
        if f._msufGFCachedPTex ~= tex then
            f.power:SetStatusBarTexture(tex)
            f._msufGFCachedPTex = tex
        end
    end
    if f.powerBg then
        if f._msufGFCachedPBgTex ~= bgTex then
            f.powerBg:SetTexture(bgTex)
            f._msufGFCachedPBgTex = bgTex
        end
    end
    -- Overlay bars use global absorb textures when available, else health texture
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local absorbTex = tex
    local healAbsorbTex = tex
    if gen then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            local aKey = gen.absorbBarTexture
            if aKey and aKey ~= "" then
                local p = resolve(aKey)
                if p then absorbTex = p end
            end
            local haKey = gen.healAbsorbBarTexture
            if haKey and haKey ~= "" then
                local p = resolve(haKey)
                if p then healAbsorbTex = p end
            end
        end
    end
    if f.incomingHealBar and f.incomingHealBar.SetStatusBarTexture then
        f.incomingHealBar:SetStatusBarTexture(tex)
    end
    if f.absorbBar and f.absorbBar.SetStatusBarTexture then
        f.absorbBar:SetStatusBarTexture(absorbTex)
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetStatusBarTexture then
        f.healAbsorbBar:SetStatusBarTexture(healAbsorbTex)
    end

    -- Gradient overlays (reads from MSUF_DB.general — same source as main UF)
    ApplyGradient(f)
end

------------------------------------------------------------------------
-- Gradient overlays: lazy-create + apply from MSUF_DB.general
-- Mirrors main UF gradient system (4-directional, per-edge toggles)
------------------------------------------------------------------------
local function _GF_MakeGradTex(bar)
    local t = bar:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    t:SetBlendMode("BLEND")
    t:Hide()
    return t
end

local function _GF_EnsureGradients(bar)
    if bar._msufGFGrads then return bar._msufGFGrads end
    local g = {
        left  = _GF_MakeGradTex(bar),
        right = _GF_MakeGradTex(bar),
        up    = _GF_MakeGradTex(bar),
        down  = _GF_MakeGradTex(bar),
    }
    bar._msufGFGrads = g
    return g
end

local function _GF_SetGrad(tex, orientation, a1, a2, strength)
    if not tex then return end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
    elseif tex.SetGradient then
        local CreateColor = _G.CreateColor
        if CreateColor then
            tex:SetGradient(orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
        else
            tex:SetColorTexture(0, 0, 0, (a1 > a2) and a1 or a2)
        end
    end
    if strength > 0 then tex:Show() else tex:Hide() end
end

local function _GF_ApplyGradientToBar(bar, gen, isPower)
    if not bar then return end
    local strength = gen.gradientStrength or 0.45
    if isPower then
        if gen.enablePowerGradient == false then strength = 0 end
    else
        if gen.enableGradient == false then strength = 0 end
    end
    local grads = _GF_EnsureGradients(bar)
    if strength <= 0 then
        for _, k in ipairs({"left","right","up","down"}) do if grads[k] then grads[k]:Hide() end end
        return
    end
    -- Read per-edge toggles (same keys as main UF)
    local left  = (gen.gradientDirLeft == true)
    local right = (gen.gradientDirRight == true)
    local up    = (gen.gradientDirUp == true)
    local down  = (gen.gradientDirDown == true)
    -- Legacy: migrate single gradientDirection
    if not left and not right and not up and not down then
        local dir = gen.gradientDirection
        if dir == "LEFT" then left = true
        elseif dir == "UP" then up = true
        elseif dir == "DOWN" then down = true
        else right = true end
    end
    -- Left
    if left then
        local t = grads.left; t:ClearAllPoints()
        if right then t:SetPoint("TOPLEFT", bar); t:SetPoint("BOTTOMLEFT", bar); t:SetPoint("RIGHT", bar, "CENTER")
        else t:SetAllPoints(bar) end
        _GF_SetGrad(t, "HORIZONTAL", strength, 0, strength)
    elseif grads.left then grads.left:Hide() end
    -- Right
    if right then
        local t = grads.right; t:ClearAllPoints()
        if left then t:SetPoint("TOPRIGHT", bar); t:SetPoint("BOTTOMRIGHT", bar); t:SetPoint("LEFT", bar, "CENTER")
        else t:SetAllPoints(bar) end
        _GF_SetGrad(t, "HORIZONTAL", 0, strength, strength)
    elseif grads.right then grads.right:Hide() end
    -- Up
    if up then
        local t = grads.up; t:ClearAllPoints()
        if down then t:SetPoint("TOPLEFT", bar); t:SetPoint("TOPRIGHT", bar); t:SetPoint("BOTTOM", bar, "CENTER")
        else t:SetAllPoints(bar) end
        _GF_SetGrad(t, "VERTICAL", 0, strength, strength)
    elseif grads.up then grads.up:Hide() end
    -- Down
    if down then
        local t = grads.down; t:ClearAllPoints()
        if up then t:SetPoint("BOTTOMLEFT", bar); t:SetPoint("BOTTOMRIGHT", bar); t:SetPoint("TOP", bar, "CENTER")
        else t:SetAllPoints(bar) end
        _GF_SetGrad(t, "VERTICAL", strength, 0, strength)
    elseif grads.down then grads.down:Hide() end
end

ApplyGradient = function(f)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if not gen then return end
    if f.health then _GF_ApplyGradientToBar(f.health, gen, false) end
    if f.power  then _GF_ApplyGradientToBar(f.power,  gen, true)  end
end

------------------------------------------------------------------------
-- Apply: bar background tint (missing-health / missing-power background)
------------------------------------------------------------------------
local function ApplyBackgroundTint(f, kind)
    local conf = GF.GetConf(kind)
    local r = conf.bgR or 0.1
    local g = conf.bgG or 0.1
    local b = conf.bgB or 0.1
    local a = conf.bgA or 0.85

    if f.healthBg then
        if f._msufGFCachedHBgR ~= r or f._msufGFCachedHBgG ~= g or f._msufGFCachedHBgB ~= b or f._msufGFCachedHBgA ~= a then
            f._msufGFCachedHBgR, f._msufGFCachedHBgG, f._msufGFCachedHBgB, f._msufGFCachedHBgA = r, g, b, a
            f.healthBg:SetVertexColor(r, g, b, a)
        end
    end
    if f.powerBg then
        if f._msufGFCachedPBgR ~= r or f._msufGFCachedPBgG ~= g or f._msufGFCachedPBgB ~= b or f._msufGFCachedPBgA ~= a then
            f._msufGFCachedPBgR, f._msufGFCachedPBgG, f._msufGFCachedPBgB, f._msufGFCachedPBgA = r, g, b, a
            f.powerBg:SetVertexColor(r, g, b, a)
        end
    end
end

------------------------------------------------------------------------
-- Apply: frame border (backdrop bg + edge)
------------------------------------------------------------------------
local function ApplyFrameBorder(f, kind)
    local conf = GF.GetConf(kind)
    local bg = f.barGroup
    if not bg then return end

    bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    bg:SetBackdropColor(
        conf.bgR or 0.1, conf.bgG or 0.1,
        conf.bgB or 0.1, conf.bgA or 0.85)

    local bf = f._msufGFBorderFrame
    if bf then
        local borderOn   = (conf.borderEnabled == true)
        local borderSize = borderOn and math_max(1, tonumber(conf.borderSize) or 1) or 1
        if borderOn then
            bf:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = borderSize })
            bf:SetBackdropColor(0, 0, 0, 0)
            bf:SetBackdropBorderColor(
                conf.borderR or 0, conf.borderG or 0,
                conf.borderB or 0, conf.borderA or 1)
            bf:Show()
        else
            bf:SetBackdrop(nil)
            bf:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Apply: effect border styles (aggro + target — pre-configure, hidden)
------------------------------------------------------------------------
local function ApplyEffectBorderStyles(f, kind)
    local hlSz  = math_max(1, tonumber(GF.GetHighlightVal(kind, "hlAggroSize")) or 2)
    local hlOfs = tonumber(GF.GetHighlightVal(kind, "hlAggroOffset")) or 0
    local hlLay = GF.GetHighlightVal(kind, "hlAggroLayer") or "DEFAULT"
    local anchor = f.barGroup or f
    local baseLvl = anchor:GetFrameLevel()

    local hb = f._msufGFHighlightBorder
    if hb then
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", -hlOfs, hlOfs)
        hb:SetPoint("BOTTOMRIGHT", hlOfs, -hlOfs)
        hb:SetFrameLevel(hlLay == "ABOVE_BORDER" and baseLvl + 8 or baseLvl + 3)
    end
end

------------------------------------------------------------------------
-- Apply: fonts
------------------------------------------------------------------------
local function ApplyFonts(f, kind)
    local conf      = GF.GetConf(kind)
    local fontPath   = GF.ResolveFontPath(kind)
    local fontFlags  = GF.ResolveFontFlags(kind)
    local fr, fg, fb = GF.ResolveFontColor(kind)
    local nameSize   = conf.nameFontSize  or 12
    local hpSize     = conf.hpFontSize    or 10
    local powSize    = conf.powerFontSize or 9

    -- Skip redundant SetFont (path+size compare)
    local function set(fs, size, r, g, b, a)
        if not fs then return end
        local curP, curS = fs:GetFont()
        if curP ~= fontPath or curS ~= size then
            fs:SetFont(fontPath, size, fontFlags)
        end
        if r then fs:SetTextColor(r, g, b, a or 1) end
        fs:SetShadowOffset(0, 0)
    end

    set(f.nameText,              nameSize,     fr, fg, fb, 1)
    set(f.textLeftFS,            hpSize,       fr, fg, fb, 0.9)
    set(f.textCenterFS,          hpSize,       fr, fg, fb, 0.9)
    set(f.textRightFS,           hpSize,       fr, fg, fb, 0.9)
    set(f.statusIndicatorText,   nameSize + 2, nil, nil, nil)
    set(f.powerTextLeftFS,       powSize,      fr, fg, fb, 0.9)
    set(f.powerTextCenterFS,     powSize,      fr, fg, fb, 0.9)
    set(f.powerTextRightFS,      powSize,      fr, fg, fb, 0.9)
    if f.groupNumberText then
        local gnSize = conf.groupNumberSize or 10
        set(f.groupNumberText, gnSize, fr, fg, fb, 0.7)
    end
end

------------------------------------------------------------------------
-- Apply: geometry (bar anchors, power height)
------------------------------------------------------------------------
local function ApplyGeometry(f, kind)
    local conf   = GF.GetConf(kind)
    local powerH = conf.powerHeight or 6
    local inset  = ((conf.borderEnabled == true) and math_max(1, tonumber(conf.borderSize) or 1)) or 1

    if f.health then
        f.health:ClearAllPoints()
        f.health:SetPoint("TOPLEFT", f.barGroup, "TOPLEFT", inset, -inset)
        f.health:SetPoint("BOTTOMRIGHT", f.barGroup, "BOTTOMRIGHT",
            -inset, powerH > 0 and (powerH + inset) or inset)
    end

    if f.power then
        f.power:ClearAllPoints()
        f.power:SetPoint("BOTTOMLEFT",  f.barGroup, "BOTTOMLEFT",  inset, inset)
        f.power:SetPoint("BOTTOMRIGHT", f.barGroup, "BOTTOMRIGHT", -inset, inset)
        if powerH > 0 then
            f.power:SetHeight(powerH)
            f.power:Show()
        else
            f.power:SetHeight(0.001)
            f.power:Hide()
        end
    end

    -- Reverse fill
    if f.health and f.health.SetReverseFill then
        f.health:SetReverseFill(conf.reverseFill and true or false)
    end
end

------------------------------------------------------------------------
-- Resolve bar color for a class token (shared by live + preview)
-- Respects global Colors menu custom class color overrides.
------------------------------------------------------------------------
local function ResolveClassColor(cls)
    if not cls then return nil end
    local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
    if type(fastClass) == "function" then
        local r, g, b = fastClass(cls)
        if r then return r, g, b end
    end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if cc then return cc.r, cc.g, cc.b end
    return nil
end

------------------------------------------------------------------------
-- Apply: health color (respects global Colors menu)
-- Global barMode (dark/unified) overrides all GF-local modes.
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end

    -- Global barMode override: dark/unified apply to ALL GF frames
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = type(getCache) == "function" and getCache() or nil
    local globalMode = cache and cache.barMode

    if globalMode == "dark" then
        f.health:SetStatusBarColor(cache.darkBarR or 0, cache.darkBarG or 0, cache.darkBarB or 0, 1)
        return
    end
    if globalMode == "unified" then
        f.health:SetStatusBarColor(cache.unifiedBarR or 0.10, cache.unifiedBarG or 0.60, cache.unifiedBarB or 0.90, 1)
        return
    end

    -- GF-local color mode
    local conf = GF.GetConf(kind)
    local mode = conf.healthColorMode or "CLASS"

    -- Resolve class token (live unit or preview)
    local cls
    if unit then
        local _
        _, cls = UnitClass(unit)
    else
        cls = f._msufGFPreviewClass
    end

    if mode == "CLASS" then
        local r, g, b = ResolveClassColor(cls)
        if r then
            f.health:SetStatusBarColor(r, g, b, 1)
            return
        end
    end

    if mode == "GRADIENT" and unit and UnitExists(unit) then
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then
            f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            return
        end
        local hpN  = tonumber(hp)
        local maxN = tonumber(hpMax)
        if hpN and maxN and maxN > 0 then
            local pct = hpN / maxN
            local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
            local g = pct > 0.5 and 1 or (pct * 2)
            f.health:SetStatusBarColor(r, g, 0, 1)
        else
            f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end
        return
    end

    f.health:SetStatusBarColor(
        conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2, 1)
end

------------------------------------------------------------------------
-- Apply: text layout
------------------------------------------------------------------------
local function ApplyTextLayout(f, kind)
    local conf = GF.GetConf(kind)
    local nox = conf.nameOffsetX or 0
    local noy = conf.nameOffsetY or 0

    if f.nameText then
        f.nameText:ClearAllPoints()
        local anchor = conf.nameAnchor or "LEFT"
        if anchor == "CENTER" then
            f.nameText:SetPoint("CENTER", f.health, "CENTER", nox, noy)
            f.nameText:SetJustifyH("CENTER")
        elseif anchor == "RIGHT" then
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -3 + nox, noy)
            f.nameText:SetJustifyH("RIGHT")
        else
            f.nameText:SetPoint("LEFT", f.health, "LEFT", 3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -3, noy)
            f.nameText:SetJustifyH("LEFT")
        end
        f.nameText:SetWordWrap(false)
        if conf.showName ~= false then f.nameText:Show() else f.nameText:Hide() end
    end

    -- 3-slot health text
    local hox = conf.hpOffsetX or 0
    local hoy = conf.hpOffsetY or 0
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"

    if f.textLeftFS then
        f.textLeftFS:ClearAllPoints()
        f.textLeftFS:SetPoint("LEFT", f.health, "LEFT", 3 + hox, hoy)
        f.textLeftFS:SetJustifyH("LEFT")
        if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
    end
    if f.textCenterFS then
        f.textCenterFS:ClearAllPoints()
        f.textCenterFS:SetPoint("CENTER", f.health, "CENTER", hox, hoy)
        f.textCenterFS:SetJustifyH("CENTER")
        if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
    end
    if f.textRightFS then
        f.textRightFS:ClearAllPoints()
        f.textRightFS:SetPoint("RIGHT", f.health, "RIGHT", -3 + hox, hoy)
        f.textRightFS:SetJustifyH("RIGHT")
        if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
    end

    if f.statusIndicatorText then
        f.statusIndicatorText:ClearAllPoints()
        f.statusIndicatorText:SetPoint("CENTER", f.health, "CENTER",
            conf.statusOffsetX or 0, conf.statusOffsetY or 0)
    end

    -- 3-slot power text
    local pox = conf.powerOffsetX or 0
    local poy = conf.powerOffsetY or 0
    local showPow = conf.showPower and (conf.powerHeight or 6) > 0
    local ptl = showPow and (conf.powerTextLeft   or "NONE") or "NONE"
    local ptc = showPow and (conf.powerTextCenter  or "NONE") or "NONE"
    local ptr = showPow and (conf.powerTextRight   or "NONE") or "NONE"

    if f.powerTextLeftFS then
        f.powerTextLeftFS:ClearAllPoints()
        f.powerTextLeftFS:SetPoint("LEFT", f.power, "LEFT", 2 + pox, poy)
        f.powerTextLeftFS:SetJustifyH("LEFT")
        if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
    end
    if f.powerTextCenterFS then
        f.powerTextCenterFS:ClearAllPoints()
        f.powerTextCenterFS:SetPoint("CENTER", f.power, "CENTER", pox, poy)
        f.powerTextCenterFS:SetJustifyH("CENTER")
        if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
    end
    if f.powerTextRightFS then
        f.powerTextRightFS:ClearAllPoints()
        f.powerTextRightFS:SetPoint("RIGHT", f.power, "RIGHT", -2 + pox, poy)
        f.powerTextRightFS:SetJustifyH("RIGHT")
        if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
    end

    -- Group number text
    if f.groupNumberText then
        if conf.showGroupNumber then
            f.groupNumberText:ClearAllPoints()
            local gnAnchor = conf.groupNumberAnchor or "BOTTOMRIGHT"
            local gnX = conf.groupNumberX
            local gnY = conf.groupNumberY
            if gnX == nil then gnX = -2 end
            if gnY == nil then gnY = 2 end
            f.groupNumberText:SetPoint(gnAnchor, f.health or f.barGroup, gnAnchor, gnX, gnY)
            f.groupNumberText:SetJustifyH("RIGHT")
        else
            f.groupNumberText:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Apply: icon layout (spec-driven)
------------------------------------------------------------------------
local ICON_SPECS = {
    { field="roleIcon",      enKey="roleIcon",      sizeKey="roleIconSize",      anchorKey="roleIconAnchor",    xKey="roleIconX",    yKey="roleIconY",    defAnchor="TOPLEFT",    defSize=12 },
    { field="leaderIcon",    enKey="leaderIcon",     sizeKey="leaderIconSize",    anchorKey="leaderIconAnchor",  xKey="leaderIconX",  yKey="leaderIconY",  defAnchor="TOPRIGHT",   defSize=12 },
    { field="assistIcon",    enKey="assistIcon",     sizeKey="assistIconSize",    anchorKey="assistIconAnchor",  xKey="assistIconX",  yKey="assistIconY",  defAnchor="TOPRIGHT",   defSize=12 },
    { field="raidIcon",      enKey="raidMarker",     sizeKey="raidMarkerSize",    anchorKey="raidMarkerAnchor",  xKey="raidMarkerX",  yKey="raidMarkerY",  defAnchor="CENTER",     defSize=14 },
    { field="readyCheckIcon",enKey="readyCheckIcon", sizeKey="readyCheckSize",    anchorKey="readyCheckAnchor",  xKey="readyCheckX",  yKey="readyCheckY",  defAnchor="CENTER",     defSize=16 },
    { field="summonIcon",    enKey="summonIcon",     sizeKey="summonIconSize",    anchorKey="summonAnchor",      xKey="summonX",      yKey="summonY",      defAnchor="CENTER",     defSize=16 },
    { field="resurrectIcon", enKey="resurrectIcon",  sizeKey="resurrectIconSize", anchorKey="resurrectAnchor",   xKey="resurrectX",   yKey="resurrectY",   defAnchor="CENTER",     defSize=16 },
    { field="phaseIcon",     enKey="phaseIcon",      sizeKey="phaseIconSize",     anchorKey="phaseAnchor",       xKey="phaseX",       yKey="phaseY",       defAnchor="TOPLEFT",    defSize=14 },
}
GF.ICON_SPECS = ICON_SPECS

local function ApplyIconLayout(f, kind)
    local conf   = GF.GetConf(kind)
    local anchor = f.statusIconLayer or f.barGroup or f

    for i = 1, #ICON_SPECS do
        local s = ICON_SPECS[i]
        local icon = f[s.field]
        if icon then
            icon:ClearAllPoints()
            local sz = conf[s.sizeKey] or s.defSize
            icon:SetSize(sz, sz)
            local pt = conf[s.anchorKey] or s.defAnchor
            icon:SetPoint(pt, anchor, pt, conf[s.xKey] or 0, conf[s.yKey] or 0)
        end
    end
end

------------------------------------------------------------------------
-- Apply: health prediction overlay colors (from global MSUF_DB.general)
-- Diff-gated per-bar to avoid redundant SetStatusBarColor calls.
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Resolve an absorb/overlay setting: GF conf (if hlOverride) → general
------------------------------------------------------------------------
local function _GF_ResolveOverlaySetting(kind, key)
    local dbKey = (kind == "raid") and "gf_raid" or "gf_party"
    local db = _G.MSUF_DB and _G.MSUF_DB[dbKey]
    if db and db.hlOverride and db[key] ~= nil then return db[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return gen and gen[key]
end

local function ApplyOverlayColors(f)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local kind = f._msufGFKind or "party"
    -- Incoming heal (heal prediction) — colors from general (shared)
    if f.incomingHealBar then
        local r = (gen and gen.healPredColorR) or 0.0
        local g = (gen and gen.healPredColorG) or 1.0
        local b = (gen and gen.healPredColorB) or 0.4
        local a = 0.45
        if f._gfCIHR ~= r or f._gfCIHG ~= g or f._gfCIHB ~= b then
            f._gfCIHR, f._gfCIHG, f._gfCIHB = r, g, b
            f.incomingHealBar:SetStatusBarColor(r, g, b, a)
        end
    end
    -- Absorb (color from general, opacity per-GF override → general)
    if f.absorbBar then
        local r = (gen and gen.absorbBarColorR) or 0.8
        local g = (gen and gen.absorbBarColorG) or 0.9
        local b = (gen and gen.absorbBarColorB) or 1.0
        local a = tonumber(_GF_ResolveOverlaySetting(kind, "absorbBarOpacity")) or 0.6
        if f._gfCAbR ~= r or f._gfCAbG ~= g or f._gfCAbB ~= b or f._gfCAbA ~= a then
            f._gfCAbR, f._gfCAbG, f._gfCAbB, f._gfCAbA = r, g, b, a
            f.absorbBar:SetStatusBarColor(r, g, b, a)
        end
    end
    -- Heal absorb (color from general, opacity per-GF override → general)
    if f.healAbsorbBar then
        local r = (gen and gen.healAbsorbBarColorR) or 1.0
        local g = (gen and gen.healAbsorbBarColorG) or 0.4
        local b = (gen and gen.healAbsorbBarColorB) or 0.4
        local a = tonumber(_GF_ResolveOverlaySetting(kind, "healAbsorbBarOpacity")) or 0.7
        if f._gfCHAbR ~= r or f._gfCHAbG ~= g or f._gfCHAbB ~= b or f._gfCHAbA ~= a then
            f._gfCHAbR, f._gfCHAbG, f._gfCHAbB, f._gfCHAbA = r, g, b, a
            f.healAbsorbBar:SetStatusBarColor(r, g, b, a)
        end
    end
    -- Absorb anchoring (per-GF override → general)
    if GF._ApplyAbsorbAnchor then
        local mode = tonumber(_GF_ResolveOverlaySetting(kind, "absorbAnchorMode")) or 2
        if f._msufGFAbsorbAnchorStamp ~= mode then
            GF._ApplyAbsorbAnchor(f)
        end
    end
end

------------------------------------------------------------------------
-- Apply all visuals for one frame (selective via bits)
------------------------------------------------------------------------
local function ApplyVisuals(f, bits)
    if not f then return end
    local kind = f._msufGFKind or "party"
    local needGeometry = (band(bits, DIRTY_GEOMETRY) ~= 0) or (band(bits, DIRTY_BORDER) ~= 0)

    if needGeometry then
        ApplyGeometry(f, kind)
    end
    if band(bits, DIRTY_TEXTURE) ~= 0 then
        ApplyBarTexture(f, kind)
    end
    if band(bits, DIRTY_FONT) ~= 0 then
        ApplyFonts(f, kind)
    end
    if band(bits, DIRTY_COLOR) ~= 0 then
        ApplyHealthColor(f, kind, f.unit)
        ApplyOverlayColors(f)
    end
    if band(bits, DIRTY_BORDER) ~= 0 then
        ApplyFrameBorder(f, kind)
        ApplyBackgroundTint(f, kind)
        ApplyEffectBorderStyles(f, kind)
    end
    if band(bits, DIRTY_LAYOUT) ~= 0 then
        ApplyTextLayout(f, kind)
        ApplyIconLayout(f, kind)
    end
end

------------------------------------------------------------------------
-- Flush dirty queue
------------------------------------------------------------------------
function GF._FlushDirty()
    for f, bits in pairs(_dirtyFrames) do
        _dirtyFrames[f] = nil
        ApplyVisuals(f, bits)
        if f._msufGFPreviewActive then
            -- Re-apply preview data (ApplyVisuals stomps colors/text)
            local idx = f._msufGFPreviewIndex
            local kind = f._msufGFKind
            if idx and kind then
                GF.ApplyPreviewData(f, idx, kind)
            end
        elseif f.unit and UnitExists(f.unit) then
            local fn = _G.MSUF_GF_UpdateAll
            if type(fn) == "function" then fn(f, f.unit) end
        end
    end
end

------------------------------------------------------------------------
-- Public: mark single frame dirty
------------------------------------------------------------------------
function GF.MarkDirty(f, bits)
    if not f then return end
    bits = bits or DIRTY_ALL
    local prev = _dirtyFrames[f] or 0
    _dirtyFrames[f] = bor(prev, bits)
    ScheduleFlush()
end

------------------------------------------------------------------------
-- Public: mark ALL GF frames dirty (Options "Apply")
------------------------------------------------------------------------
function GF.MarkAllDirty(bits)
    bits = bits or DIRTY_ALL
    for f in pairs(GF.frames) do
        local prev = _dirtyFrames[f] or 0
        _dirtyFrames[f] = bor(prev, bits)
    end
    -- Also mark preview frames
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local f = list[i]
                if f then
                    local prev = _dirtyFrames[f] or 0
                    _dirtyFrames[f] = bor(prev, bits)
                end
            end
        end
    end
    ScheduleFlush()
end

------------------------------------------------------------------------
-- Public: immediate full refresh (no coalescing)
-- Use for Options "Apply" when user expects instant feedback.
------------------------------------------------------------------------
function GF.RefreshVisuals()
    for f in pairs(GF.frames) do
        ApplyVisuals(f, DIRTY_ALL)
        if f.unit and UnitExists(f.unit) and not f._msufGFPreviewActive then
            local fn = _G.MSUF_GF_UpdateAll
            if type(fn) == "function" then fn(f, f.unit) end
        end
    end
    -- Preview frames
    if GF._previewFrames then
        for kind, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local f = list[i]
                if f then
                    ApplyVisuals(f, DIRTY_ALL)
                    if f._msufGFPreviewActive then
                        GF.ApplyPreviewData(f, i, kind)
                    end
                end
            end
        end
    end
    -- Options panel preview (drag-to-position mock frame)
    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
end

------------------------------------------------------------------------
-- Public: refresh only specific aspects
------------------------------------------------------------------------
function GF.RefreshTextures()
    GF.MarkAllDirty(DIRTY_TEXTURE)
end

function GF.RefreshFonts()
    GF.MarkAllDirty(DIRTY_FONT)
end

function GF.RefreshColors()
    GF.MarkAllDirty(bor(DIRTY_COLOR, DIRTY_BORDER))
end

function GF.RefreshGeometry()
    GF.MarkAllDirty(bor(DIRTY_GEOMETRY, DIRTY_LAYOUT))
end

------------------------------------------------------------------------
-- Hook: re-apply visuals when preview is shown
------------------------------------------------------------------------
do
    local origShowPreview = GF.ShowPreview
    if type(origShowPreview) == "function" then
        GF.ShowPreview = function(kind, count)
            origShowPreview(kind, count)
            -- Apply full visuals THEN re-apply preview data (visuals stomps colors)
            local k = kind or "party"
            local list = GF._previewFrames and GF._previewFrames[k]
            if list then
                for i = 1, #list do
                    local f = list[i]
                    if f and f:IsShown() then
                        ApplyVisuals(f, DIRTY_ALL)
                        if f._msufGFPreviewActive then
                            GF.ApplyPreviewData(f, i, k)
                        end
                    end
                end
            end
        end
        _G.MSUF_GF_ShowPreview = GF.ShowPreview
    end
end

------------------------------------------------------------------------
-- Hook: apply visuals after GF_InitButton builds hierarchy
------------------------------------------------------------------------
do
    local origInit = _G.MSUF_GF_InitButton
    if type(origInit) == "function" then
        _G.MSUF_GF_InitButton = function(f, kind)
            origInit(f, kind)
            ApplyVisuals(f, DIRTY_ALL)
        end
    end
end

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
_G.MSUF_GF_MarkDirty      = GF.MarkDirty
_G.MSUF_GF_MarkAllDirty   = GF.MarkAllDirty
_G.MSUF_GF_RefreshVisuals  = GF.RefreshVisuals
_G.MSUF_GF_RefreshTextures = GF.RefreshTextures
_G.MSUF_GF_RefreshFonts    = GF.RefreshFonts
_G.MSUF_GF_RefreshColors   = GF.RefreshColors
_G.MSUF_GF_RefreshGeometry = GF.RefreshGeometry

-- Expose ApplyVisuals for direct use by other GF modules
GF.ApplyVisuals = ApplyVisuals

------------------------------------------------------------------------
-- Hook: global Colors menu changes → refresh GF frames
-- ColorsCore.PushVisualUpdates calls MSUF_RefreshAllFrames. We hook it
-- so GF frames also re-apply class colors, font colors, bar textures.
------------------------------------------------------------------------
do
    local _hooked = false
    C_Timer.After(0.5, function()
        if _hooked then return end
        local orig = _G.MSUF_RefreshAllFrames
        if type(orig) == "function" then
            _hooked = true
            _G.MSUF_RefreshAllFrames = function(...)
                orig(...)
                GF.RefreshVisuals()
            end
        end
    end)
end

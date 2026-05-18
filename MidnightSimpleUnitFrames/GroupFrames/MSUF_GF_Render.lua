-- MSUF_GF_Render.lua — Group Frames Phase 3: Visual Pipeline
-- Coalesced dirty-flag refresh: multiple DB writes → 1 visual update per frame per tick.
-- Bar textures, backgrounds, borders, fonts, text layout, geometry, health colors.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local C_Secrets = _G.C_Secrets
local issecretvalue = _G.issecretvalue
    or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
    or nil
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitClass = _G.UnitClass
local UnitGUID = _G.UnitGUID
local UnitIsPlayer = _G.UnitIsPlayer
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local bor  = (bit and bit.bor)  or function(a, b) return a + b - (a % (b + b) >= b and b or 0) end
local band = (bit and bit.band) or function(a, b) if a % (b + b) >= b then return b else return 0 end end
local pairs = pairs
local type = type
local tonumber = tonumber
local math_max = math.max
local math_floor = math.floor

local function RuntimeEnabledForFrame(f)
    if not f then return false end
    if f._msufGFPreviewActive then return true end
    if f.unit and UnitExists and UnitExists(f.unit) and f.IsVisible and f:IsVisible() then
        return true
    end
    local kind = f._msufGFKind or (GF.frames and GF.frames[f]) or "party"
    return not (GF.IsKindEnabled and not GF.IsKindEnabled(kind))
end

local MSUF_BETTER_BLIZZARD_TEXTURE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\BetterBlizzard.blp"
local UNHALTED_BG_R, UNHALTED_BG_G, UNHALTED_BG_B = 34/255, 34/255, 34/255
local _unhaltedTextureChecked, _unhaltedTexture
local GRAD_KEYS = { "left", "right", "up", "down" }

local function GetSecretValueDetector()
    local isv = issecretvalue
    if not isv then
        local secrets = C_Secrets or _G.C_Secrets
        C_Secrets = secrets
        isv = _G.issecretvalue
            or (secrets and type(secrets.IsSecret) == "function" and secrets.IsSecret)
            or nil
        if isv then issecretvalue = isv end
    end
    return isv
end

local function SecretModeActiveWithoutDetector()
    local secrets = C_Secrets or _G.C_Secrets
    C_Secrets = secrets
    local fn = secrets and secrets.ShouldAurasBeSecret
    return type(fn) == "function" and fn() == true
end

local function IsSecretRuntimeValue(v)
    local isv = GetSecretValueDetector()
    if isv then return isv(v) == true end
    return type(v) ~= "nil" and SecretModeActiveWithoutDetector()
end

local function ResolveUnhaltedTexture()
    if _unhaltedTextureChecked then return _unhaltedTexture end
    _unhaltedTextureChecked = true

    local globalResolve = _G.MSUF_Alpha_GetPreserveHPTexture
    if type(globalResolve) == "function" then
        local ok, tex = pcall(globalResolve)
        if ok and type(tex) == "string" and tex ~= "" then
            _unhaltedTexture = tex
            return _unhaltedTexture
        end
    end

    local LibStub = _G.LibStub
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(LSM.Fetch) == "function" then
        local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", "Better Blizzard", true)
        if ok and type(tex) == "string" and tex ~= "" then
            _unhaltedTexture = tex
            return _unhaltedTexture
        end
    end

    _unhaltedTexture = MSUF_BETTER_BLIZZARD_TEXTURE
    return _unhaltedTexture
end

local function GetGFFrameAlpha(kind, conf)
    local fn = GF.GetEffectiveFrameAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return 1
end

local function GetGFHealthAlpha(kind, conf)
    local fn = GF.GetEffectiveHealthAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return tonumber(conf and conf.hpBarAlpha) or 1
end

local function GetGFPowerAlpha(kind, conf)
    local fn = GF.GetEffectivePowerAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return 1
end

local function GetGFBackgroundAlpha(kind, conf)
    local fn = GF.GetEffectiveBackgroundAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return 1
end

local function SetStatusBarTextureAlpha(bar, alpha)
    if not bar then return end
    if type(alpha) ~= "number" then alpha = 1 end
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    bar._msufGFTextureAlphaMul = alpha
    local overlayAlpha = bar._msufGFOverlayTextureAlpha
    if type(overlayAlpha) == "number" then
        alpha = alpha * overlayAlpha
    end
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local target = tex or bar
    if target and target.SetAlpha then target:SetAlpha(alpha) end
end

local function SetOverlayStatusBarTextureAlpha(bar, alpha)
    if not bar then return end
    if type(alpha) == "number" then
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        bar._msufGFOverlayTextureAlpha = alpha
    else
        alpha = bar._msufGFOverlayTextureAlpha
    end
    if type(alpha) ~= "number" then return end
    local mul = tonumber(bar._msufGFTextureAlphaMul) or 1
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local target = tex or bar
    if target and target.SetAlpha then target:SetAlpha(alpha * mul) end
end

local function SetStatusBarTextureAlphaFromBoolean(bar, boolValue, activeAlpha, inactiveAlpha)
    if not bar then return false end
    local overlayAlpha = bar._msufGFOverlayTextureAlpha
    if type(overlayAlpha) == "number" then
        activeAlpha = (tonumber(activeAlpha) or 1) * overlayAlpha
        inactiveAlpha = (tonumber(inactiveAlpha) or 1) * overlayAlpha
    end
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and tex.SetAlphaFromBoolean then
        tex:SetAlphaFromBoolean(boolValue, activeAlpha, inactiveAlpha)
        return true
    end
    if bar.SetAlphaFromBoolean then
        bar:SetAlphaFromBoolean(boolValue, activeAlpha, inactiveAlpha)
        return true
    end
    return false
end

local function ScaleValue(value, scale, minValue)
    if GF.ScaleValue then
        return GF.ScaleValue(value, scale or 1, minValue)
    end
    local v = (tonumber(value) or 0) * (tonumber(scale) or 1)
    if v >= 0 then v = math_floor(v + 0.5) else v = -math_floor((-v) + 0.5) end
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

------------------------------------------------------------------------
-- Dirty bits (bitmask, combinable via bor)
------------------------------------------------------------------------
local DIRTY_GEOMETRY = 0x01   -- size, powerHeight
local DIRTY_TEXTURE  = 0x02   -- bar texture / background
local DIRTY_FONT     = 0x04   -- font path / size / outline / color
local DIRTY_COLOR    = 0x08   -- health color mode, bg, power color
local DIRTY_BORDER   = 0x10   -- border paint/color/state, aggro/target border style
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
-- Dirty queue + budgeted coalesced flush
-- Senior-dev perf refactor:
--   * no pairs(_dirtyFrames) burst over all frames in one tick
--   * each frame is enqueued once, bits are OR-merged
--   * runtime frames are processed with a small time/count budget
------------------------------------------------------------------------
local _dirtyBits = {}   -- [frame] = bitfield
local _queued    = {}   -- [frame] = true
local _queue     = {}   -- dense frame queue
local _head      = 1
local _tail      = 0
local function _ResetQueueIfEmpty()
    if _head > _tail then
        _head, _tail = 1, 0
    end
end

local function _Enqueue(f)
    if not f or _queued[f] then return end
    _tail = _tail + 1
    _queue[_tail] = f
    _queued[f] = true
end

local _flushQueued = false
local function _DoFlush()
    _flushQueued = false
    GF._FlushDirty()
end
local function ScheduleFlush()
    if _flushQueued then return end
    _flushQueued = true
    local sched = _G.MSUF_ScheduleOnce
    if sched then
        sched("GF_RENDER_FLUSH", _DoFlush)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, _DoFlush)
    else
        _DoFlush()
    end
end

------------------------------------------------------------------------
-- Apply: bar textures + gradient overlays
------------------------------------------------------------------------
local ApplyGradient   -- forward decl (defined after ApplyBarTexture)
local function ApplyBarTexture(f, kind)
    local tex   = GF.ResolveBarTexture(kind)
    local bgTex = GF.ResolveBarBgTexture(kind)
    local hpTex = tex
    local conf = GF.GetConf(kind)
    if conf and conf.alphaPreserveHPColor == true then
        hpTex = ResolveUnhaltedTexture() or tex
    end

    if f.health and f.health.SetStatusBarTexture then
        if f._msufGFCachedHTex ~= hpTex then
            f.health:SetStatusBarTexture(hpTex)
            f._msufGFCachedHTex = hpTex
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
    if f.incomingHealBar and f.incomingHealBar.SetStatusBarTexture and f._msufGFCachedIncomingTex ~= tex then
        f.incomingHealBar:SetStatusBarTexture(tex)
        f._msufGFCachedIncomingTex = tex
    end
    if f.absorbBar and f.absorbBar.SetStatusBarTexture and f._msufGFCachedAbsorbTex ~= absorbTex then
        f.absorbBar:SetStatusBarTexture(absorbTex)
        f._msufGFCachedAbsorbTex = absorbTex
        SetOverlayStatusBarTextureAlpha(f.absorbBar)
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetStatusBarTexture and f._msufGFCachedHealAbsorbTex ~= healAbsorbTex then
        f.healAbsorbBar:SetStatusBarTexture(healAbsorbTex)
        f._msufGFCachedHealAbsorbTex = healAbsorbTex
        SetOverlayStatusBarTextureAlpha(f.healAbsorbBar)
    end

    -- Gradient overlays inherit Shared unless this GF scope has Bars overrides.
    ApplyGradient(f, kind)
end

------------------------------------------------------------------------
-- Gradient overlays: lazy-create + apply from scoped Bars settings
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

local function _GF_GradientKeyActive(conf, key)
    return conf and conf.hlOverride == true and conf.gradientOverride == true
        and conf.gradientOverrideVersion == 2
        and type(conf.gradientOverrideKeys) == "table"
        and conf.gradientOverrideKeys[key] == true
end

local function _GF_GradientValue(conf, gen, key, defaultVal)
    if _GF_GradientKeyActive(conf, key) and conf[key] ~= nil then
        return conf[key]
    end
    local v = gen and gen[key]
    if v ~= nil then return v end
    return defaultVal
end

local function _GF_GradientDirState(conf, gen)
    if _GF_GradientKeyActive(conf, "gradientDirLeft")
        or _GF_GradientKeyActive(conf, "gradientDirRight")
        or _GF_GradientKeyActive(conf, "gradientDirUp")
        or _GF_GradientKeyActive(conf, "gradientDirDown")
        or _GF_GradientKeyActive(conf, "gradientDirection")
    then
        local left  = _GF_GradientKeyActive(conf, "gradientDirLeft") and (conf.gradientDirLeft == true) or false
        local right = _GF_GradientKeyActive(conf, "gradientDirRight") and (conf.gradientDirRight == true) or false
        local up    = _GF_GradientKeyActive(conf, "gradientDirUp") and (conf.gradientDirUp == true) or false
        local down  = _GF_GradientKeyActive(conf, "gradientDirDown") and (conf.gradientDirDown == true) or false
        if not left and not right and not up and not down then
            local dir = _GF_GradientKeyActive(conf, "gradientDirection") and conf.gradientDirection or nil
            if dir == "LEFT" then left = true
            elseif dir == "UP" then up = true
            elseif dir == "DOWN" then down = true
            else right = true end
        end
        return left, right, up, down
    end
    local left  = (gen and gen.gradientDirLeft == true)
    local right = (gen and gen.gradientDirRight == true)
    local up    = (gen and gen.gradientDirUp == true)
    local down  = (gen and gen.gradientDirDown == true)
    if not left and not right and not up and not down then
        local dir = gen and gen.gradientDirection
        if dir == "LEFT" then left = true
        elseif dir == "UP" then up = true
        elseif dir == "DOWN" then down = true
        else right = true end
    end
    return left, right, up, down
end

local function _GF_ApplyGradientToBar(bar, conf, gen, isPower)
    if not bar then return end
    local strength = tonumber(_GF_GradientValue(conf, gen, "gradientStrength", 0.45)) or 0.45
    if isPower then
        if _GF_GradientValue(conf, gen, "enablePowerGradient", false) ~= true then strength = 0 end
    else
        if _GF_GradientValue(conf, gen, "enableGradient", false) ~= true then strength = 0 end
    end
    if strength <= 0 then
        local grads = bar._msufGFGrads
        if grads then
            for i = 1, #GRAD_KEYS do
                local g = grads[GRAD_KEYS[i]]
                if g then g:Hide() end
            end
        end
        return
    end
    local grads = _GF_EnsureGradients(bar)
    local left, right, up, down = _GF_GradientDirState(conf, gen)
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

ApplyGradient = function(f, kind)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if not gen then return end
    local conf = kind and GF.GetConf and GF.GetConf(kind) or nil
    if f.health then _GF_ApplyGradientToBar(f.health, conf, gen, false) end
    if f.power  then _GF_ApplyGradientToBar(f.power,  conf, gen, true)  end
end

local ResolveClassColor

------------------------------------------------------------------------
-- Apply: bar background tint (missing-health / missing-power background)
--
-- Behind-Bar Z-Order Fix:
-- Original healthBg is a texture on health (level N+1). Behind-bar icons
-- at level N are invisible beneath it. Fix: when ANY aura group uses
-- behind-bar, hide original healthBg and create a replacement texture
-- on barGroup at ARTWORK sublevel -7 (below icons but above barGroup bg).
-- Icons then sit between replacement-bg and health fill.
--
-- Z-Order (behind-bar active):
--   barGroup backdrop   (N, BG)       → dark frame bg
--   replacement-bg      (N, ART, -7)  → health area tint (configurable alpha)
--   aura icon frames    (N+1)         → icons visible above tint
--   health fill         (N+1, ART)    → HP bar covers icons where HP present
------------------------------------------------------------------------
local function ApplyBackgroundTint(f, kind)
    local conf = GF.GetConf(kind)
    local r = conf.bgR or 0.1
    local g = conf.bgG or 0.1
    local b = conf.bgB or 0.1
    local hr, hg, hb = r, g, b
    local a = conf.bgA or 0.85
    local hpBgA = conf.hpBgAlpha or a
    local layerA = GetGFBackgroundAlpha(kind, conf)
    local effA = a * layerA
    local effHpBgA = hpBgA * layerA

    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen.barBgClassColor then
        local cls
        if f.unit and UnitExists and UnitExists(f.unit) then
            local guid = UnitGUID and UnitGUID(f.unit) or f.unit
            if f._msufGFClassBgGuid == guid then
                cls = f._msufGFClassBgClass
            elseif UnitClass and ((not UnitIsPlayer) or UnitIsPlayer(f.unit)) then
                local _
                _, cls = UnitClass(f.unit)
                f._msufGFClassBgGuid = guid
                f._msufGFClassBgClass = cls
            else
                f._msufGFClassBgGuid = guid
                f._msufGFClassBgClass = nil
            end
        else
            f._msufGFClassBgGuid = nil
            f._msufGFClassBgClass = nil
            cls = f._msufGFPreviewClass
        end
        if ResolveClassColor then
            local rev = _G.MSUF_ColorStyleRevision or 0
            local cr, cg, cb
            if f._msufGFClassBgColorToken == cls and f._msufGFClassBgColorRev == rev then
                cr, cg, cb = f._msufGFClassBgR, f._msufGFClassBgG, f._msufGFClassBgB
            else
                cr, cg, cb = ResolveClassColor(cls)
                f._msufGFClassBgColorToken = cls
                f._msufGFClassBgColorRev = rev
                f._msufGFClassBgR, f._msufGFClassBgG, f._msufGFClassBgB = cr, cg, cb
            end
            if cr then hr, hg, hb = cr, cg, cb end
        end
    end

    -- Detect if any aura group uses behind-bar
    local auras = conf.auras
    local anyBehindBar = false
    if auras then
        local bu, de, ex = auras.buff, auras.debuff, auras.externals
        if (bu and bu.behindBar) or (de and de.behindBar) or (ex and ex.behindBar) then
            anyBehindBar = true
        end
    end

    if anyBehindBar and f.health and f.barGroup then
        -- Hide original healthBg (stuck at health's level, covers icons)
        if f.healthBg then f.healthBg:Hide() end
        -- Lazy-create replacement bg texture on barGroup (lower level)
        if not f._msufBehindBarBg then
            f._msufBehindBarBg = f.barGroup:CreateTexture(nil, "ARTWORK", nil, -7)
        end
        local bbBg = f._msufBehindBarBg
        bbBg:SetAllPoints(f.health)
        bbBg:SetTexture(GF.ResolveBarBgTexture(kind))
        if f._msufBBgR ~= hr or f._msufBBgG ~= hg or f._msufBBgB ~= hb or f._msufBBgA ~= effHpBgA then
            f._msufBBgR, f._msufBBgG, f._msufBBgB, f._msufBBgA = hr, hg, hb, effHpBgA
            bbBg:SetVertexColor(hr, hg, hb, effHpBgA)
        end
        bbBg:Show()
        f._msufBehindBarActive = true
    else
        -- Restore original healthBg
        if f._msufBehindBarActive then
            if f.healthBg then f.healthBg:Show() end
            if f._msufBehindBarBg then f._msufBehindBarBg:Hide() end
            f._msufBehindBarActive = nil
        end
        if f.healthBg then
            if f._msufGFCachedHBgR ~= hr or f._msufGFCachedHBgG ~= hg
               or f._msufGFCachedHBgB ~= hb or f._msufGFCachedHBgA ~= effHpBgA then
                f._msufGFCachedHBgR, f._msufGFCachedHBgG, f._msufGFCachedHBgB, f._msufGFCachedHBgA = hr, hg, hb, effHpBgA
                f.healthBg:SetVertexColor(hr, hg, hb, effHpBgA)
            end
        end
    end

    if f.powerBg then
        if f._msufGFCachedPBgR ~= r or f._msufGFCachedPBgG ~= g
           or f._msufGFCachedPBgB ~= b or f._msufGFCachedPBgA ~= effA then
            f._msufGFCachedPBgR, f._msufGFCachedPBgG, f._msufGFCachedPBgB, f._msufGFCachedPBgA = r, g, b, effA
            f.powerBg:SetVertexColor(r, g, b, effA)
        end
    end
end

local function ApplyBackgroundAlpha(f, kind)
    if not f then return end
    local conf = GF.GetConf(kind)
    if not conf then return end
    local layerA = GetGFBackgroundAlpha(kind, conf)
    if f.barGroup and f.barGroup.SetBackdropColor then
        f.barGroup:SetBackdropColor(
            conf.bgR or 0.1, conf.bgG or 0.1,
            conf.bgB or 0.1, (conf.bgA or 0.85) * layerA)
    end
    ApplyBackgroundTint(f, kind)
end
GF.ApplyBackgroundAlpha = ApplyBackgroundAlpha

------------------------------------------------------------------------
-- Apply: frame border (backdrop bg + edge)
-- Reuses shared tables to avoid allocation per-call
------------------------------------------------------------------------
local _bgOnlyBd = { bgFile = "Interface\\Buttons\\WHITE8x8" }
local _borderBd = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local function ApplyFrameBorderLevel(f, border)
    if not (f and border and border.SetFrameLevel) then return end
    local anchor = f.barGroup or f
    local anchorLevel = anchor and anchor.GetFrameLevel and anchor:GetFrameLevel() or 0
    local wantLevel = anchorLevel + 3
    local minTextLevel
    local layer = f.nameTextLayer
    local level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
    if level then minTextLevel = level end
    layer = f.healthTextLayer
    level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
    if level and (not minTextLevel or level < minTextLevel) then
        minTextLevel = level
    end
    layer = f.powerTextLayer
    level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
    if level and (not minTextLevel or level < minTextLevel) then
        minTextLevel = level
    end
    layer = f.statusTextLayer
    level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
    if level and (not minTextLevel or level < minTextLevel) then
        minTextLevel = level
    end
    if minTextLevel and wantLevel >= minTextLevel then wantLevel = minTextLevel - 1 end
    if wantLevel <= anchorLevel then wantLevel = anchorLevel + 1 end
    if border._msufGFFrameBorderLevel ~= wantLevel then
        border._msufGFFrameBorderLevel = wantLevel
        border:SetFrameLevel(wantLevel)
    end
end

local function ApplyFrameBorder(f, kind)
    local conf = GF.GetConf(kind)
    local bg = f.barGroup
    if not bg then return end
    local fScale = conf._resolvedFrameScale or 1

    if bg._msufGFBackdropKind ~= "bg" then
        bg:SetBackdrop(_bgOnlyBd)
        bg._msufGFBackdropKind = "bg"
        bg._msufGFBackdropR = nil
    end
    local br = conf.bgR or 0.1
    local bgc = conf.bgG or 0.1
    local bb = conf.bgB or 0.1
    local ba = (conf.bgA or 0.85) * GetGFBackgroundAlpha(kind, conf)
    if bg._msufGFBackdropR ~= br or bg._msufGFBackdropG ~= bgc
        or bg._msufGFBackdropB ~= bb or bg._msufGFBackdropA ~= ba
    then
        bg:SetBackdropColor(br, bgc, bb, ba)
        bg._msufGFBackdropR, bg._msufGFBackdropG = br, bgc
        bg._msufGFBackdropB, bg._msufGFBackdropA = bb, ba
    end

    local bf = f._msufGFBorderFrame
    if bf then
        local borderSize = (GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind)) or 2
        if fScale ~= 1 then borderSize = ScaleValue(borderSize, fScale, 0) end
        ApplyFrameBorderLevel(f, bf)
        if borderSize > 0 then
            if bf._msufGFBorderSize ~= borderSize then
                bf._msufGFBorderSize = borderSize
                _borderBd.edgeSize = borderSize
                bf:SetBackdrop(_borderBd)
                bf:SetBackdropColor(0, 0, 0, 0)
                bf:SetBackdropBorderColor(0, 0, 0, 1)
            end
            if not bf:IsShown() then bf:Show() end
        else
            if bf:IsShown() then bf:Hide() end
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
    local conf = GF.GetConf(kind)
    local fScale = conf._resolvedFrameScale or 1
    if fScale ~= 1 then
        hlSz = ScaleValue(hlSz, fScale, 1)
        hlOfs = ScaleValue(hlOfs, fScale)
    end

    local hb = f._msufGFHighlightBorder
    if hb then
        local wantLevel = hlLay == "ABOVE_BORDER" and baseLvl + 8 or baseLvl + 3
        if hb._msufGFStyleOfs ~= hlOfs then
            hb._msufGFStyleOfs = hlOfs
            hb:ClearAllPoints()
            hb:SetPoint("TOPLEFT", -hlOfs, hlOfs)
            hb:SetPoint("BOTTOMRIGHT", hlOfs, -hlOfs)
        end
        if hb._msufGFStyleLevel ~= wantLevel then
            hb._msufGFStyleLevel = wantLevel
            hb:SetFrameLevel(wantLevel)
        end
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
    local db = _G.MSUF_DB
    local fontKey = db and db.general and db.general.fontKey
    local fScale     = conf._resolvedFrameScale or 1
    local nameSize   = (conf.nameFontSize  or 12) * fScale
    local hpSize     = (conf.hpFontSize    or 10) * fScale
    local powSize    = (conf.powerFontSize or 9)  * fScale
    -- Floor font sizes (min 6px for readability)
    nameSize = math_max(6, math_floor(nameSize + 0.5))
    hpSize   = math_max(6, math_floor(hpSize + 0.5))
    powSize  = math_max(6, math_floor(powSize + 0.5))

    -- Diff-gate: skip SetTextColor when font color unchanged
    local colorChanged = (f._msufGFCachedFR ~= fr or f._msufGFCachedFG ~= fg or f._msufGFCachedFB ~= fb)
    if colorChanged then
        f._msufGFCachedFR, f._msufGFCachedFG, f._msufGFCachedFB = fr, fg, fb
    end

    -- Skip redundant SetFont (path+size compare) + SetTextColor (color compare)
    local safeSetFont = _G.MSUF_SetFontSafe
    local function set(fs, size, r, g, b, a)
        if not fs then return end
        local curP, curS = fs:GetFont()
        if curP ~= fontPath or curS ~= size then
            if type(safeSetFont) == "function" then
                safeSetFont(fs, fontPath, size, fontFlags, fontKey)
            else
                fs:SetFont(fontPath, size, fontFlags)
            end
        end
        if r and colorChanged then fs:SetTextColor(r, g, b, a or 1) end
        fs:SetShadowOffset(0, 0)
    end

    set(f.nameText,              nameSize,     fr, fg, fb, 1)
    set(f.textLeftFS,            hpSize,       fr, fg, fb, 0.9)
    set(f.textCenterFS,          hpSize,       fr, fg, fb, 0.9)
    set(f.textRightFS,           hpSize,       fr, fg, fb, 0.9)
    do
        local statusSize = tonumber(conf.statusTextSize)
        if statusSize then
            if fScale ~= 1 then statusSize = math_max(6, math_floor(statusSize * fScale + 0.5)) end
        else
            statusSize = nameSize + 2
        end
        set(f.statusIndicatorText, statusSize, nil, nil, nil)
    end
    set(f.powerTextLeftFS,       powSize,      fr, fg, fb, 0.9)
    set(f.powerTextCenterFS,     powSize,      fr, fg, fb, 0.9)
    set(f.powerTextRightFS,      powSize,      fr, fg, fb, 0.9)
    if f.groupNumberText then
        local gnSize = conf.groupNumberSize or 10
        if fScale ~= 1 then gnSize = math_max(6, math_floor(gnSize * fScale + 0.5)) end
        set(f.groupNumberText, gnSize, fr, fg, fb, 0.7)
    end
end

------------------------------------------------------------------------
-- Apply: geometry (bar anchors, power height)
------------------------------------------------------------------------
local function ApplyGeometry(f, kind)
    local conf   = GF.GetConf(kind)
    local fScale = conf._resolvedFrameScale or 1
    local powerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, f.unit, f._msufGFPreviewRole, conf))
        or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind))
        or ScaleValue(conf.powerHeight or 6, fScale, 0))
    local inset  = math_max(0, (GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind)) or 2)
    if fScale ~= 1 then inset = ScaleValue(inset, fScale, 0) end

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

    if f.powerTextLayer then
        local pParent = f.barGroup or f
        if f.powerTextLayer.GetParent and f.powerTextLayer:GetParent() ~= pParent
            and not (InCombatLockdown and InCombatLockdown()) then
            f.powerTextLayer:SetParent(pParent)
        end
        f.powerTextLayer:ClearAllPoints()
        f.powerTextLayer:SetAllPoints(pParent)
        f.powerTextLayer:Show()
    end

    if f.nameTextLayer and f.health then
        if f.nameTextLayer.GetParent and f.nameTextLayer:GetParent() ~= f.health
            and not (InCombatLockdown and InCombatLockdown()) then
            f.nameTextLayer:SetParent(f.health)
        end
        f.nameTextLayer:ClearAllPoints()
        f.nameTextLayer:SetAllPoints(f.health)
        f.nameTextLayer:Show()
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
ResolveClassColor = function(cls)
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
-- Apply: health color (GF-independent barMode, then global fallback)
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end

    -- Spell Indicator health color override takes precedence
    if f._msufSIHealthColorR then
        f.health:SetStatusBarColor(f._msufSIHealthColorR, f._msufSIHealthColorG or 0, f._msufSIHealthColorB or 0, 1)
        return
    end

    local conf = GF.GetConf(kind)
    local gfMode = conf.gfBarMode  -- nil/"GLOBAL" = follow UF

    -- Resolve effective mode
    local mode
    if gfMode and gfMode ~= "GLOBAL" then
        mode = gfMode
    else
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = type(getCache) == "function" and getCache() or nil
        local globalMode = cache and cache.barMode
        if globalMode == "dark" or globalMode == "unified" then
            mode = globalMode
        else
            mode = conf.healthColorMode or "CLASS"
        end
    end

    if mode == "dark" then
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = type(getCache) == "function" and getCache() or nil
        local r = conf.gfDarkR or (cache and cache.darkBarR) or 0
        local g = conf.gfDarkG or (cache and cache.darkBarG) or 0
        local b = conf.gfDarkB or (cache and cache.darkBarB) or 0
        f.health:SetStatusBarColor(r, g, b, 1)
        return
    end
    if mode == "unified" then
        local getCache = _G.MSUF_UFCore_GetSettingsCache
        local cache = type(getCache) == "function" and getCache() or nil
        local r = conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10
        local g = conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60
        local b = conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90
        f.health:SetStatusBarColor(r, g, b, 1)
        return
    end

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
        local iss = GetSecretValueDetector()
        local secretHealth = (iss and (iss(hp) or iss(hpMax)))
            or (not iss and SecretModeActiveWithoutDetector())
        if secretHealth then
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
-- Apply: health bar foreground alpha (for behind-bar icon visibility)
-- Uses the statusbar fill texture alpha so spell/status indicators parented
-- around the health bar do not inherit HP opacity.
-- Text and status indicators stay parented to the normal health text layer.
------------------------------------------------------------------------
local function ResetHealthFrameAlpha(f)
    if f and f.health and f.health.SetAlpha and f._msufGFHealthFrameAlphaOne ~= true then
        f.health:SetAlpha(1)
        f._msufGFHealthFrameAlphaOne = true
    end
end

local function HidePreserveMissingHP(f)
    if f and f._msufGFMissingHPBg then f._msufGFMissingHPBg:Hide() end
end

local function ResolvePreserveMissingHPColor(f, kind)
    local source = f and (f._msufBehindBarBg or f.healthBg)
    if source and source.GetVertexColor then
        local r, g, b = source:GetVertexColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            -- Frame API colors can be secret-tagged in Midnight. They are safe
            -- to pass to C-side color setters, but not to compare/cache in Lua.
            return r, g, b, 1, true
        end
    end

    local conf = GF.GetConf(kind)
    if conf then
        return conf.bgR or 0.1,
            conf.bgG or 0.1,
            conf.bgB or 0.1,
            1
    end
    return UNHALTED_BG_R, UNHALTED_BG_G, UNHALTED_BG_B, 1
end

local function ApplyPreserveMissingHPColor(f, bg, kind)
    if not bg or not bg.SetStatusBarColor then return end
    local r, g, b, a, secretColor = ResolvePreserveMissingHPColor(f, kind)
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if secretColor then
        bg:SetStatusBarColor(r, g, b, a)
        bg._msufGFMissingR, bg._msufGFMissingG, bg._msufGFMissingB, bg._msufGFMissingA = nil, nil, nil, nil
        return
    end
    if bg._msufGFMissingR ~= r or bg._msufGFMissingG ~= g or bg._msufGFMissingB ~= b or bg._msufGFMissingA ~= a then
        bg:SetStatusBarColor(r, g, b, a)
        bg._msufGFMissingR, bg._msufGFMissingG, bg._msufGFMissingB, bg._msufGFMissingA = r, g, b, a
    end
end

local function EnsurePreserveMissingHP(f, kind)
    local h = f and f.health
    if not h then return nil end
    local bg = f._msufGFMissingHPBg
    if not bg then
        if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
        local CreateFrame = _G.CreateFrame
        if type(CreateFrame) ~= "function" then return nil end
        bg = CreateFrame("StatusBar", nil, f.barGroup or f)
        bg:SetMinMaxValues(0, 1)
        bg:SetValue(0)
        bg:Hide()
        f._msufGFMissingHPBg = bg
    end

    if bg._msufGFMissingAnchor ~= h then
        bg:ClearAllPoints()
        bg:SetAllPoints(h)
        bg._msufGFMissingAnchor = h
    end
    if bg.SetFrameLevel and h.GetFrameLevel then
        local lvl = (h:GetFrameLevel() or 1) - 1
        if lvl < 0 then lvl = 0 end
        if bg._msufGFMissingLevel ~= lvl then
            bg:SetFrameLevel(lvl)
            bg._msufGFMissingLevel = lvl
        end
    end
    local tex = ResolveUnhaltedTexture() or GF.ResolveBarBgTexture(kind)
    if tex and bg._msufGFMissingBgTex ~= tex then
        bg:SetStatusBarTexture(tex)
        bg._msufGFMissingBgTex = tex
    end
    ApplyPreserveMissingHPColor(f, bg, kind)
    if bg.SetReverseFill and h.GetReverseFill then
        local rev = not h:GetReverseFill()
        if bg._msufGFMissingReverse ~= rev then
            bg:SetReverseFill(rev)
            bg._msufGFMissingReverse = rev
        end
    end
    return bg
end

local function SyncPreserveMissingHP(f, kind, hp, hpMax)
    if not f or not f.health then return end
    kind = kind or f._msufGFKind or "party"
    local c = f._c
    local preserve
    if c and c.alphaPreserveHPColor ~= nil then
        preserve = c.alphaPreserveHPColor == true
    else
        local conf = GF.GetConf(kind)
        preserve = conf and conf.alphaPreserveHPColor == true
    end
    if f._msufGFPreserveAlphaState ~= preserve then
        f._msufGFPreserveAlphaState = preserve
        if f.healthBg and f.healthBg.SetAlpha then f.healthBg:SetAlpha(preserve and 0 or 1) end
        if f._msufBehindBarBg and f._msufBehindBarBg.SetAlpha then f._msufBehindBarBg:SetAlpha(preserve and 0 or 1) end
    end
    if not preserve then
        if f._msufGFPreserveAlphaState == false
            and not f._msufGFMissingHPBg
            and f._msufGFMissingValue == nil
            and f._msufGFMissingMax == nil then
            return
        end
        if f._msufGFMissingHPBg then HidePreserveMissingHP(f) end
        f._msufGFMissingValue, f._msufGFMissingMax = nil, nil
        return
    end

    local bg = EnsurePreserveMissingHP(f, kind)
    if not bg then return end
    ApplyPreserveMissingHPColor(f, bg, kind)
    local unit = f.unit
    if type(hpMax) == "nil" and unit and UnitHealthMax then hpMax = UnitHealthMax(unit) end
    if type(hpMax) == "nil" and f.health.GetMinMaxValues then
        local _, mx = f.health:GetMinMaxValues()
        hpMax = mx
    end

    local missing
    local iss = GetSecretValueDetector()
    local secretNoDetector = not iss and SecretModeActiveWithoutDetector()
    local comparable = type(hpMax) == "number" and type(hp) == "number"
        and not secretNoDetector
        and not (iss and (iss(hpMax) or iss(hp)))
    if comparable then
        missing = hpMax - hp
        if missing < 0 then missing = 0 end
    elseif unit and _G.UnitHealthMissing then
        missing = _G.UnitHealthMissing(unit, true)
    elseif not secretNoDetector then
        if type(hp) == "nil" and unit and UnitHealth then hp = UnitHealth(unit) end
        if type(hpMax) == "number" and type(hp) == "number" then
            missing = hpMax - hp
            if missing < 0 then missing = 0 end
        end
    end

    local maxValue = (type(hpMax) == "nil") and 1 or hpMax
    local maxSecret = secretNoDetector or (iss and iss(maxValue))
    if maxSecret then
        bg:SetMinMaxValues(0, maxValue)
        bg._msufGFMissingMax = nil
    elseif bg._msufGFMissingMax ~= maxValue then
        bg:SetMinMaxValues(0, maxValue)
        bg._msufGFMissingMax = maxValue
    end
    local value = (type(missing) == "nil") and 0 or missing
    local valueSecret = secretNoDetector or (iss and iss(value))
    if valueSecret then
        bg:SetValue(value)
        bg._msufGFMissingValue = nil
    elseif bg._msufGFMissingValue ~= value then
        bg:SetValue(value)
        bg._msufGFMissingValue = value
    end
    if not bg:IsShown() then bg:Show() end
end
GF.SyncPreserveMissingHP = SyncPreserveMissingHP

local function SetHealthColorAlpha(f, alpha, preserve, kind)
    local h = f and f.health
    if not h or not h.GetStatusBarColor or not h.SetStatusBarColor then return end
    if type(alpha) ~= "number" then alpha = 1 end
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    if h.SetStatusBarTexture then
        local tex
        if preserve == true then
            tex = ResolveUnhaltedTexture()
        elseif kind then
            tex = GF.ResolveBarTexture(kind)
            h._msufGFHpColorPreserveTexture = nil
        end
        local fill = h.GetStatusBarTexture and h:GetStatusBarTexture()
        local cur = fill and fill.GetTexture and fill:GetTexture()
        if tex and cur ~= tex then
            h:SetStatusBarTexture(tex)
            f._msufGFCachedHTex = tex
            h._msufGFHpColorPreserveTexture = (preserve == true) and tex or nil
        end
    end
    local r, g, b = h:GetStatusBarColor()
    h:SetStatusBarColor(r, g, b, 1)

    local backing = h._msufGFHpColorBacking
    if backing then
        backing:Hide()
        h._msufGFHpColorBackingR, h._msufGFHpColorBackingG, h._msufGFHpColorBackingB, h._msufGFHpColorBackingA = nil, nil, nil, nil
    end
    h._msufGFHpColorPreserveApplied = (preserve == true) or nil
    SyncPreserveMissingHP(f, kind)
end

local function RestoreHealthTextLayer(f)
    local txtLayer = f and f.healthTextLayer
    if not txtLayer or not f.health then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local nameLayer = f.nameTextLayer
    if nameLayer and (nameLayer._msufAlphaEscaped or nameLayer:GetParent() ~= f.health) then
        nameLayer:SetParent(f.health)
        nameLayer:SetAllPoints(f.health)
        GF.SetFrameLayerLevel(nameLayer, f, conf.nameTextLayer, 5)
        nameLayer._msufAlphaEscaped = nil
    end
    if txtLayer._msufAlphaEscaped or txtLayer:GetParent() ~= f.health then
        txtLayer:SetParent(f.health)
        txtLayer:SetAllPoints(f.health)
        GF.SetFrameLayerLevel(txtLayer, f, conf.textLayer, 5)
        txtLayer._msufAlphaEscaped = nil
    end
    local st = f.statusIndicatorText
    local stParent
    if GF.EnsureStatusTextLayer then
        stParent = GF.EnsureStatusTextLayer(f, GF.GetConf(f._msufGFKind or "party"), f._msufGFStatusState)
    end
    stParent = stParent or f.statusTextLayer or f.statusIconLayer or f.barGroup or f.health
    if st and stParent and st.SetParent and st.GetParent and st:GetParent() ~= stParent then
        st:SetParent(stParent)
    end
end

local function ApplyHealthBarAlpha(f, kind)
    if not f.health then return end
    local conf = GF.GetConf(kind)
    local fgA = GetGFHealthAlpha(kind, conf)
    if fgA < 0 then fgA = 0 elseif fgA > 1 then fgA = 1 end
    local preserveHPColor = (conf.alphaPreserveHPColor == true)

    local dynamic = (f._msufGFHealthAlphaDynamic == true)
    if f._msufSIHealthColorR then
        -- Spell Indicator health tint is itself an indicator. The HP alpha
        -- slider must not dim that effect.
        fgA = 1
    end
    local boolValue = f._msufGFHealthAlphaBool
    local boolSecret = type(boolValue) ~= "nil" and IsSecretRuntimeValue(boolValue)
    local falseMul = tonumber(f._msufGFHealthAlphaFalseMul) or 1
    if falseMul < 0 then falseMul = 0 elseif falseMul > 1 then falseMul = 1 end
    local falseA = fgA * falseMul
    local activeA = fgA
    local inactiveA = falseA
    local healthTex = f.health.GetStatusBarTexture and f.health:GetStatusBarTexture()

    if dynamic and type(boolValue) ~= "nil" and healthTex and healthTex.SetAlphaFromBoolean then
        -- boolValue may be secret; pass it straight to C-side SetAlphaFromBoolean.
        f._msufCachedHpBarAlpha = nil
        f._msufCachedHpBarAlphaTarget = nil
        ResetHealthFrameAlpha(f)
        SetHealthColorAlpha(f, fgA, preserveHPColor, kind)
        healthTex:SetAlphaFromBoolean(boolValue, activeA, inactiveA)
        SetStatusBarTextureAlphaFromBoolean(f.absorbBar, boolValue, activeA, inactiveA)
        SetStatusBarTextureAlphaFromBoolean(f.healAbsorbBar, boolValue, activeA, inactiveA)
        SetStatusBarTextureAlphaFromBoolean(f.incomingHealBar, boolValue, activeA, inactiveA)
    elseif dynamic and type(boolValue) ~= "nil" and boolSecret and f.health.SetAlphaFromBoolean then
        -- Fallback for clients where statusbar textures cannot consume secret
        -- booleans directly.
        f._msufCachedHpBarAlpha = nil
        f._msufCachedHpBarAlphaTarget = nil
        f._msufGFHealthFrameAlphaOne = nil
        SetHealthColorAlpha(f, fgA, preserveHPColor, kind)
        f.health:SetAlphaFromBoolean(boolValue, fgA, falseA)
        SetStatusBarTextureAlphaFromBoolean(f.absorbBar, boolValue, activeA, inactiveA)
        SetStatusBarTextureAlphaFromBoolean(f.healAbsorbBar, boolValue, activeA, inactiveA)
        SetStatusBarTextureAlphaFromBoolean(f.incomingHealBar, boolValue, activeA, inactiveA)
    else
        local mul
        if dynamic then
            if type(boolValue) ~= "nil" and not boolSecret then
                mul = (boolValue == false) and falseMul or 1
            else
                mul = tonumber(f._msufGFHealthAlphaMul) or falseMul
            end
        else
            mul = tonumber(f._msufGFHealthAlphaMul) or 1
        end
        if mul < 0 then mul = 0 elseif mul > 1 then mul = 1 end
        local targetA = fgA * mul
        local alphaTarget = healthTex or f.health
        if healthTex then ResetHealthFrameAlpha(f) else f._msufGFHealthFrameAlphaOne = nil end
        SetHealthColorAlpha(f, targetA, preserveHPColor, kind)
        local needsApply = (f._msufCachedHpBarAlpha ~= targetA) or (f._msufCachedHpBarAlphaTarget ~= alphaTarget)
        -- SetStatusBarColor may reset the fill texture alpha without touching
        -- our cache. When HP opacity is active, re-assert the texture alpha.
        if targetA < 0.999 then needsApply = true end
        if needsApply then
            f._msufCachedHpBarAlpha = targetA
            f._msufCachedHpBarAlphaTarget = alphaTarget
            if alphaTarget and alphaTarget.SetAlpha then
                alphaTarget:SetAlpha(targetA)
            end
        end
        SetStatusBarTextureAlpha(f.absorbBar, targetA)
        SetStatusBarTextureAlpha(f.healAbsorbBar, targetA)
        SetStatusBarTextureAlpha(f.incomingHealBar, targetA)
        falseA = targetA
    end
    RestoreHealthTextLayer(f)
end
GF.ApplyHealthBarAlpha = ApplyHealthBarAlpha

local function ApplyPowerBarAlpha(f, kind)
    if not f or not f.power then return end
    local conf = GF.GetConf(kind)
    SetStatusBarTextureAlpha(f.power, GetGFPowerAlpha(kind, conf))
end
GF.ApplyPowerBarAlpha = ApplyPowerBarAlpha

local function ApplyFrameAlpha(f, kind)
    if not f or not f.SetAlpha then return end
    f:SetAlpha(GetGFFrameAlpha(kind, GF.GetConf(kind)))
end
GF.ApplyFrameAlpha = ApplyFrameAlpha

------------------------------------------------------------------------
-- Apply: text layout
------------------------------------------------------------------------
local function ApplyTextLayout(f, kind)
    local conf = GF.GetConf(kind)
    local fScale = conf._resolvedFrameScale or 1
    local pad3 = ScaleValue(3, fScale, 1)
    local pad2 = ScaleValue(2, fScale, 1)
    local nox = ScaleValue(conf.nameOffsetX or 0, fScale)
    local noy = ScaleValue(conf.nameOffsetY or 0, fScale)

    if not f.nameTextLayer and f.health and CreateFrame and not (InCombatLockdown and InCombatLockdown()) then
        f.nameTextLayer = CreateFrame("Frame", nil, f.health)
        f.nameTextLayer:SetAllPoints(f.health)
    end

    if f.nameText then
        if f.nameTextLayer and f.nameText.SetParent and f.nameText.GetParent and f.nameText:GetParent() ~= f.nameTextLayer then
            f.nameText:SetParent(f.nameTextLayer)
        end
        f.nameText:ClearAllPoints()
        local anchor = conf.nameAnchor or "LEFT"
        if anchor == "CENTER" then
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3 + nox, noy)
            f.nameText:SetJustifyH("CENTER")
        elseif anchor == "RIGHT" then
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3 + nox, noy)
            f.nameText:SetJustifyH("RIGHT")
        else
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3, noy)
            f.nameText:SetJustifyH("LEFT")
        end
        f.nameText:SetWordWrap(false)
        if conf.showName ~= false then f.nameText:Show() else f.nameText:Hide() end
    end

    -- 3-slot health text
    local hox = ScaleValue(conf.hpOffsetX or 0, fScale)
    local hoy = ScaleValue(conf.hpOffsetY or 0, fScale)
    local hlx = ScaleValue(conf.hpTextLeftOffsetX or 0, fScale)
    local hly = ScaleValue(conf.hpTextLeftOffsetY or 0, fScale)
    local hcx = ScaleValue(conf.hpTextCenterOffsetX or 0, fScale)
    local hcy = ScaleValue(conf.hpTextCenterOffsetY or 0, fScale)
    local hrx = ScaleValue(conf.hpTextRightOffsetX or 0, fScale)
    local hry = ScaleValue(conf.hpTextRightOffsetY or 0, fScale)
    local hpTextOn = conf.showHPText ~= false
    local tl = hpTextOn and (conf.textLeft  or "NONE") or "NONE"
    local tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
    local tr = hpTextOn and (conf.textRight or "NONE") or "NONE"

    if f.textLeftFS then
        f.textLeftFS:ClearAllPoints()
        f.textLeftFS:SetPoint("LEFT", f.health, "LEFT", pad3 + hox + hlx, hoy + hly)
        f.textLeftFS:SetJustifyH("LEFT")
        if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:SetText(""); f.textLeftFS:Hide() end
    end
    if f.textCenterFS then
        f.textCenterFS:ClearAllPoints()
        f.textCenterFS:SetPoint("CENTER", f.health, "CENTER", hox + hcx, hoy + hcy)
        f.textCenterFS:SetJustifyH("CENTER")
        if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:SetText(""); f.textCenterFS:Hide() end
    end
    if f.textRightFS then
        f.textRightFS:ClearAllPoints()
        f.textRightFS:SetPoint("RIGHT", f.health, "RIGHT", -pad3 + hox + hrx, hoy + hry)
        f.textRightFS:SetJustifyH("RIGHT")
        if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:SetText(""); f.textRightFS:Hide() end
    end

    if f.statusIndicatorText then
        local stParent
        if GF.EnsureStatusTextLayer then
            stParent = GF.EnsureStatusTextLayer(f, conf, f._msufGFStatusState)
        end
        stParent = stParent or f.statusTextLayer or f.statusIconLayer or f.barGroup or f.health
        if stParent and f.statusIndicatorText.SetParent and f.statusIndicatorText.GetParent
            and f.statusIndicatorText:GetParent() ~= stParent
        then
            f.statusIndicatorText:SetParent(stParent)
        end
        f.statusIndicatorText:ClearAllPoints()
        local anchor = conf.statusTextAnchor or "CENTER"
        f.statusIndicatorText:SetPoint(anchor, f.health, anchor,
            ScaleValue(conf.statusOffsetX or 0, fScale),
            ScaleValue(conf.statusOffsetY or 0, fScale))
        if f.statusIndicatorText.SetJustifyH then
            local j = "CENTER"
            if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" or anchor == "LEFT" then
                j = "LEFT"
            elseif anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "RIGHT" then
                j = "RIGHT"
            end
            f.statusIndicatorText:SetJustifyH(j)
        end
        if f.statusIndicatorText.SetDrawLayer then
            local sub = tonumber(conf.statusTextLayer) or 7
            if sub < 0 then sub = 0 elseif sub > 7 then sub = 7 end
            f.statusIndicatorText:SetDrawLayer("OVERLAY", sub)
        end
        if f._msufGFStatusState and f._msufGFStatusState ~= 0 and GF.ApplyStatusTextStateLayout then
            GF.ApplyStatusTextStateLayout(f, conf, f._msufGFStatusState)
        end
    end

    -- 3-slot power text
    local pox = ScaleValue(conf.powerOffsetX or 0, fScale)
    local poy = ScaleValue(conf.powerOffsetY or 0, fScale)
    local plx = ScaleValue(conf.powerTextLeftOffsetX or 0, fScale)
    local ply = ScaleValue(conf.powerTextLeftOffsetY or 0, fScale)
    local pcx = ScaleValue(conf.powerTextCenterOffsetX or 0, fScale)
    local pcy = ScaleValue(conf.powerTextCenterOffsetY or 0, fScale)
    local prx = ScaleValue(conf.powerTextRightOffsetX or 0, fScale)
    local pry = ScaleValue(conf.powerTextRightOffsetY or 0, fScale)
    local effectivePowerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, f.unit, f._msufGFPreviewRole, conf))
        or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind))
        or ScaleValue(conf.powerHeight or 6, fScale, 0))
    local showPow = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) or false
    local ptl = showPow and (conf.powerTextLeft   or "NONE") or "NONE"
    local ptc = showPow and (conf.powerTextCenter  or "NONE") or "NONE"
    local ptr = showPow and (conf.powerTextRight   or "NONE") or "NONE"
    local powerTextAnchor = (effectivePowerH > 0 and f.power) or f.health or f.barGroup

    if f.powerTextLeftFS then
        f.powerTextLeftFS:ClearAllPoints()
        f.powerTextLeftFS:SetPoint("LEFT", powerTextAnchor, "LEFT", pad2 + pox + plx, poy + ply)
        f.powerTextLeftFS:SetJustifyH("LEFT")
        if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
    end
    if f.powerTextCenterFS then
        f.powerTextCenterFS:ClearAllPoints()
        f.powerTextCenterFS:SetPoint("CENTER", powerTextAnchor, "CENTER", pox + pcx, poy + pcy)
        f.powerTextCenterFS:SetJustifyH("CENTER")
        if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
    end
    if f.powerTextRightFS then
        f.powerTextRightFS:ClearAllPoints()
        f.powerTextRightFS:SetPoint("RIGHT", powerTextAnchor, "RIGHT", -pad2 + pox + prx, poy + pry)
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
            gnX = ScaleValue(gnX, fScale)
            gnY = ScaleValue(gnY, fScale)
            f.groupNumberText:SetPoint(gnAnchor, f.health or f.barGroup, gnAnchor, gnX, gnY)
            f.groupNumberText:SetJustifyH("RIGHT")
        else
            f.groupNumberText:Hide()
        end
    end

    -- Text layer (frame level above health bar)
    if f.nameTextLayer and f.health then
        local want = GF.GetFrameLayerLevel(f, conf.nameTextLayer, 5)
        if f._msufGFCachedNameTxtLvl ~= want then
            f._msufGFCachedNameTxtLvl = want
            f.nameTextLayer:SetFrameLevel(want)
        end
    end
    if f.healthTextLayer and f.health then
        local want = GF.GetFrameLayerLevel(f, conf.textLayer, 5)
        if f._msufGFCachedTxtLvl ~= want then
            f._msufGFCachedTxtLvl = want
            f.healthTextLayer:SetFrameLevel(want)
        end
    end
    if f.powerTextLayer then
        local want = GF.GetFrameLayerLevel(f, conf.powerTextLayer, 2)
        if f._msufGFCachedPTxtLvl ~= want then
            f._msufGFCachedPTxtLvl = want
            f.powerTextLayer:SetFrameLevel(want)
        end
    end
end

------------------------------------------------------------------------
-- Apply: icon layout (spec-driven)
------------------------------------------------------------------------
local ICON_SPECS = {
    { field="roleIcon",      enKey="roleIcon",      sizeKey="roleIconSize",      anchorKey="roleIconAnchor",    xKey="roleIconX",    yKey="roleIconY",    layerKey="roleIconLayer",    defAnchor="TOPLEFT",    defSize=12, defLayer=1 },
    { field="leaderIcon",    enKey="leaderIcon",     sizeKey="leaderIconSize",    anchorKey="leaderIconAnchor",  xKey="leaderIconX",  yKey="leaderIconY",  layerKey="leaderIconLayer",  defAnchor="TOPRIGHT",   defSize=12, defLayer=2 },
    { field="assistIcon",    enKey="assistIcon",     sizeKey="assistIconSize",    anchorKey="assistIconAnchor",  xKey="assistIconX",  yKey="assistIconY",  layerKey="assistIconLayer",  defAnchor="TOPRIGHT",   defSize=12, defLayer=2 },
    { field="raidIcon",      enKey="raidMarker",     sizeKey="raidMarkerSize",    anchorKey="raidMarkerAnchor",  xKey="raidMarkerX",  yKey="raidMarkerY",  layerKey="raidMarkerLayer",  defAnchor="CENTER",     defSize=14, defLayer=3 },
    { field="readyCheckIcon",enKey="readyCheckIcon", sizeKey="readyCheckSize",    anchorKey="readyCheckAnchor",  xKey="readyCheckX",  yKey="readyCheckY",  layerKey="readyCheckLayer",  defAnchor="CENTER",     defSize=16, defLayer=4 },
    { field="summonIcon",    enKey="summonIcon",     sizeKey="summonIconSize",    anchorKey="summonAnchor",      xKey="summonX",      yKey="summonY",      layerKey="summonLayer",      defAnchor="CENTER",     defSize=16, defLayer=4 },
    { field="resurrectIcon", enKey="resurrectIcon",  sizeKey="resurrectIconSize", anchorKey="resurrectAnchor",   xKey="resurrectX",   yKey="resurrectY",   layerKey="resurrectLayer",   defAnchor="CENTER",     defSize=16, defLayer=4 },
    { field="phaseIcon",     enKey="phaseIcon",      sizeKey="phaseIconSize",     anchorKey="phaseAnchor",       xKey="phaseX",       yKey="phaseY",       layerKey="phaseLayer",       defAnchor="TOPLEFT",    defSize=14, defLayer=3 },
}
GF.ICON_SPECS = ICON_SPECS

local function ApplyIconLayout(f, kind)
    local conf   = GF.GetConf(kind)
    local anchor = f.statusIconLayer or f.barGroup or f
    local base = f.health or anchor
    local baseLvl = base.GetFrameLevel and base:GetFrameLevel() or anchor:GetFrameLevel()
    local fScale = conf._resolvedFrameScale or 1

    for i = 1, #ICON_SPECS do
        local s = ICON_SPECS[i]
        local icon = f[s.field]
        if icon then
            local region = icon._msufGFLayerFrame or icon
            region:ClearAllPoints()
            local sz = conf[s.sizeKey] or s.defSize
            if fScale ~= 1 then sz = math_max(4, math_floor(sz * fScale + 0.5)) end
            region:SetSize(sz, sz)
            local pt = conf[s.anchorKey] or s.defAnchor
            local ox = conf[s.xKey] or 0
            local oy = conf[s.yKey] or 0
            if fScale ~= 1 then
                ox = ScaleValue(ox, fScale)
                oy = ScaleValue(oy, fScale)
            end
            region:SetPoint(pt, anchor, pt, ox, oy)
            local layer = tonumber(conf[s.layerKey]) or s.defLayer
            if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
            local frameLevel = (GF.GetFrameLayerLevel and GF.GetFrameLayerLevel(f, layer, s.defLayer)) or (baseLvl + layer)
            if region.SetFrameLevel then region:SetFrameLevel(frameLevel) end
            if region ~= icon then
                icon:ClearAllPoints()
                icon:SetAllPoints(region)
            end
            if icon.SetDrawLayer then
                icon:SetDrawLayer("OVERLAY", 7)
            elseif icon.SetFrameLevel then
                icon:SetFrameLevel(frameLevel)
            end
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
    local dbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
    local db = _G.MSUF_DB and _G.MSUF_DB[dbKey]
    if db and db.hlOverride and db[key] ~= nil then return db[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return gen and gen[key]
end

local function ApplyOverlayColors(f)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local kind = f._msufGFKind or "party"
    -- Incoming heal (heal prediction) — colors from general (shared)
    if f.incomingHealBar and f._c and f._c.healPredEn == true then
        local r, g, b = 0.0, 1.0, 0.4
        if gen then
            if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
            if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
            if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
        end
        local a = 0.45
        if f._gfCIHR ~= r or f._gfCIHG ~= g or f._gfCIHB ~= b then
            f._gfCIHR, f._gfCIHG, f._gfCIHB = r, g, b
            f.incomingHealBar:SetStatusBarColor(r, g, b, a)
        end
    end
    -- Absorb (color from general, opacity per-GF override → general)
    if f.absorbBar then
        local r, g, b = 0.8, 0.9, 1.0
        if gen then
            if type(gen.absorbBarColorR) == "number" then r = gen.absorbBarColorR end
            if type(gen.absorbBarColorG) == "number" then g = gen.absorbBarColorG end
            if type(gen.absorbBarColorB) == "number" then b = gen.absorbBarColorB end
        end
        local a = tonumber(_GF_ResolveOverlaySetting(kind, "absorbBarOpacity")) or 0.6
        if f._gfCAbR ~= r or f._gfCAbG ~= g or f._gfCAbB ~= b or f._gfCAbA ~= a then
            f._gfCAbR, f._gfCAbG, f._gfCAbB, f._gfCAbA = r, g, b, a
            f.absorbBar:SetStatusBarColor(r, g, b, 1)
            SetOverlayStatusBarTextureAlpha(f.absorbBar, a)
        end
    end
    -- Heal absorb (color from general, opacity per-GF override → general)
    if f.healAbsorbBar then
        local r, g, b = 1.0, 0.4, 0.4
        if gen then
            if type(gen.healAbsorbBarColorR) == "number" then r = gen.healAbsorbBarColorR end
            if type(gen.healAbsorbBarColorG) == "number" then g = gen.healAbsorbBarColorG end
            if type(gen.healAbsorbBarColorB) == "number" then b = gen.healAbsorbBarColorB end
        end
        local a = tonumber(_GF_ResolveOverlaySetting(kind, "healAbsorbBarOpacity")) or 0.7
        if f._gfCHAbR ~= r or f._gfCHAbG ~= g or f._gfCHAbB ~= b or f._gfCHAbA ~= a then
            f._gfCHAbR, f._gfCHAbG, f._gfCHAbB, f._gfCHAbA = r, g, b, a
            f.healAbsorbBar:SetStatusBarColor(r, g, b, 1)
            SetOverlayStatusBarTextureAlpha(f.healAbsorbBar, a)
        end
    end
    -- Absorb anchoring (per-GF override → general).
    -- NOTE: no caller-side stamp check — the internal diff-gate in
    -- _GF_ApplyAbsorbAnchor already covers stamp + FollowActive + RF + W, and
    -- a stamp-only caller gate would strand mode 4 overflow bars at stale w
    -- when hpBar width changes without a mode change (fresh frame layout, size
    -- change, power-row toggle). ApplyOverlayColors fires on DIRTY_COLOR; width
    -- updates from DIRTY_GEOMETRY/DIRTY_LAYOUT are caught by the unconditional
    -- call added in ApplyVisuals below.
    if f._c and f._c.healPredEn == true and GF._ApplyHealPredAnchor then
        GF._ApplyHealPredAnchor(f)
    end
    if GF._ApplyAbsorbAnchor then
        GF._ApplyAbsorbAnchor(f)
    end
end

------------------------------------------------------------------------
-- Apply all visuals for one frame (selective via bits)
------------------------------------------------------------------------
local function ApplyVisuals(f, bits)
    if not f then return end
    local kind = f._msufGFKind or "party"
    local needGeometry = (band(bits, DIRTY_GEOMETRY) ~= 0)

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
        ApplyBackgroundTint(f, kind)
        ApplyOverlayColors(f)
        ApplyHealthBarAlpha(f, kind)
        ApplyPowerBarAlpha(f, kind)
    end
    if band(bits, DIRTY_BORDER) ~= 0 then
        ApplyFrameBorder(f, kind)
        ApplyBackgroundTint(f, kind)
        ApplyHealthBarAlpha(f, kind)
        ApplyPowerBarAlpha(f, kind)
        ApplyEffectBorderStyles(f, kind)
    end
    if band(bits, DIRTY_LAYOUT) ~= 0 then
        ApplyTextLayout(f, kind)
        ApplyIconLayout(f, kind)
        if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(f, kind) end
    end
    -- Absorb anchor: ensure mode 4 overflow and mode 3 clipping track hpBar
    -- width changes from DIRTY_GEOMETRY / DIRTY_LAYOUT (not just DIRTY_COLOR
    -- via ApplyOverlayColors). Internal diff-gate short-circuits no-ops at ~2μs.
    if f._c and f._c.healPredEn == true and GF._ApplyHealPredAnchor then
        GF._ApplyHealPredAnchor(f)
    end
    if GF._ApplyAbsorbAnchor then
        GF._ApplyAbsorbAnchor(f)
    end
    -- Rebuild hot-path settings cache (eliminates GF.GetConf from combat events)
    if GF.BuildFrameCache then GF.BuildFrameCache(f) end
    if _G.MSUF_RoundedUF_Active == true then
        local applyRounded = _G.MSUF_RoundedUF_OnGroupFrameApplied
        if type(applyRounded) == "function" then
            applyRounded(f, kind)
        end
    end
end

------------------------------------------------------------------------
-- Flush dirty queue
------------------------------------------------------------------------
local _cachedUpdateAll -- cached reference to MSUF_GF_UpdateAll
local _cachedUpdateVisualDirty -- cached reference to MSUF_GF_UpdateVisualDirty

function GF._FlushDirty()
    if not _cachedUpdateAll then
        local fn = _G.MSUF_GF_UpdateAll
        if type(fn) == "function" then _cachedUpdateAll = fn end
    end
    if not _cachedUpdateVisualDirty then
        local fn = _G.MSUF_GF_UpdateVisualDirty
        if type(fn) == "function" then _cachedUpdateVisualDirty = fn end
    end

    local anyFlushed = false
    local processed = 0
    local maxPerFlush = 8
    local budgetMs = 0.35
    local db = _G.MSUF_DB
    local perf = db and db.performance
    if perf then
        maxPerFlush = tonumber(perf.gfMaxFramesPerFlush) or maxPerFlush
        budgetMs = tonumber(perf.gfFlushBudgetMs) or budgetMs
    end
    if maxPerFlush < 1 then maxPerFlush = 1 end

    local endAt
    if _G.debugprofilestop then
        endAt = _G.debugprofilestop() + budgetMs
    end

    while _head <= _tail do
        local f = _queue[_head]
        _queue[_head] = nil
        _head = _head + 1

        if f then
            local bits = _dirtyBits[f]
            _dirtyBits[f] = nil
            _queued[f] = nil

            if bits and RuntimeEnabledForFrame(f) then
                anyFlushed = true
                ApplyVisuals(f, bits)
                if f._msufGFPreviewActive then
                    local idx = f._msufGFPreviewIndex
                    local kind = f._msufGFKind
                    if idx and kind then
                        GF.ApplyPreviewData(f, idx, kind)
                    end
                elseif f.unit and UnitExists(f.unit) then
                    if _cachedUpdateVisualDirty then
                        _cachedUpdateVisualDirty(f, f.unit, bits)
                    elseif _cachedUpdateAll then
                        _cachedUpdateAll(f, f.unit)
                    end
                end
            end
        end

        processed = processed + 1
        if processed >= maxPerFlush then
            ScheduleFlush()
            return
        end
        if endAt and processed % 4 == 0 and _G.debugprofilestop() > endAt then
            ScheduleFlush()
            return
        end
    end

    _ResetQueueIfEmpty()
    if anyFlushed and GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
end

------------------------------------------------------------------------
-- Options-open/OOC full refresh helper
-- Runtime stays budgeted; Options changes outside combat use one coalesced full
-- refresh so legacy option paths remain instantly correct without reintroducing
-- full updates in combat.
------------------------------------------------------------------------
function GF._OptionsFullRefreshAllowed()
    local ic = _G.InCombatLockdown
    if ic and ic() then return false end
    local win = _G.MSUF_StandaloneOptionsWindow
    if win and win.IsShown and win:IsShown() then return true end
    local p = _G.MSUF_OptionsPanel
    if p and p.IsShown and p:IsShown() then return true end
    local sp = _G.SettingsPanel
    if sp and sp.IsShown and sp:IsShown() and p then return true end
    return false
end

function GF._ScheduleOptionsFullRefresh()
    local sched = _G.MSUF_ScheduleOnce
    if type(sched) == "function" then
        sched("GF_OPTIONS_FULL_REFRESH", function()
            if GF._OptionsFullRefreshAllowed and GF._OptionsFullRefreshAllowed() and GF.RefreshVisuals then
                GF.RefreshVisuals()
            end
        end)
    else
        C_Timer.After(0, function()
            if GF._OptionsFullRefreshAllowed and GF._OptionsFullRefreshAllowed() and GF.RefreshVisuals then
                GF.RefreshVisuals()
            end
        end)
    end
end

------------------------------------------------------------------------
-- Public: mark single frame dirty
------------------------------------------------------------------------
function GF.MarkDirty(f, bits)
    if not f then return end
    if not RuntimeEnabledForFrame(f) then return end
    bits = bits or DIRTY_ALL
    local prev = _dirtyBits[f] or 0
    _dirtyBits[f] = bor(prev, bits)
    _Enqueue(f)
    ScheduleFlush()
end

------------------------------------------------------------------------
-- Memory-leak Fix1 support: drop a retiring frame from the dirty queue
-- so RetireHeader → _GF_OnFrameRetire can release the strong-ref before
-- the next coalesced flush would touch the (now hidden) frame.
------------------------------------------------------------------------
function GF._RetireFromDirty(f)
    if not f then return end
    _dirtyBits[f] = nil
    _queued[f] = nil
    -- Queue slots are lazily skipped on flush; avoids O(n) removal.
end

------------------------------------------------------------------------
-- Public: mark ALL GF frames dirty (Options "Apply")
------------------------------------------------------------------------
function GF.MarkAllDirty(bits)
    bits = bits or DIRTY_ALL
    if InCombatLockdown and InCombatLockdown() then
        if GF.UpdateAnyEnabledFlag then GF.UpdateAnyEnabledFlag() end
        if GF._anyEnabled == false then return end
        if band(bits, bor(DIRTY_GEOMETRY, DIRTY_LAYOUT)) ~= 0 then
            GF._pendingRefreshGeometry = true
        end
        GF._pendingRefreshVisuals = true
        return
    end

    -- OOC Options path: one coalesced full refresh. This preserves exact live
    -- feedback for legacy option widgets while combat/runtime remains granular.
    if GF._OptionsFullRefreshAllowed and GF._OptionsFullRefreshAllowed() then
        if GF._ScheduleOptionsFullRefresh then GF._ScheduleOptionsFullRefresh() end
        return
    end

    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f and RuntimeEnabledForFrame(f) then
                local prev = _dirtyBits[f] or 0
                _dirtyBits[f] = bor(prev, bits)
                _Enqueue(f)
            end
        end
    else
        for f in pairs(GF.frames) do
            if RuntimeEnabledForFrame(f) then
                local prev = _dirtyBits[f] or 0
                _dirtyBits[f] = bor(prev, bits)
                _Enqueue(f)
            end
        end
    end
    -- Also mark preview frames
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local f = list[i]
                if f then
                    local prev = _dirtyBits[f] or 0
                    _dirtyBits[f] = bor(prev, bits)
                    _Enqueue(f)
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
    if InCombatLockdown and InCombatLockdown() then
        if GF.UpdateAnyEnabledFlag then GF.UpdateAnyEnabledFlag() end
        if GF._anyEnabled == false then return end
        GF._pendingRefreshVisuals = true
        return
    end
    if not _cachedUpdateAll then
        local fn = _G.MSUF_GF_UpdateAll
        if type(fn) == "function" then _cachedUpdateAll = fn end
    end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f and RuntimeEnabledForFrame(f) then
                ApplyVisuals(f, DIRTY_ALL)
                if f.unit and UnitExists(f.unit) and not f._msufGFPreviewActive then
                    if _cachedUpdateAll then _cachedUpdateAll(f, f.unit) end
                end
            end
        end
    else
        for f in pairs(GF.frames) do
            if RuntimeEnabledForFrame(f) then
                ApplyVisuals(f, DIRTY_ALL)
                if f.unit and UnitExists(f.unit) and not f._msufGFPreviewActive then
                    if _cachedUpdateAll then _cachedUpdateAll(f, f.unit) end
                end
            end
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
    if GF.RefreshGroupBorders then GF.RefreshGroupBorders() end
end

------------------------------------------------------------------------
-- Public: refresh only specific aspects
------------------------------------------------------------------------
function GF.RefreshTextures()
    GF.MarkAllDirty(DIRTY_TEXTURE)
end

function GF.RefreshFonts()
    GF.MarkAllDirty(DIRTY_FONT)
    if GF.InvalidateCdFont then GF.InvalidateCdFont() end
    -- Font color may also change when fonts change (Options panel groups them);
    -- invalidate the cooldown-text color cache so next render pulls fresh DB values.
    if GF.InvalidateCdColor then GF.InvalidateCdColor() end
end

function GF.RefreshColors()
    GF.MarkAllDirty(bor(DIRTY_COLOR, DIRTY_BORDER))
    -- Color settings can include useCustomFontColor / fontColorCustomR/G/B
    -- which feed ResolveCooldownBaseColor — invalidate so next render is fresh.
    if GF.InvalidateCdColor then GF.InvalidateCdColor() end
end

function GF.RefreshGeometry()
    if InCombatLockdown and InCombatLockdown() then
        GF._pendingRefreshGeometry = true
        return
    end
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
            if not RuntimeEnabledForFrame(f) then return end
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
        -- Re-cache UpdateAll after all hooks have been applied
        local fn = _G.MSUF_GF_UpdateAll
        if type(fn) == "function" then _cachedUpdateAll = fn end
    end)
end

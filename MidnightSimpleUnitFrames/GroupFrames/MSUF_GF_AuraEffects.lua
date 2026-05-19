-- MSUF_GF_AuraEffects.lua
-- Group Frame aura-effects runtime: UNIT_AURA dispatch, dispel scanning,
-- dispel overlay/glow, debuff stripe, and shared highlight-border refresh.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown or function() return false end
local UnitExists = _G.UnitExists
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local AuraUtil = _G.AuraUtil
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime
local C_UnitAuras = _G.C_UnitAuras
local LCG = _G.LibStub and _G.LibStub("LibCustomGlow-1.0", true)
local math_max = math.max

local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function _MSUF_ScheduleDelayOnce(key, delay, fn)
    local sched = _G.MSUF_ScheduleDelayOnce
    if sched then return sched(key, delay, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(delay or 0, fn) end
    if type(fn) == "function" then return fn() end
end

local function HLVal(kind, key)
    local fn = GF.HighlightValue
    if type(fn) == "function" then return fn(kind, key) end
    local conf = GF.GetConf and GF.GetConf(kind)
    return conf and conf[key]
end

local function _GF_IsBlizzardDispelRendererActive(conf)
    local fn = GF.IsBlizzardDispelRendererActive
    if type(fn) == "function" then return fn(conf) end
    return false
end

local function _applyHighlightBorderStyle(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a)
    local fn = GF.ApplyHighlightBorderStyle or _G.MSUF_GF_ApplyHLBorderStyle
    if type(fn) == "function" then return fn(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a) end
end

local function _NotifyRoundedGFHighlight(border)
    local fn = GF.NotifyRoundedHighlight
    if type(fn) == "function" then return fn(border) end
    if _G.MSUF_RoundedUF_Active ~= true then return end
    fn = _G.MSUF_RoundedUF_OnGroupHighlightChanged
    if type(fn) == "function" then fn(border) end
end

local function GetDispelColor(dispelName)
    -- DB per-type color takes priority (Colors > Dispel panel)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and type(dispelName) == "string" then
        local r = gen["dispelType" .. dispelName .. "R"]
        if type(r) == "number" then
            return r, gen["dispelType" .. dispelName .. "G"], gen["dispelType" .. dispelName .. "B"]
        end
    end
    -- Hardcoded fallback
    local c = DISPEL_COLORS[dispelName]
    if c then return c[1], c[2], c[3] end
    -- Blizzard color objects
    local obj = _G["DEBUFF_TYPE_" .. (dispelName or ""):upper() .. "_COLOR"]
    if obj then
        if obj.GetRGB then return obj:GetRGB() end
        if obj.r then return obj.r, obj.g, obj.b end
    end
    return nil
end

local function GetReadableDispelTypeName(dispelName)
    if dispelName == nil then return nil end
    if issecretvalue and issecretvalue(dispelName) then return nil end
    if type(dispelName) ~= "string" or dispelName == "" or dispelName == "None" or dispelName == "DISPELLABLE" then
        return nil
    end
    return dispelName
end

local function ExtractColorRGB(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b
    end
    if colorObj.GetRGBA then
        local rr, gg, bb = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb end
    end
    return nil
end

local function ExtractColorRGBA(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b, colorObj.a or 1
    end
    if colorObj.GetRGBA then
        local rr, gg, bb, aa = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb, aa end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb, 1 end
    end
    return nil
end

local function GFDispelColorScopeValue(kind, key, legacyKey, fallback)
    local conf = kind and GF.GetConf and GF.GetConf(kind)
    if conf and conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
        if legacyKey and conf[legacyKey] ~= nil then return conf[legacyKey] end
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        if gen[key] ~= nil then return gen[key] end
        if legacyKey and gen[legacyKey] ~= nil then return gen[legacyKey] end
    end
    return fallback
end

------------------------------------------------------------------------
-- Secret-safe dispel color resolution.
--
-- SINGLE mode Ã¢â€ â€™ plain (r,g,b) triplet from the Colors panel.
-- TYPE mode   Ã¢â€ â€™ a *Color object* from C_UnitAuras.GetAuraDispelTypeColor.
--               The Color object carries secret-safe RGBA that can ONLY be
--               applied via texture:SetVertexColor(color:GetRGBA()). It
--               MUST NOT be unpacked into Lua locals and fed to
--               CreateColor / SetGradient / arithmetic Ã¢â‚¬â€ that taints the
--               values and breaks everything but flat fills (which is the
--               "only single-color works" bug in Beta 4/5).
--
-- Returns (colorObj, r, g, b):
--   colorObj ~= nil  Ã¢â€ â€™ TYPE mode resolved via curve. Apply via
--                      tex:SetVertexColor(colorObj:GetRGBA())
--   colorObj == nil  Ã¢â€ â€™ SINGLE/fallback. Use (r, g, b) directly.
------------------------------------------------------------------------
local function ResolveDispelColorObj(f, dispelName)
    local kind = (f and f._msufGFKind) or "party"
    local mode = GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")
    local fallbackType = GetReadableDispelTypeName(dispelName)

    if mode ~= "TYPE" then
        return nil,
            GFDispelColorScopeValue(kind, "hlDispelColorR", "dispelBorderColorR", 0.25),
            GFDispelColorScopeValue(kind, "hlDispelColorG", "dispelBorderColorG", 0.75),
            GFDispelColorScopeValue(kind, "hlDispelColorB", "dispelBorderColorB", 1.00)
    end

    -- TYPE mode: resolve Color object via shared dispel color curve.
    local CUA   = _G.C_UnitAuras
    local unit  = f and f.unit
    local curve = GF and GF._sharedDispelColorCurve

    if CUA and CUA.GetAuraDispelTypeColor and unit and curve then
        local cached = f and f._msufGFDispelColorObj
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        if cached and (f._msufGFDispelColorRev or 0) == colorRev then
            return cached
        end

        local aid = f and f._msufGFDispelAuraID
        if aid then
            local color = CUA.GetAuraDispelTypeColor(unit, aid, curve)
            if color then
                if f then
                    f._msufGFDispelColorObj = color
                    f._msufGFDispelColorRev = colorRev
                end
                return color
            end
        end

        -- Grid2 path: query the top dispellable aura directly via GetAuraDataByIndex.
        local aura = CUA.GetAuraDataByIndex and CUA.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if aura and aura.auraInstanceID then
            if f then f._msufGFDispelAuraID = aura.auraInstanceID end
            fallbackType = fallbackType or GetReadableDispelTypeName(aura.dispelName)
            local color = CUA.GetAuraDispelTypeColor(unit, aura.auraInstanceID, curve)
            if color then
                if f then
                    f._msufGFDispelColorObj = color
                    f._msufGFDispelColorRev = colorRev
                end
                return color
            end
        end

        -- Recovery fallback for clients where GetAuraDataByIndex on this filter misbehaves.
        if CUA.GetAuraSlots and CUA.GetAuraDataBySlot then
            local _, slot = CUA.GetAuraSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1)
            local auraBySlot = slot and CUA.GetAuraDataBySlot(unit, slot)
            if auraBySlot and auraBySlot.auraInstanceID then
                if f then f._msufGFDispelAuraID = auraBySlot.auraInstanceID end
                fallbackType = fallbackType or GetReadableDispelTypeName(auraBySlot.dispelName)
                local color = CUA.GetAuraDispelTypeColor(unit, auraBySlot.auraInstanceID, curve)
                if color then
                    if f then
                        f._msufGFDispelColorObj = color
                        f._msufGFDispelColorRev = colorRev
                    end
                    return color
                end
            end
        end
    end

    -- TYPE fallback: use the known dispel school if we have it, otherwise
    -- fall back to the neutral palette.
    if fallbackType then
        local fr, fg, fb = GetDispelColor(fallbackType)
        if fr then return nil, fr, fg, fb end
    end
    return nil, 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Legacy wrapper: keeps (r, g, b) shape for non-overlay callers (glow).
-- Glow APIs don't take a Color object, so we accept a *minor* loss of
-- secret-safety here Ã¢â‚¬â€ values feed into LCG's color table which is
-- only read by C-side SetVertexColor downstream, so it's still safe
-- in practice.
------------------------------------------------------------------------
local function ResolveDispelColor(dispelName, f)
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelName)
    if colorObj then
        local rr, gg, bb = ExtractColorRGB(colorObj)
        if rr ~= nil then return rr, gg, bb end
    end
    if r then return r, g, b end
    if type(dispelName) == "string" and dispelName ~= "DISPELLABLE" then
        local dr, dg, db = GetDispelColor(dispelName)
        if dr then return dr, dg, db end
    end
    return 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Dispel glow helpers (GF) Ã¢â‚¬â€ zero-alloc color table reuse
------------------------------------------------------------------------
local _gfGlowColor = { 0, 0, 0, 1 }

local function _GF_StartDispelGlow(f, r, g, b)
    local kind = f._msufGFKind or "party"
    local blizzardBlocksGlow = false
    local c = f and f._c
    if c and c.nativeBlizzardDispelsSuppressCustom ~= nil then
        blizzardBlocksGlow = c.nativeBlizzardDispelsSuppressCustom == true
    else
        local blocksGlow = _G.MSUF_GroupBlizzardAuraRenderingBlocksDispelGlow
        if type(blocksGlow) == "function" then
            blizzardBlocksGlow = blocksGlow(kind) == true
        end
    end
    if not LCG or blizzardBlocksGlow or not HLVal(kind, "hlDispelGlowEnabled") then
        f._msufGFDispelGlowActive = nil
        local offAnchor = f._msufGFDispelGlowAnchor
        f._msufGFDispelGlowAnchor = nil
        f._msufGFDispelGlowStyle = nil
        if LCG then
            if offAnchor then
                LCG.PixelGlow_Stop(offAnchor, "msufDispel")
                LCG.AutoCastGlow_Stop(offAnchor, "msufDispel")
                LCG.ProcGlow_Stop(offAnchor, "msufDispel")
            end
            local offBorder = f._msufGFHighlightBorder
            if offBorder and offBorder ~= offAnchor then
                LCG.PixelGlow_Stop(offBorder, "msufDispel")
                LCG.AutoCastGlow_Stop(offBorder, "msufDispel")
                LCG.ProcGlow_Stop(offBorder, "msufDispel")
            end
            if f ~= offAnchor and f ~= offBorder then
                LCG.PixelGlow_Stop(f, "msufDispel")
                LCG.AutoCastGlow_Stop(f, "msufDispel")
                LCG.ProcGlow_Stop(f, "msufDispel")
            end
        end
        return
    end
    local anchor = f._msufRGF_GlowAnchor or f._msufGFHighlightBorder or f
    local style = HLVal(kind, "hlDispelGlowStyle") or "PIXEL"
    local oldAnchor = f._msufGFDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or f._msufGFDispelGlowStyle ~= style) then
        LCG.PixelGlow_Stop(oldAnchor, "msufDispel")
        LCG.AutoCastGlow_Stop(oldAnchor, "msufDispel")
        LCG.ProcGlow_Stop(oldAnchor, "msufDispel")
    end
    if anchor ~= f then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
    _gfGlowColor[1], _gfGlowColor[2], _gfGlowColor[3] = r, g, b
    local lines = tonumber(HLVal(kind, "hlDispelGlowLines")) or 8
    local freq  = tonumber(HLVal(kind, "hlDispelGlowFrequency")) or 0.25
    local thick = tonumber(HLVal(kind, "hlDispelGlowThickness")) or 2
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _gfGlowColor, lines, freq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, { color = _gfGlowColor, key = "msufDispel" })
    else
        LCG.PixelGlow_Start(anchor, _gfGlowColor, lines, freq, nil, thick, nil, nil, nil, "msufDispel")
    end
    f._msufGFDispelGlowActive = true
    f._msufGFDispelGlowAnchor = anchor
    f._msufGFDispelGlowStyle = style
end

local function _GF_StopDispelGlow(f)
    if not f then return end
    f._msufGFDispelGlowActive = nil
    local anchor = f._msufGFDispelGlowAnchor
    f._msufGFDispelGlowAnchor = nil
    f._msufGFDispelGlowStyle = nil
    if not LCG then return end
    if anchor then
        LCG.PixelGlow_Stop(anchor, "msufDispel")
        LCG.AutoCastGlow_Stop(anchor, "msufDispel")
        LCG.ProcGlow_Stop(anchor, "msufDispel")
    end

    local border = f._msufGFHighlightBorder
    if border and border ~= anchor then
        LCG.PixelGlow_Stop(border, "msufDispel")
        LCG.AutoCastGlow_Stop(border, "msufDispel")
        LCG.ProcGlow_Stop(border, "msufDispel")
    end
    if f ~= anchor and f ~= border then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
end

------------------------------------------------------------------------
-- Debuff stripe: presence callback (must be before dispatchAura)
------------------------------------------------------------------------
local _QUESTION_MARK_ICON = 136243
local _PADLOCK_ICON = 134400
local _dsPresenceResult = false
local _dsPresenceAF = nil
local _dsPresenceBLHash = nil
local _FrameHasStripeDebuff

local function _DecodeStripeAuraIconFileID(icon)
    if icon == nil then return 0 end
    if issecretvalue and issecretvalue(icon) == true then return 0 end
    return tonumber(icon) or 0
end

local function _dsPresenceCallback(aura)
    if not aura then return false end

    local af = _dsPresenceAF
    local blHash = _dsPresenceBLHash
    if blHash and af then
        local sid = af.DecodeSpellId(aura)
        if af.IsBlacklisted(sid, blHash, aura) then
            return false
        end
    end

    local iconFileID = _DecodeStripeAuraIconFileID(aura.icon)
    if iconFileID == _QUESTION_MARK_ICON or iconFileID == _PADLOCK_ICON then
        return false
    end

    _dsPresenceResult = true
    return true  -- stop iteration
end

------------------------------------------------------------------------
-- Forward declarations (defined later in file)
local _GF_RefreshBorder
local _GF_ApplyDispelOverlay
local _GF_ApplyDebuffStripe
local _GF_ClearNativeSuppressedDispel

------------------------------------------------------------------------
-- UNIT_AURA: per-frame dispatch with burst-dedup (A2 P2 pattern)
-- Fast-paths (update-only 16Ã‚Âµs, remove-only-not-displayed) still fire
-- instantly. Full pipeline is gated: first event runs immediately,
-- subsequent same-frame events within 20ms are skipped.
-- Zero steady-state alloc: clear-callback allocated once per frame.
------------------------------------------------------------------------
-- Legacy _After0 removed from runtime hot paths; use central scheduler helpers above.

------------------------------------------------------------------------
-- PERF: Global per-frame budget for full aura scans.
-- AoE heal/damage Ã¢â€ â€™ 20 UNIT_AURA events in same frame Ã¢â€ â€™ 20 Ãƒâ€” 138Ã‚Âµs = 2.8ms spike.
-- Budget limits full scans to 8 per frame. Excess deferred to next frame via C_Timer.After(0).
-- Max spike capped to 8 Ãƒâ€” 138Ã‚Âµs Ã¢â€°Ë† 1.1ms.
------------------------------------------------------------------------
local _GF_AURA_BUDGET_MAX = 8
local _gfAuraBudget = 0
local _gfAuraDirtyPending = false
local _gfAuraBudgetFrame = 0  -- GetTime of last budget reset
local _gfAuraDirtyQueue = {}
local _gfAuraDirtyQueued = {}
local _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0

local function _gfQueueAuraDirty(f)
    if not f then return end
    f._msufGFAuraDirty = true
    if not _gfAuraDirtyQueued[f] then
        _gfAuraDirtyQueued[f] = true
        _gfAuraDirtyTail = _gfAuraDirtyTail + 1
        _gfAuraDirtyQueue[_gfAuraDirtyTail] = f
    end
end

-- Forward-declared; assigned after dispatchAura is defined.
local _gfFlushDirtyAuras
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    if GF.SpellIndicatorsUnitAuraRelevant then
        return GF.SpellIndicatorsUnitAuraRelevant(f, f and f.unit, f and f._msufGFKind or "party", updateInfo)
    end

    local added = updateInfo.addedAuras
    if added and #added > 0 then
        return true
    end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function NativeAuraContainerReady(f, unit)
    local container = f and f._msufGFNativeAuras
    if not (container and container._msufNativeAuraAnchorID) then return false end
    local Native = ns and ns.MSUF_AuraNative
    local effectiveUnit = Native and Native.ResolveUnitToken and Native.ResolveUnitToken(unit) or unit
    return container._msufNativeAuraUnit == effectiveUnit
end

function GF.FinishAuraVisuals(f, unit, c, updateInfo)
    if not (f and c) then return end
    if c.nativeBlizzardDispelsSuppressCustom then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
    elseif GF.DispelScanActive(c) or f._msufGFDispelType or f._msufGFMergedDispel
        or f._msufGFDispelAuraID or f._msufGFPrevDispelAuraID
    then
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        local dispelAid = f._msufGFDispelAuraID
        local prevAid = f._msufGFPrevDispelAuraID
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        local prevColorRev = f._msufGFColorStyleRevision or 0
        if mergedDispel ~= prevDispel or dispelAid ~= prevAid or colorRev ~= prevColorRev then
            f._msufGFDispelType = mergedDispel
            f._msufGFPrevDispelAuraID = dispelAid
            f._msufGFColorStyleRevision = colorRev
            _GF_RefreshBorder(f, unit)
            _GF_ApplyDispelOverlay(f)
        end
    end

    if c.dsEn then
        local scanStripe = not updateInfo or updateInfo.isFullUpdate or f._msufGFHasAnyDebuff == nil
        if not scanStripe then
            local added = updateInfo.addedAuras
            if added and #added > 0 then
                scanStripe = true
            else
                local removed = updateInfo.removedAuraInstanceIDs
                scanStripe = removed and #removed > 0
            end
        end
        if scanStripe then
            local hadDebuff = f._msufGFHasAnyDebuff or false
            local hasDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
            f._msufGFHasAnyDebuff = hasDebuff
            if hasDebuff ~= hadDebuff then
                _GF_ApplyDebuffStripe(f)
            end
        end
    end

    if GF.UpdateCornerIndicators and c.ciAura then
        GF.UpdateCornerIndicators(f, unit)
    end
end

local function dispatchAura(f, unit, updateInfo)
    local c = f._c
    if not c then return end
    local kind = f._msufGFKind or "party"
    -- PERF: use pre-cached flags from BuildFrameCache (was GF.GetConf per event)
    local aurasOn = c.anyAuraGrp
    local siRefresh = c.siEn and SpellIndicatorsNeedRefresh(f, updateInfo) or false

    -- PERF: CornerIndicators only care about aura add/remove, not duration/stack
    -- updates. Skip CI when the event is a pure update (saves ~300ms/min in raids).
    local ciRelevant = not updateInfo or updateInfo.isFullUpdate
        or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
        or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0)

    if not aurasOn then
        local dispelChanged, dispelRelevant
        if GF.DispelScanActive(c) then
            -- EQoL dirty-flag: only rescan when dispel state may have changed
            local needDispelScan = false
            if not updateInfo or updateInfo.isFullUpdate then
                needDispelScan = true
            else
                local added = updateInfo.addedAuras
                if added and #added > 0 then needDispelScan = true end
                if not needDispelScan then
                    local removed = updateInfo.removedAuraInstanceIDs
                    if removed and #removed > 0 then
                        local trackedAid = f._msufGFDispelAuraID
                        if not trackedAid then
                            -- No tracked dispel Ã¢â‚¬â€ new removals might reveal nothing, but
                            -- added check above covers new dispels. Skip.
                        else
                            -- Check if OUR tracked dispel aura was removed
                            for ri = 1, #removed do
                                if removed[ri] == trackedAid then
                                    needDispelScan = true; break
                                end
                            end
                        end
                    end
                end
            end
            if needDispelScan then
                if GF._UpdateDispelFromAuraDelta then
                    dispelChanged, dispelRelevant = GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
                else
                    GF._UpdateDispel(f, unit)
                    dispelChanged, dispelRelevant = true, true
                end
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateCornerIndicators and ((c.ciCustom and ciRelevant)
            or (c.ciDispel and ((not GF.DispelScanActive(c) and ciRelevant) or dispelChanged or dispelRelevant)))
        then
            GF.UpdateCornerIndicators(f, unit)
        end
        return
    end

    -- c.anyAuraGrp already includes sub-group enabled check, no need for second pass
    if c.nativeBlizzardAuraOnly and not c.ciAura and not c.dsEn then
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if not NativeAuraContainerReady(f, unit) and GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        end
        return
    end

    -- Full rescan required
    if not updateInfo or updateInfo.isFullUpdate then
        -- Throttle fullUpdate when out of combat (Blizzard fires these periodically)
        if updateInfo and updateInfo.isFullUpdate and not InCombatLockdown() then
            local now = GetTime()
            local last = f._msufGFLastFullAura
            if last and (now - last) < 0.5 then
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
            f._msufGFLastFullAura = now
        end
        -- fall through to full pipeline below
    else
        local added   = updateInfo.addedAuras
        local removed = updateInfo.removedAuraInstanceIDs
        local updated = updateInfo.updatedAuraInstanceIDs
        local hasAdd = added and #added > 0
        local hasRem = removed and #removed > 0
        local hasUpd = updated and #updated > 0

        -- Nothing relevant at all
        if not hasAdd and not hasRem and not hasUpd then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end

        local displayed = f._msufDisplayedAuraIDs

        -- Update-only: direct icon refresh (16Ã‚Âµs vs 115Ã‚Âµs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                local needsDeltaPipeline = false
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        if GF.RefreshAuraIcon(icon, unit, updated[ui]) == false then
                            needsDeltaPipeline = true
                            break
                        end
                    end
                end
                if not needsDeltaPipeline then
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add/remove: handled below by the cache-backed delta pipeline.
    end

    if updateInfo and not updateInfo.isFullUpdate then
        if c.siEn and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        elseif GF._UpdateDispel then
            GF._UpdateDispel(f, unit)
        end
        GF.FinishAuraVisuals(f, unit, c, updateInfo)
        return
    end

    -- Out-of-combat rate limit: max 2 full rescans/s per frame (idle optimization)
    -- In combat: unlimited (instant debuff detection)
    if not InCombatLockdown() then
        local now = GetTime()
        if f._msufGFLastFullAura and (now - f._msufGFLastFullAura) < 0.5 then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end
        f._msufGFLastFullAura = now
    end

    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    -- P1: In-combat burst-dedup (A2 P2 pattern)
    -- First event runs the full pipeline immediately (zero latency).
    -- Subsequent events for the SAME frame within 20ms are skipped.
    -- Saves N-1 full pipeline runs per AoE burst (N=simultaneous aura
    -- changes per unit). Clear-callback allocated once per frame.
    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    if f._msufGFFullPending then
        return
    end
    f._msufGFFullPending = true
    do
        local cb = f._msufGFPendClearCB
        if not cb then
            local frame = f
            cb = function() frame._msufGFFullPending = nil end
            f._msufGFPendClearCB = cb
        end
        local key = f._msufGFPendClearKey
        if not key then
            key = "GF_AURA_PEND_" .. tostring(f)
            f._msufGFPendClearKey = key
        end
        _MSUF_ScheduleDelayOnce(key, 0.02, cb)
    end

    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    -- P2: Global per-frame budget (AoE spike limiter)
    -- AoE events fire 20+ UNIT_AURA for different units in one frame.
    -- Each full scan costs ~138Ã‚Âµs. 20 Ãƒâ€” 138Ã‚Âµs = 2.8ms spike.
    -- Budget caps to 8 scans/frame Ã¢â€ â€™ max ~1.1ms. Rest deferred.
    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    _gfAuraBudget = _gfAuraBudget + 1
    local now = GetTime()
    if now ~= _gfAuraBudgetFrame then
        _gfAuraBudgetFrame = now
        _gfAuraBudget = 1
    end
    if _gfAuraBudget > _GF_AURA_BUDGET_MAX then
        _gfQueueAuraDirty(f)
        if not _gfAuraDirtyPending then
            _gfAuraDirtyPending = true
            _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
        end
        return
    end

    -- Full aura processing (add/remove/fullUpdate)
    -- SI runs first: populates dedup IDs before buff scan
    if c.siEn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
    end
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit, updateInfo)
    else
        GF._UpdateDispel(f, unit)
    end
    GF.FinishAuraVisuals(f, unit, c, updateInfo)

end

------------------------------------------------------------------------
-- Deferred aura flush: processes frames that exceeded the per-frame budget.
-- Fires via C_Timer.After(0) Ã¢â€ â€™ runs at the start of the next frame.
------------------------------------------------------------------------
_gfFlushDirtyAuras = function()
    _gfAuraBudget = 0
    _gfAuraDirtyPending = false

    -- Process at most the same number of deferred full aura scans that the
    -- immediate path allows per frame. The previous loop walked the whole
    -- queue and relied on dispatchAura to re-queue overflow frames, which was
    -- correct but created extra Lua churn during large raid-wide aura bursts.
    local processed = 0
    local stopTail = _gfAuraDirtyTail
    while _gfAuraDirtyHead <= stopTail and processed < _GF_AURA_BUDGET_MAX do
        local f = _gfAuraDirtyQueue[_gfAuraDirtyHead]
        _gfAuraDirtyQueue[_gfAuraDirtyHead] = nil
        _gfAuraDirtyHead = _gfAuraDirtyHead + 1
        if f then
            _gfAuraDirtyQueued[f] = nil
            if f._msufGFAuraDirty then
                f._msufGFAuraDirty = nil
                local u = f.unit
                if u and UnitExists(u) then
                    -- This is the deferred full scan, so bypass the short
                    -- same-unit burst guard that scheduled the deferral.
                    f._msufGFFullPending = nil
                    dispatchAura(f, u, nil)
                end
            end
        end
        processed = processed + 1
    end
    if _gfAuraDirtyHead > _gfAuraDirtyTail then
        _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0
    elseif not _gfAuraDirtyPending then
        _gfAuraDirtyPending = true
        _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
    end
end
------------------------------------------------------------------------
-- Dispel overlay (color wash on health bar)
-- StatusBar-based: mirrors health value for "current health only" clip.
--
-- SECRET-SAFE COLOR APPLICATION (Midnight 12.0):
--   TYPE mode returns a Color object from C_UnitAuras.GetAuraDispelTypeColor.
--   Secret-tainted RGB values CAN pass through tex:SetVertexColor varargs
--   (C-side handles them) but CANNOT pass through CreateColor/SetGradient
--   (Lua-side taints). We therefore:
--     Ã¢â‚¬Â¢ use pre-baked gradient *textures* (Media/MSUF_Grad_*.tga) for the
--       TOP/BOTTOM/LEFT/RIGHT/EDGE styles Ã¢â‚¬â€ no SetGradient needed,
--     Ã¢â‚¬Â¢ apply the tint via tex:SetVertexColor(color:GetRGBA()) in a single
--       varargs passthrough Ã¢â‚¬â€ no Lua arithmetic on the tint values,
--     Ã¢â‚¬Â¢ use SetAlpha on the StatusBar frame for the user's doAlpha slider.
--
--   This replaces the Beta 5 path that called CreateColor(secret_r, ...)
--   in SetGradient branches Ã¢â‚¬â€ that was the "TYPE mode broken / only
--   SINGLE works" bug.
------------------------------------------------------------------------
local _MSUF_GRAD_PATH = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local _GRAD_TEXTURES = {
    FULL   = "Interface\\Buttons\\WHITE8x8",
    TOP    = _MSUF_GRAD_PATH .. "MSUF_Grad_V",      -- solid top,    fades down
    BOTTOM = _MSUF_GRAD_PATH .. "MSUF_Grad_V_Rev",  -- solid bottom, fades up
    LEFT   = _MSUF_GRAD_PATH .. "MSUF_Grad_H",      -- solid left,   fades right
    RIGHT  = _MSUF_GRAD_PATH .. "MSUF_Grad_H_Rev",  -- solid right,  fades left
}

_GF_ApplyDispelOverlay = function(f)
    local dov = f._msufGFDispelOverlay
    if not dov then
        return
    end
    local c = f._c
    if not c then return end

    local dispelType = f._msufGFDispelType
    if not c.doEn or not dispelType then
        if dov:IsShown() then dov:Hide() end
        dov._msufDOSyncHP = nil
        return
    end

    -- Safety: anchor overlay to correct region based on style + doOnHP
    if f.health then
        local anchorTo = f.health
        if c.doStyle == "FULL" and not c.doOnHP and f.barGroup then
            anchorTo = f.barGroup
        end
        dov:ClearAllPoints()
        dov:SetAllPoints(anchorTo)
    end

    -- Pick gradient texture for the style (cheap diff-gate to avoid spamming
    -- SetStatusBarTexture Ã¢â‚¬â€ Blizzard reloads the atlas every call).
    local style = c.doStyle or "FULL"
    local texPath = _GRAD_TEXTURES[style] or _GRAD_TEXTURES.FULL
    if dov._msufDOStylePath ~= texPath then
        dov:SetStatusBarTexture(texPath)
        dov._msufDOStylePath = texPath
    end
    local tex = dov:GetStatusBarTexture()

    -- Fill value: mirror current health ("current health only") or full bar.
    local unit = f.unit
    if c.doOnHP and unit then
        local hm = f._msufGFCachedHpMax or UnitHealthMax(unit)
        dov:SetMinMaxValues(0, hm)
        dov:SetValue(UnitHealth(unit))
        dov._msufDOSyncHP = true
    else
        dov:SetMinMaxValues(0, 1)
        dov:SetValue(1)
        dov._msufDOSyncHP = nil
    end

    -- Resolve and apply tint (secret-safe path).
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelType)
    if tex then
        local rr, gg, bb, aa = ExtractColorRGBA(colorObj)
        tex:SetVertexColor(rr or r or 0.25, gg or g or 0.75, bb or b or 1.00, aa or 1)
    end
    -- User's alpha slider lives on the StatusBar frame, independent of tint.
    local userAlpha = c.doAlpha or 1
    if dov._msufDOAlphaCache ~= userAlpha then
        dov:SetAlpha(userAlpha)
        dov._msufDOAlphaCache = userAlpha
    end

    -- Reverse fill sync (match health bar direction)
    if dov.SetReverseFill then
        dov:SetReverseFill(c.reverseFill and true or false)
    end

    if not dov:IsShown() then dov:Show() end
end

------------------------------------------------------------------------
-- Debuff stripe (thin edge indicator for a configured debuff match).
-- Independent from dispel overlay Ã¢â‚¬â€ honors the Debuffs filter/list and
-- still works for non-dispellable debuffs when that filter allows them.
------------------------------------------------------------------------
_GF_ApplyDebuffStripe = function(f)
    local stripe = f._msufGFDebuffStripe
    if not stripe then return end
    local c = f._c
    if not c then return end

    if not c.dsEn or not f._msufGFHasAnyDebuff then
        if stripe:IsShown() then stripe:Hide() end
        return
    end

    -- Anchor based on edge setting
    local edge = c.dsEdge
    local h = math_max(1, c.dsH or 3)
    if stripe._msufDSEdge ~= edge or stripe._msufDSH ~= h then
        stripe._msufDSEdge = edge
        stripe._msufDSH = h
        stripe:ClearAllPoints()
        stripe:SetHeight(h)
        local anchor = f.health or f
        if edge == "TOP" then
            stripe:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
            stripe:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
        else -- BOTTOM (default)
            stripe:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
            stripe:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Color + alpha (diff-gated)
    local r, g, b, a = c.dsR, c.dsG, c.dsB, c.dsAlpha
    if stripe._msufDSR ~= r or stripe._msufDSG ~= g or stripe._msufDSB ~= b or stripe._msufDSA ~= a then
        stripe._msufDSR, stripe._msufDSG, stripe._msufDSB, stripe._msufDSA = r, g, b, a
        stripe:SetStatusBarColor(r, g, b, a)
    end

    -- Fill full width
    stripe:SetMinMaxValues(0, 1)
    stripe:SetValue(1)

    if not stripe:IsShown() then stripe:Show() end
end

_GF_RefreshBorder = function(f, unit)
    -- NOTE: Dispel overlay is fully decoupled from border highlight.
    -- Overlay lives in _GF_ApplyDispelOverlay and is called separately
    -- from dispel-change sites only Ã¢â‚¬â€ never from aggro/target/test paths.

    local border = f._msufGFHighlightBorder
    if not border then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    if not c then return end

    -- Resolve active states
    local dispelType = f._msufGFDispelType
    local hasDispel  = dispelType and c.dispelEn
    local aggroLevel = f._msufGFAggroLevel
    local hasAggro   = aggroLevel and aggroLevel >= 1 and c.aggroEn

    -- Shared geometry for dispel/aggro/purge (all use Aggro size keys)
    local sz  = c.aggroSize or 2
    local ofs = c.aggroOfs or 0
    local tex = c.aggroTex
    local lay = c.aggroLayer or "DEFAULT"
    local fScale = c.frameScale or 1
    if fScale ~= 1 and GF.ScaleValue then
        sz = GF.ScaleValue(sz, fScale, 1)
        ofs = GF.ScaleValue(ofs, fScale)
    end

    -- Configurable priority: read the resolved Bars scope for this GF kind.
    -- Maps "dispel"/"magic"/"curse"/etc Ã¢â€ â€™ dispel, "aggro" Ã¢â€ â€™ aggro.
    -- Purge/bossTarget are UF-only, skip for GF.
    local prioOrder = c.hlPrioEnabled and c.hlPrioOrder

    if type(prioOrder) == "table" then
        for _, pk in ipairs(prioOrder) do
            if pk == "dispel" or pk == "magic" or pk == "curse"
            or pk == "disease" or pk == "poison" or pk == "bleed" then
                if hasDispel then
                    local r, g, b = ResolveDispelColor(dispelType, f)
                    if r then
                        _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay, r, g, b, 1)
                        border._msufHLActivePrio = 1; border:Show()
                        _NotifyRoundedGFHighlight(border)
                        _GF_StartDispelGlow(f, r, g, b)
                        return
                    end
                end
            elseif pk == "aggro" then
                if hasAggro then
                    _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay,
                        c.aggroR or 1, c.aggroG or 0.55, c.aggroB or 0, 1)
                    border._msufHLActivePrio = 2; border:Show()
                    _NotifyRoundedGFHighlight(border)
                    _GF_StopDispelGlow(f)
                    return
                end
            end
        end
    else
        -- Default: Dispel > Aggro
        if hasDispel then
            local r, g, b = ResolveDispelColor(dispelType, f)
            if r then
                _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay, r, g, b, 1)
                border._msufHLActivePrio = 1; border:Show()
                _NotifyRoundedGFHighlight(border)
                _GF_StartDispelGlow(f, r, g, b)
                return
            end
        end
        if hasAggro then
            _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay,
                c.aggroR or 1, c.aggroG or 0.55, c.aggroB or 0, 1)
            border._msufHLActivePrio = 2; border:Show()
            _NotifyRoundedGFHighlight(border)
            _GF_StopDispelGlow(f)
            return
        end
    end

    -- After configurable prio: Target (GF-specific, always after dispel/aggro)
    if f._msufGFIsTarget and c.targetEn then
        _applyHighlightBorderStyle(border, nil,
            c.tgtSize or 2,
            c.tgtOfs or 0,
            c.tgtTex,
            c.tgtLayer or "DEFAULT",
            c.tgtR or 1,
            c.tgtG or 1,
            c.tgtB or 1, 1)
        border._msufHLActivePrio = 3; border:Show()
        _NotifyRoundedGFHighlight(border)
        _GF_StopDispelGlow(f)
        return
    end

    -- Focus (GF-specific, lowest priority)
    if f._msufGFIsFocus and c.focusEn then
        _applyHighlightBorderStyle(border, nil,
            c.focSize or 2,
            c.focOfs or 0,
            c.focTex,
            c.focLayer or "DEFAULT",
            c.focR or 0.5,
            c.focG or 0.5,
            c.focB or 1.0, 1)
        border._msufHLActivePrio = 4; border:Show()
        _NotifyRoundedGFHighlight(border)
        _GF_StopDispelGlow(f)
        return
    end

    border._msufHLActivePrio = nil
    _NotifyRoundedGFHighlight(border)
    if border:IsShown() then border:Hide() end
    _GF_StopDispelGlow(f)
end

_GF_ClearNativeSuppressedDispel = function(f, unit)
    if not f then return end
    local hadDispel = f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
        or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive
    local border = f._msufGFHighlightBorder
    if border and border._msufHLActivePrio == 1 then hadDispel = true end

    f._msufGFMergedDispel = nil
    f._msufGFDispelType = nil
    f._msufGFDispelAuraID = nil
    f._msufGFPrevDispelAuraID = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    f._msufGFColorStyleRevision = nil

    local dov = f._msufGFDispelOverlay
    if dov then
        if dov:IsShown() then hadDispel = true; dov:Hide() end
        dov._msufDOSyncHP = nil
    end
    if GF.ApplyPrivateAuraContainerOverlay then
        GF.ApplyPrivateAuraContainerOverlay(f, unit or f.unit, { containerOverlay = { enabled = false } })
    elseif f._gfPrivOverlayFrame and f._gfPrivOverlayFrame:IsShown() then
        f._gfPrivOverlayFrame:Hide()
    end
    _GF_StopDispelGlow(f)
    if hadDispel and _GF_RefreshBorder then _GF_RefreshBorder(f, unit) end
end

-- Dispel border (zero-alloc direct C_UnitAuras slot scan)
-- Replaces AuraUtil.ForEachAura which allocates a table internally
-- every call ({C_UnitAuras.GetAuraSlots(...)}).
-- Module-level vararg scanner: zero closure, zero table per call.
------------------------------------------------------------------------
local _dispelScanUnit  -- module-level state for vararg scanner
local C_UnitAuras_GetAuraSlots    = C_UnitAuras and C_UnitAuras.GetAuraSlots
local C_UnitAuras_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local C_UnitAuras_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local C_UnitAuras_IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local _DISPEL_SCAN_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local _debuffStripeScanUnit
GF._DispelFallbackCallback = GF._DispelFallbackCallback or function(auraData)
    GF._dispelFallbackFoundDispel, GF._dispelFallbackFoundAid = GF.ReadDispelBorderAura(auraData, GF._dispelFallbackTriggerMode)
    return GF._dispelFallbackFoundDispel ~= nil
end

local function _DebuffStripeScanSlots(_, ...)
    local scanUnit = _debuffStripeScanUnit
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local aura = scanUnit and C_UnitAuras_GetAuraDataBySlot and C_UnitAuras_GetAuraDataBySlot(scanUnit, slot)
        if _dsPresenceCallback(aura) then
            return true
        end
    end
    return false
end

_FrameHasStripeDebuff = function(f, unit)
    if not unit or not UnitExists(unit) then return false end

    local kind = (f and f._msufGFKind) or "party"
    local conf = GF.GetConf(kind)
    local debCfg = conf and conf.auras and conf.auras.debuff or nil
    local af = GF.AuraFilter or _G.MSUF_GF_AuraFilter
    local filter = af and af.ResolveDebuffFilter(debCfg and debCfg.filterToken) or "HARMFUL"

    _dsPresenceResult = false
    _dsPresenceAF = af
    _dsPresenceBLHash = (debCfg and af and af.BuildBlacklistHash(debCfg)) or nil

    if C_UnitAuras_GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, index, filter)
            if not aura then break end
            if _dsPresenceCallback(aura) then break end
            index = index + 1
        end
    elseif C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
        _debuffStripeScanUnit = unit
        _DebuffStripeScanSlots(C_UnitAuras_GetAuraSlots(unit, filter))
        _debuffStripeScanUnit = nil
    elseif AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, filter, nil, _dsPresenceCallback, true)
    end

    _dsPresenceAF = nil
    _dsPresenceBLHash = nil
    return _dsPresenceResult
end

local function _DispelScanSlots(cont, ...)
    local GetData = C_UnitAuras_GetAuraDataBySlot
    local u = _dispelScanUnit
    local iss = issecretvalue
    -- C-side: use RAID_PLAYER_DISPELLABLE filter directly
    -- If we got slots from that filter, the first slot IS dispellable
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local data = GetData(u, slot)
        if data and data.auraInstanceID then
            local dn = data.dispelName
            if not (iss and iss(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                return dn, data.auraInstanceID
            end
            return "DISPELLABLE", data.auraInstanceID
        end
    end
    return nil, nil
end

GF.ReadDispelBorderAura = GF.ReadDispelBorderAura or function(aura, triggerMode)
    if not (aura and aura.auraInstanceID) then return nil, nil end
    triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
    if triggerMode ~= "BY_ME" then
        local harmful = aura.isHarmful
        if issecretvalue and issecretvalue(harmful) then
            -- Continue through the dispelName path for secret-tagged aura data.
        elseif harmful == false then
            return nil, nil
        end
    end

    local dn = aura.dispelName
    local secret = issecretvalue and issecretvalue(dn)
    if secret then
        if triggerMode == "DISPEL_TYPE" then
            return "DISPELLABLE", aura.auraInstanceID
        end
    elseif type(dn) == "string" and dn ~= "" and dn ~= "None" then
        if dn == "DISPELLABLE" then
            return "DISPELLABLE", aura.auraInstanceID
        end
        return dn, aura.auraInstanceID
    elseif triggerMode == "DISPEL_TYPE" then
        return nil, nil
    end

    if triggerMode == "ANY_DEBUFF" then
        return "DISPELLABLE", aura.auraInstanceID
    end
    return nil, nil
end

GF.FindDispelBorderAura = GF.FindDispelBorderAura or function(unit, triggerMode)
    triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
    local filter = (triggerMode == "BY_ME") and _DISPEL_SCAN_FILTER or "HARMFUL"

    if C_UnitAuras_GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, index, filter)
            if not aura then break end
            local dispel, aid = GF.ReadDispelBorderAura(aura, triggerMode)
            if triggerMode == "BY_ME" and aura.auraInstanceID then
                return dispel or "DISPELLABLE", aura.auraInstanceID
            end
            if dispel then return dispel, aid end
            if triggerMode == "BY_ME" then break end
            index = index + 1
        end
        return nil, nil
    end

    if triggerMode == "BY_ME" and C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
        _dispelScanUnit = unit
        local dispel, aid = _DispelScanSlots(C_UnitAuras_GetAuraSlots(unit, _DISPEL_SCAN_FILTER))
        _dispelScanUnit = nil
        return dispel, aid
    end

    if AuraUtil and AuraUtil.ForEachAura then
        GF._dispelFallbackTriggerMode = triggerMode
        GF._dispelFallbackFoundDispel = nil
        GF._dispelFallbackFoundAid = nil
        AuraUtil.ForEachAura(unit, filter == "HARMFUL" and "HARMFUL" or "HARMFUL|RAID", nil, GF._DispelFallbackCallback, true)
        local foundDispel, foundAid = GF._dispelFallbackFoundDispel, GF._dispelFallbackFoundAid
        GF._dispelFallbackTriggerMode = nil
        GF._dispelFallbackFoundDispel = nil
        GF._dispelFallbackFoundAid = nil
        return foundDispel, foundAid
    end

    return nil, nil
end

function GF._UpdateDispel(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    local triggerMode = GF.NormalizeDispelBorderTrigger(c and c.dispelBorderTrigger or HLVal(kind, "dispelBorderTrigger"))

    local testMode = (_G.MSUF_BorderTestModesActive == true) and _G.MSUF_DispelBorderTestMode
    -- Scope filtering: if test scope doesn't match this frame's kind, ignore test mode
    if testMode then
        local testScope = _G.MSUF_DispelBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid"
                or (testScope == "mythicraid" or testScope == "gf_mythicraid") and "mythicraid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end

    local auras = conf and conf.auras
    if not testMode and (not auras or auras.enabled == false) then
        f._msufGFDispelKnown = true
        if _GF_ClearNativeSuppressedDispel then
            _GF_ClearNativeSuppressedDispel(f, unit)
        else
            f._msufGFMergedDispel = nil
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFPrevDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            f._msufGFColorStyleRevision = nil
        end
        return
    end

    if not testMode and ((c and c.nativeBlizzardDispelsSuppressCustom) or (not c and _GF_IsBlizzardDispelRendererActive(conf))) then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        f._msufGFDispelKnown = true
        return
    end

    if ((not GF.DispelScanActive(c)) or not unit
        or (GF.DispelBorderTriggerNeedsPlayerDispel(triggerMode) and not GF._playerCanDispel))
        and not testMode
    then
        f._msufGFDispelKnown = true
        if f._msufGFDispelType then
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            _GF_RefreshBorder(f, unit)
            _GF_ApplyDispelOverlay(f)
        end
        return
    end

    local topDispel = nil
    local topAid = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    if not testMode then
        if not UnitExists(unit) then
            f._msufGFDispelKnown = true
            if f._msufGFDispelType then
                f._msufGFDispelType = nil
                f._msufGFDispelAuraID = nil
                f._msufGFDispelColorObj = nil
                f._msufGFDispelColorRev = nil
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
            end
            return
        end
        topDispel, topAid = GF.FindDispelBorderAura(unit, triggerMode)
        if topAid and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
            f._msufGFDispelColorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, topAid, GF._sharedDispelColorCurve)
            f._msufGFDispelColorRev = _G.MSUF_ColorStyleRevision or 0
        else
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
        end
    else
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
    end

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFPrevDispelAuraID
    local colorRev = _G.MSUF_ColorStyleRevision or 0
    local prevColorRev = f._msufGFColorStyleRevision or 0
    f._msufGFDispelKnown = true
    f._msufGFDispelType = topDispel
    f._msufGFDispelAuraID = topAid
    f._msufGFPrevDispelAuraID = topAid

    if topDispel == prevDispel and topAid == prevAid and colorRev == prevColorRev and not testMode then return end

    f._msufGFColorStyleRevision = colorRev
    _GF_RefreshBorder(f, unit)
    -- Overlay only for real dispels Ã¢â‚¬â€ border test mode is border-only
    if not testMode then
        _GF_ApplyDispelOverlay(f)
    end
end

function GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
    if not (f and unit) then return false, false end

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFDispelAuraID
    local prevColorRev = f._msufGFColorStyleRevision or 0

    local function finishFull()
        GF._UpdateDispel(f, unit)
        return f._msufGFDispelType ~= prevDispel
            or f._msufGFDispelAuraID ~= prevAid
            or (f._msufGFColorStyleRevision or 0) ~= prevColorRev, true
    end

    if not updateInfo or updateInfo.isFullUpdate then
        return finishFull()
    end

    local c = f._c
    local triggerMode = GF.NormalizeDispelBorderTrigger(c and c.dispelBorderTrigger or HLVal(f._msufGFKind or "party", "dispelBorderTrigger"))

    local trackedAid = f._msufGFDispelAuraID
    local removed = updateInfo.removedAuraInstanceIDs
    if removed and trackedAid then
        for i = 1, #removed do
            if removed[i] == trackedAid then
                return finishFull()
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated and trackedAid then
        for i = 1, #updated do
            if updated[i] == trackedAid then
                if triggerMode ~= "BY_ME" or not C_UnitAuras_IsAuraFilteredOut
                    or C_UnitAuras_IsAuraFilteredOut(unit, trackedAid, _DISPEL_SCAN_FILTER) ~= false
                then
                    return finishFull()
                end
                return false, true
            end
        end
    end

    if trackedAid then
        return false, false
    end

    local added = updateInfo.addedAuras
    if not added then
        return false, false
    end

    for i = 1, #added do
        local aura = added[i]
        local aid = aura and aura.auraInstanceID
        if aid then
            local dispellable, triggerDispel
            if triggerMode == "BY_ME" and C_UnitAuras_IsAuraFilteredOut then
                dispellable = C_UnitAuras_IsAuraFilteredOut(unit, aid, _DISPEL_SCAN_FILTER) == false
            else
                triggerDispel = GF.ReadDispelBorderAura(aura, triggerMode)
                dispellable = triggerDispel ~= nil
            end
            if dispellable then
                local dn = aura.dispelName
                if triggerDispel then
                    f._msufGFDispelType = triggerDispel
                elseif not (issecretvalue and issecretvalue(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                    f._msufGFDispelType = dn
                else
                    f._msufGFDispelType = "DISPELLABLE"
                end
                f._msufGFDispelAuraID = aid
                f._msufGFPrevDispelAuraID = aid
                f._msufGFDispelKnown = true
                if C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                    f._msufGFDispelColorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, GF._sharedDispelColorCurve)
                    f._msufGFDispelColorRev = _G.MSUF_ColorStyleRevision or 0
                else
                    f._msufGFDispelColorObj = nil
                    f._msufGFDispelColorRev = nil
                end
                local colorRev = _G.MSUF_ColorStyleRevision or 0
                f._msufGFColorStyleRevision = colorRev
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
                return true, true
            end
        end
    end

    return false, false
end

------------------------------------------------------------------------

GF.GetDispelColor = GetDispelColor
GF.ResolveDispelColor = ResolveDispelColor
GF.StartDispelGlow = _GF_StartDispelGlow
GF.StopDispelGlow = _GF_StopDispelGlow
GF.ApplyDispelOverlay = _GF_ApplyDispelOverlay
GF.ApplyDebuffStripe = _GF_ApplyDebuffStripe
GF.ClearNativeSuppressedDispel = _GF_ClearNativeSuppressedDispel
GF.RefreshBorder = _GF_RefreshBorder
GF.FrameHasStripeDebuff = _FrameHasStripeDebuff
GF.DispatchAura = dispatchAura
GF.FlushDirtyAuras = _gfFlushDirtyAuras
GF.UpdateDispel = GF._UpdateDispel
GF.UpdateDispelFromAuraDelta = GF._UpdateDispelFromAuraDelta
if GF._UnitDispatch then
    GF._UnitDispatch.UNIT_AURA = dispatchAura
end

function GF.RetireAuraEffectsState(f)
    if not f then return end
    _GF_StopDispelGlow(f)
    _gfAuraDirtyQueued[f] = nil
    f._msufGFAuraDirty = nil
    f._msufGFFullPending = nil
end

_G.MSUF_GF_UpdateDispel = GF._UpdateDispel
_G.MSUF_GF_StopDispelGlow = _GF_StopDispelGlow
_G.MSUF_GF_RefreshDispelOverlay = function()
    if not GF.frames then return end
    local each = GF.ForEachLiveGroupFrame
    if type(each) ~= "function" then return end
    each(function(f)
        if GF.BuildFrameCache then GF.BuildFrameCache(f) end
        _GF_ApplyDispelOverlay(f)
    end)
end
_G.MSUF_GF_ApplyDispelOverlay = _GF_ApplyDispelOverlay
_G.MSUF_GF_RefreshDebuffStripe = function()
    if not GF.frames then return end
    local each = GF.ForEachLiveGroupFrame
    if type(each) ~= "function" then return end
    each(function(f)
        if GF.BuildFrameCache then GF.BuildFrameCache(f) end
        _GF_ApplyDebuffStripe(f)
    end)
end
_G.MSUF_GF_ApplyDebuffStripe = _GF_ApplyDebuffStripe
_G.MSUF_GF_RefreshBorder = _GF_RefreshBorder
_G.MSUF_GF_DispatchAura = dispatchAura

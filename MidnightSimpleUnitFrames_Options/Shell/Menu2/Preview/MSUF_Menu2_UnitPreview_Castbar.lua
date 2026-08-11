--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua
--- Cold-path castbar preview helpers.
---
--- Resolves castbar DB fields and mock layout values for Menu2 previews. It intentionally
--- does not subscribe to UNIT_SPELLCAST events or mutate live castbar frames.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local format = string.format
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local Castbar = MSUF.UFPreviewCastbar or {}
MSUF.UFPreviewCastbar = Castbar
local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end
function Castbar.OffsetFields(unitKey)
    -- Runtime and preview need the same DB keys for offsets, but only runtime owns live frame
    -- anchoring. Keep the key translation here and the actual SetPoint calls in render code.
    unitKey = CanonKey(unitKey)
    local dx, dy = 0, 0
    if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then dx, dy = _G.MSUF_GetCastbarDefaultOffsets(unitKey) end
    if unitKey == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY", dx or 0, dy or 0 end
    local prefix = type(_G.MSUF_GetCastbarPrefix) == "function" and _G.MSUF_GetCastbarPrefix(unitKey) or nil
    if not prefix or prefix == "" then return nil, nil, dx or 0, dy or 0 end
    return prefix .. "OffsetX", prefix .. "OffsetY", dx or 0, dy or 0
end
function Castbar.Prefix(unitKey)
    unitKey = CanonKey(unitKey)
    if type(_G.MSUF_GetCastbarPrefix) == "function" then return _G.MSUF_GetCastbarPrefix(unitKey) end
    if unitKey == "player" then return "castbarPlayer" end
    if unitKey == "target" then return "castbarTarget" end
    if unitKey == "focus" then return "castbarFocus" end
    return nil
end
function Castbar.Detached(key, g)
    key = CanonKey(key)
    if not g then return false end
    if key == "boss" then return g.bossCastbarDetached == true end
    local prefix = Castbar.Prefix(key)
    return prefix and g[prefix .. "Detached"] == true or false
end
local function NormalizeWidthSource(v)
    local fn = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
    if type(fn) == "function" then return fn(v) end
    if v == true then return "unitframe" end
    if v == "unitframe" or v == "essential" or v == "utility" then return v end
    return nil
end
local function WidthSourceKey(key)
    key = CanonKey(key)
    local fn = _G.MSUF_GetCastbarWidthSourceKey
    if type(fn) == "function" then
        local dbKey = fn(key)
        if dbKey then return dbKey end
    end
    if key == "player" then return "castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth" end
    if key == "target" then return "castbarTargetMatchWidth", "castbarTargetMatchUnitWidth" end
    if key == "focus" then return "castbarFocusMatchWidth", "castbarFocusMatchUnitWidth" end
    if key == "boss" then return "bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth" end
end
local function WidthSource(g, key)
    if not g then return nil end
    local primary, legacy, alias = WidthSourceKey(key)
    local source = NormalizeWidthSource(primary and g[primary])
    if source then return source end
    source = NormalizeWidthSource(alias and g[alias])
    if source then return source end
    if legacy and g[legacy] == true then return "unitframe" end
    return nil
end
local function ExternalWidthSourceFrame(source)
    if source == "essential" then
        return (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
            or _G.EssentialCooldownViewer
    elseif source == "utility" then
        return _G.UtilityCooldownViewer
    end
end
local function RuntimeCastbarFrame(key)
    key = CanonKey(key)
    if key == "boss" then
        local bars = _G.MSUF_BossCastbars
        return (bars and bars[1])
            or _G.MSUF_BossCastbar1
            or _G.MSUF_boss1CastBar
            or _G.MSUF_BossCastbar
            or _G.MSUF_BossCastbarPreview
            or _G.MSUF_BossCastbarPreview1
    elseif key == "player" then
        return _G.MSUF_PlayerCastbar or _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbarPreview
    elseif key == "target" then
        return _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbarPreview
    elseif key == "focus" then
        return _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbarPreview
    end
end
local function RuntimeUnitFrame(key)
    key = CanonKey(key)
    local unit = key == "boss" and "boss1" or key
    return CoreFrame(unit) or (unit and _G["MSUF_" .. unit])
end
local function EffectiveScaleProxy(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    scale = tonumber(scale)
    if not scale or scale <= 0 then return nil end
    return {
        GetEffectiveScale = function()
            return scale
        end
    }
end
local function ReadExternalWidth(source, targetFrame)
    local frame = ExternalWidthSourceFrame(source)
    if not (frame and frame.GetWidth and frame.IsShown and frame:IsShown()) then return nil end
    local scaleWidth = _G.MSUF_CDM_GetScaledWidth
    if type(scaleWidth) == "function" then
        local w = scaleWidth(frame, targetFrame)
        if w and w > 0 then return w end
    end
    local w = frame:GetWidth()
    if w and w > 0 then return w end
end
function Castbar.ReadSize(key, g, fallbackW, fallbackH)
    key = CanonKey(key)
    fallbackW = tonumber(fallbackW) or 250
    fallbackH = tonumber(fallbackH) or 18
    local widthSource = WidthSource(g, key)
    local targetFrame = RuntimeCastbarFrame(key) or EffectiveScaleProxy(RuntimeUnitFrame(key))
    local w, h
    if widthSource == "essential" or widthSource == "utility" then
        w = ReadExternalWidth(widthSource, targetFrame) or nil
    end
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        local desiredUnit = key == "boss" and "boss1" or key
        local desiredW, desiredH = _G.MSUF_GetCastbarDesiredSize(desiredUnit, g or {}, targetFrame, fallbackW, fallbackH)
        if not w or w <= 0 then w = desiredW end
        h = desiredH
    end
    if not w or w <= 0 then
        if key == "boss" then
            w = g and tonumber(g.bossCastbarWidth)
        else
            local prefix = Castbar.Prefix(key)
            w = prefix and g and tonumber(g[prefix .. "BarWidth"]) or nil
        end
    end
    if not h or h <= 0 then
        if key == "boss" then
            h = g and tonumber(g.bossCastbarHeight)
        else
            local prefix = Castbar.Prefix(key)
            h = prefix and g and tonumber(g[prefix .. "BarHeight"]) or nil
        end
    end
    w = tonumber(w) or fallbackW
    h = tonumber(h) or fallbackH
    if w < 40 then w = 40 elseif w > 900 then w = 900 end
    if h < 6 then h = 6 elseif h > 80 then h = 80 end
    return w, h
end
local function TextKey(key, suffix, bossKey)
    key = CanonKey(key)
    if key == "boss" then return bossKey end
    local prefix = Castbar.Prefix(key)
    return prefix and (prefix .. suffix) or nil
end
function Castbar.ReadNumber(g, key, suffix, bossKey, fallback)
    local dbKey = TextKey(key, suffix, bossKey)
    local v = dbKey and g and tonumber(g[dbKey]) or nil
    if v == nil and suffix and suffix:find("Icon", 1, true) then
        local globalKey = suffix:gsub("^Icon", "castbarIcon")
        v = g and tonumber(g[globalKey]) or nil
    end
    return (v ~= nil) and v or fallback
end
function Castbar.ReadString(g, key, suffix, bossKey, fallback)
    local dbKey = TextKey(key, suffix, bossKey)
    local value = dbKey and g and g[dbKey] or nil
    if value == nil or value == "" then value = fallback end
    return tostring(value or fallback or "")
end
function Castbar.NormalizeTextPosition(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "CENTER" or value == "RIGHT" or value == "ABOVE" or value == "BELOW" then return value end
    return "LEFT"
end
function Castbar.JustifyForTextPosition(position)
    if position == "LEFT" or position == "RIGHT" then return position end
    return "CENTER"
end
function Castbar.NormalizeTextJustify(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper()
    if value == "CENTER" or value == "RIGHT" then return value end
    return "LEFT"
end
function Castbar.AnchorText(fontString, relativeTo, position, x, y, justify, scaleFn)
    if not (fontString and relativeTo) then return end
    position = Castbar.NormalizeTextPosition(position, "LEFT")
    justify = Castbar.NormalizeTextJustify(justify, Castbar.JustifyForTextPosition(position))
    x, y = tonumber(x) or 0, tonumber(y) or 0
    if type(scaleFn) ~= "function" then scaleFn = tonumber end
    fontString:ClearAllPoints()
    if position == "CENTER" then
        fontString:SetPoint("CENTER", relativeTo, "CENTER", scaleFn(x), scaleFn(y))
    elseif position == "RIGHT" then
        fontString:SetPoint("RIGHT", relativeTo, "RIGHT", scaleFn(x), scaleFn(y))
    elseif position == "ABOVE" then
        fontString:SetPoint("BOTTOM", relativeTo, "TOP", scaleFn(x), scaleFn(y + 2))
    elseif position == "BELOW" then
        fontString:SetPoint("TOP", relativeTo, "BOTTOM", scaleFn(x), scaleFn(y - 2))
    else
        fontString:SetPoint("LEFT", relativeTo, "LEFT", scaleFn(2 + x), scaleFn(y))
    end
    -- PTR FrameXML resolves the new rect before justification for the same
    -- stale-alignment edge case (EncounterTimelineTimerEvent:UpdateNameTextLayout).
    if fontString.GetRect then fontString:GetRect() end
    fontString:SetJustifyH(justify)
end
function Castbar.ResolveTargetTextPreviewColor(key, fallbackR, fallbackG, fallbackB)
    key = CanonKey(key)
    local getDetailColor = _G.MSUF_GetCastbarDetailTextColor
    if type(getDetailColor) == "function" and key then
        local r, g, b, custom = getDetailColor(key, "TargetName")
        if custom == true then return r, g, b, true end
    end
    local getSharedColor = _G.MSUF_GetCastbarTargetNameColor
    if type(getSharedColor) == "function" then
        local r, g, b, custom = getSharedColor()
        if custom == true then return r, g, b, true end
    end
    return fallbackR or 1, fallbackG or 0.82, fallbackB or 0.20, false
end
function Castbar.FormatPreviewTime(g, key, current, total)
    local mode = "CURRENT"
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" then mode = _G.MSUF_GetCastbarTimeFormat(key, g) end
    if type(_G.MSUF_FormatCastbarTimeText) == "function" then return _G.MSUF_FormatCastbarTimeText(mode, current, total) or "" end
    return format("%.1f", tonumber(current) or 0)
end
function Castbar.Enabled(key, g)
    local fn = _G.MSUF_ShouldUseMSUFCastbar
    if type(fn) == "function" then return fn(key, g) == true end
    if key == "player" then return g.enablePlayerCastbar ~= false end
    if key == "target" then return g.enableTargetCastbar ~= false end
    if key == "focus" then return g.enableFocusCastbar ~= false end
    if key == "boss" then return g.enableBossCastbar ~= false end
    return false
end
function Castbar.ShowIcon(key, g)
    if key == "boss" then return g.showBossCastIcon ~= false end
    if key == "player" and g.castbarPlayerShowIcon ~= nil then return g.castbarPlayerShowIcon ~= false end
    if key == "target" and g.castbarTargetShowIcon ~= nil then return g.castbarTargetShowIcon ~= false end
    if key == "focus" and g.castbarFocusShowIcon ~= nil then return g.castbarFocusShowIcon ~= false end
    return g.castbarShowIcon ~= false
end
function Castbar.ShowText(key, g)
    if key == "boss" then return g.showBossCastName ~= false end
    if key == "player" and g.castbarPlayerShowSpellName ~= nil then return g.castbarPlayerShowSpellName ~= false end
    if key == "target" and g.castbarTargetShowSpellName ~= nil then return g.castbarTargetShowSpellName ~= false end
    if key == "focus" and g.castbarFocusShowSpellName ~= nil then return g.castbarFocusShowSpellName ~= false end
    return g.castbarShowSpellName ~= false
end

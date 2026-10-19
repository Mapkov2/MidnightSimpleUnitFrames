--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua
--- Cold-path castbar preview helpers.
---
--- Resolves castbar DB fields and the configured size for the Menu2 previews, which paint the engine's
--- castbar scene. It does not subscribe to UNIT_SPELLCAST events or mutate live castbar frames.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local Castbar = MSUF.UFPreviewCastbar or {}
MSUF.UFPreviewCastbar = Castbar
local CoreFrame = MSUF.UF.GetFrame
local EMPTY_DETAILS = {}
function Castbar.OffsetFields(unitKey)
    -- Runtime and preview need the same DB keys for offsets, but only runtime owns live frame
    -- anchoring. Keep the key translation here and the actual SetPoint calls in render code.
    unitKey = CanonKey(unitKey)
    local dx, dy = 0, 0
    if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then dx, dy = _G.MSUF_GetCastbarDefaultOffsets(unitKey) end
    if unitKey == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY", dx or 0, dy or 0 end
    if unitKey == "arena" then return "arenaCastbarOffsetX", "arenaCastbarOffsetY", dx or 0, dy or 0 end
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
    if key == "arena" then return g.arenaCastbarDetached == true end
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
    if key == "arena" then return "arenaCastbarMatchWidth", "castbarArenaMatchUnitWidth", "castbarArenaMatchWidth" end
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
--- The live castbar frame a unit's preview projects from (boss and arena: the
--- first frame of their pool). Runtime.lua reads the same lookup for scale and
--- detached offset.
local function RuntimeCastbarFrame(key)
    key = CanonKey(key)
    if key == "boss" then
        local bars = _G.MSUF_BossCastbars
        return (bars and bars[1])
            or _G.MSUF_BossCastbar1
            or MSUF.Castbars.Frames.Get("bossPreview")
            or _G.MSUF_BossCastbarPreview1
    elseif key == "arena" then
        local bars = _G.MSUF_ArenaCastbars
        return (bars and bars[1])
            or _G.MSUF_ArenaCastbar1
            or MSUF.Castbars.Frames.Get("arenaPreview")
            or _G.MSUF_ArenaCastbarPreview1
    elseif key == "player" then
        return MSUF.Castbars.Frames.Get("player") or MSUF.Castbars.Frames.Get("playerPreview")
    elseif key == "target" then
        return MSUF.Castbars.Frames.Get("target") or MSUF.Castbars.Frames.Get("targetPreview")
    elseif key == "focus" then
        return MSUF.Castbars.Frames.Get("focus") or MSUF.Castbars.Frames.Get("focusPreview")
    end
end
Castbar.RuntimeFrame = RuntimeCastbarFrame
local function RuntimeUnitFrame(key)
    key = CanonKey(key)
    local unit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
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
        local desiredUnit = (key == "boss" and "boss1") or (key == "arena" and "arena1") or key
        local desiredW, desiredH = _G.MSUF_GetCastbarDesiredSize(desiredUnit, g or {}, targetFrame, fallbackW, fallbackH)
        if not w or w <= 0 then w = desiredW end
        h = desiredH
    end
    if not w or w <= 0 then
        if key == "boss" then
            w = g and tonumber(g.bossCastbarWidth)
        elseif key == "arena" then
            w = g and tonumber(g.arenaCastbarWidth)
        else
            local prefix = Castbar.Prefix(key)
            w = prefix and g and tonumber(g[prefix .. "BarWidth"]) or nil
        end
    end
    if not h or h <= 0 then
        if key == "boss" then
            h = g and tonumber(g.bossCastbarHeight)
        elseif key == "arena" then
            h = g and tonumber(g.arenaCastbarHeight)
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
    if key == "arena" and bossKey then return (bossKey:gsub("^bossCast", "arenaCast")) end
    local prefix = Castbar.Prefix(key)
    return prefix and (prefix .. suffix) or nil
end
function Castbar.ReadNumber(g, key, suffix, bossKey, fallback)
    g = g or EMPTY_DETAILS
    local dbKey = TextKey(key, suffix, bossKey)
    local globalKey
    if suffix and suffix:find("Icon", 1, true) then globalKey = suffix:gsub("^Icon", "castbarIcon") end
    return MSUF.Castbars.Visuals.DetailNum(g, nil, nil, dbKey, nil)
        or MSUF.Castbars.Visuals.DetailNum(g, nil, nil, globalKey, fallback)
end
function Castbar.Enabled(key, g)
    local fn = _G.MSUF_ShouldUseMSUFCastbar
    if type(fn) == "function" then return fn(key, g) == true end
    if key == "player" then return g.enablePlayerCastbar ~= false end
    if key == "target" then return g.enableTargetCastbar ~= false end
    if key == "focus" then return g.enableFocusCastbar ~= false end
    if key == "boss" then return g.enableBossCastbar ~= false end
    if key == "arena" then return g.enableArenaCastbar ~= false end
    return false
end
function Castbar.ShowIcon(key, g)
    return MSUF.Castbars.Visuals.ShowIconForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end
function Castbar.ShowText(key, g)
    return MSUF.Castbars.Visuals.ShowSpellForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end

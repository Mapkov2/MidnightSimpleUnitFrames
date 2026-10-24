--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua
--- Cold-path castbar preview helpers.
---
--- Resolves castbar DB fields and the configured size for the Menu2 previews, which paint the engine's
--- castbar scene. It does not subscribe to UNIT_SPELLCAST events or mutate live castbar frames.
local MSUF = _G.MSUF
local FILE = "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua"
local Preview = MSUF.UFPreview or {}
local PreviewModel = Preview.Model or {}
local CanonKey = PreviewModel.CanonKey
local Castbar = MSUF.UFPreviewCastbar or {}
MSUF.UFPreviewCastbar = Castbar
local CoreFrame = MSUF.UF.GetFrame
local EMPTY_DETAILS = {}
-- The castbar module API is published once by the core castbar files, which load before this addon. It is
-- resolved here because these lookups run on every preview refresh and drag step.
local GetCastbarDefaultOffsets = MSUF.Require("MSUF_GetCastbarDefaultOffsets", FILE)
local GetCastbarPrefix = MSUF.Require("MSUF_GetCastbarPrefix", FILE)
local NormalizeWidthSource = MSUF.Require("MSUF_NormalizeCastbarWidthSource", FILE)
local GetCastbarWidthSourceKey = MSUF.Require("MSUF_GetCastbarWidthSourceKey", FILE)
local GetCastbarDesiredSize = MSUF.Require("MSUF_GetCastbarDesiredSize", FILE)
local ShouldUseMSUFCastbar = MSUF.Require("MSUF_ShouldUseMSUFCastbar", FILE)
local GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", FILE)
local CDMGetScaledWidth = MSUF.Require("MSUF_CDM_GetScaledWidth", FILE)
local PREVIEW_CASTBAR_KEYS = { player = "playerPreview", target = "targetPreview", focus = "focusPreview" }
local RUNTIME_UNITS = { boss = "boss1", arena = "arena1" }
function Castbar.OffsetFields(unitKey)
    -- Runtime and preview need the same DB keys for offsets, but only runtime owns live frame
    -- anchoring. Keep the key translation here and the actual SetPoint calls in render code.
    unitKey = CanonKey(unitKey)
    local dx, dy = GetCastbarDefaultOffsets(unitKey)
    dx, dy = dx or 0, dy or 0
    if unitKey == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY", dx, dy end
    if unitKey == "arena" then return "arenaCastbarOffsetX", "arenaCastbarOffsetY", dx, dy end
    local prefix = GetCastbarPrefix(unitKey)
    if not prefix or prefix == "" then return nil, nil, dx, dy end
    return prefix .. "OffsetX", prefix .. "OffsetY", dx, dy
end
function Castbar.Prefix(unitKey)
    return GetCastbarPrefix(CanonKey(unitKey))
end
function Castbar.Detached(key, g)
    key = CanonKey(key)
    if not g then return false end
    if key == "boss" then return g.bossCastbarDetached == true end
    if key == "arena" then return g.arenaCastbarDetached == true end
    local prefix = Castbar.Prefix(key)
    return prefix and g[prefix .. "Detached"] == true or false
end
local function WidthSourceKey(key)
    key = CanonKey(key)
    local dbKey = GetCastbarWidthSourceKey(key)
    if dbKey then return dbKey end
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
-- Blizzard's cooldown viewers appear when their load-on-demand addon loads, so they are read at use time.
local function ExternalWidthSourceFrame(source)
    if source == "essential" then
        return GetEffectiveCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
    elseif source == "utility" then
        return UtilityCooldownViewer
    end
end
--- The live castbar frame a unit's preview projects from (boss and arena: the
--- first frame of their pool). Runtime.lua reads the same lookup for scale and
--- detached offset. The pool tables are the castbar pools' published tables (the
--- MSUF_BossCastbars / MSUF_ArenaCastbars globals); the frames are named globals.
local function RuntimeCastbarFrame(key)
    key = CanonKey(key)
    if key == "boss" then
        local bars = MSUF.Castbars.Pools.BossCastbars
        return (bars and bars[1])
            or MSUF_BossCastbar1
            or MSUF.Castbars.Frames.Get("bossPreview")
    elseif key == "arena" then
        local bars = MSUF.Castbars.Pools.ArenaCastbars
        return (bars and bars[1])
            or MSUF_ArenaCastbar1
            or MSUF.Castbars.Frames.Get("arenaPreview")
            or MSUF_ArenaCastbarPreview1
    end
    local previewKey = PREVIEW_CASTBAR_KEYS[key]
    if previewKey then
        return MSUF.Castbars.Frames.Get(key) or MSUF.Castbars.Frames.Get(previewKey)
    end
end
Castbar.RuntimeFrame = RuntimeCastbarFrame
local function RuntimeUnitFrame(key)
    key = CanonKey(key)
    local unit = RUNTIME_UNITS[key] or key
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
    local scaled = CDMGetScaledWidth(frame, targetFrame)
    if scaled and scaled > 0 then return scaled end
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
    local desiredW, desiredH = GetCastbarDesiredSize(RUNTIME_UNITS[key] or key, g or {}, targetFrame, fallbackW, fallbackH)
    if not w or w <= 0 then w = desiredW end
    h = desiredH
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
    return ShouldUseMSUFCastbar(key, g) == true
end
function Castbar.ShowIcon(key, g)
    return MSUF.Castbars.Visuals.ShowIconForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end
function Castbar.ShowText(key, g)
    return MSUF.Castbars.Visuals.ShowSpellForUnit(g, key, MSUF.Castbars.Visuals.PrefixForUnit(key))
end

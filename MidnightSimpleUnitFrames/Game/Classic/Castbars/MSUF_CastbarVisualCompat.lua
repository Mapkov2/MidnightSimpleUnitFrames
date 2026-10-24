--- Classic-only castbar geometry compatibility.
---
--- The shared Castbars/ files keep Retail's geometry and reach the spark and
--- outline inset through the public entries this file replaces. Classic uses
--- a static casting-bar spark and permits very small custom bars; constrain the
--- outline inset to a drawable inner surface and size the spark from that
--- surface instead of the outer frame.

local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Game/Classic/Castbars/MSUF_CastbarVisualCompat.lua")
local Castbars = MSUF.Castbars
local Visuals = Castbars.Visuals
local Config = Castbars.Config
local Core = Castbars.Core
local Frames = Castbars.Frames
local PublicAPI = Castbars.PublicAPI
local Style = Castbars.Style
local Utils = Castbars.Utils

local type = type
local tonumber = tonumber
local math_max = math.max
local math_min = math.min
local unpack = unpack or table.unpack

local CLASSIC_SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local MIN_INNER_HEIGHT = 2

local SharedGetOutlineInset = Style.GetCastbarOutlineInset

local function RegionHeight(region, fallback)
    if region and type(region.GetHeight) == "function" then
        local height = tonumber(region:GetHeight())
        if height and height > 0 then return height end
    end
    return fallback
end

local function GetClassicOutlineInset(frame, general)
    local inset = 0
    if type(SharedGetOutlineInset) == "function" then
        inset = tonumber(SharedGetOutlineInset(frame, general)) or 0
    end
    if inset < 0 then inset = 0 end

    local outerHeight = RegionHeight(frame)
    if outerHeight then
        local innerFloor = math_min(MIN_INNER_HEIGHT, outerHeight)
        local maxInset = math_max(0, (outerHeight - innerFloor) * 0.5)
        inset = math_min(inset, maxInset)
    end
    return inset
end

local function GeneralDB(general)
    if general then return general end
    local db = Config.Read()
    return (db and db.general) or {}
end

local function EnsureClassicSpark(frame, statusBar)
    local spark = frame.spark
    if not spark and statusBar and type(statusBar.CreateTexture) == "function" then
        spark = PixelLayoutRegion(statusBar:CreateTexture(nil, "OVERLAY", nil, 6))
        frame.spark = spark
    end
    if not spark then return nil end

    if spark._msufClassicSparkTexture ~= true then
        spark:SetTexture(CLASSIC_SPARK_TEXTURE)
        spark:SetTexCoord(0, 1, 0, 1)
        if spark.SetDesaturated then spark:SetDesaturated(true) end
        if spark.SetVertexColor then spark:SetVertexColor(1, 1, 1, 1) end
        if spark.SetBlendMode then spark:SetBlendMode("ADD") end
        spark._msufClassicSparkTexture = true
    end
    return spark
end

local function ApplyClassicSparkVisual(frame, general)
    local statusBar = frame and frame.statusBar
    if not statusBar then return end

    general = GeneralDB(general)
    local enabled = general.castbarShowSpark == true
    local spark = frame.spark
    if enabled then spark = EnsureClassicSpark(frame, statusBar) end
    if not spark then return end

    if spark.SetShown then
        spark:SetShown(enabled)
    elseif enabled then
        spark:Show()
    else
        spark:Hide()
    end
    if not enabled then return end

    local innerHeight = RegionHeight(statusBar, RegionHeight(frame, 18)) or 18
    if innerHeight < 1 then innerHeight = 1 end
    local allowOverflow = general.castbarSparkOverflow ~= false
    local sparkHeight = allowOverflow and math_max(4, innerHeight * 2.1) or innerHeight
    local sparkWidth = 16
    local currentWidth = spark.GetWidth and tonumber(spark:GetWidth()) or spark._msufClassicSparkWidth
    local currentHeight = spark.GetHeight and tonumber(spark:GetHeight()) or spark._msufClassicSparkHeight
    if currentWidth ~= sparkWidth or currentHeight ~= sparkHeight then
        spark:SetSize(sparkWidth, sparkHeight)
        spark._msufClassicSparkWidth = sparkWidth
        spark._msufClassicSparkHeight = sparkHeight
    end

    local fillTexture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    if fillTexture then
        local reversed = false
        if type(Utils.GetCastbarReverseFillForFrame) == "function" then
            reversed = Utils.GetCastbarReverseFillForFrame(frame, false) == true
        elseif statusBar.GetReverseFill then
            reversed = statusBar:GetReverseFill() and true or false
        end
        if spark._msufClassicSparkAnchorTexture ~= fillTexture
            or spark._msufClassicSparkAnchorReversed ~= reversed then
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", fillTexture, reversed and "LEFT" or "RIGHT", 0, 0)
            spark._msufClassicSparkAnchorTexture = fillTexture
            spark._msufClassicSparkAnchorReversed = reversed
        end
    end
end

local function ApplyToUnit(unit, general)
    unit = tostring(unit or "")
    if unit:match("^boss%d+$") then unit = "boss" end
    if unit:match("^arena%d+$") then unit = "arena" end

    if unit == "player" then
        ApplyClassicSparkVisual(Frames.player, general)
        ApplyClassicSparkVisual(Frames.playerPreview, general)
    elseif unit == "target" then
        ApplyClassicSparkVisual(Frames.target, general)
        ApplyClassicSparkVisual(Frames.targetPreview, general)
    elseif unit == "focus" then
        ApplyClassicSparkVisual(Frames.focus, general)
        ApplyClassicSparkVisual(Frames.focusPreview, general)
    else
        -- Boss and arena: every slot's live bar and preview (MSUF_CastbarPools.lua).
        local pools = MSUF.Castbars and MSUF.Castbars.Pools
        local pool = pools and pools.kinds and pools.kinds[unit]
        if not pool then return end
        local preview = pool.preview
        for index = 1, pool.maxFrames do
            ApplyClassicSparkVisual(pool.Bar(index), general)
            if preview then ApplyClassicSparkVisual(preview:Frame(index), general) end
        end
    end
end

local function ApplyToAll(general)
    ApplyToUnit("player", general)
    ApplyToUnit("target", general)
    ApplyToUnit("focus", general)
    ApplyToUnit("boss", general)
    ApplyToUnit("arena", general)
end

local function HookModule(module, key, name, callback)
    local original = module[key]
    if not original then return false end
    module[key] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
    PublicAPI.Publish(name, module[key])
    return true
end

Style.GetCastbarOutlineInset = GetClassicOutlineInset
Core.ApplyCastbarSparkVisual = ApplyClassicSparkVisual
Style.ClassicCastbar_GetOutlineInset = GetClassicOutlineInset
Style.ClassicCastbar_ApplySparkVisual = ApplyClassicSparkVisual

HookModule(Visuals, "RefreshCastbarFrame", "MSUF_RefreshCastbarFrame", function(frame, _, general)
    ApplyClassicSparkVisual(frame, general)
end)
HookModule(Core, "ApplyCastbarVisualsForUnit", "MSUF_ApplyCastbarVisualsForUnit", function(unit, _, general)
    ApplyToUnit(unit, general)
end)
HookModule(Core, "UpdateCastbarVisuals", "MSUF_UpdateCastbarVisuals", function(unit)
    if unit then ApplyToUnit(unit) else ApplyToAll() end
end)
HookModule(Core, "UpdateCastbarVisuals_Immediate", "MSUF_UpdateCastbarVisuals_Immediate", function(unit)
    if unit then ApplyToUnit(unit) else ApplyToAll() end
end)
HookModule(Core, "ApplyAllCastbarsAndSync", "MSUF_ApplyAllCastbarsAndSync", function()
    ApplyToAll()
end)

-- The shared callback closes over its local visual function. Replace only that
-- callback key so Classic routes the cold refresh through the hooked public
-- entry and applies the final inner-surface spark geometry afterward.
local UF = MSUF.UF
if UF and type(UF.RegisterVisualRefreshCallback) == "function" then
    UF.RegisterVisualRefreshCallback("Castbars", function(unit)
        if unit ~= nil and unit ~= "*" and type(Core.ApplyCastbarVisualsForUnit) == "function" then
            Core.ApplyCastbarVisualsForUnit(unit)
        end
    end)
end

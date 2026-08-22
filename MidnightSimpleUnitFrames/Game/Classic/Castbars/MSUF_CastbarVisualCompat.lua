--- Classic-only castbar geometry compatibility.
---
--- Keep the canonical Castbars/ files byte-identical with Retail. Classic uses
--- a static casting-bar spark and permits very small custom bars; constrain the
--- outline inset to a drawable inner surface and size the spark from that
--- surface instead of the outer frame.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local G = _G
local type = type
local tonumber = tonumber
local math_max = math.max
local math_min = math.min
local unpack = unpack or table.unpack

local CLASSIC_SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local MIN_INNER_HEIGHT = 2

local ExportPublic = MSUF.ExportPublic or function(name, value)
    G[name] = value
    MSUF[name] = value
    return value
end

local SharedGetOutlineInset = G.MSUF_GetCastbarOutlineInset

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
    local db = G.MSUF_DB
    return (db and db.general) or {}
end

local function EnsureClassicSpark(frame, statusBar)
    local spark = frame.spark
    if not spark and statusBar and type(statusBar.CreateTexture) == "function" then
        spark = statusBar:CreateTexture(nil, "OVERLAY", nil, 6)
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
        if type(G.MSUF_GetCastbarReverseFillForFrame) == "function" then
            reversed = G.MSUF_GetCastbarReverseFillForFrame(frame, false) == true
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
        ApplyClassicSparkVisual(G.MSUF_PlayerCastbar or G.MSUF_PlayerCastBar, general)
        ApplyClassicSparkVisual(G.MSUF_PlayerCastbarPreview, general)
    elseif unit == "target" then
        ApplyClassicSparkVisual(G.MSUF_TargetCastbar or G.MSUF_TargetCastBar, general)
        ApplyClassicSparkVisual(G.MSUF_TargetCastbarPreview, general)
    elseif unit == "focus" then
        ApplyClassicSparkVisual(G.MSUF_FocusCastbar or G.MSUF_FocusCastBar, general)
        ApplyClassicSparkVisual(G.MSUF_FocusCastbarPreview, general)
    elseif unit == "boss" then
        local count = tonumber(G.MSUF_MAX_BOSS_FRAMES or G.MAX_BOSS_FRAMES) or 5
        count = math_max(1, math_min(12, count))
        local frames = G.MSUF_BossCastbars
        for index = 1, count do
            ApplyClassicSparkVisual((frames and frames[index])
                or G["MSUF_BossCastbar" .. index]
                or G["MSUF_BossCastBar" .. index], general)
            ApplyClassicSparkVisual(G["MSUF_BossCastbarPreview" .. index], general)
        end
    elseif unit == "arena" then
        local count = tonumber(G.MSUF_MAX_ARENA_FRAMES) or 3
        count = math_max(1, math_min(12, count))
        local frames = G.MSUF_ArenaCastbars
        for index = 1, count do
            ApplyClassicSparkVisual((frames and frames[index])
                or G["MSUF_ArenaCastbar" .. index]
                or G["MSUF_ArenaCastBar" .. index], general)
            ApplyClassicSparkVisual(G["MSUF_ArenaCastbarPreview" .. index], general)
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

local function HookGlobal(name, callback)
    local original = G[name]
    if type(original) ~= "function" then return false end
    if type(G.hooksecurefunc) == "function" then
        G.hooksecurefunc(name, callback)
        return true
    end

    -- Test/legacy fallback. These are cold-path visual functions, so preserving
    -- the return tuple through a short temporary table has no hot-path cost.
    G[name] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
    MSUF[name] = G[name]
    return true
end

ExportPublic("MSUF_GetCastbarOutlineInset", GetClassicOutlineInset)
ExportPublic("MSUF_ApplyCastbarSparkVisual", ApplyClassicSparkVisual)
ExportPublic("MSUF_ClassicCastbar_GetOutlineInset", GetClassicOutlineInset)
ExportPublic("MSUF_ClassicCastbar_ApplySparkVisual", ApplyClassicSparkVisual)

HookGlobal("MSUF_RefreshCastbarFrame", function(frame, _, general)
    ApplyClassicSparkVisual(frame, general)
end)
HookGlobal("MSUF_ApplyCastbarVisualsForUnit", function(unit, _, general)
    ApplyToUnit(unit, general)
end)
HookGlobal("MSUF_UpdateCastbarVisuals", function(unit)
    if unit then ApplyToUnit(unit) else ApplyToAll() end
end)
HookGlobal("MSUF_UpdateCastbarVisuals_Immediate", function(unit)
    if unit then ApplyToUnit(unit) else ApplyToAll() end
end)
HookGlobal("MSUF_ApplyAllCastbarsAndSync", function()
    ApplyToAll()
end)

-- The shared callback closes over its local visual function. Replace only that
-- callback key so Classic routes the cold refresh through the hooked public
-- entry and applies the final inner-surface spark geometry afterward.
local UF = MSUF.UF
if UF and type(UF.RegisterVisualRefreshCallback) == "function" then
    UF.RegisterVisualRefreshCallback("Castbars", function(unit)
        if unit ~= nil and unit ~= "*" and type(G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            G.MSUF_ApplyCastbarVisualsForUnit(unit)
        end
    end)
end

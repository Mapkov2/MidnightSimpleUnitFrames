--- ClassPower/MSUF_CP_Controller_Surface.lua - controller surface helpers
--- Cold-path surface bundle for the ClassPower controller.
---
--- Apply-time helpers that decide where, and with which media, the class
--- resource surface renders: the Ebon Might host on the Player Power bar and
--- its style, the Aug composite state reset, the hidden anchor kept alive for a
--- detached Power bar, the DK Rune display order and the cooldown-frame width
--- sync (CP.CDMWidth*). The event (un)binding for that sync stays in the
--- controller next to its event frame.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

--- The player-frame resolver is owned by ClassPower/MSUF_CP_Core.lua, which
--- the TOC loads before this file.
local CoreUnitFrame = _G.MSUF_CP_CoreUnitFrame

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

local type, tonumber = type, tonumber
local math_floor = math.floor

--- Cross-file collaborators; every provider loads before ClassPower in each
--- client TOC (Castbars, the unit-frame runtime), so a missing one fails here.
local FILE = "ClassPower/MSUF_CP_Controller_Surface.lua"
local GetFontPath = MSUF.Require("MSUF_GetFontPath", FILE)
local GetFontFlags = MSUF.Require("MSUF_GetFontFlags", FILE)
local ApplyPowerBarEmbedLayoutAll = MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_All", FILE)
local table_sort = table.sort
local InCombatLockdown = InCombatLockdown

--- DK Rune display-order comparators. The rune map is a static
--- [display_slot] = rune_id table that is re-sorted only when the setting
--- changes, so both orders are fixed rune-id orders: "asc" shows rune 1 in
--- the first slot (the natural order), "desc" shows rune 6 there.
local function _runeAscSort(a, b) return a < b end
local function _runeDescSort(a, b) return a > b end

--- Bound once by CONTROLLER_SURFACE: the shared state, cached config and the
--- BUILD/LAYOUT/colour entry points the controller passes by value.
local CP, _cpDB, CPConst, ResolveClassPowerColor, CP_ResolveTexture
local CP_Create, CP_EnsureBars, CP_Layout

local function CP_ClearAugCompositeState()
    local wasActive = CP.augCompositeActive == true or _G.MSUF_AugEvokerActive == true
    CP.augCompositeActive = false
    CP.ebonSensorDesired = false
    CP.ebonSensorRetryPending = nil
    CP.ebonTextLayerRetryPending = nil
    CP.ebonStyleRetryPending = nil
    ExportPublic("MSUF_AugEvokerActive", false)
    return wasActive
end

--- DK Rune map: [display_slot] = rune_id (1-6), sorted per sortOrder
--- Fresh on every build.
local _runeMap
local _runeAppliedSortOrder

local function CP_ApplyRuneSortOrder(sortOrder)
    local wanted = (sortOrder == "asc" or sortOrder == "desc") and sortOrder or "natural"
    if _runeAppliedSortOrder == wanted then return end

    if wanted == "asc" then
        table_sort(_runeMap, _runeAscSort)
    elseif wanted == "desc" then
        table_sort(_runeMap, _runeDescSort)
    else
        for i = 1, 6 do _runeMap[i] = i end
    end

    _runeAppliedSortOrder = wanted
end

local function CP_GetRuneMap()
    return _runeMap
end

--- Ebon Might lives on the Player Power bar itself: Essence keeps the ordinary
--- Class Resource surface and Mana moves to the Alternative Mana bar. The bar is
--- owned by the Power element, which sizes, anchors, layers and skins it from
--- the ordinary Player Power settings; ClassPower only mounts the native
--- AuraContainer on top of it.
local function CP_ResolveEbonHost()
    local playerFrame = CP._pf or (CoreUnitFrame and CoreUnitFrame("player")) or _G.MSUF_player
    local bar = playerFrame and playerFrame.targetPowerBar or nil
    if bar then CP.ebonHost = bar end
    return bar or CP.ebonHost
end

local function GetEbonTextLevel()
    local host = CP.ebonHost
    local p = MSUF_DB and MSUF_DB.player or nil
    local textLayer = tonumber(p and p.powerTextLayer) or 2
    if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
    textLayer = math_floor(textLayer + 0.5)
    if host and host.GetFrameLevel then
        return (host:GetFrameLevel() or 0) + 1 + textLayer
    end
    local layers = MSUF.UF and MSUF.UF.Layers
    return layers and layers.TextLevel and layers.TextLevel(CP.container, textLayer, 5)
        or (layers and layers.ElementLevel and layers.ElementLevel(textLayer, 5, 8))
        or ((CP.container and CP.container.GetFrameLevel and CP.container:GetFrameLevel() or 0) + 10)
end

--- Ebon Might is the Player Power bar's content, so its media, alpha and text
--- style come from the ordinary Player Power configuration. Only the fill colour
--- still resolves through the EBON_MIGHT token, because that is where every
--- other class-resource colour lives on the Colors page.
local function CP_GetEbonStyle()
    local playerFrame = CP._pf or CoreUnitFrame("player") or _G.MSUF_player
    local powerSpec = playerFrame and playerFrame.MSUFSpec and playerFrame.MSUFSpec.power or nil
    local p = MSUF_DB and MSUF_DB.player or nil
    local general = MSUF_DB and MSUF_DB.general or nil
    local b = _cpDB.bars or {}

    local r, g, blue = 1, 1, 1
    if _cpDB.colorByType ~= false then
        r, g, blue = ResolveClassPowerColor("EBON_MIGHT")
    end

    local fontPath = GetFontPath()
    local fontFlags = GetFontFlags()
    if not fontPath or fontPath == "" then fontPath = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
    if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
    local fontSize = tonumber(p and p.powerFontSize) or tonumber(general and general.powerFontSize) or 14
    if fontSize < 6 then fontSize = 6 elseif fontSize > 48 then fontSize = 48 end
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        fontPath = resolveSafe(fontPath, fontSize, fontFlags, general and general.fontKey) or fontPath
    end

    --- Same precedence the Text element uses for ordinary power slots: a frame
    --- font override may flip colour-by-type, otherwise the shared Fonts scope
    --- decides. Colour-by-type on this bar means the Ebon Might colour.
    local colorByType = general ~= nil and general.colorPowerTextByType == true
    if p and p.fontOverride == true then
        if p.powerTextColorByType ~= nil then
            colorByType = p.powerTextColorByType == true
        elseif p.colorPowerTextByType ~= nil then
            colorByType = p.colorPowerTextByType == true
        end
    end
    local textR, textG, textB, textA = 1, 1, 1, 1
    if colorByType then
        textR, textG, textB = r, g, blue
    else
        local getColor = _G.MSUF_GetConfiguredFontColor
        if type(getColor) == "function" then
            local cr, cg, cb, ca = getColor()
            textR = tonumber(cr) or 1
            textG = tonumber(cg) or 1
            textB = tonumber(cb) or 1
            textA = tonumber(ca) or 1
        end
    end

    return {
            texture = CP_ResolveTexture(powerSpec and powerSpec.texture
                or b.powerBarTexture or b.classPowerTexture),
            barR = r, barG = g, barB = blue,
            barA = tonumber(powerSpec and powerSpec.alpha) or 1,
            fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
            textR = textR, textG = textG, textB = textB, textA = textA,
            textLevel = CP.GetEbonTextLevel(),
            textOffsetX = tonumber(p and p.powerOffsetX) or 0,
            textOffsetY = tonumber(p and p.powerOffsetY) or 0,
    }
end

--- The Power element calls this once its bar is laid out and skinned, which is
--- also the only moment the host is guaranteed to exist. Creating the native
--- container is a restricted operation, so a combat-time call just arms the
--- existing PLAYER_REGEN retry instead of failing.
local function CP_MountEbonMight(bar)
    if bar then CP.ebonHost = bar end
    if CP.augCompositeActive ~= true then return false end
    if type(CP.SetEbonSensorActive) ~= "function" then return false end
    return CP.SetEbonSensorActive(true) == true
end

local function CP_ShouldMaintainHiddenAnchor(forEditMode)
    local b = _cpDB.bars or {}
    if forEditMode == true and _G.MSUF_UnitEditModeActive == true
        and b.showClassPower ~= false then
        return true
    end
    local p = MSUF_DB and MSUF_DB.player
    if not p or p.powerBarDetached ~= true or p.detachedPowerBarAnchorToClassPower ~= true then
        return false
    end
    return b.showClassPower ~= false
end

local function CP_EnsureHiddenAnchorGeometry(playerFrame, cpHeight, forEditMode)
    if not (playerFrame and CP_Create and CP_EnsureBars and CP_Layout) then return false end
    if not CP_ShouldMaintainHiddenAnchor(forEditMode) then return false end

    CP_Create(playerFrame)

    local maxP = tonumber(CP.currentMax) or 5
    if maxP < 1 then maxP = 5 end
    if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end

    CP_EnsureBars(playerFrame, maxP)
    CP_Layout(playerFrame, maxP, cpHeight, CP.powerType)
    CP._pf = playerFrame
    CP._layoutH = cpHeight

    if CP.container then
        CP.container._msufAnchorOnly = true
        CP.container:Hide()
    end
    return true
end

local function CP_CDMWidthResolveFrame(frameName)
    if type(frameName) ~= "string" or frameName == "" then return nil end
    local resolver = _G.MSUF_GetEffectiveCooldownFrame
    local frame = type(resolver) == "function" and resolver(frameName) or nil
    return frame or _G[frameName]
end

local function CDMWidthIsPositionLocked()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function CDMWidthGetDetachedPowerBarName()
    local b = _cpDB.bars or {}
    local cdmName = CPConst.CDM_FRAMES and CPConst.CDM_FRAMES[b.detachedPowerBarWidthMode or ""]
    if not cdmName then return nil end
    local db = MSUF_DB
    if not db then return nil end
    local readEnabled = _G.MSUF_ReadUnitPowerBarEnabled
    local player = db.player
    -- The Detached width mode drives the bar with or without width sync, so this
    -- watcher must not be gated on sync: doing so watched the one case where the
    -- source is a fallback and went blind in the case where it owns the width.
    if not player or player.powerBarDetached ~= true then return nil end
    if readEnabled and readEnabled("player", db) == false then return nil end
    return cdmName
end

local function CDMWidthGetConfiguredNames()
    local b = _cpDB.bars or {}
    local cpName = (CP.visible and CPConst.CDM_FRAMES and CPConst.CDM_FRAMES[b.classPowerWidthMode or ""]) or nil
    local pbName = CP.CDMWidthGetDetachedPowerBarName()
    return cpName, pbName
end

local function CDMWidthHasConfiguredSync()
    local cpName, pbName = CP.CDMWidthGetConfiguredNames()
    return cpName ~= nil or pbName ~= nil
end

local function CDMWidthFrameUsable(frameName)
    local cdm = CP_CDMWidthResolveFrame(frameName)
    local getSize = _G.MSUF_GetUsableCooldownAnchorSize
    return type(getSize) == "function" and getSize(cdm) ~= nil
end

local function CDMWidthGetNames()
    local cpName, pbName = CP.CDMWidthGetConfiguredNames()
    if cpName and not CP.CDMWidthFrameUsable(cpName) then cpName = nil end
    if pbName and not CP.CDMWidthFrameUsable(pbName) then pbName = nil end
    return cpName, pbName
end

local function CDMWidthWantsSync()
    local cpName, pbName = CP.CDMWidthGetNames()
    return cpName ~= nil or pbName ~= nil
end

local function CDMWidthReadSig(frameName)
    local cdm = CP_CDMWidthResolveFrame(frameName)
    local getScaledWidth = _G.MSUF_GetCooldownAnchorScaledWidth
    local width = type(getScaledWidth) == "function" and getScaledWidth(cdm) or nil
    return width and math_floor(width + 0.5) or 0
end

local function CDMWidthMarkChanged(tag, frameName, force)
    if not frameName then return false end
    local sig = CP.CDMWidthReadSig(frameName)
    local key = tag .. ":" .. frameName
    local cache = CP._cdmWidthSig
    if force or cache[key] ~= sig then
        cache[key] = sig
        return true
    end
    return false
end

local function CDMWidthSyncLayouts(force)
    if CP.CDMWidthIsPositionLocked() then return end
    local cpName, pbName = CP.CDMWidthGetNames()
    if not cpName and not pbName then return end

    local cpChanged = CP.CDMWidthMarkChanged("cp", cpName, force)
    local pbChanged = CP.CDMWidthMarkChanged("pb", pbName, force)

    if cpChanged and CP.visible and CP._pf and CP.currentMax and CP.currentMax > 0 and CP_Layout then
        local b = _cpDB.bars or {}
        CP_Layout(CP._pf, CP.currentMax, CP._layoutH or (b.classPowerHeight or 4), CP.powerType)
        if CP.ironfur and CP.ironfur.InvalidateLayout then
            CP.ironfur.InvalidateLayout()
        end
    end
    if pbChanged then
        ApplyPowerBarEmbedLayoutAll()
    end
end

--- CONTROLLER_SURFACE is built once, after the BUILD and LAYOUT builders have
--- bound CP_Create / CP_EnsureBars / CP_Layout, so those can be passed by value.
--- It installs CP.GetEbonTextLevel and the CP.CDMWidth* helpers on the shared
--- state table, publishes the Ebon Might mount hook and returns the helpers.
builders.CONTROLLER_SURFACE = function(E)
    CP, _cpDB, CPConst = E.CP, E._cpDB, E.CPConst
    ResolveClassPowerColor, CP_ResolveTexture = E.ResolveClassPowerColor, E.CP_ResolveTexture
    CP_Create, CP_EnsureBars, CP_Layout = E.CP_Create, E.CP_EnsureBars, E.CP_Layout
    _runeMap = { 1, 2, 3, 4, 5, 6 }
    _runeAppliedSortOrder = "natural"
    CP.GetEbonTextLevel = GetEbonTextLevel
    ExportPublic("MSUF_ClassPower_MountEbonMight", CP_MountEbonMight)
    CP._cdmWidthSig = CP._cdmWidthSig or {}
    CP.CDMWidthIsPositionLocked = CDMWidthIsPositionLocked
    CP.CDMWidthGetDetachedPowerBarName = CDMWidthGetDetachedPowerBarName
    CP.CDMWidthGetConfiguredNames = CDMWidthGetConfiguredNames
    CP.CDMWidthHasConfiguredSync = CDMWidthHasConfiguredSync
    CP.CDMWidthFrameUsable = CDMWidthFrameUsable
    CP.CDMWidthGetNames = CDMWidthGetNames
    CP.CDMWidthWantsSync = CDMWidthWantsSync
    CP.CDMWidthReadSig = CDMWidthReadSig
    CP.CDMWidthMarkChanged = CDMWidthMarkChanged
    CP.CDMWidthSyncLayouts = CDMWidthSyncLayouts
    return {
        ClearAugCompositeState = CP_ClearAugCompositeState,
        ApplyRuneSortOrder = CP_ApplyRuneSortOrder,
        GetRuneMap = CP_GetRuneMap,
        ResolveEbonHost = CP_ResolveEbonHost,
        GetEbonStyle = CP_GetEbonStyle,
        EnsureHiddenAnchorGeometry = CP_EnsureHiddenAnchorGeometry,
    }
end

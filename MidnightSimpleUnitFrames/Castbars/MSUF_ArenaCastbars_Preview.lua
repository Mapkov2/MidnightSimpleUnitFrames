--- Castbars/MSUF_ArenaCastbars_Preview.lua
--- Edit/menu previews for arena castbars.
---
--- Preview frames are non-combat, non-event copies that mirror arena castbar
--- geometry and styling. They never subscribe to UNIT_SPELLCAST events; real
--- arena castbars own live state. Mirrors MSUF_BossCastbars_Preview.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end

local MAX_ARENA_FRAMES = 3

local function GeneralDB()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end

    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general
end

local function InCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end

local function PreviewEnabled()
    local general = GeneralDB()
    -- The Menu2 castbar/arena page's transient preview must survive texture
    -- and layout re-applies that funnel through UpdateArenaCastbarPreview.
    if _G.MSUF2_CastbarPagePreviewUnit == "arena" then
        return not (MSUF_DB.arena and MSUF_DB.arena.enabled == false)
    end
    if _G.MSUF_UnitEditModeActive ~= true or not general.castbarPlayerPreviewEnabled then
        return false
    end

    if MSUF_DB.arena and MSUF_DB.arena.enabled == false then
        return false
    end

    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar
    return type(shouldUseMSUF) == "function"
        and shouldUseMSUF("arena", general) == true
        or general.enableArenaCastbar ~= false
end

local UpdateArenaCastbarPreview

local function ArenaUnitFrame(index)
    local unit = "arena" .. index
    return CoreFrame(unit) or _G["MSUF_" .. unit]
end

local function Snap(frame, value)
    value = tonumber(value) or 0
    if type(_G.MSUF_Snap) == "function" then
        return _G.MSUF_Snap(frame, value)
    end
    return math.floor(value + 0.5)
end

local function HideAllArenaCastbarPreviews()
    for index = 1, MAX_ARENA_FRAMES do
        local preview = _G["MSUF_ArenaCastbarPreview" .. index]
        if preview then
            preview:Hide()
        end
    end
end

--- Create one preview per arena unit slot. Intentionally inert: no cast
--- progression, no event registration, just layout/style.
local function CreateArenaCastbarPreview(index)
    local name = "MSUF_ArenaCastbarPreview" .. index
    local existing = _G[name]
    if existing then
        return existing
    end

    local general = GeneralDB()
    local width = 240
    local height = 18

    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        width, height = _G.MSUF_GetCastbarDesiredSize("arena" .. index, general, nil, width, height)
    else
        width = tonumber(general.arenaCastbarWidth) or width
        height = tonumber(general.arenaCastbarHeight) or height
    end

    local createPreviewFrame = _G.MSUF_CreateCastbarPreviewFrame
    if type(createPreviewFrame) ~= "function" then
        return nil
    end

    local preview = createPreviewFrame("arena", name, {
        parent = UIParent,
        strata = "DIALOG",
        width = width,
        height = height,
        label = "Greater Pyroblast",
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0,
        hideFillTexture = true,
    })

    if not preview then
        return nil
    end

    preview.unit = "arena"
    preview._msufIsArenaCastbar = true
    preview._msufIsPreview = true
    preview._msufArenaIndex = index

    if preview.statusBar then
        preview.statusBar:SetValue(0)
        preview.statusBar.MSUF_hideFillTexture = true

        local fillTexture = preview.statusBar.GetStatusBarTexture and preview.statusBar:GetStatusBarTexture()
        if fillTexture then
            fillTexture:SetAlpha(0)
        end
    end

    if index == 1 then
        ExportPublic("MSUF_ArenaCastbarPreview", preview)
    end

    return preview
end

local function ApplyArenaCastbarPreviewLayout(preview, index)
    if not (preview and preview.statusBar) then
        return
    end

    local general = GeneralDB()
    local width
    local height
    local preserveWidth

    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        width, height, preserveWidth = _G.MSUF_GetCastbarDesiredSize("arena" .. index, general, preview, 240, 18)
    else
        width = tonumber(general.arenaCastbarWidth) or 240
        height = tonumber(general.arenaCastbarHeight) or 18
    end

    if width and not preserveWidth then
        width = Snap(preview, width)
    end
    if height then
        height = Snap(preview, height)
    end

    if type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarSizeAndLayout(preview, general, width, height, preserveWidth)
    else
        preview:SetSize(width, height)
    end

    if type(_G.MSUF_ApplyCastbarFrameLayer) == "function" then
        _G.MSUF_ApplyCastbarFrameLayer(preview, general, "arena")
    end

    if type(_G.MSUF_RefreshCastbarFrame) == "function" then
        _G.MSUF_RefreshCastbarFrame(preview, "arena", general)
        if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
            _G.MSUF_ApplyCastbarSparkVisual(preview, general)
        end
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit("arena")
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals("arena")
    end

    if preview.castTargetText then
        local showTargetName = general.showArenaCastTargetName == true
        preview.castTargetText:SetText(showTargetName and "Arena Ally" or "")
        if type(_G.MSUF_ApplyCastTargetTextColor) == "function" then
            _G.MSUF_ApplyCastTargetTextColor(preview)
        end
        preview.castTargetText:SetShown(showTargetName)
    end

    if preview.statusBar then
        preview.statusBar:SetValue(0)
        if preview.MSUF_testMode then
            preview.statusBar.MSUF_hideFillTexture = nil
        else
            preview.statusBar.MSUF_hideFillTexture = true
        end

        local fillTexture = preview.statusBar.GetStatusBarTexture and preview.statusBar:GetStatusBarTexture()
        if fillTexture then
            fillTexture:SetAlpha(preview.MSUF_testMode and 1 or 0)
        end
    end
end

--- Positioning mirrors live arena castbar anchoring so edit mode and menu
--- previews show the same detached vs unit-frame-relative behavior.
local function PositionArenaCastbarPreview(preview, index)
    if not preview then
        return
    end

    local general = GeneralDB()
    local offsetX = Snap(preview, tonumber(general.arenaCastbarOffsetX) or 0)
    local offsetY = Snap(preview, tonumber(general.arenaCastbarOffsetY) or 0)

    preview:ClearAllPoints()

    if general.arenaCastbarDetached == true then
        local layoutX = 0
        local layoutY = -((index - 1) * 34)

        if type(_G.MSUF_GetArenaLayoutDelta) == "function" then
            layoutX, layoutY = _G.MSUF_GetArenaLayoutDelta(index, MSUF_DB.arena or {})
            layoutX = tonumber(layoutX) or 0
            layoutY = tonumber(layoutY) or layoutY
        end

        preview:SetPoint("CENTER", UIParent, "CENTER", offsetX + layoutX, offsetY + (tonumber(layoutY) or 0))
        return
    end

    local unitFrame = ArenaUnitFrame(index)
    if unitFrame then
        local unit = "arena" .. index
        local source = (type(_G.MSUF_GetCastbarUnitframeWidthSource) == "function"
            and _G.MSUF_GetCastbarUnitframeWidthSource(unit)) or unitFrame
        local autoX = 0
        if type(_G.MSUF_GetCastbarAutoAnchorOffsetX) == "function" then
            autoX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, unit, preview)
        end
        local bottomInset = 0
        if type(_G.MSUF_GetCastbarUnitframeBottomInset) == "function" then
            bottomInset = _G.MSUF_GetCastbarUnitframeBottomInset(unit, preview)
        end
        local gap = 3
        if type(_G.MSUF_GetPhysicalPixelSize) == "function" then
            gap = _G.MSUF_GetPhysicalPixelSize(preview, 3)
        else
            gap = Snap(preview, gap)
        end
        preview:SetPoint("TOPLEFT", source, "BOTTOMLEFT",
            offsetX + autoX, offsetY - bottomInset - gap)
    else
        preview:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -420 + offsetX, (-320 + offsetY) - ((index - 1) * 34))
    end
end

UpdateArenaCastbarPreview = function()
    if InCombat() then
        return
    end

    if not PreviewEnabled() then
        HideAllArenaCastbarPreviews()
        return
    end

    for index = 1, MAX_ARENA_FRAMES do
        local unitFrame = ArenaUnitFrame(index)
        local preview = CreateArenaCastbarPreview(index)

        if preview and unitFrame and (not unitFrame.IsShown or unitFrame:IsShown()) then
            local realCastbar = (_G.MSUF_ArenaCastbars and _G.MSUF_ArenaCastbars[index]) or _G["MSUF_ArenaCastbar" .. index]
            if type(_G.MSUF_HardSyncCastbarPreview) == "function" then
                _G.MSUF_HardSyncCastbarPreview(preview, realCastbar)
            end

            ApplyArenaCastbarPreviewLayout(preview, index)
            PositionArenaCastbarPreview(preview, index)
            preview:Show()
        elseif preview then
            preview:Hide()
        end
    end
end
ExportPublic("MSUF_UpdateArenaCastbarPreview", UpdateArenaCastbarPreview)

ExportPublic("MSUF_HideAllArenaCastbarPreviews", HideAllArenaCastbarPreviews)
ExportPublic("MSUF_CreateArenaCastbarPreview", CreateArenaCastbarPreview)
ExportPublic("MSUF_ApplyArenaCastbarPreviewLayout", ApplyArenaCastbarPreviewLayout)
ExportPublic("MSUF_PositionArenaCastbarPreview", PositionArenaCastbarPreview)

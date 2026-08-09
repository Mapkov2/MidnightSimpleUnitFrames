--- Castbars/MSUF_BossCastbars_Preview.lua
--- Edit/menu previews for boss castbars.
---
--- Preview frames are non-combat, non-event copies that mirror boss castbar
--- geometry and styling. They should never subscribe to UNIT_SPELLCAST events;
--- real boss castbars own live state.

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

local MAX_BOSS_FRAMES = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
if MAX_BOSS_FRAMES < 1 or MAX_BOSS_FRAMES > 12 then
    MAX_BOSS_FRAMES = 5
end

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
    -- The Menu2 castbar page's transient boss preview must survive texture and
    -- layout re-applies that funnel through UpdateBossCastbarPreview, even
    -- while the persistent preview option is off.
    if _G.MSUF2_CastbarPagePreviewUnit == "boss" then
        return not (MSUF_DB.boss and MSUF_DB.boss.enabled == false)
    end
    -- Edit-mode preview flags live in SavedVariables for legacy integrations.
    -- A logout can bypass the normal Edit Mode exit and leave that flag true,
    -- so the runtime session state must remain the authority for visibility.
    if _G.MSUF_UnitEditModeActive ~= true or not general.castbarPlayerPreviewEnabled then
        return false
    end

    if MSUF_DB.boss and MSUF_DB.boss.enabled == false then
        return false
    end

    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar
    return type(shouldUseMSUF) == "function"
        and shouldUseMSUF("boss", general) == true
        or general.enableBossCastbar ~= false
end

local UpdateBossCastbarPreview
local bossPreviewBatchDepth = 0
local bossPreviewBatchPending

local function BeginBossCastbarPreviewBatch()
    bossPreviewBatchDepth = bossPreviewBatchDepth + 1
end

local function EndBossCastbarPreviewBatch()
    if bossPreviewBatchDepth <= 0 then
        bossPreviewBatchDepth = 0
        return
    end
    bossPreviewBatchDepth = bossPreviewBatchDepth - 1
    if bossPreviewBatchDepth == 0 and bossPreviewBatchPending then
        bossPreviewBatchPending = nil
        if type(UpdateBossCastbarPreview) == "function" then
            UpdateBossCastbarPreview()
        end
    end
end

ExportPublic("MSUF_BeginBossCastbarPreviewBatch", BeginBossCastbarPreviewBatch)
ExportPublic("MSUF_EndBossCastbarPreviewBatch", EndBossCastbarPreviewBatch)

local function BossUnitFrame(index)
    local unit = "boss" .. index
    return CoreFrame(unit) or _G["MSUF_" .. unit]
end

local function Snap(frame, value)
    value = tonumber(value) or 0
    if type(_G.MSUF_Snap) == "function" then
        return _G.MSUF_Snap(frame, value)
    end
    return math.floor(value + 0.5)
end

local function HideAllBossCastbarPreviews()
    if _G.MSUF_BossCastbarPreview then
        _G.MSUF_BossCastbarPreview:Hide()
    end

    for index = 2, MAX_BOSS_FRAMES do
        local preview = _G["MSUF_BossCastbarPreview" .. index]
        if preview then
            preview:Hide()
        end
    end
end

--- Create one preview per visible boss unit slot. The preview is intentionally
--- inert: no cast progression, no event registration, just layout/style.
local function CreateBossCastbarPreview(index)
    local name = index == 1 and "MSUF_BossCastbarPreview" or ("MSUF_BossCastbarPreview" .. index)
    local existing = _G[name]
    if existing then
        return existing
    end

    local general = GeneralDB()
    local width = 240
    local height = 18

    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        width, height = _G.MSUF_GetCastbarDesiredSize("boss" .. index, general, nil, width, height)
    else
        width = tonumber(general.bossCastbarWidth) or width
        height = tonumber(general.bossCastbarHeight) or height
    end

    local createPreviewFrame = _G.MSUF_CreateCastbarPreviewFrame
    if type(createPreviewFrame) ~= "function" then
        return nil
    end

    local preview = createPreviewFrame("boss", name, {
        parent = UIParent,
        strata = "DIALOG",
        width = width,
        height = height,
        label = "Celestial Ruin",
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0,
        hideFillTexture = true,
    })

    if not preview then
        return nil
    end

    preview.unit = "boss"
    preview._msufIsBossCastbar = true
    preview._msufIsPreview = true
    preview._msufBossIndex = index

    if preview.statusBar then
        preview.statusBar:SetValue(0)
        preview.statusBar.MSUF_hideFillTexture = true

        local fillTexture = preview.statusBar.GetStatusBarTexture and preview.statusBar:GetStatusBarTexture()
        if fillTexture then
            fillTexture:SetAlpha(0)
        end
    end

    if index == 1 then
        ExportPublic("MSUF_BossCastbarPreview", preview)
    end

    return preview
end

local function ApplyBossCastbarPreviewLayout(preview, index)
    if not (preview and preview.statusBar) then
        return
    end

    local general = GeneralDB()
    local width
    local height
    local preserveWidth

    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        width, height, preserveWidth = _G.MSUF_GetCastbarDesiredSize("boss" .. index, general, preview, 240, 18)
    else
        width = tonumber(general.bossCastbarWidth) or 240
        height = tonumber(general.bossCastbarHeight) or 18
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
        _G.MSUF_ApplyCastbarFrameLayer(preview, general, "boss")
    end

    if type(_G.MSUF_RefreshCastbarFrame) == "function" then
        _G.MSUF_RefreshCastbarFrame(preview, "boss", general)
        if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
            _G.MSUF_ApplyCastbarSparkVisual(preview, general)
        end
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit("boss")
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals("boss")
    end

    if preview.castTargetText then
        local showTargetName = general.showBossCastTargetName == true
        preview.castTargetText:SetText(showTargetName and "Cleave Training Dummy" or "")
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

--- Positioning mirrors live boss castbar anchoring so edit mode and menu previews
--- show the same detached vs unit-frame-relative behavior.
local function PositionBossCastbarPreview(preview, index)
    if not preview then
        return
    end

    local general = GeneralDB()
    local offsetX = Snap(preview, tonumber(general.bossCastbarOffsetX) or 0)
    local offsetY = Snap(preview, tonumber(general.bossCastbarOffsetY) or 0)

    preview:ClearAllPoints()

    if general.bossCastbarDetached == true then
        local layoutX = 0
        local layoutY = -((index - 1) * 34)

        if type(_G.MSUF_GetBossLayoutDelta) == "function" then
            layoutX, layoutY = _G.MSUF_GetBossLayoutDelta(index, MSUF_DB.boss or {})
            layoutX = tonumber(layoutX) or 0
            layoutY = tonumber(layoutY) or layoutY
        end

        preview:SetPoint("CENTER", UIParent, "CENTER", offsetX + layoutX, offsetY + (tonumber(layoutY) or 0))
        return
    end

    local unitFrame = BossUnitFrame(index)
    if unitFrame then
        local unit = "boss" .. index
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
        preview:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -420 + offsetX, (-220 + offsetY) - ((index - 1) * 34))
    end
end

UpdateBossCastbarPreview = function()
    if bossPreviewBatchDepth > 0 then
        bossPreviewBatchPending = true
        return
    end

    if InCombat() then
        return
    end

    if not PreviewEnabled() then
        HideAllBossCastbarPreviews()
        return
    end

    for index = 1, MAX_BOSS_FRAMES do
        local unitFrame = BossUnitFrame(index)
        local preview = CreateBossCastbarPreview(index)

        if preview and unitFrame and (not unitFrame.IsShown or unitFrame:IsShown()) then
            local realCastbar = (_G.MSUF_BossCastbars and _G.MSUF_BossCastbars[index]) or _G["MSUF_BossCastbar" .. index]
            if type(_G.MSUF_HardSyncCastbarPreview) == "function" then
                _G.MSUF_HardSyncCastbarPreview(preview, realCastbar)
            end

            ApplyBossCastbarPreviewLayout(preview, index)
            PositionBossCastbarPreview(preview, index)
            preview:Show()
        elseif preview then
            preview:Hide()
        end
    end
end
ExportPublic("MSUF_UpdateBossCastbarPreview", UpdateBossCastbarPreview)

ExportPublic("MSUF_HideAllBossCastbarPreviews", HideAllBossCastbarPreviews)
ExportPublic("MSUF_CreateBossCastbarPreview", CreateBossCastbarPreview)
ExportPublic("MSUF_ApplyBossCastbarPreviewLayout", ApplyBossCastbarPreviewLayout)
ExportPublic("MSUF_PositionBossCastbarPreview", PositionBossCastbarPreview)

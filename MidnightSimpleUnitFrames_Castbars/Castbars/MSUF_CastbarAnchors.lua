-- Castbars/MSUF_CastbarAnchors.lua
-- Pure layout logic (ClearAllPoints, SetPoint, SetSize) — no combat-path code.

local floor = math.floor
local MSUF_SetPointIfChanged = _G.MSUF_SetPointIfChanged or function(frame, p, rel, rp, x, y)
    if not frame then return end
    frame:ClearAllPoints()
    if x then x = floor(x + 0.5) end
    if y then y = floor(y + 0.5) end
    frame:SetPoint(p, rel, rp, x, y)
end
local UnitFrames = _G.MSUF_UnitFrames

function MSUF_AttachBlizzardTargetFrame()
    if not TargetFrame then
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    if not msufTarget then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local g = MSUF_DB and MSUF_DB.general
    local offsetX = floor((g and g.castbarTargetOffsetX or 65) + 0.5)
    local offsetY = floor((g and g.castbarTargetOffsetY or -15) + 0.5)

    -- Dirty-only: don't ClearAllPoints/SetPoint unless it actually changed.
    MSUF_SetPointIfChanged(TargetFrame, "CENTER", msufTarget, "CENTER", offsetX, offsetY)
end

function MSUF_ReanchorTargetCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_TargetCastbar or _G["TargetCastBar"]
    if not frame then return end

    if g.enableTargetCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText and MSUF_IsCastTimeEnabled(frame) then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_TargetCastbarPreview then
            MSUF_TargetCastbarPreview:Hide()
        end
        return
    end

    local msufTarget = UnitFrames and UnitFrames["target"]
    local offsetX = floor((g.castbarTargetOffsetX or 65) + 0.5)
    local offsetY = floor((g.castbarTargetOffsetY or -15) + 0.5)

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarTargetDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufTarget then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufTarget, "TOPLEFT", offsetX, offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, "target")
    local width, desiredHeight = MSUF_GetCastbarDesiredSize("target", g, frame, frame.GetWidth and frame:GetWidth() or 240, frame.GetHeight and frame:GetHeight() or 18)
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or desiredHeight or 18
        MSUF_SetWidthIfChanged(frame, width)

        -- Keep the TARGET preview size 1:1 with the real bar.
        -- In "auto width" mode (no explicit DB width while attached), the real bar tracks the
        -- unitframe width. The preview must follow the same computed width/height or it will
        -- drift after profile resets/imports/reloads.
        if MSUF_TargetCastbarPreview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
            local ph = desiredHeight or tonumber(g.castbarTargetBarHeight) or tonumber(g.castbarGlobalHeight) or height
            _G.MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_TargetCastbarPreview, g, width, ph)
        end

        if frame.statusBar then
            MSUF_SetWidthIfChanged(frame.statusBar, width - height - 1)
        end
    end

    if frame.timeText then
        local showTime = (g.showTargetCastTime ~= false)
        frame.timeText:Show()
        MSUF_SetAlphaIfChanged(frame.timeText, showTime and 1 or 0)
        if not showTime then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
    end

    if frame.timeText and frame.statusBar then
        local x = g.castbarTargetTimeOffsetX
        if x == nil then x = g.castbarPlayerTimeOffsetX or -2 end
        local y = g.castbarTargetTimeOffsetY
        if y == nil then y = g.castbarPlayerTimeOffsetY or 0 end

        MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", x, y)
        MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, frame, "target")
    end

    if MSUF_TargetCastbarPreview and MSUF_PositionTargetCastbarPreview then
        MSUF_PositionTargetCastbarPreview()
    end
end
function MSUF_ReanchorFocusCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local frame = MSUF_FocusCastbar or _G["FocusCastBar"]
    if not frame then return end

    if g.enableFocusCastbar == false then
        frame:SetScript("OnUpdate", nil)
        if frame.timeText and MSUF_IsCastTimeEnabled(frame) then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame.latencyBar then
            frame.latencyBar:Hide()
        end
        frame:Hide()
        if MSUF_FocusCastbarPreview then
            MSUF_FocusCastbarPreview:Hide()
        end
        return
    end

    local msufFocus = UnitFrames and UnitFrames["focus"]

    local offsetX = floor((g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)) + 0.5)
    local offsetY = floor((g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)) + 0.5)

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarFocusDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufFocus then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufFocus, "TOPLEFT", offsetX, offsetY)
    end

    MSUF_UpdateCastbarWidthSourceSync(g, "focus")
    local width, desiredHeight = MSUF_GetCastbarDesiredSize("focus", g, frame, frame.GetWidth and frame:GetWidth() or 240, frame.GetHeight and frame:GetHeight() or 18)
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or desiredHeight or 18
        MSUF_SetWidthIfChanged(frame, width)

        -- Keep the FOCUS preview size 1:1 with the real bar (see Target notes above).
        if MSUF_FocusCastbarPreview and type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
            local ph = desiredHeight or tonumber(g.castbarFocusBarHeight) or tonumber(g.castbarGlobalHeight) or height
            _G.MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_FocusCastbarPreview, g, width, ph)
        end

        if frame.statusBar then
            MSUF_SetWidthIfChanged(frame.statusBar, width - height - 1)
        end
    end

    if frame.timeText and frame.statusBar then
        local enabledTime = MSUF_IsCastTimeEnabled(frame)
        frame.timeText:Show()
        MSUF_SetAlphaIfChanged(frame.timeText, enabledTime and 1 or 0)
        if not enabledTime then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end

        local tx = g.castbarFocusTimeOffsetX or (g.castbarPlayerTimeOffsetX or -2)
        local ty = g.castbarFocusTimeOffsetY or (g.castbarPlayerTimeOffsetY or 0)
        MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", tx, ty)
        MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
    end

    if MSUF_FocusCastbarPreview and MSUF_FocusCastbarPreview.timeText and MSUF_FocusCastbarPreview.statusBar then
        local enabledTime = MSUF_IsCastTimeEnabled(frame)
        MSUF_FocusCastbarPreview.timeText:Show()
        MSUF_SetAlphaIfChanged(MSUF_FocusCastbarPreview.timeText, enabledTime and 1 or 0)
        if not enabledTime then
            MSUF_FocusCastbarPreview.timeText:SetText("")
        end

        local tx = g.castbarFocusTimeOffsetX or (g.castbarPlayerTimeOffsetX or -2)
        local ty = g.castbarFocusTimeOffsetY or (g.castbarPlayerTimeOffsetY or 0)
        MSUF_SetPointIfChanged(MSUF_FocusCastbarPreview.timeText, "RIGHT", MSUF_FocusCastbarPreview.statusBar, "RIGHT", tx, ty)
        MSUF_SetJustifyHIfChanged(MSUF_FocusCastbarPreview.timeText, "RIGHT")
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, frame, "focus")
    end

    if MSUF_FocusCastbarPreview and MSUF_PositionFocusCastbarPreview then
        MSUF_PositionFocusCastbarPreview()
    end
end

function _G.MSUF_ApplyPlayerCastbarIconLayout(bar, g, topInset, bottomInset)
    if not bar or not g then return end
    local statusBar = bar.statusBar
    if not statusBar then return end

    topInset = tonumber(topInset) or 0
    bottomInset = tonumber(bottomInset) or 0

    local height = bar.GetHeight and (bar:GetHeight() or 18) or 18

    -- Global + per-player override (BUT: player icon is Edit-Mode driven; force visible if icon exists)
    local showIconLocal = (g.castbarShowIcon ~= false)
    if g.castbarPlayerShowIcon ~= nil then
        showIconLocal = (g.castbarPlayerShowIcon ~= false)
    end

    -- Player castbar icon toggle should work during normal gameplay.
    -- While in MSUF/Blizzard Edit Mode, keep the icon visible so it can still be positioned.
    local isPlayerBar = (bar == _G.MSUF_PlayerCastbar or bar == _G.MSUF_PlayerCastbarPreview or bar == _G.PlayerCastingBarFrame or bar == _G.CastingBarFrame)
    if isPlayerBar then
        local inMSUFEdit = (_G.MSUF_UnitEditModeActive == true)
        local inBlizzEdit = (EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown())
        if inMSUFEdit or inBlizzEdit then
            showIconLocal = true
        end
    end

    local iconOXLocal = tonumber(g.castbarPlayerIconOffsetX)
    if iconOXLocal == nil then iconOXLocal = tonumber(g.castbarIconOffsetX) or 0 end

    local iconOYLocal = tonumber(g.castbarPlayerIconOffsetY)
    if iconOYLocal == nil then iconOYLocal = tonumber(g.castbarIconOffsetY) or 0 end

    local iconSizeLocal = tonumber(g.castbarPlayerIconSize)
    if not iconSizeLocal or iconSizeLocal <= 0 then
        iconSizeLocal = tonumber(g.castbarIconSize) or 0
        if not iconSizeLocal or iconSizeLocal <= 0 then
            iconSizeLocal = height
        end
    end
    if iconSizeLocal < 6 then iconSizeLocal = 6 end
    if iconSizeLocal > 128 then iconSizeLocal = 128 end

    -- IMPORTANT: detach only on X
    local iconDetached = (iconOXLocal ~= 0)

    local icon = bar.Icon or bar.icon or (bar.IconFrame and bar.IconFrame.Icon)

    local function EnsureIconHost()
        local host = bar._msufPCIconHost
        if not host then
            host = CreateFrame("Frame", nil, bar)
            host:EnableMouse(false)
            bar._msufPCIconHost = host
        end
        host:SetSize(iconSizeLocal, iconSizeLocal)
        host:ClearAllPoints()
        host:SetPoint("LEFT", bar, "LEFT", iconOXLocal, iconOYLocal)
        if statusBar.GetFrameLevel and host.SetFrameLevel then
            host:SetFrameLevel((statusBar:GetFrameLevel() or 0) + 3)
        end
        host:Show()
        return host
    end

    if icon then
        if showIconLocal then
            icon:Show()
            local host = EnsureIconHost()

            local k = "H:" .. (iconDetached and "D" or "A") .. ":" .. tostring(iconSizeLocal) .. ":" .. tostring(iconOXLocal) .. ":" .. tostring(iconOYLocal)
            if icon._msufPCIconKey ~= k or (icon.GetParent and icon:GetParent() ~= host) then
                icon:SetParent(host)
                icon:ClearAllPoints()
                icon:SetAllPoints(host)

                -- Render: above bar texture, below castbar texts.
                if icon.SetDrawLayer then
                    icon:SetDrawLayer("OVERLAY", 7)
                end

                icon._msufPCIconKey = k
            end
        else
            icon:Hide()
            if bar._msufPCIconHost then bar._msufPCIconHost:Hide() end
        end
    elseif bar._msufPCIconHost then
        bar._msufPCIconHost:Hide()
    end

    -- Layout key (only re-anchor when state changes)
    local layoutKey = (showIconLocal and icon and (not iconDetached)) and ("G:" .. tostring(iconSizeLocal)) or "F"
    if statusBar._msufPCLayoutKey ~= layoutKey then
        statusBar:ClearAllPoints()

        if showIconLocal and icon and not iconDetached then
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSizeLocal + 1, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        else
            statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, topInset)
            statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bottomInset)
        end

        statusBar._msufPCLayoutKey = layoutKey
    end

    -- Explicit StatusBar sizing: point-anchoring alone can leave the bar in a
    -- "border-only" state until the next frame. Force immediate size so the
    -- fill/background spans the full new width (fixes black bar on CDM sync).
    local bw = (bar.GetWidth and bar:GetWidth()) or 0
    if bw <= 0 then bw = 250 end
    local desiredW
    if showIconLocal and icon and (not iconDetached) then
        desiredW = bw - (iconSizeLocal + 1)
    else
        desiredW = bw
    end
    if desiredW < 1 then desiredW = 1 end

    local desiredH = (height or 18) - 2
    if desiredH < 1 then desiredH = 1 end

    if statusBar._msufPCSbW ~= desiredW then
        statusBar:SetWidth(desiredW)
        statusBar._msufPCSbW = desiredW
    end
    if statusBar._msufPCSbH ~= desiredH then
        statusBar:SetHeight(desiredH)
        statusBar._msufPCSbH = desiredH
    end

    local bg = bar.backgroundBar
    if bg and bg.SetAllPoints then
        bg:ClearAllPoints()
        bg:SetAllPoints(statusBar)
    end
end

-- ============================================================
-- Unit castbar sizing.
-- Manual mode follows the per-unit width key. Width-source modes keep the
-- saved manual value intact and only override the effective runtime width.
-- ============================================================
local CASTBAR_WIDTH_RETRY_DELAYS = { 0.05, 0.15, 0.35, 0.75, 1.5, 3.0, 5.0, 7.0 }
local CASTBAR_WIDTH_SOURCE_HOOKED = setmetatable({}, { __mode = "k" })
local castbarWidthSourceQueued = false
local castbarWidthSourceRetryActive = false
local castbarWidthSourceRetryIndex = 0
local CASTBAR_WIDTH_UNITS = { "player", "target", "focus", "boss" }

local CASTBAR_WIDTH_SOURCES = {
    unitframe = true,
    essential = true,
    utility = true,
}

local function MSUF_NormalizeCastbarUnit(unit)
    if unit == "boss" or unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5" then
        return "boss"
    end
    return unit
end

local function MSUF_NormalizeCastbarWidthSource(matchSrc)
    if CASTBAR_WIDTH_SOURCES[matchSrc] then
        return matchSrc
    end
    return nil
end

local function MSUF_NormalizePlayerCastbarWidthSource(matchSrc)
    return MSUF_NormalizeCastbarWidthSource(matchSrc)
end

local function MSUF_IsCastbarWidthSource(matchSrc)
    return MSUF_NormalizeCastbarWidthSource(matchSrc) ~= nil
end

local function MSUF_IsPlayerCastbarWidthSource(matchSrc)
    return MSUF_IsCastbarWidthSource(matchSrc)
end

local function MSUF_GetCastbarWidthSourceKey(unit)
    unit = MSUF_NormalizeCastbarUnit(unit)
    if unit == "player" then return "castbarPlayerMatchWidth" end
    if unit == "target" then return "castbarTargetMatchWidth" end
    if unit == "focus" then return "castbarFocusMatchWidth" end
    if unit == "boss" then return "bossCastbarMatchWidth" end
end

local function MSUF_GetCastbarWidthKey(unit)
    unit = MSUF_NormalizeCastbarUnit(unit)
    if unit == "player" then return "castbarPlayerBarWidth" end
    if unit == "target" then return "castbarTargetBarWidth" end
    if unit == "focus" then return "castbarFocusBarWidth" end
    if unit == "boss" then return "bossCastbarWidth" end
end

local function MSUF_GetCastbarHeightKey(unit)
    unit = MSUF_NormalizeCastbarUnit(unit)
    if unit == "player" then return "castbarPlayerBarHeight" end
    if unit == "target" then return "castbarTargetBarHeight" end
    if unit == "focus" then return "castbarFocusBarHeight" end
    if unit == "boss" then return "bossCastbarHeight" end
end

local function MSUF_GetCastbarDetachedKey(unit)
    unit = MSUF_NormalizeCastbarUnit(unit)
    if unit == "player" then return "castbarPlayerDetached" end
    if unit == "target" then return "castbarTargetDetached" end
    if unit == "focus" then return "castbarFocusDetached" end
    if unit == "boss" then return "bossCastbarDetached" end
end

local function MSUF_GetCastbarEnableKey(unit)
    unit = MSUF_NormalizeCastbarUnit(unit)
    if unit == "player" then return "enablePlayerCastbar" end
    if unit == "target" then return "enableTargetCastbar" end
    if unit == "focus" then return "enableFocusCastbar" end
    if unit == "boss" then return "enableBossCastbar" end
end

local function MSUF_GetCastbarConfiguredWidthSource(g, unit)
    local key = MSUF_GetCastbarWidthSourceKey(unit)
    return MSUF_NormalizeCastbarWidthSource(key and g and g[key])
end

local function MSUF_GetCastbarWidthSourceNames(matchSrc)
    if matchSrc == "utility" then
        return "UtilityCooldownViewer_AnchorContainer", "UtilityCooldownViewer"
    end
    if matchSrc == "essential" then
        return "EssentialCooldownViewer_CDM_Container", "EssentialCooldownViewer"
    end
end

local function MSUF_GetCastbarUnitframe(unit)
    local frames = _G.MSUF_UnitFrames or UnitFrames
    local normalized = MSUF_NormalizeCastbarUnit(unit)
    if normalized == "boss" then
        local index = tonumber(tostring(unit or ""):match("^boss(%d+)$")) or 1
        return (frames and frames["boss" .. index]) or _G["MSUF_boss" .. index] or (frames and frames["boss1"]) or _G.MSUF_boss1
    end
    return (frames and frames[normalized]) or _G["MSUF_" .. tostring(normalized or "")]
end

local function MSUF_GetPlayerCastbarUnitframe()
    return MSUF_GetCastbarUnitframe("player")
end

local function MSUF_GetCastbarUnitframeWidthSource(unit)
    local frame = MSUF_GetCastbarUnitframe(unit)
    if not frame then return nil end

    -- Match the visible MSUF unitframe bar, not the outer container.
    -- Unitframes can have small content insets; using the container makes the
    -- castbar read a few pixels too wide in "MSUF Unit Frame" mode.
    local hp = frame.hpBar or frame.healthBar or frame.health
    if hp and hp.GetWidth then
        local w = hp:GetWidth()
        if w and w > 0 then return hp end
    end

    return frame
end

local function MSUF_GetPlayerCastbarUnitframeWidthSource()
    return MSUF_GetCastbarUnitframeWidthSource("player")
end

local MSUF_GetScaledWidthForPlayerCastbar

local function MSUF_GetCastbarFallbackUnitframeWidth(unit, targetFrame)
    local sourceFrame = MSUF_GetCastbarUnitframe(unit)
    return MSUF_GetScaledWidthForPlayerCastbar(sourceFrame, targetFrame)
end

local function MSUF_GetEffectiveCooldownViewer(viewerKey)
    if not viewerKey then return nil end
    local getEffective = _G.MSUF_GetEffectiveCooldownFrame
    if type(getEffective) == "function" then
        local frame = getEffective(viewerKey)
        if frame then return frame end
    end
    return _G[viewerKey]
end

MSUF_GetScaledWidthForPlayerCastbar = function(sourceFrame, targetFrame)
    if not sourceFrame then return nil end

    local getScaled = _G.MSUF_CDM_GetScaledWidth
    if type(getScaled) == "function" then
        return getScaled(sourceFrame, targetFrame)
    end

    if not sourceFrame.GetWidth then return nil end
    local w = sourceFrame:GetWidth()
    if not w or w <= 0 then return nil end

    local sourceScale = (sourceFrame.GetEffectiveScale and sourceFrame:GetEffectiveScale()) or 1
    local targetScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
    if not sourceScale or sourceScale <= 0 then sourceScale = 1 end
    if not targetScale or targetScale <= 0 then targetScale = 1 end

    if sourceScale == targetScale then
        return floor(w + 0.5)
    end
    return floor(w * sourceScale / targetScale + 0.5)
end

local function MSUF_GetCastbarWidthFromSource(unit, matchSrc, targetFrame)
    matchSrc = MSUF_NormalizeCastbarWidthSource(matchSrc)
    if matchSrc == "unitframe" then
        return MSUF_GetScaledWidthForPlayerCastbar(MSUF_GetCastbarUnitframeWidthSource(unit), targetFrame)
    end

    local containerKey, viewerKey = MSUF_GetCastbarWidthSourceNames(matchSrc)
    local sourceFrame = containerKey and _G[containerKey] or nil
    local w = MSUF_GetScaledWidthForPlayerCastbar(sourceFrame, targetFrame)

    if not w or w <= 0 then
        sourceFrame = MSUF_GetEffectiveCooldownViewer(viewerKey)
        w = MSUF_GetScaledWidthForPlayerCastbar(sourceFrame, targetFrame)
    end

    if (not w or w <= 0) and viewerKey then
        local rawViewer = _G[viewerKey]
        if rawViewer and rawViewer ~= sourceFrame then
            w = MSUF_GetScaledWidthForPlayerCastbar(rawViewer, targetFrame)
        end
    end

    return w
end

local function MSUF_GetPlayerCastbarWidthFromSource(matchSrc, targetFrame)
    return MSUF_GetCastbarWidthFromSource("player", matchSrc, targetFrame)
end

local MSUF_QueueCastbarWidthSourceSync

local function MSUF_CastbarWidthSourceChanged()
    if MSUF_QueueCastbarWidthSourceSync then
        MSUF_QueueCastbarWidthSourceSync()
    end
end

local function MSUF_UnitHasActiveCastbarWidthSource(g, unit)
    return MSUF_GetCastbarConfiguredWidthSource(g, unit) ~= nil
end

local function MSUF_ReanchorCastbarWidthSourceUnit(unit, g)
    unit = MSUF_NormalizeCastbarUnit(unit)
    local enableKey = MSUF_GetCastbarEnableKey(unit)
    if enableKey and g and g[enableKey] == false then return end
    if not MSUF_UnitHasActiveCastbarWidthSource(g, unit) then return end

    if unit == "player" and type(MSUF_ReanchorPlayerCastBar) == "function" then
        MSUF_ReanchorPlayerCastBar()
    elseif unit == "target" and type(MSUF_ReanchorTargetCastBar) == "function" then
        MSUF_ReanchorTargetCastBar()
    elseif unit == "focus" and type(MSUF_ReanchorFocusCastBar) == "function" then
        MSUF_ReanchorFocusCastBar()
    elseif unit == "boss" and type(MSUF_ReanchorBossCastBar) == "function" then
        MSUF_ReanchorBossCastBar()
    end
end

local function MSUF_FlushCastbarWidthSourceSync()
    castbarWidthSourceQueued = false
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    for _, unit in ipairs(CASTBAR_WIDTH_UNITS) do
        MSUF_ReanchorCastbarWidthSourceUnit(unit, g)
    end
end

local function MSUF_HookCastbarWidthSourceFrame(frame)
    if not frame or not frame.HookScript or CASTBAR_WIDTH_SOURCE_HOOKED[frame] then
        return false
    end

    CASTBAR_WIDTH_SOURCE_HOOKED[frame] = true
    frame:HookScript("OnSizeChanged", MSUF_CastbarWidthSourceChanged)
    frame:HookScript("OnShow", MSUF_CastbarWidthSourceChanged)
    frame:HookScript("OnHide", MSUF_CastbarWidthSourceChanged)
    return true
end

local function MSUF_HookCastbarUnitframeWidthSource(unit)
    local found = false
    local normalized = MSUF_NormalizeCastbarUnit(unit)
    local count = normalized == "boss" and 5 or 1
    for i = 1, count do
        local sourceUnit = normalized == "boss" and ("boss" .. i) or normalized
        local frame = MSUF_GetCastbarUnitframe(sourceUnit)
        local widthSource = MSUF_GetCastbarUnitframeWidthSource(sourceUnit)
        if frame then
            found = true
            MSUF_HookCastbarWidthSourceFrame(frame)
        end
        if widthSource and widthSource ~= frame then
            found = true
            MSUF_HookCastbarWidthSourceFrame(widthSource)
        end
    end
    return found
end

local function MSUF_EnsureCastbarWidthSourceHooks(g, unit)
    local matchSrc = MSUF_GetCastbarConfiguredWidthSource(g, unit)
    if not matchSrc then return false end

    if matchSrc == "unitframe" then
        return MSUF_HookCastbarUnitframeWidthSource(unit)
    end

    local found = false
    local containerKey, viewerKey = MSUF_GetCastbarWidthSourceNames(matchSrc)

    local container = containerKey and _G[containerKey] or nil
    if container then
        found = true
        MSUF_HookCastbarWidthSourceFrame(container)
    end

    local viewer = MSUF_GetEffectiveCooldownViewer(viewerKey)
    if viewer then
        found = true
        MSUF_HookCastbarWidthSourceFrame(viewer)
    end

    local rawViewer = viewerKey and _G[viewerKey] or nil
    if rawViewer and rawViewer ~= viewer then
        found = true
        MSUF_HookCastbarWidthSourceFrame(rawViewer)
    end

    return found
end

local function MSUF_CastbarWidthSourceRetryStep()
    castbarWidthSourceRetryIndex = castbarWidthSourceRetryIndex + 1

    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local anyMissing = false
    local anyActive = false

    for _, unit in ipairs(CASTBAR_WIDTH_UNITS) do
        if MSUF_UnitHasActiveCastbarWidthSource(g, unit) then
            anyActive = true
            if not MSUF_EnsureCastbarWidthSourceHooks(g, unit) then
                anyMissing = true
            end
        end
    end

    if not anyActive then
        castbarWidthSourceRetryActive = false
        return
    end

    if not anyMissing then
        castbarWidthSourceRetryActive = false
        MSUF_CastbarWidthSourceChanged()
        return
    end

    local delay = CASTBAR_WIDTH_RETRY_DELAYS[castbarWidthSourceRetryIndex]
    if delay and C_Timer and C_Timer.After then
        C_Timer.After(delay, MSUF_CastbarWidthSourceRetryStep)
    else
        castbarWidthSourceRetryActive = false
    end
end

local function MSUF_StartCastbarWidthSourceRetry()
    if castbarWidthSourceRetryActive or not (C_Timer and C_Timer.After) then return end
    castbarWidthSourceRetryActive = true
    castbarWidthSourceRetryIndex = 0
    C_Timer.After(0, MSUF_CastbarWidthSourceRetryStep)
end

MSUF_QueueCastbarWidthSourceSync = function()
    if castbarWidthSourceQueued then return end
    castbarWidthSourceQueued = true

    local runNext = _G.MSUF_Castbars_RunNextFrame
    if type(runNext) == "function" then
        runNext(MSUF_FlushCastbarWidthSourceSync)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_FlushCastbarWidthSourceSync)
    else
        MSUF_FlushCastbarWidthSourceSync()
    end
end

local function MSUF_UpdateCastbarWidthSourceSync(g, unit)
    if unit then
        if not MSUF_UnitHasActiveCastbarWidthSource(g, unit) then return end
        if not MSUF_EnsureCastbarWidthSourceHooks(g, unit) then
            MSUF_StartCastbarWidthSourceRetry()
        end
        return
    end

    local anyMissing = false
    for _, unitKey in ipairs(CASTBAR_WIDTH_UNITS) do
        if MSUF_UnitHasActiveCastbarWidthSource(g, unitKey) and not MSUF_EnsureCastbarWidthSourceHooks(g, unitKey) then
            anyMissing = true
        end
    end
    if anyMissing then
        MSUF_StartCastbarWidthSourceRetry()
    end
end

local function MSUF_UpdatePlayerCastbarWidthSourceSync(g)
    MSUF_UpdateCastbarWidthSourceSync(g, "player")
end

do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function()
        EnsureDB()
        local g = MSUF_DB and MSUF_DB.general or {}
        MSUF_UpdateCastbarWidthSourceSync(g)
        MSUF_CastbarWidthSourceChanged()
    end)
end

local function MSUF_GetCastbarDesiredSize(unit, g, bar, fallbackW, fallbackH)
    local widthKey = MSUF_GetCastbarWidthKey(unit)
    local heightKey = MSUF_GetCastbarHeightKey(unit)
    local w = widthKey and g and tonumber(g[widthKey]) or nil
    local h = heightKey and g and tonumber(g[heightKey]) or nil

    if g then
        local matchSrc = MSUF_GetCastbarConfiguredWidthSource(g, unit)
        if matchSrc then
            local ww = MSUF_GetCastbarWidthFromSource(unit, matchSrc, bar)
            if ww and ww > 0 then
                w = ww
            end
        end
    end

    if not w or w <= 0 then
        local detachedKey = MSUF_GetCastbarDetachedKey(unit)
        if MSUF_NormalizeCastbarUnit(unit) ~= "player" and not (g and detachedKey and g[detachedKey] == true) then
            local ww = MSUF_GetCastbarFallbackUnitframeWidth(unit, bar)
            if ww and ww > 0 then
                w = ww
            end
        end
    end

    if not w or w <= 0 then
        w = g and tonumber(g.castbarGlobalWidth) or nil
    end
    if not h or h <= 0 then
        h = g and tonumber(g.castbarGlobalHeight) or nil
    end

    if not w or w <= 0 then w = fallbackW or 250 end
    if not h or h <= 0 then h = fallbackH or 18 end

    return w, h
end

local function MSUF_GetPlayerCastbarDesiredSize(g, bar, fallbackW, fallbackH)
    return MSUF_GetCastbarDesiredSize("player", g, bar, fallbackW, fallbackH)
end

local function MSUF_ApplyPlayerCastbarSizeAndLayout(bar, g, w, h)
    if not bar then return end

    local snap = _G.MSUF_Snap
    if type(snap) == "function" then
        if w ~= nil then w = snap(bar, w) end
        if h ~= nil then h = snap(bar, h) end
    end

    -- Size
    if MSUF_SetWidthIfChanged then
        MSUF_SetWidthIfChanged(bar, w)
    else
        bar:SetWidth(w)
    end
    if MSUF_SetHeightIfChanged then
        MSUF_SetHeightIfChanged(bar, h)
    else
        bar:SetHeight(h)
    end

    -- Icon/statusbar layout (player uses a special layout helper)
    if bar.statusBar and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarIconLayout(bar, g, -1, 1)
    end

    -- Empower stage tick heights must follow bar height
    if bar.empowerStageTicks then
        local bh = bar:GetHeight() or h
        for _, tick in pairs(bar.empowerStageTicks) do
            if tick and tick.SetHeight then
                tick:SetHeight(bh)
            end
        end
    end

    -- Spark (leading-edge highlight) — lazy-create if absent
    if bar.statusBar then
        local showSpark = g and g.castbarShowSpark == true
        local sparkTex = bar.spark
        if showSpark and not sparkTex then
            sparkTex = bar.statusBar:CreateTexture(nil, "OVERLAY", nil, 6)
            sparkTex:SetTexture(4417031)
            sparkTex:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
            sparkTex:SetDesaturated(true)
            sparkTex:SetVertexColor(1, 1, 1, 1)
            sparkTex:SetBlendMode("ADD")
            bar.spark = sparkTex
        end
        if sparkTex then
            sparkTex:SetShown(showSpark)
            if showSpark then
                local barH = bar:GetHeight() or h or 18
                local overflow = (g and g.castbarSparkOverflow ~= false)
                local sparkH = overflow and math.max(4, barH * 2.1) or barH
                sparkTex:SetSize(16, sparkH)
                local fillTex = bar.statusBar:GetStatusBarTexture()
                if fillTex then
                    sparkTex:ClearAllPoints()
                    sparkTex:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
                end
            end
        end
    end
end

function MSUF_ReanchorPlayerCastBar()
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}

    -- Always hide Blizzard player castbar; we no longer use it as a fallback.
    MSUF_HideBlizzardPlayerCastbar()

    if g.enablePlayerCastbar == false then
        if MSUF_PlayerCastbar then
            MSUF_PlayerCastbar:SetScript("OnUpdate", nil)
            MSUF_PlayerCastbar.interruptFeedbackEndTime = nil
            if MSUF_PlayerCastbar.timeText then
                MSUF_PlayerCastbar.timeText:SetText("")
            end
            if MSUF_PlayerCastbar.latencyBar then
                MSUF_PlayerCastbar.latencyBar:Hide()
            end
            MSUF_PlayerCastbar:Hide()
        end
        if MSUF_PlayerCastbarPreview then
            MSUF_PlayerCastbarPreview:Hide()
        end
        return
    end

    MSUF_InitSafePlayerCastbar()

    local msufPlayer = UnitFrames and UnitFrames["player"]
    if not MSUF_PlayerCastbar then
        return
    end
    if (not g.castbarPlayerDetached) and (not msufPlayer) then
        return
    end

    local offsetX = floor((g.castbarPlayerOffsetX or 0) + 0.5)
    local offsetY = floor((g.castbarPlayerOffsetY or 5) + 0.5)

    -- Dirty-only anchor
    if MSUF_SetPointIfChanged then
        if g.castbarPlayerDetached then
        MSUF_SetPointIfChanged(MSUF_PlayerCastbar, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        MSUF_SetPointIfChanged(MSUF_PlayerCastbar, "BOTTOM", msufPlayer, "TOP", offsetX, offsetY)
    end
    else
        MSUF_PlayerCastbar:ClearAllPoints()
        if g.castbarPlayerDetached then
            MSUF_PlayerCastbar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        else
            MSUF_PlayerCastbar:SetPoint("BOTTOM", msufPlayer, "TOP", offsetX, offsetY)
        end
    end

    MSUF_UpdatePlayerCastbarWidthSourceSync(g)

    local w, h = MSUF_GetPlayerCastbarDesiredSize(g, MSUF_PlayerCastbar, 250, 18)
    MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_PlayerCastbar, g, w, h)

    -- Cast-time text offsets + visibility
    if MSUF_PlayerCastbar.timeText and MSUF_PlayerCastbar.statusBar then
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0

        if MSUF_SetPointIfChanged then
            MSUF_SetPointIfChanged(MSUF_PlayerCastbar.timeText, "RIGHT", MSUF_PlayerCastbar.statusBar, "RIGHT", timeX, timeY)
        else
            MSUF_PlayerCastbar.timeText:ClearAllPoints()
            MSUF_PlayerCastbar.timeText:SetPoint("RIGHT", MSUF_PlayerCastbar.statusBar, "RIGHT", timeX, timeY)
        end

        if MSUF_SetJustifyHIfChanged then
            MSUF_SetJustifyHIfChanged(MSUF_PlayerCastbar.timeText, "RIGHT")
        else
            MSUF_PlayerCastbar.timeText:SetJustifyH("RIGHT")
        end

        local showTime = (g.showPlayerCastTime ~= false)
        MSUF_PlayerCastbar.timeText:Show()
        if MSUF_SetAlphaIfChanged then
            MSUF_SetAlphaIfChanged(MSUF_PlayerCastbar.timeText, showTime and 1 or 0)
        else
            MSUF_PlayerCastbar.timeText:SetAlpha(showTime and 1 or 0)
        end
        if not showTime then
            MSUF_PlayerCastbar.timeText:SetText("")
        end
    end

    if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
        pcall(_G.MSUF_ApplyCastbarTimeTextLayout, MSUF_PlayerCastbar, "player")
    end

    -- Keep the PLAYER preview size 1:1 with the real bar (show/hide handled elsewhere)
    if MSUF_PlayerCastbarPreview then
        MSUF_ApplyPlayerCastbarSizeAndLayout(MSUF_PlayerCastbarPreview, g, w, h)
    end

    if MSUF_PlayerCastbarPreview and MSUF_PositionPlayerCastbarPreview then
        MSUF_PositionPlayerCastbarPreview()
    end
end

MSUF_PlayerCastbarManageHooked = true -- Blizzard fallback removed; nothing to manage here.

function MSUF_ReanchorBossCastBar()
    if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
        _G.MSUF_ApplyBossCastbarPositionSetting()
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    if type(MSUF_SyncBossCastbarSliders) == "function" then
        MSUF_SyncBossCastbarSliders()
    end
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup("boss")
    end
end

---------------------------------------------------------------------------
-- _G exports
---------------------------------------------------------------------------
_G.MSUF_AttachBlizzardTargetFrame       = MSUF_AttachBlizzardTargetFrame
_G.MSUF_ReanchorTargetCastBar           = MSUF_ReanchorTargetCastBar
_G.MSUF_ReanchorFocusCastBar            = MSUF_ReanchorFocusCastBar
-- MSUF_ApplyPlayerCastbarIconLayout is already defined directly on _G
_G.MSUF_NormalizeCastbarWidthSource       = MSUF_NormalizeCastbarWidthSource
_G.MSUF_NormalizePlayerCastbarWidthSource = MSUF_NormalizePlayerCastbarWidthSource
_G.MSUF_GetCastbarWidthSourceKey          = MSUF_GetCastbarWidthSourceKey
_G.MSUF_GetCastbarDesiredSize             = MSUF_GetCastbarDesiredSize
_G.MSUF_UpdateCastbarWidthSourceSync      = MSUF_UpdateCastbarWidthSourceSync
_G.MSUF_GetPlayerCastbarDesiredSize     = MSUF_GetPlayerCastbarDesiredSize
_G.MSUF_ApplyPlayerCastbarSizeAndLayout = MSUF_ApplyPlayerCastbarSizeAndLayout
_G.MSUF_ReanchorPlayerCastBar           = MSUF_ReanchorPlayerCastBar
_G.MSUF_ReanchorBossCastBar             = MSUF_ReanchorBossCastBar

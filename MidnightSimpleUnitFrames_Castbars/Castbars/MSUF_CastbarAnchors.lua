-- Castbars/MSUF_CastbarAnchors.lua
-- Pure layout logic (ClearAllPoints, SetPoint, SetSize) — no combat-path code.

local MSUF_SetPointIfChanged = _G.MSUF_SetPointIfChanged or function(frame, ...)
    if frame then frame:ClearAllPoints(); frame:SetPoint(...) end
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
    local offsetX = g and g.castbarTargetOffsetX or 65
    local offsetY = g and g.castbarTargetOffsetY or -15

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
    local offsetX = g.castbarTargetOffsetX or 65
    local offsetY = g.castbarTargetOffsetY or -15

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarTargetDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufTarget then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufTarget, "TOPLEFT", offsetX, offsetY)
    end

    local width = g.castbarTargetBarWidth
    if not width or width <= 0 then
        if (not g.castbarTargetDetached) and msufTarget and msufTarget.GetWidth then
            width = msufTarget:GetWidth()
        end
    end
    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 240
    end
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or 18
        MSUF_SetWidthIfChanged(frame, width)

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

    local offsetX = g.castbarFocusOffsetX or (g.castbarTargetOffsetX or 65)
    local offsetY = g.castbarFocusOffsetY or (g.castbarTargetOffsetY or -15)

    -- Anchor: either attach to unitframe or detach to UIParent
    if g.castbarFocusDetached then
        MSUF_SetPointIfChanged(frame, "CENTER", UIParent, "CENTER", offsetX, offsetY)
    else
        if not msufFocus then return end
        MSUF_SetPointIfChanged(frame, "BOTTOMLEFT", msufFocus, "TOPLEFT", offsetX, offsetY)
    end

    local width = g.castbarFocusBarWidth
    if not width or width <= 0 then
        if (not g.castbarFocusDetached) and msufFocus and msufFocus.GetWidth then
            width = msufFocus:GetWidth()
        end
    end
    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 240
    end
    if width and width > 0 then
        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            width = snap(frame, width)
        end
        local height = frame:GetHeight() or 18
        MSUF_SetWidthIfChanged(frame, width)

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

    if icon then
        if showIconLocal then
            icon:Show()

            local k = (iconDetached and "D" or "A") .. ":" .. tostring(iconSizeLocal) .. ":" .. tostring(iconOXLocal) .. ":" .. tostring(iconOYLocal)
            if icon._msufPCIconKey ~= k then
                icon:SetSize(iconSizeLocal, iconSizeLocal)
                icon:ClearAllPoints()

                -- IMPORTANT: Parent the icon to statusBar so it renders above the bar texture,
                -- but anchor it to the *bar* to avoid anchor dependency loops.
                icon:SetParent(statusBar)
                icon:SetPoint("LEFT", bar, "LEFT", iconOXLocal, iconOYLocal)

                -- Render: above bar texture, below castbar texts.
                if icon.SetDrawLayer then
                    icon:SetDrawLayer("ARTWORK", 5)
                end

                icon._msufPCIconKey = k
            end
        else
            icon:Hide()
        end
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
end

-- ============================================================
-- Player castbar sizing: always follow castbar size keys (NOT unitframe width).
-- Also keep the player preview frame in perfect sync with the real bar.
-- ============================================================
local function MSUF_GetPlayerCastbarDesiredSize(g, fallbackW, fallbackH)
    local w = g and tonumber(g.castbarPlayerBarWidth) or nil
    local h = g and tonumber(g.castbarPlayerBarHeight) or nil

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

    local offsetX = g.castbarPlayerOffsetX or 0
    local offsetY = g.castbarPlayerOffsetY or 5

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

    local w, h = MSUF_GetPlayerCastbarDesiredSize(g, 250, 18)
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
_G.MSUF_GetPlayerCastbarDesiredSize     = MSUF_GetPlayerCastbarDesiredSize
_G.MSUF_ApplyPlayerCastbarSizeAndLayout = MSUF_ApplyPlayerCastbarSizeAndLayout
_G.MSUF_ReanchorPlayerCastBar           = MSUF_ReanchorPlayerCastBar
_G.MSUF_ReanchorBossCastBar             = MSUF_ReanchorBossCastBar

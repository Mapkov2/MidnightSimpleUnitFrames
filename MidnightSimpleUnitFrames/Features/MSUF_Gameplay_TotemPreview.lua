-- MSUF_Gameplay_TotemPreview.lua
-- Blizzard TotemFrame re-anchor and preview support. Split from Gameplay.lua
-- because it owns independent events, preview frames, drag state, and class gating.
local _, ns = ...
ns = ns or {}
local S = ns.MSUF_GameplayShared or {}

local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_Spell = C_Spell
local GetCursorPosition = GetCursorPosition
local GameTooltip = GameTooltip
local type, tonumber, pairs = type, tonumber, pairs
local math_floor = math.floor
local MSUF_ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns.Translate) == "function" then return ns.Translate(text) end
    local locale = ns.L or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local _L_BLIZZARD_TOTEM_PREVIEW = Tr("Blizzard TotemFrame Preview")
local _L_DRAG_OR_ARROW_KEYS = Tr("Drag or arrow keys to move.")
local _EnsureGameplayDefaults = S.EnsureGameplayDefaults or function()
    _G.MSUF_DB = _G.MSUF_DB or {}
    _G.MSUF_DB.gameplay = _G.MSUF_DB.gameplay or {}
    return _G.MSUF_DB.gameplay
end
local _GetPlayerSpecID = S.GetPlayerSpecID or function() return nil end
local _Clamp = S.Clamp or function(v, lo, hi)
    v = tonumber(v) or 0
    if lo and v < lo then return lo end
    if hi and v > hi then return hi end
    return v
end
local _RoundInt = S.RoundInt or function(v) return math_floor((tonumber(v) or 0) + 0.5) end
local _SetupArrowNudge = S.SetupArrowNudge or function() end
local _BeginHistory = S.BeginHistory or function() end
local _CommitHistory = S.CommitHistory or function() end
local _CheckpointHistory = S.CheckpointHistory or function() end
local _SelectNudgeFrame = S.SelectNudgeFrame or function() end
-- Blizzard owns TotemFrame, its buttons, and all secret runtime values. MSUF only
-- re-anchors the frame out of combat, similar to how EQoL handles this class frame.
do
    local eventFrame
    local originalLayout
    local managed = false
    local hooked = false
    local previewWanted = false
    local previewFrame
    local previewButton

    local BLIZZ_TOTEM_BASE_SIZE = 37
    local MONK_BLACK_OX_STATUE_SPELL_ID = 115315
    local MONK_JADE_SERPENT_STATUE_SPELL_ID = 115313
    local TOTEM_FRAME_CLASSES = {
        SHAMAN = true,
        MONK = true,
    }
    local VALID_ANCHORS = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    }

    local _RefreshBlizzardTotems

    local function _GetPlayerTotemFrameClass()
        if UnitClass then
            local _, class = UnitClass("player")
            if TOTEM_FRAME_CLASSES[class] then
                return class
            end
        end
        return nil
    end

    local function _PlayerHasBlizzardTotemFrame()
        return _GetPlayerTotemFrameClass() ~= nil
    end

    local function _CanMoveBlizzardTotemFrame()
        return not (InCombatLockdown and InCombatLockdown())
    end

    local function _AnchorValue(value, fallback)
        if type(value) == "string" and VALID_ANCHORS[value] then
            return value
        end
        return fallback
    end

    local function _TotemIconSize(g)
        return _Clamp(math_floor((tonumber(g and g.playerTotemsIconSize) or 24) + 0.5), 8, 64)
    end

    local function _GetPreviewSpellID()
        local class = _GetPlayerTotemFrameClass()
        if class == "MONK" then
            return (_GetPlayerSpecID() == 270) and MONK_JADE_SERPENT_STATUE_SPELL_ID or MONK_BLACK_OX_STATUE_SPELL_ID
        end
        return nil
    end

    local function _GetPreviewIconTexture()
        local spellID = _GetPreviewSpellID()
        if spellID and C_Spell and C_Spell.GetSpellTexture then
            local icon = C_Spell.GetSpellTexture(spellID)
            if icon then
                if type(MSUF_ResolveIconTexturePath) == "function" then
                    icon = MSUF_ResolveIconTexturePath(icon)
                end
                return icon
            end
        end

        -- Same generic sample icon EQoL uses for TotemButtonTemplate previews.
        return 136099
    end

    local function _AnchorFrameToPlayer(frame, g, offX, offY)
        if not frame then return end

        local playerFrame = _G.MSUF_player
        local anchorFrom = _AnchorValue(g and g.playerTotemsAnchorFrom, "TOPLEFT")
        local anchorTo = _AnchorValue(g and g.playerTotemsAnchorTo, "BOTTOMLEFT")
        local x = (type(offX) == "number") and offX or (tonumber(g and g.playerTotemsOffsetX) or 0)
        local y = (type(offY) == "number") and offY or (tonumber(g and g.playerTotemsOffsetY) or -6)

        frame:ClearAllPoints()
        if playerFrame then
            frame:SetPoint(anchorFrom, playerFrame, anchorTo, x, y)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end

    local function _StoreOriginalLayout(frame)
        if not frame or originalLayout then return end

        local info = {
            parent = frame:GetParent(),
            scale = frame:GetScale(),
            strata = frame:GetFrameStrata(),
            level = frame:GetFrameLevel(),
            ignoreFramePositionManager = frame.ignoreFramePositionManager,
            points = {},
        }

        for i = 1, frame:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
            info.points[#info.points + 1] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end

        originalLayout = info
    end

    local function _HookBlizzardTotemFrame(frame)
        if not frame or hooked then return end
        hooked = true
        frame:HookScript("OnShow", function()
            if _RefreshBlizzardTotems then
                _RefreshBlizzardTotems()
            end
        end)
    end

    local function _RestoreBlizzardTotemFrame()
        if not managed then return true end

        local frame = _G.TotemFrame
        if not frame then
            managed = false
            return true
        end

        if not _CanMoveBlizzardTotemFrame() then
            return false
        end

        local info = originalLayout
        managed = false

        if not info then return true end

        if frame.SetParent then
            frame:SetParent(info.parent or UIParent)
        end

        frame:ClearAllPoints()
        if info.points and #info.points > 0 then
            for _, pt in pairs(info.points) do
                frame:SetPoint(pt.point, pt.relativeTo or UIParent, pt.relativePoint or pt.point, pt.x or 0, pt.y or 0)
            end
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        if info.scale and frame.SetScale then frame:SetScale(info.scale) end
        if info.strata and frame.SetFrameStrata then frame:SetFrameStrata(info.strata) end
        if info.level and frame.SetFrameLevel then frame:SetFrameLevel(info.level) end
        if info.ignoreFramePositionManager ~= nil then
            frame.ignoreFramePositionManager = info.ignoreFramePositionManager
        end
        if frame.Layout then frame:Layout() end

        return true
    end

    local function _ApplyBlizzardTotemFrame(g)
        local frame = _G.TotemFrame
        if not frame then return false end

        if not _CanMoveBlizzardTotemFrame() then
            return false
        end

        local playerFrame = _G.MSUF_player
        _StoreOriginalLayout(frame)
        _HookBlizzardTotemFrame(frame)

        managed = true
        frame.ignoreFramePositionManager = true

        if frame.SetParent then
            frame:SetParent(playerFrame or UIParent)
        end
        _AnchorFrameToPlayer(frame, g)

        if frame.SetScale then
            local baseScale = (originalLayout and originalLayout.scale) or 1
            local scale = _Clamp((_TotemIconSize(g) / BLIZZ_TOTEM_BASE_SIZE) * baseScale, 0.35, 2.50)
            frame:SetScale(scale)
        end

        if playerFrame then
            if frame.SetFrameStrata and playerFrame.GetFrameStrata then
                frame:SetFrameStrata(playerFrame:GetFrameStrata())
            end
            if frame.SetFrameLevel and playerFrame.GetFrameLevel then
                frame:SetFrameLevel((playerFrame:GetFrameLevel() or 0) + 5)
            end
        end

        if frame.Layout then frame:Layout() end
        return true
    end

    local function _ApplyPreviewAnchorOnly(g, offX, offY)
        if not previewFrame then return end
        _AnchorFrameToPlayer(previewFrame, g, offX, offY)
    end

    local function _SetPreviewDragEnabled(enabled)
        if not previewFrame or not previewFrame._msufDragOverlay then return end

        local overlay = previewFrame._msufDragOverlay
        if enabled then
            overlay:Show()
            overlay:EnableMouse(true)
        else
            overlay:EnableMouse(false)
            overlay:SetScript("OnUpdate", nil)
            overlay._msufDragging = nil
            overlay:Hide()
        end
    end

    local function _EnsurePreviewFrame()
        if previewFrame then return previewFrame end

        previewFrame = CreateFrame("Frame", "MSUF_PlayerTotemsPreviewFrame", UIParent)
        previewFrame:SetFrameStrata("MEDIUM")
        previewFrame:SetFrameLevel(200)
        previewFrame:SetSize(BLIZZ_TOTEM_BASE_SIZE, BLIZZ_TOTEM_BASE_SIZE)

        previewButton = CreateFrame("Button", nil, previewFrame, "TotemButtonTemplate")
        previewButton:SetAllPoints(previewFrame)
        previewButton.layoutIndex = 1
        previewButton.slot = 0
        previewButton:EnableMouse(false)
        if previewButton.SetScript then
            previewButton:SetScript("OnUpdate", nil)
        end
        if previewButton.Icon and previewButton.Icon.Cooldown then previewButton.Icon.Cooldown:Hide() end
        if previewButton.Duration then
            previewButton.Duration:SetText("")
            previewButton.Duration:Hide()
        end
        if not (previewButton.Icon and previewButton.Icon.Texture) then
            local icon = previewButton:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(previewButton)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            previewButton._msufFallbackIcon = icon
        end

        local overlay = CreateFrame("Button", nil, previewFrame)
        overlay:SetAllPoints(previewFrame)
        overlay:SetFrameLevel(previewFrame:GetFrameLevel() + 20)
        overlay:EnableMouse(false)
        overlay:Hide()

        local highlight = overlay:CreateTexture(nil, "OVERLAY")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        highlight:Hide()
        overlay._msufHi = highlight

        overlay:SetScript("OnEnter", function(self)
            if self._msufHi then self._msufHi:Show() end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(_L_BLIZZARD_TOTEM_PREVIEW, 1, 1, 1)
        GameTooltip:AddLine(_L_DRAG_OR_ARROW_KEYS, 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end
        end)
        overlay:SetScript("OnLeave", function(self)
            if self._msufHi then self._msufHi:Hide() end
            if GameTooltip then GameTooltip:Hide() end
        end)
        overlay:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end

            local g = _EnsureGameplayDefaults()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local cursorX, cursorY = GetCursorPosition()
            cursorX = cursorX / scale
            cursorY = cursorY / scale

            self._msufDragG = g
            self._msufDragStartCursorX = cursorX
            self._msufDragStartCursorY = cursorY
            self._msufDragStartOffX = tonumber(g.playerTotemsOffsetX) or 0
            self._msufDragStartOffY = tonumber(g.playerTotemsOffsetY) or -6
            self._msufDragLastOffX = self._msufDragStartOffX
            self._msufDragLastOffY = self._msufDragStartOffY
            self._msufDragging = true
            _BeginHistory(self, "TotemFrame position", "gameplay:totems:position")

            self:SetScript("OnUpdate", function(frame)
                if not frame._msufDragging then return end
                local dragG = frame._msufDragG
                if not dragG then return end

                local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                local x, y = GetCursorPosition()
                x = x / uiScale
                y = y / uiScale

                local offX = _RoundInt((frame._msufDragStartOffX or 0) + (x - (frame._msufDragStartCursorX or x)))
                local offY = _RoundInt((frame._msufDragStartOffY or -6) + (y - (frame._msufDragStartCursorY or y)))
                if offX == frame._msufDragLastOffX and offY == frame._msufDragLastOffY then return end

                frame._msufDragLastOffX = offX
                frame._msufDragLastOffY = offY
                dragG.playerTotemsOffsetX = offX
                dragG.playerTotemsOffsetY = offY
                _ApplyPreviewAnchorOnly(dragG, offX, offY)

                local opt = _G.MSUF_GameplayPanel
                if opt and opt.MSUF_SyncTotemOffsetSliders then
                    opt:MSUF_SyncTotemOffsetSliders()
                end
            end)
        end)
        overlay:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            self._msufDragging = nil
            self:SetScript("OnUpdate", nil)
            _SelectNudgeFrame(self, true)

            if _RefreshBlizzardTotems then
                _RefreshBlizzardTotems()
            end

            local opt = _G.MSUF_GameplayPanel
            if opt and opt.MSUF_SyncTotemOffsetSliders then
                opt:MSUF_SyncTotemOffsetSliders()
            end
            _CommitHistory(self)
        end)

        _SetupArrowNudge(overlay,
            function(_, dx, dy)
                local g = _EnsureGameplayDefaults()
                if not previewFrame or not previewFrame._msufPreviewActive then return false end

                local offX = _RoundInt((tonumber(g.playerTotemsOffsetX) or 0) + (dx or 0))
                local offY = _RoundInt((tonumber(g.playerTotemsOffsetY) or -6) + (dy or 0))
                g.playerTotemsOffsetX = offX
                g.playerTotemsOffsetY = offY
                _ApplyPreviewAnchorOnly(g, offX, offY)
                if _RefreshBlizzardTotems then
                    _RefreshBlizzardTotems()
                end

                local opt = _G.MSUF_GameplayPanel
                if opt and opt.MSUF_SyncTotemOffsetSliders then
                    opt:MSUF_SyncTotemOffsetSliders()
                end
                _CheckpointHistory("TotemFrame position", "gameplay:totems:position")
                return true
            end,
            function()
                return previewFrame and previewFrame._msufPreviewActive and overlay.IsShown and overlay:IsShown()
            end)

        previewFrame._msufDragOverlay = overlay
        previewFrame:Hide()
        return previewFrame
    end

    local function _ApplyPreview(g)
        local frame = _EnsurePreviewFrame()
        frame._msufPreviewActive = true

        frame:SetSize(BLIZZ_TOTEM_BASE_SIZE, BLIZZ_TOTEM_BASE_SIZE)
        frame:SetScale(_Clamp(_TotemIconSize(g) / BLIZZ_TOTEM_BASE_SIZE, 0.35, 2.50))

        if previewButton then
            previewButton:SetAllPoints(frame)
            previewButton.layoutIndex = 1
            previewButton.slot = 0
            local texture = (previewButton.Icon and previewButton.Icon.Texture) or previewButton._msufFallbackIcon
            if texture then
                texture:SetTexture(_GetPreviewIconTexture())
                texture:Show()
            end
            if previewButton.Icon and previewButton.Icon.Cooldown then previewButton.Icon.Cooldown:Hide() end
            if previewButton.Duration then
                previewButton.Duration:SetText("")
                previewButton.Duration:Hide()
            end
            previewButton:Show()
        end

        _AnchorFrameToPlayer(frame, g)
        frame:Show()
        _SetPreviewDragEnabled(true)
    end

    local function _ClearPreview()
        if previewFrame then
            previewFrame._msufPreviewActive = nil
            previewFrame:Hide()
        end
        _SetPreviewDragEnabled(false)
    end

    function _RefreshBlizzardTotems()
        local g = _EnsureGameplayDefaults()
        local hasTotemFrame = _PlayerHasBlizzardTotemFrame()

        if not hasTotemFrame then
            previewWanted = false
        end

        if hasTotemFrame and previewWanted then
            _ApplyPreview(g)
        else
            _ClearPreview()
        end

        if not hasTotemFrame or not (g and g.enablePlayerTotems) then
            _RestoreBlizzardTotemFrame()
            return
        end

        _ApplyBlizzardTotemFrame(g)
    end

    local function _EnsureEventFrame()
        if eventFrame then return end

        eventFrame = CreateFrame("Frame", "MSUF_PlayerTotemsBlizzardEventFrame", UIParent)
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                local unit = ...
                if unit ~= "player" then return end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, _RefreshBlizzardTotems)
                    C_Timer.After(0.10, _RefreshBlizzardTotems)
                else
                    _RefreshBlizzardTotems()
                end
                return
            end

            if event == "ADDON_LOADED" and not _G.TotemFrame then
                return
            end

            _RefreshBlizzardTotems()
        end)
    end

    function ns.MSUF_Gameplay_PlayerTotems_Apply(g)
        _EnsureEventFrame()

        eventFrame:UnregisterAllEvents()
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:RegisterEvent("PLAYER_LOGIN")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

        if g and g.enablePlayerTotems and _PlayerHasBlizzardTotemFrame() then
            eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
            if eventFrame.RegisterUnitEvent then
                eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            else
                eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            end
        end

        _RefreshBlizzardTotems()
    end

    _G.MSUF_PlayerTotems_ForceRefresh = _RefreshBlizzardTotems

    function ns.MSUF_PlayerTotems_TogglePreview()
        previewWanted = not previewWanted
        _RefreshBlizzardTotems()
    end

    function ns.MSUF_PlayerTotems_IsPreviewActive()
        return previewWanted and true or false
    end
end

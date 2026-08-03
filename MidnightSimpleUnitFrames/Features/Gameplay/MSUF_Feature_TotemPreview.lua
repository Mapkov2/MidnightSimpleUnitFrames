local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local S = MSUF.MSUF_GameplayShared or MSUF.Gameplay or {}

-- Blizzard totem/statue preview controller.
-- Lets edit mode display and move Blizzard's totem-style frame without taking ownership of
-- the live Blizzard frame during combat. Saved offsets flow through gameplay config helpers.
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local C_Spell = C_Spell
local GetCursorPosition = GetCursorPosition
local GameTooltip = GameTooltip
local type, tonumber, pairs = type, tonumber, pairs
local math_floor = math.floor
local MSUF_ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- driver disabled and silently kills the drag OnUpdate.
local ONUPDATE_MODE_DISABLED = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisible) or 1

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local _L_BLIZZARD_TOTEM_PREVIEW = Tr("Blizzard TotemFrame Preview")
local _L_DRAG_OR_ARROW_KEYS = Tr("Drag or arrow keys to move.")
local _EnsureGameplayDefaults = MSUF.MSUF_EnsureGameplayDefaults
-- EnsureGameplayDefaults re-seeds ~33 keys on every call; the fast variant returns the cached
-- table and only falls back to the full seed before the first one has run.
local _GetGameplayDB = MSUF.MSUF_GetGameplayDBFast or _EnsureGameplayDefaults
local _GetPlayerSpecID = S.GetPlayerSpecID
local _Clamp = S.Clamp
local _RoundInt = S.RoundInt
local _SetupArrowNudge = S.SetupArrowNudge
local _BeginHistory = S.BeginHistory
local _CommitHistory = S.CommitHistory
local _CheckpointHistory = S.CheckpointHistory
local _SelectNudgeFrame = S.SelectNudgeFrame

local function _SyncTotemOffsetSliders()
    -- Menu2 owns the offset sliders. RequestRefresh coalesces through a queued flag, so calling
    -- this once per drag pixel collapses into one page resync per MENU_REFRESH_DELAY.
    local menu = _G.MSUF2
    if not (menu and menu.RequestRefresh) then return end
    local frame = menu.frame
    if not (frame and frame.IsShown and frame:IsShown()) then return end
    menu.RequestRefresh(nil, "gameplay-totems-offset")
end

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
    local VALID_ANCHORS = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    }

    local _RefreshBlizzardTotems

    -- The player's class cannot change within a session, but UnitClass can still answer nil
    -- during very early load, so only a resolved token is cached. The token no longer decides
    -- availability, it only picks the statue icon the preview shows for Monks.
    local playerClassCache
    local function _GetPlayerClass()
        local class = playerClassCache
        if class == nil then
            if not UnitClass then return nil end
            local _, token = UnitClass("player")
            if token == nil then return nil end
            class = token
            playerClassCache = class
        end
        return class
    end

    -- TotemFrameMixin:Update walks STANDARD_TOTEM_PRIORITIES for every class and only reorders
    -- the four slots for Shamans, so any class that puts something into a totem slot (Death
    -- Knight ghoul, Paladin Consecration, Monk statues) gets a frame. Availability is therefore
    -- only about Blizzard's frame existing.
    local function _PlayerHasBlizzardTotemFrame()
        return _G.TotemFrame ~= nil
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
        local class = _GetPlayerClass()
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

        return 136099
    end

    local function _AnchorFrameToPlayer(frame, g, offX, offY)
        if not frame then return end
        -- Preview and live override use the same anchor resolver so saved offsets match what
        -- the user drags in EditMode.

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

    -- Container fan-out runs on every apply, so it stays allocation-free: no `seen` table and no
    -- per-call closures. There are only four candidates, so dedupe is done by direct comparison.
    local function _InvokeManagedContainer(container, frame, method, a, b, c)
        if not container or container == a or container == b or container == c then return container end
        local fn = container[method]
        if type(fn) == "function" then fn(container, frame) end
        return container
    end

    local function _ForEachTotemManagedContainer(frame, method)
        local a = _InvokeManagedContainer(frame and frame.layoutParent, frame, method)
        local b
        local getter = _G.GetPlayerBottomManagedFrameContainer
        if type(getter) == "function" then
            b = _InvokeManagedContainer(getter(), frame, method, a)
        end
        local c = _InvokeManagedContainer(_G.PlayerBottomManagedFrameContainer, frame, method, a, b)
        _InvokeManagedContainer(_G.PlayerFrameBottomManagedFramesContainer, frame, method, a, b, c)
    end

    local function _RemoveFromTotemManagedContainers(frame)
        _ForEachTotemManagedContainer(frame, "RemoveManagedFrame")
    end

    local function _ReturnToTotemManagedContainer(frame)
        if not (frame and frame.IsShown and frame:IsShown()) then return end
        _ForEachTotemManagedContainer(frame, "AddManagedFrame")
    end

    local function _StoreOriginalLayout(frame)
        if not frame or originalLayout then return end

        -- Blizzard owns TotemFrame layout. Store the full original anchor/parent state before
        -- MSUF takes temporary preview ownership so it can be restored losslessly.
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

    local function _OnBlizzardTotemFrameTouched()
        if _RefreshBlizzardTotems then
            _RefreshBlizzardTotems()
        end
    end

    local function _HookBlizzardTotemFrame(frame)
        if not frame or hooked then return end
        hooked = true
        -- TotemFrameMixin:Update ends with Layout() + SetShown(), so a post-hook lands exactly
        -- once after Blizzard finished rebuilding, for every reason Blizzard rebuilds
        -- (PLAYER_TOTEM_UPDATE, shapeshift, talents, spec). That replaces guessing with timers
        -- off UNIT_SPELLCAST_SUCCEEDED.
        if type(frame.Update) == "function" and _G.hooksecurefunc then
            _G.hooksecurefunc(frame, "Update", _OnBlizzardTotemFrameTouched)
        end
        -- Kept as a net for third parties that Show() the frame without going through Update.
        frame:HookScript("OnShow", _OnBlizzardTotemFrameTouched)
    end

    local function _RestoreBlizzardTotemFrame()
        if not managed then return true end

        local frame = _G.TotemFrame
        if not frame then
            managed = false
            return true
        end

        if not _CanMoveBlizzardTotemFrame() then
            -- Secure/protected frame layout changes are deferred by returning false to the
            -- caller; do not partially restore while combat-locked.
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
        frame.ignoreFramePositionManager = info.ignoreFramePositionManager
        if frame.Layout then frame:Layout() end
        _ReturnToTotemManagedContainer(frame)

        -- Returning true means ownership is back with Blizzard and MSUF should stop applying
        -- preview offsets until the user enables the helper again.
        return true
    end

    -- SetScale stores a 32-bit float, so a value read back never compares equal to the double we
    -- computed. Geometry offsets are integers and round-trip exactly.
    local SCALE_EPSILON = 0.0005

    local function _TotemAnchorMatches(frame, anchorFrom, relativeTo, anchorTo, x, y)
        if frame:GetNumPoints() ~= 1 then return false end
        local point, currentRelativeTo, relativePoint, currentX, currentY = frame:GetPoint(1)
        return point == anchorFrom
            and currentRelativeTo == relativeTo
            and relativePoint == anchorTo
            and currentX == x
            and currentY == y
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

        -- Blizzard rebuilds TotemFrame far more often than the user changes these settings, so
        -- every write below is verified first. A redundant refresh then costs a handful of
        -- getters instead of a parent/anchor/scale/strata rewrite.
        managed = true

        -- ManagedFrameMixin:OnShow re-adds the frame on every show, so this cannot be gated to
        -- the first apply. Both sides are self-guarding: AddManagedFrame bails on
        -- ignoreFramePositionManager, RemoveManagedFrame bails when the frame is not tracked, so
        -- repeat calls cost one table lookup and never trigger a container Layout.
        frame.ignoreFramePositionManager = true
        _RemoveFromTotemManagedContainers(frame)

        local wantParent = playerFrame or UIParent
        if frame.SetParent and frame:GetParent() ~= wantParent then
            frame:SetParent(wantParent)
        end

        local anchorFrom = _AnchorValue(g and g.playerTotemsAnchorFrom, "TOPLEFT")
        local anchorTo = _AnchorValue(g and g.playerTotemsAnchorTo, "BOTTOMLEFT")
        local x = tonumber(g and g.playerTotemsOffsetX) or 0
        local y = tonumber(g and g.playerTotemsOffsetY) or -6
        if playerFrame then
            if not _TotemAnchorMatches(frame, anchorFrom, playerFrame, anchorTo, x, y) then
                frame:ClearAllPoints()
                frame:SetPoint(anchorFrom, playerFrame, anchorTo, x, y)
            end
        elseif not _TotemAnchorMatches(frame, "CENTER", UIParent, "CENTER", x, y) then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end

        if frame.SetScale then
            local baseScale = (originalLayout and originalLayout.scale) or 1
            local scale = _Clamp((_TotemIconSize(g) / BLIZZ_TOTEM_BASE_SIZE) * baseScale, 0.35, 2.50)
            local current = frame:GetScale() or 1
            if current > scale + SCALE_EPSILON or current < scale - SCALE_EPSILON then
                frame:SetScale(scale)
            end
        end

        if playerFrame then
            if frame.SetFrameStrata and playerFrame.GetFrameStrata then
                local strata = playerFrame:GetFrameStrata()
                if strata and frame:GetFrameStrata() ~= strata then
                    frame:SetFrameStrata(strata)
                end
            end
            if frame.SetFrameLevel and playerFrame.GetFrameLevel then
                local level = (playerFrame:GetFrameLevel() or 0) + 5
                if frame:GetFrameLevel() ~= level then
                    frame:SetFrameLevel(level)
                end
            end
        end

        -- No Layout() here on purpose: LayoutMixin:Layout has no dirty check and allocates a
        -- child list on every call, while parent/anchor/scale/strata changes never affect child
        -- layout. Blizzard already calls Layout() at the end of its own Update.
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
            if overlay.SetOnUpdateMode then overlay:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
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
            if previewButton.SetOnUpdateMode then previewButton:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
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
        -- Hoisted out of OnMouseDown: one closure for the module instead of a fresh one per drag.
        local function _DragOnUpdate(frame)
            if not frame._msufDragging then return end
            local dragG = frame._msufDragG
            if not dragG then return end

            local x, y = GetCursorPosition()
            local uiScale = frame._msufDragScale
            x = x / uiScale
            y = y / uiScale

            local offX = _RoundInt(frame._msufDragStartOffX + (x - frame._msufDragStartCursorX))
            local offY = _RoundInt(frame._msufDragStartOffY + (y - frame._msufDragStartCursorY))
            if offX == frame._msufDragLastOffX and offY == frame._msufDragLastOffY then return end

            frame._msufDragLastOffX = offX
            frame._msufDragLastOffY = offY
            dragG.playerTotemsOffsetX = offX
            dragG.playerTotemsOffsetY = offY
            _ApplyPreviewAnchorOnly(dragG, offX, offY)

            _SyncTotemOffsetSliders()
        end

        overlay:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end

            local g = _GetGameplayDB()
            -- Sampled once: the drag delta must be measured against the same scale it started
            -- with, and it saves a C call per rendered frame.
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local cursorX, cursorY = GetCursorPosition()

            self._msufDragG = g
            self._msufDragScale = scale
            self._msufDragStartCursorX = cursorX / scale
            self._msufDragStartCursorY = cursorY / scale
            self._msufDragStartOffX = tonumber(g.playerTotemsOffsetX) or 0
            self._msufDragStartOffY = tonumber(g.playerTotemsOffsetY) or -6
            self._msufDragLastOffX = self._msufDragStartOffX
            self._msufDragLastOffY = self._msufDragStartOffY
            self._msufDragging = true
            _BeginHistory(self, "TotemFrame position", "gameplay:totems:position")

            if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
            self:SetScript("OnUpdate", _DragOnUpdate)
        end)
        overlay:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            self._msufDragging = nil
            self:SetScript("OnUpdate", nil)
            if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
            _SelectNudgeFrame(self, true)

            if _RefreshBlizzardTotems then
                _RefreshBlizzardTotems()
            end

            _SyncTotemOffsetSliders()
            _CommitHistory(self)
        end)

        _SetupArrowNudge(overlay,
            function(_, dx, dy)
                local g = _GetGameplayDB()
                if not previewFrame or not previewFrame._msufPreviewActive then return false end

                local offX = _RoundInt((tonumber(g.playerTotemsOffsetX) or 0) + (dx or 0))
                local offY = _RoundInt((tonumber(g.playerTotemsOffsetY) or -6) + (dy or 0))
                g.playerTotemsOffsetX = offX
                g.playerTotemsOffsetY = offY
                _ApplyPreviewAnchorOnly(g, offX, offY)
                if _RefreshBlizzardTotems then
                    _RefreshBlizzardTotems()
                end

                _SyncTotemOffsetSliders()
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
        local firstApply = not frame._msufPreviewActive
        frame._msufPreviewActive = true

        -- Every Blizzard TotemFrame rebuild now reaches this function too, so the button
        -- decoration only runs when the preview is opened or the icon size actually changed.
        local iconSize = _TotemIconSize(g)
        if firstApply or frame._msufAppliedIconSize ~= iconSize then
            frame._msufAppliedIconSize = iconSize
            frame:SetSize(BLIZZ_TOTEM_BASE_SIZE, BLIZZ_TOTEM_BASE_SIZE)
            frame:SetScale(_Clamp(iconSize / BLIZZ_TOTEM_BASE_SIZE, 0.35, 2.50))
        end

        if previewButton then
            if firstApply then
                previewButton:SetAllPoints(frame)
                previewButton.layoutIndex = 1
                previewButton.slot = 0
                if previewButton.Icon and previewButton.Icon.Cooldown then previewButton.Icon.Cooldown:Hide() end
                if previewButton.Duration then
                    previewButton.Duration:SetText("")
                    previewButton.Duration:Hide()
                end
                previewButton:Show()
            end
            -- Resolved every time rather than gated on firstApply: the Monk statue icon depends
            -- on spec, and a spec change reaches us through Blizzard's own rebuild.
            local icon = _GetPreviewIconTexture()
            if frame._msufAppliedIcon ~= icon then
                frame._msufAppliedIcon = icon
                local texture = (previewButton.Icon and previewButton.Icon.Texture) or previewButton._msufFallbackIcon
                if texture then
                    texture:SetTexture(icon)
                    texture:Show()
                end
            end
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

    local refreshing = false
    function _RefreshBlizzardTotems()
        local g = _GetGameplayDB()
        -- `managed` keeps the door open while the feature is already off: a restore refused
        -- during combat still has to run once the lockdown lifts.
        if not (g and g.enablePlayerTotems) and not previewWanted and not managed then return end
        -- The OnShow hook fires from inside Blizzard's Update, which the post-hook also covers.
        -- Re-entry would just redo the work the outer pass is about to verify anyway.
        if refreshing then return end
        refreshing = true

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
        else
            _ApplyBlizzardTotemFrame(g)
        end

        refreshing = false
    end

    local function _EnsureEventFrame()
        if eventFrame then return end

        eventFrame = CreateFrame("Frame", "MSUF_PlayerTotemsBlizzardEventFrame", UIParent)
        eventFrame:SetScript("OnEvent", function(self, event)
            if event == "ADDON_LOADED" and not _G.TotemFrame then
                return
            end

            _RefreshBlizzardTotems()

            -- Turning the feature off during combat leaves this frame registered for exactly one
            -- event so the deferred restore can finish. Drop it again once ownership is back.
            if self._msufRestorePending and not managed then
                self._msufRestorePending = nil
                self:UnregisterAllEvents()
            end
        end)
    end

    local totemWasActive = false
    function MSUF.MSUF_Gameplay_PlayerTotems_Apply(g)
        local enabled = g and g.enablePlayerTotems == true
        if not enabled then
            previewWanted = false
            _ClearPreview()
            if eventFrame then
                eventFrame._msufRestorePending = nil
                eventFrame:UnregisterAllEvents()
            end
            if totemWasActive and not _RestoreBlizzardTotemFrame() and eventFrame then
                -- Combat refused the restore. Without this the frame would keep MSUF's anchor
                -- until the next enable or reload, because every event was just dropped.
                eventFrame._msufRestorePending = true
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            totemWasActive = false
            return
        end

        _EnsureEventFrame()
        eventFrame:UnregisterAllEvents()
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

        -- PLAYER_TOTEM_UPDATE is a cheap safety net for the window before the Update post-hook is
        -- installed. Totem changes afterwards arrive through that hook, so no cast-driven
        -- refresh is registered: it fired on every successful cast and only ever re-did work the
        -- hook already covers. Registered unconditionally: the event never fires for a character
        -- that never fills a totem slot, and gating it on TotemFrame existing would drop the net
        -- exactly in the case it covers.
        eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")

        totemWasActive = true
        _RefreshBlizzardTotems()
    end

    ExportPublic("MSUF_PlayerTotems_ForceRefresh", _RefreshBlizzardTotems)

    function MSUF.MSUF_PlayerTotems_TogglePreview()
        previewWanted = not previewWanted
        _RefreshBlizzardTotems()
    end

    function MSUF.MSUF_PlayerTotems_IsPreviewActive()
        return previewWanted and true or false
    end
end

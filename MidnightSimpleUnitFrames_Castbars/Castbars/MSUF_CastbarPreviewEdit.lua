-- Castbars/MSUF_CastbarPreviewEdit.lua

local MSUF_PreviewEditCfg = {
    player = {
        widthKey  = "castbarPlayerBarWidth",
        heightKey = "castbarPlayerBarHeight",
        offsetXKey = "castbarPlayerOffsetX",
        offsetYKey = "castbarPlayerOffsetY",
        defaultX = 0,
        defaultY = 5,
        reanchorFunc = "MSUF_ReanchorPlayerCastBar",
    },
    target = {
        widthKey  = "castbarTargetBarWidth",
        heightKey = "castbarTargetBarHeight",
        offsetXKey = "castbarTargetOffsetX",
        offsetYKey = "castbarTargetOffsetY",
        defaultX = 65,
        defaultY = -15,
        reanchorFunc = "MSUF_ReanchorTargetCastBar",
    },
    focus = {
        widthKey  = "castbarFocusBarWidth",
        heightKey = "castbarFocusBarHeight",
        offsetXKey = "castbarFocusOffsetX",
        offsetYKey = "castbarFocusOffsetY",
        defaultXFrom = { "castbarFocusOffsetX", "castbarTargetOffsetX" },
        defaultYFrom = { "castbarFocusOffsetY", "castbarTargetOffsetY" },
        defaultX = 65,
        defaultY = -15,
        reanchorFunc = "MSUF_ReanchorFocusCastBar",
    },
boss = {
    widthKey  = "bossCastbarWidth",
    heightKey = "bossCastbarHeight",
    offsetXKey = "bossCastbarOffsetX",
    offsetYKey = "bossCastbarOffsetY",
    defaultX = 0,
    defaultY = 0,
    reanchorFunc = "MSUF_ReanchorBossCastBar",
},
}

local function MSUF_GetFirstNonNil(g, keys, fallback)
    if g and keys then
        for i = 1, #keys do
            local k = keys[i]
            if k and g[k] ~= nil then
                return g[k]
            end
        end
    end
    return fallback
end

-- ============================================================
-- Edit Mode UX: clicking any castbar preview should immediately
-- play the fill animation (dummy cast) so the user can see
-- progress/texture/alpha changes while positioning.
--
-- Requirements:
-- - Works for player/target/focus/boss previews.
-- - Must not persist settings; click is a temporary "pulse".
-- - Must not fight dragging (drag OnUpdate overrides test mode).
-- - Must be very low cost (Edit Mode only).
-- ============================================================

local MSUF_PREVIEW_PULSE_SECONDS = 8

local function MSUF_PulseCastbarPreview(kind)
    if not kind or not MSUF_UnitEditModeActive then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if type(EnsureDB) == "function" then EnsureDB() end
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if not g then return end

    -- Resolve start/stop funcs and the persistent DB key.
    local startFn, stopFn, dbKey
    if kind == "player" then
        startFn = _G.MSUF_SetPlayerCastbarTestMode
        stopFn  = _G.MSUF_SetPlayerCastbarTestMode
        dbKey   = "playerCastbarTestMode"
    elseif kind == "target" then
        startFn = _G.MSUF_SetTargetCastbarTestMode
        stopFn  = _G.MSUF_SetTargetCastbarTestMode
        dbKey   = "targetCastbarTestMode"
    elseif kind == "focus" then
        startFn = _G.MSUF_SetFocusCastbarTestMode
        stopFn  = _G.MSUF_SetFocusCastbarTestMode
        dbKey   = "focusCastbarTestMode"
    elseif kind == "boss" then
        startFn = _G.MSUF_SetBossCastbarTestMode
        stopFn  = _G.MSUF_SetBossCastbarTestMode
        dbKey   = "bossCastbarTestMode"
    else
        return
    end

    if type(startFn) ~= "function" or type(stopFn) ~= "function" then
        return
    end

    -- Start/refresh the dummy cast WITHOUT persisting the setting.
    startFn(true, true)

    -- Coalesce stop timers per kind (avoid timer spam if the user clicks repeatedly).
    local timers = _G.MSUF_CastbarPreviewPulseTimers
    if not timers then
        timers = {}
        _G.MSUF_CastbarPreviewPulseTimers = timers
    end

    if not (C_Timer and C_Timer.NewTimer) then
        return
    end

    local function ScheduleStop(delay)
        local old = timers[kind]
        if old and old.Cancel then
            old:Cancel()
        end
        timers[kind] = C_Timer.NewTimer(delay, function()
            if not MSUF_UnitEditModeActive then return end
            if InCombatLockdown and InCombatLockdown() then return end
            if type(EnsureDB) == "function" then EnsureDB() end
            local gg = (MSUF_DB and MSUF_DB.general) or nil
            if not gg then return end

            -- If the user enabled the persistent test mode toggle, never stop via pulse.
            if dbKey and gg[dbKey] then
                return
            end

            -- If the edit popup for this castbar is open, keep animating and check again shortly.
            local popup = _G.MSUF_CastbarPositionPopup
            if popup and popup.IsShown and popup:IsShown() and popup.unit == kind then
                ScheduleStop(2)
                return
            end

            stopFn(false, true)
        end)
    end

    ScheduleStop(MSUF_PREVIEW_PULSE_SECONDS)
end

function _G.MSUF_SetupCastbarPreviewEditHandlers(frame, kind)
    if not frame or frame.MSUF_PreviewEditHandlersSetup then return end
    frame.MSUF_PreviewEditHandlersSetup = true

    local cfg = MSUF_PreviewEditCfg[kind] or MSUF_PreviewEditCfg.player
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)

    frame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if MSUF_EditModeSizing then return end
            if InCombatLockdown and InCombatLockdown() then return end
            if type(MSUF_OpenCastbarPositionPopup) == "function" then
                MSUF_OpenCastbarPositionPopup(kind, self)
            end
            return
        end

        if button ~= "LeftButton" then return end
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local g = MSUF_DB.general or {}
        if not g.castbarPlayerPreviewEnabled then return end

        self.isDragging = true
        self.dragMoved = false

        local uiScale = UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale
        self.dragStartCursorX = cx
        self.dragStartCursorY = cy

        if MSUF_EditModeSizing then
            local baseW = g[cfg.widthKey]  or g.castbarGlobalWidth  or self:GetWidth()  or 250
            local baseH = g[cfg.heightKey] or g.castbarGlobalHeight or self:GetHeight() or 18
            self.dragStartWidth  = baseW
            self.dragStartHeight = baseH
            self.dragMode = "SIZE"
        else
            local defX = cfg.defaultXFrom and MSUF_GetFirstNonNil(g, cfg.defaultXFrom, cfg.defaultX) or cfg.defaultX
            local defY = cfg.defaultYFrom and MSUF_GetFirstNonNil(g, cfg.defaultYFrom, cfg.defaultY) or cfg.defaultY
            self.dragStartOffsetX = g[cfg.offsetXKey] or defX
            self.dragStartOffsetY = g[cfg.offsetYKey] or defY
            self.dragMode = "MOVE"
        end

        self:SetScript("OnUpdate", function(self)
            if not self.isDragging then
                self:SetScript("OnUpdate", nil)
                return
            end

            local uiScale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / uiScale, cy / uiScale

            local dx = cx - (self.dragStartCursorX or cx)
            local dy = cy - (self.dragStartCursorY or cy)

            -- Click threshold: only start applying changes once the cursor moved a bit.
            if not self.dragMoved then
                if math.abs(dx) + math.abs(dy) < 6 then
                    return
                end
                self.dragMoved = true
            end

            EnsureDB()
            local g2 = MSUF_DB.general or {}

            if self.dragMode == "SIZE" then
                local newW = math.max(50, (self.dragStartWidth  or 250) + dx)
                local newH = math.max(8,  (self.dragStartHeight or 18) + dy)

                g2[cfg.widthKey]  = math.floor(newW + 0.5)
                g2[cfg.heightKey] = math.floor(newH + 0.5)

                if kind == "boss" then
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
                else
                    if type(MSUF_UpdateCastbarVisuals) == "function" then
                        MSUF_UpdateCastbarVisuals()
                    end
                end
else
                g2[cfg.offsetXKey] = (self.dragStartOffsetX or 0) + dx
                g2[cfg.offsetYKey] = (self.dragStartOffsetY or 0) + dy

               if kind == "boss" then
    local sx = _G["MSUF_CastbarBossXOffsetSlider"]
    local sy = _G["MSUF_CastbarBossYOffsetSlider"]
    if sx then g2[cfg.offsetXKey] = MSUF_ClampToSlider(sx, tonumber(g2[cfg.offsetXKey]) or 0) end
    if sy then g2[cfg.offsetYKey] = MSUF_ClampToSlider(sy, tonumber(g2[cfg.offsetYKey]) or 0) end
end

 local rf = cfg.reanchorFunc and _G[cfg.reanchorFunc]
                if type(rf) == "function" then
                    rf()
                end

                if kind == "boss" and type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    _G.MSUF_UpdateBossCastbarPreview()
                end
            end

            if type(MSUF_UpdateCastbarEditInfo) == "function" then
                MSUF_UpdateCastbarEditInfo(kind)
            end
            if type(MSUF_SyncCastbarPositionPopup) == "function" then
                MSUF_SyncCastbarPositionPopup(kind)
            end
        end)
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end

        local wasMoved = self.dragMoved

        if self.isDragging then
            self.isDragging = false
            self:SetScript("OnUpdate", nil)
        end

        -- After any click/drag ends, ensure the preview fill animation runs.
        -- (Dragging temporarily overrides OnUpdate, so we restart the pulse here.)
        MSUF_PulseCastbarPreview(kind)

        -- Simple click (no drag) opens the edit popup (same behavior as unitframes).
        if (not wasMoved) and MSUF_UnitEditModeActive and type(MSUF_OpenCastbarPositionPopup) == "function" then
            if InCombatLockdown and InCombatLockdown() then return end
            MSUF_OpenCastbarPositionPopup(kind, self)
        end
    end)
end


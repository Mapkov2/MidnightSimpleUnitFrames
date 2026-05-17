-- MidnightSimpleUnitFrames_FocusKickIcon.lua
-- Standalone module for "Focus Kick Icon" mode.
-- When enabled:
--   * Hides the MSUF focus castbar (FocusCastBar) by setting alpha to 0
--   * Shows a separate icon that mirrors the focus cast spell
--   * Uses castbar bar color to decide interruptible vs non-interruptible:
--       - red-ish => non-interruptible (icon desaturated)
--       - anything else => interruptible (normal icon)
--   * On interrupt (via FocusCastBar:SetInterrupted) the icon flashes red and shakes.
-- All X/Y/Width/Height are configured via extra sliders in the Focus castbar options.

local addonName, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local API shortcuts
------------------------------------------------------
local CreateFrame    = CreateFrame
local UIParent       = UIParent
local hooksecurefunc = hooksecurefunc
local C_Timer_After  = C_Timer and C_Timer.After
local C_Timer_NewTicker = C_Timer and C_Timer.NewTicker

------------------------------------------------------
-- Module state
------------------------------------------------------
local FocusKickFrame
local FocusKick_Hooked            = false
local FocusKick_FocusCastBar

local function FocusKick_StopTimeUpdater(frame)
    frame = frame or FocusKickFrame
    if not frame then return end
    if frame.MSUF_timeTicker and frame.MSUF_timeTicker.Cancel then
        frame.MSUF_timeTicker:Cancel()
    end
    frame.MSUF_timeTicker = nil
    frame:SetScript("OnUpdate", nil)
    frame.MSUF_timeUpdater = nil
    frame.MSUF_timeAccum = nil
end

------------------------------------------------------
-- On-screen preview state
-- Forward-declared here so early helpers (font/apply) can access the same locals.
------------------------------------------------------
local FocusKickPreviewFrame
local FocusKickPreviewEnabled = false
local FocusKickPreviewSelected = false

------------------------------------------------------
-- DB defaults
------------------------------------------------------
local function FocusKick_EnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) ~= "function" then return end

    ensureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    if g.enableFocusKickIcon == nil then
        g.enableFocusKickIcon = false
    end
    if g.focusKickIconOffsetX == nil then
        g.focusKickIconOffsetX = 300
    end
    if g.focusKickIconOffsetY == nil then
        g.focusKickIconOffsetY = 0
    end
    if g.focusKickIconWidth == nil then
        g.focusKickIconWidth = 40
    end
    if g.focusKickIconHeight == nil then
        g.focusKickIconHeight = 40
    end

    -- Optional: user-configured font size for the mirrored cast time text.
    -- If nil, we keep legacy behavior (auto size based on icon height).
    -- NOTE: This is only used by this Focus Kick module.
    if g.focusKickTextSize == nil then
        -- leave nil (auto) by default for 0-regression
    end
end

------------------------------------------------------
-- Helper: desired time text size
------------------------------------------------------
local function FocusKick_GetDesiredTextSize(g)
    if not g then return 12 end

    local v = tonumber(g.focusKickTextSize)
    if v then
        if v < 8 then v = 8 end
        if v > 24 then v = 24 end
        return v
    end

    -- Legacy/auto sizing (0-regression): slightly larger when the icon is larger.
    local h = tonumber(g.focusKickIconHeight) or 40
    if h >= 48 then
        return 14
    end
    return 12
end

------------------------------------------------------
-- Helper: apply time text font immediately (runtime + preview)
-- Safe: only touches existing FontStrings, does not create frames.
------------------------------------------------------
local function FocusKick_ApplyTimeTextFontNow()
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general

    local fontPath = (type(MSUF_GetFontPath) == "function") and (MSUF_GetFontPath() or "Fonts\\FRIZQT__.TTF") or "Fonts\\FRIZQT__.TTF"
    local flags    = (type(MSUF_GetFontFlags) == "function") and (MSUF_GetFontFlags() or "OUTLINE") or "OUTLINE"
    local size     = FocusKick_GetDesiredTextSize(g)

    if FocusKickFrame and FocusKickFrame.timeText then
        FocusKickFrame.timeText:SetFont(fontPath, size, flags)
    end
    if FocusKickPreviewFrame and FocusKickPreviewFrame.timeText then
        FocusKickPreviewFrame.timeText:SetFont(fontPath, size, flags)
        FocusKickPreviewFrame.timeText:SetAlpha(1)
    end
end

------------------------------------------------------
-- Helper: update frame position & size from DB
------------------------------------------------------
local function FocusKick_UpdateAppearance()
    if not FocusKickFrame then return end
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general then return end

    local g = MSUF_DB.general
    local parent = UIParent

    local w = tonumber(g.focusKickIconWidth) or 40
    local h = tonumber(g.focusKickIconHeight) or 40

    if w < 16 then w = 16 end
    if h < 16 then h = 16 end
    if w > 128 then w = 128 end
    if h > 128 then h = 128 end

    FocusKickFrame:SetParent(parent)
    FocusKickFrame:ClearAllPoints()
    FocusKickFrame:SetPoint("CENTER", parent, "CENTER",
        g.focusKickIconOffsetX or 300,
        g.focusKickIconOffsetY or 0
    )
    FocusKickFrame:SetSize(w, h)

    -- Apply global font to time text (if present)
    if FocusKickFrame.timeText then
        local fontPath = (type(MSUF_GetFontPath) == "function") and MSUF_GetFontPath() or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        local flags    = (type(MSUF_GetFontFlags) == "function") and MSUF_GetFontFlags() or "OUTLINE"
        local size = FocusKick_GetDesiredTextSize(g)
        FocusKickFrame.timeText:SetFont(fontPath, size, flags)

        -- Apply the same font to on-screen preview text (if present)
        if FocusKickPreviewFrame and FocusKickPreviewFrame.timeText then
            FocusKickPreviewFrame.timeText:SetFont(fontPath, size, flags)
            FocusKickPreviewFrame.timeText:SetAlpha(1)
            if type(MSUF_GetConfiguredFontColor) == "function" then
                local pr,pg,pb = MSUF_GetConfiguredFontColor()
                if pr and pg and pb then
                    FocusKickPreviewFrame.timeText:SetTextColor(pr, pg, pb, 1)
                end
            end
        end

        if type(MSUF_GetConfiguredFontColor) == "function" then
            local r,g,b = MSUF_GetConfiguredFontColor()
            if r and g and b then
                FocusKickFrame.timeText:SetTextColor(r, g, b, 1)
            end
        end
    end
end

------------------------------------------------------
-- Frame creation
------------------------------------------------------
local function FocusKick_CreateFrame()
    if FocusKickFrame then return end

    FocusKickFrame = CreateFrame("Frame", "MSUF_FocusKickIcon", UIParent, "BackdropTemplate")
    FocusKickFrame:SetFrameStrata("HIGH")
    FocusKickFrame:SetFrameLevel(50)
    FocusKickFrame:Hide()

    -- Zero idle cost: stop timer/fallback updater when frame hides.
    FocusKickFrame:HookScript("OnHide", FocusKick_StopTimeUpdater)

    -- Background
    local bg = FocusKickFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    FocusKickFrame.bg = bg

    -- Icon
    local icon = FocusKickFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    FocusKickFrame.icon = icon

    -- Real per-edge border (4 textures) — sharp clean color regardless of icon
    local function _MakeEdge()
        local t = FocusKickFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetVertexColor(1, 0.2, 0.2, 1)
        return t
    end
    local edgeTop    = _MakeEdge()
    local edgeBottom = _MakeEdge()
    local edgeLeft   = _MakeEdge()
    local edgeRight  = _MakeEdge()
    FocusKickFrame.edges = { edgeTop, edgeBottom, edgeLeft, edgeRight }

    local function _LayoutEdges()
        if not FocusKickFrame then return end
        local thickness = 2
        edgeTop:ClearAllPoints()
        edgeTop:SetPoint("TOPLEFT", FocusKickFrame, "TOPLEFT", 0, 0)
        edgeTop:SetPoint("TOPRIGHT", FocusKickFrame, "TOPRIGHT", 0, 0)
        edgeTop:SetHeight(thickness)

        edgeBottom:ClearAllPoints()
        edgeBottom:SetPoint("BOTTOMLEFT", FocusKickFrame, "BOTTOMLEFT", 0, 0)
        edgeBottom:SetPoint("BOTTOMRIGHT", FocusKickFrame, "BOTTOMRIGHT", 0, 0)
        edgeBottom:SetHeight(thickness)

        edgeLeft:ClearAllPoints()
        edgeLeft:SetPoint("TOPLEFT", FocusKickFrame, "TOPLEFT", 0, 0)
        edgeLeft:SetPoint("BOTTOMLEFT", FocusKickFrame, "BOTTOMLEFT", 0, 0)
        edgeLeft:SetWidth(thickness)

        edgeRight:ClearAllPoints()
        edgeRight:SetPoint("TOPRIGHT", FocusKickFrame, "TOPRIGHT", 0, 0)
        edgeRight:SetPoint("BOTTOMRIGHT", FocusKickFrame, "BOTTOMRIGHT", 0, 0)
        edgeRight:SetWidth(thickness)
    end
    _LayoutEdges()
    FocusKickFrame._LayoutEdges = _LayoutEdges

    -- Cast time text (optional)
    local timeText = FocusKickFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOM", FocusKickFrame, "BOTTOM", 0, 2)
    timeText:SetJustifyH("CENTER")
    timeText:SetText("")
    timeText:SetAlpha(0)
    FocusKickFrame.timeText = timeText
    -- Drag & drop (independent of Edit Mode)
    FocusKickFrame:EnableMouse(true)
    FocusKickFrame:SetMovable(true)
    FocusKickFrame:RegisterForDrag("LeftButton")

    FocusKickFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    FocusKickFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then return end

        local g = MSUF_DB.general
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            g.focusKickIconOffsetX = cx - ux
            g.focusKickIconOffsetY = cy - uy
        end

        FocusKick_UpdateAppearance()
    end)

    FocusKick_UpdateAppearance()
end

------------------------------------------------------
-- Helper: tint the 4 edge textures (ready / cooldown / interrupted)
-- Icon texture stays untouched — multiplicative blending no longer matters.
------------------------------------------------------
local function FocusKick_SetEdgeColor(r, g, b, a)
    if not FocusKickFrame or not FocusKickFrame.edges then return end
    a = a or 1
    for i = 1, #FocusKickFrame.edges do
        local t = FocusKickFrame.edges[i]
        if t and t.SetVertexColor then t:SetVertexColor(r, g, b, a) end
    end
end

local function FocusKick_RefreshReadyColor(isNI, rawNI)
    -- isNI  = plain boolean, event-driven (frame.isNotInterruptible). Always safe.
    -- rawNI = OPTIONAL secret-tagged boolean from UnitCastingInfo.notInterruptible
    --         (frame._msufApiNotInterruptibleRaw). Only the C-side helpers may
    --         observe it. Used to catch casts that are non-interruptible from
    --         the start with no UNIT_SPELLCAST_NOT_INTERRUPTIBLE event firing,
    --         which the plain isNI bool can't see.
    --
    -- The kick-ready bool from MSUF_KickReady_IsReady() is also SECRET-tainted,
    -- so we MUST NOT compare it in Lua. We feed it through the C-side
    -- EvaluateColorFromBoolean in MSUF_KickReady_EvaluateColor, then optionally
    -- compose AGAIN with rawNI to gray-out non-interruptible casts.
    if not FocusKickFrame then return end

    if type(_G.MSUF_KickReady_Init) == "function" then _G.MSUF_KickReady_Init() end

    -- Desaturation only has a plain-bool API; gate on isNI for now. (For
    -- non-event-driven NI casts the icon stays saturated; the edge colour
    -- below still goes gray, which is the dominant visual signal.)
    if FocusKickFrame.icon and FocusKickFrame.icon.SetDesaturated then
        FocusKickFrame.icon:SetDesaturated(isNI == true)
    end

    -- Step 1: indicator colour (green/red) via C-side ready-bool eval.
    local indicatorMix
    if type(_G.MSUF_KickReady_IsReady) == "function"
       and type(_G.MSUF_KickReady_EvaluateColor) == "function" then
        indicatorMix = _G.MSUF_KickReady_EvaluateColor(_G.MSUF_KickReady_IsReady())
    end

    -- Plain-bool fast path: event has confirmed NI, no need for C-side compose.
    if isNI == true then
        FocusKick_SetEdgeColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Step 2 (optional): gate indicator colour with rawNI so casts that are
    -- non-interruptible from the start (no NI event) also go gray.
    if rawNI ~= nil
       and indicatorMix
       and _G.CreateColor
       and _G.C_CurveUtil
       and _G.C_CurveUtil.EvaluateColorFromBoolean then
        local grayMix = _G.CreateColor(0.6, 0.6, 0.6, 1)
        local finalMix = _G.C_CurveUtil.EvaluateColorFromBoolean(rawNI, grayMix, indicatorMix)
        if finalMix and finalMix.GetRGBA then
            local r, g, b, a = finalMix:GetRGBA()
            FocusKick_SetEdgeColor(r, g, b, a)
            return
        end
    end

    if indicatorMix and indicatorMix.GetRGBA then
        local r, g, b, a = indicatorMix:GetRGBA()
        FocusKick_SetEdgeColor(r, g, b, a)
    else
        -- C_CurveUtil unavailable: stay on the cooldown color (red). We
        -- cannot test the boolean to choose, so this is the safe default.
        FocusKick_SetEdgeColor(1.0, 0.2, 0.2, 1)
    end
end

------------------------------------------------------
-- Interrupt feedback: red flash + small shake
------------------------------------------------------
local function FocusKick_PlayInterruptFeedback()
    if not FocusKickFrame or not FocusKickFrame.icon then return end

    -- Flash edges red (icon stays clean)
    FocusKick_SetEdgeColor(1, 0.2, 0.2, 1)

    if FocusKickFrame.bg then
        FocusKickFrame.bg:SetColorTexture(0, 0, 0, 0.9)
    end

    if C_Timer_After then
        C_Timer_After(0.18, function()
            if FocusKickFrame then
                -- Restore based on current ready state
                local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
                local isNI = (bar and bar.isNotInterruptible == true) or false
                local rawNI = bar and bar._msufApiNotInterruptibleRaw
                FocusKick_RefreshReadyColor(isNI, rawNI)
                if FocusKickFrame.bg then
                    FocusKickFrame.bg:SetColorTexture(0, 0, 0, 0.9)
                end
            end
        end)
    end

    -- Small shake
    FocusKick_EnsureDB()
    if not MSUF_DB or not MSUF_DB.general or not C_Timer_After then return end
    local g = MSUF_DB.general

    local offset      = 6
    local steps       = 6
    local timePerStep = 0.02
    local i           = 0

    local function Step()
        if not FocusKickFrame or not FocusKickFrame:IsShown() then return end

        i = i + 1
        local dir = (i % 2 == 0) and -1 or 1

        FocusKickFrame:ClearAllPoints()
        FocusKickFrame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            (g.focusKickIconOffsetX or 300) + dir * offset,
            g.focusKickIconOffsetY or 0
        )

        if i < steps then
            C_Timer_After(timePerStep, Step)
        else
            FocusKick_UpdateAppearance()
        end
    end

    Step()
end

------------------------------------------------------
-- Resolve FocusCastBar reference (no hooks — watcher-driven)
------------------------------------------------------
local function FocusKick_AttachHooks()
    if FocusKick_Hooked then return end

    local bar = _G["FocusCastBar"]
    if not bar then
        if C_Timer_After then
            C_Timer_After(1, FocusKick_AttachHooks)
        end
        return
    end

    FocusKick_FocusCastBar = bar
    FocusKick_Hooked = true
    -- All sync/feedback is handled by the watcher (FocusKick_StartWatcher).
    -- The castbar is permanently hidden (alpha 0) by FocusKick_EnsureInitialized
    -- when the feature is enabled. No hooks needed.
end

------------------------------------------------------
-- Focus cast watcher (works even if FocusCastBar isn't shown / hasn't updated yet)
------------------------------------------------------
local FocusKick_Watcher

local function FocusKick_IsEnabled()
    FocusKick_EnsureDB()

    -- Kill switch: if Focus unitframe is disabled, treat the Focus Kick Icon as disabled.
    if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then
        return false
    end

    return MSUF_DB and MSUF_DB.general and MSUF_DB.general.enableFocusKickIcon
end

local function FocusKick_UpdateTimeText()
    if not FocusKickFrame or not FocusKickFrame.timeText then return end
    if not FocusKickFrame:IsShown() then return end

    -- Secret-safe approach:
    -- Don't compute/compare numbers here (remaining seconds can be 'secret').
    -- Instead, mirror the already-rendered cast time text from the Focus castbar (which is updated elsewhere).
    local src = FocusKickFrame.MSUF_sourceCastBar or _G.FocusCastBar or _G.MSUF_FocusCastBar
    if not src or not src.timeText then
        FocusKickFrame.timeText:SetText("")
        FocusKickFrame.timeText:SetAlpha(0)
        return
    end

    -- Direct calls: GetText/SetText/GetAlpha/SetAlpha are not secret-restricted.
    -- No pcall (MSUF_FastCall) overhead needed here.
    local txt = src.timeText:GetText()
    FocusKickFrame.timeText:SetText(txt or "")
    local a = src.timeText:GetAlpha()
    FocusKickFrame.timeText:SetAlpha(a or 1)
end

local function FocusKick_TimeTickerStep()
    local frame = FocusKickFrame
    if not frame or not frame.MSUF_timeUpdater or not frame:IsShown() then
        if frame then FocusKick_StopTimeUpdater(frame) end
        return
    end

    FocusKick_UpdateTimeText()
end

local function FocusKick_TimeFallbackOnUpdate(self, elapsed)
    if not self:IsShown() then
        FocusKick_StopTimeUpdater(self)
        return
    end
    self.MSUF_timeAccum = (self.MSUF_timeAccum or 0) + (elapsed or 0)
    if self.MSUF_timeAccum < 0.05 then return end
    self.MSUF_timeAccum = 0
    FocusKick_UpdateTimeText()
end

local function FocusKick_EnsureTimeUpdater()
    if not FocusKickFrame then return end
    if FocusKickFrame.MSUF_timeUpdater then return end
    FocusKickFrame.MSUF_timeUpdater = true
    FocusKickFrame.MSUF_timeAccum = 0

    if C_Timer_NewTicker then
        FocusKickFrame.MSUF_timeTicker = C_Timer_NewTicker(0.05, FocusKick_TimeTickerStep)
    else
        -- Legacy fallback only if C_Timer.NewTicker is unavailable.
        FocusKickFrame:SetScript("OnUpdate", FocusKick_TimeFallbackOnUpdate)
    end
end

local function FocusKick_UpdateFromUnit()
    -- Prefer mirroring text from the actual focus castbar (engine-driven), to stay secret-safe
    if FocusKickFrame then
        FocusKickFrame.MSUF_sourceCastBar = _G.FocusCastBar or _G.MSUF_FocusCastBar
    end
    if not FocusKick_IsEnabled() then
        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
        return
    end

    FocusKick_EnsureInitialized(true)
    if not FocusKickFrame then return end

    local isChannel = false
    local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, spellID

    local a,b,c,d,e,f,g,h,i
    if UnitChannelInfo then a,b,c,d,e,f,g,h,i = UnitChannelInfo("focus") end
    if a then
        isChannel = true
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, _, spellID = a,b,c,d,e,f,g,h,i
    else
        if UnitCastingInfo then a,b,c,d,e,f,g,h,i = UnitCastingInfo("focus") end
        if a then
            name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, _, spellID = a,b,c,d,e,f,g,h,i
        else
            -- No cast/channel on focus
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
            return
        end
    end

    -- Cache end time (seconds) for cheap updates
    FocusKickFrame.MSUF_castEnd = nil
    if endTimeMS ~= nil then
        local endSec = endTimeMS / 1000
        if type(endSec) == "number" then
            FocusKickFrame.MSUF_castEnd = endSec
        end
    end

    -- Cache duration object if available (helps with "snappy end" / secret-safe)
    FocusKickFrame.MSUF_durObj = nil
    if isChannel and UnitChannelDuration then
        local obj = UnitChannelDuration("focus")
        if obj then FocusKickFrame.MSUF_durObj = obj end
    elseif (not isChannel) and UnitCastingDuration then
        local obj = UnitCastingDuration("focus")
        if obj then FocusKickFrame.MSUF_durObj = obj end
    end

    -- Icon texture: prefer UnitCastingInfo/UnitChannelInfo texture, fall back to FocusCastBar icon if needed
    if not texture then
        local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
        local tex = bar and bar.icon and bar.icon.GetTexture and bar.icon:GetTexture()
        if tex then texture = tex end
    end
    if texture and FocusKickFrame.icon then
        FocusKickFrame.icon:SetTexture(texture)
    end

    -- Kick ready coloring: tint the 4-edge border (NOT the icon vertex color),
    -- so the visual is unaffected by the underlying spell texture's hue.
    if FocusKickFrame then
        if _G.MSUF_KickReady_Init then _G.MSUF_KickReady_Init() end
        -- Use cleansed plain boolean from the castbar frame (event-driven).
        local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
        local isNI = (bar and bar.isNotInterruptible == true) or false
        local rawNI = bar and bar._msufApiNotInterruptibleRaw
        FocusKick_RefreshReadyColor(isNI, rawNI)
        FocusKickFrame._msufLastCastState = { active = true, isNotInterruptible = isNI }
    end

FocusKickFrame:Show()
    FocusKick_UpdateAppearance()
    FocusKick_EnsureTimeUpdater()
    FocusKick_UpdateTimeText()
end

local function FocusKick_StartWatcher()
    if FocusKick_Watcher then
        -- ensure registered (in case it was stopped)
        FocusKick_Watcher:UnregisterAllEvents()
    else
        FocusKick_Watcher = CreateFrame("Frame")
    end

    FocusKick_Watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
    FocusKick_Watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    FocusKick_Watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "focus")
    FocusKick_Watcher:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "focus")

    FocusKick_Watcher:SetScript("OnEvent", function(self, event, unit)
        -- Interrupt feedback: play animation BEFORE UpdateFromUnit hides the icon.
        if event == "UNIT_SPELLCAST_INTERRUPTED" and unit == "focus" then
            if FocusKick_IsEnabled() and FocusKickFrame and FocusKickFrame:IsShown() then
                FocusKick_PlayInterruptFeedback()
            end
        end
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- Cheap path: only repaint edges (no full UpdateFromUnit), only if the icon
            -- is currently visible during a cast.
            if FocusKickFrame and FocusKickFrame:IsShown() then
                local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
                local isNI = (bar and bar.isNotInterruptible == true) or false
                local rawNI = bar and bar._msufApiNotInterruptibleRaw
                FocusKick_RefreshReadyColor(isNI, rawNI)
            end
            return
        end
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Spec change: re-resolve the interrupt spell, then refresh edges.
            if _G.MSUF_KickReady_Init then _G.MSUF_KickReady_Init() end
            if FocusKickFrame and FocusKickFrame:IsShown() then
                local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
                local isNI = (bar and bar.isNotInterruptible == true) or false
                local rawNI = bar and bar._msufApiNotInterruptibleRaw
                FocusKick_RefreshReadyColor(isNI, rawNI)
            end
            return
        end
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Interruptibility changed mid-cast: just repaint, do not rebuild.
            if FocusKickFrame and FocusKickFrame:IsShown() then
                local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]
                local isNI = (event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
                if bar then bar.isNotInterruptible = isNI end
                -- Mirror onto the secret-tagged raw flag too so the C-side compose path matches the event.
                if bar then bar._msufApiNotInterruptibleRaw = isNI end
                local rawNI = bar and bar._msufApiNotInterruptibleRaw
                FocusKick_RefreshReadyColor(isNI, rawNI)
            end
            return
        end
        if event == "PLAYER_FOCUS_CHANGED" or unit == "focus" then
            FocusKick_UpdateFromUnit()
        end
    end)

    -- Initial sync
    if C_Timer_After then
        C_Timer_After(0.05, FocusKick_UpdateFromUnit)
    else
        FocusKick_UpdateFromUnit()
    end
end

local function FocusKick_StopWatcher()
    if FocusKick_Watcher then
        FocusKick_Watcher:UnregisterAllEvents()
        FocusKick_Watcher:SetScript("OnEvent", nil)
    end

    FocusKick_StopTimeUpdater(FocusKickFrame)
end

------------------------------------------------------
-- Enable / disable mode
------------------------------------------------------
local function FocusKick_UpdateMode()
    FocusKick_EnsureDB()

    -- If the Castbar Engine driver is active, keep this module UI-only.
    -- The driver will call MSUF_FocusKick_ApplyCastState().
    if _G.MSUF_FocusKickUseEngineDriver then
        if not MSUF_DB or not MSUF_DB.general then return end

        local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]

        if FocusKick_IsEnabled() then
            FocusKick_CreateFrame()
            FocusKick_UpdateAppearance()

            -- Hide the focus castbar visually but keep it running (we mirror its time text).
            if bar then
                bar:SetAlpha(0)
            end

            if _G.MSUF_FocusKickDriver_ForceUpdate then
                _G.MSUF_FocusKickDriver_ForceUpdate()
            end
        else
            -- Restore bar + hide icon.
            if bar then
                bar:SetAlpha(1)
            end
            FocusKick_StopWatcher()
            if FocusKickFrame then
                if FocusKickFrame.timeText then
                    FocusKickFrame.timeText:SetText("")
                    FocusKickFrame.timeText:SetAlpha(0)
                end
                FocusKickFrame:Hide()
            end
        end

        return
    end

    FocusKick_AttachHooks()

    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general

    local bar = FocusKick_FocusCastBar or _G["FocusCastBar"]

    if FocusKick_IsEnabled() then
        FocusKick_CreateFrame()
        FocusKick_UpdateAppearance()

        -- If we have the MSUF focus castbar, hide it visually (alpha 0) but keep it functional
        if bar then
            bar:SetAlpha(0)
        end

        -- Watch focus casting directly so the timer works even if the bar never "woke up"
        FocusKick_StartWatcher()
        FocusKick_UpdateFromUnit()
    else
        FocusKick_StopWatcher()

        if bar then
            bar:SetAlpha(1)
        end

        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
    end
end

------------------------------------------------------
-- On-screen preview
-- Session-only toggle: shows a draggable preview icon on UIParent.
-- Sync: DB <-> preview <-> runtime apply.
------------------------------------------------------
-- Clamp range mirrors the Menu2 sliders.
local FocusKickPreviewMinX, FocusKickPreviewMaxX = -500, 500
local FocusKickPreviewMinY, FocusKickPreviewMaxY = -500, 500

local function FocusKick_PrintSystem(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2, 1)
        return
    end
    local f = DEFAULT_CHAT_FRAME
    if f and f.AddMessage then
        f:AddMessage(msg)
    else
        print(msg)
    end
end

local function FocusKick_Round(v)
    if not v then return 0 end
    if v >= 0 then
        return math.floor(v + 0.5)
    else
        return math.ceil(v - 0.5)
    end
end

local function FocusKick_Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Forward decl (referenced by preview drag handlers)
local MSUF_FocusKick_SyncPreviewFromDB

local function FocusKick_GetNudgeStep()
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    return 1
end

local function FocusKick_IsTextInputFocused()
    local getFocus = _G.GetCurrentKeyBoardFocus
    local focus = getFocus and getFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end

local function FocusKick_SelectPreview(selected)
    FocusKickPreviewSelected = selected and true or false
    if FocusKickPreviewFrame and FocusKickPreviewFrame._selBorder then
        FocusKickPreviewFrame._selBorder:SetShown(FocusKickPreviewSelected)
    end
end

local function FocusKick_NudgePreview(dx, dy)
    if not FocusKickPreviewEnabled or not FocusKickPreviewSelected then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    FocusKick_EnsureDB()
    local gg = MSUF_DB and MSUF_DB.general
    if not gg then return false end

    gg.focusKickIconOffsetX = FocusKick_Clamp(
        FocusKick_Round((tonumber(gg.focusKickIconOffsetX) or 0) + (dx or 0)),
        FocusKickPreviewMinX, FocusKickPreviewMaxX)
    gg.focusKickIconOffsetY = FocusKick_Clamp(
        FocusKick_Round((tonumber(gg.focusKickIconOffsetY) or 0) + (dy or 0)),
        FocusKickPreviewMinY, FocusKickPreviewMaxY)

    FocusKick_UpdateAppearance()
    if MSUF_FocusKick_SyncPreviewFromDB then
        MSUF_FocusKick_SyncPreviewFromDB()
    end
    FocusKick_SelectPreview(true)
    return true
end

local function FocusKick_EnsurePreviewFrame()
    if FocusKickPreviewFrame then return end

    local f = CreateFrame("Frame", "MSUF_FocusKickPreviewFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(70)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
    f:RegisterForDrag("LeftButton")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.icon = icon

    local sel = f:CreateTexture(nil, "OVERLAY")
    sel:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    sel:SetColorTexture(0.27, 0.53, 0.80, 0.45)
    sel:Hide()
    f._selBorder = sel

    -- Preview cast-time text (always visible; fake timer while preview is shown)
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
    timeText:SetJustifyH("CENTER")
    timeText:SetText("5.0")
    timeText:SetAlpha(1)
    f.timeText = timeText

    -- Lightweight fake timer using an AnimationGroup (no new OnUpdate loops/tickers outside preview)
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anim = ag:CreateAnimation("Animation")
    anim:SetOrder(1)
    anim:SetDuration(0.08)

    local acc = 0
    local period = 8.0

    anim:SetScript("OnUpdate", function(_, elapsed)
        if not f:IsShown() then return end
        acc = acc + (elapsed or 0)
        if acc < 0.08 then return end
        acc = 0

        local t = GetTime and GetTime() or 0
        local rem = period - (t % period)
        if rem < 0 then rem = 0 end
        if f.timeText and f.timeText.SetText then
            f.timeText:SetText(string.format("%.1f", rem))
        end
    end)

    f._msufFakeTimerAG = ag

    f:Hide()

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            FocusKick_SelectPreview(true)
        end
    end)

    f:SetScript("OnKeyDown", function(self, key)
        local dx, dy = 0, 0
        if key == "LEFT" then
            dx = -1
        elseif key == "RIGHT" then
            dx = 1
        elseif key == "UP" then
            dy = 1
        elseif key == "DOWN" then
            dy = -1
        else
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end

        if FocusKick_IsTextInputFocused() or not FocusKickPreviewSelected then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
            return
        end

        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        local step = FocusKick_GetNudgeStep()
        if not FocusKick_NudgePreview(dx * step, dy * step) then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        end
    end)

    f:SetScript("OnHide", function(self)
        FocusKick_SelectPreview(false)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)

    f:SetScript("OnDragStart", function(self)
        if not FocusKickPreviewEnabled then return end
        if InCombatLockdown and InCombatLockdown() then
            FocusKick_PrintSystem("In combat - cannot move Focus Interrupt Tracker preview.")
            return
        end
        FocusKick_SelectPreview(true)
        self:StartMoving()
    end)

    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not FocusKickPreviewEnabled then return end

        FocusKick_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then
            if MSUF_FocusKick_SyncPreviewFromDB then
                MSUF_FocusKick_SyncPreviewFromDB()
            end
            return
        end

        local px, py = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not px or not py or not ux or not uy then
            if MSUF_FocusKick_SyncPreviewFromDB then
                MSUF_FocusKick_SyncPreviewFromDB()
            end
            return
        end

        local newOffX = FocusKick_Round(px - ux)
        local newOffY = FocusKick_Round(py - uy)

        newOffX = FocusKick_Clamp(newOffX, FocusKickPreviewMinX, FocusKickPreviewMaxX)
        newOffY = FocusKick_Clamp(newOffY, FocusKickPreviewMinY, FocusKickPreviewMaxY)

        MSUF_DB.general.focusKickIconOffsetX = newOffX
        MSUF_DB.general.focusKickIconOffsetY = newOffY

        FocusKick_UpdateAppearance()
        if MSUF_FocusKick_SyncPreviewFromDB then
            MSUF_FocusKick_SyncPreviewFromDB()
        end
        FocusKick_SelectPreview(true)
    end)

    FocusKickPreviewFrame = f
    FocusKick_ApplyTimeTextFontNow()
end

local function FocusKick_SetPreviewEnabled(enabled)
    FocusKickPreviewEnabled = enabled and true or false
    FocusKick_EnsurePreviewFrame()

    if not FocusKickPreviewFrame then return end

    if not FocusKickPreviewEnabled then
        if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Stop then
            FocusKickPreviewFrame._msufFakeTimerAG:Stop()
        end
        FocusKick_SelectPreview(false)
        FocusKickPreviewFrame:Hide()
        return
    end

    FocusKick_EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or {}
    if not (gg.enableFocusKickIcon and true or false) then
        FocusKickPreviewEnabled = false
        if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Stop then
            FocusKickPreviewFrame._msufFakeTimerAG:Stop()
        end
        FocusKick_SelectPreview(false)
        FocusKickPreviewFrame:Hide()
        FocusKick_PrintSystem("Enable Focus Interrupt Tracker first to use the on-screen preview.")
        return
    end

    FocusKickPreviewFrame:Show()
    if FocusKickPreviewFrame._msufFakeTimerAG and FocusKickPreviewFrame._msufFakeTimerAG.Play then
        FocusKickPreviewFrame._msufFakeTimerAG:Play()
    end
    if MSUF_FocusKick_SyncPreviewFromDB then
        MSUF_FocusKick_SyncPreviewFromDB()
    end
end

-- Central sync: DB <-> preview
MSUF_FocusKick_SyncPreviewFromDB = function()
    FocusKick_EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or {}

    if FocusKickPreviewEnabled then
        FocusKick_EnsurePreviewFrame()
        if FocusKickPreviewFrame then
            local parent = UIParent
            local offX = gg.focusKickIconOffsetX or 0
            local offY = gg.focusKickIconOffsetY or 0

            local w = tonumber(gg.focusKickIconWidth) or 40
            local h = tonumber(gg.focusKickIconHeight) or 40
            if w < 16 then w = 16 end
            if h < 16 then h = 16 end
            if w > 128 then w = 128 end
            if h > 128 then h = 128 end

            FocusKickPreviewFrame:SetParent(parent)
            FocusKickPreviewFrame:ClearAllPoints()
            FocusKickPreviewFrame:SetPoint("CENTER", parent, "CENTER", offX, offY)
            FocusKickPreviewFrame:SetSize(w, h)

            if FocusKickPreviewFrame.icon then
                local tex = (FocusKickFrame and FocusKickFrame.icon and FocusKickFrame.icon.GetTexture and FocusKickFrame.icon:GetTexture()) or "Interface\\Icons\\INV_Misc_QuestionMark"
                FocusKickPreviewFrame.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            end

            FocusKick_ApplyTimeTextFontNow()
            FocusKickPreviewFrame:Show()
        end
    elseif FocusKickPreviewFrame then
        FocusKickPreviewFrame:Hide()
    end
end


------------------------------------------------------
-- Public API for main file
------------------------------------------------------
local FocusKick_Bootstrapped = false
local function FocusKick_EnsureInitialized(forceFrame)
    FocusKick_EnsureDB()
    if not FocusKick_Bootstrapped then
        FocusKick_AttachHooks()
        FocusKick_Bootstrapped = true
    end
    if forceFrame then
        FocusKick_CreateFrame()
        FocusKick_UpdateAppearance()
        FocusKick_UpdateMode()
    end
end
_G.MSUF_FocusKick_EnsureInitialized = FocusKick_EnsureInitialized

local function FocusKick_EnsureRuntimeFrame()
    -- Driver apply path must not run UpdateMode(), because UpdateMode() can
    -- request a driver refresh and create an eventless C_Timer.After(0) loop.
    FocusKick_EnsureInitialized(false)
    FocusKick_CreateFrame()
end

function MSUF_InitFocusKickIcon()
    FocusKick_EnsureInitialized(FocusKick_IsEnabled())
end

function MSUF_UpdateFocusKickIconOptions()
    FocusKick_EnsureInitialized(FocusKick_IsEnabled())
    if FocusKickFrame then
        FocusKick_UpdateAppearance()
        FocusKick_UpdateMode()
    end
    if MSUF_FocusKick_SyncPreviewFromDB then
        MSUF_FocusKick_SyncPreviewFromDB()
    end
end

------------------------------------------------------
-- Exports for the Menu2 castbar page
------------------------------------------------------
_G.MSUF_FocusKick_SetPreviewEnabled = FocusKick_SetPreviewEnabled
_G.MSUF_FocusKick_IsPreviewEnabled  = function() return FocusKickPreviewEnabled end
_G.MSUF_FocusKick_UpdateAppearance  = FocusKick_UpdateAppearance
_G.MSUF_FocusKick_ApplyTimeTextFont = FocusKick_ApplyTimeTextFontNow

------------------------------------------------------
-- Engine-driver API (used by Castbars/MSUF_FocusKick_StateDriver.lua)
------------------------------------------------------
function _G.MSUF_FocusKick_ApplyCastState(state)
    FocusKick_EnsureDB()

    if not FocusKick_IsEnabled() then
        if FocusKickFrame then
            if FocusKickFrame.timeText then
                FocusKickFrame.timeText:SetText("")
                FocusKickFrame.timeText:SetAlpha(0)
            end
            FocusKickFrame:Hide()
        end
        return
    end

    FocusKick_EnsureRuntimeFrame()
    if not FocusKickFrame then return end

    if not state or state.active ~= true then
        if FocusKickFrame.timeText then
            FocusKickFrame.timeText:SetText("")
            FocusKickFrame.timeText:SetAlpha(0)
        end
        FocusKickFrame:Hide()
        return
    end

    if FocusKickFrame.icon and state.icon then
        FocusKickFrame.icon:SetTexture(state.icon)
    end

    -- Kick ready coloring: tint the 4-edge border (NOT the icon vertex color),
    -- so the visual is unaffected by the underlying spell texture's hue.
    if FocusKickFrame then
        if _G.MSUF_KickReady_Init then _G.MSUF_KickReady_Init() end
        local isNI = (state.isNotInterruptible == true)
        local rawNI = state.apiNotInterruptibleRaw
        FocusKick_RefreshReadyColor(isNI, rawNI)
        -- Cache state for cooldown-driven refresh
        FocusKickFrame._msufLastCastState = state
    end

    FocusKickFrame:Show()
    FocusKick_UpdateAppearance()
    FocusKick_EnsureTimeUpdater()
    FocusKick_UpdateTimeText()
end

function _G.MSUF_FocusKick_PlayInterruptFeedback()
    FocusKick_EnsureDB()
    if not FocusKick_IsEnabled() then return end
    FocusKick_EnsureRuntimeFrame()
    FocusKick_PlayInterruptFeedback()
end

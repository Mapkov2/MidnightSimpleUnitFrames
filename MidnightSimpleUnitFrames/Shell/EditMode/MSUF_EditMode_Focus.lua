--- EditMode/MSUF_EditMode_Focus.lua - shared Edit Mode focus, hover, and Menu2 state.
--- Owns visual focus/highlight bookkeeping between edit-mode movers, quick popups, and Menu2.
--- It should not save positions directly; drag/commit code owns persistent layout writes.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Focus = EM2.Focus or {}
EM2.Focus = Focus

local max = math.max
local floor = math.floor
local W8 = "Interface/Buttons/WHITE8X8"
local U = EM2.Util or {}

local function Menu2Theme()
    local M2 = (type(MSUF) == "table" and MSUF.MSUF2) or _G.MSUF2
    return (type(M2) == "table" and type(M2.Theme) == "table") and M2.Theme or nil
end

local function ThemeColor(key, fallback)
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.Color then return ui.Color(key, fallback) end
    local T = Menu2Theme()
    return (T and T.colors and T.colors[key]) or fallback
end

local function PlayFocusMotion(frame, motion, opts)
    local T = Menu2Theme()
    if T and T.PlayMotion then
        return T.PlayMotion(frame, motion, opts)
    end
    opts = opts or {}
    if frame and frame.SetAlpha then frame:SetAlpha(opts.toAlpha or 1) end
    if type(opts.onFinished) == "function" then opts.onFinished(frame) end
end

local state = {
    active = false,
    key = nil,
    component = nil,
    slot = nil,
    popupKey = nil,
    hoverKey = nil,
    hoverComponent = nil,
    hoverSlot = nil,
    nextHUDRefresh = 0,
}

local hoverFrame

local GROUP_KIND_BY_KEY = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
}

local function PrioritySection(component)
    if component == "placement" or component == "layout" or component == "anchor"
        or component == "frame" or component == "bounds" or component == "size" then
        return "placement"
    end
    return "overview"
end

local NormalizeKey = U.NormalizeFocusKey
local NormalizeComponent = U.NormalizeFocusComponent
local NormalizeSlot = U.NormalizeFocusSlot
local UnitPageKey = U.UnitPageKey or function(unit) return unit == "player" and "uf_player" or false end

local function IsEditActive()
    return EM2.State and EM2.State.IsActive and EM2.State.IsActive()
end

local function IsPopupOpen()
    if EM2.Popups and EM2.Popups.IsAnyOpen then
        return EM2.Popups.IsAnyOpen() == true
    end
    local st = _G.MSUF_EditState
    return st and st.popupOpen == true or false
end

local function HideLegacyInspector()
    local inspector = _G.MSUF_EM2_Inspector
    if inspector and inspector.Hide then
        inspector:Hide()
        if inspector.SetAlpha then inspector:SetAlpha(0) end
    end
end

local function HideOldFocusLayer()
    local old = _G.MSUF_EM2_FocusLayer
    if old and old.Hide then old:Hide() end
end

local function Menu2()
    return _G.MSUF2 or (MSUF and MSUF.MSUF2)
end

local function PersistMenuValue(M, key, value)
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(key, value)
    end
end

local UnitSectionForComponent = U.UnitSectionForComponent

local function GroupPageForComponent(component)
    if component == "dispel" or component == "stripe" or component == "dstripe" then return "gf_bars" end
    if component == "auras" then return "gf_auras" end
    if component == "status" or component == "indicators" or component == "sicons" then return "gf_indicators" end
    return "gf_layout"
end

local function GroupSectionForComponent(pageKey, component)
    pageKey = pageKey or GroupPageForComponent(component)
    if pageKey == "gf_bars" then
        if component == "dispel" then return "dispel" end
        if component == "stripe" or component == "dstripe" then return "dstripe" end
        return "dispel"
    elseif pageKey == "gf_auras" then
        if component == "debuffs" or component == "debuff" then return "debuffs" end
        if component == "ext" or component == "externals" or component == "external" then return "ext" end
        return "buffs"
    elseif pageKey == "gf_indicators" then
        if component == "status" or component == "sicons" then return "sicons" end
        if component == "spells" or component == "si" then return "si" end
        if component == "corners" or component == "ci" then return "ci" end
        return "indicators"
    end
    if component == "portrait" then return "portrait" end
    if component == "power" then return "power" end
    if component == "name" or component == "hp" or component == "text" then return "text" end
    if component == "range" then return "range" end
    if component == "bars" then return "general" end
    if component == "anchor" or component == "anchoring" then return "anchor" end
    if component == "tooltip" then return "tooltip" end
    if component == "sorting" or component == "sort" then return "sorting" end
    if component == "scale" or component == "scaling" then return "scaling" end
    if component == "border" or component == "alpha" or component == "transparency" then return "transparency" end
    if component == "general" then return "general" end
    return "layout_advanced"
end

local function ClearPassiveMenuFocusRequest()
    local req = _G.MSUF_EM2_MenuFocusRequest
    if type(req) == "table" and req.explicit ~= true then
        ExportPublic("MSUF_EM2_MenuFocusRequest", nil)
    end
end

local function ApplyMenuSelection(key, component, slot, opts)
    opts = opts or {}
    key = NormalizeKey(key)
    component = NormalizeComponent(component)
    slot = NormalizeSlot(slot)
    if not key then return nil end

    local M = Menu2()
    local pageKey
    local sectionId
    local unitPage = UnitPageKey(key, false)
    local priorityPage = key == "gf_priority"
    if priorityPage then
        pageKey = "gf_priority"
        sectionId = PrioritySection(component)
    elseif unitPage then
        pageKey = unitPage
        sectionId = UnitSectionForComponent(component)
    else
        local groupKind = GROUP_KIND_BY_KEY[key]
        if groupKind then
            pageKey = GroupPageForComponent(component)
            sectionId = GroupSectionForComponent(pageKey, component)
        end
    end

    if opts.focusRequest == true then
        ExportPublic("MSUF_EM2_MenuFocusRequest", {
            key = key,
            component = component,
            slot = slot,
            pageKey = pageKey,
            sectionId = sectionId,
            source = opts.source,
            explicit = true,
            changedAt = GetTime and GetTime() or 0,
        })
    else
        ClearPassiveMenuFocusRequest()
    end

    if not M then return pageKey end

    M.editModeSelection = {
        key = key,
        component = component,
        slot = slot,
        pageKey = pageKey,
        sectionId = sectionId,
    }

    -- Priority Frames are profile-wide and intentionally do not participate in
    -- the Party/Raid/Mythic scope selector.
    if priorityPage then return pageKey end

    if unitPage then
        if component == "name" or component == "hp" or component == "power" then
            if opts.focusRequest == true or opts.syncTextState == true then
                U.SyncUnitTextMenuState(M, key, component, slot)
            end
        end
        return pageKey
    end

    local groupKind = GROUP_KIND_BY_KEY[key]
    if groupKind then
        if opts.focusRequest == true or opts.syncGroupScope == true then
            M.gfScope = groupKind
            PersistMenuValue(M, "gfScope", groupKind)
        end
        return pageKey
    end

    return nil
end

local function OpenMenuPage(pageKey)
    local M = Menu2()
    if M and pageKey and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        _G.MSUF_OpenStandaloneOptionsWindow(pageKey)
        return true
    elseif type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage(pageKey)
        return true
    elseif M and type(M.Open) == "function" then
        M.Open(pageKey)
        return true
    elseif M and type(M.SelectPage) == "function" then
        M.SelectPage(pageKey)
        return true
    end
    return false
end

local function PlaceAroundFrame(veil, frame)
    if not (veil and frame and frame.GetLeft) then return false end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return false end
    local uiScale = UIParent:GetEffectiveScale() or 1
    if uiScale == 0 then uiScale = 1 end
    local frameScale = frame.GetEffectiveScale and (frame:GetEffectiveScale() or uiScale) or uiScale
    local ratio = frameScale / uiScale
    local x = floor(l * ratio + 0.5)
    local y = floor(t * ratio - UIParent:GetHeight() + 0.5)
    local w = max(2, floor((r - l) * ratio + 0.5))
    local h = max(2, floor((t - b) * ratio + 0.5))
    local uiW = UIParent:GetWidth() or 0
    local uiH = UIParent:GetHeight() or 0
    if uiW > 0 and uiH > 0 and (w > uiW * 0.70 or h > uiH * 0.70 or (w * h) > (uiW * uiH * 0.35)) then
        return false
    end
    veil:ClearAllPoints()
    veil:SetSize(w, h)
    veil:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    return true
end

local function HideVeils()
    HideLegacyInspector()
end

local function EnsureHoverFrame()
    if hoverFrame then return hoverFrame end
    hoverFrame = CreateFrame("Frame", "MSUF_EM2_HoverPreviewRing", UIParent, "BackdropTemplate")
    hoverFrame:SetFrameStrata("FULLSCREEN")
    hoverFrame:SetFrameLevel(512)
    hoverFrame:EnableMouse(false)
    hoverFrame:SetBackdrop({ edgeFile = W8, edgeSize = 1 })
    local accent = ThemeColor("accent", { 0.18, 0.72, 0.90, 1 })
    hoverFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.50)
    hoverFrame:SetAlpha(0)
    hoverFrame:Hide()

    hoverFrame.fill = hoverFrame:CreateTexture(nil, "BACKGROUND")
    hoverFrame.fill:SetPoint("TOPLEFT", 1, -1)
    hoverFrame.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    hoverFrame.fill:SetColorTexture(accent[1], accent[2], accent[3], 0.040)
    return hoverFrame
end

local function HideHover()
    if hoverFrame then
        if hoverFrame.IsShown and not hoverFrame:IsShown() then
            hoverFrame._msufHiding = nil
            hoverFrame:ClearAllPoints()
            hoverFrame:SetAlpha(0)
            return
        end
        hoverFrame._msufFocusToken = (hoverFrame._msufFocusToken or 0) + 1
        local token = hoverFrame._msufFocusToken
        hoverFrame._msufHiding = true
        PlayFocusMotion(hoverFrame, "controlFocusOut", {
            fromAlpha = hoverFrame.GetAlpha and hoverFrame:GetAlpha() or 1,
            toAlpha = 0,
            duration = 0.080,
            onFinished = function(frame)
                if frame._msufFocusToken ~= token then return end
                frame._msufHiding = nil
                frame:Hide()
                frame:SetAlpha(0)
                frame:ClearAllPoints()
            end,
        })
    end
end

local function SyncVeil()
    HideLegacyInspector()
    HideOldFocusLayer()
    HideVeils()
    return false
end

function Focus.GetSelection()
    return state.key, state.component, state.slot
end

function Focus.SetSelection(key, component, slot, opts)
    opts = opts or {}
    state.key = NormalizeKey(key)
    state.component = NormalizeComponent(component)
    state.slot = NormalizeSlot(slot)
    ExportPublic("MSUF_EM2_Selection", {
        key = state.key,
        component = state.component,
        slot = state.slot,
        source = opts.source,
        changedAt = GetTime and GetTime() or 0,
    })
    local cfg = state.key and EM2.Registry and EM2.Registry.Get(state.key) or nil
    if cfg and cfg.externalPublicElement == true then opts.menu = false end
    if opts.menu ~= false then
        ApplyMenuSelection(state.key, state.component, state.slot, {
            source = opts.source,
            focusRequest = opts.menuFocus == true or opts.openSettings == true,
        })
    else
        ClearPassiveMenuFocusRequest()
    end
    HideLegacyInspector()
    if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
    return state.key ~= nil
end

function Focus.SetHover(key, component, slot, opts)
    opts = opts or {}
    if not IsEditActive() then
        HideHover()
        return false
    end
    state.hoverKey = NormalizeKey(key)
    state.hoverComponent = NormalizeComponent(component)
    state.hoverSlot = NormalizeSlot(slot)
    HideLegacyInspector()
    if not state.hoverKey then
        HideHover()
        return false
    end

    local mover = EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(state.hoverKey)
    if not (mover and mover.IsShown and mover:IsShown()) then
        HideHover()
        return false
    end

    local ring = EnsureHoverFrame()
    if not opts.force
        and ring:IsShown()
        and ring._msufKey == state.hoverKey
        and ring._msufComponent == state.hoverComponent
        and ring._msufSlot == state.hoverSlot
        and not ring._msufHiding
    then
        return true
    end
    if PlaceAroundFrame(ring, mover) then
        local wasShown = ring.IsShown and ring:IsShown()
        ring._msufFocusToken = (ring._msufFocusToken or 0) + 1
        ring._msufHiding = nil
        ring._msufKey = state.hoverKey
        ring._msufComponent = state.hoverComponent
        ring._msufSlot = state.hoverSlot
        if not wasShown and ring.SetAlpha then ring:SetAlpha(0) end
        ring:Show()
        PlayFocusMotion(ring, "controlFocusIn", {
            fromAlpha = ring.GetAlpha and ring:GetAlpha() or 0,
            toAlpha = 1,
            duration = 0.085,
        })
        return true
    end
    HideHover()
    return false
end

function Focus.ClearHover()
    state.hoverKey = nil
    state.hoverComponent = nil
    state.hoverSlot = nil
    HideLegacyInspector()
    if hoverFrame then
        hoverFrame._msufKey = nil
        hoverFrame._msufComponent = nil
        hoverFrame._msufSlot = nil
    end
    HideHover()
end

function Focus.Pulse(key, component, slot, opts)
    opts = opts or {}
    key = NormalizeKey(key)
    component = NormalizeComponent(component)
    slot = NormalizeSlot(slot)
    if not key then return false end
    local ok = Focus.SetHover(key, component, slot, {
        source = opts.source or "pulse",
        force = true,
    })
    if not ok then return false end
    state.pulseToken = (state.pulseToken or 0) + 1
    local token = state.pulseToken
    local duration = tonumber(opts.duration) or 0.30
    local function ClearPulse()
        if state.pulseToken ~= token then return end
        if state.hoverKey == key and state.hoverComponent == component and state.hoverSlot == slot then
            Focus.ClearHover()
        end
    end
    C_Timer.After(duration, ClearPulse)
    return true
end

function Focus.SetPopupFocus(key)
    state.popupKey = NormalizeKey(key)
    return SyncVeil()
end

function Focus.ClearPopupFocus()
    state.popupKey = nil
    HideVeils()
end

function Focus.RefreshPopupFocus()
    if not IsPopupOpen() then state.popupKey = nil end
    return SyncVeil()
end

function Focus.NotifyPositionChanged(_, immediate)
    local menu = Menu2()
    if menu and type(menu.RefreshVisibleSliders) == "function" then
        menu.RefreshVisibleSliders("EDIT_MODE_POSITION_CHANGED")
    end
    local now = GetTime and GetTime() or 0
    if EM2.HUD and EM2.HUD.RefreshControls and (immediate == true or now >= (state.nextHUDRefresh or 0)) then
        state.nextHUDRefresh = now + 0.05
        EM2.HUD.RefreshControls()
    end
    if EM2.ExternalPopup and EM2.ExternalPopup.IsOpen and EM2.ExternalPopup.IsOpen()
        and (immediate == true or now >= (state.nextExternalPopupRefresh or 0)) then
        state.nextExternalPopupRefresh = now + 0.05
        EM2.ExternalPopup.Sync()
    end
    if immediate == true or (state.popupKey and IsPopupOpen()) then
        return SyncVeil()
    end
    return false
end

--- Quick popups write settings straight into SavedVariables, so an open Menu2 page
--- keeps painting the pre-edit values until it is rebuilt. The narrow slider route
--- used by drags is not enough here: a value write also moves paired dropdowns and
--- enable gates (a manual castbar width clears the width source, which flips Width
--- mode back to "manual" and re-enables that slider), and those only live in the
--- page's refresher list. Positions keep the cheaper Focus.NotifyPositionChanged.
---
--- This refreshes synchronously on purpose. The debounced Menu2 route would leave a
--- queued timer behind that can fire after PLAYER_REGEN_DISABLED, and every caller
--- here is already fail-closed on combat, so the work belongs in the same frame as
--- the write - that keeps the combat cost of this route at exactly zero.
--- M.Refresh resolves the page through M.cache, which InvalidatePage clears, so a
--- torn-down page resolves to nothing instead of repainting released widgets.
function Focus.NotifySettingChanged()
    local menu = Menu2()
    if not (menu and type(menu.Refresh) == "function") then return false end
    menu.Refresh(nil)
    return true
end

function Focus.Show(key)
    state.active = true
    if key then state.key = NormalizeKey(key) end
    return SyncVeil()
end

function Focus.Hide()
    state.active = false
    state.popupKey = nil
    Focus.ClearHover()
    HideVeils()
end

function Focus.Sync()
    state.active = IsEditActive()
    return SyncVeil()
end

function Focus.NudgeSelection()
    return false
end

function Focus.ResetPosition()
    return false
end

function Focus.OpenFullSettings(pageKey)
    local key = state.key or state.popupKey
    if not key and EM2.State and EM2.State.GetUnitKey then key = EM2.State.GetUnitKey() end
    local cfg = key and EM2.Registry and EM2.Registry.Get(key) or nil
    if cfg and cfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        --- Named source: selection-adjacent routes (HUD chip / full-settings
        --- shortcut) funnel through here, and owners may treat them differently
        --- from the popup's explicit Open settings button.
        return external and type(external.OpenSettings) == "function"
            and external.OpenSettings(key, "focus-full-settings") == true or false
    end
    local resolvedPage = ApplyMenuSelection(key, state.component, state.slot, { source = "open-settings", focusRequest = true })
    return OpenMenuPage(pageKey or resolvedPage or "uf_player")
end

local function SetFocusSelection(key, component, slot, opts)
    return Focus.SetSelection(key, component, slot, opts)
end
ExportPublic("MSUF_EM2_SetFocusSelection", SetFocusSelection)

local function SetFocusHover(key, component, slot, opts)
    return Focus.SetHover(key, component, slot, opts)
end
ExportPublic("MSUF_EM2_SetFocusHover", SetFocusHover)

local function ClearFocusHover()
    return Focus.ClearHover()
end
ExportPublic("MSUF_EM2_ClearFocusHover", ClearFocusHover)

local function PulseFocus(key, component, slot, opts)
    return Focus.Pulse(key, component, slot, opts)
end
ExportPublic("MSUF_EM2_PulseFocus", PulseFocus)

local function SetPopupFocus(key)
    return Focus.SetPopupFocus(key)
end
ExportPublic("MSUF_EM2_SetPopupFocus", SetPopupFocus)

local function ClearPopupFocus()
    return Focus.ClearPopupFocus()
end
ExportPublic("MSUF_EM2_ClearPopupFocus", ClearPopupFocus)

local function SyncFocusInspector()
    return Focus.RefreshPopupFocus()
end
ExportPublic("MSUF_EM2_SyncFocusInspector", SyncFocusInspector)

local function OpenFocusSettings(pageKey)
    return Focus.OpenFullSettings(pageKey)
end
ExportPublic("MSUF_EM2_OpenFocusSettings", OpenFocusSettings)

HideLegacyInspector()
HideOldFocusLayer()

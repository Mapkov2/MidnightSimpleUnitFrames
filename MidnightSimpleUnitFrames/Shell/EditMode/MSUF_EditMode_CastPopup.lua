--- MSUF_EditMode_CastPopup.lua - Menu2-style quick castbar bounds popup.
--- This is an edit-mode convenience surface for changing castbar bounds. It writes through
--- existing castbar DB/reanchor helpers and must respect combat-safe mover sync.

local addonName, MSUF = ...
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_CastPopup.lua"
local EM2 = MSUF.Optional("MSUF_EM2")
if not EM2 then return end

local floor = math.floor
local max, min = math.max, math.min
local Style = MSUF.Optional("MSUF_EM2_Menu2Style") or {}
local Quick = EM2.QuickPopup or Style.QuickPopup
if not Quick then return end

local TEST_FUNCS = {
    player = "MSUF_SetPlayerCastbarTestMode",
    target = "MSUF_SetTargetCastbarTestMode",
    focus = "MSUF_SetFocusCastbarTestMode",
    boss = "MSUF_SetBossCastbarTestMode",
    arena = "MSUF_SetArenaCastbarTestMode",
}

local pf
local Sync
local Util = EM2.Util or {}
local SyncMovers = (EM2.Util and EM2.Util.SyncMovers)
local UnitPageKey = Util.UnitPageKey
local UnitLabel = Util.UnitLabel
local FramePositionValues = Util.FramePositionValues
local TranslateFramePosition = Util.TranslateFramePosition
local NormalizeUnit = Util.NormalizeSimpleUnit

local function ButtonOpts(sync)
    return {
        hoverWash = true,
        hoverKey = "_msufEM2CastHoverWash",
        sync = sync,
    }
end

local function General()
    local db = MSUF_DB
    return db and db.general or {}
end

local function EditableGeneral()
    local db = MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    return db.general
end

-- The castbar module loads after Edit Mode and publishes these getters once.
-- Each is resolved on its first use and kept: the castbar drag syncs this
-- popup at 20 Hz and must not pay a lookup per tick.
local CastbarProviders = {}

local function Prefix(unit)
    local fn = CastbarProviders.prefix
    if fn == nil then
        fn = MSUF.Require("MSUF_GetCastbarPrefix", CALLER)
        CastbarProviders.prefix = fn
    end
    return fn(unit) or nil
end

local function DefaultOffsets(unit)
    local fn = CastbarProviders.defaultOffsets
    if fn == nil then
        fn = MSUF.Require("MSUF_GetCastbarDefaultOffsets", CALLER)
        CastbarProviders.defaultOffsets = fn
    end
    return fn(unit)
end

local function OffsetKeys(unit)
    local fields = MSUF.Castbars.UNIT_CASTBAR[unit]
    if fields then return fields.x, fields.y end
end

local function WidthKey(unit)
    local fields = MSUF.Castbars.UNIT_CASTBAR[unit]
    return fields and fields.w
end

local function HeightKey(unit)
    local fields = MSUF.Castbars.UNIT_CASTBAR[unit]
    return fields and fields.h
end

local function WidthSourceKey(unit)
    local fn = CastbarProviders.widthSourceKey
    if fn == nil then
        fn = MSUF.Require("MSUF_GetCastbarWidthSourceKey", CALLER)
        CastbarProviders.widthSourceKey = fn
    end
    local key = fn(unit)
    if key then return key end
    local fields = MSUF.Castbars.UNIT_CASTBAR[unit]
    return fields and fields.match
end

local function DetachedKey(unit)
    local fields = MSUF.Castbars.UNIT_CASTBAR[unit]
    return fields and fields.detached
end

local function ManualWidth(g, unit)
    local key = WidthKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalWidth)
        or ((unit == "boss" or unit == "arena") and 176 or 271)
end

local function ManualHeight(g, unit)
    local key = HeightKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalHeight)
        or ((unit == "boss" or unit == "arena") and 12 or 18)
end

local function CastbarFrame(unit)
    if unit == "player" then return MSUF.Castbars.Frames.Get("playerPreview") or MSUF.Castbars.Frames.Get("player") end
    if unit == "target" then return MSUF.Castbars.Frames.Get("targetPreview") or MSUF.Castbars.Frames.Get("target") end
    if unit == "focus" then return MSUF.Castbars.Frames.Get("focusPreview") or MSUF.Castbars.Frames.Get("focus") end
    if unit == "boss" then return MSUF.Castbars.Frames.Get("bossPreview") end
    if unit == "arena" then
        local preview = MSUF.Castbars.Frames.Get("arenaPreview")
        if preview then return preview end
        -- Registry miss only: the legacy globals and the live arena pool.
        local frames = MSUF.Optional("MSUF_ArenaCastbars")
        return MSUF.Optional("MSUF_ArenaCastbarPreview1")
            or (frames and frames[1]) or MSUF.Optional("MSUF_ArenaCastbar1")
    end
end

local function EffectiveSize(g, unit)
    local fn = CastbarProviders.desiredSize
    if fn == nil then
        fn = MSUF.Require("MSUF_GetCastbarDesiredSize", CALLER)
        CastbarProviders.desiredSize = fn
    end
    local w, h = fn(unit, g, CastbarFrame(unit), ManualWidth(g, unit), ManualHeight(g, unit))
    if w and h then return floor(w + 0.5), floor(h + 0.5) end
    return floor(ManualWidth(g, unit) + 0.5), floor(ManualHeight(g, unit) + 0.5)
end

local function RefreshUFPreview(reason)
    local fn = MSUF.Optional("MSUF_UFPreview_RequestRefresh")
    if type(fn) == "function" then fn(reason or "EM2_CASTBAR_POPUP") end
end

--- Menu2 loads after this file and may be absent entirely, so the route is resolved
--- at call time. Only size writes need it: the Castbar section paints the manual
--- width/height sliders and the Width mode dropdown that a manual width forces back
--- to "manual". The position offsets have no Menu2 control, so they stay off this path.
--- Every caller sits behind Apply's combat fail-close, and the route itself defers
--- nothing, so this cannot cost a single cycle once combat starts.
local function SyncMenuAfterSizeWrite()
    if EM2.Focus and type(EM2.Focus.NotifySettingChanged) == "function" then
        EM2.Focus.NotifySettingChanged()
    end
end

local function ReapplyCastbar(unit)
    MSUF.Require("MSUF_ApplyCastbarUnitAndSync", CALLER)(unit)
    SyncMovers()
    RefreshUFPreview("EM2_CASTBAR_POPUP_APPLY")
end

local function Apply(mode)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local unit = pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local wKey, hKey = WidthKey(unit), HeightKey(unit)
    if not (xKey and yKey and wKey and hKey) then return end

    MSUF.Require("MSUF_EM_UndoBeforeChange", CALLER)("castbar", unit)

    local dx, dy = DefaultOffsets(unit)
    local currentX = Quick.San(g[xKey], dx)
    local currentY = Quick.San(g[yKey], dy)
    local displayX = pf.xBox and tonumber(pf.xBox:GetText())
    local displayY = pf.yBox and tonumber(pf.yBox:GetText())

    if mode == "width" or mode == "all" then
        local w = tonumber(pf.wBox and pf.wBox:GetText())
        if w then
            g[wKey] = floor(max(50, min(600, w)) + 0.5)
            local sourceKey = WidthSourceKey(unit)
            if sourceKey then g[sourceKey] = nil end
        end
    end

    if mode == "height" or mode == "all" then
        local h = tonumber(pf.hBox and pf.hBox:GetText())
        if h then g[hKey] = floor(max(8, min(100, h)) + 0.5) end
    end

    --- Size changes may move the visible center-facing X edge. Materialize the
    --- new geometry first, then translate the displayed X/Y fields back into
    --- the provider's saved anchor offsets.
    if mode ~= "position" then ReapplyCastbar(unit) end
    if type(TranslateFramePosition) == "function" then
        local changed
        g[xKey], g[yKey], changed = TranslateFramePosition(CastbarFrame(unit), currentX, currentY, displayX, displayY)
        if mode == "position" or changed then ReapplyCastbar(unit) end
    else
        g[xKey], g[yKey] = Quick.San(displayX, currentX), Quick.San(displayY, currentY)
        ReapplyCastbar(unit)
    end
    if mode ~= "position" then SyncMenuAfterSizeWrite() end
    if pf and pf:IsShown() then Sync() end
end

local function ResetPosition()
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local unit = pf.unit
    local xKey, yKey = OffsetKeys(unit)
    if not (xKey and yKey) then return end
    MSUF.Require("MSUF_EM_UndoBeforeChange", CALLER)("castbar", unit)
    local dx, dy = DefaultOffsets(unit)
    g[xKey], g[yKey] = dx, dy
    ReapplyCastbar(unit)
    if pf and pf:IsShown() then Sync() end
end

local function ApplyDetach(checked)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local key = DetachedKey(pf.unit)
    if not key then return end

    MSUF.Require("MSUF_EM_UndoBeforeChange", CALLER)("castbar", pf.unit)
    --- The canonical owner preserves the current on-screen center when a
    --- unitframe-relative castbar becomes UIParent-relative. Writing only
    --- the flag would reinterpret the old offsets and can move it off-screen.
    MSUF.Require("MSUF_EM_SetCastbarAnchoredToUnit", CALLER)(pf.unit, checked ~= true)
    if pf and pf:IsShown() then Sync() end
end

local function SetTest(unit, on)
    for key, fnName in pairs(TEST_FUNCS) do
        local fn = MSUF.Optional(fnName)
        if type(fn) == "function" then fn(key == unit and on, true) end
    end
end

local function CommitShortcutFields()
    Quick.ClearFocusedBoxes(pf and pf.xBox, pf and pf.yBox, pf and pf.wBox, pf and pf.hBox)
    Apply("position")
end

local function OpenUnitCastbar()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    local unit = pf.unit
    local pageKey = UnitPageKey(unit)
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(unit == "boss" and "boss" or unit, "castbar", nil, { source = "cast-popup", menu = false })
    end
    if Util.SetMenuFocusRequest then Util.SetMenuFocusRequest({
        key = unit == "boss" and "boss" or unit,
        component = "castbar",
        pageKey = pageKey,
        sectionId = "castbar",
        source = "cast-popup",
    }) end
    Quick.OpenPage(pageKey, pf)
end

local function OpenGeneralCastbars()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    if Util.SetMenuFocusRequest then Util.SetMenuFocusRequest({
        key = "castbar",
        component = "general",
        pageKey = "opt_castbar",
        sectionId = "castbar_behavior",
        source = "cast-popup",
    }) end
    Quick.OpenPage("opt_castbar", pf)
end

local function WirePopupFocus(btn)
    return Util.WirePopupFocus and Util.WirePopupFocus(btn, function() return pf and pf.unit and (pf.unit == "boss" and "boss" or pf.unit) end,
        "castbar", "cast-popup") or btn
end

function Sync()
    if not (pf and pf.unit) then return end
    local g, unit = General(), pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local dx, dy = DefaultOffsets(unit)
    local w, h = EffectiveSize(g, unit)
    local x, y
    if type(FramePositionValues) == "function" then
        x, y = FramePositionValues(CastbarFrame(unit))
    end

    if pf._titleFS then pf._titleFS:SetText(string.format(Quick.Tr("%s Castbar"), Quick.Tr(UnitLabel(unit)))) end
    Quick.SetBoxText(pf.xBox, x ~= nil and x or Quick.San(xKey and g[xKey], dx))
    Quick.SetBoxText(pf.yBox, y ~= nil and y or Quick.San(yKey and g[yKey], dy))
    Quick.SetBoxText(pf.wBox, w)
    Quick.SetBoxText(pf.hBox, h)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local dKey = DetachedKey(unit)
        pf.detachBtn:SetCheckedVisual(dKey and g[dKey] == true)
    end
end



local function ApplySize(changed)
    Quick.EnforceSizeRatio(pf, changed, 50, 600, 8, 100)
    Apply("all")
end

local function ToggleSizeRatio(checked)
    if not pf then return end
    pf._lockRatio = checked and true or false
    if pf._lockRatio then Quick.CaptureSizeRatio(pf) end
end

local function Build()
    if pf then return pf end

    pf = Quick.CreateShell("MSUF_EM2_CastPopup", {
        width = 560,
        height = 350,
        title = "Castbar",
        liveStatus = true,
        hoverSource = "cast-popup",
        onHide = function(s)
            local self = pf or s
            if self and self.unit and not MSUF.PublicGlobals.MSUF_UnitPreviewActive then SetTest(self.unit, false) end
        end,
    })
    local opts = ButtonOpts()
    Quick.ValueCard(pf, pf, 20, -58, 208, "Position", {
        { label = "X", key = "xBox", onChanged = function() Apply("position") end },
        { label = "Y", key = "yBox", onChanged = function() Apply("position") end },
    }, { height = 132, boxWidth = 64, hoverWash = true, hoverKey = opts.hoverKey })
    local sizeCard = Quick.ValueCard(pf, pf, 240, -58, 300, "Size", {
        { label = "Width", key = "wBox", onChanged = function() ApplySize("width") end },
        { label = "Height", key = "hBox", onChanged = function() ApplySize("height") end },
    }, { height = 132, boxWidth = 64, controlsRightInset = 88, hoverWash = true, hoverKey = opts.hoverKey })
    pf.ratioBtn = Quick.ToggleAt(sizeCard, "Lock ratio", 208, -80, 80, 32, ToggleSizeRatio, ButtonOpts())
    pf.detachBtn = Quick.ToggleAt(pf, "Detach castbar from unit frame", 160, -204, 240, 30, ApplyDetach,
        ButtonOpts(function() if pf and pf:IsShown() then Sync() end end))
    WirePopupFocus(Quick.ButtonAt(pf, "Open detailed settings", 20, -250, 334, 36, OpenUnitCastbar, {
        variant = "primary", hoverWash = true, hoverKey = opts.hoverKey,
    }))
    WirePopupFocus(Quick.ButtonAt(pf, "General castbar settings", 366, -250, 174, 36, OpenGeneralCastbars, opts))
    if Quick.AddFooterControls then
        Quick.AddFooterControls(pf, { anchor = "BOTTOM", bottomGap = 12, onResetPosition = ResetPosition })
    end
    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

local CastPopup = {}
EM2.CastPopup = CastPopup

function CastPopup.RefreshHistory()
    if pf and pf:IsShown() and pf._refreshUndoRedo then pf._refreshUndoRedo() end
end

function CastPopup.Open(unit, parent)
    if Quick.BlockConfigCombatLocked() then return false end
    unit = NormalizeUnit(unit)
    if not unit then return false end
    Build()
    pf.unit, pf.parent = unit, parent
    Sync()
    if pf._lockRatio then Quick.CaptureSizeRatio(pf) end
    pf:Show()
    SetTest(unit, true)
    if Style.FadeIn then Style.FadeIn(pf, 0.12, 0.86, 1) end
    return true
end

function CastPopup.Close()
    if pf then
        if pf.unit and not MSUF.PublicGlobals.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
        pf:Hide()
    end
end

function CastPopup.IsOpen()
    return pf and pf:IsShown() or false
end

function CastPopup.GetUnit()
    return pf and pf.unit or nil
end

function CastPopup.Sync()
    if pf and pf:IsShown() then Sync() end
end

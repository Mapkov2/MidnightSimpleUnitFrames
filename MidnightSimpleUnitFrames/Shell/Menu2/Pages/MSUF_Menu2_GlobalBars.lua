local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Bars page.
-- Binds shared/scoped texture, gradient, outline, absorb, and highlight controls. Page code
-- updates DB through GlobalPage helpers and lets runtime refreshers repaint live frames.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local min = math.min
local C_Timer = _G.C_Timer
local BARS_PAGE_WORK_DELAY = 0.04
local FRAME_OUTLINE_LEVEL_DEFAULT = 35
local FRAME_OUTLINE_LEVEL_MAX = 60
local DISPEL_BORDER_121_PTR_DISABLED = false
local PURGE_BORDER_121_PTR_DISABLED = true
local DISPEL_PURGE_BORDER_121_PTR_MESSAGE = "Dispel uses native 12.1 AuraContainer detection. Purge border stays disabled until Blizzard exposes a safe purge/stealable filter."
local UNITFRAME_DISPEL_AURA_WARNING = "No UnitFrame auras: Dispel Border/Overlay need Player/Target/Focus/Boss auras."
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = { 0.90, 0.84, 0.76, 1 }
local UNITFRAME_DISPEL_AURA_UNITS = { "player", "target", "focus", "boss" }
local ROUNDED_PREVIEW_WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ROUNDED_PREVIEW_MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local ROUNDED_PREVIEW_MASK = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_4x.tga"
local ROUNDED_PREVIEW_EDGE = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_edge_4x.tga"
local GRADIENT_DIR_KEYS, PRIORITY_LABELS = M.PickDefaults(GP, [[GRADIENT_DIR_KEYS PRIORITY_LABELS]])
local Call, DB, G, Bars, Unit, ReadG, SetG, ReadGBool, SetGBool, ReadB, SetB, NormalizeScopeKey, ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, CurrentBarsScope, IsGFScope, BarScopeGet, BarScopeSet, BarScopeGetBars, BarScopeSetBars, TextureValues, CurrentPowerBarScopeUnit, SmoothPowerGet, SmoothPowerSet, PriorityOrder, PriorityColor, SetPriorityOrder, NormalizePriorityKey, RefreshBorderTestModes, SetAbsorbTextureTest, ClearAbsorbTextureTest, SetControlEnabled, SetControlsEnabled, ApplyBars = M.Pick(GP, [[Call DB G Bars Unit ReadG SetG ReadGBool SetGBool ReadB SetB NormalizeScopeKey ScopeDBKeys ScopeHasOverride ScopeSetOverride CurrentBarsScope IsGFScope BarScopeGet BarScopeSet BarScopeGetBars BarScopeSetBars TextureValues CurrentPowerBarScopeUnit SmoothPowerGet SmoothPowerSet PriorityOrder PriorityColor SetPriorityOrder NormalizePriorityKey RefreshBorderTestModes SetAbsorbTextureTest ClearAbsorbTextureTest SetControlEnabled SetControlsEnabled ApplyBars]])
NormalizePriorityKey = NormalizePriorityKey or function(key) return key end
local barsPageWorkPending = {}
local function ScheduleBarsPageWork(key, delay, fn)
    if type(fn) ~= "function" then return end
    key = key or fn
    if barsPageWorkPending[key] then return end
    barsPageWorkPending[key] = fn
    local function Run()
        local cb = barsPageWorkPending[key]
        barsPageWorkPending[key] = nil
        if type(cb) == "function" then cb() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or BARS_PAGE_WORK_DELAY, Run)
    else
        Run()
    end
end
local function NormalizeFrameOutlineLevelOffset(value, fallback)
    local n = floor((tonumber(value) or fallback or FRAME_OUTLINE_LEVEL_DEFAULT) + 0.5)
    if n < 0 then return 0 end
    if n > FRAME_OUTLINE_LEVEL_MAX then return FRAME_OUTLINE_LEVEL_MAX end
    return n
end
local function RefreshFrameOutlineLevelLabel(slider, value)
    if not slider then return end
    value = NormalizeFrameOutlineLevelOffset(value, FRAME_OUTLINE_LEVEL_DEFAULT)
    if slider._msuf2Title then
        slider._msuf2Title:SetText(string.format(M.Tr("Frame level offset: +%d"), value))
    end
end
local function ApplyService()
    return M.ApplyService or _G.MSUF_Menu2_ApplyService
end
local function BarsProfileStart()
    return M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStart() or nil
end
local function BarsProfileStop(key, started, extraCount)
    if M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStop then
        M.ProfileStop("barsPage", key, started, extraCount)
    end
end
local function AnyUnitFrameAuraEnabled()
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function") then return true end
    for i = 1, #UNITFRAME_DISPEL_AURA_UNITS do
        if model.UnitEnabled(UNITFRAME_DISPEL_AURA_UNITS[i]) then return true end
    end
    return false
end
local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Bars", "Textures, gradients, outlines and highlight borders.", 72)
    local function SharedBarsControlsActive()
        return CurrentBarsScope() == "shared"
    end
    local function CurrentBarsScopeIsGroupFrame()
        local scope = CurrentBarsScope()
        if type(IsGFScope) == "function" then return IsGFScope(scope) end
        return scope == "gf_party" or scope == "gf_raid"
    end
    local function ScopedBarsControlsActive()
        local scope = CurrentBarsScope()
        return scope == "shared" or ScopeHasOverride(scope, "hlOverride")
    end
    local function HighlightControlsActive()
        return CurrentBarsScope() ~= nil
    end
    local function BorderTestScope()
        local scope = CurrentBarsScope()
        if scope == "gf_party" then return "party" end
        if scope == "gf_raid" then return "raid" end
        return scope
    end
    local function CurrentGroupFrameRefreshKinds()
        local scope = CurrentBarsScope()
        if scope == "gf_party" then return "party" end
        if scope == "gf_raid" then return "raid", "mythicraid" end
        if scope == "gf_mythicraid" then return "mythicraid" end
        return nil
    end
    local function UnitApplyKey(unit)
        unit = tostring(unit or "")
        if unit:match("^boss%d+$") then return "boss" end
        return unit
    end
    local function RequestUnitRuntime(unit, reason, opts)
        unit = UnitApplyKey(unit)
        if unit == "" then return false end
        opts = opts or { preview = true }
        local applyService = ApplyService()
        if applyService and type(applyService.RequestUnit) == "function" then
            return applyService.RequestUnit(unit, reason or "MSUF2_BARS_UNIT_RUNTIME", opts) ~= false
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            return Call("MSUF_UFCore_NotifyConfigChanged", unit, true, true, reason or "MSUF2_BARS_UNIT_RUNTIME")
        end
        return false
    end
    local function RequestUnitsRuntime(units, reason, opts)
        local seen
        local did = false
        for i = 1, #units do
            local unit = UnitApplyKey(units[i])
            if unit ~= "" then
                if not seen then seen = {} end
                if not seen[unit] then
                    seen[unit] = true
                    did = RequestUnitRuntime(unit, reason, opts) or did
                end
            end
        end
        return did
    end
    local function RequestGroupFrameDirty(dirty, reason)
        local applyService = ApplyService()
        if not applyService then return false end
        local kindA, kindB = CurrentGroupFrameRefreshKinds()
        if type(applyService.RequestGroupDirtyMask) == "function" then
            if kindA then
                local did = applyService.RequestGroupDirtyMask(kindA, dirty, reason or "MSUF2_GF_BARS_RUNTIME") ~= false
                if kindB then did = (applyService.RequestGroupDirtyMask(kindB, dirty, reason or "MSUF2_GF_BARS_RUNTIME") ~= false) or did end
                return did
            end
            return applyService.RequestGroupDirtyMask(nil, dirty, reason or "MSUF2_GF_BARS_RUNTIME") ~= false
        end
        if type(applyService.RequestGroup) == "function" then
            if kindA then
                local did = applyService.RequestGroup(kindA, "visual", reason or "MSUF2_GF_BARS_RUNTIME") ~= false
                if kindB then did = (applyService.RequestGroup(kindB, "visual", reason or "MSUF2_GF_BARS_RUNTIME") ~= false) or did end
                return did
            end
            return applyService.RequestGroup(nil, "visual", reason or "MSUF2_GF_BARS_RUNTIME") ~= false
        end
        return false
    end
    local function GroupKindMatches(frame, kindA, kindB)
        if not kindA then return true end
        local frameKind = frame and frame._msufGFKind
        return frameKind == kindA or frameKind == kindB
    end
    local function RefreshGroupFrameVisuals()
        -- Group frames have their own visual caches. Invalidate them explicitly when global
        -- bar settings can affect party/raid previews or live secure children.
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        local dirty = (GF and GF.DIRTY_VISUAL) or true
        if RequestGroupFrameDirty(dirty, "MSUF2_GF_BARS_VISUALS") then return end
        if not GF then return end
        local kindA, kindB = CurrentGroupFrameRefreshKinds()
        if GF.InvalidateConfCache then GF.InvalidateConfCache() end
        if GF.RefreshVisuals then
            if kindA then
                GF.RefreshVisuals(kindA, dirty)
                if kindB then GF.RefreshVisuals(kindB, dirty) end
            else
                GF.RefreshVisuals(nil, dirty)
            end
        elseif _G.MSUF_GF_RefreshOverlays then
            _G.MSUF_GF_RefreshOverlays()
        end
    end
    local function RefreshGroupFrameBorders()
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        local dirty = (GF and (GF.DIRTY_BORDER or GF.DIRTY_VISUAL)) or true
        if RequestGroupFrameDirty(dirty, "MSUF2_GF_BARS_BORDER") then return end
        if not GF then return end
        local kindA, kindB = CurrentGroupFrameRefreshKinds()
        if GF.InvalidateConfCache then GF.InvalidateConfCache() end
        local refreshBorder = _G.MSUF_GF_RefreshBorder
        if refreshBorder and GF.frames then
            for frame in pairs(GF.frames) do
                if GroupKindMatches(frame, kindA, kindB) then
                    if GF.BuildFrameCache then GF.BuildFrameCache(frame) end
                    local c = frame and frame._c
                    if frame and frame.unit and c and GF.DispelScanActive and GF.DispelScanActive(c) and GF._UpdateDispel then
                        GF._UpdateDispel(frame, frame.unit)
                    else
                        refreshBorder(frame, frame and frame.unit)
                    end
                end
            end
        elseif GF.RefreshVisuals then
            if kindA then
                GF.RefreshVisuals(kindA, dirty)
                if kindB then GF.RefreshVisuals(kindB, dirty) end
            else
                GF.RefreshVisuals(nil, dirty)
            end
        end
    end
    local function RefreshUnitBorders(units, reason)
        if RequestUnitsRuntime(units, reason or "MSUF2_BORDER", { preview = true }) then return end
        local UF = MSUF and MSUF.UF
        local frames = UF and UF.frames
        for i = 1, #units do
            local unit = units[i]
            local frame = (frames and frames[unit]) or _G["MSUF_" .. tostring(unit)]
            if frame and frame.ForceUpdate then frame:ForceUpdate("MSUF2_BORDER") end
        end
    end
    local UNITFRAME_AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    local function RefreshUnitAuras(units, reason)
        reason = reason or "MSUF2_UF_DISPEL_OVERLAY"
        if RequestUnitsRuntime(units, reason, { preview = true, auras = true, notify = false }) then return end
        local UF = MSUF and MSUF.UF
        local A3 = MSUF and MSUF.MSUF_Auras3 or _G.MSUF_Auras3
        local frames = UF and UF.frames
        for i = 1, #units do
            local unit = units[i]
            local spec = UF and UF.Config and UF.Config.RefreshUnit and UF.Config.RefreshUnit(unit)
            local frame = (frames and frames[unit]) or _G["MSUF_" .. tostring(unit)]
            if frame and UF and type(UF.ApplyElementToFrame) == "function" then
                UF.ApplyElementToFrame(frame, "Auras", spec or frame.MSUFSpec, reason)
            elseif A3 and type(A3.RefreshUnit) == "function" then
                A3.RefreshUnit(unit)
            end
        end
    end
    local function ApplyUnitDispelOverlayRuntime(reason)
        Call("MSUF_UFCore_RefreshSettingsCache", reason or "MSUF2_UF_DISPEL_OVERLAY_RUNTIME")
        RefreshUnitAuras(UNITFRAME_AURA_UNITS, reason or "MSUF2_UF_DISPEL_OVERLAY")
        Call("MSUF_UFPreview_RequestRefresh", reason or "MSUF2_UF_DISPEL_OVERLAY")
    end
    local function ApplyOutlineRuntime()
        Call("MSUF_ApplyBarOutlineThickness_All")
        local GF = _G.MSUF_NS and _G.MSUF_NS.GF
        if GF and type(GF.RefreshOutlineGeometry) == "function" then
            GF.RefreshOutlineGeometry()
        else
            Call("MSUF_GF_RefreshOutlineGeometry")
            RefreshGroupFrameVisuals()
        end
        Call("MSUF_ApplyRoundedUnitframes")
        Call("MSUF_UFPreview_RequestRefresh", "MSUF2_BAR_OUTLINE")
    end
    local outlineRuntimeQueued = false
    local function RequestOutlineRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestBarOutline) == "function" then
            return applyService.RequestBarOutline("MSUF2_BAR_OUTLINE", CurrentBarsScope())
        end
        if outlineRuntimeQueued then return end
        outlineRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_BARS_OUTLINE_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            outlineRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyOutlineRuntime()
            BarsProfileStop("OutlineRuntime", started)
        end)
    end
    local function ApplyAggroBorderRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_AGGRO_BORDER_RUNTIME")
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_AggroOutline_ApplyEventRegistration")
        RefreshUnitBorders({ "player", "target", "focus", "boss" }, "MSUF2_AGGRO_BORDER_RUNTIME")
        RefreshGroupFrameBorders()
        RefreshGroupFrameVisuals()
    end
    local function ApplyDispelPurgeBorderRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_DISPEL_BORDER_RUNTIME")
        Call("MSUF_ApplyBarOutlineThickness_All")
        Call("MSUF_DispelOutline_ApplyEventRegistration")
        Call("MSUF_RefreshDispelOutlineStates", true)
        RefreshUnitBorders({ "player", "target", "focus", "targettarget" }, "MSUF2_DISPEL_BORDER_RUNTIME")
        Call("MSUF_RefreshUnitDispelOverlays")
        RefreshGroupFrameBorders()
        if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(true, BorderTestScope()) end
        if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(true, BorderTestScope()) end
    end
    local function ApplyBossTargetBorderRuntime()
        local reason = "MSUF2_BOSS_TARGET_BORDER_RUNTIME"
        Call("MSUF_UFCore_RefreshSettingsCache", reason)
        if RequestUnitRuntime("boss", reason, { preview = true }) then return end
        if MSUF and MSUF.UF and MSUF.UF.RefreshBorders then
            MSUF.UF.RefreshBorders("boss")
        else
            RefreshUnitBorders({ "boss1", "boss2", "boss3", "boss4", "boss5" })
        end
    end
    local function ApplyHighlightPriorityRuntime()
        Call("MSUF_UFCore_RefreshSettingsCache", "MSUF2_HIGHLIGHT_PRIORITY_RUNTIME")
        RefreshUnitBorders({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }, "MSUF2_HIGHLIGHT_PRIORITY_RUNTIME")
        RefreshGroupFrameBorders()
        Call("MSUF_UFPreview_RequestRefresh", "MSUF2_HIGHLIGHT_PRIORITY")
    end
    local function ApplyAllHighlightBorderRuntime()
        ApplyAggroBorderRuntime()
        ApplyDispelPurgeBorderRuntime()
        ApplyBossTargetBorderRuntime()
    end
    local aggroBorderRuntimeQueued = false
    local dispelPurgeBorderRuntimeQueued = false
    local unitDispelOverlayRuntimeQueued = false
    local bossTargetBorderRuntimeQueued = false
    local highlightPriorityRuntimeQueued = false
    local allHighlightBorderRuntimeQueued = false
    local function RequestAggroBorderRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestAggroBorder) == "function" then
            return applyService.RequestAggroBorder("MSUF2_AGGRO_BORDER_RUNTIME", CurrentBarsScope())
        end
        if aggroBorderRuntimeQueued then return end
        aggroBorderRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_AGGRO_BORDER_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            aggroBorderRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyAggroBorderRuntime()
            BarsProfileStop("AggroBorderRuntime", started)
        end)
    end
    local function RequestDispelPurgeBorderRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestDispelPurgeBorder) == "function" then
            local result = applyService.RequestDispelPurgeBorder("MSUF2_DISPEL_PURGE_BORDER_RUNTIME", CurrentBarsScope())
            if _G.MSUF_DispelBorderTestMode and type(_G.MSUF_SetDispelBorderTestMode) == "function" then _G.MSUF_SetDispelBorderTestMode(true, BorderTestScope()) end
            if _G.MSUF_PurgeBorderTestMode and type(_G.MSUF_SetPurgeBorderTestMode) == "function" then _G.MSUF_SetPurgeBorderTestMode(true, BorderTestScope()) end
            return result
        end
        if dispelPurgeBorderRuntimeQueued then return end
        dispelPurgeBorderRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_DISPEL_PURGE_BORDER_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            dispelPurgeBorderRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyDispelPurgeBorderRuntime()
            BarsProfileStop("DispelPurgeBorderRuntime", started)
        end)
    end
    local function RequestUnitDispelOverlayRuntime(reason)
        if unitDispelOverlayRuntimeQueued then return end
        unitDispelOverlayRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_UF_DISPEL_OVERLAY_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            unitDispelOverlayRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyUnitDispelOverlayRuntime(reason)
            BarsProfileStop("UnitDispelOverlayRuntime", started)
        end)
    end
    local function RequestBossTargetBorderRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestBossTargetBorder) == "function" then
            return applyService.RequestBossTargetBorder("MSUF2_BOSS_TARGET_BORDER_RUNTIME", "boss")
        end
        if bossTargetBorderRuntimeQueued then return end
        bossTargetBorderRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_BOSS_TARGET_BORDER_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            bossTargetBorderRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyBossTargetBorderRuntime()
            BarsProfileStop("BossTargetBorderRuntime", started)
        end)
    end
    local function RequestHighlightPriorityRuntime()
        if highlightPriorityRuntimeQueued then return end
        highlightPriorityRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_HIGHLIGHT_PRIORITY_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            highlightPriorityRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyHighlightPriorityRuntime()
            BarsProfileStop("HighlightPriorityRuntime", started)
        end)
    end
    local function RequestAllHighlightBorderRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestHighlightBorders) == "function" then
            return applyService.RequestHighlightBorders("MSUF2_ALL_HIGHLIGHT_BORDER_RUNTIME", CurrentBarsScope())
        end
        if allHighlightBorderRuntimeQueued then return end
        allHighlightBorderRuntimeQueued = true
        ScheduleBarsPageWork("MSUF2_ALL_HIGHLIGHT_BORDER_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            allHighlightBorderRuntimeQueued = false
            local started = BarsProfileStart()
            ApplyAllHighlightBorderRuntime()
            BarsProfileStop("AllHighlightBorderRuntime", started)
        end)
    end
    local function ApplyRoundedRuntime()
        local applyService = ApplyService()
        if applyService and type(applyService.RequestRoundedBars) == "function" then
            return applyService.RequestRoundedBars("MSUF2_ROUNDED", CurrentBarsScope())
        end
        Call("MSUF_ApplyRoundedUnitframes")
        if M.RequestGeneralApply then
            M.RequestGeneralApply("MSUF2_ROUNDED", { preview = true, applyAll = false, bars = true, barsScope = CurrentBarsScope() })
        elseif Call("MSUF_UFCore_NotifyConfigChanged", nil, true, true, "MSUF2_ROUNDED") then
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_ROUNDED")
        else
            Call("MSUF_RefreshAllFrames")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_ROUNDED")
        end
        RefreshGroupFrameVisuals()
        if not RequestGroupFrameDirty(true, "MSUF2_ROUNDED_GF_PREVIEW") then
            Call("MSUF_GF_RefreshPreviewLayout", "party")
            Call("MSUF_GF_RefreshPreviewLayout", "raid")
            Call("MSUF_GF_RefreshPreviewLayout", "mythicraid")
            Call("MSUF_GF_RefreshPreviewBox")
        end
    end
    local function ShowRoundedReloadRequiredPopup()
        if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then
            if _G.print then _G.print(M.Tr("|cffffd700MSUF:|r Rounded frame texture changed. Reload the UI with /reload.")) end
            return
        end
        M.InstallStaticPopup("MSUF2_ROUNDED_RELOAD_REQUIRED", {
            text = M.Tr("Rounded frame texture was changed.\n\nA UI reload is required because this style rebuilds frame masks and protected frame visuals.\n\nReload now?"),
            button1 = _G.RELOAD or M.Tr("Reload"),
            hideOnEscape = false,
            OnAccept = function()
                if _G.InCombatLockdown and _G.InCombatLockdown() then
                    if _G.print then _G.print(M.Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")) end
                    return
                end
                if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
            end,
        })
        _G.StaticPopup_Show("MSUF2_ROUNDED_RELOAD_REQUIRED")
    end
    local function SetRoundedBool(key, value, requireReload)
        SetB(key, value and true or false, "MSUF2_ROUNDED", { preview = true })
        ApplyRoundedRuntime()
        if requireReload then ShowRoundedReloadRequiredPopup() end
    end
    local function RegisterRoundedSearch(control, label, extraKeywords, help, kind)
        if not (control and type(M.RegisterSearchWidget) == "function") then return end
        local keywords = {
            "rounded texture", "rounded frame texture", "rounded frames", "round corners", "rounded corners",
            "bars rounded", "global style bars rounded", "enable rounded frames", "disable rounded frames",
            "turn on rounded frames", "turn off rounded frames", "abgerundete frames", "runde kanten",
            "runde ecken", "abrundung", "abrunden", "einschalten", "ausschalten",
        }
        if type(extraKeywords) == "string" and extraKeywords:find("|", 1, true) then
            for keyword in extraKeywords:gmatch("[^|]+") do keywords[#keywords + 1] = keyword end
        elseif type(extraKeywords) == "table" then
            for i = 1, #extraKeywords do keywords[#keywords + 1] = extraKeywords[i] end
        elseif extraKeywords then
            keywords[#keywords + 1] = extraKeywords
        end
        M.RegisterSearchWidget(control, {
            label = label,
            kind = kind or control._msuf2ControlKind or "toggle",
            anchor = control._msuf2Title or control._msuf2Label or control,
            values = { "On", "Off", "Enable", "Disable", "Einschalten", "Ausschalten" },
            keywords = keywords,
            help = help or "Controls the rounded frame texture style for unit frames, group frames, power bars, and mouseover highlights.",
        })
    end
    local function SnapPreviewRegion(region)
        if not region then return end
        if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
    local function MaskRoundedPreviewTexture(sample, key, tex)
        if not (sample and tex and tex.AddMaskTexture and sample.CreateMaskTexture) then return end
        sample._msuf2RoundedPreviewMasks = sample._msuf2RoundedPreviewMasks or {}
        local mask = sample._msuf2RoundedPreviewMasks[key]
        if not mask then
            mask = sample:CreateMaskTexture(nil, "ARTWORK")
            SnapPreviewRegion(mask)
            sample._msuf2RoundedPreviewMasks[key] = mask
        end
        mask:ClearAllPoints()
        mask:SetTexture(ROUNDED_PREVIEW_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(sample)
        if sample._msuf2RoundedPreviewMasked and sample._msuf2RoundedPreviewMasked[tex] == mask then return end
        sample._msuf2RoundedPreviewMasked = sample._msuf2RoundedPreviewMasked or {}
        local old = sample._msuf2RoundedPreviewMasked[tex]
        if old and tex.RemoveMaskTexture then tex:RemoveMaskTexture(old) end
        tex:AddMaskTexture(mask)
        sample._msuf2RoundedPreviewMasked[tex] = mask
    end
    local function CreateRoundedTexturePreview(parent, x, y, width)
        width = max(320, floor((tonumber(width) or 560) + 0.5))
        local card = W.ControlCard(parent, "Preview", nil, x, y, width, 88)
        if not card then return nil end
        local sampleW = min(440, max(280, width - 44))
        local sampleH = 46
        local powerH = 8
        local sample = CreateFrame("Frame", nil, card)
        sample:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -38)
        sample:SetSize(sampleW, sampleH)
        card._msuf2RoundedPreviewSample = sample
        local function PreviewTex(field, layer, level, r, g, b, a, point)
            local tex = sample:CreateTexture(nil, layer, nil, level)
            if field == "_previewBg" then tex:SetTexture(ROUNDED_PREVIEW_WHITE8) end
            point(tex)
            tex:SetColorTexture(r, g, b, a)
            SnapPreviewRegion(tex)
            sample[field] = tex
            return tex
        end
        local bg = PreviewTex("_previewBg", "BACKGROUND", -7, 0.015, 0.020, 0.032, 0.96, function(tex) tex:SetAllPoints(sample) end)
        local healthBg = PreviewTex("_previewHealthBg", "BORDER", -1, 0.060, 0.070, 0.075, 1, function(tex)
            tex:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 0, powerH)
        end)
        local health = PreviewTex("_previewHealth", "ARTWORK", 1, 0.70, 0.69, 0.30, 0.94, function(tex)
            tex:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
            tex:SetSize(floor(sampleW * 0.78 + 0.5), sampleH - powerH)
        end)
        local powerBg = PreviewTex("_previewPowerBg", "ARTWORK", 2, 0.090, 0.055, 0.115, 1, function(tex)
            tex:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 0, 0)
            tex:SetHeight(powerH)
        end)
        local power = PreviewTex("_previewPower", "ARTWORK", 3, 0.62, 0.12, 0.78, 1, function(tex)
            tex:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 0, 0)
            tex:SetSize(floor(sampleW * 0.66 + 0.5), powerH)
        end)
        local gloss = PreviewTex("_previewGloss", "ARTWORK", 4, 1, 1, 1, 0.045, function(tex)
            tex:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", sample, "RIGHT", 0, -1)
        end)
        local name = T.Font(sample, "GameFontHighlightSmall", "Mapkotwo", T.colors.text)
        name:SetPoint("LEFT", sample, "LEFT", 10, 4)
        name:SetWidth(floor(sampleW * 0.42))
        name:SetJustifyH("LEFT")
        if name.SetShadowOffset then name:SetShadowOffset(1, -1) end
        local value = T.Font(sample, "GameFontHighlightSmall", "404K - 100.0%", T.colors.text)
        value:SetPoint("RIGHT", sample, "RIGHT", -10, 4)
        value:SetWidth(floor(sampleW * 0.50))
        value:SetJustifyH("RIGHT")
        if value.SetShadowOffset then value:SetShadowOffset(1, -1) end
        for key, tex in pairs({
            bg = bg,
            healthBg = healthBg,
            health = health,
            powerBg = powerBg,
            power = power,
            gloss = gloss,
        }) do
            MaskRoundedPreviewTexture(sample, key, tex)
        end
        sample._msuf2RoundedPreviewEdges = {}
        for i = 1, 2 do
            local edge = sample:CreateTexture(nil, "OVERLAY", nil, 6)
            edge:SetTexture(ROUNDED_PREVIEW_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            edge:SetPoint("TOPLEFT", sample, "TOPLEFT", -i, i)
            edge:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", i, -i)
            edge:SetVertexColor(0, 0, 0, 1)
            SnapPreviewRegion(edge)
            sample._msuf2RoundedPreviewEdges[i] = edge
        end
        function card:RefreshRoundedPreview()
            sample:SetAlpha((ReadB("roundedFramesEnabled", false) == true) and 1 or 0.62)
        end
        card:RefreshRoundedPreview()
        return card
    end
    local dispelTriggers = VT("BY_ME", "Dispellable by me", "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
    local unitDispelOverlayTriggers = VT(
        "BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
        "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
    local unitDispelOverlayStyles = VT(
        "FULL", "Full Frame", "TOP", "Top Fade", "BOTTOM", "Bottom Fade", "LEFT", "Left Fade", "RIGHT", "Right Fade")
    local function NormalizeDispelTrigger(v)
        local fn = _G.MSUF_NormalizeDispelBorderTrigger
        if type(fn) == "function" then return fn(v) end
        if v == "DISPEL_TYPE" or v == "TYPE" or v == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
        if v == "ANY_DEBUFF" or v == "ANY" or v == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
        return "BY_ME"
    end
    local function NormalizeUnitDispelOverlayTrigger(v)
        local fn = _G.MSUF_NormalizeUnitDispelOverlayTrigger
        if type(fn) == "function" then return fn(v) end
        if v == "BORDER" or v == "INHERIT" or v == "SAME" then return "BORDER" end
        return NormalizeDispelTrigger(v)
    end
    local function GradientKeyActive(entry, key)
        return entry and entry.hlOverride == true
            and entry.gradientOverride == true
            and entry.gradientOverrideVersion == 2
            and type(entry.gradientOverrideKeys) == "table"
            and entry.gradientOverrideKeys[key] == true
    end
    local function MarkGradientKey(entry, key)
        if not entry then return end
        entry.hlOverride = true
        entry.gradientOverride = true
        entry.gradientOverrideVersion = 2
        if type(entry.gradientOverrideKeys) ~= "table" then entry.gradientOverrideKeys = {} end
        entry.gradientOverrideKeys[key] = true
    end
    local function AdoptChangedGradientKey(entry, key, defaultValue)
        if not (entry and entry.hlOverride == true and entry[key] ~= nil) then return end
        if GradientKeyActive(entry, key) then return end
        local shared = ReadG(key, defaultValue)
        if entry[key] ~= shared then MarkGradientKey(entry, key) end
    end
    local function GradientControlsActive()
        local scope = CurrentBarsScope()
        return scope == "shared" or ScopeHasOverride(scope, "hlOverride")
    end
    local function TextureControlsActive()
        local scope = CurrentBarsScope()
        if scope == "shared" then return true end
        return IsGFScope(scope) and ScopeHasOverride(scope, "hlOverride")
    end
    local function GradientScopeGet(key, defaultValue)
        local scope = CurrentBarsScope()
        if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
            local db = DB()
            local keys = ScopeDBKeys(scope)
            for i = 1, #(keys or {}) do
                local entry = db[keys[i]]
                AdoptChangedGradientKey(entry, key, defaultValue)
                if GradientKeyActive(entry, key) and entry[key] ~= nil then return entry[key] end
            end
        end
        return ReadG(key, defaultValue)
    end
    local function GradientScopeSet(key, value)
        local scope = CurrentBarsScope()
        if scope == "shared" then
            G()[key] = value
            return
        end
        local db = DB()
        local keys = ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entryKey = keys[i]
            db[entryKey] = db[entryKey] or {}
            MarkGradientKey(db[entryKey], key)
            db[entryKey][key] = value
        end
    end
    local function CurrentGradientDirectionsForScope()
        local directions = {}
        local any = false
        for dir, key in pairs(GRADIENT_DIR_KEYS) do
            local on = GradientScopeGet(key, false) == true
            directions[dir] = on
            if on then any = true end
        end
        if not any then
            local legacy = GradientScopeGet("gradientDirection", "RIGHT")
            if not GRADIENT_DIR_KEYS[legacy] then legacy = "RIGHT" end
            directions[legacy] = true
        end
        return directions
    end
    local function ToggleGradientDirectionForScope(direction)
        direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
        local directions = CurrentGradientDirectionsForScope()
        directions[direction] = not directions[direction]
        local any = false
        for dir in pairs(GRADIENT_DIR_KEYS) do
            if directions[dir] == true then
                any = true
                break
            end
        end
        if not any then directions[direction] = true end
        for dir, key in pairs(GRADIENT_DIR_KEYS) do
            GradientScopeSet(key, directions[dir] == true)
        end
        GradientScopeSet("gradientDirection", direction)
    end
    local function ApplyGradientRuntime(reason)
        if (GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true) then
            local strength = tonumber(GradientScopeGet("gradientStrength", nil))
            if not (strength and strength > 0) then GradientScopeSet("gradientStrength", 0.45) end
        end
        local scope = CurrentBarsScope()
        local applyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if applyService and type(applyService.RequestBarGradients) == "function" then
            applyService.RequestBarGradients(reason or "MSUF2_GRADIENT", scope)
            return
        end
        M.RequestGeneralApply(reason or "MSUF2_GRADIENT", {
            preview = true,
            applyAll = false,
            notify = false,
            bars = true,
            barGradients = true,
            barsScope = scope,
        })
        ScheduleBarsPageWork("MSUF2_BARS_GRADIENT_RUNTIME", BARS_PAGE_WORK_DELAY, function()
            local started = BarsProfileStart()
            Call("MSUF_UpdateAllBarGradients", scope)
            BarsProfileStop("GradientRuntime", started)
        end)
    end
    local function SetOutlineRGB(entry, r, g, b)
        if entry.barOutlineColorR == r and entry.barOutlineColorG == g and entry.barOutlineColorB == b
            and entry.barOutlineColorA == 1 and entry.barOutlineColorMode == nil then
            return false
        end
        entry.barOutlineColorMode = nil
        entry.barOutlineColorR, entry.barOutlineColorG, entry.barOutlineColorB, entry.barOutlineColorA = r, g, b, 1
        return true
    end
    local function SetOutlineColorForScope(r, g, b)
        r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
        local scope = CurrentBarsScope()
        if scope == "shared" then return SetOutlineRGB(G(), r, g, b) end
        local keys = ScopeDBKeys(scope)
        if not keys then return SetOutlineRGB(G(), r, g, b) end
        ScopeSetOverride(scope, "hlOverride", true)
        local db = DB()
        local changed = false
        for i = 1, #keys do
            local key = keys[i]
            db[key] = db[key] or {}
            local entry = db[key]
            changed = SetOutlineRGB(entry, r, g, b) or changed
        end
        return changed
    end
    local function BarTextureForScope()
        local scope = CurrentBarsScope()
        if scope ~= "shared" and not IsGFScope(scope) then return ReadG("barTexture", "Blizzard") end
        return BarScopeGet("barTexture", ReadG("barTexture", "Blizzard"))
    end
    local function GeneralBarBackgroundTextureKey()
        local general = G()
        local key = general.barBackgroundTexture
        if key == nil then key = general.barBgTexture end
        return key or ""
    end
    local function SetBarTextureForScope(value)
        value = value or "Blizzard"
        local scope = CurrentBarsScope()
        if scope ~= "shared" and not IsGFScope(scope) then return false end
        if BarTextureForScope() == value then return false end
        BarScopeSet("barTexture", value, "MSUF2_BAR_TEXTURE")
        return true
    end
    local function BarBackgroundTextureForScope()
        local scope = CurrentBarsScope()
        if scope ~= "shared" and not IsGFScope(scope) then return GeneralBarBackgroundTextureKey() end
        if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
            local db = DB()
            local keys = ScopeDBKeys(scope)
            for i = 1, #(keys or {}) do
                local entry = db[keys[i]]
                if entry then
                    if entry.barBackgroundTexture ~= nil then return entry.barBackgroundTexture end
                    if entry.barBgTexture ~= nil then return entry.barBgTexture end
                end
            end
        end
        return GeneralBarBackgroundTextureKey()
    end
    local function SetGeneralBarBackgroundTexture(value)
        local general = G()
        if general.barBackgroundTexture == value then return false end
        general.barBackgroundTexture = value
        return true
    end
    local function SetBarBackgroundTextureForScope(value)
        value = value or ""
        local scope = CurrentBarsScope()
        if scope == "shared" then return SetGeneralBarBackgroundTexture(value) end
        if not IsGFScope(scope) then return false end
        local keys = ScopeDBKeys(scope)
        if not keys then return SetGeneralBarBackgroundTexture(value) end
        ScopeSetOverride(scope, "hlOverride", true)
        local db = DB()
        local changed = false
        for i = 1, #keys do
            local key = keys[i]
            db[key] = db[key] or {}
            local entry = db[key]
            if entry.barBackgroundTexture ~= value or entry.barBgTexture ~= value then changed = true end
            entry.barBackgroundTexture = value
            entry.barBgTexture = value
        end
        return changed
    end
    local scopeValues = GP.SCOPE_VALUES
    GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            if _G.MSUF_AbsorbTextureTestMode then SetAbsorbTextureTest(true) end
            RefreshBorderTestModes()
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "hlOverride")
        end,
        getOverride = function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        setOverride = function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
            end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        reset = function()
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then ScopeSetOverride(key, "hlOverride", false) end
            end
            ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end,
        hint = "Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.",
        updateHint = function(hint, current, active, shared)
            if shared then
                hint:SetText("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
            elseif IsGFScope(current) and ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This group scope can use custom textures and gradients. Raid also applies to Mythic Raid.")
            elseif ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This scope can use custom gradients and bar settings. Textures still follow Shared.")
            else
                hint:SetText("This scope follows Shared bar settings. Turn on custom settings here when this scope needs different gradients or bar settings.")
            end
        end,
    })
    local compactTextures = (ctx.width or 720) < 560
    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 326 or 214, true)
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    local gradientY = compactTextures and (topY - 126) or topY
    local function BindTextureDropdown(label, values, getValue, setValue, y)
        local control = W.Dropdown(textures, label, values, leftW)
        M.BindDropdownWidget(ctx, control, getValue, setValue)
        W.MoveWidget(control, textures, leftX, y, leftW, "LEFT")
        return control
    end
    local barTexture = BindTextureDropdown("Bar textures (SharedMedia)", function() return TextureValues(nil) end, BarTextureForScope,
        function(v)
            if SetBarTextureForScope(v) then
                ApplyBars("MSUF2_BAR_TEXTURE")
                RefreshGroupFrameVisuals()
            end
        end, topY)
    local bgTexture = BindTextureDropdown("Background texture", function() return TextureValues("Use foreground texture") end, BarBackgroundTextureForScope,
        function(v)
            if SetBarBackgroundTextureForScope(v) then
                ApplyBars("MSUF2_BAR_BG_TEXTURE")
                RefreshGroupFrameVisuals()
            end
        end, topY - 54)
    local gradLabel = T.Font(textures, "GameFontHighlightSmall", M.Tr("Gradient"), T.colors.muted)
    gradLabel:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, gradientY)
    local SyncGradientControls = M.RefreshProxy()
    local function BindGradientToggle(label, y, width, key, reason)
        local control = W.ToggleAt(textures, label, rightX, y, width)
        M.BindBoolWidget(ctx, control,
            function() return GradientScopeGet(key, false) == true end,
            function(v) GradientScopeSet(key, v and true or false); ApplyGradientRuntime(reason); SyncGradientControls() end)
        return control
    end
    local hpGradient = BindGradientToggle("HP bar gradient", gradientY - 24, compactTextures and 150 or 180, "enableGradient", "MSUF2_HP_GRADIENT")
    local powerGradient = BindGradientToggle("Power bar gradient", gradientY - 54, compactTextures and 170 or 190, "enablePowerGradient", "MSUF2_POWER_GRADIENT")
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    M.BindNumberWidget(ctx, strength,
        function() return tonumber(GradientScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v)
            GradientScopeSet("gradientStrength", tonumber(v) or 0.45)
            ApplyGradientRuntime("MSUF2_GRADIENT_STRENGTH")
        end,
        0.45)
    W.MoveWidget(strength, textures, rightX, gradientY - 90, compactTextures and math.min(leftW, 300) or 220, "LEFT")
    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local pad = T.Panel(textures, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, gradientY - 18)
    pad:SetSize(84, 64)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", pad, "CENTER", 0, 0)
    center:SetSize(10, 10)
    local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
    center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
    local directionButtons = {}
    local function PadButton(text, value, x, y)
        local btn = T.Button(pad, text, 22, 18)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, y)
        T.CenterButtonLabel(btn)
        btn:SetScript("OnClick", function()
            ToggleGradientDirectionForScope(value or "RIGHT")
            ApplyGradientRuntime("MSUF2_GRADIENT_DIRECTION")
            SyncGradientControls()
        end)
        directionButtons[value] = btn
        return btn
    end
    PadButton("^", "UP", 31, -5)
    PadButton("<", "LEFT", 8, -27)
    PadButton(">", "RIGHT", 54, -27)
    PadButton("v", "DOWN", 31, -49)
    local textureControls = { barTexture, bgTexture }
    local gradientControls = { hpGradient, powerGradient }
    M.TrackRefresh(ctx, SyncGradientControls(function()
        local current = CurrentGradientDirectionsForScope()
        local textureControlsActive = TextureControlsActive()
        local gradientControlsActive = GradientControlsActive()
        local valueControlsActive = gradientControlsActive and ((GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true))
        SetControlsEnabled(textureControls, textureControlsActive)
        SetControlsEnabled(gradientControls, gradientControlsActive)
        SetControlEnabled(strength, valueControlsActive)
        pad:SetAlpha(valueControlsActive and 1 or 0.45)
        for value, btn in pairs(directionButtons) do
            btn:SetActive(current[value] == true)
            SetControlEnabled(btn, valueControlsActive)
        end
    end))
    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 420, true)
    local absorbW = absorb._msuf2Width or ctx.width or 720
    local absorbLeftX = 30
    local absorbRightX = max(430, min(560, floor(absorbW * 0.52)))
    local absorbLeftW = max(300, min(380, absorbRightX - absorbLeftX - 58))
    local absorbRightW = max(300, min(420, absorbW - absorbRightX - 42))
    W.LabelAt(absorb, "Display", absorbLeftX, -42, absorbLeftW, "GameFontNormalSmall", T.colors.accent)
    local absorbMode = W.Dropdown(absorb, "Display mode", VT(1, "Absorb off", 2, "Absorb bar"), absorbLeftW)
    local function ReadAbsorbDisplayMode()
        local mode = tonumber(BarScopeGet("absorbTextMode", 2)) or 2
        return (mode == 1 or mode == 4) and 1 or 2
    end
    local function ApplyAbsorbRuntime(reason) Call("MSUF_InvalidateAbsorbCache"); ApplyBars(reason); RefreshGroupFrameVisuals() end
    local SyncAbsorbControls = M.RefreshProxy()
    local function AbsorbDefault(value) return type(value) == "function" and value() or value end
    local function BindAbsorbDropdown(label, values, key, defaultValue, reason, x, y, width, numeric)
        local control = W.Dropdown(absorb, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local fallback = AbsorbDefault(defaultValue)
                local value = BarScopeGet(key, fallback)
                return numeric and (tonumber(value) or fallback) or value
            end,
            function(v)
                local fallback = AbsorbDefault(defaultValue)
                BarScopeSet(key, numeric and (tonumber(v) or fallback) or (v or fallback), reason)
                ApplyAbsorbRuntime(reason)
            end)
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BindAbsorbSlider(label, minValue, maxValue, step, key, defaultValue, reason, x, y, width)
        local control = W.Slider(absorb, label, minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                BarScopeSet(key, tonumber(v) or defaultValue, reason)
                ApplyAbsorbRuntime(reason)
            end,
            defaultValue)
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BuildAbsorbControlSpecs(specs)
        return M.BuildControlSpecs(specs, {
            dropdown = function(s, i) return BindAbsorbDropdown(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10]), s[11] or s[4] or i end,
            slider = function(s, i) return BindAbsorbSlider(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[6] or i end,
        })
    end
    M.BindDropdownWidget(ctx, absorbMode,
        ReadAbsorbDisplayMode,
        function(v)
            local mode = (tonumber(v) == 1) and 1 or 2
            BarScopeSet("absorbTextMode", mode, "MSUF2_ABSORB_MODE")
            ApplyAbsorbRuntime("MSUF2_ABSORB_MODE")
            SyncAbsorbControls()
        end)
    W.MoveWidget(absorbMode, absorb, absorbLeftX, -70, absorbLeftW, "LEFT")
    local absorbAnchors = VT(
        1, "Anchor to left side", 2, "Anchor to right side", 3, "Follow HP bar",
        4, "Follow HP bar (overflow)", 5, "Reverse from max")
    local absorbControls = BuildAbsorbControlSpecs({
        { "dropdown", "Absorb bar anchoring", absorbAnchors, "absorbAnchorMode", 2, "MSUF2_ABSORB_ANCHOR", absorbLeftX, -124, absorbLeftW, true, "anchor" },
        { "dropdown", "Heal prediction anchoring", absorbAnchors, "healPredAnchorMode", 3, "MSUF2_HEALPRED_ANCHOR", absorbLeftX, -240, absorbLeftW, true, "healAnchor" },
        { "slider", "Absorb bar opacity", 0, 1, 0.05, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY", absorbLeftX, -294, absorbLeftW, "opacity" },
        { "dropdown", "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, "absorbBarTexture", function() return ReadG("absorbBarTexture", "") end, "MSUF2_ABSORB_TEXTURE", absorbRightX, -70, absorbRightW, nil, "texture" },
        { "dropdown", "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, "healAbsorbBarTexture", function() return ReadG("healAbsorbBarTexture", "") end, "MSUF2_HEAL_ABSORB_TEXTURE", absorbRightX, -124, absorbRightW, nil, "healTexture" },
        { "slider", "Heal-absorb bar opacity", 0, 1, 0.05, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY", absorbRightX, -294, absorbRightW, "healOpacity" },
    })
    local healPredToggle = W.ToggleAt(absorb, "Heal Prediction Overlay", absorbLeftX, -186, absorbLeftW)
    M.BindBoolWidget(ctx, healPredToggle,
        function()
            if CurrentBarsScopeIsGroupFrame() then return BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true end
            return ReadGBool("showSelfHealPrediction", false)
        end,
        function(v)
            if CurrentBarsScopeIsGroupFrame() then
                BarScopeSet("healPredEnabled", v and true or false, "MSUF2_GF_HEALPRED")
                Call("MSUF_InvalidateAbsorbCache")
                ApplyBars("MSUF2_GF_HEALPRED")
                RefreshGroupFrameVisuals()
                SyncAbsorbControls()
                return
            end
            SetGBool("showSelfHealPrediction", v, "MSUF2_SELF_HEAL", { preview = true })
            Call("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyBars("MSUF2_SELF_HEAL")
            SyncAbsorbControls()
        end)
    W.LabelAt(absorb, "Textures", absorbRightX, -42, absorbRightW, "GameFontNormalSmall", T.colors.accent)
    local absorbTest = W.ToggleAt(absorb, "Test prediction bars", absorbRightX, -186, absorbRightW)
    M.BindBoolWidget(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end)
    absorbTest:HookScript("OnHide", function() ClearAbsorbTextureTest() end)
    local overAbsorbOverlay = W.ToggleAt(absorb, "Over-absorb overlay", absorbRightX, -240, absorbRightW)
    M.BindBoolWidget(ctx, overAbsorbOverlay,
        function() return BarScopeGet("overAbsorbOverlay", ReadGBool("overAbsorbOverlay", false)) == true end,
        function(v)
            BarScopeSet("overAbsorbOverlay", v and true or false, "MSUF2_OVER_ABSORB_OVERLAY")
            ApplyAbsorbRuntime("MSUF2_OVER_ABSORB_OVERLAY")
            SyncAbsorbControls()
        end)
    local absorbBarControls = { absorbControls.anchor, absorbControls.texture, absorbControls.healTexture, absorbControls.opacity, absorbControls.healOpacity, overAbsorbOverlay }
    M.TrackRefresh(ctx, SyncAbsorbControls(function()
        local mode = ReadAbsorbDisplayMode()
        local showBar = mode == 2
        local scopedActive = ScopedBarsControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local groupScope = CurrentBarsScopeIsGroupFrame()
        local healPredOn
        if groupScope then
            healPredOn = BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
        else
            healPredOn = ReadGBool("showSelfHealPrediction", false)
        end
        SetControlEnabled(absorbMode, scopedActive)
        SetControlsEnabled(absorbBarControls, scopedActive and showBar)
        SetControlEnabled(absorbTest, true)
        SetControlEnabled(healPredToggle, groupScope and scopedActive or sharedActive)
        SetControlEnabled(absorbControls.healAnchor, scopedActive and healPredOn)
    end))
    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 220, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindNumberWidget(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v)
            BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE")
            ApplyBars("MSUF2_BAR_OUTLINE")
            RequestOutlineRuntime()
        end,
        1, { step = 1, roundStep = true })
    outline._msuf2OutlineLevel = W.Slider(outline, "", 0, FRAME_OUTLINE_LEVEL_MAX, 1, 300)
    M.BindNumberWidget(ctx, outline._msuf2OutlineLevel,
        function()
            return NormalizeFrameOutlineLevelOffset(BarScopeGetBars("barOutlineLevelOffset", FRAME_OUTLINE_LEVEL_DEFAULT), FRAME_OUTLINE_LEVEL_DEFAULT)
        end,
        function(v)
            BarScopeSetBars("barOutlineLevelOffset", NormalizeFrameOutlineLevelOffset(v, FRAME_OUTLINE_LEVEL_DEFAULT), "MSUF2_BAR_OUTLINE_LEVEL")
            ApplyBars("MSUF2_BAR_OUTLINE_LEVEL")
            RequestOutlineRuntime()
        end,
        FRAME_OUTLINE_LEVEL_DEFAULT, { step = 1, roundStep = true })
    outline._msuf2OutlineLevel:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        RefreshFrameOutlineLevelLabel(self, value)
    end)
    M.AddRefresher(ctx, function() RefreshFrameOutlineLevelLabel(outline._msuf2OutlineLevel, BarScopeGetBars("barOutlineLevelOffset", FRAME_OUTLINE_LEVEL_DEFAULT)) end)
    RefreshFrameOutlineLevelLabel(outline._msuf2OutlineLevel, BarScopeGetBars("barOutlineLevelOffset", FRAME_OUTLINE_LEVEL_DEFAULT))
    local outlineColor = W.Color(outline, "Outline color")
    W.MoveWidget(outlineColor, outline, 30, -150)
    M.BindColor(ctx, outlineColor,
        function()
            return tonumber(BarScopeGet("barOutlineColorR", ReadG("barOutlineColorR", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorG", ReadG("barOutlineColorG", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorB", ReadG("barOutlineColorB", 0))) or 0
        end,
        function(r, g, b)
            if SetOutlineColorForScope(r, g, b) then
                ApplyBars("MSUF2_BAR_OUTLINE_COLOR")
                RequestOutlineRuntime()
            end
        end)
    M.BindGateGroup(ctx, nil, {
        { controls = { outlineSlider, outline._msuf2OutlineLevel, outlineColor }, on = ScopedBarsControlsActive },
    })
    local rounded = b:CollapsibleSection("bars_rounded", "Rounded Texture", 246, true)
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture",
        "rounded section|rounded menu|rounded options|where rounded frames|wo rounded frames",
        "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local SyncRoundedControls = M.RefreshProxy()
    local function BindRoundedToggle(label, x, y, key, defaultOn, requireReload, searchKeywords, help, useSwitch)
        local control = (useSwitch and W.SwitchAt or W.ToggleAt)(rounded, label, x, y, roundW)
        M.BindBoolWidget(ctx, control,
            function()
                local value = ReadB(key, defaultOn)
                return defaultOn and value ~= false or value == true
            end,
            function(v)
                SetRoundedBool(key, v, requireReload)
                SyncRoundedControls()
            end)
        RegisterRoundedSearch(control, label, searchKeywords, help)
        return control
    end
    local roundedControls = M.BuildControlSpecs({
        { "master", "Rounded frame texture", roundLeftX, -52, "roundedFramesEnabled", false, true, "master toggle|all rounded frames|rounded frames master|rounded frames on|rounded frames off|rounded frames einschalten|rounded frames ausschalten|alle abgerundeten frames", "Master switch for the rounded frame texture style.", true },
        { "units", "Unit frames", roundLeftX, -90, "roundedUnitFrames", true, nil, "rounded unit frames|rounded unitframes|unit frame corners|unitframe corners|abgerundete unitframes|unitframes abgerundet|player target focus boss rounded", "Enable or disable rounded textures on unit frames." },
        { "groups", "Group frames", roundLeftX, -128, "roundedGroupFrames", true, nil, "rounded group frames|rounded party frames|rounded raid frames|group frame corners|abgerundete gruppenframes|party raid abgerundet", "Enable or disable rounded textures on group frames." },
        { "power", "Power bars", roundRightX, -52, "roundedPowerBars", true, nil, "rounded power bars|rounded powerbar|power bar corners|powerbar corners|powerbars abgerundet|powerbar abrunden", "Enable or disable rounded textures on power bars." },
        { "mouseover", "Mouseover highlights", roundRightX, -90, "roundedMouseover", true, nil, "rounded mouseover|rounded hover|rounded hover border|mouseover rounded|mouseover highlight rounded|mouseover abgerundet|hover abgerundet", "Enable or disable rounded mouseover highlight edges." },
    }, { ["*"] = function(s) return BindRoundedToggle(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10]), s[1] end })
    local roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -154, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview",
        "rounded preview|rounded example|rounded image|rounded frame preview|preview rounded frames|rounded frames aussehen|vorschau abgerundete frames",
        "Shows a small preview of the rounded frame texture style.", "preview")
    local roundedDependentControls = { roundedControls.units, roundedControls.groups, roundedControls.power, roundedControls.mouseover }
    SyncRoundedControls(M.BindGateGroup(ctx, nil, {
        { controls = roundedDependentControls, on = function() return ReadB("roundedFramesEnabled", false) == true end },
    }, {
        also = function() if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end end,
    }))
    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 710, true)
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlPreviewX = hlLeftX
    local hlPreviewW = max(280, min(440, hlInnerW - 28))
    local highlightTabFrames = {}
    local modesFrame, previewFrame, priorityFrame =
        M.UnitSectionsShared.MakeTabFrames(highlights, -88, hlW, highlightTabFrames, "modes", "preview", "priority")
    W.SegmentTabs(ctx, highlights, {
        stateKey = "barsHighlightTab", label = "Highlight area",
        values = VT("modes", "Modes", "preview", "Preview", "priority", "Priority"),
        width = min(520, hlInnerW), frames = highlightTabFrames, defaultTab = "modes",
        x = hlLeftX, y = -44,
    })
    W.ControlCard(modesFrame, "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 542)
    local priorityCardW = min(360, max(260, hlLeftW + 28))
    local priorityCard = W.ControlCard(priorityFrame, "Priority Order", nil, hlLeftX - 14, -38, priorityCardW, 296)
    W.ControlCard(previewFrame, "Preview", nil, hlPreviewX - 14, -38, hlPreviewW + 28, 248)
    local function HighlightPriorityEnabled()
        local value = BarScopeGet("hlPrioEnabled", nil)
        if value == nil then value = BarScopeGet("highlightPrioEnabled", false) end
        return value == true or value == 1 or value == "1"
    end
    local highlight = W.Slider(modesFrame, "Highlight border thickness", 1, 30, 1, hlLeftW)
    M.BindNumberWidget(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER")
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER")
            ApplyBars("MSUF2_HIGHLIGHT_BORDER")
            RequestAllHighlightBorderRuntime()
        end,
        2, { step = 1, roundStep = true })
    W.MoveWidget(highlight, modesFrame, hlLeftX, -70, hlLeftW, "LEFT")
    local borderModes = VT(0, "Off", 1, "On")
    local function StopBorderTest(flag, setter, value)
        if value == 1 or not _G[flag] then return end
        local fn = _G[setter]
        if type(fn) == "function" then fn(false) end
    end
    local function BindHighlightDropdown(label, values, y, getValue, setValue)
        local control = W.Dropdown(modesFrame, label, values, hlLeftW)
        M.BindDropdownWidget(ctx, control, getValue, setValue)
        W.MoveWidget(control, modesFrame, hlLeftX, y, hlLeftW, "LEFT")
        return control
    end
    local function BindBorderModeDropdown(label, key, defaultValue, reason, y, flag, setter, apply)
        return BindHighlightDropdown(label, borderModes, y,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                local value = tonumber(v) or defaultValue
                BarScopeSet(key, value, reason)
                StopBorderTest(flag, setter, value)
                ApplyBars(reason)
                apply()
            end)
    end
    local aggroModeValues = VT("ALL", "All roles", "NON_TANK", "Non-tanks", "HEALER", "Healers only", "TANK", "Tanks only")
    local function NormalizeAggroMode(value)
        value = tostring(value or "ALL"):upper()
        if value == "TANK_ONLY" then return "TANK" end
        if value == "HEALER_ONLY" then return "HEALER" end
        if value == "NON_TANK" or value == "HEALER" or value == "TANK" then return value end
        return "ALL"
    end
    local aggro = BindBorderModeDropdown("Aggro border", "aggroOutlineMode", 1, "MSUF2_AGGRO_BORDER", -136,
        "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", RequestAggroBorderRuntime)
    local aggroMode = BindHighlightDropdown("Aggro shows for", aggroModeValues, -190,
        function() return NormalizeAggroMode(BarScopeGet("aggroMode", "ALL")) end,
        function(v)
            BarScopeSet("aggroMode", NormalizeAggroMode(v), "MSUF2_AGGRO_MODE")
            ApplyBars("MSUF2_AGGRO_MODE")
            RequestAggroBorderRuntime()
        end)
    local dispelBorder = BindBorderModeDropdown("Dispel border", "dispelOutlineMode", 1, "MSUF2_DISPEL_BORDER", -244,
        "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", RequestDispelPurgeBorderRuntime)
    local dispelTrigger = BindHighlightDropdown("Dispel border detects", dispelTriggers, -298,
        function() return NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "DISPEL_TYPE")) end,
        function(v)
            BarScopeSet("dispelBorderTrigger", NormalizeDispelTrigger(v), "MSUF2_DISPEL_TRIGGER")
            RequestDispelPurgeBorderRuntime()
        end)
    local purge = BindBorderModeDropdown("Purge border", "purgeOutlineMode", 0, "MSUF2_PURGE_BORDER", -352,
        "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", RequestDispelPurgeBorderRuntime)
    local bossTarget = BindHighlightDropdown("Boss target border", borderModes, -406,
        function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        function(v)
            local value = tonumber(v) or 1
            SetG("bossTargetOutlineMode", value, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            SetGBool("bossTargetHighlightEnabled", value == 1, "MSUF2_BOSS_TARGET_BORDER", { preview = true })
            StopBorderTest("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", value)
            ApplyBars("MSUF2_BOSS_TARGET_BORDER")
            RequestBossTargetBorderRuntime()
        end)
    local dispelPurgePtrHint = W.Text(modesFrame, DISPEL_PURGE_BORDER_121_PTR_MESSAGE, hlLeftX, -456, hlLeftW, T.colors.dim)
    if dispelPurgePtrHint.SetWordWrap then dispelPurgePtrHint:SetWordWrap(true) end
    local bossSharedHint = W.Text(modesFrame, "Boss target border is a shared boss-frame setting.", hlLeftX, -486, hlLeftW, T.colors.dim)
    if bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end
    local unitAuraDispelHint = W.Text(modesFrame, UNITFRAME_DISPEL_AURA_WARNING, hlLeftX, -516, hlLeftW, UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if unitAuraDispelHint.SetWordWrap then unitAuraDispelHint:SetWordWrap(true) end
    local function ScopeBorderModeOn(key, defaultValue) return tonumber(BarScopeGet(key, defaultValue)) == 1 end
    local function BossTargetBorderOn()
        local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
        return (tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback) == 1
    end
    local function BindBorderTestToggle(label, y, flagName, setterName, enabledFn, noScope)
        local control = W.ToggleAt(previewFrame, label, hlPreviewX, y, hlPreviewW)
        M.BindBoolWidget(ctx, control,
            function() return _G[flagName] and true or false end,
            function(v)
                if v and not enabledFn() then
                    if M.RequestRefresh then M.RequestRefresh(ctx, "bars-border-test-disabled") elseif M.Refresh then M.Refresh(ctx) end
                    return
                end
                local fn = _G[setterName]
                if type(fn) == "function" then
                    if noScope then fn(v and true or false)
                    else fn(v and true or false, BorderTestScope()) end
                end
            end)
        control:HookScript("OnHide", function(self)
            local fn = _G[setterName]
            if _G[flagName] and type(fn) == "function" then
                fn(false)
                self:SetChecked(false)
            end
        end)
        return control
    end
    local aggroTest = BindBorderTestToggle("Test aggro border", -72, "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", function() return ScopeBorderModeOn("aggroOutlineMode", 1) end)
    local dispelTest = BindBorderTestToggle("Test dispel border", -104, "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", function() return ScopeBorderModeOn("dispelOutlineMode", 1) end)
    local purgeTest = BindBorderTestToggle("Test purge border", -214, "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", function() return ScopeBorderModeOn("purgeOutlineMode", 0) end)
    local bossTargetTest = BindBorderTestToggle("Test boss target border", -246, "MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", BossTargetBorderOn, true)
    local scopedBorderControls = { highlight, aggro, dispelBorder, purge }
    local dispelBorderControls = { dispelTrigger, dispelTest }
    local function ClearBorderTestIfDisabled(flagName, setterName, enabled)
        local fn = _G[setterName]
        if _G[flagName] and not enabled and type(fn) == "function" then fn(false) end
    end
    M.TrackRefresh(ctx, function()
        local scopedActive = HighlightControlsActive()
        local sharedActive = SharedBarsControlsActive()
        local aggroOn = ScopeBorderModeOn("aggroOutlineMode", 1)
        local dispelOn = ScopeBorderModeOn("dispelOutlineMode", 1)
        local purgeOn = ScopeBorderModeOn("purgeOutlineMode", 0)
        local bossTargetOn = BossTargetBorderOn()
        ClearBorderTestIfDisabled("MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", aggroOn)
        ClearBorderTestIfDisabled("MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", dispelOn and not DISPEL_BORDER_121_PTR_DISABLED)
        ClearBorderTestIfDisabled("MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", purgeOn and not PURGE_BORDER_121_PTR_DISABLED)
        ClearBorderTestIfDisabled("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", sharedActive and bossTargetOn)
        SetControlsEnabled(scopedBorderControls, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive and not DISPEL_BORDER_121_PTR_DISABLED)
        SetControlEnabled(purge, scopedActive and not PURGE_BORDER_121_PTR_DISABLED)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroMode, scopedActive and aggroOn)
        SetControlEnabled(aggroTest, scopedActive and aggroOn)
        SetControlsEnabled(dispelBorderControls, scopedActive and dispelOn and not DISPEL_BORDER_121_PTR_DISABLED)
        SetControlEnabled(purgeTest, scopedActive and purgeOn and not PURGE_BORDER_121_PTR_DISABLED)
        SetControlEnabled(bossTargetTest, sharedActive and bossTargetOn)
        if dispelPurgePtrHint and dispelPurgePtrHint.SetShown then dispelPurgePtrHint:SetShown(PURGE_BORDER_121_PTR_DISABLED) end
        if unitAuraDispelHint and unitAuraDispelHint.SetShown then unitAuraDispelHint:SetShown((not CurrentBarsScopeIsGroupFrame()) and not AnyUnitFrameAuraEnabled()) end
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1)
    end)
    local overlaySectionW = ctx.width or 720
    local overlayCardWProbe = min(900, max(320, overlaySectionW - 40))
    local overlayWide = overlayCardWProbe >= 760
    local overlaySectionH = overlayWide and 358 or 468
    local overlayCardH = overlayWide and 294 or 404
    local ufOverlay = b:CollapsibleSection("bars_unit_dispel_overlay", "UnitFrame Dispel Overlay", overlaySectionH, false)
    local ufOverlayW = ufOverlay._msuf2Width or ctx.width or 720
    local ufOverlayCardW = min(900, max(320, ufOverlayW - 40))
    overlayWide = ufOverlayCardW >= 760
    overlayCardH = overlayWide and 294 or 404
    local ufOverlayCard = W.ControlCard(ufOverlay, "UnitFrame Dispel Overlay", "Tints unit-frame health bars when a configured debuff condition is active.", 20, -38, ufOverlayCardW, overlayCardH)
    local function BindUFOverlayDropdown(label, values, key, defaultValue, normalizer, reason, y)
        local dropdown = W.Dropdown(ufOverlayCard, label, values, 280)
        M.BindDropdownWidget(ctx, dropdown,
            function()
                local value = BarScopeGet(key, defaultValue)
                return normalizer and normalizer(value) or value
            end,
            function(value)
                BarScopeSet(key, normalizer and normalizer(value) or (value or defaultValue), reason)
                RequestUnitDispelOverlayRuntime(reason)
            end)
        W.MoveWidget(dropdown, ufOverlayCard, 16, y, min(280, ufOverlayCardW - 32), "LEFT")
        return dropdown
    end
    local SyncUFOverlayControls = M.RefreshProxy()
    local function BindUFOverlayToggle(label, key, defaultOn, reason, y)
        local toggle = W.ToggleAt(ufOverlayCard, label, 16, y, ufOverlayCardW - 32)
        M.BindBoolWidget(ctx, toggle,
            function() return BarScopeGet(key, defaultOn) ~= false end,
            function(value)
                BarScopeSet(key, value and true or false, reason)
                RequestUnitDispelOverlayRuntime(reason)
                SyncUFOverlayControls()
            end)
        return toggle
    end
    local function BindUFOverlaySlider(label, key, defaultValue, reason, y)
        local slider = W.Slider(ufOverlayCard, label, 0.05, 1, 0.05, 340)
        M.BindNumberWidget(ctx, slider,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(value)
                BarScopeSet(key, tonumber(value) or defaultValue, reason)
                RequestUnitDispelOverlayRuntime(reason)
            end,
            defaultValue)
        W.MoveWidget(slider, ufOverlayCard, 16, y, min(360, ufOverlayCardW - 72), "CENTER")
        return slider
    end
    local ufOverlayToggle = W.SwitchAt(ufOverlayCard, "UnitFrame Dispel Overlay", ufOverlayCardW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, ufOverlayToggle,
        function() return BarScopeGet("unitDispelOverlayEnabled", false) == true end,
        function(v)
            BarScopeSet("unitDispelOverlayEnabled", v and true or false, "MSUF2_UF_DISPEL_OVERLAY")
            RequestUnitDispelOverlayRuntime("MSUF2_UF_DISPEL_OVERLAY")
            SyncUFOverlayControls()
        end)
    local ufOverlayTrigger = BindUFOverlayDropdown("Overlay detects", unitDispelOverlayTriggers, "unitDispelOverlayTrigger", "BORDER", NormalizeUnitDispelOverlayTrigger, "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", -74)
    local ufOverlayStyle = BindUFOverlayDropdown("Overlay style", unitDispelOverlayStyles, "unitDispelOverlayStyle", "FULL", nil, "MSUF2_UF_DISPEL_OVERLAY_STYLE", -126)
    local ufOverlayCurrent = BindUFOverlayToggle("Show on current health only", "unitDispelOverlayOnHealth", true, "MSUF2_UF_DISPEL_OVERLAY_HEALTH", -174)
    local ufOverlayAlpha = BindUFOverlaySlider("Overlay opacity", "unitDispelOverlayAlpha", 0.35, "MSUF2_UF_DISPEL_OVERLAY_ALPHA", -218)
    local ufOverlayControls = { ufOverlayTrigger, ufOverlayStyle, ufOverlayCurrent, ufOverlayAlpha }
    local ufOverlayGroupHintY = overlayWide and -284 or -384
    local ufOverlayGroupHint = W.Text(ufOverlayCard, "Group frame scopes use Group Frames > Health & Bars > Dispel Overlay.", 16, ufOverlayGroupHintY, ufOverlayCardW - 32, T.colors.muted)
    if ufOverlayGroupHint.SetWordWrap then ufOverlayGroupHint:SetWordWrap(true) end
    local ufOverlayUnitAuraHint = W.Text(ufOverlayCard, UNITFRAME_DISPEL_AURA_WARNING, 16, ufOverlayGroupHintY, ufOverlayCardW - 32, UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if ufOverlayUnitAuraHint.SetWordWrap then ufOverlayUnitAuraHint:SetWordWrap(true) end
    M.TrackRefresh(ctx, SyncUFOverlayControls(function()
        local groupScope = CurrentBarsScopeIsGroupFrame()
        local activeScope = (not groupScope) and ScopedBarsControlsActive()
        local overlayOn = activeScope and BarScopeGet("unitDispelOverlayEnabled", false) == true
        SetControlEnabled(ufOverlayToggle, activeScope)
        SetControlsEnabled(ufOverlayControls, overlayOn)
        ufOverlayGroupHint:SetShown(groupScope)
        ufOverlayUnitAuraHint:SetShown((not groupScope) and not AnyUnitFrameAuraEnabled())
    end))
    local RefreshPriorityRows
    local prio = W.SwitchAt(priorityCard, "Custom highlight priority", 16, -54, priorityCardW - 32)
    M.BindBoolWidget(ctx, prio,
        HighlightPriorityEnabled,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY")
            if CurrentBarsScope() == "shared" then
                G().hlPrioEnabled = on and 1 or 0
                G().highlightPrioEnabled = on and 1 or 0
            end
            RequestHighlightPriorityRuntime()
            if RefreshPriorityRows then RefreshPriorityRows() end
        end)
    local rowMax = 4
    local prioContainer, prioRows, prioCount
    local function SavePriorityRows()
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            SetPriorityOrder(order)
            RequestHighlightPriorityRuntime()
        end
        M.RunWithHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
    end
    local function SetPriorityRowsEnabled(enabled)
        prioContainer:SetRowsEnabled(enabled)
    end
    prioContainer = M.UnitSectionsShared.MakeDragSortRows(priorityCard, nil, {
        x = 16, y = -82, width = min(220, priorityCardW - 32), rowHeight = 22, gap = 4, maxRows = rowMax,
        bg = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.30, 0.30, 0.30, 0.60 },
        disabledAlpha = 0.4,
        dragAllowed = function() return HighlightControlsActive() and HighlightPriorityEnabled() end,
        onReorder = SavePriorityRows,
    })
    prioRows = prioContainer.rows
    RefreshPriorityRows = function()
        SetControlEnabled(prio, HighlightControlsActive())
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(M.Tr(PRIORITY_LABELS[key] or key))
            row.frame._numText:SetText(tostring(i))
        end
        prioContainer:SetActiveCount(prioCount)
        SetPriorityRowsEnabled(HighlightControlsActive() and HighlightPriorityEnabled())
    end
    M.TrackRefresh(ctx, RefreshPriorityRows)
    local power = b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 152, false)
    local smoothPower = W.Toggle(power, "Smooth power bar")
    M.BindBoolWidget(ctx, smoothPower,
        function() return SmoothPowerGet() end,
        function(v) SmoothPowerSet(v, "MSUF2_BARS_SMOOTH_POWER"); ApplyBars("MSUF2_BARS_SMOOTH_POWER") end)
    local realtimePower = W.Toggle(power, "Realtime power text")
    M.BindBoolWidget(ctx, realtimePower,
        function() return ReadB("realtimePowerText", true) ~= false end,
        function(v) SetB("realtimePowerText", v and true or false, "MSUF2_BARS_REALTIME_POWER", { preview = true }); ApplyBars("MSUF2_BARS_REALTIME_POWER") end)
    M.BindGateGroup(ctx, nil, {
        { controls = smoothPower, on = function() return CurrentPowerBarScopeUnit() ~= nil end },
        { controls = realtimePower, on = SharedBarsControlsActive },
    })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 16 })

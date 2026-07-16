_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_ApplyService.lua"
local handle = io.open(path, "r")
if not handle then path = "Shell/Menu2/MSUF_Menu2_ApplyService.lua" else handle:close() end

local scheduled = {}
local calls = {}
local order = {}
local lastBarArgs
local lastFontArgs
local lastGroupKind
local lastGroupMask
local lastGroupPreviewKind
local lastGroupPreviewOpts
local lastPriorityReason
local lastNotifyMask
local lastApplyMask
local function Count(name)
    calls[name] = (calls[name] or 0) + 1
    order[#order + 1] = name
    return true
end
local function ResetCalls()
    for key in pairs(calls) do calls[key] = nil end
    for i = #order, 1, -1 do order[i] = nil end
    lastBarArgs, lastFontArgs, lastGroupKind, lastGroupMask = nil, nil, nil, nil
    lastGroupPreviewKind, lastGroupPreviewOpts, lastPriorityReason = nil, nil, nil
    lastNotifyMask, lastApplyMask = nil, nil
end
local function FlushOne()
    assert(#scheduled == 1, "expected exactly one coalesced ApplyService flush")
    local fn = table.remove(scheduled, 1)
    fn()
end
local function IndexOf(name)
    for i = 1, #order do if order[i] == name then return i end end
end

_G.C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end }
_G.InCombatLockdown = function() return false end
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function() end,
    }
end
_G.MSUF_UFCore_RefreshSettingsCache = function() return Count("settings") end
_G.MSUF_UFCore_NotifyConfigChanged = function(_, _, _, _, mask)
    lastNotifyMask = mask
    Count("notify")
    return true
end
_G.MSUF_UpdateAllFonts_Immediate = function(scope, skipUnitFrames, skipCastbars, skipClassPower)
    lastFontArgs = { scope, skipUnitFrames, skipCastbars, skipClassPower }
    return Count("fontsImmediate")
end
_G.MSUF_UpdateAllBarTextures_Immediate = function(scope, skipUnitFrames, skipCastbars)
    lastBarArgs = { scope, skipUnitFrames, skipCastbars }
    return Count("barsImmediate")
end
_G.MSUF_UpdateAllBarTextures = function() return Count("barsDeferred") end
_G.MSUF_UpdateCastbarTextures_Immediate = function() return Count("castbarTextures") end
_G.MSUF_UpdateAbsorbBarTextures = function() return Count("absorbTextures") end
_G.MSUF_RefreshPredictionBars = function() return Count("prediction") end
_G.MSUF_InvalidateAbsorbCache = function() return Count("absorbInvalidate") end
_G.MSUF_UpdateAllBarGradients = function(_, skipUnitFrames)
    if skipUnitFrames then Count("gradientSkipUF") end
    return Count("gradients")
end
_G.MSUF_RefreshAllFrameColors = function() return Count("frameColors") end
_G.MSUF_RefreshAllFrames = function() return Count("refreshFrames") end
_G.MSUF_RefreshAllIdentityColors = function() return Count("identityColors") end
_G.MSUF_RefreshAllPowerTextColors = function() return Count("powerTextColors") end
_G.MSUF_RefreshAllUnitAlphas = function() return Count("alpha") end
_G.MSUF_ForceTextLayoutForUnitKey = function() return Count("text") end
_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() return Count("power") end
_G.MSUF_ApplyPowerBarEmbedLayout_All = function() return Count("powerAll") end
_G.MSUF_ApplyCastbarUnitAndSync = function() return Count("castbarUnit") end
_G.MSUF_ApplyAllCastbarsAndSync = function() return Count("castbarBulk") end
_G.MSUF_ApplyBarOutlineThickness_All = function() return Count("outline") end
_G.MSUF_ApplyRoundedUnitframes = function() return Count("rounded") end
_G.MSUF_ClassPower_Apply = function() return Count("classpower") end
_G.MSUF_PrioRows_Reinit = function() return Count("priorityRows") end
_G.MSUF_UFPreview_RequestRefresh = function() return Count("preview") end

local MSUF = {
    MSUF2 = {},
    UF = {
        Metadata = {
            coordinatedApplyMask = {
                Health = true,
                Power = true,
                Alpha = true,
                Auras = false,
                Castbars = false,
                ClassPower = false,
            },
        },
        Apply = function(_, mask)
            lastApplyMask = mask
            return Count("ufApply")
        end,
        RefreshElements = function(_, names)
            assert(type(names) == "table" and names[1] == "Auras", "targeted aura refresh must use the stable Auras element list")
            return Count("auraElements")
        end,
        RefreshBorders = function() return Count("ufBorders") end,
    },
    MSUF_Auras3 = {
        RequestScope = function() return Count("auras") end,
    },
    _colorsAPI = { PushVisualUpdates = function() return Count("colorPipeline") end },
    GF = {
        DIRTY_COLOR = 8,
        DIRTY_BORDER = 16,
        RefreshColors = function() return Count("groupColors") end,
        RefreshVisuals = function(kind, mask)
            lastGroupKind = kind
            lastGroupMask = mask
            return Count("groupBorders")
        end,
        RefreshPreviewLayout = function(kind, opts)
            lastGroupPreviewKind = kind
            lastGroupPreviewOpts = opts
            return Count("groupPreview")
        end,
        RequestPriorityApply = function(self, reason)
            assert(self and self.DIRTY_COLOR == 8, "priority apply lost its method owner")
            lastPriorityReason = reason
            return Count("priorityApply")
        end,
    },
}

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local Apply = assert(MSUF.MSUF2.ApplyService, "ApplyService missing")

assert(Apply.RequestBars("TEST_BARS", "target") == true)
FlushOne()
assert(calls.settings == nil, "bar apply must not build a settings cache before Config.RefreshUnit")
assert(calls.absorbInvalidate == 1, "bar apply must invalidate absorb data once")
assert(calls.barsImmediate == 1, "bar apply must execute one immediate texture pipeline")
assert(calls.barsDeferred == nil, "bar apply must not schedule the legacy texture pipeline too")
assert(calls.absorbTextures == nil and calls.prediction == nil, "bar pipeline already owns prediction textures")

ResetCalls()
assert(Apply.RequestBarGradients("TEST_GRADIENT", "target") == true)
FlushOne()
assert(calls.gradients == 1, "gradient change must execute the gradient pipeline once")
assert(calls.barsImmediate == nil, "gradient-only change must not repaint textures")

ResetCalls()
assert(Apply.RequestColors("TEST_GLOBAL_COLORS") == true)
assert(#scheduled == 0, "global colors already have one dedicated coalesced pipeline")
assert(calls.colorPipeline == 1, "global colors must use the color pipeline once")
assert(calls.notify == nil and calls.frameColors == nil, "global colors must not queue a second UF refresh")

ResetCalls()
assert(Apply.RequestColors("TEST_TARGET_COLORS", "target") == true)
FlushOne()
assert(calls.settings == nil, "scoped colors must let Config.RefreshUnit own cache invalidation")
assert(calls.frameColors == 1, "scoped colors must refresh the scoped color elements once")
assert(calls.notify == nil and calls.barsImmediate == nil, "scoped colors must stay targeted")

ResetCalls()
assert(Apply.RequestGeneral("TEST_FULL_COLOR", { applyAll = true, colors = true }) == true)
FlushOne()
assert(calls.notify == 1, "full transaction must apply unit frames once")
assert(calls.frameColors == nil, "full transaction must not repeat its UF color pass")

ResetCalls()
assert(Apply.RequestGeneral("TEST_TARGET_NO_NOTIFY", { applyAll = false, notify = false, text = true }) == true)
assert(Apply.RequestGeneral("TEST_FULL_NOTIFY", { applyAll = true, frames = true }) == true)
FlushOne()
assert(calls.notify == 1, "targeted notify=false must not poison a later full notifying request")

ResetCalls()
assert(Apply.RequestGeneral("TEST_FULL_NO_NOTIFY", { applyAll = true, notify = false, frames = true }) == true)
FlushOne()
assert(calls.notify == nil and calls.ufApply == 1, "explicit full notify=false must use one direct UF apply")
assert(lastApplyMask == MSUF.UF.Metadata.coordinatedApplyMask, "direct full apply must use the coordinated bridge-free mask")

ResetCalls()
assert(Apply.RequestClassPower("TEST_DETACHED_WIDTH_MODE",
    { anchor = true, cdm = true, syncNow = false },
    { preview = true, power = true, applyAll = false, classpowerApplied = true }) == true)
FlushOne()
assert(calls.powerAll == 1 and calls.power == nil,
    "global detached width mode must refresh Player, Target, and Focus instead of Player only")
assert(calls.classpower == 1, "global detached width mode lost its Class Resource companion apply")

ResetCalls()
assert(Apply.RequestUnit("target", "TEST_UNIT", { text = true, power = true, fonts = true, alpha = true, auras = true, castbar = true }) == true)
FlushOne()
assert(calls.notify == 1, "unit request must notify once")
assert(lastNotifyMask == MSUF.UF.Metadata.coordinatedApplyMask, "unit notify must use the coordinated bridge-free mask")
assert(lastNotifyMask.Alpha == true, "unit notify must own Alpha before clearing its targeted alpha follower")
assert(calls.text == nil and calls.power == nil and calls.alpha == nil, "successful unit notify owns UF-local followers")
assert(calls.fontsImmediate == 1 and lastFontArgs[1] == "target" and lastFontArgs[2] == true and lastFontArgs[3] == true, "unit font requests must retain external followers without repainting UF text or castbars")
assert(calls.auras == 1 and calls.auraElements == nil and calls.castbarUnit == 1,
    "external aura/castbar followers must remain without a second UF aura apply")

ResetCalls()
assert(Apply.RequestUnit("target", "TEST_TARGET_AURAS", { auras = true, notify = false, preview = true }) == true)
FlushOne()
assert(calls.notify == nil and calls.ufApply == nil, "notify=false aura apply must stay element-targeted")
assert(calls.auraElements == 1 and calls.auras == nil, "targeted aura apply must refresh config and Auras exactly once")

ResetCalls()
assert(Apply.RequestHighlightPriority("TEST_PRIORITY", "shared") == true)
FlushOne()
assert(calls.ufBorders == 1 and calls.groupBorders == 1, "shared priority apply must refresh each border owner once")
assert(lastGroupMask == 16, "shared priority refresh must use DIRTY_BORDER")
assert(calls.outline == nil and calls.rounded == nil and calls.settings == nil, "priority apply must not start unrelated border pipelines")
assert(calls.preview == 1, "priority apply must refresh the menu preview once")

ResetCalls()
assert(Apply.RequestHighlightPriority("TEST_GROUP_PRIORITY", "gf_party") == true)
FlushOne()
assert(calls.ufBorders == nil and calls.outline == nil, "group-only priority apply must not touch main unit frames")
assert(calls.groupBorders == 1 and lastGroupKind == "party", "group-only priority apply must refresh only its group scope")
assert(lastGroupMask == 16, "group-only priority refresh must use DIRTY_BORDER")

ResetCalls()
assert(Apply.RequestGroup("party", "border", "TEST_GROUP_PREVIEW_BORDER") == true)
FlushOne()
assert(calls.groupPreview == 1 and lastGroupPreviewKind == "party", "group preview must refresh exactly once for its scope")
assert(type(lastGroupPreviewOpts) == "table" and lastGroupPreviewOpts.dirtyMask == 16,
    "group preview must retain the precise dirty mask")

ResetCalls()
assert(Apply.RequestGroup("gf_priority", "geometry", "TEST_PRIORITY_GEOMETRY") == true)
FlushOne()
assert(calls.priorityApply == 1 and lastPriorityReason == "TEST_PRIORITY_GEOMETRY",
    "gf_priority must use the dedicated priority apply contract exactly once")
assert(calls.groupPreview == nil and calls.groupBorders == nil and lastGroupKind == nil,
    "gf_priority must never alias into Party preview or generic group visuals")

ResetCalls()
assert(Apply.RequestGeneral("TEST_FULL_VISUAL", {
    applyAll = true,
    fonts = true,
    bars = true,
    colors = true,
    castbar = true,
    castbarTextures = true,
}) == true)
FlushOne()
assert(calls.notify == 1 and calls.ufApply == nil, "full visual transaction must use one UF owner")
assert(calls.fontsImmediate == 1 and lastFontArgs[2] == true and lastFontArgs[3] == true, "font runtime must run non-castbar followers only before the bulk castbar apply")
assert(calls.barsImmediate == 1 and lastBarArgs[2] == true and lastBarArgs[3] == true, "bar runtime must skip UF and castbars owned by the bulk castbar pass")
assert(calls.frameColors == nil, "full visual transaction must not repeat UF colors")
assert(calls.castbarTextures == nil and calls.castbarBulk == 1, "bulk castbar apply must be the single castbar owner")

ResetCalls()
assert(Apply.RequestClassPower("TEST_CP_FONT", { fonts = true, playerHP = true }, {
    unit = "player",
    applyAll = false,
    fonts = true,
    preview = false,
}) == true)
FlushOne()
assert(calls.classpower == 1, "pending classpower must remain the single classpower owner")
assert(calls.fontsImmediate == 1 and lastFontArgs[4] == true, "font followers must not pre-apply classpower when a classpower transaction is pending")

ResetCalls()
assert(Apply.RequestClassPower("TEST_CP_COLOR", { colors = true, playerHP = true }, {
    applyAll = false,
    colors = true,
    colorScope = "player",
}) == true)
FlushOne()
assert(calls.frameColors == 1 and calls.classpower == 1, "color and classpower followers must each run once")
assert(IndexOf("frameColors") < IndexOf("classpower"), "classpower must run after UF config/color refresh")
assert(calls.power == nil and calls.powerAll == nil, "explicit classpower/color flags must not trigger POWER reason heuristics")

ResetCalls()
assert(Apply.RequestGeneral("MSUF2_BARS_REALTIME_POWER", { applyAll = false, preview = false }) == true)
FlushOne()
assert(calls.powerAll == 1, "flagless legacy power reasons must retain their targeted fallback")

ResetCalls()
assert(Apply.RequestGeneral("TEST_ALPHA", { applyAll = false, alpha = true, preview = false }) == true)
FlushOne()
assert(calls.alpha == 1, "targeted alpha must have one deferred owner")

ResetCalls()
assert(Apply.RequestGeneral("TEST_VISUAL_ALPHA", { applyAll = false, alpha = true, frames = true, preview = false }) == true)
FlushOne()
assert(calls.refreshFrames == 1 and calls.alpha == nil, "targeted visual refresh must cover alpha without a second pass")

ResetCalls()
assert(Apply.RequestVisuals("TEST_FONT_COLOR_VISUALS") == true)
FlushOne()
assert(calls.fontsImmediate == 1, "RequestVisuals font-color callers must use one font pipeline")
assert(calls.text == nil and calls.colorPipeline == nil and calls.frameColors == nil and calls.barsImmediate == nil, "RequestVisuals must not start overlapping text/color/bar pipelines")

io.write("apply_service_dedup_smoke: ok\n")

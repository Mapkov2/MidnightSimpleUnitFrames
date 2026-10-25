-- GlobalBars: Shapes responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GlobalBarsParts
local ApplyRoundedRuntime = Parts.ApplyRoundedRuntime
local AttachBarsColorShortcut = Parts.AttachBarsColorShortcut
local BarScopeGet = Parts.BarScopeGet
local BarScopeGetBars = Parts.BarScopeGetBars
local BarScopeSetBars = Parts.BarScopeSetBars
local Bars = Parts.Bars
local C_Timer = Parts.C_Timer
local CaptureBarsScopeFields = Parts.CaptureBarsScopeFields
local CreateRoundedTexturePreview = Parts.CreateRoundedTexturePreview
local CurrentBarsScope = Parts.CurrentBarsScope
local DB = Parts.DB
local FILE = Parts.FILE
local Meta = Parts.Meta
local OUTLINE_COLOR_STATE_FIELDS = Parts.OUTLINE_COLOR_STATE_FIELDS
local ROUNDED_SECTION_HEIGHT = Parts.ROUNDED_SECTION_HEIGHT
local ROUNDED_STRENGTH_APPLY_DELAY = Parts.ROUNDED_STRENGTH_APPLY_DELAY
local ReadB = Parts.ReadB
local ReadG = Parts.ReadG
local RegisterControl = Parts.RegisterControl
local RegisterRoundedSearch = Parts.RegisterRoundedSearch
local RequestOutlineRuntime = Parts.RequestOutlineRuntime
local RestoreBarsScopeFields = Parts.RestoreBarsScopeFields
local Rows = Parts.Rows
local SLANTED_DIRECTION_VALUES = Parts.SLANTED_DIRECTION_VALUES
local SLANTED_PRESET_GROUPS = Parts.SLANTED_PRESET_GROUPS
local SLANTED_PRESET_UNITS = Parts.SLANTED_PRESET_UNITS
local SLANTED_SCOPED_DIRECTION_VALUES = Parts.SLANTED_SCOPED_DIRECTION_VALUES
local ScopeDBKeys = Parts.ScopeDBKeys
local ScopedControls = Parts.ScopedControls
local SetOutlineColorForScope = Parts.SetOutlineColorForScope
local SetRoundedBool = Parts.SetRoundedBool
local ShapePreviewSurface = Parts.ShapePreviewSurface
local T = Parts.T
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

local function BuildOutlineSection(ctx, b)
    local outline = Rows.Schema.Section(b:CollapsibleSection("bars_outline", "Frame Outline", 226, false), "bars")
    local options = Rows.Options(BarScopeGetBars, BarScopeSetBars, RequestOutlineRuntime, nil, true)
    local BorderStyles = MSUF.BorderStyles or MSUF.Require("MSUF_BorderStyles", FILE)
    local function OutlineTextureValues()
        return BorderStyles.FrameList("None (solid color)")
    end
    local controls = Rows.Build(ctx, outline, {
        { "slider", "barOutlineThickness", 1, { "Bar outline thickness", 0, 8, 1, 300 },
            path = "outline.thickness", reason = "MSUF2_BAR_OUTLINE", exact = { step = 1, roundStep = true },
            tip = "Width in pixels of the normal frame outline; 0 hides it. Aggro, dispel and other highlight borders use their own thickness.",
            tipOpts = "plain" },
        { "slider", "barOutlineLayer", 0, { "Frame outline layer (0-30)", 0, 30, 1, 300 },
            path = "outline.layer", reason = "MSUF2_BAR_OUTLINE_LAYER", exact = { step = 1, roundStep = true },
            tip = "Draw order on the shared 0-30 layer scale. Raise it to draw the outline above text, icons or auras on a lower layer.", tipOpts = "plain" },
        { "dropdown", "texture", "", { "Outline style", OutlineTextureValues, 300 }, path = "outline.texture",
            get = function() return BorderStyles.NormalizeFrame(BarScopeGetBars("barOutlineTexture", "")) end,
        write = { call = BarScopeSetBars, keyOnly = true, fallback = "",
            resolve = function()
                local scope = CurrentBarsScope()
                return (scope == "shared" and "bars" or scope) .. ".barOutlineTexture"
            end,
            args = { "MSUF2_BAR_OUTLINE_TEXTURE", true }, after = RequestOutlineRuntime
        } --[[schema setter: J5.GlobalBars.OutlineTexture]] },
    }, options)
    local outlineSlider, outlineLayer, outlineTexture = controls.barOutlineThickness, controls.barOutlineLayer, controls.texture
    AttachBarsColorShortcut(outline,
        "Frame Outline Color",
        "Outline color for the selected Bars scope.",
        "Outline color",
        function()
            return tonumber(BarScopeGet("barOutlineColorR", ReadG("barOutlineColorR", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorG", ReadG("barOutlineColorG", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorB", ReadG("barOutlineColorB", 0))) or 0
        end,
        function(r, g, b)
            if SetOutlineColorForScope(r, g, b) then
                RequestOutlineRuntime()
            end
        end,
        "menu:bars-outline-color",
        function() return CaptureBarsScopeFields(OUTLINE_COLOR_STATE_FIELDS) end,
        function(state)
            RestoreBarsScopeFields(state)
            RequestOutlineRuntime()
        end,
        Meta("outline.color"))
    local turnOn = W.TurnOnReason
    local scopeReason = turnOn and turnOn("Use custom settings for this scope", ScopedControls)
    -- Rounded and slanted frames draw the selected style along their shape.
    M.BindGateGroup(ctx, nil, {
        { controls = { outlineSlider, outlineLayer, outlineTexture }, on = ScopedControls, reason = scopeReason },
    })
end

local function BuildRoundedSection(ctx, b)
    local rounded = Rows.Schema.Section(b:CollapsibleSection("bars_rounded", "Rounded Texture", ROUNDED_SECTION_HEIGHT, true), "bars")
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture",
        "rounded section|rounded menu|rounded options|where rounded frames|wo rounded frames",
        "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local SyncRoundedControls = M.RefreshProxy()
    local options = Rows.Options(ReadB,
        function(key, value, row) SetRoundedBool(key, value, row.reload) end, SyncRoundedControls)
    options.register = function(_, control, row)
        RegisterRoundedSearch(control, row[4][1], row.search[1], row.search[2], nil, Meta(row.path))
    end
    local roundedControls = Rows.Schema.Build(ctx, rounded, {
        { "switch", "roundedFramesEnabled", false, { "Rounded frame texture", roundLeftX, -52, roundW },
            path = "rounded.roundedFramesEnabled", defaultOn = true, reload = true, register = true,
            companionWrites = { "bars.slantedBarsEnabled" },
            search = { "master toggle|all rounded frames|rounded frames master|rounded frames on|rounded frames off|rounded frames einschalten|rounded " ..
                "frames ausschalten|alle abgerundeten frames",
                "Master switch for the rounded frame texture style." } },
        { "toggle", "roundedUnitFrames", true, { "Unit frames", roundLeftX, -90, roundW },
            path = "rounded.roundedUnitFrames", defaultOn = true, register = true,
            search = { "rounded unit frames|rounded unitframes|unit frame corners|unitframe corners|abgerundete unitframes|unitframes " ..
                "abgerundet|player target focus boss rounded",
                "Enable or disable rounded textures on unit frames." } },
        { "toggle", "roundedGroupFrames", true, { "Group frames", roundLeftX, -128, roundW },
            path = "rounded.roundedGroupFrames", defaultOn = true, register = true,
            search = { "rounded group frames|rounded party frames|rounded raid frames|group frame corners|abgerundete gruppenframes|party raid abgerundet",
                "Enable or disable rounded textures on group frames." } },
        { "toggle", "roundedClassResources", false, { "Class resources", roundLeftX, -166, roundW },
            path = "rounded.roundedClassResources", defaultOn = true, register = true,
            search = { "rounded class resources|rounded combo points|rounded soul shards|class resource bar corners|klassenressourcen abgerundet|combo " ..
                "punkte abrunden|seelensplitter abrunden",
                "Round rectangular class resource bars. Circle, Diamond, and Hex shapes are unchanged." } },
        { "toggle", "roundedPowerBars", true, { "Power bars", roundRightX, -52, roundW },
            path = "rounded.roundedPowerBars", defaultOn = true, register = true,
            search = { "rounded power bars|rounded powerbar|power bar corners|powerbar corners|powerbars abgerundet|powerbar abrunden",
                "Enable or disable rounded textures on power bars." } },
        { "toggle", "roundedMouseover", true, { "Mouseover highlights", roundRightX, -90, roundW },
            path = "rounded.roundedMouseover", defaultOn = true, register = true,
            search = { "rounded mouseover|rounded hover|rounded hover border|mouseover " ..
                "rounded|mouseover highlight rounded|mouseover abgerundet|hover abgerundet",
                "Enable or disable rounded mouseover highlight edges." } },
        { "toggle", "roundedCastbars", false, { "Castbars", roundRightX, -128, roundW },
            path = "rounded.roundedCastbars", defaultOn = true, register = true,
            search = { "rounded castbars|castbar corners|cast bars rounded|castbars abgerundet|zauberbalken abgerundet",
                "Round MSUF castbar surfaces and outlines. Blizzard castbars, spell icons, and the GCD bar are not changed." } },
    }, options)
    local roundedPreview
    local roundingSlider
    local roundingApplyPending, roundingApplyTimer, roundingReleaseScheduled
    local function CancelRoundingApplyTimer()
        if roundingApplyTimer and type(roundingApplyTimer.Cancel) == "function" then roundingApplyTimer:Cancel() end
        roundingApplyTimer = nil
    end
    local function FlushRoundingRuntime()
        if not roundingApplyPending then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return
        end
        if M.IsConfigCombatLocked and M.IsConfigCombatLocked(true) then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return false
        end
        roundingApplyPending = nil
        roundingReleaseScheduled = nil
        CancelRoundingApplyTimer()
        ApplyRoundedRuntime()
        return true
    end
    local function ScheduleRoundingRelease()
        if not roundingApplyPending or roundingReleaseScheduled then return end
        roundingReleaseScheduled = true
        CancelRoundingApplyTimer()
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, FlushRoundingRuntime)
        else FlushRoundingRuntime() end
    end
    local function QueueRoundingRuntime()
        roundingApplyPending = true
        if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end
        if roundingSlider._msuf2SliderActive == true then
            roundingReleaseScheduled = nil
            CancelRoundingApplyTimer()
            return
        end
        if roundingReleaseScheduled then return end
        CancelRoundingApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            roundingApplyTimer = C_Timer.NewTimer(ROUNDED_STRENGTH_APPLY_DELAY, FlushRoundingRuntime)
        else
            FlushRoundingRuntime()
        end
    end
    roundingSlider = Rows.Schema.Build(ctx, rounded, {
        { "slider", "rounding", 3, { "Corner rounding", 1, 5, 1, 300 },
            { roundRightX, -166, 300, "LEFT" }, path = "rounded.roundedCornerStrength", exact = { step = 1, roundStep = true },
            get = function() return tonumber(Bars().roundedCornerStrength) or 3 end,
        write = { source = Bars, numberDefault = 3, round = true, clamp = true, skipEqual = true,
            after = QueueRoundingRuntime } --[[schema setter: GlobalBars.11]] },
    }, Rows.Commands).rounding
    roundingSlider:HookScript("OnMouseUp", ScheduleRoundingRelease)
    roundingSlider:HookScript("OnHide", FlushRoundingRuntime)
    roundingSlider:HookScript("OnShow", FlushRoundingRuntime)
    RegisterRoundedSearch(roundingSlider, "Corner rounding",
        "corner rounding|rounding strength|rounded strength|corner radius|rounding radius|abrundungsstaerke|eckenradius|staerke der abrundung",
        "Controls how subtle or strong the rounded corners appear. Masks, outlines, highlights, mouseover edges, power bars, enabled class resources, " ..
            "and enabled castbars use the same value.",
        "slider", Meta("rounded.roundedCornerStrength", "setting", { step = 1, min = 1, max = 5 }))
    roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -214, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview",
        "rounded preview|rounded example|rounded image|rounded frame preview|preview rounded frames|rounded frames aussehen|vorschau abgerundete frames",
        "Shows a small preview of the rounded frame texture style.", "preview")
    Rows.Schema.Custom(roundedPreview, { id = Meta("rounded.preview", "ephemeral").controlId, kind = "preview",
        labelKey = "Rounded Texture Preview", meta = roundedPreview._msuf2SearchMeta,
        scope = "bars", applyDomain = "preview", owner = roundedPreview, refresh = roundedPreview.RefreshRoundedPreview })
    local roundedDependentControls = { roundedControls.roundedUnitFrames, roundedControls.roundedGroupFrames, roundedControls.roundedClassResources,
        roundedControls.roundedPowerBars,
        roundedControls.roundedMouseover, roundedControls.roundedCastbars, roundingSlider }
    SyncRoundedControls(M.BindGateGroup(ctx, nil, {
        { controls = roundedDependentControls, on = function() return ReadB("roundedFramesEnabled", false) == true end,
            reason = W.TurnOnReason and W.TurnOnReason("Rounded frame texture") },
    }, {
        also = function() if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end end,
    }))
end

local function SlantedStylesSelected(keys)
    local db = DB()
    local function InScope(scope)
        for _, key in ipairs(scope) do
            if db[key] and db[key].frameBarShape == "SLANTED" then return true end
        end
        return false
    end
    if keys then return InScope(keys) end
    return InScope(SLANTED_PRESET_UNITS) or InScope(SLANTED_PRESET_GROUPS)
end

local function SlantedSwitchOn()
    local saved = Bars().slantedBarsEnabled
    if saved ~= nil then return saved == true end
    return SlantedStylesSelected()
end

local function CreateSlantedBarPreview(section, width)
    local card = W.ControlCard(section, "Slanted bar preview", nil, 30, -300, width - 60, 92)
    if not card then return end
    local surface = ShapePreviewSurface(card, min(440, max(240, width - 110)), 43)
    function card:RefreshSlantedPreview() surface:Refresh() end
    card:RefreshSlantedPreview()
    return card
end

local function SlantedDirectionForScope()
    local keys = ScopeDBKeys(CurrentBarsScope())
    local value = keys and DB()[keys[1]] and DB()[keys[1]].slantedBarDirection
        or (not keys and Bars().slantedBarDirection)
    for i = 1, #SLANTED_DIRECTION_VALUES do
        if SLANTED_DIRECTION_VALUES[i].value == value then return value end
    end
    return keys and "DEFAULT" or "RIGHT_DOWN"
end
local function SetSlantedDirectionForScope(value)
    local keys = ScopeDBKeys(CurrentBarsScope())
    local allowed = keys and value == "DEFAULT"
    for i = 1, #SLANTED_DIRECTION_VALUES do
        if SLANTED_DIRECTION_VALUES[i].value == value then
            allowed = true
            break
        end
    end
    if not allowed then return false end
    if value == "DEFAULT" then value = nil end
    if not keys then
        if Bars().slantedBarDirection == value then return false end
        Bars().slantedBarDirection = value
        return true
    end
    local db, changed = DB(), false
    for i = 1, #keys do
        local entry = db[keys[i]]
        if not entry and value ~= nil then
            entry = {}
            db[keys[i]] = entry
        end
        if entry and entry.slantedBarDirection ~= value then
            entry.slantedBarDirection, changed = value, true
        end
    end
    return changed
end
local function BuildSlantedSection(ctx, b)
    local section = Rows.Schema.Section(b:CollapsibleSection("bars_slanted", "Slanted Bars", 480, true), "bars")
    local width = (section and section._msuf2Width) or b.width or 720
    local SyncSlantedControls = M.RefreshProxy()
    local function Search(control, label, kind, keywords, help)
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(control, { label = label, kind = kind, keywords = keywords, help = help })
        end
    end
    local function ApplySlantedToScope(keys)
        local db, changed = DB(), false
        for _, key in ipairs(keys) do
            db[key] = db[key] or {}
            if db[key].frameBarShape ~= "SLANTED" then db[key].frameBarShape, changed = "SLANTED", true end
        end
        return changed
    end
    local function ApplySlantedToAll()
        local units = ApplySlantedToScope(SLANTED_PRESET_UNITS)
        return ApplySlantedToScope(SLANTED_PRESET_GROUPS) or units
    end
    local ApplyRoundedUnitframes = MSUF.Require("MSUF_ApplyRoundedUnitframes", FILE)
    local function RefreshSlanted(reason)
        ApplyRoundedUnitframes()
        SyncSlantedControls()
        if M.RequestRefresh then M.RequestRefresh(ctx, reason) end
    end
    Rows.Schema.Build(ctx, section, {
        { "text", "slantedHint", nil, { "Choose where slanted edges appear. Turning this off keeps your frame choices.",
            30, -40, width - 60, T.colors.muted }, scope = "bars" },
    })
    local preview = CreateSlantedBarPreview(section, width)
    if preview and type(M.RegisterSearchWidget) == "function" then
        M.RegisterSearchWidget(preview, {
            label = "Slanted bar preview", kind = "preview",
            keywords = { "slanted", "angled", "preview", "vorschau", "schraege" },
            help = "Shows the selected cut on a Health and Power bar sample.",
        })
        Rows.Schema.Custom(preview, { id = Meta("slanted.preview", "ephemeral").controlId, kind = "preview",
            labelKey = "Slanted bar preview", meta = preview._msuf2SearchMeta,
            scope = "bars", applyDomain = "preview", owner = preview, refresh = preview.RefreshSlantedPreview })
    end
    local presetWrites = Rows.Schema.ScopedFields({ "frameBarShape" }, nil).keys
    presetWrites[#presetWrites + 1] = "bars.roundedFramesEnabled"
    local enabled = Rows.Schema.Build(ctx, section, {
        -- Turning it on restyles every unit and group frame: whole-profile undo.
        { "switch", "enabled", false, { "Enable slanted bars", 30, -78, min(340, width - 60) },
            path = "slanted.enabled", exact = { historyScope = false }, get = SlantedSwitchOn,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = presetWrites,
            set = function(value)
            value = value == true
            local bars = Bars()
            local switchStyle = value and bars.roundedFramesEnabled == true
            if bars.slantedBarsEnabled == value and not switchStyle then return end
            bars.slantedBarsEnabled = value
            if switchStyle then bars.roundedFramesEnabled = false end
            if value and not SlantedStylesSelected() then ApplySlantedToAll() end
            RefreshSlanted("slanted-bar-enabled")
        end },
    }, Rows.Commands).enabled
    Search(enabled, "Enable slanted bars", "toggle",
        { "slanted", "enable", "disable", "on", "off", "schraege", "einschalten", "ausschalten" },
        "Choose where slanted edges appear. Turning this off keeps your frame choices.")
    local options = Rows.Options(ReadB, function(key, value) Bars()[key] = value end,
        function(row, value)
            if value and row.presetKeys and not SlantedStylesSelected(row.presetKeys) then ApplySlantedToScope(row.presetKeys) end
            RefreshSlanted("slanted-" .. row.id)
        end, function(key) return Bars()[key] end)
    options.register = function(_, control, row)
        Search(control, row[4][1], "toggle", { "slanted", "angled", row.id, "schraege", "ein", "aus" })
    end
    local controls = Rows.Schema.Build(ctx, section, {
        { "toggle", "slantedUnitFrames", true, { "Unit frames", 30, -116, 250 },
            path = "slanted.units", id = "units", defaultOn = true, skipEqual = true, register = true, presetKeys = SLANTED_PRESET_UNITS,
            companionWrites = Rows.Schema.Fields(SLANTED_PRESET_UNITS, { "frameBarShape" }).recordPaths },
        { "toggle", "slantedGroupFrames", true, { "Group frames", 30, -154, 250 },
            path = "slanted.groups", id = "groups", defaultOn = true, skipEqual = true, register = true, presetKeys = SLANTED_PRESET_GROUPS,
            companionWrites = Rows.Schema.Fields(SLANTED_PRESET_GROUPS, { "frameBarShape" }).recordPaths },
        { "toggle", "slantedClassResources", false, { "Class resources", 30, -192, 250 },
            path = "slanted.class_resources", id = "class_resources", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedPowerBars", true, { "Power bars", 330, -78, 250 },
            path = "slanted.power", id = "power", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedMouseover", true, { "Mouseover highlights", 330, -116, 250 },
            path = "slanted.mouseover", id = "mouseover", defaultOn = true, skipEqual = true, register = true },
        { "toggle", "slantedCastbars", false, { "Castbars", 330, -154, 250 },
            path = "slanted.castbars", id = "castbars", defaultOn = true, skipEqual = true, register = true },
        { "dropdown", "direction", nil, { "Cut direction", function()
            return CurrentBarsScope() == "shared" and SLANTED_DIRECTION_VALUES or SLANTED_SCOPED_DIRECTION_VALUES
        end, min(340, width - 60) }, { 30, -248, min(340, width - 60), "LEFT" },
            path = "slanted.direction", get = SlantedDirectionForScope,
            writeTargets = Rows.Schema.Family(Rows.keys["slanted.direction"]),
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
            if not SetSlantedDirectionForScope(value) then return end
            if preview and preview.RefreshSlantedPreview then preview:RefreshSlantedPreview() end
            ApplyRoundedRuntime()
            if M.RequestRefresh then M.RequestRefresh(ctx, "slanted-bar-direction") end
        end },
    }, options)
    local dependent = { controls.slantedUnitFrames, controls.slantedGroupFrames, controls.slantedClassResources,
        controls.slantedPowerBars, controls.slantedMouseover, controls.slantedCastbars }
    local direction = controls.direction
    Search(direction, "Cut direction", "dropdown", { "slanted", "diagonal", "left", "right", "both", "schraege", "richtung" },
        "Choose the cut direction for the selected scope. Use shared style follows the shared direction.")
    local preset = W.Button(section, "Apply slanted bars to all frames", 280)
    W.MoveWidget(preset, section, 30, -420)
    preset:SetScript("OnClick", function()
        local function Write()
            local bars = Bars()
            local changed = ApplySlantedToAll()
            if bars.slantedBarsEnabled ~= true then bars.slantedBarsEnabled, changed = true, true end
            if bars.slantedUnitFrames ~= true then bars.slantedUnitFrames, changed = true, true end
            if bars.slantedGroupFrames ~= true then bars.slantedGroupFrames, changed = true, true end
            if not changed then return false end
            RefreshSlanted("slanted-bar-preset")
            return true
        end
        if type(M.RunWithHistory) == "function" then
            M.RunWithHistory("Apply slanted bars to all frames", "bars:slanted-preset", Write)
        else
            Write()
        end
    end)
    RegisterControl(preset, Meta("slanted.apply_preset", "action"), "Apply slanted bars to all frames", "button")
    Rows.Schema.Owned(preset, "bars", "bars")
    Rows.Schema.SetSetting(preset, Rows.Schema.Record({ "bars.slantedBarsEnabled", "bars.slantedUnitFrames", "bars.slantedGroupFrames",
        "{unit}.frameBarShape", "gf_{scope}.frameBarShape" }))
    Search(preset, "Apply slanted bars to all frames", "button",
        { "slanted bars", "slanted preset", "angled health bar", "schraege leiste", "schraege balken" },
        "Cuts the Health and Power bar edges. Choose frames in Basics or apply this shape everywhere.")
    dependent[#dependent + 1] = direction
    SyncSlantedControls(M.BindGateGroup(ctx, nil, {
        { controls = dependent, on = SlantedSwitchOn, reason = W.TurnOnReason and W.TurnOnReason("Enable slanted bars") },
    }, {
        also = function() if preview and preview.RefreshSlantedPreview then preview:RefreshSlantedPreview() end end,
    }))
end

-- Upgrade-tour playground for the 5.x highlight card. The rounded rework is the
-- one 6.0 change that has to be felt rather than read, so the tour hosts the
-- real controls; reading, writing, applying and the master gate all stay here.
local ROUNDED_TOUR_STRENGTHS = {}
for i = 1, 5 do ROUNDED_TOUR_STRENGTHS[i] = { value = i, text = tostring(i) } end

local function RoundedTourGet(key, defaultOn)
    return function()
        local value = ReadB(key, defaultOn)
        if defaultOn then return value ~= false end
        return value == true
    end
end

local function RoundedTourSet(key, requireReload)
    return function(value) SetRoundedBool(key, value, requireReload) end
end

local function SetRoundedTourStrength(value)
    value = floor((tonumber(value) or 3) + 0.5)
    if value < 1 then value = 1 elseif value > 5 then value = 5 end
    local bars = Bars()
    if bars.roundedCornerStrength == value then return end
    bars.roundedCornerStrength = value
    -- A segment commits once per click, so the page slider's drag debounce
    -- (ROUNDED_STRENGTH_APPLY_DELAY) has nothing to smooth out here.
    ApplyRoundedRuntime()
end

if type(M.RegisterUpgradeTourControls) == "function" then
    M.RegisterUpgradeTourControls("rounded_frames", {
        -- Grid height only; the tour adds its own "try it here" label above.
        -- Two columns: 48 (toggle + segment row) + 36 + 36, each plus the 6px
        -- row gap W.SettingsRows uses.
        columns = 2,
        height = 126,
        rows = function()
            return {
                { id = "master", kind = "toggle", label = "Rounded frame texture",
                    get = RoundedTourGet("roundedFramesEnabled", false),
                    set = RoundedTourSet("roundedFramesEnabled", true) },
                { id = "strength", kind = "segment", label = "Corner rounding",
                    values = ROUNDED_TOUR_STRENGTHS,
                    get = function() return floor(tonumber(Bars().roundedCornerStrength) or 3) end,
                    set = SetRoundedTourStrength },
                { id = "units", kind = "toggle", label = "Unit frames",
                    get = RoundedTourGet("roundedUnitFrames", true), set = RoundedTourSet("roundedUnitFrames") },
                { id = "groups", kind = "toggle", label = "Group frames",
                    get = RoundedTourGet("roundedGroupFrames", true), set = RoundedTourSet("roundedGroupFrames") },
                { id = "power", kind = "toggle", label = "Power bars",
                    get = RoundedTourGet("roundedPowerBars", true), set = RoundedTourSet("roundedPowerBars") },
                { id = "mouseover", kind = "toggle", label = "Mouseover highlights",
                    get = RoundedTourGet("roundedMouseover", true), set = RoundedTourSet("roundedMouseover") },
            }
        end,
        after = function(ctx, result)
            local controls = result and result.controls
            if type(controls) ~= "table" then return end
            local refresh = M.BindGateGroup(ctx, nil, {
                {
                    controls = { controls.strength, controls.units, controls.groups,
                        controls.power, controls.mouseover },
                    on = function() return ReadB("roundedFramesEnabled", false) == true end,
                },
            })
            if type(refresh) == "function" then refresh() end
        end,
    })
end


-- Explicit load-time exports for the following responsibility modules.
Parts.BuildOutlineSection = BuildOutlineSection
Parts.BuildRoundedSection = BuildRoundedSection
Parts.BuildSlantedSection = BuildSlantedSection

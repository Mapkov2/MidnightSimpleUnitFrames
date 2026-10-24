-- menu_colors_page_bugs_smoke.lua <repoRoot> <flavor>
--
-- Colors page and colour-picker shortcuts (MSUF_Menu2_AdvancedColors*.lua,
-- MSUF_Menu2_ColorPainter.lua), on the real core and Options graph:
--   1. Status text colours (Colors > Status Text Colors and the ::: picker of a
--      status text card) ask for a colour repaint of the edited frame. Without
--      colors=true the apply service read "TEXT" out of the reason string, ran a
--      text layout pass and never reached the status indicators, so live frames
--      kept the old colour until the next unrelated repaint.
--   2. A colour pick that carries no opacity (the colour wheel) keeps the stored
--      opacity of the cast border, cast background, power background and bar
--      background tint instead of resetting it to the default; the opacity
--      slider still writes its value.
--   3. Colors > Gradient strength writes the Bars shade-overlay key, so it carries
--      the Bars label and tooltip for that key (the health-gradient colouring has no strength).
--   4. The Colors page unit previews request their apply as (unit, reason, opts).
-- Every section runs on its own; all failures are listed together.
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    clientScriptBindings = true, nativeButtonLifecycle = true,
    beforeOptions = arg[3] and function(world)
        local load = world.LoadFile
        world.LoadFile = function(self, path, addon, namespace)
            local target = arg[4] or "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
            if path:gsub("\\", "/") == root .. "/" .. target then path = arg[3] end
            return load(self, path, addon, namespace)
        end
    end })
local M, env, core = mw.M, mw.env, mw.core
local db = env.MSUF_DB
-- The canonical Colors transaction also repaints unrelated gameplay features;
-- keep those API-heavy consumers out of this contract.
core.MSUF_ApplyGameplayVisuals = function() end

local failures = {}
local function Section(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
local function Check(condition, message)
    if not condition then error(message, 0) end
    return condition
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- Registered controls by control id and by setting key, with the Colors and Bars
-- pages' sections built.
local byId, bySetting, controlWidgets = {}, {}, {}
local Register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.controlId then
        local copy = {}
        for field, value in pairs(payload) do copy[field] = value end
        byId[copy.controlId] = copy
        controlWidgets[copy.controlId] = widget
        if copy.settingKey then
            bySetting[copy.settingKey] = bySetting[copy.settingKey] or {}
            table.insert(bySetting[copy.settingKey], copy)
        end
    end
    return Register(widget, payload, ...)
end
-- The "Health strength" tooltips pages attach, in the order they were built.
local strengthTips = {}
local AddTooltip = M.AddTooltip
M.AddTooltip = function(widget, title, body, ...)
    if title == "Health strength" then strengthTips[#strengthTips + 1] = body end
    return AddTooltip(widget, title, body, ...)
end
local previewPanels = {}
for _, owner in ipairs({ core, env }) do
    local create = owner.MSUF_Menu2_CreateUnitPreviewBox
    if type(create) == "function" then
        owner.MSUF_Menu2_CreateUnitPreviewBox = function(parent, panel, ...)
            previewPanels[#previewPanels + 1] = panel
            return create(parent, panel, ...)
        end
    end
end
-- Build one page and the named sections (all of them when none is named).
local function BuildSections(pageKey, ...)
    mw:Select(pageKey)
    mw:RunTimers()
    local entry = Check(M.cache[pageKey], "the " .. pageKey .. " page did not build")
    local names = { ... }
    if #names == 0 then
        for name in pairs(entry.sections or {}) do names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        M.Widgets.EnsureSectionContent(Check(entry.sections[name], "section " .. name .. " is missing"))
    end
    mw:RunTimers()
end
BuildSections("opt_colors")
local colorsStrengthTip = strengthTips[1]

-- The calls the apply service makes into the unit frame runtime.
local repaints, textPasses = {}, 0
env.MSUF_RefreshAllFrameColors = function(unit) repaints[#repaints + 1] = unit or "*" end
env.MSUF_ForceTextLayoutForUnitKey = function() textPasses = textPasses + 1 end
local function Painted(unit)
    for i = 1, #repaints do
        if repaints[i] == unit or repaints[i] == "*" then return true end
    end
    return false
end

Section("Status text colour repaints the live frame (Colors page)", function()
    -- The frame dropdown keeps its choice on the module, as its setter does.
    M._colorsStatusTextUnit = "target"
    local value = Check(byId["menu2.opt.colors.advanced.status.text.color.value"], "the status text colour control is missing")
    repaints, textPasses = {}, 0
    value.command.set(0.2, 0.3, 0.4)
    mw:RunTimers()
    Check(Near(db.target.levelIndicatorColorR, 0.2), "the colour was not stored on the edited frame")
    Check(Painted("target"), "no colour repaint reached the Target frame after the status text colour changed")
end)

Section("Status text colour repaints the live frame (picker shortcut)", function()
    local targets = M.ResolveContextColorReferences({ "status.text.current" },
        { unit = "focus", colorPrefix = "statusGhostText", colorLabel = "Ghost text" })
    local target = Check(targets and targets[1], "the status text colour target did not resolve")
    repaints, textPasses = {}, 0
    target.setRGB(0.5, 0.6, 0.7)
    mw:RunTimers()
    Check(Near(db.focus.statusGhostTextColorR, 0.5), "the colour was not stored on the edited frame")
    Check(Painted("focus"), "no colour repaint reached the Focus frame after the picker changed the status text colour")
end)

-- Opacity: key prefix by target id, the default the target falls back to.
local ALPHA_TARGETS = {
    { "bar.power_background", "powerBarBgColor", 1 },
    { "bar.background_tint", "classBarBg", 1 },
    { "cast.border", "castbarBorder", 1 },
    { "cast.background", "castbarBg", 0.85 },
}
for _, row in ipairs(ALPHA_TARGETS) do
    Section("Colour edit keeps the stored opacity: " .. row[1], function()
        local targets = M.ResolveContextColorReferences({ row[1] }, {})
        local target = Check(targets and targets[1], "the " .. row[1] .. " colour target did not resolve")
        local key = row[2] .. "A"
        db.general[key] = 0.37
        target.setRGB(0.1, 0.2, 0.3)
        Check(Near(tonumber(db.general[key]), 0.37), "a colour pick reset the stored opacity to "
            .. tostring(db.general[key]))
        Check(target.getOpacity and Near(target.getOpacity(), 0.37), "the picker reads another opacity than the stored one")
        target.setRGB(0.1, 0.2, 0.3, 0.6)
        Check(Near(tonumber(db.general[key]), 0.6), "the opacity slider no longer writes its value")
        db.general[key] = nil
        target.setRGB(0.4, 0.5, 0.6)
        Check(Near(tonumber(db.general[key]), row[3]), "a colour that never had an opacity did not get the default " .. row[3])
    end)
end

Section("Gradient strength carries the Bars label", function()
    BuildSections("opt_bars", "bars_textures")
    local colors = Check(byId["menu2.opt.colors.advanced.appearance.gradient.strength"], "the Colors strength control is missing")
    local bars = Check(byId["menu2.opt.bars.global.gradient.health.strength"], "the Bars health strength control is missing")
    -- The Bars slider scopes general.gradientStrength; the Colors slider writes it directly.
    Check(colors.settingKey == "general.gradientStrength", "the Colors strength slider writes " .. tostring(colors.settingKey))
    Check(colors.label == bars.label, "Colors calls the Bars shade-overlay strength '" .. tostring(colors.label)
        .. "', Bars calls it '" .. tostring(bars.label) .. "'")
    -- It explains the control with the Bars tooltip (an existing, translated text), not with nothing.
    Check(colorsStrengthTip, "the Colors strength slider has no tooltip")
    Check(strengthTips[2], "fixture: the Bars strength slider has no tooltip")
    Check(colorsStrengthTip == strengthTips[2], "the Colors strength tooltip differs from the Bars one: " .. tostring(colorsStrengthTip))
end)

Section("Colors page unit previews request their apply as (unit, reason, opts)", function()
    Check(#previewPanels > 0, "the Colors page built no unit preview")
    local service = Check(M.ApplyService, "ApplyService missing")
    local original, calls = service.RequestUnitDomains, {}
    service.RequestUnitDomains = function(...) calls[#calls + 1] = { ... } end
    for _, panel in ipairs(previewPanels) do panel._msufAPI.ApplySettingsForKey() end
    service.RequestUnitDomains = original
    Check(#calls == #previewPanels, "a preview apply did not reach the apply service")
    for _, call in ipairs(calls) do
        Check(type(call[1]) == "string" and call[2] == "MSUF2_COLOR_PAINTER" and (call[3] == nil or type(call[3]) == "table"),
            "RequestUnit(" .. tostring(call[1]) .. ", " .. tostring(call[2]) .. ", " .. tostring(call[3])
            .. ") does not match (unit, reason, opts)")
    end
end)

-- All ten ordinary Dispel controls use their actual client widget callbacks.
-- The page's other categories and shortcut owners keep their separate contracts.
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Snapshot() return core.ProfileFields.CopySnapshot(env.MSUF_DB) end
local function RefreshDispel() M.Refresh() mw:RunTimers() end
local function DispelInput(widget, kind)
    if kind == "enabled" then widget:Click("LeftButton")
    else
        widget:_msuf2BeginColorInteraction()
        widget._msuf2OnColorChanged(0, 0.37, 0.91)
        widget:_msuf2CommitColorInteraction()
    end
    mw:RunTimers()
end
local function DispelControls(spec)
    local id = "menu2.opt.colors.advanced.auras.dispel." .. spec.path
    return Check(controlWidgets[id .. ".enabled"], "missing switch " .. id),
        Check(controlWidgets[id .. ".color"], "missing color " .. id)
end
local function DispelDisplay(spec)
    local enabled, color = DispelControls(spec)
    return { enabled = enabled:GetChecked(), rgb = { color:GetRGB() } }
end
local function CheckDispelDisplay(spec, enabled, rgb, phase, actual)
    actual = actual or DispelDisplay(spec)
    Check(actual.enabled == enabled, phase .. " paired switch display drift " .. spec.key)
    Check(Near(actual.rgb[1], rgb[1]) and Near(actual.rgb[2], rgb[2]) and Near(actual.rgb[3], rgb[3]),
        phase .. " paired swatch display drift " .. spec.key)
end
local function DispelSetup(spec, state)
    local general = env.MSUF_DB.general
    general.dispelTypeColorOverrides = state == "edge"
        and { [spec.key] = { 0, 0.2, 0.3 }, futureFlag = false } or nil
    RefreshDispel() M.ClearHistory()
end
local function CheckDispel(widget, kind, spec, state, factory)
    local overrides = env.MSUF_DB.general.dispelTypeColorOverrides
    local stored = overrides and overrides[spec.key]
    if kind == "enabled" then
        Check((stored ~= nil) == (state ~= "edge"), "switch input did not toggle " .. spec.key)
        Check(widget:GetChecked() == (stored ~= nil), "switch refresh drift " .. spec.key)
    else
        Check(stored and stored[1] == 0 and Near(stored[2], 0.37) and Near(stored[3], 0.91),
            "color input did not save " .. spec.key)
        local r, g, b = widget:GetRGB()
        Check(r == 0 and Near(g, 0.37) and Near(b, 0.91), "color widget did not refresh " .. spec.key)
    end
    local enabled = DispelControls(spec)
    Check(enabled:GetChecked() == (stored ~= nil), "paired switch refresh drift " .. spec.key)
    if state == "edge" then Check(overrides.futureFlag == false, "input dropped unknown false field") end
    CheckDispelDisplay(spec, kind ~= "enabled" or state ~= "edge",
        kind == "enabled" and factory or { 0, 0.37, 0.91 }, "input")
    if kind == "enabled" and state ~= "edge" then
        Check(stored and Near(stored[1], factory[1]) and Near(stored[2], factory[2]) and Near(stored[3], factory[3]),
            "switch did not store factory RGB " .. spec.key)
    end
end
Section("Malformed Dispel override containers retain factory fallback", function()
    local original = env.MSUF_DB.general.dispelTypeColorOverrides
    for _, invalid in ipairs({ true, false, 0, "invalid" }) do
        env.MSUF_DB.general.dispelTypeColorOverrides = invalid
        for _, spec in ipairs(M.DISPEL_COLOR_SPECS) do
            local r, g, b = M._GetDispelTypeRGB(spec.key, true)
            local dr, dg, dbb = M._GetDispelTypeRGB(spec.key, false)
            Check(Near(r, dr) and Near(g, dg) and Near(b, dbb), "malformed fallback drift " .. spec.key)
            Check(env.MSUF_DB.general.dispelTypeColorOverrides == invalid, "getter repaired profile on read")
        end
    end
    env.MSUF_DB.general.dispelTypeColorOverrides = original
end)
local auraApplies = 0
local auraApply = M.ApplyService.RequestAuraFonts
M.ApplyService.RequestAuraFonts = function(...) auraApplies = auraApplies + 1 return auraApply(...) end
local savedOverrides = env.MSUF_DB.general.dispelTypeColorOverrides
for _, width in ipairs({ 720, 400 }) do
    local builder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...) ctx.width = width return builder(ctx, ...) end
    mw:Select("home") M.InvalidatePage("opt_colors") mw:Select("opt_colors") mw:RunTimers()
    M.ColorsEnsureCategoryBuilt("colors_auras") BuildSections("opt_colors", "colors_auras")
    M.Widgets.PageBuilder = builder
    for _, spec in ipairs(M.DISPEL_COLOR_SPECS) do
        -- Explicit useOverride=false reads the actual factory owner, never the displayed swatch.
        local factory = { M._GetDispelTypeRGB(spec.key, false) }
        local enabled, color = DispelControls(spec)
        for _, row in ipairs({ { "enabled", enabled }, { "color", color } }) do
            local kind, widget = row[1], row[2]
            local id = tostring(widget._msuf2ControlId)
            Section("Dispel declarations " .. width .. " " .. spec.key .. " " .. kind, function()
                local declaration = Check(widget._msuf2ControlSchema, "missing typed Dispel declaration")
                Check(declaration.id == widget._msuf2CommandAction.controlId, "stable control ID changed")
                Check(declaration.scope == "general" and declaration.applyDomain == "auras", "scope/domain missing")
                Check(widget._msuf2CommandAction.settingKey == (kind == "color"
                    and "general.dispelTypeColorOverrides." .. spec.key or nil), "search setting changed")
            end)
            for _, state in ipairs({ "default", "edge" }) do
                Section("Dispel combat " .. width .. " " .. spec.key .. " " .. kind .. " " .. state, function()
                    DispelSetup(spec, state)
                    local initial = state == "edge" and { 0, 0.2, 0.3 } or factory
                    CheckDispelDisplay(spec, state == "edge", initial, "combat setup refresh")
                    local before, calls = Snapshot(), auraApplies
                    core.Util.InCombat("PLAYER_REGEN_DISABLED")
                    env.InCombatLockdown = function() return false end
                    DispelInput(widget, kind)
                    local early = Same(before, Snapshot()) and calls == auraApplies
                    env.InCombatLockdown = function() return true end
                    DispelInput(widget, kind)
                    local locked = Same(before, Snapshot()) and calls == auraApplies
                    core.Util.InCombat("PLAYER_REGEN_ENABLED")
                    env.InCombatLockdown = function() return false end
                    mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                    Check(early and locked, "combat input wrote/applied " .. spec.key .. " " .. kind)
                    Check(not M.Undo(), "combat refusal created undo entry")
                    CheckDispelDisplay(spec, state == "edge", initial, "combat release")
                end)
                Section("Dispel history/input " .. width .. " " .. spec.key .. " " .. kind .. " " .. state, function()
                    DispelSetup(spec, state)
                    local initial = state == "edge" and { 0, 0.2, 0.3 } or factory
                    CheckDispelDisplay(spec, state == "edge", initial, "setup refresh")
                    local before, applies = Snapshot(), auraApplies
                    DispelInput(widget, kind) CheckDispel(widget, kind, spec, state, factory)
                    Check(auraApplies > applies, "input did not request aura apply")
                    local after = Snapshot()
                    RefreshDispel()
                    Check(Same(after, Snapshot()), "input refresh changed exact edited profile")
                    CheckDispel(widget, kind, spec, state, factory)
                    Check(M.Undo(), "input created no undo entry") mw:RunTimers()
                    Check(Same(before, Snapshot()), "undo did not restore exact sparse profile")
                    -- Inspect Undo's own repaint before asking for any additional refresh.
                    CheckDispelDisplay(spec, state == "edge", initial, "undo")
                    RefreshDispel()
                    Check(Same(before, Snapshot()), "undo refresh changed exact sparse profile")
                    CheckDispelDisplay(spec, state == "edge", initial, "undo refresh")
                    Check(not M.Undo(), "one input created multiple undo entries")
                    local pending, pendingApplies = M.GetHistoryState(), auraApplies
                    local pendingEntry = Check(M.historyRedo[1], "Undo left no real pending Redo entry")
                    Check(pending.canRedo and pending.redoCount == 1 and pending.undoCount == 0,
                        "Undo did not leave exactly one pending Redo")
                    local function CapturePending(phase, redoResult)
                        return { phase = phase, redoResult = redoResult, db = Snapshot(), display = DispelDisplay(spec),
                            history = M.GetHistoryState(), entry = M.historyRedo[1],
                            undoCount = #M.historyUndo, redoCount = #M.historyRedo, applies = auraApplies }
                    end
                    -- No Setup, ClearHistory or successful Redo until both actual refused inputs and release.
                    core.Util.InCombat("PLAYER_REGEN_DISABLED")
                    env.InCombatLockdown = function() return false end
                    DispelInput(widget, kind)
                    local edge = CapturePending("pending combat-edge", M.Redo())
                    env.InCombatLockdown = function() return true end
                    DispelInput(widget, kind)
                    local locked = CapturePending("pending combat", M.Redo())
                    core.Util.InCombat("PLAYER_REGEN_ENABLED")
                    env.InCombatLockdown = function() return false end
                    mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                    local released = CapturePending("pending combat-release")
                    -- Check captured phases after unlocking, so a failed assertion cannot strand this section in combat.
                    for _, observed in ipairs({ edge, locked, released }) do
                        Check(Same(before, observed.db) and observed.applies == pendingApplies,
                            observed.phase .. " wrote/applied while Redo pending")
                        Check(Same(pending, observed.history) and observed.entry == pendingEntry
                            and observed.undoCount == 0 and observed.redoCount == 1,
                            observed.phase .. " destroyed or replaced pending Redo")
                        CheckDispelDisplay(spec, state == "edge", initial, observed.phase, observed.display)
                    end
                    Check(edge.redoResult == false and locked.redoResult == false, "combat Redo was not refused")
                    Check(M.Redo(), "input created no redo entry") mw:RunTimers()
                    Check(Same(after, Snapshot()), "redo did not restore exact edited profile")
                    CheckDispel(widget, kind, spec, state, factory)
                    RefreshDispel()
                    Check(Same(after, Snapshot()), "redo refresh changed exact edited profile")
                    CheckDispel(widget, kind, spec, state, factory)
                end)
            end
        end
        Section("Dispel readback edge " .. width .. " " .. spec.key, function()
            local defaults = { M._GetDispelTypeRGB(spec.key, false) }
            env.MSUF_DB.general.dispelTypeColorOverrides = { [spec.key] = { r = -2, g = 1.4, b = 0 } }
            local r, g, b = M._GetDispelTypeRGB(spec.key, true)
            Check(r == 0 and g == 1 and b == 0, "named RGB was not clamped")
            env.MSUF_DB.general.dispelTypeColorOverrides[spec.key] = { 0.2, 0.3 }
            r, g, b = M._GetDispelTypeRGB(spec.key, true)
            Check(Near(r, defaults[1]) and Near(g, defaults[2]) and Near(b, defaults[3]), "incomplete RGB fallback drift")
            env.MSUF_DB.general.dispelTypeColorOverrides = nil
            RefreshDispel() color._msuf2OnColorChanged(0, 0.37, 0.91) mw:RunTimers()
            mw:Select("home") mw:Select("opt_colors") mw:RunTimers()
            r, g, b = M._GetDispelTypeRGB(spec.key, true)
            Check(r == 0 and Near(g, 0.37) and Near(b, 0.91), "reopen readback drift")
            enabled:Click("LeftButton") mw:RunTimers()
            Check(env.MSUF_DB.general.dispelTypeColorOverrides == nil, "last disable materialized defaults")
        end)
    end
end
M.ApplyService.RequestAuraFonts = auraApply
env.MSUF_DB.general.dispelTypeColorOverrides = savedOverrides

if #failures > 0 then
    error("menu_colors_page_bugs_smoke (" .. flavor .. "): " .. #failures .. " section(s) failed\n  "
        .. table.concat(failures, "\n  "), 0)
end
print("menu colors: PASS " .. flavor)

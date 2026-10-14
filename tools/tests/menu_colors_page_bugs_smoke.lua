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
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true })
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
local byId, bySetting = {}, {}
local Register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.controlId then
        local copy = {}
        for field, value in pairs(payload) do copy[field] = value end
        byId[copy.controlId] = copy
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

if #failures > 0 then
    error("menu_colors_page_bugs_smoke (" .. flavor .. "): " .. #failures .. " section(s) failed\n  "
        .. table.concat(failures, "\n  "), 0)
end
print("menu colors: PASS " .. flavor)

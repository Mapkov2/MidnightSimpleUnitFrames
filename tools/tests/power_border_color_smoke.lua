-- power_border_color_smoke.lua <repoRoot>
--
-- A unit's power bar border has its own color (unit keys powerBarBorderColorR/G/B).
-- Unset, the border keeps following the frame outline color, so existing profiles
-- look the same. The Power page's Border & fill card offers it through its ":::"
-- picker as "Power bar border" while the border is on.
--
-- Boots each client's real core and Options graph (tools/tests/client_world.lua)
-- and checks, per client:
--   * CompileUnitPower: the outline color until the unit sets its own, then the own color
--   * the "power.border" context target: label, its starting color, the write,
--     and cancel restoring an unset color
--   * Copy To / section reset carry the three keys
-- plus source pins for the card reference and the preview colors.
-- Plain Lua 5.1 with the repo root as argument.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("power_border_color_smoke: " .. message, 2) end
    return condition
end

local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local function ReadSource(relative)
    local handle = Check(io.open(root .. "/" .. relative, "rb"), "cannot read " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local KEYS = { "powerBarBorderColorR", "powerBarBorderColorG", "powerBarBorderColorB" }

local checked = {}
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    Check(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local Config = Check(world.core.UF and world.core.UF.Config, flavor .. ": UF.Config did not load")
    local M = Check(world.core.MSUF2, flavor .. ": Menu2 did not load")
    local db = Config.GetDB()
    local general, target = db.general, db.target
    general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = 0.1, 0.2, 0.3
    target.hlOverride = false
    target.powerBarBorderEnabled = true
    for i = 1, #KEYS do target[KEYS[i]] = nil end

    local power = Config.RefreshUnit("target").power
    Check(Near(power.borderR, 0.1) and Near(power.borderG, 0.2) and Near(power.borderB, 0.3),
        flavor .. ": an unset power border color must follow the frame outline color")

    local targets = M.ResolveContextColorReferences({ "power.border" }, { unit = "target" })
    Check(#targets == 1, flavor .. ": power.border resolves to " .. #targets .. " targets")
    local picker = targets[1]
    Check(picker.label == "Power bar border", flavor .. ": the target is labelled " .. tostring(picker.label))
    local r, g, b = picker.getRGB()
    Check(Near(r, 0.1) and Near(g, 0.2) and Near(b, 0.3), flavor .. ": the picker must start from the outline color")

    local state = picker.captureState()
    picker.setRGB(0.9, 0.4, 0.05)
    Check(Near(target.powerBarBorderColorR, 0.9) and Near(target.powerBarBorderColorG, 0.4)
        and Near(target.powerBarBorderColorB, 0.05), flavor .. ": the picker did not store the unit's own color")
    power = Config.RefreshUnit("target").power
    Check(Near(power.borderR, 0.9) and Near(power.borderG, 0.4) and Near(power.borderB, 0.05),
        flavor .. ": the unit's own power border color must win over the outline color")
    Check(Near(general.barOutlineColorR, 0.1), flavor .. ": the power border color changed the frame outline color")
    r, g, b = picker.getRGB()
    Check(Near(r, 0.9) and Near(g, 0.4) and Near(b, 0.05), flavor .. ": the picker does not read the unit's own color")

    picker.restoreState(state)
    for i = 1, #KEYS do Check(target[KEYS[i]] == nil, flavor .. ": cancel left " .. KEYS[i] .. " behind") end
    power = Config.RefreshUnit("target").power
    Check(Near(power.borderR, 0.1), flavor .. ": after cancel the border must follow the outline color again")

    local fields = " " .. Check(M.UnitPage and M.UnitPage.SectionFields and M.UnitPage.SectionFields.power_bar,
        flavor .. ": the Power section field list is missing") .. " "
    for i = 1, #KEYS do
        Check(fields:find(" " .. KEYS[i] .. " ", 1, true), flavor .. ": Copy To / reset of Power leaves " .. KEYS[i] .. " behind")
    end
    checked[#checked + 1] = flavor
end

local visuals = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua")
Check(visuals:find('refs[#refs + 1] = "bar.power_loss"\n            if ReadPowerBorderEnabled() then refs[#refs + 1] = "power.border" end', 1, true),
    "the Border & fill card no longer offers the power border color while the border is on")

local preview = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
for _, channel in ipairs({ "R", "G", "B" }) do
    Check(preview:find("or tonumber(conf.powerBarBorderColor" .. channel .. ") or tonumber(conf.barOutlineColor" .. channel .. ")", 1, true),
        "the unit preview fallback ignores powerBarBorderColor" .. channel)
end
Check(preview:find("SetBackdropBorderColor(mock._msufPreviewPowerBorderR, mock._msufPreviewPowerBorderG,", 1, true),
    "the detached power preview border is painted black instead of the power border color")

print("power_border_color_smoke: ok (" .. table.concat(checked, ", ") .. ")")

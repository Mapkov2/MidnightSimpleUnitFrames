-- Rebuild an authored layout through the profile APIs, then read the active castbars and preview.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local ClientWorld = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
Corpus.Login(world, {})
local gameType = world.client.isForever and "camelot" or nil
local options = ClientWorld.Graph(root, ClientWorld.OptionsTOC(world.client.tocSuffix or flavor), "enUS", gameType)
world:LoadGraph("MidnightSimpleUnitFrames_Options", options, world.options)
local mw = MenuWorld.Open(root, flavor, { world = world, page = "opt_castbar" })
local env, core, menu = mw.env, mw.core, mw.M
local profiles, castbars = core.PublicGlobals, core.Castbars

local units = {
    { unit = "player", prefix = "castbarPlayer", enabled = "enablePlayerCastbar", timer = "showPlayerCastTime",
      controlX = -31, draftX = 0, timePosition = "LEFT", widthMode = "AUTO", timeFormat = "CURRENT" },
    { unit = "target", prefix = "castbarTarget", enabled = "enableTargetCastbar", timer = "showTargetCastTime",
      controlX = 37, draftX = 7, timePosition = "RIGHT", widthMode = "CLIP", timeFormat = "CURRENT_MAX" },
}

local function Author(draft)
    local db = env.MSUF_DB
    for _, spec in ipairs(units) do
        local prefix, general = spec.prefix, db.general
        general[spec.enabled], general[spec.timer] = true, draft
        general[prefix .. "ShowSpellName"] = true
        general[prefix .. "SpellNamePosition"] = "CENTER"
        general[prefix .. "TextOffsetX"] = draft and spec.draftX or spec.controlX
        general[prefix .. "TimePosition"] = spec.timePosition
        general[prefix .. "TimeOffsetX"] = -2
        general[prefix .. "TimeFontSize"] = 12
        general[prefix .. "TimeFormat"] = spec.timeFormat
        general[prefix .. "SpellNameTruncate"] = spec.widthMode
        general[prefix .. "SpellNameMaxWidth"] = 100
        db[spec.unit].width = draft and 350 or 270
    end
end

local function CheckAnchor(frame, spec, expectedX, hasTimer, label)
    local context = label .. " " .. spec.unit
    local point, bar, relative, x = frame.castText:GetPoint(1)
    assert(point == "CENTER" and bar == frame.statusBar and relative == "CENTER", context .. " lost its center anchor")
    assert(frame.castText:GetJustifyH() == "CENTER", context .. " lost its center justification")
    assert(x == expectedX, ("%s expected anchor X=%g, got %s"):format(context, expectedX, tostring(x)))
    assert(frame.castText:GetAlpha() == 1, context .. " hid the spell name")
    local width = frame.castText:GetWidth()
    assert(width > 1, context .. " lost usable spell-name width")
    if hasTimer then
        local timerPoint, timerBar = frame.timeText:GetPoint(1)
        assert(timerPoint == spec.timePosition and timerBar == bar, context .. " misplaced timer")
        assert(frame.timeText:GetAlpha() == 1, context .. " hid the timer")
        assert(width < bar:GetWidth(), context .. " left the name unconstrained beside the timer")
    else
        assert(frame.timeText:GetAlpha() == 0, context .. " inherited the timer visibility")
    end
    if spec.widthMode == "CLIP" then
        assert(width <= 100, context .. " lost its manual width limit")
    end
end

local function CheckLayout(name, draft)
    local profile = env.MSUF_DB
    assert(env.MSUF_ActiveProfile == name and profile == env.MSUF_GlobalDB.profiles[name], name .. " was not rebound")
    for _, spec in ipairs(units) do
        local prefix, general = spec.prefix, profile.general
        local x = draft and spec.draftX or spec.controlX
        assert(profile[spec.unit].width == (draft and 350 or 270), name .. " lost the unit-frame width")
        assert(general[spec.timer] == draft and general[prefix .. "TextOffsetX"] == x, name .. " lost saved castbar values")
        assert(general[prefix .. "SpellNamePosition"] == "CENTER" and general[prefix .. "SpellNameTruncate"] == spec.widthMode,
            name .. " changed the spell-name settings")
        CheckAnchor(assert(castbars.Frames[spec.unit]), spec, x, draft, name .. " live")
        menu.SetCastbarPreviewUnit(spec.unit)
        local preview = assert(menu._msuf2CastbarPreview)
        preview:Refresh()
        CheckAnchor(assert(preview.frame), spec, x, draft, name .. " preview")
    end
end

local function SwitchAndCheck(name, draft)
    assert(profiles.MSUF_SwitchProfile(name))
    CheckLayout(name, draft)
end

local existing, fresh, design = assert(env.MSUF_ActiveProfile), "Fresh layout", "Authored layout"
local defaults = {}
for _, spec in ipairs(units) do
    defaults[spec.unit] = {
        x = env.MSUF_DB.general[spec.prefix .. "TextOffsetX"],
        width = env.MSUF_DB[spec.unit].width,
    }
end
Author(false)
assert(profiles.MSUF_CreateProfile(fresh))
assert(env.MSUF_ActiveProfile == existing, "new profile replaced the current profile")
assert(profiles.MSUF_SwitchProfile(fresh))
for _, spec in ipairs(units) do
    local expected = defaults[spec.unit]
    assert(env.MSUF_DB.general[spec.prefix .. "TextOffsetX"] == expected.x, "fresh profile inherited the existing castbar offset")
    assert(env.MSUF_DB[spec.unit].width == expected.width, "fresh profile inherited the existing unit-frame width")
end
SwitchAndCheck(existing, false)

-- Modern Dark's supported hosts start the reconstruction from the shipped frame preset.
if flavor == "Mainline" or flavor == "Forever" then
    local compact = assert(core.MSUF_MODERN_DARK_PROFILE_COMPACT, "shipped Modern Dark profile missing")
    assert(profiles.MSUF_ImportIntoNewProfile(design, compact))
else
    assert(profiles.MSUF_CreateProfile(design))
end
assert(profiles.MSUF_SwitchProfile(design))
Author(true)
local portable = assert(profiles.MSUF_ExportSelectionToString("all"))
assert(profiles.MSUF_CopyProfile(design, "Local copy"))
assert(env.MSUF_ActiveProfile == design, "copy replaced the current profile")
assert(profiles.MSUF_ImportIntoNewProfile("Rebuilt from export", portable))
CheckLayout("Rebuilt from export", true)
SwitchAndCheck("Local copy", true)
Author(false)
SwitchAndCheck(design, true)
SwitchAndCheck("Rebuilt from export", true)
SwitchAndCheck("Local copy", false)
SwitchAndCheck(existing, false)

local errors = Corpus.UnexpectedErrors({ world = world, flavor = flavor }, {})
assert(#errors == 0, "unexpected profile errors:\n" .. table.concat(errors, "\n"))
print("profile_castbar_layout_smoke " .. flavor .. ": passed (fresh, copied, imported and existing profile layouts)")

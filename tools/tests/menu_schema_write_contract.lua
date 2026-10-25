-- Custom actions publish physical writes; editor actions explicitly publish none.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local M = { Widgets = {} }
local namespace = { MSUF2 = M, CPBuilders = { ExtraAuraDefaults = {} } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua"))("Options", namespace)
local S = M.ControlSchema
assert(S.Writes and S.MatchesWrite, "concrete schema write contracts missing (red baseline)")
local widget = {}
local function Declare(spec)
    spec.id, spec.kind, spec.scope, spec.applyDomain = "contract", "toggle", "unit", spec.applyDomain or "unit"
    S.Custom(widget, spec)
    return widget._msuf2ControlSchema
end
local spec = Declare({ setting = "player.enabled" })
assert(S.MatchesWrite(spec, "player.enabled") and not S.MatchesWrite(spec, "target.enabled"), "single-key contract escaped")
spec = Declare({ setting = S.Record({ "gf_{scope}.spellIndicators.multiSpecs.{spec}" }) })
assert(S.MatchesWrite(spec, "gf_raid.spellIndicators.multiSpecs.123")
    and not S.MatchesWrite(spec, "gf_raid.unrelated"), "record contract escaped")
spec = Declare({ setting = S.Family({ "player.first", "player.second" }) })
assert(#spec.writes.keys == 2 and S.MatchesWrite(spec, "player.second"), "compound contract lost a companion write")
spec = Declare({ ephemeralReason = "Changes the selected editor tab.", applyDomain = "menuState" })
assert(spec.writes.menuState and #spec.writes.keys == 0 and not S.MatchesWrite(spec, "player.enabled"), "menu action declares profile writes")
local original = { "player.first" }
spec = Declare({ setting = S.Family(original) })
original[1] = "player.other"
assert(S.MatchesWrite(spec, "player.first") and not S.MatchesWrite(spec, "player.other"), "contract follows mutable search metadata")
Declare({ ephemeralReason = "Selects a temporary preview." })
S.SetSetting(widget, "player.stateIconsTestMode")
assert(S.MatchesWrite(widget._msuf2ControlSchema, "player.stateIconsTestMode")
    and not widget._msuf2ControlSchema.writes.menuState, "late composite target retained its earlier zero-write contract")
S.SetSetting(widget, nil)
assert(widget._msuf2ControlSchema.writes.menuState
    and not S.MatchesWrite(widget._msuf2ControlSchema, "player.stateIconsTestMode"), "temporary composite retained profile writes")
spec = Declare({ setting = "player.anchorToUnitframe", companionWrites = { "player.anchorFrameName" } })
assert(S.MatchesWrite(spec, "player.anchorFrameName"), "anchor command omitted its cleared companion")
spec = Declare({ ephemeralReason = "Selects a group spec and initializes its defaults.",
    writeTargets = S.Record({ "gf_{scope}.spellIndicators" }) })
assert(not spec.writes.menuState and S.MatchesWrite(spec, "gf_raid.spellIndicators.specs.123.New.spellID"),
    "selection with record initialization claimed no writes")
local existing = function() return "existing binding" end
local command = { set = existing, write = { keyOnly = true } }
Declare({ setting = "player.enabled", meta = { command = command } })
assert(command.set == existing, "declaration rebound an existing compound command")
for _, row in ipairs({
    { "reset_aura_colors", "general.aurasCooldownTextSafeColor.r", 8 },
    { "reset_bar_colors", "general.barOutlineColorA", 44 },
    { "reset_castbar_colors", "general.castbarFontR", 34 },
    { "reset_unitframe_colors", "general.petFrameUsePlayerClassColor", 7 },
    { "reset_portrait_colors", "boss.portraitBgColorB", 56 },
}) do
    spec = Declare({ actionKey = row[1] })
    assert(#spec.writes.keys == row[3] and S.MatchesWrite(spec, row[2]), row[1] .. ": reset fields incomplete")
    assert(not S.MatchesWrite(spec, "general.unrelated") and not S.MatchesWrite(spec, "player.unrelated"),
        row[1] .. ": reset admitted unrelated profile siblings")
end
M.ClassPowerWorkspace = { QuickWriteKeys = { bars = { "height" }, player = { "showPowerBar" } } }
spec = Declare({ actionKey = "class_power_quick_setup" })
assert(#spec.writes.keys == 3 and S.MatchesWrite(spec, "bars.height") and not S.MatchesWrite(spec, "bars.unrelated"),
    "quick setup contract diverged from its canonical undo fields")
M.GroupPage = { GF_STATUS_ICON_SPECS = { { size = "roleIconSize", x = "roleIconOffsetX" } } }
spec = Declare({ actionKey = "reset_selected_group_status_icon" })
assert(S.MatchesWrite(spec, "gf_raid.roleIconSize") and not S.MatchesWrite(spec, "gf_raid.unrelated"),
    "group status reset escaped its finite field list")
M.UnitPage = { STATUS_CONTROLS = { { x = "restingX", colorPrefix = "threatIndicator" } } }
S.Custom(widget, { id = "contract.unit.reset", kind = "button", scope = "uf_player", applyDomain = "unit",
    actionKey = "reset_unit_status_indicator" })
spec = widget._msuf2ControlSchema
assert(S.MatchesWrite(spec, "player.restingX") and S.MatchesWrite(spec, "player.threatIndicatorColorR")
    and not S.MatchesWrite(spec, "player.unrelated") and not S.MatchesWrite(spec, "0.restingX"),
    "unit status reset escaped its finite physical fields")
local calls = 0
local refuse = S.Setter({ id = "contract.refusal", setting = "general.selection", write = {
    keyOnly = true, accept = function(value) return value ~= "refuse" end, refused = false,
    convert = function(value) calls = calls + 1; return value end,
    call = function(key, value) assert(key == "selection" and value == "allow"); calls = calls + 1 end,
    after = function() calls = calls + 1 end,
} })
assert(refuse("refuse") == false and calls == 0, "refused writer normalized, wrote or refreshed")
assert(refuse("allow") == nil and calls == 3, "accepted writer changed its return or execution order")
print("PASS concrete write contracts: scalar/compound/dynamic targets; explicit zero-write menu actions; immutable snapshot")

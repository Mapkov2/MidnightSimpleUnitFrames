-- menu_color_cancel_false_smoke.lua <repoRoot>
--
-- Cancelling the menu's colour picker restores what each target captured on
-- open. A setting stored as false must come back as false, not nil: nil means
-- "use the default", and for a group scope's useGlobalFontColor the default is
-- true, so Cancel switched a custom group font colour back to the global one
-- and recorded an undo step (bh2 H-C7-03). The ::: text shortcut
-- (TextQuickSettings) and the Advanced Colors context targets
-- (AdvancedColors_Context, field and per-row states) share the idiom.
--
-- Boots the real Classic Era core and Options graph. Plain Lua 5.1, repo root.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_color_cancel_false_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Vanilla")
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local M = Check(world.core.MSUF2, "Menu2 did not load")
local W = Check(M.Widgets, "Menu2 widgets missing")
local factories = Check(M.ContextColorReferenceFactories, "context colour factories missing")
world.widgets:ClearTimers()

local db = Check(M.EnsureDB(), "profile DB missing")
local function CustomGroupColor()
    db.gf_party = db.gf_party or {}
    local party = db.gf_party
    party.fontOverride, party.useGlobalFontColor = true, false
    party.fontR, party.fontG, party.fontB = 1, 0.5, 0
    return party
end
-- Open, drag the wheel once, Cancel: panel:Finish(true) -> restoreState(saved).
local function OpenDragCancel(target, what)
    Check(type(target) == "table" and target.captureState and target.restoreState, what .. " has no restore state")
    local saved = target.captureState()
    target.setRGB(0.2, 0.4, 0.9)
    target.restoreState(saved)
end

-- 1. The ::: shortcut of a Party text card (TextQuickSettings).
local party = CustomGroupColor()
local captured
local open = W.OpenContextColors
W.OpenContextColors = function(_, _, targets) captured = targets; return true end
W.OpenTextQuickSettings({ GetParent = function() return world.env.UIParent end },
    { textSettings = { scope = "gf_party", kind = "name", group = true, capabilities = { colorMode = false } } })
W.OpenContextColors = open
local target = Check(captured and captured[1], "the text shortcut opened no colour target")
Check(target.label == "Group font color", "the text shortcut offered " .. tostring(target.label))
OpenDragCancel(target, "the text shortcut target")
Check(party.useGlobalFontColor == false, "Cancel on the text shortcut turned useGlobalFontColor into "
    .. tostring(party.useGlobalFontColor))
Check(party.fontR == 1 and party.fontG == 0.5 and party.fontB == 0, "Cancel on the text shortcut lost the colour")

-- 2. The Advanced Colors group font target (per-row state).
party = CustomGroupColor()
OpenDragCancel(Check(factories["font.default.current"], "font.default.current missing")({ scope = "gf_party" }),
    "the Advanced Colors group font target")
Check(party.useGlobalFontColor == false, "Cancel on the Advanced Colors group font target turned useGlobalFontColor into "
    .. tostring(party.useGlobalFontColor))

-- 3. The default font target (field state on the general table).
local general = Check(db.general, "general table missing")
general.useCustomFontColor = false
OpenDragCancel(Check(factories["font.global"], "font.global missing")(), "the default font target")
Check(rawget(general, "useCustomFontColor") == false, "Cancel on the default font target turned useCustomFontColor into "
    .. tostring(rawget(general, "useCustomFontColor")))

print("menu_color_cancel_false_smoke: ok (Cancel keeps false on the text shortcut, a group row and a general field)")

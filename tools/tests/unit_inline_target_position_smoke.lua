local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local inlineExists = true
local inlineName = "Ally"
local mw = World.Open(root, flavor, { beforeCore = function(world)
    World.InstallNativeUnitInputs(world)
    world.env.issecretvalue = Secrets.IsSecret
    local unitExists, unitName = world.env.UnitExists, world.env.UnitName
    world.env.UnitExists = function(unit)
        if unit == "targettarget" then return inlineExists end
        return unitExists(unit)
    end
    world.env.UnitName = function(unit)
        if unit == "targettarget" then return inlineName end
        return unitName(unit)
    end
end })
local M, core = mw.M, mw.core
local db, text = M.EnsureDB(), core.UFText

-- The Pre-Midnight target keeps a large direct name box. Its inline suffix
-- should follow the short name inside that box.
local target = db.target
target.showName = true
target.directTextLayout, target.directNameWidth = true, 200
target.directNamePoint, target.directNameRelativePoint = "TOPLEFT", "TOPLEFT"
target.directNameOffsetX, target.directNameOffsetY = 8, -2
target.nameTextAnchor = "TOPRIGHT"
db.targettarget.showToTInTargetName = true
local frame = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
local function Paint()
    core.UF.Config.Refresh()
    local spec = core.UF.Config.GetSpec("target")
    frame.MSUFSpec = spec
    text.Apply(frame, spec)
    text.PaintSampleName(frame, "Mapko")
    text.PaintSampleInline(frame, "Ally")
end
local function CheckAnchor(point)
    local name, proxy = frame.nameText, assert(frame._msufNameAnchorText)
    assert(name._msufPoint == point and proxy._msufPoint == point)
    assert(proxy._msufRelPoint == point and proxy._msufX == 8 and proxy._msufY == -2)
    assert(name:GetWidth() == 200 and proxy:GetWidth() == 0, "the name twin must size to its text")
    assert(name:GetText() == "Mapko" and proxy:GetText() == "Mapko")
    local sep = frame.totInlineSep
    assert(sep._msufRelativeTo == proxy and sep._msufRelPoint == "RIGHT",
        "inline text must follow the target's rendered name")
    assert(frame.totInlineText._msufRelativeTo == sep and frame.totInlineText:GetText() == "Ally")
end
Paint()
CheckAnchor("TOPLEFT")

assert(mw:Select("uf_target"))
local entry = assert(M.cache.uf_target)
local disclosure = assert(entry.sections.text)._msuf2CollapsibleEntry
if disclosure._msuf2EnsureContent then disclosure._msuf2EnsureContent() end
disclosure.SetOpenImmediate(true)
M.Refresh()
local anchor
for _, widget in ipairs(entry.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    if record and record.controlId:match("text%.name%.anchor$") then anchor = widget end
end
local action = assert(anchor, "target name anchor control missing")._msuf2CommandAction
assert(action.get() == "TOPLEFT", "menu did not read the active direct point")
action.set("FRAMECENTER")
assert(target.directNamePoint == "CENTER" and target.directNameRelativePoint == "CENTER")
assert(action.get() == "FRAMECENTER")
Paint()
CheckAnchor("CENTER")
action.set("TOPRIGHT")
Paint()
local suffix, glyph, sep = frame.totInlineText, frame._msufInlineRightGlyph, frame.totInlineSep
assert(action.get() == "TOPRIGHT" and suffix._msufPoint == "TOPRIGHT")
assert(suffix._msufRelPoint == "TOPRIGHT" and suffix._msufX == 8 and suffix._msufY == -2)
assert(glyph:GetText() == "Ally" and glyph:GetWidth() == 0 and suffix._msufJustifyH == "RIGHT")
assert(sep._msufRelativeTo == glyph and sep._msufRelPoint == "LEFT")
assert(frame.nameText._msufRelativeTo == sep and frame.nameText._msufRelPoint == "LEFT",
    "right placement must fit the entire inline row before the anchor")
text.PaintSampleInline(frame, "")
assert(frame.nameText._msufPoint == "TOPRIGHT" and frame.nameText._msufRelativeTo == suffix._msufRelativeTo,
    "losing the suffix displaced the target's own name")
text.PaintSampleInline(frame, "Another ally")
assert(frame.nameText._msufRelativeTo == sep and glyph:GetText() == "Another ally")
inlineExists = false
text.UpdateInline(frame, "UNIT_TARGET", "target")
assert(frame.nameText._msufRelativeTo == suffix._msufRelativeTo and not suffix:IsShown())
inlineExists = true
if flavor == "Mainline" or flavor == "Forever" then
    inlineName = Secrets.New("string")
    local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", { strict = true })
    text.UpdateInline(frame, "UNIT_TARGET", "target")
    assert(#stop() == 0, "the inline update inspected a restricted name")
    assert(Secrets.IsSecret(suffix:GetText()) and Secrets.IsSecret(glyph:GetText()),
        "the restricted name must reach both native text sinks")
    inlineName = "Ally"
end
action.set("TOPLEFT")
Paint()
CheckAnchor("TOPLEFT")
assert(not glyph:IsShown(), "left placement retained the right-side glyph sink")

db.targettarget.showToTInTargetName = false
Paint()
assert(frame._msufNameAnchorTextActive ~= true and not frame.totInlineSep:IsShown(),
    "turning inline text off retained the suffix or its sizing sink")
print("PASS inline Target of Target name sizing and position control: " .. flavor)

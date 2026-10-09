-- Exercise the real menu binding, deferred apply, mask/edge resolver and previews.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true })
local M, env, UF = mw.M, mw.env, mw.core.UF
local dropdown
local Dropdown = M.Widgets.Dropdown
M.Widgets.Dropdown = function(parent, label, ...)
    local result = Dropdown(parent, label, ...)
    if label == "Cut direction" then dropdown = result end
    return result
end
mw:Select("opt_bars")
M.Widgets.EnsureSectionContent(assert(M.cache.opt_bars.sections.bars_slanted))
mw:RunTimers()
assert(dropdown and dropdown._msuf2OnValueChanged, "cut direction did not bind")
local db, kit, preview = M.EnsureDB(), mw.core.RoundedSurfaceKit, M.PreviewHelpers
local fields = mw.core.ProfileFields
local factory = assert(fields.CopySnapshot(db))
mw.core.MSUF_CreateFactoryDefaultProfile = function() return fields.CopySnapshot(factory) end
db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames, db.bars.slantedGroupFrames = true, true, true
db.bars.slantedPowerBars, db.bars.slantedBarDirection = true, "BOTH_DOWN"
env.MSUF_ApplyRoundedUnitframes()
local applies, Apply = 0, env.MSUF_ApplyRoundedUnitframes
env.MSUF_ApplyRoundedUnitframes = function(...)
    applies = applies + 1
    return Apply(...)
end
local function Select(scope, direction)
    db.general.hpPowerTextSelectedKey = scope
    dropdown._msuf2OnValueChanged(direction)
end
local frames = {}
for _, unit in ipairs({ "player", "target" }) do
    local f = env.CreateFrame("Button", nil, env.UIParent)
    f:SetSize(180, 40)
    f.MSUFUnitKey, f.unit = unit, unit
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.hpBar = env.CreateFrame("StatusBar", nil, f)
    f.hpBar:SetSize(180, 30)
    f.targetPowerBar = env.CreateFrame("StatusBar", nil, f)
    f.targetPowerBar:SetSize(180, 8)
    UF.frames[unit], UF.frameList[#UF.frameList + 1], frames[unit] = f, f, f
end
local function Paths(scope, direction, group)
    local frame = { configKey = scope }
    if group then frame._msufIsGroupFrame, frame._msufGFKind = true, group end
    local mask, edge = kit.SurfaceMaskPath(frame), kit.SurfaceEdgePath(frame)
    assert(mask == kit.SLANTED_MASK_PATHS[direction], scope .. ": wrong mask: " .. tostring(mask))
    assert(edge == kit.SLANTED_EDGE_PATHS[direction], scope .. ": wrong edge")
    local pm, pe = preview.ResolveFrameBarMedia("SLANTED", group and nil or scope, group and db[scope] or nil)
    assert(pm == mask and pe == edge, scope .. ": preview differs from runtime")
    local live = frames[scope]
    if live then
        local masks = assert(live._msufRUF_MaskedTextures, "runtime did not mask unit")
        for _, bar in ipairs({ live.hpBar, live.targetPowerBar }) do
            local attached = assert(masks[bar:GetStatusBarTexture()], scope .. ": missing Health/Power mask")
            assert(attached:GetTexture() == mask, scope .. ": Health/Power uses wrong direction")
        end
        assert(live._msufRUF_Edge and live._msufRUF_Edge:GetTexture() == edge,
            scope .. ": runtime outline did not repaint with the bars")
    end
end
for _, scope in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena", "gf_party", "gf_raid", "gf_mythicraid" }) do
    db[scope] = db[scope] or {}
    db[scope].frameBarShape, db[scope].slantedBarDirection = "SLANTED", nil
end
-- Global legacy direction remains the fallback; overrides never activate unrelated colors.
env.MSUF_ApplyRoundedUnitframes()
applies = 0
Paths("player", "BOTH_DOWN")
local playerOverride, targetOverride = db.player.hlOverride, db.target.hlOverride
Select("player", "LEFT_DOWN")
Select("target", "RIGHT_UP")
assert(db.player.hlOverride == playerOverride and db.target.hlOverride == targetOverride,
    "cut direction changed unrelated custom color/bar settings")
assert(applies == 0, "direction selection painted synchronously")
mw:RunTimers()
assert(applies == 1, "burst was not coalesced")
Paths("player", "LEFT_DOWN")
Paths("target", "RIGHT_UP")
Select("player", "RIGHT_DOWN")
Select("target", "LEFT_UP")
mw:RunTimers()
Paths("player", "RIGHT_DOWN")
Paths("target", "LEFT_UP")
local am = { container = env.CreateFrame("Frame", nil, env.UIParent) }
am.container:SetSize(180, 8)
am.bar = env.CreateFrame("StatusBar", nil, am.container)
am.bar:SetSize(180, 8)
am.bgTex = am.container:CreateTexture(nil, "BACKGROUND")
am._border = env.CreateFrame("Frame", nil, am.container)
assert(mw.core.RoundedSurface.ApplyAltMana(am, true), "AltMana did not apply Player's shape")
local manaMask = assert(am.container._msufRAMMaskedTextures[am.bar:GetStatusBarTexture()])
assert(manaMask:GetTexture() == kit.SLANTED_MASK_PATHS.RIGHT_DOWN, "AltMana lost Player's scoped direction")
assert(mw.core.RoundedSurface.ResolveSlantedMedia() == kit.SLANTED_MASK_PATHS.BOTH_DOWN,
    "scope override changed shared extra surfaces")
-- The real preview painters must forward the unit/config, not the shared direction.
local Resolve, seenScope, seenConf = preview.ResolveFrameBarMedia
preview.ResolveFrameBarMedia = function(style, scope, conf)
    seenScope, seenConf = scope, conf
    return Resolve(style, scope, conf)
end
local mock = env.CreateFrame("Frame", nil, env.UIParent)
mock:SetSize(180, 40)
mock.hpBG, mock.hp, mock.powerBG, mock.power = mock:CreateTexture(), mock:CreateTexture(), mock:CreateTexture(), mock:CreateTexture()
mw.core.UFPreviewCore.ApplyRounded({ mock = mock }, "target", true, 1, true, 1)
assert(seenScope == "target", "unit preview lost its selected scope")
local gm = env.CreateFrame("Frame", nil, env.UIParent)
gm:SetSize(180, 40)
gm._health = env.CreateFrame("StatusBar", nil, gm)
gm._power = env.CreateFrame("StatusBar", nil, gm)
M.GroupPreviewRounded.ApplyRounded(gm, db.gf_party, true, 1, true, false, 1)
assert(seenConf == db.gf_party, "group preview lost its config")
preview.ResolveFrameBarMedia = Resolve
for _, scope in ipairs({ "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena", "gf_party", "gf_raid" }) do
    Select(scope, "BOTH_UP")
    mw:RunTimers()
    Paths(scope, "BOTH_UP", scope:match("^gf_(.+)$"))
end
assert(db.gf_mythicraid.slantedBarDirection == "BOTH_UP", "Raid did not update its Mythic config")
Paths("gf_mythicraid", "BOTH_UP", "mythicraid")
-- Boss/arena tokens resolve through their category config.
assert(kit.SurfaceMaskPath({ MSUFUnitKey = "boss1" }) == kit.SLANTED_MASK_PATHS.BOTH_UP)
assert(kit.SurfaceMaskPath({ MSUFUnitKey = "arena2" }) == kit.SLANTED_MASK_PATHS.BOTH_UP)
local count = applies
Select("player", "RIGHT_DOWN")
Select("player", "INVALID")
mw:RunTimers()
assert(applies == count, "no-op/invalid selection scheduled work")
-- Reset only this direction to inheritance; changing Shared preserves Target's override.
Select("player", "DEFAULT")
mw:RunTimers()
assert(dropdown.value == "DEFAULT", "inherited scope did not display Use shared style")
local choices = dropdown.values()
assert(#choices == 7 and choices[1].value == "DEFAULT", "scoped directions lost inheritance option")
Select("shared", "LEFT_DOWN")
mw:RunTimers()
assert(#dropdown.values() == 6, "Shared offered a meaningless inheritance option")
assert(db.player.slantedBarDirection == nil and db.target.slantedBarDirection == "LEFT_UP")
Paths("player", "LEFT_DOWN")
Paths("target", "LEFT_UP")
db.player.slantedBarDirection = "INVALID"
Paths("player", "LEFT_DOWN")
-- Combat holds the transaction; leaving combat applies the latest selection once.
count = applies
Select("target", "RIGHT_DOWN")
Select("target", "BOTH_DOWN")
mw.world:EnterCombat()
mw:RunTimers()
assert(applies == count, "combat painted protected surfaces")
mw.world:LeaveCombat()
mw:RunTimers()
assert(applies == count + 1, "combat replay was lost or duplicated")
Paths("target", "BOTH_DOWN")
mw:RunTimers()
assert(applies == count + 1, "idle repeated direction apply")
-- History restores the scoped value, and Bars page reset removes the new field.
mw:RunTimers()
assert(M.Undo(), "scope change was not undoable")
db = M.EnsureDB()
assert(db.target.slantedBarDirection == "RIGHT_DOWN", "Undo restored the wrong scope direction")
mw:RunTimers()
Paths("target", "RIGHT_DOWN")
assert(M.Redo(), "scope change was not redoable")
db = M.EnsureDB()
assert(db.target.slantedBarDirection == "BOTH_DOWN", "Redo restored the wrong scope direction")
mw:RunTimers()
Paths("target", "BOTH_DOWN")
assert(M.ResetPageToDefaults("opt_bars"), "Bars page reset failed")
db = M.EnsureDB()
assert(db.player.slantedBarDirection == nil and db.target.slantedBarDirection == nil
    and db.gf_raid.slantedBarDirection == nil, "Bars reset left scoped directions behind")
print("slanted_direction_scope_smoke: OK (" .. flavor .. ")")

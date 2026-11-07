local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "classpower", beforeCore = function(world)
    world.env.RAID_CLASS_COLORS = {
        ROGUE = { r = 1, g = .9, b = .3 }, WARRIOR = { r = .8, g = .6, b = .4 },
        DRUID = { r = 1, g = .5, b = .1 }, MAGE = { r = .4, g = .8, b = .9 },
    }
    local enum = world.env.Enum
    world.env.Enum = setmetatable({ PowerType = setmetatable({
        Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6,
        SoulShards = 7, LunarPower = 8, HolyPower = 9, Maelstrom = 11, Chi = 12, Insanity = 13,
        BurningEmbers = 14, DemonicFury = 15, ArcaneCharges = 16, Essence = 19,
    }, { __index = enum and enum.PowerType }) }, { __index = enum })
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, db = mw.M, mw.env.MSUF_DB
local ui = assert(M.ClassPowerWorkspace.current)
local box = assert(ui.page.ctx.entry.classPowerPreview)
local bars, player = db.bars, db.player
local function Check(condition, message)
    assert(condition, flavor .. ": " .. message)
end
local function Select(key)
    M.SetClassPowerPreviewSpecKey(key)
    mw:RunTimers()
end
local function Shown(frame)
    return frame and frame:IsShown()
end
local function PowerColor()
    local bar = box.detachedPower
    if box.playerRuntime then return bar:GetStatusBarColor() end
    return bar.fill:GetVertexColor()
end
local function HealthColor()
    local bar = box.playerHP
    if box.playerRuntime then return bar._msufRuntimeHealthState.bar:GetStatusBarColor() end
    return bar.fill:GetVertexColor()
end

bars.showClassPower, bars.showAltMana, bars.playerHPBarEnabled = true, true, true
bars.playerHPBarColorMode = "CLASS"
bars.playerHPBarAnchor, bars.playerHPBarWidthMode = "POWER_TOP", "power"
bars.detachedPowerBarWidthMode = "manual"
player.showPowerBar, player.powerBarDetached = true, true
player.detachedPowerBarShape = "BAR"
player.detachedPowerBarAnchorToClassPower, player.detachedPowerBarSyncClassPower = false, false
player.detachedPowerBarWidth, player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 334, 350, 34
player.detachedPowerBarAnchorMode, player.playerPowerSource = "CENTER", "AUTO"
db.general.powerColorMode = "power"
db.general.powerColorOverrides = {
    ENERGY = { .8, .1, .2 }, RAGE = { .4, .2, .3 }, MANA = { .2, .3, .8 }, MAELSTROM = { .3, .7, .8 },
}

ui:Select("power")
Select("rogue_combo")
box:Refresh()
Check(Shown(box.detachedPower) and Shown(box.handlePower), "unanchored detached power is missing")
local _, anchor, _, x, y = box.detachedPower:GetPoint()
Check(anchor == box.playerRef and x == 350 and y == 34, "free Player Power offsets are ignored")
Check(box.detachedPower:GetWidth() == 334, "configured Player Power width is ignored")
Check(PowerColor() == .8, "Rogue does not use its Energy color")
Check(not Shown(box.altMana) and not Shown(box.handleMana) and not box.layerAvailable.mana, "Rogue has an extra Mana bar")
Check(Shown(box.playerHP) and box.playerHP:GetWidth() == 334, "Extra Health cannot follow free Player Power width")
local _, hpAnchor = box.playerHP:GetPoint()
Check(hpAnchor == box.detachedPower, "Extra Health cannot anchor to free Player Power")

ui:Select("hp")
local rogueHealthG = select(2, HealthColor())
Select("druid_guardian")
if M.GetClassPowerPreviewSpecKey() == "druid_guardian" then
    Check(PowerColor() == .4, "Guardian does not use its Rage color")
    Check(select(2, HealthColor()) ~= rogueHealthG, "Extra Health retains the previous class color")
end

ui:Select("mana")
db.general.classPowerColorOverrides = { MANA = { .15, .45, .75 } }
Select("druid_feral")
Check(Shown(box.altMana) and Shown(box.handleMana) and box.layerAvailable.mana, "Feral has no separate Mana bar")
local manaR
if box.playerRuntime then manaR = box.auxiliary.AM.bar:GetStatusBarColor()
else manaR = box.altMana.fill:GetVertexColor() end
Check(manaR == .15, "Alternative Mana ignores its Class Resource color")
player.playerPowerSource = "MANA"
box:Refresh()
Check(PowerColor() == .2, "Feral's configured Mana source is ignored")
Check(not Shown(box.altMana) and not Shown(box.handleMana) and not box.layerAvailable.mana, "Mana is displayed twice")
player.playerPowerSource = "AUTO"
box:Refresh()
Check(Shown(box.altMana) and Shown(box.handleMana), "alternative Mana does not return after restoring AUTO")
bars.showAltMana = false
box:Refresh()
Check(not Shown(box.altMana) and not Shown(box.handleMana), "disabling Alternative Mana left a preview")
bars.showAltMana = true
bars.playerHPBarEnabled = false
box:Refresh()
Check(not Shown(box.playerHP) and not Shown(box.handleHP), "disabling Extra Health left a preview")

ui:Select("power")
player.detachedPowerBarAnchorToClassPower = true
box:Refresh()
local _, classAnchor = box.detachedPower:GetPoint()
Check(classAnchor == box.classPower, "enabling the Class Resource anchor did not move Player Power")
player.showPowerBar = false
box:Refresh()
Check(not Shown(box.detachedPower) and not Shown(box.handlePower), "a disabled Player Power bar is still previewed")
player.showPowerBar, player.powerBarDetached = true, false
box:Refresh()
Check(not Shown(box.detachedPower) and not Shown(box.handlePower), "attached Player Power is still previewed as detached")

if flavor == "Mainline" then
    player.showPowerBar, player.powerBarDetached = true, true
    bars.showEleMaelstrom = false
    Select("shaman_elemental")
    Check(PowerColor() == .3 and Shown(box.altMana), "Elemental lost Maelstrom when the class row was disabled")
    bars.showEleMaelstrom = true
    box:Refresh()
    Check(PowerColor() == .2 and not Shown(box.altMana), "Elemental class row did not take ownership of Maelstrom")
end

if M.ClassPowerPreviewSpecs.monk_windwalker then
    player.showPowerBar, player.powerBarDetached = true, true
    Select("monk_windwalker")
    Check(PowerColor() == .8 and Shown(box.altMana), "Windwalker did not preview Energy alongside Mana")
end

player.showPowerBar, player.powerBarDetached = false, false
ui:Select("extras")
Check(M.ResourceExtrasPreview.Select("cost"), "Mana cost example unavailable")
M.ResourceExtrasPreview.UpdateHeader(ui.page.ctx, "extras")
box:Refresh()
Check(Shown(box.detachedPower), "disabled live Power hides the example Power bar")

print("PASS Class Resources auxiliary previews: " .. flavor)

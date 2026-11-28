local root, flavor = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local narrow = flavor == "Vanilla" or flavor == "Forever"
local w = World.Open(root, flavor, { open = false, beforeCore = function(world)
    world.env.TotemFrame = false
end })
local M, core = w.M, w.core
M.formContentMaxWidth = narrow and 580 or 900
local gameplay = M.EnsureDB().gameplay
gameplay.enableCombatTimer = true
gameplay.combatTimerBrackets = true
assert(M.Open("gameplay") ~= false)
w:RunTimers()

local function Control(key)
    local _, widget = M.RuntimeControlCatalog.FindBySettingKey("gameplay." .. key, "gameplay")
    return assert(widget, "missing Combat Timer control: " .. key)
end

local anchor = Control("combatTimerAnchor")
local slider = Control("combatFontSize")
local format = Control("combatTimerBrackets")
local xOffset = Control("combatOffsetX")
local _, _, _, anchorX = anchor:GetPoint()
local _, _, _, sliderX, sliderY = slider:GetPoint()
local formatTitle = format._msuf2Title or format
local _, _, _, formatX, formatY = formatTitle:GetPoint()
local _, _, _, _, fieldY = format:GetPoint()
local _, _, _, _, offsetY = xOffset._msuf2Title:GetPoint()
assert((anchorX == sliderX) == narrow, "expected timer layout was not built")
assert(formatX == sliderX and formatY <= sliderY - slider:GetHeight() - 8,
    "Combat Timer format overlaps the size slider")
assert(offsetY <= fieldY - format:GetHeight() - 12, "Combat Timer format overlaps the offsets")
assert(format._msuf2ControlKind == "dropdown", "Combat Timer format is not a dropdown")

core.MSUF_ApplyGameplayVisuals()
local timerText
for _, frame in ipairs(w.world.widgets.frames) do
    if frame:GetName() == "MSUF_CombatTimerFrame" then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" then timerText = region break end
        end
        break
    end
end
assert(timerText, "Combat Timer text not created")
assert(format:GetValue() == "square" and timerText:GetText() == "[0:00]", "legacy enabled checkbox lost square brackets")

gameplay.combatTimerBrackets = false
core.MSUF_ApplyGameplayVisuals()
M.Refresh(M.cache.gameplay.ctx)
assert(format:GetValue() == "none" and timerText:GetText() == "0:00", "legacy disabled checkbox lost plain display")

local choices = {
    { "none", "1:23", "0:00" },
    { "square", "[1:23]", "[0:00]" },
    { "round", "(1:23)", "(0:00)" },
    { "curly", "{1:23}", "{0:00}" },
    { "angle", "<1:23>", "<0:00>" },
}
assert(#format.values == #choices, "dropdown lost a timer format")
for index, choice in ipairs(choices) do
    local item = format.values[index]
    local value, example, placeholder = unpack(choice)
    assert(item.value == value and item.text == example, "format example differs at " .. index)
    format._msuf2CommandAction.set(value)
    core.MSUF_ApplyGameplayVisuals()
    assert(gameplay.combatTimerBrackets == value and timerText:GetText() == placeholder, "format did not apply: " .. value)
end

gameplay.combatTimerPadMinutes = true
gameplay.combatTimerKeepLast = true
w.world:EnterCombat()
core.MSUF_Gameplay_TickCombatTimer("PLAYER_REGEN_DISABLED")
w.world.widgets:AdvanceTime(83)
core.MSUF_Gameplay_TickCombatTimer()
assert(timerText:GetText() == "<01:23>", "combat timer lost its format or minute padding")
w.world:LeaveCombat()
core.MSUF_Gameplay_TickCombatTimer("PLAYER_REGEN_ENABLED")
format._msuf2CommandAction.set("round")
core.MSUF_ApplyGameplayVisuals()
assert(timerText:GetText() == "(01:23)", "changing the format discarded the retained elapsed time")
format._msuf2CommandAction.set("none")
core.MSUF_ApplyGameplayVisuals()
assert(timerText:GetText() == "01:23", "return to plain format failed")

print("PASS Combat Timer format, compatibility and " .. (narrow and "stacked" or "wide") .. " layout: " .. flavor)

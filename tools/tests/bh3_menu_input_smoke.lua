local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, arg[2] or "Mainline")
world.env.MAX_BOSS_FRAMES = 5
local methods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetNumeric", "ClearFocus",
    "SetCursorPosition", "HighlightText", "EnableKeyboard", "SetValueStep" }) do
    methods[name] = methods[name] or function() end
end
methods.GetValue = function(self) return self.value or self.minimum or 0 end
world:Boot()
assert(not world:FirstFailure(), "client boot failed")
local env, M = world.env, world.core.MSUF2
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(600, 500)
local slider = M.Widgets.Slider(parent, "Fraction", 0, 1, 0.01, 400)
local function Enter(text)
    local edit = slider.editBox
    edit:GetScript("OnEditFocusGained")(edit)
    edit:SetText(text)
    edit:GetScript("OnEnterPressed")(edit)
    edit:GetScript("OnEditFocusLost")(edit)
end
slider:SetValue(0.5)
Enter("0,75")
assert(math.abs(slider:GetValue() - 0.75) < 0.001, "decimal comma dropped the user's value")
Enter("1,2,3")
assert(math.abs(slider:GetValue() - 0.75) < 0.001, "malformed decimal mutated the value")
Enter("0.25")
assert(math.abs(slider:GetValue() - 0.25) < 0.001, "decimal point regressed")
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua", "rb"))
local source = file:read("*a"); file:close()
assert(source:find("M.UsePercentInput(slider)", 1, true), "Range Fade did not wire the shared percent parser")
M.UsePercentInput(slider)
Enter("30")
assert(math.abs(slider:GetValue() - 0.3) < 0.001, "percent input 30 must mean 0.3")
Enter("40%")
assert(math.abs(slider:GetValue() - 0.4) < 0.001, "percent suffix failed")
local hides = 0
M.HideNavSearchIntro = function() hides = hides + 1 end
M.SetSearchIntroSeen(true, true)
assert(hides == 0, "persisting a just-shown search introduction dismissed it")
M.SetSearchIntroSeen(true)
assert(hides == 1, "explicit search introduction dismissal regressed")
print("numeric input and search introduction: PASS")

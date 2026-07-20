local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local classReads = 0
_G.issecretvalue = function() return false end
_G.UnitClass = function(unit)
    assert(unit == "party1", "class-color HP text resolved the wrong unit")
    classReads = classReads + 1
    return "Warrior", "WARRIOR"
end
_G.UnitIsPlayer = function(unit)
    assert(unit == "party1", "NPC name color resolved the wrong unit")
    return false
end
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
_G.MSUF_UFCore_GetClassBarColorFast = function(token)
    assert(token == "WARRIOR", "class-color HP text resolved the wrong class")
    return 0.17, 0.39, 0.83
end

local UF = { Clamp01 = function(value) return value end }
local MSUF = {
    UF = UF,
    UFText = {},
    Secrets = {
        SafeNumber = tonumber,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    },
}
_G.MSUF_NS = MSUF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local writes = 0
local hp = {}
function hp:SetTextColor(r, g, b, a)
    writes = writes + 1
    self.r, self.g, self.b, self.a = r, g, b, a
end

local frame = { unit = "party1", hpTextLeft = hp }
local runtime = {
    healthColorByClass = true,
    healthSlotCount = 1,
    healthSlots = { { fs = hp } },
    healthTextAlpha = 0.78,
}
MSUF.UFText.UpdateHealthTextColor(frame, runtime, "party1")
assert(hp.r == 0.17 and hp.g == 0.39 and hp.b == 0.83 and hp.a == 0.78,
    "runtime HP text did not use the configured class color and font opacity")
assert(classReads == 1 and writes == 1, "runtime class color did not use the cached text-color setter")

classReads = 0
frame.MSUFSpec = {
    text = { nameNpcClassColor = true },
    textColor = { r = 1, g = 1, b = 1, a = 0.66 },
}
local nr, ng, nb, na = MSUF.UFText.NameTextColor(frame, "party1")
assert(nr == 0.17 and ng == 0.39 and nb == 0.83 and na == 0.66,
    "NPC name text did not resolve its class color: "
      .. tostring(nr) .. "," .. tostring(ng) .. "," .. tostring(nb) .. "," .. tostring(na))
assert(classReads == 1, "NPC name class color repeated UnitClass")

local menu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
assert(menu:find('{ value = "CLASS", text = "Class Color"', 1, true),
    "HP Text Color dropdown is missing Class Color")

local healthElement = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua")
assert(not healthElement:find("healthColorByClass", 1, true),
    "static class-color HP text leaked into the UNIT_HEALTH value hotpath")

for _, path in ipairs({
    "MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua",
}) do
    assert(Read(path):find("healthColorByClass", 1, true), "preview is missing HP class-color support: " .. path)
end

print("hp_text_class_color_smoke: ok")

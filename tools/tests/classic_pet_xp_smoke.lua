-- Classic Pet XP element: event wiring, live values and preview state.
-- lua tools/tests/classic_pet_xp_smoke.lua <repo root>
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local function Check(value, message)
    if not value then error(message, 2) end
end
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local manifest = Read("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames.xml")
    Check(manifest:find('MSUF_UF_PetXP.lua', 1, true), flavor .. " must load Pet XP")
end
local searchRoot = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/"
local classicIndex = Read(searchRoot .. "MSUF_Menu2_Search_StaticIndex_Data_Classic.lua")
Check(classicIndex:find("\nuf_pet\tPet XP bar width\t", 1, true),
    "Classic Pet page must expose the XP width control")
Check(not classicIndex:find("\nuf_target\tPet XP bar width\t", 1, true),
    "other units must not expose the Pet XP width control")
local mainlineIndex = Read(searchRoot .. "MSUF_Menu2_Search_StaticIndex_Data.lua")
Check(not mainlineIndex:find("Pet XP bar width", 1, true),
    "Mainline search must not expose the Classic Pet XP width control")
local current, maximum, hasUI, canGainXP = 42, 100, true, true
local xpReads = 0
_G.GetPetExperience = function()
    xpReads = xpReads + 1
    return current, maximum
end
_G.HasPetUI = function() return hasUI, canGainXP end
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.MSUF_PixelLayoutRegion = function(region) return region end

local function Region(parent)
    local region = { parent = parent, visible = true }
    function region:EnableMouse() end
    function region:SetAllPoints() end
    function region:SetColorTexture() end
    function region:SetPoint(...) self.point = { ... } end
    function region:ClearAllPoints() end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetFrameLevel(level) self.level = level end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:SetStatusBarTexture(texture) self.texture = texture end
    function region:SetStatusBarColor() end
    function region:SetMinMaxValues(low, high)
        self.low, self.high = low, high
        self.rangeWrites = (self.rangeWrites or 0) + 1
    end
    function region:SetValue(value)
        self.value = value
        self.valueWrites = (self.valueWrites or 0) + 1
    end
    function region:CreateTexture() return Region(self) end
    function region:Show() self.visible = true; self.visibilityWrites = (self.visibilityWrites or 0) + 1 end
    function region:Hide() self.visible = false; self.visibilityWrites = (self.visibilityWrites or 0) + 1 end
    return region
end
_G.CreateFrame = function(_, _, parent) return Region(parent) end

local element
local ns = { UF = {
    RegisterElement = function(name, value)
        Check(name == "PetXPBar", "element name")
        element = value
    end,
} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_PetXP.lua"))(
    "MidnightSimpleUnitFrames", ns)
Check(element ~= nil, "Pet XP element was not registered")

local cfg = { enabled = true, width = 80, size = 8, anchor = "BOTTOM", x = 0, y = -5, layer = 7 }
local frame = { MSUFUnitKey = "pet", MSUFSpec = { status = { petXP = cfg, alpha = 1 } } }
Check(element.IsEnabled(frame) == true, "pet XP should enable on the pet frame")
Check(element.IsEnabled({ MSUFUnitKey = "target", MSUFSpec = frame.MSUFSpec }) == false,
    "pet XP must not attach to target")
Check(element.GetEvents(frame)[1] == "UNIT_LEVEL", "pet level event missing")
Check(element.GetUnitlessEvents(frame)[1] == "UNIT_PET_EXPERIENCE", "XP event missing")

element.Create(frame, frame.MSUFSpec)
local holder = frame.petXPBar
Check(holder and holder.width == 80 and holder.height == 8, "default geometry")
Check(holder.point and holder.point[1] == "BOTTOM" and holder.point[4] == 0
    and holder.point[5] == -5, "default anchor")
element.Update(frame)
Check(holder.visible and holder.fill.high == 100 and holder.fill.value == 42,
    "live XP was not drawn")
local writes = holder.fill.valueWrites
local visibilityWrites = holder.visibilityWrites
element.Update(frame)
Check(holder.fill.valueWrites == writes, "unchanged XP should not rewrite fill")
Check(holder.visibilityWrites == visibilityWrites, "unchanged XP should not toggle visibility")

maximum = 0
element.Update(frame)
Check(holder.visible == false, "max level pet should hide the XP bar")
maximum, hasUI = 100, false
element.Update(frame)
Check(holder.visible == false, "missing pet UI should hide the XP bar")
hasUI, current = true, { secret = true }
element.Update(frame)
Check(holder.visible == false, "secret XP should be treated as unknown")
frame.MSUFSpec.status.testMode = true
local reads = xpReads
element.Update(frame)
Check(holder.visible and holder.fill.high == 100 and holder.fill.value == 68,
    "status preview should show sample XP")
Check(xpReads == reads, "preview must not query live pet XP")
Check(#element.GetEvents(frame) == 0 and #element.GetUnitlessEvents(frame) == 0,
    "status preview must not subscribe to pet events")
element.Disable(frame)
Check(holder.visible == false, "disabling must hide the XP bar")
print("classic_pet_xp_smoke: ok")

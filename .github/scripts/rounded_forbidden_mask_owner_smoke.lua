local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local rounded = Read("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
assert(not rounded:find("_msufRoundedMaskOwners", 1, true),
    "native forbidden regions must not retain a mutable rounded owner registry")

local prepareStart = assert(rounded:find("local function PrepareFrozenDispelOverlayMask", 1, true),
    "frozen native dispel-mask preparation missing")
local prepareEnd = assert(rounded:find("local function ApplyDispelOverlayMask", prepareStart, true),
    "could not find end of frozen native dispel-mask preparation")
local prepareSource = rounded:sub(prepareStart, prepareEnd - 1)
assert(not prepareSource:find("ClearAllPoints", 1, true),
    "fresh native dispel masks must not perform redundant point clearing")
assert(not prepareSource:find("MaskedTextures", 1, true),
    "frozen native dispel masks entered the mutable rounded mask registry")
local setTexture = assert(prepareSource:find("mask:SetTexture", 1, true),
    "frozen native dispel mask texture setup missing")
local setPoints = assert(prepareSource:find("mask:SetAllPoints", 1, true),
    "frozen native dispel mask layout missing")
local addMask = assert(prepareSource:find("region:AddMaskTexture(mask)", 1, true),
    "frozen native dispel mask binding missing")
assert(setTexture < setPoints and setPoints < addMask,
    "native dispel mask is not fully configured before binding")

local compile = loadstring or load
local harness = [[
local calls = {}
local roundedMaskPath = "rounded-mask"
local anchor = {}
local function IsCombatLocked() return false end
local function DeferApply() error("unexpected defer") end
local function FrameIsGroup() return true end
local function RoundedGroupFramesEnabled() return true end
local function RoundedUnitFramesEnabled() return true end
local function RoundedPowerBarsEnabled() return false end
local function PowerIsEmbedded() return false end
local function CanCreateRoundedRegion() return true end
local function UpdateRoundedMediaState() calls[#calls + 1] = "media" end
local function SE_SnapOff(mask) mask:SnapOff() end
local function ApplyRoundedMediaSlice(mask, path) mask:Slice(path) end
]] .. prepareSource .. [[
return PrepareFrozenDispelOverlayMask, calls, anchor
]]
local prepare, calls, anchor = assert(compile(harness))()
local sealed = false
local mask = {
    SnapOff = function() assert(not sealed); calls[#calls + 1] = "snap" end,
    SetTexture = function(_, path) assert(not sealed and path == "rounded-mask"); calls[#calls + 1] = "texture" end,
    SetAllPoints = function(_, target) assert(not sealed and target == anchor); calls[#calls + 1] = "points" end,
    Slice = function(_, path) assert(not sealed and path == "rounded-mask"); calls[#calls + 1] = "slice" end,
    ClearAllPoints = function() assert(not sealed, "forbidden ClearAllPoints") end,
}
local owner = {
    CreateMaskTexture = function()
        calls[#calls + 1] = "create"
        return mask
    end,
}
local region = {
    AddMaskTexture = function(_, value)
        assert(value == mask)
        calls[#calls + 1] = "bind"
    end,
}
local frame = { health = anchor }
assert(prepare(frame, region, owner) == true, "frozen native dispel mask preparation failed")
assert(table.concat(calls, ",") == "media,create,snap,texture,points,slice,bind",
    "frozen native dispel mask setup order changed")
sealed = true
assert(not pcall(mask.ClearAllPoints),
    "test mask did not model the post-AddDispelTypeTexture forbidden state")

local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local overlayBranch = assert(auras:match(
    'if sensor%.visual == "overlay" then(.-)elseif sensor%.visual == "purge" then'
), "native dispel overlay branch missing")
local prepareCall = assert(overlayBranch:find(
    "PrepareRoundedDispelOverlayRegion(parentFrame, region, button)", 1, true),
    "native dispel overlay is not prepared with its explicit owner")
local blizzardHandoff = assert(overlayBranch:find(
    "button:AddDispelTypeTexture(region, GetSensorOverlayOptions())", 1, true),
    "native dispel overlay Blizzard handoff missing")
assert(prepareCall < blizzardHandoff,
    "native dispel overlay is masked after Blizzard makes it forbidden")
assert(not auras:find("RegisterRoundedDispelOverlayRegion", 1, true),
    "legacy post-handoff native dispel registration remains")
assert(auras:find("RegisterRoundedDispelOverlayPreviewRegion(frame, region)", 1, true),
    "MSUF-owned dispel overlay preview lost its mutable rounded registration")
assert(auras:find("function A3.RefreshRoundedDispelOverlayMasks()", 1, true),
    "rounded setting changes cannot recreate frozen native dispel masks")
assert(auras:find("A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1", 1, true),
    "native dispel-mask recreation does not advance the Auras3 visual generation")
local modulesApplied = assert(rounded:match(
    'ExportPublic%("MSUF_RoundedUF_OnModulesApplied", function%b()%s*(.-)%s*end%)'
), "rounded module-apply callback missing")
assert(modulesApplied:find("RefreshFrozenDispelOverlayMasks()", 1, true),
    "profile/module applies do not recreate frozen native dispel masks")
local applyRounded = assert(rounded:match(
    "local function ApplyRoundedUnitframes%b()%s*(.-)%s*end%s*ExportPublic"
), "rounded settings apply function missing")
assert(applyRounded:find("RefreshFrozenDispelOverlayMasks()", 1, true),
    "direct rounded setting changes do not recreate frozen native dispel masks")

io.write("rounded_forbidden_mask_owner_smoke: ok\n")

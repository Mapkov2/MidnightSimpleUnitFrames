local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local rounded = Read("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua")
local resolve = assert(rounded:match(
    "local function ResolveMaskOwner%b()%s*(.-)%s*local function EnsureMaskForAnchor"
), "rounded mask-owner resolver missing")
local registeredLookup = assert(resolve:find("local owners = f and f._msufRoundedMaskOwners", 1, true),
    "rounded masks do not consult the registered native texture owner")
local forbiddenGetter = assert(resolve:find("tex:GetParent()", 1, true),
    "ordinary texture-parent fallback missing")
assert(registeredLookup < forbiddenGetter,
    "forbidden native display regions are queried before their registered owner")
assert(resolve:find("if not owner then", registeredLookup, true),
    "texture-parent fallback is not guarded by the registered owner")

local resolverStart = assert(rounded:find("local function ResolveMaskOwner", 1, true),
    "could not find rounded mask-owner resolver")
local resolverEnd = assert(rounded:find("local function EnsureMaskForAnchor", resolverStart, true),
    "could not find end of rounded mask-owner resolver")
local resolverSource = rounded:sub(resolverStart, resolverEnd - 1)
local compile = loadstring or load
local resolveOwner = assert(compile(resolverSource .. "\nreturn ResolveMaskOwner"))()
local forbiddenTexture = {
    GetParent = function()
        error("forbidden GetParent must not run for registered native regions")
    end,
}
local registeredOwner = { CreateMaskTexture = function() end }
assert(resolveOwner({ _msufRoundedMaskOwners = { [forbiddenTexture] = registeredOwner } }, forbiddenTexture, nil)
        == registeredOwner,
    "registered native texture owner did not bypass forbidden GetParent")
local ordinaryOwner = { CreateMaskTexture = function() end }
local ordinaryTexture = { GetParent = function() return ordinaryOwner end }
assert(resolveOwner({}, ordinaryTexture, nil) == ordinaryOwner,
    "ordinary texture-parent fallback no longer resolves the real owner")

local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local register = assert(auras:match(
    "local function RegisterRoundedDispelOverlayRegion%b()%s*(.-)%s*local function PrepareDispelSensorButton"
), "rounded dispel-overlay registration missing")
assert(register:find('setmetatable({}, { __mode = "k" })', 1, true),
    "native texture owner registry must not retain discarded regions")
local ownerStore = assert(register:find("owners[region] = owner", 1, true),
    "native dispel texture owner is not retained")
local callback = assert(register:find("callback(parentFrame, region)", 1, true),
    "rounded dispel callback missing")
assert(ownerStore < callback,
    "native texture owner must be available before RoundedFrames applies the mask")
assert(auras:find("RegisterRoundedDispelOverlayRegion(parentFrame, region, button)", 1, true),
    "dispel overlay registration does not pass its already-known AuraButton owner")
assert(auras:find("RegisterRoundedDispelOverlayRegion(frame, region, host)", 1, true),
    "dispel overlay preview does not pass its already-known host owner")
local registrations = 0
for arguments in auras:gmatch("RegisterRoundedDispelOverlayRegion(%b())") do
    local _, commaCount = arguments:gsub(",", "")
    assert(commaCount == 2, "rounded dispel overlay registration omitted its explicit owner")
    registrations = registrations + 1
end
assert(registrations == 3, "unexpected rounded dispel overlay registration call count")
assert(not register:find("GetParent", 1, true),
    "dispel overlay registration reintroduced a forbidden parent query")

io.write("rounded_forbidden_mask_owner_smoke: ok\n")

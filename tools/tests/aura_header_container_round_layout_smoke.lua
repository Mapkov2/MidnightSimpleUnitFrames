-- aura_header_container_round_layout_smoke.lua
-- SecureGroupHeader creates one AuraContainer per party/raid child inside the
-- restricted environment, and Auras3 adopts it as the GroupSlots owner. Every
-- other native aura owner gets native pixel rounding in
-- CreateNativeAuraContainer. On WoW Forever (12.1.5 engine) the adopted header
-- owner gets the same root-only rounding through the real Kernel helper. This
-- smoke proves that, that a client without SetRoundLayoutToNearestPixel adopts
-- it unchanged, that a protected owner in combat is left alone, that only the
-- primary GroupSlots root adopts the header container, and that Retail (and a
-- harness without MSUF.Client) keeps adopting it without rounding.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- Use the shipped Kernel helper, not a copy of its rules. Reason: the helper
-- is one function, cut at its own `end` by the shared slicer.
local UTIL = "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
local helperBody = Slice.Function(util, "local function MSUF_SetRoundLayoutToNearestPixel", UTIL)
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.MSUF_SetRoundLayoutToNearestPixel = assert(loadstring(helperBody
    .. "\nreturn MSUF_SetRoundLayoutToNearestPixel", "round-layout helper"))()

local function NewContainer(withRounding, protected)
    local container = { rounding = {}, shown = false }
    if withRounding then
        function container:SetRoundLayoutToNearestPixel(enabled)
            self.rounding[#self.rounding + 1] = enabled
        end
    end
    function container:IsProtected() return protected == true end
    function container:GetParent() return self.parent end
    function container:SetAllPoints() end
    function container:SetFrameLevel() end
    function container:SetAlpha() end
    function container:Show() self.shown = true end
    function container:Hide() self.shown = false end
    return container
end

local function AutoTable()
    return setmetatable({}, { __index = function() return function() end end })
end

-- Loads Containers.lua into a fresh addon namespace. The client fact is read
-- once at file load, so each client needs its own load.
local function LoadContainers(client)
    local created = {}
    local dependencies = setmetatable({}, {
        __index = function(self, key)
            local value = AutoTable()
            rawset(self, key, value)
            return value
        end,
    })
    local platform = dependencies.Platform
    rawset(platform, "AURA_CONTAINER_ADDON", "Blizzard_AuraContainer")
    rawset(platform, "EnsureBlizzardAuraContainerLoaded", function() return true end)
    rawset(platform, "CreateFrame", function(frameType, _, parent)
        Check(frameType == "AuraContainer", "unexpected CreateFrame type " .. tostring(frameType))
        local container = NewContainer(true, false)
        container.parent = parent
        created[#created + 1] = container
        return container
    end)
    rawset(dependencies.NativeContract, "ValidateNativeAuraContainerContract", function() return true end)
    -- The factory attaches sensor helpers to the shared Appearance DS table.
    rawset(dependencies.Appearance, "DS", {})

    local MSUF = { Client = client }
    local A3 = { SpellIndicators = AutoTable() }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Containers.lua"))(
        "MidnightSimpleUnitFrames", MSUF)
    local factory = MSUF.Auras3RuntimeFactories and MSUF.Auras3RuntimeFactories.Containers
    Check(type(factory) == "function", "Containers factory was not registered")
    local Containers = factory("MidnightSimpleUnitFrames", MSUF, A3, {}, function() end, dependencies)
    Containers.Bind({ RegisterNativeContainer = function() return true end })
    return Containers, created
end

local function NewUnitButton(headerContainer)
    local frame = { AuraContainer = headerContainer }
    headerContainer.parent = frame
    function frame:GetFrameLevel() return 5 end
    return frame
end

local function Adopt(Containers, unitButton, rootKey)
    local auraRoot = {}
    return Containers.CreateNativeGroupSlots(auraRoot,
        { rootKey = rootKey or "GroupSlots", unit = "party1" }, unitButton)
end

do
    local Forever, created = LoadContainers({ Family = "Mainline", IsRetail = true, IsForever = true })

    -- The header-born owner is adopted and rounded exactly once.
    local headerContainer = NewContainer(true, false)
    local unitButton = NewUnitButton(headerContainer)
    Check(Adopt(Forever, unitButton) == headerContainer, "Forever GroupSlots did not adopt the header container")
    Check(#headerContainer.rounding == 1 and headerContainer.rounding[1] == true,
        "Forever header container was not rounded on adoption")
    Check(headerContainer._msufA3HeaderContainerConsumed == true, "header container was not marked consumed")
    Check(#created == 0, "adoption created a replacement container")

    -- A consumed header owner is never adopted (or rounded) again; the
    -- structural replacement is a fresh container rounded by its creation path.
    local replacement = Adopt(Forever, unitButton)
    Check(replacement ~= headerContainer and replacement == created[1],
        "consumed header container was adopted twice")
    Check(#headerContainer.rounding == 1, "consumed header container was rounded again")
    Check(#replacement.rounding == 1 and replacement.rounding[1] == true,
        "replacement container lost its creation-time rounding")

    -- Only the primary GroupSlots root adopts the header owner.
    local secondaryHeader = NewContainer(true, false)
    local secondaryButton = NewUnitButton(secondaryHeader)
    local secondary = Adopt(Forever, secondaryButton, "GroupSlotsSecondary")
    Check(secondary ~= secondaryHeader and #secondaryHeader.rounding == 0
        and secondaryHeader._msufA3HeaderContainerConsumed == nil,
        "a secondary root adopted or rounded the header container")

    -- No native rounding API: adoption is unchanged and nothing is called.
    local plainHeader = NewContainer(false, false)
    local plainButton = NewUnitButton(plainHeader)
    Check(Adopt(Forever, plainButton) == plainHeader, "GroupSlots without the rounding API did not adopt the header container")
    Check(plainHeader._msufA3HeaderContainerConsumed == true, "header container without the rounding API was not consumed")

    -- Combat: the helper refuses the protected function on a protected owner,
    -- and adoption still completes.
    inCombat = true
    local protectedHeader = NewContainer(true, true)
    local protectedButton = NewUnitButton(protectedHeader)
    Check(Adopt(Forever, protectedButton) == protectedHeader, "combat adoption of a protected header container failed")
    Check(#protectedHeader.rounding == 0, "protected header container was rounded under combat lockdown")
    local combatHeader = NewContainer(true, false)
    local combatButton = NewUnitButton(combatHeader)
    Check(Adopt(Forever, combatButton) == combatHeader and #combatHeader.rounding == 1,
        "unprotected header container was not rounded in combat")
    inCombat = false
end

-- Retail (12.1.5 API present) and a harness without MSUF.Client keep the old
-- behaviour: the header owner is adopted without rounding, and containers MSUF
-- creates itself are still rounded by the creation path.
for _, case in ipairs({
    { label = "Retail", client = { Family = "Mainline", IsRetail = true, IsForever = false } },
    { label = "no-Client", client = nil },
}) do
    local Containers, created = LoadContainers(case.client)
    local headerContainer = NewContainer(true, false)
    local unitButton = NewUnitButton(headerContainer)
    Check(Adopt(Containers, unitButton) == headerContainer,
        case.label .. " GroupSlots did not adopt the header container")
    Check(headerContainer._msufA3HeaderContainerConsumed == true,
        case.label .. " header container was not marked consumed")
    Check(#headerContainer.rounding == 0, case.label .. " header container was rounded on adoption")
    local replacement = Adopt(Containers, unitButton)
    Check(replacement == created[1] and #replacement.rounding == 1,
        case.label .. " replacement container lost its creation-time rounding")
end

print("aura_header_container_round_layout_smoke: ok")

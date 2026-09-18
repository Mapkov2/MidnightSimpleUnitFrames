--- Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua
--- WoW Forever character names: show both parts, the first name or the surname.
---
--- Forever characters carry a surname. Blizzard's Camelot NameUtil reads it from
--- UnitName's second return and joins both parts for display; with regional
--- unique names the first return can already hold both parts. The Fonts page
--- (Name Shortening) lets the player choose what MSUF shows on every unit and
--- group frame:
---   general.characterNameParts = nil ("FULL") | "FIRST" | "SURNAME"
---
--- The choice is applied where names are read for display, through the unit text
--- module's display-name resolver. The nickname integration uses the same single
--- slot, so on Forever this file owns the slot and asks the nickname resolver
--- first: a nickname always replaces the whole name.
---
--- Secret names cannot be searched, compared or tested for emptiness. A secret
--- surname is joined with C_StringUtil.WrapString, which adds the separator only
--- to a non-empty surname; where a part cannot be proven to exist, the whole
--- name stays, never an empty one. The separator is Blizzard's constant and is
--- never assumed.
---
--- Every other client returns at once: no surnames, no resolver, no cost.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local Client = MSUF.Client
if not (Client and Client.HasCharacterSurnames == true) then return end
local Text = MSUF.UFText
if not (Text and type(Text.SetDisplayNameResolver) == "function" and type(Text.UnitName) == "function") then return end

local UnitName = Text.UnitName
local UnitIsPlayer = Text.UnitIsPlayer or _G.UnitIsPlayer
local ReadUnitIsPlayerCached = MSUF.UF and MSUF.UF.ReadUnitIsPlayerCached
local issecretvalue = _G.issecretvalue
local stringUtil = _G.C_StringUtil
local WrapString = type(stringUtil) == "table" and stringUtil.WrapString or nil
local find, sub, type = string.find, string.sub, type

local Names = {}
MSUF.CharacterNames = Names

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Blizzard's constant; its value is not part of the UI source.
local separator
local function Separator()
    if separator then return separator end
    local constants = _G.Constants
    local names = type(constants) == "table" and constants.CharacterNameSeparatorConsts
    local value = type(names) == "table" and names.CHARACTERNAME_SURNAME_SEPARATOR
    if type(value) == "string" and value ~= "" then separator = value end
    return separator
end

local function Mode()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    local mode = type(general) == "table" and general.characterNameParts
    if mode == "FIRST" or mode == "SURNAME" then return mode end
    return "FULL"
end

-- A realm's naming policy does not change during a session. Only a confirmed
-- "on" is kept, so an answer that came too early is asked again.
local regionalUniqueNames = false
local function RegionalUniqueNames()
    if regionalUniqueNames then return true end
    local enabled = _G.RegionalUniqueNamesEnabled
    if type(enabled) == "function" and enabled() == true then regionalUniqueNames = true end
    return regionalUniqueNames
end

local function IsPlayerUnit(unit, frame)
    if frame and ReadUnitIsPlayerCached then
        -- The engine read this for the frame's identity already; reuse it.
        local isPlayer, known = ReadUnitIsPlayerCached(frame, unit)
        return known == true and isPlayer == true
    end
    local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
    return not IsSecret(isPlayer) and isPlayer == true
end

-- With regional unique names the first return holds "first<separator>surname".
-- Only player names are split: an NPC name may contain the separator by chance
-- (the beta's separator is a space). The string is searched first, so a name
-- without the separator costs no unit API call.
local function SplitMergedName(unit, frame, name, sep)
    local from, to = find(name, sep, 2, true)
    if not from or to >= #name then return name end
    if not (RegionalUniqueNames() and IsPlayerUnit(unit, frame)) then return name end
    return sub(name, 1, from - 1), sub(name, to + 1)
end

local function ComposeSecretName(mode, first, second, secondIsSecret)
    if mode == "FIRST" then return first end
    local sep = Separator()
    if not secondIsSecret then
        if type(second) ~= "string" or second == "" then return first end
        if mode == "SURNAME" then return second end
        return sep and (first .. sep .. second) or first
    end
    -- The surname may be empty, which cannot be tested. "Surname only" therefore
    -- keeps the whole name here instead of risking an empty one.
    if not (sep and WrapString) then return first end
    return first .. WrapString(second, sep)
end

--- first, second: the two returns of UnitName(unit). frame: the frame the name
--- is read for, when the caller has one.
function Names.Compose(unit, first, second, frame)
    local mode = Mode()
    local secondIsSecret = IsSecret(second)
    if not secondIsSecret and (second == nil or second == "") then
        -- No separate surname: the usual case, and the whole job for "Full name".
        if mode == "FULL" or IsSecret(first) or type(first) ~= "string" then return first end
        local sep = Separator()
        if not sep then return first end
        local firstName, surname = SplitMergedName(unit, frame, first, sep)
        if not surname then return first end
        return mode == "FIRST" and firstName or surname
    end
    if secondIsSecret or IsSecret(first) then
        return ComposeSecretName(mode, first, second, secondIsSecret)
    end
    if type(first) ~= "string" or first == "" then return first end
    if type(second) ~= "string" then return first end

    -- A separate surname (Blizzard's Camelot NameUtil joins both for display).
    local sep = Separator()
    local firstName = first
    if sep and find(first, sep, 2, true) then
        -- Never print the surname twice should the first return hold it too.
        local tail = sep .. second
        if #first > #tail and sub(first, -#tail) == tail then firstName = sub(first, 1, #first - #tail) end
    end
    if mode == "FIRST" then return firstName end
    if mode == "SURNAME" then return second end
    return sep and (firstName .. sep .. second) or firstName
end

local Compose = Names.Compose
local nicknameResolver

local function ResolveDisplayName(unit, frame)
    local first, second = UnitName(unit)
    if nicknameResolver then
        local shown = nicknameResolver(unit, frame)
        -- The nickname resolver hands a secret or unknown name back untouched.
        if not IsSecret(shown) and not IsSecret(first) and shown ~= first then return shown end
    end
    return Compose(unit, first, second, frame)
end

-- One resolver slot, two users: keep this file's resolver installed and route
-- the nickname integration's resolver through it.
local InstallResolver = Text.SetDisplayNameResolver
function Text.SetDisplayNameResolver(resolver)
    nicknameResolver = type(resolver) == "function" and resolver or nil
end
InstallResolver(ResolveDisplayName)

local function RefreshFrameName(frame, _, runtime)
    local active = frame and frame._msufActiveElements
    if not active then return end
    if active.NameText == true and runtime.UpdateName then
        runtime.UpdateName(frame, "MSUF_CHARACTER_NAMES", frame.MSUFUnitKey)
    end
    if active.Text == true and runtime.UpdateInline then
        runtime.UpdateInline(frame, "MSUF_CHARACTER_NAMES", nil)
    end
end

--- Re-read every displayed name after the option changed. The menu is closed to
--- changes in combat, so this only runs out of combat.
function Names.Refresh()
    local inCombat = _G.InCombatLockdown
    if type(inCombat) == "function" and inCombat() then return false end
    local UF, runtime, GF = MSUF.UF, MSUF.UFTextRuntime, MSUF.GF
    if UF and type(UF.ForEachFrame) == "function" and runtime then UF.ForEachFrame(RefreshFrameName, runtime) end
    if GF and type(GF.RefreshGroupNames) == "function" then GF.RefreshGroupNames() end
    return true
end

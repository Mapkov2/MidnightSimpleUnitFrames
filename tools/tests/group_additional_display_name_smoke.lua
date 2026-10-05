-- group_additional_display_name_smoke.lua <repoRoot>
--
-- The extra group blocks (GroupFrames/MSUF_GroupFrames_Additional.lua: healer
-- mana rows, party targets, pets, allied bosses) paint names outside the unit
-- frame engine. Engine frames read names through one display-name resolver
-- slot (MSUF_UF_Text_Runtime.lua Text.SetDisplayNameResolver), which WoW
-- Forever's character names and the nickname providers fill. The blocks read
-- raw UnitName, so with a resolver installed the healer mana row showed a
-- different name than the same member's party frame. Reading the resolver on
-- bind was not enough: a name refresh (the nickname providers registering or
-- notifying, the Forever character-name option) repaints the group frames
-- through GF.RefreshGroupNames and left the blocks on the old name until the
-- next name event.
--
-- Pins, on the real load graph (tools/tests/group_header_world.lua):
--   * without a resolver a healer mana row shows UnitName;
--   * the nickname provider API (MSUF.API.Nicknames): registering, a full
--     NotifyChanged, a per-unit NotifyChanged and unregistering repaint the
--     healer mana row with nothing else run;
--   * UNIT_NAME_UPDATE on a row repaints through the resolver;
--   * WoW Forever: switching Character Names from full to first name and the
--     option's own refresh (CharacterNames.Refresh) repaint the mana row.
-- The secure blocks (party targets, pets, allied bosses) need the XML
-- template this harness does not build; group_additional_runtime_smoke pins
-- their names on the same refresh.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function Holder(h, name)
    for _, frame in ipairs(h.widgets.frames) do
        if frame.frameName == name then return frame end
    end
    return nil
end

local function ManaRowNames(h)
    local holder = Holder(h, "MSUF_GroupAdditional_HealerMana")
    local names = {}
    if not holder then return names end
    for _, row in ipairs({ holder:GetChildren() }) do
        if row:IsShown() and row.name then names[#names + 1] = tostring(row.name:GetText()) end
    end
    return names
end

local function Boot(flavor, beforeBoot)
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "DAMAGER" end
        hh.env.UnitIsPlayer = function() return true end
        if beforeBoot then beforeBoot(hh) end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local party = GF.GetConf("party")
    party.enabled = true
    party.showPlayer = true
    party.healerManaEnabled = true
    h:SetRoster({ "player", "party1", "party2" })
    GF.RefreshHeaderLayout()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    GF.RefreshAdditionalGroups(true)
    return h
end

local function Expect(h, label, mana)
    local names = ManaRowNames(h)
    Check(#names == 1 and names[1] == mana,
        ("%s %s: healer mana rows show [%s], expected [%s]"):format(h.flavor, label, table.concat(names, ","), mana))
end

local function RunNicknames(flavor)
    local h = Boot(flavor)
    Expect(h, "without a resolver", "Name-party1")

    -- The nickname provider API, the way a nickname addon uses it.
    local api = assert(h.core.API and h.core.API.Nicknames, flavor .. ": no nickname provider API")
    local nick = "Nick"
    Check(api.RegisterProvider("MSUFDisplayNameSmoke", function(_, nativeName)
        return nick .. "-" .. tostring(nativeName)
    end) == true, flavor .. ": the nickname provider did not register")
    Expect(h, "after a provider registered", "Nick-Name-party1")
    nick = "Other"
    api.NotifyChanged("MSUFDisplayNameSmoke")
    Expect(h, "after a full provider notification", "Other-Name-party1")
    nick = "Unit"
    api.NotifyChanged("MSUFDisplayNameSmoke", "party1")
    Expect(h, "after a party1 provider notification", "Unit-Name-party1")

    -- UNIT_NAME_UPDATE on the row repaints through the resolver too (the
    -- provider API caches its answer until the next notification).
    local holder = Holder(h, "MSUF_GroupAdditional_HealerMana")
    for _, row in ipairs({ holder:GetChildren() }) do
        if row:IsShown() and row.unit then
            row.name:SetText("stale")
            row:GetScript("OnEvent")(row, "UNIT_NAME_UPDATE", row.unit)
        end
    end
    Expect(h, "after UNIT_NAME_UPDATE", "Unit-Name-party1")
    api.UnregisterProvider("MSUFDisplayNameSmoke")
    Expect(h, "after the provider unregistered", "Name-party1")
end

-- WoW Forever character names: Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua.
local function RunForeverCharacterNames()
    local h = Boot("Forever", function(hh)
        hh.env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
        hh.env.UnitName = function() return "Arthas Menethil", nil end
        hh.env.RegionalUniqueNamesEnabled = function() return true end
    end)
    local names = assert(h.core.CharacterNames, "Forever: no CharacterNames")
    h.env.MSUF_DB.general.characterNameParts = "FULL"
    names.Refresh()
    Expect(h, "Character Names full", "Arthas Menethil")
    h.env.MSUF_DB.general.characterNameParts = "FIRST"
    Check(names.Refresh() == true, "Forever: CharacterNames.Refresh refused out of combat")
    Expect(h, "Character Names first name", "Arthas")
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do RunNicknames(flavor) end
RunForeverCharacterNames()

if failures > 0 then error(("group additional display name smoke: %d failure(s)"):format(failures)) end
print("group additional display name smoke: ok (Mainline, Vanilla, Forever)")

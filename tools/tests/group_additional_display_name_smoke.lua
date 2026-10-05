-- group_additional_display_name_smoke.lua <repoRoot>
--
-- The extra group blocks (GroupFrames/MSUF_GroupFrames_Additional.lua: healer
-- mana rows, party targets, pets, allied bosses) paint names outside the unit
-- frame engine. Engine frames read names through one display-name resolver
-- slot (MSUF_UF_Text_Runtime.lua Text.SetDisplayNameResolver), which WoW
-- Forever's character names and the nickname providers fill. The blocks read
-- raw UnitName, so with a resolver installed the healer mana row showed a
-- different name than the same member's party frame.
--
-- Pins, on the real load graph (tools/tests/group_header_world.lua): with a
-- resolver in the engine's slot, a healer mana row shows the resolved name on
-- bind and on UNIT_NAME_UPDATE; without one it shows UnitName.
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

local function ManaHolder(h)
    for _, frame in ipairs(h.widgets.frames) do
        if frame.frameName == "MSUF_GroupAdditional_HealerMana" then return frame end
    end
    return nil
end

local function ManaRowNames(h)
    local holder = ManaHolder(h)
    local names = {}
    if not holder then return names end
    for _, row in ipairs({ holder:GetChildren() }) do
        if row:IsShown() and row.name then names[#names + 1] = tostring(row.name:GetText()) end
    end
    return names
end

local function Run(flavor)
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "DAMAGER" end
    end })
    local GF, core = h.GF, h.core
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
    local names = ManaRowNames(h)
    Check(#names == 1 and names[1] == "Name-party1",
        ("%s without a resolver: healer mana rows show [%s], expected [Name-party1]"):format(flavor, table.concat(names, ",")))

    -- A resolver in the engine's slot, the way the nickname providers install one.
    core.UFText.SetDisplayNameResolver(function(unit) return "Nick-" .. tostring(unit) end)
    GF.RefreshAdditionalGroups(true)
    names = ManaRowNames(h)
    Check(#names == 1 and names[1] == "Nick-party1",
        ("%s with a resolver: healer mana rows show [%s], expected [Nick-party1]"):format(flavor, table.concat(names, ",")))

    -- UNIT_NAME_UPDATE on the row repaints through the resolver too.
    core.UFText.SetDisplayNameResolver(function(unit) return "Renamed-" .. tostring(unit) end)
    local holder = ManaHolder(h)
    for _, row in ipairs({ holder:GetChildren() }) do
        if row:IsShown() and row.unit then
            row:GetScript("OnEvent")(row, "UNIT_NAME_UPDATE", row.unit)
        end
    end
    names = ManaRowNames(h)
    Check(#names == 1 and names[1] == "Renamed-party1",
        ("%s UNIT_NAME_UPDATE: healer mana rows show [%s], expected [Renamed-party1]"):format(flavor, table.concat(names, ",")))
    core.UFText.SetDisplayNameResolver(nil)
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do Run(flavor) end

if failures > 0 then error(("group additional display name smoke: %d failure(s)"):format(failures)) end
print("group additional display name smoke: ok (Mainline, Vanilla)")

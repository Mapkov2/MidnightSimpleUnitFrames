-- group_housing_hide_smoke.lua <repoRoot>
--
-- Group Layout "Hide in Housing" (party/raid conf.hideInHousing, off by
-- default) hides that scope's block while the player is inside a house or on a
-- plot. The UFCore refactor removed its only consumer, so the option stored a
-- value nothing read and the frames stayed on screen.
--
-- Client facts (Blizzard mirror, live and forever): C_Housing.IsInsideHouseOrPlot
-- is read by Blizzard_Game/Mainline/EventImplementation.lua; walking onto or off
-- a plot raises HOUSE_PLOT_ENTERED / HOUSE_PLOT_EXITED without a zone change
-- (Blizzard_HousingControls.lua). Classic clients have no C_Housing.
--
-- Pins, on the real group runtime and the SecureGroupHeader emulator
-- (tools/tests/group_header_world.lua), with C_Housing stubbed:
--   * with the option on, entering a plot hides the party block and its group
--     border, leaving brings both back;
--   * with the option off nothing hides and no housing event is registered (a
--     default profile pays nothing); switching it on or off while inside
--     applies through the option's own visual refresh;
--   * entering in combat writes nothing protected and hides the block once
--     combat ends;
--   * logging in inside a house starts hidden; the raid scope follows its own
--     option;
--   * the option covers everything the scope's settings draw: the Priority
--     Frames (no settings of their own here: GF.GetConf("priority") is the
--     Party conf and the strip follows the live base scope's conf) and the
--     scope's extra blocks (healer mana, party targets: keys of the same conf)
--     hide and come back with the block, on plot events and on the toggle;
--     in combat the unprotected mana rows hide at once, the protected
--     Priority strip and target buttons wait for the end of combat;
--   * a client without IsInsideHouseOrPlot hides nothing and registers no
--     housing event (the harness answers every unknown C_* namespace with a
--     callable stub, so the Vanilla run installs an empty C_Housing).
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

local function Visible(frame)
    while frame do
        if not frame.shown then return false end
        frame = frame.parent
    end
    return true
end

local function UnitShown(h, unit)
    local frame = h.GF.FrameForUnit(unit)
    return frame ~= nil and Visible(frame)
end

local function BorderShown(h, key)
    local anchor = h.GF.anchors and h.GF.anchors[key]
    local edges = anchor and anchor.MSUFGFGroupBorder
    if not edges then return false end
    for _, edge in pairs(edges) do
        if edge.shown and Visible(anchor) then return true end
    end
    return false
end

local function Boot(flavor, housing)
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.C_Housing = housing and { IsInsideHouseOrPlot = function() return housing.inside == true end } or {}
    end })
    local GF = h.GF
    GF.EnsureDB()
    local party = GF.GetConf("party")
    party.enabled = true
    party.showPlayer = true
    party.groupBorderEnabled = true
    return h, party
end

local function HousingEventsRegistered(h)
    for _, frame in ipairs(h.widgets.frames) do
        local events = frame.events
        if events and (events.HOUSE_PLOT_ENTERED or events.HOUSE_PLOT_EXITED) then return true end
    end
    return false
end

local function Party(h)
    h:SetRoster({ "player", "party1" })
    h.GF.RefreshHeaderLayout()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end

local function Run(flavor)
    local housing = { inside = false }
    local h, party = Boot(flavor, housing)
    local GF = h.GF
    party.hideInHousing = true
    Party(h)
    Check(UnitShown(h, "party1") and BorderShown(h, "party"), flavor .. ": the party block is not shown outside housing")

    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    Check(not UnitShown(h, "party1"), flavor .. ": Hide in Housing left the party frames shown on a plot")
    Check(not BorderShown(h, "party"), flavor .. ": Hide in Housing left the party group border shown on a plot")

    housing.inside = false
    h:Event("HOUSE_PLOT_EXITED")
    h:RunTimers()
    Check(UnitShown(h, "party1") and BorderShown(h, "party"), flavor .. ": the party block did not come back after leaving the plot")

    -- The option off: nothing hides; the toggle applies as a visual refresh.
    party.hideInHousing = false
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    Check(not HousingEventsRegistered(h), flavor .. ": housing events stay registered with Hide in Housing off")
    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    Check(UnitShown(h, "party1"), flavor .. ": the party block hid on a plot with Hide in Housing off")
    party.hideInHousing = true
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    Check(not UnitShown(h, "party1"), flavor .. ": switching Hide in Housing on inside a house did not hide the block")
    party.hideInHousing = false
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    Check(UnitShown(h, "party1"), flavor .. ": switching Hide in Housing off inside a house did not bring the block back")

    -- Entering in combat: nothing protected now, hidden once combat ends.
    housing.inside = false
    h:Event("HOUSE_PLOT_EXITED")
    party.hideInHousing = true
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    Check(HousingEventsRegistered(h), flavor .. ": switching Hide in Housing on did not register the housing events")
    Check(UnitShown(h, "party1"), flavor .. ": the party block is not shown before the combat case")
    h:EnterCombat()
    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    Check(#h.violations == 0, flavor .. ": " .. #h.violations .. " protected write(s) in combat")
    h:LeaveCombat()
    h:RunTimers()
    Check(not UnitShown(h, "party1"), flavor .. ": entering the plot in combat did not hide the block after combat")

    -- The raid scope follows its own option.
    local raid = GF.GetConf("raid")
    raid.enabled = true
    raid.hideInHousing = false
    housing.inside = true
    h:SetRaid(10)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    Check(UnitShown(h, "raid3"), flavor .. ": the raid block hid with its own Hide in Housing off")
    raid.hideInHousing = true
    GF.RefreshVisuals("raid", GF.DIRTY_VISUAL)
    h:RunTimers()
    Check(not UnitShown(h, "raid3"), flavor .. ": the raid block stayed shown with its Hide in Housing on")
    housing.inside = false
    h:Event("HOUSE_PLOT_EXITED")
    h:RunTimers()
    Check(UnitShown(h, "raid3"), flavor .. ": the raid block did not come back after leaving the plot")

    -- Logging in inside a house starts hidden.
    local inside = { inside = true }
    local login, loginParty = Boot(flavor, inside)
    loginParty.hideInHousing = true
    login:SetRoster({ "player", "party1" })
    login:Event("PLAYER_ENTERING_WORLD")
    login:RunTimers()
    Check(login.GF.FrameForUnit("party1") == nil or not UnitShown(login, "party1"),
        flavor .. ": logging in inside a house showed the party block")
end

local function Named(h, name)
    for _, frame in ipairs(h.widgets.frames) do
        if frame.frameName == name then return frame end
    end
end

-- Priority Frames and the extra blocks of the Party scope.
local function RunInherited(flavor)
    local housing = { inside = false }
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.C_Housing = { IsInsideHouseOrPlot = function() return housing.inside == true end }
        hh.env.UnitGroupRolesAssigned = function(unit)
            return unit == "party1" and "HEALER" or unit == "party2" and "TANK" or "DAMAGER"
        end
        -- MSUF_GroupFrames_Additional.xml: the extra-block button inherits
        -- SecureUnitButtonTemplate (protected), carries a Health status bar with
        -- Background and Name regions, and runs MSUF_GroupAdditionalUnitOnLoad.
        local createFrame = hh.env.CreateFrame
        hh.env.CreateFrame = function(frameType, name, parent, template)
            local frame = createFrame(frameType, name, parent, template)
            if template == "MSUF_GroupAdditionalUnitTemplate" then
                hh.Protect(frame)
                frame.Health = createFrame("StatusBar", nil, frame)
                frame.Health.Background = frame.Health:CreateTexture()
                frame.Health.Name = frame.Health:CreateFontString()
                hh.env.MSUF_GroupAdditionalUnitOnLoad(frame)
            end
            return frame
        end
    end })
    local GF = h.GF
    GF.EnsureDB()
    local party = GF.GetConf("party")
    party.enabled, party.showPlayer, party.hideInHousing = true, true, true
    party.healerManaEnabled, party.targetsEnabled = true, true
    local priority = GF.GetPriorityConf()
    priority.enabled, priority.autoTanks = true, true
    h:SetRoster({ "player", "party1", "party2" })
    GF.RefreshHeaderLayout()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    local mana, targets = Named(h, "MSUF_GroupAdditional_HealerMana"), Named(h, "MSUF_GroupAdditional_Targets")
    local function PriorityShown() return GF.headers.priority ~= nil and Visible(GF.headers.priority) end
    local function ManaShown() return mana ~= nil and Visible(mana) end
    local function TargetsShown() return targets ~= nil and Visible(targets) end
    local function State() return ("priority=%s mana=%s targets=%s"):format(tostring(PriorityShown()),
        tostring(ManaShown()), tostring(TargetsShown())) end
    local function AllShown(label) Check(PriorityShown() and ManaShown() and TargetsShown(), flavor .. ": " .. label .. " (" .. State() .. ")") end
    local function NoneShown(label) Check(not PriorityShown() and not ManaShown() and not TargetsShown(), flavor .. ": " .. label .. " (" .. State() .. ")") end
    AllShown("precondition: the Priority strip, healer mana and party targets are not shown")

    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    Check(not UnitShown(h, "party1"), flavor .. ": precondition: the party block did not hide on the plot")
    NoneShown("Hide in Housing left Priority Frames or an extra block of the party scope shown on a plot")
    housing.inside = false
    h:Event("HOUSE_PLOT_EXITED")
    h:RunTimers()
    AllShown("Priority Frames and the extra blocks did not come back after leaving the plot")

    -- The toggle inside a house.
    party.hideInHousing = false
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    AllShown("Priority Frames or an extra block hid on a plot with Hide in Housing off")
    party.hideInHousing = true
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    NoneShown("switching Hide in Housing on inside a house left Priority Frames or an extra block shown")
    party.hideInHousing = false
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    AllShown("switching Hide in Housing off inside a house did not bring Priority Frames and the extra blocks back")

    -- In combat: nothing protected; the mana rows hide at once, the rest after combat.
    housing.inside = false
    h:Event("HOUSE_PLOT_EXITED")
    party.hideInHousing = true
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    h:RunTimers()
    AllShown("precondition: Priority Frames and the extra blocks are not shown before the combat case")
    h:EnterCombat()
    housing.inside = true
    h:Event("HOUSE_PLOT_ENTERED")
    h:RunTimers()
    Check(#h.violations == 0, flavor .. ": " .. #h.violations .. " protected write(s) in combat: " .. tostring(h.violations[1]))
    Check(not ManaShown(), flavor .. ": the healer mana rows stayed shown on a plot in combat")
    Check(PriorityShown() and TargetsShown(), flavor .. ": a protected block changed in combat (" .. State() .. ")")
    h:LeaveCombat()
    h:RunTimers()
    NoneShown("entering the plot in combat left Priority Frames or an extra block shown after combat")
end

local function RunWithoutHousing(flavor)
    local h, party = Boot(flavor, nil)
    party.hideInHousing = true
    Party(h)
    Check(UnitShown(h, "party1"), flavor .. ": Hide in Housing hid the party block on a client without housing")
    Check(not HousingEventsRegistered(h), flavor .. ": a housing event was registered on a client without housing")
end

for _, flavor in ipairs({ "Mainline", "Forever" }) do
    Run(flavor)
    RunInherited(flavor)
end
RunWithoutHousing("Vanilla")

if failures > 0 then error(("group housing hide smoke: %d failure(s)"):format(failures)) end
print("group housing hide smoke: ok (Mainline, Forever, Vanilla)")

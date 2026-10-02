-- group_header_combat_child_smoke.lua <repoRoot> <flavor>
--
-- A party member who joins mid-combat must get a visible, styled, click-cast
-- registered frame at once, without one protected write from MSUF in lockdown.
--
-- SecureGroupHeader births missing children on demand, in combat too
-- (SecureGroupHeaders.lua configureChildren). Before the fix the header's
-- initialConfigFunction had no CallMethod and the styling scan waits for
-- PLAYER_REGEN_ENABLED, so such a child was an empty, clickable slot without
-- Clique for the rest of the fight. Fix (the oUF pattern): the snippet calls the
-- header's insecure method, which hooks the child's unit attribute; the unit
-- write then builds the visuals, and the protected setup (secure clicks,
-- RegisterForClicks) runs at the regen edge.
--
-- Runs the real core load graph of one flavor on the SecureGroupHeader emulator
-- of tools/tests/group_header_world.lua. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local h = Harness.New(root, flavor)
local GF, env = h.GF, h.env
GF.EnsureDB()
local party = GF.GetConf("party")
party.enabled = true
party.showPlayer = true
-- What the menu toggle does: one layout pass, which also subscribes the runtime.
GF.RefreshHeaderLayout()

-- Out of combat: a three-member party settles through the normal batched scan.
h:SetRoster({ "player", "party1", "party2" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local header = GF.headers.party
Check(header ~= nil and header.shown, "the party header did not build out of combat")
local snippet = header.attributes.initialConfigFunction
Check(type(snippet) == "string" and snippet:find("header:CallMethod('MSUFGFInitChild', self:GetName())", 1, true),
    "the secure snippet must hand every new child to the header's insecure method")
Check(type(header.MSUFGFInitChild) == "function", "the party header carries no child init method")
local children = h:Children(header)
Check(#children == 3, "expected 3 party children out of combat, got " .. #children)
for index, child in ipairs(children) do
    Check(child.MSUFSpec ~= nil and GF.frames[child] == true, "out-of-combat child " .. index .. " was not styled")
end
Check(#h.violations == 0, "protected write out of combat?\n" .. tostring(h.violations[1]))
Check(#h.callMethodErrors == 0, "CallMethod raised out of combat: " .. tostring(h.callMethodErrors[1]))

local function AssertStyled(child, unit, label)
    Check(child ~= nil, label .. ": SecureGroupHeader did not birth the child")
    Check(child.attributes.unit == unit and child.shown == true, label .. ": child is not shown for " .. unit)
    Check(child.MSUFSpec ~= nil, label .. ": child born in combat has no spec (an empty, clickable slot)")
    Check(GF.frames[child] == true and GF.FrameForUnit(unit) == child, label .. ": child is not tracked for " .. unit)
    local hp = child.hpBar or child.health
    Check(hp ~= nil and hp.shown == true, label .. ": child has no visible health bar")
    Check(child.nameText ~= nil, label .. ": child has no name text")
    Check(child._msufActiveElements and child._msufActiveElements.Health == true,
        label .. ": the Health element is not active")
    Check(env.ClickCastFrames[child] == true, label .. ": child is not registered with ClickCastFrames")
end

local function AssertRegenFinished(child)
    Check(child.forClicks and child.forClicks[1] == "AnyUp", "the regen edge did not register clicks for "
        .. tostring(child.attributes.unit))
    Check(child.attributes["*type1"] == "target" and child.attributes["*type2"] == "togglemenu",
        "secure click actions missing after regen for " .. tostring(child.attributes.unit))
    Check(GF.frames[child] == true and child.MSUFSpec ~= nil, "child lost its styling at the regen edge")
end

-- In lockdown: Blizzard's header births the fourth child itself.
h:EnterCombat()
local bornBefore = #h.born
h:SetRoster({ "player", "party1", "party2", "party3" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
Check(#h.born == bornBefore + 1 and h.born[#h.born].combat == true, "the header did not birth a child in lockdown")
local late = h:Children(header)[4]
AssertStyled(late, "party3", "child born in lockdown")
Check(#h.callMethodErrors == 0, "CallMethod raised in combat: " .. tostring(h.callMethodErrors[1]))
Check(#h.violations == 0, #h.violations .. " protected write(s) from insecure code in lockdown; first:\n"
    .. tostring(h.violations[1]))
-- The protected half waits for the regen edge.
Check(late.forClicks == nil, "RegisterForClicks ran in lockdown")
h:LeaveCombat()
Check(#h.violations == 0, "protected write in combat during the regen edge?\n" .. tostring(h.violations[1]))
AssertRegenFinished(late)

-- PLAYER_REGEN_DISABLED fires before lockdown. A child born in that window must
-- be adopted as well: the settle the roster event schedules runs in lockdown.
h:EnterCombat(function()
    h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
    h:Event("GROUP_ROSTER_UPDATE")
end)
h:RunTimers()
local early = h:Children(header)[5]
AssertStyled(early, "party4", "child born between REGEN_DISABLED and lockdown")
Check(#h.violations == 0, "protected write around the combat edge:\n" .. tostring(h.violations[1]))
h:LeaveCombat()
AssertRegenFinished(early)

-- A member who leaves in combat: the slot is cleared by the header, and the
-- adapter suspends the binding without a protected write.
h:EnterCombat()
h:SetRoster({ "player", "party1", "party2", "party3" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
Check(early.attributes.unit == nil and GF.frames[early] == nil, "a cleared slot stayed tracked")
Check(#h.violations == 0, "protected write while a member left in combat:\n" .. tostring(h.violations[1]))
h:LeaveCombat()

-- An out-of-combat birth whose next-frame settle the combat start overtakes:
-- the roster event births the child and writes its unit at once, the settle
-- then runs in lockdown and defers. The unit hook goes on at birth in every
-- state, so the unit write itself builds the frame; before, such a child was
-- an unstyled, clickable slot for the whole fight.
local raidConf = GF.GetConf("raid")
raidConf.enabled = true
h:SetRaid(6)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local raidHeader = GF.headers.raid
Check(raidHeader ~= nil and #h:Children(raidHeader) >= 6, "the raid header did not build out of combat")
h:SetRaid(7)
h:Event("GROUP_ROSTER_UPDATE")
Check(h.born[#h.born].combat == false and h.born[#h.born].header == raidHeader,
    "the seventh raid child was not born out of combat")
h:EnterCombat()
h:RunTimers()
local overtaken = h:Children(raidHeader)[7]
AssertStyled(overtaken, "raid7", "child born out of combat, settle overtaken by combat")
Check(#h.violations == 0, "protected write while combat overtook a settle:\n" .. tostring(h.violations[1]))
h:LeaveCombat()
AssertRegenFinished(overtaken)
raidConf.enabled = false

print(string.format("group_header_combat_child_smoke: ok (%s: %d children, %d born in lockdown, 0 protected writes)",
    flavor, #h:Children(header), (function()
        local count = 0
        for _, record in ipairs(h.born) do if record.combat then count = count + 1 end end
        return count
    end)()))

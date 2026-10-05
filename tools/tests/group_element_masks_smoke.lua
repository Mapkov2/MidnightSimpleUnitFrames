-- group_element_masks_smoke.lua <repoRoot>
--
-- Group frames apply only the elements their apply mask names (UF.ApplySpec
-- skips the rest). A group element left out of a mask keeps its old state on
-- that path: an element absent from the structure mask never reaches a frame
-- that was born at login or for a member who joined later.
--
-- Pins, on the real group runtime and an emulated SecureGroupHeader
-- (tools/tests/group_header_world.lua):
--   * Temporary max health (compiled into every group spec) reaches group
--     frames after login/reload and for members who join later, not only
--     after the Bars toggle (UF.RefreshTempMaxHealth).
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

local function PartyFrames(h, GF)
    local frames = {}
    for _, child in ipairs(h:Children(GF.headers.party)) do
        if child.MSUFUnitKey then frames[child.MSUFUnitKey] = child end
    end
    return frames
end

local function TempMaxHealth(flavor)
    local h = Harness.New(root, flavor, { beforeBoot = function(hh)
        hh.env.GetUnitTotalModifiedMaxHealthPercent = function() return 0.25 end
    end })
    local GF, env = h.GF, h.env
    GF.EnsureDB()
    -- The saved setting as the Bars page stores it for the Shared scope.
    env.MSUF_DB.general.tempMaxHealthEnabled = true
    local party = GF.GetConf("party")
    party.enabled = true
    party.showPlayer = true
    GF.InvalidateCompiledSpecs()
    GF.RefreshHeaderLayout()
    h:SetRoster({ "player", "party1" })
    h:Event("PLAYER_ENTERING_WORLD")
    h:RunTimers()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()

    local function Expect(label, units)
        local frames = PartyFrames(h, GF)
        for _, unit in ipairs(units) do
            local frame = frames[unit]
            Check(frame ~= nil, ("%s %s: no party frame for %s"):format(flavor, label, unit))
            if frame then
                local spec = frame.MSUFSpec and frame.MSUFSpec.tempMaxHealth
                Check(spec and spec.enabled == true, ("%s %s: %s spec has temporary max health off"):format(flavor, label, unit))
                Check(frame._msufActiveElements and frame._msufActiveElements.TempMaxHealth == true,
                    ("%s %s: %s has no active TempMaxHealth element"):format(flavor, label, unit))
                Check(frame.tempMaxHealthBar ~= nil and frame.tempMaxHealthBar:IsShown(),
                    ("%s %s: %s shows no temporary max health overlay"):format(flavor, label, unit))
            end
        end
    end
    Expect("after login/reload", { "player", "party1" })

    h:SetRoster({ "player", "party1", "party2" })
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    Expect("after a member joined", { "player", "party1", "party2" })

    -- A visual refresh (texture or layout change) re-applies it, and turning it
    -- off reaches live frames the same way.
    env.MSUF_DB.general.tempMaxHealthEnabled = false
    GF.RefreshVisuals("party", GF.DIRTY_VISUAL)
    local frames = PartyFrames(h, GF)
    for unit, frame in pairs(frames) do
        Check(not (frame._msufActiveElements and frame._msufActiveElements.TempMaxHealth == true),
            ("%s visual refresh after turning it off: %s still runs TempMaxHealth"):format(flavor, unit))
    end
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    TempMaxHealth(flavor)
end

if failures > 0 then error(("group element masks smoke: %d failure(s)"):format(failures)) end
print("group element masks smoke: ok (Mainline, Vanilla)")

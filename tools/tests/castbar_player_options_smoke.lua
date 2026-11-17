local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local checks, rankReads = 0, 0
local function Check(value, message)
    assert(value, flavor .. ": " .. message)
    checks = checks + 1
end
local world = World.New(root, { flavor = flavor, setup = function(env)
    env.C_Spell.GetSpellSubtext = function(id)
        assert(not env.issecretvalue(id), "secret spell ID passed to rank API")
        rankReads = rankReads + 1
        return id == 133 and "Rank 4" or "Passive"
    end
end })
local C, env = world.core.Castbars, world.env
world.core.Require("MSUF_EnsureDB", "castbar player options test")(true)
local g = env.MSUF_DB.general
g.showGCDBar, g.castbarShowPushback = false, false
g.castbarFadeEnabled, g.castbarPlayerShowSpellRank, g.castbarPlayerShowTargetName = true, true, true
g.castbarLatencyR, g.castbarLatencyG, g.castbarLatencyB, g.castbarLatencyA = .2, .4, .6, .7
world.core.Require("MSUF_Castbars_OnSettingsChanged", "castbar player options test")()
world:Advance(.5)
g = env.MSUF_DB.general
for i = #world.errors, 1, -1 do world.errors[i] = nil end
world.secretCasts = false
local player = assert(C.Frames.Get("player"))
local stopWatch = world:Watch({
    root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua",
    root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua",
    root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarStyle.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua",
})
local function Cast(guid, name, id, seconds)
    id = id or 133
    world:Fire(player, "UNIT_SPELLCAST_SENT", "player", name, guid, id)
    world:StartCast("player", "Healing spell", seconds or 10, 101, { spellID = id, castID = guid })
    world:Fire(player, "UNIT_SPELLCAST_START", "player", guid, id, 101)
end
Cast("Cast-A", "First recipient")
Check(player.castTargetText and player.castTargetText.text == "First recipient", "actual player spell recipient missing")
local ranked = flavor == "Forever" or flavor == "TBC" or flavor == "Vanilla"
Check(player.castText.text == (ranked and "Healing spell (Rank 4)" or "Healing spell"), "rank capability or text wrong")
Check(rankReads == (ranked and 1 or 0), "rank queried on unsupported client")
Check(player:GetAlpha() < 1, "fade-in did not start")
world:Advance(.06)
Check(player:GetAlpha() > 0 and player:GetAlpha() < 1, "fade-in has no intermediate opacity")
world:Advance(.4)
Check(player:GetAlpha() == 1, "fade-in never settled")
local zone = player.latencyBar.colorTexture
Check(zone and zone[1] == .2 and zone[2] == .4 and zone[3] == .6 and zone[4] == .7, "latency RGBA not painted")
C.Player.UpdateTargetText(player)
Check(player.castTargetText.text == "First recipient", "target lost on cold refresh")
local previousText = player.castText.text
world.casting.player = nil
C.Runtime:Stop(player, "STOPPED")
Check(player.MSUF_castActive == false and player:IsShown(), "soft stop did not release runtime before fade")
Check(player.castText.text == previousText, "fade-out lost cast text")
world:Advance(.06)
Check(player:GetAlpha() > 0 and player:GetAlpha() < 1, "fade-out has no intermediate opacity")
local alpha, velocity = player:GetAlpha(), player._msufFadeDriver.velocity
Cast("Cast-B", "Second recipient")
Check(player:GetAlpha() == alpha and player._msufFadeDriver.velocity == velocity, "re-cast lost spring position or velocity")
Check(player.castTargetText.text == "Second recipient", "previous recipient leaked into next cast")
world:Advance(.5)
Check(player:IsShown() and player:GetAlpha() == 1, "stale fade completion hid new cast")
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", "Queued recipient", "Queued", 133)
world:StartCast("player", "Different cast", 10, 102, { spellID = 133, castID = "Different" })
world:Fire(player, "UNIT_SPELLCAST_START", "player", "Different", 133, 102)
Check(not player.castTargetText:IsShown(), "mismatching queued SENT recipient leaked")
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", "Expired recipient", "Expired", 133)
world:Advance(2.1)
world:StartCast("player", "Expired cast", 10, 103, { spellID = 133, castID = "Expired" })
world:Fire(player, "UNIT_SPELLCAST_START", "player", "Expired", 133, 103)
Check(not player.castTargetText:IsShown(), "expired SENT recipient leaked")
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", "Superseded recipient", "Superseded", 133)
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", "Latest recipient", world.Secrets.New("string"), 133)
world:StartCast("player", "Latest cast", 10, 107, { spellID = 133, castID = "Latest" })
world:Fire(player, "UNIT_SPELLCAST_START", "player", "Latest", 133, 107)
Check(player.castTargetText.text == "Latest recipient", "a superseded public GUID overrode the newest restricted SENT")
g.castbarPlayerShowSpellRank = false
C.Config.Compile("style")
C.Utils.RefreshCastbarSpellNameText(player)
Check(not player.castText.text:find("Rank", 1, true), "rank toggle did not remove the suffix")
g.castbarPlayerShowSpellRank = true
C.Config.Compile("style")
C.Utils.RefreshCastbarSpellNameText(player)
Check(not ranked or player.castText.text:find("Rank 4", 1, true), "mid-cast rank toggle did not acquire the current rank")
Cast("Passive", "Recipient", 999)
Check(not player.castText.text:find("Passive", 1, true), "non-rank spell subtext displayed")
if ranked then
    C.Utils.CapturePlayerSpellRank(player, 133, nil, "vehicle")
    Check(player._msufPlayerCastRank == nil, "vehicle cast retained a player spell rank")
end
local secretName = world.Secrets.New("string")
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", secretName, "Secret-name", 133)
world:StartCast("player", "Secret target cast", 10, 104, { castID = "Secret-name" })
world:Fire(player, "UNIT_SPELLCAST_START", "player", "Secret-name", 133, 104)
Check(world.Secrets.IsSecret(player.castTargetText.text), "secret recipient did not reach native text sink")
world.casting.player = nil
C.Runtime:Stop(player, "STOPPED")
world:Advance(.5)
Check(not player:IsShown() and player.castText.text == "", "fade-out did not hide and clean content")
Cast("Completion", "Recipient", 133, .25)
world:Advance(.3)
Check(not player.MSUF_castActive and player:IsShown(), "natural completion bypassed the fade tail")
world.casting.player = nil
world:Advance(.5)
Check(not player:IsShown(), "natural completion fade did not finish")
if flavor == "Mainline" or flavor == "Forever" then
Cast("Before-empower", "Old empower recipient")
world:Advance(.5)
world.casting.player = nil
C.Runtime:Stop(player, "STOPPED")
world:Advance(.06)
world:Fire(player, "UNIT_SPELLCAST_SENT", "player", "Empower recipient", "Empower", 357208)
world:StartChannel("player", "Fire Breath", 1.2, 105, { empowered = true, spellID = 357208, castID = "Empower" })
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_START", "player", "Empower", 357208, 105)
Check(player.isEmpower == true, "re-cast cleanup erased new empower state")
Check(player.castTargetText:IsShown() and player.castTargetText.text == "Empower recipient", "empower recipient missing or stale")
world:Advance(.1)
Check(player.isEmpower == true and player:IsShown(), "empower state did not survive its first update")
world.channeling.player = nil
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "Empower", 357208, true, nil, 105)
Check(player:IsShown() and player._msufRetainedCast == true, "empower stop bypassed fade-out")
world:Advance(.06)
Check(player:GetAlpha() > 0 and player:GetAlpha() < 1, "empower fade-out has no intermediate opacity")
world:Advance(.5)
Check(not player:IsShown() and not player.castTargetText:IsShown(), "empower fade did not clean up")
Cast("Before-empower-recovery", "Old recovery recipient")
world:Advance(.5)
world.casting.player = nil
C.Runtime:Stop(player, "STOPPED")
world:Advance(.06)
world:StartChannel("player", "Recovered empower", 1.2, 106, { empowered = true, spellID = 357208 })
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_UPDATE", "player", "Recovered", 357208, 106)
Check(player.isEmpower == true, "empower recovery cleanup erased new empower state")
local visible = player.IsVisible
player.IsVisible = function() return false end
world.channeling.player = nil
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "Recovered", 357208, true, nil, 106)
player.IsVisible = visible
Check(not player.isEmpower, "hidden empower stop retained empower state")
Cast("After-hidden-empower", "New recipient")
Check(player.MSUF_castActive == true and not player.isEmpower, "normal cast blocked after hidden empower completion")
world.casting.player = nil
C.Runtime:Stop(player, "STOPPED")
world:Advance(.5)
Cast("Interrupted-before-empower", "Old recipient")
world.casting.player = nil
world:Fire(player, "UNIT_SPELLCAST_INTERRUPTED", "player", player._msufActiveCastGUID, 133, nil, 101)
Check(player.interruptFeedbackEndTime ~= nil, "interrupt-to-empower fixture did not interrupt")
world:StartChannel("player", "Empower after interrupt", 1.2, 108, { empowered = true, spellID = 357208 })
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_START", "player", "After-interrupt", 357208, 108)
Check(not player.interrupted and player.isEmpower == true, "new empower retained old interrupt state")
world.channeling.player = nil
world:Fire(player, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "After-interrupt", 357208, true, nil, 108)
world:Advance(.5)
Check(not player:IsShown(), "completed empower after interrupt remained visible")
end
Cast("Hard-hide", "Recipient")
player:Hide()
Check(not player._msufFadeDriver.active and player._msufFadeDriver.scripts.OnUpdate == nil, "hard hide left motion running")
Cast("Reduced", "Recipient")
g.reduceMotion = true
C.Config.Compile("style")
world:Advance(.1)
Check(player:GetAlpha() == 1 and not player._msufFadeDriver.active, "reduced motion did not settle")
g.reduceMotion = false
C.Config.Compile("style")
local target = C.Frames.Get("target") or C.Driver.CreateCastBar("MSUF_TargetCastBar", "target")
local unitFrame = env.CreateFrame("Frame")
unitFrame.MSUFUnitKey = "target"
world.core.UF.frames.target = unitFrame
if target then
    target:Hide()
    unitFrame._msufAlphaRangeActive, unitFrame._msufAlphaRangeHealthLayer = true, false
    unitFrame._msufRangeMul = .35
    C.Style.Fade.Show(target)
    world:Advance(.5)
    Check(math.abs(target:GetAlpha() - .35) < .001, "fade overrode out-of-range alpha")
    unitFrame._msufRangeBooleanActive = true
    unitFrame._msufRangeBooleanValue = world.Secrets.New("boolean")
    unitFrame._msufRangeBooleanOutAlpha = .35
    C.Style.Fade.Hide(target)
    world:Advance(.06)
    Check(world.Secrets.IsSecret(target.alphaBoolean), "secret range decision did not stay in a native sink")
    Check(target.alphaIfTrue > 0 and target.alphaIfTrue < 1
        and math.abs(target.alphaIfFalse - .35 * target.alphaIfTrue) < .001,
        "fade multiplier was not composed into both native range outcomes")
    unitFrame._msufRangeBooleanActive = false
    target._msufFocusKickSuppressed = true
    target:SetAlpha(0)
    C.Style.Fade.Hide(target)
    world:Advance(.06)
    C.Style.Fade.Show(target)
    world:Advance(.4)
    Check(target:GetAlpha() == 0, "fade overrode focus suppression")
    target._msufFocusKickSuppressed = nil
    target:Hide()
end
Check(target ~= nil, "range composition was not exercised")
env.MSUF_UnitEditModeActive = true
g.castbarPlayerShowSpellRank = false
C.Config.Compile("style")
C.Previews.SetPlayerCastbarTestMode(true, true)
local testPreview = C.Frames.playerPreview or player
Check(testPreview.MSUF_testMode == true, "player test preview did not start")
g.castbarPlayerShowSpellRank = true
C.Config.Compile("style")
C.Utils.RefreshCastbarSpellNameText(testPreview)
Check(not ranked or testPreview.castText.text:find("Rank 4", 1, true), "running player test preview did not acquire rank")
C.Previews.SetPlayerCastbarTestMode(false, true)
env.MSUF_UnitEditModeActive = false
local violations = stopWatch()
Check(#violations == 0, table.concat(violations, "\n"))
Check(#world.errors == 0, table.concat(world.errors, "\n"))
-- Exercise the readable fallback on clients without a native duration object.
local fallback = World.New(root, { flavor = flavor, setup = function(api)
    api.UnitCastingDuration, api.UnitChannelDuration = nil, nil
end })
fallback.core.Require("MSUF_EnsureDB", "castbar fallback options test")(true)
fallback.env.MSUF_DB.general.castbarFadeEnabled = true
fallback.core.Require("MSUF_Castbars_OnSettingsChanged", "castbar fallback options test")()
fallback:Advance(.5)
fallback.secretCasts = false
local bar = assert(fallback.core.Castbars.Frames.Get("target"))
fallback:StartCast("target", "Old fallback cast", 4, 601)
fallback:Fire(bar, "UNIT_SPELLCAST_START", fallback:Payload("UNIT_SPELLCAST_START", "target", 601))
fallback:Advance(.5)
fallback.casting.target = nil
fallback.core.Castbars.Runtime:Stop(bar, "STOPPED")
fallback:Advance(.06)
local retained = bar.castText.text
bar:Cast()
Check(bar.castText.text == retained, "empty cast refresh erased the retained fade content")
fallback:StartCast("target", "New fallback cast", 4, 602)
fallback:Fire(bar, "UNIT_SPELLCAST_START", fallback:Payload("UNIT_SPELLCAST_START", "target", 602))
Check(bar:IsShown() and bar.castText.text == "New fallback cast", "fade cleanup erased the new fallback spell name")
print("castbar_player_options_smoke " .. flavor .. ": " .. checks .. " checks passed")

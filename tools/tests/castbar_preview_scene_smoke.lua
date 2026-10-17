local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local W = dofile(root .. "/tools/tests/preview_surface_world.lua")
local h = W.Open(root, flavor, { class = "MAGE", spec = 1, count = 3, maximum = 5, time = 100 })
local env, C = h.env, h.core.Castbars
local g = env.MSUF_DB.general
g.castbarTargetShowTargetName, g.castbarFocusShowTargetName = true, true
g.showBossCastTargetName, g.showArenaCastTargetName = true, true
g.kickReadyTimeMarker, g.kickReadyTimeSegment = true, true
g.castbarShowChannelTicks, g.castbarShowSpark = true, true
g.empowerColorStages, g.castbarAccentLastTick = true, true
g.castbarOutlineThickness, g.castbarBorderR, g.castbarBorderG, g.castbarBorderB = 2, .2, .4, .6
env.MSUF_DB.player.castbar = { channelTickUseCustom = true, channelTickCount = 3, channelTickPosPct = { 15, 40, 80 } }
local owner = h:Host()
local r = h.GF.NewPreviewScene(owner)
local cases, last = 0
local kinds = { "CAST", "CHANNEL", "INTERRUPT" }
if C.Empower.LayoutEmpowerTicks then kinds[#kinds + 1] = "EMPOWER" end
for _, unit in ipairs({ "player", "target", "focus", "boss1", "arena1" }) do
  if h.core.Client.SupportsUnit(unit) then
    h.core.UF.frames[unit] = owner
    local live
    if unit == "player" then
      C.Manager.InitSafePlayerCastbar()
      live = assert(C.Frames.player)
    else live = C.Driver.CreateCastBar(nil, unit) end
    live:SetParent(owner)
    live:ClearAllPoints(); live:SetPoint("CENTER", owner, "CENTER", 0, 0)
    live:SetSize(283, 23)
    local scene = h:SceneCall(r.Castbar, r, unit, { width = 283, height = 23 })
    if not r:IsActive() then assert(not scene:Frame(), "closed castbar allocated"); h:SceneCall(r.Activate, r) end
    for _, style in ipairs({ "box", "border", "fill" }) do
    g.kickReadyStyle = style
    g.playerCastbarOverrideEnabled = style ~= "box"
    g.playerCastbarOverrideMode = style == "border" and "CLASS" or "CUSTOM"
    g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = .67, .31, .82
    g.kickReadyShowTarget, g.kickReadyShowFocus, g.kickReadyShowBoss, g.kickReadyShowArena = true, true, true, true
    for _, kind in ipairs(kinds) do
      for _, blocked in ipairs({ false, true }) do
        local sample = { class = "MAGE", name = "Sample Frostbolt", icon = 136048, duration = 4,
          targetName = "Sample Tank", targetClass = "WARRIOR", progress = .625, latency = .12, kind = kind, notInterruptible = blocked, stages = { .7, 1.8, 3 }, spellID = 5143 }
        sample.kickRecovery = { .4, .75 }
        sample.kickReady, sample.interrupted = kind == "CHANNEL", kind == "INTERRUPT"
        C.Config.Refresh()
        if C.Empower.PlayerCastbar_ClearEmpower then C.Empower.PlayerCastbar_ClearEmpower(live, false) end
        local channel = kind == "CHANNEL"
        local state = { unit = unit, active = true, castType = channel and "CHANNEL" or "CAST",
          spellName = sample.name, text = sample.name, icon = sample.icon, apiNotInterruptibleRaw = blocked,
          startTimeMS = 97500, endTimeMS = 101500, spellID = sample.spellID }
        live.isNotInterruptible = blocked
        if unit == "player" then
          live.icon:SetTexture(sample.icon)
          C.Utils.CB_ApplyTexts(live, nil, sample.name, nil)
          live.MSUF_isChanneled = channel
          live._msufPlainTotal = 4
          live._msufCountsDown = channel and C.Utils.GetCastbarCountsDown(live, true) == true
          live._msufTimerAssumeCountdown = live._msufCountsDown
          live.statusBar:SetReverseFill(C.Utils.GetReverseFillSafe(live, channel) == true)
          live._msufStripeReverseFill = C.Utils.GetReverseFillSafe(live, channel) == true
          live.statusBar:SetMinMaxValues(0, 4)
          live.statusBar:SetValue((live._msufCountsDown and 1 - sample.progress or sample.progress) * 4)
          C.Driver.UpdateCastTimeText_FromStatusBar(live)
          live._msufActiveSpellID = sample.spellID
        else live:Cast(state) end
        C.Visuals.RefreshCastbarFrame(live, unit, g)
        -- Parent live layout catches up on the next refresh; compare its settled geometry.
        C.Visuals.RefreshCastbarFrame(live, unit, g)
        C.Driver.CreateTargetPainter(function(value) return value.targetName, value.targetClass, true end,
          function() return true end)(live, sample)
        C.Core.ApplyCastbarFrameLayer(live, g, unit)
        C.Core.ApplyCastbarSparkVisual(live, g)
        if unit == "player" then
          C.Player.PlayerCastbar_UpdateColorForInterruptible(live)
          C.Player.ApplyLatencySample(live, sample.latency, channel)
        end
        if kind == "EMPOWER" then
          live.isEmpower, live.empowerStageEnds, live.empowerTotalWithGrace = true, sample.stages, 4
          C.Empower.LayoutEmpowerTicks(live)
        end
        if C.ChannelTicks.PlayerChannelHasteMarkers_Update then C.ChannelTicks.PlayerChannelHasteMarkers_Update(live, true) end
        live.MSUF_castActive = true
        local projection = { duration = { GetStartTime = function() return 0 end,
          GetEndTime = function() return sample.duration end }, cooldowns = {} }
        for i, recovery in ipairs(sample.kickRecovery) do
          projection.cooldowns[i] = { GetEndTime = function() return recovery * sample.duration end }
        end
        C.KickReady.CreateSamplePainter({ resolved = true, ready = sample.kickReady,
          projection = projection })(live, nil, g)
        if sample.interrupted then C.Runtime:ApplyInterruptValues(live, 1, false, nil, nil, nil, nil, true) end
        live:Show()
        h:SceneCall(scene.SetOptions, scene, { sample = sample, width = 283, height = 23 })
        W.Equal(h, W.Snapshot(h, live, owner), W.Snapshot(h, scene:Frame(), owner), unit .. "/" .. kind .. "/" .. style .. "/" .. tostring(blocked))
        W.Isolated(h, scene:Frame())
        if unit ~= "player" and not sample.interrupted then
          assert(scene:Frame().castTargetText:GetText() == sample.targetName, "lost cast target")
        end
        if kind == "EMPOWER" then
          assert(#scene:Frame().empowerTicks == 3 and #scene:Frame().empowerSegments == 4, "lost stage or hold")
        end
        if unit ~= "player" and not blocked and not sample.interrupted then
          local projections = scene:Frame()._msufKickTimeProjections
          assert(projections and #projections == 2, "lost interrupt recovery projection")
          assert(projections[1]:GetValue() == 1.6, "wrong recovery fraction")
        end
        cases = cases + 1
      end
    end
    end
    last = scene
  end
end
W.InputAndIsolation(h, r, last)
last.opts.sample.interrupted = false
last.opts.sample.kind = "CAST"
h:SceneCall(last.Refresh, last)
local value = last:Frame().statusBar:GetValue()
assert(value == last.opts.sample.progress * last.opts.sample.duration, "wrong static progress")
last.opts.animate = true
h:SceneCall(last.Refresh, last)
local tickers = #h.widgets.tickers
h:SceneCall(r.SetClock, r, .03)
assert(last:Frame().statusBar:GetValue() ~= value, "clock did not advance progress")
h:SceneCall(r.SetClock, r, nil)
assert(last:Frame().statusBar:GetValue() == value, "static progress not restored")
assert(#h.widgets.tickers == tickers and not last.host.clock, "scene started its own clock")
W.Lifecycle(h, r, last)
h:SceneCall(r.SetClock, r, .06)
assert(not last:Frame() and #h.widgets.tickers == tickers, "clock revived released scene")
print("castbar_preview_scene_smoke: " .. flavor .. " " .. cases .. " twin paints, geometry, API isolation and lifecycle")

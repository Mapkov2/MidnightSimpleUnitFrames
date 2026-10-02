-- Real addon load graph and Edit Mode bridge: disabled/idle GCD placement,
-- movement, dimensions, history and profile switches without casting a spell.
local root = assert(arg[1], "root required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor)
    world.env.MAX_BOSS_FRAMES = 5
    world.env.GetCursorPosition = function() return 800, 600 end
    -- The separate GCD bar exists only where the client fills it natively:
    -- the Duration API, and on WoW Forever the GCD spell in its spell data.
    world.env.C_Spell = setmetatable({
        GetSpellCooldownDuration = function() return nil end,
        DoesSpellExist = function(spellID) return spellID == 61304 end,
    }, { __index = World.Stub })
    world:Boot()
    assert(not world:FirstFailure(), flavor .. " boot failed")
    local env = world.env
    env.GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end }
    -- GCD is independent of unit-frame health widgets. Keep the session's
    -- unrelated full UF rebuild out of this bridge-focused fake client.
    world.core.UF.Apply = function() end
    env.MSUF_EnsureDB(true)
    env.MSUF_ActiveProfile = "Default"
    env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
    local g = env.MSUF_DB.general
    g.showGCDBar, g.gcdBarDetached, g.gcdBarCombatOnly = false, true, true
    g.gcdBarX, g.gcdBarY, g.gcdBarWidth, g.gcdBarHeight = 0, -180, 180, 12
    env.MSUF_GCDBar_RefreshLayout()
    local em, key = env.MSUF_EM2, "external:msuf.gcd:bar"
    assert(em.Registry.Get(key), flavor .. " GCD mover not registered")
    assert(em.State.Enter("player"), flavor .. " edit entry failed")
    world.widgets:RunTimers(1000)
    em.Movers.SyncAll()
    local bar, mover = em.Registry.Get(key).getFrame(), em.Movers.Get(key)
    assert(bar:IsShown() and mover and mover:IsShown(), flavor .. " disabled/combat-only GCD has no edit surface")
    assert(not g.showGCDBar, "placement enabled gameplay")
    assert(env.MSUF_EditModeAPI.Open("MSUF.GCD", "bar"), "GCD selection failed")
    local external = em.ExternalElements
    local cx, cy = mover:GetCenter()
    assert(mover:GetScript("OnDragStart")(mover, "LeftButton"), "GCD drag did not start")
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", env.UIParent, "BOTTOMLEFT", cx + 13, cy + 9)
    -- The widget harness stores anchors without resolving screen rectangles.
    mover.left, mover.bottom = mover.left + 13, mover.bottom + 9
    assert(mover:GetScript("OnDragStop")(mover, "LeftButton"), "GCD drag did not finish")
    assert(g.gcdBarX == 13 and g.gcdBarY == -171, "drag did not save offsets")
    em.Undo.DoUndo()
    assert(g.gcdBarX == 0 and g.gcdBarY == -180, "drag undo failed")
    assert(external.Nudge(key, 23, -17), "GCD nudge failed")
    assert(g.gcdBarX == 23 and g.gcdBarY == -197, "nudge did not save offsets")
    assert(external.ApplyControl(key, "width", 240), "width edit failed")
    assert(external.ApplyControl(key, "height", 22), "height edit failed")
    assert(bar:GetWidth() == 240 and bar:GetHeight() == 22, "size did not reach frame")
    assert(em.Undo.CanUndo(), "size undo missing")
    em.Undo.DoUndo()
    assert(g.gcdBarHeight == 12, "undo lost old size")
    assert(em.Undo.CanRedo(), "size redo missing")
    em.Undo.DoRedo()
    assert(g.gcdBarHeight == 22, "redo lost new size")
    g.showGCDBarSpell, g.showGCDBarTime = false, false
    env.MSUF_GCDBar_RefreshLayout()
    assert(not bar.icon:IsShown() and bar.castText:GetText() == "" and bar.timeText:GetText() == "", "preview ignored text/icon toggles")
    g.showGCDBarSpell, g.showGCDBarTime = true, true
    env.MSUF_GCDBar_RefreshLayout()
    assert(bar.icon:IsShown() and bar.timeText:GetText() == "0.8", "preview did not restore details")
    g.gcdBarDetached = false
    env.MSUF_GCDBar_RefreshLayout()
    em.Movers.SyncAll()
    assert(not bar:IsShown() and not mover:IsShown(), "attached mode retained detached mover")
    g.gcdBarDetached = true
    env.MSUF_GCDBar_RefreshLayout()
    -- The same external transaction used by CancelAll, isolated from the
    -- unrelated full unit-frame rebuild in this fake client.
    assert(external.EndSession("discard"), "discard transaction failed")
    em.State.Exit()
    world.widgets:RunTimers(1000)
    g = env.MSUF_DB.general
    assert(not bar:IsShown(), "discard leaked GCD preview")
    assert(g.gcdBarX == 0 and g.gcdBarY == -180 and g.gcdBarWidth == 180 and g.gcdBarHeight == 12, "discard did not restore placement/size")
    -- Registration must follow the current profile, never close over the first DB.
    local old = env.MSUF_DB.general
    env.MSUF_DB.general = { gcdBarDetached = true, gcdBarX = -55, gcdBarY = 68 }
    env.MSUF_GCDBar_RefreshLayout()
    assert(em.State.Enter("player"), "second edit entry failed")
    world.widgets:RunTimers(1000)
    assert(external.Nudge(key, 5, 2), "new profile nudge failed")
    assert(env.MSUF_DB.general.gcdBarX == -50 and old.gcdBarX == 0, "mover wrote old profile")
    world.widgets:SetCombat(true)
    for _, frame in ipairs(world.widgets.frames) do
        local callback = frame:GetScript("OnEvent")
        if frame:IsEventRegistered("PLAYER_REGEN_DISABLED") and callback
            and debug.getinfo(callback, "S").source:find("MSUF_EditMode_State.lua", 1, true) then
            callback(frame, "PLAYER_REGEN_DISABLED")
        end
    end
    assert(not em.State.IsActive() and not bar:IsShown() and not mover:IsShown(), "combat leaked GCD edit surface")
    assert(env.MSUF_DB.general.gcdBarX == -50, "save discarded new profile position")
    print("castbar_detached_gcd_editmode_smoke: " .. flavor .. " PASS")
end

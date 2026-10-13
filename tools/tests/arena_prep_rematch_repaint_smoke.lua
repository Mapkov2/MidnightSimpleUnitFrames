-- arena_prep_rematch_repaint_smoke.lua <repoRoot>
--
-- The arena preparation room paints synthetic opponents ("Frost - Mage", a
-- full 0..1 health bar) straight onto the arena frames, past the engine's
-- write caches. When the match starts, the live writers must repaint the real
-- name and health even if the opponent is the same as last round, so the
-- caches those writers compare against are dropped when prep ends. Before the
-- fix a Mists rematch kept the "Spec - Class" text and the 0..1 bar.
--
-- Real Features/Gameplay/MSUF_Feature_ArenaMatch.lua, Libs/MSUFUnitFrames/
-- MSUF_UF_Apply.lua and UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua
-- in a Mists client world, once on the absolute health route (current and max
-- text) and once on the native percent route (UnitHealthPercent on 0..100).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Scenario(route)
    local world = World.New(root, "Mists")
    local env, ns = world.env, world.core
    ns.ExportPublic = function(name, value) env[name] = value end
    ns.Optional = function(name) return rawget(env, name) end
    ns.Require = function(name) return assert(rawget(env, name), "missing " .. name) end
    ns.Util = { InCombat = function() return world.widgets:IsInCombat() end }
    local function Load(path)
        local ok, err = world:LoadFile(root .. "/MidnightSimpleUnitFrames/" .. path, "MidnightSimpleUnitFrames", ns)
        assert(ok, route .. ": " .. tostring(err))
    end

    env.MSUF_MAX_ARENA_FRAMES = 1
    -- Kernel's event bus: the module wires its arena events there; the smoke drives
    -- the prep sync directly.
    env.MSUF_EventBus_Register = function() end
    env.MSUF_DB = { arena = { enabled = true } }
    env.C_EventUtils = { IsEventValid = function() return false end }
    env.C_PvP, env.UnitFrameUtil = {}, false
    env.IsActiveBattlefieldArena = function() return true end
    env.GetNumArenaOpponentSpecs = function() return 1 end
    env.GetArenaOpponentSpec = function() return 64, 0 end
    env.GetSpecializationInfoByID = function() return 64, "Frost", nil, nil, nil, "MAGE", "Mage" end
    local live = false
    env.UnitExists = function() return live end
    env.UnitHealth = function() return 40000 end
    env.UnitHealthMax = function() return 50000 end

    local frame = env.CreateFrame("Button", "ArenaRematchFrame", env.UIParent)
    frame.nameText = frame:CreateFontString()
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.MSUFUnitKey = "arena1"
    frame._msufHealthRuntimeColorUpdateEnabled = false
    ns.UF = { GetFrame = function() return frame end }
    Load("Libs/MSUFUnitFrames/MSUF_UF_Apply.lua")
    local health
    ns.UF.RegisterElement = function(_, element) health = element end
    local wantMax, wantValue
    if route == "percent" then
        ns.UFBarTextCommon = { UnitHealthPercent = function() return 80 end, SCALE_100 = 1 }
        wantMax, wantValue = 100, 80
    else
        ns.UFBarTextCommon = {}
        frame._msufTextRuntime = { healthSlotCount = 1, healthNeedsCurrent = true, healthNeedsMax = true }
        wantMax, wantValue = 50000, 40000
    end
    Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua")
    assert(health and health.Update, route .. ": the Health element did not register")

    -- Round one through the live writers, so every write cache holds the
    -- live name, range and value.
    local bar = frame.hpBar
    local function PaintLive(event)
        ns.Apply.Text(frame.nameText, "Peer")
        health.Update(frame, event, "arena1")
    end
    frame.ForceUpdate = function(_, event) PaintLive(event) end
    live = true
    PaintLive("UNIT_HEALTH")
    local _, liveMax = bar:GetMinMaxValues()
    assert(frame.nameText:GetText() == "Peer" and liveMax == wantMax and bar:GetValue() == wantValue,
        route .. ": the live health element did not paint the first round")

    Load("Features/Gameplay/MSUF_Feature_ArenaMatch.lua")
    for round = 1, 2 do
        -- Preparation room: no live unit yet, the synthetic opponent shows.
        live = false
        env.MSUF_ArenaMatch_SyncPrepDisplay()
        local _, prepMax = bar:GetMinMaxValues()
        assert(frame.nameText:GetText() == "Frost - Mage" and prepMax == 1 and bar:GetValue() == 1,
            route .. " round " .. round .. ": prep did not paint the synthetic opponent")
        -- Gates open: the same opponent, the same name, range and value.
        live = true
        env.MSUF_ArenaMatch_SyncPrepDisplay()
        assert(frame.nameText:GetText() == "Peer", route .. " round " .. round
            .. ": the live name lost to a stale cache, the frame still shows " .. tostring(frame.nameText:GetText()))
        local _, maximum = bar:GetMinMaxValues()
        assert(maximum == wantMax and bar:GetValue() == wantValue, route .. " round " .. round
            .. ": the live health lost to a stale cache, the bar shows "
            .. tostring(bar:GetValue()) .. " of " .. tostring(maximum))
        PaintLive("UNIT_HEALTH")
    end
end

Scenario("absolute")
Scenario("percent")
print("arena_prep_rematch_repaint_smoke: OK")

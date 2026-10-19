-- unit_preview_secret_health_full_bar_smoke.lua <repoRoot> [flavor]
--
-- A live unit whose current health is secret shows a full bar in the Options unit preview, like its frame out of
-- combat, instead of the stylized 72% sample. Readable health keeps its exact fraction, and a unit without
-- readable live health keeps the sample.
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local SECRET = {}
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
-- The preview model reads issecretvalue once while it loads, so the stub has to be in place before it does.
local w = World.Open(root, flavor, { page = "home", beforeOptions = function(world)
    local original = world.env.issecretvalue
    world.env.issecretvalue = function(value)
        return rawequal(value, SECRET) or (original ~= nil and original(value)) or false
    end
end })
local env, core = w.env, w.core

local function Check(condition, message)
    if not condition then error("unit_preview_secret_health_full_bar_smoke " .. flavor .. ": " .. message, 2) end
end

local Preview = core.UFPreview
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return "player" end
local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
World.FireVisibilityScripts(box)
box:Show()
box.canvas:SetSize(600, 260)
local function SampleHp()
    Preview.Refresh(box, "SETTINGS")
    return box._unitScene:Sample().hp
end

env.UnitExists = function() return false end
local stylized = SampleHp()
Check(stylized ~= nil and stylized < 1, "the stylized sample is expected to be a partial bar, got " .. tostring(stylized))

env.UnitExists = function() return true end
env.UnitHealthMax = function() return 900000 end
env.UnitHealth = function() return SECRET end
Check(SampleHp() == 1, "a secret current health did not show a full bar: " .. tostring(SampleHp()))

env.UnitHealth = function() return 450000 end
Check(SampleHp() == 0.5, "readable health lost its exact fraction: " .. tostring(SampleHp()))

env.UnitHealthMax = function() return SECRET end
env.UnitHealth = function() return SECRET end
Check(SampleHp() == stylized, "a unit without readable live health lost the stylized sample: " .. tostring(SampleHp()))
box:Hide()

print("unit_preview_secret_health_full_bar_smoke: PASS (" .. flavor .. ")")

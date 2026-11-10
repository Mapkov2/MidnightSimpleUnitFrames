-- A Druid form controls bar art and text independently, including the shaped outline.
local root, flavor = assert(arg[1]):gsub("\\", "/"), assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local CP, build, config
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    h.env.UnitClass = function() return "Druid", "DRUID", 11 end
    h.env.GetShapeshiftFormID = function() return 1 end -- Cat Form
    local load = h.world.LoadFile
    function h.world:LoadFile(path, addon, ns)
        if path:match("/MSUF_CP_Controller%.lua$") then
            local builders = ns.CPFactoryShared.Core.builders
            local original = builders.BUILD
            builders.BUILD = function(env)
                CP, config = env.CP, env._cpDB
                build = original(env)
                return build
            end
        end
        return load(self, path, addon, ns)
    end
end })
local bars = h.UF.Config.GetDB().bars
bars.roundedClassResources = true
bars.classPowerShape = "BAR"
bars.classPowerOutline = 2
assert(build and CP and config, "production class resource builder did not load")
config.bars = bars
build.CP_Create(h.env.UIParent)
build.CP_EnsureMainText()
CP.currentMax = 5
local apply = h.core.Require("MSUF_ClassPower_ApplyRoundedSurface", "class resource test")
assert(apply(true), "rounded class resources did not activate")
local outline = assert(CP._msufRCPOutlineHost, "rounded outline was not built")
assert(outline:IsShown() and CP._msufRCPOutlineEdge:IsShown(), "expected visible rounded outline")

local function EffectiveAlpha(frame)
    local alpha = 1
    while frame do
        alpha = alpha * frame:GetAlpha()
        if frame:IsIgnoringParentAlpha() then break end
        frame = frame:GetParent()
    end
    return alpha
end

local function Check(mode, barAlpha, textAlpha, label)
    bars.classPowerCatVisibility = mode
    CP.RefreshDruidFormVisibility(false)
    assert(EffectiveAlpha(CP.druidVisual) == barAlpha, label .. " ignored bar alpha")
    assert(EffectiveAlpha(CP.textFrame) == textAlpha, label .. " ignored text alpha")
    assert(EffectiveAlpha(CP._msufRCPOutlineEdge) == barAlpha, label .. " left the outline at the wrong alpha")
end
Check(1, 1, 1, "show bar and text")
Check(2, 0, 1, "hide bar")
Check(3, 1, 0, "hide text")
Check(4, 0, 0, "hide bar and text")
Check(1, 1, 1, "restore both")
print("PASS " .. flavor .. " Druid class resource form visibility with a rounded outline")

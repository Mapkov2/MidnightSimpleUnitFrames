-- The real optional pet/threat elements must inherit their scene root's band.
local root, flavor = assert(arg[1]), assert(arg[2])
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.MAX_BOSS_FRAMES = 5
    if flavor == "Vanilla" or flavor == "TBC" then
        world.env.GetPetExperience = function() return 30, 100 end
    end
end })
local GF, UF = h.GF, h.core.UF
GF.EnsureDB()
local db = h.core.Require("MSUF_EnsureDB", "preview level sample test")()
db.pet.showPetHappinessIndicator, db.pet.showPetXPBar = true, true
db.target.showThreatIndicator = true
local parent = h.env.CreateFrame("Frame", nil, h.env.UIParent)
parent:SetSize(400, 250)
local owner = GF.NewPreviewScene(parent)
local pet, target = owner:Unit("pet"), owner:Unit("target")
pet.level, target.level = 700, 1100
pet:Show()
target:Show()
owner:Activate()
h:RunTimers()
local frame = pet:Frame()
if h.core.Client.SupportsPetHappiness then
    local cfg = assert(frame.MSUFSpec.status.petHappiness)
    assert(cfg.enabled, "pet happiness control was unavailable")
    local holder = assert(frame.petHappinessIndicatorHolder, "enabled pet scene did not build happiness")
    assert(holder:GetFrameLevel() == 800 + UF.Layers.ClampLayer(cfg.layer, 7) * 32 + 8,
        "pet happiness used a live/global level instead of the pet scene root")
end
if flavor == "Vanilla" or flavor == "TBC" then
    local cfg = assert(frame.MSUFSpec.status.petXP)
    assert(cfg.enabled, "pet XP control was unavailable")
    local holder = assert(frame.petXPBar, "enabled pet scene did not build pet XP")
    assert(holder:GetFrameLevel() == 800 + UF.Layers.ClampLayer(cfg.layer, 7) * 32 + 8,
        "pet XP used a live/global level instead of the pet scene root")
end
local targetFrame = target:Frame()
local cfg = assert(targetFrame.MSUFSpec.status.threat)
assert(cfg.enabled, "threat control was unavailable")
local holder = assert(targetFrame.threatIndicatorHolder, "enabled target scene did not build threat")
assert(holder:GetFrameLevel() == 1200 + UF.Layers.ClampLayer(cfg.layer, 7) * 32 + 8,
    "threat used a live/global level instead of the target scene root")
assert(UF.Layers.ElementLevel(0, 0, 0) == 100, "optional samples changed live levels")
owner:Release()
assert(#h.violations == 0, "optional sample scene wrote protected geometry")
print("PASS optional scene sample levels " .. flavor)

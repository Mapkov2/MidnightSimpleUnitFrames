local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function ReadSource(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

-- Runtime: one texture region follows all classifications at the shared
-- Elite Indicator position and uses Blizzard's current classification atlases.
do
    local World = assert(loadfile(root .. "/tools/tests/unit_scene_world.lua"))()
    local w = World.New(root, arg[2] or "Mainline")
    w:Enable()
    local sample = { name = "Classified Target", class = "MAGE", level = 80, hp = .7, power = .5,
        classification = "elite", reaction = "enemy" }
    local frame = w:LiveFrame("target", sample)
    local texture = assert(frame.eliteIcon)
    local update = assert(w.env.MSUF.UFStatusRuntime.UpdateElite)
    local cases = {
        elite = "nameplates-icon-elite-gold",
        worldboss = "nameplates-icon-elite-gold",
        rareelite = "nameplates-icon-elite-silver",
        rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
    }
    for state, atlas in pairs(cases) do
        sample.classification = state
        w:Model("target", sample)
        update(frame, frame.MSUFSpec.status)
        Check(texture:IsShown(), state .. " classification did not show the shared indicator")
        Check(texture.atlas == atlas, state .. " classification used the wrong atlas")
    end
    Check(frame.eliteIcon == texture, "classification update replaced the shared Elite Indicator region")
    w:Unmodel()
end

-- The menu uses the same native Elite region and live classification snapshot.
do
    local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local w = World.Open(root, arg[2] or "Mainline", { page = "home" })
    local env, Preview = w.env, w.core.UFPreview
    local classification = "elite"
    env.UnitExists = function(unit) return unit == "target" end
    env.UnitName = function() return "Classified Target" end
    env.UnitIsPlayer = function() return false end
    env.UnitClassification = function() return classification end
    env.UnitLevel = function() return 80 end
    env.MSUF_DB.target.showEliteIcon = true
    env.MSUF_DB.target.eliteIconStyle = "BLIZZARD"
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "target" end
    local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
    World.FireVisibilityScripts(box)
    box:Show()
    box.canvas:SetSize(600, 260)
    Preview.selectedStatusId = "elite"
    local cases = {
        elite = "nameplates-icon-elite-gold",
        worldboss = "nameplates-icon-elite-gold",
        rareelite = "nameplates-icon-elite-silver",
        rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
    }
    local texture
    for state, atlas in pairs(cases) do
        classification = state
        Preview.Refresh(box, "SETTINGS")
        local body = box.mock._body
        Check(body == box._unitScene:Frame(), "classification preview bypassed the native scene")
        texture = texture or body.eliteIcon
        Check(body.eliteIcon == texture, "classification preview replaced the shared Elite region")
        Check(texture:IsShown() and texture.atlas == atlas, state .. " preview used the wrong native atlas")
    end
    classification = "normal"
    Preview.Refresh(box, "SETTINGS")
    Check(texture:IsShown() and texture.atlas == "nameplates-icon-elite-gold",
        "selected Elite Indicator preview disappeared instead of using its deterministic fallback")
    Preview.selectedStatusId = "leader"
    Preview.Refresh(box, "SETTINGS")
    Check(not texture:IsShown(), "unselected Elite Indicator ignored normal live classification")
    Preview.statusPreviewMode = "all"
    Preview.Refresh(box, "SETTINGS")
    Check(texture:IsShown(), "Status All lost the Elite Indicator sample")
    if w.core.UF.UnitScene.Normalize("boss") then
        panel._msufGetCurrentKey = function() return "boss" end
        Preview.Refresh(box, "SETTINGS")
        Check(box._unitScene:Sample().classification == "worldboss", "Status All replaced the boss classification")
    end
    box:Hide()
end

local section = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua")
for _, variant in ipairs({ '"ELITE"', '"RAREELITE"', '"RARE"' }) do
    Check(section:find('{ "elite", ' .. variant .. ' }', 1, true),
        variant .. " is missing from the Elite Indicator icon strip")
end
Check(not section:find("rareEliteIconOffset", 1, true) and not section:find("rareIconOffset", 1, true),
    "classification variants introduced separate positions instead of sharing Elite Indicator placement")

print("PASS elite indicator classifications: runtime and preview share one position with Elite/Rare Elite/Rare visuals")

local root, flavor = assert(arg[1]), arg[2] or "Forever"
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, core = world.env, world.core
local inside, hostile = false, true
env.UnitExists = function() return true end
env.UnitIsVisible = function() return true end
env.UnitIsConnected = function() return true end
env.UnitGUID = function() return "PortraitDetailsUnit" end
env.UnitClass = function() return "Mage", "MAGE" end
env.UnitClassification = function() return "elite" end
env.IsInInstance = function() return inside, inside and "party" or "none" end
env.UnitCanAttack = function() return hostile end
env.InCombatLockdown = function() return false end
-- Class portraits use Blizzard's class atlases. The sheet coordinates of an
-- atlas must never reach SetTexCoord: after SetAtlas, texcoords are local to
-- the atlas, so sheet values crop into a corner of the icon.
env.CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49609375, 0, 0.25 } }
env.C_Texture = { GetAtlasInfo = function()
    return { width=80, height=90, leftTexCoord=.1, rightTexCoord=.8, topTexCoord=.2, bottomTexCoord=.9 }
end }
env.UnitCastingInfo = function() end
env.UnitChannelInfo = function() end
env.RAID_CLASS_COLORS = { MAGE = { r = .2, g = .5, b = .8 } }
env.SetPortraitTexture = function(tex, unit) tex:SetTexture("portrait:" .. unit) end
local createFrame, models = env.CreateFrame, 0
env.CreateFrame = function(kind, ...)
    if kind == "PlayerModel" then models = models + 1 end
    return createFrame(kind, ...)
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
env.MSUF_InitProfiles(); env.MSUF_EnsureDB(true)
local UF, conf = core.UF, env.MSUF_DB.player
conf.portraitMode, conf.portraitRender, conf.portraitShape = "LEFT", "2D", "SQUARE"
conf.portraitZoom, conf.portraitSizeOverride = 100, 60
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame:SetSize(240, 44); frame.MSUFUnitKey = "player"
frame.Health = env.CreateFrame("StatusBar", nil, frame); frame.Health:SetSize(240, 44)
frame.hpBar = frame.Health
local portrait = UF.elements.Portrait
local function apply()
    UF.Config.Refresh()
    frame.MSUFSpec = UF.Config.GetSpec("player")
    portrait.Apply(frame, frame.MSUFSpec)
    return frame.MSUFSpec.portrait
end
local function near(a,b) assert(math.abs(a-b)<1e-6, tostring(a).." ~= "..tostring(b)) end
local function UV(tex, l, r, t, b, label)
    local c = tex.texCoord
    assert(c and c[1] == l and c[2] == r and c[3] == t and c[4] == b, label .. ": "
        .. (c and table.concat(c, ",") or "none"))
end
conf.portraitFlip = true
local p = apply()
assert(p.texL > p.texR and frame.portrait.texCoord[1] > frame.portrait.texCoord[2], "2D mirrored")
conf.portraitFlip = false; apply()
assert(frame.portrait.texCoord[1] < frame.portrait.texCoord[2], "2D mirror restored")
-- The whole class icon, never the atlas sheet crop (Warlock icon report).
conf.portraitRender = "CLASS"; apply()
assert(frame.portrait.atlas == "classicon-MAGE", "class portrait uses the class atlas")
UV(frame.portrait, 0, 1, 0, 1, "class icon shows its whole atlas")
conf.portraitFlip = true; apply()
UV(frame.portrait, 1, 0, 0, 1, "class icon mirrors in atlas space")
conf.portraitFlip = false; apply()
UV(frame.portrait, 0, 1, 0, 1, "class mirror restored")
conf.portraitRender = "2D"; p = apply()
assert(frame.portrait.texture == "portrait:player", "2D after class resolves the unit portrait")
UV(frame.portrait, p.texL, p.texR, p.texT, p.texB, "2D after class restores its crop")
conf.portraitRender = "CLASS"; apply()
UV(frame.portrait, 0, 1, 0, 1, "class after 2D drops the 2D crop")
-- The 3D model mode is retired: saved and imported values load as 2D and no
-- native model is ever built.
conf.portraitRender = "3D"
p = apply()
assert(p.render == "2D" and frame.portrait:IsShown(), "a saved 3D portrait renders as 2D")
assert(frame.portrait.texture == "portrait:player", "a saved 3D portrait shows the unit portrait")
local saved = { player = { portraitRender = "3D" }, target = { portraitRender = "CLASS" } }
env.MSUF_NormalizePortraitRenderDB(saved)
assert(saved.player.portraitRender == "2D" and saved.target.portraitRender == "CLASS", "3D profile values load as 2D")
do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    local values = assert(source:match('local PORTRAIT_RENDER = VTP "([^"]*)"'), "portrait render values moved")
    assert(values == "2D=2D portrait|CLASS=Class portrait", "the menu offers 2D and class portraits only: " .. values)
end
conf.portraitRender = "2D"
conf.portraitInnerShadow = 65; apply()
assert(frame.MSUFPortraitHolder.innerShadow:IsShown(), "square shadow")
near(frame.MSUFPortraitHolder.innerShadow.vertexColor[4], .65)
conf.portraitShape = "CIRCLE"; apply()
assert(not frame.MSUFPortraitHolder.innerShadow:IsShown(), "unsupported shape clears shadow")
conf.portraitEdgeSoftness = 20
assert(apply().edgeSoftnessLevel == 10, "a 2D portrait keeps its edge softness")
conf.portraitEdgeSoftness = 0
conf.portraitRender, conf.portraitShape = "2D", "BLIZZARD"
conf.portraitBlizzardElite = true
conf.portraitDragonScale, conf.portraitDragonX, conf.portraitDragonY = 180, 17, -9
-- Retired class tint in old/imported profiles must leave the native art unchanged.
assert(conf.portraitDragonClassColor == nil, "retired dragon tint is not a default")
conf.portraitDragonFlip, conf.portraitDragonClassColor = true, true
conf.portraitDragonLayer, conf.portraitDragonLevel = "ARTWORK", 5
p = apply()
local holder, dragon = frame.MSUFPortraitHolder, frame.MSUFPortraitHolder.blizzElite
assert(dragon:IsShown(), "elite dragon shown")
near(holder.dragonFrame:GetFrameLevel(), holder:GetFrameLevel()+5)
local anchor, _, relative, x, y = dragon:GetPoint(1)
assert(anchor == "TOPLEFT" and relative == "TOPLEFT", "mirrored anchor")
near(x, -15*holder:GetWidth()/58*1.8+17); near(y, 11*holder:GetHeight()/58*1.8-9)
assert(p.dragonClassColor == nil, "retired dragon tint is not compiled")
local function NativeDragonColor(texture)
    for component = 1, 4 do near(texture.vertexColor[component], 1) end
end
NativeDragonColor(dragon)
-- SetAtlas owns the sheet crop; local UVs must cover the whole dragon.
local function FullDragon(tex, flip)
    near(tex.texCoord[1], flip and 1 or 0); near(tex.texCoord[2], flip and 0 or 1)
    near(tex.texCoord[3], 0); near(tex.texCoord[4], 1)
end
FullDragon(dragon, true)
for _, classification in ipairs({ "elite", "rare", "rareelite", "worldboss" }) do
    env.UnitClassification = function() return classification end
    for _, flip in ipairs({ false, true, false }) do
        conf.portraitDragonFlip = flip; p = apply()
        assert(dragon:IsShown(), classification .. " dragon missing")
        FullDragon(dragon, flip)
        NativeDragonColor(dragon)
        local previewHolder = env.CreateFrame("Frame", nil, env.UIParent)
        previewHolder:SetSize(60, 60)
        portrait.PaintClassification(previewHolder, true, classification, 60, 60, previewHolder, p, "player")
        assert(previewHolder.blizzElite:IsShown(), classification .. " preview dragon missing")
        FullDragon(previewHolder.blizzElite, flip)
        NativeDragonColor(previewHolder.blizzElite)
    end
end
env.UnitClassification = function() return "elite" end
conf.portraitDragonFlip = true; p = apply()
assert(dragon.layer == "ARTWORK" or dragon.drawLayer == "ARTWORK", "dragon draw layer")
assert(dragon:GetParent() == holder.dragonFrame, "a level above the ring must give the dragon its own frame")
-- The draw layer orders the dragon on the frame it shares: the default level is
-- the ring's frame, level 0 the portrait image's frame.
local ring = holder.blizzRing or holder.artBorder
assert(ring and ring:GetParent() == holder.border, "the gold ring lives on the portrait border frame")
conf.portraitDragonLayer, conf.portraitDragonLevel = "OVERLAY", 1
apply()
local ringLayer, ringSub = ring:GetDrawLayer()
local dragonLayer, dragonSub = dragon:GetDrawLayer()
assert(dragon:GetParent() == holder.border, "the default dragon level must share the ring's frame")
assert(dragonLayer == ringLayer and dragonSub > ringSub, "OVERLAY must draw the dragon in front of the ring")
conf.portraitDragonLayer = "ARTWORK"; apply()
assert(dragon:GetParent() == holder.border and dragon:GetDrawLayer() == "ARTWORK" and ringLayer == "OVERLAY",
    "ARTWORK must keep the dragon behind the ring on the ring's frame")
conf.portraitDragonLevel = 0; apply()
assert(dragon:GetParent() == holder and frame.portrait:GetParent() == holder,
    "level 0 must put the dragon on the portrait image's frame")
conf.portraitDragonLevel = 5; apply()
assert(dragon:GetParent() == holder.dragonFrame, "the dragon must move back to its own frame")
-- Unchanged repaints neither re-level the dragon frame nor ask for its parent.
local relevels, parentReads, atlasWrites, uvWrites = 0, 0, 0, 0
local dragonFrame = holder.dragonFrame
local setLevel, getParent = dragonFrame.SetFrameLevel, dragon.GetParent
local setAtlas, setUV = dragon.SetAtlas, dragon.SetTexCoord
dragon.SetAtlas = function(self, ...) atlasWrites = atlasWrites + 1; return setAtlas(self, ...) end
dragon.SetTexCoord = function(self, ...) uvWrites = uvWrites + 1; return setUV(self, ...) end
dragonFrame.SetFrameLevel = function(self, ...) relevels = relevels + 1; return setLevel(self, ...) end
dragon.GetParent = function(self) parentReads = parentReads + 1; return getParent(self) end
for _ = 1, 3 do portrait.Update(frame, "UNIT_CLASSIFICATION_CHANGED", "player") end
assert(dragon:IsShown(), "classification repaints keep the dragon")
local repaintParentReads = parentReads
dragonFrame.SetFrameLevel, dragon.GetParent = setLevel, getParent
dragon.SetAtlas, dragon.SetTexCoord = setAtlas, setUV
assert(atlasWrites == 0 and uvWrites == 0, "unchanged dragon repaint rewrote its atlas or UVs")
assert(relevels == 0 and repaintParentReads == 0, "an unchanged dragon repaint re-levelled or re-parented the dragon")
conf.portraitDragonLayer = "ARTWORK"
conf.portraitDragonInInstances = false; inside = true; apply()
assert(not dragon:IsShown(), "hostile instance rule")
hostile = false; portrait.Update(frame, "ZONE_CHANGED_NEW_AREA", "player")
assert(dragon:IsShown(), "friendly classification preserved")
hostile = true; inside = false; portrait.Update(frame, "ZONE_CHANGED_NEW_AREA", "player")
assert(dragon:IsShown(), "open world restoration")
-- Unitless events: details only extend the per-unit set, and only when they
-- need it. The target keeps its party-member events in every mode.
local function Names(list) return table.concat(list, ",") end
local tconf = env.MSUF_DB.target
tconf.portraitMode, tconf.portraitRender, tconf.portraitShape = "LEFT", "2D", "SQUARE"
tconf.portraitBlizzardElite, tconf.portraitDragonInInstances = false, nil
local tframe = env.CreateFrame("Frame", nil, env.UIParent)
tframe.MSUFUnitKey = "target"
local function TargetEvents()
    UF.Config.Refresh()
    tframe.MSUFSpec = UF.Config.GetSpec("target")
    return portrait.GetUnitlessEvents(tframe, tframe.MSUFSpec)
end
local TARGET_BASE = "PORTRAITS_UPDATED,PARTY_MEMBER_ENABLE,PARTY_MEMBER_DISABLE"
assert(Names(TargetEvents()) == TARGET_BASE, "2D target: " .. Names(TargetEvents()))
tconf.portraitShape, tconf.portraitBlizzardElite = "BLIZZARD", true
assert(Names(TargetEvents()) == TARGET_BASE, "dragons shown everywhere need no zone events")
tconf.portraitDragonInInstances = false
local zoned = TargetEvents()
assert(Names(zoned) == TARGET_BASE .. ",PLAYER_ENTERING_WORLD,ZONE_CHANGED_NEW_AREA",
    "the instance rule needs the zone events: " .. Names(zoned))
assert(TargetEvents() == zoned, "a union must be built once and reused")
tconf.portraitShape = "CIRCLE"
assert(Names(TargetEvents()) == TARGET_BASE, "an elite flag without the Blizzard shape must add nothing")
tconf.portraitRender = "3D"
assert(Names(TargetEvents()) == TARGET_BASE, "a saved 3D target adds no combat edges")
tconf.portraitRender, tconf.portraitShape, tconf.portraitBlizzardElite = "CLASS", "BLIZZARD", true
assert(Names(TargetEvents()) == "PORTRAITS_UPDATED,PLAYER_ENTERING_WORLD,ZONE_CHANGED_NEW_AREA",
    "a class portrait with the instance rule adds only the zone events")
-- Fixed artwork must not sample unit identity or subscribe to classification/zone changes.
assert(conf.portraitDragonArtwork == false, "fixed artwork is opt-in")
conf.portraitDragonArtwork, conf.portraitDragonInInstances = true, false
inside, hostile = true, true
local queries = 0
local oldClassification, oldInstance, oldAttack = env.UnitClassification, env.IsInInstance, env.UnitCanAttack
local function NoIdentity() queries = queries + 1; return "normal" end
env.UnitClassification, env.IsInInstance, env.UnitCanAttack = NoIdentity, NoIdentity, NoIdentity
for _, shape in ipairs({ "BLIZZARD", "CIRCLE", "SQUARE", "ROUNDED", "DIAMOND" }) do
    conf.portraitRender, conf.portraitShape = "2D", shape
    for _, native in ipairs({ false, true }) do
        conf.portraitBlizzardElite = native
        p = apply()
        assert(p.dragonArtwork == true and dragon:IsShown(), "player artwork on " .. shape)
        assert(dragon.atlas == "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", "fixed gold artwork")
        for _, event in ipairs(portrait.GetEvents(frame, frame.MSUFSpec)) do
            assert(event ~= "UNIT_CLASSIFICATION_CHANGED", "artwork adds no classification subscription")
        end
        local events = Names(portrait.GetUnitlessEvents(frame, frame.MSUFSpec))
        assert(not events:find("ZONE_CHANGED", 1, true), "artwork adds no zone subscription")
        portrait.Update(frame, "MSUF_FORCE_UPDATE", "player")
        assert(dragon:IsShown(), "ordinary portrait update retains artwork")
        local preview = env.CreateFrame("Frame", nil, env.UIParent)
        portrait.PaintClassification(preview, false, "normal", 60, 60, preview, p, "player")
        assert(preview.blizzElite:IsShown() and preview.blizzElite.atlas == dragon.atlas, "shared fixed-art painter")
        NativeDragonColor(preview.blizzElite)
    end
end
assert(queries == 0, "fixed artwork must not query classification, instance or hostility")
env.UnitClassification, env.IsInInstance, env.UnitCanAttack = oldClassification, oldInstance, oldAttack
conf.portraitDragonArtwork, conf.portraitDragonInInstances = false, true
conf.portraitRender, conf.portraitShape, conf.portraitBlizzardElite = "2D", "BLIZZARD", true
env.UnitClassification = function() return "rare" end
apply()
assert(dragon.atlas == "ui-hud-unitframe-target-portraiton-boss-rare-silver", "off restores native classification")
env.UnitClassification = function() return "normal" end
portrait.Update(frame, "UNIT_CLASSIFICATION_CHANGED", "player")
assert(not dragon:IsShown(), "normal unit has no native dragon when artwork is off")
conf.portraitDragonArtwork, conf.portraitMode = true, "OFF"
apply()
assert(not holder:IsShown(), "artwork follows portrait visibility")
portrait.Disable(frame)
assert(not holder:IsShown(), "disable cleanup")
assert(models == 0, "portraits must never build a native PlayerModel")
print("portrait_details_smoke: OK ("..flavor..")")

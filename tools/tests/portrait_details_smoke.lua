local root, flavor = assert(arg[1]), arg[2] or "Forever"
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, core = world.env, world.core
local restricted, inside, hostile, casting, visible = false, false, true, false, true
env.UnitExists = function() return true end
env.UnitIsVisible = function() return visible end
env.UnitIsConnected = function() return true end
local guidReads, predicateReads = 0, 0
env.UnitGUID = function() guidReads = guidReads + 1; return "PortraitDetailsUnit" end
env.UnitClass = function() return "Mage", "MAGE" end
env.UnitClassification = function() return "elite" end
env.IsInInstance = function() return inside, inside and "party" or "none" end
env.UnitCanAttack = function() return hostile end
env.InCombatLockdown = function() return false end
env.C_Secrets = { ShouldUnitIdentityBeSecret = function()
    predicateReads = predicateReads + 1
    return restricted
end }
env.C_Texture = { GetAtlasInfo = function()
    return { width=80, height=90, leftTexCoord=.1, rightTexCoord=.8, topTexCoord=.2, bottomTexCoord=.9 }
end }
env.UnitCastingInfo = function() if casting then return "Example", nil, 1234 end end
env.UnitChannelInfo = function() end
env.RAID_CLASS_COLORS = { MAGE = { r = .2, g = .5, b = .8 } }
local setPortrait = 0
env.SetPortraitTexture = function(tex, unit)
    setPortrait = setPortrait + 1
    tex:SetTexture("portrait:" .. unit)
end
local createFrame, models = env.CreateFrame, {}
env.CreateFrame = function(kind, ...)
    local frame = createFrame(kind, ...)
    if kind == "PlayerModel" then
        models[#models+1] = frame
        frame.SetUnit = function(self, unit) self.unit = unit; self.assigns = (self.assigns or 0)+1 end
        frame.SetPortraitZoom = function(self, value) self.portraitZoom = value end
        frame.SetCamDistanceScale = function(self, value) self.distanceScale = value end
        frame.ClearModel = function(self) self.clears = (self.clears or 0)+1 end
        local hide = frame.Hide
        frame.Hide = function(self)
            local wasShown = self:IsShown()
            hide(self)
            local handler = self:GetScript("OnHide")
            if wasShown and handler then handler(self) end
        end
    end
    return frame
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
conf.portraitFlip = true
local p = apply()
assert(p.texL > p.texR and frame.portrait.texCoord[1] > frame.portrait.texCoord[2], "2D mirrored")
conf.portraitFlip = false; apply()
assert(frame.portrait.texCoord[1] < frame.portrait.texCoord[2], "2D mirror restored")
conf.portraitRender = "CLASS"; conf.portraitFlip = true; apply()
assert(frame.portrait.texCoord[1] > frame.portrait.texCoord[2], "class mirrored")
conf.portraitFlip = false; apply()
assert(frame.portrait.texCoord[1] < frame.portrait.texCoord[2], "class mirror restored")
conf.portraitInnerShadow = 65; apply()
assert(frame.MSUFPortraitHolder.innerShadow:IsShown(), "square shadow")
near(frame.MSUFPortraitHolder.innerShadow.vertexColor[4], .65)
conf.portraitShape = "CIRCLE"; apply()
assert(not frame.MSUFPortraitHolder.innerShadow:IsShown(), "unsupported shape clears shadow")
conf.portraitEdgeSoftness = 20
assert(apply().edgeSoftnessLevel == 10, "a 2D portrait keeps its edge softness")
conf.portraitRender = "3D"; conf.portraitZoom = 300
p = apply()
assert(p.render == "3D" and p.shape == "SQUARE", "3D native rectangle")
-- The model itself is a native rectangle; the softness feathers the 2D
-- portrait that stands in while the unit's identity is private.
assert(p.edgeSoftnessLevel == 10, "a 3D portrait lost the edge softness of its 2D stand-in")
conf.portraitEdgeSoftness = 0
-- The menu matches the compile: the softness control stays on for 3D.
do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local gate = assert(source:match("{ controls = edgeSoftness, on = function%(conf%)\n(.-)\n        end },"),
        "the edge softness control gate moved")
    assert(not gate:find("3D", 1, true), "the edge softness control must stay available for 3D portraits")
end
p = apply()
local model = assert(frame.MSUFPortraitModel)
assert(model:IsShown() and not frame.portrait:IsShown(), "model owns image")
near(model.distanceScale, 1/3)
local assigns = model.assigns
apply(); assert(model.assigns == assigns, "unchanged model not rebound")
assert(not frame.portrait:IsShown(), "cached 3D does not show fallback texture")
restricted = true
portrait.Update(frame, "PLAYER_REGEN_DISABLED", "player")
assert(not model:IsShown() and frame.portrait:IsShown(), "restricted native 2D fallback")
assert(model.assigns == assigns and setPortrait > 0, "no restricted SetUnit")
restricted = false
portrait.Update(frame, "PLAYER_REGEN_ENABLED", "player")
assert(model:IsShown(), "identity unlock restores model")
-- A combat edge with an unchanged secrecy answer reads that one predicate and
-- nothing else: no rebind, no GUID, no native portrait.
local edgeAssigns, edgeGuids, edgePortraits, edgePredicates = model.assigns, guidReads, setPortrait, predicateReads
for _ = 1, 3 do
    portrait.Update(frame, "PLAYER_REGEN_DISABLED")
    portrait.Update(frame, "PLAYER_REGEN_ENABLED")
end
assert(model.assigns == edgeAssigns, "an unchanged combat edge rebound the 3D model")
assert(guidReads == edgeGuids and setPortrait == edgePortraits, "an unchanged combat edge read the portrait identity")
assert(predicateReads - edgePredicates == 6, "each combat edge must read the secrecy predicate exactly once")
assert(model:IsShown() and not frame.portrait:IsShown(), "the model keeps the image across combat edges")
conf.portraitCastSpellIcon = true; casting = true; apply()
assert(not model:IsShown() and frame.MSUFPortraitCastIcon:IsShown(), "cast replaces model")
casting = false; portrait.Update(frame, "UNIT_SPELLCAST_STOP", "player")
assert(model:IsShown() and not frame.MSUFPortraitCastIcon:IsShown(), "model restored after cast")
-- The cast icon only covers the model: its binding survives every cast.
local castAssigns, castClears = model.assigns, model.clears or 0
for _ = 1, 5 do
    casting = true; portrait.Update(frame, "UNIT_SPELLCAST_START", "player")
    assert(not model:IsShown() and frame.MSUFPortraitCastIcon:IsShown() and not frame.portrait:IsShown(),
        "a cast must show its icon over a hidden model")
    casting = false; portrait.Update(frame, "UNIT_SPELLCAST_STOP", "player")
    assert(model:IsShown() and not frame.portrait:IsShown() and not frame.MSUFPortraitCastIcon:IsShown(),
        "the cast end must show the same model again")
end
assert(model.assigns == castAssigns and (model.clears or 0) == castClears, "a cast cleared or rebound the 3D model")
-- A cast that ends after the identity turned secret keeps the native 2D image.
casting = true; portrait.Update(frame, "UNIT_SPELLCAST_START", "player")
restricted = true
local restrictedPortraits = setPortrait
casting = false; portrait.Update(frame, "UNIT_SPELLCAST_STOP", "player")
assert(not model:IsShown() and frame.portrait:IsShown() and setPortrait > restrictedPortraits,
    "a secret identity at the cast end must fall back to the 2D portrait")
assert(model.assigns == castAssigns, "a secret identity must never reach SetUnit")
restricted = false
portrait.Update(frame, "PLAYER_REGEN_ENABLED", "player")
assert(model:IsShown() and not frame.portrait:IsShown(), "the identity unlock after a cast restores the model")
-- Hiding the model for good (Disable, 2D) still drops a suspended binding.
casting = true; portrait.Update(frame, "UNIT_SPELLCAST_START", "player")
local suspendedClears = model.clears or 0
core.PortraitDetails.HideModel(frame)
assert((model.clears or 0) == suspendedClears + 1 and not model._msufReady, "HideModel must clear a model a cast suspended")
casting = false; portrait.Update(frame, "UNIT_SPELLCAST_STOP", "player")
assert(model:IsShown() and model.assigns == castAssigns + 2, "a cleared model is bound again once the cast ends")
conf.portraitRender, conf.portraitShape = "2D", "BLIZZARD"
conf.portraitBlizzardElite = true
conf.portraitDragonScale, conf.portraitDragonX, conf.portraitDragonY = 180, 17, -9
conf.portraitDragonFlip, conf.portraitDragonClassColor = true, true
conf.portraitDragonLayer, conf.portraitDragonLevel = "ARTWORK", 5
p = apply()
local holder, dragon = frame.MSUFPortraitHolder, frame.MSUFPortraitHolder.blizzElite
assert(dragon:IsShown() and not model:IsShown(), "switch back clears 3D")
near(holder.dragonFrame:GetFrameLevel(), holder:GetFrameLevel()+5)
local anchor, _, relative, x, y = dragon:GetPoint(1)
assert(anchor == "TOPLEFT" and relative == "TOPLEFT", "mirrored anchor")
near(x, -15*holder:GetWidth()/58*1.8+17); near(y, 11*holder:GetHeight()/58*1.8-9)
near(dragon.vertexColor[1], .2); near(dragon.vertexColor[2], .5)
assert(dragon.texCoord[1] > dragon.texCoord[2], "dragon atlas mirror")
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
local relevels, parentReads = 0, 0
local dragonFrame = holder.dragonFrame
local setLevel, getParent = dragonFrame.SetFrameLevel, dragon.GetParent
dragonFrame.SetFrameLevel = function(self, ...) relevels = relevels + 1; return setLevel(self, ...) end
dragon.GetParent = function(self) parentReads = parentReads + 1; return getParent(self) end
for _ = 1, 3 do portrait.Update(frame, "UNIT_CLASSIFICATION_CHANGED", "player") end
assert(dragon:IsShown(), "classification repaints keep the dragon")
local repaintParentReads = parentReads
dragonFrame.SetFrameLevel, dragon.GetParent = setLevel, getParent
assert(relevels == 0 and repaintParentReads == 0, "an unchanged dragon repaint re-levelled or re-parented the dragon")
conf.portraitDragonLayer = "ARTWORK"
conf.portraitDragonInInstances = false; inside = true; apply()
assert(not dragon:IsShown(), "hostile instance rule")
hostile = false; portrait.Update(frame, "ZONE_CHANGED_NEW_AREA", "player")
assert(dragon:IsShown(), "friendly classification preserved")
hostile = true; inside = false; portrait.Update(frame, "ZONE_CHANGED_NEW_AREA", "player")
assert(dragon:IsShown(), "open world restoration")
local preview = env.CreateFrame("Frame", nil, env.UIParent)
preview.tex = preview:CreateTexture()
local previewSpec = { render="3D", shape="SQUARE", zoom=300 }
core.PortraitDetails.ApplyPreview(preview, previewSpec, "player")
local previewModel = preview._msufDetailsPreviewOwner.MSUFPortraitModel
assert(previewModel:IsShown(), "preview model created")
local previewAssigns = previewModel.assigns
core.PortraitDetails.ApplyPreview(preview, previewSpec, "player")
assert(previewModel.assigns == previewAssigns, "preview cache avoids native rebind")
restricted = true
core.PortraitDetails.ApplyPreview(preview, previewSpec, "player")
assert(not previewModel:IsShown(), "preview cache respects restricted identity")
restricted = false
core.PortraitDetails.ApplyPreview(preview, previewSpec, "player")
visible = false
core.PortraitDetails.ApplyPreview(preview, previewSpec, "player")
assert(not previewModel:IsShown(), "preview cache respects invisible unit")
visible = true
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
assert(Names(TargetEvents()) == TARGET_BASE .. ",PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED",
    "a 3D target adds only the combat edges")
tconf.portraitRender, tconf.portraitShape, tconf.portraitBlizzardElite = "CLASS", "BLIZZARD", true
assert(Names(TargetEvents()) == "PORTRAITS_UPDATED,PLAYER_ENTERING_WORLD,ZONE_CHANGED_NEW_AREA",
    "a class portrait with the instance rule adds only the zone events")
conf.portraitRender, conf.portraitShape = "3D", "SQUARE"
UF.Config.Refresh()
local playerSpec = UF.Config.GetSpec("player")
assert(Names(portrait.GetUnitlessEvents(frame, playerSpec)) == "PORTRAITS_UPDATED,PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED",
    "a 3D player adds only the combat edges")
conf.portraitRender, conf.portraitShape = "2D", "BLIZZARD"
apply()
portrait.Disable(frame)
assert(not holder:IsShown() and not model:IsShown(), "disable cleanup")
print("portrait_details_smoke: OK ("..flavor..")")

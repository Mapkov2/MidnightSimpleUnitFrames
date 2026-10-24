-- Icon skins for painters outside MSUF's aura runtime: the interface
-- MSUF_HostAPI.GetIconSkins() hands out (Auras3/MSUF_Auras3_IconSkins_Host.lua).
--
-- Runs the real BorderStyles, IconShape, IconSkins, catalog, host interface and
-- Runtime/MSUF_HostAPI.lua on widget stubs. Owners and anchors raise on any
-- field write: the interface keeps its state in side tables. Checks:
--   1. MSUF_HostAPI.GetIconSkins() hands out the version 1 interface, and nil
--      on a client that does not load it (Classic);
--   2. Compile: DEFAULT follows the default skin and look, an own id wins,
--      CUSTOM and unknown ids give nil, and so does a skin made for another
--      icon shape than the caller's (square unless it names one); signatures
--      follow the look;
--   3. Paint lays every layer out around the anchor (the region the icon
--      fills), never around the owner, as textures of the owner on ARTWORK 5-7
--      and OVERLAY -1; a repaint of the same look and size makes no widget
--      call; nil hides; it paints with InCombatLockdown() true; a clipped
--      paint masks every layer with one mask over the anchor, also the layers
--      a later skin adds, and unclipped takes it off; ShapeOf answers the
--      shape a pick matches as the Icon Skins page does;
--   4. combat parity: a default edited in combat (the page writes through
--      Skins.WriteDefault, which freezes it) compiles to the old look for the
--      whole fight, also for a consumer that compiles for the first time then;
--      the combat end tells the listeners ("combat") and releases the new look;
--   5. notifications: a shared aura apply that changed the default tells every
--      listener once ("apply"); one that changed nothing, or only other aura
--      settings, tells nobody; a raising listener is reported and the next
--      still runs; Unsubscribe stops one;
--   6. MSUF core calls the interface from the shared aura apply (after its
--      combat refusal and the generation bump) and from the profile apply;
--   7. cost: exact caps for Compile, an unchanged repaint and a notification
--      that changed nothing (VM instructions, widget calls, KB);
--   8. the interface file registers no events, hooks, timers, scripts or
--      frames;
--   9. shapes (ApplyShape, ShapeArt): MSUF's shape media on a consumer's
--      textures and swipes with one mask of the owner over the anchor, no
--      field written on any of them, a cooldown's countdown text (no
--      AddMaskTexture) left alone, a repeat writes nothing and a cooldown or
--      texture made later costs only its own writes, a new shape re-skins
--      the swipes, square again takes every mask off, and a square icon that
--      was never shaped writes nothing.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.UnitAffectingCombat = function() return inCombat end

local calls = 0
local childrenOf = setmetatable({}, { __mode = "k" })
local Region = {}
Region.__index = Region
local function Count() calls = calls + 1 end
local function Point(self, point, rel, relPoint, x, y)
    Count()
    self.points = self.points or {}
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region:SetPoint(point, rel, relPoint, x, y) Point(self, point, rel, relPoint, x, y) end
function Region:SetAllPoints(rel) Point(self, "ALL", rel) end
function Region:ClearAllPoints() Count(); self.points = {} end
for _, name in ipairs({ "SetTexture", "SetAtlas", "SetTexCoord", "SetSize", "SetWidth", "SetHeight", "SetBlendMode" }) do
    Region[name] = Count
end
function Region:SetDrawLayer(layer, sublevel) Count(); self.layer, self.sublevel = layer, sublevel end
-- Texture paths are kept on our own regions (a guarded frame raises on it).
function Region:SetTexture(path) Count(); self.path = path end
function Region:SetAtlas(atlas) Count(); self.path = atlas end
function Region:SetVertexColor(r, g, b, a) Count(); self.color = { r, g, b, a } end
function Region:Show() Count(); self.shown = true end
function Region:Hide() Count(); self.shown = false end
function Region:CreateTexture(_, layer, _, sublevel)
    Count()
    local texture = setmetatable({ layer = layer, sublevel = sublevel }, Region)
    local list = childrenOf[self] or {}
    childrenOf[self] = list
    list[#list + 1] = texture
    return texture
end
local maskOf = setmetatable({}, { __mode = "k" })
local swipeOf = setmetatable({}, { __mode = "k" })
local regionsOf = setmetatable({}, { __mode = "k" })
function Region:CreateMaskTexture()
    Count()
    local mask = setmetatable({ kind = "MaskTexture" }, Region)
    local list = childrenOf[self] or {}
    childrenOf[self] = list
    list[#list + 1] = mask
    return mask
end
function Region:AddMaskTexture(mask) Count(); maskOf[self] = mask end
function Region:RemoveMaskTexture(mask)
    Count()
    if maskOf[self] == mask then maskOf[self] = nil end
end
function Region:SetSwipeTexture(path) Count(); swipeOf[self] = path end
function Region:SetDesaturated() Count() end
function Region:GetNumRegions() return #(regionsOf[self] or {}) end
function Region:GetRegions() return unpack(regionsOf[self] or {}) end
local framesCreated = 0
_G.CreateFrame = function()
    framesCreated = framesCreated + 1
    return setmetatable({}, Region)
end
-- A frame or region the interface must never write a field on.
local Guarded = { __index = Region, __newindex = function(_, key) error("field written on a caller's frame: " .. tostring(key), 2) end }
local function GuardedFrame() return setmetatable({}, Guarded) end
-- A cooldown's countdown FontString: no AddMaskTexture (Blizzard's API docs).
local TextGuard = { __index = { SetText = Count }, __newindex = Guarded.__newindex }
local function GuardedText() return setmetatable({}, TextGuard) end

-- The aura database the interface reads (A3.EnsureDB) and the generation the
-- runtime bumps on every apply (A3.BumpRuntimeConfig).
local shared = { iconSkinDefault = { styleSkin = "SHADOW1" }, appearanceIconStyles = {} }
local busHandlers = {}
local reports = {}
local function NewNamespace()
    local A3 = { _runtimeConfigGen = 1 }
    function A3.EnsureDB() return {}, shared end
    function A3.BumpRuntimeConfig() A3._runtimeConfigGen = A3._runtimeConfigGen + 1 end
    local namespace = { MSUF_Auras3 = A3, Util = { InCombat = function() return inCombat end } }
    local providers = {
        MSUF_PixelLayoutRegion = function(region) return region end,
        MSUF_EventBus_Register = function(event, key, fn)
            busHandlers[event] = busHandlers[event] or {}
            busHandlers[event][key] = fn
        end,
        MSUF_EventBus_Unregister = function(event, key)
            if busHandlers[event] then busHandlers[event][key] = nil end
        end,
        -- Runtime/MSUF_BorderStyles.lua binds the shared-media and file-asset owners at load.
        -- This harness has no LibSharedMedia and no file-asset API: no library, and a file
        -- the client cannot vouch for stays unknown (not invalid).
        MSUF_GetSharedMedia = function() return nil end,
        MSUF_IsKnownFileAsset = function() return nil end,
    }
    function namespace.Require(name) return assert(providers[name], "unexpected dependency " .. tostring(name)) end
    function namespace.RunHostAPIStep(label, step, ...)
        local ok, result = pcall(step, ...)
        if ok then return true, result end
        reports[#reports + 1] = tostring(label) .. ": " .. tostring(result)
        return false
    end
    function namespace.ExportPublic(name, value)
        namespace.exported = namespace.exported or {}
        namespace.exported[name] = value
    end
    return namespace
end
local function Load(namespace, path)
    assert(loadfile(ADDON .. path))("MidnightSimpleUnitFrames", namespace)
end
local CORE = { "Runtime/MSUF_BorderStyles.lua", "Auras3/MSUF_Auras3_IconShape.lua", "Auras3/MSUF_Auras3_IconSkins.lua",
    "Auras3/MSUF_Auras3_IconSkins_Catalog.lua" }

-- 1. The host API ---------------------------------------------------------------
local MSUF = NewNamespace()
for _, path in ipairs(CORE) do Load(MSUF, path) end
Load(MSUF, "Auras3/MSUF_Auras3_IconSkins_Host.lua")
Load(MSUF, "Runtime/MSUF_HostAPI.lua")
local HostAPI = MSUF.exported and MSUF.exported.MSUF_HostAPI
Check(HostAPI and HostAPI.version == 1, "MSUF_HostAPI must stay version 1 (the icon skins are additive)")
Check(type(HostAPI.GetIconSkins) == "function", "MSUF_HostAPI.GetIconSkins is missing")
local Host = HostAPI.GetIconSkins()
Check(Host and Host.version == 1, "GetIconSkins must hand out the version 1 interface")
for _, name in ipairs({ "Compile", "Paint", "ShapeOf", "Outset", "Subscribe", "Unsubscribe", "ApplyShape", "ShapeArt" }) do
    Check(type(Host[name]) == "function", "the icon skin interface lacks " .. name)
end
Check(Host.DEFAULT == "DEFAULT" and Host.CUSTOM == "CUSTOM", "the interface must name DEFAULT and CUSTOM")
local Skins = MSUF.MSUF_Auras3.IconSkins
local Shape = MSUF.MSUF_Auras3.IconShape
do
    local classic = NewNamespace()
    for _, path in ipairs(CORE) do Load(classic, path) end
    Load(classic, "Runtime/MSUF_HostAPI.lua")
    Check(classic.exported.MSUF_HostAPI.GetIconSkins() == nil, "without the interface file GetIconSkins must answer nil")
    -- The engine's own notification stays callable there (profile apply, combat end).
    classic.MSUF_Auras3.IconSkins.NotifyChanged("profile")
end

-- 2. Compile --------------------------------------------------------------------
local look = Host.Compile("DEFAULT")
Check(look and look.skin and look.skin.id == "SHADOW1", "DEFAULT must compile the default skin")
Check(type(look.signature) == "string" and look.signature == look.skin.signature, "a look carries its signature")
Check(Host.Compile(nil).signature == look.signature, "nil must mean Like default")
Check(Host.Compile("DARK2").skin.id == "DARK2", "an own skin id must win over the default")
Check(Host.Compile("CUSTOM") == nil, "CUSTOM is no skin")
Check(Host.Compile("NO_SUCH_SKIN") == nil and Host.Compile(7) == nil, "an unknown id is no skin")
local round
for _, item in ipairs(Skins.List()) do
    if item.value ~= "CUSTOM" and Skins.ShapeOf(item.value) ~= "RECTANGLE" then round = item.value break end
end
Check(round ~= nil, "the catalog lost its shaped skins")
Check(Host.Compile(round) == nil, "a skin made for another icon shape must not compile for square icons")
local roundShape = Skins.ShapeOf(round)
local roundLook = Host.Compile(round, roundShape)
Check(roundLook and roundLook.skin.id == round, "a caller drawing that shape must get the skin")
Check(Host.Compile("SHADOW1", roundShape) == nil, "a square skin must not compile for a shaped icon")
do
    local o = GuardedFrame()
    Check(Host.Paint(o, roundLook, 36, 36) == true and #(childrenOf[o] or {}) > 0, "a shaped look must paint")
end
shared.iconSkinDefault.styleSkin = round
Check(Host.Compile("DEFAULT") == nil, "a shaped default must leave square icons with their own look")
Check(Host.ShapeOf("DEFAULT") == roundShape and Host.ShapeOf(nil) == roundShape, "Like default: the default skin's shape")
shared.iconSkinDefault.styleSkin = "CUSTOM"
Check(Host.ShapeOf("DEFAULT") == nil and Host.ShapeOf("CUSTOM") == nil, "no skin has no shape to match")
shared.iconSkinDefault.styleSkin = "SHADOW1"
Check(Host.ShapeOf("DEFAULT") == "RECTANGLE" and Host.ShapeOf(round) == roundShape, "a skin's own shape")
Check(select(2, Host.ShapeOf("DEFAULT")) == "SHADOW1" and select(2, Host.ShapeOf(round)) == round,
    "ShapeOf names the skin it resolved")
-- Outset: the engine's frame reach of the look's skin (Skins.Outset), 0 for none.
do
    local framed = Host.Compile("DARK3")
    local x, y = Host.Outset(framed, 36, 36)
    local ex, ey = Skins.Outset(framed.skin, 36, 36)
    Check(x == ex and y == ey, "Outset must be the engine's outset of the look's skin")
    x, y = Host.Outset(nil, 36, 36)
    Check(x == 0 and y == 0, "no look reaches nowhere")
end
shared.iconSkinDefault.styleSkinGlossColor = { 1, 1, 1, 0.5 }
Check(Host.Compile("DEFAULT").signature ~= look.signature, "the default's look must reach the signature")
Check(Host.Compile("DARK2").skin.ga == 0.5, "an own skin must be drawn with the default's look")
shared.iconSkinDefault.styleSkinGlossColor = nil
Check(Host.Compile("DEFAULT").signature == look.signature, "equal looks must have equal signatures")

-- 3. Paint ----------------------------------------------------------------------
local function SkinTextures(owner)
    local list = {}
    for _, texture in ipairs(childrenOf[owner] or {}) do
        if texture.shown and ((texture.layer == "ARTWORK" and texture.sublevel and texture.sublevel >= 5)
            or (texture.layer == "OVERLAY" and texture.sublevel == -1)) then list[#list + 1] = texture end
    end
    return list
end
local function CheckAnchored(owner, anchor, what)
    local own = {}
    for _, texture in ipairs(childrenOf[owner] or {}) do own[texture] = true end
    for _, texture in ipairs(SkinTextures(owner)) do
        local onAnchor = false
        for _, p in ipairs(texture.points or {}) do
            Check(anchor == owner or p.rel ~= owner, what .. ": a layer is laid out around the owner instead of the icon")
            Check(p.rel == anchor or own[p.rel], what .. ": a layer is laid out around a foreign region")
            if p.rel == anchor then onAnchor = true end
        end
        Check(onAnchor or #(texture.points or {}) > 0, what .. ": a layer has no anchor")
    end
end
local owner, anchor = GuardedFrame(), GuardedFrame()
local dark = Host.Compile("DARK3")
Check(Host.Paint(owner, dark, 36, 32, anchor) == true, "Paint must report that the skin draws the look")
local drawn = SkinTextures(owner)
Check(#drawn > 0, "Paint drew nothing")
CheckAnchored(owner, anchor, "DARK3")
for _, texture in ipairs(drawn) do
    local first = texture.points and texture.points[1]
    if first and first.point == "ALL" then Check(first.rel == anchor, "dim and gloss must cover the anchor") end
end
calls = 0
Host.Paint(owner, Host.Compile("DARK3"), 36, 32, anchor)
Check(calls == 0, "an unchanged repaint made " .. calls .. " widget calls")
-- Every catalog skin a consumer can compile lays out around the anchor.
for _, item in ipairs(Skins.List()) do
    local compiled = Host.Compile(item.value)
    if compiled then
        local o, a = GuardedFrame(), GuardedFrame()
        Host.Paint(o, compiled, 40, 40, a)
        CheckAnchored(o, a, item.value)
    end
end
Check(Host.Paint(owner, nil, 36, 32, anchor) == false and #SkinTextures(owner) == 0, "a nil look must hide the skin")
Check(Host.Paint(nil, dark, 36, 32) == false, "Paint without an owner draws nothing")
inCombat = true
Check(Host.Paint(owner, dark, 36, 32, anchor) == true and #SkinTextures(owner) > 0, "Paint must draw in combat too")
inCombat = false
-- Without an anchor the owner is the icon, as for MSUF's own auras.
local plain = GuardedFrame()
Host.Paint(plain, dark, 32, 32)
CheckAnchored(plain, plain, "owner as icon")
-- A clipped paint (an overlay over an icon with the same look): one mask of
-- the owner over the anchor on every layer, a later skin's new layers too.
do
    local o, a = GuardedFrame(), GuardedFrame()
    Check(Host.Paint(o, dark, 36, 36, a, true) == true, "a clipped skin draws")
    local clip
    for _, texture in ipairs(SkinTextures(o)) do
        clip = clip or maskOf[texture]
        Check(clip and maskOf[texture] == clip, "every layer must be clipped by the one mask")
    end
    Check(clip and clip.kind == "MaskTexture" and clip.points[1].point == "ALL" and clip.points[1].rel == a,
        "the clip lies over the anchor")
    Check(clip.path:find("WHITE8X8", 1, true), "a square look is clipped to the icon's rectangle")
    calls = 0
    Host.Paint(o, dark, 36, 36, a, true)
    Check(calls == 0, "an unchanged clipped repaint must write nothing (" .. calls .. " calls)")
    local shadow = Host.Compile("SHADOW1")
    Host.Paint(o, shadow, 36, 36, a, true)
    for _, texture in ipairs(SkinTextures(o)) do Check(maskOf[texture] == clip, "a new skin's layers join the clip") end
    Host.Paint(o, shadow, 36, 36, a)
    for _, texture in ipairs(SkinTextures(o)) do Check(maskOf[texture] == nil, "unclipped again") end
    -- A shaped look (a round skin on a round icon) clips to the icon's shape,
    -- so its ring and shadow outside the circle draw once (from the icon below).
    local roundOwner = GuardedFrame()
    Host.Paint(roundOwner, roundLook, 36, 36, a, true)
    local roundClip
    for _, texture in ipairs(SkinTextures(roundOwner)) do roundClip = roundClip or maskOf[texture] end
    local media = Shape.MEDIA[roundShape]
    Check(roundClip and roundClip.path == (media.mask or media.swipe or media.maskAtlas),
        "a shaped look must be clipped to its icon shape, not the rectangle")
    local unclipped = GuardedFrame()
    calls = 0
    Host.Paint(unclipped, dark, 36, 36, a)
    local plainCalls = calls
    for _, texture in ipairs(SkinTextures(unclipped)) do Check(maskOf[texture] == nil, "an unclipped paint masks nothing") end
    Check(plainCalls > 0, "the unclipped paint drew")
end
Check(framesCreated == 0, "the interface must not create frames")

-- 3b. Shapes -------------------------------------------------------------------
do
    local list = {}
    for i, shape in ipairs(Host.SHAPES) do list[i] = shape end
    Check(table.concat(list, " ") == "RECTANGLE CIRCLE ROUNDED DIAMOND HEXAGON STAR BLIZZARD", "the shape list changed")
    local o, a, t1, t2 = GuardedFrame(), GuardedFrame(), GuardedFrame(), GuardedFrame()
    local cd, edge, countdown = GuardedFrame(), GuardedFrame(), GuardedText()
    regionsOf[cd] = { edge, countdown }
    calls = 0
    Check(Host.ApplyShape(o, "RECTANGLE", a, { cd }, t1) == "RECTANGLE" and calls == 0,
        "a square icon that was never shaped must write nothing")
    Check(Host.ApplyShape(o, "CIRCLE", a, { cd }, t1, nil, t2) == "CIRCLE", "circle")
    local mask = maskOf[t1]
    Check(mask and maskOf[t2] == mask and maskOf[edge] == mask, "one mask of the owner over the textures and the cooldown")
    Check(mask.points and mask.points[1].point == "ALL" and mask.points[1].rel == a, "the mask lies over the anchor")
    Check(swipeOf[cd] and swipeOf[cd]:find("circle_mask", 1, true), "the swipe takes the shape")
    calls = 0
    Host.ApplyShape(o, "CIRCLE", a, { cd }, t1, nil, t2)
    Check(calls == 0, "repeating a shape must write nothing (" .. calls .. " calls)")
    -- A press flash and a charge swipe made later (also in combat): only theirs.
    local flash, charge, chargeEdge = GuardedFrame(), GuardedFrame(), GuardedFrame()
    regionsOf[charge] = { chargeEdge, GuardedText() }
    calls = 0
    Host.ApplyShape(o, "CIRCLE", a, { cd, charge }, t1, flash, t2)
    Check(calls == 3 and maskOf[flash] == mask and maskOf[chargeEdge] == mask and swipeOf[charge] == swipeOf[cd],
        "a later texture and cooldown take the shape with their own writes only (" .. calls .. " calls)")
    Check(Host.ApplyShape(o, "DIAMOND", a, { cd, charge }, t1, flash, t2) == "DIAMOND"
        and swipeOf[cd]:find("diamond_mask", 1, true) and swipeOf[charge]:find("diamond_mask", 1, true)
        and maskOf[t1] == mask, "a new shape re-skins the swipes under the same mask")
    Check(Host.ApplyShape(o, "CIRCLE", a, { cd }, t1, nil, t2) == "CIRCLE" and swipeOf[cd]:find("circle_mask", 1, true), "circle again")
    Check(Host.ApplyShape(o, "FOLLOW_PORTRAIT", a, { cd }, t1, nil, t2) == "RECTANGLE" and not maskOf[t1] and not maskOf[edge],
        "FOLLOW_PORTRAIT draws square and takes the masks off")
    Check(swipeOf[cd]:find("WHITE8X8", 1, true), "a square swipe again")
    Check(Host.ApplyShape(o, "BLIZZARD", nil, nil, t1) == "BLIZZARD" and maskOf[t1], "Blizzard portrait")
    Check(Host.ApplyShape(o, "NOPE", nil, nil, t1) == "RECTANGLE" and not maskOf[t1], "unknown shapes draw square")
    local ring, fill, outer, desaturate = Host.ShapeArt("CIRCLE")
    Check(ring:find("circle_ring_thin", 1, true) and fill:find("circle_mask", 1, true) and not outer and not desaturate, "circle art")
    ring, fill, outer, desaturate = Host.ShapeArt("STAR")
    Check(ring and outer and desaturate, "a star ring only works behind the icon and tints after desaturation")
    Check(Host.ShapeArt("RECTANGLE") == nil and Host.ShapeArt("FOLLOW_PORTRAIT") == nil, "no art for square icons")
end

-- 4. Combat parity --------------------------------------------------------------
local heard = {}
Check(Host.Subscribe("suite", function(reason) heard[#heard + 1] = reason end), "Subscribe refused a listener")
Check(not Host.Subscribe(nil, print) and not Host.Subscribe("x", "nope"), "Subscribe must refuse a malformed listener")
Skins.NotifyChanged("profile") -- the first notification always tells
heard = {}
local before = Host.Compile("DEFAULT").signature
inCombat = true
Skins.WriteDefault("styleSkin", "DARK2") -- the Icon Skins page in combat
Check(Host.Compile("DEFAULT").signature == before, "a default edited in combat must not reach new compiles in combat")
local firstTime = Host.Compile(nil)
Check(firstTime.signature == before, "a consumer compiling first in combat must see the applied look")
Skins.NotifyChanged("apply") -- nothing applies in combat; a stray call tells nobody
Check(#heard == 0, "listeners must not hear of a frozen default in combat")
inCombat = false
local edge = busHandlers.PLAYER_REGEN_ENABLED
local edgeFn
for _, fn in pairs(edge or {}) do edgeFn = fn end
Check(edgeFn ~= nil, "the frozen default must listen for the combat end")
edgeFn("PLAYER_REGEN_ENABLED")
Check(#heard == 1 and heard[1] == "combat", "the combat end must tell the listeners once (heard " .. #heard .. ")")
Check(Host.Compile("DEFAULT").skin.id == "DARK2", "after combat the new default must compile")
-- A profile switched in a fight (ProfileRuntime freezes every product through
-- Skins.FreezeProfile) is reported as "profile" at its end, not as a pick:
-- consumers keep their own shapes on a profile change.
heard = {}
inCombat = true
Skins.FreezeProfile()
shared.iconSkinDefault = { styleSkin = "SHADOW1" } -- the other profile's default
Check(Host.Compile("DEFAULT").skin.id == "DARK2", "a profile switched in combat must not reach compiles in combat")
inCombat = false
edgeFn = nil
for _, fn in pairs(busHandlers.PLAYER_REGEN_ENABLED or {}) do edgeFn = fn end
Check(edgeFn ~= nil, "the frozen profile must listen for the combat end")
edgeFn("PLAYER_REGEN_ENABLED")
Check(#heard == 1 and heard[1] == "profile", "a profile switched in combat must be reported as a profile change")
Check(Host.Compile("DEFAULT").skin.id == "SHADOW1", "after combat the profile's default must compile")
-- The same when an apply queued in the fight runs first at its end (the menu's
-- apply service): reading the committed default releases the freeze there.
heard = {}
inCombat = true
Skins.FreezeProfile()
shared.iconSkinDefault = { styleSkin = "DARK2" }
inCombat = false
MSUF.MSUF_Auras3.BumpRuntimeConfig()
Skins.NotifyChanged("apply")
Check(#heard == 1 and heard[1] == "profile", "a queued apply that releases a profile switch must report a profile change")
Skins.NotifyChanged("apply")
Check(#heard == 1, "the switch is reported once")
-- After it, a pick is a pick again.
Skins.WriteDefault("styleSkin", "SHADOW1")
MSUF.MSUF_Auras3.BumpRuntimeConfig()
Skins.NotifyChanged("apply")
Check(#heard == 2 and heard[2] == "apply", "a later pick must be reported as a pick")
-- A notification inside the fight (an aura apply while the switched profile is
-- still frozen) reports nothing and leaves the switch for the fight's end:
-- there and back, so the default is SHADOW1 again afterwards.
for _, id in ipairs({ "DARK2", "SHADOW1" }) do
    heard = {}
    inCombat = true
    Skins.FreezeProfile()
    shared.iconSkinDefault = { styleSkin = id }
    Skins.NotifyChanged("apply")
    Check(#heard == 0, "nothing is reported while the switched profile is frozen")
    inCombat = false
    edgeFn = nil
    for _, fn in pairs(busHandlers.PLAYER_REGEN_ENABLED or {}) do edgeFn = fn end
    edgeFn("PLAYER_REGEN_ENABLED")
    Check(#heard == 1 and heard[1] == "profile", "an apply inside the fight must leave the profile switch for its end")
    Check(Host.Compile("DEFAULT").skin.id == id, "after the fight the switched profile's default must compile")
end

-- 5. Notifications --------------------------------------------------------------
heard = {}
local A3 = MSUF.MSUF_Auras3
local function SharedApply()
    A3.BumpRuntimeConfig()
    Skins.NotifyChanged("apply")
end
Skins.WriteDefault("styleSkinGlossColor", { 1, 1, 1, 0.3 })
SharedApply()
Check(#heard == 1 and heard[1] == "apply", "an applied default edit must tell the listeners once")
SharedApply()
Check(#heard == 1, "an apply that changed nothing must tell nobody")
shared.appearanceIconStyles.buff = { iconSize = 30 }
SharedApply()
Check(#heard == 1, "other aura settings must not reach the icon skin listeners")
local after = {}
Host.Subscribe("broken", function() error("listener raised") end)
Host.Subscribe("late", function(reason) after[#after + 1] = reason end)
Skins.WriteDefault("styleSkin", "SHADOW4")
SharedApply()
Check(#reports == 1 and reports[1]:find("listener raised", 1, true), "a raising listener must be reported once")
Check(#after == 1 and #heard == 2, "a raising listener must not stop the others")
Check(Host.Unsubscribe("broken") and not Host.Unsubscribe("broken"), "Unsubscribe must answer whether it removed one")
Host.Unsubscribe("late")
Skins.WriteDefault("styleSkin", "SHADOW1")
SharedApply()
Check(#after == 1 and #heard == 3 and #reports == 1, "an unsubscribed listener must not be called")
Check(Host.Subscribe("late", function(reason) after[#after + 1] = reason end), "a key may subscribe again")

-- 6. Notification sources in MSUF core -------------------------------------------
local function Source(path)
    local file = assert(io.open(ADDON .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
do
    local model = Source("Auras3/MSUF_Auras3_Menu_Model.lua")
    local apply = model:find("function Model.Apply(", 1, true)
    local refusal = model:find("InCombatLockdown() == true", apply, true)
    local bump = model:find("A3.BumpRuntimeConfig() end", apply, true)
    local notify = model:find('A3.IconSkins.NotifyChanged("apply")', apply, true)
    Check(apply and refusal and bump and notify, "MenuModel.Apply must tell icon skin consumers after a shared apply")
    Check(refusal < notify and bump < notify, "the shared apply must notify after its combat refusal and generation bump")
    local runtime = Source("State/MSUF_ProfileRuntime.lua")
    local post = runtime:find("MSUF_ProfileIO_PostProfileRuntimeApply = function", 1, true)
    local defer = runtime:find("MSUF_ProfileIO_DeferPostProfileRuntimeApply(reason, applyAll) then", post, true)
    local profile = runtime:find('IconSkins.NotifyChanged("profile")', post, true)
    Check(post and defer and profile and defer < profile, "the profile apply must tell icon skin consumers after its combat deferral")
    local engine = Source("Auras3/MSUF_Auras3_IconSkins.lua")
    local edge = engine:find("local function OnCombatEdge(event)", 1, true)
    local thaw = engine:find("Thaw()", edge, true)
    local told = engine:find('Skins.NotifyChanged("combat")', edge, true)
    Check(edge and thaw and told and thaw < told, "the combat end must tell icon skin consumers after the thaw")
end

-- 7. Cost (exact caps, measured 2026-10-17 on Lua 5.1 with this catalog) ---------
local function Measure(fn)
    local count = 0
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    calls = 0
    debug.sethook(function() count = count + 1 end, "", 1)
    fn()
    debug.sethook()
    kb = collectgarbage("count") - kb
    collectgarbage("restart")
    return count, calls, kb
end
-- 2026-10-17, measured on this interface (round-8 review state): compile 311
-- VM instructions / 0 widget calls / 1.06 KB, unchanged repaint 85 / 0 /
-- 0.05 KB, quiet notification 182 / 0 / 0.09 KB. Instruction caps are the
-- measured counts; KB caps sit 0.01 above the printed (rounded) values.
local CAPS = {
    -- One compile: AttachPreview's style and skin tables and the signature.
    compile = { instructions = 311, calls = 0, kb = 1.07 },
    -- A style pass over an icon that already shows this look (also the clip
    -- check of an unclipped paint).
    repaint = { instructions = 85, calls = 0, kb = 0.06 },
    -- A shared aura apply that left the default as it was (also the profile
    -- switch check).
    quiet = { instructions = 182, calls = 0, kb = 0.10 },
}
local compiled = Host.Compile("DARK3")
Host.Paint(owner, compiled, 36, 32, anchor)
local results = {
    compile = { Measure(function() Host.Compile("DEFAULT") end) },
    repaint = { Measure(function() Host.Paint(owner, compiled, 36, 32, anchor) end) },
    quiet = { Measure(function() Skins.NotifyChanged("apply") end) },
}
for name, cap in pairs(CAPS) do
    local instructions, widgetCalls, kb = results[name][1], results[name][2], results[name][3]
    print(("icon skin host cost %s: %d instructions, %d widget calls, %.2f KB"):format(name, instructions, widgetCalls, kb))
    Check(instructions <= cap.instructions, ("%s: %d VM instructions, cap %d"):format(name, instructions, cap.instructions))
    Check(widgetCalls <= cap.calls, ("%s: %d widget calls, cap %d"):format(name, widgetCalls, cap.calls))
    Check(kb <= cap.kb, ("%s: %.2f KB, cap %.2f"):format(name, kb, cap.kb))
end

-- 8. Cold path ------------------------------------------------------------------
do
    local source = Source("Auras3/MSUF_Auras3_IconSkins_Host.lua")
    for _, token in ipairs({ "RegisterEvent", "SetScript", "HookScript", "hooksecurefunc", "C_Timer", "CreateFrame",
        "OnUpdate", "pcall" }) do
        Check(not source:find(token, 1, true), "the icon skin interface must stay cold path; found " .. token)
    end
end

print("icon skin host API smoke passed")

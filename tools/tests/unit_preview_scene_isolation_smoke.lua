-- unit_preview_scene_isolation_smoke.lua <repoRoot> [flavor]
--
-- Static unit preview scenes (root:Unit on GF.NewPreviewScene): plain Buttons painted through the ordinary spec
-- pipeline with a mock sample. Pins that a scene frame
--   * exists for every unit key the client has, and for no other;
--   * is reachable from nothing but its scene: not the live registry, the unit index, click casting, an event route,
--     a timer, a driver or any cache of the engine (a walk of everything reachable from the sandbox, closures and
--     metatables included), and carries no event, script, secure attribute or unit watch;
--   * calls no unit API, whatever the settings: health, name, text and portrait colour modes, NPC colours, prediction,
--     every status icon, every sample (player and NPC, every classification, every PvP state);
--   * paints exactly what a live frame of that unit paints for the same sample (twin comparison of every named region:
--     bars as fills, texts, colours, icons, borders, geometry), except the intended differences, which are pinned too:
--     the portrait draws the sample's picture, the out-of-combat fade is ignored, a boss border is not snapped to a
--     screen position the scene does not have.
-- Boots the real core through tools/tests/unit_scene_world.lua. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = dofile(root .. "/tools/tests/unit_scene_world.lua")

local function Check(condition, message)
    if not condition then error("unit_preview_scene_isolation_smoke " .. flavor .. ": " .. message, 2) end
end

-- Recorders for the calls a scene must never make. Installed before the addon loads, so a captured local is seen too.
local calls = {}
local w = World.New(root, flavor, { beforeBoot = function(world)
    local env = world.env
    for _, name in ipairs({ "RegisterUnitWatch", "UnregisterUnitWatch", "RegisterStateDriver", "UnregisterStateDriver",
        "RegisterAttributeDriver", "UnregisterAttributeDriver" }) do
        local original = env[name]
        env[name] = function(frame, ...)
            calls[#calls + 1] = { frame = frame, name = name }
            if original then return original(frame, ...) end
        end
    end
end })
local h, UF, GF, env = w.h, w.UF, w.GF, w.env
local Methods = h.widgets.Methods
for _, name in ipairs({ "SetAttribute", "RegisterEvent", "RegisterUnitEvent", "RegisterAllEvents", "SetScript", "HookScript",
    "RegisterForClicks" }) do
    local original = assert(Methods[name], "stub lacks " .. name)
    Methods[name] = function(self, first, ...)
        calls[#calls + 1] = { frame = self, name = name, first = first }
        return original(self, first, ...)
    end
end

w:Enable()
local db = env.MSUF_DB
-- Difficulty-graded level colours and the colour-by-health text curve are the client's own curves: the twin compares
-- them with both switched off, and the spy runs below keep them on.
local UNIT_CONFIG_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }
h:RunTimers()

local U = UF.UnitScene
Check(type(U) == "table" and type(U.SAMPLES) == "table", "the core has no unit scene module")
local function FamilyOf(unit)
    if U.SAMPLES[unit] then return unit end
    return (unit:gsub("%d+$", ""))
end

local function Owned(frame, container)
    for _ = 1, 80 do
        if frame == container then return true end
        frame = frame and rawget(frame, "parent")
        if not frame then return false end
    end
    return false
end
local function CallsOn(container, names)
    local found = {}
    for _, call in ipairs(calls) do
        if names[call.name] and Owned(call.frame, container) then
            found[#found + 1] = call.name .. "(" .. tostring(call.first) .. ") on " .. tostring(call.frame.objectType)
        end
    end
    return found
end

local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(400, 300)

---------------------------------------------------------------------------
-- 1. Every unit key the client has gets a scene, no other does.
---------------------------------------------------------------------------
local rootA = GF.NewPreviewScene(host)
local scenes, scenesByUnit = {}, {}
local supported = {}
for _, unit in ipairs(UF.unitOrder) do supported[unit] = true end
for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss1", "boss2",
    "boss3", "boss4", "boss5", "arena1", "arena2", "arena3", "arena4", "arena5" }) do
    local scene = rootA:Unit(unit)
    if supported[unit] then
        Check(scene ~= nil, unit .. ": the client has this unit frame and the root made no scene")
        Check(rootA:Unit(unit) == scene, unit .. ": a second request made a second scene")
        scenes[#scenes + 1] = scene
        scenesByUnit[unit] = scene
    else
        Check(scene == nil, unit .. ": the client has no such unit frame and the root made a scene")
    end
end
Check(#scenes >= 5, "too few unit scenes: " .. #scenes)
Check(rootA:Unit("nonsense") == nil and rootA:Unit(nil) == nil and rootA:Unit("party1") == nil, "a root made a scene for a token that is no unit frame")
Check(rootA:Unit("boss") == scenesByUnit.boss1 and rootA:Unit("arena") == scenesByUnit.arena1, "boss and arena are not their first slot")
for _, scene in ipairs(scenes) do
    Check(scene:Frame() ~= nil and scene:Frame().objectType == "Button", scene:Unit() .. ": the scene frame is not a plain Button")
    Check(scene:Unit() ~= nil and scene:Sample() ~= nil, "a scene lost its unit or sample")
end

---------------------------------------------------------------------------
-- 2. Isolation. Show every scene with every feature on, then look for the frame everywhere.
---------------------------------------------------------------------------
local attachedBefore = #UF.attachedFrameList
local framesBefore = {}
for unit, frame in pairs(UF.frames or {}) do framesBefore[unit] = frame end
rootA:Activate()
for _, scene in ipairs(scenes) do
    Check(scene:Show() == true and scene:IsActive(), scene:Unit() .. ": the scene did not show on an active root")
end
h:RunTimers()
Check(#UF.attachedFrameList == attachedBefore, "showing the scenes changed the attached frame list")
local shownCount = 0
for _, scene in ipairs(scenes) do
    local frame = scene:Frame()
    local unit = scene:Unit()
    Check(frame:IsShown() and frame:GetParent() == host, unit .. ": the scene frame is not shown under its owner's frame")
    Check(frame._msufPreviewScope == true and frame._msufPreviewScene == scene, unit .. ": the scene frame carries no scope")
    Check(frame.MSUFUnitKey == nil and frame.unitKey == nil, unit .. ": the scene frame holds a unit outside its paint window")
    Check(frame._msufDispatchActive ~= true, unit .. ": the paint window stayed open")
    Check(frame:GetAttribute("unit") == nil and next(frame.attributes or {}) == nil, unit .. ": the scene frame holds a secure attribute")
    Check(frame.events == nil or next(frame.events) == nil, unit .. ": the scene frame holds registered events")
    -- The one script a scene frame carries is the portrait's own repaint-on-show hook, which only runs after the portrait
    -- asked for a visible refresh; a scene never asks (checked below by firing it).
    Check(frame.scripts.OnEvent == nil and frame.scripts.OnHide == nil and frame.scripts.OnEnter == nil
        and frame.scripts.OnLeave == nil and frame.scripts.OnAttributeChanged == nil,
        unit .. ": the scene frame carries a script")
    Check(frame.scripts.OnShow == nil or frame._msufPortraitOnShowHooked == true,
        unit .. ": the scene frame carries a show script that is not the portrait's own")
    Check(frame._msufPortraitNeedsVisibleRefresh == nil, unit .. ": the scene asked for a portrait refresh on show")
    if frame.scripts.OnShow then
        w:Reset()
        w:Arm()
        frame.scripts.OnShow(frame)
        w:Disarm()
        Check(w:Violations() == nil and frame:IsShown() and frame.MSUFUnitKey == nil, unit .. ": the portrait's show script did something on a scene frame")
    end
    Check(UF.attachedFrames[frame] ~= true and frame._msufCoreVisible == true, unit .. ": the scene frame joined the attached list or lost its visible mark")
    Check(UF.frames[unit] ~= frame and framesBefore[unit] == UF.frames[unit], unit .. ": the scene frame is in the live unit index")
    Check(env.ClickCastFrames[frame] == nil and not (_G.ClickCastFrames and _G.ClickCastFrames[frame]),
        unit .. ": the scene frame is registered for click casting")
    for index = 1, #UF.frameList do Check(UF.frameList[index] ~= frame, unit .. ": the live frame list holds a scene frame") end
    for index = 1, #UF.attachedFrameList do Check(UF.attachedFrameList[index] ~= frame, unit .. ": the attached list holds a scene frame") end
    Check(frame.name == nil and frame.frameName == nil, unit .. ": the scene frame took a global name")
    local forbidden = CallsOn(frame, { SetAttribute = true, RegisterEvent = true, RegisterUnitEvent = true, RegisterAllEvents = true,
        RegisterForClicks = true, RegisterUnitWatch = true, UnregisterUnitWatch = true, RegisterStateDriver = true,
        UnregisterStateDriver = true, RegisterAttributeDriver = true, UnregisterAttributeDriver = true })
    Check(#forbidden == 0, unit .. ": the scene made a call it must not make: " .. tostring(forbidden[1]))
    for _, call in ipairs(CallsOn(frame, { SetScript = true, HookScript = true })) do
        for _, script in ipairs({ "OnEvent", "OnEnter", "OnLeave", "OnHide", "OnAttributeChanged", "OnClick", "OnMouseDown", "OnMouseUp" }) do
            Check(not call:find("(" .. script .. ")", 1, true), unit .. ": the scene installed a " .. script .. " script (" .. call .. ")")
        end
        if call:find("(OnShow)", 1, true) then
            Check(call:find("HookScript", 1, true) and frame._msufPortraitOnShowHooked == true, unit .. ": the scene hooked its visibility (" .. call .. ")")
        end
    end
    shownCount = shownCount + 1
end
Check(shownCount == #scenes, "not every scene was checked")
-- A positive control: a live frame registers events and scripts, so the recorder above would have seen a scene doing it.
local before = #calls
local controlUnit = scenes[1]:Unit()
local control = w:LiveFrame(controlUnit, U.SAMPLES[FamilyOf(controlUnit)], "MSUF_Control")
local seenControl = 0
for index = before + 1, #calls do
    if calls[index].name == "SetScript" or calls[index].name == "RegisterEvent" or calls[index].name == "RegisterUnitEvent" then
        seenControl = seenControl + 1
    end
end
Check(seenControl > 0, "the control found no script or event registration on a live frame; the recorder is blind")
w:Unmodel()

-- Nothing outside the scene holds a scene frame or any of its regions.
do
    local targets, allowed = {}, { [rootA] = true, [host] = true, [calls] = true }
    local function Collect(region)
        targets[region] = true
        for _, child in ipairs(region.children or {}) do Collect(child) end
        for _, sub in ipairs(region.regions or {}) do targets[sub] = true end
    end
    for _, scene in ipairs(scenes) do
        allowed[scene] = true
        Collect(scene:Frame())
    end
    -- The harness's live control frame holds its own regions; it is not a scene.
    local held = w:Holders(targets, allowed)
    Check(held == nil, "something outside the scene holds a scene frame or region: " .. tostring(held))
    -- Positive control: the walk finds a holder.
    local sample = scenes[1]:Frame()
    env.MSUF.__sceneHolderControl = { sample.hpBar }
    local control_ = w:Holders(targets, allowed)
    env.MSUF.__sceneHolderControl = nil
    Check(control_ ~= nil, "the holder walk missed a planted reference; it is blind")
end

---------------------------------------------------------------------------
-- 3. No unit API: every unit, every sample, every colour and text mode.
---------------------------------------------------------------------------
-- Positive controls. A call to an engine entry point is counted; so is one to a unit API nobody listed (the sandbox
-- answers those through its fallback, which a file caches as a local at load or reaches through _G) and one into a
-- namespace the client has. Only UnitClass("player") under a named settings read is let through: the same call
-- anywhere else, another API under the same read and another unit under the same read are counted.
w:Reset()
w:Direct(true)
env.UnitName("player")
env._G.UnitSex("target")
env._G.UnitAura("target", 1)
local expectedDirect = 3
if rawget(env, "C_PlayerInfo") ~= nil or env.C_PlayerInfo ~= nil then
    env.C_PlayerInfo.GetRace({})
    expectedDirect = expectedDirect + 1
end
w:Direct(false)
Check(#w.seen == expectedDirect, "the spy missed a direct unit API call (" .. #w.seen .. " of " .. expectedDirect .. ")")
w:Reset()
w:Arm()
env.UnitClass("player")
local function PlayerClassToken() env.UnitClass("player") end
PlayerClassToken()
local function CompileUnitCustomContainers() env.UnitLevel("player") env.UnitClass("target") end
CompileUnitCustomContainers()
w:Disarm()
Check(#w.seen == 3 and w.seen[1] == "UnitClass" and w.seen[2] == "UnitLevel" and w.seen[3] == "UnitClass",
    "the settings exemption is not exactly UnitClass(player) under a named read (" .. table.concat(w.seen, ",") .. ")")
w:Reset()

-- The settings refresh is the test's own call (the live runtime answers it with unit queries of its own): the spy is armed
-- again for the scenes' repaints and the timers they queue.
local function RefreshAll(reason)
    local armed = w.armed
    w:Disarm()
    UF.Config.Refresh()
    if armed then w:Arm() end
    for _, scene in ipairs(scenes) do Check(scene:Refresh() == true, scene:Unit() .. ": the scene did not repaint after " .. reason) end
    h:RunTimers()
end
local function Silent(label)
    local violations = w:Violations()
    Check(violations == nil, label .. ": a scene called a unit API: " .. tostring(violations))
end

local function EveryConf(fn)
    for _, key in ipairs(UNIT_CONFIG_KEYS) do fn(db[key]) end
end

w:Arm()
RefreshAll("the base settings")
for _, scene in ipairs(scenes) do
    scene:RefreshData()
end
w:Disarm()
Silent("base settings")

local VARIANTS = {
    { "gradient health with a gradient background", function()
        EveryConf(function(conf) conf.healthColorMode = "GRADIENT" end)
        db.general.barBgColorMode, db.general.barBgFillMode = "health_gradient", "missing"
    end },
    { "dark health, class background", function()
        EveryConf(function(conf) conf.healthColorMode = "DARK" end)
        db.general.barBgColorMode, db.general.barBgFillMode = "class", "full"
    end },
    { "unified health, matched background", function()
        EveryConf(function(conf) conf.healthColorMode = "UNIFIED" end)
        db.general.barBgColorMode = "match_health"
    end },
    { "NPC type colours, NPC class colours and tapped gray", function()
        EveryConf(function(conf) conf.healthColorMode = "CLASS" end)
        db.general.barBgColorMode = "custom"
        db.general.npcColorMode, db.general.npcTypeColorBar, db.general.npcTypeColorText = "type", true, true
        db.general.npcClassColorBar, db.general.tapDeniedGray = true, true
    end },
    { "name colours off, health text by class", function()
        db.general.nameClassColor, db.general.npcNameRed, db.general.nameNpcClassColor = false, false, false
        db.general.colorHealthTextByHealth, db.general.healthTextColorMode = false, "class"
    end },
    { "pet colours and power colours", function()
        db.general.petFrameColorEnabled, db.general.petFrameUsePlayerClassColor = true, true
        db.general.powerColorMode, db.general.colorPowerTextByType = "class", false
    end },
    { "class portraits with a class border", function()
        EveryConf(function(conf) conf.portraitRender, conf.portraitBorderStyle = "CLASS", "CLASS_COLOR" end)
    end },
    { "reaction border on a blizzard-shaped portrait with elite art", function()
        EveryConf(function(conf)
            conf.portraitRender, conf.portraitBorderStyle, conf.portraitShape, conf.portraitBlizzardElite = "2D", "REACTION", "BLIZZARD", true
        end)
    end },
    { "dragon artwork portraits", function()
        EveryConf(function(conf) conf.portraitShape, conf.portraitDragonArtwork = "BLIZZARD", true end)
    end },
    { "prediction bars and absorb text", function()
        db.general.healPredEnabled, db.general.enableAbsorbBar, db.general.healAbsorbEnabled = true, true, true
        db.general.absorbTextMode, db.general.showTotalAbsorbAmount, db.general.overAbsorbOverlay = 2, true, true
    end },
    { "inline target of target and name shortening", function()
        db.targettarget.totInlineColorMode = "AUTO"
        db.general.shortenNameMaxChars, db.general.shortenNameClipSide = 4, "LEFT"
    end },
}
for _, variant in ipairs(VARIANTS) do
    variant[2]()
    w:Reset()
    w:Arm()
    RefreshAll(variant[1])
    w:Disarm()
    Silent(variant[1])
end

-- Every sample a scene can be given: player and NPC, every classification, every PvP state, every reaction.
local SAMPLES_TO_TRY = {
    { name = "A player", player = true, class = "PRIEST", reaction = "friendly", level = 12, hp = 0.1, power = 0, leader = true, assist = true },
    { name = "A hostile player", player = true, class = "ROGUE", reaction = "enemy", pvp = "FFA", hp = 1, power = 1 },
    { name = "A rare", classification = "rare", reaction = "neutral", level = 60 },
    { name = "A rare elite", classification = "rareelite", reaction = "enemy", level = 61 },
    { name = "A world boss", classification = "worldboss", reaction = "enemy", level = -1, npcKind = "npcBoss" },
    { name = "A friendly boss", classification = "worldboss", reaction = "friendly", level = -1, npcKind = "npcBoss" },
    { name = "A horde player", player = true, class = "SHAMAN", pvp = "Horde", combat = true, resting = true, raidTarget = 3 },
    { name = "A pet", reaction = "friendly", class = "HUNTER", npcKind = "npcRegular", portrait = "Interface\\ICONS\\INV_Misc_QuestionMark" },
}
for _, scene in ipairs(scenes) do
    for _, sample in ipairs(SAMPLES_TO_TRY) do
        w:Reset()
        w:Arm()
        Check(scene:SetSample(sample) == true, scene:Unit() .. ": the scene did not repaint for a new sample")
        w:Disarm()
        Silent(scene:Unit() .. " with the sample " .. sample.name)
        Check(scene:Frame().nameText == nil or not scene:Frame().nameText:IsShown() or scene:Frame().nameText.text == sample.name,
            scene:Unit() .. ": the sample name did not reach the name text")
    end
    Check(scene:SetSample(nil) == true and scene:Sample().name == U.SAMPLES[FamilyOf(scene:Unit())].name,
        scene:Unit() .. ": clearing the sample did not restore the unit's own")
end
-- Restore the settings the variants changed.
w:Enable()
EveryConf(function(conf)
    conf.healthColorMode, conf.portraitShape, conf.portraitDragonArtwork, conf.portraitBlizzardElite = nil, nil, nil, nil
end)
for _, key in ipairs({ "barBgColorMode", "barBgFillMode", "npcColorMode", "npcTypeColorBar", "npcTypeColorText", "npcClassColorBar",
    "tapDeniedGray", "healthTextColorMode", "petFrameColorEnabled", "petFrameUsePlayerClassColor", "powerColorMode",
    "healPredEnabled", "enableAbsorbBar", "healAbsorbEnabled", "absorbTextMode", "showTotalAbsorbAmount", "shortenNameMaxChars",
    "shortenNameClipSide" }) do
    db.general[key] = nil
end
db.targettarget.totInlineColorMode = "DEFAULT"
UF.Config.Refresh()
RefreshAll("the settings restored")

---------------------------------------------------------------------------
-- 4. Twin paint: a live frame of the unit over the same sample paints the same regions.
---------------------------------------------------------------------------
local SCALARS = { "objectType", "shown", "width", "height", "alpha", "scale", "frameLevel", "frameStrata", "drawLayer", "text",
    "texture", "atlas", "justifyH", "fontSize", "fontPath", "blendMode" }
local TUPLES = { "color", "vertexColor", "textColor", "texCoord", "colorTexture", "backdropColor", "backdropBorderColor", "shadowColor" }
local function Tuple(value)
    if type(value) ~= "table" then return tostring(value) end
    local out = {}
    for index = 1, 8 do
        local part = value[index]
        if type(part) == "number" then part = string.format("%.4f", part) end
        out[#out + 1] = tostring(part)
    end
    return table.concat(out, ",")
end
-- What a region looks like, as one string: regions that differ only in the order they were created in compare equal.
local function Signature(region)
    local point = region.points and region.points[1]
    local parts = { tostring(region.objectType), tostring(rawget(region, "shown")), tostring(rawget(region, "width")),
        tostring(rawget(region, "height")), tostring(rawget(region, "atlas") or rawget(region, "texture")),
        tostring(rawget(region, "text")), Tuple(rawget(region, "color") or rawget(region, "vertexColor")) }
    if point then
        parts[#parts + 1] = tostring(point.point) .. tostring(point.relativePoint) .. tostring(point.x) .. "," .. tostring(point.y)
    end
    return table.concat(parts, "|")
end
local function Children(frame)
    local list = {}
    for _, child in ipairs(frame.children or {}) do list[#list + 1] = child end
    for _, region in ipairs(frame.regions or {}) do list[#list + 1] = region end
    local signatures = {}
    for _, region in ipairs(list) do signatures[region] = Signature(region) end
    table.sort(list, function(x, y) return signatures[x] < signatures[y] end)
    return list
end
local function Fill(bar)
    local ratio = (bar.value or 0) / math.max(bar.maximum - (bar.minimum or 0), 1e-9)
    return math.min(1, math.max(0, ratio))
end
-- Resolved geometry: the rectangle a region occupies in its frame's own coordinates (left, bottom, right, top), from its
-- points, its size and, for a status bar's fill texture, the bar's fill. Two regions are equal when they occupy the same
-- rectangle, whatever chain of anchors put them there; a region the chain cannot place has no rectangle.
local FRACTION = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
local function Resolver(frame)
    local barOf, cache = {}, {}
    local function Index(region)
        local fill = rawget(region, "statusBarTexture")
        if type(fill) == "table" then barOf[fill] = region end
        for _, child in ipairs(region.children or {}) do Index(child) end
        for _, sub in ipairs(region.regions or {}) do Index(sub) end
    end
    Index(frame)
    local Rect
    local function Place(region, depth)
        local all = rawget(region, "allPoints")
        if all then
            local relative = all == true and rawget(region, "parent") or all
            return relative and Rect(relative, depth + 1) or nil
        end
        local points = rawget(region, "points")
        if type(points) ~= "table" or #points == 0 then return nil end
        local width, height = rawget(region, "width"), rawget(region, "height")
        local left, bottom, right, top, centerX, centerY
        for _, point in ipairs(points) do
            local relative = point.relativeTo or rawget(region, "parent")
            local box = relative and Rect(relative, depth + 1)
            if not box then return nil end
            local at = FRACTION[point.relativePoint or point.point] or FRACTION.CENTER
            local x = box[1] + (box[3] - box[1]) * at[1] + (point.x or 0)
            local y = box[2] + (box[4] - box[2]) * at[2] + (point.y or 0)
            local own = FRACTION[point.point] or FRACTION.CENTER
            if own[1] == 0 then left = x elseif own[1] == 1 then right = x else centerX = x end
            if own[2] == 0 then bottom = y elseif own[2] == 1 then top = y else centerY = y end
        end
        if not left and not right then
            if centerX and width then left, right = centerX - width / 2, centerX + width / 2 end
        elseif not left then
            left = width and right - width or nil
        elseif not right then
            right = width and left + width or nil
        end
        if not bottom and not top then
            if centerY and height then bottom, top = centerY - height / 2, centerY + height / 2 end
        elseif not bottom then
            bottom = height and top - height or nil
        elseif not top then
            top = height and bottom + height or nil
        end
        if left and right and bottom and top then return { left, bottom, right, top } end
        return nil
    end
    Rect = function(region, depth)
        if region == frame then return { 0, 0, rawget(frame, "width") or 0, rawget(frame, "height") or 0 } end
        if depth > 40 then return nil end
        local known = cache[region]
        if known ~= nil then return known or nil end
        cache[region] = false
        local rect
        local bar = barOf[region]
        if bar then
            local box = Rect(bar, depth + 1)
            if box then
                local fill = bar.maximum and Fill(bar) or 1
                local width, height = box[3] - box[1], box[4] - box[2]
                if bar.orientation == "VERTICAL" then
                    rect = bar.reverseFill and { box[1], box[4] - height * fill, box[3], box[4] }
                        or { box[1], box[2], box[3], box[2] + height * fill }
                else
                    rect = bar.reverseFill and { box[3] - width * fill, box[2], box[3], box[4] }
                        or { box[1], box[2], box[1] + width * fill, box[4] }
                end
            end
        else
            rect = Place(region, depth)
        end
        cache[region] = rect or false
        return rect
    end
    return function(region) return Rect(region, 0) end
end
local liveRect, sceneRect
local function SameRect(left, right)
    for index = 1, 4 do
        if math.abs(left[index] - right[index]) > 0.01 then return false end
    end
    return true
end
local function RectText(rect)
    if not rect then return "unresolved" end
    return string.format("%.2f,%.2f,%.2f,%.2f", rect[1], rect[2], rect[3], rect[4])
end

-- The portrait's art texture of the live frame being compared: a scene draws the sample's own picture there.
local artRegion
local ART_KEYS = { texture = true, atlas = true, texCoord = true, vertexColor = true }
local function CompareTrees(a, b, path, diffs)
    for _, key in ipairs(SCALARS) do
        local left, right = rawget(a, key), rawget(b, key)
        if a == artRegion and ART_KEYS[key] then left, right = nil, nil end
        -- A FontString that was never given text and one given "" both draw nothing.
        if key == "text" then left, right = left or "", right or "" end
        if type(left) == "number" and type(right) == "number" then left, right = string.format("%.3f", left), string.format("%.3f", right) end
        if left ~= right then diffs[#diffs + 1] = path .. "." .. key .. ": " .. tostring(rawget(a, key)) .. " vs " .. tostring(rawget(b, key)) end
    end
    -- A status bar is compared by what it draws: its fill, not the scale its value and maximum are on (the live health
    -- bar runs on a percent, the scene's on the sample's absolute values).
    if a.maximum and b.maximum and math.abs(Fill(a) - Fill(b)) > 1e-6 then
        diffs[#diffs + 1] = path .. ".fill: " .. Fill(a) .. " vs " .. Fill(b)
    end
    -- Colours and coordinates of a region that is hidden on both sides draw nothing.
    local hidden = rawget(a, "shown") ~= true and rawget(b, "shown") ~= true
    if not hidden then
        local left, right = liveRect(a), sceneRect(b)
        if (left == nil) ~= (right == nil) then
            diffs[#diffs + 1] = path .. ".rect: " .. RectText(left) .. " vs " .. RectText(right)
        elseif left and not SameRect(left, right) then
            diffs[#diffs + 1] = path .. ".rect: " .. RectText(left) .. " vs " .. RectText(right)
        end
    end
    for _, key in ipairs(TUPLES) do
        if not hidden and not (a == artRegion and ART_KEYS[key]) and Tuple(rawget(a, key)) ~= Tuple(rawget(b, key)) then
            diffs[#diffs + 1] = path .. "." .. key .. ": " .. Tuple(rawget(a, key)) .. " vs " .. Tuple(rawget(b, key))
        end
    end
    local left, right = Children(a), Children(b)
    if #left ~= #right then diffs[#diffs + 1] = path .. " has " .. #left .. " regions vs " .. #right end
    for index = 1, math.min(#left, #right) do
        CompareTrees(left[index], right[index], path .. "/" .. tostring(left[index].objectType) .. index, diffs)
    end
end
--- The regions each frame names (hpBar, nameText, portrait, ...): compared one by one, each region once however many
--- aliases name it.
local function NamedRegions(live, scene)
    local names = {}
    for _, source in ipairs({ live, scene }) do
        for key, value in pairs(source) do
            if type(key) == "string" and type(value) == "table" and rawget(value, "objectType") and key ~= "parent"
                and key:sub(1, 1) ~= "_" then
                names[key] = true
            end
        end
    end
    local list = {}
    for key in pairs(names) do list[#list + 1] = key end
    table.sort(list)
    return list
end

--- The differences between a live frame and a scene frame of one unit: the portrait picture is the only thing excluded
--- (a scene draws the sample's own, section 5 pins it); every region is compared in colour, text, state and geometry.
local function Differences(unit, live, scene)
    local diffs, seen = {}, {}
    artRegion = live.portrait
    liveRect, sceneRect = Resolver(live), Resolver(scene)
    for _, key in ipairs(NamedRegions(live, scene)) do
        local a, b = live[key], scene[key]
        if (a == nil) ~= (b == nil) then
            diffs[#diffs + 1] = key .. ": live " .. tostring(a ~= nil) .. " scene " .. tostring(b ~= nil)
        elseif a and not seen[a] then
            seen[a] = true
            CompareTrees(a, b, key, diffs)
        end
    end
    return diffs
end

-- A scene that was painted under other settings keeps the regions those settings built (pooled, hidden), so each
-- comparison is made on a freshly built scene.
local twinSerial = 0
local function TwinAll(label)
    twinSerial = twinSerial + 1
    local fresh = GF.NewPreviewScene(host)
    fresh:Activate()
    for _, unit in ipairs(UF.unitOrder) do
        local scene = fresh:Unit(unit, { show = true })
        local sample = U.SAMPLES[FamilyOf(unit)]
        Check(scene:IsActive(), unit .. ": the fresh scene did not show for the twin comparison")
        local live = w:LiveFrame(unit, sample, "MSUF_Twin" .. twinSerial .. "_" .. unit)
        local diffs = Differences(unit, live, scene:Frame())
        w:Unmodel()
        Check(#diffs == 0, label .. ": the scene frame of " .. unit .. " paints differently from a live frame (" .. #diffs
            .. "): " .. table.concat(diffs, " | ", 1, math.min(#diffs, 4)))
    end
    fresh:Release()
end

-- The twin starts from settings both sides can draw: the colour-by-health text and the difficulty-graded level colour
-- read the client's own colour curves, which the sandbox does not model.
db.general.colorHealthTextByHealth = false
EveryConf(function(conf) conf.levelIndicatorDifficultyColor = false end)
UF.Config.Refresh()
TwinAll("base settings")
local TWIN_VARIANTS = {
    { "NPC type colours", function()
        db.general.npcColorMode, db.general.npcTypeColorBar, db.general.npcTypeColorText = "type", true, true
    end },
    { "dark health", function() db.general.barMode = "dark" end },
    { "unified health", function() db.general.barMode = "unified" end },
    { "class background", function() db.general.barBgColorMode = "class" end },
    { "matched background in missing mode", function()
        db.general.barBgColorMode, db.general.barBgFillMode = "match_health", "missing"
    end },
    { "NPC class colours", function() db.general.npcClassColorBar = true end },
    { "class power colour", function() db.general.powerColorMode = "class" end },
    { "pet colours", function() db.general.petFrameColorEnabled, db.general.petFrameUsePlayerClassColor = true, true end },
    { "class portraits with a class border", function()
        EveryConf(function(conf) conf.portraitRender, conf.portraitBorderStyle = "CLASS", "CLASS_COLOR" end)
    end },
    { "reaction portrait border", function() EveryConf(function(conf) conf.portraitBorderStyle = "REACTION" end) end },
    { "elite art on a blizzard-shaped portrait", function()
        EveryConf(function(conf)
            conf.portraitRender, conf.portraitBorderStyle, conf.portraitShape, conf.portraitBlizzardElite = "2D", "NONE", "BLIZZARD", true
        end)
    end },
}
for _, variant in ipairs(TWIN_VARIANTS) do
    variant[2]()
    UF.Config.Refresh()
    TwinAll(variant[1])
end

-- Native rounded/slanted decoration must also remain unit-free on these plain scene frames.
do
    local bars = db.bars
    local saved = { bars.roundedFramesEnabled, bars.roundedUnitFrames, bars.slantedBarsEnabled, bars.slantedUnitFrames }
    local forEach = UF.ForEachFrame
    local auras = env.MSUF.MSUF_Auras3
    local function ApplyDecoratorConfig()
        UF.ForEachFrame = function() end -- this world's header placeholders have no native edge pools
        local refreshMasks = auras.RefreshRoundedDispelOverlayMasks
        auras.RefreshRoundedDispelOverlayMasks = function() return false end -- no live aura surfaces in this scene-only fixture
        env.MSUF_ApplyRoundedUnitframes()
        auras.RefreshRoundedDispelOverlayMasks = refreshMasks
        UF.ForEachFrame = forEach
    end
    for _, shape in ipairs({ "rounded", "slanted" }) do
        bars.roundedFramesEnabled, bars.roundedUnitFrames = shape == "rounded", shape == "rounded"
        bars.slantedBarsEnabled, bars.slantedUnitFrames = shape == "slanted", shape == "slanted"
        ApplyDecoratorConfig()
        UF.Config.Refresh()
        w:Reset(); w:Arm()
        for _, scene in ipairs(scenes) do scene:Refresh() end
        w:Disarm()
        Check(not w:Violations(), shape .. " unit scene queried the client: " .. tostring(w:Violations()))
    end
    bars.roundedFramesEnabled, bars.roundedUnitFrames, bars.slantedBarsEnabled, bars.slantedUnitFrames = unpack(saved, 1, 4)
    ApplyDecoratorConfig()
    UF.Config.Refresh()
end

---------------------------------------------------------------------------
-- 4b. A scene paint touches no live frame, whatever its unit token finds: the live frame of the same token (in the unit
-- index, under its global name) is digested before and after every kind of scene paint.
---------------------------------------------------------------------------
for _, scene in ipairs(scenes) do
    local unit = scene:Unit()
    local previous = UF.frames[unit]
    local live = w:LiveFrame(unit, U.SAMPLES[FamilyOf(unit)], "MSUF_" .. unit, true)
    w:Unmodel()
    local digest = World.Digest(live)
    Check(scene:Refresh() and scene:RefreshData() and scene:SetSample({ name = "Other", hp = 0.3, class = "PRIEST", player = true })
        and scene:SetSample(nil), unit .. ": the scene did not repaint")
    scene:Hide()
    Check(scene:Show(), unit .. ": the scene did not show again")
    Check(World.Digest(live) == digest, unit .. ": a scene paint changed the live frame of the same token")
    UF.frames[unit] = previous
end

---------------------------------------------------------------------------
-- 4c. A paint that fails (nothing in the addon catches it) leaves its window open until the next paint; the next full
-- refresh must still apply the spec with the frame holding no unit.
---------------------------------------------------------------------------
do
    local scene = scenes[1]
    local unit, frame = scene:Unit(), scene:Frame()
    local health = UF.elements.Health
    local paint = health.PaintSample
    health.PaintSample = function() error("injected sample paint failure") end
    -- A coroutine takes the failure; nothing in the addon (or here) catches it with a protected call.
    local survived = coroutine.resume(coroutine.create(function() scene:RefreshData() end))
    health.PaintSample = paint
    Check(not survived, "the injected paint failure did not reach the scene")
    Check(frame.MSUFUnitKey == unit, "the control: a failed paint leaves its window open (the next refresh has to close it)")
    local field = health.SceneApply and "SceneApply" or "Apply"
    local original, held = health[field], {}
    health[field] = function(target, ...)
        held[#held + 1] = target.MSUFUnitKey or false
        return original(target, ...)
    end
    local refreshed = scene:Refresh()
    health[field] = original
    Check(refreshed == true and #held >= 1, unit .. ": the refresh after a failed paint did not apply")
    for _, key in ipairs(held) do
        Check(key == false, unit .. ": the spec was applied with the frame holding " .. tostring(key) .. " after a failed paint")
    end
    Check(frame.MSUFUnitKey == nil and frame._msufDispatchActive ~= true, unit .. ": the window is still open after the refresh")
end

---------------------------------------------------------------------------
-- 5. The intended differences, pinned.
---------------------------------------------------------------------------
-- The portrait draws the sample's own picture: the class icon of a player or of a class render, else the sample's picture.
w:Enable()
UF.Config.Refresh()
EveryConf(function(conf) conf.portraitRender, conf.portraitBorderStyle = "2D", "NONE" end)
UF.Config.Refresh()
for _, scene in ipairs(scenes) do
    local unit = scene:Unit()
    local sample = scene:Sample()
    Check(scene:Refresh(), unit .. ": the scene did not repaint")
    local portrait = scene:Frame().portrait
    Check(portrait and portrait:IsShown(), unit .. ": the scene draws no portrait")
    if sample.player == true then
        local art = tostring(portrait.atlas or portrait.texture)
        Check(art:find(sample.class, 1, true), unit .. ": a player's portrait is not its class icon (" .. art .. ")")
    else
        Check(portrait.texture == sample.portrait, unit .. ": an NPC's portrait is not the sample's picture (" .. tostring(portrait.texture) .. ")")
    end
end
-- The out-of-combat fade is for a frame outside the menu: a scene ignores it and keeps the unified opacity.
EveryConf(function(conf) conf.hpBarAlpha, conf.oocFadeEnabled, conf.oocFadeAlpha = 0.6, true, 0.3 end)
UF.Config.Refresh()
for _, scene in ipairs(scenes) do
    local unit = scene:Unit()
    Check(scene:Refresh(), unit .. ": the scene did not repaint")
    Check(scene:Frame():GetAlpha() == 1, unit .. ": the scene frame took the out-of-combat fade (alpha " .. tostring(scene:Frame():GetAlpha()) .. ")")
    local fill = scene:Frame().hpBar:GetStatusBarTexture()
    Check(fill and fill:GetAlpha() == 0.6, unit .. ": the scene lost the unified health opacity")
end
do
    local unit = scenes[1]:Unit()
    local live = w:LiveFrame(unit, U.SAMPLES[FamilyOf(unit)], "MSUF_FadeControl")
    w:Unmodel()
    Check(live:GetAlpha() == 0.3, "the control: a live frame out of combat does not take the fade (alpha " .. tostring(live:GetAlpha()) .. ")")
end
EveryConf(function(conf) conf.oocFadeEnabled = false end)
UF.Config.Refresh()

-- The level takes the colour of its difficulty tier from the sample: "??" is the top band, else the sample's own tier.
EveryConf(function(conf) conf.levelIndicatorDifficultyColor = true end)
UF.Config.Refresh()
for _, scene in ipairs(scenes) do
    local unit = scene:Unit()
    Check(scene:SetSample({ levelTier = 5 }), unit .. ": the scene did not repaint")
    local frame = scene:Frame()
    local level = frame.MSUFSpec.status.level
    if level and level.enabled and level.difficultyColors and frame.levelText and frame.levelText:IsShown() then
        local tier = scene:Sample().level == -1 and 1 or 5
        local colors, color = level.difficultyColors, frame.levelText.textColor
        local base = (tier - 1) * 3
        Check(color and color[1] == colors[base + 1] and color[2] == colors[base + 2] and color[3] == colors[base + 3],
            unit .. ": the level text is not coloured by the sample's tier " .. tier)
    end
    scene:SetSample(nil)
end
-- The health text coloured by health follows each sample's fraction.
db.general.colorHealthTextByHealth = true
UF.Config.Refresh()
for _, scene in ipairs(scenes) do
    local unit = scene:Unit()
    local frame = scene:Frame()
    if frame._msufTextRuntime and frame._msufTextRuntime.healthColorByHealth == true then
        scene:SetSample({ hp = 0.1 })
        local low = Tuple(frame.hpTextLeft and frame.hpTextLeft.textColor or frame.hpTextRight.textColor)
        scene:SetSample({ hp = 0.95 })
        local high = Tuple(frame.hpTextLeft and frame.hpTextLeft.textColor or frame.hpTextRight.textColor)
        Check(low ~= high, unit .. ": the health text colour does not follow the sample's health")
        scene:SetSample(nil)
    end
end
db.general.colorHealthTextByHealth = false
EveryConf(function(conf) conf.levelIndicatorDifficultyColor = false end)
UF.Config.Refresh()

---------------------------------------------------------------------------
-- 6. Aura stand-ins: the buff and debuff lanes of the unit's own aura configuration, two icons each, and nothing else.
---------------------------------------------------------------------------
local A3 = env.MSUF.MSUF_Auras3
local STANDINS = 2
local AURA_LANES = { buff = true, debuff = true, custom1 = true, custom2 = true, custom3 = true, custom4 = true, defensivePortrait = true, targetDotPortrait = true }
--- The stand-in icons a scene frame shows, by the lane host they are anchored to, and the icons that belong to no lane.
local function StandIns(frame)
    local counts, strays, byHost = {}, 0, {}
    for key in pairs(AURA_LANES) do counts[key] = 0 end
    for key, laneHost in pairs(frame._msufGFFrameAuraPreviewHosts or {}) do byHost[laneHost] = key end
    for _, visual in ipairs(frame._msufGFFrameAuraPreviews or {}) do
        if visual.shown == true and (visual._texture == nil or visual._texture.shown ~= false) then
            local first = visual.points and visual.points[1]
            local key = first and byHost[first.relativeTo]
            if key and counts[key] then counts[key] = counts[key] + 1 else strays = strays + 1 end
        end
    end
    return counts, strays
end
--- What the unit's own aura configuration asks for, resolved by the aura runtime itself.
local function WantedStandIns(scene)
    local frame = scene:Frame()
    local spec = frame.MSUFSpec
    local config = spec.auras and spec.auras.enabled == true and A3.ResolveAuraPreviewConfig(frame, scene:Unit(), spec)
    local wanted = {}
    for key in pairs(AURA_LANES) do wanted[key] = 0 end
    for key in pairs(wanted) do
        local lane = config and config.lanes and config.lanes[key]
        if lane and lane.enabled == true and (tonumber(lane.max) or 0) >= 1 then
            wanted[key] = math.min(STANDINS, math.floor(lane.max + 0.5))
        end
    end
    return wanted, config
end
local function CheckStandIns(label)
    local total = {}
    for key in pairs(AURA_LANES) do total[key] = 0 end
    for _, scene in ipairs(scenes) do
        local unit, frame = scene:Unit(), scene:Frame()
        local wanted, config = WantedStandIns(scene)
        local counts, strays = StandIns(frame)
        for key in pairs(AURA_LANES) do
            Check(counts[key] == wanted[key], label .. ": " .. unit .. " shows " .. counts[key] .. " " .. key
                .. " stand-ins, the unit's aura configuration asks for " .. wanted[key])
            total[key] = total[key] + wanted[key]
            if counts[key] > 0 then
                local lane = config.lanes[key]
                for _, visual in ipairs(frame._msufGFFrameAuraPreviews) do
                    local first = visual.points and visual.points[1]
                    if visual.shown == true and first and first.relativeTo == frame._msufGFFrameAuraPreviewHosts[key] then
                        Check(visual.width == (lane.buttonWidth or lane.size) and visual.height == (lane.buttonHeight or lane.size),
                            label .. ": " .. unit .. " " .. key .. " stand-in is not the lane's size")
                    end
                end
            end
        end
        Check(strays == 0, label .. ": " .. unit .. " shows " .. strays .. " stand-in icons that belong to no configured unit lane")
        for key, laneHost in pairs(frame._msufGFFrameAuraPreviewHosts or {}) do
            Check(AURA_LANES[key] == true, label .. ": " .. unit .. " built a lane host for " .. tostring(key)
                .. ", a lane a unit frame has no stand-ins for")
            Check((laneHost.shown == true) == ((wanted[key] or 0) > 0), label .. ": " .. unit .. " " .. key
                .. " lane host is " .. (laneHost.shown == true and "shown" or "hidden") .. " against " .. tostring(wanted[key]) .. " stand-ins")
        end
    end
    return total
end
UF.Config.Refresh()
for _, scene in ipairs(scenes) do Check(scene:Refresh(), scene:Unit() .. ": the scene did not repaint") end
local standIns = CheckStandIns("auras on")
Check(standIns.buff > 0 and standIns.debuff > 0, "no unit scene shows a buff or a debuff stand-in; the check is blind")
-- Off: the aura master switch hides every stand-in; one unit's own switch hides that unit's alone.
local auraDB = A3.EnsureDB()
auraDB.enabled = false
A3.InvalidateUnitRuntimeConfig(nil)
RefreshAll("the auras are off")
local none = CheckStandIns("auras off")
Check(none.buff == 0 and none.debuff == 0, "a scene shows aura stand-ins with the auras off")
auraDB.enabled = true
A3.InvalidateUnitRuntimeConfig(nil)
RefreshAll("the auras are back")
CheckStandIns("auras back")
-- The spec's own switch decides, whatever the aura runtime would resolve for the unit.
do
    local scene = scenes[1]
    local spec = scene:Frame().MSUFSpec
    local wanted = WantedStandIns(scene)
    Check(wanted.buff + wanted.debuff > 0, scene:Unit() .. ": the control unit asks for no stand-ins")
    spec.auras.enabled = false
    scene:RefreshData()
    local counts, strays = StandIns(scene:Frame())
    spec.auras.enabled = true
    Check(counts.buff == 0 and counts.debuff == 0 and strays == 0, scene:Unit() .. ": a scene shows stand-ins for a spec whose auras are off")
    scene:RefreshData()
    CheckStandIns("spec switch restored")
end
if scenesByUnit.target then
    auraDB.showTarget = false
    A3.InvalidateUnitRuntimeConfig(nil)
    RefreshAll("the target auras are off")
    local counts = StandIns(scenesByUnit.target:Frame())
    Check(counts.buff == 0 and counts.debuff == 0, "the target scene shows stand-ins with the target auras off")
    local rest = CheckStandIns("target auras off")
    Check(rest.buff + rest.debuff > 0, "switching the target auras off hid every unit's stand-ins")
    auraDB.showTarget = true
    A3.InvalidateUnitRuntimeConfig(nil)
    RefreshAll("the target auras are back")
    CheckStandIns("target auras back")
end

---------------------------------------------------------------------------
-- 7. Scenes of two roots share nothing: frame, spec and pool are per scene.
---------------------------------------------------------------------------
local otherHost = env.CreateFrame("Frame", nil, env.UIParent)
local rootB = GF.NewPreviewScene(otherHost)
rootB:Activate()
local first = scenesByUnit.target or scenesByUnit.player
local twin = rootB:Unit(first:Unit(), { show = true })
Check(twin ~= first and twin:Frame() ~= first:Frame() and twin:Frame():GetParent() == otherHost, "two roots share a scene or a frame")
Check(twin.spec ~= first.spec and twin.spec ~= UF.Config.GetSpec(first:Unit()), "a scene shares its spec table with another scene or the live spec")
twin:SetSample({ name = "Another", hp = 0.2 })
Check(first:Sample().name ~= "Another" and first:Frame().hpBar.value ~= twin:Frame().hpBar.value, "a sample leaked into another scene")
Check(twin:Frame().nameText == nil or twin:Frame().nameText.text == "Another", "the second scene did not take its own sample")
Check(rootB:Unit(first:Unit(), { sample = { name = "Third" } }) == twin and twin:Sample().name == "Third"
    and twin:Frame().nameText.text == "Third", "a later request with a sample did not apply it")
Check(rootB:Unit("pet", { sample = { name = "Born with it" } }) == nil or rootB:Unit("pet"):Sample().name == "Born with it",
    "a request that makes a scene did not give it the sample")
rootB:Release()
Check(not twin:IsActive() and not twin:Frame():IsShown(), "releasing a root left its scene shown")
Check(first:IsActive() and first:Frame():IsShown(), "releasing one root hid another root's scene")

print("unit_preview_scene_isolation_smoke: PASS (" .. flavor .. ")")

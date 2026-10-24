-- group_preview_scene_isolation_smoke.lua <repoRoot> [flavor]
--
-- Isolated group preview scenes (GF.NewPreviewScene): plain Buttons painted through the ordinary spec pipeline.
-- Pins that a scene
--   * owns its pool, container, count and layout tier, next to the on-screen preview and next to other scenes;
--   * never reaches the live registry, the unit index, click casting, events or secure attributes;
--   * paints exactly what the on-screen dummy of the same index paints (differential region comparison);
--   * keeps its own layer filter, and the on-screen filter survives every scene call;
--   * is hidden by combat like every other preview and refuses to show during combat;
--   * leaves the on-screen preview's registry membership and unit attribute as they were.
-- Boots the real group runtime through group_header_world.lua. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error("group_preview_scene_isolation_smoke " .. flavor .. ": " .. message, 2) end
end

-- The reduced-max-health bar of the on-screen dummies exists where the client has the API the live bar reads; a scene
-- shows its sample on every client, so the comparison gives every client the API.
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.MAX_BOSS_FRAMES = 5
    world.env.GetUnitTotalModifiedMaxHealthPercent = function() return 0 end
end })
local GF, UF, env = h.GF, h.core.UF, h.env
GF.EnsureDB()
h.core.ExportPublic("MSUF2_GFPagePreviewActive", true)

local party, raid = GF.GetConf("party"), GF.GetConf("raid")
party.enabled, raid.enabled = true, true
party.auras = party.auras or {}
party.auras.enabled, party.auras.renderer = true, "CUSTOM"
party.trackedBuffMax = 3
-- Settings away from the defaults, so the twin comparison covers the unified alpha, the fades and the layout keys.
party.hpBarAlpha, party.hpBgAlpha, party.oocFadeEnabled, party.oocFadeAlpha = 0.6, 0.5, true, 0.7
party.borderSize, party.powerHeight, party.groupBorderEnabled = 2, 9, true
party.textLeft, party.textCenter, party.textRight, party.showPowerText = "PERCENT", "NONE", "NONE", true
party.nameAnchor, party.nameFontSize, party.hpFontSize = "CENTER", 16, 14
party.healthColorMode, party.nameBarEnabled, party.nameMaxChars = "GRADIENT", true, 4
env.MSUF_DB.general.tempMaxHealthEnabled, env.MSUF_DB.general.overAbsorbOverlay = true, true
env.MSUF_DB.general.healPredAnchorMode, env.MSUF_DB.general.absorbAnchorMode = 3, 3
env.MSUF_DB.general.healPredictionBarHeight, env.MSUF_DB.general.absorbBarHeight = 50, 30
raid.layoutTiersEnabled, raid.tier10Width, raid.tier20Width = true, 61, 73
GF.InvalidateCompiledSpecs("party")
GF.InvalidateCompiledSpecs("raid")

-- Recorders for the calls a scene must never make. Installed before any scene frame exists.
local Methods = h.widgets.Methods
local calls = {}
for _, name in ipairs({ "SetAttribute", "RegisterEvent", "RegisterUnitEvent", "RegisterAllEvents", "SetScript",
    "HookScript", "RegisterForClicks" }) do
    local original = assert(Methods[name], "stub lacks " .. name)
    Methods[name] = function(self, first, ...)
        calls[#calls + 1] = { frame = self, name = name, first = first }
        return original(self, first, ...)
    end
end

local function Owned(frame, container)
    for _ = 1, 60 do
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
local otherHost = env.CreateFrame("Frame", nil, env.UIParent)
otherHost:SetSize(400, 300)

---------------------------------------------------------------------------
-- 1. The on-screen preview keeps its behavior: tracked frames, "player" unit attribute, GF tables as state.
---------------------------------------------------------------------------
Check(GF.ShowPreview("party", 4, { immediate = true }) == true, "the on-screen party preview did not show")
h:RunTimers()
local onScreen = GF._previewFrames.party
Check(#onScreen == 4 and GF._previewActive.party == true and GF._previewShownCounts.party == 4,
    "the on-screen preview state is no longer kept in the GF._preview* tables")
Check(GF.frames[onScreen[1]] == true, "the on-screen preview frame left the live frame registry")
Check(onScreen[1]:GetAttribute("unit") == "player", "the on-screen preview lost its unit attribute")
Check(GF._previewContainer.party and GF._previewContainer.party.frameName == "MSUF_GFPreviewContainer_party",
    "the on-screen container lost its global name")
Check(GF.GetActivePreviewCount("party") == 4 and GF.GetActivePreviewCount("party", onScreen[1]) == 4,
    "the on-screen preview count changed")

---------------------------------------------------------------------------
-- 2. Two scenes of one kind with different counts, next to the on-screen preview.
---------------------------------------------------------------------------
local rootA, rootB = GF.NewPreviewScene(host), GF.NewPreviewScene(otherHost)
rootA:Activate()
rootB:Activate()
local groupA = rootA:Group("party", 3, { immediate = true })
local groupB = rootB:Group("party", 5, { immediate = true })
h:RunTimers()
Check(groupA and groupB and groupA ~= groupB, "two scene roots made one group")
Check(rootA:Group("party") == groupA, "a second request for a kind made a second group")
Check(#groupA:Frames() == 3 and #groupB:Frames() == 5 and #onScreen == 4, "scene counts leaked into each other")
Check(groupA:Count() == 3 and groupB:Count() == 5, "a scene lost its own count")
Check(GF.GetActivePreviewCount("party", groupA:Frames()[1]) == 3
    and GF.GetActivePreviewCount("party", groupB:Frames()[1]) == 5
    and GF.GetActivePreviewCount("party", onScreen[1]) == 4, "a frame did not lay out for its own scene's count")
local shared = {}
for _, frame in ipairs(onScreen) do shared[frame] = "onscreen" end
for _, list in ipairs({ groupA:Frames(), groupB:Frames() }) do
    for _, frame in ipairs(list) do
        Check(shared[frame] == nil, "two pools handed out one frame")
        shared[frame] = "scene"
        Check(frame._msufPreviewScene ~= nil and frame._msufPreviewScope == true, "a scene frame carries no scope flag")
        Check(frame._msufCoreVisible == true, "a scene frame is not marked visible for the core's runtime update")
    end
end
Check(groupA:Container():GetParent() == host and groupB:Container():GetParent() == otherHost,
    "a scene container is not parented to its owner's frame")
Check(groupA:Container() ~= GF._previewContainer.party and groupA:Layout() ~= GF._previewLayoutFrame.party,
    "a scene shares the on-screen container")
Check(groupA:Container().frameName == nil and groupA:Frames()[1].frameName == nil, "a scene frame took a global name")
Check(GF._previewFrames.party == onScreen and #onScreen == 4 and GF._previewShownCounts.party == 4,
    "showing scenes changed the on-screen preview")
-- Hiding one scene leaves the others.
groupA:Hide()
Check(not groupA:IsActive() and groupB:IsActive() and GF._previewActive.party == true, "hiding a scene hid another preview")
Check(not groupA:Container():IsShown() and groupB:Container():IsShown(), "a hidden scene kept its container shown")
Check(groupA:Show(2, { immediate = true }) == true and groupA:Count() == 2, "a re-shown scene kept the old count")
local shownA = 0
for _, frame in ipairs(groupA:Frames()) do if frame:IsShown() then shownA = shownA + 1 end end
Check(shownA == 2, "a scene kept a frame shown beyond its count")
groupA:Show(3, { immediate = true })

---------------------------------------------------------------------------
-- 3. Layout tier by the scene's own count (raid size tiers).
---------------------------------------------------------------------------
Check(GF.ShowPreview("raid", 8, { immediate = true }) == true, "the on-screen raid preview did not show")
local raidGroup = rootA:Group("raid", 15, { immediate = true })
h:RunTimers()
Check(GF._previewFrames.raid[1].MSUFSpec.width == 61, "the on-screen raid dummy lost its 8-member tier width")
Check(raidGroup:Frames()[1].MSUFSpec.width == 73, "a 15-member scene did not lay out its own tier width")
Check(GF._previewFrames.raid[1].MSUFSpec.width == 61, "a scene changed the on-screen raid dummy's width")
GF.HidePreview("raid")

---------------------------------------------------------------------------
-- 4. Isolation: registry, unit index, click casting, attributes, events.
---------------------------------------------------------------------------
local scenes = { groupA, groupB, raidGroup }
for _, group in ipairs(scenes) do
    for _, frame in ipairs(group:Frames()) do
        Check(GF.frames[frame] ~= true, "a scene frame joined the live frame registry")
        Check(frame._msufGFInFrameList ~= true and frame._msufGFIndexedUnit == nil, "a scene frame joined the frame list or unit index")
        Check(UF.attachedFrames[frame] ~= true, "a scene frame joined the unit-frame attached list")
        Check(frame:GetAttribute("unit") == nil, "a scene frame holds a unit attribute")
        Check(env.ClickCastFrames[frame] == nil, "a scene frame is registered for click casting")
        Check(frame.events and next(frame.events) == nil, "a scene frame holds registered events")
        Check(frame.scripts.OnEvent == nil, "a scene frame has an event script")
    end
end
for _, list in pairs(GF.frameList) do Check(list._msufPreviewScope ~= true, "the frame list holds a scene frame") end
Check(GF.unitFrames.player ~= groupA:Frames()[1] and GF.unitFrames.player ~= groupB:Frames()[1], "the unit index points at a scene frame")
for index = 1, #UF.attachedFrameList do
    Check(UF.attachedFrameList[index]._msufPreviewScope ~= true, "the attached list holds a scene frame")
end
for _, group in ipairs(scenes) do
    local forbidden = CallsOn(group:Container(), { SetAttribute = true, RegisterEvent = true, RegisterUnitEvent = true,
        RegisterAllEvents = true, RegisterForClicks = true })
    Check(#forbidden == 0, "a scene made a call it must not make: " .. tostring(forbidden[1]))
    local scripts = CallsOn(group:Container(), { SetScript = true, HookScript = true })
    for _, call in ipairs(scripts) do
        -- A show/hide hook (core visibility, range settle) is a subscription a scene never makes; a size hook on a
        -- bar is the bar's own layout.
        Check(not (call:find("HookScript(OnShow)", 1, true) or call:find("HookScript(OnHide)", 1, true)),
            "a scene hooked its visibility: " .. call)
        for _, forbiddenScript in ipairs({ "OnEvent", "OnEnter", "OnLeave", "OnAttributeChanged" }) do
            Check(not call:find("(" .. forbiddenScript .. ")", 1, true), "a scene installed a " .. forbiddenScript .. " script")
        end
    end
end
-- A positive control: the on-screen dummies do register unit events once their OnShow edge runs, so the
-- recorder above would have seen a scene doing the same.
GF.ShowPreview("raid", 3, { immediate = true })
local before = #calls
for _, frame in ipairs(GF._previewFrames.raid) do
    local show = frame.scripts and frame.scripts.OnShow
    if show then show(frame) end
end
local registered = 0
for index = before + 1, #calls do
    if calls[index].name == "RegisterEvent" or calls[index].name == "RegisterUnitEvent" then registered = registered + 1 end
end
Check(registered > 0, "the control found no event registration on the on-screen dummies; the recorder is blind")
GF.HidePreview("raid")

---------------------------------------------------------------------------
-- 5. Same paint as the on-screen dummy of the same index.
---------------------------------------------------------------------------
local SCALARS = { "objectType", "shown", "width", "height", "alpha", "scale", "frameLevel", "frameStrata", "drawLayer", "text",
    "texture", "atlas", "value", "minimum", "maximum", "justifyH", "fontSize", "fontPath", "blendMode" }
local TUPLES = { "color", "vertexColor", "textColor", "texCoord", "colorTexture", "backdropColor", "backdropBorderColor",
    "shadowColor" }
local function Tuple(value)
    if type(value) ~= "table" then return tostring(value) end
    local out = {}
    for index = 1, 8 do out[#out + 1] = tostring(value[index]) end
    return table.concat(out, ",")
end
local function Children(frame)
    local list = {}
    for _, child in ipairs(frame.children or {}) do list[#list + 1] = child end
    for _, region in ipairs(frame.regions or {}) do list[#list + 1] = region end
    return list
end
local function CompareTrees(a, b, path, pairing, diffs)
    pairing[a] = b
    for _, key in ipairs(SCALARS) do
        local left, right = rawget(a, key), rawget(b, key)
        -- A FontString that was never given text and one given "" both draw nothing.
        if key == "text" then left, right = left or "", right or "" end
        if left ~= right then diffs[#diffs + 1] = path .. "." .. key .. ": " .. tostring(rawget(a, key)) .. " vs " .. tostring(rawget(b, key)) end
    end
    -- Colours and coordinates of a region that is hidden on both sides draw nothing.
    local hidden = rawget(a, "shown") ~= true and rawget(b, "shown") ~= true
    for _, key in ipairs(TUPLES) do
        if not hidden and Tuple(rawget(a, key)) ~= Tuple(rawget(b, key)) then diffs[#diffs + 1] = path .. "." .. key .. ": " .. Tuple(rawget(a, key)) .. " vs " .. Tuple(rawget(b, key)) end
    end
    if a.statusBarTexture and b.statusBarTexture then pairing[a.statusBarTexture] = b.statusBarTexture end
    local left, right = Children(a), Children(b)
    if #left ~= #right then diffs[#diffs + 1] = path .. " has " .. #left .. " regions vs " .. #right end
    for index = 1, math.min(#left, #right) do
        CompareTrees(left[index], right[index], path .. "/" .. tostring(left[index].objectType) .. index, pairing, diffs)
    end
end
local function ComparePoints(a, b, path, pairing, diffs, skipRoot)
    if not skipRoot then
        local left, right = a.points or {}, b.points or {}
        if #left ~= #right then diffs[#diffs + 1] = path .. " has " .. #left .. " points vs " .. #right end
        for index = 1, math.min(#left, #right) do
            local x, y = left[index], right[index]
            local relative = pairing[x.relativeTo] or x.relativeTo
            if x.point ~= y.point or x.relativePoint ~= y.relativePoint or x.x ~= y.x or x.y ~= y.y or relative ~= y.relativeTo then
                diffs[#diffs + 1] = path .. " point " .. index .. " differs"
            end
        end
    end
    local left, right = Children(a), Children(b)
    for index = 1, math.min(#left, #right) do
        ComparePoints(left[index], right[index], path .. "/" .. tostring(left[index].objectType) .. index, pairing, diffs)
    end
end
-- The one intended difference: the on-screen dummy of index 1 draws the real player name, a scene draws its sample
-- name (a scene asks the client nothing). `expectedName` is the single text difference allowed on that frame.
local function SamePaint(label, defaultFrame, sceneFrame, expectedName)
    local pairing, diffs = {}, {}
    CompareTrees(defaultFrame, sceneFrame, "frame", pairing, diffs)
    ComparePoints(defaultFrame, sceneFrame, "frame", pairing, diffs, true)
    if expectedName then
        local kept = {}
        for _, diff in ipairs(diffs) do
            if diff:sub(-#expectedName) ~= expectedName then kept[#kept + 1] = diff end
        end
        Check(#kept == #diffs - 1, label .. ": the player-name difference is missing or repeated: " .. tostring(diffs[1]) .. " | " .. tostring(diffs[2]))
        diffs = kept
    end
    Check(#diffs == 0, label .. ": the scene frame paints differently from the on-screen dummy: " .. tostring(diffs[1]))
end
-- Same kind, same count, same index, same configuration: the paint is the same.
-- The on-screen dummy lays out for the player's own role (damage in this world); pin the scene to the same role
-- before its first frame, so the two build the same regions.
local rootT = GF.NewPreviewScene(otherHost)
rootT:Activate()
local twin = rootT:Group("party")
twin:SetRole("DAMAGER")
twin:Show(4, { immediate = true })
h:RunTimers()
Check(#twin:Frames() == 4, "the twin scene has the wrong count")
for index = 1, 4 do
    SamePaint("party " .. index, onScreen[index], twin:Frames()[index], index == 1 and ".text: Name-player vs Mapko" or nil)
end

---------------------------------------------------------------------------
-- 6. Layer filters: a scene's own, and the on-screen one survives scene calls.
---------------------------------------------------------------------------
local function NameTexts(frames)
    local texts = {}
    for index = 1, #frames do texts[index] = frames[index].nameText and frames[index].nameText.text or "" end
    return texts
end
Check(NameTexts(twin:Frames())[2] ~= "", "the control name is blank")
GF.SetPreviewLayerFilter({ status = false }, nil)
twin:SetLayerFilter({ text = false }, nil)
for index, text in ipairs(NameTexts(twin:Frames())) do Check(text == "", "a scene kept a name with the text layer off (" .. index .. ")") end
for index, text in ipairs(NameTexts(onScreen)) do Check(text ~= "", "a scene's text filter blanked the on-screen dummy " .. index) end
Check(not onScreen[2].roleIcon:IsShown(), "the on-screen status filter was lost to a scene call")
twin:RefreshData()
GF.RefreshPreviewAnimation()
Check(not onScreen[2].roleIcon:IsShown() and NameTexts(onScreen)[2] ~= "", "the on-screen filter changed after a scene refresh")
for index, text in ipairs(NameTexts(twin:Frames())) do Check(text == "", "a refresh ignored the scene's text filter (" .. index .. ")") end
Check(twin:Frames()[2].roleIcon:IsShown(), "the on-screen status filter hid a scene's status layer")
twin:SetLayerFilter({ status = false }, nil)
Check(not twin:Frames()[2].roleIcon:IsShown(), "a scene kept its role icon with the status layer off")
Check(onScreen[2].roleIcon:IsShown() == false and twin:Frames()[3].roleIcon:IsShown() == false, "the status filter missed a frame")
twin:SetLayerFilter(nil, nil)
Check(twin:Frames()[2].roleIcon:IsShown(), "clearing a scene's filter did not bring its status layer back")
GF.SetPreviewLayerFilter(nil, nil)
Check(onScreen[2].roleIcon:IsShown(), "clearing the on-screen filter did not bring its status layer back")

-- A scene that builds in slices keeps its filter for every slice.
local raidSlices = rootB:Group("raid", 12, {})
raidSlices:SetLayerFilter({ text = false }, nil)
raidSlices:Show(12, {})
h:RunTimers()
Check(#raidSlices:Frames() == 12, "the sliced scene did not finish")
for index, text in ipairs(NameTexts(raidSlices:Frames())) do Check(text == "", "a sliced build ignored the scene filter (" .. index .. ")") end
GF.SetPreviewLayerFilter({ text = false }, nil)
Check(NameTexts(onScreen)[2] == "", "the on-screen text filter did not apply")
raidSlices:SetLayerFilter(nil, nil)
raidSlices:Show(12, {})
h:RunTimers()
Check(NameTexts(onScreen)[2] == "", "a sliced scene build reset the on-screen filter")
GF.SetPreviewLayerFilter(nil, nil)
raidSlices:Hide()

---------------------------------------------------------------------------
-- 7. Anchor: the on-screen preview follows SetPreviewAnchor, a scene follows its own parent.
---------------------------------------------------------------------------
local mover = env.CreateFrame("Frame", nil, env.UIParent)
GF.SetPreviewAnchor("party", mover)
Check(GF._previewAnchorFrame.party == mover and groupB:Container():GetParent() == otherHost, "the party anchor leaked into a scene")
GF.SetPreviewAnchor("party", nil)
rootB:SetParent(mover)
groupB:Refresh({ immediate = true })
Check(groupB:Container():GetParent() == mover and GF._previewAnchorFrame.party == nil and
    GF._previewContainer.party:GetParent() == env.UIParent, "re-parenting a scene touched the on-screen container")
rootB:SetParent(otherHost)
groupB:Refresh({ immediate = true })

---------------------------------------------------------------------------
-- 8. Combat: scenes refuse to show and are hidden with every other preview.
---------------------------------------------------------------------------
Check(groupB:IsActive() and twin:IsActive(), "the control scenes are not active")
h:EnterCombat()
Check(GF.HidePreviewsForCombat() == true or GF._previewActive.party ~= true, "combat hide reported nothing hidden")
for _, group in ipairs({ groupA, groupB, twin }) do
    Check(not group:IsActive() and not group:Container():IsShown(), "combat left a scene visible")
    for _, frame in ipairs(group:Frames()) do Check(not frame:IsShown(), "combat left a scene frame shown") end
end
Check(groupB:Show(5, { immediate = true }) == false and not groupB:IsActive(), "a scene showed during combat")
Check(rootB:Group("party", 5, { immediate = true }) == groupB and not groupB:IsActive(), "a group request showed a scene during combat")
Check(GF._previewActive.party ~= true, "combat left the on-screen preview active")
h:LeaveCombat()
Check(groupB:Show(5, { immediate = true }) == true and groupB:IsActive(), "a scene did not show again after combat")

---------------------------------------------------------------------------
-- 9. Release drops the groups; the on-screen preview and the other roots are untouched.
---------------------------------------------------------------------------
GF.ShowPreview("party", 4, { immediate = true })
Check(twin:Show(4, { immediate = true }) and twin:IsActive(), "the twin scene did not show again after combat")
rootB:Release()
Check(not groupB:IsActive() and twin:IsActive(), "release left a scene active or hid another root's scene")
rootT:Release()
Check(not twin:IsActive(), "release left the twin scene active")
Check(rootB:Group("party", 2, { immediate = true }) ~= groupB, "a released root reused a released group")
Check(groupA:Show(3, { immediate = true }) and groupA:IsActive(), "releasing one root broke another")
Check(GF._previewActive.party == true and #GF._previewFrames.party == 4, "releasing a root changed the on-screen preview")
-- Pools stay apart across a release: a frame the on-screen preview let go never reappears in a scene, and the
-- other way round.
local released = {}
for _, frame in ipairs(GF._previewFrames.party) do released[frame] = true end
GF.HidePreview("party")
Check(groupA:IsActive(), "hiding the on-screen preview hid a scene")
local rootC = GF.NewPreviewScene(host)
rootC:Activate()
local groupC = rootC:Group("party", 4, { immediate = true })
local fromScene = {}
for _, frame in ipairs(groupC:Frames()) do
    Check(not released[frame], "a scene took a frame the on-screen preview released")
    fromScene[frame] = true
end
groupC:Hide()
GF.ShowPreview("party", 4, { immediate = true })
for _, frame in ipairs(GF._previewFrames.party) do
    Check(not fromScene[frame], "the on-screen preview took a frame a scene released")
end
GF.HidePreview("party")
rootC:Release()

---------------------------------------------------------------------------
-- 10. Combat hides an isolated scene but hands nothing back to the live headers.
---------------------------------------------------------------------------
-- A scene suppresses no header, so the REGEN_DISABLED handler (which sets the headers up again whenever a preview
-- hid, because a preview retires its scope's header) must not run for a scene. The handler is live once the runtime
-- events are on; the header pass always ends in GF.ApplyBlizzardGroupFrameOwnership.
GF.RefreshHeaderLayout()
h:RunTimers()
local handoffs = 0
do
    local original = assert(GF.ApplyBlizzardGroupFrameOwnership, "the header pass no longer ends in the ownership handoff")
    GF.ApplyBlizzardGroupFrameOwnership = function(...)
        handoffs = handoffs + 1
        return original(...)
    end
end
Check(groupA:IsActive() and GF._previewActive.party ~= true and GF._previewActive.raid ~= true,
    "only an isolated scene should be open")
Check(GF.HidePreviewsForCombat() == false, "hiding an isolated scene for combat reported a hidden default preview")
Check(not groupA:IsActive(), "combat did not hide the isolated scene")
Check(groupA:Show(3, { immediate = true }) and groupA:IsActive(), "the isolated scene did not show again")
handoffs = 0
h:EnterCombat()
Check(not groupA:IsActive(), "the REGEN_DISABLED handler did not hide the isolated scene (the runtime events are off)")
Check(handoffs == 0, "combat with only an isolated scene open rebuilt the live headers (" .. handoffs .. " handoffs)")
h:LeaveCombat()
h:RunTimers()
Check(groupA:IsActive(), "combat end did not bring the isolated scene back")
-- Control: a default preview retires its header, so hiding it for combat does hand the block back.
Check(GF.ShowPreview("party", 3, { immediate = true }) == true, "the control preview did not show")
h:RunTimers()
handoffs = 0
h:EnterCombat()
Check(GF._previewActive.party ~= true, "combat did not hide the control preview")
Check(handoffs >= 1, "combat with a default preview open did not set the live headers up again; the spy is blind")
h:LeaveCombat()
h:RunTimers()
GF.HidePreview("party")

---------------------------------------------------------------------------
-- 11. A group whose root is not active shows nothing.
---------------------------------------------------------------------------
-- The root owns what is on screen: before Activate and after Deactivate a direct Show only records the wanted count.
local rootI = GF.NewPreviewScene(host)
local groupI = rootI:Group("party")
Check(groupI:Show(3, { immediate = true }) == false, "a group of an inactive root reported that it showed")
Check(not groupI:IsActive() and groupI:Frames() == nil, "a group of an inactive root built its frames")
Check(groupI:Container() == nil or not groupI:Container():IsShown(), "a group of an inactive root showed its container")
Check(groupI.want == 3, "the direct Show forgot the wanted count")
rootI:Activate()
h:RunTimers()
Check(groupI:IsActive() and #groupI:Frames() == 3 and groupI:Container():IsShown(), "activating the root did not show the wanted group")
rootI:Deactivate()
Check(groupI:Show(2, { immediate = true }) == false and not groupI:IsActive() and not groupI:Container():IsShown(),
    "a group of a deactivated root showed")
Check(groupI.want == 2, "a direct Show on a deactivated root forgot the wanted count")
rootI:Release()

---------------------------------------------------------------------------
-- 12. One member resolver: role, class, name and painted data follow the member, not the slot.
---------------------------------------------------------------------------
-- A second world whose PreviewMember (the one place that maps a grid slot to the sample member it shows) answers
-- from a test table. A frame's role, portrait class, sample name and data must all follow that answer.
local MEMBERS = {}
-- The boot loads the group preview file through loadfile: hand it the same source with the one resolver swapped.
local realLoadfile = loadfile
loadfile = function(path, ...)
    if type(path) ~= "string" or not path:find("MSUF_UF_Group_Preview.lua", 1, true) then return realLoadfile(path, ...) end
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local from, to = source:find("local function PreviewMember%(scene, slot%)%s+return slot%s+end")
    if not from then return nil, "PreviewMember is not one resolver that returns the slot" end
    source = source:sub(1, from - 1)
        .. "local function PreviewMember(scene, slot) return MSUF_TEST_PREVIEW_MEMBER(scene, slot) or slot end"
        .. source:sub(to + 1)
    return loadstring(source, "@" .. path)
end
local worldP = Harness.New(root, flavor, { beforeBoot = function(booting)
    booting.env.MAX_BOSS_FRAMES = 5
    booting.env.MSUF_TEST_PREVIEW_MEMBER = function(_, slot) return MEMBERS[slot] end
end })
loadfile = realLoadfile
local GFp, envp = worldP.GF, worldP.env
GFp.EnsureDB()
worldP.core.ExportPublic("MSUF2_GFPagePreviewActive", true)
local partyP = GFp.GetConf("party")
partyP.enabled, partyP.portraitMode, partyP.portraitRender = true, "LEFT", "CLASS"
partyP.textLeft, partyP.textCenter, partyP.textRight, partyP.showPowerText = "PERCENT", "NONE", "NONE", true
partyP.auras = partyP.auras or {}
partyP.auras.enabled, partyP.auras.renderer = true, "CUSTOM"
GFp.InvalidateCompiledSpecs("party")
local hostP = envp.CreateFrame("Frame", nil, envp.UIParent)
hostP:SetSize(400, 300)
local rootIdentity = GFp.NewPreviewScene(hostP)
rootIdentity:Activate()
local identity = rootIdentity:Group("party", 5, { immediate = true })
worldP:RunTimers()
Check(#identity:Frames() == 5, "the identity scene has the wrong count")
for slot, frame in ipairs(identity:Frames()) do
    Check(frame._msufGFPreviewIndex == slot, "with no resolver answer the member is not the slot")
end
-- Role, class, name and the member itself follow the answer; `painted` also compares the whole region tree with the
-- identity scene's frame of that member (a frame that was painted before keeps pooled hidden regions, so only a
-- freshly built scene is compared whole).
local function FollowMembers(group, order, label, painted)
    local frames, reference = group:Frames(), identity:Frames()
    Check(#frames == 5, label .. ": the permuted scene has the wrong count")
    local moved = false
    for slot = 1, 5 do
        local member, frame, twin = order[slot], frames[slot], reference[order[slot]]
        Check(frame._msufGFPreviewIndex == member, label .. ": slot " .. slot .. " does not hold member " .. member)
        Check(GFp.PreviewSampleRole(frame) == GFp.PreviewSampleRole(twin), label .. ": slot " .. slot .. " has the role of another member")
        Check(frame._msufPortraitSampleClass == twin._msufPortraitSampleClass, label .. ": slot " .. slot .. " has the class of another member")
        Check(frame.nameText.text == twin.nameText.text and frame.nameText.text ~= "", label .. ": slot " .. slot .. " shows the name of another member")
        if painted then
            local pairing, diffs = {}, {}
            CompareTrees(frame, twin, "frame", pairing, diffs)
            Check(#diffs == 0, label .. ": slot " .. slot .. " is not painted like member " .. member .. ": " .. tostring(diffs[1]))
        end
        if member ~= slot then
            moved = true
            Check(frame.nameText.text ~= reference[slot].nameText.text, label .. ": slot " .. slot .. " still shows its own slot's name")
        end
    end
    Check(moved, label .. ": the permutation moved nothing")
end
local function BuildPermuted(order)
    for slot = 1, 5 do MEMBERS[slot] = order[slot] end
    local builtRoot = GFp.NewPreviewScene(hostP)
    builtRoot:Activate()
    local built = builtRoot:Group("party", 5, { immediate = true })
    worldP:RunTimers()
    return built
end
local permuted = BuildPermuted({ 3, 1, 5, 2, 4 })
FollowMembers(permuted, { 3, 1, 5, 2, 4 }, "first order", true)
FollowMembers(BuildPermuted({ 5, 4, 3, 2, 1 }), { 5, 4, 3, 2, 1 }, "reversed order", true)
-- A new order takes effect on the next show of the same scene; a data refresh keeps it.
for slot, member in ipairs({ 5, 4, 3, 2, 1 }) do MEMBERS[slot] = member end
permuted:Show(5, { immediate = true })
worldP:RunTimers()
FollowMembers(permuted, { 5, 4, 3, 2, 1 }, "re-sorted scene")
permuted:RefreshData()
-- The aura refresh paints each frame as its member, not as its slot.
local auraPaints, paintAuras = {}, GFp.PreviewFrameAuras
GFp.PreviewFrameAuras = function(frame, kind, previewIndex, ...)
    auraPaints[frame] = previewIndex
    return paintAuras(frame, kind, previewIndex, ...)
end
permuted:RefreshAuras()
GFp.PreviewFrameAuras = paintAuras
for slot, frame in ipairs(permuted:Frames()) do
    Check(auraPaints[frame] == ({ 5, 4, 3, 2, 1 })[slot], "the aura refresh painted slot " .. slot .. " as member " .. tostring(auraPaints[frame]))
end
FollowMembers(permuted, { 5, 4, 3, 2, 1 }, "refreshed scene")

print("group_preview_scene_isolation_smoke: PASS (" .. flavor .. ")")

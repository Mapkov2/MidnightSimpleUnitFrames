_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

-- Some repository Lua files intentionally retain an UTF-8 BOM. WoW accepts
-- them, while the standalone Lua 5.1 loadfile does not, so the test loader
-- strips only that transport marker before compiling a chunk.
local function TestLoadfile(path)
    local handle, openError = io.open(path, "rb")
    if not handle then return nil, openError end
    local source = handle:read("*a")
    handle:close()
    if source:sub(1, 3) == string.char(239, 187, 191) then source = source:sub(4) end
    return (loadstring or load)(source, "@" .. path)
end
loadfile = TestLoadfile

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local function status(result)
    return result and (result.status or result.result)
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function resetTask()
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
end

local function patchSetting(key, initial)
    local setting = assert(Registry:GetSetting(key), "missing setting " .. key)
    local original = { get = setting.get, set = setting.set, apply = setting.apply }
    local box = { value = initial }
    setting.get = function() return box.value end
    setting.set = function(value) box.value = value end
    setting.apply = function() return true end
    return setting, box, original
end

local hideSetting, hideBox, hideOriginal = patchSetting(
    "auras3.player.buff.blacklist.hidePermanent", false)
local widthSetting, widthBox, widthOriginal = patchSetting("target.width", 275)
local sharedHealthTextSetting, sharedHealthTextBox, sharedHealthTextOriginal = patchSetting(
    "fontScope.shared.colorHealthTextByHealth", "DEFAULT")
local playerHealthTextSetting, playerHealthTextBox, playerHealthTextOriginal = patchSetting(
    "fontScope.player.colorHealthTextByHealth", "DEFAULT")
local sharedPowerTextSetting, sharedPowerTextBox, sharedPowerTextOriginal = patchSetting(
    "fontScope.shared.colorPowerTextByType", "DEFAULT")
local playerPowerTextSetting, playerPowerTextBox, playerPowerTextOriginal = patchSetting(
    "fontScope.player.colorPowerTextByType", "DEFAULT")
local sharedNameTextSetting, sharedNameTextBox, sharedNameTextOriginal = patchSetting(
    "fontScope.shared.nameColorMode", "DEFAULT")
local targetNPCNameTextSetting, targetNPCNameTextBox, targetNPCNameTextOriginal = patchSetting(
    "fontScope.target.npcNameRed", "DEFAULT")
local playerPortraitModeSetting, playerPortraitModeBox, playerPortraitModeOriginal = patchSetting(
    "player.portraitMode", "OFF")
local playerPortraitXSetting, playerPortraitXBox, playerPortraitXOriginal = patchSetting(
    "player.portraitOffsetX", 0)
local playerRootXSetting, playerRootXBox, playerRootXOriginal = patchSetting(
    "player.offsetX", -2)
local targetTargetNameAnchorSetting, targetTargetNameAnchorBox, targetTargetNameAnchorOriginal = patchSetting(
    "targettarget.nameTextAnchor", "RIGHT")
local targetTargetNameXSetting, targetTargetNameXBox, targetTargetNameXOriginal = patchSetting(
    "targettarget.nameOffsetX", 0)
local targetTargetRootXSetting, targetTargetRootXBox, targetTargetRootXOriginal = patchSetting(
    "targettarget.offsetX", 37)
local partyNameAnchorSetting, partyNameAnchorBox, partyNameAnchorOriginal = patchSetting(
    "gf_party.nameAnchor", "RIGHT")
local raidNameAnchorSetting, raidNameAnchorBox, raidNameAnchorOriginal = patchSetting(
    "gf_raid.nameAnchor", "LEFT")
local unitNameAnchorCases = {
    { scope = "player", key = "player.nameTextAnchor" },
    { scope = "target", key = "target.nameTextAnchor" },
    { scope = "focus", key = "focus.nameTextAnchor" },
    { scope = "pet", key = "pet.nameTextAnchor" },
    { scope = "boss", key = "boss.nameTextAnchor" },
    { scope = "focus target", key = "focustarget.nameTextAnchor" },
}
for i = 1, #unitNameAnchorCases do
    local item = unitNameAnchorCases[i]
    item.setting, item.box, item.original = patchSetting(item.key, "LEFT")
end
local groupAuraSpacingCases = {
    { scope = "party", prefix = "gf_party" },
    { scope = "raid", prefix = "gf_raid" },
    { scope = "mythic raid", prefix = "gf_mythicraid" },
}
for i = 1, #groupAuraSpacingCases do
    local item = groupAuraSpacingCases[i]
    item.buffSetting, item.buffBox, item.buffOriginal = patchSetting(
        item.prefix .. ".auras.buff.spacing", 2)
    item.debuffSetting, item.debuffBox, item.debuffOriginal = patchSetting(
        item.prefix .. ".auras.debuff.spacing", 2)
end
local partyBuffSizeSetting, partyBuffSizeBox, partyBuffSizeOriginal = patchSetting(
    "gf_party.auras.buff.size", 24)
local partyDebuffSizeSetting, partyDebuffSizeBox, partyDebuffSizeOriginal = patchSetting(
    "gf_party.auras.debuff.size", 26)
local playerRaidMarkerAnchorSetting, playerRaidMarkerAnchorBox, playerRaidMarkerAnchorOriginal = patchSetting(
    "player.raidMarkerAnchor", "TOPLEFT")
local playerRaidMarkerXSetting, playerRaidMarkerXBox, playerRaidMarkerXOriginal = patchSetting(
    "player.raidMarkerOffsetX", 16)

local portraitOwnerUnits = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss" }
for i = 1, #portraitOwnerUnits do
    local unit = portraitOwnerUnits[i]
    local mode = assert(Registry:GetSetting(unit .. ".portraitMode"), "missing " .. unit .. " portrait mode")
    local offset = assert(Registry:GetSetting(unit .. ".portraitOffsetX"), "missing " .. unit .. " portrait X offset")
    assert(A.ResolveContextAxisSetting(mode, "left") == offset,
        unit .. " portrait mode did not resolve to its own X offset")
end
assert(A.ResolveContextAxisSetting({
    unit = "player", frameType = "unitframe", category = "Portrait", attribute = "missingMode",
}, "left") == nil, "component without a local X companion fell back to the Player frame root")

resetTask()
playerPortraitModeBox.value, playerPortraitXBox.value, playerRootXBox.value = "OFF", 0, -2
local initialPortraitPlacement = assert(A.Submit("now move player portrait next to player left side"))
assert(status(initialPortraitPlacement) == "applied" or status(initialPortraitPlacement) == "unchanged",
    "initial portrait side relationship was not actionable")
assert(playerPortraitModeBox.value == "LEFT", "portrait relationship did not select the left portrait side")
assert(playerPortraitXBox.value == 0, "portrait relationship was misread as a local pixel nudge")
assert(playerRootXBox.value == -2, "portrait relationship moved the Player frame root")

resetTask()
playerPortraitModeBox.value, playerPortraitXBox.value, playerRootXBox.value = "LEFT", 0, -2
local repeatedPortraitPlacement = assert(A.Submit("now move player portrait next to player left side"))
assert(status(repeatedPortraitPlacement) == "unchanged", "repeated portrait relationship was not a no-op")
assert(playerPortraitModeBox.value == "LEFT" and playerPortraitXBox.value == 0,
    "repeated portrait relationship changed portrait state")
assert(playerRootXBox.value == -2, "repeated portrait relationship leaked into Player X Position")
assert(#A.undoStack == 0, "repeated portrait relationship created an undoable mutation")

resetTask()
playerPortraitModeBox.value, playerPortraitXBox.value, playerRootXBox.value = "LEFT", 0, -2
local numericPortraitMove = assert(A.Submit("move player portrait left 10"))
assert(status(numericPortraitMove) == "applied" or status(numericPortraitMove) == "unchanged",
    "numeric portrait movement was not actionable")
assert(playerPortraitModeBox.value == "LEFT", "numeric portrait movement changed its side mode")
assert(playerPortraitXBox.value == -10, "numeric portrait movement did not change Portrait X Position")
assert(playerRootXBox.value == -2, "numeric portrait movement changed Player X Position")

resetTask()
playerPortraitModeBox.value, playerPortraitXBox.value, playerRootXBox.value = "LEFT", 0, -2
local relativePortraitMove = assert(A.Submit("move player portrait more to the left"))
assert(status(relativePortraitMove) == "applied" or status(relativePortraitMove) == "unchanged",
    "relative portrait follow-up was not actionable")
assert(playerPortraitXBox.value == -10, "relative portrait follow-up did not use Portrait X Position")
assert(playerRootXBox.value == -2, "relative portrait follow-up changed Player X Position")

resetTask()
targetTargetNameAnchorBox.value, targetTargetNameXBox.value, targetTargetRootXBox.value = "RIGHT", 0, 37
local relativeNameMove = assert(A.Submit("move target of target name more to the right"))
assert(status(relativeNameMove) == "applied" or status(relativeNameMove) == "unchanged",
    "existing relative name follow-up stopped working")
assert(targetTargetNameXBox.value == 10, "relative name follow-up did not use Name X Position")
assert(targetTargetRootXBox.value == 37, "relative name follow-up changed the Target of Target frame root")

resetTask()
targetTargetNameAnchorBox.value, targetTargetNameXBox.value, targetTargetRootXBox.value = "RIGHT", 0, 37
local explicitNameAnchor = assert(A.HandleInput("set target of target name anchor to right"))
assert(status(explicitNameAnchor) == "unchanged", "explicit reviewed name-anchor no-op was not unchanged")
assert(lower(explicitNameAnchor.text):find("already set", 1, true),
    "explicit reviewed name-anchor no-op did not explain that the value was already set")
assert(targetTargetNameAnchorBox.value == "RIGHT", "explicit name-anchor no-op changed Name Text Anchor")
assert(targetTargetNameXBox.value == 0, "explicit name-anchor no-op leaked into Name X Position")
assert(targetTargetRootXBox.value == 37, "explicit name-anchor no-op changed the Target of Target frame root")
assert(#A.undoStack == 0, "explicit name-anchor no-op created an undoable mutation")

for i = 1, #unitNameAnchorCases do
    resetTask()
    local item = unitNameAnchorCases[i]
    item.box.value = "LEFT"
    local prompt = "set " .. item.scope .. " name anchor to right"
    local result = assert(A.HandleInput(prompt), prompt .. ": missing result")
    assert(status(result) == "applied", prompt .. ": public handler did not apply reviewed Name Text Anchor")
    assert(item.box.value == "RIGHT", prompt .. ": changed the wrong setting owner")
    assert(not lower(result.text):find("raw fallback", 1, true),
        prompt .. ": was intercepted by a generated compatibility shadow")
end

for i = 1, #groupAuraSpacingCases do
    resetTask()
    local item = groupAuraSpacingCases[i]
    item.buffBox.value, item.debuffBox.value = 2, 2
    local prompt = "set " .. item.scope .. " aura spacing to 4"
    local result = assert(A.HandleInput(prompt), prompt .. ": missing result")
    assert(status(result) == "applied", prompt .. ": public handler did not apply shared Aura Spacing")
    assert(item.buffBox.value == 4 and item.debuffBox.value == 4,
        prompt .. ": did not update the reviewed Buff and Debuff spacing pair")
    assert(#A.undoStack == 1, prompt .. ": did not create one compound undo transaction")
end

resetTask()
partyBuffSizeBox.value, partyDebuffSizeBox.value = 24, 26
local privateAuraLayout = assert(A.HandleInput("set party private aura size to 20"))
assert(status(privateAuraLayout) == "info", "Private Aura layout request did not fail closed as info")
assert(lower(privateAuraLayout.text):find("no standalone private aura", 1, true),
    "Private Aura layout request omitted the explicit capability boundary")
assert(partyBuffSizeBox.value == 24 and partyDebuffSizeBox.value == 26,
    "Private Aura layout request changed an ordinary Buff or Debuff size")
assert(#A.undoStack == 0, "Private Aura layout request created an undoable mutation")

resetTask()
partyNameAnchorBox.value = "RIGHT"
local explicitPartyNameAnchor = assert(A.HandleInput("set party name text anchor to left"))
assert(status(explicitPartyNameAnchor) == "applied", "reviewed Party Name Anchor write was not applied")
assert(partyNameAnchorBox.value == "LEFT", "Party name-text anchor wording did not write reviewed Party Name Anchor")
assert(not lower(explicitPartyNameAnchor.text):find("raw fallback", 1, true),
    "Party name-text anchor wording was intercepted by its generated compatibility shadow")

resetTask()
raidNameAnchorBox.value = "LEFT"
local explicitRaidNameAnchor = assert(A.HandleInput("set raid name text anchor to left"))
assert(status(explicitRaidNameAnchor) == "unchanged", "reviewed Raid Name Anchor no-op was not unchanged")
assert(lower(explicitRaidNameAnchor.text):find("already set", 1, true),
    "reviewed Raid Name Anchor no-op did not explain that the value was already set")
assert(raidNameAnchorBox.value == "LEFT", "Raid name-text anchor no-op changed the reviewed owner")
assert(#A.undoStack == 0, "Raid name-text anchor no-op created an undoable mutation")

resetTask()
playerRaidMarkerAnchorBox.value, playerRaidMarkerXBox.value, playerRootXBox.value = "TOPLEFT", 16, -2
local repeatedRaidMarkerPlacement = assert(A.Submit("move player raid marker to top left"))
assert(status(repeatedRaidMarkerPlacement) == "unchanged", "repeated fixed-corner placement was not a no-op")
assert(playerRaidMarkerXBox.value == 16, "fixed-corner placement became a Raid Marker pixel nudge")
assert(playerRootXBox.value == -2, "fixed-corner placement changed Player X Position")

local valueLessTextColorPrompts = {
    { "change global hp text color", sharedHealthTextBox, "shared health text color mode", { "default", "health" } },
    { "change shared health text color", sharedHealthTextBox, "shared health text color mode", { "default", "health" } },
    { "change player hp text color", playerHealthTextBox, "player health text color mode", { "default", "health" } },
    { "change global power text color", sharedPowerTextBox, "shared power text color mode", { "default", "resource" } },
    { "change player power text color", playerPowerTextBox, "player power text color mode", { "default", "resource" } },
    { "please change global name text color", sharedNameTextBox, "shared name text color mode", { "default", "class" } },
    { "modify target npc name color please", targetNPCNameTextBox, "target npc name text color", { "default", "npc", "class" } },
}
for i = 1, #valueLessTextColorPrompts do
    resetTask()
    local prompt, box, expectedControl, expectedValues = unpack(valueLessTextColorPrompts[i])
    box.value = "DEFAULT"
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local output = lower(result.text)
    assert(status(result) == "ambiguous", prompt .. ": expected a retained exact-control choice")
    assert(box.value == "DEFAULT", prompt .. ": guessed and wrote a text-color mode without a value")
    assert(#A.undoStack == 0, prompt .. ": created an undoable mutation without a value")
    assert(output:find(expectedControl, 1, true), prompt .. ": omitted the exact scoped text-color control: " .. output)
    for j = 1, #expectedValues do
        assert(output:find(expectedValues[j], 1, true), prompt .. ": omitted real value " .. expectedValues[j])
    end
    assert(not output:find("best place to start", 1, true), prompt .. ": fell back to generic page guidance")
    assert(not output:find("current group layout page", 1, true), prompt .. ": fell back to unrelated page choices")
end

resetTask()
sharedHealthTextBox.value = "DEFAULT"
assert(status(assert(A.Submit("change global hp text color"))) == "ambiguous")
local selectedHealthText = assert(A.Submit("2"), "global HP text color follow-up missing result")
assert(status(selectedHealthText) == "applied" or status(selectedHealthText) == "unchanged",
    "global HP text color follow-up did not apply the retained setting")
assert(sharedHealthTextBox.value == "HEALTH", "global HP text color follow-up changed the wrong value")

resetTask()
sharedPowerTextBox.value = "DEFAULT"
assert(status(assert(A.Submit("change global power text color"))) == "ambiguous")
local selectedPowerText = assert(A.Submit("2"), "global power text color follow-up missing result")
assert(status(selectedPowerText) == "applied" or status(selectedPowerText) == "unchanged",
    "global power text color follow-up did not apply the retained setting")
assert(sharedPowerTextBox.value == "RESOURCE", "global power text color follow-up changed the wrong value")

local refusalPrompts = {
    { "do not hide player buffs with no duration", true },
    { "never hide player buffs with no duration", false },
}
for i = 1, #refusalPrompts do
    resetTask()
    local prompt, initial = refusalPrompts[i][1], refusalPrompts[i][2]
    hideBox.value = initial
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    assert(status(result) == "info", prompt .. ": expected read-only info")
    assert(hideBox.value == initial, prompt .. ": changed Hide Permanent despite refusal")
    assert(#A.undoStack == 0, prompt .. ": created an undoable mutation")
    local output = lower(result.text)
    assert(output:find("unchanged", 1, true) or output:find("kept", 1, true)
        or output:find("did not", 1, true), prompt .. ": did not acknowledge unchanged state")
end

resetTask()
hideBox.value = false
local semanticFilter = assert(A.Submit("do not show player buffs that have no timer"))
assert(status(semanticFilter) == "applied" or status(semanticFilter) == "unchanged",
    "semantic no-timer filter was no longer actionable")
assert(hideBox.value == true, "semantic no-timer filter did not enable Hide Permanent")

local unsupported = {
    { "can you rotate player frame in 3D", "3d frame-rotation control" },
    { "can you add a weather radar", "weather data or a radar widget" },
    { "can you play chess", "cannot play chess" },
    { "is it possible to rotate player frame in 3D", "3d frame-rotation control" },
    { "could i add a weather radar", "weather data or a radar widget" },
}
for i = 1, #unsupported do
    resetTask()
    widthBox.value = 275
    local prompt, expected = unsupported[i][1], unsupported[i][2]
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local output = lower(result.text)
    assert(status(result) == "info", prompt .. ": expected read-only info")
    assert(output:find(expected, 1, true), prompt .. ": missing honest capability boundary: " .. output)
    assert(not output:match("^yes[%s%p]"), prompt .. ": answered an unsupported capability with yes")
    assert(output:find("unchanged", 1, true), prompt .. ": did not say settings were unchanged")
    assert(widthBox.value == 275 and #A.undoStack == 0, prompt .. ": mutated MSUF state")
end

resetTask()
widthBox.value = 275
local supported = assert(A.Submit("is it possible to change target width to 300"))
assert(status(supported) == "info", "verified capability question did not stay read-only")
assert(tostring(supported.text):find("Target Width", 1, true), "verified capability omitted its real control")
assert(widthBox.value == 275 and #A.undoStack == 0, "verified capability question changed Target Width")

resetTask()
widthBox.value = 275
local directPoliteWrite = assert(A.Submit("can you set target width to 300"))
assert(status(directPoliteWrite) == "applied" or status(directPoliteWrite) == "unchanged",
    "ordinary polite setting command was mistaken for a capability question")
assert(widthBox.value == 300, "ordinary polite setting command no longer changed Target Width")

resetTask()
widthBox.value = 275
local politeNumericAdd = assert(A.Submit("can you add 5 to target width"))
assert(status(politeNumericAdd) == "applied" or status(politeNumericAdd) == "unchanged",
    "polite numeric add was mistaken for an unsupported capability")
assert(widthBox.value == 280, "polite numeric add no longer adjusted Target Width: value="
    .. tostring(widthBox.value) .. " status=" .. tostring(status(politeNumericAdd))
    .. " text=" .. tostring(politeNumericAdd.text))

resetTask()
local politeAuraAdd = assert(A.Submit("can you add Rejuvenation to target buff blacklist"))
local auraOutput = lower(politeAuraAdd.text)
assert(not auraOutput:find("could not verify that as an msuf capability", 1, true),
    "polite aura-list action was intercepted as an unsupported capability")
assert(auraOutput:find("rejuvenation", 1, true) or auraOutput:find("blacklist", 1, true),
    "polite aura-list action did not reach aura guidance")

hideSetting.get, hideSetting.set, hideSetting.apply = hideOriginal.get, hideOriginal.set, hideOriginal.apply
widthSetting.get, widthSetting.set, widthSetting.apply = widthOriginal.get, widthOriginal.set, widthOriginal.apply
sharedHealthTextSetting.get, sharedHealthTextSetting.set, sharedHealthTextSetting.apply = sharedHealthTextOriginal.get, sharedHealthTextOriginal.set, sharedHealthTextOriginal.apply
playerHealthTextSetting.get, playerHealthTextSetting.set, playerHealthTextSetting.apply = playerHealthTextOriginal.get, playerHealthTextOriginal.set, playerHealthTextOriginal.apply
sharedPowerTextSetting.get, sharedPowerTextSetting.set, sharedPowerTextSetting.apply = sharedPowerTextOriginal.get, sharedPowerTextOriginal.set, sharedPowerTextOriginal.apply
playerPowerTextSetting.get, playerPowerTextSetting.set, playerPowerTextSetting.apply = playerPowerTextOriginal.get, playerPowerTextOriginal.set, playerPowerTextOriginal.apply
sharedNameTextSetting.get, sharedNameTextSetting.set, sharedNameTextSetting.apply = sharedNameTextOriginal.get, sharedNameTextOriginal.set, sharedNameTextOriginal.apply
targetNPCNameTextSetting.get, targetNPCNameTextSetting.set, targetNPCNameTextSetting.apply = targetNPCNameTextOriginal.get, targetNPCNameTextOriginal.set, targetNPCNameTextOriginal.apply
playerPortraitModeSetting.get, playerPortraitModeSetting.set, playerPortraitModeSetting.apply = playerPortraitModeOriginal.get, playerPortraitModeOriginal.set, playerPortraitModeOriginal.apply
playerPortraitXSetting.get, playerPortraitXSetting.set, playerPortraitXSetting.apply = playerPortraitXOriginal.get, playerPortraitXOriginal.set, playerPortraitXOriginal.apply
playerRootXSetting.get, playerRootXSetting.set, playerRootXSetting.apply = playerRootXOriginal.get, playerRootXOriginal.set, playerRootXOriginal.apply
targetTargetNameAnchorSetting.get, targetTargetNameAnchorSetting.set, targetTargetNameAnchorSetting.apply = targetTargetNameAnchorOriginal.get, targetTargetNameAnchorOriginal.set, targetTargetNameAnchorOriginal.apply
targetTargetNameXSetting.get, targetTargetNameXSetting.set, targetTargetNameXSetting.apply = targetTargetNameXOriginal.get, targetTargetNameXOriginal.set, targetTargetNameXOriginal.apply
targetTargetRootXSetting.get, targetTargetRootXSetting.set, targetTargetRootXSetting.apply = targetTargetRootXOriginal.get, targetTargetRootXOriginal.set, targetTargetRootXOriginal.apply
partyNameAnchorSetting.get, partyNameAnchorSetting.set, partyNameAnchorSetting.apply = partyNameAnchorOriginal.get, partyNameAnchorOriginal.set, partyNameAnchorOriginal.apply
raidNameAnchorSetting.get, raidNameAnchorSetting.set, raidNameAnchorSetting.apply = raidNameAnchorOriginal.get, raidNameAnchorOriginal.set, raidNameAnchorOriginal.apply
for i = 1, #unitNameAnchorCases do
    local item = unitNameAnchorCases[i]
    item.setting.get, item.setting.set, item.setting.apply = item.original.get, item.original.set, item.original.apply
end
for i = 1, #groupAuraSpacingCases do
    local item = groupAuraSpacingCases[i]
    item.buffSetting.get, item.buffSetting.set, item.buffSetting.apply = item.buffOriginal.get, item.buffOriginal.set, item.buffOriginal.apply
    item.debuffSetting.get, item.debuffSetting.set, item.debuffSetting.apply = item.debuffOriginal.get, item.debuffOriginal.set, item.debuffOriginal.apply
end
partyBuffSizeSetting.get, partyBuffSizeSetting.set, partyBuffSizeSetting.apply = partyBuffSizeOriginal.get, partyBuffSizeOriginal.set, partyBuffSizeOriginal.apply
partyDebuffSizeSetting.get, partyDebuffSizeSetting.set, partyDebuffSizeSetting.apply = partyDebuffSizeOriginal.get, partyDebuffSizeOriginal.set, partyDebuffSizeOriginal.apply
playerRaidMarkerAnchorSetting.get, playerRaidMarkerAnchorSetting.set, playerRaidMarkerAnchorSetting.apply = playerRaidMarkerAnchorOriginal.get, playerRaidMarkerAnchorOriginal.set, playerRaidMarkerAnchorOriginal.apply
playerRaidMarkerXSetting.get, playerRaidMarkerXSetting.set, playerRaidMarkerXSetting.apply = playerRaidMarkerXOriginal.get, playerRaidMarkerXOriginal.set, playerRaidMarkerXOriginal.apply

io.write("assistant_router_safety_regression: ok cases=48\n")

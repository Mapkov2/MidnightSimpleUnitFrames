local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local locale = flavor == "TBC" and "deDE" or "enUS"
local activeQuests, questReads, itemReads, mapID = {}, 0, 0, 2548
local instantReads, requestedItem, instantSecret = 0, nil, nil
local newSecret
local referenceNamesReady, withoutDisplayName, withoutIcon = flavor ~= "Forever", false, false
local world = dofile(root .. "/tools/tests/castbar_secret_world.lua").New(root, {
    flavor = flavor,
    setup = function(env)
        env.GetLocale = function() return locale end
        env.C_QuestLog = { IsOnQuest = function(id)
            questReads = questReads + 1
            return activeQuests[id] == true
        end }
        local oldSpellName = env.C_Spell.GetSpellName
        env.C_Spell.GetSpellName = function(id)
            if id == 3365 or id == 1308379 then
                return referenceNamesReady and "Opening" or nil
            end
            return oldSpellName(id)
        end
        local castInfo, channelInfo = env.UnitCastingInfo, env.UnitChannelInfo
        local function OverrideCastInfo(name, text, icon, ...)
            if withoutDisplayName then text = nil end
            if withoutIcon then icon = nil end
            return name, text, icon, ...
        end
        env.UnitCastingInfo = function(unit)
            if withoutDisplayName or withoutIcon then return OverrideCastInfo(castInfo(unit)) end
            return castInfo(unit)
        end
        env.UnitChannelInfo = function(unit)
            if withoutIcon then return OverrideCastInfo(channelInfo(unit)) end
            return channelInfo(unit)
        end
        env.C_Item = {
            RequestLoadItemDataByID = function(id) requestedItem = id end,
            GetItemInfoInstant = function(label)
                assert(not env.issecretvalue(label), "instant lookup received a secret")
                instantReads = instantReads + 1
                if label == "Lost Documents" or label == "Other object" then
                    local itemID = instantSecret == "id" and newSecret("number") or 1000
                    local icon = instantSecret == "icon" and newSecret("number") or 132784
                    return itemID, nil, nil, nil, icon
                end
            end,
            GetItemNameByID = function(id)
                assert(not env.issecretvalue(id), "item name lookup received a secret")
                if id == 1000 then
                    return instantSecret == "name" and newSecret("string") or "Lost Documents"
                end
                if id == 271620 and requestedItem == id then return "Kiste des Großknechts" end
            end,
            GetItemInfo = function(label)
                assert(not env.issecretvalue(label), "instance received a secret item name")
                itemReads = itemReads + 1
                if label == "Sealed Dispatch" then
                    return label, nil, nil, nil, nil, nil, nil, nil, nil, 132784
                end
            end,
        }
        env.C_Map = { GetBestMapForUnit = function() return mapID end }
        env.MAX_TOTEMS = 4
    end,
})
local env, core = world.env, world.core
newSecret = world.Secrets.New
core.Require("MSUF_EnsureDB", "castbar pickup test")(true)
local general = env.MSUF_DB.general
general.castbarPlayerShowTargetName = false
general.showGCDBar = false
core.Require("MSUF_Castbars_OnSettingsChanged", "castbar pickup test")()
world:Advance(.5)
local frame = assert(core.Castbars.Frames.Get("player"))
local texture, serial = nil, 0
local setTexture = frame.icon.SetTexture
function frame.icon:SetTexture(value, ...)
    texture = value
    return setTexture(self, value, ...)
end

local function Check(condition, message)
    assert(condition, flavor .. ": " .. message)
end

local function Cast(label, sentTarget, spellID, mismatch)
    serial = serial + 1
    local guid = "Cast-Pickup-" .. serial
    if sentTarget ~= nil then
        world:Broadcast("UNIT_SPELLCAST_SENT", "player", sentTarget, mismatch and guid .. "-other" or guid, spellID)
    end
    world:StartCast("player", label, 2, serial, { spellID = spellID, guid = guid })
    world:Fire(frame, "UNIT_SPELLCAST_START", "player", guid, spellID, serial)
    return guid
end

local function AcceptQuest(id)
    if core.Client.IsClassic then
        world:Broadcast("QUEST_ACCEPTED", 1, id)
    else
        world:Broadcast("QUEST_ACCEPTED", id)
    end
end

local normalIcon, appleIcon = 135812, 133975
local opening = 3365
local cactusQuest = (flavor == "Mainline" or flavor == "Mists") and 25136 or 4402
local quest = flavor == "Forever" and 95561 or cactusQuest
local name = flavor == "Forever" and "Fresh Apple" or (locale == "deDE" and "Kaktusapfel" or "Cactus Apple")

activeQuests[quest] = true
world:Broadcast("PLAYER_ENTERING_WORLD", false, true)
world.secretCasts, world.combat = false, true
world.base:EnterCombat()
local beforeCasts = questReads
AcceptQuest(42)
world:Broadcast("QUEST_REMOVED", 42)
local guid = Cast("Opening", name, opening)
Check(texture == appleIcon, "matched pickup must show the item icon from cast start with target text disabled")
Check(not frame.castTargetText:IsShown(), "pickup must not turn on the target text")
world:Fire(frame, "UNIT_SPELLCAST_DELAYED", "player", guid, opening, serial)
Check(texture == appleIcon, "cast refresh lost the item icon")
world.casting.player = nil
world:Fire(frame, "UNIT_SPELLCAST_INTERRUPTED", "player", guid, opening, nil, serial)
Check(texture == appleIcon, "interrupted feedback lost the item icon")

local pickupSpell = flavor == "Forever" and opening or 2366
guid = Cast(name, nil, pickupSpell)
Check(texture == appleIcon, "a public cast label must work without SENT")
world.casting.player = nil
world:Fire(frame, "UNIT_SPELLCAST_STOP", "player", guid, pickupSpell, serial)
world:Fire(frame, "UNIT_SPELLCAST_INTERRUPTED", "player", guid, pickupSpell, nil, serial)
Check(texture == appleIcon, "STOP before INTERRUPTED lost the item icon")
Cast("Opening", name, opening, true)
Check(texture == normalIcon, "a mismatched cast GUID reused the item icon")
Cast("Healing Spell", name, 133)
Check(texture == normalIcon, "an ordinary spell reused the item icon")
Cast("Opening", "Other object", opening)
Check(texture == normalIcon, "an unknown object reused the item icon")
Check(questReads == beforeCasts, "cast events should not query the quest log")
if flavor ~= "Forever" then
    activeQuests[95561] = true
    AcceptQuest(95561)
    Cast("Fresh Apple", nil, opening)
    Check(texture == normalIcon, "Forever-only item appeared in another client")
end

if flavor == "Forever" then
    withoutDisplayName = true
    Cast("Opening", world.Secrets.New("string"), 1308379)
    Check(texture == appleIcon, "live Fresh Apple spell ID must work before reference names load and with no display name")
    withoutDisplayName, referenceNamesReady = false, true
    world:Broadcast("PLAYER_ENTERING_WORLD", false, false)
    mapID = 1415
    Cast("Opening", world.Secrets.New("string"), 1308379)
    Check(texture == normalIcon, "a shared opening spell outside Riverglades showed the apple icon")
    mapID = 2548

    local crateQuest, crateIcon = 95943, 132594
    activeQuests[crateQuest] = true
    AcceptQuest(crateQuest)
    Cast("Opening", "Foreman's Crate", 6478)
    Check(texture == crateIcon, "Foreman's Crate fell back to the opening icon on a cold item lookup")
    Check(requestedItem == 271620, "accepting the crate quest did not request localized item data")
    Cast("Opening", "Kiste des Großknechts", 22810)
    Check(texture == crateIcon, "localized crate name did not resolve")
    Cast("Foreman's Crate", nil, 22810)
    Check(texture == crateIcon, "a public crate cast label without SENT did not resolve")
    Cast("Frostbolt", "Foreman's Crate", 116)
    Check(texture == normalIcon, "ordinary spells must keep their icon")
    activeQuests[crateQuest] = false
    world:Broadcast("QUEST_REMOVED", crateQuest)
    Cast("Opening", "Foreman's Crate", 6478)
    Check(texture == normalIcon, "a completed crate quest still overrode the icon")
end

local previousItemReads = itemReads
local genericGUID = Cast("Opening", "Sealed Dispatch", 214058)
Check(texture == 132784, "a public object name with a matching item must resolve an unlisted opening cast")
world:Fire(frame, "UNIT_SPELLCAST_DELAYED", "player", genericGUID, 214058, serial)
Check(texture == 132784 and itemReads == previousItemReads + 1, "cast refresh must reuse the resolved item")
Cast("Healing Spell", "Sealed Dispatch", 133)
Check(texture == normalIcon and itemReads == previousItemReads + 1, "a normal cast queried item data")

local previousInstantReads = instantReads
genericGUID = Cast("Opening", "Lost Documents", 214058)
Check(texture == 132784, "an exact instant item match must work before full item info loads")
world:Fire(frame, "UNIT_SPELLCAST_DELAYED", "player", genericGUID, 214058, serial)
Check(texture == 132784 and instantReads == previousInstantReads + 1, "cast refresh repeated the instant lookup")

genericGUID = Cast("Opening", "Sealed Dispatch", 214058)
Check(texture == 132784, "missing-icon fixture did not paint a pickup texture first")
world.casting.player = nil
world:Fire(frame, "UNIT_SPELLCAST_STOP", "player", genericGUID, 214058, serial)
withoutIcon = true
Cast("Frostbolt", nil, 116)
Check(texture == nil, "a normal cast with no texture kept the pickup icon")
withoutIcon = false

if core.Client.HasEmpoweredCasts then
    local function EmpowerAfterPickup(missingTexture)
        local guid = Cast("Opening", "Sealed Dispatch", 214058)
        Check(texture == 132784, "empower handoff fixture did not paint the pickup icon")
        world.casting.player = nil
        world:Fire(frame, "UNIT_SPELLCAST_STOP", "player", guid, 214058, serial)
        local barID = serial + 100
        withoutIcon = missingTexture
        world:StartChannel("player", "Fire Breath", 1.2, barID, { empowered = true, spellID = 357208 })
        world:Fire(frame, "UNIT_SPELLCAST_EMPOWER_START", "player", "Empower", 357208, barID)
        withoutIcon = false
        return barID
    end

    local empowerBarID = EmpowerAfterPickup(false)
    Check(texture == 136208, "an empower cast must use its own texture after a pickup")
    world.channeling.player = nil
    world:Fire(frame, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "Empower", 357208, true, nil, empowerBarID)
    withoutIcon = true
    Cast("Frostbolt", nil, 116)
    Check(texture == 136208, "a missing texture must not clear an icon from an intervening empower")
    withoutIcon = false

    empowerBarID = EmpowerAfterPickup(true)
    Check(texture == nil, "an empower cast with no texture kept the pickup icon")
    world.channeling.player = nil
    world:Fire(frame, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "Empower", 357208, true, nil, empowerBarID)
end

if core.Client.IsRetail then
    local applySettings = core.Require("MSUF_Castbars_OnSettingsChanged", "GCD pickup handoff test")
    local gcdDriver = assert(world:Named("MSUF_GCDBarDriver"))
    local gcdSpellID = 1449
    env.MSUF_DB.general.showGCDBar = true
    world.secretCooldowns = false
    for _, showSpell in ipairs({ true, false }) do
        env.MSUF_DB.general.showGCDBarSpell = showSpell
        applySettings()
        local guid = Cast("Opening", "Sealed Dispatch", 214058)
        Check(texture == 132784, "GCD handoff fixture did not paint the pickup icon")
        world.casting.player = nil
        world:Fire(frame, "UNIT_SPELLCAST_STOP", "player", guid, 214058, serial)
        world.cooldowns[61304] = { startTime = world.clock, total = 1.5 }
        world:Fire(gcdDriver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, gcdSpellID)
        Check(frame._msufGCDActive == true, "integrated GCD did not start")
        local expected = showSpell and env.C_Spell.GetSpellInfo(gcdSpellID).iconID or nil
        Check(texture == expected, "integrated GCD kept the pickup texture")
        world:Advance(1.6)
        withoutIcon = true
        Cast("Frostbolt", nil, 116)
        Check(texture == expected, "a missing texture must not clear an icon from an intervening GCD")
        withoutIcon = false
    end
    env.MSUF_DB.general.showGCDBar = false
    applySettings()
end

local beforeSecrets = #world.errors
local runtime = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"
local stopWatch = world.Secrets.Watch(runtime, { strict = true })
if flavor == "Forever" then
    mapID = world.Secrets.New("number")
    Cast("Opening", world.Secrets.New("string"), 1308379)
    Check(texture == normalIcon, "a secret map ID must not enable a zone-scoped pickup")
    mapID = 2548
end
Cast("Opening", world.Secrets.New("string"), opening)
Check(texture == normalIcon, "a secret target name must use the original icon")
world:Broadcast("UNIT_SPELLCAST_SENT", "player", name, "Cast-Pickup-" .. (serial + 1), world.Secrets.New("number"))
Cast("Opening", nil, opening)
Check(texture == normalIcon, "a secret SENT spell ID must not identify the pickup")
world:Broadcast("UNIT_SPELLCAST_SENT", "player", name, world.Secrets.New("string"), opening)
Cast("Opening", nil, opening)
Check(texture == normalIcon, "a secret SENT cast GUID must not bind the target")
Cast("Opening", "Sealed Dispatch", 214058)
Check(texture == 132784, "secret-icon fixture did not paint a pickup texture first")
world.secretCasts = true
Cast("Fireball", nil, 133)
Check(world.Secrets.IsSecret(texture), "a secret normal cast after pickup must forward its own texture")
world.secretCasts = false
for _, field in ipairs({ "id", "icon", "name" }) do
    instantSecret = field
    Cast("Opening", "Lost Documents", 214058)
    Check(texture == normalIcon, "secret instant-lookup " .. field .. " must retain the original texture")
end
instantSecret = nil
local violations = stopWatch()
Check(#violations == 0, table.concat(violations, "; "))
Check(#world.errors == beforeSecrets, table.concat(world.errors, "; "))

local sentPlayer, sentVehicle
local registerUnitEvent = frame.RegisterUnitEvent
function frame:RegisterUnitEvent(event, first, second, ...)
    if event == "UNIT_SPELLCAST_SENT" then sentPlayer, sentVehicle = first, second end
    return registerUnitEvent(self, event, first, second, ...)
end
env.MSUF_DB.general.castbarPlayerShowTargetName = true
core.Require("MSUF_Castbars_OnSettingsChanged", "castbar pickup test")()
Check(sentPlayer == "player" and sentVehicle == "vehicle", "target text did not restore both SENT units")
Check(frame.events.UNIT_SPELLCAST_SUCCEEDED, "target text lost its success event")
Cast("Opening", name, opening)
Check(texture == appleIcon and frame.castTargetText.text == name, "target text and pickup icon did not work together")
env.MSUF_DB.general.castbarPlayerShowTargetName = false
core.Require("MSUF_Castbars_OnSettingsChanged", "castbar pickup test")()
Check(sentPlayer == "player" and sentVehicle == nil, "pickup-only SENT must register just the player")
Check(not frame.events.UNIT_SPELLCAST_SUCCEEDED, "pickup-only mode kept the success listener")

world:Broadcast("QUEST_REMOVED", quest)
activeQuests[quest] = nil
Cast(name, name, opening)
Check(texture == normalIcon, "an inactive quest reused the item icon")
Check(frame.events.UNIT_SPELLCAST_SENT and not frame.events.UNIT_SPELLCAST_SUCCEEDED,
    "general pickups need SENT but must not enable the target success listener")
Cast("Opening", "Sealed Dispatch", 214058)
Check(texture == 132784, "general item pickup still depends on an apple quest")
Cast("Sealed Dispatch", nil, opening)
Check(texture == 132784, "a public item name in the cast display needs no SENT data")
AcceptQuest(quest)
Cast("Opening", name, opening)
Check(texture == appleIcon, "quest acceptance must arm pickup capture immediately")
print("player pickup icon: " .. flavor .. " passed")

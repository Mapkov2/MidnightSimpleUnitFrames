_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[clone(key, seen)] = clone(item, seen) end
    return out
end

local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not equal(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function snapshotSettings()
    local out = {}
    local settings = Registry:AllSettings() or {}
    for i = 1, #settings do
        local setting = settings[i]
        if setting and setting.key and type(setting.get) == "function" then
            local ok, value = pcall(setting.get)
            if ok then out[setting.key] = clone(value) end
        end
    end
    return out
end

local function snapshotConfigDB()
    local out = {}
    for key, value in pairs(type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}) do
        -- Conversation history, turn serials, and pending read-only choices are
        -- expected Assistant state. Every actual addon configuration branch
        -- must remain byte-for-byte equivalent across an informational turn.
        if key ~= "assistant" then out[clone(key)] = clone(value) end
    end
    return out
end

local function assertNoSettingWrite(prompt)
    local before = snapshotSettings()
    local dbBefore = snapshotConfigDB()
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local after = snapshotSettings()
    local changed = {}
    for key, value in pairs(before) do
        if not equal(value, after[key]) then changed[#changed + 1] = key end
    end
    for key in pairs(after) do
        if before[key] == nil then changed[#changed + 1] = key end
    end
    table.sort(changed)
    assert(#changed == 0, prompt .. ": read-only intent changed settings: " .. table.concat(changed, ", ") .. "; output=" .. tostring(result.text))
    assert(equal(dbBefore, snapshotConfigDB()), prompt .. ": read-only intent changed MSUF config DB; output=" .. tostring(result.text))
    local status = tostring(result.status or result.result or "")
    assert(status ~= "applied" and status ~= "changed", prompt .. ": read-only intent reported mutation status " .. status)
    return result
end

local readOnlyPrompts = {
    "totem frame is gone",
    "crosshair is missing",
    "list castbar interrupt color options",
    "hide useless buffs",
    "show important debuffs",
    "can exact SpellID blacklists hide friendly debuffs",
    "can I turn off the moon icon on player frame?",
    "ziel buffs weg",
    "ziel buffs fehlen",
    "target buffs failed",
    "bitte repariere ziel buffs",
    "repariere fehlende ziel buffs",
    "party frames weg",
    "party frames versteckt",
    "raid frames weg",
    "raid frames ausgeblendet",
    "raid frames are too far apart",
    "party buffs weg",
    "raid buffs weg",
    "mythic raid buffs weg",
    "party debuffs gone",
    "can I turn off the moon icon on player frame?",
    "how do I hide player name?",
    -- Exact in-game interactive acceptance sequence from AssistantAudit.lua.
    "what is target frame width",
    "where is raid ready check",
    "what depends on target buffs",
    "why is player power text hidden",
    "how do profiles work",
    "explain class resource width mode",
    "where can I change castbar texture",
    "why are party frames missing",
    "what are your limits",
    "answer in German what is aura filtering",
}

for i = 1, #readOnlyPrompts do assertNoSettingWrite(readOnlyPrompts[i]) end

local marker = assert(Registry:GetSetting("target.showRaidMarker"), "target raid marker setting missing")
marker.set(true)
local markerResult = assert(A.Submit("disable skull marker on target frame"), "marker command missing result")
assert(marker.get() == false, "marker command did not disable target.showRaidMarker")
assert(tostring(markerResult.text or ""):find("Target Raid Marker", 1, true), "marker command did not identify Target Raid Marker")

local targetEnabled = assert(Registry:GetSetting("target.enabled"), "target root setting missing")
assert(targetEnabled.get() ~= false, "marker command disabled the Target frame root")

local targetBuffs = assert(Registry:GetSetting("auras3.target.buff.visible"), "target buff setting missing")
targetBuffs.set(true)
local exactHideResult = assert(A.Submit("hide Rejuvenation in target buffs"), "exact target blacklist command missing result")
assert(targetBuffs.get() == true, "exact target blacklist command disabled the whole Target Buff lane")
assert(not (exactHideResult.changes and exactHideResult.changes[1]), "exact target blacklist command returned a broad setting mutation")

local raidBuffs = assert(Registry:GetSetting("gf_raid.auras.buff.enabled"), "raid buff setting missing")
raidBuffs.set(false)
local exactAllowResult = assert(A.Submit("allow Rejuvenation in raid buffs"), "exact raid allow command missing result")
assert(raidBuffs.get() == false, "exact raid allow command enabled the whole Raid Buff lane")
assert(not (exactAllowResult.changes and exactAllowResult.changes[1]), "exact raid allow command returned a broad setting mutation")

local buffResult = assert(A.Submit("turn off target buffs"), "target buff command missing result")
assert(targetBuffs.get() == false, "explicit target buff command was incorrectly blocked")
assert(tostring(buffResult.text or ""):find("Target Buffs", 1, true), "target buff command changed the wrong setting")

print("assistant_prompt_intent_safety_audit: ok")

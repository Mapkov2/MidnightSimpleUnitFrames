-- A fade duration or fade alpha is inert while the feature that owns it is off.
-- The Assistant used to write the number alone and report success, so the player
-- saw nothing change ("set name fade in to 0.25" with Name Text Mouseover off,
-- answered by "you forgot to turn on name fade"). Every write funnels through
-- ExecuteChanges, so the owner is switched on there, in the same transaction.
-- Source model: runs the real AP.AddFadeFeatureGates against a registry stub.
local root = arg[1] or "."

local function Read(path)
    local file = assert(io.open(path, "rb"), "missing " .. path)
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local ASSISTANT = root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_Assistant.lua"
local source = Read(ASSISTANT)

local first = assert(source:find("AP.FadeFeatureGates = {", 1, true), "fade gate table missing")
local last = assert(source:find("\nend\n", source:find("function AP.AddFadeFeatureGates", 1, true), true),
    "AddFadeFeatureGates unterminated")
local AP, Registry = {}, {}
assert(loadstring("local AP, Registry = ...\n" .. source:sub(first, last + 4), "fadegate"))(AP, Registry)

-- Registry stub: only what the gate expander touches.
local db = {}
local settings = {}
local function Define(key, value)
    db[key] = value
    settings[key] = {
        key = key,
        get = function() return db[key] end,
        set = function(v) db[key] = v end,
    }
    return settings[key]
end
function Registry:GetSetting(key) return settings[key] end

local SCOPES = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }
local PAIRS = {
    { "nameTextMouseoverFadeIn", "nameTextMouseover" },
    { "nameTextMouseoverFadeOut", "nameTextMouseover" },
    { "hpTextMouseoverFadeIn", "hpTextMouseover" },
    { "hpTextMouseoverFadeOut", "hpTextMouseover" },
    { "powerTextMouseoverFadeIn", "powerTextMouseover" },
    { "powerTextMouseoverFadeOut", "powerTextMouseover" },
    { "oocFadeAlpha", "oocFadeEnabled" },
    { "rangeFadeAlpha", "rangeFadeEnabled" },
}
for _, scope in ipairs(SCOPES) do
    for _, pair in ipairs(PAIRS) do
        Define(scope .. "." .. pair[1], 0)
        Define(scope .. "." .. pair[2], false)
    end
end
Define("player.nameTextSize", 12)

local function Keys(changes)
    local out = {}
    for i = 1, #changes do out[i] = changes[i].setting.key end
    return out
end

-- 1. The reported case, on every unit frame and every fade pair.
local covered = 0
for _, scope in ipairs(SCOPES) do
    for _, pair in ipairs(PAIRS) do
        local valueKey, gateKey = scope .. "." .. pair[1], scope .. "." .. pair[2]
        db[gateKey] = false
        local changes = AP.AddFadeFeatureGates({ { setting = settings[valueKey], value = 0.25 } })
        assert(#changes == 2, "no gate added for " .. valueKey)
        assert(changes[1].setting.key == gateKey,
            "gate is not first: got " .. tostring(changes[1].setting.key) .. " for " .. valueKey)
        assert(changes[1].value == true, "gate not switched on for " .. valueKey)
        assert(changes[2].setting.key == valueKey, "the requested change was displaced")
        covered = covered + 1
    end
end
print("gated pairs covered: " .. covered .. " across " .. #SCOPES .. " unit frames")

-- 2. Already on: nothing added, so the reply stays a single change.
db["player.nameTextMouseover"] = true
local on = AP.AddFadeFeatureGates({ { setting = settings["player.nameTextMouseoverFadeIn"], value = 0.25 } })
assert(#on == 1, "gate added while the feature was already on")

-- 3. An explicit off in the same plan is the player's word and must stand.
db["player.nameTextMouseover"] = false
local both = AP.AddFadeFeatureGates({
    { setting = settings["player.nameTextMouseover"], value = false },
    { setting = settings["player.nameTextMouseoverFadeIn"], value = 0.25 },
})
assert(#both == 2, "an explicit off was overridden: " .. table.concat(Keys(both), ", "))
assert(both[1].value == false, "the player's off was flipped on")

-- 3b. A plan paused for combat is re-executed later against the same table, so
--     expanding it twice must not stack a second copy of the gate.
db["player.nameTextMouseover"] = false
local queued = { { setting = settings["player.nameTextMouseoverFadeIn"], value = 0.25 } }
AP.AddFadeFeatureGates(queued)
AP.AddFadeFeatureGates(queued)
assert(#queued == 2, "re-expansion stacked duplicates: " .. table.concat(Keys(queued), ", "))

-- 4. Ungated settings are untouched.
local plain = AP.AddFadeFeatureGates({ { setting = settings["player.nameTextSize"], value = 14 } })
assert(#plain == 1, "an ungated setting grew a companion")

-- 5. One gate serves both of its fades, and scopes never cross.
db["player.nameTextMouseover"] = false
db["target.nameTextMouseover"] = false
local pair = AP.AddFadeFeatureGates({
    { setting = settings["player.nameTextMouseoverFadeIn"], value = 0.25 },
    { setting = settings["player.nameTextMouseoverFadeOut"], value = 0.4 },
    { setting = settings["target.nameTextMouseoverFadeIn"], value = 0.25 },
})
assert(#pair == 5, "expected two gates for three fades, got " .. #pair .. ": " .. table.concat(Keys(pair), ", "))
local gates = {}
for i = 1, #pair do
    if pair[i].companion then gates[pair[i].setting.key] = true end
end
assert(gates["player.nameTextMouseover"] and gates["target.nameTextMouseover"],
    "each scope must switch on its own gate")

-- 6. Every gated key the expander knows must exist in the shipped schema, and
--    must name a real gate there: a typo would silently do nothing forever.
local schema = Read(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua")
local checked = 0
for leaf, gateLeaf in pairs(AP.FadeFeatureGates) do
    local found, gateFound = false, false
    for _, scope in ipairs(SCOPES) do
        if schema:find("'" .. scope .. "." .. leaf .. "'", 1, true) then found = true end
        if schema:find("'" .. scope .. "." .. gateLeaf .. "'", 1, true) then gateFound = true end
    end
    assert(found, "gated key is in no schema record: " .. leaf)
    assert(gateFound, "gate key is in no schema record: " .. gateLeaf)
    checked = checked + 1
end
print("schema-backed gate mappings: " .. checked)

-- The expander only helps if ExecuteChanges actually runs it; both call sites
-- reach the plan through that one function.
local body = source:match("local function ExecuteChanges%(plan%)\n(.-)\n")
assert(body and body:find("AP.AddFadeFeatureGates(plan.changes", 1, true),
    "ExecuteChanges no longer expands fade gates")
print("assistant_fade_gate_smoke: fade values switch on the feature that owns them")

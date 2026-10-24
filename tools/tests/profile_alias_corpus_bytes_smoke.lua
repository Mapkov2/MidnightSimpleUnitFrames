-- Alias contexts preserve the previous transformations; optional exact full corpus dumps.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local units = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local groups = { "gf_party", "gf_raid", "gf_mythicraid" }
local narrow = { "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local wide = {
    "general", "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget",
    "boss", "boss1", "boss2", "boss3", "boss4", "arena", "arena1", "arena2", "arena3",
    "gf_party", "gf_raid", "gf_mythicraid",
}
local anchors = { global = "GLOBAL", free = "FREE", tot = "targettarget", targetoftarget = "targettarget",
    focus_target = "focustarget", focustargettarget = "focustarget" }
-- Independent pre-refactor position rules, including the narrower boot context.
local function LegacyPosition(scope, extended)
    if type(scope) ~= "table" then return end
    local function Alias(key, old)
        if scope[key] == nil then scope[key] = scope[old] end
    end
    local function Number(key, low, high)
        local value = tonumber(scope[key])
        if value ~= nil then scope[key] = math.max(low, math.min(high, value)) end
    end
    Alias("point", "anchorMyPoint")
    Alias("relativePoint", "anchorRelPoint")
    if extended then
        if scope.anchorFrameName == "UI_Parent" then scope.anchorFrameName = "UIParent" end
        Alias("offsetX", "x")
        Alias("offsetY", "y")
        Alias("width", "frameWidth")
        Alias("height", "frameHeight")
        for _, key in ipairs({ "x", "y", "spacing" }) do Number(key, -4096, 4096) end
        for _, key in ipairs({ "width", "height", "frameWidth", "frameHeight" }) do Number(key, 1, 4096) end
        local anchor = scope.anchorToUnitframe
        if type(anchor) == "string" then
            if anchors[anchor] then scope.anchorToUnitframe = anchors[anchor]
            elseif anchor:match("^boss%d+$") then scope.anchorToUnitframe = "boss"
            elseif anchor:match("^arena%d+$") then scope.anchorToUnitframe = "arena" end
        end
    end
    local limit = extended and 4096 or 10000
    Number("offsetX", -limit, limit)
    Number("offsetY", -limit, limit)
    for _, key in ipairs({ "point", "relativePoint" }) do
        if type(scope[key]) == "string" then
            if extended and scope[key] == "" then scope[key] = nil
            else scope[key] = scope[key]:upper() end
        end
    end
end
local function Contexts(world, profile, label)
    local S = world.core.StateHelpers
    for _, context in ipairs({ "defaults", "profileio" }) do
        local actual, expected = Copy(profile), Copy(profile)
        local extended = context == "profileio"
        local positions = extended and units or narrow
        for _, key in ipairs(positions) do
            LegacyPosition(expected[key], extended)
            S.NormalizePositionAliases(actual[key], context)
        end
        if extended then
            for i = 1, 5 do
                LegacyPosition(expected["boss" .. i], true)
                S.NormalizePositionAliases(actual["boss" .. i], context)
            end
            for i = 1, S.AliasMigrations.ArenaSlots do
                LegacyPosition(expected["arena" .. i], true)
                S.NormalizePositionAliases(actual["arena" .. i], context)
            end
        end
        local spec = extended and S.ProfileIOSpec or S.DefaultsSpec
        for _, key in ipairs(extended and wide or narrow) do
            local group = key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid"
            S.NormalizeTextScope(expected[key], group, spec, extended and key ~= "general")
            S.NormalizeStatusScope(expected[key], group, spec)
        end
        if not extended then
            for _, key in ipairs(groups) do
                S.NormalizeTextScope(expected[key], true, spec)
                S.NormalizeStatusScope(expected[key], true, spec)
            end
        end
        S.NormalizeProfileTextAliases(actual, context)
        assert(H.Literal(actual) == H.Literal(expected), label .. ": alias context differs: " .. context)
    end
end
if not arg[3] then
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, {})
    local ledger = world.core.StateHelpers.AliasMigrations
    local owners = {
        { canonical = "targettarget", aliases = { "tot", "targetoftarget", "target_of_target" } },
        { canonical = "focustarget", aliases = { "focus_target", "focustargettarget" } },
    }
    assert(H.Literal(ledger.UnitOwners) == H.Literal(owners), "unit owner aliases changed")
    local slots = ledger.ArenaSlots
    for i = 4, slots do wide[#wide + 1] = "arena" .. i end
    Contexts(world, world.env.MSUF_DB, "factory")
    local adversarial = {}
    for _, key in ipairs(wide) do
        adversarial[key] = { anchorMyPoint = "bottom", relativePoint = "", x = "9000", y = "-9000",
            frameWidth = "0", frameHeight = "5000", spacing = "9000", anchorToUnitframe = "tot",
            anchorFrameName = "UI_Parent", nameNoEllipsis = false, hideName = 1, fontSize = "15" }
    end
    adversarial.tot = Copy(adversarial.target)
    Contexts(world, adversarial, "adversarial")
    local count = 0
    for _, entry in ipairs(C.EntriesFor(root, flavor)) do
        if entry.kind == "sv" then
            local saved = C.LoadSavedVariablesFixture(root, entry.file)
            if saved.MSUF_DB then Contexts(world, saved.MSUF_DB, entry.id .. "/standalone") end
            for name, profile in pairs((saved.MSUF_GlobalDB or {}).profiles or {}) do
                Contexts(world, profile, entry.id .. "/" .. name)
            end
            count = count + 1
        end
    end
    print("PASS profile_alias_corpus_bytes_smoke " .. flavor .. " context corpus " .. count)
    return
end
local count = 0
for _, entry in ipairs(C.EntriesFor(root, flavor)) do
    local run = C.RunEntry(root, entry, flavor)
    local parts = {}
    for _, subtree in ipairs(run.subtrees) do parts[#parts + 1] = subtree.name .. "\n" .. H.Literal(subtree.value) end
    local dump = table.concat(parts, "\n")
    local path = arg[3] .. "/" .. flavor .. "-" .. entry.id .. ".dump"
    if arg[4] == "--capture" then
        local file = assert(io.open(path, "wb"))
        file:write(dump)
        file:close()
    else
        local file = assert(io.open(path, "rb"))
        local before = file:read("*a")
        file:close()
        assert(before == dump, "profile bytes differ: " .. flavor .. "/" .. entry.id)
    end
    count = count + 1
end
print("PASS profile_alias_corpus_bytes_smoke " .. flavor .. " " .. count .. " complete dumps")

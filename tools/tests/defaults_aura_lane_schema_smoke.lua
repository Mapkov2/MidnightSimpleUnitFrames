-- defaults_aura_lane_schema_smoke.lua <repoRoot>
--
-- State/MSUF_Defaults.lua materializes the unit aura lane owners with its own
-- copy of the Buff and Debuff lane keys (MSUF_DEFAULTS_UNIT_AURA_LANES): it
-- loads before Auras3/MSUF_Auras3_Core.lua on every client TOC, so it cannot
-- read the aura core's schema while it loads. This smoke pins that copy to the
-- aura schema's lane specs, key by key, so the two cannot drift:
--   * A3.LaneKeySchema.LANE_SPECS when the aura core publishes it (wave 4,
--     the single lane-key source), read from each client's booted core graph;
--   * otherwise the lane specs the menu schema declares
--     (Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua, GROUPS).
-- Every field of the Defaults copy must equal the schema's; its prefix must be
-- the one the schema's keys carry. Saved keys and defaults are not touched.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- The table constructor that follows `marker`, evaluated as data.
local function TableAfter(path, marker)
    local text = World.Read(root .. "/" .. path)
    local start = assert(text:find(marker, 1, true), path .. ": no " .. marker)
    local open = assert(text:find("{", start + #marker - 1, true), path .. ": no table after " .. marker)
    local depth, index = 0, open
    while true do
        local char = text:sub(index, index)
        if char == "{" then depth = depth + 1 elseif char == "}" then depth = depth - 1 end
        if depth == 0 then break end
        index = index + 1
        Check(index <= #text, path .. ": unbalanced table after " .. marker)
    end
    local chunk = assert(loadstring("return " .. text:sub(open, index)))
    setfenv(chunk, {})
    return chunk()
end

local DEFAULTS = "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"
local defaults = TableAfter(DEFAULTS, "local MSUF_DEFAULTS_UNIT_AURA_LANES = {")

local function Compare(schema, source)
    local compared = 0
    for kind, spec in pairs(defaults) do
        local laneSpec = schema[kind]
        Check(type(laneSpec) == "table", source .. " has no " .. kind .. " lane")
        for field, value in pairs(spec) do
            if field == "prefix" then
                Check(laneSpec.xKey == value .. "GroupOffsetX", string.format(
                    "%s: %s prefix %q does not match the schema's keys (%s)", DEFAULTS, kind, value, tostring(laneSpec.xKey)))
            else
                Check(laneSpec[field] == value, string.format("%s: %s.%s is %s, %s says %s",
                    DEFAULTS, kind, field, tostring(value), source, tostring(laneSpec[field])))
            end
            compared = compared + 1
        end
    end
    for kind in pairs(schema) do
        Check(defaults[kind] ~= nil, source .. " has a lane the defaults do not materialize: " .. tostring(kind))
    end
    return compared
end

local compared, source = 0, nil
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local A3 = world.core.AuraCore and world.core.AuraCore.Auras3
    local laneKeySchema = A3 and A3.LaneKeySchema
    if laneKeySchema then
        source = "A3.LaneKeySchema.LANE_SPECS (" .. flavor .. ")"
        compared = compared + Compare(laneKeySchema.LANE_SPECS, source)
    end
end
if not source then
    source = "the menu schema's lane specs"
    compared = Compare(TableAfter("MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua",
        "local GROUPS = A3.UnitLaneSpecs or {"), source)
end
print("defaults_aura_lane_schema_smoke: ok (" .. compared .. " lane fields against " .. source .. ")")

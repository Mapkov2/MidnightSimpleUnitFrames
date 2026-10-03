-- gf_aura_filter_fixture.lua: the shipped group aura filter table for page fixtures.
--
-- The group aura page resolves MSUF_GF_AuraFilter with MSUF.Require at load
-- (the core's aura menu model publishes it before the Options addon loads).
-- Page fixtures that build their own namespace call Install(root, env, ns):
-- it runs the shipped Schema, Common, Presets and GroupFilters factories into
-- a private model (the fixture's own model stubs stay untouched), publishes
-- the real MSUF_GF_AuraFilter into env, and gives ns the shipped
-- MSUF.Require / MSUF.Optional (tools/tests/require_fixture.lua).
--
--   local Fixture = assert(loadfile(root .. "/tools/tests/gf_aura_filter_fixture.lua"))()
--   local filter = Fixture.Install(root, _G, namespace)
--
-- Plain Lua 5.1. Not a smoke itself.

local Fixture = {}

local function Load(root, path, ns)
    local chunk = assert(loadfile(root .. "/" .. path))
    return chunk("MidnightSimpleUnitFrames", ns)
end

-- The menu schema reads the unit lane-key schema the Auras3 core builds
-- (A3.LaneKeySchema) where the core has one; the fixture builds it from the
-- core's own functions.
local function LaneKeySchema(root, ns)
    local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
    local owner = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
    local text = Slice.Read(root .. "/" .. owner)
    if not text:find("local function BuildLaneKeySchema(", 1, true) then return nil end
    local parts = {
        Slice.Function(text, "local function DeepCopy", owner),
        Slice.Function(text, "local function LaneKeySchemaRows", owner),
        Slice.Function(text, "local function BuildLaneKeySchema", owner),
        "return BuildLaneKeySchema()",
    }
    return assert(loadstring("local MSUF = ...\n" .. table.concat(parts, "\n"), "@" .. owner))(ns)
end

-- The group filters read State's stored-token check
-- (MSUF.ProfileNormalize.NormalizeGFAuraFilterToken) where State publishes
-- one; the fixture builds it from the normalizer's own table and function.
local function StoredFilterTokenCheck(root)
    local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
    local owner = "MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua"
    local text = Slice.Read(root .. "/" .. owner)
    if not text:find("local function MSUF_ProfileIO_NormalizeGFAuraFilterToken(", 1, true) then return nil end
    local parts = {
        Slice.Declaration(text, "local MSUF_PROFILEIO_GF_CURRENT_FILTER_TOKENS", owner),
        Slice.Function(text, "local function MSUF_ProfileIO_NormalizeGFAuraFilterToken", owner),
        "return MSUF_ProfileIO_NormalizeGFAuraFilterToken",
    }
    return assert(loadstring(table.concat(parts, "\n"), "@" .. owner))()
end

function Fixture.Install(root, env, ns)
    env = env or _G
    ns = ns or {}
    local function ExportPublic(name, value) env[name] = value end
    assert(loadfile(root .. "/tools/tests/require_fixture.lua"))().Install(root, ns)
    if type(env.MSUF_GF_AuraFilter) ~= "table" then
        local private = { ExportPublic = ExportPublic }
        local tokenCheck = StoredFilterTokenCheck(root)
        if tokenCheck then private.ProfileNormalize = { NormalizeGFAuraFilterToken = tokenCheck } end
        for _, file in ipairs({ "Schema", "Common", "Presets", "GroupFilters" }) do
            Load(root, "MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_" .. file .. ".lua", private)
        end
        local Factories = private.Auras3MenuModelFactories
        local A3, Model = { MenuModel = {} }, {}
        A3.MenuModel = Model
        A3.LaneKeySchema = LaneKeySchema(root, private)
        local Schema = Factories.Schema(A3)
        local Common = Factories.Common(Schema)
        local Presets = Factories.Presets(Model, Common)
        Factories.GroupFilters(A3, Model, Common, Presets, ExportPublic)
    end
    return assert(env.MSUF_GF_AuraFilter, "gf_aura_filter_fixture: the shipped factories published no MSUF_GF_AuraFilter")
end

return Fixture

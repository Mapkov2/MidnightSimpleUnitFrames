-- <root> <flavor> [--case id] [--mutate property] [--capture EMPTY_EXISTING_DIRECTORY]
local root = assert(arg[1], "root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local Regions = assert(loadfile(root .. "/tools/tests/preview_oracle_regions.lua"))()
local Cases = assert(loadfile(root .. "/tools/tests/preview_oracle_cases.lua"))()
local Adapter = assert(loadfile(root .. "/tools/tests/preview_oracle_world.lua"))()
local options = {}
for index = 3, #arg, 2 do
    assert(arg[index]:match("^%-%-"), "unknown argument " .. arg[index])
    options[arg[index]:sub(3)] = assert(arg[index + 1], "option value required")
end
for key in pairs(options) do assert(key == "case" or key == "mutate" or key == "capture", "unknown option " .. key) end
assert(not (options.capture and options.mutate), "capture cannot mutate output")
assert(not options.mutate or options.case, "mutations require a specific case")
local fixtureDir = options.capture or (root .. "/tools/fixtures/preview-render-oracle/" .. flavor)
local catalog = Adapter.Open(root, flavor, Regions)
local matrix = Cases.For(catalog.core.Client)
catalog = nil

local count, total = 0, 0
for _, case in ipairs(matrix) do
    if not options.case or case.id == options.case then
        local mw, roots, aliases, provenance = Adapter.Render(root, flavor, case, Regions, Cases)
        local actual, objects = Regions.Capture(mw.world, roots, aliases)
        local regionCount = 0
        for _ in pairs(actual) do regionCount = regionCount + 1 end
        local observation = { schema = 1, case = case, client = flavor, provenance = provenance, regions = actual }
        local path = fixtureDir .. "/" .. case.id .. ".lua"
        if options.capture then
            Regions.Write(path, observation)
        else
            local expected = assert(loadfile(path), "frozen fixture missing: " .. path)()
            if options.mutate then
                local Mutations = assert(loadfile(root .. "/tools/tests/preview_oracle_mutations.lua"))()
                local changed = Mutations.Apply(mw.world, case, objects, actual, options.mutate, Regions)
                print("MUTATION " .. options.mutate .. " " .. case.id .. " " .. changed)
                observation.regions = Regions.Capture(mw.world, roots, aliases)
            end
            -- Provenance describes the frozen legacy renderer. A migrated adapter may have a new entry point.
            local diffs = Regions.Compare(expected.regions, observation.regions)
            for _, field in ipairs({ "schema", "case", "client" }) do
                for _, diff in ipairs(Regions.Compare(expected[field], observation[field])) do
                    diffs[#diffs + 1] = field .. diff
                end
            end
            if #diffs > 0 then
                print("PREVIEW MISMATCH " .. flavor .. "/" .. case.id .. " (" .. #diffs .. " differences)")
                for index = 1, math.min(8, #diffs) do print(diffs[index]) end
                error("frozen preview output differs; explicit review required, never regenerate to hide a mismatch", 0)
            end
        end
        count, total = count + 1, total + regionCount
        print(string.format("%s %s/%s: %d regions", options.capture and "CAPTURE" or "MATCH", flavor, case.id, regionCount))
    end
end
assert(count > 0, "case is absent or unsupported")
print(string.format("preview_render_oracle_smoke: ok (%s, %d previews, %d regions)", flavor, count, total))

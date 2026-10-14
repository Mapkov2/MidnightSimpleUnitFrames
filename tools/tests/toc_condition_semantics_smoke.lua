local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
assert(Manifest.TocReference("x.lua [AllowLoadTextLocale enUS] [AllowLoadGameType camelot]", "enUS", "standard") == "x.lua",
    "only the first TOC condition is honored by the client")
assert(Manifest.TocReference("x.lua [AllowLoadTextLocale deDE] [ExcludeLoadGameType camelot]", "enUS", "standard") == nil)
assert(Manifest.TocReference("x.lua [ExcludeLoadGameType camelot] [AllowLoadTextLocale deDE]", "enUS", "standard") == "x.lua")
assert(Manifest.TocReference("x.lua [AllowLoadTextLocale enUS, enGB]", "enGB") == "x.lua")
for _, line in ipairs({
    "x.lua [AllowLoadTextLocale enUS] [ExcludeLoadGameType camelot]",
    "## Version: 6.50 [AllowLoadTextLocale enUS] [AllowLoadGameType camelot]",
}) do
    local ok, reason = pcall(Manifest.LintToc, line, "fixture.toc")
    assert(not ok and tostring(reason):find("stacked TOC conditions", 1, true), "stacked conditions escaped the lint")
end
Manifest.LintToc("# Example: x.lua [AllowLoadTextLocale enUS] [ExcludeLoadGameType camelot]", "comment.toc")
print("PASS TOC first-condition semantics")

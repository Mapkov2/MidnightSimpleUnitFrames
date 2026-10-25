-- TOC file-line conditions: stacked conditions must all hold (warcraft.wiki.gg
-- TOC format). The unchanged 6.50x Forever graph depends on it.
local root = assert(arg[1])
local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local Ref = Manifest.TocReference

local file = [[Auras3\AliasData\MSUF_Auras3_AliasData_enUS.lua]]
local alias = file .. " [AllowLoadTextLocale enUS, enGB] [ExcludeLoadGameType camelot]"
assert(Ref(alias, "enUS", "camelot") == nil, "a trailing ExcludeLoadGameType was ignored")
assert(Ref(alias, "enGB", "standard") == file, "stacked conditions dropped a valid load")
assert(Ref(alias, "deDE", "standard") == nil, "a leading AllowLoadTextLocale was ignored")

local wiki = "ForeverOnly.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]"
assert(Ref(wiki, "enUS", "camelot") == "ForeverOnly.lua", "the wiki example must load on Forever")
assert(Ref(wiki, "enUS", "standard") == nil and Ref(wiki, "enUS", "classic") == nil, "the wiki example loaded outside Forever")

-- Nil locale / game type inventories every branch.
assert(Ref(alias, nil, nil) == file, "inventory walk lost a branch")
assert(Ref("  Core.lua  ", "enUS", "standard") == "Core.lua", "plain line")
assert(Ref("# Core.lua [AllowLoadGameType camelot]", "enUS", "camelot") == nil, "comment line loaded")
assert(Ref("", "enUS", "standard") == nil, "blank line loaded")
for _, bad in ipairs({ "A.lua [AllowLoadSomething x]", "A.lua [AllowLoadGameType camelot] junk", "[AllowLoadGameType camelot]" }) do
    assert(not pcall(Ref, bad, "enUS", "camelot"), "unsupported TOC line accepted: " .. bad)
end

-- MSUF's own TOCs keep one condition per line.
assert(pcall(Manifest.LintToc, "A.lua [ExcludeLoadGameType camelot]\n", "single.toc"), "single condition rejected")
assert(not pcall(Manifest.LintToc, alias .. "\n", "stacked.toc"), "stacked condition accepted in an MSUF TOC")
print("PASS TOC conditions: stacked conditions all hold; MSUF TOCs keep one per line")

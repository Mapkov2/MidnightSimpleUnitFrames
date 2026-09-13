local repo, flavor = assert(arg[1]), assert(arg[2])
local ns = { Client = { IsClassic = flavor ~= "Mainline" } }
ns.ExportPublic = function(name, value) _G[name] = value end
local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(repo, flavor, ns, {
    "State/MSUF_AuraDefaults.lua", "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
})
local A3 = assert(ns.MSUF_Auras3)
assert(A3.NewPlayerDefensiveContainer == ns.MSUF_CreateCanonicalPlayerDefensiveAuraContainer)
local a, b = A3.NewPlayerDefensiveContainer(), A3.NewPlayerDefensiveContainer()
a.filters.onlyMine = true; a.placed.size = 99; a.frame.color[1] = 0
assert(b.filters.onlyMine == false and b.placed.size == 24 and b.frame.color[1] == 0.69,
    "factory shared mutable profile data")
assert(b.placed.stylePadding == (flavor == "Mainline" and 0 or nil), "client schema changed")
local shape = A3.IconShape
assert(A3.NormalizeAuraIconShape == shape.Normalize)
assert(shape.Normalize("round") == "CIRCLE" and shape.Normalize("square") == "RECTANGLE")
assert(shape.Normalize("invalid", "DIAMOND") == "DIAMOND")
assert(shape.Resolve("FOLLOW", "HEXAGON") == "HEXAGON")
assert(shape.Resolve("FOLLOW", "invalid") == "RECTANGLE")
local region, mask = { adds = 0, removes = 0 }, {}
function region:AddMaskTexture(value) assert(value == mask); self.adds = self.adds + 1 end
function region:RemoveMaskTexture(value) assert(value == mask); self.removes = self.removes + 1 end
shape.ApplyMask(region, mask); shape.ApplyMask(region, mask)
assert(region.adds == 1, "unchanged mask was reapplied")
shape.ClearMask(region); assert(region.removes == 1 and region._msufA3AuraShapeMask == nil)
local broken = { ExportPublic = ns.ExportPublic }
local ok, err = pcall(assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua")), "MSUF", broken)
assert(not ok and tostring(err):find("Aura defaults must load",1,true), "missing factory silently substituted defaults")
print("PASS " .. flavor .. ": shared aura factories, independent profile tables, shape aliases and mask cache")

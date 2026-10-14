-- Physical ownership, independent of compatibility aliases and fixture loaders.
local root = assert(arg[1])
local function Read(path)
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local core = Read("Castbars/MSUF_Castbars_Core.lua")
assert(not core:find("local function GetFontPath", 1, true), "castbar core still owns global font policy")
assert(not core:find("local resolvedStatusbarTextureCache", 1, true), "castbar core still owns shared media cache")
assert(not Read("Kernel/MSUF_Libs.lua"):find("local function ResolveFontKeyPath", 1, true), "Kernel still owns font policy")
assert(not Read("Runtime/MSUF_FontRegistry.lua"):find("local function MSUF_GetConfiguredFontColor", 1, true),
    "font registry still owns color policy")
assert(Read("Runtime/MSUF_Fonts.lua"):find("local function ResolveFontKeyPath", 1, true))
assert(Read("Runtime/MSUF_MediaRuntime.lua"):find("local resolvedStatusbarTextureCache", 1, true))
print("runtime_media_ownership_smoke: OK")

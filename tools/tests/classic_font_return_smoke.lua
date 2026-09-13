-- A cold client's false SetFont result must not abort valid font application.
local repo = assert(arg[1])
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
local ns = { UF = {} }
ns.ExportPublic = function(name, value) _G[name] = value end
local function load(path)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
load("Kernel/MSUF_Libs.lua")
load("UnitFrames/Engine/MSUF_UF_Shared.lua")
local path = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Bold.ttf"
local count = 0
local fs = {
    SetFont = function(self, requested, size, flags)
        count = count + 1
        self.path, self.size, self.flags = requested, size, flags
        return false
    end,
    GetFont = function(self) return self.path, self.size, self.flags end,
}
-- The reported arena, status, cold-probe and gameplay sizes/flags all use this owner.
for _, spec in ipairs({ {14, "OUTLINE,SLUG"}, {16, "OUTLINE,SLUG"}, {14, ""}, {22, "OUTLINE,SLUG"} }) do
    assert(MSUF_SetFontChecked(fs, path, spec[1], spec[2]))
    assert(fs.path == path and fs.size == spec[1] and fs.flags == spec[2])
end
assert(ns.UF.Shared.ApplyFontChecked(fs, path, 16, "OUTLINE,SLUG", 14))
assert(MSUF_ApplyResolvedFont(fs, path, 14, "OUTLINE,SLUG"))
local appliedCount = count
assert(MSUF_ApplyResolvedFont(fs, path, 14, "OUTLINE,SLUG"))
assert(count == appliedCount, "cached requests must not repeat native SetFont")
MSUF_FontApplyEpoch = MSUF_FontApplyEpoch + 1
assert(MSUF_ApplyResolvedFont(fs, path, 14, "OUTLINE,SLUG"))
assert(count == appliedCount + 1, "new epoch must reapply cold-start fonts")
-- Exercise the actual widget and menu-theme entry points from the new reports.
load("Shell/UI/MSUF_Widgets.lua")
assert(loadfile(repo .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", ns)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))("MidnightSimpleUnitFrames_Options", ns)
local regular = path:gsub("Expressway Bold", "Expressway Regular")
MSUF_DB = { general = { menuFontKey = "EXPRESSWAY" } }
assert(MSUF_SetFontChecked(fs, regular, 11, ""))
ns.UI.ApplyFontRole(fs, "body", regular, "")
assert(fs.path == regular and fs.size == 13 and fs.flags == "")
fs:SetFont(regular, 10, "")
ns.MSUF2.Theme.StyleFontString(fs, {0.4, 0.4, 0.4, 1}, 1)
assert(fs.path == regular and fs.size == 11 and fs._msuf2AppliedFontKey, "menu font styling aborted")
-- The reported regression: false plus stale/missing readback is pending, not
-- an exception. Do not replace the requested face or stamp a ready cache.
for _, actual in ipairs({ {"Fonts\\ARIALN.TTF", 14}, {path, 19}, {} }) do
    local pending = {
        SetFont = function(self, requested, size, flags)
            self.request = {requested, size, flags}
            return false
        end,
        GetFont = function() return actual[1], actual[2], "" end,
    }
    local ready, requested, source = MSUF_ApplyResolvedFont(pending, path, 14, "")
    assert(ready == false and requested == path and source == "pending")
    assert(pending._msufFontAppliedPath == nil and pending._msufFontRequestPath == nil)
    -- The same FontString becomes ready later; retry must really apply it.
    pending.GetFont = function(self) return unpack(self.request) end
    assert(MSUF_ApplyResolvedFont(pending, path, 14, ""))
end
local coldUI = {
    SetFont = function(self, requested, size, flags) self.request = {requested, size, flags}; return false end,
    GetFont = function() return "Fonts\\ARIALN.TTF", 10, "" end,
    GetText = function() return "MSUF" end,
    GetStringWidth = function() return 0 end,
}
ns.UI.ApplyFontRole(coldUI, "body", regular, "")
assert(coldUI.request[1] == regular and coldUI.request[2] == 13)
ns.MSUF2.Theme.StyleFontString(coldUI, {0.4, 0.4, 0.4, 1}, 1)
assert(coldUI.request[1] == regular and coldUI.request[2] == 11)
assert(coldUI._msuf2AppliedFontKey == nil, "pending menu font was cached as ready")
coldUI.GetFont = function(self) return unpack(self.request) end
-- Matching tuple alone still must not cache zero glyph metrics as ready.
ns.MSUF2.Theme.StyleFontString(coldUI, {0.4, 0.4, 0.4, 1}, 1)
assert(coldUI._msuf2AppliedFontKey == nil)
coldUI.GetStringWidth = function() return 28 end
ns.MSUF2.Theme.StyleFontString(coldUI, {0.4, 0.4, 0.4, 1}, 1)
assert(coldUI._msuf2AppliedFontKey ~= nil)
-- No protected call in production: retain the exact native error object.
local marker = {}
local broken = { SetFont = function() error(marker) end, GetFont = function() error("unexpected readback") end }
local ok, err = pcall(MSUF_SetFontChecked, broken, path, 14, "")
assert(not ok and err == marker, "native error was swallowed or replaced")
-- Missing imported media is rejected at the probe boundary, before application.
local missing = "Interface\\AddOns\\ChonkyCharacterSheet\\Media\\Fonts\\FiraSans-Medium.ttf"
local probes = 0
CreateFont = function()
    return { SetFont = function(_, requested)
        if requested == missing then
            probes = probes + 1
            error("Invalid font asset: file not found")
        end
        return false -- Cold Classic success must remain accepted by the wrapper.
    end }
end
load("Runtime/MSUF_FontRegistry.lua")
for i = 1, 51 do
    assert(MSUF_ResolveFontKeyPath(missing) == nil)
    assert(MSUF_ResolveFontPath(missing, 14, "") == "Fonts\\FRIZQT___CYR.TTF")
end
assert(probes == 1, "missing font must be negatively cached")
assert(MSUF_ApplyResolvedFont(fs, missing, 14, ""))
assert(fs.path == "Fonts\\FRIZQT___CYR.TTF", "missing media must use the default face")
assert(MSUF_FontPathIsLoadable(path, 14, ""), "cold valid fonts must remain loadable")
-- Standalone aura harnesses must load the same native error boundary.
MSUF_SetFontChecked = nil
local Loader = assert(loadfile(repo .. "/.github/scripts/auras3_test_loader.lua"))()
Loader.Install()
assert(MSUF_SetFontChecked(fs, regular, 11, ""))
print("PASS cold font stale readback, HUD/menu construction, pending recovery, native errors: reported font tuples, UF/castbar owner, cache/epoch and visible failures")

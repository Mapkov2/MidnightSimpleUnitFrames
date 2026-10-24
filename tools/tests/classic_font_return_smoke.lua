-- A cold client's false SetFont result must not abort valid font application.
local repo = assert(arg[1])
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
local ns = { UF = {} }
local RequireFixture = assert(loadfile(repo .. "/tools/tests/require_fixture.lua"))()
local function loadKernel(path)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
-- The real namespace API (Kernel/MSUF_Bootstrap.lua: ExportPublic with the
-- shipped global keep policy, then Kernel/MSUF_Require.lua), as in every core TOC.
loadKernel("Kernel/MSUF_Bootstrap.lua")
loadKernel("Kernel/MSUF_Require.lua")
-- Later files run through the shipped loader: a provider this harness does not
-- load (the font checks never call it) is a forwarder that raises when used.
local function load(path)
    RequireFixture.LoadShipped(repo, "MidnightSimpleUnitFrames/" .. path, ns)
end
load("Kernel/MSUF_Libs.lua")
load("Runtime/MSUF_Fonts.lua")
load("UnitFrames/Engine/MSUF_UF_Shared.lua")
-- These font owners are namespace-only exports, never globals; each call
-- resolves the live owner from the registry.
local function MSUF_ApplyResolvedFont(...) return ns.PublicGlobals.MSUF_ApplyResolvedFont(...) end
local function MSUF_ResolveFontPath(...) return ns.PublicGlobals.MSUF_ResolveFontPath(...) end
local function MSUF_IsAvailableFontPath(...) return ns.PublicGlobals.MSUF_IsAvailableFontPath(...) end
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
-- FontRegistry owns MSUF_ResolveSafeFontPath, which the widget files require, and the
-- availability metadata the later checks read; the TOC loads it before any caller runs.
-- IsRegisteredLSMFontPath is a namespace-only export that FontRegistry binds when it
-- loads, so the registration-aware stand-in is published before that load.
local registered = {}
local isRegistered = ns.PublicGlobals.MSUF_IsRegisteredLSMFontPath
ns.ExportPublic("MSUF_IsRegisteredLSMFontPath",
    function(value) return registered[value] or isRegistered(value) end, false)
load("Runtime/MSUF_FontRegistry.lua")
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
-- Menu styling keeps the selected face, removes inherited effects, and
-- leaves gameplay's separate outline/font owner intact.
;(function()
    local custom = "Interface\\AddOns\\CustomFont\\Readable.ttf"
    -- The selected face is a media-addon font, registered with LibSharedMedia as in the
    -- client; the loaded font registry would otherwise fall back from an unknown path.
    registered[custom] = true
    local label = {
        path = custom, size = 12, flags = "OUTLINE,MONOCHROME",
        GetFont = fs.GetFont, SetFont = fs.SetFont,
        SetShadowColor = function(self, r, g, b, a) self.shadowAlpha = a end,
        SetShadowOffset = function(self, x, y) self.shadowX, self.shadowY = x, y end,
    }
    local selected = MSUF_DB.general.menuFontKey
    MSUF_DB.general.menuFontKey = custom
    ns.MSUF2.Theme.StyleFontString(label, {1, 1, 1, 1}, 0, "navigation")
    assert(label.path == custom and label.size == 14 and label.flags == "", "custom menu font was replaced")
    assert(label.shadowAlpha == 0 and label.shadowX == 0 and label.shadowY == 0, "menu shadow remains")
    -- Empty selection retains the native locale-compatible font family.
    MSUF_DB.general.menuFontKey = ""
    local localized = { path = "Fonts\\FRIZQT___CYR.TTF", size = 12, flags = "OUTLINE",
        GetFont = fs.GetFont, SetFont = fs.SetFont }
    ns.MSUF2.Theme.StyleFontString(localized, {1, 1, 1, 1}, 0, "navigation")
    assert(localized.path == "Fonts\\FRIZQT___CYR.TTF" and localized.size == 14 and localized.flags == "")
    MSUF_DB.general.menuFontKey = selected
    local gameplay = { GetFont = fs.GetFont, SetFont = fs.SetFont }
    assert(MSUF_ApplyResolvedFont(gameplay, path, 14, "OUTLINE,SLUG"))
    assert(gameplay.flags == "OUTLINE,SLUG", "menu font policy leaked into gameplay")
end)()
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
-- Hidden strings have no glyph metrics yet; the matching tuple is ready.
coldUI.GetStringWidth = function() error("font readiness queried hidden glyph metrics") end
ns.MSUF2.Theme.StyleFontString(coldUI, {0.4, 0.4, 0.4, 1}, 1)
assert(coldUI._msuf2AppliedFontKey ~= nil)
-- No protected call in production: retain the exact native error object.
local marker = {}
local broken = { SetFont = function() error(marker) end, GetFont = function() error("unexpected readback") end }
local ok, err = pcall(MSUF_SetFontChecked, broken, path, 14, "")
assert(not ok and err == marker, "native error was swallowed or replaced")
-- Unknown imported media is resolved from availability metadata, without
-- probing a native API or converting unrelated errors into a missing font.
local missing = "Interface\\AddOns\\ChonkyCharacterSheet\\Media\\Fonts\\FiraSans-Medium.ttf"
CreateFont = function() error("font resolution must not create native probes") end
-- (FontRegistry and its registration stand-in load above, before the widget files use them.)
MSUF_DB.general.fontKey = missing
for i = 1, 51 do
    assert(MSUF_ResolveFontKeyPath(missing) == nil)
    assert(MSUF_ResolveFontPath(missing, 14, "") == "Fonts\\FRIZQT___CYR.TTF")
end
assert(MSUF_DB.general.fontKey == missing, "imported selection must remain saved")
assert(MSUF_ApplyResolvedFont(fs, missing, 14, ""))
assert(fs.path == "Fonts\\FRIZQT___CYR.TTF", "unavailable media must use the default face")
assert(MSUF_IsAvailableFontPath(path), "bundled fonts must remain available")
assert(MSUF_IsAvailableFontPath(path:gsub("\\", "/"):upper()), "path aliases must resolve")
-- Registration after a negative lookup must become visible immediately.
registered[missing] = true
assert(MSUF_IsAvailableFontPath(missing), "late media registration was negatively cached")
assert(MSUF_ResolveFontKeyPath(missing) == missing)
local applied, nativeError = pcall(MSUF_ApplyResolvedFont, broken, missing, 14, "")
assert(not applied and nativeError == marker, "registered font application error was hidden")
-- Standalone aura harnesses must load the same native error boundary.
MSUF_SetFontChecked = nil
local Loader = assert(loadfile(repo .. "/.github/scripts/auras3_test_loader.lua"))()
Loader.Install()
assert(MSUF_SetFontChecked(fs, regular, 11, ""))
print("PASS cold font stale readback, HUD/menu construction, pending recovery, native errors: reported font tuples, UF/castbar owner, cache/epoch and visible failures")

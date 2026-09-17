-- Exercise shipped client detection and the real Menu2 painters offline.
-- The Classic Glass menu skin belongs to WoW Forever only (owner decision
-- 2026-09-16). Every shipped client (a matrix suffix or FutureVanilla) must keep
-- the stock menu; the "Forever" run stands in for the client fact
-- Game/Shared/Initialize.lua sets once the Forever client ships.
local root, flavor = assert(arg[1]), assert(arg[2])
local Stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
local projects = { Mainline = 1, Vanilla = 2, TBC = 5, Mists = 19, FutureVanilla = 2, Forever = 1 }
WOW_PROJECT_ID = assert(projects[flavor])
GetBuildInfo = function() return "test", "test", "test", flavor == "FutureVanilla" and 199999 or 11509 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
IsLoggedIn = function() return true end
local tinted = arg[3] == "tinted"
local general = tinted and { menuAccent = "custom", menuAccentColor = "101211", menuAccentTintSurfaces = true, menuClassicAtlasRevision = 2 } or {}
if arg[3] == "midnight" then general.menuAppearancePreset = "midnight" end
MSUF_DB = { general = general }
local ns = { Translate = function(s) return s end }
ns.ExportPublic = function(name, value) _G[name] = value end
local function load(path)
    assert(loadfile(root .. "/" .. path))("MidnightSimpleUnitFrames", ns)
end
load("MidnightSimpleUnitFrames/Game/Shared/Initialize.lua")
local forever = flavor == "Forever"
assert(ns.Client.IsForever == false, "shipped client detection reported WoW Forever")
if forever then ns.Client.IsForever = true end
assert(not tinted or forever, "the tinted run exercises the Forever skin; pass Forever")
load("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua")
local prefix = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
load(prefix .. "MSUF_Menu2_Support.lua")
load(prefix .. "MSUF_Menu2_Theme_Forever.lua")
load(prefix .. "MSUF_Menu2_Theme_Tokens.lua")
ns.MSUF2.GetGeneralDB = function() return general end
local T = ns.MSUF2.Theme
local originalText, originalAccent = T.colors.text, T.colors.accent
local danger = { unpack(T.colors.danger) }
load(prefix .. "MSUF_Menu2_Theme.lua")
local classic = forever and arg[3] ~= "midnight"
if forever then
    assert(general.menuAppearancePreset == (classic and "classicGlass" or "midnight"), "saved appearance preset lost")
    assert(T.GetMenuAppearancePreset({ menuAppearancePreset = "classicGlass" }) == "classicGlass")
    assert(T.GetMenuAppearancePreset({ menuAppearancePreset = "midnight" }) == "midnight")
else
    assert(T.GetMenuAppearancePreset == nil, "the Forever appearance selector leaked into " .. flavor)
    assert(general.menuAppearancePreset == nil, "the Forever Glass default was saved on " .. flavor)
end
assert((T.classicAtlas == true) == classic, "wrong default client skin for " .. flavor)
assert(originalText == T.colors.text and originalAccent == T.colors.accent, "captured token identity lost")
assert(T.materials.shell.bg == T.colors.glassShell, "material detached from palette")
for i = 1, 4 do assert(T.colors.danger[i] == danger[i], "danger color changed") end
assert(T.ApplyMenuAccent() == (tinted and "custom:101211+tint" or "midnight"), "skin rewrote the saved accent")
if classic then
    if not tinted then assert(T.colors.text[1] == 244 / 255 and T.colors.accent[1] == 216 / 255) end
    for key, path in pairs(T.media) do
        if path:find("Menu2\\Classic\\", 1, true) then
            local relative = path:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/")
            local file = assert(io.open(root .. "/" .. relative, "rb"), "missing atlas asset: " .. key)
            file:close()
        end
    end
end
local shell = CreateFrame("Frame")
shell:SetSize(1060, 740)
local heading = T.Font(shell, "GameFontNormal", "Frame Basics", T.colors.text, "accordion")
local body = T.Font(shell, "GameFontNormal", "275 x 40 px", T.colors.text, "body")
local expectedHeading = classic and T.colors.title or T.colors.text
local hr, hg, hb = heading:GetTextColor()
assert(hr == expectedHeading[1] and hg == expectedHeading[2] and hb == expectedHeading[3], "heading lost preset color")
assert(select(1, body:GetTextColor()) == T.colors.text[1], "heading color leaked into values")
local dangerHeading = T.Font(shell, "GameFontNormal", "Error", T.colors.danger, "heading")
assert(select(1, dangerHeading:GetTextColor()) == T.colors.danger[1], "heading preset overrode semantic color")
shell._msuf2Bg = shell:CreateTexture(nil, "BACKGROUND")
shell._msuf2Bg:Show()
T.ApplySurface(shell, "shell")
assert(shell._msuf2PanelAsset.path == T.media.panelShell)
local regionCount = #shell.regions
T.ApplySurface(shell, "shell")
assert(#shell.regions == regionCount, "repeat paint allocates more regions")
if classic then
    assert(shell._msuf2AtlasDecoration and shell._msuf2AtlasDecoration:IsShown())
    assert(not shell._msuf2PanelAssetDepth, "atlas allocated neon depth layers")
    assert(not shell._msuf2Bg:IsShown(), "fallback background blocks transparency")
    assert(not shell._msuf2MaterialGradient:IsShown(), "underpaint blocks transparency")
    assert(shell:GetAlpha() == 1, "whole-frame alpha dims text and controls")
end
local card = CreateFrame("Frame")
card:SetSize(650, 340)
T.ApplySurface(card, "card")
assert(not card._msuf2AtlasDecoration, "map artwork painted under settings")
if classic then
    assert(not card._msuf2MaterialGradient:IsShown(), "nested card accumulates gradient opacity")
end
local control = CreateFrame("Frame")
control:SetSize(140, 28)
local fill, edge = T.CreateSuperellipseLayers(control)
if classic then
    assert(fill.L:GetWidth() == 4, "control reverted to round pill")
    assert(edge.L.drawLayer == fill.L.drawLayer and edge.L.drawSublevel < fill.L.drawSublevel,
        "solid bronze edge covers button fill")
end
local button = T.Button(shell, "Reset page", 140, 28)
if classic then
    assert(button._msuf2Edge.L.drawLayer == button._msuf2Fill.L.drawLayer)
    local top = assert(button._msuf2Fill._msuf2GradientTopColor)
    local function Luminance(c)
        local function Linear(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
        return 0.2126 * Linear(c[1]) + 0.7152 * Linear(c[2]) + 0.0722 * Linear(c[3])
    end
    assert((Luminance(T.colors.pillText) + 0.05) / (Luminance(top) + 0.05) >= 4.5,
        "button label has insufficient contrast")
    if not tinted then
        assert((Luminance(T.colors.title) + 0.05) / (Luminance(T.colors.coreGlow) + 0.05) >= 4.5,
            "gold heading has insufficient contrast on the open section highlight")
    end
    button._msuf2NavItem = true
    button:SetActive(true)
    assert(not button._msuf2NavActiveFX, "static atlas navigation allocated glow layers")
end
if tinted then
    assert(T.MenuAccentSurfacesTinted(), "saved surface tint was discarded")
    print("PASS " .. flavor .. ": dark custom accent plus surface tint, thin edge behind dark button fill")
    return
end
if classic then
    local old = { menuAccent = "custom", menuAccentColor = "111111", menuAccentTintSurfaces = true }
    T.PrepareMenuAccent(old)
    assert(old.menuAccent == "midnight" and old.menuAccentTintSurfaces == false)
    assert(old.menuClassicAtlasPreviousAppearance.menuAccentColor == "111111")
    assert(old.menuClassicAtlasPreviousAppearance.menuAccentTintSurfaces == true)
    old.menuAccent, old.menuAccentTintSurfaces = "custom", true
    T.PrepareMenuAccent(old)
    assert(old.menuAccent == "custom" and old.menuAccentTintSurfaces == true, "later user choice was overwritten")
    local colorful = { menuAccent = "custom", menuAccentColor = "38b878", menuAccentTintSurfaces = true }
    T.PrepareMenuAccent(colorful)
    assert(colorful.menuAccent == "custom" and not colorful.menuClassicAtlasPreviousAppearance)
else
    assert(T.PrepareMenuAccent == nil, "the Forever accent migration leaked into " .. flavor)
end
-- A saved user accent must still override interaction colors after reload;
-- settings, default text, and semantic state colors remain untouched.
general.menuAccent, general.menuAccentColor = "custom", "38b878"
T._menuAccentApplied = nil
T.ApplyMenuAccent()
assert(T.colors.accent[2] > T.colors.accent[1], "custom accent failed on the new palette")
assert(T.colors.danger[1] == danger[1], "custom accent recolored danger")
assert(T.ApplyMenuAccent() == "custom:38b878", "accent is not idempotent")
print("PASS " .. flavor .. ": " .. (classic and "Forever Glass skin, assets, real panel paint, reusable decoration, control shape"
    or "stock menu, real panel paint") .. ", custom accent")

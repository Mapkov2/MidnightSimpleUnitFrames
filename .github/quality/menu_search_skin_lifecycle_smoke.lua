-- The navigation search input acquires rounded chrome after its first skin paint.
-- Exercise the real bridge at the same rank used by the input painter.
local root = arg and arg[1] or "."
local enabled, nativePaints, skinCalls, activeCalls, releases = true, 0, 0, 0, 0
local regions = {}
local function Region(shown)
    local region = { shown = shown ~= false, hides = 0, shows = 0 }
    function region:IsShown() return self.shown end
    function region:Hide() self.hides = self.hides + 1; self.shown = false end
    function region:Show() self.shows = self.shows + 1; self.shown = true end
    regions[#regions + 1] = region
    return region
end
local function Rounded(hiddenRight)
    return { L = Region(), M = Region(), R = Region(not hiddenRight) }
end
local function Hidden(parts, message)
    for _, side in ipairs({ "L", "M", "R" }) do
        assert(not parts[side]:IsShown(), message .. " (" .. side .. ")")
    end
end
local function HideCount()
    local total = 0
    for _, region in ipairs(regions) do total = total + region.hides end
    return total
end

local client = {}
function client:SkinFrame(target, options)
    skinCalls = skinCalls + 1
    assert(options.role == "input" and options.activeRole == "navigationActive")
    return true, "applied"
end
function client:SetActive(target, value)
    activeCalls = activeCalls + 1
    target.providerActive = value
end
function client:ReleaseAll() releases = releases + 1 end
local api = {}
function api:RegisterAddon(name) assert(name == "MidnightSimpleUnitFrames"); return client end
function api:IsEnabled() return enabled end
function api:GetAppearanceSnapshot() return {} end
function api:OnAppearanceChanged() end
_G.MapkoSkin = { GetAPI = function(major, minor)
    assert(major == 2 and minor == 1)
    return api
end }
_G.MSUF_DB = { general = {} }
_G.InCombatLockdown = function() return false end
_G.hooksecurefunc = function() end
_G.CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
end
local MSUF = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua"))("MidnightSimpleUnitFrames", MSUF)
local Skin = assert(MSUF.MenuSkin)
local input = { _msuf2EditBg = Region(), focused = false }
function input:HasFocus() return self.focused end
local function Paint(target)
    if Skin.Surface(target, "input", Paint, nil, nil, 7) then return end
    assert(target._msuf2EditBg:IsShown() and target._msuf2RoundedEditFill.L:IsShown()
        and target._msuf2RoundedEditEdge.M:IsShown(), "native painter ran before chrome restoration")
    nativePaints = nativePaints + 1
end

Paint(input)
assert(Skin.Owns(input) and not input._msuf2EditBg:IsShown(), "initial input chrome was not suppressed")
assert(skinCalls == 1 and input.providerActive == false, "initial provider input state was not applied")

-- NavRail creates these uncolored texture triplets after the initial SkinEditBox.
input._msuf2RoundedEditFill = Rounded(true)
Paint(input)
Hidden(input._msuf2RoundedEditFill, "late rounded fill remains visible after same-rank paint")
input._msuf2RoundedEditEdge = Rounded()
Paint(input)
Hidden(input._msuf2RoundedEditEdge, "late rounded edge remains visible after same-rank paint")
local hides, focusUpdates = HideCount(), activeCalls
for _ = 1, 20 do Paint(input) end
assert(HideCount() == hides, "unchanged input paint repeats chrome suppression")
assert(skinCalls == 1 and activeCalls == focusUpdates, "unchanged paint repeats provider state writes")
input.focused = true
Paint(input)
assert(input.providerActive == true and activeCalls == focusUpdates + 1, "focus did not update provider state")
assert(HideCount() == hides, "focus-only paint rescans native chrome")
input.focused = false
Paint(input)
assert(input.providerActive == false and activeCalls == focusUpdates + 2, "focus loss did not clear provider state")
assert(HideCount() == hides, "focus-loss paint rescans native chrome")
input.focused = true
Paint(input)

-- Disabling the provider must restore the original shown/hidden mix before repaint.
enabled = false
Skin.Refresh()
assert(not Skin.IsActive() and not Skin.Owns(input) and releases == 1)
assert(nativePaints == 1, "disabling provider did not invoke native painter")
assert(input._msuf2EditBg:IsShown(), "initial chrome was not restored")
assert(input._msuf2RoundedEditFill.L:IsShown() and input._msuf2RoundedEditFill.M:IsShown(),
    "late rounded fill did not restore")
assert(not input._msuf2RoundedEditFill.R:IsShown() and input._msuf2RoundedEditFill.R.shows == 0,
    "restoration showed a texture that was originally hidden")
for _, side in ipairs({ "L", "M", "R" }) do
    assert(input._msuf2RoundedEditEdge[side]:IsShown(), "late rounded edge did not restore")
end

enabled = true
Skin.Refresh()
assert(Skin.Owns(input) and input.providerActive == true and skinCalls == 2)
Hidden(input._msuf2RoundedEditFill, "reenabling provider did not suppress rounded fill")
Hidden(input._msuf2RoundedEditEdge, "reenabling provider did not suppress rounded edge")
hides = HideCount()
Paint(input)
assert(HideCount() == hides, "reenabled unchanged paint repeats chrome suppression")
assert(nativePaints == 1, "provider paint unexpectedly entered native painter")

-- Menu2 T.Button (the only setter of _msuf2RawSetScript) declares its plain
-- Buttons ownedArt, so the provider skips native-art and gold-text scans on
-- them; any other button (core widget fallback) does not claim it.
local buttonSpecs = {}
function client:SkinButton(target, options)
    buttonSpecs[target] = options
    return true, "applied"
end
local function SkinnedButton(menu2)
    local label = { SetTextColor = function(self, ...) self.color = { ... } end }
    local button = { _msuf2Label = label, IsEnabled = function() return true end,
        _msuf2Fill = { L = Region(), M = Region(), R = Region(), glow = { Region(), { fill = Region() } } } }
    if menu2 then button._msuf2RawSetScript = function() end end
    function api:GetColor() return 0.1, 0.2, 0.3, 1 end
    assert(Skin.Button(button, false, false, function() end), "provider did not skin the button")
    return button
end
local menuButton, coreButton = SkinnedButton(true), SkinnedButton(false)
assert(buttonSpecs[menuButton].ownedArt == true, "Menu2 button was not declared ownedArt")
assert(buttonSpecs[coreButton].ownedArt == false, "a core widget button claimed ownedArt")
-- Suppression hides every part down to depth 3 and leaves deeper art alone.
local fill = menuButton._msuf2Fill
assert(not fill.L:IsShown() and not fill.M:IsShown() and not fill.R:IsShown(), "button fill parts stayed visible")
assert(not fill.glow[1]:IsShown() and not fill.glow[2].fill:IsShown(), "depth-3 art stayed visible")
local deep = { L = { L = { L = { L = Region() } } } }
local deepButton = { _msuf2Edge = deep, IsEnabled = function() return true end }
assert(Skin.Button(deepButton, false, false, function() end))
assert(deep.L.L.L.L:IsShown(), "suppression reached past depth 3")
print("menu_search_skin_lifecycle_smoke: PASS")

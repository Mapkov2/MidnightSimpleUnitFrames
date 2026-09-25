-- Exercise the shipped client/helper/build/layout paths. Native rendering itself
-- is deliberately not emulated: these checks prove opt-in and unchanged layout
-- inputs/profile data, not the WoW renderer's final screen pixels.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Read(path)
    return World.Read(root .. "/" .. path)
end
local function Load(world, path, returns)
    local chunk = assert(loadstring(Read(path) .. "\nreturn " .. returns, "@" .. path))
    setfenv(chunk, world.env)
    return chunk("MidnightSimpleUnitFrames", world.core)
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = Copy(v) end
    return result
end
local function Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Geometry(region)
    local out = { width = region.width, height = region.height, points = {} }
    for i, point in ipairs(region.points) do
        out.points[i] = { point.point, point.relativePoint, point.x, point.y }
    end
    return out
end
-- Offline call counts, not timings: detect pixel work returning to warm paths.
local function CountCalls(watched, run)
    local count = 0
    debug.sethook(function()
        local fn = debug.getinfo(2, "f").func
        if watched[fn] then count = count + 1 end
    end, "c")
    local ok, err = pcall(run)
    debug.sethook()
    assert(ok, err)
    return count
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    -- Install the API even on old clients: the client gate, not its absence,
    -- must preserve Era/TBC/Mists. Record calls without altering requested data.
    world.widgets.Methods.SetRoundLayoutToNearestPixel = function(self, enabled)
        self.pixelCalls = (self.pixelCalls or 0) + 1
        self.pixelEnabled = enabled
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": " .. tostring(failure and failure.message))
    local env, ns = world.env, world.core
    local expected = flavor == "Mainline" or flavor == "Forever"
    local enable = assert(ns.Util.EnablePixelPerfectLayout)
    local frame = env.CreateFrame("Frame", nil, env.UIParent)
    frame:SetPoint("CENTER", env.UIParent, "CENTER", -133.375, 57.125)
    frame:SetSize(273.5, 39.25)
    local original = Geometry(frame)
    assert(enable(frame) == expected)
    assert(enable(frame) == expected)
    assert((frame.pixelCalls or 0) == (expected and 1 or 0), "opt-in must be once")
    assert(Equal(original, Geometry(frame)), "helper rewrote geometry")
    local child = frame:CreateTexture(nil, "OVERLAY")
    assert(not child.pixelEnabled, "helper recursed into child art")
    -- No API: no marker, no geometry rewrite. A later supported call can retry.
    child.SetRoundLayoutToNearestPixel = false
    assert(not enable(child) and child._msufPixelLayoutEnabled == nil)
    child.SetRoundLayoutToNearestPixel = nil
    local combat = true
    env.InCombatLockdown = function() return combat end
    child.IsProtected = function() return true end
    -- Kernel captured InCombatLockdown at boot; use a fresh real helper below
    -- for combat rather than depending on a replaced captured reference.
    local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
    local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
    local scoped = assert(loadstring("local InCombatLockdown = ...\n"
        .. Slice.Function(util, "local function MSUF_SetRoundLayoutToNearestPixel", "util")
        .. "\nreturn MSUF_SetRoundLayoutToNearestPixel"))(function() return combat end)
    assert(not scoped(child, true) and not child.pixelEnabled, "protected combat write")
    combat = false
    assert(scoped(child, true) and child.pixelEnabled, "post-combat retry failed")

    -- Whole-widget creation and post-template setup use the real shared helper.
    local pixel = assert(env.MSUF_PixelLayoutRegion)
    local owner = env.CreateFrame("Frame", nil, env.UIParent)
    owner:SetSize(163.375, 27.125)
    owner:SetPoint("CENTER", env.UIParent, "CENTER", -15.625, 4.375)
    local templateText = owner:CreateFontString(nil, "OVERLAY")
    local templateMask = owner:CreateTexture(nil, "ARTWORK")
    templateMask.GetObjectType = function() return "MaskTexture" end
    local ownerBefore = Geometry(owner)
    local createBefore = env.CreateFrame
    local pointBefore = world.widgets.Methods.SetPoint
    assert(pixel(owner) == owner, "creation boundary changed identity")
    assert((owner.pixelEnabled == true) == expected, "widget root not gated")
    assert((templateText.pixelEnabled == true) == expected, "template text not rounded")
    assert(not templateMask.pixelEnabled, "mask rounded")
    assert(Equal(ownerBefore, Geometry(owner)), "constructor changed logical coordinates")
    assert(env.CreateFrame == createBefore and world.widgets.Methods.SetPoint == pointBefore,
        "global constructor or widget method was replaced")
    local lateForeign = env.CreateFrame("Frame", nil, owner)
    local lateForeignTexture = owner:CreateTexture(nil, "OVERLAY")
    local setterCalls = 0
    local settings = { edgeSize = 1.375 }
    function owner:SetBackdrop(value)
        setterCalls = setterCalls + 1
        assert(value == settings, "backdrop arguments rewritten")
        self.generatedEdge = self.generatedEdge or self:CreateTexture(nil, "BORDER")
        self.TopLeftCorner = self.generatedEdge
        return nil, "native-result", 17
    end
    local a, b, c = pixel(owner, "SetBackdrop", settings)
    assert(setterCalls == 1 and a == nil and b == "native-result" and c == 17,
        "template method semantics changed")
    assert((owner.generatedEdge.pixelEnabled == true) == expected, "late template edge missed")
    assert(not lateForeign.pixelEnabled and not lateForeignTexture.pixelEnabled,
        "template setter enrolled unrelated late foreign regions")
    -- Repeated setup neither reapplies native flags nor overwrites smooth art.
    local edge = owner.generatedEdge
    pixel(edge, true)
    pixel(owner, "SetBackdrop", settings)
    assert(not edge.pixelEnabled, "smooth-art opt-out lost")
    if expected then assert(not enable(edge), "individual helper ignored opt-out") end
    local foreign = env.CreateFrame("Frame")
    foreign.SetBackdrop = owner.SetBackdrop
    pixel(foreign, "SetBackdrop", settings)
    assert(not foreign.pixelEnabled and not foreign.generatedEdge.pixelEnabled,
        "borrowed Blizzard/third-party frame enrolled by a setter")
    -- Native texture setters can create their region after construction too.
    for setter, getter in pairs({ SetNormalTexture = "GetNormalTexture",
        SetPushedTexture = "GetPushedTexture", SetHighlightTexture = "GetHighlightTexture",
        SetDisabledTexture = "GetDisabledTexture", SetThumbTexture = "GetThumbTexture" }) do
        local widget = pixel(env.CreateFrame("Button", nil, owner))
        local generated
        widget[setter] = function(self, value, blend)
            assert(value == "test-texture" and blend == "ADD", "texture arguments changed")
            generated = self:CreateTexture(nil, "OVERLAY")
            return nil, 23
        end
        widget[getter] = function() return generated end
        local first, second = pixel(widget, setter, "test-texture", "ADD")
        assert(first == nil and second == 23, "texture setter return values changed")
        assert((generated.pixelEnabled == true) == expected, setter .. ": late texture missed")
    end
    local logical = env.CreateFrame("Frame")
    local label = logical:CreateFontString(nil, "OVERLAY")
    pixel(logical, true)
    assert(not logical.pixelEnabled and (label.pixelEnabled == true) == expected,
        "logical owner/visible child distinction lost")
    local statusbar = env.CreateFrame("StatusBar")
    local fill = statusbar:GetStatusBarTexture()
    pixel(statusbar)
    assert(not fill or not fill.pixelEnabled, "native interpolated status-bar fill rounded")
    local button = ns.MSUF2.Widgets.RoleButton(owner, "Pixel test", "primary", 93.375, 23.625)
    assert((button.pixelEnabled == true) == expected, "real Menu2 widget missed")

    local ensureText, layoutText = Load(world,
        "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua",
        "EnsureFontString, LayoutText")
    -- Forever exposes the atlas to Texture:SetAtlas even when GetAtlasInfo is
    -- unavailable; the native badge must not depend on that optional query.
    world.env.C_Texture = { GetAtlasInfo = function() return nil end }
    local statusLayout, ensureIcon, statusRuntime = Load(world,
        "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua", "LayoutRegion, EnsureTexture, Runtime")
    local fs = ensureText(frame, "nameText", "GameFontNormal", 5, 5, "MSUFNameTextLayer")
    assert((fs.pixelEnabled == true) == expected, flavor .. ": text not gated")
    layoutText(fs, "LEFT", "LEFT", -3.375, 2.125, "LEFT", frame)
    local _, target, _, x, y = fs:GetPoint()
    assert(target == frame and x == -3.375 and y == 2.125, "text anchor changed")
    local icon = ensureIcon(frame, "testStatusIcon", 7)
    local cfg = { anchor = "TOPRIGHT", x = 13.25, y = -7.125, size = 17.75, layer = 7 }
    local beforeCfg = Copy(cfg)
    statusLayout(icon, frame, { status = {} }, cfg, false)
    assert((icon.pixelEnabled == true) == expected, flavor .. ": status icon not gated")
    assert(Equal(cfg, beforeCfg), "status config mutated")
    assert(icon.width == cfg.size and icon.points[1].x == cfg.x and icon.points[1].y == cfg.y)
    local badgeFrame = env.CreateFrame("Frame", nil, env.UIParent)
    badgeFrame.MSUFUnitKey = "player"
    badgeFrame.MSUFSpec = { fontFlags = "OUTLINE", status = { alpha = 1,
        level = { enabled = true, size = 14, anchor = "BOTTOMLEFT", x = -59, y = -6,
            layer = 7, foreverBadge = true } } }
    statusRuntime.ApplyConfiguredRegions(badgeFrame, badgeFrame.MSUFSpec)
    if flavor == "Forever" then
        local badge = assert(badgeFrame.levelBackdrop, "Forever level badge was not created")
        assert(badge.atlas == "UI-HUD-UnitFrame-SmallCircle", "Forever level badge atlas drifted")
        assert(badge.width == 35 and badge.height == 35, "Forever level badge no longer scales from the text size")
        assert(badge.points[1].x == -59 and badge.points[1].y == -6, "Forever level badge lost the level anchor")
        statusRuntime.SetForeverLevelBadgeShown(badgeFrame, true)
        assert(badge:IsShown(), "Forever level badge did not follow visible level text")
    else
        local badge = assert(badgeFrame.levelBackdrop, flavor .. ": fallback level badge was not created")
        assert(tostring(badge.texture):find("circle_mask", 1, true), flavor .. ": fallback level badge lost its dark circle")
        local ring = assert(badgeFrame.levelBackdropRing, flavor .. ": fallback level badge lost its gold rim")
        assert(tostring(ring.texture):find("msuf_portrait_ring_circle", 1, true), flavor .. ": fallback level ring art drifted")
        statusRuntime.SetForeverLevelBadgeShown(badgeFrame, true)
        assert(badge:IsShown() and ring:IsShown(), flavor .. ": fallback level badge did not follow visible level text")
    end
    badgeFrame.MSUFSpec.status.level.enabled = false
    statusRuntime.ApplyConfiguredRegions(badgeFrame, badgeFrame.MSUFSpec)
    assert(not badgeFrame.levelBackdrop:IsShown(), flavor .. ": disabled level retained its badge")
    assert(not badgeFrame.levelBackdropRing or not badgeFrame.levelBackdropRing:IsShown(),
        flavor .. ": disabled level retained its fallback ring")
    local legacyIcon = ensureIcon(frame, "testLegacyIcon", 7)
    ns.Icons._layout.Apply(legacyIcon, frame, 15.25, "LEFT", "RIGHT", -2.375, 3.625)
    assert((legacyIcon.pixelEnabled == true) == expected, flavor .. ": legacy icon not gated")
    assert(legacyIcon.width == 15.25 and legacyIcon.points[1].x == -2.375)

    world.widgets:SetCombat(true)
    local watched = { [pixel] = true, [enable] = true,
        [env.MSUF_SetRoundLayoutToNearestPixel] = true }
    assert(CountCalls(watched, function()
        for i = 1, 1000 do
            ensureText(frame, "nameText", "GameFontNormal", 5, 5, "MSUFNameTextLayer")
            statusLayout(icon, frame, { status = {} }, cfg, false)
            ns.Icons._layout.Apply(legacyIcon, frame, 15.25, "LEFT", "RIGHT", -2.375, 3.625)
        end
    end) == 0, flavor .. ": warm combat layout called a pixel helper")
    world.widgets:SetCombat(false)

    -- Match the native BackdropTemplate/NineSlice lifecycle: the first apply
    -- creates nine textures; clear/reapply retain those exact same objects.
    local names = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
        "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
    local backdrop = pixel(env.CreateFrame("Frame"))
    local applications = 0
    backdrop.SetBackdrop = function(self, info)
        applications = applications + 1
        if info then
            for _, name in ipairs(names) do
                self[name] = self[name] or self:CreateTexture(nil, "BORDER")
            end
        end
        return nil, info, 41
    end
    pixel(backdrop, "SetBackdrop", settings)
    assert((backdrop._msufPixelLayoutBackdropReady == true) == expected, "backdrop cache not complete")
    world.widgets:SetCombat(true)
    assert(CountCalls({ [enable] = true, [env.MSUF_SetRoundLayoutToNearestPixel] = true }, function()
        for i = 1, 500 do
            local a, b, c = pixel(backdrop, "SetBackdrop", i % 2 == 0 and settings or nil)
            assert(a == nil and c == 41, "cached setter return values changed")
            assert(b == (i % 2 == 0 and settings or nil), "cached setter lost arguments")
        end
    end) == 0, "cached backdrop revisited pixel setup")
    assert(applications == 501, "pixel cache suppressed native setter")
    world.widgets:SetCombat(false)
    for _, name in ipairs(names) do
        assert((backdrop[name].pixelCalls or 0) == (expected and 1 or 0), "backdrop piece initialized twice")
    end

    -- A partial backdrop never poisons completion; blocked pieces are retried.
    local partial = pixel(env.CreateFrame("Frame"))
    partial.SetBackdrop = function(self, info)
        for _, name in ipairs(names) do
            self[name] = self[name] or self:CreateTexture(nil, "BORDER")
            self[name].IsProtected = function() return true end
        end
    end
    world.widgets:SetCombat(true)
    pixel(partial, "SetBackdrop", settings)
    assert(not partial._msufPixelLayoutBackdropReady, "combat-blocked backdrop marked complete")
    world.widgets:SetCombat(false)
    pixel(partial, "SetBackdrop", settings)
    assert((partial._msufPixelLayoutBackdropReady == true) == expected, "deferred backdrop could not retry")
    local smooth = pixel(env.CreateFrame("Frame"):CreateTexture(nil, "OVERLAY"), true)
    assert(not smooth.pixelCalls, "smooth art was enabled and immediately disabled")

    -- Run ClassPower's real builders twice with the same existing-profile
    -- inputs: native API present vs absent. Every requested segment/tick/text
    -- geometry and every saved setting must be identical across both runs.
    for _, scale in ipairs({ 0.5333333333, 0.7111111111, 0.83, 1, 1.25 }) do
        for _, shape in ipairs({ "BAR", "CIRCLE", "DIAMOND", "HEX" }) do
            for _, reverse in ipairs({ false, true }) do
                local function Build(native)
                    local nativeMethod = world.widgets.Methods.SetRoundLayoutToNearestPixel
                    if not native then world.widgets.Methods.SetRoundLayoutToNearestPixel = nil end
                    local bars = { classPowerWidthMode = "custom", classPowerWidth = 271.375,
                        classPowerOffsetX = -7.25, classPowerOffsetY = 13.625,
                        classPowerGap = 1.375, classPowerTickWidth = 1.25,
                        classPowerShape = shape, classPowerShapeAlign = "CENTER",
                        classPowerFillReverse = reverse, classPowerOutlineThickness = 0 }
                    local db = { bars = bars }
                    local before = Copy(db)
                    local player = env.CreateFrame("Frame", nil, env.UIParent)
                    player:SetScale(scale)
                    player:SetSize(277.375, 39.5)
                    local cp = { bars = {}, ticks = {}, maxBars = 0 }
                    local E = { CP = cp, _cpDB = db, CreateFrame = env.CreateFrame,
                        CP_ResolveTexture = function() return "WHITE" end,
                        CPConst = env.MSUF_CP_CONST,
                        ResolveClassPowerBgColor = function() return 0, 0, 0 end,
                        SetFilledAlpha = function() end, SetEmptyAlpha = function() end,
                        SetAutoHideActive = function() end }
                    local build = env.MSUF_CP_CORE_BUILDERS.BUILD(E)
                    build.CP_Create(player)
                    local text = build.CP_EnsureMainText()
                    local runeText = build.CP_EnsureRuneText(cp.bars[1])
                    local layout = env.MSUF_CP_CORE_BUILDERS.LAYOUT(E)
                    layout.CP_Layout(player, 5, 11.375, "COMBO_POINTS")
                    local out = { container = Geometry(cp.container), text = Geometry(text),
                        rune = Geometry(runeText), bars = {}, ticks = {} }
                    for i, bar in ipairs(cp.bars) do
                        out.bars[i] = Geometry(bar)
                        assert((bar.pixelEnabled == true) == (native and expected), "CP bar not gated")
                        assert((bar._bg.pixelEnabled == true) == (native and expected), "CP background not gated")
                    end
                    for i, tick in ipairs(cp.ticks) do
                        out.ticks[i] = Geometry(tick)
                        assert((tick.pixelEnabled == true) == (native and expected), "CP tick not gated")
                    end
                    assert((text.pixelEnabled == true) == (native and expected), "CP text not gated")
                    assert((runeText.pixelEnabled == true) == (native and expected), "rune text not gated")
                    assert(Equal(db, before), "existing ClassPower profile mutated")
                    -- Player mode must span the owning frame, including after Custom.
                    bars.classPowerWidthMode = "player"
                    layout.CP_Layout(player, 5, 11.375, "COMBO_POINTS")
                    local expectedWidth = math.floor(player:GetWidth() + 0.5)
                    if env.MSUF_Snap then expectedWidth = env.MSUF_Snap(cp.container, expectedWidth) end
                    assert(cp.container:GetWidth() == expectedWidth, "player width was inset")
                    assert(cp.container.points[1].x == bars.classPowerOffsetX, "player anchor was inset")
                    bars.classPowerWidthMode = "custom"
                    layout.CP_Layout(player, 5, 11.375, "COMBO_POINTS")
                    assert(Equal(Geometry(cp.container), out.container), "custom geometry changed after player mode")
                    world.widgets.Methods.SetRoundLayoutToNearestPixel = nativeMethod
                    return out
                end
                assert(Equal(Build(true), Build(false)), flavor .. ": layout inputs moved")
            end
        end
    end
end
-- Profile switches restore the selected profile's global scale before its
-- saved group offsets are reanchored, and restore Blizzard scale when it is off.
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor):Boot()
    assert(#world.failures == 0, flavor .. ": client boot failed")
    local env = world.env
    local general = assert(env.MSUF_DB and env.MSUF_DB.general)
    local apply = assert(env.MSUF_ApplyCurrentProfileGlobalUiScale)
    general.UIScale = { Enabled = true, Scale = 0.6 }
    general.globalUiScalePreset = "custom"
    assert(apply() and math.abs(env.UIParent:GetScale() - 0.6) < 0.0001,
        flavor .. ": old profile UI scale was not restored")
    assert(apply() and math.abs(env.UIParent:GetScale() - 0.6) < 0.0001,
        flavor .. ": same-scale profile apply drifted")
    general.UIScale.Enabled = false
    assert(apply() and math.abs(env.UIParent:GetScale() - 1) < 0.0001,
        flavor .. ": scale-off profile did not restore Blizzard scale")
end
print("pixel_layout_profile_smoke: ok (5 clients, profile scale switches, 200 ClassPower layout pairs, 15000 warm layout calls without pixel helpers)")

-- Native rasterization is not emulated; pin smooth-art policy and logical bounds.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
for _, skin in ipairs({ "midnight", "midnightDark", "classicGlass" }) do
    local world = World.New(root, flavor)
    world.widgets.Methods.SetRoundLayoutToNearestPixel = function(self, enabled)
        self.nativePixelRounding = enabled
    end
    world.env.MSUF_DB = { general = { menuAppearancePreset = skin } }
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.path)
    local M = assert(world.core.MSUF2)
    local W, T, env = M.Widgets, M.Theme, world.env
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(420, 180)
    local color = W.AttachContextColorShortcut(parent, { targets = {} })
    local action = T.Button(parent, "...", 34, 20)
    W.StyleSectionActionButton(action)
    for _, button in ipairs({ color, action }) do
        local function Check()
            local dots = assert(button._msuf2ThreeDotTextures)
            assert(#dots == 3, "three-dot shortcut lost its artwork")
            assert(button._msuf2Label._msuf2AlwaysHidden and not button._msuf2Label:IsShown(),
                "fallback label overlaps the dot artwork")
            for i, dot in ipairs(dots) do
                assert(dot.nativePixelRounding ~= true and ((flavor ~= "Mainline" and flavor ~= "Forever")
                    or dot._msufPixelLayoutExcluded == true),
                    "rounded shortcut art uses native pixel rounding")
                assert(dot.snapToPixelGrid == false and dot.texelSnappingBias == 0,
                    "rounded shortcut art uses pixel-grid texture snapping")
                local l, r, t, b = dot:GetTexCoord()
                assert(l == 0 and r == 1 and t == 0 and b == 1, "shortcut texture UV is cropped")
                local point, relative, relativePoint, x, y = dot:GetPoint()
                assert(point == "CENTER" and relative == button and relativePoint == "CENTER",
                    "shortcut dot lost its own button anchor")
                assert(x == (i - 2) * 7 and y == 0 and dot:GetWidth() == 5 and dot:GetHeight() == 5,
                    "shortcut dot geometry changed")
                assert(math.abs(x) + dot:GetWidth() / 2 < button:GetWidth() / 2
                    and dot:GetHeight() < button:GetHeight(), "shortcut dot escapes its button")
            end
        end
        for _, scale in ipairs({ 0.533333, 0.711111, 0.83, 1, 1.25 }) do
            parent:SetScale(scale)
            W.SetControlShown(button, false)
            W.SetControlShown(button, true)
            if button.RefreshVisual then button:RefreshVisual() end
            Check()
        end
        assert((button.nativePixelRounding == true) == (flavor == "Mainline" or flavor == "Forever"),
            "shortcut button lost its client-gated pixel alignment")
    end
end
print("PASS shortcut artwork: " .. flavor .. ", three skins, five scales, color and action buttons")

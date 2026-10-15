-- Full-overlay dressing must use the actual anchored extents, even when no
-- live frame exists or a uniform override bypasses the applied-size reader.
local root = assert(arg[1], "root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local selected = arg[3]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local atlasProbes = 0
local mw = World.Open(root, flavor, { page = "home", beforeCore = function(world)
    world.env.C_Texture = { GetAtlasInfo = function(name)
        if name == "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment" then
            atlasProbes = atlasProbes + 1
            return { width = 80, height = 90, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
        end
    end }
end })
local core, env = mw.core, mw.env
local UF, Preview = core.UF, core.UFPreview
local Portrait = UF.elements.Portrait
if core.Client.IsVanilla then
    assert(atlasProbes == 0, "Era must skip modern corner availability probe from initial menu construction")
end
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return "player" end
local box = Preview._BuildPreview(parent, panel, 900, 400)
box._manualZoom = 1
box:Show()
box.canvas:SetSize(600, 260)
local conf = env.MSUF_DB.player
conf.width, conf.height = 275, 40
conf.showPowerBar = false
conf.portraitMode, conf.portraitRender, conf.portraitShape = "LEFT", "CLASS", "BLIZZARD"
conf.portraitPlacement, conf.portraitOverlayAlign = "OVERLAY", "FULL"
conf.portraitSizeMode = "UNIFORM"
conf.portraitOffsetX, conf.portraitOffsetY = 0, 0
conf.portraitBlizzardCorner, conf.portraitBlizzardStandaloneRing = true, true
conf.portraitBorderStyle = "NONE"
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame:SetSize(275, 40)
frame.MSUFUnitKey = "player"
frame.Health = env.CreateFrame("StatusBar", nil, frame)
frame.Health:SetSize(275, 40)
frame.hpBar = frame.Health
local failures = {}
local function Near(actual, expected, label)
    if type(actual) ~= "number" or type(expected) ~= "number" or math.abs(actual - expected) > 1e-7 then
        failures[#failures + 1] = label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
    end
end
local function ComparePoints(actual, expected, label)
    assert(actual and expected, label .. " missing decoration")
    Near(actual:GetNumPoints(), expected:GetNumPoints(), label .. " point count")
    for i = 1, expected:GetNumPoints() do
        local ap, _, ar, ax, ay = actual:GetPoint(i)
        local ep, _, er, ex, ey = expected:GetPoint(i)
        assert(ap == ep and ar == er, label .. " anchor point differs")
        Near(ax, ex, label .. " X " .. i)
        Near(ay, ey, label .. " Y " .. i)
    end
end
for _, scenario in ipairs({ "no_live_frame", "size_override" }) do
    if not selected or selected == scenario then
        conf.portraitSizeOverride = scenario == "size_override" and 36 or 0
        UF.Config.Refresh()
        frame.MSUFSpec = UF.Config.GetSpec("player")
        Portrait.Apply(frame, frame.MSUFSpec)
        local live = assert(frame.MSUFPortraitHolder)
        UF.frames.player = scenario == "size_override" and frame or nil
        env.MSUF_player = UF.frames.player
        if scenario == "no_live_frame" then
            assert(core.UFPreviewRuntime.AppliedPortraitSizeForPreviewKey("player") == nil, "live size leaked into missing-frame case")
        end
        for pass = 1, 2 do
            local before = atlasProbes
            Preview.Refresh(box, "FULL_OVERLAY_PARITY")
            local portrait = box.mock.portrait
            assert(box._runtimeAppliedPortraitW == nil, "scenario did not bypass applied-size reader")
            Near(box._mockScale, 1, scenario .. " preview zoom")
            Near(portrait._msufPreviewLayoutWidth, live._msufLayoutWidth, scenario .. " cached full width")
            Near(portrait._msufPreviewLayoutHeight, live._msufLayoutHeight, scenario .. " cached full height")
            Near(portrait._msufLayoutWidth, live._msufLayoutWidth, scenario .. " painted full width")
            Near(portrait._msufLayoutHeight, live._msufLayoutHeight, scenario .. " painted full height")
            Near(portrait._msufPreviewBorderSpec.width, live._msufLayoutWidth, scenario .. " spec width")
            Near(portrait._msufPreviewBorderSpec.height, live._msufLayoutHeight, scenario .. " spec height")
            if core.Client.IsVanilla then
                ComparePoints(portrait.artBorder, live.artBorder, scenario .. " Era gold ring")
                Near(select(4, live.artBorder:GetPoint(1)), -26, "275px Era ring reference")
                Near(atlasProbes, before, "Era must skip modern corner availability probe")
                print(scenario .. " ring X: preview=" .. select(4, portrait.artBorder:GetPoint(1))
                    .. " live=" .. select(4, live.artBorder:GetPoint(1)))
            else
                ComparePoints(portrait.blizzCorner, live.blizzCorner, scenario .. " modern corner")
                assert(portrait.blizzRing:IsShown() and live.blizzRing:IsShown(), "stock rim hidden")
            end
        end
    end
end
if not selected or selected == "availability" then
    -- Reinstall the real painter to observe its cold capability probe even if
    -- opening the menu already warmed the original closure.
    core.UFPreviewRender.Install(Preview, Preview.RefreshDeps)
    local render = Preview.RefreshDeps._RenderState
    local before = atlasProbes
    render.LayoutPreviewBlizzardPortrait(box.mock.portrait, true, 36, 36, true, true, {})
    if core.Client.IsVanilla then Near(atlasProbes, before, "cold Era corner availability probe") end
end
assert(#failures == 0, table.concat(failures, "; "))
print("portrait_full_overlay_preview_smoke: ok (" .. flavor .. "; no live frame, uniform override, repeated full overlay)")

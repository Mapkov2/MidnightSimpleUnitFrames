-- Preview background scene smoke.
--
--   lua tools/tests/preview_background_scene_smoke.lua <repo root>
--
-- The Menu2 previews can sit on four image scenes (Silvermoon, City scene, Bright
-- stone, Dark stone). They ship as PNG. The WoW Forever beta client leaves those
-- PNG files black, so every scene also ships as BLP2/DXT1, the client's own
-- texture format: Forever starts from the BLP, every other client keeps the PNG
-- and swaps to the BLP once, on first use, when SetTexture reports a failed load.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local MEDIA = root .. "/MidnightSimpleUnitFrames_Options/Media/PreviewBackgrounds/"
local SCENES = { "bright_stone", "city_scene", "dark_stone", "silvermoon" }

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Media: every PNG scene has a loadable BLP twin
---------------------------------------------------------------------------
local function U32(data, offset)
    local a, b, c, d = data:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
for _, scene in ipairs(SCENES) do
    Check(io.open(MEDIA .. scene .. ".png", "rb"), scene .. ".png is missing"):close()
    local handle = Check(io.open(MEDIA .. scene .. ".blp", "rb"), scene .. ".blp is missing")
    local data = handle:read("*a")
    handle:close()
    Check(data:sub(1, 4) == "BLP2", scene .. ".blp is not a BLP2 file")
    Check(U32(data, 4) == 1, scene .. ".blp must be a directly encoded texture (type 1)")
    local encoding, alphaDepth, alphaEncoding, hasMips = data:byte(9, 12)
    Check(encoding == 2 and alphaDepth == 0 and alphaEncoding == 0, scene .. ".blp must be DXT1 without alpha")
    Check(hasMips == 1, scene .. ".blp must carry its mip chain")
    local width, height = U32(data, 12), U32(data, 16)
    Check(width == 1024 and height == 512, scene .. ".blp must keep the 1024x512 scene size")
    Check(U32(data, 20) == 1172 and U32(data, 84) == width * height / 2,
        scene .. ".blp: the first mip must follow the 1172 byte header and hold one DXT1 level")
    local last = 0
    for level = 0, 15 do
        local offset, size = U32(data, 20 + level * 4), U32(data, 84 + level * 4)
        if size > 0 then
            Check(offset >= 1172 and offset + size <= #data, scene .. ".blp: mip " .. level .. " points outside the file")
            last = math.max(last, offset + size)
        end
    end
    Check(last == #data, scene .. ".blp carries bytes no mip level owns")
end

---------------------------------------------------------------------------
-- Code: which file a client starts from, and the one-time fallback
---------------------------------------------------------------------------
local function LoadHelpers(isForever)
    local main = {
        Client = { IsForever = isForever },
        UF = { Clamp01 = function(value, fallback) return tonumber(value) or fallback end },
        MSUF2 = {},
    }
    _G.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
    _G.issecretvalue = function() return false end
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))(
        "MidnightSimpleUnitFrames_Options", main)
    return main.MSUF2.PreviewHelpers, main.MSUF2
end

-- A canvas whose image texture records every SetTexture and can refuse PNG files.
local function Canvas(refusePNG)
    local image = { sets = {} }
    function image:SetTexture(path)
        self.sets[#self.sets + 1] = path
        self.texture = path
        if refusePNG and type(path) == "string" and path:find("%.png$") then return false end
        return true
    end
    function image:SetAllPoints() end
    function image:SetVertexColor() end
    function image:SetTexCoord() end
    function image:Show() self.shown = true end
    function image:Hide() self.shown = false end
    local frame = { image = image }
    function frame:CreateTexture() return image end
    function frame:HookScript() end
    function frame:GetWidth() return 1000 end
    function frame:GetHeight() return 200 end
    function frame:SetBackdropColor() end
    return frame, image
end
local PALETTE = { canvasBg = { 0, 0, 0, 1 }, canvasTop = { 0, 0, 0, 1 }, canvasBottom = { 0, 0, 0, 1 } }

-- WoW Forever starts from the BLP scene.
do
    local H, M = LoadHelpers(true)
    M.previewBackground = "silvermoon"
    local frame, image = Canvas(false)
    H.ApplyPreviewBackground(frame, PALETTE, nil)
    Check(image.texture and image.texture:find("PreviewBackgrounds\\silvermoon%.blp$"),
        "Forever must draw the BLP scene, got " .. tostring(image.texture))
    Check(image.shown == true, "Forever: the scene image must be shown")
    local _, spec = H.GetPreviewBackground()
    Check(spec.texture:find("%.blp$"), "Forever: the dropdown thumbnail must use the BLP scene too")
end

-- Every other client keeps the PNG while it loads.
do
    local H, M = LoadHelpers(false)
    M.previewBackground = "silvermoon"
    local frame, image = Canvas(false)
    H.ApplyPreviewBackground(frame, PALETTE, nil)
    Check(image.texture and image.texture:find("PreviewBackgrounds\\silvermoon%.png$"),
        "a client that loads PNG must keep the PNG scene, got " .. tostring(image.texture))
end

-- A client that reports a failed PNG load swaps to the BLP, once, for every scene.
do
    local H, M = LoadHelpers(false)
    M.previewBackground = "city_scene"
    local frame, image = Canvas(true)
    H.ApplyPreviewBackground(frame, PALETTE, nil)
    Check(image.texture and image.texture:find("PreviewBackgrounds\\city_scene%.blp$"),
        "a refused PNG must fall back to the BLP scene, got " .. tostring(image.texture))
    local probes = #image.sets
    H.ApplyPreviewBackground(frame, PALETTE, nil)
    Check(#image.sets == probes + 1, "the PNG check must run once, not on every repaint")
    for _, scene in ipairs(SCENES) do
        M.previewBackground = scene
        local _, spec = H.GetPreviewBackground()
        Check(spec.texture:find(scene .. "%.blp$"), "every scene must follow the fallback: " .. scene)
    end
    -- Studio has no image at all.
    M.previewBackground = "studio"
    H.ApplyPreviewBackground(frame, PALETTE, nil)
    Check(image.shown == false, "the Studio background must hide the scene image")
end

print("preview_background_scene_smoke: ok")

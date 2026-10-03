-- Issue #159: icon artwork edges must not overdraw the configured border.
local root = assert(arg[1], "repo root required")
local function Noop() end
local namespace = { Client = { IsClassic = true }, MSUF_Auras3 = {} }
local function Load(path)
    return assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", namespace)
end
Load("Auras3/MSUF_Auras3_IconShape.lua")
local A3 = namespace.MSUF_Auras3
local function Clamp(value, fallback, low, high)
    return math.max(low, math.min(high, tonumber(value) or fallback))
end
Load("Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua")
local native = namespace.Auras3RuntimeFactories.ConfigValues("MidnightSimpleUnitFrames", namespace, A3, {}, nil, {
    Appearance = { Shape = A3.IconShape }, Platform = { ClampNumber = Clamp }, Schema = {}, Signatures = {},
})
Load("Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
local function CheckZoom(label, apply)
    for _, case in ipairs({ {100, 0.07}, {110, 0.07}, {125, 0.1}, {150, 1/6}, {200, 0.25} }) do
        local writes, coords = 0
        local texture = { SetShown=Noop, Show=Noop, SetTexture=Noop, SetVertexColor=Noop,
            ClearAllPoints=Noop, SetAllPoints=Noop, SetTexCoord = function(_, ...)
            writes = writes + 1
            coords = {...}
        end }
        apply(texture, case[1])
        assert(coords and math.abs(coords[1] - case[2]) < 0.000001,
            label .. ": zoom " .. case[1] .. " exposes baked icon border; inset=" .. tostring(coords and coords[1]))
        assert(coords[1] == coords[3] and coords[2] == coords[4] and coords[2] == 1-coords[1], label .. ": symmetric crop")
        if label == "native" then
            apply(texture, case[1])
            assert(writes == 1, "unchanged native zoom must not rewrite UVs")
        end
    end
end
CheckZoom("native", function(texture, zoom) native.ApplyAuraIconZoom(texture, {iconZoom=zoom}) end)
A3.ApplyAuraIconShape = function() end
A3.ApplyIconStylePreview = function() end
CheckZoom("classic", function(texture, zoom)
    A3.ClassicVisuals.ApplyButtonLayout({config={size=24,iconZoom=zoom}}, {Icon=texture})
end)
local function PreviewZoom(path, functionName)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local code = assert(source:match("local function " .. functionName .. "%(.-\nend"), path)
    local chunk = assert(loadstring(code .. "\nreturn " .. functionName))
    setfenv(chunk, setmetatable({A3=A3, MSUF=namespace, Clamp=Clamp, ClampNumber=Clamp,
        max=math.max, min=math.min, floor=math.floor, VALID_POINTS={TOPLEFT=true},
        PreviewLayerOn=function() return false end, FrameAuraPreviewOffset=function() return 0,0 end, ApplySpellFrameEffectPreview=function() return false end,
    }, {__index=_G}))
    return chunk()
end
CheckZoom("Edit Mode", PreviewZoom("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_Preview.lua", "ApplyIconZoom"))
CheckZoom("Unit preview", PreviewZoom("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua", "ApplyIconZoom"))
CheckZoom("Group preview", PreviewZoom("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua", "ApplyPreviewIconZoom"))
CheckZoom("Aura Style preview", PreviewZoom("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Preview.lua", "ApplyAuraPreviewIconZoom"))
local groupPath = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua"
local auraPreview = PreviewZoom(groupPath, "ApplyFrameAuraPreview")
local spellPreview = PreviewZoom(groupPath, "ApplySpellIndicatorPreview")
local function Visual(texture)
    return {_texture=texture,ClearAllPoints=Noop,SetSize=Noop,SetPoint=Noop,Show=Noop,SetShown=Noop}
end
CheckZoom("in-world group aura preview", function(texture, zoom)
    auraPreview({}, "party", Visual(texture), {iconZoom=zoom}, {textures={123}}, 0, 1, {})
end)
CheckZoom("in-world group spell preview", function(texture, zoom)
    spellPreview({}, "party", Visual(texture), {visual="icon",iconZoom=zoom})
end)
A3.SpellIndicators = {IdentityCandidateMode=function() return "neutral" end, _deps={IconShape=A3.IconShape}}
Load("Auras3/MSUF_Auras3_SpellIndicators_Reminders.lua")
local reminders = A3.SpellIndicatorModules.Reminders({ClampNumber=Clamp,
    ResolveFrameStrata=Noop,SyncFrameStrata=Noop,SpellIconBaseOffset=function() return 1 end},
    {GroupOutputVisible=function() return true end})
reminders.Install(Noop)
CheckZoom("missing spell reminder", function(texture, zoom)
    local frame=Visual(texture)
    frame._tex,frame._label=texture,{Hide=Noop,SetText=Noop}
    frame.SetFrameLevel=Noop
    local parent={_msufA3SpellIndicatorMissingFrames={one=frame},GetFrameLevel=function() return 1 end}
    reminders.SyncMissingFrame(parent,{slotKey="one",showWhenMissing=true,visual="icon",iconZoom=zoom})
end)
print("PASS aura icon crop: native, Classic, reminders and all previews; zoom and unchanged native writes")

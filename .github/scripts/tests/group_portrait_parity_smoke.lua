-- Party GroupFrames portrait integration contract.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.MSUF_DB = {
    general = {},
    gf_party = {},
    gf_raid = { portraitMode = "LEFT" }, -- stale/imported data must stay inert
    gf_mythicraid = { portraitMode = "RIGHT" },
}

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local GF = MSUF.GF
Check(GF.PARTY_DEFAULTS.portraitMode == "OFF", "party portrait must default off")
Check(GF.PARTY_DEFAULTS.portraitRender == "2D", "party portrait render default drifted")
Check(GF.RAID_DEFAULTS.portraitMode == nil, "raid defaults must not inherit party portrait keys")
Check(GF.MYTHIC_RAID_DEFAULTS.portraitMode == nil, "mythic defaults must not inherit party portrait keys")

local conf = _G.MSUF_DB.gf_party
conf.portraitMode = "RIGHT"
conf.portraitRender = "CLASS"
conf.portraitClassStyle = "BLIZZARD"
conf.portraitShape = "DIAMOND"
conf.portraitSizeOverride = 44
conf.portraitWidth = 52
conf.portraitHeight = 38
conf.portraitOffsetX = 7
conf.portraitOffsetY = -3
conf.portraitPlacement = "DETACHED"
conf.portraitDetachedPoint = "TOPRIGHT"
conf.portraitDetachedTo = "BOTTOMLEFT"
conf.portraitLevelOffset = 12
conf.portraitAlpha = 65
conf.portraitCastSpellIcon = true
conf.portraitBorderStyle = "CUSTOM"
conf.portraitBorderThickness = 4
conf.portraitFillBorder = true
conf.portraitBorderArt = "RELIEF"
conf.portraitBorderDirection = "RIGHT"
conf.portraitBorderColorR = 0.2
conf.portraitBorderColorG = 0.3
conf.portraitBorderColorB = 0.4
conf.portraitBorderColorA = 0.5
conf.portraitBgEnabled = true
conf.portraitBgColorR = 0.11
conf.portraitBgColorG = 0.12
conf.portraitBgColorB = 0.13
conf.portraitBgColorA = 0.75

GF.InvalidateCompiledSpecs("party")
local portrait = GF.CompileSpec("party", nil, "party1").portrait
Check(portrait.enabled == true and portrait.side == "RIGHT", "party portrait mode did not compile")
Check(portrait.render == "CLASS" and portrait.classStyle == "BLIZZARD", "class portrait did not compile")
Check(portrait.shape == "DIAMOND", "portrait shape did not compile")
Check(portrait.size == 44 and portrait.width == 52 and portrait.height == 38, "portrait geometry did not compile")
Check(portrait.x == 7 and portrait.y == -3, "portrait offsets did not compile")
Check(portrait.placement == "DETACHED" and portrait.point == "TOPRIGHT" and portrait.relPoint == "BOTTOMLEFT",
    "detached portrait anchors did not compile")
Check(portrait.levelOffset == 12 and portrait.alpha == 0.65, "portrait layer/alpha did not compile")
Check(portrait.castSpellIcon == true, "portrait cast-spell overlay did not compile")
Check(portrait.border.style == "CUSTOM" and portrait.border.thickness == 4
    and portrait.border.fill == true and portrait.border.art == "RELIEF"
    and portrait.border.direction == "RIGHT", "portrait border contract did not compile")
Check(portrait.border.r == 0.2 and portrait.border.a == 0.5, "static portrait border color did not compile")
Check(portrait.bg.enabled == true and portrait.bg.r == 0.11 and portrait.bg.a == 0.75,
    "portrait background did not compile")

GF.InvalidateCompiledSpecs("raid")
Check(GF.CompileSpec("raid", nil, "raid1").portrait.enabled == false,
    "stale raid portrait settings must compile disabled")
GF.InvalidateCompiledSpecs("mythicraid")
Check(GF.CompileSpec("mythicraid", nil, "raid1").portrait.enabled == false,
    "stale mythic portrait settings must compile disabled")
Check(GF.Metadata.MASK_VISUAL.Portrait == true and GF.Metadata.MASK_RUNTIME.Portrait == true,
    "group portrait is missing from visual/runtime apply masks")

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), path .. " missing")
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local adapter = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua")
Check(adapter:find("Portrait = true", 1, true), "group apply allowlist still excludes Portrait")
local menu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
Check(menu:find('local kind = "party"', 1, true), "portrait menu bindings are not fixed to party")
Check(menu:find('"gf_party." .. tostring(key)', 1, true), "portrait menu lacks exact party Assistant keys")
Check(menu:find('CurrentScope() == "party"', 1, true), "portrait menu shell is not party-gated")
Check(menu:find('W.AttachContextColorReferences(borderCard, { "group.portrait.border" }', 1, true),
    "group portrait border lacks the Unitframe-style context color shortcut")
Check(not menu:find('BindColor(borderCard, "Color"', 1, true),
    "group portrait border still exposes the removed inline Color row")
Check(not menu:find('BindNumber(borderCard, "Opacity"', 1, true),
    "group portrait border still exposes the removed inline Opacity row")
Check(menu:find('W.AttachGroupEditFocus(widget, stateKey, "portrait")', 1, true),
    "portrait controls do not focus the Party portrait preview layer")
local colors = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
Check(colors:find('FixedContextFactory("group.portrait.border"', 1, true)
    and colors:find('"portraitBorderColor", 1, 1, 1, "portraitBorderColorA", 1', 1, true),
    "group portrait context color does not own the group RGB/opacity settings")
local preview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(preview:find("PaintGroupPreviewPortrait(scene)", 1, true), "group preview does not paint the compiled portrait")
Check(preview:find('scene.kind ~= "party"', 1, true), "group portrait preview is not party-gated")
Check(preview:find("scene.S and scene.S.portraitHandle", 1, true),
    "group portrait renderer does not use the interactive preview handle")
Check(preview:find("local portraitHandle = deps.portraitHandle", 1, true)
    and preview:find("portraitHandle = portraitHandle", 1, true),
    "Render.Install drops the portrait handle before the real refresh path")
Check(preview:find("EnsureGroupPreviewPortrait(scene.mock, handle)", 1, true),
    "group portrait visual is not owned by its mouse handle")
Check(preview:find("holder = handle", 1, true)
    and preview:find("mock._msufGroupPortrait = holder", 1, true),
    "group portrait Button is not the visible portrait owner")
Check(preview:find("holder:SetMouseClickEnabled(true)", 1, true)
    and preview:find("holder:SetMouseMotionEnabled(true)", 1, true),
    "group portrait Button does not explicitly own click and hover interaction")
Check(preview:find("if holder ~= handle then", 1, true),
    "group portrait renderer can still overlay a separate visual frame on its Button")
Check(preview:find('button._layerKey ~= "portrait" or scene.kind == "party"', 1, true),
    "portrait layer row must be hidden outside Party")

local handles = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
Check(handles:find('CreatePreviewHandle("portrait", "portrait"', 1, true),
    "group preview does not create a portrait mouse handle")
Check(handles:find('36, 36, false, dragParent)', 1, true),
    "group portrait mouse handle must use the preview stage outside mock bounds")
Check(handles:find("portraitHandle._cfgPortrait = true", 1, true),
    "group portrait handle lacks its dedicated offset contract")
Check(handles:find('conf.portraitOffsetX = OffsetToConfig(offX or 0, scale)', 1, true)
    and handles:find('conf.portraitOffsetY = OffsetToConfig(offY or 0, scale)', 1, true),
    "group portrait dragging does not persist portrait X/Y")

local native = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
Check(native:find('{ "Portrait", { 0.90, 0.42, 1.00 }, "portrait", "portrait" }', 1, true),
    "group preview layer sidebar lacks Portrait")
Check(native:find("renderDeps.portraitHandle = portraitHandle", 1, true),
    "group preview does not pass the portrait handle to the renderer")

local specs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Specs.lua")
Check(specs:find("portrait=gf_layout", 1, true), "portrait preview settings do not route to Group Layout")

local focus = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Focus.lua")
Check(focus:find('if component == "portrait" then return "portrait" end', 1, true),
    "portrait preview selection does not route to the Portrait section")

local layers = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_LayerOverview.lua")
Check(layers:find('if scope.key == "party" then', 1, true)
    and layers:find('settingKey = "gf_party.portraitLevelOffset"', 1, true),
    "Party portrait is missing from the layer overview")

local element = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua")
Check(element:find('return DYNAMIC_PORTRAIT_BORDER[style] == true', 1, true),
    "load-bearing static border event fast path changed")
Check(not element:find('SetScript("OnUpdate"', 1, true), "portrait runtime must remain event-driven")

print("PASS group portrait parity: party-only runtime/menu plus draggable preview layer")

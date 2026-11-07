-- Exercise the Menu2 painter when an external skin owns its button material.
-- The rail owns its stripe. The tab uses the surface provided by its skin.
local root = assert(arg[1], "Classic repository root required")
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local themeFile = arg[2] or "MSUF_Menu2_Theme.lua"
local themeSource = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/" .. themeFile)
local cueStart = assert(themeSource:find("local function SetNavStripe", 1, true),
    "skinned selection cue missing")
local painterStart = assert(themeSource:find("local function ButtonVisual", cueStart, true),
    "Menu2 button painter missing")
local nativePaintStart = assert(themeSource:find("    local c = T.colors", painterStart, true),
    "Menu2 native paint boundary missing")
local cueAndSkinBranch = themeSource:sub(cueStart, painterStart - 1)
    .. themeSource:sub(painterStart, nativePaintStart - 1)
    .. "\nend\nreturn ButtonVisual"

local theme = { colors = { accent = { 0, 0, 0, 1 }, navTextActive = { 0.94, 0.96, 1, 1 } } }
local skin = { owned = true }
function skin.Button() return skin.owned end

local factory = assert(loadstring("local T, MenuSkin, HideNavPillArt, SetNavActiveFX = ...\n"
    .. "local PixelLayoutRegion = function(region) return region end\n"
    .. cueAndSkinBranch))
local paint = factory(theme, skin, function() end, function() end)

local function NewButton(role)
    local button = { textures = {} }
    button[role] = true
    function button:CreateTexture(_, layer, _, sublevel)
        local texture = { layer = layer, sublevel = sublevel, shown = false }
        function texture:SetTexture(path) self.path = path end
        function texture:SetPoint(point, owner, relativePoint, x, y)
            self[point] = { owner, relativePoint, x or 0, y or 0 }
        end
        function texture:SetWidth(width) self.width = width end
        function texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        function texture:IsShown() return self.shown end
        function texture:SetShown(shown) self.shown = shown end
        self.textures[#self.textures + 1] = texture
        return texture
    end
    return button
end
local function CueShown(button)
    local cue = button._msuf2SkinnedSelectionCue
    return cue and cue.wash:IsShown() and cue.line:IsShown()
end

local nav = NewButton("_msuf2NavItem")
paint(nav, false, false)
assert(not nav._msuf2SkinnedSelectionCue, "idle Unitframes row allocated a selection cue")
paint(nav, true, false)
assert(CueShown(nav) and #nav.textures == 2, "selected Unitframes row is not highlighted")
assert(nav._msuf2SkinnedSelectionCue.line.width == 3, "selected rail marker lost its width")
assert(nav._msuf2SkinnedSelectionCue.line.color[1] >= 0.8, "black accent hides the selection marker")
theme.colors.navTextActive = { 0.90, 0.95, 1, 1 }
paint(nav, true, true)
assert(#nav.textures == 2 and nav._msuf2SkinnedSelectionCue.line.color[1] == 0.90,
    "theme refresh allocated art or kept the old selection color")
paint(nav, false, false)
assert(not CueShown(nav), "old Unitframes selection remains visible")

local widgetsSource = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_Controls.lua")
local barStart = assert(widgetsSource:find("function W.ScopeOverrideBar", 1, true), "unit scope bar missing")
local barEnd = assert(widgetsSource:find("function W.ScopeOverrideTooltipBody", barStart, true),
    "unit scope bar end missing")
assert(widgetsSource:sub(barStart, barEnd - 1):find("btn._msuf2SegmentChoice = true", 1, true),
    "unit tabs are not marked as selectable")
local target = NewButton("_msuf2SegmentChoice")
paint(target, true, false)

assert(#target.textures == 0 and not target._msuf2SkinnedSelectionCue,
    "selected tab painted separate art over the external skin")
paint(target, false, false)
assert(#target.textures == 0, "deselecting allocated overlay art")

local ordinary = NewButton("_msuf2OrdinaryButton")
skin.owned = true
paint(ordinary, true, false)
assert(not ordinary._msuf2SkinnedSelectionCue and not ordinary._msuf2TabOutline, "ordinary button got a selection cue")
print("menu2_skinned_selection_smoke: Unitframes and Target selection transitions passed")

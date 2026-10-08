-- Real Menu2 groups: title hierarchy, portrait containment and retained actions.
-- These are layout inputs and offline interactions, not native pixel proof.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {
    page = "home",
    locale = arg[3] or "enUS",
    beforeCore = function(world)
        -- The shared stub omits the inherited GameFont template tuple.
        local CreateFontString = world.widgets.Methods.CreateFontString
        world.widgets.Methods.CreateFontString = function(self, ...)
            local fs = CreateFontString(self, ...)
            fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
            return fs
        end
    end,
})
local M, W, T = mw.M, mw.M.Widgets, mw.M.Theme
local failures, checks, surfaces = {}, 0, {}
local function Check(ok, message)
    checks = checks + 1
    if not ok then failures[#failures + 1] = message end
end
local function XY(region)
    local _, _, _, x, y = region:GetPoint()
    return tonumber(x) or 0, -(tonumber(y) or 0)
end
local function Descendant(frame, parent)
    while frame do
        if frame == parent then return true end
        frame = frame:GetParent()
    end
end
local function Divider(card)
    for _, region in ipairs({ card:GetRegions() }) do
        if region ~= card.title and region:GetHeight() == 1 then return region end
    end
end
local Panel = T.Panel
T.Panel = function(...)
    local panel = Panel(...)
    surfaces[panel] = true
    return panel
end
local probe = W.ControlCard(mw.env.UIParent, "Geometry", nil, 0, 0, 360, 160)
local toggle = W.ToggleAt(probe, "Enable", 16, -62, 300)
local _, headingSize = probe.title:GetFont()
local _, controlSize = toggle._msuf2Label:GetFont()
Check(headingSize > controlSize, "group headings do not stand above ordinary control labels")
Check(controlSize == T.FontSize("control"), "ordinary label sizing changed")
Check(surfaces[probe], "normal cards lost their filled surface")
local width, Builder, Lazy = 760, W.PageBuilder, M.UnitPage.BuildSectionLazy
W.PageBuilder = function(ctx) ctx.width = width; return Builder(ctx) end
local groups = {
    { "general", "Visibility & Mode" }, { "geometry", "Geometry" },
    { "placement", "Placement" }, { "border", "Shape & Border" },
    { "advanced", "Class & Background" }, { "dragon", "Dragon decoration" },
}
local function Build(mode)
    mw:Select("home")
    if mode == "eager" then M.UnitPage.BuildSectionLazy = nil
    else M.UnitPage.BuildSectionLazy = Lazy end
    M.InvalidatePage("uf_player")
    if mode == "hidden" then M.BuildPageEntry("uf_player", true); mw:RunTimers()
    else mw:Select("uf_player") end
    local body = assert(M.cache.uf_player.sections.portrait)
    body._msuf2CollapsibleEntry.SetOpenImmediate(true)
    mw:RunTimers()
    return body
end
local opened
local OpenPicker = W.OpenColorContextPicker
W.OpenColorContextPicker = function(_, owners) opened = owners end
for _, testWidth in ipairs({ 520, 760, 1100 }) do
    width = testWidth
    for _, mode in ipairs({ "visible", "hidden", "eager" }) do
        local body, cards = Build(mode), {}
        local label = flavor .. " " .. width .. "px " .. mode
        for _, frame in ipairs(mw.world.widgets.frames) do
            if frame._msuf2ControlCard and Descendant(frame, body) then
                cards[frame._msuf2ControlCardTitle] = frame
            end
        end
        for _, group in ipairs(groups) do
            local tab, title = group[1], group[2]
            local card = assert(cards[title], title .. " group missing")
            Check(not surfaces[card] and card:GetBackdrop() == nil, label .. ": " .. title .. " nests a filled surface")
            Check(not card:IsMouseEnabled(), label .. ": decorative group intercepts input")
            Check(body._msuf2GuidedSelectTab(tab) == true, label .. ": guided tab selection failed")
            mw:RunTimers()
            local x, y = XY(card)
            local _, tabY = XY(card:GetParent())
            Check(x >= 0 and x + card:GetWidth() <= width, label .. ": " .. title .. " escapes width")
            Check(tabY + y + card:GetHeight() <= body:GetHeight(), label .. ": " .. title .. " escapes tab height")
            Check(card:GetParent():IsShown(), label .. ": chosen group stays hidden")
            for _, other in ipairs(groups) do
                Check(cards[other[2]]:GetParent():IsShown() == (other[1] == tab), label .. ": tab visibility drift")
            end
            local _, titleY = XY(card.title)
            local _, size = card.title:GetFont()
            Check(size > controlSize, label .. ": " .. title .. " heading is not distinguished")
            local divider = Divider(card)
            Check(divider ~= nil, label .. ": " .. title .. " has no group divider")
            local dividerY = divider and select(2, XY(divider)) or 0
            Check(dividerY >= titleY + card.title:GetStringHeight() + 4, label .. ": divider crowds heading")
            for _, frame in ipairs(mw.world.widgets.frames) do
                if frame:GetParent() == card and frame._msuf2ControlKind then
                    local cx, cy = XY(frame)
                    local top = frame._msuf2ContextLayoutY and -frame._msuf2ContextLayoutY or cy
                    local controlWidth = frame:GetWidth()
                    if frame._msuf2ControlKind == "toggle" then
                        -- Toggle labels reserve a wrapping box; the actual click
                        -- proxy follows the measured text and is the hit bound.
                        cx = cx - 4
                        controlWidth = frame._msuf2LabelHit:GetWidth()
                    elseif frame._msuf2ControlKind == "slider" then
                        controlWidth = frame._msuf2RequestedWidth or controlWidth
                    end
                    Check(cx >= 12 and cx + controlWidth <= card:GetWidth() - 12,
                        label .. ": " .. tostring(frame._msuf2StableSearchLabel or frame._msuf2SearchText)
                            .. " exceeds group horizontal bounds (" .. cx .. ", " .. controlWidth .. ", " .. card:GetWidth() .. ")")
                    Check(top >= dividerY + 8 and cy + frame:GetHeight() + 4 <= card:GetHeight(),
                        label .. ": " .. title .. " / " .. tostring(frame._msuf2StableSearchLabel or frame._msuf2SearchText)
                            .. " crosses group heading or bottom padding (" .. top .. ", " .. (cy + frame:GetHeight()) .. ")")
                    local contract = frame._msuf2ExactTargetContracts
                    local key = contract and contract.unitPortraitTab and contract.unitPortraitTab[tab]
                    if key then
                        body._msuf2GuidedSelectTab("general")
                        Check(frame:_msuf2PrepareExactSearchTarget({ prepareKind = "unitPortraitTab", prepareValue = tab }) == true,
                            label .. ": exact target cannot reveal its group")
                    end
                end
            end
            if card._msuf2ContextColorShortcut then
                local shortcut = card._msuf2ContextColorShortcut
                local _, _, _, sx, sy = shortcut:GetPoint()
                local tx = select(1, XY(card.title))
                Check(tx + card.title:GetWidth() + 4 <= card:GetWidth() + sx - shortcut:GetWidth(),
                    label .. ": heading overlaps color shortcut")
                Check(-sy + shortcut:GetHeight() < dividerY, label .. ": color shortcut crosses divider")
                opened = nil
                shortcut:GetScript("OnClick")(shortcut)
                Check(opened and #opened == 1 and opened[1]._msuf2OnColorChanged,
                    label .. ": portrait color action lost its canonical target")
            end
        end
    end
end
-- Additional open groups use real page builders on every client.
local additional = {
    gf_layout = { ["Visibility & Size"] = true, ["Border & fill"] = true,
        ["Roles"] = true, ["Detached placement"] = true },
    classpower = { ["Shape & Size"] = true, ["Position"] = true, ["Resource & Textures"] = true,
        ["Text"] = true, ["Opacity"] = true, ["Pips & Border"] = true },
    uf_player = { ["Provider & Surface"] = true, ["Size"] = true, ["Portrait Cast Icon"] = true,
        ["Cast Target Text"] = true, ["Spell Text Behavior"] = true, ["Icon Style"] = true,
        ["Whole Castbar Layer"] = true },
}
M.UnitPage.BuildSectionLazy = nil
for _, testWidth in ipairs({ 520, 760, 1100 }) do
    width = testWidth
    for pageKey, wanted in pairs(additional) do
        mw:Select("home")
        M.InvalidatePage(pageKey)
        local first = #mw.world.widgets.frames + 1
        mw:Select(pageKey)
        local entry = assert(M.cache[pageKey])
        for _, body in pairs(entry.sections or {}) do
            local section = body._msuf2CollapsibleEntry
            if section then section.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        local found = {}
        for i = first, #mw.world.widgets.frames do
            local card = mw.world.widgets.frames[i]
            local title = card._msuf2ControlCardTitle
            if card._msuf2ControlCard and wanted[title] then
                found[title] = true
                local label = flavor .. " " .. width .. "px " .. pageKey .. " / " .. title
                Check(not surfaces[card] and card:GetBackdrop() == nil, label .. " remains a filled inner card")
                Check(not card:IsMouseEnabled(), label .. " intercepts input")
                Check(Divider(card) ~= nil, label .. " has no open-group divider")
                local _, size = card.title:GetFont()
                Check(size > controlSize, label .. " lost its heading hierarchy")
                local x = XY(card)
                local bound = pageKey == "uf_player" and math.max(width, 680) or width
                Check(x >= 0 and x + card:GetWidth() <= bound, label .. " exceeds its established minimum page width")
                if card._msuf2ContextColorShortcut then
                    local shortcut = card._msuf2ContextColorShortcut
                    Check(type(shortcut:GetScript("OnClick")) == "function", label .. " lost its contextual color action")
                end
            end
        end
        for title in pairs(wanted) do
            -- Cast Target Text depends on the client's/unit's castbar fields.
            if title ~= "Cast Target Text" then
                Check(found[title], flavor .. " " .. width .. "px " .. pageKey .. " missing " .. title)
            end
        end
    end
end
W.OpenColorContextPicker, W.PageBuilder, M.UnitPage.BuildSectionLazy, T.Panel = OpenPicker, Builder, Lazy, Panel
-- Attach the real public skin bridge after the unskinned layout checks. Live
-- palette changes repaint existing groups, and disabling restores native color.
local native = { unpack(T.colors.borderSoft) }
local enabled, rgb = true, { 0.11, 0.22, 0.33 }
local client = { ReleaseAll = function() end, Release = function() end }
local api = {
    RegisterAddon = function() return client end,
    IsEnabled = function() return enabled end,
    GetAppearanceSnapshot = function() return {} end,
    GetColor = function() return rgb[1], rgb[2], rgb[3], 1 end,
    OnAppearanceChanged = function() end,
}
mw.env.MapkoSkin = { GetAPI = function() return api end }
assert(mw.world:LoadFile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua", "MidnightSimpleUnitFrames", mw.core))
local Skin = mw.core.MenuSkin
Skin.BindColors(T.colors)
local group = W.ControlCard(mw.env.UIParent, "Geometry", nil, 0, 0, 360, 160, "group")
local divider = Divider(group)
local function CheckColor(expected, label)
    local r, g, b
    if divider then r, g, b = divider:GetVertexColor() end
    Check(r == expected[1] and g == expected[2] and b == expected[3], label)
end
CheckColor(rgb, "initial skin palette does not reach group divider")
rgb = { 0.72, 0.63, 0.54 }
Skin.Refresh(nil, "color", "borderSoft")
CheckColor(rgb, "live palette refresh leaves the group divider in its old color")
enabled = false
Skin.Refresh(nil, "adapter", "master")
CheckColor(native, "disabling the skin does not restore the group divider color")
assert(#failures == 0, table.concat(failures, "\n"))
print("menu_group_design_smoke: OK (" .. flavor .. "; 520/760/1100px; visible/hidden/eager; " .. checks .. " checks)")

-- Real Class Resources builders: card containment, aligned labels and narrow stacking.
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local width = tonumber(arg[3]) or 760
local mode = arg[4] or "visible"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, W = mw.M, mw.M.Widgets
local Builder = W.PageBuilder
W.PageBuilder = function(ctx) ctx.width = width; return Builder(ctx) end
if mode == "eager" then M.UnitPage.BuildSectionLazy = nil end
if mode == "hidden" then M.BuildPageEntry("classpower", true); mw:RunTimers() else mw:Select("classpower") end
local ui = assert(M.ClassPowerWorkspace.current)
local failures, checked = {}, 0
local function Check(ok, message)
    checked = checked + 1
    if not ok then failures[#failures + 1] = message end
end
local function XY(region)
    local _, _, _, x, y = region:GetPoint()
    return tonumber(x) or 0, -(tonumber(y) or 0)
end
local function ControlWidth(control)
    if control._msuf2ControlKind == "toggle" then
        return control:GetWidth() + 8 + (control._msuf2Label:GetWidth() or 0)
    end
    return control._msuf2RequestedWidth or control:GetWidth() or 22
end
for _, kind in ipairs({ "class", "power", "hp", "mana", "extras" }) do
    ui:Select(kind)
    for _, entry in ipairs(ui.entries[kind]) do entry.SetOpenImmediate(true) end
    mw:RunTimers()
end
local parents = {}
for id, section in pairs(M.cache.classpower.sections) do parents[section] = id end
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2ControlCard then parents[frame:GetParent()] = parents[frame:GetParent()] or frame._msuf2ControlCardTitle end
end
for section, id in pairs(parents) do
    local cards, controls = {}, {}
    local height = section:GetHeight()
    if not section._msuf2CollapsibleEntry then
        local _, _, _, _, y = section:GetPoint()
        height = section:GetParent():GetHeight() + (y or 0)
    end
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame:GetParent() == section and (frame._msuf2ControlCard or frame._msuf2DecorativeBackdrop) then
            cards[#cards + 1] = frame
            local x, y = XY(frame)
            Check(x >= 0 and x + frame:GetWidth() <= width, id .. ": card exceeds width")
            Check(y + frame:GetHeight() <= height, id .. ": card exceeds section")
        end
        if frame:GetParent() == section and frame._msuf2ControlKind then controls[#controls + 1] = frame end
    end
    for _, control in ipairs(controls) do
        local label = control._msuf2StableSearchLabel or control._msuf2SearchText or control._msuf2ControlKind
        local x, y = XY(control)
        local top = control._msuf2ContextLayoutY and -control._msuf2ContextLayoutY or y
        local bottom = y + (control:GetHeight() or 22)
        Check(bottom + 12 <= height, id .. ": " .. label .. " exceeds section")
        if control._msuf2Title and control._msuf2ControlKind ~= "color" then
            Check(control._msuf2Title.justifyH == "LEFT", id .. ": " .. label .. " title is not left aligned")
        end
        if #cards > 0 then
            local inside = false
            for _, card in ipairs(cards) do
                local cx, cy = XY(card)
                local controlWidth = ControlWidth(control)
                if x >= cx + 12 and x + controlWidth <= cx + card:GetWidth() - 12
                    and top >= cy + (card._msuf2ControlCard and 30 or 12) and bottom + 12 <= cy + card:GetHeight() then inside = true end
            end
            Check(inside, id .. ": " .. label .. " exceeds card padding")
        end
        for _, other in ipairs(controls) do
            if other ~= control then
                local ox, oy = XY(other)
                local otop = other._msuf2ContextLayoutY and -other._msuf2ContextLayoutY or oy
                local obottom = oy + (other:GetHeight() or 22)
                local cw, ow = ControlWidth(control), ControlWidth(other)
                Check(x + cw <= ox or ox + ow <= x or bottom + 4 <= otop or obottom + 4 <= top,
                    id .. ": overlapping rows " .. label .. " / " .. (other._msuf2SearchText or other._msuf2ControlKind))
            end
        end
    end
end
if #failures > 0 then error(table.concat(failures, "\n")) end
print("classpower_layout_smoke: OK (" .. flavor .. ", " .. width .. "px, " .. mode .. ", " .. checked .. " checks)")

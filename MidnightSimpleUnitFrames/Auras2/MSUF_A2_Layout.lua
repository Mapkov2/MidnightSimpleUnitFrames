-- MSUF_A2_Layout.lua
-- Auras2 icon grid layout. Split from MSUF_A2_Icons.lua so icon visual commit
-- and row/column positioning stay independently reviewable.
local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.Icons = (type(API.Icons) == "table") and API.Icons or {}
local Icons = API.Icons
-- Layout Engine

function Icons.LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap, configGen)
    if not container or count <= 0 then return end

    --  Layout diff gate
    -- If count and configGen match last call, positions are identical. Skip.
    -- configGen covers iconSize, spacing, perRow, growth, rowWrap (all settings).
    local gen = configGen or _G.MSUF_A2_ConfigGen or 0
    if count == container._msufA2_lastLayoutN and gen == container._msufA2_lastLayoutGen then return end
    container._msufA2_lastLayoutN = count
    container._msufA2_lastLayoutGen = gen

    iconSize = iconSize or 26
    spacing = spacing or 2
    perRow = perRow or 12
    if perRow < 1 then perRow = 1 end

    local step = iconSize + spacing
    local vertical = (growth == "UP" or growth == "DOWN")

    -- Direction multipliers + anchor
    local dx, dy = 1, -1  -- defaults: growth RIGHT, wrap DOWN
    local anchorX, anchorY = "LEFT", "BOTTOM"

    if vertical then
        -- Vertical: fill a column first (perRow icons), then wrap rightward.
        -- UP:   anchor BOTTOMLEFT, icons go upward   (dy = +1)
        -- DOWN: anchor TOPLEFT,    icons go downward  (dy = -1)
        if growth == "DOWN" then
            anchorY = "TOP"
            dy = -1
        else -- UP
            anchorY = "BOTTOM"
            dy = 1
        end
        dx = 1
        anchorX = "LEFT"
    else
        -- Horizontal: fill a row first, then wrap vertically.
        if growth == "LEFT" then
            dx = -1
            anchorX = "RIGHT"
        end
        if rowWrap == "UP" then
            dy = 1
        end
    end

    -- Precompute anchor string ONCE (not per icon)
    local anchor = anchorY .. anchorX

    local pool = container._msufIcons
    if not pool then return end

    -- PERF: Cache container-level layout params to skip per-icon checks
    local lastSize = container._msufA2_lastIconSize
    local sizeChanged = (lastSize ~= iconSize)
    if sizeChanged then container._msufA2_lastIconSize = iconSize end

    for i = 1, count do
        local icon = pool[i]
        if icon then
            local idx = i - 1
            local col, row
            if vertical then
                -- Fill column first (row within column), then wrap to next column
                row = idx % perRow
                col = (idx - row) / perRow  -- integer division
            else
                -- Fill row first (col within row), then wrap to next row
                col = idx % perRow
                row = (idx - col) / perRow  -- integer division
            end
            local x = col * step * dx
            local y = row * step * dy

            -- PERF: Skip SetPoint if position unchanged
            if icon._msufA2_lastX ~= x or icon._msufA2_lastY ~= y or icon._msufA2_lastAnchor ~= anchor then
                icon._msufA2_lastX = x
                icon._msufA2_lastY = y
                icon._msufA2_lastAnchor = anchor
                icon:ClearAllPoints()
                icon:SetPoint(anchor, container, anchor, x, y)
            end

            -- PERF: Skip SetSize if unchanged
            if sizeChanged or icon._msufA2_lastSize ~= iconSize then
                icon._msufA2_lastSize = iconSize
                icon:SetSize(iconSize, iconSize)
            end
        end
    end
end

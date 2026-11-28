-- Frozen outer heights of the unit aura workspace, captured from 75ff89d0f (before
-- page areas) with the cache smoke's open/settle walk. buff/layout's first
-- closed->open view has 14px more padding than views built open.
-- Optional contextualVisibility adds only the reviewed 2026-10-29 diagnostic card.
-- Its 132px outer card adds 154px to ordinary flow and 140px where the previous
-- style/first-view layout already retained 14px padding. With the card suppressed,
-- all original heights still match across the complete release matrix.
-- In Beta 2 Retail and Forever put both bar controls and the new appearance settings in Bars.
-- 2026-11-24: the 16 px section flow gap adds 4 px per nested card; every value above
-- includes it, and the diagnostic card now adds 158 (144 with retained padding).
-- Returns Expected(flavor, unit, contextualVisibility) -> function(lane, tool, slot) -> height.
return function(flavor, unit, contextualVisibility)
    local classic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists"
    local player = unit == "player"
    local normal = {
        layout = 416, behavior = 364, filters = classic and 326 or 464, blacklist = 828,
        style = classic and 1484 or 1738,
        bars = not classic and 912 or nil,
    }
    local custom = { setup = 734, layout = 398, behavior = 398, filters = 464, whitelist = player and 980 or 638, style = 1326 }
    local custom4 = {
        setup = player and 598 or 618, layout = 398, behavior = 398, filters = 368,
        defensives = 768, dots = 638, style = not player and not classic and 1618 or 1326,
    }
    return function(lane, tool, slot)
        local expected = (lane == "buff" or lane == "debuff") and normal[tool] or (lane == "custom4" and custom4[tool] or custom[tool])
        if lane == "buff" and tool == "layout" and slot == 1 then expected = 430 end
        if lane == "buff" and tool == "style" and not player then expected = expected + 34 end
        if lane == "debuff" and tool == "blacklist" and player then expected = 654 end
        local diagnostic = player and lane == "custom4" or not player and (lane == "buff" or lane == "debuff")
        if contextualVisibility and diagnostic then
            local retainedPadding = tool == "style" or lane == "buff" and tool == "layout" and slot == 1
            expected = expected + (retainedPadding and 144 or 158)
        end
        return expected
    end
end

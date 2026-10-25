-- Frozen outer heights of the unit aura workspace, captured from 75ff89d0f (before
-- page areas) with the cache smoke's open/settle walk. buff/layout's first
-- closed->open view has 14px more padding than views built open.
-- Returns Expected(flavor, unit) -> function(lane, tool, slot) -> height.
return function(flavor, unit)
    local classic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists"
    local player = unit == "player"
    local normal = {
        layout = 408, behavior = 356, filters = classic and 318 or 456, blacklist = 820,
        style = classic and 1464 or 1714,
    }
    local custom = { setup = 722, layout = 390, behavior = 390, filters = 456, whitelist = player and 968 or 630, style = 1302 }
    local custom4 = {
        setup = player and 590 or 610, layout = 390, behavior = 390, filters = 360,
        defensives = 760, dots = 630, style = not player and not classic and 1590 or 1302,
    }
    return function(lane, tool, slot)
        local expected = (lane == "buff" or lane == "debuff") and normal[tool] or (lane == "custom4" and custom4[tool] or custom[tool])
        if lane == "buff" and tool == "layout" and slot == 1 then expected = 422 end
        if lane == "buff" and tool == "style" and not player then expected = expected + 34 end
        if lane == "debuff" and tool == "blacklist" and player then expected = 646 end
        return expected
    end
end

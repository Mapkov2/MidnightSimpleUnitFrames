local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "opt_castbar" })
local core = mw.core
local C, M, g = core.Castbars, mw.M, mw.env.MSUF_DB.general

local function CheckAnchor(frame, expected, context)
    local point, parent, relative, x = frame.castText:GetPoint(1)
    assert(point == "CENTER" and relative == "CENTER" and parent == frame.statusBar, context .. " lost its center anchor")
    assert(frame.castText:GetJustifyH() == "CENTER", context .. " lost its center justification")
    assert(x == expected, ("%s expected anchor X=%g, got %s"):format(context, expected, tostring(x)))
end

local function Frame(unit, width)
    local frame = C.Frames.CreateCastbarPreviewFrame(unit, nil, { parent = mw.env.UIParent, width = width, height = 30 })
    frame._msufIsPreview = false
    frame.castText:SetText("Flame Buffet")
    frame.timeText:SetText("0.8")
    return frame
end

for _, unit in ipairs({ "player", "target" }) do
    local capitalized = unit:gsub("^%l", string.upper)
    local prefix, showTime = "castbar" .. capitalized, "show" .. capitalized .. "CastTime"
    g[prefix .. "SpellNamePosition"], g[prefix .. "ShowSpellName"], g[prefix .. "ShowIcon"] = "CENTER", true, false
    g[prefix .. "TimeFontSize"], g[prefix .. "TimeFormat"] = 12, "CURRENT"
    g[prefix .. "SpellNameMaxWidth"] = 1000
    local frame = Frame(unit, 350)

    local function Paint(bar, timePosition, mode, offset, shown, timeOffset)
        g[showTime], g[prefix .. "TimePosition"] = shown ~= false, timePosition
        g[prefix .. "SpellNameTruncate"], g[prefix .. "TextOffsetX"] = mode, offset
        g[prefix .. "TimeOffsetX"] = timeOffset or -2
        local namePosition = g[prefix .. "SpellNamePosition"]
        C.Config.Compile("style")
        C.Visuals.ApplyCastbarDetailLayout(bar, unit, g)
        assert(g[prefix .. "TextOffsetX"] == offset and g[prefix .. "SpellNamePosition"] == namePosition,
            unit .. " layout rewrote profile settings")
        return bar.castText:GetWidth(), bar.statusBar:GetWidth()
    end

    -- At 12pt, CURRENT reserves 46 units on the left for the timer in this fixture.
    local textWidth, barWidth = Paint(frame, "LEFT", "AUTO", 0)
    CheckAnchor(frame, 0, unit .. " with left timer")
    assert(textWidth > 0 and textWidth <= barWidth - 92, unit .. " auto fit overlaps the left timer")

    textWidth, barWidth = Paint(frame, "RIGHT", "CLIP", 5)
    CheckAnchor(frame, 5, unit .. " with right timer and saved offset")
    assert(textWidth > 0 and textWidth <= barWidth - 106, unit .. " manual fit overlaps the right timer")

    local narrow = Frame(unit, 60)
    textWidth = Paint(narrow, "LEFT", "AUTO", 0)
    CheckAnchor(narrow, 0, unit .. " with narrow bar")
    assert(textWidth == 1, unit .. " narrow bar must keep a positive font string width")

    textWidth, barWidth = Paint(frame, "CENTER", "AUTO", 0, true, 0)
    -- With equal space left and right, the existing layout places the name in the left interval.
    local leftRoom = (barWidth - 46) / 2
    CheckAnchor(frame, (leftRoom - barWidth) / 2, unit .. " with centered timer")
    assert(textWidth > 1 and textWidth <= leftRoom, unit .. " centered timer left no usable spell-name width")

    textWidth = Paint(frame, "LEFT", "NONE", -7)
    CheckAnchor(frame, -7, unit .. " without width limit")
    assert(textWidth >= 1000, unit .. " no-width-limit mode clipped the name")

    textWidth, barWidth = Paint(frame, "LEFT", "AUTO", 0, false)
    CheckAnchor(frame, 0, unit .. " with hidden timer")
    assert(textWidth > barWidth - 92, unit .. " hidden timer still consumes spell-name width")

    g[prefix .. "SpellNamePosition"] = "LEFT"
    Paint(frame, "LEFT", "AUTO", -12, false)
    local point, _, _, x = frame.castText:GetPoint(1)
    assert(point == "LEFT" and x == -10, unit .. " hidden timer clamped the left name offset")
    Paint(frame, "RIGHT", "AUTO", -12)
    point, _, _, x = frame.castText:GetPoint(1)
    assert(point == "LEFT" and x == -10, unit .. " opposite timer clamped the left name offset")

    g[prefix .. "SpellNamePosition"] = "RIGHT"
    textWidth = Paint(frame, "ABOVE", "CLIP", 12)
    point, _, _, x = frame.castText:GetPoint(1)
    assert(point == "RIGHT" and x == 12, unit .. " timer above clamped the right name offset")
    assert(textWidth == 1000, unit .. " timer above clamped the explicit name width")
    Paint(frame, "LEFT", "AUTO", 12)
    point, _, _, x = frame.castText:GetPoint(1)
    assert(point == "RIGHT" and x == 12, unit .. " opposite timer clamped the right name offset")

    g[prefix .. "SpellNamePosition"] = "CENTER"
    Paint(frame, "LEFT", "AUTO", 0)
    assert(mw:Select("opt_castbar") ~= false)
    M.SetCastbarPreviewUnit(unit)
    M.SetCastbarPreviewType("normal")
    local globalPreview = assert(M._msuf2CastbarPreview)
    globalPreview:Refresh()
    CheckAnchor(assert(globalPreview.frame), 0, unit .. " global Cast Bars preview")

    assert(mw:Select("uf_" .. unit) ~= false)
    M.Refresh(M.cache["uf_" .. unit].ctx)
    mw:RunTimers()
    local unitPreview
    for _, box in ipairs(mw.world.widgets.frames) do
        if box.key == unit and box._castScene and not box._castScene.retired then
            unitPreview = box._castScene:Frame()
            assert(box._castScene.opts.matchParent == core.Client.IsRetail, "cast preview ignored its layout slot")
            local slot = box.mock.cast
            local width, height = slot:GetWidth(), slot:GetHeight()
            local pixel = core.Require("MSUF_GetPhysicalPixelSize", "castbar layout test")(slot)
            assert(math.abs(width / pixel - math.floor(width / pixel + 0.5)) < 1e-6, "cast slot width is off grid")
            assert(math.abs(height / pixel - math.floor(height / pixel + 0.5)) < 1e-6, "cast slot height is off grid")
        end
    end
    CheckAnchor(assert(unitPreview, unit .. " preview missing"), 0, unit .. " unit preview")
    assert(g[prefix .. "TextOffsetX"] == 0 and g[prefix .. "SpellNamePosition"] == "CENTER",
        unit .. " preview rewrote profile settings")
end

print("castbar_spell_text_layout_smoke " .. flavor .. ": passed (player, target, live layout and both previews)")

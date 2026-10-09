-- Selected RGB must reach visible Frame Outline regions in every style and shape.
-- Uses offline client regions; actual pixels still need a WoW client.
local root, flavor = assert(arg[1]), assert(arg[2])
local function Run(route)
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true })
local M, env, UF = mw.M, mw.env, mw.core.UF
-- The canonical Colors transaction also repaints unrelated gameplay features;
-- isolate those API-heavy consumers from the owned Frame Outline color sink.
mw.core.MSUF_ApplyGameplayVisuals = function() end
local outlinePicker
local Attach = M.Widgets.AttachContextColorShortcut
M.Widgets.AttachContextColorShortcut = function(section, options)
    if options.title == "Frame Outline Color" then outlinePicker = options.getTargets()[1] end
    return Attach(section, options)
end
mw:Select("opt_bars")
M.Widgets.EnsureSectionContent(assert(M.cache.opt_bars.sections.bars_outline))
mw:RunTimers()
assert(outlinePicker, "real Frame Outline Color target did not build")
if route == "colors" then
    outlinePicker = assert(M.ResolveContextColorReferences({ "bar.outline" })[1], "canonical color target absent")
end
local db, border = M.EnsureDB(), UF.elements.Borders
local frame
local function NewFrame()
    frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(180, 40)
    frame.MSUFUnitKey, frame.unit = "target", "target"
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.hpBar:SetSize(180, 40)
    frame.targetPowerBar = env.CreateFrame("StatusBar", nil, frame)
    frame.targetPowerBar:SetSize(180, 8)
    UF.frames.target, UF.frameList[1] = frame, frame
end
local function Paint(spec)
    UF.SetFrameSpec(frame, spec)
    border.Apply(frame, spec)
    border.Update(frame, spec, "MSUF_FORCE_UPDATE")
end
UF.ApplyElementsToFrame = function(f, names, spec)
    assert(f == frame, "fixture received an unexpected frame")
    UF.SetFrameSpec(f, spec)
    for _, name in ipairs(names) do if name == "Borders" then Paint(spec) end end
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function RGB(value, expected)
    return value and Near(value[1], expected[1]) and Near(value[2], expected[2]) and Near(value[3], expected[3])
end
local function SetRGB(entry, color)
    entry.barOutlineColorMode = nil
    entry.barOutlineColorR, entry.barOutlineColorG, entry.barOutlineColorB = unpack(color)
    entry.barOutlineColorA = 1
end
local function Sinks()
    local regions = {}
    if frame._msufRUFModernBorderSuppressed then
        local pool = frame._msufRoundedBorderStyledRings
        for key, region in pairs(pool or {}) do
            if type(key) == "number" and region:IsShown() then regions[#regions + 1] = region end
        end
        for _, region in ipairs(pool and pool._msufArtShown or {}) do
            if region:IsShown() then regions[#regions + 1] = region end
        end
        local edge = frame._msufRoundedBorderEdge
        if edge and edge:IsShown() then regions[#regions + 1] = edge end
    else
        for _, pieces in ipairs({ frame.MSUFBorderEdges or {}, frame.MSUFBorderTexturePieces or {} }) do
            for _, region in pairs(pieces) do
                if type(region) == "table" and type(region.IsShown) == "function" and region:IsShown() then
                    regions[#regions + 1] = region
                end
            end
        end
    end
    if #regions == 0 then
        print("DIAGNOSTIC source=" .. tostring(frame._msufBorderVisualSource) .. " suppressed=" .. tostring(frame._msufRUFModernBorderSuppressed)
            .. " mode=" .. tostring(frame._msufBorderRuntimeTextureMode) .. " path=" .. tostring(frame._msufBorderRuntimeTexture)
            .. " shown=" .. tostring(frame._msufBorderShown))
        for key, region in pairs(frame.MSUFBorderEdges or {}) do
            print("EDGE " .. key .. " shown=" .. tostring(region:IsShown()) .. " rgb=" .. table.concat({region:GetVertexColor()}, ":"))
        end
    end
    assert(#regions > 0, "no visible outline region")
    return regions
end
db.bars.showBarBorder, db.bars.barOutlineThickness = true, 2
db.target.barOutlineThickness = 2
local colors = {
    { name = "red", 0.9, 0.1, 0.2 }, { name = "green", 0.1, 0.9, 0.3 },
    { name = "blue", 0.1, 0.2, 0.9 }, { name = "black", 0, 0, 0 }, { name = "white", 1, 1, 1 },
}
local styles = { { name = "solid", key = "" }, { name = "Soft Glow", key = "BORDER:GLOW" },
    { name = "Shadow", key = "BORDER:SHADOW" }, { name = "Blizzard Tooltip", key = "BORDER:BLIZZARD" },
    { name = "Blizzard Dialog", key = "BORDER:DIALOG" }, { name = "Blizzard Achievement", key = "BORDER:ACHIEVEMENT" },
    { name = "Blizzard texture", key = "Blizzard" } }
local white = { 1, 1, 1 }
local cases, regionsChecked, previewChecks = 0, 0, 0
for _, shape in ipairs({ "square", "rounded", "slanted" }) do
    db.target.frameBarShape = shape:upper()
    db.bars.roundedFramesEnabled, db.bars.roundedUnitFrames = shape == "rounded", true
    db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames = shape == "slanted", true
    for _, scope in ipairs(route == "colors" and { "shared" } or { "shared", "target" }) do
        db.general.hpPowerTextSelectedKey = scope
        for _, style in ipairs(styles) do
            NewFrame()
            local mock = env.CreateFrame("Frame", nil, env.UIParent)
            mock:SetSize(180, 40)
            db.bars.barOutlineTexture, db.target.barOutlineTexture = style.key, style.key
            for _, color in ipairs(colors) do
                db.target.hlOverride = scope == "target"
                local entry = scope == "shared" and db.general or db.target
                SetRGB(entry, color.name == "black" and white or { 0.02, 0.03, 0.04 })
                env.MSUF_ApplyRoundedUnitframes()
                Paint(UF.Config.RefreshUnit("target"))
                local previous = {}
                for _, region in ipairs(Sinks()) do previous[region] = true end
                local oldPool = frame._msufRoundedBorderStyledRings
                outlinePicker.setRGB(unpack(color))
                mw:RunTimers()
                assert(RGB({outlinePicker.getRGB()}, color), "picker did not read requested RGB")
                assert(RGB({entry.barOutlineColorR, entry.barOutlineColorG, entry.barOutlineColorB}, color), "stored RGB wrong")
                local compiled = frame.MSUFSpec.border
                assert(RGB({compiled.r, compiled.g, compiled.b}, color), "compiled RGB wrong")
                local expected = color
                local sinks = Sinks()
                assert(frame._msufRoundedBorderStyledRings == oldPool, "a color change replaced the pool")
                for _, region in ipairs(sinks) do
                    assert(previous[region], "a color change replaced a visible region")
                    assert(RGB({region:GetVertexColor()}, expected), "unexpected final region RGB for " .. shape .. "/" .. scope .. "/" .. style.name)
                    regionsChecked = regionsChecked + 1
                end
                if shape ~= "square" and compiled.textureMode then
                    local opts = {
                        styledKey = "_outlineColorProof",
                        edgeTexture = assert(frame._msufRoundedBorderStyledRings, "shaped runtime did not activate")._msufEdgePath,
                        outlineStyle = function() return compiled end,
                        baseEdgeColor = function() return compiled.r, compiled.g, compiled.b, compiled.a end,
                    }
                    -- The real preview helper calls the shared painter without
                    -- the former tint flag. Cold and reused regions must color.
                    assert(M.PreviewHelpers.ApplyRoundedEdgeStack(mock, 2, opts), "preview did not draw outline")
                    local count = 0
                    mw.core.RoundedSurface.ForEachStyledEdgeRing(mock, opts.styledKey, function(region)
                        assert(RGB({region:GetVertexColor()}, color), "preview ignored selected RGB")
                        count = count + 1
                    end)
                    assert(count > 0, "preview produced no styled regions")
                    previewChecks = previewChecks + count
                end
                cases = cases + 1

            end
        end
    end
end
-- Choosing the saved scoped RGB also enables Override. That state-only
-- change still needs a paint, even when none of its RGB fields changes.
if route == "bars" then
    db.general.hpPowerTextSelectedKey = "target"
    db.target.frameBarShape = "SQUARE"
    db.bars.roundedFramesEnabled, db.bars.slantedBarsEnabled = false, false
    db.bars.barOutlineTexture, db.target.barOutlineTexture = "Blizzard", "Blizzard"
    SetRGB(db.general, { 0.1, 0.2, 0.3 })
    local color = { 0.9, 0.4, 0.1 }
    SetRGB(db.target, color)
    db.target.hlOverride = false
    NewFrame()
    env.MSUF_ApplyRoundedUnitframes()
    Paint(UF.Config.RefreshUnit("target"))
    outlinePicker.setRGB(unpack(color))
    mw:RunTimers()
    assert(db.target.hlOverride == true, "color edit did not enable the scope Override")
    for _, region in ipairs(Sinks()) do
        assert(RGB({region:GetVertexColor()}, color), "enabling Override with saved RGB did not repaint")
    end
    local GF = mw.core.GF
    local Refresh, paints = GF.RefreshVisuals, 0
    GF.RefreshVisuals = function(...)
        paints = paints + 1
        return Refresh(...)
    end
    for _, active in ipairs({ "gf_raid", "gf_mythicraid" }) do
        db.general.hpPowerTextSelectedKey = "gf_raid"
        for _, key in ipairs({ "gf_raid", "gf_mythicraid" }) do
            db[key] = db[key] or {}
            SetRGB(db[key], color)
            db[key].hlOverride = key == active
        end
        local before = paints
        outlinePicker.setRGB(unpack(color))
        mw:RunTimers()
        assert(db.gf_raid.hlOverride and db.gf_mythicraid.hlOverride, "Raid did not enable both Overrides")
        assert(paints > before, "asymmetric Raid Overrides with saved RGB did not repaint")
    end
end
print("bars_outline_color_smoke: OK (" .. flavor .. "; " .. route .. "; " .. cases .. " cases; " .. regionsChecked .. " regions; " .. previewChecks .. " preview regions)")
end
Run("bars")
Run("colors")

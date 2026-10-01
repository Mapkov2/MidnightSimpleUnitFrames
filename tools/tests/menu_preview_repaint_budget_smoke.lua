-- menu_preview_repaint_budget_smoke.lua <repoRoot> <flavor> [report]
--
-- Repaint budget of the options menu previews (unit and group), measured on
-- the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, with the harness's allocating widget setters
-- replaced by non-allocating ones so the numbers are the addon's own:
--
--   * after warm-up a repaint and an Animate tick create no region (frame,
--     texture, font string, mask);
--   * a repaint passes the same backdrop table again (Blizzard's SetBackdrop
--     skips a table it already holds, so a fresh table re-applies the whole
--     nine-slice), and rebinds no script (aura sample drag proxies);
--   * Lua garbage per repaint and per Animate tick stays under a ceiling;
--   * an Animate tick never runs the full repaint: it updates fills, texts,
--     swipes and timers of the last scene;
--   * an unchanged Auras3 profile is never normalized on a repaint (the menu
--     reads its model dozens of times per repaint);
--   * a preview key the client has no compiled spec for never recompiles the
--     unit config on a repaint.
--
-- Pass "report" as a third argument to print the measurements.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
local report = arg[3] == "report"
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_preview_repaint_budget_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu_preview_repaint_budget_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
-- Blizzard's boss frame count, read by the core at load (the harness has none).
world.env.MAX_BOSS_FRAMES = 5
-- Working curves in C_CurveUtil's shape (every client ships it): health
-- gradients evaluate to real colours, so the tick/refresh parity below
-- compares colour values instead of harness placeholders. Linear by default,
-- step for any other curve type.
do
    local base = world.env.C_CurveUtil
    local function NewCurve()
        local xs, ys = {}, {}
        local curve = { curveType = 0 }
        function curve:SetType(curveType) self.curveType = curveType end
        function curve:GetType() return self.curveType end
        function curve:ClearPoints() for i = #xs, 1, -1 do xs[i], ys[i] = nil, nil end end
        function curve:AddPoint(x, y)
            local i = #xs + 1
            while i > 1 and xs[i - 1] > x do xs[i], ys[i] = xs[i - 1], ys[i - 1]; i = i - 1 end
            xs[i], ys[i] = x, y
        end
        local function Span(x)
            local n = #xs
            if n == 0 then return nil end
            if x <= xs[1] then return ys[1], ys[1], 0 end
            if x >= xs[n] then return ys[n], ys[n], 0 end
            for i = 2, n do
                if x <= xs[i] then
                    if curve.curveType ~= 0 then return ys[i - 1], ys[i - 1], 0 end
                    return ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1])
                end
            end
        end
        local function Lerp(a, b, t) return a + (b - a) * t end
        function curve:EvaluateUnpacked(x)
            local a, b, t = Span(tonumber(x) or 0)
            if not a then return 0, 0, 0, 0 end
            return Lerp(a.r, b.r, t), Lerp(a.g, b.g, t), Lerp(a.b, b.b, t), Lerp(a.a or 1, b.a or 1, t)
        end
        function curve:Evaluate(x)
            local a, b, t = Span(tonumber(x) or 0)
            if not a then return 0 end
            if type(a) == "number" then return Lerp(a, b, t) end
            return world.env.CreateColor(self:EvaluateUnpacked(x))
        end
        return curve
    end
    world.env.C_CurveUtil = setmetatable({ CreateCurve = NewCurve, CreateColorCurve = NewCurve }, { __index = base })
end
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local env, MSUF = world.env, world.core
local widgets = world.widgets
local methods = widgets.Methods
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters",
    "EnableKeyboard", "SetNumeric", "SetTextInsets", "ClearFocus", "SetCursorPosition", "HighlightText",
    "SetPropagateKeyboardInput", "SetPropagateMouseWheel", "SetValueStep", "SetObeyStepOnDrag" }) do
    if not methods[key] then methods[key] = function() end end
end
methods.GetFont = methods.GetFont or function() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
-- Atlas availability is a static client fact: a repaint must not probe it.
-- The animated rest flipbook is the live Status element's own painter
-- (MSUF.UFRestingFlipbook, UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua),
-- shared 1:1 with the preview; its probe belongs to that element and is not
-- counted here.
local atlasProbes = 0
local SHARED_ELEMENT_ATLASES = { ["UI-HUD-UnitFrame-Player-Rest-Flipbook"] = true }
env.C_Texture = { GetAtlasInfo = function(atlas)
    if not SHARED_ELEMENT_ATLASES[atlas] then atlasProbes = atlasProbes + 1 end
    return nil
end }

-- Non-allocating replacements for the harness setters that allocate per call.
local function Reuse(self, field, a, b, c, d)
    local t = rawget(self, field)
    if type(t) ~= "table" then t = {}; rawset(self, field, t) end
    t[1], t[2], t[3], t[4] = a, b, c, d
    return t
end
methods.SetVertexColor = function(self, r, g, b, a) Reuse(self, "vertexColor", r, g, b, a) end
methods.SetColorTexture = function(self, r, g, b, a)
    self.texture = nil
    Reuse(self, "colorTexture", r, g, b, a)
    Reuse(self, "vertexColor", r, g, b, a)
end
methods.SetTexCoord = function(self, a, b, c, d) Reuse(self, "texCoord", a, b, c, d) end
methods.SetBackdropColor = function(self, r, g, b, a) Reuse(self, "backdropColor", r, g, b, a) end
methods.SetBackdropBorderColor = function(self, r, g, b, a) Reuse(self, "backdropBorderColor", r, g, b, a) end
methods.SetStatusBarColor = function(self, r, g, b, a) Reuse(self, "statusBarColor", r, g, b, a) end
methods.SetTextColor = function(self, r, g, b, a) Reuse(self, "textColor", r, g, b, a) end
methods.SetShadowColor = function(self, r, g, b, a) Reuse(self, "shadowColor", r, g, b, a) end
-- Proportional glyph widths: a value text whose digits change changes width,
-- so a text handle that does not follow its text shows.
methods.GetStringWidth = function(self)
    local fixed = rawget(self, "stringWidth")
    if fixed then return fixed end
    local text, width = tostring(rawget(self, "text") or ""), 0
    for i = 1, #text do width = width + 4 + (text:byte(i) % 5) end
    return width
end
methods.SetGradient = function(self, orientation, from, to)
    local gradient = rawget(self, "gradient")
    if type(gradient) ~= "table" then gradient = {}; rawset(self, "gradient", gradient) end
    gradient.orientation, gradient.from, gradient.to = orientation, from, to
end
methods.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "string" or type(relativeTo) == "number" then
        relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
    end
    local pool = rawget(self, "_pp")
    if not pool then pool = {}; rawset(self, "_pp", pool) end
    local n = #self.points + 1
    local e = pool[n]
    if not e then e = {}; pool[n] = e end
    e.point, e.relativeTo, e.relativePoint, e.x, e.y = point, relativeTo, relativePoint or point, x or 0, y or 0
    self.points[n] = e
end

-- Counters ------------------------------------------------------------------
local counters = { regions = 0, backdrops = 0, scripts = 0, configRefreshes = 0, normalizes = 0 }
local function AtlasProbes() return atlasProbes end
local originalRegion = widgets.Region
widgets.Region = function(self, objectType, parent)
    counters.regions = counters.regions + 1
    return originalRegion(self, objectType, parent)
end
-- Blizzard's SetBackdrop returns early when it already holds this table; a
-- different table re-applies the nine-slice. Count the re-applies.
local originalSetBackdrop = methods.SetBackdrop
methods.SetBackdrop = function(self, info, ...)
    if info ~= nil and rawget(self, "_msufSmokeBackdrop") ~= info then counters.backdrops = counters.backdrops + 1 end
    rawset(self, "_msufSmokeBackdrop", info)
    if originalSetBackdrop then return originalSetBackdrop(self, info, ...) end
end
local originalSetScript = methods.SetScript
methods.SetScript = function(self, name, fn, ...)
    if name ~= "OnUpdate" then counters.scripts = counters.scripts + 1 end
    return originalSetScript(self, name, fn, ...)
end

local function Measure(fn, n)
    fn(); fn(); fn()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local regions, backdrops, scripts = counters.regions, counters.backdrops, counters.scripts
    local configRefreshes, probes, normalizes = counters.configRefreshes, AtlasProbes(), counters.normalizes
    for _ = 1, n do fn() end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return {
        kb = (after - before) / n,
        regions = (counters.regions - regions) / n,
        backdrops = (counters.backdrops - backdrops) / n,
        scripts = (counters.scripts - scripts) / n,
        configRefreshes = (counters.configRefreshes - configRefreshes) / n,
        atlasProbes = (AtlasProbes() - probes) / n,
        normalizes = (counters.normalizes - normalizes) / n,
    }
end
local measured = {}
local function Record(label, result)
    measured[#measured + 1] = { label, result }
    if report then
        print(string.format("%-8s %-34s %8.2f KB  regions=%.2f backdrops=%.2f scripts=%.2f config=%.2f atlas=%.2f normalize=%.2f", flavor, label,
            result.kb, result.regions, result.backdrops, result.scripts, result.configRefreshes, result.atlasProbes, result.normalizes))
    end
    return result
end
local function CheckSteady(label, result)
    Check(result.regions == 0, label .. " creates " .. result.regions .. " regions per repaint after warm-up")
    Check(result.backdrops == 0, label .. " re-applies " .. result.backdrops .. " backdrops per repaint (a new table each time)")
    Check(result.scripts == 0, label .. " rebinds " .. result.scripts .. " scripts per repaint")
    Check(result.configRefreshes == 0, label .. " recompiles the unit config " .. result.configRefreshes .. " times per repaint")
    Check(result.atlasProbes == 0, label .. " probes " .. result.atlasProbes .. " atlases per repaint")
    Check(result.normalizes == 0, label .. " normalizes the Auras3 profile " .. result.normalizes .. " times per repaint")
end
-- A repaint stays near 20-27 KB on every client (it was 56-411 KB before the
-- preview repaint pass); the ceiling keeps headroom for the Lua strings a
-- repaint formats.
local REPAINT_KB_CEILING = 36
local function CheckRepaint(label, result)
    CheckSteady(label, result)
    Check(result.kb < REPAINT_KB_CEILING, string.format("%s costs %.2f KB per repaint (ceiling %d KB)", label, result.kb, REPAINT_KB_CEILING))
end

env.MSUF_EnsureDB(true)
local M = MSUF.MSUF2
-- A key without a compiled spec (a unit the client has no frames for) must
-- not recompile the unit config on every repaint.
do
    local Config = MSUF.UF and MSUF.UF.Config
    Check(type(Config) == "table" and type(Config.Refresh) == "function", "no unit config")
    local refresh = Config.Refresh
    Config.Refresh = function(...)
        counters.configRefreshes = counters.configRefreshes + 1
        return refresh(...)
    end
    -- The menu reads the aura model many times per repaint; the profile it
    -- normalized last is stamped, so an unchanged profile never normalizes.
    local A3 = MSUF.MSUF_Auras3
    Check(type(A3) == "table" and type(A3.NormalizeProfileDB) == "function", "no Auras3 profile adapter")
    local normalize = A3.NormalizeProfileDB
    A3.NormalizeProfileDB = function(...)
        counters.normalizes = counters.normalizes + 1
        return normalize(...)
    end
end

-- Unit preview ----------------------------------------------------------------
local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
local selected = "player"
panel._msufGetCurrentKey = function() return selected end
local box = Preview._BuildPreview(parent, panel, 900, 400)
box:Show(); box.canvas:SetSize(400, 200)
for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss", "arena" }) do
    selected = key
    local result = Record("unit " .. key .. " repaint", Measure(function() Preview.Refresh(box, "MENU_PREVIEW_BUDGET") end, 20))
    CheckRepaint("the unit " .. key .. " preview", result)
end
-- Both backdrop paths that run on every repaint: a true-outline frame border
-- (an edgeFile border style) and the detached player power bar.
do
    local bars, player = env.MSUF_DB.bars, env.MSUF_DB.player
    local savedOutline, savedDetached = bars.barOutlineTexture, player.powerBarDetached
    local savedShape, savedCorner, savedMode = player.portraitShape, player.portraitBlizzardCorner, player.portraitMode
    bars.barOutlineTexture, player.powerBarDetached = "BORDER:BLIZZARD", true
    player.portraitShape, player.portraitBlizzardCorner, player.portraitMode = "BLIZZARD", true, "LEFT"
    MSUF.UF.Config.Refresh()
    selected = "player"
    -- Every status indicator at once (the Status page's "all" view), with the
    -- leader, combat and level art that probes its atlas.
    local savedStatusMode = Preview.statusPreviewMode
    Preview.statusPreviewMode = "all"
    local result = Record("unit player styled repaint", Measure(function() Preview.Refresh(box, "MENU_PREVIEW_BUDGET") end, 20))
    Preview.statusPreviewMode = savedStatusMode
    Check(box.mock.detachedPower:IsShown(), "harness: the styled player preview shows no detached power bar")
    Check(box.mock._msufPreviewFrameBorder and box.mock._msufPreviewFrameBorder._msufSmokeBackdrop
        and box.mock._msufPreviewFrameBorder._msufSmokeBackdrop.edgeFile ~= nil,
        "harness: the styled player preview draws no true-outline frame border")
    CheckRepaint("the styled unit player preview", result)
    bars.barOutlineTexture, player.powerBarDetached = savedOutline, savedDetached
    player.portraitShape, player.portraitBlizzardCorner, player.portraitMode = savedShape, savedCorner, savedMode
    MSUF.UF.Config.Refresh()
end

-- Animate ticks ---------------------------------------------------------------
-- Blizzard's ColorMixin refills in place (SetRGBA, on every client); the
-- harness colour has no setter, so it gets the client's.
do
    local createColor = env.CreateColor
    local function SetRGBA(self, r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    env.CreateColor = function(r, g, b, a)
        local color = createColor(r, g, b, a)
        color.SetRGBA = SetRGBA
        return color
    end
end
local fullRefreshes = 0
do
    local refresh = Preview.Refresh
    Preview.Refresh = function(...)
        fullRefreshes = fullRefreshes + 1
        return refresh(...)
    end
end
-- Everything a tick or a refresh can leave on the preview's regions, in tree
-- order, so a tick and a full refresh at the same clock compare 1:1.
local SNAP_SCALARS = { "text", "value", "width", "height", "shown", "alpha", "texture", "atlas", "minimum", "maximum",
    "reverseFill", "orientation", "desaturated", "fontPath", "fontSize", "fontFlags", "frameLevel", "drawLayer",
    "drawSublevel", "justifyH", "justifyV", "blendMode" }
local SNAP_TUPLES = { "vertexColor", "color", "statusBarColor", "textColor", "texCoord", "colorTexture",
    "backdropColor", "backdropBorderColor", "shadowColor" }
local function SnapValue(value)
    if type(value) == "number" then return string.format("%.6f", value) end
    return tostring(value)
end
local function Snapshot(rootRegion)
    local ids, order = {}, {}
    local function Index(region)
        if type(region) ~= "table" or ids[region] then return end
        order[#order + 1] = region
        ids[region] = #order
        for _, child in ipairs(rawget(region, "children") or {}) do Index(child) end
        for _, child in ipairs(rawget(region, "regions") or {}) do Index(child) end
        Index(rawget(region, "statusBarTexture"))
    end
    Index(rootRegion)
    local lines = {}
    for index = 1, #order do
        local region, parts = order[index], {}
        for _, field in ipairs(SNAP_SCALARS) do
            local value = rawget(region, field)
            if value ~= nil then parts[#parts + 1] = field .. "=" .. SnapValue(value) end
        end
        for _, field in ipairs(SNAP_TUPLES) do
            local value = rawget(region, field)
            if type(value) == "table" then
                parts[#parts + 1] = field .. "=" .. SnapValue(value[1]) .. "," .. SnapValue(value[2]) .. ","
                    .. SnapValue(value[3]) .. "," .. SnapValue(value[4])
            end
        end
        local gradient = rawget(region, "gradient")
        if type(gradient) == "table" then
            local from, to = gradient.from or {}, gradient.to or {}
            parts[#parts + 1] = "gradient=" .. tostring(gradient.orientation) .. ":" .. SnapValue(from.r) .. "," .. SnapValue(from.g)
                .. "," .. SnapValue(from.b) .. "," .. SnapValue(from.a) .. ":" .. SnapValue(to.r) .. "," .. SnapValue(to.g)
                .. "," .. SnapValue(to.b) .. "," .. SnapValue(to.a)
        end
        local allPoints = rawget(region, "allPoints")
        if allPoints ~= nil then parts[#parts + 1] = "all=" .. tostring(ids[allPoints] or allPoints == true or "?") end
        local points = rawget(region, "points")
        for p = 1, type(points) == "table" and #points or 0 do
            local e = points[p]
            parts[#parts + 1] = "pt" .. p .. "=" .. tostring(e.point) .. ":" .. tostring(ids[e.relativeTo] or (e.relativeTo == nil and "nil" or "?"))
                .. ":" .. tostring(e.relativePoint) .. ":" .. SnapValue(e.x) .. ":" .. SnapValue(e.y)
        end
        lines[index] = table.concat(parts, " ")
    end
    return lines, order
end
local function CheckSameScene(label, light, full, order)
    local diffs = {}
    for index = 1, math.max(#light, #full) do
        if light[index] ~= full[index] and #diffs < 6 then
            local region = order[index]
            diffs[#diffs + 1] = string.format("  region %d (%s %s):\n    tick: %s\n    full: %s", index,
                tostring(region and rawget(region, "objectType")), tostring(region and (rawget(region, "frameName")
                    or rawget(region, "_label") or rawget(region, "key"))),
                tostring(light[index]), tostring(full[index]))
        end
    end
    Check(#diffs == 0, label .. ": an Animate tick leaves the preview unlike a full refresh at the same clock:\n" .. table.concat(diffs, "\n"))
end
local function StartAnimation(owner, label)
    local action = owner.animateCombatButton and owner.animateCombatButton._msuf2CommandAction
    Check(action and action.set(true) == true, label .. ": the Animate toggle does not start the animation")
    local onUpdate = owner:GetScript("OnUpdate")
    Check(type(onUpdate) == "function", label .. ": Animate installs no OnUpdate driver")
    return onUpdate, action
end
-- A tick costs a fraction of a repaint; the ceilings hold with headroom on
-- every client (Lua strings for the changed value texts and timers are most
-- of it).
local TICK_KB_CEILING = 0.25
local function CheckTick(label, result)
    CheckSteady(label, result)
    Check(result.kb < TICK_KB_CEILING, string.format("%s costs %.2f KB per Animate tick (ceiling %.2f KB)", label, result.kb, TICK_KB_CEILING))
end
-- Runs the real driver over a few seconds of the clock (cast wrap, aura
-- timers, the DoT's Pandemic window). The light tick must paint exactly what
-- a full refresh paints at the same clock; `refreshes` names the frames that
-- may hand over to a full refresh, nil for none.
local function AnimateUnit(key, label, refreshes)
    selected = key
    Preview.Refresh(box, "MENU_PREVIEW_BUDGET")
    local onUpdate, action = StartAnimation(box, label)
    onUpdate(box, 0.06)
    if not refreshes then
        local before = fullRefreshes
        local result = Record(label .. " animate tick", Measure(function() onUpdate(box, 0.06) end, 40))
        Check(fullRefreshes == before, label .. ": an Animate tick runs the full repaint (" .. (fullRefreshes - before) .. " in 43 ticks)")
        CheckTick("the " .. label .. " preview", result)
    end
    local handedOver = 0
    for _ = 1, 4 do
        for _ = 1, 9 do
            local before = fullRefreshes
            local expected = refreshes and refreshes(box) or false
            onUpdate(box, 0.06)
            local ran = fullRefreshes - before
            Check(ran == (expected and 1 or 0), string.format("%s at %.2fs: an Animate tick ran %d full repaints (%s expected)",
                label, box._animationElapsed, ran, expected and "one" or "none"))
            handedOver = handedOver + ran
        end
        local light, order = Snapshot(box)
        Preview.Refresh(box, "UNIT_PREVIEW_ANIMATE")
        local full = Snapshot(box)
        CheckSameScene(label .. string.format(" at %.2fs", box._animationElapsed), light, full, order)
        onUpdate(box, 0.06)
    end
    action.set(false)
    return handedOver
end
for _, key in ipairs({ "player", "target", "focus", "boss" }) do AnimateUnit(key, "unit " .. key) end
-- Widget writes counted on one region. The count wrapper is an instance field
-- over the shared method; Uncount restores the method.
local writeCounts = {}
local function CountWrites(region, method, label)
    local original = region[method]
    rawset(region, method, function(self, ...)
        writeCounts[label] = (writeCounts[label] or 0) + 1
        return original(self, ...)
    end)
end
local function ResetWriteCounts() for label in pairs(writeCounts) do writeCounts[label] = nil end end
-- Each health value is written once per full repaint: RenderHealth writes the
-- fill, the heal prediction that follows it and the heal absorb width, and the
-- shared value painter skips them on a full refresh. A tick writes each once
-- and leaves the heal prediction anchored where the refresh put it.
do
    selected = "player"
    Preview.Refresh(box, "MENU_PREVIEW_BUDGET")
    local scene, mock = box._msufPreviewScene, box.mock
    Check(scene.healPredShown and scene.healPredMode == 3 and scene.healAbsorbShown,
        "harness: the player preview shows no following heal prediction and heal absorb")
    local watched = {
        { mock.healthBar, "SetValue", "health fill" }, { mock.healPred, "SetWidth", "heal prediction width" },
        { mock.healPred, "ClearAllPoints", "heal prediction anchor" }, { mock.healAbsorb, "SetWidth", "heal absorb width" },
    }
    for _, w in ipairs(watched) do CountWrites(w[1], w[2], w[3]) end
    ResetWriteCounts()
    Preview.Refresh(box, "MENU_PREVIEW_BUDGET")
    for _, label in ipairs({ "health fill", "heal prediction width", "heal absorb width" }) do
        Check(writeCounts[label] == 1, string.format("a full player repaint writes the %s %d times (once expected)", label, writeCounts[label] or 0))
    end
    local onUpdate, action = StartAnimation(box, "unit player value writes")
    onUpdate(box, 0.06)
    ResetWriteCounts()
    local before = fullRefreshes
    onUpdate(box, 0.06)
    Check(fullRefreshes == before, "harness: the counted player tick ran a full repaint")
    for _, label in ipairs({ "health fill", "heal prediction width", "heal absorb width" }) do
        Check(writeCounts[label] == 1, string.format("an Animate tick writes the %s %d times (once expected)", label, writeCounts[label] or 0))
    end
    Check((writeCounts["heal prediction anchor"] or 0) == 0, "an Animate tick re-anchors the heal prediction")
    action.set(false)
    for _, w in ipairs(watched) do rawset(w[1], w[2], nil) end
end
-- The class resource animates on the Class Power page (a segmented and,
-- where the client has one, a continuous resource, with its text), and every
-- status indicator of the Status page's "all" view stays as a full refresh
-- leaves it.
do
    local bars = env.MSUF_DB.bars
    local savedKey, savedSpec, savedText = M.activeKey, M._msuf2ClassPowerPreviewSpecKey, bars.classPowerShowText
    M.activeKey, bars.classPowerShowText = "classpower", true
    for _, specKey in ipairs({ "rogue_combo", "priest_shadow" }) do
        if M.ClassPowerPreviewSpecs and M.ClassPowerPreviewSpecs[specKey] then
            M._msuf2ClassPowerPreviewSpecKey = specKey
            AnimateUnit("player", "unit player " .. specKey)
            local cp = box._msufPreviewScene and box._msufPreviewScene.cp
            Check(cp and cp.preview and cp.preview.key == specKey and cp.animatedValue ~= nil,
                "harness: the player preview animates no " .. specKey .. " class resource")
        else
            Check(specKey ~= "rogue_combo", "harness: the client has no combo point preview")
        end
    end
    M.activeKey, M._msuf2ClassPowerPreviewSpecKey, bars.classPowerShowText = savedKey, savedSpec, savedText
    local savedStatusMode = Preview.statusPreviewMode
    Preview.statusPreviewMode = "all"
    AnimateUnit("player", "unit player status")
    local combat = box.mock.icons and box.mock.icons.statusCombat
    Check(combat and combat:IsShown(), "harness: the all-status player preview shows no combat icon")
    Preview.statusPreviewMode = savedStatusMode
end
-- Value-driven colours: health text and health bar by health, a texture
-- layer coloured by health, and a power background that matches the health
-- bar colour.
local function SetFields(t, fields)
    local saved = {}
    for field, value in pairs(fields) do saved[field] = t[field]; t[field] = value end
    return saved
end
local function RestoreFields(t, saved)
    for field, value in pairs(saved) do t[field] = value end
end
do
    local g, target = env.MSUF_DB.general, env.MSUF_DB.target
    local savedG = SetFields(g, { colorHealthTextByHealth = true, barMode = "gradient", powerBarBgMatchBarColor = true })
    local savedT = SetFields(target, { texLayerEnabled = true, texLayerColorMode = "HEALTH" })
    MSUF.UF.Config.Refresh()
    -- Boss runs without a compiled spec on the clients that have no boss
    -- frames, where the power background follows the health colour.
    AnimateUnit("boss", "unit boss value colours")
    AnimateUnit("target", "unit target value colours")
    Check(box.mock.texLayers and box.mock.texLayers[1] and box.mock.texLayers[1]:IsShown(),
        "harness: the value colours target preview shows no texture layer")
    local healthColor = rawget(box.mock.healthBar, "statusBarColor")
    Check(type(healthColor) == "table" and type(healthColor[1]) == "number" and type(healthColor[2]) == "number",
        "harness: the gradient health colour is no number")
    -- A second layer shown only below 75% health appears and disappears
    -- with the animated health: exactly those frames hand over to a full
    -- refresh, which lays the layer out.
    local savedT2 = SetFields(target, { texLayer2Enabled = true, texLayer2HealthCondition = "BELOW", texLayer2HealthThreshold = 0.75 })
    MSUF.UF.Config.Refresh()
    local layer, scratch = nil, {}
    local handedOver = AnimateUnit("target", "unit target health-gated layer", function(owner)
        layer = layer or owner.mock.texLayers[2]
        local state = MSUF.PreviewAnimation.BuildFrameState(nil, 1, "target", scratch, owner._animationElapsed + 0.06)
        return (state.hpPct < 0.75) ~= (layer:IsShown() == true)
    end)
    Check(handedOver > 0, "harness: the health-gated layer never crossed its threshold")
    RestoreFields(target, savedT2)
    RestoreFields(g, savedG)
    RestoreFields(target, savedT)
    MSUF.UF.Config.Refresh()
end

-- Group preview ----------------------------------------------------------------
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
MSUF.GF.EnsureDB()
-- The menu's spell indicator model runs many times per group repaint; with a
-- complete style block it must not rebuild the style defaults table.
do
    local readSpellIndicators = M.GroupPage and M.GroupPage.SpellIndicators
    Check(type(readSpellIndicators) == "function", "no group spell indicator model")
    M.gfScope = "party"
    local si = readSpellIndicators("party")
    Check(type(si) == "table" and type(si.style) == "table", "no spell indicator style block")
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 200 do readSpellIndicators("party") end
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    Check(kb < 0.5, string.format("reading a complete spell indicator style block costs %.2f KB per 200 reads", kb))
    si.style.stackY = nil
    readSpellIndicators("party")
    Check(si.style.stackY ~= nil, "an incomplete spell indicator style block is no longer filled")
end
-- The group preview's Animate driver, like the unit one: every tick past the
-- first advances the last scene, and paints exactly what a full
-- GROUP_PREVIEW_ANIMATE refresh paints at the same clock.
local function AnimateGroup(group, label)
    group:Refresh("SETTINGS")
    local fullGroupRefreshes = 0
    local refresh = group.Refresh
    group.Refresh = function(self, reason)
        fullGroupRefreshes = fullGroupRefreshes + 1
        return refresh(self, reason)
    end
    local action = group._previewAnimationButton and group._previewAnimationButton._msuf2CommandAction
    Check(action and action.set(true) == true, label .. ": the Animate toggle does not start the animation")
    local onUpdate = group:GetScript("OnUpdate")
    Check(type(onUpdate) == "function", label .. ": Animate installs no OnUpdate driver")
    onUpdate(group, 0.06)
    local before = fullGroupRefreshes
    local result = Record(label .. " animate tick", Measure(function() onUpdate(group, 0.06) end, 40))
    Check(fullGroupRefreshes == before, label .. ": an Animate tick runs the full repaint (" .. (fullGroupRefreshes - before) .. " in 43 ticks)")
    CheckTick("the " .. label .. " preview", result)
    for _ = 1, 4 do
        for _ = 1, 9 do onUpdate(group, 0.06) end
        local light, order = Snapshot(group)
        refresh(group, "GROUP_PREVIEW_ANIMATE")
        local full = Snapshot(group)
        CheckSameScene(label .. string.format(" at %.2fs", group._animationElapsed), light, full, order)
        onUpdate(group, 0.06)
    end
    action.set(false)
    group.Refresh = refresh
end
for _, scope in ipairs({ "party", "raid" }) do
    M.gfScope = scope
    local group = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    group:Show(); group._stage:SetSize(600, 220)
    local result = Record("group " .. scope .. " repaint", Measure(function() group:Refresh("SETTINGS") end, 20))
    CheckRepaint("the group " .. scope .. " preview", result)
    -- The harness has no layout engine: resolved rects for the mock and its
    -- texts let the text handles measure the value texts, so a handle that
    -- does not follow a changed value is visible.
    local mock = group._msufGFRenderState.mock
    rawset(mock, "left", 0); rawset(mock, "bottom", 0)
    for _, field in ipairs({ "_nameFS", "_hpLeftFS", "_hpCenterFS", "_hpRightFS", "_powerLeftFS", "_powerCenterFS", "_powerRightFS" }) do
        local fs = rawget(mock, field)
        Check(fs ~= nil, "harness: the group mock has no " .. field)
        rawset(fs, "left", 10); rawset(fs, "bottom", 10); rawset(fs, "width", 200); rawset(fs, "height", 12)
    end
    AnimateGroup(group, "group " .. scope)
    -- Health-driven colours: the gradient bar mode, the health text coloured
    -- by health, and both health-following background modes.
    local conf = M.GroupPage and M.GroupPage.Conf and M.GroupPage.Conf(scope)
    Check(type(conf) == "table", "harness: no " .. scope .. " group config")
    local general = env.MSUF_DB.general
    local savedConf = SetFields(conf, { gfBarMode = "gradient", fontOverride = true, colorHealthTextByHealth = true })
    for _, bgMode in ipairs({ "match_health", "health_gradient" }) do
        local savedGeneral = SetFields(general, { barBgColorMode = bgMode })
        MSUF.UF.Config.Refresh()
        MSUF.GF.InvalidateCompiledSpecs(scope)
        AnimateGroup(group, "group " .. scope .. " " .. bgMode)
        Check(mock._msufGFPreviewBackgroundColorMode == bgMode,
            "harness: the " .. scope .. " preview background is not in " .. bgMode .. " mode")
        RestoreFields(general, savedGeneral)
    end
    RestoreFields(conf, savedConf)
    MSUF.UF.Config.Refresh()
    MSUF.GF.InvalidateCompiledSpecs(scope)
    -- The preview spec is reused while the compiled group spec holds and is
    -- replaced with it: Auras3 caches the preview lanes by its identity.
    local state = group._msufGFRenderState
    local first, again = state.CompiledSpec(scope), state.CompiledSpec(scope)
    Check(type(first) == "table" and first == again, "the group " .. scope .. " preview builds a new spec on every repaint")
    MSUF.GF.InvalidateCompiledSpecs(scope)
    local recompiled = state.CompiledSpec(scope)
    Check(type(recompiled) == "table" and recompiled ~= first,
        "the group " .. scope .. " preview spec kept its identity across a recompile (stale Auras3 lanes)")
    group:Hide()
end

print(string.format("menu_preview_repaint_budget_smoke: ok (%s)", flavor))

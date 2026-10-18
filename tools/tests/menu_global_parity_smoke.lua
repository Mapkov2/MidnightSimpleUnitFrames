-- Parent/candidate replay of the four Global owners through the real client menu.
-- The immutable parent is materialized under .checks; no git metadata is written.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local parent = "e48e595c3eef2009f5f4933ec5cf9303c36bed96"
local names = { "Global", "GlobalFonts", "GlobalMisc", "GlobalCastbars" }
local scratch = root .. "/.checks"
assert(not root:find('["%%\r\n]'), "unsafe worktree path")
local windows = package.config:sub(1, 1) == "\\"
local function Quote(s)
    if windows then return '"' .. s .. '"' end
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
os.execute((windows and "if not exist " or "mkdir -p ") .. Quote(scratch)
    .. (windows and (" mkdir " .. Quote(scratch)) or ""))
local sources = {}
for _, name in ipairs(names) do
    local file = "MSUF_Menu2_" .. name .. ".lua"
    local command = "git -C " .. Quote(root) .. " show " .. parent
        .. ":MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/" .. file
    local pipe = assert(io.popen(command, "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 1000 and source:find("local M =", 1, true), "parent source unavailable: " .. file)
    local path = scratch .. "/global-parent-" .. flavor .. "-" .. file
    local out = assert(io.open(path, "wb")) out:write(source) out:close()
    sources[file] = path
end
local function Encode(v, seen)
    local t = type(v)
    if t == "function" then return "<function>" end
    if t ~= "table" then
        -- Catalog revision keys contain process-local widget addresses.
        local text = tostring(v):gsub("table: 0x%x+", "<widget-address>"):gsub("table: %x+", "<widget-address>")
        return t .. ":" .. text
    end
    if v.GetObjectType then return "<widget>" end
    -- Compare refresh targets by identity; widget state and geometry are recorded separately.
    if type(v.SetContentHeight) == "function" and type(v.key) == "string" then
        return "context:" .. v.key .. ":width:" .. tostring(v.width)
    end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys, values = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do values[#values + 1] = tostring(k) .. "=" .. Encode(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(values, ",") .. "}"
end
-- The sandbox answers every unknown global with a stub, so a page that forgets to declare
-- one of its locals (ctx, b, s) would read a stub instead of failing. Reads of these names
-- as globals are recorded and refused.
local LOCAL_NAMES = { ctx = true, b = true, s = true, page = true, unit = true, scope = true,
    parent = true, section = true, rows = true, row = true, widget = true, builder = true }
local leaks = {}
local function Run(prior)
    local calls, output, targets, owned = {}, {}, {}, {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local meta = getmetatable(world.env)
            local index = meta.__index
            meta.__index = function(t, key)
                if LOCAL_NAMES[key] then
                    leaks[key] = true
                    error("local name read as a global: " .. key, 2)
                end
                return index(t, key)
            end
            if prior then
                local load = world.LoadFile
                world.LoadFile = function(self, path, ...)
                    path = sources[path:match("([^/\\]+)$")] or path
                    return load(self, path, ...)
                end
            end
            world.widgets.Methods.GetCenter = function(f)
                return (tonumber(f.left) or 0) + (tonumber(f.width) or 0) / 2,
                    (tonumber(f.bottom) or 0) + (tonumber(f.height) or 0) / 2
            end
            for _, n in ipairs({ "Rows", "Columns", "Frames", "FrameWidth", "FrameHeight" }) do
                world.widgets.Methods["SetFlipBook" .. n] = function(f, v) f["flipBook" .. n] = v end
            end
        end,
        beforeOptions = function(world)
            -- Native duration/third-party surfaces are fixture seams. Page input,
            -- capability gates and apply requests still use the production owners.
            if flavor == "Mainline" or flavor == "Forever" then
                -- C_Spell drops writes, so it is replaced as the sibling gate smokes do.
                world.env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end,
                    DoesSpellExist = function(spellID) return spellID == 61304 end },
                    { __index = world.env.C_Spell })
                world.env.MSUF_GCDBar_IsSupported = function() return true end
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    for _, name in ipairs({ "Toggle", "ToggleAt", "SwitchAt", "Slider", "Dropdown", "Segment",
        "Color", "Text", "ControlCard", "ScopeOverrideBar", "LabelAt", "Button", "ThemeFont", "ThemeButton" }) do
        local theme = name == "ThemeFont" or name == "ThemeButton"
        local owner = theme and M.Theme or M.Widgets
        local method = theme and name:sub(6) or name
        local constructor = name == "ThemeFont" and "LabelAt" or name == "ThemeButton" and "Button" or name
        local create = owner[method]
        owner[method] = function(...)
            local level, info = 2, debug.getinfo(2, "S")
            while info and (info.what == "tail" or info.source:find("MSUF_Menu2_ControlSchema.lua", 1, true)) do
                level = level + 1 info = debug.getinfo(level, "S")
            end
            local file = info and info.source:match("(MSUF_Menu2_Global[%w]*%.lua)$")
            local widget = create(...)
            if sources[file] and widget then owned[#owned + 1] = { widget, constructor } end
            return widget
        end
    end
    env.GameTooltip.IsForbidden = function() return false end
    local F = core.ProfileFields
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    for _, owner in ipairs({ M, M.ApplyService }) do
        for name, fn in pairs(owner) do
            if type(fn) == "function" and (owner ~= M or name:match("^Request") or name:match("^Set.*Value$")) then
                owner[name] = function(...)
                    local args = {}
                    for i = 1, select("#", ...) do args[i] = Encode((select(i, ...))) end
                    calls[#calls + 1] = name .. "(" .. table.concat(args, ",") .. ")"
                    return fn(...)
                end
            end
        end
    end
    -- The pages also call apply globals directly (GCD layout, kick icon, textures), not only M.
    for name, fn in pairs(env) do
        if type(name) == "string" and name:sub(1, 5) == "MSUF_" and type(fn) == "function" then
            for _, verb in ipairs({ "Refresh", "Update", "Apply", "Ensure", "Reset", "Set", "Clear", "Request", "Show" }) do
                if name:find(verb, 6, true) then
                    env[name] = function(...)
                        local args = {}
                        for i = 1, select("#", ...) do args[i] = Encode((select(i, ...))) end
                        calls[#calls + 1] = "global:" .. name .. "(" .. table.concat(args, ",") .. ")"
                        return fn(...)
                    end
                    break
                end
            end
        end
    end
    local function Add(key, ...)
        local row = {}
        for i = 1, select("#", ...) do row[i] = Encode((select(i, ...))) end
        assert(output[key] == nil, "duplicate observation " .. key)
        output[key] = table.concat(row, "\t")
    end
    local function Diff(a, b, path, out)
        path, out = path or "", out or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for k in pairs(a) do keys[k] = true end
            for k in pairs(b) do keys[k] = true end
            for k in pairs(keys) do Diff(a[k], b[k], path .. "." .. tostring(k), out) end
        elseif Encode(a) ~= Encode(b) then out[path] = { Encode(a), Encode(b) } end
        return out
    end
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function Input(w, kind, value)
        if kind == "color" then w._msuf2OnColorChanged(unpack(value))
        elseif kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
        elseif w.buttons then
            for _, button in ipairs(w.buttons) do
                if button._msuf2Value == value then button:Click("LeftButton") end
            end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        elseif w._msuf2OnCommit then w._msuf2OnCommit(value)
        else w:SetValue(value) World.FireScript(w, "OnValueChanged", value) end
        mw:RunTimers()
    end
    local function Records(page)
        local rows = {}
        for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if r.pageKey == page then rows[#rows + 1] = M.RuntimeControlCatalog.Get(r.controlId) end
        end
        table.sort(rows, function(a, b) return a.controlId < b.controlId end)
        return rows
    end
    local function State(page)
        local out = {}
        for _, r in ipairs(Records(page)) do
            local w = r.widget
            if w then
                local command = Command(w)
                out[r.controlId] = { w:IsShown(), w:IsEnabled(), command and command.get and { command.get() },
                    w.GetChecked and w:GetChecked(), w.GetValue and w:GetValue() }
            end
        end
        return out
    end
    local function Expand(page)
        local sections = M.cache[page].sections
        local ids = {}
        for id in pairs(sections) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local entry = sections[id]._msuf2CollapsibleEntry
            if entry then entry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        M.Refresh(M.cache[page].ctx)
        mw:RunTimers()
    end
    local function Choice(r, w, edge)
        local command = Command(w)
        if r.kind == "toggle" then return not command.get() end
        if r.kind == "color" then return edge and { 0, 0.25, 1 } or { 0.7, 0.4, 0.2 } end
        if r.kind == "slider" then
            local low, high = w:GetMinMaxValues()
            return edge and low or high
        end
        if r.kind == "textinput" then return edge and "" or "Test" end
        local values = w.GetValues and w:GetValues() or w.values
        if type(values) == "function" then values = values() end
        local choices = {}
        for _, item in ipairs(values or {}) do
            if not item.disabled then choices[#choices + 1] = item.value or item[1] end
        end
        return choices[edge and 1 or #choices]
    end
    -- State 1 is the default profile, 2 an edge profile and 3 clears every key the pages read.
    local readKeys = {}
    for state = 1, 3 do
        local edge, absent = state == 2, state == 3
        for _, page in ipairs({ "opt_fonts", "opt_misc", "opt_castbar" }) do
            local g = env.MSUF_DB.general
            g._fontScopeKey = edge and "gf_raid" or "shared"
            if edge then
                core.SuiteLink.HasNameplateKickReady = function() return true end
                core.SuiteLink.ModuleTitle = function() return "Nameplates" end
                core.KickReady.HasConsumers = function() return true end
                if core.Client.Family == "Mainline" then
                    env.MSUF_EllesmereEditMode_IsAvailable = function() return true end
                end
                for _, key in ipairs({ "gf_raid", "gf_mythicraid" }) do
                    env.MSUF_DB[key].fontOverride = true
                    env.MSUF_DB[key].fontShadowOpacity = 0.2
                    env.MSUF_DB[key].fontBaselineOffset = -4
                    env.MSUF_DB[key].nameShortenEnabled = true
                end
                for _, key in ipairs({ "highlightEnabled", "enableFocusKickIcon", "showGCDBar", "gcdBarDetached",
                    "kickReadyShowTarget", "castbarShowChannelTicks", "empowerStageBlink" }) do g[key] = true end
                g.castbarSpellNameShortening, g.menuAccent, g.unitTooltipMode = 1, "custom", "MODIFIER"
            end
            if absent then
                g._fontScopeKey = nil
                for path in pairs(readKeys) do
                    local node, rest = env.MSUF_DB, path
                    for part in path:gmatch("([^.]+)%.") do
                        node = type(node) == "table" and node[part] or nil
                        rest = rest:sub(#part + 2)
                    end
                    if type(node) == "table" then node[rest] = nil end
                end
            end
            owned = {}
            M.InvalidatePage(page)
            assert(mw:Select(page), "page missing: " .. page)
            Expand(page)
            if page == "opt_castbar" and (flavor == "Mainline" or flavor == "Forever") then
                assert(M.cache[page].sections.castbar_gcd, "GCD Bar section was not built: " .. flavor)
            end
            local tag = page .. ":" .. state
            for i, item in ipairs(owned) do
                local widget, constructor = item[1], item[2]
                if not prior then
                    local declaration = assert(widget._msuf2ControlSchema, "undeclared " .. page .. " " .. constructor)
                    assert(declaration.id and declaration.kind and declaration.scope and declaration.applyDomain,
                        "incomplete row: " .. tostring(declaration.id))
                    local record = widget._msuf2RuntimeControlRecord
                    if record and record.command then
                        assert(declaration.id == record.controlId, "declared identity drift: " .. record.controlId)
                    end
                end
                local layout = {}
                local function Geometry(w)
                    local points = {}
                    for point = 1, w:GetNumPoints() do points[point] = { w:GetPoint(point) } end
                    layout[#layout + 1] = { w:GetObjectType(), points, w.width, w.height, w.text, w.alpha,
                        w:IsShown(), w:IsEnabled(), w.justifyH, w.justifyV, w._msuf2CursorY }
                    for _, region in ipairs(w.regions or {}) do Geometry(region) end
                end
                Geometry(widget)
                if widget._msuf2Title then Geometry(widget._msuf2Title) end
                if widget._msuf2Label then Geometry(widget._msuf2Label) end
                Add(tag .. ":owned:" .. i, constructor, layout, widget._msuf2SearchText, widget._msuf2ControlKind,
                    widget._msuf2SearchRegistryId ~= nil)
            end
            local rows = Records(page)
            Add(tag .. ":count", #rows)
            local searched = {}
            for _, widget in ipairs(M.cache[page].searchWidgets or {}) do
                searched[#searched + 1] = tostring(widget._msuf2SearchText or widget._msuf2SearchTitle) .. "|"
                    .. tostring(widget._msuf2ControlKind) .. "|" .. tostring(widget._msuf2SearchRegistryId ~= nil)
            end
            Add(tag .. ":search", searched)
            for _, r in ipairs(rows) do
                if r.settingKey and r.settingKey ~= "" and not absent then readKeys[r.settingKey] = true end
            end
            for _, r in ipairs(rows) do
                local w = r.widget
                if w then
                    local command = Command(w)
                    local tips = {}
                    env.GameTooltip.SetOwner = function() end
                    env.GameTooltip.SetText = function(_, ...) tips[#tips + 1] = { ... } end
                    env.GameTooltip.AddLine = function(_, ...) tips[#tips + 1] = { ... } end
                    env.GameTooltip.Show, env.GameTooltip.Hide = function() end, function() end
                    if w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
                    if w:HasScript("OnLeave") then World.FireScript(w, "OnLeave") end
                    local points = {}
                    for i = 1, w:GetNumPoints() do points[i] = { w:GetPoint(i) } end
                    Add(tag .. ":control:" .. r.controlId, r, w._msuf2SearchMeta, points, w.width, w.height,
                        w.valueStep, w.GetMinMaxValues and { w:GetMinMaxValues() },
                        w.GetValues and w:GetValues() or w.values, tips)
                    local kind = r.kind
                    local ordinary = kind == "toggle" or kind == "slider" or kind == "dropdown"
                        or kind == "segment" or kind == "color" or kind == "textinput"
                    -- Scope navigation rebuilds its page and is replayed separately below.
                    local navigation = r.controlId:find(".scope.selector", 1, true)
                    if ordinary and command and command.get and command.set and not navigation and not absent then
                        targets[r.controlId] = true
                        local value = Choice(r, w, edge)
                        assert(value ~= nil, "no input value: " .. r.controlId)
                        M.ClearHistory()
                        local before = F.CopySnapshot(env.MSUF_DB)
                        calls = {}
                        Input(w, kind, value)
                        M.Refresh(M.cache[page].ctx)
                        local after = F.CopySnapshot(env.MSUF_DB)
                        local key = tag .. ":input:" .. r.controlId
                        Add(key, value, Diff(before, after), calls, State(page))
                        local undo = M.Undo() mw:RunTimers()
                        Add(key .. ":undo", undo, Diff(before, env.MSUF_DB), State(page))
                        local redo = M.Redo() mw:RunTimers()
                        Add(key .. ":redo", redo, Diff(after, env.MSUF_DB), State(page))
                        M.ClearHistory()
                        -- Revert the input before combat so the combat mutation is causal.
                        for _, change in ipairs(F.Diff(env.MSUF_DB, before)) do
                            F.Write(env.MSUF_DB, change.path, change.value)
                        end
                        M.Refresh(M.cache[page].ctx)
                        M.ClearHistory()
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        env.InCombatLockdown = function() return false end
                        before = F.CopySnapshot(env.MSUF_DB) calls = {}
                        Input(w, kind, value)
                        Add(key .. ":combat-edge", Diff(before, env.MSUF_DB), calls, M.Undo())
                        env.InCombatLockdown = function() return true end
                        Input(w, kind, value)
                        Add(key .. ":combat", Diff(before, env.MSUF_DB), M.Undo())
                        core.Util.InCombat("PLAYER_REGEN_ENABLED")
                        env.InCombatLockdown = function() return false end
                        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                    end
                end
            end
            for _, r in ipairs(Records(page)) do
                if not absent and r.kind == "button" and (r.controlId:find(".scope.overrides.reset", 1, true)
                    or r.controlId:find(".focus.kick.reset.position", 1, true)) then
                    local widget = r.widget
                    M.ClearHistory()
                    local before = F.CopySnapshot(env.MSUF_DB)
                    calls = {} widget:Click() mw:RunTimers()
                    local after = F.CopySnapshot(env.MSUF_DB)
                    local key = tag .. ":button:" .. r.controlId
                    Add(key, Diff(before, after), calls, State(page))
                    Add(key .. ":undo", M.Undo()) mw:RunTimers()
                    Add(key .. ":undone", Diff(before, env.MSUF_DB))
                    Add(key .. ":redo", M.Redo()) mw:RunTimers()
                    Add(key .. ":redone", Diff(after, env.MSUF_DB))
                    for _, change in ipairs(F.Diff(env.MSUF_DB, before)) do
                        F.Write(env.MSUF_DB, change.path, change.value)
                    end
                    M.ClearHistory()
                    core.Util.InCombat("PLAYER_REGEN_DISABLED")
                    before = F.CopySnapshot(env.MSUF_DB)
                    calls = {} widget:Click() mw:RunTimers()
                    Add(key .. ":combat", Diff(before, env.MSUF_DB), calls, M.Undo())
                    core.Util.InCombat("PLAYER_REGEN_ENABLED")
                    mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                end
            end
            if page == "opt_fonts" and not absent then
                local baseline = assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_fonts", "global", "text_style.baseline").controlId)).widget
                local originalScope = env.MSUF_DB.general._fontScopeKey
                env.MSUF_DB.general._fontScopeKey = "target"
                env.MSUF_DB.target.fontOverride = true
                env.MSUF_DB.target.fontBaselineOffset = -4
                M.Refresh(M.cache[page].ctx)
                local before = F.CopySnapshot(env.MSUF_DB)
                calls = {} M.ClearHistory()
                Input(baseline, "slider", 3)
                assert(env.MSUF_DB.target.fontBaselineOffset == 3, "input captured the build-time font scope")
                Add(tag .. ":input-time-scope", Diff(before, env.MSUF_DB), calls, M.Undo())
                mw:RunTimers()
                env.MSUF_DB.general._fontScopeKey = originalScope
                M.Refresh(M.cache[page].ctx)
                local selector = assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_fonts", "global", "scope.selector").controlId)).widget
                calls = {} before = F.CopySnapshot(env.MSUF_DB)
                selector:SetValue(edge and "player" or "target") mw:RunTimers() Expand(page)
                Add(tag .. ":navigation", Diff(before, env.MSUF_DB), calls, State(page))
            end
            -- Existing reset/copy popup owners keep their real widget dispatch.
            local sectionIds = {}
            for id in pairs(M.cache[page].sections) do sectionIds[#sectionIds + 1] = id end
            table.sort(sectionIds)
            for _, id in ipairs(sectionIds) do
                local entry = M.cache[page].sections[id]._msuf2CollapsibleEntry
                local actions = entry and entry._msuf2SectionActions
                if actions and not absent then
                    actions:Click()
                    local popup = actions._msuf2GetSectionPopup()
                    if popup then
                        for _, widget in ipairs(mw.world.widgets.frames) do
                            if widget:GetParent() == popup and widget._msuf2Label
                                and widget._msuf2Label:GetText() == "Reset section" then
                                local before = F.CopySnapshot(env.MSUF_DB)
                                calls = {} M.ClearHistory() widget:Click() mw:RunTimers()
                                Add(tag .. ":reset:" .. id, Diff(before, env.MSUF_DB), calls, M.Undo())
                                mw:RunTimers()
                            end
                        end
                        if popup._msuf2CopySection then
                            local before = F.CopySnapshot(env.MSUF_DB)
                            calls = {}
                            local copied = popup._msuf2CopySection("player") mw:RunTimers()
                            Add(tag .. ":copy:" .. id, copied, Diff(before, env.MSUF_DB), calls)
                        end
                        popup:Hide()
                    end
                end
            end
            Add(tag .. ":refresh", State(page))
            mw:Select("home")
            mw:Select(page) Expand(page)
            Add(tag .. ":reopen", State(page))
        end
    end
    return output, targets
end
local expected, targets = Run(true)
local actual, candidateTargets = Run(false)
assert(next(leaks) == nil, "page reads a local name as a global: " .. tostring(next(leaks)))
local checks, controls = 0, 0
for id in pairs(targets) do
    controls = controls + 1
    assert(candidateTargets[id], "control removed: " .. id)
end
assert(controls >= 75, "incomplete Global control replay: " .. controls)
if flavor == "Mainline" or flavor == "Forever" then
    local gcd = 0
    for id in pairs(targets) do if id:find(".global.gcd.", 1, true) then gcd = gcd + 1 end end
    assert(gcd >= 11, "GCD Bar controls were not replayed: " .. gcd)
end
local keys = {}
for key in pairs(expected) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do
    checks = checks + 1
    if actual[key] ~= expected[key] then
        for name, value in pairs({ expected = expected[key], actual = actual[key] or "<missing>" }) do
            local file = assert(io.open(scratch .. "/global-" .. flavor .. "-" .. name .. ".txt", "wb"))
            file:write(key, "\n", value) file:close()
        end
        error(flavor .. ": parity mismatch " .. key)
    end
end
for key in pairs(actual) do assert(expected[key], "unexpected control/observation: " .. key) end
print("menu_global_parity_smoke: " .. flavor .. " PASS (" .. controls .. " controls, " .. checks .. " observations)")

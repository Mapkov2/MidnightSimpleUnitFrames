-- menu_section_parity_world.lua: control/layout/behavior receipts for unit page sections.
--
-- The receipts are captured once from the builders before they moved onto the
-- control schema (tools/fixtures/menu-section-parity). Every later run rebuilds the
-- real sections in the real client graph and must reproduce them: control records
-- (identity, label, key, range, values, value, search metadata), tooltip text,
-- a layout digest of every owned widget, and replayed inputs with their profile
-- diffs, apply requests, undo/redo and combat refusal. A control without a schema
-- declaration fails. Plain Lua 5.1. Not a smoke itself.
local Parity = {}
local UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
Parity.UNITS = UNITS

local function Encode(value, seen)
    local kind = type(value)
    if kind == "function" then return "<function>" end
    if kind ~= "table" then return (tostring(value):gsub("[\r\n\t]", " ")) end
    if value.GetObjectType then return "<widget>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do
        if type(key) ~= "table" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. Encode(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Digest(text)
    local a, b = 5381, 52711
    for i = 1, #text do
        local byte = text:byte(i)
        a, b = (a * 33 + byte) % 4294967296, (b * 31 + byte) % 4294967296
    end
    return string.format("%08x%08x", a, b)
end
local function Read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local function Write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

function Parity.Run(cfg)
    local root = cfg.root:gsub("\\", "/"):gsub("/$", "")
    local area, flavor = cfg.area, cfg.flavor
    local integrated = area == "dispel_overlay" or area == "dispel_symbol" or area == "boss_target_highlight"
    local sharedParent = arg[3] == "--shared-parent"
    assert(not sharedParent or (integrated and not cfg.capture), "invalid shared-parent replay")
    local parentPath, parentName
    if sharedParent then
        parentName = area == "boss_target_highlight" and "MSUF_Menu2_UnitSections.lua" or "MSUF_Menu2_UnitDispel.lua"
        local original = "096d5e0e0ffc2c386189932cecb946435db09bc3:MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/" .. parentName
        local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. original, "r"))
        local source = pipe:read("*a")
        pipe:close()
        assert(#source > 1000, "authentic section parent unavailable")
        parentPath = root .. "/.checks/shared-parent-" .. area .. "-" .. flavor .. ".lua"
        Write(parentPath, source)
    end
    local sourceRoot = (os.getenv("MSUF_SECTION_SOURCE_ROOT") or root):gsub("\\", "/"):gsub("/$", "")
    local captureOutput = os.getenv("MSUF_SECTION_CAPTURE_OUTPUT")
    if cfg.capture then
        local python = assert(os.getenv("MSUF_SECTION_CAPTURE_PYTHON"), "capture requires the authenticated original-source runner")
        local base = assert(os.getenv("MSUF_SECTION_CAPTURE_BASE"), "capture base required")
        assert(captureOutput and sourceRoot ~= root, "capture cannot execute candidate builders")
        for _, value in ipairs({ python, root, sourceRoot, base }) do
            assert(not value:find('["%%\r\n]'), "unsafe capture argument")
        end
        local windows = package.config:sub(1, 1) == "\\"
        local function Quote(value)
            if windows then return '"' .. value .. '"' end
            return "'" .. value:gsub("'", "'\\''") .. "'"
        end
        local command = Quote(python) .. ' -I -S ' .. Quote(root .. '/tools/tests/menu_section_capture.py')
            .. ' --check-source --source ' .. Quote(sourceRoot) .. ' --base ' .. Quote(base)
        local pipe = assert(io.popen(windows and ('"' .. command .. '"') or command, "r"))
        local receipt = pipe:read("*a"):gsub("%s+$", "")
        pipe:close()
        assert(receipt == "AUTHENTIC_PRE_SCHEMA:" .. base, "original-source capture authentication failed")
    else
        assert(captureOutput == nil, "comparison must use canonical repository receipts")
        assert(sourceRoot == root, "comparison must execute candidate builders")
    end
    local World = assert(loadfile(sourceRoot .. "/tools/tests/menu_core_world.lua"))()
    if cfg.capture then
        local loader = debug.getinfo(World.Open, "S").source:gsub("^@", ""):gsub("\\", "/")
        assert(loader == sourceRoot .. "/tools/tests/menu_core_world.lua", "capture executed an unpinned menu loader")
    end
    local mw = World.Open(sourceRoot, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            if sharedParent then
                local load = world.LoadFile
                world.LoadFile = function(self, path, ...)
                    if path:sub(-#parentName) == parentName then path = parentPath end
                    return load(self, path, ...)
                end
            end
            world.widgets.Methods.GetCenter = function(frame)
                return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                    (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    if cfg.capture then assert(mw.world.root == sourceRoot, "capture booted a different product root") end
    local Semantics = assert(loadfile(root .. "/tools/tests/menu_section_parity_semantics.lua"))()
    local semantic = Semantics.Open(M, area, env)
    local Gaps = assert(loadfile(root .. "/tools/tests/menu_section_parent_semantics.lua"))()
    local gaps = Gaps.Open(M, area, env)
    local F = core.ProfileFields
    local tooltipLines = {}
    local tooltip = env.GameTooltip
    tooltip.SetOwner = function() end
    tooltip.SetText = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end
    tooltip.AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end
    tooltip.Show, tooltip.Hide = function() end, function() end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local calls = {}
    for _, owner in ipairs({ M, M.ApplyService }) do
        for name, fn in pairs(owner) do
            if type(fn) == "function" and (owner ~= M or name:match("^Request") or name:match("^Set.*Value$")) then
                owner[name] = function(...)
                    local args = { ... }
                    for i = 1, #args do args[i] = Encode(args[i]) end
                    calls[#calls + 1] = name .. "(" .. table.concat(args, ",") .. ")"
                    return fn(...)
                end
            end
        end
    end
    local lines, unique, groups, assertions = {}, {}, {}, 0
    local widgetRows = {}
    local function Add(...)
        local values = { ... }
        local group = tostring(values[2]) .. ":" .. tostring(table.remove(values, 3))
        groups[group] = groups[group] or {}
        for i = 1, #values do values[i] = Encode(values[i]) end
        local line = table.concat(values, "\t")
        groups[group][line] = true
        if not unique[line] then unique[line], lines[#lines + 1] = true, line end
    end
    local function Check(value, message)
        assertions = assertions + 1
        assert(value, area .. ": " .. message)
        return value
    end
    local function SectionOf(frame, entry)
        local current = frame
        while current do
            for id, section in pairs(entry.sections) do
                if cfg.sections[id] and (current == section or current == section._msuf2CollapsibleEntry.header) then return id end
            end
            current = current.GetParent and current:GetParent()
        end
    end
    local function Expand(page)
        local entry = Check(M.cache[page], "page missing " .. page)
        for id, section in pairs(entry.sections) do
            if cfg.sections[id] then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        M.Refresh(entry.ctx)
        mw:RunTimers()
    end
    local function Snapshot(page, state)
        local entry = M.cache[page]
        local own, index, names = {}, {}, {}
        local function Include(frame)
            if index[frame] then return end
            own[#own + 1], index[frame] = frame, #own + 1
            for _, region in ipairs(frame.regions or {}) do Include(region) end
        end
        for _, frame in ipairs(mw.world.widgets.frames) do
            if SectionOf(frame, entry) then Include(frame) end
        end
        local function Label(frame)
            return frame:GetObjectType() .. ":" .. (type(frame.text) == "string" and frame.text or "")
                .. ":" .. tostring(frame.width) .. "x" .. tostring(frame.height)
        end
        local function Name(frame)
            if not frame or not index[frame] then return "external" end
            if names[frame] then return names[frame] end
            names[frame] = "..."
            local parent = frame:GetParent()
            names[frame] = (index[parent] and Name(parent) or "") .. "/" .. Label(frame)
            return names[frame]
        end
        local rows = {}
        for _, frame in ipairs(own) do
            local points = {}
            for j = 1, frame:GetNumPoints() do
                local a, p, b, x, y = frame:GetPoint(j)
                points[#points + 1] = Encode({ a, Name(p), b, x, y })
            end
            local alpha = type(frame.alpha) == "number" and frame.alpha or ""
            local texture = type(frame.texture) == "string" and frame.texture or ""
            rows[#rows + 1] = table.concat({ Name(frame), Name(frame:GetParent()), table.concat(points, ";"),
                tostring(frame.allPoints and Name(frame.allPoints) or ""), tostring(frame:IsShown()), tostring(frame:IsEnabled()),
                tostring(alpha), tostring(texture), tostring(type(frame.level) == "number" and frame.level or "") }, "\t")
        end
        table.sort(rows)
        Add("layout", page, state, #rows, Digest(table.concat(rows, "\n")))
        widgetRows[#widgetRows + 1] = "# " .. page .. " " .. state .. "\n" .. table.concat(rows, "\n")
        semantic.Snapshot(page, state, function(widget) return SectionOf(widget, entry) end)
        local order = 0
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            local wanted = record.pageKey == page and (widget and SectionOf(widget, entry)
                or (cfg.virtual and cfg.virtual(record)))
            if wanted then
                order = order + 1
                local command = widget and (widget._msuf2CommandAction or record.command) or record.command
                local meta = widget and widget._msuf2SearchMeta or {}
                local values = widget and (widget.GetValues and widget:GetValues() or widget.values)
                if type(values) == "function" then values = values() end
                local low, high
                if widget and record.kind == "slider" then low, high = widget:GetMinMaxValues() end
                tooltipLines = {}
                if widget and widget.HasScript and widget:HasScript("OnEnter") then World.FireScript(widget, "OnEnter") end
                Add("control", page, state, record.controlId, order, record, low or "", high or "", widget and widget.valueStep or "",
                    values or {}, command and command.get and command.get() or "", meta, widget and widget._msuf2ExactTargetContracts or {},
                    widget and widget._msuf2ContextColorOptions or {}, tooltipLines, widget and widget:IsShown() or "",
                    widget and widget:IsEnabled() or "")
                if not cfg.capture and not sharedParent and widget and SectionOf(widget, entry) then
                    local spec = Check(widget._msuf2ControlSchema, "control has no schema declaration: " .. record.controlId)
                    Check(spec.id == record.controlId and spec.scope and spec.applyDomain, "declaration identity: " .. record.controlId)
                    Check(spec.get or spec.action or (spec.unit and spec.key and spec.reason),
                    "declaration has no owned behavior: " .. record.controlId)
                end
            end
        end
        if not cfg.capture and not sharedParent then
            for _, frame in ipairs(own) do
                if frame._msuf2ContextColorOptions then
                    Check(frame._msuf2ControlSchema, "color shortcut has no schema declaration in " .. page)
                end
            end
        end
    end
    local function Record(page, state)
        Expand(page)
        Snapshot(page, state)
    end
    local function Find(page, path)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if record.pageKey == page and record.controlId:lower():sub(-#path - 1) == "." .. path:lower() then
                return M.RuntimeControlCatalog.Get(record.controlId).widget
            end
        end
        error(area .. ": missing control " .. page .. " " .. path)
    end
    local function Input(widget, value)
        local command = widget._msuf2CommandAction
        if command and command.kind == "toggle" then
            widget:SetChecked(value)
            widget:Click("LeftButton")
        elseif widget.buttons then
            for _, button in ipairs(widget.buttons) do
                if button._msuf2Value == value then button:Click("LeftButton") end
            end
        elseif widget._msuf2OnValueChanged then widget._msuf2OnValueChanged(value)
        elseif widget._msuf2OnCommit then widget._msuf2OnCommit(value)
        else
            widget:SetValue(value)
            World.FireScript(widget, "OnValueChanged", value)
        end
        mw:RunTimers()
    end
    local function Diff(before, after)
        local out = {}
        for _, scope in ipairs({ "general", "bars" }) do
            for key, value in pairs(after[scope] or {}) do
                if Encode(value) ~= Encode((before[scope] or {})[key]) then out[scope .. "." .. key] = value end
            end
        end
        for unit, conf in pairs(after) do
            if type(conf) == "table" and (unit == "player" or unit == "target" or unit == "boss" or unit == "arena"
                or unit == "focus" or unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit == "pettarget") then
                for key, value in pairs(conf) do
                    if Encode(value) ~= Encode((before[unit] or {})[key]) then out[unit .. "." .. key] = value end
                end
            end
        end
        return out
    end
    local function Gates(page)
        local gates = {}
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            if record.pageKey == page and widget and SectionOf(widget, M.cache[page]) then
                gates[record.controlId] = (widget:IsEnabled() and "on" or "off") .. (widget:IsShown() and "" or ":hidden")
            end
        end
        return gates
    end
    local function Edit(page, path, value)
        local widget = Find(page, path)
        M.ClearHistory()
        local before = F.CopySnapshot(env.MSUF_DB)
        calls = {}
        Input(widget, value)
        Add("behavior", page, path .. ":" .. tostring(value), "input", Diff(before, env.MSUF_DB), calls, Gates(page))
        if not F.Equal(before, env.MSUF_DB) then
            Check(M.Undo() and F.Equal(before, env.MSUF_DB), "undo " .. path)
            Check(M.Redo(), "redo " .. path)
        end
        M.ClearHistory()
        before = F.CopySnapshot(env.MSUF_DB)
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        Input(widget, value)
        Check(F.Equal(before, env.MSUF_DB) and not M.Undo(), "combat command refusal " .. path)
        core.Util.InCombat("PLAYER_REGEN_ENABLED")
    end
    local function SectionActions(page, mode, observer)
        local observations = observer or semantic
        for id, section in pairs(M.cache[page].sections) do
            local action = cfg.sections[id] and section._msuf2CollapsibleEntry._msuf2SectionActions
            if action then
                local popup = action._msuf2GetSectionPopup()
                if popup and popup:IsShown() then action:Click() end
                action:Click()
                popup = Check(action._msuf2GetSectionPopup(), "section popup " .. id)
                local labels, selector = {}, nil
                for _, widget in ipairs(mw.world.widgets.frames) do
                    if widget:GetParent() == popup then
                        local label = widget._msuf2Label and widget._msuf2Label:GetText()
                        if label then labels[label] = widget end
                        if widget.SetOnValueChanged and widget.SetValues then selector = widget end
                    end
                end
                Add("behavior", page, "popup:" .. id, "targets",
                    selector and (selector.GetValues and selector:GetValues() or selector.values or selector._msuf2Values) or {})
                local reset = labels["Reset section"]
                if reset then
                    M.ClearHistory()
                    if mode then
                        observations.PrepareReset(page, env, function(widget) return SectionOf(widget, M.cache[page]) == id end, mode == "missing")
                        observations.Snapshot(page, "reset-" .. mode .. ":before:" .. id,
                            function(widget) return SectionOf(widget, M.cache[page]) == id end)
                    end
                    local before = F.CopySnapshot(env.MSUF_DB)
                    core.Util.InCombat("PLAYER_REGEN_DISABLED")
                    reset:Click()
                    Check(F.Equal(before, env.MSUF_DB) and not M.Undo(), "section reset combat " .. id)
                    core.Util.InCombat("PLAYER_REGEN_ENABLED")
                    calls = {}
                    reset:Click()
                    if mode then
                        observations.Snapshot(page, "reset-" .. mode .. ":after:" .. id,
                            function(widget) return SectionOf(widget, M.cache[page]) == id end)
                    else
                        Add("behavior", page, "reset:" .. id, "result", Diff(before, env.MSUF_DB), calls)
                    end
                    if not F.Equal(before, env.MSUF_DB) then
                        if mode then
                            local undone = M.Undo()
                            observations.Add("reset-undo", page, mode, id, undone, F.Equal(before, env.MSUF_DB), Encode(Diff(before, env.MSUF_DB)))
                        else
                            Check(M.Undo() and F.Equal(before, env.MSUF_DB), "section reset undo " .. id)
                        end
                        if mode then observations.Add("reset-redo", page, mode, id, M.Redo())
                        else Check(M.Redo(), "section reset redo " .. id) end
                    end
                end
                Check(popup._msuf2CopySection("invalid") == false, "copy unsupported destination " .. id)
                Add("behavior", page, "copy:" .. id, "invalid", {})
                if labels["x"] then labels["x"]:Click() end
            end
        end
    end
    local api = { M = M, env = env, core = core, mw = mw, Record = Record, Find = Find, Input = Input, Edit = Edit, Add = Add,
        Check = Check }
    for _, unit in ipairs(cfg.units or UNITS) do
        local page = "uf_" .. unit
        if M.pages[page] then
            Check(mw:Select(page), "select " .. page)
            Record(page, "cold")
            mw:Select("home")
            mw:Select(page)
            Record(page, "warm")
            if cfg.states then cfg.states(api, unit, page) end
            for _, edit in ipairs(cfg.edits or {}) do
                if not edit.units or edit.units[unit] then Edit(page, edit[1], edit[2]) end
            end
            if cfg.behavior then cfg.behavior(api, unit, page) end
            SectionActions(page)
            Record(page, "edited")
        else
            Add("absent", page, "page", unit)
        end
    end
    table.sort(lines)
    local ids = {}
    for i, line in ipairs(lines) do ids[line] = i end
    local states = {}
    for group, rows in pairs(groups) do
        local members = {}
        for line in pairs(rows) do members[#members + 1] = ids[line] end
        table.sort(members)
        states[#states + 1] = "state\t" .. group .. "\t" .. table.concat(members, ",")
    end
    table.sort(states)
    local result = table.concat(lines, "\n") .. "\n" .. table.concat(states, "\n") .. "\n"
    -- Extra scenarios run after the original receipt has been finalized, retaining every old row and state index.
    for _, unit in ipairs(cfg.units or UNITS) do
        local page = "uf_" .. unit
        if M.pages[page] then
            Check(mw:Select(page), "semantic select " .. page)
            Expand(page)
            semantic.Probe(page, env, function(widget) return SectionOf(widget, M.cache[page]) end, Check)
            mw:RunTimers()
            SectionActions(page, "missing")
            SectionActions(page, "customized")
        else
            semantic.Add("absent", page)
        end
    end
    local name = area .. "-" .. flavor .. ".tsv"
    local directory = captureOutput or (root .. "/tools/fixtures/menu-section-parent")
    local path = directory .. "/" .. name
    local semanticPath = directory .. "/semantics/" .. name
    local semanticResult = semantic.Result()
    -- New observations happen after every historical receipt is finalized.
    for _, unit in ipairs(cfg.units or UNITS) do
        local page = "uf_" .. unit
        if M.pages[page] then
            Check(mw:Select(page), "parent semantic select " .. page)
            Expand(page)
            gaps.Probe(page, env, function(widget) return SectionOf(widget, M.cache[page]) end, Check)
            mw:RunTimers()
            SectionActions(page, "missing", gaps)
            SectionActions(page, "customized", gaps)
        else gaps.Add("absent", page) end
    end
    local gapPath = directory .. "/gaps/" .. name
    local gapResult = gaps.Result()
    if sharedParent then
        io.write("SHARED_PARENT_RECEIPT\n", result, "END_SHARED_PARENT_RECEIPT\n")
        return
    end
    if cfg.capture then
        assert(not Read(path), "section receipts are immutable once captured: " .. path)
        Write(path, result)
        assert(not Read(semanticPath), "semantic receipts are immutable once captured")
        Write(semanticPath, semanticResult)
        assert(not Read(gapPath), "parent gap receipts are immutable once captured")
        Write(gapPath, gapResult)
        Write(directory .. "/layouts/" .. area .. "-" .. flavor .. "-layout.tsv", table.concat(widgetRows, "\n") .. "\n")
    else
        local provenance = assert(loadfile(directory .. "/provenance.lua"), "missing authentic section provenance")()
        assert(provenance.base == "096d5e0e0ffc2c386189932cecb946435db09bc3", "incorrect pre-schema source base")
        local gapExpected = assert(Read(gapPath), "missing authentic parent gap receipt")
        assert(provenance.receipts["gaps/" .. name] == Digest(gapExpected), "parent gap receipt lost provenance")
        if gapResult ~= gapExpected then
            Write(root .. "/.checks/" .. area .. "-" .. flavor .. "-gaps-actual.tsv", gapResult)
            error("section parent storage/fallback/reset observations drifted: " .. area .. " " .. flavor)
        end
        local expected = assert(Read(path), "missing section receipt " .. path)
        local semanticExpected = assert(Read(semanticPath), "missing authentic semantic receipt")
        assert(provenance.receipts[name] == Digest(expected), "original section receipt lost provenance")
        assert(provenance.receipts["semantics/" .. name] == Digest(semanticExpected), "semantic receipt lost provenance")
        if semanticResult ~= semanticExpected then
            Write(root .. "/.checks/" .. area .. "-" .. flavor .. "-semantics-actual.tsv", semanticResult)
            error("section defaults/reset/alignment drifted from authentic original builders: " .. area .. " " .. flavor)
        end
        if integrated then
            -- Compare the authentic pre-schema builder under the same current widgets and scenes.
            -- Every original control, layout row, behavior and state remains in this comparison;
            -- shared finite motion is observed on both sides rather than erased or recaptured.
            local command = '"' .. assert(arg[-1]) .. '" "' .. root .. '/tools/tests/menu_' .. area
                .. '_inventory_smoke.lua" "' .. root .. '" ' .. flavor .. ' --shared-parent'
            if package.config:sub(1, 1) == "\\" then command = '"' .. command .. '"' end
            local pipe = assert(io.popen(command, "r"))
            local output = pipe:read("*a"):gsub("\r\n", "\n")
            pipe:close()
            expected = assert(output:match("^SHARED_PARENT_RECEIPT\n(.*)END_SHARED_PARENT_RECEIPT\n$"),
                "authentic shared-parent replay failed: " .. output)
        end
        if result ~= expected then
            Write(root .. "/.checks/" .. area .. "-" .. flavor .. "-actual.tsv", result)
            Write(root .. "/.checks/" .. area .. "-" .. flavor .. "-actual-layout.tsv", table.concat(widgetRows, "\n") .. "\n")
            error("section inventory drifted from the pre-schema receipt: " .. area .. " " .. flavor)
        end
    end
    print("menu_" .. area .. "_inventory_smoke " .. flavor .. ": " .. #lines .. " receipt rows, " .. assertions .. " assertions OK")
end
return Parity

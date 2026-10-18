-- Lean replay of the actual parent builders and the replacing rows.
-- Native rendering is outside this fixture; input, profile, apply and history are real.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
assert(({ Mainline = true, Forever = true, Vanilla = true, TBC = true, Mists = true })[flavor], "unsupported client")
local parentBlobs = {
    "89a22e91eb7374836d8d63508662e14f70c717f0",
    "8a37e2bce876c951ac15eec4783bbe1cd341a504",
}
local candidateSource = arg[3] -- Isolated candidate mutations; the parent stays pinned.
local paths = {
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua",
}
local function Write(path, text)
    local f = assert(io.open(path, "wb")); f:write(text); f:close()
end
assert(not root:find('["%%\r\n]'), "unsafe repository path")
local parents = {}
local parentDir = root .. "/.checks/unitsections-parent-" .. flavor .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages"
if package.config:sub(1, 1) == "\\" then
    os.execute('if not exist "' .. parentDir:gsub("/", "\\") .. '" mkdir "' .. parentDir:gsub("/", "\\") .. '"')
else os.execute("mkdir -p '" .. parentDir:gsub("'", "'\\''") .. "'") end
for i, path in ipairs(paths) do
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. parentBlobs[i], "r"))
    local source = pipe:read("*a"); pipe:close()
    assert(#source > 1000, "missing authentic parent source " .. path)
    parents[path:match("[^/]+$")] = parentDir .. "/" .. path:match("[^/]+$")
    Write(parents[path:match("[^/]+$")], source)
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Encode(v, seen)
    if type(v) == "function" then return "<function>" end
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    if v.GetObjectType then return "<widget>" end
    seen = seen or {}; if seen[v] then return "<cycle>" end; seen[v] = true
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Encode(k) .. "=" .. Encode(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
-- Fixture snapshots copy every field without repeatedly validating the same
-- factory profile. Production history retains its real validated snapshot path.
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end
local sections = { frame_basics = true, anchoring = true, inline_text = true,
    load_conditions = true, boss_layout = true, arena_layout = true, boss_target_highlight = true }
local function Replay(parent)
    local calls, tips = {}, {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                local prior = parents[path:match("[^/\\]+$")]
                if prior and not parent and candidateSource then path = candidateSource .. "/" .. path:match("[^/\\]+$") end
                return load(self, parent and prior or path, ...)
            end
            world.widgets.Methods.GetCenter = function() return 500, 500 end
            for _, key in ipairs({ "Rows", "Columns", "Frames", "FrameWidth", "FrameHeight" }) do
                world.widgets.Methods["SetFlipBook" .. key] = function() end
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    local F = core.ProfileFields
    local function Restore(snapshot)
        for _, edit in ipairs(F.Diff(env.MSUF_DB, snapshot)) do
            if edit.remove then F.Write(env.MSUF_DB, edit.path, nil)
            else F.Write(env.MSUF_DB, edit.path, Copy(edit.value)) end
        end
    end
    core.ProfileRuntime.Apply = function() end
    core.MSUF_ApplyGameplayVisuals = function() end
    -- Keep each explicit edge-state root in place after the normal initial boot.
    env.MSUF_InitProfiles = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    local factory = assert(F.CopySnapshot(env.MSUF_DB))
    core.MSUF_CreateFactoryDefaultProfile = function() return Copy(factory) end
    for _, name in ipairs({ "RequestUnitDomains", "RequestOrRefresh", "RequestRefresh", "Refresh" }) do
        local fn = M[name]
        M[name] = function(...)
            local args = { ... }
            if type(args[1]) == "table" then args[1] = args[1].key end
            calls[#calls + 1] = { name, args }
            return fn(...)
        end
    end
    env.GameTooltip.SetText = function(_, ...) tips[#tips + 1] = { ... } end
    env.GameTooltip.AddLine = function(_, ...) tips[#tips + 1] = { ... } end
    env.GameTooltip.SetOwner = function() end
    env.GameTooltip.Show, env.GameTooltip.Hide = function() end, function() end
    local result, edits = {}, 0
    local function Row(...)
        local values = {}
        for i = 1, select("#", ...) do values[i] = Encode((select(i, ...))) end
        result[#result + 1] = table.concat(values, "\t")
    end
    local sharedPopups, sharedAnchors, sharedWidgets = {}, {}, {}
    local Shared = M.UnitSectionsShared
    local makePopup, makeAnchor = Shared.MakeScopeCopyPopup, Shared.CustomAnchorEditor
    Shared.MakeScopeCopyPopup = function(anchor, opts)
        local api = makePopup(anchor, opts)
        sharedPopups[#sharedPopups + 1] = { api, opts, anchor }
        return api
    end
    Shared.CustomAnchorEditor = function(ctx, parentFrame, opts)
        local editor = makeAnchor(ctx, parentFrame, opts)
        sharedAnchors[#sharedAnchors + 1] = { editor, opts, ctx }
        return editor
    end
    for _, name in ipairs({ "CreateSectionNotice", "TextCard", "PreviewText", "MakeDragSortRows" }) do
        local create = Shared[name]
        Shared[name] = function(...)
            local values = { create(...) }
            for _, w in ipairs(values) do sharedWidgets[#sharedWidgets + 1] = { name, w } end
            return unpack(values)
        end
    end
    local topSections = {}
    local function Section(widget, entry)
        while widget do
            if widget == topSections[entry] then return "top_actions" end
            for id, sec in pairs(entry.sections or {}) do
                if sections[id] and (widget == sec or widget == sec._msuf2CollapsibleEntry.header) then return id end
            end
            widget = widget.GetParent and widget:GetParent()
        end
    end
    local function Controls(page)
        local out = {}
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if record.pageKey == page and record.controlId:find("navigation.unit_page.selector", 1, true) then
                topSections[M.cache[page]] = M.RuntimeControlCatalog.Get(record.controlId).widget:GetParent()
            end
        end
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local widget = M.RuntimeControlCatalog.Get(record.controlId).widget
            if record.pageKey == page and widget and Section(widget, M.cache[page]) then
                out[#out + 1] = { record, widget }
            end
        end
        table.sort(out, function(a, b) return a[1].controlId < b[1].controlId end)
        return out
    end
    local function Gates(controls)
        local out = {}
        for _, pair in ipairs(controls) do
            local r, w = unpack(pair)
            local command = w._msuf2CommandAction
            out[r.controlId] = { w:IsEnabled(), w:IsShown(), command and command.get and command.get() }
        end
        return out
    end
    local function Input(w, kind, value)
        if kind == "toggle" then w:SetChecked(value); w:Click()
        elseif kind == "slider" then w:SetValue(value); World.FireScript(w, "OnValueChanged", value)
        elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
        elseif kind == "textinput" then
            if w._msuf2OnCommit then w._msuf2OnCommit(value)
            else w:SetText(value); World.FireScript(w, "OnEnterPressed") end
        elseif kind == "segment" then
            for _, button in ipairs(w.buttons) do if button._msuf2Value == value then button:Click() end end
        end
        mw:RunTimers()
    end
    local function Values(r, w)
        if r.controlId:find("navigation.unit_page.selector", 1, true) then return end
        if r.kind == "toggle" then return { true, false } end
        if r.kind == "slider" then local lo, hi = w:GetMinMaxValues(); return { lo, math.min(hi, lo + (w.valueStep or 1) * 3) } end
        if r.kind == "textinput" and (w._msuf2OnCommit or w:GetScript("OnEnterPressed")) then return { "::", "" } end
        if r.kind == "dropdown" or r.kind == "segment" then
            local values = w.GetValues and w:GetValues() or w.values
            if type(values) == "function" then values = values() end
            local out = {}
            for _, item in ipairs(values or {}) do
                if not item.disabled then out[#out + 1] = item.value end
            end
            if #out > 0 then return { out[1], out[#out] } end
        end
    end
    local function Snapshot(page, controls)
        local names = {}
        local function Name(w)
            if not w then return "root" end
            if names[w] then return names[w] end
            local label = type(w.text) == "string" and w.text or ""
            names[w] = Name(w:GetParent()) .. "/" .. w:GetObjectType() .. ":" .. label
            return names[w]
        end
        local layout = {}
        local function Geometry(w)
            local points = {}
            for i = 1, w:GetNumPoints() do
                local a, p, b, x, y = w:GetPoint(i)
                points[#points + 1] = { a, Name(p), b, x, y }
            end
            layout[#layout + 1] = Encode({ Name(w), w:GetWidth(), w:GetHeight(), points, w:IsShown(), w:IsEnabled() })
            for _, region in ipairs(w.regions or {}) do Geometry(region) end
        end
        for _, w in ipairs(mw.world.widgets.frames) do
            if Section(w, M.cache[page]) then Geometry(w) end
        end
        table.sort(layout); Row("layout", page, layout)
        for _, pair in ipairs(controls) do
            local r, w = unpack(pair)
            tips = {}; if w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
            local low, high; if r.kind == "slider" then low, high = w:GetMinMaxValues() end
            Row("control", page, r, w._msuf2SearchMeta, low, high, w.valueStep,
                w.GetValues and w:GetValues() or w.values, tips, w:GetPoint(), w:GetWidth(), w:GetHeight())
            if not parent and w._msuf2CommandAction and Values(r, w) then
                local declaration = assert(w._msuf2ControlSchema, "undeclared control " .. r.controlId)
                assert(declaration.id == r.controlId, "declaration identity " .. r.controlId)
                assert(declaration.scope == page:match("^uf_(.+)$"), "declaration scope " .. r.controlId)
            end
        end
        Row("gates", page, Gates(controls))
    end
    for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
        local page = "uf_" .. unit
        if M.pages[page] then
            assert(mw:Select(page))
            local entry = M.cache[page]
            local ids = {}; for id in pairs(entry.sections) do if sections[id] then ids[#ids + 1] = id end end; table.sort(ids)
            for _, id in ipairs(ids) do entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            mw:RunTimers(); M.Refresh(entry.ctx); mw:RunTimers()
            local controls = Controls(page)
            Snapshot(page, controls)
            local picker = env.CreateFrame("Frame", nil, env.UIParent)
            env.MSUF_EnsureAnchorPicker = function() return picker end
            for _, suffix in ipairs({ ".anchoring.custom.pick", ".anchoring.custom.clear", ".basics.enable_now" }) do
                for _, pair in ipairs(controls) do
                    local r, w = unpack(pair)
                    if r.controlId:sub(-#suffix) == suffix then
                        M.ClearHistory(); local before = Copy(env.MSUF_DB); calls = {}
                        w:Click()
                        if suffix:find("pick", 1, true) and picker._onPick then picker._onPick("ParentProbeAnchor") end
                        Row("action", r.controlId, F.Diff(before, env.MSUF_DB), calls)
                        Row("action-undo", r.controlId, M.Undo(), F.Diff(before, env.MSUF_DB))
                    end
                end
            end
            for _, pair in ipairs(controls) do
                local r, w = unpack(pair)
                local values = Values(r, w)
                if values then
                    for state, value in ipairs(values) do
                        local initial = Copy(env.MSUF_DB)
                        if state == 2 then
                            local scope, key = (r.settingKey or ""):match("^([^.]+)%.([^.]+)$")
                            if scope and type(env.MSUF_DB[scope]) == "table" then
                                local prior = env.MSUF_DB[scope][key]
                                local edgeToggle = r.kind == "toggle" and w._msuf2CommandAction and not w._msuf2CommandAction.get()
                                env.MSUF_DB[scope][key] = type(prior) == "number" and 0 or type(prior) == "string" and "" or false
                                if r.kind == "toggle" and w._msuf2CommandAction then
                                    env.MSUF_DB[scope][key] = edgeToggle
                                end
                                if key == "smoothFill" then env.MSUF_DB[scope].chunkedFill = true end
                                if key == "chunkedFill" then env.MSUF_DB[scope].smoothFill = true end
                            end
                            if r.controlId:find("anchoring.anchor_point", 1, true) then env.MSUF_DB[unit].point = "INVALID" end
                            if r.controlId:find("anchoring.anchor_to", 1, true) then env.MSUF_DB[unit].anchorToUnitframe = "LegacyCustomAnchor" end
                            if key ~= "enabled" or scope ~= unit then env.MSUF_DB[unit].enabled = true end
                            if env.MSUF_DB.focus then env.MSUF_DB.focus.enabled = true end
                            env.MSUF_DB.targettarget.showToTInTargetName = true
                            if r.kind == "textinput" then env.MSUF_DB.targettarget.totInlineSeparator = "__CUSTOM__" end
                            M.Refresh(entry.ctx); mw:RunTimers()
                        end
                        Row("before", r.controlId, state, Gates(controls))
                        -- Each real input starts from the same state in both worlds. Restore
                        -- through Undo after probing, so disabling a frame cannot hide later inputs.
                        M.ClearHistory()
                        local before = Copy(env.MSUF_DB)
                        calls = {}; Input(w, r.kind, value)
                        local after = Copy(env.MSUF_DB)
                        Row("input", r.controlId, state, F.Diff(before, after), calls, Gates(controls))
                        local undo = M.Undo(); mw:RunTimers()
                        Row("undo", r.controlId, state, undo, F.Diff(before, env.MSUF_DB))
                        if undo then
                            local redo = M.Redo(); mw:RunTimers()
                            Row("redo", r.controlId, state, redo, F.Diff(after, env.MSUF_DB))
                            -- Undo and Redo have both been observed. Restore the fixture
                            -- root directly instead of applying the entire profile a third time.
                            Restore(before)
                            M.Refresh(entry.ctx); mw:RunTimers()
                        end
                        M.ClearHistory(); before = Copy(env.MSUF_DB)
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        calls = {}; Input(w, r.kind, value)
                        Row("combat", r.controlId, state, F.Diff(before, env.MSUF_DB), calls)
                        core.Util.InCombat("PLAYER_REGEN_ENABLED")
                        Row("combat-history", r.controlId, state, M.Undo())
                        Restore(initial)
                        M.Refresh(entry.ctx); mw:RunTimers()
                        edits = edits + 1
                    end
                end
            end
            -- Shared section popup: actual lazy controls, destination callback,
            -- reset/copy, refusal, and history, including the absent-field reset case.
            local sec = entry.sections.frame_basics
            local action = sec._msuf2CollapsibleEntry._msuf2SectionActions
            action:Click(); local popup = assert(action._msuf2GetSectionPopup())
            for _, w in ipairs(mw.world.widgets.frames) do
                if w:GetParent() == popup and w.SetOnValueChanged and w.SetValues then
                    Row("section-targets", page, w.GetValues and w:GetValues() or w.values)
                end
            end
            local sectionInitial = Copy(env.MSUF_DB)
            local color
            for _, pair in ipairs(controls) do
                local r, w = unpack(pair)
                if r.settingKey == unit .. ".enabled" and not w:GetChecked() then Input(w, r.kind, true) end
                if r.settingKey == unit .. ".healthColorMode" then color = w end
            end
            assert(color, "missing real section input " .. page)
            Input(color, "dropdown", "dark")
            assert(env.MSUF_DB[unit].healthColorMode == "dark", "section seed input refused " .. page)
            local destination = unit == "player" and "target" or "player"
            for _, target in ipairs({ destination, "invalid" }) do
                popup:Hide()
                action:Click()
                M.ClearHistory()
                local before = Copy(env.MSUF_DB)
                calls = {}
                local ok = popup._msuf2CopySection(target)
                local changes = F.Diff(before, env.MSUF_DB)
                local history = M.GetHistoryState()
                Row("section-copy", page, target, ok, changes, calls, history.undoCount, history.undoLabel)
                local undo = M.Undo()
                mw:RunTimers()
                Row("section-copy-undo", page, target, undo, F.Diff(before, env.MSUF_DB))
                if target == destination then
                    assert(ok and #changes > 0, "section copy made no change " .. page)
                    -- The history owner also settles an unrecorded change, but under its own label.
                    assert(history.undoCount == 1 and history.undoLabel == "Copy section" and undo,
                        "section copy history missing " .. page)
                    assert(#F.Diff(before, env.MSUF_DB) == 0, "section copy undo did not restore " .. page)
                else assert(not ok and not undo and #changes == 0, "invalid section copy accepted " .. page) end
            end
            popup:Hide()
            action:Click()
            M.ClearHistory()
            local before = Copy(env.MSUF_DB)
            core.Util.InCombat("PLAYER_REGEN_DISABLED")
            Row("section-copy-refused", page, popup._msuf2CopySection(destination), F.Diff(before, env.MSUF_DB))
            Row("section-reset-refused", page, popup._msuf2ResetSection(), F.Diff(before, env.MSUF_DB))
            core.Util.InCombat("PLAYER_REGEN_ENABLED")
            calls = {}
            local reset = popup._msuf2ResetSection()
            local changes = F.Diff(before, env.MSUF_DB)
            local history = M.GetHistoryState()
            Row("section-reset", page, reset, changes, calls, history.undoCount, history.undoLabel)
            local undo = M.Undo()
            mw:RunTimers()
            Row("section-reset-undo", page, undo, F.Diff(before, env.MSUF_DB))
            assert(reset and #changes > 0, "section reset made no change " .. page)
            assert(history.undoCount == 1 and history.undoLabel == "Reset section" and undo,
                "section reset history missing " .. page)
            assert(#F.Diff(before, env.MSUF_DB) == 0, "section reset undo did not restore " .. page)
            popup:Hide()
            Restore(sectionInitial)
            M.Refresh(entry.ctx)
            mw:RunTimers()
            for _, pair in ipairs(controls) do
                local r, w = unpack(pair)
                if r.controlId:find("navigation.unit_page.selector", 1, true) then
                    for _, button in ipairs(w.buttons) do
                        button:Click()
                        mw:RunTimers()
                        Row("top-navigation", page, button._msuf2Value, M.activeKey, w:GetValue())
                        assert(M.activeKey == "uf_" .. button._msuf2Value, "unit navigation refused")
                        assert(mw:Select(page))
                    end
                elseif r.controlId:find("copy.open", 1, true) then
                    for _, item in ipairs(sharedPopups) do
                        if item[3] == w then
                            for _, combat in ipairs({ false, true }) do
                                M.ClearHistory()
                                local initial = Copy(env.MSUF_DB)
                                if combat then core.Util.InCombat("PLAYER_REGEN_DISABLED") end
                                w:Click()
                                local copyPopup = assert(item[1].GetPopup(), "Copy To did not create popup")
                                Row("top-copy-open", page, combat, copyPopup:IsShown(), F.Diff(initial, env.MSUF_DB))
                                assert(copyPopup:IsShown(), "Copy To did not open popup")
                                if combat then core.Util.InCombat("PLAYER_REGEN_ENABLED") end
                                Row("top-copy-open-undo", page, M.Undo())
                                item[1].Hide()
                            end
                        end
                    end
                end
            end
        else Row("absent", page) end
    end
    -- Build every other owner of these shared helpers. Their pages retain their
    -- own controllers; only shared widget observations and inputs are replayed.
    for _, page in ipairs({ "uf_player", "gf_layout", "gf_bars", "gf_indicators", "gf_priority", "classpower", "swingtimers", "opt_bars" }) do
        if M.pages[page] then
            assert(mw:Select(page))
            local entry = M.cache[page]
            local ids = {}; for id in pairs(entry.sections or {}) do ids[#ids + 1] = id end; table.sort(ids)
            for _, id in ipairs(ids) do entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            mw:RunTimers(); M.Refresh(entry.ctx); mw:RunTimers()
            Row("consumer", page)
        end
    end
    for i, item in ipairs(sharedWidgets) do
        local name, w = unpack(item)
        Row("shared-widget", i, name, w:GetObjectType(), w.text, w:GetWidth(), w:GetHeight(), w:IsShown(), w:IsEnabled())
    end
    for i, item in ipairs(sharedAnchors) do
        local editor, opts, ctx = unpack(item)
        if not parent then
            assert(editor.box._msuf2ControlSchema.kind == "customAnchor", "anchor editor declaration " .. tostring(opts.controlDomain))
        end
        -- Unit editors were already driven through their real page controls above.
        if opts.controlDomain ~= "unit" then
        for _, value in ipairs({ "ScopedAnchorProbe", "" }) do
            M.ClearHistory(); local before = Copy(env.MSUF_DB); calls = {}
            Input(editor.box, "textinput", value); editor.Refresh()
            Row("shared-anchor", i, ctx.key, value, editor.box:GetText(), F.Diff(before, env.MSUF_DB), calls)
            Row("shared-anchor-undo", i, M.Undo(), F.Diff(before, env.MSUF_DB))
        end
        end
    end
    for i, item in ipairs(sharedPopups) do
        local api, opts = unpack(item)
        api.Show(); local popup = api.GetPopup()
        if not parent then
            -- A caller's own declaration is the only one applied; the shared one is its fallback.
            local domain = ({ unit = "copy", group = "copy", swing = "copyNavigation" })[opts.controlDomain] or "shared"
            local scope = opts.controlDomain == "unit" and opts.controlPageKey:match("^uf_(.+)$") or opts.controlDomain
            for _, cb in ipairs(popup._checks) do
                if cb._msuf2RuntimeControlRecord then
                    local declaration = assert(cb._msuf2ControlSchema, "copy popup control undeclared")
                    assert(declaration.applyDomain == domain and declaration.owner == cb,
                        "copy popup declaration " .. tostring(opts.controlDomain))
                    assert(declaration.scope == scope, "copy popup scope " .. tostring(opts.controlDomain))
                end
            end
        end
        for _, value in ipairs({ true, false }) do
            for j, cb in ipairs(popup._checks) do
                cb:SetChecked(value); cb:Click()
                Row("caller-category", i, opts.controlDomain, j, value, opts.scopes)
            end
        end
        M.ClearHistory(); local before = Copy(env.MSUF_DB); calls = {}
        if popup._runBtn then popup._runBtn:Click() end
        Row("caller-copy", i, opts.controlDomain, F.Diff(before, env.MSUF_DB), calls)
        Row("caller-copy-undo", i, M.Undo(), F.Diff(before, env.MSUF_DB))
        api.Hide()
    end
    -- Every shared copy-popup caller retains the same independent menu-state
    -- controls. Use the production helper with two scopes to expose late reads.
    local scopes, source, target = { layout = true, text = false }, "player", "target"
    local anchor = M.Theme.Button(env.UIParent, "Copy", 80, 24)
    local api = Shared.MakeScopeCopyPopup(anchor, { scopes = scopes,
        categories = { { key = "layout", label = "Layout" }, { key = "text", label = "Text", description = "Text settings" } },
        targets = { "player", "target" }, sourceKey = function() return source end,
        selectedTarget = function() return target end, onTargetClick = function(key) target = key end,
        runLabel = "Copy Selected", onRun = function() Row("copy-run", source, target, scopes) end })
    for _, nextSource in ipairs({ "player", "target" }) do
        source = nextSource; api.Show(); local popup = api.GetPopup(); api.Refresh()
        for _, cb in ipairs(popup._checks) do cb:SetChecked(not cb:GetChecked()); cb:Click() end
        for _, key in ipairs({ "player", "target" }) do popup._targetBtns[key]:Click() end
        popup._runBtn:Click(); Row("copy-state", source, target, scopes); api.Hide()
        for _, label in ipairs({ "All", "None", "x" }) do
            api.Show()
            for _, w in ipairs(mw.world.widgets.frames) do
                if w:GetParent() == popup and w._msuf2Label and w._msuf2Label:GetText() == label then
                    w:Click(); Row("copy-button", source, label, scopes, popup:IsShown())
                end
            end
            api.Hide()
        end
    end
    assert(edits > 80, "incomplete control replay")
    -- Coverage assertions must also reject an incomplete replay of the parent.
    local required = { ["top-navigation"] = false, ["top-copy-open"] = false,
        ["section-copy-undo"] = false, ["section-reset-undo"] = false }
    for _, row in ipairs(result) do
        local kind = row:match("^string:([^\t]+)")
        if required[kind] ~= nil then
            required[kind] = required[kind] or not kind:find("undo", 1, true)
                or row:find("boolean:true", 1, true) ~= nil
        end
    end
    local missing = {}
    for kind, observed in pairs(required) do
        if not observed then missing[#missing + 1] = kind end
    end
    table.sort(missing)
    assert(#missing == 0, "incomplete action replay: " .. table.concat(missing, ", "))
    return result, edits
end
local expected, count = Replay(true)
local actual, actualCount = Replay(false)
assert(actualCount == count, "control count changed")
Write(root .. "/.checks/unitsections-" .. flavor .. "-parent.tsv", table.concat(expected, "\n"))
Write(root .. "/.checks/unitsections-" .. flavor .. "-actual.tsv", table.concat(actual, "\n"))
assert(#actual == #expected, "observation count changed")
for i, row in ipairs(expected) do assert(actual[i] == row, "unitsections parity " .. flavor .. " row " .. i .. ": " .. row:sub(1, 230)) end
print("menu_unitsections_parity_smoke " .. flavor .. ": " .. count .. " inputs, " .. #actual .. " parent observations OK")

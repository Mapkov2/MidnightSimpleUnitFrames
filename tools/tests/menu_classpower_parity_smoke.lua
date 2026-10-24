-- Lean replay of the authentic pre-conversion page and the replacing rows.
-- Native rendering is a fixture boundary; input, history and page owners are real.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local candidate = arg[3]
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"
local workspaceTarget = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_ClassPowerWorkspace.lua"
local parent = root .. "/.checks/classpower-parent-" .. flavor .. ".lua"
local parentWorkspace = root .. "/.checks/classpower-parent-workspace-" .. flavor .. ".lua"
-- The authentic old page still needs the workspace adapters it originally used.
for _, fixture in ipairs({
    { parent, "9ec540936b684c7e5eb244daee97890f60db0c7d", "function Page:CreateControlKinds()" },
    { parentWorkspace, "de0a2267f8ab96ccd59b68bbf4c1a36798a159f7", "function Workspace.BindBoolWidget(" },
}) do
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. fixture[2], "r"))
    local original = pipe:read("*a")
    pipe:close()
    assert(original:find(fixture[3], 1, true), "authentic parent unavailable")
    local file = io.open(fixture[1], "wb")
    if not file then
        os.execute('mkdir "' .. root .. '/.checks"')
        file = assert(io.open(fixture[1], "wb"))
    end
    file:write(original)
    file:close()
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Encode(value, seen)
    if type(value) == "function" then return "function" end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget" end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys, out = {}, {}
    -- Catalog cache revisions contain the command table's VM address; all
    -- public metadata and the command itself are compared separately.
    for key in pairs(value) do if key ~= "_revisionKey" then keys[#keys + 1] = key end end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key) .. "=" .. Encode(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Diff(a, b, path, out)
    path, out = path or "", out or {}
    if type(a) == "table" and type(b) == "table" then
        local keys = {}
        for key in pairs(a) do keys[key] = true end
        for key in pairs(b) do keys[key] = true end
        for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), out) end
    elseif Encode(a) ~= Encode(b) then out[path] = { Encode(a), Encode(b) } end
    return out
end
local function Replay(path, converted)
    local calls = {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
        local load = world.LoadFile
        world.LoadFile = function(self, name, ...)
            if name:sub(-#target) == target then
                -- Direct runtime fan-out is a native-rendering boundary: the recorders are in place
                -- before the page loads, because the current page binds these providers when it loads.
                for _, recorded in ipairs({ "MSUF_ApplyModules", "MSUF_ClassPower_Apply", "MSUF_UFPreview_RequestRefresh",
                    "MSUF_EnsureCooldownWidthObservers" }) do
                    world.env[recorded] = function(...) calls[#calls + 1] = { recorded, ... } end
                end
                name = path
                -- The authentic parent reads these three shape normalizers as globals when it loads;
                -- the client now keeps them in the namespace registry, so the replay publishes them.
                if not converted then
                    for _, global in ipairs({ "MSUF_UF_NormalizeShapeAlign", "MSUF_UF_NormalizeDetachedPowerShape",
                        "MSUF_UF_NormalizePlayerHPShape" }) do
                        if rawget(world.env, global) == nil then world.env[global] = world.core.PublicGlobals[global] end
                    end
                end
            elseif not converted and name:sub(-#workspaceTarget) == workspaceTarget then name = parentWorkspace end
            return load(self, name, ...)
        end
        world.widgets.Methods.GetCenter = function(frame)
            return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
        end
    end })
    local M, env, core = mw.M, mw.env, mw.core
    local declarations, schema = {}, M.ControlSchema
    local sectionOwner, settingOwner = schema.Section, schema.Bind
    local borrowedId = "menu2.classpower.section.classpower_resource_visibility.expanded"
    local settingKeys = {
        ["menu2.classpower.advanced.layout.shape.alignment"] = "alignment",
        ["menu2.classpower.advanced.detached.power.text.outline"] = "outline",
        ["menu2.classpower.advanced.detached.power.text.slot.selector"] = "slot",
    }
    local function Capture(widget)
        local spec = widget._msuf2ControlSchema
        declarations[spec.id] = { widget = widget, spec = spec, snapshot = Encode(spec) }
    end
    if converted then
        schema.Section = function(section, scope)
            local result = sectionOwner(section, scope)
            local header = section._msuf2CollapsibleEntry.header
            if scope == "bars" and header._msuf2ControlSchema.id == borrowedId then Capture(header) end
            return result
        end
        schema.Bind = function(ctx, widget, spec)
            local result = settingOwner(ctx, widget, spec)
            if settingKeys[spec.id] then Capture(widget) end
            return result
        end
    end
    local F, receipts = core.ProfileFields, {}
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    -- Direct runtime fan-out is a native-rendering boundary. Record its exact
    -- request rather than creating live unit frames in this menu fixture.
    for _, name in ipairs({ "MSUF_ApplyModules", "MSUF_ClassPower_Apply", "MSUF_UFPreview_RequestRefresh",
        "MSUF_EnsureCooldownWidthObservers" }) do
        env[name] = function(...) calls[#calls + 1] = { name, ... } end
    end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    for _, name in ipairs({ "RequestClassPowerDomains", "RequestUnitDomains", "RequestGeneralDomains", "RequestBarOutline" }) do
        local fn = M.ApplyService[name]
        if fn then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, ... }
            return fn(...)
        end end
    end
    local refresh = M.Refresh
    M.Refresh = function(...) calls[#calls + 1] = { "refresh" }; return refresh(...) end
    assert(mw:Select("classpower"))
    local ui, entry = M.ClassPowerWorkspace.current, M.cache.classpower
    for _, scope in ipairs({ "class", "power", "hp", "mana", "extras" }) do
        ui:Select(scope)
        local ids = {}
        for id in pairs(entry.sections) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        mw:RunTimers()
    end
    if converted then
        schema.Section, schema.Bind = sectionOwner, settingOwner
        local failures = {}
        local function Unchanged(id, scope, domain, key)
            local captured = declarations[id]
            local spec = captured and captured.widget._msuf2ControlSchema
            if not captured or spec ~= captured.spec or Encode(spec) ~= captured.snapshot
                or spec.scope ~= scope or spec.applyDomain ~= domain or spec.key ~= key then
                failures[#failures + 1] = id .. " lost its original declaration"
            end
        end
        Unchanged(borrowedId, "bars", "sectionNavigation")
        for id, key in pairs(settingKeys) do Unchanged(id, "classpower", "classpower", key) end
        table.sort(failures)
        assert(#failures == 0, table.concat(failures, "\n"))
        local tabs = assert(M.RuntimeControlCatalog.Get("menu2.classpower.advanced.style.workspace.tab")).widget
        assert(tabs._msuf2ControlSchema.applyDomain == "selection", "style tabs lost their selection owner")
        print("PASS ClassPower declaration owners " .. flavor .. ": borrowed header, three bound segments, style tabs")
    end
    local controls = {}
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local widget = M.RuntimeControlCatalog.Get(record.controlId).widget
        local command = widget and widget._msuf2CommandAction
        -- This file owns advanced settings; resource extras/preview/copy retain separate owners.
        if record.pageKey == "classpower" and record.controlId:find(".advanced.", 1, true)
            and command and command.get and command.set
            and (not record.controlId:find(".resource.extras.", 1, true)
                or record.controlId:find(".resource.extras.visibility.", 1, true)) then
            controls[#controls + 1] = widget
        end
    end
    table.sort(controls, function(a,b) return a._msuf2RuntimeControlRecord.controlId < b._msuf2RuntimeControlRecord.controlId end)
    assert(#controls >= 110, "incomplete ClassPower control inventory: " .. #controls)
    local function Add(label, ...)
        receipts[#receipts + 1] = { label, Encode({ ... }) }
    end
    local function Command(w) return w._msuf2CommandAction end
    local function Input(w, value)
        local kind = Command(w).kind
        if kind == "toggle" then w:SetChecked(value); w:Click("LeftButton")
        elseif w.buttons then
            for _, b in ipairs(w.buttons) do if b._msuf2Value == value then b:Click("LeftButton") end end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        else w:SetValue(value); World.FireScript(w, "OnValueChanged", value) end
        mw:RunTimers()
    end
    local function View(w)
        local value
        if Command(w).kind == "toggle" then value = w:GetChecked() else value = w:GetValue() end
        return { Command(w).get(), value }
    end
    local function Gates()
        local out = {}
        for _, w in ipairs(controls) do
            local label = w._msuf2Title or w._msuf2Label
            out[w._msuf2RuntimeControlRecord.controlId] = { w:IsEnabled(), w:IsShown(), label and label:GetText() }
        end
        return out
    end
    -- The preview dropdown and confirmed quick-setup button have native custom
    -- callbacks rather than setting commands. Exercise their real owners too.
    local preview, quick
    for _, w in ipairs(mw.world.widgets.frames) do
        local r = w._msuf2RuntimeControlRecord
        if r and r.controlId == "menu2.classpower.advanced.preview.resource" then preview = w end
        if r and r.controlId == "menu2.classpower.advanced.quick.setup.class.bar" then quick = w end
    end
    assert(preview and quick, "header controls missing")
    for _, state in ipairs({ "default", "edge" }) do
        local values = M.ClassPowerPreviewSpecValues
        local value = values[state == "default" and 1 or #values].value
        local before = F.CopySnapshot(env.MSUF_DB)
        calls = {}; preview._msuf2OnValueChanged(value); mw:RunTimers()
        Add("preview:" .. state, preview:GetValue(), M.GetClassPowerPreviewSpecKey(), Diff(before, env.MSUF_DB), calls)
        local prompt
        local show = M.ShowPrompt
        M.ShowPrompt = function(id, spec) prompt = { id, spec.text, spec.accept, spec.cancel, type(spec.onAccept) } end
        quick:Click("LeftButton")
        M.ShowPrompt = show
        Add("quick-confirm:" .. state, prompt, Diff(before, env.MSUF_DB))
    end
    local function Restore(snapshot)
        local db, restored = env.MSUF_DB, F.CopySnapshot(snapshot)
        for key in pairs(db) do db[key] = nil end
        for key, value in pairs(restored) do db[key] = value end
    end
    local baseline = F.CopySnapshot(env.MSUF_DB)
    for _, state in ipairs({ "default", "edge" }) do
        for _, w in ipairs(controls) do
            Restore(baseline)
            local db = env.MSUF_DB
            if state == "edge" then
                db.bars, db.player = {}, { width = 413, showPower = false, powerBarBorderEnabled = true, powerBarBorderThickness = 3 }
                db.general.hidePercentSymbol = true
                db.bars.classPowerBgAlpha = 35
                db.bars.classPowerWidthMode = "custom"
                db.bars.playerHPBarUsePlayerText = false
                db.player.powerTextCenter = "PERCENT"
                M.classPowerDetachedPowerTextSlot = "right"
            else M.classPowerDetachedPowerTextSlot = "center" end
            local r, cmd = w._msuf2RuntimeControlRecord, Command(w)
            local meta = w._msuf2SearchMeta or {}
            if meta.prepareExactSearchTarget then meta.prepareExactSearchTarget() else ui:Select("class") end
            M.Refresh(entry.ctx)
            M.ClearHistory()
            local values = w.GetValues and w:GetValues() or w.values
            if type(values) == "function" then values = values() end
            local value
            if cmd.kind == "toggle" then value = not cmd.get()
            elseif cmd.kind == "slider" then
                local low, high = w:GetMinMaxValues()
                value = state == "edge" and low or high
                if value == cmd.get() then value = state == "edge" and high or low end
            elseif cmd.kind == "dropdown" or cmd.kind == "segment" then
                for _, option in ipairs(values or {}) do
                    local v = option.value or option[1]
                    if v ~= cmd.get() then value = v; if state == "default" then break end end
                end
            end
            assert(value ~= nil, "no input for " .. r.controlId)
            if converted then assert(w._msuf2ControlSchema, "missing row " .. r.controlId) end
            local label = state .. ":" .. r.controlId
            local tips = {}
            env.GameTooltip.SetOwner = function(_, _, anchor) tips[#tips + 1] = { "owner", anchor } end
            env.GameTooltip.Show = function() tips[#tips + 1] = { "show" } end
            env.GameTooltip.Hide = function() tips[#tips + 1] = { "hide" } end
            env.GameTooltip.AddLine = function(_, ...) tips[#tips + 1] = { ... } end
            env.GameTooltip.SetText = function(_, ...) tips[#tips + 1] = { ... } end
            World.FireScript(w, "OnEnter"); World.FireScript(w, "OnLeave")
            Add(label .. ":before", r, meta, View(w), w:GetWidth(), w:GetHeight(), { w:GetPoint() }, values, tips, Gates())
            local before = F.CopySnapshot(db)
            calls = {}; Input(w, value)
            local after = F.CopySnapshot(env.MSUF_DB)
            Add(label .. ":input", value, Diff(before, after), calls, View(w), Gates())
            local undo = M.Undo(); mw:RunTimers()
            Add(label .. ":undo", undo, Diff(before, env.MSUF_DB), View(w), Gates())
            local redo = M.Redo(); mw:RunTimers()
            Add(label .. ":redo", redo, Diff(after, env.MSUF_DB), View(w), Gates())
            -- Restore the original input state so refusal must prevent a real change.
            Restore(before)
            M.Refresh(entry.ctx); M.ClearHistory()
            core.Util.InCombat("PLAYER_REGEN_DISABLED")
            env.InCombatLockdown = function() return true end
            calls = {}; Input(w, value)
            Add(label .. ":combat", Diff(before, env.MSUF_DB), calls, M.Undo())
            core.Util.InCombat("PLAYER_REGEN_ENABLED")
            env.InCombatLockdown = function() return false end
            mw:Fire("PLAYER_REGEN_ENABLED"); mw:RunTimers()
        end
    end
    Restore(baseline)
    for _, scope in ipairs({ "class", "power", "hp", "mana" }) do
        ui:Select(scope); M.ClearHistory()
        local before = F.CopySnapshot(env.MSUF_DB)
        calls = {}
        local copied = ui:Copy(scope == "class" and "hp" or "class", { size = true, appearance = true, text = true, behavior = true })
        mw:RunTimers()
        Add("copy:" .. scope, copied, Diff(before, env.MSUF_DB), calls)
        local undo = M.Undo(); mw:RunTimers()
        Add("copy-undo:" .. scope, undo, Diff(before, env.MSUF_DB))
    end
    return receipts, #controls
end
local expected, count = Replay(parent, false)
if candidate == "parent" then candidate = parent end
local actual = Replay(candidate or root .. "/" .. target, not candidate or candidate ~= parent)
assert(#actual == #expected, "receipt count changed")
local mismatches = {}
for i, row in ipairs(expected) do
    if row[1] ~= actual[i][1] or row[2] ~= actual[i][2] then
        mismatches[#mismatches + 1] = row[1]
        if #mismatches == 1 then
            local f = assert(io.open(root .. "/.checks/classpower-parity-diff-" .. flavor .. ".txt", "wb"))
            f:write(row[1], "\nPARENT\n", row[2], "\nCANDIDATE\n", actual[i][2]); f:close()
        end
    end
end
if #mismatches > 0 then
    error(flavor .. ": parity mismatch (" .. #mismatches .. ") " .. table.concat(mismatches, "; ", 1, math.min(8, #mismatches)))
end
print("PASS ClassPower parity " .. flavor .. ": " .. count .. " controls, two states, " .. #actual .. " receipts")

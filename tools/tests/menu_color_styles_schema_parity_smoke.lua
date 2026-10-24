-- Replay actual shared color-style controls against the reachable pre-migration page.
-- Offline binding/layout evidence does not establish live WoW rendering or taint.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local candidate, mode = arg[3], arg[4] or "full"
assert(mode == "full" or mode == "push" or mode == "layout" or mode == "scope", "unknown color style tier")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
-- This page blob is reachable from actual Main f2a324f82caaa17c0f5efbc64ecaa29f3106767d.
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root
    .. '" show a4be243c80530d587e1ba881c460b72841c7dce9', "r"))
local source = pipe:read("*a")
assert(pipe:close() and #source > 90000, "reachable parent page missing")
if package.config:sub(1, 1) == "\\" then os.execute('if not exist "' .. root .. '/.checks" mkdir "' .. root .. '/.checks"')
else os.execute('mkdir -p "' .. root .. '/.checks"') end
local scratch = root .. "/.checks/color-styles-parent.lua"
local file = assert(io.open(scratch, "wb")) file:write(source) file:close()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or value:GetObjectType()) end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids) .. "=" .. Encode(value[key], ids, seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Replay(original, narrow, restoredProfile)
    print("Color styles " .. flavor .. ": " .. (original and "parent" or "candidate") .. (narrow and " 400px" or " normal"))
    local rows, ids, calls, refreshes, tips, replaced = {}, {}, {}, 0, {}, 0
    local override = original and scratch or candidate
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            -- Same deterministic numeric input policy as unit_scene_world; opaque API stubs are not RGB values.
            world.env.RAID_CLASS_COLORS = {}
            for index, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
                "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
                world.env.RAID_CLASS_COLORS[token] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
            end
        end,
        beforeOptions = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if override and override ~= "-" and path:gsub("\\", "/") == root .. "/" .. target then
                    replaced = replaced + 1 path = override
                    -- The pinned parent predates namespace-only exports.
                    if original then return MenuWorld.LoadHistorical(self, path, addon, namespace) end
                end
                return load(self, path, addon, namespace)
            end
        end })
    if override and override ~= "-" then assert(replaced == 1, "exact page override not loaded once") end
    local M, core, env = mw.M, mw.core, mw.env
    local created, captured = {}, {}
    for _, name in ipairs({ "Color", "Toggle", "ToggleAt", "SwitchAt", "ScopeOverrideBar" }) do
        local create = M.Widgets[name]
        M.Widgets[name] = function(...)
            local w = create(...)
            if not captured[w] then created[#created + 1], captured[w] = w, true end
            return w
        end
    end
    local nativeButton = M.Theme.Button
    M.Theme.Button = function(...)
        local w = nativeButton(...)
        if not captured[w] then created[#created + 1], captured[w] = w, true end
        return w
    end
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
    end
    local F = core.ProfileFields
    core.MSUF_ApplyGameplayVisuals = function(...) calls[#calls + 1] = { "GameplayVisuals", Pack(...) } end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Restore(dst, src)
        for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
        for key, value in pairs(src) do
            if type(value) == "table" then
                if type(dst[key]) ~= "table" then dst[key] = {} end
                Restore(dst[key], value)
            else dst[key] = value end
        end
    end
    local function Diff(a, b, path, result)
        path, result = path or "", result or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for key in pairs(a) do keys[key] = true end
            for key in pairs(b) do keys[key] = true end
            for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), result) end
        elseif Encode(a, ids) ~= Encode(b, ids) then result[path] = { Encode(a, ids), Encode(b, ids) } end
        return result
    end
    local restoredBefore
    if restoredProfile then
        -- Preserve the current DB/store aliases; replace only their raw contents before the first target construction.
        Restore(env.MSUF_DB, restoredProfile)
        restoredBefore = F.CopySnapshot(env.MSUF_DB)
        assert(not next(Diff(restoredProfile, restoredBefore)), "fresh restore changed the saved snapshot")
    end
    assert(mw:Select("opt_colors"))
    assert(M.ColorsSetPainterCategory)("unit") mw:RunTimers()
    local entry = assert(M.cache.opt_colors)
    for _, name in ipairs({ "colors_classes", "colors_bar_gradients", "colors_highlight", "colors_texture_layer", "colors_gameplay" }) do
        local section = assert(entry.sections[name], "color style section missing: " .. name)
        M.Widgets.EnsureSectionContent(section)
        local shell = assert(section._msuf2CollapsibleEntry)
        shell.SetOpenImmediate(true) ids[section] = name
        if not original then
            local spec = assert(shell.header._msuf2ControlSchema, "section declaration missing")
            assert(spec.id == shell.header._msuf2RuntimeControlRecord.controlId and spec.scope == "colors"
                and spec.applyDomain == "sectionNavigation", "section declaration drift")
        end
    end
    mw:RunTimers()
    local expected = { ["bar_gradient.health.color"] = "color", ["bar_gradient.power.color"] = "color",
        ["highlight.mouseover.color"] = "color", ["table.bossTargetHighlightColor"] = "color",
        ["table.combatTimerColor"] = "color", ["gameplay.combat_enter_color"] = "color",
        ["table.combatStateLeaveColor"] = "color", ["table.crosshairInRangeColor"] = "color",
        ["table.crosshairOutRangeColor"] = "color", ["gameplay.combat_state_color_sync"] = "toggle" }
    for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
        "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do expected["class_bar.token." .. token] = "color" end
    for _, key in ipairs({ "texture_layer", "texture_layer2", "texture_layer3" }) do
        expected[key .. ".color"], expected[key .. ".gradient_color"] = "color", "color"
    end
    local function Domain(path) return path:match("^bar_gradient%.") and "barGradients" or "unitColors" end
    local controls, actions, seen = {}, {}, {}
    local function Widget(path)
        local id = M.ControlMeta("opt_colors", "advanced", path).controlId
        local item = assert(M.RuntimeControlCatalog.Get(id), "real control missing: " .. path)
        local w = assert(item.widget, "real widget missing: " .. path)
        ids[w] = id
        return w
    end
    for path, kind in pairs(expected) do
        local w = Widget(path)
        assert(w._msuf2RuntimeControlRecord.kind == kind, "native kind drift: " .. path)
        assert(not seen[w], "duplicated control: " .. path) seen[w] = true
        if not original then
            local spec = assert(w._msuf2ControlSchema, "ordinary declaration missing: " .. path)
            assert(spec.id == ids[w] and spec.kind == kind and spec.scope == "colors" and spec.applyDomain == Domain(path),
                "ordinary declaration identity/kind/scope/domain drift: " .. path)
        end
        controls[#controls + 1] = w
    end
    for _, path in ipairs({ "class_bar.reset_all", "bar_gradient.reset", "gameplay.reset" }) do
        local w = Widget(path) actions[#actions + 1] = w
        if not original then
            local spec = assert(w._msuf2ControlSchema, "action declaration missing")
            assert(spec.owner == w and spec.action and spec.scope == "colors" and spec.applyDomain == Domain(path),
                "action owner contract drift")
        end
    end
    for _, action in ipairs(actions) do seen[action] = true end
    local scopeBar = Widget("bar_gradient.scope.selector") seen[scopeBar] = true
    if not original then
        local spec = assert(scopeBar._msuf2ControlSchema, "scope selector declaration missing")
        assert(spec.owner == scopeBar and spec.kind == "segment" and spec.applyDomain == "menuState"
            and type(spec.get) == "function" and type(spec.set) == "function" and spec.values == scopeBar.values,
            "scope selector native accessor contract missing")
    end
    local function TargetParent(w) return ids[w:GetParent()] and ids[w:GetParent()]:match("^colors_") end
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local item = M.RuntimeControlCatalog.Get(record.controlId)
        local w = item and item.widget
        if w and w.GetParent and (w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command) then
            local parent = w:GetParent()
            if TargetParent(w) then
                assert(seen[w], "unexpected native input/action in color style: " .. record.controlId)
            end
        end
    end
    for _, w in ipairs(created) do
        local parent = w:GetParent()
        if TargetParent(w) then
            assert(seen[w] or seen[w._msuf2ControlPartOf], "extra or unbound native primitive in color style")
        end
    end
    table.sort(controls, function(a, b) return ids[a] < ids[b] end)
    assert(#controls == 29, "native input inventory drift")
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function ModelValue(w) return Pack(Command(w).get()) end
    local function DisplayValue(w)
        local kind = w._msuf2RuntimeControlRecord.kind
        if kind == "color" then return Pack(w:GetRGB()) end
        if kind == "toggle" then return Pack(w:GetChecked()) end
        return Pack(w:GetValue())
    end
    local function CheckDisplayed(tag, capturePendingRefresh)
        local values = {}
        for _, w in ipairs(controls) do
            local model, displayed = ModelValue(w), DisplayValue(w)
            local visible = model
            if w._msuf2RuntimeControlRecord.kind == "color" then
                visible = Pack(model[1], model[2], model[3])
                assert(w._msuf2GetColorOpacity() == model[4], "opacity getter drift: " .. ids[w])
            end
            assert(capturePendingRefresh or Encode(visible, ids) == Encode(displayed, ids), "displayed widget/model drift at " .. tag .. ": " .. ids[w] .. " MODEL=" .. Encode(model, ids) .. " DISPLAY=" .. Encode(displayed, ids))
            values[#values + 1] = { ids[w], model, displayed, w:IsEnabled() }
        end
        Add(tag .. ":displayed", values)
    end
    local function ExplicitRefresh(tag)
        local before = F.CopySnapshot(env.MSUF_DB)
        M.Refresh() mw:RunTimers()
        assert(not next(Diff(before, env.MSUF_DB)), "refresh materialized profile keys at " .. tag)
        CheckDisplayed(tag .. ":refresh")
        Add(tag .. ":refresh-effects", calls, refreshes)
    end
    local function Input(w, value)
        local kind = w._msuf2RuntimeControlRecord.kind
        if kind == "color" then w._msuf2OnColorChanged(unpack(value))
        elseif kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
        elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
        else w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value) end
        mw:RunTimers()
    end
    for _, name in ipairs({ "SetOwner", "SetText", "AddLine", "Show", "Hide" }) do
        env.GameTooltip[name] = function(_, ...) tips[#tips + 1] = { name, ... } end
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, Pack(...) } return fn(...)
        end end
    end
    for name, fn in pairs(core._colorsAPI) do
        if type(fn) == "function" and (name:sub(1, 3) == "Set" or name:sub(1, 5) == "Reset") then
            core._colorsAPI[name] = function(...)
                calls[#calls + 1] = { "ColorAPI." .. name, Pack(...) }
                return fn(...)
            end
        end
    end
    local refresh = M.RunEntryRefreshers
    M.RunEntryRefreshers = function(...) refreshes = refreshes + 1 return refresh(...) end
    local defaults = F.CopySnapshot(env.MSUF_DB)
    local keys = { "highlightColor", "bossTargetHighlightColor" }
    for _, prefix in ipairs({ "texLayerColor", "texLayerGradient2", "texLayer2Color", "texLayer2Gradient2", "texLayer3Color", "texLayer3Gradient2",
        "healthBarGradientColor", "powerBarGradientColor" }) do
        for _, suffix in ipairs({ "R", "G", "B", "A" }) do keys[#keys + 1] = prefix .. suffix end
    end
    local gameplayKeys = { "combatTimerColor", "combatStateEnterColor", "combatStateLeaveColor", "crosshairInRangeColor", "crosshairOutRangeColor" }
    local function Setup(state)
        Restore(env.MSUF_DB, defaults)
        local db, g, gp = env.MSUF_DB, env.MSUF_DB.general, env.MSUF_DB.gameplay
        g.hpPowerTextSelectedKey, gp.combatStateColorSync = "shared", false
        if state ~= "default" then
            db.classColors = { WARRIOR = { r = 0.17, g = 0.28, b = 0.39 } }
            g.highlightColor, g.bossTargetHighlightColor = { 0.21, 0.32, 0.43 }, { 0.19, 0.29, 0.39 }
            g.texLayerColorR, g.texLayerColorG, g.texLayerColorB = 0.15, 0.25, 0.35
            for _, key in ipairs(gameplayKeys) do gp[key] = { 0.12, 0.23, 0.34 } end
            g.unrelatedPaletteExtension = { enabled = false, amount = 0 }
        end
        if state == "edge" then
            g.texLayerColorR, g.texLayerColorG, g.texLayerColorB = false, 0, 1
            gp.combatStateColorSync, gp.combatStateLeaveColor = 0, { ["1"] = 0, ["2"] = 0.25, ["3"] = 1 }
        elseif state == "absent" then
            db.classColors = nil
            for _, key in ipairs(keys) do g[key] = nil end
            for _, key in ipairs(gameplayKeys) do gp[key] = nil end
            gp.combatStateColorSync = nil
        elseif state == "disabled" then gp.combatStateColorSync = true end
        ExplicitRefresh(state) M.ClearHistory()
    end
    local function Observe(tag)
        for _, w in ipairs(controls) do
            tips = {}
            if w:HasScript("OnEnter") then MenuWorld.FireScript(w, "OnEnter") end
            if w:HasScript("OnLeave") then MenuWorld.FireScript(w, "OnLeave") end
            local points = {} for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
            local title = w._msuf2Title or w._msuf2Label
            local titlePoints = {}
            if title then for i = 1, title:GetNumPoints() do titlePoints[i] = Pack(title:GetPoint(i)) end end
            Add(tag .. ":control:" .. ids[w], w._msuf2RuntimeControlRecord, w._msuf2SearchMeta, ModelValue(w), DisplayValue(w),
                w:GetParent(), w.width, w.height, points, w:IsShown(), w:IsEnabled(),
                title and title.text, title and title.width, titlePoints, w._msuf2DefaultRGB, tips)
        end
    end
    local function Alternate(w)
        local kind, value = w._msuf2RuntimeControlRecord.kind, ModelValue(w)[1]
        if kind == "color" then
            local rgb = ModelValue(w)
            if rgb[1] == 0 and rgb[2] == 0.25 and rgb[3] == 1 then return { 0.13, 0.4, 0.9 } end
            return { 0, 0.25, 1 }
        end
        if kind == "toggle" then return not value end
        if kind == "slider" then return value == 1 and 0 or 1 end
        local values = w.values
        if type(values) == "function" then values = values() end
        for _, item in ipairs(values) do if item.value ~= value then return item.value end end
        error("dropdown has no alternate value")
    end
    Observe("factory")
    if restoredProfile then
        assert(not next(Diff(restoredBefore, env.MSUF_DB)), "fresh target construction materialized profile keys")
        Add("fresh-before-selection", restoredBefore)
        Add("fresh-after-selection", F.CopySnapshot(env.MSUF_DB))
        ExplicitRefresh("fresh-restored")
        for _, path in ipairs({ "class_bar.token.WARRIOR", "bar_gradient.health.color", "texture_layer.color", "table.combatTimerColor" }) do
            local w = Widget(path)
            local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
            M.ClearHistory() calls, refreshes = {}, 0 Input(w, value)
            local after = F.CopySnapshot(env.MSUF_DB)
            assert(next(Diff(before, after)), "fresh input made no change: " .. path)
            Add("fresh-input:" .. path, Diff(before, after), ModelValue(w), DisplayValue(w), calls, refreshes)
            calls, refreshes = {}, 0 local undo = M.Undo() mw:RunTimers()
            assert(undo and not next(Diff(before, env.MSUF_DB)), "fresh undo drift: " .. path)
            Add("fresh-undo:" .. path, undo, Diff(before, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("fresh-undo:" .. path)
            calls, refreshes = {}, 0 local redo = M.Redo() mw:RunTimers()
            assert(redo and not next(Diff(after, env.MSUF_DB)), "fresh redo drift: " .. path)
            Add("fresh-redo:" .. path, redo, Diff(after, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("fresh-redo:" .. path)
        end
        return rows, #controls
    end
    local states = mode == "push" and { "default", "custom", "absent", "disabled" } or { "default", "custom", "edge", "absent", "disabled" }
    if mode == "scope" then states = { "absent" } end
    for _, state in ipairs(states) do
        Setup(state) Observe(state)
        if not narrow and mode == "full" then
            for _, w in ipairs(controls) do
                if not w:IsEnabled() then
                    local before, model, display = F.CopySnapshot(env.MSUF_DB), ModelValue(w), DisplayValue(w)
                    calls, refreshes = {}, 0 w:Click("LeftButton") mw:RunTimers()
                    assert(not next(Diff(before, env.MSUF_DB)) and #calls == 0 and not M.Undo(), "disabled native input executed")
                    assert(Encode(model, ids) == Encode(ModelValue(w), ids) and Encode(display, ids) == Encode(DisplayValue(w), ids),
                        "disabled native input changed display/model")
                    Add(state .. ":disabled-native:" .. ids[w], ModelValue(w), DisplayValue(w), calls, refreshes)
                end
            end
        end
        for _, w in ipairs((narrow or mode == "layout" or mode == "scope" or state == "absent" or state == "disabled") and {} or controls) do
            Setup(state)
            if w:IsEnabled() then
                local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
                calls, refreshes = {}, 0
                Input(w, value)
                local after = F.CopySnapshot(env.MSUF_DB)
                assert(next(Diff(before, after)), "native input changed no profile keys: " .. ids[w])
                Add(state .. ":input:" .. ids[w], value, Diff(before, after), ModelValue(w), DisplayValue(w), calls, refreshes)
                ExplicitRefresh(state .. ":input:" .. ids[w])
                calls, refreshes = {}, 0
                assert(M.Undo(), "input created no undo: " .. ids[w]) mw:RunTimers()
                assert(not next(Diff(before, env.MSUF_DB)), "undo profile drift: " .. ids[w])
                Add(state .. ":undo-calls:" .. ids[w], calls, refreshes)
                CheckDisplayed(state .. ":undo:" .. ids[w])
                calls, refreshes = {}, 0
                assert(M.Redo(), "input created no redo: " .. ids[w]) mw:RunTimers()
                assert(not next(Diff(after, env.MSUF_DB)), "redo profile drift: " .. ids[w])
                Add(state .. ":redo-calls:" .. ids[w], calls, refreshes)
                CheckDisplayed(state .. ":redo:" .. ids[w])
                if w._msuf2RuntimeControlRecord.kind == "color" then
                    calls, refreshes = {}, 0 w:Click("RightButton") mw:RunTimers()
                    Add(state .. ":right-reset:" .. ids[w], Diff(after, env.MSUF_DB), ModelValue(w), DisplayValue(w), calls, refreshes)
                    -- Preserve the parent's immediate coupled-color display, then require coherence after the actual full refresh.
                    CheckDisplayed(state .. ":right-reset-pending:" .. ids[w], true)
                    ExplicitRefresh(state .. ":right-reset:" .. ids[w])
                end
                Setup(state) before = F.CopySnapshot(env.MSUF_DB)
                core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return false end
                calls, refreshes = {}, 0 Input(w, value)
                assert(not next(Diff(before, env.MSUF_DB)) and #calls == 0, "combat-edge profile/apply changed")
                Add(state .. ":combat-edge:" .. ids[w], ModelValue(w), DisplayValue(w), calls, refreshes)
                env.InCombatLockdown = function() return true end Input(w, value)
                assert(not next(Diff(before, env.MSUF_DB)) and #calls == 0, "combat profile/apply changed")
                Add(state .. ":combat:" .. ids[w], ModelValue(w), DisplayValue(w), calls, refreshes, M.Undo())
                core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
            else Add(state .. ":disabled:" .. ids[w], ModelValue(w), DisplayValue(w)) end
        end
    end
    if not narrow and mode == "full" then
        for _, key in ipairs(keys) do
            Setup("custom") env.MSUF_DB.general[key] = nil ExplicitRefresh("absent-key:" .. key)
            Add("absent-key:" .. key, F.CopySnapshot(env.MSUF_DB))
        end
        local api, saved = core._colorsAPI, {}
        for _, key in ipairs({ "GetClassColor", "SetClassColor", "ResetAllClassColors" }) do saved[key], api[key] = api[key], nil end
        for _, w in ipairs(controls) do
            Setup("custom") calls = {} Input(w, Alternate(w))
            Add("api-absent:" .. ids[w], F.CopySnapshot(env.MSUF_DB), ModelValue(w), DisplayValue(w), calls)
        end
        local resetClass = Widget("class_bar.reset_all")
        Setup("custom") local before = F.CopySnapshot(env.MSUF_DB)
        calls, refreshes = {}, 0 resetClass:Click("LeftButton") mw:RunTimers()
        local after = F.CopySnapshot(env.MSUF_DB)
        Add("api-absent-class-reset", Diff(before, after), calls, refreshes)
        ExplicitRefresh("api-absent-class-reset")
        calls, refreshes = {}, 0 local undo = M.Undo() mw:RunTimers()
        Add("api-absent-class-reset-undo", undo, Diff(before, env.MSUF_DB), calls, refreshes)
        CheckDisplayed("api-absent-class-reset-undo")
        calls, refreshes = {}, 0 local redo = M.Redo() mw:RunTimers()
        Add("api-absent-class-reset-redo", redo, Diff(after, env.MSUF_DB), calls, refreshes)
        CheckDisplayed("api-absent-class-reset-redo")
        for key, fn in pairs(saved) do api[key] = fn end
        -- Sparse history retains the parent raw root effects, including any existing absent-container materialization.
        for _, path in ipairs({ "highlight.mouseover.color", "texture_layer.color", "table.combatTimerColor" }) do
            Setup("absent") local w = Widget(path)
            local before = F.CopySnapshot(env.MSUF_DB)
            calls, refreshes = {}, 0 Input(w, Alternate(w))
            local after = F.CopySnapshot(env.MSUF_DB)
            assert(next(Diff(before, after)), "sparse input made no change: " .. path)
            Add("sparse-input:" .. path, Diff(before, after), calls, refreshes) ExplicitRefresh("sparse-input:" .. path)
            calls, refreshes = {}, 0 local undo = M.Undo() mw:RunTimers()
            assert(undo, "sparse input created no undo: " .. path)
            Add("sparse-undo:" .. path, undo, Diff(before, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("sparse-undo:" .. path)
            calls, refreshes = {}, 0 local redo = M.Redo() mw:RunTimers()
            assert(redo, "sparse input created no redo: " .. path)
            Add("sparse-redo:" .. path, redo, Diff(after, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("sparse-redo:" .. path)
        end
        for _, w in ipairs(actions) do
            for _, state in ipairs({ "default", "edge", "absent" }) do
                Setup(state) local before = F.CopySnapshot(env.MSUF_DB)
                calls, refreshes = {}, 0 w:Click("LeftButton") mw:RunTimers()
                local after, tag = F.CopySnapshot(env.MSUF_DB), state .. ":action:" .. ids[w]
                Add(tag, Diff(before, after), calls, refreshes) ExplicitRefresh(tag)
                calls, refreshes = {}, 0 local undo = M.Undo() mw:RunTimers()
                Add(tag .. ":undo", undo, Diff(before, env.MSUF_DB), calls, refreshes)
                CheckDisplayed(tag .. ":undo")
                calls, refreshes = {}, 0 local redo = M.Redo() mw:RunTimers()
                Add(tag .. ":redo", redo, Diff(after, env.MSUF_DB), calls, refreshes)
                CheckDisplayed(tag .. ":redo")
                for _, lockdown in ipairs({ false, true }) do
                    Setup(state) before = F.CopySnapshot(env.MSUF_DB)
                    core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
                    calls, refreshes = {}, 0 w:Click("LeftButton") mw:RunTimers()
                    Add(tag .. ":combat:" .. tostring(lockdown), Diff(before, env.MSUF_DB), calls, refreshes, M.Undo())
                    core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                    mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                end
            end
        end
    end
    if not narrow and (mode == "full" or mode == "scope") then
        local health, power, reset = Widget("bar_gradient.health.color"), Widget("bar_gradient.power.color"), Widget("bar_gradient.reset")
        for _, button in ipairs(scopeBar.buttons) do
            Setup("absent") calls, refreshes = {}, 0
            local before = F.CopySnapshot(env.MSUF_DB)
            button:Click("LeftButton") mw:RunTimers()
            local scope = button._msuf2Value
            assert(scopeBar:GetValue() == scope, "actual scope button did not select value")
            Add("scope-select:" .. scope, Diff(before, env.MSUF_DB), calls, refreshes)
            M.ClearHistory() before = F.CopySnapshot(env.MSUF_DB)
            Input(health, { 0, 0.25, 1 }) Input(power, { 0.13, 0.4, 0.9 })
            Add("scope-colors:" .. scope, Diff(before, env.MSUF_DB), ModelValue(health), ModelValue(power), calls)
            ExplicitRefresh("scope-colors:" .. scope)
            local declaration = scopeBar._msuf2ControlSchema
            local declaredGet = original and scopeBar:GetValue() or declaration.get()
            local sameScope
            if original then sameScope = scopeBar:SetValue(scope) else sameScope = declaration.set(scope) end
            assert(declaredGet == scope and sameScope == false, "declared scope accessors diverged from native owner")
            Add("declared-scope:" .. scope, declaredGet, sameScope, F.CopySnapshot(env.MSUF_DB))
            reset:Click("LeftButton") mw:RunTimers()
            Add("scope-reset:" .. scope, F.CopySnapshot(env.MSUF_DB), ModelValue(health), ModelValue(power), calls)
            assert(Encode(Pack(0, 0, 0), ids) == Encode(Pack(health:GetRGB()), ids)
                and Encode(Pack(0, 0, 0), ids) == Encode(Pack(power:GetRGB()), ids), "scope reset did not restore RGB")
        end
        Setup("absent")
        local first, second = assert(scopeBar.buttons[2]), assert(scopeBar.buttons[3])
        local scopeA, scopeB = first._msuf2Value, second._msuf2Value
        local function SelectDeclared(value)
            if original then return scopeBar:SetValue(value) end
            return scopeBar._msuf2ControlSchema.set(value)
        end
        first:Click("LeftButton") mw:RunTimers()
        Input(health, { 0.16, 0.27, 0.38 })
        local valueA = ModelValue(health)
        M.ClearHistory() calls, refreshes = {}, 0 local beforeScope = F.CopySnapshot(env.MSUF_DB)
        local selected = SelectDeclared(scopeB) mw:RunTimers()
        assert(scopeBar:GetValue() == scopeB, "declared scope setter did not change value")
        Add("persistent-declared-B", selected, Diff(beforeScope, env.MSUF_DB), ModelValue(health), calls, refreshes, M.Undo())
        M.ClearHistory() local beforeColor = F.CopySnapshot(env.MSUF_DB)
        calls, refreshes = {}, 0 Input(health, { 0.61, 0.72, 0.83 })
        local afterColor = F.CopySnapshot(env.MSUF_DB)
        Add("persistent-B-color", Diff(beforeColor, afterColor), ModelValue(health), calls, refreshes)
        calls, refreshes = {}, 0 local undo = M.Undo() mw:RunTimers()
        assert(undo, "scoped color input created no undo")
        Add("persistent-B-undo", undo, Diff(beforeColor, env.MSUF_DB), ModelValue(health), calls, refreshes)
        calls, refreshes = {}, 0 local redo = M.Redo() mw:RunTimers()
        assert(redo, "scoped color input created no redo")
        Add("persistent-B-redo", redo, Diff(afterColor, env.MSUF_DB), ModelValue(health), calls, refreshes)
        calls, refreshes = {}, 0 SelectDeclared(scopeA) mw:RunTimers()
        assert(Encode(ModelValue(health), ids) == Encode(valueA, ids), "scope revisit lost original RGB")
        Add("persistent-revisit-A", F.CopySnapshot(env.MSUF_DB), ModelValue(health), calls, refreshes)
        ExplicitRefresh("persistent-revisit-A")
        SelectDeclared(scopeA) mw:RunTimers() M.ClearHistory()
        local beforeNative = F.CopySnapshot(env.MSUF_DB)
        calls, refreshes = {}, 0 second:Click("LeftButton") mw:RunTimers()
        local afterNative = F.CopySnapshot(env.MSUF_DB)
        Add("native-scope-click", Diff(beforeNative, afterNative), scopeBar:GetValue(), ModelValue(health), calls, refreshes)
        calls, refreshes = {}, 0 local nativeUndo = M.Undo() mw:RunTimers()
        Add("native-scope-undo", nativeUndo, Diff(beforeNative, env.MSUF_DB), scopeBar:GetValue(), ModelValue(health), calls, refreshes)
        CheckDisplayed("native-scope-undo")
        calls, refreshes = {}, 0 local nativeRedo = M.Redo() mw:RunTimers()
        Add("native-scope-redo", nativeRedo, Diff(afterNative, env.MSUF_DB), scopeBar:GetValue(), ModelValue(health), calls, refreshes)
        CheckDisplayed("native-scope-redo")
        for _, lockdown in ipairs({ false, true }) do
            SelectDeclared(scopeA) mw:RunTimers() M.ClearHistory()
            local before = F.CopySnapshot(env.MSUF_DB)
            core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
            calls, refreshes = {}, 0 local changed = SelectDeclared(scopeB) mw:RunTimers()
            Add("scope-combat:" .. tostring(lockdown), changed, Diff(before, env.MSUF_DB), ModelValue(health), calls, refreshes, M.Undo())
            SelectDeclared(scopeA) mw:RunTimers() M.ClearHistory()
            local beforeClick = F.CopySnapshot(env.MSUF_DB)
            calls, refreshes = {}, 0 second:Click("LeftButton") mw:RunTimers()
            local afterClick = F.CopySnapshot(env.MSUF_DB)
            Add("native-scope-combat:" .. tostring(lockdown), Diff(beforeClick, afterClick), scopeBar:GetValue(),
                ModelValue(health), DisplayValue(health), calls, refreshes)
            calls, refreshes = {}, 0 local clickUndo = M.Undo() mw:RunTimers()
            Add("native-scope-combat-undo:" .. tostring(lockdown), clickUndo, Diff(beforeClick, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("native-scope-combat-undo:" .. tostring(lockdown))
            calls, refreshes = {}, 0 local clickRedo = M.Redo() mw:RunTimers()
            Add("native-scope-combat-redo:" .. tostring(lockdown), clickRedo, Diff(afterClick, env.MSUF_DB), calls, refreshes)
            CheckDisplayed("native-scope-combat-redo:" .. tostring(lockdown))
            core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
            mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
        end
        Setup("disabled") local sync, leave = Widget("gameplay.combat_state_color_sync"), Widget("table.combatStateLeaveColor")
        assert(not leave:IsEnabled(), "synced leave color is editable") Input(sync, false) ExplicitRefresh("unsync")
        assert(leave:IsEnabled(), "leave color did not unlock") Input(leave, { 0.13, 0.4, 0.9 })
        Add("unsynced-leave-input", F.CopySnapshot(env.MSUF_DB), calls)

    end
    if not narrow and mode == "full" then
        Setup("custom") scopeBar.buttons[2]:Click("LeftButton") mw:RunTimers()
        Input(Widget("class_bar.token.WARRIOR"), { 0.16, 0.27, 0.38 })
        Input(Widget("texture_layer.color"), { 0.61, 0.72, 0.83 })
        Input(Widget("bar_gradient.health.color"), { 0.13, 0.4, 0.9 })
        Input(Widget("table.combatTimerColor"), { 0, 0.25, 1 })
        Add("saved-restored-seed", F.CopySnapshot(env.MSUF_DB), calls, refreshes)
    end
    mw:Select("home") mw:Select("opt_colors") M.ColorsSetPainterCategory("unit") mw:RunTimers()
    Observe("reopen")
    return rows, #controls, F.CopySnapshot(env.MSUF_DB)
end
local started, total, count = os.clock(), 0, 0
local function Compare(narrow, saved)
    local expected, _, parentSaved = Replay(true, narrow, saved and saved[1])
    local actual, n, candidateSaved = Replay(false, narrow, saved and saved[2]) count = n
    assert(#expected == #actual, "color style observation count drift")
    for i = 1, #expected do
        if expected[i] ~= actual[i] then
            local file = assert(io.open(root .. "/.checks/color-styles-first-diff-" .. flavor .. ".txt", "wb"))
            file:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n") file:close()
            error("color style drift at observation " .. i .. " " .. expected[i]:match("^[^\t]+"))
        end
    end
    total = total + #expected
    return { parentSaved, candidateSaved }
end
local saved
for _, narrow in ipairs({ false, true }) do
    local snapshots = Compare(narrow)
    if not narrow then saved = snapshots end
end
if mode == "full" then Compare(false, saved) end
print(string.format("menu_color_styles_schema_parity_smoke %s %s: %d inputs/%d observations exact (%.2fs)",
    mode, flavor, count, total, os.clock() - started))

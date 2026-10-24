-- Replay actual unit/NPC Colors controls against the reachable pre-migration page.
-- Offline binding/layout evidence does not establish live WoW rendering or taint.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local candidate, mode = arg[3], arg[4] or "full"
assert(mode == "full" or mode == "push" or mode == "layout", "unknown unit palette tier")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
-- This page blob is reachable from actual Main f2a324f82caaa17c0f5efbc64ecaa29f3106767d.
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root
    .. '" show a4be243c80530d587e1ba881c460b72841c7dce9', "r"))
local source = pipe:read("*a")
assert(pipe:close() and #source > 90000, "reachable parent page missing")
if package.config:sub(1, 1) == "\\" then os.execute('if not exist "' .. root .. '/.checks" mkdir "' .. root .. '/.checks"')
else os.execute('mkdir -p "' .. root .. '/.checks"') end
local scratch = root .. "/.checks/unit-palettes-parent.lua"
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
local function Replay(original, narrow)
    print("Unit palettes " .. flavor .. ": " .. (original and "parent" or "candidate") .. (narrow and " 400px" or " normal"))
    local rows, ids, calls, refreshes, tips, replaced = {}, {}, {}, 0, {}, 0
    local override = original and scratch or candidate
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeOptions = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if override and override ~= "-" and path:gsub("\\", "/") == root .. "/" .. target then
                    replaced = replaced + 1 path = override
                end
                return load(self, path, addon, namespace)
            end
        end })
    if override and override ~= "-" then assert(replaced == 1, "exact page override not loaded once") end
    local M, core, env = mw.M, mw.core, mw.env
    local created, captured = {}, {}
    for _, name in ipairs({ "Color", "Toggle", "ToggleAt", "SwitchAt" }) do
        local create = M.Widgets[name]
        M.Widgets[name] = function(...)
            local w = create(...)
            if not captured[w] then created[#created + 1], captured[w] = w, true end
            return w
        end
    end
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
    end
    local F = core.ProfileFields
    core.MSUF_ApplyGameplayVisuals = function(...) calls[#calls + 1] = { "GameplayVisuals", ... } end
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
    assert(mw:Select("opt_colors"))
    assert(M.ColorsSetPainterCategory)("unit") mw:RunTimers()
    local entry = assert(M.cache.opt_colors)
    for _, name in ipairs({ "colors_unit", "colors_npc_type" }) do
        local section = assert(entry.sections[name], "unit palette section missing: " .. name)
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
    local expected = {
        ["api.SetPetFrameColor"] = "color", ["unit.pet.use_player_class_color"] = "toggle",
        ["npc.class_color_bar"] = "toggle", ["npc_type.enabled"] = "toggle",
        ["npc_type.option.npcTypeColorBar"] = "toggle", ["npc_type.option.npcTypeColorText"] = "toggle",
    }
    for _, key in ipairs({ "friendly", "neutral", "enemy", "dead", "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }) do
        expected["npc.color." .. key] = "color"
    end
    for _, key in ipairs({ "npcTypeTarget", "npcTypeFocus", "npcTypeBoss", "npcTypeToT" }) do expected["npc_type.option." .. key] = "toggle" end
    if core.Client.SupportsTapDenied then expected["npc.color.tapped"], expected["npc.tap_denied_gray"] = "color", "toggle" end
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
            assert(spec.id == ids[w] and spec.kind == kind and spec.scope == "colors" and spec.applyDomain == "unitColors",
                "ordinary declaration identity/kind/scope/domain drift: " .. path)
        end
        controls[#controls + 1] = w
    end
    for _, path in ipairs({ "unitframe.reset", "npc_type.reset" }) do
        local w = Widget(path) actions[#actions + 1] = w
        if not original then
            local spec = assert(w._msuf2ControlSchema, "action declaration missing")
            assert(spec.owner == w and spec.action and spec.scope == "colors" and spec.applyDomain == "unitColors",
                "action owner contract drift")
        end
    end
    for _, action in ipairs(actions) do seen[action] = true end
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local item = M.RuntimeControlCatalog.Get(record.controlId)
        local w = item and item.widget
        if w and w.GetParent and (w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command) then
            local parent = w:GetParent()
            if ids[parent] == "colors_unit" or ids[parent] == "colors_npc_type" then
                assert(seen[w], "unexpected native input/action in unit palette: " .. record.controlId)
            end
        end
    end
    for _, w in ipairs(created) do
        local parent = w:GetParent()
        if ids[parent] == "colors_unit" or ids[parent] == "colors_npc_type" then
            assert(seen[w], "extra or unbound native primitive in unit palette")
        end
    end
    table.sort(controls, function(a, b) return ids[a] < ids[b] end)
    assert(#controls == (core.Client.SupportsTapDenied and 21 or 19), "native input inventory drift")
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function ModelValue(w) return Pack(Command(w).get()) end
    local function DisplayValue(w)
        local kind = w._msuf2RuntimeControlRecord.kind
        if kind == "color" then return Pack(w:GetRGB()) end
        if kind == "toggle" then return Pack(w:GetChecked()) end
        return Pack(w:GetValue())
    end
    local function CheckDisplayed(tag)
        local values = {}
        for _, w in ipairs(controls) do
            local model, displayed = ModelValue(w), DisplayValue(w)
            local visible = model
            if w._msuf2RuntimeControlRecord.kind == "color" then
                visible = Pack(model[1], model[2], model[3])
                assert(w._msuf2GetColorOpacity() == model[4], "opacity getter drift: " .. ids[w])
            end
            assert(Encode(visible, ids) == Encode(displayed, ids), "displayed widget/model drift at " .. tag .. ": " .. ids[w])
            values[#values + 1] = { ids[w], model, displayed, w:IsEnabled() }
        end
        Add(tag .. ":displayed", values)
    end
    local function ExplicitRefresh(tag)
        local before = F.CopySnapshot(env.MSUF_DB)
        M.Refresh() mw:RunTimers()
        assert(not next(Diff(before, env.MSUF_DB)), "refresh materialized profile keys at " .. tag)
        CheckDisplayed(tag .. ":refresh")
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
            calls[#calls + 1] = { name, ... } return fn(...)
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
    local keys = { "petFrameUsePlayerClassColor", "npcClassColorBar", "npcColorMode", "npcTypeColorBar", "npcTypeColorText",
        "npcTypeTarget", "npcTypeFocus", "npcTypeBoss", "npcTypeToT", "tapDeniedGray", "petFrameColorR", "petFrameColorG", "petFrameColorB" }
    local function Setup(state)
        Restore(env.MSUF_DB, defaults)
        local db, general = env.MSUF_DB, env.MSUF_DB.general
        if state ~= "default" then
            general.npcColorMode, general.petFrameUsePlayerClassColor, general.tapDeniedGray = "type", false, true
            db.npcColors = { friendly = { r = 0.17, g = 0.28, b = 0.39 }, tapped = { r = 0, g = 0.25, b = 1 } }
            for _, key in ipairs({ "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }) do
                db.npcColors[key] = { r = 0.12, g = 0.23, b = 0.34 }
            end
            general.unrelatedPaletteExtension = { enabled = false, amount = 0 }
        end
        if state == "edge" then
            general.petFrameColorR, general.petFrameColorG, general.petFrameColorB = 0, 0.25, 1
            general.npcTypeColorBar, general.npcTypeColorText, general.npcTypeBoss = false, 0, false
        elseif state == "absent" then
            db.npcColors = nil
            for _, key in ipairs(keys) do general[key] = nil end
        elseif state == "disabled" then
            general.petFrameUsePlayerClassColor, general.tapDeniedGray, general.npcColorMode = true, false, "reaction"
        end
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
    local states = mode == "push" and { "default", "custom", "absent", "disabled" } or { "default", "custom", "edge", "absent", "disabled" }
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
        for _, w in ipairs((narrow or mode == "layout" or state == "absent" or state == "disabled") and {} or controls) do
            Setup(state)
            if w:IsEnabled() then
                local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
                calls, refreshes = {}, 0
                Input(w, value)
                local after = F.CopySnapshot(env.MSUF_DB)
                assert(next(Diff(before, after)), "native input changed no profile keys: " .. ids[w])
                Add(state .. ":input:" .. ids[w], value, Diff(before, after), ModelValue(w), DisplayValue(w), calls, refreshes)
                ExplicitRefresh(state .. ":input:" .. ids[w])
                assert(M.Undo(), "input created no undo: " .. ids[w]) mw:RunTimers()
                assert(not next(Diff(before, env.MSUF_DB)), "undo profile drift: " .. ids[w])
                CheckDisplayed(state .. ":undo:" .. ids[w])
                assert(M.Redo(), "input created no redo: " .. ids[w]) mw:RunTimers()
                assert(not next(Diff(after, env.MSUF_DB)), "redo profile drift: " .. ids[w])
                CheckDisplayed(state .. ":redo:" .. ids[w])
                if w._msuf2RuntimeControlRecord.kind == "color" then
                    w:Click("RightButton") mw:RunTimers()
                    Add(state .. ":right-reset:" .. ids[w], Diff(after, env.MSUF_DB), ModelValue(w), DisplayValue(w))
                    CheckDisplayed(state .. ":right-reset:" .. ids[w])
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
        for _, key in ipairs({ "GetNPCColor", "SetNPCColor", "GetPetFrameColor", "SetPetFrameColor", "GetNPCColorMode", "SetNPCColorMode",
            "GetNPCTypeColorBar", "SetNPCTypeColorBar", "GetNPCTypeColorText", "SetNPCTypeColorText", "GetNPCClassColorBar",
            "SetNPCClassColorBar", "GetNPCTypePerUnit", "SetNPCTypePerUnit" }) do saved[key], api[key] = api[key], nil end
        for _, w in ipairs(controls) do
            Setup("custom") calls = {} Input(w, Alternate(w))
            Add("api-absent:" .. ids[w], F.CopySnapshot(env.MSUF_DB), ModelValue(w), DisplayValue(w), calls)
        end
        for key, fn in pairs(saved) do api[key] = fn end
        for _, w in ipairs(actions) do
            for _, state in ipairs({ "default", "edge", "absent" }) do
                Setup(state) local before = F.CopySnapshot(env.MSUF_DB)
                calls, refreshes = {}, 0 w:Click("LeftButton") mw:RunTimers()
                local after, tag = F.CopySnapshot(env.MSUF_DB), state .. ":action:" .. ids[w]
                Add(tag, Diff(before, after), calls, refreshes) ExplicitRefresh(tag)
                local undo = M.Undo() mw:RunTimers() Add(tag .. ":undo", undo, Diff(before, env.MSUF_DB))
                CheckDisplayed(tag .. ":undo")
                local redo = M.Redo() mw:RunTimers() Add(tag .. ":redo", redo, Diff(after, env.MSUF_DB))
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
        for _, pair in ipairs({ { "unit.pet.use_player_class_color", "api.SetPetFrameColor" },
            { "npc.tap_denied_gray", "npc.color.tapped" } }) do
            if expected[pair[1]] then
                Setup("disabled") local toggle, color = Widget(pair[1]), Widget(pair[2])
                assert(not color:IsEnabled(), "disabled color gate open: " .. pair[2])
                Input(toggle, not ModelValue(toggle)[1]) ExplicitRefresh("enable-gate:" .. pair[1])
                assert(color:IsEnabled(), "color gate did not enable: " .. pair[2])
                Input(color, Alternate(color)) Add("enabled-gate-input:" .. pair[2], F.CopySnapshot(env.MSUF_DB), calls)
            end
        end
        Setup("disabled") Input(Widget("npc_type.enabled"), true) ExplicitRefresh("npc-master-enable")
        for path in pairs(expected) do
            if path:match("^npc_type.option%.") or path:match("^npc.color.npc") then
                assert(Widget(path):IsEnabled(), "NPC master did not enable child: " .. path)
            end
        end
    end
    mw:Select("home") mw:Select("opt_colors") M.ColorsSetPainterCategory("unit") mw:RunTimers()
    Observe("reopen")
    return rows, #controls
end
local started, total, count = os.clock(), 0, 0
for _, narrow in ipairs({ false, true }) do
    local expected = Replay(true, narrow)
    local actual, n = Replay(false, narrow) count = n
    assert(#expected == #actual, "unit palette observation count drift")
    for i = 1, #expected do
        if expected[i] ~= actual[i] then
            local file = assert(io.open(root .. "/.checks/unit-palettes-first-diff-" .. flavor .. ".txt", "wb"))
            file:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n") file:close()
            error("unit palette drift at observation " .. i .. " " .. expected[i]:match("^[^\t]+"))
        end
    end
    total = total + #expected
end
print(string.format("menu_unit_palette_schema_parity_smoke %s %s: %d inputs/%d observations exact (%.2fs)",
    mode, flavor, count, total, os.clock() - started))

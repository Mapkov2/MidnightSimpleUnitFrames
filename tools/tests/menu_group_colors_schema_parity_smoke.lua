-- Replay the actual Group Colors controls against their reachable immutable parent.
-- This is offline binding/layout evidence, not live rendering, taint or CPU proof.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
-- Both blobs are reachable from the pre-migration Main ancestor d4332a69d.
local base = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local targets = { base .. "MSUF_Menu2_AdvancedColors.lua", base .. "MSUF_Menu2_AdvancedColors_Group.lua" }
local blobs = { "a04d10dbe1ae48364dde2fa897be0172019dffbd", "910806dc6d09fdef0f582e217ab0c8aad01ba2e8" }
local mode = arg[5] or "full"
assert(mode == "full" or mode == "push" or mode == "layout", "unknown Group Colors tier")
if package.config:sub(1, 1) == "\\" then
    os.execute('if not exist "' .. root .. '/.checks" mkdir "' .. root .. '/.checks"')
else os.execute('mkdir -p "' .. root .. '/.checks"') end
local originals = {}
for i, path in ipairs(targets) do
    local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root .. '" show ' .. blobs[i], "r"))
    local source = pipe:read("*a")
    assert(pipe:close(), "parent read failed")
    assert(#source > 9000, "reachable parent source missing: " .. path)
    local scratch = root .. "/.checks/group-colors-parent-" .. i .. ".lua"
    local file = assert(io.open(scratch, "wb")) file:write(source) file:close()
    originals[path] = scratch
end
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
    print("Group Colors " .. flavor .. ": " .. (original and "immutable parent" or "candidate"))
    local rows, ids, calls, refreshes, tips, replaced = {}, {}, {}, 0, {}, {}
    local overrides = original and originals or { [targets[2]] = arg[3] ~= "-" and arg[3] or nil,
        [targets[1]] = arg[4] ~= "-" and arg[4] or nil }
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeOptions = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                for target, source in pairs(overrides) do
                    if source and source ~= "" and path:gsub("\\", "/") == root .. "/" .. target then replaced[target] = (replaced[target] or 0) + 1 path = source break end
                end
                return load(self, path, addon, namespace)
            end
        end })
    for target, source in pairs(overrides) do
        if source then assert(replaced[target] == 1, "exact source override not loaded once: " .. target) end
    end
    local M, core, env = mw.M, mw.core, mw.env
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
    assert(M.ColorsSetPainterCategory, "actual Colors category selector missing")("group")
    mw:RunTimers()
    local entry = assert(M.cache.opt_colors)
    local sections = { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state",
        "colors_group_frames_highlights", "colors_group_frames_healer_mana" }
    for _, name in ipairs(sections) do
        local section = assert(entry.sections[name], "group section missing: " .. name)
        M.Widgets.EnsureSectionContent(section)
        local shell = assert(section._msuf2CollapsibleEntry)
        shell.SetOpenImmediate(true)
        ids[section] = name
        if not original then
            local declaration = assert(shell.header._msuf2ControlSchema, "section schema owner missing")
            assert(declaration.id == shell.header._msuf2RuntimeControlRecord.controlId
                and declaration.scope == "colors" and declaration.applyDomain == "sectionNavigation",
                "section declaration contract drift: " .. name)
        end
    end
    mw:RunTimers()
    local prefix = M.ControlMeta("opt_colors", "advanced", "group_frame").controlId .. "."
    local expectedKinds = {
        ["group_frame.healer_mana.text_color"] = "color", ["group_frame.health.mode"] = "dropdown",
        ["group_frame.health.color"] = "color", ["group_frame.color.bg"] = "color",
        ["group_frame.health.fallback_mode"] = "dropdown", ["group_frame.state.dead_offline.enabled"] = "toggle",
        ["group_frame.color.deadBg"] = "color", ["group_frame.alpha.deadBgA"] = "slider",
        ["group_frame.state.dead_offline.include_offline"] = "toggle", ["group_frame.color.debuffStripeColor"] = "color",
        ["group_frame.alpha.debuffStripeAlpha"] = "slider", ["group_frame.color.target"] = "color",
        ["group_frame.color.hlFocusColor"] = "color", ["group_frame.color.groupBorder"] = "color",
        ["group_frame.alpha.groupBorderA"] = "slider", ["group_frame.color.ciAggroColor"] = "color",
    }
    local declarations = {}
    for path, kind in pairs(expectedKinds) do declarations[M.ControlMeta("opt_colors", "advanced", path).controlId] = kind end
    local controls, kinds, seenControls = {}, {}, {}
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(record.controlId).widget
        if record.pageKey == "opt_colors" and record.controlId:sub(1, #prefix) == prefix and w and (w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command) then
            ids[w] = record.controlId
            controls[#controls + 1] = w
            kinds[record.kind] = (kinds[record.kind] or 0) + 1
            assert(not seenControls[record.controlId] and declarations[record.controlId] == record.kind,
                "native control declaration identity/kind drift: " .. record.controlId)
            seenControls[record.controlId] = true
            if not original then
                local declaration = assert(w._msuf2ControlSchema, "ordinary schema missing: " .. record.controlId)
                assert(declaration.id == record.controlId and declaration.kind == declarations[record.controlId]
                    and declaration.scope == "colors" and declaration.applyDomain == "groupColors",
                    "ordinary declaration contract drift: " .. record.controlId)
            end
        end
    end
    table.sort(controls, function(a, b) return ids[a] < ids[b] end)
    assert(#controls == 16 and kinds.color == 9 and kinds.slider == 3 and kinds.dropdown == 2 and kinds.toggle == 2,
        "actual Group Colors input inventory drift: " .. #controls)
    for id in pairs(declarations) do assert(seenControls[id], "native control missing: " .. id) end
    print("Group Colors " .. flavor .. ": " .. #controls .. " actual ordinary inputs")
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
            assert(Encode(model, ids) == Encode(displayed, ids),
                "displayed widget/model drift at " .. tag .. ": " .. ids[w])
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
    local refresh = M.RunEntryRefreshers
    M.RunEntryRefreshers = function(...) refreshes = refreshes + 1 return refresh(...) end
    local defaults = F.CopySnapshot(env.MSUF_DB)
    local groupKeys = { "gf_party", "gf_raid", "gf_mythicraid" }
    local function Setup(state)
        Restore(env.MSUF_DB, defaults)
        for _, key in ipairs(groupKeys) do
            local group = assert(env.MSUF_DB[key], "factory group profile missing: " .. key)
            if state == "custom" or state == "edge" then
                group.gfBarMode, group.healthColorMode, group.deadBgEnabled = "CUSTOM", "CUSTOM", true
            end
            if state ~= "default" then group.unknownColorExtension = { enabled = false, amount = 0 } end
        end
        if state == "edge" then
            local party, raid = env.MSUF_DB.gf_party, env.MSUF_DB.gf_raid
            party.bgR, party.bgG, party.bgB = nil, false, 0
            raid.bgR, raid.bgG, raid.bgB = 0.22, 0.33, 0.44
            party.deadBgA, party.groupBorderA, party.healerManaTextR = 0, nil, 0
            raid.groupBorderA, party.deadBgOffline = false, 0
        end
        if state == "absent" then
            for _, groupKey in ipairs(groupKeys) do
                local group = env.MSUF_DB[groupKey]
                group.gfBarMode, group.healthColorMode, group.deadBgEnabled = nil, nil, nil
                for _, key in ipairs({ "bg", "deadBg", "debuffStripeColor", "target", "hlFocusColor", "groupBorder",
                    "ciAggroColor", "healerManaText", "healthCustom", "gfDark", "gfUnified" }) do
                    group[key .. "R"], group[key .. "G"], group[key .. "B"] = nil, nil, nil
                end
                group.deadBgA, group.debuffStripeAlpha, group.groupBorderA, group.deadBgOffline = nil, nil, nil, nil
            end
        end
        ExplicitRefresh(state)
        if state == "absent" then
            for _, key in ipairs(groupKeys) do
                local group = env.MSUF_DB[key]
                assert(group.gfBarMode == nil and group.healthColorMode == nil, "missing modes were materialized")
                for _, prefix in ipairs({ "healthCustom", "gfDark", "gfUnified" }) do
                    assert(group[prefix .. "R"] == nil and group[prefix .. "G"] == nil and group[prefix .. "B"] == nil,
                        "missing per-mode RGB was materialized: " .. prefix)
                end
            end
        end
        M.ClearHistory()
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
        if kind == "color" then return { 0, 0.25, 1 } end
        if kind == "toggle" then return not value end
        if kind == "slider" then return value == 1 and 0 or 1 end
        local values = w.values
        if type(values) == "function" then values = values() end
        for _, item in ipairs(values) do if item.value ~= value then return item.value end end
        error("dropdown has no alternate value")
    end
    Observe("factory")
    for _, state in ipairs({ "default", "custom", "edge", "absent" }) do
        Setup(state) Observe(state)
        for _, w in ipairs((narrow or mode == "layout" or state == "absent" or (mode == "push" and state == "edge")) and {} or controls) do
            Setup(state)
            if w:IsEnabled() then
            local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
            calls, refreshes = {}, 0
            Input(w, value)
            local after = F.CopySnapshot(env.MSUF_DB)
            assert(next(Diff(before, after)), "ordinary input did not change profile: " .. ids[w])
            Add(state .. ":input:" .. ids[w], value, Diff(before, after), ModelValue(w), DisplayValue(w), calls, refreshes)
            ExplicitRefresh(state .. ":input:" .. ids[w])
            local undo = M.Undo() mw:RunTimers()
            Add(state .. ":undo:" .. ids[w], undo, Diff(before, env.MSUF_DB), ModelValue(w), DisplayValue(w))
            CheckDisplayed(state .. ":undo:" .. ids[w])
            local redo = M.Redo() mw:RunTimers()
            Add(state .. ":redo:" .. ids[w], redo, Diff(after, env.MSUF_DB), ModelValue(w), DisplayValue(w))
            CheckDisplayed(state .. ":redo:" .. ids[w])
            if w._msuf2RuntimeControlRecord.kind == "color" and w._msuf2DefaultRGB then
                w:Click("RightButton") mw:RunTimers()
                Add(state .. ":right-reset:" .. ids[w], Diff(after, env.MSUF_DB), ModelValue(w), DisplayValue(w))
                CheckDisplayed(state .. ":right-reset:" .. ids[w])
            end
            Setup(state) before = F.CopySnapshot(env.MSUF_DB)
            core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return false end
            calls, refreshes = {}, 0
            Input(w, value)
            Add(state .. ":combat-edge:" .. ids[w], Diff(before, env.MSUF_DB), calls, refreshes)
            env.InCombatLockdown = function() return true end
            Input(w, value)
            Add(state .. ":combat:" .. ids[w], Diff(before, env.MSUF_DB), ModelValue(w), DisplayValue(w), M.Undo())
            core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
            mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
            else Add(state .. ":disabled:" .. ids[w], ModelValue(w), DisplayValue(w)) end
        end
    end
    local function Find(path)
        local id = M.ControlMeta("opt_colors", "advanced", path).controlId
        for _, w in ipairs(controls) do if ids[w] == id then return w end end
        error("mode control missing: " .. path)
    end
    local health = Find("group_frame.health.color")
    local barMode, fallback = Find("group_frame.health.mode"), Find("group_frame.health.fallback_mode")
    Setup("absent")
    assert(ModelValue(barMode)[1] == "GLOBAL" and DisplayValue(barMode)[1] == "GLOBAL", "missing bar mode fallback drift")
    assert(ModelValue(fallback)[1] == "CLASS" and DisplayValue(fallback)[1] == "CLASS", "missing health mode fallback drift")
    if not narrow and mode ~= "layout" then
        local function ModeHistory(tag, before, after)
            local undo = M.Undo() mw:RunTimers()
            Add(tag .. ":undo", undo, Diff(before, env.MSUF_DB))
            CheckDisplayed(tag .. ":undo")
            local redo = M.Redo() mw:RunTimers()
            Add(tag .. ":redo", redo, Diff(after, env.MSUF_DB))
            CheckDisplayed(tag .. ":redo")
        end
        for _, selector in ipairs({ barMode, fallback }) do
            local values = selector.values
            if type(values) == "function" then values = values() end
            assert(#values == (selector == barMode and 6 or 3), "supported mode inventory drift")
            for _, item in ipairs(values) do
                Setup("absent")
                local tag = "supported-mode:" .. ids[selector] .. ":" .. item.value
                local before = F.CopySnapshot(env.MSUF_DB)
                local priorMode = ModelValue(selector)[1]
                calls, refreshes = {}, 0
                Input(selector, item.value)
                local after = F.CopySnapshot(env.MSUF_DB)
                Add(tag .. ":input", item.value, Diff(before, after), ModelValue(selector), DisplayValue(selector), calls, refreshes)
                assert(DisplayValue(selector)[1] == item.value, "supported mode selection drift: " .. tag)
                for _, key in ipairs(groupKeys) do
                    local group = env.MSUF_DB[key]
                    if selector == barMode then
                        local stored = item.value ~= "GLOBAL" and item.value or nil
                        assert(group.gfBarMode == stored, "supported bar mode storage drift: " .. tag)
                        if item.value == "CLASS" or item.value == "GRADIENT" then
                            assert(group.healthColorMode == item.value, "bar mode fallback route drift: " .. tag)
                        else assert(group.healthColorMode == nil, "bar mode materialized fallback: " .. tag) end
                    else
                        local stored = item.value
                        if priorMode == item.value then stored = before[key].healthColorMode end
                        assert(group.healthColorMode == stored, "supported fallback storage drift: " .. tag)
                    end
                end
                if priorMode == item.value then
                    assert(not next(Diff(before, after)), "same-mode selection materialized profile state: " .. tag)
                    assert(#calls == 0, "same-mode selection applied settings: " .. tag)
                end
                ExplicitRefresh(tag)
                if next(Diff(before, after)) then ModeHistory(tag, before, after) end
                if selector == barMode then
                    local prefix = ({ dark = "gfDark", unified = "gfUnified", CUSTOM = "healthCustom" })[item.value]
                    assert(health:IsEnabled() == (prefix ~= nil), "health mode gate drift: " .. tag)
                    if prefix then
                        M.ClearHistory()
                        before = F.CopySnapshot(env.MSUF_DB)
                        Input(health, { 0, 0.25, 1 })
                        after = F.CopySnapshot(env.MSUF_DB)
                        for _, key in ipairs(groupKeys) do
                            local group = env.MSUF_DB[key]
                            assert(group[prefix .. "R"] == 0 and group[prefix .. "G"] == 0.25 and group[prefix .. "B"] == 1,
                                "per-mode health RGB setter drift: " .. item.value .. ":" .. prefix)
                        end
                        Add(tag .. ":health-input", Diff(before, after), ModelValue(health), DisplayValue(health))
                        ExplicitRefresh(tag .. ":health-input")
                        ModeHistory(tag .. ":health-input", before, after)
                    end
                end
            end
        end
    end
    Setup("edge")
    env.MSUF_DB.gf_party, env.MSUF_DB.gf_mythicraid = nil, nil
    M.Refresh() mw:RunTimers()
    for _, w in ipairs((narrow or mode == "layout") and {} or controls) do
        calls = {} Input(w, Alternate(w))
        Add("missing-group:" .. ids[w], F.CopySnapshot(env.MSUF_DB), calls)
    end
    mw:Select("home") mw:Select("opt_colors") M.ColorsSetPainterCategory("group") mw:RunTimers()
    Observe("reopen")
    return rows
end
local started = os.clock()
local total = 0
for _, narrow in ipairs({ false, true }) do
    local expected, actual = Replay(true, narrow), Replay(false, narrow)
    assert(#expected == #actual, "Group Colors observation count drift")
    for i = 1, #expected do
        if expected[i] ~= actual[i] then
            local file = assert(io.open(root .. "/.checks/group-colors-first-diff-" .. flavor .. ".txt", "wb"))
            file:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n") file:close()
            error("Group Colors drift at observation " .. i .. " " .. expected[i]:match("^[^\t]+"))
        end
    end
    total = total + #expected
end
print(string.format("menu_group_colors_schema_parity_smoke %s %s:16 controls/%d observations, declarations/400px/absent/modes/display/DB/apply/history/combat/default/custom/edge/reset/reopen exact (%.2fs)",
    mode, flavor, total, os.clock() - started))

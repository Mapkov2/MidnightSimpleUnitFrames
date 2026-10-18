-- Replay the three original page owners and their replacing rows in real client worlds.
-- The immutable parent is main commit e48e595c3, blob-identical to the batch's starting HEAD.
-- Scratch sources are never shipped.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local mutantPage, mutantPath = arg[3], arg[4] -- Optional scratch mutation of one page, only in the candidate world.
local base = "e48e595c3eef2009f5f4933ec5cf9303c36bed96"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local parentFiles = {}
assert(not root:find('["%%\r\n]') and flavor:match("^%w+$"), "unsafe scratch path")
local windows = package.config:sub(1, 1) == "\\"
local function Quote(s) return windows and ('"' .. s .. '"') or ("'" .. s:gsub("'", "'\\''") .. "'") end
os.execute((windows and "if not exist " or "mkdir -p ") .. Quote(root .. "/.checks")
    .. (windows and (" mkdir " .. Quote(root .. "/.checks")) or ""))
for _, name in ipairs({ "Unit", "UnitAlpha", "UnitText" }) do
    local file = "MSUF_Menu2_" .. name .. ".lua"
    local pipe = assert(io.popen("git -C " .. Quote(root) .. " show " .. base
        .. ":MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/" .. file, "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 1000, "parent source unavailable: " .. file)
    local path = root .. "/.checks/unitcore-parent-" .. flavor .. "-" .. file
    local out = assert(io.open(path, "wb"))
    out:write(source)
    out:close()
    parentFiles[file] = path
end
-- Every declaration the candidate pages own, as id, kind and apply domain. The id starts with @. for menu2.<page>.
-- Control rows must also match their registered record, chrome rows are pinned only here.
local DECLARED = [[
@.section.text.expanded toggle sectionNavigation
@.section.transparency.colors.health button contextColors
@.section.transparency.colors.resource button contextColors
@.section.transparency.expanded toggle sectionNavigation
@.unit.text.advanced.hptextlayer slider unit
@.unit.text.advanced.layers card layout
@.unit.text.advanced.nametextlayer slider unit
@.unit.text.advanced.powertextlayer slider unit
@.unit.text.hp.content card layout
@.unit.text.hp.content.colors button contextColors
@.unit.text.hp.content.preview font preview
@.unit.text.hp.content.preview.label text preview
@.unit.text.hp.decimals toggle unit
@.unit.text.hp.formatting text presentation
@.unit.text.hp.full_value_short toggle unit
@.unit.text.hp.mouseover toggle unit
@.unit.text.hp.mouseover.fadein slider unit
@.unit.text.hp.mouseover.fadeout slider unit
@.unit.text.hp.move_together toggle unit
@.unit.text.hp.position card layout
@.unit.text.hp.reverse toggle unit
@.unit.text.hp.separator dropdown unit
@.unit.text.hp.show toggle unit
@.unit.text.hp.slot.absorb segment unit
@.unit.text.hp.slot.hide_percent toggle unit
@.unit.text.hp.slot.mode dropdown unit
@.unit.text.hp.slot.size slider unit
@.unit.text.hp.slot_selector segment unit
@.unit.text.hp.visibility card layout
@.unit.text.hp.visibility.help text presentation
@.unit.text.name.anchor dropdown unit
@.unit.text.name.appearance card layout
@.unit.text.name.content card layout
@.unit.text.name.content.colors button contextColors
@.unit.text.name.content.preview font preview
@.unit.text.name.content.preview.label text preview
@.unit.text.name.mouseover toggle unit
@.unit.text.name.mouseover.fadein slider unit
@.unit.text.name.mouseover.fadeout slider unit
@.unit.text.name.position card layout
@.unit.text.name.show toggle unit
@.unit.text.name.size slider unit
@.unit.text.name.visibility card layout
@.unit.text.name.visibility.help text presentation
@.unit.text.power.content card layout
@.unit.text.power.content.colors button contextColors
@.unit.text.power.content.preview font preview
@.unit.text.power.content.preview.label text preview
@.unit.text.power.formatting text presentation
@.unit.text.power.mouseover toggle unit
@.unit.text.power.mouseover.fadein slider unit
@.unit.text.power.mouseover.fadeout slider unit
@.unit.text.power.move_together toggle unit
@.unit.text.power.navigation.class_resources button navigation
@.unit.text.power.position card layout
@.unit.text.power.separator dropdown unit
@.unit.text.power.show toggle unit
@.unit.text.power.slot.hide_percent toggle unit
@.unit.text.power.slot.mode dropdown unit
@.unit.text.power.slot.size slider unit
@.unit.text.power.slot_selector segment unit
@.unit.text.power.visibility card layout
@.unit.text.power.visibility.help text presentation
@.unit.text.workspace_tab segment menuState
@.unit.transparency.alpha_exclude_prediction_bars toggle alpha
@.unit.transparency.alpha_exclude_text_portrait toggle alpha
@.unit.transparency.health card layout
@.unit.transparency.hpbaralpha slider alpha
@.unit.transparency.hpbgalpha slider background
@.unit.transparency.ooc card layout
@.unit.transparency.ooc_fade_alpha slider oocAlpha
@.unit.transparency.ooc_fade_enabled toggle oocAlpha
@.unit.transparency.options card layout
@.unit.transparency.powerbaralpha slider powerAlpha
@.unit.transparency.powerbarbgalpha slider powerAlpha
@.unit.transparency.resource card layout
@.unit.transparency.state_selector segment navigation
]]
local function Encode(v, seen)
    if type(v) == "function" then return "<function>" end
    if type(v) ~= "table" then return tostring(v) end
    if v.GetObjectType then return "<widget>" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Encode(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Digest(text)
    local a, b = 5381, 52711
    for i = 1, #text do a, b = (a * 33 + text:byte(i)) % 4294967296, (b * 31 + text:byte(i)) % 4294967296 end
    return string.format("%08x%08x", a, b)
end
local function Run(parent)
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            world.widgets.Methods.GetCenter = function(f) return (f.width or 0) / 2, (f.height or 0) / 2 end
            if parent or mutantPath then
                local load = world.LoadFile
                world.LoadFile = function(self, path, ...)
                    local name = path:match("([^/\\]+)$")
                    local replacement = parent and parentFiles[name]
                        or (not parent and name == "MSUF_Menu2_" .. tostring(mutantPage) .. ".lua" and mutantPath)
                    return load(self, replacement or path, ...)
                end
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    local F = core.ProfileFields
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local output, calls, edits = {}, {}, 0
    local function Add(key, ...) output[#output + 1] = key .. "\t" .. Encode({ ... }) end
    for _, owner in ipairs({ M, M.ApplyService }) do
        for name, fn in pairs(owner) do
            if type(fn) == "function" and (owner ~= M or name == "Refresh" or name:match("^Request")) then
                owner[name] = function(...)
                    local a = { ... }
                    if a[1] and type(a[1]) == "table" and a[1].key then a[1] = a[1].key end
                    calls[#calls + 1] = name .. Encode(a)
                    return fn(...)
                end
            end
        end
    end
    local tips = {}
    env.GameTooltip.SetOwner = function() end
    env.GameTooltip.SetText = function(_, text) tips[#tips + 1] = text end
    env.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = text end
    env.GameTooltip.Show, env.GameTooltip.Hide = function() end, function() end
    local function Owned(w, entry)
        while w do
            for _, id in ipairs({ "text", "transparency" }) do
                local sec = entry.sections[id]
                if w == sec or (sec and w == sec._msuf2CollapsibleEntry.header) then return true end
            end
            w = w.GetParent and w:GetParent()
        end
        return false
    end
    local function Records(page)
        local out = {}
        for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local w = M.RuntimeControlCatalog.Get(r.controlId).widget
            if r.pageKey == page and w and Owned(w, M.cache[page]) then out[#out + 1] = { r = r, w = w } end
        end
        return out
    end
    local function Refresh(page)
        M.Refresh(M.cache[page].ctx)
        mw:RunTimers()
    end
    local function Gates(rows)
        local out = {}
        for _, c in ipairs(rows) do
            local shown, w = true, c.w
            while w do
                shown = shown and w:IsShown()
                w = w.GetParent and w:GetParent()
            end
            out[c.r.controlId] = { c.w:IsEnabled(), shown, c.w.GetValue and c.w:GetValue(), c.w.checked }
        end
        return out
    end
    local function Layout(page)
        local out, names = {}, {}
        local function Name(f)
            if not f or not Owned(f, M.cache[page]) then return "external" end
            if names[f] then return names[f] end
            names[f] = Name(f:GetParent()) .. "/" .. f:GetObjectType() .. ":" .. Encode(f.text or "")
                .. ":" .. tostring(f.width) .. "x" .. tostring(f.height)
            return names[f]
        end
        local function Include(f)
            local points = {}
            for i = 1, f:GetNumPoints() do
                local a, p, b, x, y = f:GetPoint(i)
                points[#points + 1] = { a, Name(p), b, x, y }
            end
            out[#out + 1] = Encode({ Name(f), points, f:IsShown(), f:IsEnabled(), f.alpha, f.texture, f.level })
            for _, r in ipairs(f.regions or {}) do Include(r) end
        end
        for _, f in ipairs(mw.world.widgets.frames) do if Owned(f, M.cache[page]) then Include(f) end end
        table.sort(out)
        return #out, Digest(table.concat(out, "\n"))
    end
    -- Every schema declaration on an owned frame or region: scope is the unit, and the
    -- id, kind and apply domain are pinned. Control declarations also match their record.
    local function CheckDeclarations(page, unit, rows)
        local prefix = "menu2." .. page .. "."
        local expected, actual, seen = {}, {}, {}
        for id, kind, domain in DECLARED:gmatch("(%S+) (%S+) (%S+)") do
            expected[id:gsub("^@%.", prefix)] = kind .. " " .. domain
        end
        local function Visit(f)
            if seen[f] then return end
            seen[f] = true
            local spec = f._msuf2ControlSchema
            if spec then
                assert(spec.scope == unit, "declared scope " .. tostring(spec.id) .. " " .. tostring(spec.scope))
                assert(actual[spec.id] == nil, "duplicate declaration " .. tostring(spec.id))
                actual[spec.id] = spec.kind .. " " .. tostring(spec.applyDomain)
            end
            for _, region in ipairs(f.regions or {}) do Visit(region) end
        end
        for _, f in ipairs(mw.world.widgets.frames) do if Owned(f, M.cache[page]) then Visit(f) end end
        for _, c in ipairs(rows) do
            local spec = assert(c.w._msuf2ControlSchema, "undeclared control " .. c.r.controlId)
            assert(spec.id == c.r.controlId and spec.kind == c.r.kind and spec.scope == unit,
                "declaration differs from its record " .. c.r.controlId .. " " .. tostring(spec.kind))
        end
        if os.getenv("UNITCORE_DUMP") then
            local lines = {}
            for id, what in pairs(actual) do lines[#lines + 1] = (id:gsub("^" .. prefix:gsub("%.", "%%."), "@.")) .. " " .. what end
            table.sort(lines)
            print("DECLARED " .. page .. "\n" .. table.concat(lines, "\n"))
        end
        for id, what in pairs(actual) do
            assert(expected[id] == what, "declaration " .. id .. ": " .. what .. " expected " .. tostring(expected[id]))
        end
        for id, what in pairs(expected) do assert(actual[id] == what, "declaration missing " .. id .. " " .. what) end
    end
    local function Snapshot(page, state, rows)
        Add(page .. ":" .. state .. ":layout", Layout(page))
        for i, c in ipairs(rows) do
            local r, w = c.r, c.w
            local command = w._msuf2CommandAction or r.command
            local lo, hi
            if r.kind == "slider" then lo, hi = w:GetMinMaxValues() end
            local values = w.GetValues and w:GetValues() or w.values
            if type(values) == "function" then values = values() end
            tips = {}
            World.FireScript(w, "OnEnter")
            World.FireScript(w, "OnLeave")
            Add(page .. ":" .. state .. ":" .. r.controlId, i, r.kind, r.label, r.settingKey, r.controlPath,
                r.classification, r.searchSettingKeys, r.searchSettingKeyPatterns, r.actionKey,
                w._msuf2SearchMeta, lo, hi, w.valueStep, values, command and command.get and command.get(), tips)
        end
        Add(page .. ":" .. state .. ":gates", Gates(rows))
    end
    local function Input(c, value)
        local w, kind = c.w, c.r.kind
        if not w:IsEnabled() then return end
        if kind == "toggle" then
            w:SetChecked(value)
            w:Click("LeftButton")
        elseif kind == "segment" then
            local found = false
            for _, b in ipairs(w.buttons or {}) do
                if b._msuf2Value == value then
                    b:Click("LeftButton")
                    found = true
                    break
                end
            end
            assert(found, "segment input missing " .. c.r.controlId .. " " .. tostring(value))
        elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
        elseif kind == "slider" then
            w:SetValue(value)
            World.FireScript(w, "OnValueChanged", value)
        else error("unhandled input " .. kind) end
        mw:RunTimers()
    end
    local function NextValue(c, edge)
        local w, kind = c.w, c.r.kind
        local cmd = w._msuf2CommandAction or c.r.command
        local current
        if cmd and cmd.get then current = cmd.get() elseif w.GetValue then current = w:GetValue() end
        if kind == "toggle" then return not current end
        if kind == "slider" then
            local lo, hi = w:GetMinMaxValues()
            local v = edge and hi or (lo + (hi - lo) / 2)
            return v == current and lo or v
        end
        local values = w.GetValues and w:GetValues() or w.values
        if type(values) == "function" then values = values() end
        for i = 1, #(values or {}) do
            local item = values[edge and (#values + 1 - i) or i]
            if item.value ~= current then return item.value end
        end
        error("no input choice " .. c.r.controlId)
    end
    local function Edit(page, state, rows, c)
        M.ClearHistory()
        local before = F.CopySnapshot(env.MSUF_DB)
        local value = NextValue(c, state == "edge")
        calls = {}
        -- Test refusal with a DIFFERENT input before the successful edit.
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        Input(c, value)
        Add(page .. ":" .. state .. ":combat:" .. c.r.controlId, calls, F.Equal(before, env.MSUF_DB), M.GetHistoryState().undoCount)
        assert(F.Equal(before, env.MSUF_DB), "combat DB write " .. c.r.controlId)
        core.Util.InCombat("PLAYER_REGEN_ENABLED")
        M.ClearHistory()
        calls = {}
        Input(c, value)
        local after = F.CopySnapshot(env.MSUF_DB)
        Add(page .. ":" .. state .. ":input:" .. c.r.controlId, value, Digest(Encode(after)), calls,
            M.GetHistoryState().undoCount, Gates(rows))
        if not F.Equal(before, after) then
            assert(M.GetHistoryState().undoCount > 0, "lost history entry " .. c.r.controlId)
            assert(M.Undo() and F.Equal(before, env.MSUF_DB), "lost history " .. c.r.controlId)
            assert(M.Redo() and F.Equal(after, env.MSUF_DB), "lost redo " .. c.r.controlId)
        end
        Refresh(page)
        Add(page .. ":" .. state .. ":refresh:" .. c.r.controlId, Gates(rows))
        edits = edits + 1
    end
    Add("unit-pages", M.UnitPage.UNIT_PAGES, M.UnitPage.UNIT_COPY_TARGETS, M.UnitPage.SectionFields)
    for _, unit in ipairs({ "player", "target" }) do
        local page = "uf_" .. unit
        assert(mw:Select(page))
        local entry = M.cache[page]
        for _, id in ipairs({ "text", "transparency" }) do entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        mw:RunTimers()
        Refresh(page)
        local rows = Records(page)
        if not parent then CheckDeclarations(page, unit, rows) end
        local initial = F.CopySnapshot(env.MSUF_DB[unit])
        local function Prepare(state, c, tab)
            local conf = env.MSUF_DB[unit]
            for key in pairs(conf) do conf[key] = nil end
            -- The absent state is a profile without any of the exercised keys: every getter and
            -- refresh falls back to its page default.
            if state ~= "absent" then
                for key, value in pairs(F.CopySnapshot(initial)) do conf[key] = value end
            end
            M.unitTextSlotSelection[unit] = { hp = "right", power = "right" }
            M.unitTextMoveTogether[unit] = { hp = true, power = true }
            if state == "edge" then
                conf.showName, conf.showHP, conf.showPowerText = true, true, true
                conf.nameTextMouseover, conf.hpTextMouseover, conf.powerTextMouseover = true, true, true
                conf.oocFadeEnabled, conf.hpBarAlpha, conf.nameFontSize = true, 0, nil
                conf.textCenter, conf.powerTextCenter = "CURPERCENTABSORB", "CURPERCENT"
                conf.hpTextCenterAbsorbIcon, conf.hpTextCenterHidePercentSymbol = true, false
                M.unitTextSlotSelection[unit] = { hp = "center", power = "center" }
                M.unitTextMoveTogether[unit] = { hp = false, power = false }
            end
            local path = c and c.r.controlId or ""
            tab = tab or path:match("%.text%.(hp)%.") or path:match("%.text%.(power)%.")
                or path:match("%.text%.(advanced)%.") or "name"
            entry.sections.text._msuf2GuidedSelectTab(tab)
            for _, row in ipairs(rows) do
                if row.r.controlId:find("transparency.state_selector", 1, true) then
                    row.w:SetValue(path:find("ooc", 1, true) and "ooc" or "combat")
                end
            end
            Refresh(page)
        end
        for _, state in ipairs({ "default", "edge" }) do
            Prepare(state)
            Snapshot(page, state, rows)
            for _, c in ipairs(rows) do
                if c.r.kind == "toggle" or c.r.kind == "slider" or c.r.kind == "dropdown" or c.r.kind == "segment" then
                    Prepare(state, c)
                    Edit(page, state, rows, c)
                end
            end
        end
        for _, tab in ipairs({ "name", "hp", "power", "advanced" }) do
            Prepare("absent", nil, tab)
            Snapshot(page, "absent-" .. tab, rows)
        end
        mw:Select("home")
        mw:Select(page)
        Refresh(page)
        Snapshot(page, "reopen", rows)
    end
    -- Unit.lua owns copy field lists, source defaults and the status icon strip helper.
    M.ClearHistory()
    calls = {}
    local beforeCopy = F.CopySnapshot(env.MSUF_DB)
    M.UnitPage.CopyUnitSettings("player", "target", { text = true, transparency = true })
    mw:RunTimers()
    Add("unit-copy", env.MSUF_DB.target, calls, M.GetHistoryState().undoCount)
    if not F.Equal(beforeCopy, env.MSUF_DB) then assert(M.Undo() and F.Equal(beforeCopy, env.MSUF_DB), "copy history") end
    local strip, holders = M.UnitPage.CreateStatusIconStrip(M.cache.uf_target.sections.text, -32, 220)
    assert(#holders == 5 and strip:GetWidth() == 220 and holders[1].tex:GetWidth() == 22, "status strip geometry")
    Add("status-assets", M.UnitPage.StatusIconAssetValues({}), #holders)
    assert(edits >= 160, "incomplete ordinary control replay")
    return output, edits
end
local before, count = Run(true)
collectgarbage("collect")
local after = Run(false)
assert(#before == #after, "parity receipt count changed")
for i = 1, #before do
    assert(before[i] == after[i], "unitcore parity " .. flavor .. " row " .. i .. "\nPARENT " .. before[i] .. "\nCURRENT " .. after[i])
end
print("menu_unitcore_parity_smoke: " .. flavor .. " PASS (" .. count .. " inputs per version, " .. #before .. " receipts)")

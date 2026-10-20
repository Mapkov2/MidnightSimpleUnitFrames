-- Replay both castbar settings owners against immutable parent blobs through real menu input.
-- The immutable parent is materialized under .checks; no git metadata is written.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local push = arg[3] == "--push" or arg[4] == "--push"
local candidate = arg[3] ~= "--push" and arg[3] or nil
local parents = {
    MSUF_Menu2_GlobalCastbars = "7b001d859d1775eec3aefef6aaa582ee94a6ee1d",
    MSUF_Menu2_UnitFrameVisuals = "6fbd040a1ab7e9f8204b31d31f3ddd17ed6aaa1c",
}
local scratch, sources = root .. "/.checks", {}
assert(not root:find('["%%\r\n]'), "unsafe worktree path")
for name, blob in pairs(parents) do
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. blob, "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 1000 and source:find("local M =", 1, true), "parent blob unavailable: " .. blob)
    local path = scratch .. "/castbars-parent-" .. flavor .. "-" .. name .. ".lua"
    local file = io.open(path, "wb")
    if not file then
        os.execute('mkdir "' .. scratch .. '"')
        file = assert(io.open(path, "wb"))
    end
    file:write(source)
    file:close()
    sources[name .. ".lua"] = path
end
local function Encode(v, seen)
    local t = type(v)
    if t == "function" then return "<function>" end
    if t == "string" then
        -- Catalog revision strings alone can contain process-local widget addresses.
        if v:find("table:", 1, true) then
            v = v:gsub("table: 0x%x+", "<widget-address>"):gsub("table: %x+", "<widget-address>")
        end
        return "string:" .. v
    end
    if t == "boolean" then return v and "boolean:true" or "boolean:false" end
    if t ~= "table" then return t .. ":" .. tostring(v) end
    if v.GetObjectType then return "<widget>" end
    -- Compare refresh targets by identity; widget state and geometry are recorded separately.
    if type(v.SetContentHeight) == "function" and type(v.key) == "string" then
        return "context:" .. v.key .. ":width:" .. tostring(v.width)
    end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys, values, keyType, mixed = {}, {}, nil, false
    for k in pairs(v) do
        keys[#keys + 1] = k
        local current = type(k)
        if keyType and keyType ~= current then mixed = true end
        keyType = keyType or current
    end
    if not mixed and (keyType == "number" or keyType == "string") then table.sort(keys)
    else table.sort(keys, function(a, b) return tostring(a) < tostring(b) end) end
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
local function Run(prior, expected)
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
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                local name = path:match("([^/\\]+)$")
                if prior then path = sources[name] or path
                elseif candidate and sources[name] then path = candidate .. "/" .. name end
                return load(self, path, ...)
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
    local contexts, createContext = {}, M.CreateContext
    M.CreateContext = function(key, ...)
        local ctx = createContext(key, ...)
        contexts[key] = ctx
        return ctx
    end
    for index, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
        local viewer = env.CreateFrame("Frame", nil, env.UIParent)
        viewer:SetSize(300 + index * 40, 32)
        viewer:Show()
        env[name] = viewer
    end
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
                level = level + 1
                info = debug.getinfo(level, "S")
            end
            local file = info and info.source:match("(MSUF_Menu2_[%w]+%.lua)$")
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
        if expected and expected[key] ~= output[key] then
            for name, value in pairs({ expected = expected[key] or "<missing>", actual = output[key] }) do
                local file = assert(io.open(scratch .. "/castbars-" .. flavor .. "-" .. name .. ".txt", "wb"))
                file:write(key, "\n", value)
                file:close()
            end
            error(flavor .. ": parity mismatch " .. key)
        end
    end
    local function Diff(a, b, path, out)
        path, out = path or "", out or {}
        if a == b then return out end
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
        elseif kind == "toggle" then w:SetChecked(value)
            w:Click("LeftButton")
        elseif w.buttons then
            for _, button in ipairs(w.buttons) do
                if button._msuf2Value == value then button:Click("LeftButton") end
            end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        elseif w._msuf2OnCommit then w._msuf2OnCommit(value)
        else w:SetValue(value)
            World.FireScript(w, "OnValueChanged", value) end
        mw:RunTimers()
    end
    local function InCastbar(w, page)
        if page == "opt_castbar" then return true end
        local sec = M.cache[page].sections.castbar
        while w do
            if w == sec or w == sec._msuf2CollapsibleEntry.header then return true end
            w = w.GetParent and w:GetParent()
        end
        return false
    end
    local function Records(page)
        local rows = {}
        for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if r.pageKey == page then
                local record = M.RuntimeControlCatalog.Get(r.controlId)
                if record.widget and (InCastbar(record.widget, page) or r.controlId:find(".navigation.", 1, true)
                    or r.controlId:find(".copy.open", 1, true)) then
                    rows[#rows + 1] = record
                end
            end
        end
        table.sort(rows, function(a, b) return a.controlId < b.controlId end)
        return rows
    end
    local stateRows, lifecycleRows, pushSamples = {}, {}, {}
    local function ReplayRow(page, r, edge)
        -- The nightly/default replay keeps every unit identity in both states.
        local identity = page .. ":" .. r.controlId .. ":" .. tostring(edge)
        assert(not lifecycleRows[identity], "duplicate lifecycle: " .. identity)
        if not push or r.kind == "button" then return true end
        -- Push samples each workspace/kind on every unit, including the Focus
        -- detail slider that a unit-erasing replay previously missed.
        if r.settingKey == "general.castbarInterruptShake"
            or r.settingKey == "general.castbarFocusSpellNameFontSize" then return true end
        local area = page == "opt_castbar" and r.controlId:match("^menu2%.opt%.castbar%.global%.([^.]+)") or r.workspace
        local sample = page .. ":" .. tostring(area) .. ":" .. r.kind .. ":" .. tostring(edge)
        if pushSamples[sample] then return false end
        pushSamples[sample] = true
        return true
    end
    local function State(page)
        local out = {}
        for _, r in ipairs(stateRows[page] or Records(page)) do
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
        for id in pairs(sections) do
            if page == "opt_castbar" or id == "castbar" then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local entry = sections[id]._msuf2CollapsibleEntry
            if entry then entry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        M.Refresh(contexts[page])
        mw:RunTimers()
    end
    local function Choice(r, w, edge)
        local command = Command(w)
        if r.kind == "toggle" then return not command.get() end
        if r.kind == "color" then return edge and { 0, 0.25, 1 } or { 0.7, 0.4, 0.2 } end
        if r.kind == "slider" then
            local low, high = w:GetMinMaxValues()
            if edge and r.settingKey and r.settingKey:match("IconBorderThickness$") then return 1 end
            return edge and low or high
        end
        if r.controlId:find("spell_text_width_mode", 1, true) or r.controlId:find("spell.text.width.mode", 1, true) then
            return edge and "NONE" or "CLIP"
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
    local function Layout(parent)
        local frames, ids, seen = {}, {}, {}
        local function Include(w)
            if seen[w] then return end
            seen[w], ids[w], frames[#frames + 1] = true, #frames + 1, w
            for _, region in ipairs(w.regions or {}) do Include(region) end
        end
        for _, w in ipairs(mw.world.widgets.frames) do
            local ancestor = w
            while ancestor and ancestor ~= parent do ancestor = ancestor.GetParent and ancestor:GetParent() end
            if ancestor then Include(w) end
        end
        local out = {}
        for _, w in ipairs(frames) do
            local points = {}
            for i = 1, w:GetNumPoints() do
                local a, relative, b, x, y = w:GetPoint(i)
                points[#points + 1] = { a, ids[relative] or "external", b, x, y }
            end
            local meta = w._msuf2SearchMeta
            out[#out + 1] = { ids[w:GetParent()] or "external", w:GetObjectType(), w.text, w.width, w.height,
                points, w:IsShown(), w:IsEnabled(), w.alpha, w.texture, w._msuf2ControlKind,
                meta and meta.label, w._msuf2StableSearchLabel, meta and meta.workspace }
        end
        return out
    end
    local function PageChrome(page, tag)
        if page == "opt_castbar" then return end
        for _, r in ipairs(Records(page)) do
            if r.controlId:find(".copy.open", 1, true) then
                r.widget:Click()
                mw:RunTimers()
                local popup
                for _, w in ipairs(mw.world.widgets.frames) do
                    if w._targetBtns and w._checks and w:IsShown() then popup = w end
                end
                assert(popup, "Copy To popup missing")
                Add(tag .. ":copy-popup", Layout(popup))
                for i, check in ipairs(popup._checks) do
                    check:SetChecked(not check:GetChecked())
                    check:Click()
                    Add(tag .. ":copy-category:" .. i, check:GetChecked(), F.CopySnapshot(env.MSUF_DB))
                end
                local targets = {}
                for key in pairs(popup._targetBtns) do targets[#targets + 1] = key end
                table.sort(targets)
                for _, key in ipairs(targets) do
                    local button = popup._targetBtns[key]
                    if button:IsShown() then
                        button:Click()
                        Add(tag .. ":copy-target:" .. key, Layout(popup))
                    end
                end
                for _, w in ipairs(mw.world.widgets.frames) do
                    if w:GetParent() == popup and w._msuf2Label and not w._msuf2CopyTarget then
                        local text = w._msuf2Label:GetText()
                        if text == "All" or text == "None" then
                            w:Click()
                            Add(tag .. ":copy-" .. text, Layout(popup))
                        end
                    end
                end
                -- Exercise the actual Castbar category copy without copying unrelated unit options.
                for _, check in ipairs(popup._checks) do
                    check:SetChecked(check._msuf2Label:GetText() == "Castbar")
                    check:Click()
                end
                local destination = page == "uf_player" and "target" or "player"
                popup._targetBtns[destination]:Click()
                local before = F.CopySnapshot(env.MSUF_DB)
                M.ClearHistory()
                calls = {}
                popup._runBtn:Click()
                mw:RunTimers()
                local after = F.CopySnapshot(env.MSUF_DB)
                Add(tag .. ":copy-run", Diff(before, after), calls)
                Add(tag .. ":copy-undo", M.Undo())
                mw:RunTimers()
                Add(tag .. ":copy-restored", Diff(before, env.MSUF_DB))
                Add(tag .. ":copy-redo", M.Redo())
                mw:RunTimers()
                Add(tag .. ":copy-redone", Diff(after, env.MSUF_DB))
                for _, change in ipairs(F.Diff(env.MSUF_DB, before)) do F.Write(env.MSUF_DB, change.path, change.value) end
                M.ClearHistory()
                core.Util.InCombat("PLAYER_REGEN_DISABLED")
                calls = {}
                popup._runBtn:Click()
                Add(tag .. ":copy-combat", Diff(before, env.MSUF_DB), calls, M.Undo())
                core.Util.InCombat("PLAYER_REGEN_ENABLED")
                mw:Fire("PLAYER_REGEN_ENABLED")
                mw:RunTimers()
                popup:Hide()
            end
        end
        for _, r in ipairs(Records(page)) do
            if r.controlId:find(".navigation.", 1, true) then
                local widget = r.widget
                local value = page == "uf_player" and "target" or "player"
                local before = F.CopySnapshot(env.MSUF_DB)
                Input(widget, "segment", value)
                Add(tag .. ":scope-navigation", M.activeKey, Diff(before, env.MSUF_DB), widget:GetValue())
                assert(M.activeKey == "uf_" .. value, "scope navigation did not reach its destination")
                assert(mw:Select(page))
                Expand(page)
            end
        end
    end
    -- A clean profile, replaced edge profile, absent keys and a narrow rebuild.
    local readKeys, pages = {}, { "opt_castbar" }
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local page = "uf_" .. unit
        if M.pages[page] then pages[#pages + 1] = page end
    end
    local function ClearPath(path)
        local owner, key = path:match("^([^.]+)%.(.+)$")
        if owner and env.MSUF_DB[owner] then env.MSUF_DB[owner][key] = nil end
    end
    local function CompoundKeys(page)
        if page == "opt_castbar" then return { "general.focusKickPreviewTestMode" } end
        local unit = page:sub(4)
        local fields = M.UnitPage.CASTBAR_FIELDS[unit]
        local prefix = ({ player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus",
            boss = "bossCast", arena = "arenaCast" })[unit]
        return { unit .. ".portraitCastSpellIcon", "general." .. fields.enable, "general." .. fields.backend,
            "general." .. (fields.providerMemory or fields.backend .. "BeforeHide"),
            "general." .. prefix .. "SpellNameTruncate", "general." .. prefix .. "SpellNameMaxWidth" }
    end
    for state = 1, 4 do
        local edge, absent, narrow = state == 2, state == 3, state == 4
        M.formContentMaxWidth = narrow and 420 or nil
        for _, page in ipairs(pages) do
            if edge then
                env.MSUF_DB.general = F.CopySnapshot(env.MSUF_DB.general)
                local g = env.MSUF_DB.general
                core.SuiteLink.HasNameplateKickReady = function() return true end
                core.SuiteLink.ModuleTitle = function() return "Nameplates" end
                core.KickReady.HasConsumers = function() return true end
                for _, key in ipairs({ "enableFocusKickIcon", "showGCDBar", "gcdBarDetached",
                    "kickReadyShowTarget", "castbarShowChannelTicks", "empowerStageBlink" }) do g[key] = true end
                g.castbarSpellNameShortening, g.focusKickIconHeight = 1, 64
                g.focusKickTextSize = nil
                g.focusKickIconOffsetX, g.focusKickIconOffsetY = -73, 41
                g.kickReadyAutoSize, g.kickReadyStyle = false, "box"
                if page ~= "opt_castbar" then
                    local unit = page:sub(4)
                    env.MSUF_DB[unit] = F.CopySnapshot(env.MSUF_DB[unit])
                    env.MSUF_DB[unit].enabled, env.MSUF_DB[unit].portraitMode = true, "RIGHT"
                    local fields = M.UnitPage.CASTBAR_FIELDS[unit]
                    g[fields.backend], g[fields.enable] = "MSUF", true
                    for _, key in ipairs({ fields.icon, fields.text, fields.time, fields.targetName }) do g[key] = true end
                    local source = ({ player = "castbarPlayerMatchWidth", target = "castbarTargetMatchWidth",
                        focus = "castbarFocusMatchWidth", boss = "bossCastbarMatchWidth", arena = "arenaCastbarMatchWidth" })[unit]
                    g[source] = nil
                    local prefix = ({ player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus",
                        boss = "bossCast", arena = "arenaCast" })[unit]
                    g[prefix .. "SpellNameTruncate"], g[prefix .. "IconBorderStyle"] = "CLIP", "NONE"
                end
            end
            if absent then
                for path in pairs(readKeys[page]) do ClearPath(path) end
                for _, path in ipairs(CompoundKeys(page)) do ClearPath(path) end
            end
            owned = {}
            M.InvalidatePage(page)
            assert(mw:Select(page), "page missing: " .. page)
            Expand(page)
            if edge then
                env.MSUF_DB.general = F.CopySnapshot(env.MSUF_DB.general)
                if page ~= "opt_castbar" then
                    local unit = page:sub(4)
                    env.MSUF_DB[unit] = F.CopySnapshot(env.MSUF_DB[unit])
                end
                M.Refresh(contexts[page])
                mw:RunTimers()
            end
            if page == "opt_castbar" and (flavor == "Mainline" or flavor == "Forever") then
                assert(M.cache[page].sections.castbar_gcd, "GCD Bar section was not built: " .. flavor)
            end
            local tag = page .. ":" .. state
            if narrow then
                local section = M.cache[page].sections[page == "opt_castbar" and "castbar_behavior" or "castbar"]
                assert(section._msuf2Width <= 420, "narrow rebuild did not constrain content")
            end
            Add(tag .. ":profile-after-build", env.MSUF_DB)
            local declarations = {}
            for i, item in ipairs(owned) do
                local widget, constructor = item[1], item[2]
                if InCastbar(widget, page) then
                    if not prior then
                        local declaration = assert(widget._msuf2ControlSchema, "undeclared " .. page .. " " .. constructor)
                        assert(declaration.id and declaration.kind and declaration.scope and declaration.applyDomain,
                            "incomplete row: " .. tostring(declaration.id))
                        assert(not declaration.id:find("[%s&]"), "unreadable control ID: " .. declaration.id)
                        assert(not declarations[declaration.id] or declarations[declaration.id] == widget,
                            "duplicate declaration: " .. declaration.id)
                        declarations[declaration.id] = widget
                        assert(declaration.scope == (page == "opt_castbar" and page or page:sub(4)),
                            "wrong declaration scope: " .. declaration.id)
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
                        widget._msuf2SearchRegistryId ~= nil, widget._msuf2SearchMeta and widget._msuf2SearchMeta.label,
                        widget._msuf2StableSearchLabel, widget._msuf2SearchMeta and widget._msuf2SearchMeta.workspace)
                end
            end
            Add(tag .. ":page-chrome", Layout(M.cache[page].wrapper))
            local rows = Records(page)
            stateRows[page] = rows
            Add(tag .. ":count", #rows)
            local searched = {}
            for _, widget in ipairs(M.cache[page].searchWidgets or {}) do
                searched[#searched + 1] = tostring(widget._msuf2SearchText or widget._msuf2SearchTitle) .. "|"
                    .. tostring(widget._msuf2ControlKind) .. "|" .. tostring(widget._msuf2SearchRegistryId ~= nil)
            end
            Add(tag .. ":search", searched)
            readKeys[page] = readKeys[page] or {}
            for _, r in ipairs(rows) do
                if r.settingKey and r.settingKey ~= "" and not absent then readKeys[page][r.settingKey] = true end
            end
            local function Views()
                local unit = page ~= "opt_castbar" and page:sub(4) or nil
                local own, other = {}, {}
                for key, value in pairs(env.MSUF_DB) do
                    if key == "general" or key == "bars" or key == unit then own[key] = value
                    else other[key] = value end
                end
                return own, other
            end
            local function Snapshot()
                local own = Views()
                return F.CopySnapshot(own)
            end
            local _, other = Views()
            local foreignBaseline = F.CopySnapshot(other)
            local function ForeignChanges()
                local _, current = Views()
                return Diff(foreignBaseline, current)
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
                        w.GetValues and w:GetValues() or w.values, tips, w._msuf2StableSearchLabel,
                        w._msuf2SearchMeta and w._msuf2SearchMeta.label, r.workspace,
                        command and command.get and { command.get() })
                    local kind = r.kind
                    local ordinary = kind == "toggle" or kind == "slider" or kind == "dropdown"
                        or kind == "segment" or kind == "color" or kind == "textinput"
                    -- Scope navigation rebuilds its page and is replayed separately below.
                    local navigation = r.controlId:find(".navigation.", 1, true)
                    local button = kind == "button" and (r.classification == "setting" or r.classification == "action")
                    local editable = ordinary and command and command.get and command.set and not navigation
                    if (editable or button) and not absent and not narrow and ReplayRow(page, r, edge) then
                        targets[r.controlId] = true
                        local original = Snapshot()
                        if button then
                            local g = env.MSUF_DB.general
                            if r.controlId:match("%.castbar%.use[_%.]msuf$") then
                                local fields = M.UnitPage.CASTBAR_FIELDS[page:sub(4)]
                                local backend = edge and page == "uf_player" and "BLIZZARD" or "HIDE"
                                g[fields.backend], g[fields.enable] = backend, false
                                g[fields.providerMemory or fields.backend .. "BeforeHide"] = edge and "BLIZZARD" or "MSUF"
                            elseif r.controlId:find(".focus.kick.reset.position", 1, true) then
                                g.enableFocusKickIcon = true
                                g.focusKickIconOffsetX, g.focusKickIconOffsetY = edge and -73 or 71, edge and 41 or -19
                            end
                            M.Refresh(contexts[page])
                            mw:RunTimers()
                        end
                        local value = "click"
                        if not button then value = Choice(r, w, edge) end
                        assert(value ~= nil, "no input value: " .. r.controlId)
                        local function Act()
                            if button then w:Click("LeftButton")
                                mw:RunTimers()
                            else Input(w, kind, value) end
                        end
                        M.ClearHistory()
                        local before = Snapshot()
                        calls = {}
                        Act()
                        M.Refresh(contexts[page])
                        mw:RunTimers()
                        local after = Snapshot()
                        local key = tag .. (button and ":button:" or ":input:") .. r.controlId
                        Add(key, value, Diff(before, after), calls, State(page), ForeignChanges())
                        if button then
                            assert(next(Diff(before, after)), "button input made no DB change: " .. r.controlId)
                        end
                        calls = {}
                        local undo = M.Undo()
                        mw:RunTimers()
                        Add(key .. ":undo", undo, Diff(before, (Views())), calls, State(page), ForeignChanges())
                        if button then assert(undo, "button history missing: " .. r.controlId) end
                        -- Keep redo pending while both combat signals refuse the same input.
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        env.InCombatLockdown = function() return false end
                        calls = {}
                        Act()
                        Add(key .. ":combat-edge", Diff(before, (Views())), calls, M.Undo(), State(page), ForeignChanges())
                        env.InCombatLockdown = function() return true end
                        calls = {}
                        Act()
                        Add(key .. ":combat", Diff(before, (Views())), calls, M.Undo(), State(page), ForeignChanges())
                        core.Util.InCombat("PLAYER_REGEN_ENABLED")
                        env.InCombatLockdown = function() return false end
                        mw:Fire("PLAYER_REGEN_ENABLED")
                        mw:RunTimers()
                        calls = {}
                        local redo = M.Redo()
                        mw:RunTimers()
                        Add(key .. ":redo", redo, Diff(after, (Views())), calls, State(page), ForeignChanges())
                        if button then assert(redo, "button redo missing: " .. r.controlId) end
                        lifecycleRows[page .. ":" .. r.controlId .. ":" .. tostring(edge)] = true
                        for _, change in ipairs(F.Diff((Views()), original)) do
                            F.Write(env.MSUF_DB, change.path, change.value)
                        end
                        M.Refresh(contexts[page])
                        mw:RunTimers()
                        M.ClearHistory()
                    end
                end
            end
            if not absent and not narrow then
                local replayed = 0
                for _, r in ipairs(rows) do
                    local command = Command(r.widget)
                    local setting = command and command.get and command.set and r.kind ~= "button"
                        and not r.controlId:find(".navigation.", 1, true)
                    local button = r.kind == "button" and (r.classification == "setting" or r.classification == "action")
                    local complete = lifecycleRows[page .. ":" .. r.controlId .. ":" .. tostring(edge)]
                    if complete then replayed = replayed + 1 end
                    if (setting or button) and (not push or button) then
                        assert(complete,
                            "missing instance lifecycle: " .. tag .. ":" .. r.controlId)
                    end
                end
                assert(replayed >= 4, "insufficient page lifecycle replay: " .. tag)
                Add(tag .. ":lifecycle-count", replayed)
            end
            -- Existing reset/copy popup owners keep their real widget dispatch.
            local sectionIds = {}
            for id in pairs(M.cache[page].sections) do
                if page == "opt_castbar" or id == "castbar" then sectionIds[#sectionIds + 1] = id end
            end
            table.sort(sectionIds)
            for _, id in ipairs(sectionIds) do
                local entry = M.cache[page].sections[id]._msuf2CollapsibleEntry
                local actions = entry and entry._msuf2SectionActions
                if actions and not absent and not narrow then
                    actions:Click()
                    local popup = actions._msuf2GetSectionPopup()
                    if popup then
                        Add(tag .. ":popup:" .. id, Layout(popup))
                        for _, widget in ipairs(mw.world.widgets.frames) do
                            if widget:GetParent() == popup and widget._msuf2Label
                                and widget._msuf2Label:GetText() == "Reset section" then
                                local before = F.CopySnapshot(env.MSUF_DB)
                                calls = {}
                                M.ClearHistory()
                                widget:Click()
                                mw:RunTimers()
                                Add(tag .. ":reset:" .. id, Diff(before, env.MSUF_DB), calls, M.Undo())
                                mw:RunTimers()
                            end
                        end
                        if popup._msuf2CopySection then
                            local before = F.CopySnapshot(env.MSUF_DB)
                            calls = {}
                            local copied = popup._msuf2CopySection("player")
                            mw:RunTimers()
                            Add(tag .. ":copy:" .. id, copied, Diff(before, env.MSUF_DB), calls)
                        end
                        popup:Hide()
                    end
                end
            end
            if not absent and not narrow then PageChrome(page, tag) end
            stateRows[page] = Records(page)
            Add(tag .. ":refresh", State(page))
            mw:Select("home")
            mw:Select(page)
            Expand(page)
            stateRows[page] = Records(page)
            Add(tag .. ":reopen", State(page))
        end
    end
    return output, targets
end
local started = os.clock()
local expected, targets = Run(true)
collectgarbage("collect")
local actual, candidateTargets = Run(false, expected)
assert(next(leaks) == nil, "page reads a local name as a global: " .. tostring(next(leaks)))
local checks, controls, pageCounts = 0, 0, {}
for id in pairs(targets) do
    controls = controls + 1
    local page = assert(id:match("^menu2%.([^.]+)"))
    pageCounts[page] = (pageCounts[page] or 0) + 1
    assert(candidateTargets[id], "control removed: " .. id)
end
local minimum = push and 25 or (flavor == "Vanilla" and 60 or 75)
assert(controls >= minimum, "incomplete castbar control replay: " .. controls)
if not push and (flavor == "Mainline" or flavor == "Forever") then
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
            local file = assert(io.open(scratch .. "/castbars-" .. flavor .. "-" .. name .. ".txt", "wb"))
            file:write(key, "\n", value)
            file:close()
        end
        error(flavor .. ": parity mismatch " .. key)
    end
end
for key in pairs(actual) do assert(expected[key], "unexpected control/observation: " .. key) end
print(string.format("menu_castbars_parity_smoke: %s PASS (%d controls, %d observations, %.2fs)",
    flavor, controls, checks, os.clock() - started))
print("Castbar controls per page: " .. Encode(pageCounts))

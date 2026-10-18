-- Replay the immutable pre-conversion page and current page through real menu inputs.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local candidatePath = arg[3]
local pagePath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua"
local parent = "2a1e3ff5ec5b5bba69b2f10ac09db60289e182a2"
assert(not root:find('["%%\r\n]'), "unsafe repository path")
local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. parent .. ':' .. pagePath, "r"))
local source = pipe:read("*a")
pipe:close()
assert(source:find("local function BuildPortrait", 1, true), "immutable parent page unavailable")
-- The pinned parent predates the menu selection motion, which opts the portrait direction pad out of
-- exclusive selection ({ multiSelect = true }: several arrows are selected at once, so none may slide).
-- The page under test carries that one-line edit; give the parent source the same one in memory, or the
-- replay would build the parent's pad with the selection fill frames that the page under test never creates.
local direction = 'W.Segment(card, "Blizzard frame direction", values, 340)'
local directionAt = assert(source:find(direction, 1, true), "the parent's portrait direction pad moved")
assert(not source:find(direction, directionAt + 1, true), "the parent has two portrait direction pads")
source = source:sub(1, directionAt - 1) .. 'W.Segment(card, "Blizzard frame direction", values, 340, { multiSelect = true })'
    .. source:sub(directionAt + #direction)
local scratch = root .. "/.checks/unitframevisuals-parent-" .. flavor .. ".lua"
local file = io.open(scratch, "wb")
if not file then
    os.execute('mkdir "' .. root .. '/.checks"')
    file = assert(io.open(scratch, "wb"))
end
file:write(source)
file:close()

local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local sections = { portrait = true, power_bar = true, castbar = true }
local function Encode(value, seen)
    local kind = type(value)
    if kind == "function" then return "<function>" end
    if kind ~= "table" then return tostring(value) end
    if value.GetObjectType then return "<widget>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. Encode(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Diff(a, b, path, out)
    path, out = path or "", out or {}
    if a == b then return out end
    if type(a) == "table" and type(b) == "table" then
        local keys = {}
        for key in pairs(a) do keys[key] = true end
        for key in pairs(b) do keys[key] = true end
        for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), out) end
    elseif Encode(a) ~= Encode(b) then out[path] = { Encode(a), Encode(b) } end
    return out
end
local function Replay(prior, expected)
    local mw = World.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
        world.widgets.Methods.GetCenter = function(frame)
            return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
        end
        if prior or candidatePath then
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                if path:sub(-#pagePath) == pagePath then path = prior and scratch or candidatePath end
                return load(self, path, ...)
            end
        end
    end })
    local M, env, core = mw.M, mw.env, mw.core
    local built = {}
    local build = M.ControlSchema.Build
    M.ControlSchema.Build = function(...)
        local refs = build(...)
        for _, widget in pairs(refs) do built[widget] = true end
        return refs
    end
    local F = core.ProfileFields
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    -- The external cooldown viewers are native frames in game. Give the real
    -- width/preview owners numeric geometry instead of the harness's unknown-API table.
    for index, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
        local viewer = env.CreateFrame("Frame", nil, env.UIParent)
        viewer:SetSize(300 + index * 40, 32)
        viewer:Show()
        env[name] = viewer
    end
    local activeUnit
    local function Snapshot()
        local owned = { general = env.MSUF_DB.general, bars = env.MSUF_DB.bars }
        owned[activeUnit] = env.MSUF_DB[activeUnit]
        return (F.CopySnapshot(owned))
    end
    local calls, tips, result = {}, {}, {}
    for _, owner in ipairs({ M.ApplyService, M }) do
        for name, fn in pairs(owner) do
            if type(fn) == "function" and (owner ~= M or name == "RequestRefresh" or name == "Refresh") then
                owner[name] = function(...)
                    if name == "Refresh" then calls[#calls + 1] = name
                    elseif name == "RequestRefresh" then
                        local ctx, reason = ...
                        calls[#calls + 1] = name .. Encode({ ctx and ctx.key, reason })
                    else calls[#calls + 1] = name .. Encode({ ... }) end
                    return fn(...)
                end
            end
        end
    end
    env.GameTooltip.SetOwner = function() end
    env.GameTooltip.SetText = function(_, text) tips[#tips + 1] = text end
    env.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = text end
    env.GameTooltip.Show, env.GameTooltip.Hide = function() end, function() end
    local function Add(tag, ...)
        local line, index = tag .. ":" .. Encode({ ... }), #result + 1
        if expected then
            assert(line == expected[index], "parity row " .. index .. "\nparent: " .. tostring(expected[index]) .. "\ncurrent: " .. line)
        end
        result[index] = line
    end
    local function Own(w, entry)
        while w do
            for id, sec in pairs(entry.sections) do
                if sections[id] and (w == sec or w == sec._msuf2CollapsibleEntry.header) then return id end
            end
            w = w.GetParent and w:GetParent()
        end
    end
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function Input(w, value)
        local cmd = Command(w)
        if cmd.kind == "toggle" then w:SetChecked(value); w:Click("LeftButton")
        elseif w.buttons then
            for _, button in ipairs(w.buttons) do if button._msuf2Value == value then button:Click("LeftButton") end end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        elseif w._msuf2OnCommit then w._msuf2OnCommit(value)
        else w:SetValue(value); World.FireScript(w, "OnValueChanged", value) end
        mw:RunTimers()
    end
    local function State(controls)
        local out = {}
        for _, w in ipairs(controls) do
            out[#out + 1] = { w._msuf2RuntimeControlRecord.controlId, w:IsEnabled(), w:IsShown(),
                w.value, w.checked }
        end
        return out
    end
    local function AbsentKeys(unit, record)
        if record.settingKey and record.settingKey ~= "" then return { record.settingKey } end
        local path = record.controlId:gsub("^menu2%.uf_[^%.]+%.unit%.", "")
        local fields = M.UnitPage.CASTBAR_FIELDS[unit]
        local prefix = ({ player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus",
            boss = "bossCast", arena = "arenaCast" })[unit]
        if path == "portrait.enabled" then return { unit .. ".portraitMode" } end
        if path == "power.detached" then return { unit .. ".powerBarDetached" } end
        if path == "castbar.portrait_cast_icon" then return { unit .. ".portraitCastSpellIcon" } end
        if path == "castbar.spell_text_width_mode" then return { "general." .. prefix .. "SpellNameTruncate" } end
        if path == "castbar.enabled" then
            return { "general." .. fields.enable, "general." .. fields.backend,
                "general." .. (fields.providerMemory or fields.backend .. "BeforeHide") }
        end
        assert(record.classification == "ephemeral", "missing absent-key route: " .. record.controlId)
        return {}
    end
    local function CheckAbsent(unit, record, w, ctx)
        local keys, saved = AbsentKeys(unit, record), {}
        if #keys == 0 then return end
        for i, path in ipairs(keys) do
            local owner, key = path:match("^([^.]+)%.(.+)$")
            local conf = assert(env.MSUF_DB[owner], "missing setting owner: " .. path)
            saved[i] = { conf, key, conf[key] }
            conf[key] = nil
        end
        local before, cmd = Snapshot(), Command(w)
        Add("absent-get", record.controlId, keys, cmd.get(), Diff(before, Snapshot()))
        M.Refresh(ctx)
        mw:RunTimers()
        Add("absent-refresh", record.controlId, cmd.get(), w.value, w.checked, w:IsEnabled(), w:IsShown(), Diff(before, Snapshot()))
        for _, item in ipairs(saved) do item[1][item[2]] = item[3] end
        M.Refresh(ctx)
        mw:RunTimers()
    end
    local function Layout(entry)
        local frames, ids, seen = {}, {}, {}
        local function Include(w)
            if seen[w] then return end
            seen[w], ids[w], frames[#frames + 1] = true, #frames + 1, w
            for _, region in ipairs(w.regions or {}) do Include(region) end
        end
        for _, w in ipairs(mw.world.widgets.frames) do if Own(w, entry) then Include(w) end end
        local out = {}
        for _, w in ipairs(frames) do
            if not prior and (w._msuf2ControlCard or w._msuf2ContextColorOptions) then
                assert(w._msuf2ControlSchema, "visual composite escaped declaration")
            end
            local points = {}
            for i = 1, w:GetNumPoints() do
                local a, parentFrame, b, x, y = w:GetPoint(i)
                points[#points + 1] = { a, ids[parentFrame] or "external", b, x, y }
            end
            out[#out + 1] = { ids[w:GetParent()] or "external", w:GetObjectType(), w.text, w.width, w.height,
                points, w:IsShown(), w:IsEnabled(), w.alpha, w.texture, w.level }
        end
        return out
    end
    local count, exercised, scopeErrors = 0, {}, {}
    local function ShouldReplay(unit, record, edge)
        -- Player and Target cover the distinct control variants. Other unit
        -- instances keep complete inventories/layouts plus their scope routes;
        -- any additional unique control is always replayed in both states.
        local path = record.controlId:lower()
        local identity = path:gsub("^menu2%.uf_[^%.]+", "unit") .. tostring(edge)
        local wanted = unit == "player" or unit == "target" or not exercised[identity]
            or path:find(".castbar.manual_width", 1, true) or path:find(".castbar.height", 1, true)
            or path:find(".power.detachedpowerbarwidth", 1, true) or path:find(".portrait.portraitclickable", 1, true)
        exercised[identity] = true
        return wanted
    end
    for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
        activeUnit = unit
        local page = "uf_" .. unit
        if M.pages[page] then
            mw:Select(page)
            local entry = M.cache[page]
            assert(entry.sections.portrait, "portrait section missing: " .. page)
            if M.UnitPage.POWER_UNITS[unit] then assert(entry.sections.power_bar, "power section missing: " .. page) end
            if M.UnitPage.CASTBAR_FIELDS[unit] then assert(entry.sections.castbar, "castbar section missing: " .. page) end
            for id, sec in pairs(entry.sections) do
                if sections[id] then
                    if not prior then assert(sec._msuf2CollapsibleEntry.header._msuf2ControlSchema,
                        "section header escaped declaration: " .. id) end
                    sec._msuf2CollapsibleEntry.SetOpenImmediate(true)
                end
            end
            mw:RunTimers()
            M.Refresh(entry.ctx)
            local controls = {}
            for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
                local w = M.RuntimeControlCatalog.Get(record.controlId).widget
                if record.pageKey == page and w and Own(w, entry) then
                    tips = {}
                    if w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
                    local low, high
                    if record.kind == "slider" then low, high = w:GetMinMaxValues() end
                    Add("inventory", page, record, w._msuf2SearchMeta, w._msuf2ExactTargetContracts, tips,
                        low, high, w.valueStep, w.GetValues and w:GetValues() or w.values,
                        w.width, w.height, { w:GetPoint() })
                    local cmd = Command(w)
                    if cmd and cmd.get and cmd.set then
                        if not prior then assert(built[w] or w._msuf2ControlSchema,
                            "input escaped schema: " .. record.controlId) end
                        if not prior and w._msuf2ControlSchema.scope ~= unit then
                            scopeErrors[#scopeErrors + 1] = record.controlId .. "=" .. tostring(w._msuf2ControlSchema.scope)
                        end
                        controls[#controls + 1] = w
                    end
                end
            end
            assert(#controls >= 40, "visual controls missing on " .. page)
            for _, edge in ipairs({ false, true }) do
                if edge then
                    -- Replace the tables after the widgets exist: bindings must read
                    -- the current profile roots at input time, including explicit false/zero.
                    env.MSUF_DB[unit] = F.CopySnapshot(env.MSUF_DB[unit])
                    env.MSUF_DB.general = F.CopySnapshot(env.MSUF_DB.general)
                    local conf = env.MSUF_DB[unit]
                    conf.portraitMode, conf.portraitShape, conf.portraitRender = "RIGHT", "BLIZZARD", "CLASS"
                    conf.portraitPlacement, conf.portraitSizeMode = "DETACHED", "SEPARATE"
                    conf.portraitBlizzardElite, conf.portraitBlizzardCorner = true, true
                    conf.showPowerBar, conf.powerBarDetached, conf.powerBarBorderEnabled = true, true, true
                    conf.detachedPowerBarShape, conf.detachedPowerBarSyncClassPower = "ORB", false
                    local prefix = ({ player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast", arena = "arenaCast" })[unit]
                    if prefix then
                        env.MSUF_DB.general[prefix .. "SpellNameTruncate"] = "CLIP"
                        env.MSUF_DB.general[prefix .. "IconBorderStyle"] = "NONE"
                    end
                end
                M.Refresh(entry.ctx)
                mw:RunTimers()
                Add("state", page, edge, State(controls))
                Add("layout", page, edge, Layout(entry))
                for _, w in ipairs(controls) do
                    local cmd, record = Command(w), w._msuf2RuntimeControlRecord
                    local value, opposite
                    if cmd.kind == "toggle" then value = not cmd.get(); opposite = not value
                    elseif record.kind == "slider" then
                        local low, high = w:GetMinMaxValues()
                        value = edge and high or low + (high - low) * 0.37
                        opposite = value == low and high or low
                    else
                        local values = w.GetValues and w:GetValues() or w.values
                        if type(values) == "function" then values = values() end
                        assert(type(values) == "table" and #values > 0, "missing choices " .. record.controlId)
                        value = values[edge and #values or 1].value
                        opposite = values[value == values[1].value and #values or 1].value
                    end
                    if ShouldReplay(unit, record, edge) then
                        if edge then CheckAbsent(unit, record, w, entry.ctx) end
                        M.ClearHistory()
                        local before = Snapshot()
                        calls = {}
                        Input(w, value)
                        local after = Snapshot()
                        Add("input", record.controlId, edge, value, Diff(before, after), cmd.get(), calls, State(controls))
                        local undo = M.Undo()
                        mw:RunTimers()
                        Add("undo", record.controlId, undo, Diff(before, Snapshot()))
                        local redo = M.Redo()
                        mw:RunTimers()
                        Add("redo", record.controlId, redo, Diff(after, Snapshot()))
                        M.ClearHistory()
                        before = Snapshot()
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        env.InCombatLockdown = function() return true end
                        calls = {}
                        Input(w, opposite)
                        Add("combat", record.controlId, Diff(before, Snapshot()), calls, M.Undo())
                        core.Util.InCombat("PLAYER_REGEN_ENABLED")
                        env.InCombatLockdown = function() return false end
                        mw:RunTimers()
                        count = count + 1
                    end
                end
            end
            if unit == "target" then
                for _, id in ipairs({ "portrait", "power_bar", "castbar" }) do
                    local section = entry.sections[id]
                    local action = section and section._msuf2CollapsibleEntry._msuf2SectionActions
                    if action then
                        action:Click()
                        local popup = assert(action._msuf2GetSectionPopup(), "section actions missing")
                        M.ClearHistory()
                        local before = F.CopySnapshot(env.MSUF_DB)
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        env.InCombatLockdown = function() return true end
                        local refused = popup._msuf2CopySection("player")
                        Add("copy-combat", id, refused, Diff(before, env.MSUF_DB), M.Undo())
                        core.Util.InCombat("PLAYER_REGEN_ENABLED")
                        env.InCombatLockdown = function() return false end
                        calls = {}
                        local copied = popup._msuf2CopySection("player")
                        mw:RunTimers()
                        Add("copy", id, copied, Diff(before, env.MSUF_DB), calls)
                        Add("copy-undo", id, M.Undo())
                        mw:RunTimers()
                        Add("copy-restored", id, Diff(before, env.MSUF_DB))
                        local reset
                        for _, w in ipairs(mw.world.widgets.frames) do
                            if w:GetParent() == popup and w._msuf2Label and w._msuf2Label:GetText() == "Reset section" then reset = w end
                        end
                        assert(reset, "section reset missing")
                        M.ClearHistory()
                        before, calls = F.CopySnapshot(env.MSUF_DB), {}
                        reset:Click()
                        mw:RunTimers()
                        Add("reset", id, Diff(before, env.MSUF_DB), calls)
                        Add("reset-undo", id, M.Undo())
                        mw:RunTimers()
                        Add("reset-restored", id, Diff(before, env.MSUF_DB))
                        popup:Hide()
                    end
                end
            end
        end
    end
    assert(#scopeErrors == 0, "wrong schema unit scope: " .. tostring(scopeErrors[1]) .. " (" .. #scopeErrors .. " inputs)")
    Add("whole-profile", env.MSUF_DB)
    return result, count
end
local started = os.clock()
local expected, count = Replay(true)
collectgarbage("collect")
local actual, actualCount = Replay(false, expected)
assert(count == actualCount, "control input count changed")
assert(#expected == #actual, "parity receipt length changed")
for i, line in ipairs(expected) do
    assert(line == actual[i], "parity row " .. i .. "\nparent: " .. line .. "\ncurrent: " .. actual[i])
end
print(string.format("menu_unitframevisuals_parity_smoke %s: %d inputs, %d receipts, %.2fs", flavor, count, #actual, os.clock() - started))

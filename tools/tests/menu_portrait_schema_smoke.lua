-- Portrait colors retain their real multi-root/history/lifecycle behavior.
-- Optional arg3 is an authentic parent page; arg4 is a package-only page override.
-- Offline bindings and painter inputs do not prove live rendering or taint.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, parentPage, candidatePage = arg[2] or "Mainline", arg[3], arg[4]
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
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
local function Restore(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            Restore(dst[key], value)
        else dst[key] = value end
    end
end
local owners = { "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss" }
local paths = { "portrait.border_color", "portrait.background_color", "portrait.reset" }
local prefixes = { "portraitBorderColor", "portraitBgColor" }
local defaults = { { 1, 1, 1 }, { 0.05, 0.05, 0.05 } }
local function Replay(original, narrow, saved)
    local rows, ids, requests, tips, refreshes, replaced = {}, {}, {}, {}, 0, 0
    local override = original and parentPage or candidatePage
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            -- The framework captures this real TOC field while the core loads.
            local env = world.env
            -- Full UF/color apply also reads the native idle Warrior inputs.
            local power = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))().PT
            local enum = env.Enum
            env.Enum = setmetatable({ PowerType = { Mana = power.MANA, Rage = power.RAGE, Focus = 2,
                Energy = power.ENERGY, ComboPoints = power.COMBO } }, { __index = enum })
            local function PowerType(value)
                assert(value == nil or type(value) == "number", "native power-type argument must be numeric or nil")
            end
            env.UnitPowerType = function() return power.RAGE, "RAGE" end
            env.UnitPower = function(_, value) PowerType(value) return 0 end
            env.UnitPowerMax = function(_, value)
                PowerType(value) return (value == nil or value == power.RAGE) and 100 or 5
            end
            env.UnitPowerDisplayMod = function(value) PowerType(value) return 1 end
            env.UnitHasVehicleUI = function() return false end
            env.PlayerVehicleHasComboPoints = function() return false end
            env.GetShapeshiftFormID = function() return nil end
            local kind, token = env.UnitPowerType("player")
            assert(kind == power.RAGE and token == "RAGE" and env.UnitPower("player", kind) == 0
                and env.UnitPowerMax("player", kind) == 100 and env.UnitPowerMax("player", power.COMBO) == 5
                and env.UnitPowerDisplayMod(power.COMBO) == 1 and env.UnitHasVehicleUI("player") == false
                and env.PlayerVehicleHasComboPoints() == false and env.GetShapeshiftFormID() == nil,
                "native idle Warrior provider fixture drift")
            local function Number(value)
                assert(type(value) == "number" and value == value and value - value == 0,
                    "native numeric formatter requires a finite number")
                return value
            end
            local function Abbreviate(value)
                value = Number(value)
                if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
                if value >= 1000 then return string.format("%.1fK", value / 1000) end
                return string.format("%d", value)
            end
            env.AbbreviateNumbers, env.AbbreviateLargeNumbers = Abbreviate, Abbreviate
            env.BreakUpLargeNumbers = function(value) return string.format("%d", math.floor(Number(value))) end
            assert(env.AbbreviateNumbers(1234) == "1.2K" and env.AbbreviateLargeNumbers(1234000) == "1.2M"
                and env.BreakUpLargeNumbers(1234) == "1234", "native numeric formatter string contract drift")
            for _, formatter in ipairs({ env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.BreakUpLargeNumbers }) do
                for _, invalid in ipairs({ false, "1234", {}, math.huge }) do
                    assert(not pcall(formatter, invalid), "native numeric formatter accepted an opaque/nonfinite input")
                end
            end
            env.RAID_CLASS_COLORS = {}
            for index, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
                "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
                env.RAID_CLASS_COLORS[class] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
            end
            env.TotemFrame = env.CreateFrame("Frame", nil, env.UIParent)
            assert(env.TotemFrame:GetObjectType() == "Frame" and env.TotemFrame:GetNumPoints() == 0,
                "native TotemFrame empty region fixture drift")
            local path = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. world.client.tocSuffix .. ".toc"
            local file = assert(io.open(path, "rb"), "portrait core TOC metadata missing")
            local metadata = file:read("*a") assert(file:close(), "portrait core TOC metadata close failed")
            local prefix = metadata:match("\n## X%-MSUF%-UnitFrames%-Prefix:%s*([^\r\n]+)")
            assert(prefix == "MSUF", "native unit-frame TOC prefix fixture drift")
            local previous = env.C_AddOns.GetAddOnMetadata
            env.C_AddOns.GetAddOnMetadata = function(addon, field)
                if addon == "MidnightSimpleUnitFrames" and field == "X-MSUF-UnitFrames-Prefix" then return prefix end
                return previous(addon, field)
            end
            env.GetAddOnMetadata = env.C_AddOns.GetAddOnMetadata
            assert(env.GetAddOnMetadata("MidnightSimpleUnitFrames", "X-MSUF-UnitFrames-Prefix") == prefix,
                "native metadata provider did not expose the real unit-frame prefix")
        end,
        beforeOptions = function(world)
            local env, common, text = world.env, world.core.UFBarTextCommon, world.core.UFText
            assert(type(env.issecretvalue) == "function" and env.issecretvalue(1234) == false,
                "native secret API presence must retain the real compiled writer route")
            assert(common.AbbreviateNumbers == env.AbbreviateNumbers and text.AbbreviateNumbers == env.AbbreviateNumbers
                and common.AbbreviateLargeNumbers == env.AbbreviateLargeNumbers
                and text.AbbreviateLargeNumbers == env.AbbreviateLargeNumbers
                and common.BreakUpLargeNumbers == env.BreakUpLargeNumbers and text.BreakUpLargeNumbers == env.BreakUpLargeNumbers,
                "UF/text providers did not capture native numeric formatters before core load")
            assert(common.UnitPower == env.UnitPower and text.UnitPower == env.UnitPower
                and common.UnitPowerMax == env.UnitPowerMax and text.UnitPowerMax == env.UnitPowerMax
                and common.RAID_CLASS_COLORS == env.RAID_CLASS_COLORS and text.RAID_CLASS_COLORS == env.RAID_CLASS_COLORS,
                "UF/text providers did not capture typed native power/class-color inputs")
            local power = env.MSUF_CP_CONST.PT
            assert(power.Mana == 0 and power.Rage == 1 and power.ComboPoints == 4, "native captured power identity drift")
            assert(world.core.UF.frameNamePrefix == "MSUF", "unit-frame framework did not capture native TOC metadata")
            local frameName = world.core.UF.FrameName("player")
            assert(world.env[frameName] == rawget(world.env, frameName), "owned frame lookup returned an opaque API stub")
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if override and override ~= "-" and path:gsub("\\", "/") == root .. "/" .. target then
                    replaced = replaced + 1
                    path = override
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(not override or override == "-" or replaced == 1, "parent/candidate page not replaced exactly once")
    local M, core, env = mw.M, mw.core, mw.env
    local Copy = core.ProfileFields.CopySnapshot
    local function Same(a, b) return Encode(a, ids) == Encode(b, ids) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Snapshot() return Copy(env.MSUF_DB) end
    local function Counts()
        local state = M.GetHistoryState()
        return { state.undoCount, state.redoCount, state.canUndo, state.canRedo }
    end
    if saved then Restore(env.MSUF_DB, saved) end
    local created, nativeColor = {}, M.Widgets.Color
    M.Widgets.Color = function(...)
        local widget = nativeColor(...)
        created[#created + 1] = widget
        return widget
    end
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
    end
    local coldBefore = Snapshot()
    assert(mw:Select("opt_colors"))
    assert(M.ColorsSetPainterCategory)("unit") mw:RunTimers()
    local entry = assert(M.cache.opt_colors)
    local section = assert(entry.sections.colors_portrait, "portrait lazy section missing")
    local shell = assert(section._msuf2CollapsibleEntry)
    ids[section] = "colors_portrait"
    local closedAtBirth = shell.open
    M.Widgets.EnsureSectionContent(section)
    shell.SetOpenImmediate(true) mw:RunTimers()
    Add("cold-build", coldBefore, Snapshot(), closedAtBirth)
    local function Widget(path)
        local id = M.ControlMeta("opt_colors", "advanced", path).controlId
        local record = assert(M.RuntimeControlCatalog.Get(id), "portrait catalog owner missing: " .. path)
        local widget = assert(record.widget, "portrait widget missing: " .. path)
        ids[widget] = id
        return widget
    end
    local controls = { Widget(paths[1]), Widget(paths[2]) }
    local reset = Widget(paths[3])
    local function Command(widget) return assert(widget._msuf2CommandAction or widget._msuf2RuntimeControlRecord.command) end
    local function CheckSchema(widget, kind, domain)
        local spec = assert(widget._msuf2ControlSchema, "portrait schema declaration missing")
        assert(spec.id == widget._msuf2RuntimeControlRecord.controlId and spec.kind == kind
            and spec.scope == "colors" and spec.applyDomain == domain, "portrait schema identity/kind/scope/domain drift")
        if kind == "button" then assert(spec.owner == widget and spec.action, "portrait reset lost its actual owner") end
    end
    if not original then
        for _, widget in ipairs(controls) do CheckSchema(widget, "color", "unitColors") end
        CheckSchema(reset, "button", "unitColors")
        local spec = assert(shell.header._msuf2ControlSchema)
        assert(spec.owner == shell.header and spec.scope == "colors" and spec.applyDomain == "sectionNavigation",
            "portrait section lost native navigation ownership")
    end
    local owned = 0
    for _, widget in ipairs(created) do if widget:GetParent() == section then owned = owned + 1 end end
    assert(owned == 2, "portrait created duplicate color widgets")
    local function Display()
        local out = {}
        for _, widget in ipairs(controls) do
            local model, shown = Pack(Command(widget).get()), Pack(widget:GetRGB())
            assert(Same(Pack(model[1], model[2], model[3]), shown), "portrait displayed/model RGB mismatch")
            assert(widget._msuf2GetColorOpacity() == model[4], "portrait alpha getter changed")
            local title = widget._msuf2Title
            out[#out + 1] = { ids[widget], model, shown, widget:GetWidth(), widget:GetHeight(),
                Pack(widget:GetPoint(1)), title and title:GetText(), title and title:GetWidth(),
                widget._msuf2DefaultRGB, widget:IsEnabled() }
        end
        return out
    end
    local function Runtime()
        local out = {}
        for _, unit in ipairs({ "player", "target" }) do
            local spec = assert(core.UF.Config.CompileSpec(unit, {}))
            out[unit] = { border = Copy(spec.portrait.border), background = Copy(spec.portrait.bg) }
        end
        return out
    end
    local request = M.ApplyService.RequestGeneralDomains
    M.ApplyService.RequestGeneralDomains = function(reason, opts, ...)
        requests[#requests + 1] = { reason, Copy(opts) }
        return request(reason, opts, ...)
    end
    local refresh = M.RunEntryRefreshers
    M.RunEntryRefreshers = function(...) refreshes = refreshes + 1 return refresh(...) end
    for _, name in ipairs({ "SetOwner", "SetText", "AddLine", "Show", "Hide" }) do
        env.GameTooltip[name] = function(_, ...) tips[#tips + 1] = { name, ... } end
    end
    local function Clear() requests, tips, refreshes = {}, {}, 0 end
    local function Observe(tag)
        Add(tag, Snapshot(), Display(), Runtime(), Counts(), requests, refreshes, tips,
            shell._msuf2ModifiedBadgeCount, section:GetHeight(), reset:GetWidth(), reset:GetHeight())
    end
    local seed = Snapshot()
    local function Setup(state)
        Restore(env.MSUF_DB, seed)
        local db = env.MSUF_DB
        if state ~= "factory" then
            for index, owner in ipairs(owners) do
                db[owner] = db[owner] or {}
                local conf = db[owner]
                conf.portraitContractSentinel = { enabled = false, zero = 0, nested = { index = index } }
                for _, prefix in ipairs(prefixes) do
                    conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = index / 20, 0.2, 0.7
                    conf[prefix .. "A"] = index / 30
                    if state == "sparse" then
                        conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"], conf[prefix .. "A"] = nil, nil, nil, nil
                    elseif state == "edge" then
                        conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"], conf[prefix .. "A"] = false, 0, nil, false
                    elseif state == "explicit-defaults" then
                        local color = prefix == prefixes[1] and defaults[1] or defaults[2]
                        conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = unpack(color)
                    end
                end
            end
            db.arena = db.arena or {}
            db.arena.portraitContractSentinel = { false, 0, "arena stays separate" }
            if state == "sparse" then db.pettarget = nil end
            if state == "explicit-defaults" then
                db.general.portraitBorderColorA, db.general.portraitBgColorA = 1, 0.85
            end
        end
        local before = Snapshot()
        M.Refresh() mw:RunTimers()
        Add(state .. ":setup-refresh", before, Snapshot())
        M.ClearHistory() Clear()
    end
    local function ExpectedRGB(before, prefix, color)
        local expected = Copy(before)
        for _, owner in ipairs(owners) do
            expected[owner] = expected[owner] or {}
            for index, suffix in ipairs({ "R", "G", "B" }) do expected[owner][prefix .. suffix] = color[index] end
        end
        return expected
    end
    local function Input(widget, color)
        widget._msuf2OnColorChanged(unpack(color)) mw:RunTimers()
    end
    local function CheckRequests(reasons)
        assert(#requests == #reasons, "portrait logical apply request count changed")
        for index, reason in ipairs(reasons) do
            local row = requests[index]
            assert(row[1] == reason and row[2].preview == true and row[2].applyAll == true and row[2].colors == true,
                "portrait logical apply request order/domain changed")
        end
    end
    local function UndoTo(expected, label)
        assert(M.Undo(), label .. ": missing undo") mw:RunTimers()
        assert(Same(expected, env.MSUF_DB), label .. ": whole-profile undo did not restore all roots/presence")
    end
    local function RedoTo(expected, label)
        assert(M.Redo(), label .. ": missing redo") mw:RunTimers()
        assert(Same(expected, env.MSUF_DB), label .. ": whole-profile redo drift")
    end
    for _, state in ipairs({ "factory", "custom", "sparse", "edge", "explicit-defaults" }) do
        for index, widget in ipairs(controls) do
            Setup(state)
            local prefix, before = prefixes[index], Snapshot()
            Input(widget, { 0.23, 0.47, 0.71 })
            local after = Snapshot()
            assert(Same(ExpectedRGB(before, prefix, { 0.23, 0.47, 0.71 }), after), "portrait RGB fanout/alpha/isolation changed")
            CheckRequests({ prefix }) Observe(state .. ":input:" .. index)
            local width = tonumber(env.MSUF_DB.player.width) or 250
            M.SetUnitValue("player", "width", width + 1) mw:RunTimers()
            local afterWidth = Snapshot()
            UndoTo(after, "width after portrait") UndoTo(before, "portrait after width")
            Observe(state .. ":two-undos:" .. index)
            RedoTo(after, "portrait") RedoTo(afterWidth, "width")
            Observe(state .. ":two-redos:" .. index)
            assert(Command(widget).historyScope == false, "portrait multi-root historyScope=false lost")

            Setup(state) before = Snapshot()
            local current = Pack(Command(widget).get())
            Input(widget, { current[1], current[2], current[3] })
            assert(Same(before, env.MSUF_DB) and #requests == 0 and M.GetHistoryState().undoCount == 0,
                "unchanged effective portrait RGB synchronized units/materialized defaults/history")
            Observe(state .. ":effective-noop:" .. index)

            -- The existing setter ignores picker alpha; a changed alpha still
            -- takes the callback/fanout path. Preserve that exact distinction.
            Setup(state) before = Snapshot()
            current = Pack(Command(widget).get())
            local alpha = current[4] == 0.61 and 0.73 or 0.61
            Input(widget, { current[1], current[2], current[3], alpha })
            after = Snapshot()
            assert(Same(ExpectedRGB(before, prefix, current), after), "portrait alpha-only callback changed stored alpha")
            CheckRequests({ prefix }) Observe(state .. ":alpha-only:" .. index)
            if not Same(before, after) then UndoTo(before, "alpha-only fanout") RedoTo(after, "alpha-only fanout") end

            Setup(state) before = Snapshot()
            widget._msuf2BeginColorInteraction(widget)
            Input(widget, { 0.19, 0.37, 0.53 }) Input(widget, { 0.29, 0.43, 0.61 })
            widget._msuf2CommitColorInteraction(widget)
            after = Snapshot()
            assert(M.GetHistoryState().undoCount == 1, "one portrait picker interaction made multiple history entries")
            UndoTo(before, "portrait picker") RedoTo(after, "portrait picker")
            Observe(state .. ":picker-transaction:" .. index)

            Setup(state) before = Snapshot()
            widget:Click("RightButton") mw:RunTimers()
            after = Snapshot()
            local model = Pack(Command(widget).get())
            assert(Same(Pack(model[1], model[2], model[3]), Pack(unpack(defaults[index]))), "native color default click failed")
            Observe(state .. ":native-default:" .. index)
            if not Same(before, after) then UndoTo(before, "native default") RedoTo(after, "native default") end
        end
        Setup(state)
        local before = Snapshot()
        reset:Click("LeftButton") mw:RunTimers()
        local expected = ExpectedRGB(ExpectedRGB(before, prefixes[1], defaults[1]), prefixes[2], defaults[2])
        expected.general.portraitBorderColorA, expected.general.portraitBgColorA = 1, 0.85
        local after = Snapshot()
        assert(Same(expected, after), "portrait section reset changed unrelated roots/alpha/presence")
        CheckRequests({ "portraitBorderColor", "portraitBgColor", "PORTRAIT_COLOR_RESET" })
        Observe(state .. ":native-reset")
        if not Same(before, after) then
            UndoTo(before, "portrait section reset") RedoTo(after, "portrait section reset")
        else assert(M.GetHistoryState().undoCount == 0, "already explicit portrait defaults gained reset history") end
        Observe(state .. ":reset-history")
    end
    for _, lockdown in ipairs({ false, true }) do
        Setup("custom")
        local before = Snapshot()
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return lockdown end
        Input(controls[1], { 0.31, 0.42, 0.63 }) reset:Click("LeftButton") mw:RunTimers()
        assert(Same(before, env.MSUF_DB) and #requests == 0 and M.GetHistoryState().undoCount == 0,
            "portrait write/history/apply escaped event-derived combat refusal")
        Observe("combat:" .. tostring(lockdown))
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers() M.ClearHistory() Clear()
        before = Snapshot() Input(controls[1], { 0.31, 0.42, 0.63 })
        assert(Same(ExpectedRGB(before, prefixes[1], { 0.31, 0.42, 0.63 }), env.MSUF_DB), "post-combat portrait color did not resume")
        Observe("post-combat:" .. tostring(lockdown))
    end
    for _, widget in ipairs(controls) do
        MenuWorld.FireScript(widget, "OnEnter")
        MenuWorld.FireScript(widget, "OnLeave")
    end
    Observe("tooltips")
    local before, sameControls = Snapshot(), { controls[1], controls[2], reset }
    shell.SetOpenImmediate(false) M.Widgets.EnsureSectionContent(section)
    shell.SetOpenImmediate(true) M.Refresh() mw:RunTimers()
    assert(Same(before, env.MSUF_DB), "warm portrait refresh/reopen changed the saved profile")
    for index, path in ipairs(paths) do assert(Widget(path) == sameControls[index], "warm portrait construction replaced/duplicated owner") end
    owned = 0
    for _, widget in ipairs(created) do if widget:GetParent() == section then owned = owned + 1 end end
    assert(owned == 2, "warm portrait construction made an extra color widget")
    Observe("warm-reopen")
    mw:Select("home") mw:Select("opt_colors") M.ColorsSetPainterCategory("unit") mw:RunTimers()
    assert(Same(before, env.MSUF_DB), "portrait page revisit changed the saved profile") Observe("page-revisit")
    return rows, Snapshot()
end
local function Compare(narrow, saved)
    local expected, parentSaved
    if parentPage and parentPage ~= "-" then expected, parentSaved = Replay(true, narrow, saved and saved[1]) end
    local actual, candidateSaved = Replay(false, narrow, saved and saved[2])
    if expected then
        assert(#expected == #actual, "portrait parity observation count changed")
        for index, row in ipairs(expected) do
            assert(row == actual[index], "portrait parent parity drift at " .. index .. " " .. row:match("^[^\t]+"))
        end
    end
    return { parentSaved, candidateSaved }, #actual
end
local saved, normal = Compare(false)
local _, narrow = Compare(true)
local _, restored = Compare(false, saved)
print("menu_portrait_schema_smoke " .. flavor .. ": " .. (parentPage and parentPage ~= "-" and "parent parity" or "behavior")
    .. " PASS (" .. normal .. "/" .. narrow .. "/" .. restored .. " normal/400px/restored observations)")

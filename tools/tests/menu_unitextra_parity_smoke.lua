-- Replay the six builders at the batch parent and candidate through real Menu2 bindings.
-- Native rendering is a fixture seam. These checks establish offline menu behavior.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local mutationRoot = arg[3]
local parent = "e48e595c3eef2009f5f4933ec5cf9303c36bed96"
local files = { "Dispel", "RangeFade", "ArenaTrinket", "TextureLayer", "StatusSection", "Lazy" }
local prefix = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit"
assert(not root:find('["%%\r\n]'), "unsafe scratch path")
local scratch, originals = root .. "/.checks", {}
local probe = io.open(scratch .. "/unitextra-scratch-probe", "wb")
if not probe then
    os.execute((package.config:sub(1, 1) == "\\" and "mkdir " or "mkdir -p ") .. '"' .. scratch .. '"')
else
    probe:close()
end
-- The immutable parent remains the oracle after this package is committed.
for _, name in ipairs(files) do
    local relative = prefix .. name .. ".lua"
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. parent .. ':' .. relative, "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 100, "missing parent " .. name)
    local path = scratch .. "/unitextra-parent-" .. flavor .. "-" .. name .. ".lua"
    local out = assert(io.open(path, "wb"))
    out:write(source)
    out:close()
    originals[relative] = path
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Encode(value, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
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
local sections = { unit_dispel_overlay = true, unit_dispel_symbol = true, range_fade = true,
    pvp_trinket = true, texture_layer = true, status_icons = true }
-- Keys the six sections own. Clearing them leaves every control on its UI fallback.
local SECTION_KEYS = { "^unitDispel", "^texLayer", "^rangeFade", "^showTrinket$", "^trinket", "^raidGroupName",
    "^levelIndicator", "^threatIndicator", "^stateIconsTestMode$" }
local STATUS_FIELDS = { "show", "size", "anchor", "x", "y", "layer", "symbol", "iconStyle", "customIcon", "width",
    "legacyShow", "legacyX", "legacyY", "legacyAnchor", "legacyLayer", "legacySize" }
local function Enabled(widget)
    if widget.IsEnabled then return widget:IsEnabled() end
    return "<region>"
end
local function Replay(prior)
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                local relative = path:sub(#root + 2)
                local override = not prior and mutationRoot and originals[relative] and
                    mutationRoot .. "/" .. relative:match("[^/]+$")
                if override then
                    local file = io.open(override, "rb")
                    if file then file:close() else override = nil end
                end
                return load(self, prior and originals[relative] or override or path, ...)
            end
            world.widgets.Methods.GetCenter = function(frame)
                return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                    (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    local F, receipts, calls = core.ProfileFields, {}, {}
    local tipLines, openedDropdown = {}, nil
    env.GameTooltip.SetOwner = function() end
    env.GameTooltip.SetText = function(_, text) tipLines[#tipLines + 1] = text end
    env.GameTooltip.AddLine = function(_, text) tipLines[#tipLines + 1] = text end
    env.GameTooltip.Show, env.GameTooltip.Hide = function() end, function() end
    local openDropdown = M.Widgets.OpenDropdown
    M.Widgets.OpenDropdown = function(owner, values, current, changed, ...)
        calls[#calls + 1] = "OpenDropdown"
        openedDropdown = { values = values, changed = changed }
        return openDropdown(owner, values, current, changed, ...)
    end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    env.MSUF_RequestPetXPBarRefresh = function(...)
        calls[#calls + 1] = "MSUF_RequestPetXPBarRefresh" .. Encode({ ... })
    end
    for _, owner in ipairs({ M, M.ApplyService }) do
        for _, name in ipairs({ "RequestUnit", "RequestUnitDomains", "RequestUnitRefresh", "RequestRefresh", "Refresh" }) do
            local fn = owner[name]
            if type(fn) == "function" then
                owner[name] = function(...)
                    local args = { ... }
                    -- Context tables contain ephemeral widget state, so pin their page identity.
                    for i, value in ipairs(args) do
                        if type(value) == "table" and value.refreshers then args[i] = value.key end
                    end
                    calls[#calls + 1] = name .. Encode(args)
                    return fn(...)
                end
            end
        end
    end
    local function Add(key, value)
        assert(receipts[key] == nil, "duplicate receipt " .. key)
        receipts[key] = Encode(value)
    end
    local wantedSections = sections
    local function SectionOf(widget, entry)
        while widget do
            for id, section in pairs(entry.sections) do
                if wantedSections[id] and (widget == section or widget == section._msuf2CollapsibleEntry.header) then return id end
            end
            widget = widget.GetParent and widget:GetParent()
        end
    end
    local function Controls(page, includeVirtual)
        local out = {}
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local live = M.RuntimeControlCatalog.Get(record.controlId)
            if record.pageKey == page and live and live.widget and (includeVirtual or not live.widget._msuf2VirtualRuntimeControl)
                and SectionOf(live.widget, M.cache[page]) then
                out[#out + 1] = { record = record, widget = live.widget }
            end
        end
        table.sort(out, function(a, b) return a.record.controlId < b.record.controlId end)
        return out
    end
    local function Gates(page)
        local out = {}
        for _, c in ipairs(Controls(page)) do
            local kind, w = c.record.kind, c.widget
            out[c.record.controlId] = { Enabled(w), w:IsShown(), kind == "toggle" and w:GetChecked()
                or (kind == "slider" or kind == "dropdown" or kind == "segment") and w:GetValue()
                or kind == "textinput" and w:GetText() }
        end
        return out
    end
    local function Diff(before, after, path, out)
        out, path = out or {}, path or ""
        local keys = {}
        for k in pairs(before or {}) do keys[k] = true end
        for k in pairs(after or {}) do keys[k] = true end
        for key in pairs(keys) do
            local a, b = (before or {})[key], (after or {})[key]
            if not F.Equal(a, b) then
                local name = path .. tostring(key)
                if type(a) == "table" and type(b) == "table" then Diff(a, b, name .. ".", out)
                else out[name] = b == nil and "<nil>" or b end
            end
        end
        return out
    end
    local function Input(c, value)
        local widget, kind = c.widget, c.record.kind
        if kind == "toggle" then
            widget:SetChecked(value)
            widget:Click("LeftButton")
        elseif kind == "slider" then
            widget:SetValue(value)
            World.FireScript(widget, "OnValueChanged", value)
        elseif kind == "dropdown" then widget._msuf2OnValueChanged(value)
        elseif kind == "textinput" then widget._msuf2OnCommit(value)
        elseif kind == "segment" and widget.buttons then
            for _, button in ipairs(widget.buttons) do
                if button._msuf2Value == value then button:Click("LeftButton") end
            end
        elseif kind == "segment" and widget.SetValue then widget:SetValue(value)
        elseif kind == "button" then
            openedDropdown = nil
            widget:Click("LeftButton")
            if c.record.controlId:find("preset.msuf_texture", 1, true) and openedDropdown then
                local values = openedDropdown.values
                for i = value and 1 or #values, value and #values or 1, value and 1 or -1 do
                    if not values[i].header then
                        openedDropdown.changed(values[i].value)
                        break
                    end
                end
            end
        else error("unhandled input " .. c.record.controlId .. ": " .. tostring(kind)) end
        mw:RunTimers()
    end
    local function Values(c)
        local w, kind = c.widget, c.record.kind
        if kind == "toggle" then return { true, false } end
        if kind == "slider" then
            local low, high = w:GetMinMaxValues()
            return { low + (w.valueStep or 1), high }
        end
        if kind == "textinput" then return { "Interface\\Buttons\\WHITE8X8", "" } end
        if kind == "button" then return { true, false } end
        local source = w.GetValues and w:GetValues() or w.values
        if type(source) == "function" then source = source() end
        local out = {}
        for _, item in ipairs(source or {}) do
            if not item.header and not item.disabled then out[#out + 1] = item.value end
        end
        if #out == 0 then return { "DEFAULT", "" } end
        return { out[1], out[#out] }
    end
    local function Owned(page)
        local owned = {}
        local function Include(w, id)
            if owned[w] then return end
            owned[w] = id
            for _, region in ipairs(w.regions or {}) do Include(region, id) end
        end
        for _, w in ipairs(mw.world.widgets.frames) do
            local id = SectionOf(w, M.cache[page])
            if id then Include(w, id) end
        end
        return owned
    end
    -- The candidate declares every owned row: unit scope, a readable id, and the owner's kind and domain.
    local TYPED_DOMAIN = { unit_dispel_overlay = "dispel", unit_dispel_symbol = "dispel", range_fade = "range",
        pvp_trinket = "arenaTrinket", texture_layer = "textureLayer", status_icons = "unitStatus" }
    local STATIC_DOMAIN = { card = "layout", text = "presentation", font = "presentation", statusPreview = "preview",
        directionPad = "textureLayer" }
    local function ExpectedDomain(section, spec)
        local id = spec.id
        if STATIC_DOMAIN[spec.kind] then return STATIC_DOMAIN[spec.kind] end
        if id:find("%.expanded$") then return "sectionNavigation" end
        if id:find("%.colors$") then return "contextColors" end
        if id:find("_selector$") or id:find("_tab$") then return "menuState" end
        if id:find("%.preview$") then return "dispelPreview" end
        return TYPED_DOMAIN[section]
    end
    local function CheckDeclared(unit, owned)
        for w, section in pairs(owned) do
            local spec = w._msuf2ControlSchema
            if spec then
                local what = section .. " " .. tostring(spec.id)
                assert(type(spec.id) == "string" and spec.id:find("^[%l%d_%.]+$") and not spec.id:find("%.%d+$"),
                    what .. " has an unreadable id")
                assert(spec.scope == unit, what .. " declares scope " .. tostring(spec.scope))
                assert(spec.applyDomain == ExpectedDomain(section, spec),
                    what .. " declares domain " .. tostring(spec.applyDomain))
            end
        end
    end
    local function Inventory(page, state)
        local out = {}
        for _, c in ipairs(Controls(page)) do
            local w, r = c.widget, c.record
            local command = w._msuf2CommandAction or r.command
            local values = w.GetValues and w:GetValues() or w.values
            if type(values) == "function" then values = values() end
            local low, high
            if r.kind == "slider" then low, high = w:GetMinMaxValues() end
            tipLines = {}
            if w.HasScript and w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
            out[#out + 1] = { r, w._msuf2SearchMeta, w._msuf2StableSearchLabel, values, low, high, w.valueStep,
                command and command.get and command.get(), Enabled(w),
                w:IsShown(), w._msuf2ExactTargetContracts, tipLines }
            if not prior and command and command.set then
                local spec = assert(w._msuf2ControlSchema, "undeclared control " .. r.controlId)
                assert(spec.id == r.controlId, "declared " .. tostring(spec.id) .. " for " .. r.controlId)
            end
        end
        -- Virtual search aliases target the selected-indicator editor and have no native widget.
        local virtual = {}
        for _, c in ipairs(Controls(page, true)) do
            if c.widget._msuf2VirtualRuntimeControl then
                local command = c.widget._msuf2CommandAction or c.record.command
                virtual[#virtual + 1] = { c.record, command and command.get and command.get(),
                    c.widget._msuf2ExactTargetContracts }
            end
        end
        Add(page .. "/" .. state .. "/virtual", virtual)
        Add(page .. "/" .. state .. "/inventory", out)
        Add(page .. "/" .. state .. "/values", Gates(page))
        local names, layout, owned = {}, {}, Owned(page)
        local function Name(w)
            if not w or not owned[w] then return "external" end
            if names[w] then return names[w] end
            names[w] = "..."
            names[w] = Name(w:GetParent()) .. "/" .. w:GetObjectType() .. ":" .. (type(w.text) == "string" and w.text or "")
                .. ":" .. tostring(w.width) .. "x" .. tostring(w.height)
            return names[w]
        end
        for w in pairs(owned) do
            local points = {}
            for i = 1, w:GetNumPoints() do
                local point, parentWidget, relative, x, y = w:GetPoint(i)
                points[#points + 1] = { point, Name(parentWidget), relative, x, y }
            end
            layout[#layout + 1] = Encode({ Name(w), points, w:IsShown(), Enabled(w), w.alpha,
                w._msuf2FontRole, w.textColor, w.justifyH, w.texture })
        end
        table.sort(layout)
        Add(page .. "/" .. state .. "/layout", layout)
        return owned
    end
    local function Edit(page, c, value, tag)
        local key = page .. "/" .. tag .. "/" .. c.record.controlId
        -- Hidden selected-field controls have no input route (e.g. Pet XP width on another indicator).
        if not c.widget:IsShown() then
            Add(key .. "/hidden", Gates(page))
            return
        end
        M.ClearHistory()
        local before = F.CopySnapshot(env.MSUF_DB)
        calls = {}
        Input(c, value)
        local after = F.CopySnapshot(env.MSUF_DB)
        Add(key .. "/input", { Diff(before, after), calls, Gates(page) })
        Add(key .. "/history", M.GetHistoryState())
        local undo = M.Undo()
        mw:RunTimers()
        Add(key .. "/undo", { undo, Diff(before, env.MSUF_DB) })
        local redo = M.Redo()
        mw:RunTimers()
        Add(key .. "/redo", { redo, Diff(after, env.MSUF_DB) })
        M.ClearHistory()
        before = F.CopySnapshot(env.MSUF_DB)
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        calls = {}
        local combatValue = value
        if type(value) == "boolean" then combatValue = not value end
        Input(c, combatValue)
        Add(key .. "/combat", { Diff(before, env.MSUF_DB), calls, M.Undo() })
        core.Util.InCombat("PLAYER_REGEN_ENABLED")
    end
    local function OpenSections(page)
        for id, section in pairs(M.cache[page].sections) do
            if wantedSections[id] then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        M.Refresh(M.cache[page].ctx)
        mw:RunTimers()
    end
    -- Controls that exist for one indicator only need that indicator selected before their input.
    local function IndicatorFor(unit, id)
        local want
        if id:find("selected.symbol", 1, true) or id:find("status.midnight", 1, true) then want = "statusCombat"
        elseif id:find("selected.iconstyle", 1, true) or id:find("selected.customicon", 1, true) then want = "leader"
        elseif id:find("raid_group.style", 1, true) then want = "raidgroupname" end
        local spec = want and M.UnitPage.FindStatusSpec(unit, want)
        if spec and spec.value == want then return want end
        return unit == "pet" and "statusPetXP" or "level"
    end
    local function SectionKey(key)
        for _, pattern in ipairs(SECTION_KEYS) do
            if key:find(pattern) then return true end
        end
        return false
    end
    local function ClearSectionKeys(unit)
        local conf, owned = env.MSUF_DB[unit], {}
        for _, item in ipairs(M.UnitPage.StatusValues(unit)) do
            local spec = M.UnitPage.FindStatusSpec(unit, item.value)
            for _, field in ipairs(STATUS_FIELDS) do
                if spec and type(spec[field]) == "string" then owned[spec[field]] = true end
            end
        end
        local saved = {}
        for key, value in pairs(conf) do
            if type(key) == "string" and (owned[key] or SectionKey(key)) then saved[key] = value end
        end
        for key in pairs(saved) do conf[key] = nil end
        return saved
    end
    -- Four pages cover every builder/control, including boss-only rate, arena-only
    -- trinkets and Classic pet XP. Both ordinary and non-default selected states run.
    for _, unit in ipairs({ "target", "boss", "arena", "pet" }) do
        wantedSections = unit == "boss" and { range_fade = true } or unit == "arena" and { pvp_trinket = true }
            or unit == "pet" and { status_icons = true } or sections
        local page = "uf_" .. unit
        if not M.pages[page] then Add(page .. "/absent", true)
        else
            assert(mw:Select(page))
            local cold = {}
            for id, section in pairs(M.cache[page].sections) do
                if wantedSections[id] then cold[id] = { section._msuf2CollapsibleEntry.open, section:GetHeight() } end
            end
            Add(page .. "/lazy-shells", cold)
            OpenSections(page)
            local owned = Inventory(page, "default")
            if not prior then CheckDeclared(unit, owned) end
            -- A sparse profile reads every control through its UI fallback.
            local saved = ClearSectionKeys(unit)
            M.Refresh(M.cache[page].ctx)
            mw:RunTimers()
            Inventory(page, "absent")
            for key, value in pairs(saved) do env.MSUF_DB[unit][key] = value end
            M.Refresh(M.cache[page].ctx)
            mw:RunTimers()
            local controls = Controls(page)
            for state = 1, 2 do
                if state == 2 then
                    local conf = env.MSUF_DB[unit]
                    conf.unitDispelOverlayEnabled, conf.unitDispelSymbolEnabled = true, true
                    conf.texLayerEnabled, conf.texLayerGradientEnabled = true, true
                    conf.texLayerVisibility, conf.texLayerTargetOnly = "TARGET", nil
                    conf.texLayerColorMode, conf.texLayerHealthLowAlphaEnabled = "HEALTH", true
                    M.unitStatusSelection = M.unitStatusSelection or {}
                    M.unitStatusSelection[unit] = unit == "pet" and "statusPetXP" or "level"
                    M.Refresh(M.cache[page].ctx)
                    mw:RunTimers()
                    Inventory(page, "edge")
                end
                for _, c in ipairs(controls) do
                    local w, r = c.widget, c.record
                    local kind, id = r.kind, r.controlId
                    -- Section navigation/actions and selectors are exercised separately,
                    -- because they replace the control tree being iterated here.
                    local conf, section = env.MSUF_DB[unit], SectionOf(w, M.cache[page])
                    if state == 2 then
                        if section == "unit_dispel_overlay" then conf.unitDispelOverlayEnabled = true end
                        if section == "unit_dispel_symbol" then conf.unitDispelSymbolEnabled = true end
                        if section == "texture_layer" then conf.texLayerEnabled, conf.texLayerGradientEnabled = true, true end
                        if section == "range_fade" then conf.rangeFadeEnabled = true end
                        if section == "pvp_trinket" then conf.showTrinket = true end
                    end
                    if section == "status_icons" then
                        -- Indicator-specific controls are only reachable with their indicator selected.
                        M.unitStatusSelection[unit] = IndicatorFor(unit, id)
                        local spec = M.UnitPage.CurrentStatusSpec(unit)
                        if state == 2 and spec then conf[spec.show] = true end
                        -- A stored non-default style turns the default choice into a real write.
                        if id:find("raid_group.style", 1, true) then conf.raidGroupNameStyle = "BRACKET" end
                        if state == 2 and spec and id:find(".reset", 1, true) then conf[spec.size] = 31 end
                    end
                    if state == 2 or section == "status_icons" then
                        M.Refresh(M.cache[page].ctx)
                        mw:RunTimers()
                    end
                    if (kind == "toggle" or kind == "slider" or kind == "dropdown" or kind == "textinput"
                        or id:find("range_fade.layer_mode", 1, true)
                        or (kind == "button" and (id:find("texture_layer.preset.", 1, true)
                            or id:find("gradient_direction.", 1, true) or id:find("status.preview.", 1, true)
                            or id:find("status.selected.reset", 1, true) or id:find("status.advanced.reset", 1, true))))
                        and not id:find("status.selector", 1, true) then
                        local values = Values(c)
                        Edit(page, c, values[state], tostring(state))
                    end
                end
            end
            -- The same status controls resolve their selected field at input time.
            local selected = M.UnitPage.FindStatusSpec(unit, "statusThreat")
            if selected and selected.value == "statusThreat" then
                M.unitStatusSelection[unit] = "statusThreat"
                M.Refresh(M.cache[page].ctx)
                for _, c in ipairs(controls) do
                    if c.record.controlId:find("status.threat.", 1, true) then Edit(page, c, false, "threat") end
                end
            end
            for id, section in pairs(M.cache[page].sections) do
                local action = wantedSections[id] and section._msuf2CollapsibleEntry._msuf2SectionActions
                if action then
                    action:Click()
                    local popup = assert(action._msuf2GetSectionPopup(), "section actions " .. id)
                    M.ClearHistory()
                    local before = F.CopySnapshot(env.MSUF_DB)
                    calls = {}
                    local copied = popup._msuf2CopySection("player")
                    mw:RunTimers()
                    Add(page .. "/copy/" .. id, { copied, Diff(before, env.MSUF_DB), calls })
                    local undone = M.Undo()
                    mw:RunTimers()
                    Add(page .. "/copy-undo/" .. id, { undone, Diff(before, env.MSUF_DB) })
                    popup:Hide()
                end
            end
            if unit == "target" then
                local slot, customPath, selector, tabs
                for _, c in ipairs(controls) do
                    if c.record.controlId:find("texture_layer.slot_selector", 1, true) then slot = c.widget end
                    if c.record.controlId:find("texture_layer.category_selector", 1, true) then tabs = c end
                    if c.record.controlId:find("texture_layer.customtexturepath", 1, true) then customPath = c end
                    if c.record.controlId:find("status.selector", 1, true) then selector = c end
                end
                assert(selector, "status selector missing")
                Edit(page, selector, "level", "select-status")
                -- The category bar only switches which card is shown.
                assert(tabs, "texture category selector missing")
                Edit(page, tabs, "advanced", "select-tab")
                Add(page .. "/tab", M.unitTexLayerTab.target)
                Inventory(page, "advanced-tab")
                assert(slot and customPath, "texture slot owners missing")
                slot:SetValue(2)
                mw:RunTimers()
                M.ClearHistory()
                Edit(page, customPath, "Interface\\Buttons\\UI-CheckBox-Check", "old-slot-callback")
                Add(page .. "/slot-owner", { env.MSUF_DB.target.texLayerCustomTexturePath,
                    env.MSUF_DB.target.texLayer2CustomTexturePath, M.unitTexLayerSlot.target, slot:GetValue() })
            end
            mw:Select("home")
            mw:Select(page)
            Inventory(page, "reopen")
            -- The narrow layouts (dispel cards, texture columns) are separate code paths.
            M.formContentMaxWidth = 420
            M.InvalidatePage(page)
            assert(mw:Select(page))
            OpenSections(page)
            Inventory(page, "narrow")
            M.formContentMaxWidth = nil
            M.InvalidatePage(page)
        end
    end
    return receipts
end
local expected, actual = Replay(true), Replay(false)
local keys = {}
for key in pairs(expected) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do
    local value = expected[key]
    if actual[key] ~= value then
        local out = assert(io.open(scratch .. "/unitextra-parity-diff-" .. flavor .. ".txt", "wb"))
        out:write(key, "\nPARENT\n", value, "\nCANDIDATE\n", tostring(actual[key]), "\n")
        out:close()
        error(flavor .. ": parity mismatch " .. key)
    end
end
for key in pairs(actual) do assert(expected[key], "extra receipt " .. key) end
print("menu_unitextra_parity_smoke: " .. flavor .. " PASS (" .. #keys .. " receipts)")

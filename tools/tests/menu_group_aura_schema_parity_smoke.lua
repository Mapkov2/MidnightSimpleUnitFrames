-- Real Group Aura controls replayed against their reachable pre-schema source.
-- Offline binding and layout evidence; no live rendering or performance claim.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local mode = arg[3] or "full"
assert(mode == "full" or mode == "push" or mode == "original", "unknown Group Aura tier")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua"
local blob = "c811f4e51321cd98594cb94032583fc6be04edfd"
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root .. '" show ' .. blob, "r"))
local source = pipe:read("*a") assert(pipe:close(), "parent source read failed")
assert(#source > 23000, "reachable parent source missing")
-- Each invocation owns a portable temporary parent; concurrent clients never share it.
local scratch = os.tmpname()
local file, diff, diffPath
local function Run()
file = assert(io.open(scratch, "wb"))
assert(file:write(source)) assert(file:close()) file = nil
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or value:GetObjectType()) end
    seen = seen or {} if seen[value] then return "<cycle>" end seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids) .. "=" .. Encode(value[key], ids, seen) end
    seen[value] = nil return "{" .. table.concat(out, ",") .. "}"
end
local function Restore(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end Restore(dst[key], value)
        else dst[key] = value end
    end
end
local function Replay(original)
    print("Group Aura " .. flavor .. ": " .. (original and "immutable parent" or "candidate"))
    local loaded = 0
    local classicReplay = mode ~= "push" and (flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists")
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = classicReplay and function(world)
            -- Same native API seam as group_page_reset_cases; unknown IDs stay absent.
            -- Real per-flavor SI Druid names and the shared Classic Filters SATED table.
            local names = { [774] = "Rejuvenation", [8936] = "Regrowth", [57723] = "Exhaustion", [57724] = "Sated" }
            world.env.GetSpellInfo = function(rawID)
                local id = tonumber(rawID)
                local name = names[id]
                if name then return name, nil, nil, nil, nil, nil, id end
            end
        end or nil,
        beforeOptions = function(world)
            if mode ~= "push" then
                -- Native FlipBook dimensions used by the real spell-glow painter.
                -- Keep this fixture local to full replays; preserve existing methods.
                local methods = world.widgets.Methods
                for _, part in ipairs({ "Wheel", "Value" }) do
                    local key = part
                    methods["SetColor" .. key .. "Texture"] = function(self, texture) self["color" .. key] = texture end
                    methods["SetColor" .. key .. "ThumbTexture"] = function(self, path)
                        local texture = self:CreateTexture()
                        texture:SetTexture(path) self["color" .. key .. "Thumb"] = texture
                    end
                    methods["GetColor" .. key .. "ThumbTexture"] = function(self) return self["color" .. key .. "Thumb"] end
                end
                methods.SetColorRGB = function(self, red, green, blue)
                    self.nativeRGB = { red, green, blue }
                    MenuWorld.FireScript(self, "OnColorSelect", red, green, blue)
                end
                if methods.SetFlipBookFrameWidth == nil then
                    methods.SetFlipBookFrameWidth = function(self, width) self.flipBookFrameWidth = width end
                end
                if methods.SetFlipBookFrameHeight == nil then
                    methods.SetFlipBookFrameHeight = function(self, height) self.flipBookFrameHeight = height end
                end
            end
            local load = world.LoadFile
            world.LoadFile = function(self, path, addon, namespace)
                if path:gsub("\\", "/") == root .. "/" .. target then
                    loaded = loaded + 1
                    if original then path = scratch elseif arg[4] and arg[4] ~= "-" then path = arg[4] end
                end
                return load(self, path, addon, namespace)
            end
        end })
    assert(loaded == 1, "exact page source not loaded once")
    local M, env, core = mw.M, mw.env, mw.core
    env.MSUF_UFCore_NotifyConfigChanged = function() return true end
    env.MSUF_ApplyModules = function() return true end
    env.MSUF_ClassPower_Apply = function() return true end
    local F, rows, ids, calls = core.ProfileFields, {}, {}, {}
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Diff(a, b, path, out)
        path, out = path or "", out or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {} for key in pairs(a) do keys[key] = true end for key in pairs(b) do keys[key] = true end
            for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), out) end
        elseif Encode(a, ids) ~= Encode(b, ids) then out[path] = { Encode(a, ids), Encode(b, ids) } end
        return out
    end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, ... } return fn(...)
        end end
    end
    local GP = M.GroupPage
    local scopes = { "party", "raid" }
    if core.Client.SupportsGroupKind("mythicraid") then scopes[#scopes + 1] = "mythicraid" end
    if mode == "push" then scopes = { "party" } end
    local lanes = mode == "push" and { "buff" } or { "buff", "debuff", "externals" }
    local factory = F.CopySnapshot(env.MSUF_DB)
    local total, exercised, nilCases, seams, declarations = 0, 0, 0, 0, 0
    local pageBuilder, forcedWidth = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, ...)
        if forcedWidth then ctx.width = forcedWidth end
        return pageBuilder(ctx, ...)
    end
    local fieldNames = {}
    for name in ("enabled anchor growth max size layer perRow spacing iconScale autoBlacklistBuffs iconZoom showTooltip "
        .. "showCooldown showCooldownSwipe cooldownSize cooldownAnchor cooldownX cooldownY cooldownSwipeReverse "
        .. "cooldownDecimalSeconds showDurationBar durationBarHeight durationBarDisplay durationBarPosition "
        .. "durationBarDirection showStacks stackSize stackAnchor stackX stackY dynamicScale sortMethod sortReverse"):gmatch("%S+") do
        fieldNames[name:lower()] = name
    end
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function ModelValue(w) return Pack(Command(w).get()) end
    local function DisplayValue(w)
        local kind = w._msuf2RuntimeControlRecord.kind
        if kind == "toggle" then return Pack(w:GetChecked()) end
        if kind == "textinput" then return Pack(w:GetText()) end
        return Pack(w:GetValue())
    end
    local nativeCounts, nativeSeen, nativeScopes, nativeScopeSeen, nativeContext = {}, {}, {}, {}
    local popups = assert(loadfile(root .. "/tools/tests/static_popup_stub.lua"))().Install(env)
    local function Text(region)
        if type(region) ~= "table" or type(region.GetText) ~= "function" then return {} end
        return Pack(region:GetText(), region:GetObjectType() == "FontString" and Pack(region:GetTextColor()) or {}, region:IsShown(), region:GetAlpha())
    end
    local function Paint(region)
        if not region then return {} end
        if region.L or region.M or region.R then
            -- Theme.CreateSuperellipseLayers returns a plain L/M/R composite, not a native region.
            assert(region.GetObjectType == nil and type(region.SetVertexColor) == "function"
                and type(region.Layout) == "function", "unexpected superellipse paint owner")
            local parts = { "superellipse-parts" }
            for _, key in ipairs({ "L", "M", "R" }) do
                local texture = assert(region[key], "missing superellipse native texture: " .. key)
                assert(texture:GetObjectType() == "Texture", "wrong superellipse native texture kind: " .. key)
                parts[#parts + 1] = { key, Paint(texture) }
            end
            return parts
        end
        local value = { region:GetObjectType(), region:IsShown(), region:GetAlpha() }
        if region:GetObjectType() == "Texture" then
            value[#value + 1] = { Pack(region:GetVertexColor()), region.colorTexture, region.gradientAlpha, region.gradient }
        end
        for _, child in ipairs(region.regions or {}) do
            if child:GetObjectType() == "Texture" then value[#value + 1] = { child:IsShown(), Pack(child:GetVertexColor()), child.colorTexture, child.gradientAlpha, child.gradient } end
        end
        return value
    end
    local function NativeDetails(w)
        if w._msuf2RuntimeControlRecord and w._msuf2RuntimeControlRecord.kind == "slider" and w.editBox and type(w._msuf2FormatValue) == "function" then
            assert(w.editBox:GetText() == w._msuf2FormatValue(w:GetValue()),
                "visible slider caption drift: " .. tostring(w._msuf2RuntimeControlRecord.controlId)
                    .. ":native=" .. tostring(w:GetValue()) .. ":caption=" .. tostring(w.editBox:GetText()))
        end
        local buttons = {}
        for _, button in ipairs(w.buttons or {}) do
            buttons[#buttons + 1] = { button._msuf2Value, button._msuf2Active,
                button:GetText(), Text(button._msuf2Label), Paint(button._msuf2Fill), Paint(button._msuf2Edge) }
        end
        local motion = {}
        for _, selection in ipairs(w._msuf2SelectionMotions or {}) do
            local driver = selection.driver
            motion[#motion + 1] = { selection.selected and selection.selected._msuf2Value,
                driver and Paint(driver.art), driver and Pack(driver:GetSize()), driver and Pack(driver:GetPoint()) }
        end
        local parent = w:GetParent()
        local disclosure = parent and parent._msuf2CollapsibleEntry
        local header
        if disclosure and disclosure.header == w then
            header = { disclosure.open, Text(disclosure.label), Text(disclosure.hint), disclosure.body:IsShown(),
                disclosure.body:GetAlpha(), disclosure.body:GetHeight(), disclosure.outer:GetHeight(), disclosure.arrow.rotation }
        end
        local kind = w._msuf2RuntimeControlRecord and w._msuf2RuntimeControlRecord.kind
        local objectType = w:GetObjectType()
        local hasValue = (kind == "slider" and objectType == "Slider") or kind == "dropdown" or kind == "segment"
        local previewBox = kind == "slider" and objectType == "Frame" and w:GetParent() and w:GetParent():GetParent()
        local hasText = objectType == "Button" or objectType == "CheckButton" or objectType == "EditBox" or objectType == "FontString"
        return { value = hasValue and w:GetValue(), text = hasText and w:GetText(), label = Text(w._msuf2Label), title = Text(w._msuf2Title),
            caption = w.editBox and w.editBox:GetText(), directLabel = type(w.label) == "table" and Text(w.label),
            buttons = buttons, selectionPaint = motion, labelPaint = Paint(w._msuf2Label),
            nativeFS = Text(w.fs), nativeLabel = Text(w._label), disclosure = header,
            nativeZoomReadout = previewBox and Text(previewBox._zoomReadout) }
    end
    local function Within(w, parent)
        while w do if w == parent then return true end w = w:GetParent() end
        return false
    end
    local function EffectiveShown(w)
        while w do
            if not w:IsShown() then return false end
            w = w:GetParent()
        end
        return true
    end
    local function BlacklistOwner(w)
        local record = w._msuf2RuntimeControlRecord
        local scope, lane, token
        if record then
            scope, lane, token = tostring(record.controlPath):match(
                "^auras/group%-workspace/scope/([^/]+)/lane/([^/]+)/blacklist/entry/([^/]+)/remove$")
        end
        if not scope then return end
        local row = w:GetParent()
        assert(record.pageKey == "gf_auras" and record.kind == "button" and record.classification == "action"
            and row and row.remove == w, "native blacklist Remove row owner drift")
        local live = M.RuntimeControlCatalog.Get(record.controlId)
        assert(live and live.widget == w and live == record and w._msuf2RuntimeControlId == record.controlId,
            "native blacklist Remove catalog owner drift")
        return row, scope, lane, token
    end
    local function Find(id, optional)
        local entry = M.cache.gf_auras
        for _, w in ipairs(mw.world.widgets.frames) do
            local record = w._msuf2RuntimeControlRecord
            if record and record.controlId == id and entry and Within(w, entry.wrapper) then ids[w] = id return w end
        end
        local record = M.RuntimeControlCatalog.Get(id)
        local w = record and record.widget
        if w then ids[w] = id return w end
        assert(optional, "native owner missing: " .. id)
    end
    local function OpenSections()
        local entry = assert(M.cache.gf_auras)
        for _ = 1, 3 do
            local names = {} for name in pairs(entry.sections) do names[#names + 1] = name end table.sort(names)
            for _, name in ipairs(names) do
                local section = entry.sections[name]
                M.Widgets.EnsureSectionContent(section)
                if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
        end
        mw:RunTimers()
    end
    local function FinishNativeTransitions()
        -- Deliver only bounded native UI completion/ticks; never call refresh/paint helpers.
        for _, frame in ipairs(mw.world.widgets.frames) do
            for _, key in ipairs({ "_msuf2AlphaFade", "_msuf2AlphaScale" }) do
                local group = frame[key]
                if group and group:IsPlaying() and group:GetScript("OnFinished") then
                    group:Finish() MenuWorld.FireScript(group, "OnFinished")
                end
            end
            for _, selection in ipairs(frame._msuf2SelectionMotions or {}) do
                local driver = selection.driver
                for _ = 1, 120 do
                    if not (driver and driver:GetScript("OnUpdate")) then break end
                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                end
                assert(not (driver and driver:GetScript("OnUpdate")), "native finite selection motion did not settle")
            end
        end
        mw:RunTimers()
    end
    local function PickerSwatchPaint(field, expectedRGBA, role)
        local fill = assert(field.fill, "native context picker fill missing: " .. role)
        local values = {}
        local function Texture(texture, part)
            assert(texture, "native context picker texture missing: " .. role .. "." .. part)
            local kind, rgba, shown, alpha = texture:GetObjectType(), Pack(texture:GetVertexColor()), texture:IsShown(), texture:GetAlpha()
            assert(kind == "Texture", "native context picker texture kind drift: " .. role .. "." .. part)
            assert(shown == true and alpha == 1, "native context picker texture visibility drift: " .. role .. "." .. part)
            assert(Encode(rgba, ids) == Encode(expectedRGBA, ids), "native context picker swatch drift: " .. role .. "." .. part
                .. ":expected=" .. Encode(expectedRGBA, ids) .. ":actual=" .. Encode(rgba, ids))
            values[#values + 1] = { part, kind, rgba, shown, alpha }
        end
        if fill.GetObjectType then
            Texture(fill, "single")
        else
            assert(type(fill.SetVertexColor) == "function" and fill.L and fill.M and fill.R,
                "native context picker composite shape drift: " .. role)
            for _, part in ipairs({ "L", "M", "R" }) do Texture(fill[part], part) end
        end
        return values
    end
    local function NativeInput(w, value)
        local record, result = w._msuf2RuntimeControlRecord
        local inputId = record and record.controlId
        if inputId then
            nativeSeen[inputId] = true
            if nativeContext then nativeScopeSeen[nativeContext .. ":" .. inputId] = true end
        end
        if not w:IsShown() then nativeCounts.hidden_attempts = (nativeCounts.hidden_attempts or 0) + 1 return false end
        if not w:IsEnabled() then nativeCounts.disabled_attempts = (nativeCounts.disabled_attempts or 0) + 1 return false end
        nativeCounts.dispatched_inputs = (nativeCounts.dispatched_inputs or 0) + 1
        local kind = record and record.kind or w:GetObjectType():lower()
        if kind == "segment" then
            local choice
            for _, button in ipairs(w.buttons or {}) do if button._msuf2Value == value then choice = button break end end
            assert(choice and choice:GetScript("OnClick"), "native selector choice missing: " .. tostring(ids[w]))
            result = choice:Click("LeftButton")
            mw:RunTimers()
            if record and record.controlId == "menu2.gf_auras.group.navigation.section.selector" then
                -- The departed page keeps ctx.key; the destination owns the new visible selector.
                assert(M.activeKey == value, "native page navigation active key drift")
                local entry = assert(M.cache[value], "native page navigation destination missing")
                assert(entry.wrapper:IsShown(), "native page navigation destination hidden")
                local targetId = "menu2." .. value .. ".group.navigation.section.selector"
                local target
                for _, candidate in ipairs(mw.world.widgets.frames) do
                    local candidateRecord = candidate._msuf2RuntimeControlRecord
                    if candidateRecord and candidateRecord.controlId == targetId then
                        local owner = candidate
                        while owner do
                            -- Sticky headers retain logical page ownership when reparented to their host.
                            if owner == entry.wrapper or owner._msuf2PageOwnerWrapper == entry.wrapper then
                                assert(not target or target == candidate, "native page navigation selector ambiguous")
                                target = candidate break
                            end
                            owner = owner:GetParent()
                        end
                    end
                end
                assert(target and target:IsShown(), "native page navigation destination selector missing or hidden")
                ids[target] = targetId
                assert(target:GetValue() == value, "native page navigation destination selector drift")
                for _, button in ipairs(target.buttons) do
                    assert(button._msuf2Active == (button._msuf2Value == value), "native page navigation destination paint drift")
                end
                Add("native-page-navigation-display", record.controlId, value, M.activeKey, entry.wrapper:IsShown(),
                    targetId, NativeDetails(target), target:IsShown(), target:IsEnabled())
            else
                assert(w:GetValue() == value, "native selector callback drift: " .. tostring(ids[w]))
                for _, button in ipairs(w.buttons) do
                    assert(button._msuf2Active == (button._msuf2Value == value), "native selector active paint drift: " .. tostring(ids[w]))
                end
            end
        elseif kind == "dropdown" then
            assert(w:GetScript("OnClick"), "native dropdown opener missing: " .. tostring(ids[w]))
            FinishNativeTransitions()
            w:Click("LeftButton") mw:RunTimers()
            if M.IsConfigCombatLocked and M.IsConfigCombatLocked() then return false end
            local selected
            for _, row in ipairs(mw.world.widgets.frames) do
                if row._msuf2Owner == w and row._msuf2Value == value and row:IsShown() and not row._msuf2DropdownDisabled then selected = row break end
            end
            assert(selected and selected:GetScript("OnClick"), "native dropdown row missing: " .. tostring(ids[w]))
            selected:Click("LeftButton")
            assert(w:GetValue() == value, "native dropdown selection drift: " .. tostring(ids[w]))
        elseif kind == "textinput" or kind == "editbox" then
            w:SetText(value) MenuWorld.FireScript(w, "OnTextChanged", true) MenuWorld.FireScript(w, "OnEnterPressed")
        elseif kind == "toggle" then w:SetChecked(value) result = w:Click("LeftButton")
        elseif kind == "slider" and w:GetObjectType() ~= "Slider" then
            -- The registered zoom surface is a Frame with wheel ownership, not a Slider.
            local command = w._msuf2CommandAction or record.command
            assert(command and command.get and w:GetScript("OnMouseWheel"), "logical slider lost its native wheel owner")
            local before, control = command.get(), env.IsControlKeyDown
            env.IsControlKeyDown = function() return true end
            MenuWorld.FireScript(w, "OnMouseWheel", before >= command.max and -1 or 1)
            env.IsControlKeyDown = control
            mw:RunTimers() FinishNativeTransitions()
            assert(command.get() ~= before, "native preview wheel callback drift")
            local box = w:GetParent():GetParent()
            assert(box._zoomReadout:GetText() == tostring(command.get()) .. "%", "native preview zoom readout drift")
        elseif kind == "slider" then w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value)
        else assert(w:GetScript("OnClick"), "native action Click missing: " .. tostring(ids[w])) result = w:Click(value or "LeftButton") end
        mw:RunTimers() FinishNativeTransitions()
        Add("native-input-display", record and record.controlId or w:GetObjectType(), NativeDetails(w), w:IsShown(), w:IsEnabled())
        local parent = w
        while parent do
            if parent.compactHex and parent.current and parent.owner then
                local red, green, blue = parent.owner:GetRGB()
                local expectedRGBA = Pack(red, green, blue, 1)
                local currentPaint = PickerSwatchPaint(parent.current, expectedRGBA, "current.fill")
                local selectorPaint = PickerSwatchPaint(parent.selector.color, expectedRGBA, "selector.fill")
                Add("native-picker-display", Text(parent.title), Text(parent.selector.label), Text(parent.compactHex),
                    currentPaint, selectorPaint)
                break
            end
            parent = parent:GetParent()
        end
        if inputId then
            nativeSeen[inputId] = true
            if nativeContext then nativeScopeSeen[nativeContext .. ":" .. inputId] = true end
        end
        return result
    end
    local function NativeCase(family, tag, run)
        nativeCounts[family] = (nativeCounts[family] or 0) + 1
        calls = {}
        local before = F.CopySnapshot(env.MSUF_DB)
        local result = run()
        Add("native:" .. family .. ":" .. tag, result, Diff(before, env.MSUF_DB), calls, M.activeKey)
        return result
    end
    local function SelectView(scope, lane, tool, cycle)
        nativeContext = scope .. ":" .. tostring(forcedWidth or 720)
        assert(mw:Select("gf_auras") ~= false) OpenSections()
        local scopeId = "menu2.gf_auras.group.scope.selector"
        local laneId = "menu2.gf_auras.auras.group-workspace.container-selector"
        local function Select(id, value, family)
            local w = Find(id)
            local before = w:GetValue()
            NativeCase(family, scope .. ":" .. lane .. ":" .. tool .. ":" .. tostring(value), function()
                local profileBefore = F.CopySnapshot(env.MSUF_DB)
                M.ClearHistory()
                NativeInput(w, value)
                assert(w:GetValue() == value, "native selector callback drift: " .. id)
                Add("native-selector-display", id, before, value, NativeDetails(w), M.gfScope, M.gfAuraLaneSelection, M.gfAuraToolSelection)
                if not next(Diff(profileBefore, env.MSUF_DB)) then
                    local undo = M.Undo() mw:RunTimers()
                    local redo = M.Redo() mw:RunTimers()
                    assert(not undo and not redo, "native pure menu selector entered profile history: " .. id)
                    Add("native-selector-history", id, undo, redo)
                end
            end)
            OpenSections()
        end
        if cycle then Select(scopeId, scope == "party" and "raid" or "party", "scope") end
        Select(scopeId, scope, "scope") assert(GP.CurrentScope() == scope, "native scope owner drift")
        if cycle then Select(laneId, lane == "buff" and "debuff" or "buff", "container") end
        Select(laneId, lane, "container")
        assert(M.gfAuraLaneSelection[scope] == lane, "native container menu state drift")
        local toolId = "menu2.gf_auras.auras.group-workspace.lane." .. lane .. ".tool-selector"
        if cycle then Select(toolId, tool == "layout" and "behavior" or "layout", "tool") end
        Select(toolId, tool, "tool")
        assert(M.gfAuraToolSelection[scope][lane] == tool, "native tool menu state drift")
    end
    local function Contents(tag)
        local entry = M.cache.gf_auras
        local values = {}
        for _, w in ipairs(mw.world.widgets.frames) do
            if entry and Within(w, entry.wrapper) then
                local record = w._msuf2RuntimeControlRecord
                local texts = {} for _, region in ipairs(w.regions or {}) do
                    if region:GetObjectType() == "FontString" then texts[#texts + 1] = Text(region) end
                end
                if record or #texts > 0 or w._spellID then
                    values[#values + 1] = { record and record.controlId, w._spellID, w:IsShown(), w:IsEnabled(), NativeDetails(w), texts }
                end
            end
        end
        Add("native-contents:" .. tag, values)
        return values
    end
    local function PrepareSpell(scope, w)
        local si = GP.SpellIndicators(scope)
        si.enabled = true
        if si.spec == nil or si.spec == "auto" or si.spec == "multi" then
            for _, item in ipairs(GP.SpellSpecValues()) do
                if item.value ~= "auto" and item.value ~= "multi" then
                    si.spec = item.value
                    if GP.CurrentSpellAura(scope) ~= "" then break end
                end
            end
        end
        local id = w and w._msuf2RuntimeControlRecord.controlId or ""
        if id:find(".multi_spec.tracked", 1, true) then
            si.spec = "multi"
            for _, item in ipairs(GP.SpellTrackedSpecValues()) do
                if item.value ~= "" and not GP.IsAllSpecsSpellSpec(item.value) then
                    M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
                    M.gfSpellMultiSpecSelection[scope] = item.value
                    break
                end
            end
        end
        if id:find(".spell.selected.auto_blacklist", 1, true) then
            GP.AuraGroup(scope, "externals").autoBlacklistBuffs = false
        end
        local selected = GP.CurrentSpellConfig(scope, true)
        if selected then
            selected.enabled = true
            if id:find(".spell.selected.spell_ids", 1, true) then selected.custom = true end
            local placed = GP.PlacedConfig(scope, true)
            placed.type = id:find(".spell.placed.bar", 1, true) and "bar" or "icon"
            placed.barShowTimer = true
            local frame = GP.FrameEffectConfig(scope, true)
            frame.type = "healthtint"
        end
        si.style.showCooldownText, si.style.showCooldownSwipe = true, true
        si.style.showStacks, si.style.showDurationBar = true, true
    end
    local function ClearOrdinary(w, scope, lane)
        local id, targets = w._msuf2RuntimeControlRecord.controlId, {}
        local function Target(owner, key, label)
            if owner then targets[#targets + 1] = { owner = owner, key = key, label = label } end
        end
        local aura = id:match("^menu2%.gf_auras%.auras%.(.*)")
        local spell = id:match("^menu2%.gf_auras%.group%.spell%.(.*)")
        if aura then
            local key = aura:match("%.layout%.([%w%-]+)$") or aura:match("^group%-style%.lane%.[^.]+%.([%w%-]+)$")
            key = key == "icon-scale" and "iconScale" or fieldNames[key or ""]
            if aura:match("^group%-workspace%.root%.enabled$") then key = "enabled"
            elseif aura:match("^group%-workspace%.lane%.[^.]+%.enabled$") then key = "enabled"
            elseif aura:match("%.auto%-blacklist%-buffs$") then key = "autoBlacklistBuffs"
            elseif aura:match("%.sort%-direction$") then key = "sortReverse"
            elseif aura:match("%.cooldown%-swipe%-direction$") then key = "cooldownSwipeReverse"
            elseif aura:find(".filters.native.", 1, true) or aura:match("%.filters%.only%-mine$")
                or aura:match("%.filters%.non%-player$") then key = "filterToken" end
            for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
                local config = GP.AurasRoot(kind)
                local group = GP.AuraGroup(kind, lane)
                if aura:match("^group%-workspace%.root%.") or aura:match("^group%-style%.root%.") then
                    local rootKey = key or fieldNames[aura:match("([^.]+)$") or ""]
                    assert(rootKey, "unmapped ordinary root setting: " .. id)
                    Target(config, rootKey, "gf_" .. kind .. ".auras." .. rootKey)
                elseif aura:match("%.dispel%-border%-mode$") then
                    for _, field in ipairs({ "dispelBorderMode", "showDispelBorder", "showDispelSymbol" }) do
                        Target(group, field, "gf_" .. kind .. ".auras." .. lane .. "." .. field)
                    end
                elseif aura:match("%.filters%.hide%-permanent$") or aura:match("%.filters%.max%-duration$") then
                    group.blacklist = group.blacklist or {}
                    local field = aura:match("%.hide%-permanent$") and "hidePermanent" or "maxDuration"
                    Target(group.blacklist, field, "gf_" .. kind .. ".auras." .. lane .. ".blacklist." .. field)
                else
                    assert(key, "unmapped ordinary aura setting: " .. id)
                    Target(group, key, "gf_" .. kind .. ".auras." .. lane .. "." .. key)
                    if key == "showTooltip" then Target(config, key, "gf_" .. kind .. ".auras." .. key) end
                end
            end
        elseif spell then
            local spec = assert(w._msuf2ControlSchema, "spell ordinary declaration missing: " .. id)
            local key, owner = spec.key or (spell == "selected.layer" and "layer"), nil
            assert(key, "spell declaration key missing: " .. id)
            if spell:match("^placed%.") then owner = GP.PlacedConfig(scope, true)
            elseif spell:match("^frame%.") then owner = GP.FrameEffectConfig(scope, true)
            elseif spell:match("^selected%.") then owner = GP.CurrentSpellConfig(scope, true)
            elseif spell:match("^style%.") then owner = GP.SpellIndicators(scope).style
            elseif spell == "icon_zoom" or spell == "icon_scale" or spell == "enabled" or spell == "spec" then
                owner = GP.SpellIndicators(scope)
            elseif spell == "multi_spec.tracked" then
                local si = GP.SpellIndicators(scope)
                si.multiSpecs = si.multiSpecs or {}
                owner, key = si.multiSpecs, GP.CurrentSpellMultiSpec(scope)
            else error("unmapped ordinary spell setting: " .. id) end
            -- No selected record is itself a real absent-record fallback, distinct
            -- from a field removed from an existing record.
            if owner then
                Target(owner, key, "gf_" .. scope .. ".spellIndicators." .. spell .. ":" .. key)
                if spell == "frame.alpha" and type(owner.color) == "table" then
                    Target(owner.color, 4, "gf_" .. scope .. ".spellIndicators.frame.color.4")
                end
            else Add("absent-record:" .. id, scope, spell) end
        else error("unmapped ordinary identity: " .. id) end
        local cleared = {}
        for _, target in ipairs(targets) do
            target.owner[target.key] = nil
            assert(rawget(target.owner, target.key) == nil, "ordinary field was not cleared: " .. target.label)
            cleared[#cleared + 1] = target.label
        end
        assert(#cleared > 0 or spell, "ordinary nil case has no target: " .. id)
        return cleared
    end
    local function Values(w)
        local values = w.values if type(values) == "function" then values = values() end
        return values or {}
    end
    local function Different(w)
        local current = w:GetValue()
        for _, item in ipairs(Values(w)) do
            if item.value ~= nil and not item.disabled and item.value ~= current then return item.value end
        end
        return current
    end
    local function HistoryAction(family, tag, input, capture, verify, verifyHistory)
        local before = Encode(capture(), ids)
        local dbBefore = F.CopySnapshot(env.MSUF_DB)
        M.ClearHistory()
        NativeCase(family, tag, input)
        local after = Encode(capture(), ids)
        assert(before ~= after and next(Diff(dbBefore, env.MSUF_DB)), "native action callback drift: " .. family .. ":" .. tag)
        if verify then verify() end
        Contents(family .. ":input")
        local undo = M.Undo() mw:RunTimers() FinishNativeTransitions()
        assert(undo and Encode(capture(), ids) == before, "native action Undo drift: " .. family .. ":" .. tag)
        if verifyHistory then verifyHistory("undo") end
        Add("native-history-undo:" .. family, tag, undo, Diff(dbBefore, env.MSUF_DB)) Contents(family .. ":undo")
        local redo = M.Redo() mw:RunTimers() FinishNativeTransitions()
        assert(redo and Encode(capture(), ids) == after, "native action Redo drift: " .. family .. ":" .. tag)
        if verifyHistory then verifyHistory("redo") end
        Add("native-history-redo:" .. family, tag, redo, Diff(dbBefore, env.MSUF_DB)) Contents(family .. ":redo")
    end
    local function Refusal(family, tag, input)
        if mode == "push" then return end
        local before = F.CopySnapshot(env.MSUF_DB)
        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return false end
        NativeCase(family .. "-combat-edge", tag, input)
        assert(not next(Diff(before, env.MSUF_DB)), "native action combat-edge profile drift: " .. family)
        env.InCombatLockdown = function() return true end
        NativeCase(family .. "-combat", tag, input)
        assert(not next(Diff(before, env.MSUF_DB)), "native action combat profile drift: " .. family)
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
    end
    local historyGenerationCase, historyGenerations = nil, 0
    local function RunNativeOwners(scope, lane, tool, width, setup)
        local scopeKey, tag = scope .. ":" .. width, scope .. "/" .. lane .. "/" .. tool .. "/" .. width
        nativeContext = scopeKey
        local function ReturnView() SelectView(scope, lane, tool, false) setup("default") end
        local function Once(family, run)
            local key = scopeKey .. ":" .. family
            if nativeScopes[key] then return end
            nativeScopes[key] = true run()
        end
        local function AllOwners(label)
            local inventory, seen = {}, {}
            for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
                local item = M.RuntimeControlCatalog.Get(record.controlId)
                local w = item and item.widget
                if w and record.pageKey == "gf_auras" and Within(w, assert(M.cache.gf_auras).wrapper)
                    and not seen[w] and (record.kind == "button" or record.kind == "segment" or record.kind == "dropdown"
                        or record.kind == "textinput" or record.kind == "toggle" or record.kind == "slider") then
                    seen[w], ids[w] = true, w._msuf2RuntimeControlRecord.controlId
                    inventory[#inventory + 1] = w
                end
            end
            table.sort(inventory, function(a, b) return ids[a] < ids[b] end)
            for _, w in ipairs(inventory) do
                Add("native-owner-inventory:" .. label, ids[w], w._msuf2RuntimeControlRecord, NativeDetails(w), w:IsShown(), w:IsEnabled())
            end
            return inventory
        end
        AllOwners(tag)
        -- These are native UI navigation owners. No synthetic command is supplied.
        Once("header-scope-navigation", function()
            local entry = M.cache.gf_auras
            local names = {} for name in pairs(entry.sections) do names[#names + 1] = name end table.sort(names)
            assert(#names == 3, "native disclosure census drift")
            for _, name in ipairs(names) do
                local owner = entry.sections[name]._msuf2CollapsibleEntry
                if owner then
                    M.ClearHistory()
                    local before, wasOpen = F.CopySnapshot(env.MSUF_DB), owner.open
                    for _ = 1, 2 do
                        NativeCase("header", scopeKey .. ":" .. name, function()
                            owner.header:Click("LeftButton")
                            for _ = 1, 120 do
                                local driver = owner._msuf2AccordionMotion
                                if not (driver and driver:GetScript("OnUpdate")) then break end
                                MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                            end
                            mw:RunTimers()
                            assert(not owner._msuf2MotionActive and owner.body:IsShown() == owner.open,
                                "native header disclosure drift: " .. name)
                            assert(M.GetPersistentMenuStateTable("accordionState")[owner.stateKey] == owner.open,
                                "native header persistence drift: " .. name)
                            Add("native-header-display", name, owner.open, Text(owner.label), Text(owner.hint), owner.arrow.rotation,
                                owner.body:GetAlpha(), owner.body:GetHeight(), owner.outer:GetHeight())
                        end)
                    end
                    assert(owner.open == wasOpen and not next(Diff(before, env.MSUF_DB)), "native balanced header profile drift")
                    assert(not M.Undo() and not M.Redo(), "native header entered profile history")
                    local record = owner.header._msuf2RuntimeControlRecord
                    if record then
            nativeSeen[record.controlId] = true
            if nativeContext then nativeScopeSeen[nativeContext .. ":" .. record.controlId] = true end
        end
                end
            end
            if mode ~= "push" then
                local page = Find("menu2.gf_auras.group.navigation.section.selector")
                local alternate = Different(page)
                NativeCase("page-navigation", scopeKey, function()
                    NativeInput(page, alternate) assert(M.activeKey == alternate, "native page navigation drift")
                end)
                ReturnView()
            end
        end)
        if mode ~= "push" then Once("open-style:" .. lane, function()
            local style = Find("menu2.gf_auras.auras.group-workspace.open-aura-style")
            NativeCase("open-style", scopeKey .. ":" .. lane, function()
                NativeInput(style) assert(M.activeKey == "auras3_styling", "native global-style action drift")
                assert(M.auraAppearanceContainer == (lane == "debuff" and "debuff" or "buff"), "native style lane drift")
            end)
            ReturnView()
        end) end
        if mode ~= "push" then Once("copy-popup", function()
            ReturnView()
            local opener = Find("menu2.gf_auras.group.copy.open")
            NativeCase("copy-open", scopeKey, function() NativeInput(opener) end)
            local popup
            for _, w in ipairs(mw.world.widgets.frames) do if w._checks and w._targetBtns and w:IsShown() then popup = w end end
            assert(popup, "native Copy To popup missing")
            local function PopupButton(suffix)
                for _, w in ipairs(mw.world.widgets.frames) do
                    local record = w._msuf2RuntimeControlRecord
                    if w:GetParent() == popup and record and record.controlId:sub(-#suffix) == suffix then ids[w] = record.controlId return w end
                end
                error("native copy owner missing: " .. suffix)
            end
            for _, selected in ipairs({ false, true }) do
                NativeCase("copy-categories", scopeKey .. ":" .. tostring(selected), function()
                    NativeInput(PopupButton(selected and ".categories.all" or ".categories.none"))
                    for _, check in ipairs(popup._checks) do assert(check:GetChecked() == selected, "native copy All/None drift") end
                end)
            end
            assert(#popup._checks == 12, "native copy category census drift")
            for _, check in ipairs(popup._checks) do
                local id = assert(check._msuf2RuntimeControlRecord).controlId
                ids[check] = id
                local key, before = assert(id:match("%.category%.(.+)$")), check:GetChecked()
                NativeCase("copy-category", scopeKey .. ":" .. key, function()
                    NativeInput(check, not before)
                    assert(check:GetChecked() == not before and M.gfCopyScopes[key] == not before, "native copy category callback drift: " .. key)
                end)
            end
            NativeInput(PopupButton(".categories.none"))
            NativeInput(PopupButton(".category.auras"), true)
            local targets = {} for dest in pairs(popup._targetBtns) do targets[#targets + 1] = dest end table.sort(targets)
            for _, dest in ipairs(targets) do if dest ~= scope and core.Client.SupportsGroupKind(dest) then
                GP.AuraGroup(scope, "buff").max, GP.AuraGroup(dest, "buff").max = 7, 19
                local target = popup._targetBtns[dest]
                ids[target] = assert(target._msuf2RuntimeControlRecord).controlId
                if not popup:IsShown() then NativeInput(opener) end
                HistoryAction("copy-target", scopeKey .. ":" .. dest, function() NativeInput(target) end,
                    function() return GP.AuraGroup(dest, "buff").max end,
                    function() assert(GP.AuraGroup(dest, "buff").max == 7, "native Copy To aura payload drift") end)
                if not popup:IsShown() then NativeInput(opener) end
                GP.AuraGroup(dest, "buff").max = 19
                Refusal("copy-target", scopeKey .. ":" .. dest, function() NativeInput(target) end)
                ReturnView() opener = Find("menu2.gf_auras.group.copy.open")
                if not popup:IsShown() then NativeInput(opener) end
            end end
            NativeCase("copy-close", scopeKey, function()
                NativeInput(PopupButton(".close")) assert(not popup:IsShown(), "native copy close drift")
            end)
            ReturnView()
        end) end
        if mode ~= "push" then Once("spell-native-owners", function()
            ReturnView()
            local auraPicker = Find("menu2.gf_auras.group.spell.selected_aura")
            PrepareSpell(scope, auraPicker) M.Refresh() mw:RunTimers() M.ClearHistory()
            local value = Different(auraPicker)
            NativeCase("spell-aura-picker", scopeKey, function()
                NativeInput(auraPicker, value)
                assert(GP.CurrentSpellAura(scope) == value and ModelValue(auraPicker)[1] == value, "native spell aura picker drift")
            end)
            local spec = Find("menu2.gf_auras.group.spell.spec")
            NativeInput(spec, "multi")
            local multiPicker = Find("menu2.gf_auras.group.spell.multi_spec.selector")
            value = Different(multiPicker)
            NativeCase("spell-multi-picker", scopeKey, function()
                NativeInput(multiPicker, value)
                assert(GP.CurrentSpellMultiSpec(scope) == value and ModelValue(multiPicker)[1] == value, "native spell multi picker drift")
            end)
            ReturnView() PrepareSpell(scope, auraPicker) M.Refresh() mw:RunTimers()
            local previewAll = Find("menu2.gf_auras.group.spell.preview_all")
            local wasAll = M.gfPreviewAllSpecSpellIcons and M.gfPreviewAllSpecSpellIcons[scope] == true
            NativeCase("spell-preview-all", scopeKey, function()
                NativeInput(previewAll)
                assert((M.gfPreviewAllSpecSpellIcons[scope] == true) ~= wasAll, "native preview-all callback drift")
            end)
            NativeInput(previewAll)
            local tiles = {}
            for _, w in ipairs(mw.world.widgets.frames) do
                if w._grid and w._specKey and w:IsShown() and Within(w, M.cache.gf_auras.wrapper) then tiles[#tiles + 1] = w end
            end
            assert(#tiles > 1, "native spell tile census missing")
            local addTile
            for _, tile in ipairs(tiles) do
                ids[tile] = assert(tile._msuf2RuntimeControlRecord).controlId
                if tile._isAddTile then addTile = tile
                else
                    NativeCase("spell-tile-select", scopeKey .. ":" .. tile._auraName, function()
                        NativeInput(tile, "LeftButton") assert(GP.CurrentSpellAura(scope) == tile._auraName, "native spell tile selection drift")
                    end)
                    local function Enabled()
                        local cfg = GP.SpellIndicators(scope).specs[tile._specKey][tile._auraName]
                        return cfg.enabled ~= false
                    end
                    HistoryAction("spell-tile-toggle", scopeKey .. ":" .. tile._auraName,
                        function() NativeInput(tile, "RightButton") end, Enabled)
                    Refusal("spell-tile-toggle", scopeKey .. ":" .. tile._auraName, function() NativeInput(tile, "RightButton") end)
                    SelectView(scope, lane, tool, false)
                end
            end
            assert(addTile, "native add-custom spell tile missing")
            local function CustomCount()
                local n = 0
                local si = GP.SpellIndicators(scope)
                for _, cfg in pairs(si.specs[addTile._specKey] or {}) do if cfg.custom == true then n = n + 1 end end
                return n
            end
            HistoryAction("spell-custom-add", scopeKey, function()
                NativeInput(addTile)
                local dialog = popups.shown[#popups.shown]
                assert(dialog and dialog.which == "GENERIC_INPUT_BOX", "native custom-spell prompt missing")
                dialog:GetEditBox():SetText("1459")
                assert(popups.Click(dialog, 1), "native custom-spell accept refused") mw:RunTimers()
            end, CustomCount)
            local customTile
            for _, w in ipairs(mw.world.widgets.frames) do
                if w._customBuff and w:IsShown() and Within(w, M.cache.gf_auras.wrapper) then customTile = w break end
            end
            assert(customTile, "native custom-spell tile not painted")
            ids[customTile] = customTile._msuf2RuntimeControlRecord.controlId
            HistoryAction("spell-custom-remove", scopeKey, function() NativeInput(customTile, "RightButton") end, CustomCount)
            ReturnView()
            for _, suffix in ipairs({ "selected.color", "frame.color" }) do
                local shortcut = Find("menu2.gf_auras.group.spell." .. suffix)
                PrepareSpell(scope, shortcut) M.Refresh() mw:RunTimers()
                local picker, owner
                local function OpenPicker()
                    NativeInput(shortcut)
                    for _, w in ipairs(mw.world.widgets.frames) do if w.compactHex and w.done and w.owner and w:IsShown() then picker = w owner = w.owner end end
                    assert(picker and owner, "native context-color picker missing: " .. suffix)
                end
                OpenPicker()
                HistoryAction("spell-color", scopeKey .. ":" .. suffix, function()
                    NativeInput(picker.compactHex, "336699") NativeInput(picker.done)
                end, function() return Pack(owner:GetRGB()) end,
                    function() assert(Encode(Pack(owner:GetRGB()), ids) == Encode(Pack(0.2, 0.4, 0.6), ids), "native color edit callback drift") end)
                OpenPicker()
                local beforeColor = Encode(Pack(owner:GetRGB()), ids)
                NativeCase("spell-color-cancel", scopeKey .. ":" .. suffix, function()
                    NativeInput(picker.compactHex, "774411") NativeInput(picker.cancel)
                    assert(Encode(Pack(owner:GetRGB()), ids) == beforeColor, "native context color Cancel drift")
                end)
                Refusal("spell-color-open", scopeKey .. ":" .. suffix, function()
                    NativeInput(shortcut)
                    for _, w in ipairs(mw.world.widgets.frames) do
                        assert(not (w.compactHex and w.owner and w:IsShown()), "native color opener ignored combat refusal")
                    end
                end)
                ReturnView()
            end
        end) end
        local blacklist = tool == "blacklist" or (mode == "push" and lane == "buff" and tool == "layout" and width == 720)
        if blacklist then
            if tool ~= "blacklist" then SelectView(scope, lane, "blacklist", false) end
            local model = core.MSUF_Auras3.MenuModel
            local prefix = "menu2.gf_auras.auras.group-workspace."
            local baseId = prefix .. "scope." .. scope .. ".lane." .. lane .. ".blacklist"
            local function Entries() return model.GroupBlacklistEntries(scope, lane) end
            local function ListCheck(query)
                local entries, count = Entries(), 0
                query = tostring(query or ""):lower()
                for _, row in ipairs(mw.world.widgets.frames) do
                    if row._spellID and row:IsShown() and Within(row, M.cache.gf_auras.wrapper) then
                        local expected
                        for _, item in ipairs(entries) do if tostring(item.value) == tostring(row._spellID) then expected = item break end end
                        assert(expected, "native blacklist painted unknown ID")
                        local haystack = (tostring(expected.text or "") .. " " .. tostring(expected.spellID or expected.value)):lower()
                        assert(query == "" or haystack:find(query, 1, true), "native blacklist Search callback drift")
                        assert(row.name:GetText() ~= "" and row.id:GetText():find(tostring(expected.spellID or expected.value), 1, true),
                            "native blacklist row label drift")
                        count = count + 1
                    end
                end
                local wanted = 0 for _, item in ipairs(entries) do
                    local text = (tostring(item.text or "") .. " " .. tostring(item.spellID or item.value)):lower()
                    if query == "" or text:find(query, 1, true) then wanted = wanted + 1 end
                end
                assert(count == wanted, "native blacklist Search row-count drift")
            end
            if lane == "buff" then
                local input = Find(prefix .. "lane.buff.blacklist.manual-input")
                NativeCase("blacklist-manual", tag, function()
                    NativeInput(input, "1459") assert(ModelValue(input)[1] == "1459" and input:GetText() == "1459", "native manual input drift")
                end)
                local add = Find(baseId .. ".add")
                HistoryAction("blacklist-add", tag, function() NativeInput(add) end, Entries,
                    function() assert(input:GetText() == "", "native blacklist Add did not clear input") end)
                NativeInput(input, "139")
                Refusal("blacklist-add", tag, function() NativeInput(add) end)
                SelectView(scope, lane, "blacklist", false)
                NativeInput(Find(prefix .. "lane.buff.blacklist.manual-input"), "")
            end
            local preset = Find(prefix .. "lane." .. lane .. ".blacklist.preset-selection")
            local selected = Different(preset)
            if classicReplay then
                -- A real curated but unresolved preset remains a separate empty-list case.
                local emptyPreset = lane == "debuff" and "CHALLENGE_DEBUFFS" or "BLESSING_BRONZE"
                local before = F.CopySnapshot(env.MSUF_DB)
                M.ClearHistory()
                NativeCase("blacklist-empty-preset", tag, function()
                    NativeInput(preset, emptyPreset)
                    assert(M.auraBlacklistPreset == emptyPreset, "Classic empty preset callback drift")
                end)
                assert(#calls == 0, "Classic empty preset selection requested apply")
                local emptySpell = Find(prefix .. "lane." .. lane .. ".blacklist.spell-selection")
                local curated = assert(env.MSUF_GF_AuraFilter.PUBLIC_AURA_PRESET_SPELLS[emptyPreset])
                assert(next(curated) and #model.GroupBlacklistSpellValues(lane, emptyPreset) == 0,
                    "Classic empty preset is missing real source membership or resolved unexpectedly")
                for id in pairs(curated) do assert(env.GetSpellInfo(id) == nil, "Classic unknown fixture ID acquired a name") end
                assert(#Values(emptySpell) == 0 and ModelValue(emptySpell)[1] == nil and emptySpell:GetValue() == nil
                    and M.auraBlacklistSpell == nil, "Classic empty Spell provider/model/native drift")
                NativeCase("blacklist-empty-spell", tag, function()
                    assert(EffectiveShown(emptySpell) and emptySpell:IsEnabled() and emptySpell:GetScript("OnClick"),
                        "Classic empty Spell has no visible enabled native opener")
                    FinishNativeTransitions()
                    emptySpell:Click("LeftButton") mw:RunTimers()
                    for _, row in ipairs(mw.world.widgets.frames) do
                        assert(not (row._msuf2Owner == emptySpell and EffectiveShown(row)
                            and row._msuf2Value ~= nil and not row._msuf2DropdownDisabled),
                            "Classic empty Spell opened a selectable native row")
                    end
                end)
                local undo = M.Undo() mw:RunTimers()
                local redo = M.Redo() mw:RunTimers()
                assert(not undo and not redo and not next(Diff(before, env.MSUF_DB)) and #calls == 0,
                    "Classic empty preset/Spell input changed DB/apply/history")
                assert(M.auraBlacklistPreset == emptyPreset and M.auraBlacklistSpell == nil
                    and ModelValue(emptySpell)[1] == nil and emptySpell:GetValue() == nil,
                    "Classic empty Spell changed selection on native open/history")
                Add("native-classic-empty-preset", tag, emptyPreset, NativeDetails(emptySpell), undo, redo, calls)
                -- Positive choices below use the same genuine native preset owner and popup.
                selected = lane == "debuff" and "SATED" or "RESTO_DRUID"
            end
            NativeCase("blacklist-preset", tag, function()
                NativeInput(preset, selected) assert(M.auraBlacklistPreset == selected, "native preset callback drift")
            end)
            local spell = Find(prefix .. "lane." .. lane .. ".blacklist.spell-selection")
            selected = Different(spell)
            if mode ~= "push" then
                local blocked = M.AuraControls.BlockedSet(Entries())
                if blocked[tostring(selected)] then
                    -- CurrentSpell rejects blocked choices; exercise a genuine eligible alternate.
                    local current = spell:GetValue()
                    selected = nil
                    for _, item in ipairs(Values(spell)) do
                        if item.value ~= nil and not item.disabled and item.value ~= current
                            and not blocked[tostring(item.value)] then selected = item.value break end
                    end
                    assert(selected ~= nil, "native blacklist spell has no eligible alternate: " .. tag)
                end
            end
            if classicReplay then
                local current, choices = ModelValue(spell)[1], Values(spell)
                local blocked, eligible = M.AuraControls.BlockedSet(Entries()), 0
                for _, item in ipairs(choices) do
                    if item.value ~= nil and not item.disabled and not blocked[tostring(item.value)] then eligible = eligible + 1 end
                end
                -- FirstUnblockedSpell is the real getter; a same-value Click never calls the setter.
                assert(#choices == 2 and eligible == 2 and current == spell:GetValue()
                    and selected ~= nil and selected ~= current and M.auraBlacklistSpell == nil,
                    "Classic positive Spell needs two genuine eligible choices and a native alternate")
                Add("native-classic-positive-before", tag, current, selected, eligible, NativeDetails(spell))
            end
            NativeCase("blacklist-spell", tag, function()
                NativeInput(spell, selected) assert(M.auraBlacklistSpell == selected, "native blacklist spell picker drift")
            end)
            if classicReplay then
                local names = lane == "debuff" and { ["57723"] = "Exhaustion", ["57724"] = "Sated" }
                    or { ["774"] = "Rejuvenation", ["8936"] = "Regrowth" }
                local values, count, selectedText = Values(spell), 0, nil
                for value in pairs(names) do count = count + 1 end
                assert(#values == count and #model.GroupBlacklistSpellValues(lane, M.auraBlacklistPreset) == count,
                    "Classic positive Spell provider census drift")
                for _, item in ipairs(values) do
                    assert(names[item.value] and item.text == names[item.value] .. " (#" .. item.value .. ")"
                        and not item.disabled, "Classic positive Spell invented an option/label")
                    if item.value == selected then selectedText = item.text end
                end
                assert(selectedText and ModelValue(spell)[1] == selected and spell:GetValue() == selected
                    and spell:GetText() == selectedText and spell._msuf2Label:GetText() == selectedText,
                    "Classic positive Spell callback/model/native label drift")
                Add("native-classic-positive-spell", tag, M.auraBlacklistPreset, selected, count, NativeDetails(spell))
            end
            for _, suffix in ipairs({ ".add-preset-spell", ".add-preset-set" }) do
                local button = Find(baseId .. suffix)
                if button:IsEnabled() then
                    HistoryAction("blacklist" .. suffix, tag, function() NativeInput(button) end, Entries)
                else
                    local before = Encode(Entries(), ids)
                    NativeCase("blacklist-disabled" .. suffix, tag, function() NativeInput(button) end)
                    assert(Encode(Entries(), ids) == before, "disabled native blacklist action changed profile")
                end
            end
            local search = Find(baseId .. ".search")
            local first = Entries()[1]
            assert(first, "native blacklist actions produced no list entries")
            for _, query in ipairs({ tostring(first.spellID or first.value), "no-such-blocked-spell", "" }) do
                NativeCase("blacklist-search", tag .. ":" .. query, function()
                    NativeInput(search, query) assert(search:GetText() == query and ModelValue(search)[1] == query, "native Search text owner drift")
                    ListCheck(query) Contents(tag .. ":search:" .. query)
                end)
            end
            if mode == "push" then
                local remove = Find(baseId .. ".entry." .. tostring(first.value):lower():gsub("[^%w_%-]+", "-") .. ".remove")
                HistoryAction("blacklist-remove", tag, function() NativeInput(remove) end, Entries)
                ListCheck("")
            else
                local function VisibleRows()
                    local entries, byValue, paint, inventory = Entries(), {}, {}, {}
                    for _, w in ipairs(mw.world.widgets.frames) do
                        local row, ownerScope, ownerLane, token
                        if Within(w, M.cache.gf_auras.wrapper) then
                            row, ownerScope, ownerLane, token = BlacklistOwner(w)
                        end
                        if row and ownerScope == scope and ownerLane == lane and EffectiveShown(w) then
                            local value = tostring(row._spellID)
                            assert(row._spellID ~= nil and w:IsEnabled() and not byValue[value],
                                "visible native blacklist Remove binding drift")
                            assert(token == value:lower():gsub("[^%w_%-]+", "-"), "native blacklist Remove target path drift")
                            byValue[value] = w
                        end
                    end
                    for _, item in ipairs(entries) do
                        local value = tostring(item.value)
                        local w = assert(byValue[value], "visible native blacklist entry has no Remove owner: " .. value)
                        local row = w:GetParent()
                        local name = tostring(item.text or item.value or "Spell"):gsub("%s*%(#%d+%)$", "")
                        assert(row.name:GetText() == name and row.id:GetText() == value
                            and EffectiveShown(row.name) and EffectiveShown(row.id), "visible native blacklist row text drift")
                        assert(row.icon:GetTexture() == (item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"),
                            "visible native blacklist row icon drift")
                        paint[#paint + 1] = { value, Text(row.name), Text(row.id), Paint(row.icon), row.icon:GetTexture(),
                            NativeDetails(w), Paint(w._msuf2Fill), Paint(w._msuf2Edge) }
                        inventory[#inventory + 1] = { value, w._msuf2RuntimeControlRecord.controlId }
                    end
                    local count = 0 for _ in pairs(byValue) do count = count + 1 end
                    assert(count == #entries, "visible native blacklist Remove census drift")
                    return byValue, paint, inventory
                end
                local expectedEntries, exercisedValues, expectedRows = F.CopySnapshot(Entries()), {}, {}
                local initialRows, _, initialInventory = VisibleRows()
                for value, w in pairs(initialRows) do expectedRows[value] = w end
                local ownerEntry, entryValues = M.cache.gf_auras, {}
                for _, item in ipairs(expectedEntries) do entryValues[tostring(item.value)] = true end
                local function RowsAfterLifecycle(phase)
                    local byValue, paint, inventory = VisibleRows()
                    local currentEntry = M.cache.gf_auras
                    if currentEntry ~= ownerEntry then
                        assert(phase == "undo" or phase == "redo" or phase == "restore",
                            "native blacklist wrapper changed outside history restore: " .. phase)
                        assert(M.PageRebuildsItself("gf_auras") and ownerEntry._msuf2Invalidated == true
                            and ownerEntry.wrapper ~= currentEntry.wrapper and not ownerEntry.wrapper:IsShown()
                            and ownerEntry.wrapper:GetParent() == nil and currentEntry._msuf2Invalidated ~= true
                            and currentEntry.wrapper:IsShown() and currentEntry.wrapper:GetParent() ~= nil,
                            "native blacklist wrapper replacement lacks real lifecycle retirement")
                        for _, widget in pairs(expectedRows) do
                            assert(Within(widget, ownerEntry.wrapper) and not EffectiveShown(widget),
                                "native blacklist retired physical owner is live or detached from its wrapper")
                        end
                        for value in pairs(byValue) do
                            assert(entryValues[value], "native blacklist rebuilt owner changed semantic entry")
                        end
                        Add("native-blacklist-owner-generation", tag, phase, inventory)
                        historyGenerations = historyGenerations + 1
                        -- Only physical owners follow a proven history rebuild; expected DB/model/paint never change.
                        expectedRows, ownerEntry = byValue, currentEntry
                    end
                    return byValue, paint, inventory
                end
                Add("native-blacklist-visible-census", tag, expectedEntries, initialInventory)
                for _, item in ipairs(expectedEntries) do
                    local value = tostring(item.value)
                    local beforeEntries, beforeDB = F.CopySnapshot(Entries()), F.CopySnapshot(env.MSUF_DB)
                    local currentRows, beforePaint = RowsAfterLifecycle("before-input")
                    local remove = assert(currentRows[value], "native blacklist target disappeared: " .. value)
                    assert(remove == expectedRows[value] and EffectiveShown(remove), "native blacklist current visible owner changed")
                    local clickedId = remove._msuf2RuntimeControlRecord.controlId
                    local afterEntries, afterPaint = {}, {}
                    for _, entry in ipairs(beforeEntries) do if tostring(entry.value) ~= value then afterEntries[#afterEntries + 1] = entry end end
                    for _, painted in ipairs(beforePaint) do if painted[1] ~= value then afterPaint[#afterPaint + 1] = painted end end
                    -- Expected snapshot only: the live profile is changed exclusively by the native callback/history.
                    local afterDB = F.CopySnapshot(beforeDB)
                    local kinds = scope == "party" and { "party" } or { "raid", "mythicraid" }
                    for _, kind in ipairs(kinds) do
                        local config = assert(afterDB["gf_" .. kind])
                        local blacklist = assert(config.auras[lane].blacklist)
                        assert(blacklist.spells[value] == true, "native blacklist target absent from raw profile")
                        blacklist.spells[value] = nil
                        if blacklist.rankFamilySpellIDs then blacklist.rankFamilySpellIDs[value] = nil end
                        config.auras.renderer = "CUSTOM"
                    end
                    local function CheckState(db, entries, painted, phase)
                        assert(not next(Diff(db, env.MSUF_DB)), "native blacklist exact raw DB drift: " .. value .. ":" .. phase)
                        assert(Encode(Entries(), ids) == Encode(entries, ids), "native blacklist exact model drift: " .. value .. ":" .. phase)
                        ListCheck("")
                        local _, actualPaint, inventory = RowsAfterLifecycle(phase)
                        assert(Encode(actualPaint, ids) == Encode(painted, ids), "native blacklist exact visible paint drift: " .. value .. ":" .. phase)
                        Add("native-blacklist-state", tag, value, phase, inventory, actualPaint)
                    end
                    M.ClearHistory()
                    Refusal("blacklist-remove", tag .. ":" .. value, function()
                        assert(EffectiveShown(remove) and tostring(remove:GetParent()._spellID) == value,
                            "native blacklist refused input lost its visible target")
                        NativeInput(remove)
                        CheckState(beforeDB, beforeEntries, beforePaint, "refused")
                    end)
                    local undo = M.Undo() mw:RunTimers()
                    local redo = M.Redo() mw:RunTimers()
                    assert(not undo and not redo, "native blacklist refused input entered history")
                    CheckState(beforeDB, beforeEntries, beforePaint, "after-refusal")
                    HistoryAction("blacklist-remove", tag .. ":" .. value, function()
                        assert(EffectiveShown(remove) and tostring(remove:GetParent()._spellID) == value,
                            "native blacklist input lost its visible target")
                        NativeInput(remove)
                        assert(nativeScopeSeen[scopeKey .. ":" .. clickedId], "native blacklist clicked ID was not exercised")
                    end, Entries, function() CheckState(afterDB, afterEntries, afterPaint, "input") end,
                    function(phase)
                        if phase == "undo" then CheckState(beforeDB, beforeEntries, beforePaint, phase)
                        else CheckState(afterDB, afterEntries, afterPaint, phase) end
                    end)
                    local restored = M.Undo() mw:RunTimers() FinishNativeTransitions()
                    assert(restored, "native blacklist restoration Undo failed")
                    CheckState(beforeDB, beforeEntries, beforePaint, "restore")
                    exercisedValues[value] = clickedId
                    M.ClearHistory()
                end
                for _, item in ipairs(expectedEntries) do
                    assert(exercisedValues[tostring(item.value)], "visible native blacklist Remove input census missing")
                end
                local exercisedCount = 0 for _ in pairs(exercisedValues) do exercisedCount = exercisedCount + 1 end
                assert(exercisedCount == #expectedEntries, "visible native blacklist Remove input census drift")
                Add("native-blacklist-exercised-census", tag, exercisedValues)
                if width == 400 and scope == "party" and lane == "buff" and not historyGenerationCase then
                    -- Capture this exact view's setup and real preset entry, never the final loop's context.
                    local targetValue = tostring(expectedEntries[1].value)
                    historyGenerationCase = function()
                        local generationTag = "party/buff/blacklist/400:bounded-active-rebuild"
                        assert(forcedWidth == 400 and scope == "party" and lane == "buff" and tool == "blacklist",
                            "bounded history generation captured the wrong view")
                        -- Match the regular cross-scope fixture: enable the target, then use native selector cycles.
                        setup("default")
                        assert(GP.Conf(scope).enabled == true, "bounded native context target scope was not enabled by its captured setup")
                        SelectView(scope, lane, tool, true) setup("default")
                        assert(M.activeKey == "gf_auras" and GP.CurrentScope() == scope
                            and M.gfAuraLaneSelection[scope] == lane and M.gfAuraToolSelection[scope][lane] == tool
                            and M.cache.gf_auras.layoutSlot == M.CurrentPageLayoutSlot("gf_auras"),
                            "bounded native context did not select its actual current variant")
                        local container = Find("menu2.gf_auras.auras.group-workspace.container-selector")
                        local toolbar = Find("menu2.gf_auras.auras.group-workspace.lane.buff.tool-selector")
                        assert(EffectiveShown(container) and container:IsEnabled() and container:GetValue() == lane
                            and EffectiveShown(toolbar) and toolbar:IsEnabled() and toolbar:GetValue() == tool,
                            "bounded native context selectors are stale, hidden or disabled")
                        Add("native-bounded-generation-context", generationTag, GP.CurrentScope(), M.gfAuraLaneSelection[scope],
                            M.gfAuraToolSelection[scope][lane], M.cache.gf_auras.layoutSlot, NativeDetails(container), NativeDetails(toolbar))
                        local manual = Find(prefix .. "lane.buff.blacklist.manual-input")
                        local present = false
                        for _, item in ipairs(Entries()) do if tostring(item.value) == targetValue then present = true end end
                        if not present then
                            NativeCase("blacklist-generation-seed", generationTag, function()
                                NativeInput(manual, targetValue)
                                local add = Find(baseId .. ".add")
                                assert(EffectiveShown(add) and add:IsEnabled(), "bounded history native Add unavailable")
                                NativeInput(add)
                            end)
                        end
                        NativeInput(manual, "")
                        assert(M.activeKey == "gf_auras" and not M.PageRebuildsItself("gf_auras"),
                            "bounded active rebuild started from an already sticky or inactive page")
                        local retired = M.cache.gf_auras
                        M.InvalidatePage("gf_auras") mw:RunTimers()
                        assert(M.PageRebuildsItself("gf_auras") and M.cache.gf_auras == nil and retired._msuf2Invalidated == true
                            and not retired.wrapper:IsShown() and retired.wrapper:GetParent() == nil,
                            "bounded active invalidation did not mark and retire its actual page")
                        assert(mw:Select("gf_auras") ~= false) OpenSections()
                        assert(M.cache.gf_auras ~= retired and M.cache.gf_auras.sections.auras._msuf2Width == 400
                            and M.cache.gf_auras.sections.auras:GetWidth() == 400, "bounded active rebuild is not a fresh 400px page")
                        local beforeEntries, beforeDB = F.CopySnapshot(Entries()), F.CopySnapshot(env.MSUF_DB)
                        local beforePaint
                        expectedRows, beforePaint = VisibleRows()
                        ownerEntry, entryValues = M.cache.gf_auras, {}
                        for _, item in ipairs(beforeEntries) do entryValues[tostring(item.value)] = true end
                        local remove = assert(expectedRows[targetValue], "bounded history case has no genuine visible Remove target")
                        assert(EffectiveShown(remove) and remove:IsEnabled() and tostring(remove:GetParent()._spellID) == targetValue,
                            "bounded history Remove target binding drift")
                        local clickedId = remove._msuf2RuntimeControlRecord.controlId
                        local afterEntries, afterPaint, afterDB = {}, {}, F.CopySnapshot(beforeDB)
                        for _, item in ipairs(beforeEntries) do if tostring(item.value) ~= targetValue then afterEntries[#afterEntries + 1] = item end end
                        for _, item in ipairs(beforePaint) do if item[1] ~= targetValue then afterPaint[#afterPaint + 1] = item end end
                        local config = assert(afterDB.gf_party)
                        local blocked = assert(config.auras.buff.blacklist)
                        assert(blocked.spells[targetValue] == true, "bounded history target absent from raw profile")
                        blocked.spells[targetValue] = nil
                        if blocked.rankFamilySpellIDs then blocked.rankFamilySpellIDs[targetValue] = nil end
                        config.auras.renderer = "CUSTOM"
                        local function Check(db, entries, painted, phase)
                            assert(not next(Diff(db, env.MSUF_DB)) and Encode(Entries(), ids) == Encode(entries, ids),
                                "bounded history exact DB/model drift: " .. phase)
                            ListCheck("")
                            local _, actualPaint, inventory = RowsAfterLifecycle(phase)
                            assert(Encode(actualPaint, ids) == Encode(painted, ids), "bounded history exact native paint drift: " .. phase)
                            Add("native-bounded-generation-state", generationTag, targetValue, phase, inventory, actualPaint)
                        end
                        local generationsBefore = historyGenerations
                        M.ClearHistory()
                        Refusal("blacklist-generation-remove", generationTag, function()
                            assert(EffectiveShown(remove) and tostring(remove:GetParent()._spellID) == targetValue,
                                "bounded refused Remove lost its actual target")
                            NativeInput(remove) Check(beforeDB, beforeEntries, beforePaint, "refused")
                        end)
                        local undo = M.Undo() mw:RunTimers()
                        local redo = M.Redo() mw:RunTimers()
                        assert(not undo and not redo, "bounded refused Remove entered history")
                        Check(beforeDB, beforeEntries, beforePaint, "after-refusal")
                        HistoryAction("blacklist-generation-remove", generationTag, function()
                            assert(EffectiveShown(remove) and tostring(remove:GetParent()._spellID) == targetValue,
                                "bounded native Remove lost its actual target")
                            NativeInput(remove)
                            assert(nativeScopeSeen[scopeKey .. ":" .. clickedId], "bounded native Remove clicked ID missing")
                        end, Entries, function() Check(afterDB, afterEntries, afterPaint, "input") end,
                        function(phase)
                            if phase == "undo" then Check(beforeDB, beforeEntries, beforePaint, phase)
                            else Check(afterDB, afterEntries, afterPaint, phase) end
                        end)
                        local restored = M.Undo() mw:RunTimers() FinishNativeTransitions()
                        assert(restored, "bounded native Remove restore failed")
                        Check(beforeDB, beforeEntries, beforePaint, "restore")
                        assert(historyGenerations == generationsBefore + 3, "bounded Undo/Redo/restore did not each replace the native owner generation")
                        Add("native-bounded-active-generation", generationTag, targetValue, clickedId, historyGenerations - generationsBefore)
                        M.ClearHistory()
                    end
                end
            end
            ReturnView()
        end
        if mode ~= "push" then
            -- Remaining native preview/chrome owners have their own callbacks;
            -- do not turn their menu actions into profile setting commands.
            for _, w in ipairs(AllOwners(tag .. ":post-actions")) do
                local record = w._msuf2RuntimeControlRecord
                local parent = w:GetParent()
                local disclosure = parent and parent._msuf2CollapsibleEntry
                local poolRow = BlacklistOwner(w)
                if poolRow and poolRow._spellID == nil then
                    assert(not poolRow:IsShown() and not EffectiveShown(w), "retired native blacklist Remove owner is visible")
                    Add("native-retired-blacklist-owner", tag, ids[w], poolRow:IsShown(), EffectiveShown(w), poolRow._spellID)
                elseif record.classification ~= "setting" and not nativeScopeSeen[scopeKey .. ":" .. ids[w]] then
                    if not w:IsShown() or not w:IsEnabled() then
                        local before = F.CopySnapshot(env.MSUF_DB)
                        NativeCase("unavailable-native-owner", tag .. ":" .. ids[w], function() NativeInput(w) end)
                        assert(not next(Diff(before, env.MSUF_DB)), "unavailable native owner changed profile")
                    elseif disclosure and disclosure.header == w then
                        -- Later Style views build real nested headers after the scope's first root-header pass.
                        assert(disclosure.outer == parent and disclosure.body._msuf2CollapsibleEntry == disclosure
                            and disclosure.pageKey == "gf_auras" and w:GetObjectType() == "Button"
                            and record.kind == "toggle" and record.classification == "ephemeral",
                            "native disclosure owner metadata drift: " .. ids[w])
                        assert(EffectiveShown(w), "native disclosure header not effectively visible: " .. tag .. ":" .. ids[w])
                        local live = M.RuntimeControlCatalog.Get(record.controlId)
                        assert(live == record and live.widget == w and w._msuf2RuntimeControlId == record.controlId,
                            "native disclosure catalog owner drift: " .. ids[w])
                        local token = tostring(disclosure.sectionId):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", "")
                        if token == "" then token = "section" end
                        local meta, inputId = assert(w._msuf2SearchMeta), record.controlId
                        assert(meta.controlId == "menu2.gf_auras.section." .. token .. ".expanded"
                            and record.controlPath == "gf_auras/section/" .. token:gsub("%.", "/") .. "/expanded"
                            and disclosure.stateKey == "gf_auras:" .. disclosure.sectionId,
                            "native disclosure source identity drift: " .. inputId)
                        local command = assert(meta.command, "native disclosure source command missing")
                        assert(command.historyMode == "none" and type(command.get) == "function" and w:GetScript("OnClick"),
                            "native disclosure native Click owner missing: " .. inputId)
                        local before, wasOpen = F.CopySnapshot(env.MSUF_DB), disclosure.open
                        M.ClearHistory()
                        for _ = 1, 2 do
                            local wanted = not disclosure.open
                            NativeCase("header", tag .. ":" .. inputId, function()
                                assert(EffectiveShown(w) and w:IsEnabled(), "native disclosure input is unavailable: " .. inputId)
                                w:Click("LeftButton")
                                for _ = 1, 120 do
                                    local driver = disclosure._msuf2AccordionMotion
                                    if not (driver and driver:GetScript("OnUpdate")) then break end
                                    MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
                                end
                                mw:RunTimers()
                                assert(not disclosure._msuf2MotionActive and disclosure.open == wanted and command.get() == wanted
                                    and disclosure.body:IsShown() == wanted and EffectiveShown(disclosure.body) == wanted
                                    and disclosure.body:GetAlpha() == 1, "native disclosure Click/display drift: " .. inputId)
                                assert(M.GetPersistentMenuStateTable("accordionState")[disclosure.stateKey] == wanted
                                    and not next(Diff(before, env.MSUF_DB)), "native disclosure persistent/profile drift: " .. inputId)
                                Add("native-nested-header-display", inputId, NativeDetails(w), EffectiveShown(w),
                                    EffectiveShown(disclosure.body), disclosure.body:GetHeight(), disclosure.outer:GetHeight())
                            end)
                            nativeSeen[inputId] = true
                            nativeScopeSeen[scopeKey .. ":" .. inputId] = true
                        end
                        assert(disclosure.open == wasOpen and not next(Diff(before, env.MSUF_DB)),
                            "native disclosure balanced profile/state drift: " .. inputId)
                        assert(not M.Undo() and not M.Redo(), "native disclosure entered profile history: " .. inputId)
                    elseif ids[w]:find(".preview.", 1, true) then
                        local command = w._msuf2CommandAction or record.command
                        local before = command and command.get and command.get()
                        local value = record.kind == "slider" and w:GetObjectType() == "Slider" and select(2, w:GetMinMaxValues()) or nil
                        NativeCase("preview-owner", tag .. ":" .. ids[w], function()
                            NativeInput(w, value)
                            if command and command.get and type(before) == "boolean" and w._layerAvailable ~= false then
                                assert(command.get() ~= before, "native preview toggle callback drift: " .. ids[w])
                            end
                        end)
                        ReturnView()
                    elseif record.kind == "button" and w._msuf2ContextColorOptions then
                        NativeCase("context-color-owner", tag .. ":" .. ids[w], function()
                            NativeInput(w)
                            local picker
                            for _, item in ipairs(mw.world.widgets.frames) do if item.compactHex and item.owner and item:IsShown() then picker = item end end
                            assert(picker, "native contextual color owner did not open picker: " .. ids[w])
                            NativeInput(picker.cancel)
                        end)
                    else error("unexercised ordinary native owner: " .. ids[w] .. ":" .. tostring(record.kind)) end
                end
            end
        end
        Contents(tag .. ":native-complete")
    end
    local function NavigateGroupPage(pageKey, tag)
        local previousKey = M.activeKey
        local previous = assert(M.cache[previousKey])
        local function Selector(key)
            local entry = assert(M.cache[key])
            local record = assert(M.RuntimeControlCatalog.Get("menu2." .. key .. ".group.navigation.section.selector"))
            local widget, owner = assert(record.widget), record.widget
            while owner and owner ~= entry.wrapper and owner._msuf2PageOwnerWrapper ~= entry.wrapper do owner = owner:GetParent() end
            assert(owner and record.pageKey == key and record.kind == "segment" and widget._msuf2RuntimeControlRecord == record
                and EffectiveShown(widget) and widget:IsEnabled() and entry.wrapper:IsShown(), "native rebuild navigation owner drift: " .. key)
            return widget
        end
        local selector, choice = Selector(previousKey)
        for _, button in ipairs(selector.buttons) do if button._msuf2Value == pageKey then choice = button break end end
        assert(choice and choice:GetScript("OnClick") and EffectiveShown(choice) and choice:IsEnabled(), "native rebuild page choice unavailable")
        local before = F.CopySnapshot(env.MSUF_DB)
        NativeCase("page-navigation", tag, function()
            choice:Click("LeftButton") mw:RunTimers() FinishNativeTransitions()
            assert(M.activeKey == pageKey and not previous.wrapper:IsShown(), "native rebuild page departure drift")
            local target = Selector(pageKey)
            assert(target:GetValue() == pageKey, "native rebuild destination selector drift")
            for _, button in ipairs(target.buttons) do
                assert(button._msuf2Active == (button._msuf2Value == pageKey), "native rebuild destination selector paint drift")
            end
            assert(not next(Diff(before, env.MSUF_DB)), "native rebuild page navigation changed profile")
            Add("native-rebuild-navigation-display", tag, previousKey, pageKey, NativeDetails(target), EffectiveShown(target))
        end)
    end
    local priorEntries = {}
    for _, width in ipairs({ 720, 400 }) do
        forcedWidth = width
        if width == 400 then
            assert(M.activeKey == "gf_auras" and not M.PageRebuildsItself("gf_auras"), "400px rebuild started from sticky or inactive Aura page")
            local retired = assert(M.cache.gf_auras)
            NavigateGroupPage("gf_layout", "400px-inactive-rebuild:away")
            assert(M.activeKey == "gf_layout" and not retired.wrapper:IsShown(), "Aura page is not genuinely inactive before invalidation")
            M.InvalidatePage("gf_auras") mw:RunTimers()
            assert(M.activeKey == "gf_layout" and M.cache.gf_auras == nil and not M.PageRebuildsItself("gf_auras"),
                "inactive Aura invalidation changed active page or marked permanent rebuild")
            local retiredCount = 0
            for _, entry in pairs(priorEntries) do
                assert(entry._msuf2Invalidated == true and not entry.wrapper:IsShown() and entry.wrapper:GetParent() == nil,
                    "inactive 400px invalidation retained a cached Aura wrapper")
                retiredCount = retiredCount + 1
            end
            NavigateGroupPage("gf_auras", "400px-inactive-rebuild:return")
            local fresh = assert(M.cache.gf_auras)
            assert(fresh ~= retired and fresh.wrapper ~= retired.wrapper and fresh._msuf2Invalidated ~= true
                and fresh.wrapper:IsShown() and fresh.wrapper:GetParent() ~= nil and not M.PageRebuildsItself("gf_auras")
                and fresh.sections.auras._msuf2Width == 400 and fresh.sections.auras:GetWidth() == 400,
                "inactive return did not build a fresh nonsticky 400px Aura page")
            Add("native-400px-inactive-rebuild", retiredCount, fresh.sections.auras:GetWidth(), M.PageRebuildsItself("gf_auras"))
        end
        local exercisedIds = {}
        for _, scope in ipairs(scopes) do for _, lane in ipairs(lanes) do
            local tools = lane == "externals" and { "layout", "behavior", "style" }
                or { "layout", "behavior", "filters", "blacklist", "style" }
            if mode == "push" then tools = { "layout" } end
            for _, tool in ipairs(tools) do
                Restore(env.MSUF_DB, factory)
                GP.Conf(scope).enabled = true
                SelectView(scope, lane, tool, lane == "buff" and tool == "layout")
                local accordion = M.GetPersistentMenuStateTable("accordionState")
                accordion["gf_auras:auras"], accordion["gf_auras:si"], accordion["gf_auras:si_style"] = true, true, true
                assert(mw:Select("gf_auras") ~= false) mw:RunTimers()
                local entry = assert(M.cache.gf_auras)
                local view = scope .. "/" .. lane .. "/" .. tool .. "/" .. width
                local viewKey = scope .. "/" .. lane .. "/" .. tool
                if width == 400 then assert(priorEntries[viewKey] ~= entry, "400px page was not rebuilt: " .. view) end
                if width == 400 then
                    assert(not M.PageRebuildsItself("gf_auras") and entry.sections.auras._msuf2Width == 400
                        and entry.sections.auras:GetWidth() == 400, "400px view is sticky or built at the wrong native width: " .. view)
                end
                priorEntries[viewKey] = entry
                -- Style, Spell Indicators and Spell Icon Style are lazy siblings.
                -- Open every actual section instead of observing Layout alone.
                for pass = 1, 3 do
                    local names = {} for name in pairs(entry.sections) do names[#names + 1] = name end table.sort(names)
                    for _, name in ipairs(names) do
                        local section = entry.sections[name]
                        M.Widgets.EnsureSectionContent(section)
                        if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
                        ids[section] = view .. "/section/" .. name
                    end
                end
                mw:RunTimers()
                local section = assert(entry.sections.auras, "aura accordion missing")
                if not original then
                    assert(section._msuf2CollapsibleEntry.header._msuf2ControlSchema, "section owner declaration missing")
                end
                local controls, custom, layoutCount, spellCount, seen = {}, {}, 0, 0, {}
                for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
                    local w = M.RuntimeControlCatalog.Get(record.controlId).widget
                    local aura = record.controlId:match("^menu2%.gf_auras%.auras%.")
                    local spell = record.controlId:match("^menu2%.gf_auras%.group%.spell%.")
                    local typed = record.kind == "toggle" or record.kind == "slider" or record.kind == "dropdown" or record.kind == "textinput"
                    if record.pageKey == "gf_auras" and (aura or spell) and w then
                        ids[w] = record.controlId
                        if typed and record.classification == "setting" then
                            assert(Command(w) and Command(w).get and Command(w).set, "ordinary command missing: " .. record.controlId)
                            assert(not seen[record.controlId], "duplicate ordinary identity: " .. record.controlId)
                            seen[record.controlId] = true controls[#controls + 1] = w
                            if spell then spellCount = spellCount + 1 end
                            local localRow = record.controlId:find(".auras.group-workspace.", 1, true)
                                and (tool == "layout" or record.controlId:match("%.root%.enabled$"))
                            if localRow then layoutCount = layoutCount + 1 end
                            if not original and localRow then
                                local spec = assert(w._msuf2ControlSchema, "ordinary declaration missing: " .. record.controlId)
                                assert(spec.id == record.controlId and spec.kind == record.kind
                                    and spec.scope == "groups" and spec.applyDomain == "auras", "typed declaration drift: " .. record.controlId)
                                assert(spec.get and spec.set and spec.defaultSource, "declaration has no live accessors: " .. record.controlId)
                                if record.kind == "slider" then assert(spec.range and spec.range[3] == 1, "slider declaration range missing") end
                            end
                            -- Unchanged Auras_Group remains a legacy typed-binding
                            -- seam at this exact commit; spell rows already declare.
                            if not original and w._msuf2ControlSchema then declarations = declarations + 1 end
                        elseif record.classification == "action" or record.classification == "ephemeral"
                            or record.classification == "navigation" then
                            custom[#custom + 1] = record
                        end
                    end
                end
                table.sort(controls, function(a, b) return ids[a] < ids[b] end)
                assert(spellCount == 46, view .. ": spell ordinary inventory drift: " .. spellCount)
                if tool == "layout" then
                    local count = lane == "externals" and 11 or 10
                    assert(layoutCount == count, view .. ": actual ordinary inventory drift: " .. layoutCount)
                else assert(layoutCount == 1, view .. ": root enable input missing") end
                local expected = tool == "layout" and (lane == "externals" and 11 or 10)
                    or tool == "behavior" and 3 or tool == "blacklist" and 1
                    or tool == "style" and (lane == "debuff" and 23 or 22)
                    or (M.CLASSIC_AURA_FILTERS_REDUCED == true and (lane == "debuff" and 4 or 3) or (lane == "debuff" and 11 or 13))
                assert(#controls == expected + spellCount, view .. ": complete ordinary inventory drift: " .. #controls)
                if tool == "blacklist" then assert(#custom > 3, view .. ": custom blacklist seam missing") end
                Add(view .. ":inventory", #controls, layoutCount, spellCount, custom)
                total, seams = total + #controls, seams + #custom
                local function DisplaySnapshot()
                    local values = {}
                    for _, w in ipairs(controls) do values[#values + 1] = { ids[w], DisplayValue(w), w:IsShown(), w:IsEnabled(), NativeDetails(w) } end
                    return values
                end
                local function AssertDisplay(expectedValues, tag)
                    assert(Encode(expectedValues, ids) == Encode(DisplaySnapshot(), ids), "displayed history drift: " .. view .. ":" .. tag)
                end
                if flavor == "TBC" and mode ~= "push" then
                    local StrictAssertDisplay = AssertDisplay
                    local function DescribeDisplayRow(row)
                        if not row then return "<missing row>" end
                        return "id=" .. tostring(row[1]) .. " displayed=" .. Encode(row[2], ids)
                            .. " shown=" .. tostring(row[3]) .. " enabled=" .. tostring(row[4])
                    end
                    AssertDisplay = function(expectedValues, tag)
                        local actualValues = DisplaySnapshot()
                        if Encode(expectedValues, ids) ~= Encode(actualValues, ids) then
                            print("GROUP_AURA_DISPLAY_DIFF_BEGIN " .. flavor .. ":" .. view .. ":" .. tag)
                            local changed = 0
                            for i = 1, math.max(#expectedValues, #actualValues) do
                                if Encode(expectedValues[i], ids) ~= Encode(actualValues[i], ids) then
                                    changed = changed + 1
                                    print("GROUP_AURA_DISPLAY_DIFF row=" .. i .. " expected " .. DescribeDisplayRow(expectedValues[i])
                                        .. " actual " .. DescribeDisplayRow(actualValues[i]))
                                end
                            end
                            print("GROUP_AURA_DISPLAY_DIFF_END changed=" .. changed)
                        end
                        return StrictAssertDisplay(expectedValues, tag)
                    end
                end
                if flavor == "Mists" and mode ~= "push" then
                    local StrictAssertDisplay = AssertDisplay
                    local maxId = "menu2.gf_auras.auras.group-workspace.lane.externals.layout.max"
                    local function DescribeDisplayRow(row)
                        if not row then return "<missing row>" end
                        return "id=" .. tostring(row[1]) .. " displayed=" .. Encode(row[2], ids)
                            .. " shown=" .. tostring(row[3]) .. " enabled=" .. tostring(row[4])
                    end
                    AssertDisplay = function(expectedValues, tag)
                        if tag:sub(-#maxId) == maxId then
                            local actualValues = DisplaySnapshot()
                            if Encode(expectedValues, ids) ~= Encode(actualValues, ids) then
                                print("GROUP_AURA_DISPLAY_DIFF_BEGIN " .. flavor .. ":" .. view .. ":" .. tag)
                                local changed = 0
                                for i = 1, math.max(#expectedValues, #actualValues) do
                                    local expected, actual = expectedValues[i], actualValues[i]
                                    if Encode(expected, ids) ~= Encode(actual, ids) then
                                        changed = changed + 1
                                        print("GROUP_AURA_DISPLAY_DIFF row=" .. i .. " expected " .. DescribeDisplayRow(expected)
                                            .. " actual " .. DescribeDisplayRow(actual))
                                    end
                                    local row = expected or actual
                                    if row and row[1] == "menu2.gf_auras.group.spell.selected.auto_blacklist" then
                                        print("GROUP_AURA_DISPLAY_COMPANION expected " .. DescribeDisplayRow(expected)
                                            .. " actual " .. DescribeDisplayRow(actual))
                                    end
                                end
                                print("GROUP_AURA_DISPLAY_DIFF_END changed=" .. changed)
                            end
                        end
                        return StrictAssertDisplay(expectedValues, tag)
                    end
                end
                local function AssertSpellDisplay(w, tag)
                    local model, actual = ModelValue(w), DisplayValue(w)
                    local kind, expected = w._msuf2RuntimeControlRecord.kind, model
                    -- These are the native binder's conversions, not DB defaults.
                    if kind == "toggle" then expected = Pack(model[1] and true or false)
                    elseif kind == "textinput" then expected = Pack(tostring(model[1] or ""))
                    elseif kind == "slider" then expected = Pack(tonumber(model[1]) or 0) end
                    assert(Encode(expected, ids) == Encode(actual, ids), "spell displayed/model drift: " .. view .. ":" .. tag .. ":" .. ids[w]
                        .. ":model=" .. Encode(model, ids) .. ":expected=" .. Encode(expected, ids) .. ":actual=" .. Encode(actual, ids))
                end
                local function AssertSpellDisplays(tag)
                    for _, w in ipairs(controls) do
                        if ids[w]:find(".group.spell.", 1, true) then AssertSpellDisplay(w, tag) end
                    end
                end
                local function Input(w, value)
                    if not w:IsEnabled() then return end
                    local kind = w._msuf2RuntimeControlRecord.kind
                    if kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
                    elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
                    elseif kind == "textinput" then w:SetText(value) MenuWorld.FireScript(w, "OnTextChanged", true) MenuWorld.FireScript(w, "OnEnterPressed")
                    else w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value) end
                    mw:RunTimers()
                end
                local function Alternate(w)
                    local kind, current = w._msuf2RuntimeControlRecord.kind, ModelValue(w)[1]
                    if kind == "toggle" then return not current end
                    if kind == "textinput" then return current == "17" and "139" or "17" end
                    if kind == "slider" then local lo, hi = w:GetMinMaxValues() return current ~= lo and lo or hi end
                    local values = w.values if type(values) == "function" then values = values() end
                    for _, item in ipairs(values) do if item.value ~= nil and item.value ~= current and not item.disabled then return item.value end end
                    error("dropdown has no alternate: " .. ids[w])
                end
                local defaults = F.CopySnapshot(env.MSUF_DB)
                local function Setup(state, w)
                    Restore(env.MSUF_DB, defaults)
                    GP.Conf(scope).enabled = true
                    local config = GP.AurasRoot(scope, true) config.enabled = true
                    local group = GP.AuraGroup(scope, lane) group.enabled = true
                    group.unknownSchemaExtension = { enabled = false, amount = 0 }
                    if state == "edge" then
                        group.max, group.iconScale, group.layer, group.autoBlacklistBuffs = 0, 0, 0, false
                        group.anchor, group.growth, group.spacing = nil, "DOWN", nil
                    end
                    if w and ids[w]:find(".filters.native.", 1, true) then
                        -- An active All choice cannot be unchecked to no filter.
                        -- Start every native choice on another real supported choice.
                        local token = ids[w]:match("%.native%.all$") and "Player" or "ALL"
                        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
                            GP.AuraGroup(kind, lane).filterToken = token
                        end
                    end
                    if w and ids[w]:find(".group.spell.", 1, true) then PrepareSpell(scope, w) end
                    M.Refresh() mw:RunTimers() M.ClearHistory()
                end
                local function Observe(tag)
                    for _, w in ipairs(controls) do
                        local points = {} for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
                        Add(view .. ":" .. tag .. ":" .. ids[w], w._msuf2RuntimeControlRecord, w._msuf2SearchMeta,
                            ModelValue(w), DisplayValue(w), w.width, w.height, points, w:IsShown(), w:IsEnabled(), NativeDetails(w))
                    end
                end
                Observe("factory")
                for _, state in ipairs({ "default", "edge" }) do
                    Setup(state) Observe(state)
                    for _, w in ipairs(width == 400 and {} or controls) do
                        local isSpell = ids[w]:find(".group.spell.", 1, true)
                        local run = not isSpell or (mode ~= "push" and not exercisedIds[scope .. ":" .. ids[w]])
                        if run then
                            Setup(state, w)
                            local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
                            local beforeDisplay, priorEnabled = DisplaySnapshot(), w:IsEnabled()
                            calls = {} Input(w, value)
                            local after, afterDisplay = F.CopySnapshot(env.MSUF_DB), DisplaySnapshot()
                            if priorEnabled then
                                assert(next(Diff(before, after)), "enabled input did not change profile: " .. view .. ":" .. ids[w])
                            else assert(not next(Diff(before, after)), "disabled input changed profile: " .. view .. ":" .. ids[w]) end
                            Add(view .. ":" .. state .. ":input:" .. ids[w], value, Diff(before, after), ModelValue(w), DisplayValue(w), calls)
                            local externalCompanion
                            if (flavor == "TBC" or flavor == "Mists") and mode ~= "push"
                                and ids[w] == "menu2.gf_auras.auras.group-workspace.lane.externals.layout.max" then
                                for _, control in ipairs(controls) do
                                    if ids[control] == "menu2.gf_auras.group.spell.selected.auto_blacklist" then externalCompanion = control end
                                end
                                assert(externalCompanion, "external Max spell companion missing")
                            end
                            if isSpell then
                                Add(view .. ":" .. state .. ":input-display:" .. ids[w], afterDisplay)
                                AssertSpellDisplay(w, state .. ":input")
                                M.Refresh() mw:RunTimers()
                                -- Input refreshes its own section; sibling style gates
                                -- become canonical only when the whole page refreshes.
                                AssertSpellDisplays(state .. ":refresh:" .. ids[w])
                                Add(view .. ":" .. state .. ":refresh-model-effects:" .. ids[w], Diff(after, env.MSUF_DB))
                                after, afterDisplay = F.CopySnapshot(env.MSUF_DB), DisplaySnapshot()
                            elseif externalCompanion then
                                Add(view .. ":" .. state .. ":input-display:" .. ids[w], afterDisplay)
                                local canonicalDisplay, matched = {}, 0
                                local companionModel = ModelValue(externalCompanion)
                                assert(externalCompanion._msuf2RuntimeControlRecord.kind == "toggle", "external Max companion kind drift")
                                -- Max changes the external auto-blacklist predicate;
                                -- only its sibling checkbox waits for page refresh.
                                -- NativeDetails retains opaque native fields; a profile-value copier can reject them.
                                -- Copy records without altering the authentic immediate snapshot or any other field.
                                for i, row in ipairs(afterDisplay) do
                                    local expectedRow = {}
                                    for key, field in pairs(row) do expectedRow[key] = field end
                                    canonicalDisplay[i] = expectedRow
                                    if row[1] == ids[externalCompanion] then
                                        expectedRow[2], matched = Pack(companionModel[1] and true or false), matched + 1
                                    end
                                end
                                assert(matched == 1, "external Max companion snapshot identity drift")
                                Add(view .. ":" .. state .. ":companion-model:" .. ids[w], ids[externalCompanion], companionModel)
                                M.Refresh() mw:RunTimers() AssertDisplay(canonicalDisplay, state .. ":refresh:" .. ids[w])
                                AssertSpellDisplay(externalCompanion, state .. ":refresh:" .. ids[w])
                                Add(view .. ":" .. state .. ":refresh-model-effects:" .. ids[w], Diff(after, env.MSUF_DB))
                                after, afterDisplay = F.CopySnapshot(env.MSUF_DB), canonicalDisplay
                            else
                                M.Refresh() mw:RunTimers() AssertDisplay(afterDisplay, state .. ":refresh:" .. ids[w])
                            end
                            Add(view .. ":" .. state .. ":refresh:" .. ids[w], DisplaySnapshot())
                            local undo = M.Undo() mw:RunTimers()
                            Add(view .. ":" .. state .. ":undo:" .. ids[w], undo, Diff(before, env.MSUF_DB), ModelValue(w), DisplayValue(w))
                            AssertDisplay(beforeDisplay, state .. ":undo:" .. ids[w])
                            if isSpell then AssertSpellDisplays(state .. ":undo:" .. ids[w]) end
                            if externalCompanion then AssertSpellDisplay(externalCompanion, state .. ":undo:" .. ids[w]) end
                            local redo = M.Redo() mw:RunTimers()
                            Add(view .. ":" .. state .. ":redo:" .. ids[w], redo, Diff(after, env.MSUF_DB), ModelValue(w), DisplayValue(w))
                            AssertDisplay(afterDisplay, state .. ":redo:" .. ids[w])
                            if isSpell then AssertSpellDisplays(state .. ":redo:" .. ids[w]) end
                            if externalCompanion then AssertSpellDisplay(externalCompanion, state .. ":redo:" .. ids[w]) end
                            exercised = exercised + 1
                            if mode ~= "push" then
                                Setup(state, w) before = F.CopySnapshot(env.MSUF_DB) calls = {}
                                local combatDisplay = isSpell and DisplaySnapshot()
                                core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return false end
                                Input(w, value) Add(view .. ":" .. state .. ":combat-edge:" .. ids[w], Diff(before, env.MSUF_DB), calls)
                                env.InCombatLockdown = function() return true end Input(w, value)
                                Add(view .. ":" .. state .. ":combat:" .. ids[w], Diff(before, env.MSUF_DB), ModelValue(w), DisplayValue(w))
                                core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                                mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                                if isSpell then
                                    Add(view .. ":" .. state .. ":combat-display:" .. ids[w], DisplaySnapshot())
                                    M.Refresh() mw:RunTimers()
                                    AssertDisplay(combatDisplay, state .. ":combat-refresh:" .. ids[w])
                                    AssertSpellDisplays(state .. ":combat-refresh:" .. ids[w])
                                    Add(view .. ":" .. state .. ":combat-refresh:" .. ids[w], Diff(before, env.MSUF_DB), DisplaySnapshot())
                                end
                            end
                        end
                    end
                end
                for _, w in ipairs(controls) do
                    local isSpell = ids[w]:find(".group.spell.", 1, true)
                    local run = not isSpell or (mode ~= "push" and not exercisedIds[scope .. ":" .. ids[w]])
                    if run then
                        Setup("default", w)
                        local cleared = ClearOrdinary(w, scope, lane)
                        local absent = F.CopySnapshot(env.MSUF_DB)
                        M.Refresh() mw:RunTimers()
                        Add(view .. ":absent:" .. ids[w], cleared, ModelValue(w), DisplayValue(w), Diff(absent, env.MSUF_DB))
                        nilCases = nilCases + 1
                        -- The layout fallback is fixed UI data, separate from seeded defaults.
                        if lane == "buff" and ids[w]:match("%.layout%.size$") then
                            assert(ModelValue(w)[1] == 22 and DisplayValue(w)[1] == 22, "absent Buff size fallback drift")
                        end
                        if width ~= 400 and w._msuf2RuntimeControlRecord.kind == "slider" then
                            Setup("default", w) calls = {} local before = F.CopySnapshot(env.MSUF_DB)
                            w._msuf2SliderActive = true Input(w, Alternate(w))
                            Add(view .. ":drag:" .. ids[w], Diff(before, env.MSUF_DB), calls)
                            w._msuf2SliderActive = nil MenuWorld.FireScript(w, "OnMouseUp", "LeftButton") mw:RunTimers()
                            Add(view .. ":release:" .. ids[w], Diff(before, env.MSUF_DB), calls)
                            MenuWorld.FireScript(w, "OnHide") MenuWorld.FireScript(w, "OnShow") mw:RunTimers()
                            Add(view .. ":hide-show:" .. ids[w], calls)
                        end
                        exercisedIds[scope .. ":" .. ids[w]] = true
                    end
                end
                RunNativeOwners(scope, lane, tool, width, Setup)
                if width == 400 then assert(not M.PageRebuildsItself("gf_auras"), "ordinary 400px native actions marked the page self-rebuilding: " .. view) end
                Observe("reopen")
            end
        end end
    end
    if mode ~= "push" then
        assert(historyGenerationCase, "bounded native history generation case was not captured")
        historyGenerationCase()
    end
    Add("complete-inventory", total, exercised, nilCases, seams)
    if mode ~= "push" then
        for _, family in ipairs({ "scope", "container", "tool", "header", "page-navigation", "open-style", "copy-open",
            "copy-categories", "copy-category", "copy-target", "copy-close", "spell-aura-picker", "spell-multi-picker",
            "spell-preview-all", "spell-tile-select", "spell-tile-toggle", "spell-custom-add", "spell-custom-remove",
            "spell-color", "spell-color-cancel", "blacklist-manual", "blacklist-add", "blacklist-preset", "blacklist-spell",
            "blacklist-search", "blacklist-remove" }) do
            assert((nativeCounts[family] or 0) > 0, "native fixed-family case census missing: " .. family)
        end
    end
    Add("native-case-census", nativeCounts, nativeSeen, nativeScopes, nativeScopeSeen)
    if not original then print("Group Aura declarations observed: " .. declarations .. "; legacy Aura binder seam retained") end
    return rows, total
end
local started = os.clock()
local expected, oldCount = Replay(true)
if mode == "original" then print("Group Aura immutable parent passed: " .. oldCount .. " inputs") return end
local actual, count = Replay(false)
assert(#expected == #actual and count == oldCount, "Group Aura observation count drift")
for i = 1, #expected do if expected[i] ~= actual[i] then
    diffPath = os.tmpname()
    diff = assert(io.open(diffPath, "wb"))
    assert(diff:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n")) assert(diff:close()) diff = nil
    error("Group Aura parity drift at " .. i .. " " .. expected[i]:match("^[^\t]+"))
end end
print(string.format("menu_group_aura_schema_parity_smoke %s %s: %d ordinary controls across views/%d observations, all tools/ordinary+custom inventory/absent/display/400px/DB/apply/history/drag/release exact; full tier also covers combat (%.2fs)",
    mode, flavor, count, #actual, os.clock() - started))
end
local ok, problem = xpcall(Run, debug.traceback)
if io.type(file) == "file" then file:close() end
if io.type(diff) == "file" then diff:close() end
local removed, cleanupError = os.remove(scratch)
if diffPath then io.stderr:write("Group Aura " .. flavor .. " diff artifact: " .. diffPath .. "\n") end
if not ok then
    if not removed then io.stderr:write("Group Aura temporary parent cleanup failed: " .. tostring(cleanupError) .. "\n") end
    error(problem, 0)
end
assert(removed, "Group Aura temporary parent cleanup failed: " .. tostring(cleanupError))

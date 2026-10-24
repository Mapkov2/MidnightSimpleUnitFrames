-- One maintained real-menu replay against the immutable pre-migration page.
-- This checks offline bindings and layout data, not native rendering or taint.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua"
local parentBlob = "f7ad6aec94a6cc1beb79f6a7cf43c7c53de4ac81"
local mode = arg[4] or "full"
assert(mode == "full" or mode == "push" or mode == "narrow" or mode == "palette" or mode == "drag" or mode == "absent", "unknown parity tier")
local narrow = mode == "narrow"
local override = arg[3] ~= "-" and arg[3] or nil
local pipe = assert(io.popen('git -c safe.directory="' .. root .. '" -C "' .. root .. '" show ' .. parentBlob, "r"))
local original = pipe:read("*a")
assert(pipe:close(), "immutable parent read failed")
assert(original:find("function GP.BuildAbsorbBindings", 1, true), "immutable parent unavailable")
-- Each invocation owns a portable temporary parent; concurrent modes never share it.
local scratch, projectionPath = os.tmpname(), os.tmpname()
local file, diff, diffPath
local function Run()
file = assert(io.open(scratch, "wb"))
assert(file:write(original)) assert(file:close()) file = nil
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    if type(value) == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then
        return "widget:" .. tostring(ids[value] or value._msuf2SearchText or value:GetObjectType())
    end
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
-- Fixed stored fields and genuine owners; UI row aliases are not DB keys.
local ABSENT_FIELDS = {
    { { "general", "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid" }, {
        "enableGradient", "enablePowerGradient", "gradientStrength", "powerGradientStrength", "gradientDirection", "powerGradientDirection",
        "gradientDirRight", "gradientDirLeft", "gradientDirUp", "gradientDirDown",
        "powerGradientDirRight", "powerGradientDirLeft", "powerGradientDirUp", "powerGradientDirDown",
        "healthBarGradientColorR", "healthBarGradientColorG", "healthBarGradientColorB",
        "powerBarGradientColorR", "powerBarGradientColorG", "powerBarGradientColorB",
        "tempMaxHealthEnabled", "tempMaxHealthTexture", "tempMaxHealthOpacity", "tempMaxHealthBackgroundOpacity",
        "tempMaxHealthColorR", "tempMaxHealthColorG", "tempMaxHealthColorB", "enableAbsorbBar", "absorbTextMode",
        "absorbAnchorMode", "absorbBarHeight", "absorbBarOffsetY", "absorbBarTexture", "absorbBarOpacity",
        "overAbsorbOverlay", "fullHealthAbsorbStripe", "healAbsorbEnabled", "healAbsorbAnchorMode", "healAbsorbBarHeight",
        "healAbsorbBarOffsetY", "healAbsorbBarTexture", "healAbsorbBarOpacity", "healPredEnabled", "healPredAnchorMode",
        "healPredictionBarHeight", "healPredictionBarOffsetY", "healPredictionBarTexture", "healPredictionBarOpacity", "healPredAllHealers",
        "barOutlineColorMode", "barOutlineColorR", "barOutlineColorG", "barOutlineColorB", "barOutlineColorA",
        "highlightBorderThickness", "hlAggroSize", "aggroOutlineMode", "aggroMode", "dispelOutlineMode", "dispelBorderTrigger",
        "dispelBorderShowOn", "purgeOutlineMode", "hlPrioEnabled", "highlightPrioEnabled", "hlPrioOrder", "highlightPrioOrder",
    } },
    { { "general", "gf_party", "gf_raid", "gf_mythicraid" }, { "barTexture", "barBackgroundTexture", "barBgTexture" } },
    { { "general" }, { "showSelfHealPrediction", "bossTargetOutlineMode", "bossTargetHighlightEnabled",
        "bossTargetHighlightColor", "dispelTypeColorOverrides",
        "absorbBarColorR", "absorbBarColorG", "absorbBarColorB", "absorbBarColorA",
        "healAbsorbBarColorR", "healAbsorbBarColorG", "healAbsorbBarColorB", "healAbsorbBarColorA",
        "healPredictionColorR", "healPredictionColorG", "healPredictionColorB", "healPredictionColorA",
        "hlAggroColorR", "hlAggroColorG", "hlAggroColorB", "aggroBorderColorR", "aggroBorderColorG", "aggroBorderColorB",
        "aggroBorderR", "aggroBorderG", "aggroBorderB", "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
        "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB",
    } },
    { { "bars", "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid" }, { "barOutlineThickness", "barOutlineLayer", "barOutlineTexture", "slantedBarDirection" } },
    { { "bars" }, { "powerBarTexture", "powerBarBgTexture", "smoothPowerBar", "chunkedPowerBar", "realtimePowerText",
        "roundedFramesEnabled", "roundedUnitFrames", "roundedGroupFrames", "roundedPowerBars", "roundedCastbars", "roundedClassResources",
        "roundedMouseover", "roundedCornerStrength", "slantedBarsEnabled", "slantedUnitFrames", "slantedGroupFrames", "slantedPowerBars",
        "slantedCastbars", "slantedClassResources", "slantedMouseover" } },
    { { "player", "target", "focus", "boss", "arena" }, { "powerSmoothFill", "powerChunkedFill" } },
    { { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid" }, { "hlOverride", "gradientOverride", "gradientOverrideVersion", "gradientOverrideKeys", "frameBarShape" } },
    { { "gf_party", "gf_raid", "gf_mythicraid" }, { "barTextureOverride" } },
}
local function Replay(source, candidate)
    print("GlobalBars " .. flavor .. ": replay " .. (candidate and "candidate" or "immutable parent"))
    local rows, ids, calls, tips, refreshes = {}, {}, {}, {}, 0
    local dragCommands = {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                if source and path:sub(-#target) == target then
                    path = source
                    -- The immutable parent predates namespace-only exports; the projection is the current page.
                    if not candidate then return World.LoadHistorical(self, path, ...) end
                end
                return load(self, path, ...)
            end
            -- Native preview methods absent from the shared widget fixture.
            for _, name in ipairs({ "Rows", "Columns", "Frames", "FrameWidth", "FrameHeight" }) do
                local field = "flipBook" .. name
                world.widgets.Methods["SetFlipBook" .. name] = function(w, value) w[field] = value end
            end
            world.widgets.Methods.GetCenter = function(w)
                return (tonumber(w.left) or 0) + (tonumber(w.width) or 0) / 2,
                    w._fixtureDragCenterY or ((tonumber(w.bottom) or 0) + (tonumber(w.height) or 0) / 2)
            end
            -- Native ColorSelect rendering seam, as in the existing picker-owner smoke.
            for _, kind in ipairs({ "Wheel", "Value" }) do
                world.widgets.Methods["SetColor" .. kind .. "Texture"] = function(w, texture) w[kind] = texture end
                world.widgets.Methods["SetColor" .. kind .. "ThumbTexture"] = function(w) w[kind .. "Thumb"] = w:CreateTexture() end
                world.widgets.Methods["GetColor" .. kind .. "ThumbTexture"] = function(w) return w[kind .. "Thumb"] end
            end
            world.widgets.Methods.SetColorRGB = function(w, r, g, b) w.rgb = { r, g, b } end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...) ctx.width = 400 return builder(ctx, ...) end
    end
    local F = core.ProfileFields
    core.ProfileRuntime.Apply = function() end
    -- Match the existing Colors contract seam: observe gameplay requests, not unrelated native TotemFrame rendering.
    core.MSUF_ApplyGameplayVisuals = function(...) calls[#calls + 1] = { "GameplayVisuals", ... } end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    local function Add(tag, ...) rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids) end
    local function Diff(a, b, path, out)
        path, out = path or "", out or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for key in pairs(a) do keys[key] = true end
            for key in pairs(b) do keys[key] = true end
            for key in pairs(keys) do Diff(a[key], b[key], path .. "." .. tostring(key), out) end
        elseif Encode(a, ids) ~= Encode(b, ids) then out[path] = { Encode(a, ids), Encode(b, ids) } end
        return out
    end
    local function Command(w)
        local record = w._msuf2RuntimeControlRecord
        if record and record.kind == "dragrow" then return dragCommands[w] end
        return w._msuf2CommandAction or (record and record.command)
    end
    local function Value(w)
        local command = Command(w)
        if command and command.get then return Pack(command.get()) end
        if w.GetValue then return Pack(w:GetValue()) end
        return Pack()
    end
    local function Values(w)
        local command = Command(w)
        local values = w.values or (command and command.values)
        return type(values) == "function" and values() or values
    end
    local picker, openPicker = nil, M.Widgets.OpenColorContextPicker
    M.Widgets.OpenColorContextPicker = function(...)
        picker = openPicker(...)
        return picker
    end
    local function Input(w, value)
        picker = nil
        local command, record = Command(w), w._msuf2RuntimeControlRecord
        local kind = command and command.kind or (record and record.kind) or "button"
        if kind == "color" then
            if w._msuf2OnColorChanged then w._msuf2OnColorChanged(unpack(value)) else w:Click("LeftButton") end
        elseif kind == "toggle" then
            -- A disabled native click cannot pre-toggle the CheckButton.
            if w:IsEnabled() then w:SetChecked(value) end
            w:Click("LeftButton")
        elseif w.buttons then
            for _, button in ipairs(w.buttons) do if button._msuf2Value == value then button:Click("LeftButton") end end
        elseif kind == "button" then w:Click("LeftButton")
        elseif kind == "dragrow" then
            local holder = w:GetParent()
            if holder._enabled then
                w._fixtureDragCenterY = holder:GetTop() - 89
                World.FireScript(w, "OnDragStart")
                World.FireScript(w, "OnDragStop")
                w._fixtureDragCenterY = nil
            end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        else w:SetValue(value) World.FireScript(w, "OnValueChanged", value) end
        if picker and picker:IsShown() then
            local owners = {}
            for i, owner in ipairs(picker.owners) do owners[i] = owner end
            -- Each real owner has a distinct color and its own native transaction.
            -- The reviewed highlight card has at most eight targets (recent cap nine).
            assert(#owners > 0 and #owners <= 9, "palette owner count exceeds tested recent capacity")
            local recentStore = assert(env.MSUF_DB.menu2ColorPicker)
            recentStore.recent = {}
            local expectedRecent, distinct = {}, {}
            for i, owner in ipairs(owners) do
                picker:SetOwner(owner)
                picker:Apply((i * 31 % 256) / 255, (i * 67 % 256) / 255, (i * 97 % 256) / 255)
                picker:ApplyOpacity(0.5)
                -- Finish records the native owner's readback. Classic's legacy
                -- dispel getter may retain factory colors despite stored overrides.
                -- Keep that parent behavior, exact DB diffs and distinct colors.
                local r, g, b = owner:GetRGB()
                local hex = string.format("#%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
                assert(not distinct[hex], "actual owner colors are not distinct")
                distinct[hex], expectedRecent[#owners - i + 1] = true, hex
                picker:Finish(false)
                if i < #owners then w:Click("LeftButton") end
            end
            assert(#recentStore.recent == #owners, "distinct owner colors collapsed in recent palette")
            for i = 1, #owners do
                local owner = #owners - i + 1
                assert(recentStore.recent[i] == expectedRecent[i],
                    "recent palette order drift at owner " .. owner .. " control=" .. tostring(ids[w])
                    .. " actual=" .. tostring(recentStore.recent[i]) .. " all=" .. table.concat(recentStore.recent, ","))
            end
        end
        mw:RunTimers()
    end
    local arrows, arrowMetadata, registerSearch = {}, {}, M.RegisterSearchWidget
    M.RegisterSearchWidget = function(widget, meta)
        -- Search intentionally forwards a field whitelist without command.
        -- Observe the actual page-owned command before that catalog boundary.
        if meta.kind == "dragrow" and meta.command then dragCommands[widget] = meta.command end
        if meta.controlId and meta.controlId:find(".gradient.", 1, true)
            and meta.controlId:find(".direction.", 1, true) and meta.kind == "button" then
            arrows[widget], arrowMetadata[widget] = meta.controlId, meta
        end
        return registerSearch(widget, meta)
    end
    assert(mw:Select("opt_bars"))
    local entry = M.cache.opt_bars
    if candidate then
        local shells = 0
        for _, section in pairs(entry.sections) do
            local shell = section._msuf2CollapsibleEntry
            if shell then
                shells = shells + 1
                assert(shell.header._msuf2ControlSchema, "cold section owner missing")
            end
        end
        assert(shells == 8, "Bars lazy section inventory drift")
    end
    local function OpenSections()
        for _, section in pairs(entry.sections) do
            if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
    end
    OpenSections()
    local controls, selector, tabs = {}, nil, {}
    local function ControlID(path) return M.ControlMeta("opt_bars", "global", path).controlId end
    local function Own(w)
        while w do
            if w == entry.wrapper or w._msuf2PageOwnerWrapper == entry.wrapper then return true end
            w = w.GetParent and w:GetParent()
        end
    end
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(record.controlId).widget
        if record.pageKey == "opt_bars" and w and Own(w) then
            ids[w] = record.controlId
            local command = Command(w)
            if record.controlId == ControlID("scope.selector") and w.buttons then selector = w end
            if record.controlId == ControlID("absorb.workspace_tab") and w.buttons then tabs.menuTab = w end
            if record.controlId == ControlID("highlight.workspace_tab") and w.buttons then tabs.barsHighlightTab = w end
            if (command and command.get and command.set) or w.buttons or (record.kind == "button" and w:HasScript("OnClick")) then
                controls[#controls + 1] = w
            end
        end
    end
    assert(selector, "real Bars scope selector missing from " .. #controls .. " page controls")
    assert(#controls >= 60, "incomplete real control inventory: " .. #controls)
    local catalogCount, colorOwners = #controls, 0
    for _, w in ipairs(mw.world.widgets.frames) do
        if Own(w) and w._msuf2ContextColorOptions then
            colorOwners = colorOwners + 1
            if not ids[w] then
                ids[w] = "native-color:" .. assert(w._msuf2ContextColorOptions.historySource)
                controls[#controls + 1] = w
            end
        end
    end
    assert(colorOwners == 7, "native Bars color owner inventory drift: " .. colorOwners)
    local arrowCount = 0
    for widget, id in pairs(arrows) do
        arrowCount = arrowCount + 1
        if not ids[widget] then ids[widget] = id controls[#controls + 1] = widget end
    end
    assert(arrowCount == 8, "native gradient arrow inventory drift")
    local selected, dragOwners = {}, 0
    for _, control in ipairs(controls) do selected[control] = true end
    for _, widget in ipairs(mw.world.widgets.frames) do
        local record = widget._msuf2RuntimeControlRecord
        if Own(widget) and not widget._msuf2ControlPartOf and record and record.kind == "dragrow" then
            dragOwners = dragOwners + 1
            ids[widget] = record.controlId
            if not selected[widget] then controls[#controls + 1] = widget selected[widget] = true end
        end
    end
    assert(dragOwners == 1, "actual priority drag owner missing or duplicated")
    table.sort(controls, function(a, b) return ids[a] < ids[b] end)
    local function CheckAction(w, spec)
        if not spec.action then return end
        local click, script, called = w.Click, w:GetScript("OnClick"), false
        w.Click = function(self, button, down)
            called = self == w and button == "RightButton" and down == true
            return false, "native-owner", 17
        end
        local result = Pack(spec.action(nil, "RightButton", true))
        w.Click = click
        assert(called and result.n == 3 and result[1] == false and result[2] == "native-owner" and result[3] == 17,
            "custom action bypasses current native Click: " .. ids[w])
        assert(w:GetScript("OnClick") == script, "custom declaration replaced native input")
    end
    local ordinary = 0
    for _, w in ipairs(controls) do
        local record = w._msuf2RuntimeControlRecord
        local command = Command(w)
        if candidate then
            local spec = assert(w._msuf2ControlSchema, "actual input lacks declaration: " .. ids[w])
            assert(spec.scope == "bars", "wrong input declaration scope: " .. ids[w])
            if spec.owner then assert(spec.owner == w, "custom input owner replaced") end
            CheckAction(w, spec)
            if arrows[w] then
                local nativeMeta = assert(arrowMetadata[w])
                assert(spec.labelKey == nativeMeta.label and spec.meta and spec.meta.controlId == nativeMeta.controlId,
                    "arrow semantic label/metadata drift: " .. ids[w])
            end
            if w == tabs.menuTab or w == tabs.barsHighlightTab then
                assert(spec.applyDomain == "sectionNavigation", "workspace tab domain drift")
            end
            if record and record.kind == "dragrow" then
                assert(spec.dragStart == w:GetScript("OnDragStart") and spec.dragStop == w:GetScript("OnDragStop"), "drag owner drift")
                local drag = assert(dragCommands[w], "actual priority command registration missing")
                assert(drag.kind == "dragrow" and spec.get == drag.get and spec.set == drag.set, "drag declaration command drift")
            end
        end
        if command and command.get and command.set and (record.kind == "toggle" or record.kind == "slider" or record.kind == "dropdown")
            and not ids[w]:find(".scope.", 1, true) then
            ordinary = ordinary + 1
            if candidate then assert(w._msuf2ControlSchema, "ordinary control lacks schema: " .. ids[w]) end
        end
    end
    assert(ordinary >= 55, "ordinary control coverage incomplete")
    assert(tabs.menuTab and tabs.barsHighlightTab, "real Bars workspace tabs missing")
    print("GlobalBars " .. flavor .. ": " .. catalogCount .. " catalog inputs, " .. #controls .. " actual inputs, " .. ordinary .. " ordinary")
    local indexed, serial = {}, 0
    local function Index(w)
        if indexed[w] then return end
        indexed[w] = true
        serial = serial + 1
        ids[w] = ids[w] or "page-widget:" .. serial
        for _, region in ipairs(w.regions or {}) do Index(region) end
    end
    for _, w in ipairs(mw.world.widgets.frames) do if Own(w) then Index(w) end end
    if candidate then
        local counts = { card = 0, text = 0, font = 0, preview = 0, directionpad = 0, scope = 0 }
        -- The shared scope builder owns these two text rows under its page key.
        -- Keep their census separate from this page's own bars declarations.
        local sharedScopeText = {
            ["menu2.opt_bars.scope.overrideInfo"] = true,
            ["menu2.opt_bars.scope.hint"] = true,
        }
        local sharedScopeSeen, sharedScopeCount = {}, 0
        local priorityOwner
        for _, control in ipairs(controls) do
            local record = control._msuf2RuntimeControlRecord
            if record and record.kind == "dragrow" then
                assert(record.controlId == ControlID("highlight.priority.order.order"), "unexpected priority drag owner")
                assert(not priorityOwner, "duplicate priority drag owner")
                priorityOwner = control
            end
        end
        local priorityHolder = assert(priorityOwner, "priority drag owner missing"):GetParent()
        local holderSpec = assert(priorityHolder._msuf2ControlSchema, "native drag holder declaration missing")
        assert(holderSpec.id == "shared.dragRows" and holderSpec.kind == "dragRows" and holderSpec.scope == "shared"
            and holderSpec.applyDomain == "sorting" and holderSpec.owner == priorityHolder, "native drag holder owner drift")
        assert(indexed[priorityHolder] and #priorityHolder.rows == 4, "native priority row inventory drift")
        local sharedDragFonts, sharedDragSeen = {}, {}
        local sharedDragCounts = { ["dragrow.label"] = 0, ["dragrow.number"] = 0 }
        for i, row in ipairs(priorityHolder.rows) do
            local frame = row.frame
            assert(frame:GetParent() == priorityHolder and frame._msuf2DragRow == row, "native priority row identity drift")
            if i == 1 then assert(frame == priorityOwner, "atomic priority owner drift")
            else assert(frame._msuf2ControlPartOf == priorityOwner, "priority component owner drift") end
            for _, part in ipairs({ { "_label", "dragrow.label" }, { "_numText", "dragrow.number" } }) do
                local font = assert(frame[part[1]], "native drag font missing: " .. part[2])
                assert(font:GetParent() == frame and not sharedDragFonts[font], "native drag font identity drift")
                sharedDragFonts[font] = part[2]
            end
        end
        local sharedHolderCount = 0
        for w in pairs(indexed) do
            local spec = w._msuf2ControlSchema
            if spec and spec.kind == "dragRows" then
                assert(w == priorityHolder and spec == holderSpec, "unexpected native drag holder")
                sharedHolderCount = sharedHolderCount + 1
            end
            if w._msuf2ControlCard then
                assert(spec and (spec.kind == "card" or spec.kind == "preview"), "undeclared actual card")
            end
            if spec and counts[spec.kind] then
                assert(spec.owner == w, "presentation/custom owner drift: " .. tostring(spec.id))
                if sharedScopeText[spec.id] then
                    assert(spec.kind == "text" and spec.scope == "opt_bars" and spec.applyDomain == "presentation",
                        "shared scope text declaration drift: " .. spec.id)
                    assert(not sharedScopeSeen[spec.id], "duplicate shared scope text owner: " .. spec.id)
                    sharedScopeSeen[spec.id], sharedScopeCount = true, sharedScopeCount + 1
                elseif sharedDragFonts[w] then
                    local id = sharedDragFonts[w]
                    assert(spec.id == id and spec.kind == "font" and spec.scope == "shared" and spec.applyDomain == "presentation",
                        "native drag font declaration drift: " .. id)
                    assert(not sharedDragSeen[w], "duplicate native drag font: " .. id)
                    sharedDragSeen[w], sharedDragCounts[id] = true, sharedDragCounts[id] + 1
                else
                    assert(spec.scope == "bars", "presentation/custom scope drift: " .. tostring(spec.id))
                    counts[spec.kind] = counts[spec.kind] + 1
                end
                if spec.kind == "preview" then
                    assert(spec.refresh == (w.RefreshRoundedPreview or w.RefreshSlantedPreview), "preview painter owner drift")
                    assert(spec.meta == w._msuf2SearchMeta and spec.labelKey == spec.meta.label, "preview label/metadata drift")
                elseif spec.kind == "directionpad" then
                    local arrows = 0
                    for _, arrow in pairs(spec.controls) do assert(arrow:GetParent() == w) arrows = arrows + 1 end
                    assert(arrows == 4, "native direction pad coverage drift")
                elseif spec.kind == "scope" then
                    assert(spec.selector == selector and selector._msuf2ControlSchema.get() == selector:GetValue(), "scope owner drift")
                end
            end
        end
        assert(sharedHolderCount == 1 and sharedDragCounts["dragrow.label"] == 4 and sharedDragCounts["dragrow.number"] == 4,
            "native drag chrome coverage drift")
        for font, id in pairs(sharedDragFonts) do assert(sharedDragSeen[font], "native drag font owner missing: " .. id) end
        assert(sharedScopeCount == 2, "shared scope text coverage drift")
        for id in pairs(sharedScopeText) do assert(sharedScopeSeen[id], "shared scope text owner missing: " .. id) end
        local boss = not M.SupportsUnitPage or M.SupportsUnitPage("uf_boss")
        assert(counts.card == 3 and counts.text == (boss and 4 or 3) and counts.font == 1, "ordinary presentation coverage drift")
        assert(counts.preview == 2 and counts.directionpad == 2 and counts.scope == 1, "native composite coverage drift")
    end
    for _, name in ipairs({ "SetOwner", "SetText", "AddLine", "Show", "Hide" }) do
        env.GameTooltip[name] = function(_, ...) tips[#tips + 1] = { name, ... } end
    end
    local refresh = M.RunEntryRefreshers
    M.RunEntryRefreshers = function(...) refreshes = refreshes + 1 return refresh(...) end
    for name, fn in pairs(M.ApplyService) do
        if type(fn) == "function" then M.ApplyService[name] = function(...)
            calls[#calls + 1] = { name, ... }
            return fn(...)
        end end
    end
    if core.Client.IsClassic then
        -- Classic TOCs use their own compiler and the shared menu model, not Retail CustomConfig.
        local a3 = assert(core.MSUF_Auras3, "real Classic Aura3 provider missing")
        assert(a3.PRESET_CUSTOM_CONTAINER_INDEX == 4, "reviewed Classic Custom-4 index changed")
        local auras = assert(env.MSUF_DB.auras3, "real Classic aura profile missing")
        assert(auras.customContainers.perUnit.player.items[4], "existing Classic Player Custom-4 owner missing")
        local compile = assert(a3._ClassicCompile, "real Classic aura compiler missing")
        assert(type(compile.FrameAuraConfig) == "function" and type(compile.ResolveGroupFrameConfig) == "function",
            "real Classic unit/group config exports missing")
        local model = assert(a3.MenuModel, "real Classic shared menu model missing")
        assert(type(model.CustomContainerStyleItem) == "function" and type(model.CustomContainer) == "function",
            "real Classic Custom-4 menu owners missing")
        assert((a3.Runtime and a3.Runtime.CustomConfig) == nil, "Classic graph unexpectedly loaded Retail CustomConfig")
    else
    -- Settle the genuine Custom-4 legacy style migration before capturing test baselines.
    -- The private one-time guard has real style semantics; it is never ignored in DB comparisons.
    do
        local a3 = assert(core.MSUF_Auras3, "real Aura3 provider missing")
        local index = assert(a3.PRESET_CUSTOM_CONTAINER_INDEX, "real Custom-4 index missing")
        assert(index == 4, "reviewed Custom-4 fixture index changed")
        local auras = assert(env.MSUF_DB.auras3, "real aura profile missing")
        local entry = assert(auras.customContainers.perUnit.player.items[index], "existing Player Custom-4 owner missing")
        local config = assert(a3.Runtime and a3.Runtime.CustomConfig, "real custom config provider missing")
        local resolve = assert(config.ResolveSpecialCustomStyle, "real legacy style resolver missing")
        local beforeMigration = F.CopySnapshot(env.MSUF_DB)
        resolve(auras, "player", index, entry)
        assert(entry._msufA3LocalStyleFromShared_v1 == true, "real Custom-4 migration did not settle")
        for path, delta in pairs(Diff(beforeMigration, env.MSUF_DB)) do
            assert(path == ".auras3.customContainers.perUnit.player.items.4._msufA3LocalStyleFromShared_v1"
                and delta[1] == "nil:nil" and delta[2] == "boolean:true",
                "unexpected profile write during exact Custom-4 fixture migration: " .. path)
        end
        local settled = F.CopySnapshot(env.MSUF_DB)
        resolve(auras, "player", index, entry)
        assert(not next(Diff(settled, env.MSUF_DB)), "settled Custom-4 migration is not idempotent")
    end
    end
    local defaults = F.CopySnapshot(env.MSUF_DB)
    local function Restore(dst, src)
        for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
        for key, value in pairs(src) do
            if type(value) == "table" then
                if type(dst[key]) ~= "table" then dst[key] = {} end
                Restore(dst[key], value)
            else dst[key] = value end
        end
    end
    local function AssertAbsent(phase, exceptions)
        local checked = 0
        for _, fields in ipairs(ABSENT_FIELDS) do
            for _, owner in ipairs(fields[1]) do
                local conf = env.MSUF_DB[owner]
                for _, key in ipairs(fields[2]) do
                    local expected = exceptions and exceptions[owner] and exceptions[owner][key]
                    local actual
                    if conf then actual = rawget(conf, key) end
                    assert(actual == expected, phase .. " stored absence drift: " .. owner .. "." .. key)
                    checked = checked + 1
                end
            end
        end
        assert(checked == 1047, "stored-field absence census drift")
        Add(phase .. ":raw-nil", checked)
    end
    local function Setup(state, scope, control)
        local enabledShared = state == "shared-default" or state == "shared-edge"
        if enabledShared then state = state == "shared-edge" and "edge" or "default" end
        Restore(env.MSUF_DB, defaults)
        Input(selector, scope)
        assert(M.GlobalPage.CurrentBarsScope() == scope, "scope selector did not persist " .. scope)
        local db = env.MSUF_DB
        M.GlobalPage.ScopeSetOverride(scope, "hlOverride", true)
        for _, key in ipairs({ "general", "player", "gf_raid", "gf_mythicraid" }) do
            local conf = db[key]
            if conf then
                conf.enableGradient, conf.enablePowerGradient = true, true
                -- Inactive group scopes inherit this key; cold repair removes a local seed.
                if key == "general" or key == "player" or conf.hlOverride then conf.enableAbsorbBar = true end
                conf.healAbsorbEnabled, conf.healPredEnabled = true, true
                conf.tempMaxHealthEnabled, conf.hlPrioEnabled = true, true
                conf.aggroOutlineMode, conf.dispelOutlineMode, conf.purgeOutlineMode = 1, 1, 1
            end
        end
        db.bars.roundedFramesEnabled, db.bars.slantedBarsEnabled = true, true
        if state == "absent" then
            for _, fields in ipairs(ABSENT_FIELDS) do
                for _, tableKey in ipairs(fields[1]) do
                    local conf = db[tableKey]
                    if conf then for _, key in ipairs(fields[2]) do conf[key] = nil end end
                end
            end
        end
        if state == "edge" then
            db.general.powerGradientStrength, db.general.tempMaxHealthOpacity = false, 0
            db.bars.powerBarTexture, db.bars.roundedUnitFrames, db.bars.realtimePowerText = false, 0, 0
            db.bars.roundedCornerStrength = nil
            db.player.gradientStrength, db.player.slantedBarDirection = 0, nil
        end
        -- Separate enabled inputs retain the original Player/zero edge case.
        if enabledShared then db.bars.realtimePowerText = false end
        if state == "absent" then AssertAbsent("absent-cleared:" .. scope) end
        OpenSections()
        Input(tabs.menuTab, "positive")
        Input(tabs.barsHighlightTab, "modes")
        local owner = control
        while owner do
            local view = owner._msuf2ExactTabView
            if view then Input(assert(tabs[view.kind], "unknown Bars tab owner"), view.value) break end
            owner = owner.GetParent and owner:GetParent()
        end
        M.Refresh()
        mw:RunTimers()
        M.ClearHistory()
        if state == "absent" then AssertAbsent("absent-refreshed:" .. scope) end
    end
    local function Gates()
        local result = {}
        for _, w in ipairs(controls) do result[ids[w]] = { w:IsShown(), w:IsEnabled() } end
        return result
    end
    local function NativeValue(w)
        local buttons = {}
        for i, button in ipairs(w.buttons or {}) do buttons[i] = { button._msuf2Value, button:GetChecked(), button.value } end
        return Pack(w:GetChecked(), w:GetValue(), w.value,
            w._msuf2Label and w._msuf2Label:GetText(), w.editBox and w.editBox:GetText(), buttons)
    end
    local function HistoryStack(stack)
        local entries = {}
        for i, value in ipairs(stack) do entries[i] = value end
        return entries
    end
    local function AssertStack(expected, actual, phase)
        assert(#expected == #actual, phase .. " history stack size drift")
        for i, value in ipairs(expected) do assert(actual[i] == value, phase .. " history entry identity drift at " .. i) end
    end
    local function AssertFallback(path, expected)
        local control
        for _, w in ipairs(controls) do if ids[w] == ControlID(path) then assert(not control, "duplicate fallback owner") control = w end end
        assert(control, "missing real fallback owner: " .. path)
        assert(Value(control)[1] == expected, "stored-nil getter fallback drift: " .. path)
        if path == "highlight.priority.enabled" then
            assert(control:GetChecked() == expected, "stored-nil native toggle fallback drift")
        else
            assert(control:GetValue() == expected, "stored-nil native dropdown fallback drift: " .. path)
        end
        Add("fallback:" .. M.GlobalPage.CurrentBarsScope() .. ":" .. path, Value(control), NativeValue(control))
    end
    local function AssertAbsentFallbacks(background, priority)
        AssertFallback("textures.foreground", "Blizzard")
        AssertFallback("textures.background", background)
        AssertFallback("outline.texture", "")
        AssertFallback("highlight.priority.enabled", priority)
    end
    local function Observe(tag)
        for _, w in ipairs(mw.world.widgets.frames) do
            if Own(w) then
                local points = {}
                for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
                Add(tag .. ":layout", w, w:GetParent(), w.width, w.height, w.text, points, w:IsShown(), w:IsEnabled(), w._msuf2CursorY)
                for _, region in ipairs(w.regions or {}) do
                    local rp = {}
                    for i = 1, region:GetNumPoints() do rp[i] = Pack(region:GetPoint(i)) end
                    Add(tag .. ":region", region, region.text, region.width, region.height, rp, region:IsShown())
                end
            end
        end
        for _, w in ipairs(controls) do
            tips = {}
            if w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
            if w:HasScript("OnLeave") then World.FireScript(w, "OnLeave") end
            local points = {}
            for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
            local low, high = w:GetMinMaxValues()
            Add(tag .. ":control", w._msuf2RuntimeControlRecord, w._msuf2SearchMeta, w._msuf2SearchText,
                w:GetObjectType(), w.width, w.height, points, low, high, w.valueStep,
                Values(w), Value(w), tips)
        end
    end
    local function Alternate(w)
        local command, record = Command(w), w._msuf2RuntimeControlRecord
        local kind = command and command.kind or (record and record.kind) or "button"
        local old = Value(w)[1]
        if kind == "toggle" then return not old end
        if kind == "button" then return "LeftButton" end
        if kind == "color" then return { 0, 0.25, 1 } end
        if kind == "slider" then local lo, hi = w:GetMinMaxValues() return old == hi and lo or hi end
        local values = Values(w)
        for i = #(values or {}), 1, -1 do
            local item = values[i]
            if not item.disabled and not item.header and item.value ~= nil and item.value ~= old then return item.value end
        end
        return old
    end
    local pendingRedoCases, enabledSharedCases = 0, 0
    local states = (mode == "palette" or mode == "drag") and { "default" } or { "default", "edge", "absent" }
    if mode == "full" or mode == "push" then
        states[#states + 1], states[#states + 2] = "shared-default", "shared-edge"
    end
    for _, state in ipairs(states) do
        local enabledShared = state == "shared-default" or state == "shared-edge"
        local scope = (state == "default" or enabledShared) and "shared" or "player"
        Setup(state, scope)
        if not enabledShared then Observe(state) end
        if state == "absent" then AssertAbsentFallbacks("", false) AssertAbsent("absent-observed:" .. scope) end
        for _, w in ipairs(controls) do
            local record = w._msuf2RuntimeControlRecord
            local runInput = not narrow and mode ~= "absent" and state ~= "absent" and not (mode == "push" and state == "edge")
            if mode == "palette" then runInput = w._msuf2ContextColorOptions ~= nil end
            if mode == "drag" then runInput = record and record.kind == "dragrow" end
            if enabledShared then runInput = ids[w] == ControlID("power.realtime_text") end
            if runInput then
            Setup(state, scope, w)
            local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
            if enabledShared then
                assert(M.GlobalPage.CurrentBarsScope() == "shared" and w:IsShown() and w:IsEnabled(), "enabled Shared control gate drift")
                assert(before.bars.realtimePowerText == false and Value(w)[1] == false and w:GetChecked() == false,
                    "enabled Shared control did not begin at stored/model/native false")
                assert(value == true, "enabled Shared input is not false-to-true")
                Add(state .. ":enabled-seed", before.bars.realtimePowerText, Value(w), NativeValue(w), Gates())
            end
            calls, refreshes = {}, 0
            Input(w, value)
            local after = F.CopySnapshot(env.MSUF_DB)
            local afterValue, afterNative, afterHistory = Value(w), NativeValue(w), M.GetHistoryState()
            if enabledShared then
                local expected = F.CopySnapshot(before)
                expected.bars.realtimePowerText = true
                assert(not next(Diff(expected, after)), "enabled Shared input changed unexpected DB fields")
                assert(after.bars.realtimePowerText == true and afterValue[1] == true and afterNative[1] == true,
                    "enabled Shared input did not set stored/model/native true")
                local applied = 0
                for _, call in ipairs(calls) do
                    if call[1] == "RequestUnitDomains" and call[3] == "MSUF2_BARS_REALTIME_POWER" then
                        assert(call[2] == "player" and call[4].preview == true and call[4].power == true and call[4].text == true,
                            "enabled Shared input lost the real Player power/text apply domains")
                        applied = applied + 1
                    end
                end
                assert(applied == 1, "enabled Shared input did not request exactly one real Player power/text apply")
            end
            if record and record.kind == "dragrow" then assert(next(Diff(before, after)), "priority drag did not reorder real profile") end
            Add(state .. ":input:" .. ids[w], value, Diff(before, after), Value(w), calls, refreshes, Gates())
            local undo = M.Undo()
            mw:RunTimers()
            Add(state .. ":undo:" .. ids[w], undo, Diff(before, env.MSUF_DB), Value(w))
            -- Keep the real Undo entry pending through both refused native inputs.
            -- No Setup, ClearHistory or successful Redo may run in this interval.
            local pendingDB, pendingValue, pendingNative = F.CopySnapshot(env.MSUF_DB), Value(w), NativeValue(w)
            local pendingHistory = M.GetHistoryState()
            local pendingUndo, pendingRedo = HistoryStack(M.historyUndo), HistoryStack(M.historyRedo)
            if enabledShared then
                assert(undo == true and not next(Diff(before, pendingDB)), "enabled Shared Undo did not restore exact DB")
                assert(pendingDB.bars.realtimePowerText == false and pendingValue[1] == false and pendingNative[1] == false,
                    "enabled Shared Undo did not refresh stored/model/native false")
                assert(refreshes > 0, "enabled Shared Undo did not run real entry refreshers")
            end
            if undo then
                assert(pendingHistory.canRedo and pendingHistory.redoCount == 1, "Undo left no real pending Redo: " .. ids[w])
                pendingRedoCases = pendingRedoCases + 1
            else assert(pendingHistory.redoCount == 0, "no-op Undo invented Redo") end
            local function AssertPending(phase)
                assert(not next(Diff(pendingDB, env.MSUF_DB)), phase .. " changed DB while Redo pending: " .. ids[w])
                assert(Encode(Value(w), ids) == Encode(pendingValue, ids), phase .. " changed pending model")
                assert(Encode(NativeValue(w), ids) == Encode(pendingNative, ids), phase .. " changed pending native display: " .. ids[w])
                assert(Encode(M.GetHistoryState(), ids) == Encode(pendingHistory, ids), phase .. " changed pending history state")
                AssertStack(pendingUndo, M.historyUndo, phase)
                AssertStack(pendingRedo, M.historyRedo, phase)
                if enabledShared then
                    for _, call in ipairs(calls) do
                        assert(call[1] ~= "RequestUnitDomains" or call[3] ~= "MSUF2_BARS_REALTIME_POWER",
                            phase .. " applied a refused Shared input")
                    end
                end
            end
            core.Util.InCombat("PLAYER_REGEN_DISABLED")
            env.InCombatLockdown = function() return false end
            calls, refreshes = {}, 0
            Input(w, value)
            AssertPending("combat-edge")
            Add(state .. ":combat-edge:" .. ids[w], Diff(pendingDB, env.MSUF_DB), Value(w), calls, refreshes, M.GetHistoryState(), NativeValue(w))
            env.InCombatLockdown = function() return true end
            Input(w, value)
            local refusedUndo = M.Undo()
            assert(refusedUndo == false, "combat Undo was not refused")
            AssertPending("combat")
            Add(state .. ":combat:" .. ids[w], Diff(pendingDB, env.MSUF_DB), Value(w), refusedUndo, M.GetHistoryState(), NativeValue(w))
            core.Util.InCombat("PLAYER_REGEN_ENABLED")
            env.InCombatLockdown = function() return false end
            mw:Fire("PLAYER_REGEN_ENABLED")
            mw:RunTimers()
            AssertPending("combat-release")
            local redo = M.Redo()
            mw:RunTimers()
            assert(redo == undo, "post-refusal Redo lost its pending entry: " .. ids[w])
            assert(not next(Diff(after, env.MSUF_DB)), "post-refusal Redo did not restore exact DB: " .. ids[w])
            assert(Encode(Value(w), ids) == Encode(afterValue, ids), "post-refusal Redo model drift")
            assert(Encode(NativeValue(w), ids) == Encode(afterNative, ids), "post-refusal Redo native display drift: " .. ids[w])
            assert(Encode(M.GetHistoryState(), ids) == Encode(afterHistory, ids), "post-refusal Redo history drift")
            Add(state .. ":redo:" .. ids[w], redo, Diff(after, env.MSUF_DB), Value(w), NativeValue(w), M.GetHistoryState())
            if enabledShared then enabledSharedCases = enabledSharedCases + 1 end
            end
        end
    end
    if not narrow and mode ~= "absent" then assert(pendingRedoCases > 0, "no real pending-Redo refusal was exercised") end
    Add("pending-redo-census", pendingRedoCases)
    if mode == "full" or mode == "push" then
        assert(enabledSharedCases == 2, "enabled Shared default/edge input census drift")
        Add("enabled-shared-census", enabledSharedCases)
    end
    if mode ~= "palette" and mode ~= "drag" then
        -- Scope aliases resolve to canonical DB owners; Raid also owns the Mythic row.
        for alias, expected in pairs({ party = "gf_party", groupparty = "gf_party", group_party = "gf_party", gfparty = "gf_party",
            raid = "gf_raid", mythic = "gf_raid", mythicraid = "gf_raid", groupraid = "gf_raid", group_raid = "gf_raid",
            gfraid = "gf_raid", gf_mythicraid = "gf_raid", focus_target = "focustarget", focustargettarget = "focustarget" }) do
            assert(M.GlobalPage.NormalizeScopeKey(alias) == expected, "Bars scope alias drift: " .. alias)
            local keys = M.GlobalPage.ScopeDBKeys(alias)
            assert(keys[1] == expected and #keys == (expected == "gf_raid" and 2 or 1), "Bars DB owner alias drift")
            if expected == "gf_raid" then assert(keys[2] == "gf_mythicraid", "Raid lost Mythic fallback owner") end
        end
        for _, scope in ipairs({ "shared", "player", "gf_party", "gf_raid" }) do
            Setup("absent", scope)
            Observe("absent-owner:" .. scope)
            AssertAbsentFallbacks("", false)
            AssertAbsent("absent-owner-observed:" .. scope)
            local legacyOwner = scope == "gf_raid" and "gf_mythicraid" or scope == "gf_party" and "gf_party" or "general"
            local conf, exceptions = env.MSUF_DB[legacyOwner], {}
            if not conf then conf = {} env.MSUF_DB[legacyOwner] = conf end
            conf.barBgTexture, conf.highlightPrioEnabled = "Blizzard", 1
            exceptions[legacyOwner] = { barBgTexture = "Blizzard", highlightPrioEnabled = 1 }
            if scope == "gf_party" or scope == "gf_raid" then
                M.GlobalPage.ScopeSetOverride(scope, "hlOverride", true)
                exceptions[scope] = exceptions[scope] or {}
                exceptions[scope].hlOverride = true
                exceptions[legacyOwner].hlOverride = true
            end
            M.Refresh()
            mw:RunTimers()
            AssertAbsentFallbacks("Blizzard", true)
            AssertAbsent("absent-legacy-owner:" .. scope, exceptions)
        end
    end
    for _, scope in ipairs((narrow or mode == "absent" or mode == "palette" or mode == "drag") and {} or { "gf_raid", "player", "shared" }) do
        Setup("edge", scope)
        Observe("scope:" .. scope)
        for _, w in ipairs(controls) do
            if ids[w] == ControlID("slanted.direction") or ids[w] == ControlID("absorb.positive.opacity") then
                local before = F.CopySnapshot(env.MSUF_DB)
                calls, refreshes = {}, 0
                Input(w, Alternate(w))
                Add("scope-input:" .. scope .. ":" .. ids[w], Diff(before, env.MSUF_DB), Value(w), calls, refreshes)
            end
        end
    end
    mw:Select("home")
    mw:Select("opt_bars")
    M.Refresh()
    mw:RunTimers()
    Add("reopen", Gates())
    return rows, #controls, ordinary
end
local started = os.clock()
-- Project only the separately tested Gloss addition out of this historical
-- replay. Every pre-existing control, coordinate, input and DB delta remains
-- compared to the unchanged immutable parent. The dedicated gloss menu smoke
-- verifies the four added controls and the complete new section dimensions.
local candidateFile = assert(io.open(override or (root .. "/" .. target), "rb"))
local candidateSource = candidateFile:read("*a")
assert(candidateFile:close())
local function ReplaceOne(before, after)
    local first, last = candidateSource:find(before, 1, true)
    assert(first and not candidateSource:find(before, last + 1, true), "Gloss feature projection no longer matches exactly")
    candidateSource = candidateSource:sub(1, first - 1) .. after .. candidateSource:sub(last + 1)
end
ReplaceOne("    GP.BuildBarGlossControls(ctx, textures, leftX, rightX, leftW, compactTextures)", "")
ReplaceOne("compactTextures and 766 or 448", "compactTextures and 566 or 330")
ReplaceOne("< 560) and 766 or 448 end", "< 560) and 566 or 330 end")
file = assert(io.open(projectionPath, "wb"))
assert(file:write(candidateSource)) assert(file:close()) file = nil
local baseline, count, ordinary = Replay(scratch, false)
local actual = Replay(projectionPath, true)
assert(#baseline == #actual, "observation count drift: " .. #baseline .. " / " .. #actual)
for i = 1, #baseline do
    if baseline[i] ~= actual[i] then
        diffPath = os.tmpname()
        diff = assert(io.open(diffPath, "wb"))
        assert(diff:write("parent\n", baseline[i], "\ncandidate\n", actual[i], "\n")) assert(diff:close()) diff = nil
        error("GlobalBars parity drift at observation " .. i .. " " .. baseline[i]:match("^[^\t]+"))
    end
end
if mode == "full" or mode == "push" then
    narrow = true
    local before, after = Replay(scratch, false), Replay(projectionPath, true)
    assert(#before == #after, "400px observation count drift")
    for i = 1, #before do assert(before[i] == after[i], "400px GlobalBars parity drift at " .. i) end
end
print("menu_global_bars_schema_parity_smoke " .. mode .. " " .. flavor .. ": " .. count .. " controls (" .. ordinary .. " ordinary), " .. #baseline
    .. " observations; input/DB/apply/refresh/history/refusal/scope/false-zero-nil/reopen OK (" .. string.format("%.2fs", os.clock() - started) .. ")")
end
local ok, problem = xpcall(Run, debug.traceback)
if io.type(file) == "file" then file:close() end
if io.type(diff) == "file" then diff:close() end
local removed, cleanupError = os.remove(scratch)
local projectedRemoved = os.remove(projectionPath)
if ok then assert(projectedRemoved, "Gloss projection cleanup failed") end
if diffPath then io.stderr:write("GlobalBars " .. flavor .. " " .. mode .. " diff artifact: " .. diffPath .. "\n") end
if not ok then
    if not removed then io.stderr:write("GlobalBars temporary parent cleanup failed: " .. tostring(cleanupError) .. "\n") end
    error(problem, 0)
end
assert(removed, "GlobalBars temporary parent cleanup failed: " .. tostring(cleanupError))

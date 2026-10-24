-- Real Group Aura Style controls replayed against their reachable pre-schema source.
-- Offline binding and layout evidence; no live rendering or performance claim.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local mode = arg[3] or "full"
assert(mode == "full" or mode == "push" or mode == "original", "unknown Group Aura Style tier")
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Group.lua"
local blob = "a06ff35b0fa681858379bc5f2f2f3a42bc9e51c2"
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
local function Replay(original, narrow, positiveBlacklist)
    print("Group Aura Style " .. flavor .. ": " .. (original and "immutable parent" or "candidate"))
    local coldPickerCases, selectedPickerCases, selectedColdCases = 0, 0, 0
    local loaded = 0
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true, keepFlush = true,
        beforeCore = positiveBlacklist and function(world)
            -- Menu_Presets RAID_BUFFS59-60: actual Classic IDs/names only.
            local names = { [1459] = "Arcane Intellect", [6673] = "Battle Shout" }
            world.env.GetSpellInfo = function(rawID)
                local id = tonumber(rawID)
                local name = names[id]
                if name then return name, nil, nil, nil, nil, nil, id end
            end
        end or nil,
        beforeOptions = function(world)
            -- Native FlipBook calls reached by GroupPreview_Render's icon glow.
            -- The shared stub already captures Rows/Columns/Frames; dimensions
            -- are the two missing methods, installed only in this local world.
            local methods = world.widgets.Methods
            if not methods.SetFlipBookFrameWidth then
                methods.SetFlipBookFrameWidth = function(self, value) self.flipBookFrameWidth = value end
            end
            if not methods.SetFlipBookFrameHeight then
                methods.SetFlipBookFrameHeight = function(self, value) self.flipBookFrameHeight = value end
            end
            -- Native ColorSelect storage used by the real picker in every tier.
            -- Keep the widget, script hooks, owner getters and painter unchanged.
            for _, part in ipairs({ "Wheel", "Value" }) do
                local key = part
                if not methods["SetColor" .. key .. "Texture"] then
                    methods["SetColor" .. key .. "Texture"] = function(self, texture) self["color" .. key] = texture end
                end
                if not methods["SetColor" .. key .. "ThumbTexture"] then
                    methods["SetColor" .. key .. "ThumbTexture"] = function(self, path)
                        local texture = self:CreateTexture()
                        texture:SetTexture(path) self["color" .. key .. "Thumb"] = texture
                    end
                end
                if not methods["GetColor" .. key .. "ThumbTexture"] then
                    methods["GetColor" .. key .. "ThumbTexture"] = function(self) return self["color" .. key .. "Thumb"] end
                end
            end
            if not methods.SetColorRGB then
                methods.SetColorRGB = function(self, red, green, blue)
                    self.nativeRGB = { red, green, blue }
                    MenuWorld.FireScript(self, "OnColorSelect", red, green, blue)
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
    if narrow then
        local builder = M.Widgets.PageBuilder
        M.Widgets.PageBuilder = function(ctx, ...)
            ctx.width = 400
            local page = builder(ctx, ...)
            assert(page.width == 400, "400px page was not rebuilt")
            return page
        end
    end
    -- The apply owners read these from the registry (and some from the global): publish the stand-ins the
    -- way the owners do (the registry, and the global for a kept name).
    core.ExportPublic("MSUF_UFCore_NotifyConfigChanged", function() return true end)
    core.ExportPublic("MSUF_ApplyModules", function() return true end)
    core.ExportPublic("MSUF_ClassPower_Apply", function() return true end)
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
    if positiveBlacklist then
        assert(core.Client.IsClassic == true and not narrow, "positive blacklist world is Classic-only")
        local model, W = core.MSUF_Auras3.MenuModel, M.Widgets
        M.GroupPage.Conf("party").enabled = true
        M.GroupPage.AurasRoot("party", true).enabled = true
        M.GroupPage.AuraGroup("party", "buff").enabled = true
        M.SetMenuStateValue("gfScope", "party")
        M.SetMenuStateValue("gfAuraLaneSelection", { party = "buff" })
        M.SetMenuStateValue("gfAuraToolSelection", { party = { buff = "blacklist" } })
        M.GetPersistentMenuStateTable("accordionState")["gf_auras:auras"] = true
        assert(mw:Select("gf_auras") ~= false) mw:RunTimers()
        local entry = assert(M.cache.gf_auras)
        for pass = 1, 3 do
            local sections = {} for _, section in pairs(entry.sections) do sections[#sections + 1] = section end
            for _, section in ipairs(sections) do
                W.EnsureSectionContent(section)
                if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
            mw:RunTimers()
        end
        local function Owned(id, kind, classification)
            local record = assert(M.RuntimeControlCatalog.Get(id), "positive blacklist control missing: " .. id)
            local w = assert(record.widget)
            local current = w._msuf2RuntimeControlRecord
            assert(current.pageKey == "gf_auras" and current.kind == kind and current.classification == classification,
                "positive blacklist declaration drift: " .. id)
            local parent = w
            while parent and parent ~= entry.wrapper do parent = parent:GetParent() end
            assert(parent == entry.wrapper, "positive blacklist owner escaped current page: " .. id)
            ids[w] = id
            return w
        end
        local preset = Owned("menu2.gf_auras.auras.group-workspace.lane.buff.blacklist.preset-selection", "dropdown", "ephemeral")
        local spell = Owned("menu2.gf_auras.auras.group-workspace.lane.buff.blacklist.spell-selection", "dropdown", "ephemeral")
        local add = Owned("menu2.gf_auras.auras.group-workspace.scope.party.lane.buff.blacklist.add-preset-spell", "button", "action")
        local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
        local function Values(w)
            local values = w.GetValues and w:GetValues() or w.values
            if type(values) == "function" then values = values() end
            return assert(type(values) == "table" and values, "positive blacklist real values missing")
        end
        local labels = { ["1459"] = "Arcane Intellect (#1459)", ["6673"] = "Battle Shout (#6673)" }
        local choices, nativeClicks = 0, 0
        local function NativePick(w, value)
            assert(w:IsEnabled(), "positive blacklist choice disabled: " .. ids[w])
            local item, matches
            matches = 0
            for _, option in ipairs(Values(w)) do
                if option.value == value and not option.disabled and not option.header then item, matches = option, matches + 1 end
            end
            assert(matches == 1 and type(item.text) == "string", "positive blacklist real option missing/ambiguous")
            W.CloseDropdown({ immediate = true })
            w:Click("LeftButton") nativeClicks = nativeClicks + 1 mw:RunTimers()
            local selected, count = nil, 0
            for _, frame in ipairs(mw.world.widgets.frames) do
                if frame._msuf2Owner == w and frame:IsShown() and frame._msuf2Value == value
                    and not frame._msuf2DropdownDisabled then selected, count = frame, count + 1 end
            end
            assert(count == 1 and selected:GetScript("OnClick"), "positive blacklist real popup row missing/ambiguous")
            assert(selected._msuf2Item == item or selected._msuf2Item.text == item.text,
                "positive blacklist popup item differs from provider")
            selected:Click("LeftButton") nativeClicks = nativeClicks + 1 mw:RunTimers()
            assert(Command(w).get() == value and w:GetValue() == value and w:GetText() == item.text
                and w._msuf2Label:GetText() == item.text, "positive blacklist native choice/model/label drift")
            choices = choices + 1
            Add("classic-blacklist:choice:" .. ids[w], value, item.text, Command(w).get(), w:GetValue(), calls)
        end
        local function PurePick(w, value)
            M.ClearHistory() calls = {}
            local before = F.CopySnapshot(env.MSUF_DB)
            NativePick(w, value)
            assert(not next(Diff(before, env.MSUF_DB)) and #calls == 0,
                "positive blacklist ephemeral choice mutated DB/apply")
            assert(not M.Undo() and not M.Redo(), "positive blacklist ephemeral choice created history")
            Add("classic-blacklist:pure:" .. ids[w], value, Diff(before, env.MSUF_DB), calls)
        end
        -- Do not inherit the preceding matrix's BLESSING_BRONZE selection.
        -- Both preset selections and all Spell inputs go through real popup rows.
        PurePick(preset, "BLESSING_BRONZE")
        PurePick(preset, "RAID_BUFFS")
        local curated = assert(env.MSUF_GF_AuraFilter.PUBLIC_AURA_PRESET_SPELLS.RAID_BUFFS)
        assert(curated[1459] == true and curated[6673] == true, "positive blacklist source preset membership drift")
        local values = Values(spell)
        assert(#values == 2, "positive blacklist must expose exactly the two resolved source spells")
        for _, item in ipairs(values) do assert(item.text == labels[item.value], "positive blacklist invented/unresolved Spell option") end
        assert(#model.GroupBlacklistSpellValues("buff", "RAID_BUFFS") == 2, "positive blacklist provider census drift")
        PurePick(spell, "6673")
        PurePick(spell, "1459")
        assert(add:IsEnabled(), "positive blacklist curated Add is disabled")
        M.ClearHistory() calls = {}
        local before = F.CopySnapshot(env.MSUF_DB)
        assert(add:Click("LeftButton") == true, "positive blacklist native curated Add refused")
        nativeClicks = nativeClicks + 1 mw:RunTimers()
        local after = F.CopySnapshot(env.MSUF_DB)
        local list = assert(env.MSUF_DB.gf_party.auras.buff.blacklist)
        assert(list.spells["1459"] == true and list.rankFamilySpellIDs["1459"] == true
            and next(Diff(before, after)), "positive blacklist curated Add did not write actual Classic owner")
        local applied = false
        for _, call in ipairs(calls) do
            if call[1] == "RequestGroup" and call[2] == "party" and call[3] == "auras" then applied = true end
        end
        assert(applied, "positive blacklist curated Add missed focused party Aura apply")
        Add("classic-blacklist:add", Diff(before, after), calls, model.GroupBlacklistEntries("party", "buff"))
        assert(M.Undo(), "positive blacklist curated Add has no Undo") mw:RunTimers()
        assert(not next(Diff(before, env.MSUF_DB)), "positive blacklist Undo did not restore exact DB")
        Add("classic-blacklist:undo", Diff(before, env.MSUF_DB), model.GroupBlacklistEntries("party", "buff"))
        assert(M.Redo(), "positive blacklist curated Add has no Redo") mw:RunTimers()
        assert(not next(Diff(after, env.MSUF_DB)), "positive blacklist Redo did not restore exact DB")
        Add("classic-blacklist:redo", Diff(after, env.MSUF_DB), model.GroupBlacklistEntries("party", "buff"))
        assert(M.Undo(), "positive blacklist cleanup Undo missing") mw:RunTimers()
        assert(not next(Diff(before, env.MSUF_DB)), "positive blacklist cleanup Undo drift")
        PurePick(spell, "6673")
        M.ClearHistory() calls = {} before = F.CopySnapshot(env.MSUF_DB)
        local display = Pack(Command(spell).get(), spell:GetValue(), spell:GetText())
        core.Util.InCombat("PLAYER_REGEN_DISABLED")
        for _, locked in ipairs({ false, true }) do
            env.InCombatLockdown = function() return locked end
            local result = add:Click("LeftButton") nativeClicks = nativeClicks + 1 mw:RunTimers()
            assert(result ~= true and not next(Diff(before, env.MSUF_DB)) and #calls == 0
                and Encode(display, ids) == Encode(Pack(Command(spell).get(), spell:GetValue(), spell:GetText()), ids),
                "positive blacklist curated Add combat-edge/locked refusal drift")
            Add("classic-blacklist:combat", locked, result, Diff(before, env.MSUF_DB), calls, display)
        end
        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
        assert(not M.Undo() and not M.Redo(), "positive blacklist refused Add created history")
        assert(choices == 5 and nativeClicks == 13, "positive blacklist native-input census drift")
        Add("classic-blacklist:coverage", 3, 2, choices, nativeClicks, 1, 2)
        print("Classic blacklist positive " .. flavor .. ": 3 controls/2 real Spell options/5 native choices/13 Clicks/1 curated write/2 combat refusals")
        return rows, choices
    end
    local scopes = { "party", "raid" }
    if core.Client.SupportsGroupKind("mythicraid") then scopes[#scopes + 1] = "mythicraid" end
    if mode == "push" then scopes = { arg[5] or "party" } end
    local lanes = mode == "push" and { "buff" } or { "buff", "debuff", "externals" }
    local total, mutating, missingCount, actionCount = 0, 0, 0, 0
    local spellScopes = {}
    local tools = mode == "push" and { arg[6] or "style" } or { "style", "behavior", "filters", "blacklist" }
    for _, scope in ipairs(scopes) do for _, lane in ipairs(lanes) do for _, tool in ipairs(tools) do
        if lane ~= "externals" or tool == "style" or tool == "behavior" then
        M.GroupPage.Conf(scope).enabled = true
        M.SetMenuStateValue("gfScope", scope)
        M.SetMenuStateValue("gfAuraLaneSelection", { [scope] = lane })
        M.SetMenuStateValue("gfAuraToolSelection", { [scope] = { [lane] = tool } })
        local accordion = M.GetPersistentMenuStateTable("accordionState")
        accordion["gf_auras:auras"] = true
        assert(mw:Select("gf_auras") ~= false) mw:RunTimers()
        local entry = assert(M.cache.gf_auras)
        for pass = 1, 3 do
            local sections = {} for _, section in pairs(entry.sections) do sections[#sections + 1] = section end
            for _, section in ipairs(sections) do
                M.Widgets.EnsureSectionContent(section)
                if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
            mw:RunTimers()
        end
        if tool == "blacklist" then
            local model = core.MSUF_Auras3.MenuModel
            model.AddGroupBlacklistSpell(scope, lane, "774", true)
            model.AddGroupBlacklistSpell(scope, lane, "17", true)
            M.Refresh() mw:RunTimers()
        end
        local view = scope .. "/" .. lane .. "/" .. tool
        local function Within(widget)
            while widget do
                if widget == entry.wrapper then return true end
                widget = widget.parent
            end
            return false
        end
        local controls, actions, inventory, menuOwners = {}, {}, {}, {}
        local function AccordionOwner(widget)
            local parent = widget:GetParent()
            local owner = parent and parent._msuf2CollapsibleEntry
            if owner and owner.header == widget then return owner end
        end
        local function Command(w)
            return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command
        end
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local w = M.RuntimeControlCatalog.Get(record.controlId).widget
            local id, kind = record.controlId, record.kind
            local relevant = id:find(".auras.group-style.", 1, true)
                or id:find(".auras.group-workspace.lane.", 1, true)
                or id:find(".auras.group-workspace.scope.", 1, true)
            local ordinary = kind == "toggle" or kind == "slider" or kind == "dropdown"
                or kind == "textinput" or kind == "segment" or kind == "button"
            if record.pageKey == "gf_auras" and ordinary and w and Within(w) then
                ids[w] = id
                inventory[#inventory + 1] = w
                local command, accordionOwner = Command(w), AccordionOwner(w)
                if accordionOwner then
                    -- Search forwards identity, not meta.command; this is the
                    -- PageBuilder's native disclosure, never a bound checkbox.
                    assert(kind == "toggle" and record.classification == "ephemeral"
                        and accordionOwner.body and w:GetScript("OnClick"), "accordion native owner missing: " .. id)
                    menuOwners[w] = accordionOwner
                    actions[#actions + 1] = w
                elseif kind == "segment" then
                    assert(type(w.buttons) == "table" and #w.buttons > 0 and type(w.GetValue) == "function",
                        "selector native owner missing: " .. id)
                    for _, button in ipairs(w.buttons) do
                        assert(button:GetScript("OnClick"), "selector native button missing: " .. id)
                    end
                    actions[#actions + 1] = w
                elseif kind == "button" then
                    assert(w:GetScript("OnClick"), "ordinary action native Click missing: " .. id)
                    actions[#actions + 1] = w
                elseif command and command.get and command.set then controls[#controls + 1] = w
                else error("ordinary input has no real owner: " .. id) end
                local ownButton = kind == "button" and relevant
                local ownInput = relevant and kind ~= "button" and kind ~= "segment"
                    and not id:find(".tool-selector", 1, true) and not id:match("%.enabled$")
                if not original and (ownButton or ownInput) then
                    local spec = assert(w._msuf2ControlSchema, "ordinary declaration missing: " .. id)
                    local domain = record.classification == "ephemeral" and "menuState" or "auras"
                    assert(spec.id == id and spec.kind == record.kind and spec.scope == "groups"
                        and spec.applyDomain == domain, "typed declaration drift: " .. id .. " [" .. tostring(spec.kind) .. "/"
                            .. tostring(spec.scope) .. "/" .. tostring(spec.applyDomain) .. "/expected:" .. domain .. "]")
                    if ownButton then
                        assert(spec.owner == w and spec.action, "ordinary action lost its native owner: " .. id)
                    else
                        assert(spec.get and spec.set and spec.defaultSource, "live accessors missing: " .. id)
                        if record.kind == "slider" then assert(spec.range and spec.range[3] == 1, "slider range missing") end
                        if record.kind == "textinput" then assert(spec.textAdapter == true, "text adapter missing") end
                    end
                end
            end
        end
        table.sort(inventory, function(a, b) return ids[a] < ids[b] end)
        table.sort(actions, function(a, b) return ids[a] < ids[b] end)
        table.sort(controls, function(a, b) return ids[a] < ids[b] end)
        assert(#controls > 0, view .. ": actual ordinary inventory missing")
        print(view .. ": " .. #controls .. " controls / " .. #actions .. " native actions / " .. #inventory .. " inventoried")
        total = total + #controls
        local function Display(w)
            local owner = menuOwners[w]
            if owner then
                return Pack("accordion", owner.open, w:IsShown(), owner.outer:IsShown(), owner.body:IsShown(),
                    owner.body:GetAlpha(), owner.outer:GetHeight(), owner.body:GetHeight(), owner.arrow.rotation,
                    owner.label:GetText(), owner.hint:GetText(), owner.hint:IsShown(), owner._msuf2MotionActive,
                    M.GetPersistentMenuStateTable("accordionState")[owner.stateKey])
            end
            local kind = w._msuf2RuntimeControlRecord.kind
            local value
            if kind == "toggle" then value = w:GetChecked()
            elseif kind == "slider" or kind == "dropdown" or kind == "segment" then value = w:GetValue()
            elseif kind == "textinput" then value = w:GetText() end
            local choices = {}
            for _, button in ipairs(w.buttons or {}) do
                choices[#choices + 1] = { button._msuf2Value, button._msuf2Active, button:GetChecked(), button:GetText() }
            end
            return Pack(value, w:GetText(), w._msuf2Label and w._msuf2Label:GetText(), choices,
                w.editBox and w.editBox:GetText(), w._msuf2Title and w._msuf2Title:GetText())
        end
        local function Value(w)
            local command = Command(w)
            return { model = command and command.get and Pack(command.get()) or {}, display = Display(w) }
        end
        local function SettleAccordion(owner)
            -- Drive only the native finite layout motion, bounded to four seconds.
            local driver = owner._msuf2AccordionMotion
            for _ = 1, 120 do
                if not (driver and driver:GetScript("OnUpdate")) then break end
                MenuWorld.FireScript(driver, "OnUpdate", 1 / 30)
            end
            mw:RunTimers()
            assert(not owner._msuf2MotionActive, "native accordion motion did not settle: " .. owner.sectionId)
            assert(owner.body:IsShown() == owner.open, "native accordion body visibility drift: " .. owner.sectionId)
        end
        local function Input(w, value)
            if not w:IsEnabled() then return end
            local kind, result = w._msuf2RuntimeControlRecord.kind
            local accordionOwner = menuOwners[w]
            if accordionOwner then
                result = w:Click("LeftButton")
                SettleAccordion(accordionOwner)
                assert(accordionOwner.open == value, "native accordion Click did not select requested state: " .. ids[w])
            elseif kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
            elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
            elseif kind == "textinput" then
                w:SetText(value) MenuWorld.FireScript(w, "OnTextChanged", true)
                MenuWorld.FireScript(w, "OnEnterPressed")
            elseif kind == "button" then result = w:Click("LeftButton")
            elseif kind == "segment" then
                local found
                for _, button in ipairs(w.buttons or {}) do
                    if button._msuf2Value == value then button:Click("LeftButton") found = true break end
                end
                assert(found, "native selector choice missing: " .. ids[w])
            else w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value) end
            mw:RunTimers()
            return result
        end
        local function Alternate(w)
            local accordionOwner = menuOwners[w]
            if accordionOwner then return not accordionOwner.open end
            local kind, current = w._msuf2RuntimeControlRecord.kind, Value(w).model[1]
            if kind == "toggle" then return not current end
            if kind == "slider" then local lo, hi = w:GetMinMaxValues() return current ~= lo and lo or hi end
            if kind == "textinput" then return current ~= "774" and "774" or "17" end
            if kind == "segment" then current = w:GetValue() end
            if kind == "button" then return true end
            local values = w.GetValues and w:GetValues() or w.values if type(values) == "function" then values = values() end
            for _, item in ipairs(values or {}) do
                if item.value ~= nil and item.value ~= current and not item.disabled then return item.value end
            end
            if not w:IsEnabled() then return current end
            -- Classic's real preset owner excludes spells without a resolved name.
            -- This exact empty-list state is not an alternate selection.
            if core.Client.IsClassic == true and tool == "blacklist" and kind == "dropdown"
                and (lane == "buff" or lane == "debuff")
                and ids[w] == "menu2.gf_auras.auras.group-workspace.lane." .. lane .. ".blacklist.spell-selection"
                and type(values) == "table" and #values == 0 then
                assert(M.CLASSIC_AURA_FILTERS_REDUCED == true and type(w.values) == "function",
                    "empty Blacklist Spell must retain its real Classic values provider")
                local preset, presetOwners = nil, 0
                for _, input in ipairs(controls) do
                    if ids[input] == "menu2.gf_auras.auras.group-workspace.lane." .. lane .. ".blacklist.preset-selection" then
                        preset, presetOwners = Command(input).get(), presetOwners + 1
                    end
                end
                assert(presetOwners == 1 and preset ~= nil, "empty Blacklist Spell has no exact preset owner")
                local curated = assert(env.MSUF_GF_AuraFilter.PUBLIC_AURA_PRESET_SPELLS[preset],
                    "empty Blacklist Spell must still reference a real curated preset")
                local rawCount = 0 for _ in pairs(curated) do rawCount = rawCount + 1 end
                local spellAPI = env.C_Spell
                assert(rawCount > 0 and type(env.GetSpellInfo) ~= "function"
                    and (type(spellAPI) ~= "table" or type(spellAPI.GetSpellInfo) ~= "function"),
                    "empty Blacklist Spell is specific to this fixture's absent name resolvers")
                assert(#core.MSUF_Auras3.MenuModel.GroupBlacklistSpellValues(lane, preset) == 0
                    and current == nil and w:GetValue() == nil
                    and w._msuf2RuntimeControlRecord.classification == "ephemeral",
                    "empty Blacklist Spell provider/model/native census drift")
                return nil, { choices = 0, preset = preset, rawPresetSpells = rawCount }
            end
            error("enabled dropdown has no real alternate: " .. ids[w])
        end
        -- Canonical profile keys are independent of the candidate schema metadata.
        local fields = {}
        for key in ([[iconZoom showTooltip showCooldown showCooldownSwipe cooldownSize cooldownAnchor cooldownX cooldownY
            cooldownDecimalSeconds showDurationBar durationBarHeight durationBarDisplay durationBarPosition durationBarDirection
            showStacks stackSize stackAnchor stackX stackY sortMethod filterToken]]):gmatch("%S+") do fields[key:lower()] = key end
        fields["cooldown-swipe-direction"], fields["sort-direction"] = "cooldownSwipeReverse", "sortReverse"
        fields["dispel-border-mode"] = "dispelBorderMode"
        -- SpellSection's existing rows are an unchanged sibling on gf_auras.
        -- Pin their actual storage keys independently of declaration metadata.
        local spellFields = {
            enabled = { "root", "enabled" }, spec = { "root", "spec" },
            icon_zoom = { "root", "iconZoom" }, icon_scale = { "root", "iconScale" },
            ["multi_spec.tracked"] = { "multi", "tracked" },
            ["selected.layer"] = { "selected", "layer" }, ["selected.enabled"] = { "selected", "enabled" },
            ["selected.spell_ids"] = { "selected", "spells" }, ["selected.only_mine"] = { "selected", "onlyOwn" },
            ["selected.auto_blacklist"] = { "selected", "autoBlacklist" },
            ["selected.placed.type"] = { "placed", "type" }, ["selected.frame.type"] = { "frame", "type" },
        }
        for _, family in ipairs({
            { "style", [[alpha showTooltip showCooldownText showCooldownSwipe cooldownSize cooldownAnchor cooldownX cooldownY
                cooldownSwipeReverse cooldownDecimalSeconds showStacks stackSize stackAnchor stackX stackY showDurationBar
                durationBarHeight durationBarDisplay durationBarPosition durationBarDirection]] },
            { "placed", "anchor size barWidth growth iconEffect barSmoothFill barShowTimer barTimerAnchor barTimerX barTimerY" },
            { "frame", "priority alpha thickness layer" },
        }) do
            for field in family[2]:gmatch("%S+") do spellFields[family[1] .. "." .. field:lower()] = { family[1], field } end
        end
        local function IsSpell(w) return ids[w]:find(".group.spell.", 1, true) ~= nil end
        local function PrepareSpell(w)
            local GP = M.GroupPage
            local si = GP.SpellIndicators(scope)
            si.enabled = true
            if si.spec == nil or si.spec == "auto" or si.spec == "multi" then
                for _, item in ipairs(GP.SpellSpecValues()) do
                    if item.value and item.value ~= "auto" and item.value ~= "multi" then
                        si.spec = item.value
                        if GP.CurrentSpellAura(scope) ~= "" then break end
                    end
                end
            end
            local id = ids[w]
            if id:find(".multi_spec.", 1, true) then
                si.spec = "multi"
                for _, item in ipairs(GP.SpellTrackedSpecValues()) do
                    if item.value and item.value ~= "" and not GP.IsAllSpecsSpellSpec(item.value) then
                        M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
                        M.gfSpellMultiSpecSelection[scope] = item.value
                        if GP.CurrentSpellAura(scope) ~= "" then break end
                    end
                end
            end
            if id:find(".selected.auto_blacklist", 1, true) then GP.AuraGroup(scope, "externals").autoBlacklistBuffs = false end
            local selected = assert(GP.CurrentSpellConfig(scope, true), "native selected Spell record unavailable: " .. id)
            -- Seed genuine existing records before deleting one field or record.
            -- Values follow the real rows/defaults, never candidate declarations.
            for key, value in pairs({ layer = 0, enabled = true, spells = "774, 17", onlyOwn = true, autoBlacklist = false }) do
                if selected[key] == nil then selected[key] = value end
            end
            selected.enabled = true
            if id:find(".selected.spell_ids", 1, true) then selected.custom = true end
            local placed = assert(GP.PlacedConfig(scope, true))
            for key, value in pairs({ anchor = "TOPLEFT", size = 18, barWidth = 42, growth = "RIGHTDOWN",
                iconEffect = "none", barSmoothFill = false, barTimerAnchor = "CENTER", barTimerX = 0, barTimerY = 0 }) do
                if placed[key] == nil then placed[key] = value end
            end
            placed.type = id:find(".placed.bar", 1, true) and "bar" or "icon"
            placed.barShowTimer = true
            local frame = assert(GP.FrameEffectConfig(scope, true))
            for key, value in pairs({ priority = 5, alpha = 0.8, thickness = 2, layer = 0 }) do
                if frame[key] == nil then frame[key] = value end
            end
            frame.type = "healthtint"
            frame.color = frame.color or { 0.4, 1, 0.4, 0.8 }
            if frame.color[4] == nil then frame.color[4] = 0.8 end
            si.style.showCooldownText, si.style.showCooldownSwipe = true, true
            si.style.showStacks, si.style.showDurationBar = true, true
        end
        local function SpellTarget(missing)
            local GP = M.GroupPage
            local si, family = GP.SpellIndicators(scope), missing[3]
            if family == "root" then return si, missing[2] end
            if family == "style" then return si.style, missing[2] end
            if family == "selectedRecord" then
                local selected, specKey, auraName = GP.CurrentSpellConfig(scope, true)
                assert(selected and specKey and auraName ~= "", "native selected-record target unavailable")
                assert(si.specs[specKey][auraName] == selected, "selected-record owner drift")
                return si.specs[specKey], auraName
            end
            if family == "selected" then return GP.CurrentSpellConfig(scope, true), missing[2] end
            if family == "placed" then return GP.PlacedConfig(scope, true), missing[2] end
            if family == "frame" then return GP.FrameEffectConfig(scope, true), missing[2] end
            if family == "frameColor" then
                local frame = GP.FrameEffectConfig(scope, true)
                if frame then frame.alpha = nil return frame.color, missing[2] end
            end
            if family == "multi" then
                si.multiSpecs = si.multiSpecs or {}
                local key = GP.CurrentSpellMultiSpec(scope)
                assert(key ~= "" and not GP.IsAllSpecsSpellSpec(key), "native tracked-spec target unavailable")
                si.multiSpecs[key] = true
                return si.multiSpecs, key
            end
            error("unknown actual Spell target: " .. tostring(family))
        end
        local function MissingCases(w)
            local id, cases = ids[w], { false }
            if w._msuf2RuntimeControlRecord.classification == "ephemeral" then return cases end
            local spell = id:match("^menu2%.gf_auras%.group%.spell%.(.+)$")
            if spell then
                local field = assert(spellFields[spell], "unmapped ordinary Spell key: " .. id)
                cases[#cases + 1] = { "spell", field[2], field[1] }
                if field[1] == "placed" or field[1] == "frame" then
                    cases[#cases + 1] = { "spell", field[1], "selected" }
                end
                if field[1] == "selected" or field[1] == "placed" or field[1] == "frame" then
                    cases[#cases + 1] = { "spell", "record", "selectedRecord" }
                end
                if spell == "frame.alpha" then cases[#cases + 1] = { "spell", 4, "frameColor" } end
                return cases
            end
            local key = id:match("%.group%-style%.lane%.[^.]+%.([^.]+)$")
            if key then
                local field = assert(fields[key], "missing absent-key contract: " .. id)
                cases[#cases + 1] = { "group", field }
                if key == "showtooltip" then cases[#cases + 1] = { "root", "showTooltip" } end
                if key == "dispel-border-mode" then cases[#cases + 1] = { "group", "showDispelBorder" } end
            elseif id:find(".group-style.root.dynamicscale", 1, true) then cases[#cases + 1] = { "root", "dynamicScale" }
            elseif id:find(".group-workspace.root.enabled", 1, true) then cases[#cases + 1] = { "root", "enabled", scope }
            elseif id:find(".filters.", 1, true) then
                if id:find(".hide-permanent", 1, true) then cases[#cases + 1] = { "blacklist", "hidePermanent" }
                elseif id:find(".max-duration", 1, true) then cases[#cases + 1] = { "blacklist", "maxDuration" }
                else cases[#cases + 1] = { "group", "filterToken" } end
            else error("ordinary setting lacks independent absent-key case: " .. id) end
            return cases
        end
        -- Spell providers use CurrentScope/spec/aura, independently of Aura lane/tool.
        -- Every view proves the complete catalog and replays both native pickers.
        -- Only repeated setting matrices share their first view within this scope.
        local expectedSpell = { selected_aura = "ephemeral", ["multi_spec.selector"] = "ephemeral" }
        for key in pairs(spellFields) do expectedSpell[key] = "setting" end
        local spellCatalog, spellCount, pickerCount, spellNilCount = {}, 0, 0, 0
        for _, widget in ipairs(controls) do
            local cases = MissingCases(widget)
            if IsSpell(widget) then
                local id, record = ids[widget], widget._msuf2RuntimeControlRecord
                local suffix = id:match("^menu2%.gf_auras%.group%.spell%.(.+)$")
                assert(expectedSpell[suffix] == record.classification and not spellCatalog[id],
                    "unexpected/duplicate Spell ordinary identity: " .. view .. ":" .. id)
                local plan = { kind = record.kind, classification = record.classification, page = record.pageKey,
                    key = widget._msuf2ControlSchema and widget._msuf2ControlSchema.key, cases = { default = true, edge = true } }
                for _, missing in ipairs(cases) do if missing then
                    plan.cases["default:nil:" .. table.concat(missing, ".")] = true
                    spellNilCount = spellNilCount + 1
                end end
                spellCatalog[id], expectedSpell[suffix] = plan, nil
                if record.classification == "setting" then spellCount = spellCount + 1 else pickerCount = pickerCount + 1 end
            end
        end
        assert(not next(expectedSpell) and spellCount == 46 and pickerCount == 2 and spellNilCount == 84,
            "complete Spell ordinary/record-nil inventory drift: " .. view)
        assert(M.GroupPage.CurrentScope() == scope, "actual Spell scope drift: " .. view)
        local spellScope = spellScopes[scope]
        if not spellScope then
            spellScope = { catalog = spellCatalog, views = 0, exercised = {}, matrixView = not narrow and view or nil }
            spellScopes[scope] = spellScope
        end
        assert(Encode(spellScope.catalog, ids) == Encode(spellCatalog, ids), "Spell catalog differs across Aura views: " .. view)
        spellScope.views = spellScope.views + 1
        local matrixControls = {}
        for _, widget in ipairs(controls) do
            if not narrow and (not IsSpell(widget) or spellCatalog[ids[widget]].classification == "ephemeral"
                or spellScope.matrixView == view) then matrixControls[#matrixControls + 1] = widget end
        end
        local function AssertNativePrimary(widget, tag)
            local model = Command(widget).get()
            local expected = model
            local kind = widget._msuf2RuntimeControlRecord.kind
            -- BindBool/BindNumber/TextInput adapters apply these exact native conversions.
            if kind == "toggle" then expected = expected and true or false
            elseif kind == "slider" then expected = tonumber(expected) or 0
            elseif kind == "textinput" then expected = tostring(expected or "") end
            local actual, details = Display(widget), ""
            if Encode(actual[1], ids) ~= Encode(expected, ids) then
                -- Failure-only evidence: never repaint, call setters or widen equality.
                local native = { display = actual, shown = widget:IsShown(), enabled = widget:IsEnabled(),
                    refreshing = widget._msuf2Refreshing, editing = widget._msuf2Editing }
                if kind == "slider" then
                    native.range, native.step = Pack(widget:GetMinMaxValues()), widget._msuf2Step
                    native.storedStep, native.obeyStepOnDrag = widget.valueStep, widget.obeyStepOnDrag
                end
                if ids[widget] == "menu2.gf_auras.group.spell.frame.alpha" then
                    local selected, specKey, auraName = M.GroupPage.CurrentSpellConfig(scope, false)
                    native.selected, native.spec, native.aura = Pack(selected), specKey, auraName
                    native.frame = Pack(type(selected) == "table" and rawget(selected, "frame") or nil)
                end
                details = ":view=" .. view .. ":scope=" .. scope .. ":model=" .. Encode(model, ids)
                    .. ":expected=" .. Encode(expected, ids)
                    .. ":native=" .. Encode(native, ids)
            end
            assert(Encode(actual[1], ids) == Encode(expected, ids),
                "refresh display/model drift: " .. ids[widget] .. ":" .. tag .. details)
        end
        local function SpellDisplays(tag)
            local values = {}
            for _, widget in ipairs(controls) do if IsSpell(widget) then
                AssertNativePrimary(widget, tag)
                values[#values + 1] = { ids[widget], Display(widget), widget:IsShown(), widget:IsEnabled() }
            end end
            return values
        end
        local function ReturnView()
            M.SetMenuStateValue("gfScope", scope)
            M.SetMenuStateValue("gfAuraLaneSelection", { [scope] = lane })
            M.SetMenuStateValue("gfAuraToolSelection", { [scope] = { [lane] = tool } })
            assert(mw:Select("gf_auras") ~= false) mw:RunTimers()
            for _, section in pairs(entry.sections) do
                if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
            mw:RunTimers()
        end
        local defaults = F.CopySnapshot(env.MSUF_DB)
        local function Setup(state, missing, widget)
            Restore(env.MSUF_DB, defaults)
            for _, section in pairs(entry.sections) do
                if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
            M.GroupPage.Conf(scope).enabled = true
            local config = M.GroupPage.AurasRoot(scope, true)
            config.enabled = true
            local group = M.GroupPage.AuraGroup(scope, lane)
            group.enabled = true
            group.unknownSchemaExtension = { enabled = false, amount = 0 }
            if state == "edge" then
                group.showTooltip, group.showCooldown, group.showCooldownSwipe, group.showStacks = nil, false, true, false
                config.showTooltip, config.dynamicScale = false, false
                group.cooldownX, group.cooldownY, group.cooldownDecimalSeconds = 0, 0, 0
                group.iconZoom, group.showDurationBar, group.durationBarHeight = 100, true, 0
                group.sortMethod, group.sortReverse, group.filterToken = "UNKNOWN", true, "Player"
                group.durationBarDisplay, group.durationBarPosition = "OVERLAY", "TOP"
            end
            if widget and IsSpell(widget) then PrepareSpell(widget) end
            if widget and ids[widget]:find(".filters.native.", 1, true) then
                -- All cannot be unchecked to no filter; begin on another real choice.
                for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
                    M.GroupPage.AuraGroup(kind, lane).filterToken = ids[widget]:match("%.native%.all$") and "Player" or "ALL"
                end
            end
            local target, targetKey, absent, missingEffects
            if missing and missing[1] == "spell" then
                target, targetKey = SpellTarget(missing)
                assert(target and targetKey ~= nil, "prepared native Spell record missing: " .. ids[widget])
                assert(rawget(target, targetKey) ~= nil, "Spell nil case did not remove an existing key: " .. ids[widget])
                target[targetKey] = nil
                assert(rawget(target, targetKey) == nil, "Spell key not absent before native refresh: " .. ids[widget])
                absent = F.CopySnapshot(env.MSUF_DB)
            elseif missing then
                -- Style/filter readers canonicalize Raid/Mythic to Raid; the
                -- retained page root-enable owner reads the actual selected scope.
                local readScope = missing[3] or (scope == "party" and "party" or "raid")
                local readRoot = M.GroupPage.AurasRoot(readScope, true)
                local readGroup = M.GroupPage.AuraGroup(readScope, lane)
                target = missing[1] == "root" and readRoot or readGroup
                if missing[1] == "root" and missing[2] == "showTooltip" then readGroup.showTooltip = nil end
                if missing[1] == "blacklist" then
                    readGroup.blacklist = readGroup.blacklist or {}
                    target = readGroup.blacklist
                end
                target[missing[2]] = nil
            end
            M.Refresh() mw:RunTimers() M.ClearHistory()
            if missing and missing[1] == "spell" then
                -- SpellIndicators/EnsureSpellIndicatorStyle deliberately materialize
                -- native defaults while reading. Preserve and compare those writes.
                missingEffects = { missing[3], targetKey, rawget(target, targetKey), Diff(absent, env.MSUF_DB),
                    M.GroupPage.EffectiveSpellSpec(scope), M.GroupPage.CurrentSpellAura(scope) }
            elseif missing then assert(target[missing[2]] == nil, "refresh filled absent key: " .. missing[2]) end
            for _, input in ipairs(controls) do
                if input._msuf2RuntimeControlRecord.classification ~= "ephemeral" then
                    AssertNativePrimary(input, "setup:" .. state .. ":" .. (widget and ids[widget] or "whole-view")
                        .. ":" .. (missing and table.concat(missing, ".") or "present"))
                end
            end
            return missingEffects
        end
        local function Observe(tag)
            for _, w in ipairs(inventory) do
                local points = {} for i = 1, w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
                Add(view .. ":" .. tag .. ":" .. ids[w], w._msuf2RuntimeControlRecord, w._msuf2SearchMeta,
                    Value(w), w.width, w.height, points, w:IsShown(), w:IsEnabled())
            end
        end
        Observe("factory")
        for _, state in ipairs({ "default", "edge" }) do
            Setup(state) Observe(state)
            for _, w in ipairs(matrixControls) do
                for _, missing in ipairs(state == "default" and MissingCases(w) or { false }) do
                    local missingEffects = Setup(state, missing, w)
                    local value, noAlternative = Alternate(w)
                    local before = F.CopySnapshot(env.MSUF_DB)
                    local case = state
                    if missing then
                        missingCount = missingCount + 1
                        case = state .. ":nil:" .. table.concat(missing, ".")
                        Add(view .. ":" .. case .. ":refresh:" .. ids[w], Value(w), w:IsShown(), w:IsEnabled(), missingEffects)
                    end
                    calls = {}
                    local priorValue, priorEnabled = Value(w), w:IsEnabled()
                    if noAlternative then
                        -- Exercise the real empty-list opening and nil callback;
                        -- no invented option and no omitted matrix input.
                        w:Click("LeftButton") mw:RunTimers()
                        for _, frame in ipairs(mw.world.widgets.frames) do
                            assert(not (frame._msuf2Owner == w and frame:IsShown()),
                                "empty Blacklist Spell opened a selectable native row")
                        end
                    end
                    Input(w, value)
                    local after = F.CopySnapshot(env.MSUF_DB)
                    if noAlternative then
                        assert(not next(Diff(before, after)) and #calls == 0
                            and Encode(priorValue, ids) == Encode(Value(w), ids),
                            "empty Blacklist Spell input mutated DB/apply/model/display")
                        Add(view .. ":" .. case .. ":no-alternative:" .. ids[w], noAlternative, priorValue, Value(w), calls)
                    end
                    if next(Diff(before, after)) then mutating = mutating + 1 end
                    if not priorEnabled then assert(not next(Diff(before, after)), "disabled input changed profile: " .. ids[w]) end
                    Add(view .. ":" .. case .. ":input:" .. ids[w], value, Diff(before, after), Value(w), calls)
                    if IsSpell(w) then
                        AssertNativePrimary(w, "input")
                        -- Its setter refreshes its own section. Whole-page refresh
                        -- then makes sibling style gates/default reads canonical.
                        M.Refresh() mw:RunTimers()
                        Add(view .. ":" .. case .. ":spell-refresh:" .. ids[w], Diff(after, env.MSUF_DB), SpellDisplays("input-refresh"))
                        after = F.CopySnapshot(env.MSUF_DB)
                    end
                    local undo = M.Undo() mw:RunTimers() Add(view .. ":" .. case .. ":undo:" .. ids[w], undo, Diff(before, env.MSUF_DB), Value(w))
                    if noAlternative then assert(not undo, "empty Blacklist Spell input created Undo history") end
                    if IsSpell(w) then Add(view .. ":" .. case .. ":spell-undo:" .. ids[w], SpellDisplays("undo")) end
                    local redo = M.Redo() mw:RunTimers() Add(view .. ":" .. case .. ":redo:" .. ids[w], redo, Diff(after, env.MSUF_DB), Value(w))
                    if noAlternative then assert(not redo, "empty Blacklist Spell input created Redo history") end
                    if IsSpell(w) then Add(view .. ":" .. case .. ":spell-redo:" .. ids[w], SpellDisplays("redo")) end
                    if mode ~= "push" then
                        Setup(state, missing, w) before = F.CopySnapshot(env.MSUF_DB) calls = {}
                        local displayBefore = Encode(Display(w), ids)
                        core.Util.InCombat("PLAYER_REGEN_DISABLED") env.InCombatLockdown = function() return false end
                        Input(w, value) Add(view .. ":" .. case .. ":combat-edge:" .. ids[w], Diff(before, env.MSUF_DB), calls, Value(w))
                        env.InCombatLockdown = function() return true end Input(w, value)
                        Add(view .. ":" .. case .. ":combat:" .. ids[w], Diff(before, env.MSUF_DB), Value(w))
                        if IsSpell(w) then AssertNativePrimary(w, "combat-refusal") end
                        if w._msuf2RuntimeControlRecord.classification ~= "ephemeral" then
                            assert(Encode(Display(w), ids) == displayBefore, "combat display was not restored: " .. ids[w])
                        end
                        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                        if IsSpell(w) then
                            M.Refresh() mw:RunTimers()
                            Add(view .. ":" .. case .. ":spell-combat-refresh:" .. ids[w], Diff(before, env.MSUF_DB), SpellDisplays("combat-refresh"))
                        end
                    end
                    if IsSpell(w) then
                        local seen = spellScope.exercised[ids[w]] or { cases = {}, enabledStates = {} }
                        seen.cases[case] = (seen.cases[case] or 0) + 1
                        local limit = spellCatalog[ids[w]].classification == "setting" and 1 or (mode == "push" and 1 or 10)
                        assert(seen.cases[case] <= limit, "Spell matrix case repeated within scope: " .. scope .. ":" .. ids[w] .. ":" .. case)
                        if priorEnabled then
                            seen.enabledStates[state] = seen.enabledStates[state] or {}
                            seen.enabledStates[state][view] = true
                        end
                        spellScope.exercised[ids[w]] = seen
                    end
                end
            end
        end
        for _, w in ipairs(matrixControls) do if w._msuf2RuntimeControlRecord.kind == "slider" then
            Setup("default", false, w) calls = {} local before = F.CopySnapshot(env.MSUF_DB)
            w._msuf2SliderActive = true Input(w, Alternate(w))
            Add(view .. ":drag:" .. ids[w], Diff(before, env.MSUF_DB), calls)
            w._msuf2SliderActive = nil MenuWorld.FireScript(w, "OnMouseUp", "LeftButton") mw:RunTimers()
            Add(view .. ":release:" .. ids[w], Diff(before, env.MSUF_DB), calls)
            MenuWorld.FireScript(w, "OnHide") MenuWorld.FireScript(w, "OnShow") mw:RunTimers()
            Add(view .. ":hide-show:" .. ids[w], calls)
            if IsSpell(w) then
                local seen = assert(spellScope.exercised[ids[w]], "Spell drag has no input evidence: " .. ids[w])
                assert(not seen.drag, "Spell drag repeated within scope: " .. scope .. ":" .. ids[w])
                seen.drag = true
            end
        end end
        local function Contents(tag)
            for i, widget in ipairs(mw.world.widgets.frames) do
                if Within(widget) then
                    Add(view .. ":" .. tag .. ":content", i, widget.text, widget:GetText(), widget._spellID, widget:IsShown())
                    for j, region in ipairs(widget.regions or {}) do
                        Add(view .. ":" .. tag .. ":text", i, j, region.text, region:GetText(), region:IsShown())
                    end
                end
            end
        end
        if tool == "blacklist" then
            for _, w in ipairs(controls) do if ids[w]:match("%.search$") then
                for _, query in ipairs({ "", "774", "no-such-blocked-spell", "" }) do
                    Input(w, query)
                    Add(view .. ":blacklist-search", query, Value(w))
                    Contents("blacklist-search:" .. query)
                end
            end end
        end
        if not narrow then
            local actionPlan, actionEvidence = {}, {}
            for _, widget in ipairs(actions) do
                assert(not actionPlan[ids[widget]], "duplicate ordinary action identity: " .. ids[widget])
                actionPlan[ids[widget]] = true
            end
            for _, state in ipairs({ "default", "edge" }) do
            for _, w in ipairs(actions) do
                local seen = { refresh = {} }
                actionEvidence[ids[w]] = actionEvidence[ids[w]] or {}
                assert(not actionEvidence[ids[w]][state], "ordinary action state repeated: " .. ids[w] .. ":" .. state)
                actionEvidence[ids[w]][state] = seen
                local function RefreshAction(phase)
                    local beforeRefresh = F.CopySnapshot(env.MSUF_DB)
                    M.Refresh() mw:RunTimers()
                    Add(view .. ":action-refresh:" .. state .. ":" .. ids[w], phase, Diff(beforeRefresh, env.MSUF_DB),
                        Value(w), w:IsShown(), w:IsEnabled(), calls, M.activeKey)
                    seen.refresh[phase] = true
                end
                local function EffectivelyShown(widget)
                    while widget do if not widget:IsShown() then return false end widget = widget:GetParent() end
                    return true
                end
                local function PreparePickerOpener()
                    local selectedOpener = ids[w] == "menu2.gf_auras.group.spell.selected.color"
                    if (ids[w] ~= "menu2.gf_auras.group.spell.frame.color" and not selectedOpener) or not w:IsEnabled() then return end
                    -- Open-only shortcuts persist picker preferences, not a color edit.
                    -- Cover that real cold path before the unchanged action/history baseline.
                    local before, prior = F.CopySnapshot(env.MSUF_DB), Value(w)
                    local cold = rawget(before, "menu2ColorPicker") == nil
                    local color
                    if selectedOpener then
                        local cfg, specKey, auraName = M.GroupPage.CurrentSpellConfig(scope, false)
                        assert(type(cfg) == "table", "selected picker has no prepared native spell record")
                        assert(w._msuf2ContextColorOptions.historySource == "menu:group-spell-indicator-color",
                            "selected picker history identity drift")
                        -- Match the real selected owner: stored color, trackable color, WHITE_RGB.
                        local rgb = type(cfg.color) == "table" and cfg.color
                        if not rgb then
                            local gf = M.GroupPage.GF()
                            local runtime = gf and gf.SpellIndicators
                            local trackable = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
                            for i = 1, type(trackable) == "table" and #trackable or 0 do
                                if trackable[i] and trackable[i].name == auraName then rgb = trackable[i].color break end
                            end
                        end
                        rgb = rgb or { 1, 1, 1 }
                        -- ContextColorVirtualOwner:GetRGB applies the same numeric channel fallback.
                        color = { tonumber(rgb[1]) or 1, tonumber(rgb[2]) or 1, tonumber(rgb[3]) or 1 }
                    else
                        color = F.CopySnapshot(assert(M.GroupPage.FrameEffectConfig(scope, false)).color)
                    end
                    assert(EffectivelyShown(w) and w._msuf2SkipHistoryCheckpoint == true,
                        "picker opener must retain its visible native/history owner")
                    Input(w, true)
                    local panel, matches = nil, 0
                    for _, frame in ipairs(mw.world.widgets.frames) do
                        if frame.colorSelect and frame.owner and frame.blocker and frame:IsShown() then
                            panel, matches = frame, matches + 1
                        end
                    end
                    assert(matches == 1 and panel.owners[1] == panel.owner and #panel.owners == 1,
                        "picker opener did not expose its unique real context owner")
                    -- Native picker Hide must dispatch its real OnHide cleanup in this fixture.
                    MenuWorld.FireVisibilityScripts(panel)
                    local parent = panel:GetParent()
                    local cx, cy = panel:GetCenter()
                    local px, py = parent:GetCenter()
                    local limitX = math.max(0, (parent:GetWidth() - panel:GetWidth()) * 0.5 - 12)
                    local limitY = math.max(0, (parent:GetHeight() - panel:GetHeight()) * 0.5 - 12)
                    local x = math.min(limitX, math.max(-limitX, cx - px))
                    local y = math.min(limitY, math.max(-limitY, cy - py))
                    local clamped = math.abs(x - (cx - px)) >= 0.01 or math.abs(y - (cy - py)) >= 0.01
                    local expected = F.CopySnapshot(before)
                    if cold then
                        expected.menu2ColorPicker = { recent = {}, saved = {} }
                        if clamped then
                            expected.menu2ColorPicker.x = math.floor(x + 0.5)
                            expected.menu2ColorPicker.y = math.floor(y + 0.5)
                        end
                    end
                    local store = assert(expected.menu2ColorPicker)
                    local anchor, relative, relativeAnchor, offsetX, offsetY = panel:GetPoint()
                    assert(anchor == "CENTER" and relative == parent and relativeAnchor == "CENTER"
                        and offsetX == (clamped and x or (store.x or 0))
                        and offsetY == (clamped and y or (store.y or 0)), "picker native position drift")
                    assert(not next(Diff(expected, env.MSUF_DB)), "picker opener changed more than exact cold preferences")
                    if not selectedOpener then
                    assert(panel.blocker:IsShown() and EffectivelyShown(panel) and panel:GetAlpha() == 1
                        and panel.owner._msuf2ColorLabel == "Health bar highlight"
                        and Encode(Pack(panel.owner:GetRGB()), ids) == Encode(Pack(color[1], color[2], color[3]), ids),
                        "picker opener native owner/visibility/RGB drift")
                    else
                        assert(panel.blocker:IsShown() and EffectivelyShown(panel) and panel:GetAlpha() == 1
                            and panel.owner._msuf2ColorLabel == "Selected Spell Color"
                            and Encode(Pack(panel.owner:GetRGB()), ids) == Encode(Pack(color[1], color[2], color[3]), ids),
                            "selected picker native owner/visibility/RGB drift")
                    end
                    local hex = string.format("#%02X%02X%02X", math.floor(color[1] * 255 + 0.5),
                        math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
                    if not selectedOpener then
                    assert(panel.compactHex:GetText() == hex and panel.hex:GetText() == hex
                        and panel.selector.label:GetText() == "Health bar highlight", "picker visible HEX/target drift")
                    else
                        assert(panel.compactHex:GetText() == hex and panel.hex:GetText() == hex
                            and panel.selector.label:GetText() == "Selected Spell Color", "selected picker visible HEX/target drift")
                    end
                    local paint = {}
                    for _, field in ipairs({ panel.original, panel.current, panel.selector.color }) do
                        local fill = assert(field.fill)
                        local parts = fill.L and { fill.L, assert(fill.M), assert(fill.R) } or { fill }
                        for _, texture in ipairs(parts) do
                            local rgba = Pack(texture:GetVertexColor())
                            assert(texture:GetObjectType() == "Texture" and EffectivelyShown(texture) and texture:GetAlpha() == 1
                                and Encode(rgba, ids) == Encode(Pack(color[1], color[2], color[3], 1), ids),
                                "picker native swatch kind/paint/visibility drift")
                            paint[#paint + 1] = rgba
                        end
                    end
                    assert(not panel.historyOwner and not next(panel.touched) and #calls == 0,
                        "picker opener began a color edit/apply")
                    assert(panel.done:GetScript("OnClick") and EffectivelyShown(panel.done) and panel.done:IsEnabled(),
                        "picker has no native Apply Color close owner")
                    panel.done:Click("LeftButton") mw:RunTimers()
                    local undo = M.Undo() mw:RunTimers()
                    local redo = M.Redo() mw:RunTimers()
                    assert(not undo and not redo and #M.historyUndo == 0 and #M.historyRedo == 0,
                        "picker open/close entered profile history")
                    assert(not panel:IsShown() and not panel.blocker:IsShown() and panel.owner == nil,
                        "picker native close retained its visible/session owner")
                    assert(not next(Diff(expected, env.MSUF_DB)) and #calls == 0
                        and Encode(Value(w), ids) == Encode(prior, ids), "picker open/close changed profile action/UI/apply")
                    if cold then coldPickerCases = coldPickerCases + 1 end
                    if selectedOpener then
                        selectedPickerCases = selectedPickerCases + 1
                        if cold then selectedColdCases = selectedColdCases + 1 end
                        Add(view .. ":selected-picker-opener:" .. state, ids[w], cold, color, selectedPickerCases)
                    end
                    Add(view .. ":picker-opener:" .. state, cold, Diff(before, env.MSUF_DB), store,
                        anchor, relativeAnchor, offsetX, offsetY, hex, paint, undo, redo, Value(w))
                end
                local function PrepareAction()
                ReturnView() Setup(state, false, w) calls = {}
                -- Text-action input is filled through its real text owner before native Click.
                if ids[w]:match("%.add$") or ids[w]:match("%.remove$") then
                    for _, input in ipairs(controls) do
                        if ids[input]:match("%.manual%-input$") then
                            Input(input, ids[w]:match("%.add$") and "1459" or "774")
                        end
                    end
                end
                if ids[w]:find(".add-preset-", 1, true) then
                    for _, input in ipairs(controls) do
                        if ids[input]:match("%.preset%-selection$") then
                            local values = input.GetValues and input:GetValues() or input.values
                            if type(values) == "function" then values = values() end
                            for _, item in ipairs(values) do if item.value then Input(input, item.value) break end end
                        end
                    end
                end
                M.ClearHistory()
                PreparePickerOpener()
                end
                PrepareAction()
                local accordionOwner = menuOwners[w]
                local beforeOpen = accordionOwner and accordionOwner.open
                local before, value = F.CopySnapshot(env.MSUF_DB), Alternate(w)
                local beforeValue, enabled = Value(w), w:IsEnabled()
                if enabled then assert(EffectivelyShown(w), "enabled ordinary action is not natively visible: " .. ids[w]) end
                seen.enabled = enabled
                Add(view .. ":action-state:" .. ids[w], state, enabled, w:IsShown())
                local result = Input(w, value)
                actionCount = actionCount + 1
                Add(view .. ":action:" .. ids[w], value, result, Diff(before, env.MSUF_DB), Value(w), calls, M.activeKey)
                Contents("action:" .. ids[w])
                seen.input = true
                RefreshAction("input")
                local after, afterValue = F.CopySnapshot(env.MSUF_DB), Value(w)
                local changed = next(Diff(before, after)) ~= nil
                if not enabled then assert(not changed, "disabled ordinary action changed profile: " .. ids[w]) end
                local undo = M.Undo() mw:RunTimers()
                Add(view .. ":action-undo:" .. ids[w], undo, Diff(before, env.MSUF_DB), Value(w), M.activeKey)
                RefreshAction("undo") seen.undo = true
                assert((undo and true or false) == changed, "ordinary action Undo ownership drift: " .. ids[w])
                if undo then
                    assert(not next(Diff(before, env.MSUF_DB)) and Encode(Value(w), ids) == Encode(beforeValue, ids),
                        "ordinary action Undo failed to restore profile/native value: " .. ids[w])
                end
                local redo = M.Redo() mw:RunTimers()
                Add(view .. ":action-redo:" .. ids[w], redo, Value(w), M.activeKey)
                RefreshAction("redo") seen.redo = true
                assert((redo and true or false) == changed, "ordinary action Redo ownership drift: " .. ids[w])
                if redo then
                    assert(not next(Diff(after, env.MSUF_DB)) and Encode(Value(w), ids) == Encode(afterValue, ids),
                        "ordinary action Redo failed to restore profile/native value: " .. ids[w])
                end
                if accordionOwner then
                    assert(not undo and not redo, "native accordion entered profile history: " .. ids[w])
                    assert(not next(Diff(before, env.MSUF_DB)), "native accordion changed profile: " .. ids[w])
                    Input(w, beforeOpen)
                    assert(w:IsShown() and accordionOwner.body:IsShown() == beforeOpen,
                        "balanced accordion Click lost visible header/body state: " .. ids[w])
                    assert(M.GetPersistentMenuStateTable("accordionState")[accordionOwner.stateKey] == beforeOpen,
                        "balanced accordion Click did not persist menu state: " .. ids[w])
                    Add(view .. ":action-balanced:" .. ids[w], Value(w), Diff(before, env.MSUF_DB))
                end
                if mode ~= "push" then
                    for _, phase in ipairs({ "combat-edge", "combat" }) do
                        PrepareAction()
                        local priorOpen = accordionOwner and accordionOwner.open
                        local wanted, prior = Alternate(w), Value(w)
                        local profile, page = F.CopySnapshot(env.MSUF_DB), M.activeKey
                        local inputOwner = w
                        if w._msuf2RuntimeControlRecord.kind == "segment" then
                            inputOwner = nil
                            for _, child in ipairs(w.buttons) do if child._msuf2Value == wanted then inputOwner = child break end end
                            assert(inputOwner, "ordinary action combat selector choice missing: " .. ids[w])
                        end
                        local proxyRefuses = not accordionOwner and inputOwner._msuf2OnClickHandler
                            and not inputOwner._msuf2AllowCombatClick
                        core.Util.InCombat("PLAYER_REGEN_DISABLED")
                        env.InCombatLockdown = function() return phase == "combat" end
                        calls = {}
                        Input(w, wanted)
                        assert(not next(Diff(profile, env.MSUF_DB)) and #calls == 0,
                            "ordinary action ignored native combat refusal: " .. ids[w] .. ":" .. phase)
                        if proxyRefuses then
                            assert(M.activeKey == page and Encode(Value(w), ids) == Encode(prior, ids),
                                "guarded ordinary action changed page/native display in combat: " .. ids[w])
                        elseif accordionOwner then
                            -- Raw PageBuilder disclosure is an allowed menu action; balance only by native Click.
                            Input(w, priorOpen)
                            assert(accordionOwner.open == priorOpen and accordionOwner.body:IsShown() == priorOpen,
                                "combat menu disclosure did not balance its native state: " .. ids[w])
                        end
                        Add(view .. ":action-refusal:" .. state .. ":" .. ids[w], phase, wanted, proxyRefuses and true or false,
                            Diff(profile, env.MSUF_DB), Value(w), calls, M.activeKey)
                        RefreshAction(phase)
                        assert(not next(Diff(profile, env.MSUF_DB)), "combat action refresh changed profile: " .. ids[w])
                        core.Util.InCombat("PLAYER_REGEN_ENABLED") env.InCombatLockdown = function() return false end
                        mw:Fire("PLAYER_REGEN_ENABLED") mw:RunTimers()
                        RefreshAction(phase .. "-release")
                        local refusedUndo = M.Undo() mw:RunTimers()
                        local refusedRedo = M.Redo() mw:RunTimers()
                        assert(not refusedUndo and not refusedRedo and not next(Diff(profile, env.MSUF_DB)),
                            "refused ordinary action entered profile history: " .. ids[w])
                        Add(view .. ":action-refusal-history:" .. state .. ":" .. ids[w], phase, refusedUndo, refusedRedo,
                            Value(w), M.activeKey)
                        seen[phase] = true
                    end
                end
            end
            end
            local cases = 0
            for id in pairs(actionPlan) do for _, state in ipairs({ "default", "edge" }) do
                local seen = assert(actionEvidence[id] and actionEvidence[id][state], "ordinary action state missing: " .. id .. ":" .. state)
                assert(seen.input and seen.undo and seen.redo and seen.refresh.input and seen.refresh.undo and seen.refresh.redo,
                    "ordinary action refresh/input/history lifecycle missing: " .. id .. ":" .. state)
                if mode ~= "push" then
                    assert(seen["combat-edge"] and seen.combat and seen.refresh["combat-edge"] and seen.refresh.combat
                        and seen.refresh["combat-edge-release"] and seen.refresh["combat-release"],
                        "ordinary action combat/refusal/refresh lifecycle missing: " .. id .. ":" .. state)
                end
                cases = cases + 1
            end end
            assert(cases == #actions * 2, "ordinary action independent state census drift")
            for id in pairs(actionEvidence) do assert(actionPlan[id], "unexpected ordinary action lifecycle evidence: " .. id) end
            Add(view .. ":action-lifecycle-census", cases, actionEvidence)
            ReturnView() Setup("default")
        end
        mw:Select("home") ReturnView()
        Observe("reopen")
        end
    end end end
    for _, scope in ipairs(scopes) do
        local evidence = assert(spellScopes[scope], "Spell scope has no inventory: " .. scope)
        assert(evidence.views == (mode == "push" and 1 or 10), "Spell per-view inventory count drift: " .. scope)
        local unique, drags, settingCases, pickerCases = 0, 0, 0, 0
        if not narrow then
            for id, plan in pairs(evidence.catalog) do
                local seen = assert(evidence.exercised[id], "Spell ordinary identity was never exercised: " .. scope .. ":" .. id)
                local repeats, expectedCases = plan.classification == "setting" and 1 or evidence.views, {}
                for key in pairs(plan.cases) do expectedCases[key] = repeats end
                assert(Encode(seen.cases, ids) == Encode(expectedCases, ids), "Spell field/record-nil matrix incomplete: " .. scope .. ":" .. id)
                for _, state in ipairs({ "default", "edge" }) do
                    local enabledViews = 0
                    for _ in pairs(seen.enabledStates[state] or {}) do enabledViews = enabledViews + 1 end
                    assert(enabledViews == repeats, "Spell identity had no enabled native input: " .. scope .. ":" .. id .. ":" .. state)
                end
                assert((seen.drag == true) == (plan.kind == "slider"), "Spell drag coverage drift: " .. scope .. ":" .. id)
                unique = unique + 1
                for _, count in pairs(seen.cases) do
                    if plan.classification == "setting" then settingCases = settingCases + count else pickerCases = pickerCases + count end
                end
                if seen.drag then drags = drags + 1 end
            end
            for id in pairs(evidence.exercised) do assert(evidence.catalog[id], "unexpected exercised Spell identity: " .. id) end
            assert(unique == 48 and settingCases == 176 and pickerCases == 4 * evidence.views and drags == 20,
                "Spell unique scope matrix count drift: " .. scope)
        else assert(not next(evidence.exercised), "400px world unexpectedly replayed Spell matrix") end
        Add("spell-scope-coverage:" .. scope, evidence, unique, settingCases, pickerCases, drags)
        print("Spell scope " .. scope .. ": 46 settings / 2 pickers in " .. evidence.views .. " views; "
            .. unique .. " unique inputs / " .. settingCases .. " setting cases / " .. pickerCases .. " picker cases / "
            .. drags .. " drags" .. (narrow and " (400px inventory)" or ""))
    end
    if not narrow then
        assert(coldPickerCases > 0, "real cold picker opener coverage missing")
        Add("picker-cold-census", coldPickerCases)
        assert(selectedPickerCases > 0 and selectedColdCases > 0, "real selected cold picker lifecycle coverage missing")
        Add("selected-picker-census", selectedPickerCases, selectedColdCases)
    end
    if not narrow then assert(mutating > 10, "input replay did not exercise actual profile changes") end
    return rows, total, missingCount, actionCount
end
local started = os.clock()
local expected, oldCount, missingCount, actionCount = Replay(true)
if mode == "original" then print("Group Aura Style immutable parent passed: " .. oldCount .. " inputs") return end
local actual, count = Replay(false)
assert(#expected == #actual and count == oldCount, "Group Aura Style observation count drift")
for i = 1, #expected do if expected[i] ~= actual[i] then
    diffPath = os.tmpname()
    diff = assert(io.open(diffPath, "wb"))
    assert(diff:write("parent\n", expected[i], "\ncandidate\n", actual[i], "\n")) assert(diff:close()) diff = nil
    error("Group Aura Style parity drift at " .. i .. " " .. expected[i]:match("^[^\t]+"))
end end
local narrowExpected, narrowCount = Replay(true, true)
local narrowActual, narrowActualCount = Replay(false, true)
assert(narrowCount == narrowActualCount and #narrowExpected == #narrowActual, "400px inventory drift")
for i = 1, #narrowExpected do assert(narrowExpected[i] == narrowActual[i], "400px Group Aura Style parity drift at " .. i) end
print("Group Aura Style coverage: " .. missingCount .. " absent-key cases / " .. actionCount .. " native actions/selectors; 400px rebuild exact")
if flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists" then
    local positiveExpected, positiveOldCount = Replay(true, false, true)
    local positiveActual, positiveCount = Replay(false, false, true)
    assert(positiveOldCount == 5 and positiveCount == 5 and #positiveExpected == #positiveActual,
        "Classic positive blacklist observation/census drift")
    for i = 1, #positiveExpected do
        assert(positiveExpected[i] == positiveActual[i], "Classic positive blacklist parity drift at " .. i)
    end
end
print(string.format("menu_group_aura_style_schema_parity_smoke %s %s: %d inputs/%d observations, DB/apply/history/drag/release exact; full tier also covers combat (%.2fs)",
    mode, flavor, count, #actual, os.clock() - started))
end
local ok, problem = xpcall(Run, debug.traceback)
if io.type(file) == "file" then file:close() end
if io.type(diff) == "file" then diff:close() end
local removed, cleanupError = os.remove(scratch)
if diffPath then io.stderr:write("Group Aura Style " .. flavor .. " diff artifact: " .. diffPath .. "\n") end
if not ok then
    if not removed then io.stderr:write("Group Aura Style temporary parent cleanup failed: " .. tostring(cleanupError) .. "\n") end
    error(problem, 0)
end
assert(removed, "Group Aura Style temporary parent cleanup failed: " .. tostring(cleanupError))

-- The fixture is captured from the real pre-migration builders, never from declarations.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
assert(arg[3] ~= "--capture", "pilot fixtures are immutable pre-migration receipts")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
local mw = MenuWorld.Open(root, flavor, { beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62 end,
    }
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, env = mw.M, mw.env
local lines, counts = {}, {}
local function Encode(value)
    if type(value) == "table" then
        local out = {}
        for i, item in ipairs(value) do
            out[i] = type(item) == "table" and (tostring(item.value) .. "=" .. tostring(item.text)) or tostring(item)
        end
        return table.concat(out, ",")
    end
    local text = tostring(value == nil and "" or value):gsub("[\r\n\t]", " ")
    return text
end
local function Wanted(record, page)
    if record.pageKey ~= page then return false end
    if page == "classpower" then return record.controlId:find("resource.extras", 1, true) ~= nil end
    if page:match("^uf_") then
        return record.controlPath:find("transparency", 1, true) ~= nil
            or record.controlPath:find("range_fade", 1, true) ~= nil
    end
    return true
end
local function Snapshot(page, state)
    local count = 0
    for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if Wanted(r, page) then
            local w, values = M.RuntimeControlCatalog.Get(r.controlId).widget, nil
            local declaration = assert(w and w._msuf2ControlSchema,
                "control_declaration missing: " .. r.controlId)
            assert(declaration.id == r.controlId and declaration.kind == r.kind,
                "control_declaration identity/kind mismatch: " .. r.controlId)
            assert(declaration.labelKey ~= nil and declaration.scope and declaration.applyDomain,
                "control_declaration label/scope/apply missing: " .. r.controlId)
            if r.settingKey and r.settingKey ~= "" then
                assert(declaration.settingPath == r.settingKey,
                    "control_declaration setting path mismatch: " .. r.controlId)
            end
            assert(declaration.set or declaration.action or (declaration.source and declaration.key and declaration.apply),
                "control_declaration lost action semantics: " .. r.controlId)
            if declaration.owner then
                local owner = w._msuf2CommandAction or M.RuntimeControlCatalog.Get(r.controlId).command
                OwnerAssert.Command(w, declaration, owner)
            end
            if declaration.action or r.kind == "button" then OwnerAssert.Button(w, declaration) end
            if r.kind == "slider" then
                assert(declaration.range and declaration.defaultSource,
                    "control_declaration slider range/default missing: " .. r.controlId)
            end
            if w and w.GetValues then values = w:GetValues() end
            if not values and w then values = w.values or w._msuf2Values or w.items end
            if type(values) == "function" then values = values() end
            local lo, hi
            if r.kind == "slider" then lo, hi = w:GetMinMaxValues() end
            local command = w and w._msuf2CommandAction
            local value = command and command.get and command.get()
            local fields = { state, r.controlId, r.kind, r.label, r.settingKey, r.controlPath,
                Encode(r.searchSettingKeys), Encode(r.searchSettingKeyPatterns), r.actionKey, r.classification,
                Encode(lo), Encode(hi), Encode(w and w.valueStep), Encode(values), Encode(value),
                Encode(w and w._msuf2SearchMeta and w._msuf2SearchMeta.searchPrepareKind),
                Encode(w and w._msuf2SearchMeta and w._msuf2SearchMeta.searchPrepareValue) }
            for i = 1, #fields do fields[i] = Encode(fields[i]) end
            lines[#lines + 1] = table.concat(fields, "\t")
            count = count + 1
        end
    end
    counts[state] = count
end
local function Expand(page)
    local entry = assert(M.cache[page], "missing page " .. page)
    for _, section in pairs(entry.sections or {}) do
        local e = section._msuf2CollapsibleEntry
        if e then e.SetOpenImmediate(true) end
    end
    mw:RunTimers()
    M.Refresh(entry.ctx)
    mw:RunTimers()
end
local function Visit(page)
    assert(mw:Select(page), "cannot select " .. page)
    Expand(page)
    Snapshot(page, page .. ":cold")
    mw:Select("home")
    assert(mw:Select(page))
    Expand(page)
    Snapshot(page, page .. ":warm")
end
Visit("gameplay")
M.formContentMaxWidth = 420
M.InvalidatePage("gameplay")
assert(mw:Select("gameplay"))
Expand("gameplay")
Snapshot("gameplay", "gameplay:narrow")
env.MSUF_DB.gameplay.enableCombatTimer = true
env.MSUF_DB.gameplay.enableCombatStateText = true
env.MSUF_DB.gameplay.enableCombatCrosshair = true
env.MSUF_DB.gameplay.enableCombatCrosshairMeleeRangeColor = true
env.MSUF_DB.gameplay.meleeSpellPerClass = true
env.MSUF_DB.gameplay.meleeSpellPerSpec = true
M.Refresh(M.cache.gameplay.ctx)
Snapshot("gameplay", "gameplay:enabled")
M.formContentMaxWidth = nil
Visit("classpower")
local ui = assert(M.ClassPowerWorkspace.current)
ui:Select("extras")
Expand("classpower")
Snapshot("classpower", "extras:empty")
env.MSUF_DB.bars.resourceMarks = { { target = "PLAYER", resource = "ALL", mode = "PERCENT",
    value = 50, width = 2, color = { 1, 1, 1 }, mark = true } }
M.Refresh(M.cache.classpower.ctx)
Snapshot("classpower", "extras:percent")
env.MSUF_DB.bars.resourceMarks[1].mode = "ABSOLUTE"
env.MSUF_DB.bars.resourceMarks[1].value = 250
M.Refresh(M.cache.classpower.ctx)
Snapshot("classpower", "extras:absolute")
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    local page = "uf_" .. unit
    if M.pages[page] then
        Visit(page)
        local _, widget = M.RuntimeControlCatalog.FindBySettingKey(unit .. ".oocFadeEnabled", page)
        if widget and widget._msuf2PrepareExactSearchTarget then
            widget:_msuf2PrepareExactSearchTarget({ prepareKind = "unitAlphaTab", prepareValue = "ooc" })
        end
        Snapshot(page, page .. ":ooc")
        env.MSUF_DB[unit].rangeFadeEnabled = false
        env.MSUF_DB[unit].oocFadeEnabled = true
        M.Refresh(M.cache[page].ctx)
        Snapshot(page, page .. ":gated")
    end
end
if M.pages.swingtimers then
    Visit("swingtimers")
    for _, hand in ipairs({ "main", "off", "ranged" }) do
        mw.core.SwingTimer.menuContext._msuf2SwingTimerPreview.SelectHand(hand)
        Snapshot("swingtimers", "swing:" .. hand)
    end
end
table.sort(lines)
local result = table.concat(lines, "\n") .. "\n"
local path = root .. "/tools/fixtures/menu-pilot/" .. flavor .. ".tsv"
do
    local f = assert(io.open(path, "rb"))
    local expected = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if result ~= expected then
        local actual = assert(io.open(root .. "/.checks/inventory-" .. flavor .. "-actual.tsv", "wb"))
        actual:write(result)
        actual:close()
        error("built pilot control inventory differs from immutable pre-migration fixture: " .. flavor)
    end
end
assert(#lines > 100, "pilot builders did not materialize their controls")
print("menu_pilot_inventory_smoke " .. flavor .. ": " .. #lines .. " real state/control rows OK")

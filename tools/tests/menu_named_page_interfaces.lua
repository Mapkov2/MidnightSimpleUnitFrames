-- menu_named_page_interfaces.lua <root> <client> [ownedBaseline] [--observe]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local observe = arg[4] == "--observe"
local captured = {}
local contracts = {
    Layout = {
        Profile = "EnsureDB GetConf GetGeneral ReadBool ReadNumber NormalizeBossLayoutMode UpdateLoadActive",
        Controls = "Widgets Theme Schema SetControlEnabled SettingMeta RegisterControl UnitOptions TooltipOptions Shared",
        Layout = "PixelLayoutRegion LoadConditions BossLayouts Separators AnchorSectionHeight",
        HealthColors = "Global Labels Aliases Options", Runtime = "Core RequestUnitApply",
    },
    Castbar = {
        Profile = "Fields GetGeneral UnitTopLabel ReadBool SetBool ReadGeneralBool SetGeneralBool NormalizePortrait SetPortraitValue",
        Controls = "Widgets Schema Row Card Note SettingMeta ReviewedMeta RegisterControl Shared",
        Runtime = "OnSettingsChanged SuppressBlizzardPlayerCastbars ShowReloadPopup", Tabs = "Normalize Current SetBodyHeight Build PrepareTarget",
    },
    Portrait = {
        Profile = "GetConf ReadBool ReadNumber SetNumber NormalizePortrait SetPortraitValue",
        Controls = "Widgets Schema Row Card PixelLayoutRegion ControlMeta ReviewedMeta Shared",
        Portrait = "Render Shapes Borders CastbarUnits", Tabs = "Normalize Current SetBodyHeight Build PrepareTarget",
    },
    Power = {
        Profile = "Units GetConf GetGeneral GetBars UnitTopLabel ReadBool SetBool ReadNumber SetNumber IsPlayerPowerManagedByClassResources",
        Controls = "Widgets Schema Row Card SettingMeta RegisterControl Shared", Runtime = "Core EnsureCooldownWidthObservers",
    },
}
local domains = {
    Layout = { "Profile", "Controls", "Layout", "HealthColors", "Runtime" },
    Castbar = { "Profile", "Controls", "Runtime", "Tabs" },
    Portrait = { "Profile", "Controls", "Portrait", "Tabs" },
    Power = { "Profile", "Controls", "Runtime" },
}
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local names = path:match("MSUF_Menu2_UnitSections.lua$") and { "Layout" }
            or path:match("MSUF_Menu2_UnitFrameVisuals.lua$") and { "Castbar", "Portrait", "Power" }
        for _, name in ipairs(names or {}) do
            local factories = name == "Layout" and world.core.MSUF2.UnitSectionFactories or world.core.MSUF2.UnitVisualFactories
            local factory = factories[name]
            factories[name] = function(...)
                local prior = captured[name]
                captured[name] = { factory = factory, args = { ... }, calls = (prior and prior.calls or 0) + 1 }
                return factory(...)
            end
        end
        return load(self, path, addon, ns)
    end
end }, arg[3])
local count = 0
for _, name in ipairs({ "Layout", "Castbar", "Portrait", "Power" }) do
    local entry = assert(captured[name], name .. " factory was not bound")
    if not observe then
        assert(#entry.args == #domains[name] and type(entry.args[1]) == "table",
            name .. " still takes a positional context list")
        for i, domainName in ipairs(domains[name]) do
            local domain, prefix = entry.args[i], name .. "." .. domainName
            for _, invalid in ipairs({ false, "missing" }) do
                if invalid == false then entry.args[i] = false else entry.args[i] = nil end
                local ok, message = pcall(entry.factory, unpack(entry.args, 1, #domains[name]))
                entry.args[i] = domain
                assert(not ok and tostring(message):find(prefix .. " interface is required", 1, true), prefix .. " was not required")
            end
            local required = {}
            for key in contracts[name][domainName]:gmatch("%S+") do
                required[key] = true
                local value = assert(domain[key], prefix .. "." .. key .. " was not supplied")
                domain[key] = nil
                local ok, message = pcall(entry.factory, unpack(entry.args))
                domain[key] = value
                assert(not ok and tostring(message):find(prefix .. "." .. key .. " is required", 1, true),
                    prefix .. " did not reject missing named field " .. key)
                count = count + 1
            end
            for key in pairs(domain) do assert(required[key], prefix .. "." .. key .. " lacks a missing-field test") end
        end
    end
    assert(entry.calls == 1, name .. " was rebound during page build")
end
-- Build the real lazy sections on every available unit page, including every portrait tab.
-- --observe replays the positional baseline too; compare its receipts with the named build.
local function Encode(value, seen)
    local kind = type(value)
    if kind == "function" then return "<function>" end
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    if value.GetObjectType then return "<widget>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key) .. "=" .. Encode(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
-- Captured from the positional owners at 13ac6bd6a, replayed with the same client graph.
local expectedReceipts = {
    Mainline = { 54, 1590333432 },
    Vanilla = { 30, 86774051 },
    TBC = { 48, 2410186907 },
    Mists = { 54, 1185371098 },
    Forever = { 48, 676652794 },
}
local M, builds, receipts = mw.M, 0, {}
local function InSection(widget, entry)
    while widget do
        if widget == entry.sections.portrait or widget == entry.sections.power_bar then return true end
        widget = widget:GetParent()
    end
    return false
end
local function Receipt(page, tab)
    local entry, rows = M.cache[page], {}
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local control = M.RuntimeControlCatalog.Get(record.controlId)
        local widget = control and control.widget
        if record.pageKey == page and widget and InSection(widget, entry) then
            local command = widget._msuf2CommandAction or record.command
            local values = widget.GetValues and widget:GetValues() or widget.values
            if type(values) == "function" then values = values() end
            local low, high = widget:GetMinMaxValues()
            rows[#rows + 1] = Encode({ record, values, command and command.get and command.get(), low, high,
                widget.valueStep, widget._msuf2SearchMeta, widget._msuf2ExactTargetContracts, widget:IsShown(), widget:IsEnabled(),
                widget:GetWidth(), widget:GetHeight() })
        end
    end
    assert(#rows > 0, page .. " did not build portrait/power controls")
    table.sort(rows)
    local a, b = 1, 0
    for _, row in ipairs(rows) do
        for i = 1, #row do a = (a + row:byte(i)) % 65521; b = (b + a) % 65521 end
    end
    local portrait, power = entry.sections.portrait, entry.sections.power_bar
    local receipt = string.format("PARITY %s %s %s controls=%d digest=%.0f heights=%s/%s", flavor, page, tab, #rows, b * 65536 + a,
        portrait and portrait:GetHeight() or "absent", power and power:GetHeight() or "absent")
    receipts[#receipts + 1] = receipt
    if observe then print(receipt) end
end
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    local page = "uf_" .. unit
    if M.pages[page] then
        assert(mw:Select(page), "could not select " .. page)
        local entry = assert(M.cache[page])
        for _, id in ipairs({ "portrait", "power_bar" }) do
            local sec = entry.sections[id]
            if sec then
                sec._msuf2CollapsibleEntry.SetOpenImmediate(true)
                assert(M.Widgets.EnsureSectionContent(sec), "could not build " .. page .. "." .. id)
                builds = builds + 1
            end
        end
        for _, tab in ipairs({ "general", "placement", "geometry", "border", "dragon", "advanced" }) do
            if entry.sections.portrait then assert(entry.sections.portrait._msuf2GuidedSelectTab(tab), "portrait tab " .. tab) end
            mw:RunTimers()
            M.Theme.StopAllMenuAnimations()
            Receipt(page, tab)
        end
    end
end
mw:Select("uf_target")
mw:Select("uf_player")
for name, entry in pairs(captured) do assert(entry.calls == 1, name .. " interface was allocated per build") end
assert(builds > 0, "no real lazy sections built")
local a, b = 1, 0
local receiptText = table.concat(receipts, "\n")
for i = 1, #receiptText do a = (a + receiptText:byte(i)) % 65521; b = (b + a) % 65521 end
local expected = assert(expectedReceipts[flavor], "unsupported receipt client")
assert(#receipts == expected[1] and b * 65536 + a == expected[2], "portrait/power page build changed from positional baseline")
print("PASS named page interfaces " .. flavor .. ": " .. count .. " required fields; " .. builds .. " real sections; one binding per owner")

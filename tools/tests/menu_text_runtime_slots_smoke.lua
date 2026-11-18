-- menu_text_runtime_slots_smoke.lua <root> <flavor> [original-source-root]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    world.env.AbbreviateNumbers = function(value)
        return value >= 1000 and "short:" .. value or tostring(value)
    end
    world.env.BreakUpLargeNumbers = function(value)
        return value >= 1000 and "full:" .. value or tostring(value)
    end
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_UnitText.lua$") or path:match("MSUF_Menu2_GroupBars.lua$")
            or path:match("MSUF_Menu2_UnitSectionShared.lua$") then path = arg[3] .. path:sub(#root + 1) end
        return load(self, path, addon, ns)
    end
end })
local function Expand()
    for _, section in pairs(mw.M.cache[mw.M.activeKey].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
end
local function Previews()
    local result = {}
    for _, frame in ipairs(mw.world.widgets.frames) do
        for _, region in ipairs(frame.regions or {}) do
            local schema = region._msuf2ControlSchema
            if schema and tostring(schema.id):match("%.preview$") and region.GetText then result[#result + 1] = region end
        end
    end
    return result
end
local function Control(path)
    local page = mw.M.cache[mw.M.activeKey]
    for _, widget in ipairs(page.searchWidgets) do
        local schema = widget._msuf2ControlSchema
        local setting = schema and schema.setting
        if setting == path then return widget end
        if type(setting) == "table" then
            for _, key in ipairs(setting.keys or {}) do
                if key == path and mw.M.ControlSchema.ResolvePath(schema) == path then return widget end
            end
        end
    end
    error("missing text control " .. path)
end
local function CheckNamePosition(path)
    local anchor = Control(path)
    local _, card, _, _, titleY = anchor._msuf2Title:GetPoint()
    local _, _, _, _, subtitleY = card.subtitle:GetPoint()
    local _, _, _, _, buttonY = anchor:GetPoint()
    assert(subtitleY - titleY >= 2 * card.subtitle:GetStringHeight() + 4, path .. " overlaps a wrapped Position subtitle")
    assert(card:GetHeight() + buttonY - anchor:GetHeight() >= 8, path .. " dropdown extends past the Position card")
end
Expand()
CheckNamePosition("player.nameTextAnchor")
mw:Select("gf_layout")
Expand()
CheckNamePosition("gf_party.nameAnchor")
local previews = Previews()
assert(#previews >= 4, "unit/group text previews did not build")
local slotCalls, text = 0, mw.core.UFText
local update = text.UpdateTextSlots
text.UpdateTextSlots = function(slots, count, ...)
    slotCalls = slotCalls + count
    for i = 1, count do slots[i].fs:SetText("RUNTIME-SLOT") end
end
mw.M.RunEntryRefreshers(mw.M.cache.gf_layout, { force = true })
mw:Select("uf_player")
mw.M.RunEntryRefreshers(mw.M.cache.uf_player, { force = true })
local painted = 0
for _, value in ipairs(previews) do
    if tostring(value:GetText()):find("RUNTIME-SLOT", 1, true) then painted = painted + 1 end
end
assert(painted >= 4 and slotCalls >= 4, "menu text samples bypassed runtime text slots")
text.UpdateTextSlots = update
local shared = mw.M.UnitSectionsShared
local value = mw.env.UIParent:CreateFontString()
local modes = { { "CURPERCENT", false, false }, { "ABSORB", false, true }, { "DEFICIT", true, false } }
shared.PaintTextPreview(value, modes, { delimiter = " / ", decimals = true, short = false })
local first = value:GetText()
assert(first:find("63.0%%") and not first:find("63.4%%"), "fraction and value sample disagree")
assert(first:find("INV_Shield_06", 1, true), "absorb icon was lost")
shared.PaintTextPreview(value, modes, { delimiter = " / ", decimals = true, short = false })
assert(value:GetText() == first, "retained text slot cache returned the previous summary")
shared.PaintTextPreview(value, { { "NONE" }, { "NONE" }, { "NONE" } }, {})
assert(value:GetText() == "(none)", "empty slots retained text")
local M, core = mw.M, mw.core
local function CheckPowerFormatting(scope, conf, getSpec, legacyShort)
    local page = M.cache[M.activeKey]
    conf.powerFullValueShort, conf.hpFullValueShort = nil, true
    conf.showPowerText, conf.powerTextLeft, conf.powerTextCenter, conf.powerTextRight = true, "NONE", "CURMAXPERCENT", "NONE"
    local toggle = Control(scope .. ".powerFullValueShort")
    local id = toggle._msuf2ControlSchema.id
    local selected, found, exact = M.Search._RoutingAPI.OpenSearchTarget(M.activeKey, "", "", nil, nil,
        { controlId = id, settingKey = scope .. ".powerFullValueShort", sectionId = "text", prepareKind = "menuTab", prepareValue = "power" })
    local card = toggle:GetParent()
    assert(selected and found and exact and card:GetParent():IsShown(), scope .. " power format search target did not open")
    local sample
    for _, region in ipairs(card.regions) do
        local schema = region._msuf2ControlSchema
        if schema and schema.id:match("%.preview$") then sample = region end
    end
    assert(sample, scope .. " power sample missing")
    local _, _, _, _, toggleY = toggle:GetPoint()
    assert(card:GetHeight() + toggleY - toggle:GetHeight() >= 8, scope .. " Short numbers extends past the content card")
    local frame = { powerTextCenter = mw.env.UIParent:CreateFontString() }
    local function CheckFormatting(short)
        M.RunEntryRefreshers(page, { force = true })
        mw:RunTimers()
        local value = sample:GetText()
        assert(toggle:GetChecked() == short, scope .. " displayed the wrong format setting")
        local spec = getSpec()
        assert(spec.text.shortNumbers == short and spec.text.healthShortNumbers == true, scope .. " power setting did not reach the runtime spec")
        local runtime = text.CompileTextRuntime(frame, spec, spec.text)
        text.UpdateTextSlots(runtime.powerSlots, runtime.powerSlotCount, 12450, 15000, "player", function() return 83 end, true, runtime)
        local prefix = short and "short:" or "full:"
        for _, output in ipairs({ value, frame.powerTextCenter:GetText() }) do
            assert(output:find(prefix .. "12450", 1, true) and output:find(prefix .. "15000", 1, true) and output:find("83%", 1, true),
                scope .. " did not format the current and max values while preserving percent: " .. output)
        end
    end
    CheckFormatting(legacyShort)
    toggle:Click()
    assert(conf.powerFullValueShort == not legacyShort and conf.hpFullValueShort == true, scope .. " toggle wrote to the wrong field")
    CheckFormatting(not legacyShort)
    conf.powerTextCenter = "PERCENT"
    M.RunEntryRefreshers(page, { force = true })
    assert(not toggle:IsEnabled() and sample:GetText() == "83%", scope .. " disabled control or percent-only sample is incorrect")
end
local db = mw.env.MSUF_DB
db.general.useShortNumbers = false
CheckPowerFormatting("player", db.player, function() return core.UF.Config.CompileSpec("player") end, false)
db.general.useShortNumbers = true
CheckPowerFormatting("player", db.player, function() return core.UF.Config.CompileSpec("player") end, true)
assert(db.target.powerFullValueShort == nil, "Player toggle changed the Target setting")
db.general.useShortNumbers = false
mw:Select("gf_layout")
local scopes = { "party", "raid" }
if M.SupportsFrameScope("mythicraid") then scopes[#scopes + 1] = "mythicraid" end
for _, scope in ipairs(scopes) do
    M.SetMenuStateValue("gfScope", scope)
    core.GF.InvalidateCompiledSpecs(scope)
    CheckPowerFormatting("gf_" .. scope, core.GF.GetConf(scope), function() return core.GF.GetCompiledSpec(scope) end, true)
end
print("menu_text_runtime_slots_smoke " .. flavor .. ": text layout, power formats and runtime writers passed")

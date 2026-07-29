-- Focused Assistant-side MSUF Layer contract audit.
--
-- This intentionally loads only the small registry modules under test. It does
-- not build Menu2 pages or emulate the WoW UI.
--
-- Usage from the repository root:
--   lua .github/scripts/tests/layer_contract_smoke.lua

_G = _G or _ENV

local function Exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function Read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local content = file:read("*a") or ""
    file:close()
    return content
end

local function Join(left, right)
    left = tostring(left or ""):gsub("[/\\]+$", "")
    right = tostring(right or ""):gsub("^[/\\]+", "")
    return left == "." and "./" .. right or left .. "/" .. right
end

local function ResolveRepositoryRoot()
    for _, root in ipairs({ ".", "..", "../..", "../../.." }) do
        if Exists(Join(root, "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_Unitframes_Power.lua"))
            and Exists(Join(root, "tools/assistant_v1_catalog_crosswalk.lua"))
        then
            return root
        end
    end
    error("repository root not found")
end

local ROOT = ResolveRepositoryRoot()
local ASSISTANT = Join(ROOT, "MidnightSimpleUnitFrames_Assistant/Assistant")

local function LoadAssistant(relative, MSUF)
    local path = Join(ASSISTANT, relative)
    local chunk, err = loadfile(path)
    assert(chunk, path .. ": " .. tostring(err))
    return chunk("MidnightSimpleUnitFrames_Assistant", MSUF)
end

local function HasAlias(setting, expected)
    for _, alias in ipairs(setting.aliases or {}) do
        if alias == expected then return true end
    end
    return false
end

local function AssertLayerContract(setting, key)
    assert(setting, "missing layer setting " .. tostring(key))
    assert(setting.type == "number", key .. " is not numeric")
    assert(setting.min == 0 and setting.max == 30 and setting.step == 1,
        key .. " must expose the MSUF Layer 0..30/step 1 contract")
end

local MSUF = { MSUF2 = {}, Assistant = { UnitframesRegistry = {} } }
local UnitframesRegistry = MSUF.Assistant.UnitframesRegistry
UnitframesRegistry.AddDetachedPowerVerbAliases = function() end
UnitframesRegistry.DetachedPowerMoveAliases = function() return {} end
UnitframesRegistry.DetachedPowerMoveGuard = function() return nil end
UnitframesRegistry.InitDetachedPowerBar = function() end

LoadAssistant("MSUF_AssistantRegistry_Unitframes_Power.lua", MSUF)

local layerSettings = {}
local unitTables = {}
local function UnitDB(unit)
    unitTables[unit] = unitTables[unit] or {}
    return unitTables[unit]
end
local function MakeAliases(unit, ...)
    local aliases = {}
    for i = 1, select("#", ...) do
        aliases[#aliases + 1] = unit .. " " .. tostring(select(i, ...))
    end
    return aliases
end
local function RegisterUnitNumberSetting(unit, attr, dbKey, label, defaultValue, minValue, maxValue, aliases, opts)
    if attr == "detachedPowerBarFrameLevelOffset" then
        local key = unit .. "." .. dbKey
        layerSettings[key] = {
            key = key, type = "number", min = minValue, max = maxValue,
            step = opts and opts.step or 1, aliases = aliases,
        }
    end
end

local powerContext = {
    UnitDB = UnitDB,
    BarsDB = function() return {} end,
    MakeAliases = MakeAliases,
    RegisterUnitBooleanSetting = function() end,
    RegisterUnitNumberSetting = RegisterUnitNumberSetting,
    RegisterUnitEnum = function() end,
    DETACHED_POWER_SHAPE_VALUES = { "BAR", "ROUND", "CRYSTAL", "ORB" },
    DETACHED_POWER_SHAPE_ALIASES = {},
}
local powerUnits = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
for _, unit in ipairs(powerUnits) do
    MSUF.Assistant.UnitframesRegistry.RegisterPowerSettings(powerContext, unit)
    AssertLayerContract(layerSettings[unit .. ".detachedPowerBarFrameLevelOffset"],
        unit .. ".detachedPowerBarFrameLevelOffset")
end

LoadAssistant("MSUF_AssistantRegistry_AurasUnitLanes.lua", MSUF)

local registered = {}
local Registry = {}
function Registry:RegisterSetting(setting)
    assert(not registered[setting.key], "duplicate setting " .. tostring(setting.key))
    registered[setting.key] = setting
    layerSettings[setting.key] = setting
    return setting
end

local customContainers = {}
local model = {}
function model.CustomContainer(unit, index, create)
    customContainers[unit] = customContainers[unit] or {}
    if create and type(customContainers[unit][index]) ~= "table" then
        customContainers[unit][index] = { layer = 9 }
    end
    return customContainers[unit][index]
end

local auraApply = {}
local auraUnits = { "player", "target", "focus", "boss" }
local labels = { player = "Player", target = "Target", focus = "Focus", boss = "Boss" }
MSUF.Assistant.AurasRegistry.RegisterUnitCustomContainerLayerSettings({
    Registry = Registry,
    UNIT_LABELS = labels,
    AURA_UNITS = auraUnits,
    AddAliasesForAuraScope = function(out, unit, noun)
        out[#out + 1] = unit .. " " .. noun
        return true
    end,
    AuraModel = function() return model end,
    ApplyAura = function(unit, reason) auraApply[unit] = reason end,
})

for _, unit in ipairs(auraUnits) do
    for index = 1, 4 do
        local key = "auras3." .. unit .. ".custom" .. tostring(index) .. ".layer"
        local setting = registered[key]
        AssertLayerContract(setting, key)
        assert(setting.page == "uf_" .. unit, key .. " has the wrong Menu2 page")
        assert(HasAlias(setting, unit .. " custom " .. tostring(index) .. " aura layer"),
            key .. " lacks its unambiguous custom-container alias")
        assert(setting.get() == 9, key .. " default changed")
        setting.set(31)
        assert(setting.get() == 30, key .. " did not clamp above 30")
        setting.set(-1)
        assert(setting.get() == 0, key .. " did not clamp below 0")
        setting.set(12.6)
        assert(setting.get() == 13, key .. " did not apply step-1 rounding")
        setting.apply()
        assert(auraApply[unit] == "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_LAYOUT",
            key .. " did not request the custom-container aura apply")
    end
end

LoadAssistant("MSUF_AssistantRegistry_AurasGroupLaneSettings.lua", MSUF)

local groupRoots, groupApply = {}, {}
local groupScopes = { "party", "raid", "mythicraid" }
local groupLabels = { party = "Party", raid = "Raid", mythicraid = "Mythic Raid" }
MSUF.Assistant.AurasRegistry.RegisterGroupExternalLayerSettings({
    Registry = Registry,
    UNIT_LABELS = groupLabels,
    GF_AURA_GROUPS = groupScopes,
    AddAliasesForUnit = function(out, scope, noun)
        out[#out + 1] = scope .. " " .. noun
        return true
    end,
    GFAurasRoot = function(scope)
        groupRoots[scope] = groupRoots[scope] or {}
        return groupRoots[scope]
    end,
    ApplyGroup = function(scope, reason) groupApply[scope] = reason end,
})

for _, scope in ipairs(groupScopes) do
    local key = "gf_" .. scope .. ".auras.externals.layer"
    local setting = registered[key]
    AssertLayerContract(setting, key)
    assert(setting.page == "gf_auras", key .. " has the wrong Menu2 page")
    assert(HasAlias(setting, scope .. " external defensive layer"),
        key .. " lacks its unambiguous external-defensive alias")
    assert(setting.get() == 7, key .. " default changed")
    setting.set(31)
    assert(setting.get() == 30, key .. " did not clamp above 30")
    setting.set(-1)
    assert(setting.get() == 0, key .. " did not clamp below 0")
    setting.apply()
    assert(groupApply[scope] == "auras", key .. " did not request a group-aura apply")
end

local crosswalk = Read(Join(ROOT, "tools/assistant_v1_catalog_crosswalk.lua"))
assert(crosswalk:find('local regionMinMaxValues = setmetatable({}, { __mode = "k" })', 1, true),
    "catalog crosswalk does not retain per-widget slider bounds")
assert(crosswalk:find('if key == "SetMinMaxValues" then', 1, true),
    "catalog crosswalk does not capture SetMinMaxValues")
assert(crosswalk:find('local values = regionMinMaxValues[self]', 1, true),
    "catalog crosswalk GetMinMaxValues does not return captured bounds")
assert(not crosswalk:find('if key == "GetMinMaxValues" then return function() return 0, 100 end end', 1, true),
    "catalog crosswalk still hard-codes every slider to 0..100")

local settingsInstaller = Read(Join(ASSISTANT, "MSUF_AssistantRegistry_Auras_SettingRegistries.lua"))
local controlSchema = Read(Join(ASSISTANT, "MSUF_AssistantControlSchema_Data.lua"))
local globalBarBaseRegistry = Read(Join(ASSISTANT, "MSUF_AssistantRegistry_GlobalBarSettings_Base.lua"))
local globalBarScopedRegistry = Read(Join(ASSISTANT, "MSUF_AssistantRegistry_GlobalBarSettings_Scoped.lua"))
assert(settingsInstaller:find("AuraModel = C.AuraModel", 1, true)
        and settingsInstaller:find("ApplyAura = C.ApplyAura", 1, true),
    "custom-container layer registry is not connected to the production Auras3 model/apply context")
assert(globalBarBaseRegistry:find('RegisterBarsNumber("barOutlineLayer", "layer"', 1, true)
        and not globalBarBaseRegistry:find('RegisterBarsEnum("barOutlineStrata"', 1, true)
        and globalBarScopedRegistry:find('"barOutlineLayer", "layer", "Bar Outline Layer", "number", 0', 1, true)
        and not globalBarScopedRegistry:find('"barOutlineStrata", "strata"', 1, true),
    "Assistant still exposes Frame Outline Strata separately from Layer 0..30")
for _, ghostPath in ipairs({
    "/custom-container/effect/strata", "/group-workspace/lane/buff/layout/strata",
    "/group-workspace/lane/debuff/layout/strata", "/group-workspace/lane/externals/layout/strata",
    "/spell/frame/strata", "/spell/selected/strata", "/field/dispeloverlaystrata",
    "/corner/strata", "/outline/strata", "/custom-container/layout/strata",
}) do
    assert(not controlSchema:find(ghostPath, 1, true),
        "generated Assistant schema retained duplicate Strata control " .. ghostPath)
end
assert(controlSchema:find("/custom-container/effect/layer", 1, true)
        and controlSchema:find("/spell/frame/layer", 1, true)
        and controlSchema:find("/field/dispeloverlaylayer", 1, true)
        and controlSchema:find("/outline/layer", 1, true),
    "generated Assistant schema omitted a unified Layer 0..30 control")

-- The quiet white three-dot button is a shared hook, while the popup always reads the same
-- addon-wide cold collector. Keep this as a source contract instead of a full
-- Menu2/WoW widget mock.
local menuRoot = Join(ROOT, "MidnightSimpleUnitFrames_Options/Shell/Menu2")
local overviewPath = Join(menuRoot, "MSUF_Menu2_LayerOverview.lua")
assert(Exists(overviewPath), "global LayerOverview module is missing")
local overview = Read(overviewPath)
local menuXML = Read(Join(menuRoot, "MSUF_Menu2.xml"))
local widgets = Read(Join(menuRoot, "MSUF_Menu2_Widgets.lua"))
local support = Read(Join(menuRoot, "MSUF_Menu2_Support.lua"))
local window = Read(Join(menuRoot, "MSUF_Menu2_Window.lua"))
local aurasMenu = Read(Join(menuRoot, "Pages/MSUF_Menu2_Auras.lua"))
local groupAurasMenu = Read(Join(menuRoot, "Pages/MSUF_Menu2_GroupAuras.lua"))
local groupIndicatorsMenu = Read(Join(menuRoot, "Pages/MSUF_Menu2_GroupIndicators.lua"))
local groupBarsMenu = Read(Join(menuRoot, "Pages/MSUF_Menu2_GroupBars.lua"))
local globalBarsMenu = Read(Join(menuRoot, "Pages/MSUF_Menu2_GlobalBars.lua"))
local aurasModel = Read(Join(ROOT, "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))
local auraRuntime = Read(Join(ROOT, "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
local auraUnitRuntime = Read(Join(ROOT, "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
local groupConfig = Read(Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))
local groupIndicatorConfig = Read(Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua"))
local unitConfig = Read(Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua"))
local borderRuntime = Read(Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"))

assert(menuXML:find('<Script file="MSUF_Menu2_LayerOverview.lua"/>', 1, true),
    "Menu2 XML does not load the global LayerOverview module")
assert(widgets:find("local function AttachLayerOverviewButton", 1, true)
        and widgets:find('local LAYER_OVERVIEW_SHORTCUT_TEXT = "|cffffffff', 1, true)
        and widgets:find('T.Button(section, LAYER_OVERVIEW_SHORTCUT_TEXT, 34, 20, { noSearch = true })', 1, true)
        and widgets:find("AddThreeDotShortcutTextures(shortcut, LAYER_SHORTCUT_DOTS)", 1, true),
    "numeric layer sliders do not receive the shared white textured three-dot button")
assert(not widgets:find('W.RoleButton(section, "I", "success"', 1, true),
    "numeric layer sliders still use the old green I button")
assert(widgets:find("slider._msuf2LayerShortcutButton = shortcut", 1, true),
    "layer slider does not retain its single three-dot shortcut hook")
assert(widgets:find("local show = M.ShowLayerOverview or _G.MSUF_ShowLayerOverview", 1, true)
        and widgets:find("AttachLayerOverviewButton(section, slider, title, label, minVal, maxVal)", 1, true),
    "layer info buttons do not call the shared global overview")
assert(widgets:find("tonumber(minValue) ~= 0 or tonumber(maxValue) ~= 30", 1, true),
    "the shared three-dot hook is not restricted to numeric MSUF Layer 0..30 controls")
assert(widgets:find("control._msuf2LayerShortcutButton:SetShown(shown)", 1, true),
    "a conditionally hidden Layer control can leave its three-dot button behind")

assert(overview:find("function Overview.CollectLayerOverviewRows()", 1, true)
        and overview:find('ExportPublic("MSUF_CollectLayerOverviewRows"', 1, true),
    "LayerOverview numeric collector is not globally inspectable")
assert(overview:find("local popup = Overview.popup or CreatePopup()", 1, true)
        and overview:find('popup:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)', 1, true),
    "LayerOverview is not one reusable popup anchored above the clicked option")
assert(overview:find("local function CurrentLayerContext()", 1, true)
        and overview:find("PartitionForContext", 1, true)
        and overview:find('Tr("More")', 1, true),
    "LayerOverview does not prioritize the active Menu2 context behind a collapsed More row")
assert(support:find('field == "gfScope" or field == "auraScope"', 1, true)
        and support:find("M.RefreshLayerOverviewContext()", 1, true)
        and window:find("M.CallIf(M.RefreshLayerOverviewContext)", 1, true),
    "an open LayerOverview does not follow page and scope changes")
assert(window:find("M.CallIf(M.HideLayerOverview)", 1, true),
    "LayerOverview can outlive its owning Menu2 window")
assert(aurasModel:find("function Model.ReadLaneStrata(unit, kind)", 1, true)
        and aurasModel:find("function Model.WriteLaneStrata(unit, kind, value)", 1, true)
        and aurasModel:find("buffStrata = true", 1, true)
        and aurasModel:find("debuffStrata = true", 1, true),
    "legacy Unit Aura FrameStrata compatibility no longer persists through lane layout overrides")

-- Unified UX contract: each ordering surface exposes one numeric Layer 0..30
-- control. Blizzard FrameStrata stays an internal legacy compatibility field.
assert(aurasMenu:find('NumberRow("Layer (0-30)", "layer", "layer", 0, 30', 1, true),
    "regular Unit Aura lane lost its Layer 0..30 control")
assert(aurasMenu:find('"Layer (0-30)", "layer", 0, 30, 9', 1, true),
    "Custom Aura container lost its Layer 0..30 control")
assert(aurasMenu:find('"Layer (0-30)"', 1, true)
        and aurasMenu:find('custom-container.effect.layer', 1, true),
    "Custom Aura full-frame effect lost its Layer 0..30 control")
assert(groupAurasMenu:find('Slider("Layer (0-30)", 3, -146, 0, 30', 1, true),
    "Group Aura lanes lost their Layer 0..30 control")
assert(groupIndicatorsMenu:find('W.Slider(spells, Tr("Layer (0-30)"), 0, 30, 1, siRightW)', 1, true)
        and groupIndicatorsMenu:find('"Effect Layer (0-30)"', 1, true)
        and groupIndicatorsMenu:find('"ciLayer", 7', 1, true),
    "Group indicator icon, frame-effect, or corner Layer control regressed")
assert(groupBarsMenu:find('"Effect Layer (0-30)"', 1, true)
        and groupBarsMenu:find('"dispelOverlayLayer", 0', 1, true),
    "Group Dispel Overlay lost its Layer 0..30 control")
assert(globalBarsMenu:find('"Frame outline layer (0-30)"', 1, true)
        and globalBarsMenu:find('"barOutlineLayer", 0', 1, true),
    "Frame Outline lost its Layer 0..30 control")
assert(not aurasMenu:find('BindDropdown(ctx, section, "Strata"', 1, true),
    "Aura menus expose a duplicate Strata control beside Layer 0..30")
assert(not groupAurasMenu:find('W.Slider(section, "Strata"', 1, true),
    "Group Aura menus expose a duplicate Strata control beside Layer 0..30")
assert(not groupIndicatorsMenu:find('Tr("Frame Strata")', 1, true)
        and not groupIndicatorsMenu:find('Tr("Effect Strata")', 1, true),
    "Group indicator menus expose duplicate Frame/Effect Strata controls")
assert(not groupBarsMenu:find('"Effect Strata"', 1, true),
    "Group Bars exposes a duplicate Effect Strata control")
assert(not globalBarsMenu:find('_msuf2OutlineStrata', 1, true),
    "Global Bars exposes a duplicate Frame Outline Strata control")

assert(auraRuntime:find('layer = Round(ClampNumber(raw.layer, 0, 0, 30))', 1, true)
        and auraRuntime:find('(11 - priority) + layer', 1, true),
    "Aura full-frame effect Layer is not cold-compiled and applied at runtime")
assert(groupIndicatorConfig:find('layer = Layer(frame.layer, 0)', 1, true),
    "Group spell frame-effect Layer is not normalized by its cold compiler")
assert(groupConfig:find('dispelOverlayLayer = Layer(conf.dispelOverlayLayer, 0)', 1, true)
        and auraUnitRuntime:find('DISPEL_OVERLAY_EFFECT_OFFSET + (sensor.layer or 0)', 1, true),
    "Dispel Overlay Layer is not cold-compiled and applied")
assert(unitConfig:find('border.layer = max(0, min(30', 1, true)
        and groupConfig:find('local borderLayer = Layer(', 1, true)
        and borderRuntime:find('(offset or BORDER_LEVEL_DEFAULT) + (layer or 0)', 1, true),
    "Frame Outline Layer is not cold-compiled for Unit and Group frames")
assert(borderRuntime:find("Runtime event updates only", 1, true)
        and not borderRuntime:find("barOutlineLayer", 1, true),
    "Border runtime does not consume only the compiled generic Layer field")

local auraModelMSUF = {}
auraModelMSUF.ExportPublic = function(name, value) _G[name] = value; return value end
_G.MSUF_DB = { auras3 = { shared = {}, perUnit = {} } }
local auraModelChunk, auraModelLoadError = loadfile(Join(ROOT, "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))
assert(auraModelChunk, auraModelLoadError)
auraModelChunk("MidnightSimpleUnitFrames", auraModelMSUF)
local productionAuraModel = assert(auraModelMSUF.MSUF_Auras3.MenuModel)
assert(productionAuraModel.ReadLaneStrata("player", "buff") == "AUTO", "Unit Aura FrameStrata default changed")
productionAuraModel.WriteLaneStrata("player", "buff", "HIGH")
local playerAuraLayout = assert(_G.MSUF_DB.auras3.perUnit.player.layout)
assert(_G.MSUF_DB.auras3.perUnit.player.overrideLayout == true and playerAuraLayout.buffStrata == "HIGH",
    "Unit Aura FrameStrata did not write a Player-scoped layout override")
assert(productionAuraModel.ReadLaneStrata("player", "buff") == "HIGH",
    "Unit Aura FrameStrata did not read its scoped override")
productionAuraModel.WriteLaneStrata("player", "buff", "invalid")
assert(productionAuraModel.ReadLaneStrata("player", "buff") == "AUTO",
    "invalid Unit Aura FrameStrata was not normalized to AUTO")

assert(overview:find('placeholder:SetText(Tr("Search layers..."))', 1, true)
        and overview:find("SearchMatches", 1, true),
    "LayerOverview is missing its local layer search")
assert(overview:find("function Overview.SetLayerValue(row, value)", 1, true)
        and overview:find('ExportPublic("MSUF_SetLayerOverviewValue"', 1, true),
    "LayerOverview numeric rows are not directly editable")
assert(overview:find('Tr("EDITABLE: click a green Layer number', 1, true)
        and overview:find('Tr("EDIT: click green number")', 1, true),
    "LayerOverview no longer makes its numeric values visually explicit")
assert(overview:find('local layers = CollectRows()', 1, true)
        and not overview:find('local layers, strataRows = CollectRows()', 1, true)
        and not overview:find('Tr("editable FrameStrata values")', 1, true)
        and not overview:find('Tr("EDIT: click blue value")', 1, true),
    "LayerOverview still renders a second FrameStrata inventory")
assert(overview:find("popup:SetMovable(true)", 1, true)
        and overview:find("popup:SetResizable(true)", 1, true)
        and overview:find('popup:StartSizing("BOTTOMRIGHT")', 1, true),
    "LayerOverview is not mouse-movable and corner-resizable")
assert(not overview:find('SetScript("OnUpdate"', 1, true)
        and not overview:find("C_Timer.NewTicker", 1, true),
    "LayerOverview introduced continuous menu runtime work")

local requiredOverviewAreas = {
    "Unit Frames", "Unit Status", "Unit Auras",
    "Group Frames", "Group Status", "Group Bars", "Group Auras",
    "Spell Indicators", "Class Resources", "Global Bars",
}
for _, area in ipairs(requiredOverviewAreas) do
    assert(overview:find('area = "' .. area .. '"', 1, true),
        "global LayerOverview collector is missing the " .. area .. " area")
end

-- Load the cold collector without a WoW UI and verify the actual combined
-- result, not just provider source strings. Missing Custom/Dots records are
-- intentional: every editable slot must still appear as Layer 9 / off.
_G.MSUF_DB = {
    general = { nameTextLayer = 5, hpTextLayer = 5, powerTextLayer = 2 },
    player = { nameTextLayer = 99, showName = true },
    auras3 = { enabled = true, showPlayer = true, customContainers = { perUnit = {} } },
    gf_party = {
        enabled = true, ciEnabled = true, ciLayer = -4,
        dispelOverlayEnabled = true, dispelOverlayLayer = 31,
        spellIndicators = {
            enabled = true,
            specs = { test = { Aura = { enabled = true, layer = 9, strata = "AUTO", frame = { type = "border", layer = 4, strata = "HIGH" } } } },
        },
    },
    gf_raid = {},
    gf_mythicraid = {},
    bars = { classPowerFrameLevelOffset = 31, barOutlineLayer = -2 },
}
local overviewMSUF = { MSUF2 = {} }
overviewMSUF.ExportPublic = function(name, value)
    _G[name] = value
    return value
end
local overviewChunk, overviewLoadError = loadfile(overviewPath)
assert(overviewChunk, overviewLoadError)
overviewChunk("MidnightSimpleUnitFrames", overviewMSUF)
local layerRows = assert(_G.MSUF_CollectLayerOverviewRows)()
assert(type(layerRows) == "table" and #layerRows > 100, "global Layer collector returned an incomplete inventory")

local actualAreas, rowsById, emptyCustomDefaults = {}, {}, 0
for _, row in ipairs(layerRows) do
    assert(type(row.layer) == "number" and row.layer >= 0 and row.layer <= 30 and row.layer == math.floor(row.layer),
        "Layer collector emitted a value outside the 0..30 integer contract: " .. tostring(row.id))
    actualAreas[row.area] = true
    rowsById[row.id] = row
    assert(type(row.edit) == "table", "numeric Layer row is not editable: " .. tostring(row.id))
    if tostring(row.id):match("^auras3%.[^.]+%.custom%.[1234]%.layer$") then
        assert(row.layer == 9 and row.enabled == false, "missing Custom Aura slot did not remain Layer 9 / off")
        emptyCustomDefaults = emptyCustomDefaults + 1
    end
end
-- Target/Focus/Boss expose Custom 1-3 plus Dots on target; the player frame has
-- no Dots on target container and stops at Custom 3.
assert(emptyCustomDefaults == 15, "combined Layer collector must expose all 15 empty Custom/Dots slots")
assert(rowsById["auras3.player.custom.4.layer"] == nil,
    "Layer collector still exposes a player Dots on target slot")
assert(rowsById["unit.player.nameTextLayer"].layer == 30, "combined Layer collector did not clamp an upper sentinel")
assert(rowsById["group.party.ciLayer"].layer == 0, "combined Layer collector did not clamp a lower sentinel")
assert(rowsById["class-resources.classPowerFrameLevelOffset"].layer == 30,
    "combined Layer collector did not clamp the Class Resource sentinel")
assert(rowsById["group.party.dispelOverlayLayer"].layer == 30,
    "combined Layer collector did not clamp the Dispel Overlay Layer")
assert(rowsById["group.party.spellIndicators.test.Aura.frame.layer"].layer == 4,
    "combined Layer collector omitted the Spell Indicator frame-effect Layer")
assert(rowsById["bars.shared.barOutlineLayer"].layer == 0,
    "combined Layer collector did not clamp the Frame Outline Layer")

local setLayer = assert(_G.MSUF_SetLayerOverviewValue)
assert(setLayer(rowsById["unit.player.nameTextLayer"], 17), "direct Unit Layer edit failed")
assert(_G.MSUF_DB.player.nameTextLayer == 17, "direct Unit Layer edit did not update the profile")
assert(setLayer(rowsById["group.party.auras.buff.layer"], 13), "direct nested Group Layer edit failed")
assert(_G.MSUF_DB.gf_party.auras.buff.layer == 13, "direct nested Group Layer edit wrote the wrong path")
assert(setLayer(rowsById["class-resources.classPowerFrameLevelOffset"], 11), "direct Class Resource Layer edit failed")
assert(_G.MSUF_DB.bars.classPowerFrameLevelOffset == 11, "direct Class Resource Layer edit did not update bars")

local laneWrite, customItem = nil, { layer = 9, frame = { layer = 0 } }
overviewMSUF.MSUF_Auras3 = { MenuModel = {
    WriteLaneLayer = function(scope, lane, value) laneWrite = { scope, lane, value } end,
    CustomContainer = function() return customItem end,
} }
assert(setLayer(rowsById["auras3.player.buffLayer"], 14), "direct Unit Aura lane edit failed")
assert(laneWrite and laneWrite[1] == "player" and laneWrite[2] == "buff" and laneWrite[3] == 14,
    "direct Unit Aura lane edit did not use the Auras3 model")
assert(setLayer(rowsById["auras3.player.custom.1.layer"], 12), "direct Custom Aura Layer edit failed")
assert(customItem.layer == 12, "direct Custom Aura Layer edit did not update the selected container")
assert(setLayer(rowsById["auras3.player.custom.1.frame.layer"], 18), "direct Custom Aura frame-effect Layer edit failed")
assert(customItem.frame.layer == 18, "direct Custom Aura frame-effect Layer edit wrote the wrong field")
assert(setLayer(rowsById["group.party.dispelOverlayLayer"], 16), "direct Dispel Overlay Layer edit failed")
assert(_G.MSUF_DB.gf_party.dispelOverlayLayer == 16, "direct Dispel Overlay Layer edit wrote the wrong field")
local lastGeneralApply
overviewMSUF.MSUF2.RequestGeneralApply = function(reason, opts) lastGeneralApply = { reason = reason, opts = opts } end
assert(setLayer(rowsById["bars.focus.barOutlineLayer"], rowsById["bars.focus.barOutlineLayer"].layer),
    "same-as-inherited Frame Outline Layer did not activate the Focus bars override")
assert(_G.MSUF_DB.focus.hlOverride == true and _G.MSUF_DB.focus.barOutlineLayer == 0,
    "direct Focus Frame Outline Layer edit did not persist its bars override")
assert(setLayer(rowsById["bars.gf_mythicraid.barOutlineLayer"], 12),
    "direct Mythic Raid Frame Outline Layer edit failed")
assert(_G.MSUF_DB.gf_raid.hlOverride == true and _G.MSUF_DB.gf_raid.barOutlineLayer == 12
        and _G.MSUF_DB.gf_mythicraid.hlOverride == true and _G.MSUF_DB.gf_mythicraid.barOutlineLayer == 12,
    "Raid/Mythic Raid Frame Outline Layer edit did not activate the coupled bars overrides")
assert(lastGeneralApply and lastGeneralApply.opts and lastGeneralApply.opts.barsScope == "gf_raid",
    "Mythic Raid Frame Outline Layer edit did not refresh the coupled Raid/Mythic Raid scope")
assert(setLayer(rowsById["bars.shared.barOutlineLayer"], 7), "direct Frame Outline Layer edit failed")
assert(_G.MSUF_DB.bars.barOutlineLayer == 7, "direct Frame Outline Layer edit wrote the wrong field")

local strataRows = assert(_G.MSUF_CollectFrameStrataRows)()
local strataById = {}
for _, row in ipairs(strataRows) do strataById[row.id] = row end
local setStrata = assert(_G.MSUF_SetStrataOverviewValue)
assert(setStrata(strataById["bars.target.barOutlineStrata"], strataById["bars.target.barOutlineStrata"].strata),
    "same-as-inherited Frame Outline Strata did not activate the Target bars override")
assert(_G.MSUF_DB.target.hlOverride == true and _G.MSUF_DB.target.barOutlineStrata == "AUTO",
    "direct Target Frame Outline Strata edit did not persist its bars override")
assert(setStrata(strataById["bars.gf_raid.barOutlineStrata"], "HIGH"),
    "direct Raid Frame Outline Strata edit failed")
assert(_G.MSUF_DB.gf_raid.hlOverride == true and _G.MSUF_DB.gf_raid.barOutlineStrata == "HIGH"
        and _G.MSUF_DB.gf_mythicraid.hlOverride == true and _G.MSUF_DB.gf_mythicraid.barOutlineStrata == "HIGH",
    "Raid/Mythic Raid Frame Outline Strata edit did not activate the coupled bars overrides")
assert(lastGeneralApply and lastGeneralApply.opts and lastGeneralApply.opts.barsScope == "gf_raid",
    "Raid Frame Outline Strata edit did not refresh the coupled Raid/Mythic Raid scope")
for _, area in ipairs(requiredOverviewAreas) do
    assert(actualAreas[area], "combined Layer collector omitted the " .. area .. " area")
end

local count = 0
for _, setting in pairs(layerSettings) do
    AssertLayerContract(setting, setting.key)
    count = count + 1
end
assert(count == 26, "focused layer inventory changed; expected 7 detached + 16 custom/Dots + 3 external settings")

print("layer_contract_smoke: ok (26 Assistant MSUF Layer settings, 0..30/step 1)")

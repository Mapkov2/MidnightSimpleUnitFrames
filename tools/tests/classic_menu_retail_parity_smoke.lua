local root = assert(arg[1], "repo root missing")

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- Classic loads the Retail aura page, its Group and Preview siblings and the
-- shared Custom workspace (MSUF_Menu2_AfterGroupPreview_Classic.xml).
local auras = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Group.lua")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace.lua")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Preview.lua")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AuraSettings.lua")
    .. Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AuraControls.lua")
for _, contract in ipairs({
    "labelHitWhenDisabled",
    "CUSTOM_DISPLAY_MODES",
    "reminderEnabled",
    "CLASSIC_AURA_FILTERS_REDUCED",
}) do
    assert(auras:find(contract, 1, true),
        "Classic Aura menu lost the current Retail contract: " .. contract)
end
-- The dispel preview helper is not Retail-only. The Classic aura backend
-- publishes its own, which is what lets the shared unit aura preview
-- (MSUF_Menu2_UnitPreview_Auras.lua, loaded by the Classic manifest) call it on
-- every client. classic_aura_render_smoke.lua drives the values it returns.
local classicAuraVisuals = Read("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
assert(classicAuraVisuals:find("function A3.PreviewDispelTypeForIndex(index)", 1, true),
    "Classic aura visuals no longer publish the dispel preview helper the shared previews call")

local unit = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua")
for _, contract in ipairs({ "statusAFKTimer", "statusPetHappiness", "showStanceIndicator" }) do
    assert(unit:find(contract, 1, true),
        "Classic Unit menu lost a Retail/Classic status contract: " .. contract)
end

local status = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua")
assert(status:find("identityRestrictionWarning", 1, true),
    "Classic status menu lost the current Retail identity warning")
-- Retail b2abf551: the ::: text shortcut is the single status text-color entry
-- point, so it carries the color search and the placement swatch is gone.
assert(status:find("status.selected.text_settings", 1, true),
    "Classic status menu no longer registers the ::: text shortcut for search")
assert(not status:find('W.Color(placementCard, "Text color")', 1, true),
    "Classic status menu brought back the duplicate placement text-color swatch")

-- Classic loads the shared preview specs: the client model decides the Pet
-- Happiness row (classic_pet_happiness_smoke.lua runs it per flavor).
local previewManifest = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Classic.xml")
assert(previewManifest:find('<Script file="MSUF_Menu2_UnitPreview_Specs.lua"/>', 1, true),
    "Classic unit preview manifest no longer loads the shared preview specs")
local specs = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua")
assert(specs:find("statusPetHappiness", 1, true) and specs:find("stance|showStanceIndicator", 1, true),
    "Classic preview specs do not combine Pet Happiness with the current Retail stance preview")

local search = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua")
assert(search:find("exactTargetContracts, haystack", 1, true),
    "Classic search index is still on the legacy pre-Retail column format")
for _, contract in ipairs({
    "Custom Container > Reminder",
    "statusPetHappiness",
    "statusAFKTimer",
    "stance=player.showStanceIndicator",
}) do
    assert(search:find(contract, 1, true),
        "Classic search index is missing a current menu contract: " .. contract)
end
assert(not search:find("status%2Eselected%2Etext_color", 1, true),
    "Classic search index still lists the removed placement status text-color swatch")
-- Settings the Classic menu no longer builds must not stay searchable.
for _, key in ipairs({
    "showGCDBar", "showGCDBarTime", "showGCDBarSpell",
    "empowerColorStages", "empowerStageBlink", "empowerStageBlinkTime",
    "tooltipShowAuraSpellIDs", "tooltipShowAuraCasterNames",
}) do
    assert(not search:find("\tgeneral." .. key .. "\t", 1, true),
        "Classic search index lists a setting with no Classic control: general." .. key)
end

for _, key in ipairs({ "menuAppearancePreset", "menuBackgroundOpacity" }) do
    assert(search:find("\tgeneral." .. key .. "\t", 1, true),
        "Classic search index is missing a universal menu setting: general." .. key)
end

local aurasPage = (Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"):gsub("\r\n", "\n"))
local aurasGroupPage = (Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Group.lua"):gsub("\r\n", "\n"))
local groupAurasPage = (Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua"):gsub("\r\n", "\n"))
-- The Retail group filter builder stays unreachable: the Group Auras page is the
-- only caller of the lane workspace and always asks for the compact tools,
-- which return before BuildGroupFilters.
local _, workspaceCalls = groupAurasPage:gsub("BuildAuras3GroupLaneWorkspace%(", "")
assert(workspaceCalls == 1 and groupAurasPage:find(
    "M.BuildAuras3GroupLaneWorkspace(ctx, auraBuilder, scope, lane, { tool = tool, compact = true })", 1, true),
    "the Group Auras page no longer builds the lane workspace only in its compact form")
local compactAt = assert(aurasGroupPage:find("\n[ \t]*if opts and opts%.compact == true then\n"),
    "the group lane workspace lost its compact dispatch")
assert(aurasGroupPage:find("\n[ \t]*return\n[ \t]*end\n[ \t]*BuildGroupFilters%(ctx, b, scope, lane, opts%)\n", compactAt),
    "the compact group lane workspace no longer returns before the Retail group filter builder")
-- No Classic runtime renders the lane Full-Frame Effect, so the Classic flavors
-- skip its section and its badge; whole live source lines, so a commented-out,
-- disabled or inverted guard fails.
assert(aurasPage:find("\n[ \t]*if M%.CLASSIC_AURA_FILTERS_REDUCED ~= true then BuildUnitStyleFrameEffect%(S%) end\n"),
    "Classic Aura menu exposes the lane Full-Frame Effect section that no Classic runtime renders")
local _, frameEffectMentions = aurasPage:gsub("BuildUnitStyleFrameEffect%(S%)", "")
assert(frameEffectMentions == 2 and aurasPage:find("\nlocal function BuildUnitStyleFrameEffect(S)\n", 1, true),
    "the lane Full-Frame Effect section is built outside its Classic gate")
assert(aurasPage:find("\n[ \t]*if M%.CLASSIC_AURA_FILTERS_REDUCED ~= true then\n[ \t]*local effectType = tostring%(ReadEffectValue%(\"Type\", \"none\"%)%)\n"),
    "the lane Full-Frame Effect badge is not gated with its section")
-- Whole live source lines, so a commented-out, disabled or inverted guard fails.
-- classic_aura_menu_filters_smoke.lua drives the same setter for behaviour.
assert(aurasPage:find('\n[ \t]*if value == true and lane == "debuff" then Model%.WriteFilter%(unit, lane, "nonPlayer", false%) end\n'),
    "Classic Only mine no longer clears the mutually exclusive nonPlayer debuff filter")
local shadowAlphaAt = assert(aurasPage:find('iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)"', 1, true),
    "Classic Aura menu lost the shared icon-style Shadow Alpha slider")
local gateRefreshAt = assert(aurasPage:find("\n[ \t]*if appearanceGlobalsOnly then\n[ \t]*%-%-[^\n]*\n[ \t]*%-%-[^\n]*\n[ \t]*%-%-[^\n]*\n[ \t]*M%.TrackRefresh%(ctx, function%(%) iconStyleGates%.Apply%(true%) end%)\n[ \t]*end\n", shadowAlphaAt),
    "Classic icon-style gates are not refreshed on every Appearance page")
local buffOnlyAt = assert(aurasPage:find('if appearanceGlobalsOnly and previewContainer == "buff" then', shadowAlphaAt, true),
    "Classic Aura menu lost the Buff-only Native Aura Flow section")
assert(gateRefreshAt < buffOnlyAt,
    "Classic icon-style gate refresh must be registered before the Buff-only Native Aura Flow section")
local _, gateApplyCount = aurasPage:gsub("iconStyleGates%.Apply%(true%)", "")
assert(gateApplyCount == 1,
    "Classic icon-style gates must be re-applied from exactly one Appearance refresher")

-- Pandemic Warning & Style is a native aura-backend feature. The shared Custom
-- workspace is on every client, so it builds the section behind the backend's
-- own capability and Midnight and WoW Forever keep it unchanged.
local workspace = (Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace.lua"):gsub("\r\n", "\n"))
assert(workspace:find('\n[ \t]*if isTargetDots and PandemicVisualSupported%(%) then\n'),
    "Custom workspace builds Pandemic Warning & Style without the aura backend capability gate")
assert(workspace:find('\n[ \t]*return type%(A3%.ApplyPandemicVisual%) == "function"\n'),
    "The Pandemic capability no longer asks the aura backend for its applier")
-- The premise of that gate: no Classic flavor loads the applier.
local flavorExclusions = Read("tools/classic-flavor-load-exclusions.tsv")
assert(flavorExclusions:find(
    "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua\t*\t", 1, true),
    "The Pandemic applier is no longer excluded from every Classic flavor, so its menu gate needs a rethink")

local function ReadLF(relativePath)
    return (Read(relativePath):gsub("\r\n", "\n"))
end
local function CountPlain(haystack, needle)
    local count, at = 0, 1
    while true do
        local _, finish = haystack:find(needle, at, true)
        if not finish then return count end
        count, at = count + 1, finish + 1
    end
end

-- Castbar sections that no Classic client can drive stay off the page.
local castbars = ReadLF("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
for _, contract in ipairs({
    "if GCDBarSupported() then",
    "GetSpellCooldownDuration",
    "SetTimerDuration",
    -- Empowered Casts follows the capability (WoW Forever has no Evoker either);
    -- a harness that fakes only IsClassic still hides the section.
    "client.HasEmpoweredCasts ~= false and client.IsClassic ~= true) then",
    'M.SupportsFrameScope("focus") then',
}) do
    assert(castbars:find(contract, 1, true),
        "Classic Castbar page lost a client capability gate: " .. contract)
end

-- Only the Mainline TOC loads Runtime/MSUF_TooltipSpellIDs.lua.
local misc = ReadLF("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua")
assert(misc:find('\n[ \t]*if IS_MAINLINE then\n[ \t]*local tooltipSpellIDs = BindMiscToggle%(tooltips, "Show spell IDs in aura tooltips"'),
    "Misc page builds the Mainline-only aura tooltip spell-ID switch outside the IS_MAINLINE gate")

-- UnitSections hides "Reset section" for every section whose fields are missing.
local sections = ReadLF("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local sectionFieldCount = 0
for key in sections:gmatch("fields = fields%.([%w_]+)") do
    sectionFieldCount = sectionFieldCount + 1
    assert(unit:find(key .. " = table.concat(COPY_", 1, true),
        "Classic Unit page does not publish SectionFields." .. key .. ", so its Reset section action is hidden")
end
assert(sectionFieldCount >= 6, "MSUF_Menu2_UnitSections.lua no longer reads the SectionFields contract")
assert(unit:find("loadCondShowWhenInjured loadCondActive", 1, true),
    "Classic Load Conditions copy and reset skip loadCondShowWhenInjured")

-- Arena preview branches from the Mainline Render, and Retail 7f0aa2c6 guides.
local render = ReadLF("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
for _, contract in ipairs({
    '(key == "arena" and "Greater Pyroblast")',
    '(key == "arena" and g.showArenaCastTime ~= false)',
    "timeX = -2 + (tonumber(g.arenaCastTimeOffsetX) or 0)",
    "timeY = tonumber(g.arenaCastTimeOffsetY) or 0",
    '((key == "boss" or key == "arena") and 180 or (key == "focus" and 180 or 275))',
    '((key == "boss" or key == "arena") and 30 or (key == "focus" and 30 or 40))',
    'ReadCastbarSize(key, g, w, (key == "boss" or key == "arena") and 12 or 18)',
    'if (key == "boss" or key == "arena")\n',
    '(key == "target" or key == "boss" or key == "arena" or key == "focus" or key == "focustarget")',
    "box.layerVisibility.guides = g.unitPreviewGuidesEnabled == true",
}) do
    assert(render:find(contract, 1, true),
        "Classic unit preview lost an Arena or Retail parity branch: " .. contract)
end
assert(CountPlain(render, '(key == "arena" and "arena1")') == 2,
    "Classic unit preview must resolve arena to arena1 for the live frame and the spell-name shortener")
assert(CountPlain(render, '(key == "arena" and g.showArenaCastTargetName == true)') == 2,
    "Classic unit preview must honor showArenaCastTargetName in the castbar details and the footprint")
assert(CountPlain(render, 'elseif key == "boss" or key == "arena" then') == 2,
    "Classic unit preview must anchor the Arena castbar below the frame in both the footprint and the render")
local classicDefaults = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
assert(classicDefaults:find("g.unitPreviewGuidesEnabled = false", 1, true)
    and classicDefaults:find("g.classPowerPreviewGuidesEnabled = false", 1, true),
    "Classic factory profile no longer starts the previews with the Guides layer off")
assert(not classicDefaults:find("PreviewGuidesEnabled = true", 1, true),
    "Classic factory profile forces a preview Guides layer back on")

print("Classic Menu2 Retail parity smoke passed")

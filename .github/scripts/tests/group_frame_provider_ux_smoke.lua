local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local checks = 0
local function Contains(source, needle, label)
    checks = checks + 1
    assert(source:find(needle, 1, true), label)
end
local function Omits(source, needle, label)
    checks = checks + 1
    assert(not source:find(needle, 1, true), label)
end

local specs = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua")
for _, value in ipairs({ "MSUF", "AUTO", "SHOW", "NONE" }) do
    Contains(specs, 'value = "' .. value .. '"', "missing frame-provider value " .. value)
end
Contains(specs, 'text = "Blizzard frames (WoW settings)"', "normal Blizzard ownership is not named clearly")
Contains(specs, 'text = "Force Blizzard frames"', "forced Blizzard ownership is not exposed")
Contains(specs, "tooltipTitle", "frame-provider entries have no hover titles")
Contains(specs, "tooltip =", "frame-provider entries have no hover explanations")

local group = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
Contains(group, "local function FrameProvider(kind)", "combined provider getter is missing")
Contains(group, "local function SetFrameProvider(kind, provider)", "combined provider setter is missing")
Contains(group, "conf.enabled = nextEnabled", "provider setter does not update MSUF ownership")
Contains(group, "conf.blizzardFallbackMode = provider", "provider setter does not update Blizzard fallback ownership")
Contains(group, 'Frame providers | Party: ', "all-scope provider summary is missing")

local layout = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua")
Contains(layout, '"Frames used in this scope"', "combined provider dropdown is missing")
Contains(layout, "FrameProviderTooltip(CurrentScope())", "selected provider has no hover explanation")
Contains(layout, "Party, Raid, and Mythic Raid are independent.", "scope independence is not explained")
Contains(layout, "RefreshFrameBasicsProviderHeader", "provider header does not share the live scope resolver")
Contains(layout, 'M.AddRefresherOnce(ctx, "group-frame-basics-provider-header"', "collapsed provider header is not refreshed on scope changes")
Contains(layout, 'hint = "MSUF provider"', "collapsed Mythic/Raid header does not identify MSUF ownership")
Omits(layout, '"If this switch is off"', "legacy two-control ownership UX is still visible")
Omits(layout, 'W.SwitchAt(general, "Use MSUF group frames"', "legacy MSUF ownership switch is still visible")
Omits(layout, "another MSUF group scope is on", "menu still claims inactive scopes override the live scope")

local dropdowns = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Dropdowns.lua")
Contains(dropdowns, 'row:SetScript("OnEnter", ShowDropdownItemTooltip)', "dropdown rows do not show item help on hover")
Contains(dropdowns, 'row:SetScript("OnLeave"', "dropdown row help is not dismissed on mouse leave")

local runtime = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua")
Contains(runtime, "local function MSUFOwnsLiveGroupFrames()", "live-context ownership resolver is missing")
Contains(runtime, "local msufOwnsGroupFrames = MSUFOwnsLiveGroupFrames()", "Blizzard ownership does not use the live context")

print(string.format("group_frame_provider_ux_smoke: %d checks passed", checks))

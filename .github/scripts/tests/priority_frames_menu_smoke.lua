-- Contract: Priority Frames is a profile-wide fifth Group tab with event-driven
-- Menu2 refresh, managed key capture, bounded row reuse, and no polling.
local root = arg and arg[1] or "."

local function Read(path)
  local file = assert(io.open(root .. "/" .. path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function Has(source, token, message)
  assert(source:find(token, 1, true), (message or "missing contract") .. ": " .. token)
end

local page = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua")
local group = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Group.lua")
local nav = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Navigation.lua")
local xml = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml")
local keywords = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_Keywords.lua")
local routing = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua")
local faq = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_FAQ_Catalog_02.lua")
local window = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua")
local bindings = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua")
local enUS = Read("MidnightSimpleUnitFrames/Locales/enUS.lua")
local deDE = Read("MidnightSimpleUnitFrames/Locales/deDE.lua")

Has(xml, 'Pages\\MSUF_Menu2_GroupPriority.lua', "Priority page is not loaded")
Has(group, '{ key = "gf_priority"', "Priority is not the fifth Group workspace tab")
Has(group, 'priorityMode = opts.priorityMode == true', "Priority top bar still depends on Group scope")
Has(group, 'Profile-wide', "Priority top bar does not explain ownership")
Has(nav, 'gf_priority = "gf_layout"', "Priority page is not owned by the Group nav item")
Has(nav, 'gf_priority = "Priority"', "Priority breadcrumb label missing")
Has(page, 'M.RegisterPage("gf_priority"', "Priority page registration missing")
Has(page, 'ScopeSection(ctx, b, { priorityMode = true })', "Priority page uses Party/Raid scope controls")

for _, api in ipairs({
  "GetPriorityConf", "GetPriorityMenuSnapshot", "GetPriorityState", "GetPriorityPinView", "GetPriorityPins",
  "SetPriorityOption", "RemovePriorityPin", "MovePriorityPin", "ClearPriorityPins",
  "RequestPriorityApply", "RegisterPriorityListener",
  "UnregisterPriorityListener", "MSUF_GetManagedBindingKeys", "MSUF_SetManagedBinding",
  "MSUF_ClearManagedBinding",
}) do
  Has(page, api, "Priority Menu2 runtime API is not connected")
end

Has(page, 'local PIN_ROWS_PER_PAGE = 5', "Priority pin row pool is not bounded")
Has(page, 'for i = 1, PIN_ROWS_PER_PAGE do', "Priority pin rows are not reused")
Has(page, 'ctx.wrapper:HookScript("OnShow", RegisterListener)', "Priority listener is not visibility-scoped")
Has(page, 'ctx.wrapper:HookScript("OnHide", UnregisterListener)', "Priority listener is retained while hidden")
Has(page, 'code == "CONFLICT"', "Keybinding conflict confirmation missing")
Has(page, 'key == "BACKSPACE" or key == "DELETE"', "Accessible binding clear missing")
Has(page, '"MOUSEWHEELUP" or "MOUSEWHEELDOWN"', "Mouse-wheel binding capture missing")
Has(page, 'state.baseFramesEnabled == false', "Overview does not explain the active base-frame dependency")
Has(page, 'entry.waitingReason == "NOT_IN_GROUP"', "Saved pins do not distinguish being outside a group")
Has(page, 'entry.waitingReason == "NOT_PRESENT"', "Saved pins do not distinguish absence from the current group")
Has(page, 'entry.waitingReason == "GROUP_FRAMES_DISABLED"', "Saved pins claim to be visible while base frames are disabled")
Has(page, 'entry.waitingReason == "DISABLED"', "Saved pins lack a disabled-feature waiting state")
Has(page, 'Could not update that keybinding.', "Binding write failures have no user feedback")
Has(page, 'M.TrackRefresh(ctx, RefreshSnapshot)', "Priority panels do not share one menu snapshot")
assert(page:find('M.TrackRefresh(ctx, RefreshSnapshot)', 1, true)
  < page:find('TrackSectionRefresh(ctx, overview, RefreshOverview)', 1, true),
  "Priority snapshot must run before panel refreshers")
Has(page, '"Preview in Edit Mode"', "Disabled Priority Frames do not advertise the Edit Mode placeholder truthfully")
Has(page, '"Priority Frames remain disabled; Edit Mode is showing the placement preview."', "Disabled Edit Mode feedback is misleading")
Has(page, 'M.RunWithHistory', "Profile-owned Priority settings bypass Menu2 history")
Has(page, 'Waiting — enable Party frames first.', "Party base-frame dependency is not explained")
Has(page, 'Waiting — enable the active Raid or Mythic Raid frames first.', "Raid base-frame dependency is not explained")
Has(page, 'Ready — join a party or raid to show Priority Frames.', "solo waiting state is still raid-only")
Has(page, 'Right of group frames', "placement labels are still raid-only")
Has(page, 'Hover an MSUF Party, Raid, or Priority frame', "Party mouseover workflow is undocumented")
Has(page, 'Use the hover hotkey above to add or remove players.', "honest hover-hotkey guidance is missing")
assert(not page:find("shown only in raids", 1, true)
  and not page:find("Ready — join a raid to show Priority Frames.", 1, true)
  and not page:find("No manual pins yet. Join a raid", 1, true)
  and not page:find("Pin mouseover", 1, true)
  and not page:find("TogglePriorityMouseover", 1, true),
  "Priority Menu2 retained misleading raid-only UX")
assert(not page:find('SetScript("OnUpdate"', 1, true), "Priority Menu2 page polls with OnUpdate")
assert(not page:find("C_Timer.NewTicker", 1, true), "Priority Menu2 page owns a ticker")
assert(not page:find("QueueGF(", 1, true), "Priority Menu2 rebuilds normal group headers")

Has(keywords, "gf_priority", "Priority search keywords missing")
Has(keywords, "party priority frames", "Party Priority search keywords missing")
Has(keywords, "dungeon priority frames", "Dungeon Priority search keywords missing")
Has(routing, "who_appears=pin player", "Priority pin search routing missing")
Has(routing, "placement=priority placement", "Priority placement search routing missing")
Has(faq, '"How do Priority Frames work?"', "Priority feature help is not searchable")
Has(faq, '"gf_priority", "Opens: Group Frames > Priority"', "Priority help does not open the feature page")
Has(faq, "In a party they inherit Party Frames", "Priority FAQ does not explain Party behavior")
Has(window, '"PLAYER_SPECIALIZATION_CHANGED", "UPDATE_BINDINGS"', "Visible Menu2 state events do not refresh Priority state")
Has(bindings, "gf_priority = GROUP_RESET_INFO", "Priority page reset mapping missing")
Has(bindings, 'ReplaceRootTable(db, defaults, "gf_priority")', "Priority reset fallback missing")

for _, locale in ipairs({ enUS, deDE }) do
  Has(locale, 'L["Waiting — enable Party frames first."]', "Party waiting locale missing")
  Has(locale, 'L["Saved · Party frames disabled"]', "Party pin-state locale missing")
  Has(locale, 'L["Right of group frames"]', "generic placement locale missing")
  Has(locale, 'L["Use the hover hotkey above to add or remove players."]', "hover-hotkey hint locale missing")
end

print("PASS priority frames Menu2: Party/Raid UX, live listener, managed hotkey, pooled pins, search/reset wiring, zero polling")

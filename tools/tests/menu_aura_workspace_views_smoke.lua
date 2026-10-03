-- menu_aura_workspace_views_smoke.lua <repoRoot> <flavor> [report]
--
-- WoW never frees a frame. The aura workspaces used to rebuild their whole
-- page for every Container:, Edit: or lane click and for every list edit, so
-- each click left the old page tree behind for the session (review R7: about
-- 136 frames per click on uf_target, 216 on gf_auras). Contract:
--   1. the unit page workspace (Container: x Edit:), the group workspace
--      (scope x Container: x Edit:) and the Global Aura Appearance selector
--      are declared views (spec.variantKey): once every view has been shown,
--      clicking through all of them again creates no frame or region, shows
--      the very entry built for that view, keeps the reader's scroll and
--      paints the selectors with the view's own value;
--   2. a view shown again from its cache looks exactly like a fresh build of
--      that view, including data changed while another view was on screen
--      (the Setup tool's whitelist count after a Whitelist edit);
--   3. adding and removing a custom whitelist spell and a group blacklist
--      spell repaints in place: after the first row exists, add/remove cycles
--      create nothing, keep the page entry and show the list as saved; undo
--      of an add repaints in place as well;
--   4. a search route that only changes a page's declared view state switches
--      views without invalidating the page, so repeated hops create nothing;
--   5. an edit that changes which controls the tools build (the custom aura
--      type) still rebuilds the page.
-- Pass "report" to print the frame counts.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local report = arg[3] == "report"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_aura_workspace_views_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, core = mw.M, mw.env, mw.core
local widgets = mw.world.widgets
env.StaticPopup_Show = function() return nil end
-- The queued unit-frame, module and class-power applies read runtime APIs the
-- harness only stubs; this contract is about the menu's own frames.
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ApplyModules = function() return true end
env.MSUF_ClassPower_Apply = function() return true end
local Model = Check(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel, "the Auras3 menu model did not load")

local function Settle() widgets:RunTimers() end
-- Frames plus their textures and font strings: regions leak with a tree too.
local function WidgetCount()
    local total = #widgets.frames
    for i = 1, #widgets.frames do total = total + #(widgets.frames[i].regions or {}) end
    return total
end
local lines = {}
local function Note(label, value) lines[#lines + 1] = string.format("  %-52s %s", label, tostring(value)) end

local invalidations = {}
do
    local invalidate = M.InvalidatePage
    M.InvalidatePage = function(key, ...)
        if key then invalidations[key] = (invalidations[key] or 0) + 1 end
        return invalidate(key, ...)
    end
end

local function Walk(frame, visit)
    visit(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.parent == frame then Walk(child, visit) end
    end
end
local function ShownWithin(frame, stop)
    while frame and frame ~= stop do
        if frame.shown == false then return false end
        frame = frame.parent
    end
    return true
end
local function IsBar(frame, label)
    return frame.buttons and frame.values and frame.label and frame.label:GetText() == label
end
-- A docked page header is reparented to the shared header host and names its
-- page through _msuf2PageOwnerWrapper.
local function DockedIn(frame, wrapper)
    local current = frame
    while current do
        if current.shown == false then return false end
        if current._msuf2PageOwnerWrapper == wrapper then return true end
        current = current.parent
    end
    return false
end
local function Bar(entry, label)
    local found
    Walk(entry.wrapper, function(frame)
        if not found and IsBar(frame, label) and ShownWithin(frame, entry.wrapper) then found = frame end
    end)
    if found then return found end
    for _, frame in ipairs(widgets.frames) do
        if IsBar(frame, label) and DockedIn(frame, entry.wrapper) then return frame end
    end
end
local function BarValues(bar)
    local values = {}
    for i = 1, #bar.buttons do
        local button = bar.buttons[i]
        if button.enabled ~= false then values[#values + 1] = button._msuf2Value end
    end
    return values
end
local function ActiveValue(bar)
    local active
    for i = 1, #bar.buttons do
        if bar.buttons[i]._msuf2Active == true then
            Check(active == nil, "a selector shows two active values")
            active = bar.buttons[i]._msuf2Value
        end
    end
    return active
end
local function ClickValue(bar, value)
    for i = 1, #bar.buttons do
        local button = bar.buttons[i]
        if button._msuf2Value == value then
            button:GetScript("OnClick")(button, "LeftButton")
            Settle()
            return
        end
    end
    error("selector has no value " .. tostring(value))
end
-- What a reader sees on a page entry: every shown text, check state, value and
-- selector highlight, in creation order. Frame identity is left out.
local function Signature(entry)
    local parts = {}
    Walk(entry.wrapper, function(frame)
        if not ShownWithin(frame, entry.wrapper) then return end
        if frame.checked ~= nil then parts[#parts + 1] = "c=" .. tostring(frame.checked and true or false) end
        if frame._msuf2Active ~= nil then parts[#parts + 1] = "a=" .. tostring(frame._msuf2Active) end
        for _, region in ipairs(frame.regions or {}) do
            if region.shown ~= false and type(region.text) == "string" and region.text ~= "" then
                parts[#parts + 1] = region.text
            end
        end
    end)
    return table.concat(parts, "\n")
end
-- The workspaces live in each page's Auras accordion; open it so the views
-- are on screen the way a reader sees them.
do
    local accordion = M.GetPersistentMenuStateTable and M.GetPersistentMenuStateTable("accordionState")
    if type(accordion) ~= "table" then
        M.accordionState = M.accordionState or {}
        accordion = M.accordionState
    end
    for _, key in ipairs({ "uf_target", "uf_player", "gf_auras" }) do accordion[key .. ":auras"] = true end
end
local function Select(key)
    Check(M.SelectPage(key) ~= false, "could not open " .. key)
    Settle()
    return Check(M.cache[key], key .. " was not built")
end

---------------------------------------------------------------------------
-- 1. Declared views: every view is built once, then switching is free
---------------------------------------------------------------------------
-- walk(key, visit) visits every view of the page through its selectors and
-- calls visit(view) right after each click; it returns how many clicks ran.
local function SweepViews(key, walk, label)
    local entries, clicks = {}, 0
    local function Visit(pass)
        local entry = M.cache[key]
        Check(M.activeKey == key, label .. ": a selector click left the page")
        Check(entry and entry.wrapper.shown == true, label .. ": the selected view is hidden")
        local slot = entry.layoutSlot
        if pass == 1 then
            entries[slot] = entries[slot] or entry
        else
            Check(entries[slot] == entry, label .. ": the view " .. slot .. " was built again")
        end
        for other, otherEntry in pairs(entries) do
            if other ~= slot then
                Check(otherEntry.wrapper.shown == false, label .. ": the view " .. other .. " stayed visible")
            end
        end
    end
    clicks = walk(function() Visit(1) end)
    local first = WidgetCount()
    local scroll = M.scrollFrame
    scroll:SetVerticalScroll(37)
    for pass = 2, 3 do
        walk(function()
            Visit(pass)
            Check(scroll:GetVerticalScroll() == 37, label .. ": a view switch moved the scroll position")
        end)
    end
    Check(WidgetCount() == first, label .. ": switching between built views created "
        .. (WidgetCount() - first) .. " widgets")
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    Note(label .. " (" .. count .. " views, " .. clicks .. " clicks) x2", "0 widgets")
    return entries
end

-- A Buffs or Debuffs view also selects the lane the shared style and filter
-- state follow, whether it was built or shown from its cache.
local function CheckUnitLanes(key, container)
    if container ~= "buff" and container ~= "debuff" then return end
    Check(M.auraStyleGFLane == container and M.auraFilterLane == container,
        key .. ": showing " .. container .. " left the shared aura lanes on another lane")
end
-- Unit page: Container: x Edit:.
local function UnitWalker(key, containers)
    return function(visit)
        local clicks = 0
        for _, container in ipairs(containers) do
            ClickValue(Check(Bar(M.cache[key], "Container:"), key .. " has no Container: selector"), container)
            clicks = clicks + 1
            visit()
            CheckUnitLanes(key, container)
            local edit = Check(Bar(M.cache[key], "Edit:"), key .. " has no Edit: selector")
            Check(ActiveValue(Bar(M.cache[key], "Container:")) == container,
                key .. ": the Container: selector does not show " .. container)
            for _, tool in ipairs(BarValues(edit)) do
                ClickValue(Bar(M.cache[key], "Edit:"), tool)
                clicks = clicks + 1
                visit()
                CheckUnitLanes(key, container)
                Check(ActiveValue(Bar(M.cache[key], "Edit:")) == tool, key .. ": the Edit: selector does not show " .. tool)
                Check(ActiveValue(Bar(M.cache[key], "Container:")) == container,
                    key .. ": the Container: selector does not show " .. container .. " in tool " .. tool)
            end
        end
        return clicks
    end
end

local unitPages = 0
local targetEntries
for _, key in ipairs({ "uf_target", "uf_player" }) do
    if M.pages[key] then
        local entry = Select(key)
        local containerBar = Bar(entry, "Container:")
        if containerBar then
            unitPages = unitPages + 1
            local containers = BarValues(containerBar)
            -- The player page proves the second unit and the Defensives tab
            -- with the container tabs alone; uf_target walks every tool.
            local walker = key == "uf_target" and UnitWalker(key, containers)
                or function(visit)
                    for _, container in ipairs(containers) do
                        ClickValue(Bar(M.cache[key], "Container:"), container)
                        visit()
                    end
                    return #containers
                end
            local entries = SweepViews(key, walker, key)
            if key == "uf_target" then targetEntries = entries end
        end
    end
end
Check(unitPages >= 1, "no unit page has an aura workspace")
Check(targetEntries ~= nil, "uf_target has no aura workspace")
-- An Edit: click that shows a cached view selects its lanes as well, after
-- another page moved them.
if M.cache.uf_player and Bar(M.cache.uf_player, "Container:") then
    Select("uf_target")
    ClickValue(Bar(M.cache.uf_target, "Container:"), "buff")
    ClickValue(Bar(M.cache.uf_target, "Edit:"), "layout")
    Select("uf_player")
    ClickValue(Bar(M.cache.uf_player, "Container:"), "debuff")
    CheckUnitLanes("uf_player", "debuff")
    Select("uf_target")
    ClickValue(Bar(M.cache.uf_target, "Edit:"), "filters")
    Check(M.cache.uf_target == targetEntries["normal|buff:filters"], "the cached buff filters view was built again")
    CheckUnitLanes("uf_target", "buff")
end

-- Group page: two scopes x Container: x Edit:.
local function GroupWalker(visit)
    local clicks = 0
    for _, scope in ipairs({ "party", "raid" }) do
        M.SetMenuStateValue("gfScope", scope)
        M.RebuildPageKeepingScroll("gf_auras")
        Settle()
        clicks = clicks + 1
        visit()
        for _, lane in ipairs(BarValues(Check(Bar(M.cache.gf_auras, "Container:"), "gf_auras has no Container: selector"))) do
            ClickValue(Bar(M.cache.gf_auras, "Container:"), lane)
            clicks = clicks + 1
            visit()
            for _, tool in ipairs(BarValues(Check(Bar(M.cache.gf_auras, "Edit:"), "gf_auras has no Edit: selector"))) do
                ClickValue(Bar(M.cache.gf_auras, "Edit:"), tool)
                clicks = clicks + 1
                visit()
                Check(ActiveValue(Bar(M.cache.gf_auras, "Edit:")) == tool, "gf_auras: the Edit: selector does not show " .. tool)
                Check(ActiveValue(Bar(M.cache.gf_auras, "Container:")) == lane, "gf_auras: the Container: selector does not show " .. lane)
            end
        end
    end
    return clicks
end
if M.pages.gf_auras then
    Select("gf_auras")
    SweepViews("gf_auras", GroupWalker, "gf_auras")
end

-- Global Aura Appearance: Aura type:.
if M.pages.auras3_styling then
    local entry = Select("auras3_styling")
    local values = BarValues(Check(Bar(entry, "Aura type:"), "auras3_styling has no Aura type: selector"))
    SweepViews("auras3_styling", function(visit)
        for _, value in ipairs(values) do
            ClickValue(Bar(M.cache.auras3_styling, "Aura type:"), value)
            visit()
            local lane = (value == "targetDots" or value == "debuff") and "debuff" or "buff"
            Check(M.auraStyleGFLane == lane, "auras3_styling: " .. value .. " left the shared aura lane on another lane")
            Check(ActiveValue(Bar(M.cache.auras3_styling, "Aura type:")) == value,
                "auras3_styling: the Aura type: selector does not show " .. value)
        end
        return #values
    end, "auras3_styling")
end

---------------------------------------------------------------------------
-- 2 + 3. Custom whitelist add/remove repaints in place; cached views stay fresh
---------------------------------------------------------------------------
local function ShowUnitView(key, container, tool)
    ClickValue(Bar(M.cache[key], "Container:"), container)
    if tool then ClickValue(Bar(M.cache[key], "Edit:"), tool) end
    return M.cache[key]
end
local function TextAction(entry, text)
    local found
    Walk(entry.wrapper, function(frame)
        local action = frame._msuf2CommandAction
        if not found and action and action.valueKind == "text" and frame.GetText and frame:GetText() == text
            and ShownWithin(frame, entry.wrapper)
        then
            found = frame
        end
    end)
    return Check(found, "no shown text action " .. text)
end
-- The shown pooled list row that carries the spell and shows its name.
local function RowShowing(entry, text)
    local found
    Walk(entry.wrapper, function(frame)
        if found or frame._spellID == nil or not ShownWithin(frame, entry.wrapper) then return end
        for _, region in ipairs(frame.regions or {}) do
            if region.shown ~= false and region.text == text then found = frame end
        end
    end)
    return found
end
local function RemoveButton(row) return row.remove end
do
    local key = "uf_target"
    Select(key)
    local entries = Model.CustomContainerSpellEntries("target", 1)
    Check(#entries == 0, "the booted profile already whitelists a Custom 1 spell")
    local setup = ShowUnitView(key, "custom1", "setup")
    local setupBefore = Signature(setup)
    local whitelist = ShowUnitView(key, "custom1", "whitelist")
    local function AddSpell()
        Check(TextAction(M.cache[key], "Add buff")._msuf2CommandAction.set("774") == true, "the whitelist add was refused")
        Settle()
    end
    local function RemoveSpell()
        local name = Model.CustomContainerSpellEntries("target", 1)[1]
        name = tostring(name.text or name.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
        local row = Check(RowShowing(M.cache[key], name), "the whitelisted spell has no shown row")
        local remove = Check(RemoveButton(row), "the whitelist row has no remove button")
        remove:GetScript("OnClick")(remove, "LeftButton")
        Settle()
        return name
    end
    AddSpell()
    Check(M.cache[key] == whitelist, "a whitelist add rebuilt the page")
    Check(#Model.CustomContainerSpellEntries("target", 1) == 1, "the whitelist add did not save")
    local added = Model.CustomContainerSpellEntries("target", 1)[1]
    local addedName = tostring(added.text or added.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
    Check(RowShowing(whitelist, addedName), "the added spell is not listed")
    -- The Setup view was built before the add; shown again it repaints.
    local setupCached = ShowUnitView(key, "custom1", "setup")
    Check(setupCached == setup, "the Setup view was built again")
    Check(Signature(setupCached) ~= setupBefore, "the cached Setup view still shows the count from before the add")
    Check(ShowUnitView(key, "custom1", "whitelist") == whitelist, "the Whitelist view was built again")
    RemoveSpell()
    Check(M.cache[key] == whitelist, "a whitelist remove rebuilt the page")
    Check(#Model.CustomContainerSpellEntries("target", 1) == 0, "the whitelist remove did not save")
    Check(not RowShowing(whitelist, addedName), "the removed spell is still listed")
    local first = WidgetCount()
    for cycle = 1, 3 do
        AddSpell()
        Check(RowShowing(M.cache[key], addedName), "cycle " .. cycle .. ": the added spell is not listed")
        RemoveSpell()
        Check(not RowShowing(M.cache[key], addedName), "cycle " .. cycle .. ": the removed spell is still listed")
        Check(M.cache[key] == whitelist, "cycle " .. cycle .. ": a whitelist edit rebuilt the page")
    end
    Check(WidgetCount() == first, "3 whitelist add/remove cycles created " .. (WidgetCount() - first) .. " widgets")
    Note("uf_target custom1 whitelist add+remove x3", "0 widgets")
    -- Undo of an add repaints in place and drops the row again. The first
    -- undo's runtime apply builds the player castbar once; that is not menu.
    AddSpell()
    Check(M.Undo(), "undo of a whitelist add failed")
    Settle()
    first = WidgetCount()
    AddSpell()
    Check(M.Undo(), "undo of a whitelist add failed")
    Settle()
    Check(M.cache[key] == whitelist, "undo of a whitelist add rebuilt the page")
    Check(#Model.CustomContainerSpellEntries("target", 1) == 0, "undo did not remove the whitelisted spell")
    Check(not RowShowing(M.cache[key], addedName), "undo left the removed spell listed")
    Check(WidgetCount() == first, "undo of a whitelist add created " .. (WidgetCount() - first) .. " widgets")
    -- 2. A cached view looks exactly like a fresh build of it, also for data
    -- another view changed meanwhile (the Setup tool counts the whitelist).
    AddSpell()
    local cachedSetup = ShowUnitView(key, "custom1", "setup")
    Check(cachedSetup == setup, "the Setup view was built again")
    local cachedSignature = Signature(cachedSetup)
    M.InvalidatePage(key)
    local fresh = Select(key)
    Check(fresh ~= cachedSetup and fresh.layoutSlot == cachedSetup.layoutSlot, "the invalidated Setup view was reused")
    Check(Signature(fresh) == cachedSignature, "the cached Setup view differs from a fresh build:\n"
        .. cachedSignature .. "\n----\n" .. Signature(fresh))
    ShowUnitView(key, "custom1", "whitelist")
    RemoveSpell()
    -- Two more views shown from their cache against fresh builds of them.
    for _, view in ipairs({ { "debuff", "filters" }, { "buff", "style" } }) do
        local container, tool = view[1], view[2]
        local built = ShowUnitView(key, container, tool)
        ShowUnitView(key, "custom1", "setup")
        local cached = ShowUnitView(key, container, tool)
        Check(cached == built, "the " .. container .. " " .. tool .. " view was built again")
        local signature = Signature(cached)
        M.InvalidatePage(key)
        local rebuilt = Select(key)
        Check(rebuilt ~= cached and rebuilt.layoutSlot == cached.layoutSlot, "the " .. container .. " " .. tool .. " view was reused")
        Check(Signature(rebuilt) == signature, "the cached " .. container .. " " .. tool .. " view differs from a fresh build")
    end
    -- 5. The aura type changes which controls the tools build: still a rebuild.
    ShowUnitView(key, "custom1", "setup")
    local before = M.cache[key]
    local item = Model.CustomContainer("target", 1, true)
    local function AuraTypeControl(entry)
        local found
        Walk(entry.wrapper, function(frame)
            local action = frame._msuf2CommandAction
            if not found and action and tostring(action.controlId or ""):find("custom-container.setup.aura-type", 1, true) then
                found = action
            end
        end)
        return Check(found, "the Setup view has no Aura type control")
    end
    local original = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
    AuraTypeControl(before).set(original == "DEBUFF" and "BUFF" or "DEBUFF")
    Settle()
    Check(M.cache[key] ~= before, "an aura type change did not rebuild the page")
    AuraTypeControl(M.cache[key]).set(original)
    Settle()
    Check((item.auraType == "DEBUFF" and "DEBUFF" or "BUFF") == original, "the aura type was not restored")
end

-- Group blacklist: the compact Buff Blacklist adds and removes in place.
if M.pages.gf_auras then
    Select("gf_auras")
    M.SetMenuStateValue("gfScope", "party")
    M.RebuildPageKeepingScroll("gf_auras")
    Settle()
    ClickValue(Bar(M.cache.gf_auras, "Container:"), "buff")
    ClickValue(Bar(M.cache.gf_auras, "Edit:"), "blacklist")
    local entry = M.cache.gf_auras
    local add = TextAction(entry, "Add custom buff")
    local function Count() return #(Model.GroupBlacklistEntries("party", "buff") or {}) end
    local base = Count()
    local function AddSpell()
        Check(add._msuf2CommandAction.set("774") == true, "the group blacklist add was refused")
        Settle()
        Check(Count() == base + 1, "the group blacklist add did not save")
    end
    local function RemoveSpell()
        local name
        for _, blocked in ipairs(Model.GroupBlacklistEntries("party", "buff")) do
            if tostring(blocked.value) == "774" or tostring(blocked.spellID) == "774" then name = blocked end
        end
        name = tostring(Check(name, "no blocked spell to remove").text or name.value or "Spell"):gsub("%s*%(#%d+%)$", "")
        local row = Check(RowShowing(M.cache.gf_auras, name), "the blocked spell has no shown row")
        local remove = RemoveButton(row)
        if not remove then
            local keys = {}
            for k in pairs(row) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            error("the blocked row has no remove button: " .. table.concat(keys, ","))
        end
        remove:GetScript("OnClick")(remove, "LeftButton")
        Settle()
        Check(Count() == base, "the group blacklist remove did not save")
        Check(not RowShowing(M.cache.gf_auras, name), "the removed spell is still listed")
    end
    AddSpell()
    RemoveSpell()
    local first = WidgetCount()
    for cycle = 1, 3 do
        AddSpell()
        RemoveSpell()
        Check(M.cache.gf_auras == entry, "cycle " .. cycle .. ": a group blacklist edit rebuilt the page")
    end
    Check(WidgetCount() == first, "3 group blacklist add/remove cycles created " .. (WidgetCount() - first) .. " widgets")
    Note("gf_auras party buff blacklist add+remove x3", "0 widgets")
end

---------------------------------------------------------------------------
-- 4. A search route that only switches declared views does not rebuild
---------------------------------------------------------------------------
do
    local routing = Check(M.Search and M.Search._RoutingAPI, "the search routing API is missing")
    local key = "uf_target"
    Select(key)
    local function Hop(container, tool)
        local route = {
            tables = { unitAuraTabSelection = { target = container } },
            nestedTables = { unitAuraToolSelection = { target = { [container] = tool } } },
        }
        routing.ApplySearchRoute(key, route)
        Check(M.SelectPage(key) ~= false, "the search hop did not open " .. key)
        Settle()
        Check(M.cache[key].layoutSlot:find(container .. ":" .. tool, 1, true), "the search hop shows another view")
        Check(ActiveValue(Bar(M.cache[key], "Edit:")) == tool, "the search hop's Edit: selector does not show " .. tool)
    end
    Hop("debuff", "filters")
    Hop("buff", "layout")
    local before, first = invalidations[key] or 0, WidgetCount()
    for _ = 1, 3 do
        Hop("debuff", "filters")
        Hop("buff", "layout")
    end
    Check((invalidations[key] or 0) == before, "a view-only search hop invalidated " .. key)
    Check(WidgetCount() == first, "6 view-only search hops created " .. (WidgetCount() - first) .. " widgets")
    Note("uf_target search hops between two views x6", "0 widgets")
end

if report then
    print("menu_aura_workspace_views_smoke " .. flavor .. ":")
    for i = 1, #lines do print(lines[i]) end
end
print(string.format("menu_aura_workspace_views_smoke %s: ok (%d unit pages; group, appearance, list edits and search hops flat)",
    flavor, unitPages))

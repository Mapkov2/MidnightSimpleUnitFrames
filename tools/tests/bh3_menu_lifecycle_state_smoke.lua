local root, flavor, mode = assert(arg[1]), arg[2] or "Mainline", arg[3] or "variants"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { locale = "enUS" })
local M = mw.M
local function OpenSection()
    if mode == "variants" then M.BuildPageEntry("gf_layout", false) else M.SelectPage("gf_layout") end
    mw:RunTimers()
    local section = M.cache.gf_layout.sections.sorting
    return section, section._msuf2CollapsibleEntry
end
local function Click(entry)
    entry.header:GetScript("OnClick")(entry.header)
    mw:RunTimers()
end
if mode == "variants" then
    M.frame._msuf2WindowState = "normal"
    local section, normal = OpenSection()
    if not normal.open then Click(normal) end
    M.frame._msuf2WindowState = "maximized"
    local _, large = OpenSection()
    assert(large ~= normal and large.open)
    Click(large); assert(not large.open)
    M.frame._msuf2WindowState = "normal"
    local _, restored = OpenSection()
    assert(restored == normal, "return must reuse normal variant")
    assert(restored.open == false, "cached variant kept stale accordion state")
elseif mode == "focus" then
    local section, entry = OpenSection()
    if entry.open then Click(entry) end
    M.Widgets.FocusCollapsibleSection(section, { scroll = false, flash = false })
    assert(entry._msuf2AutoOpened and entry.open)
    Click(entry); Click(entry)
    assert(entry.open)
    M.SelectPage("home"); mw:RunTimers()
    OpenSection()
    assert(entry.open and M.accordionState[entry.stateKey] == true, "explicit user choice was erased after automatic focus")
elseif mode == "history" then
    assert(mw.env.MSUF_FullChangelog and mw.env.MSUF_FullChangelog.historyFromVersion == "6.02", "Classic Options did not load complete LoD history")
elseif mode == "targets" then
    M.SetMenuStateValue("gfScope", "party")
    M.SelectPage("gf_layout"); mw:RunTimers()
    local party = M.cache.gf_layout
    assert(party.sections.party_targets, "Party lost its supported target frames")
    M.SetMenuStateValue("gfScope", "raid")
    M.RebuildPageKeepingScroll("gf_layout"); mw:RunTimers()
    assert(not M.cache.gf_layout.sections.party_targets, "Raid offers a party-only backend")
    assert(not M.SupportsSearchTarget("gf_layout", "gf_raid.targetsEnabled", "groupScope", "raid"))
    M.SetMenuStateValue("gfScope", "party")
    M.RebuildPageKeepingScroll("gf_layout"); mw:RunTimers()
    assert(M.cache.gf_layout == party and party.sections.party_targets, "Party scope did not reuse its supported view")
elseif mode == "native" then
    M.SelectPage("uf_pettarget"); mw:RunTimers()
    local section = M.cache.uf_pettarget.sections.frame_basics
    if section and section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
    mw:RunTimers()
    local checked = false
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.settingKey == "pettarget.useBlizzardFrame" then
            local widget = M.RuntimeControlCatalog.Get(record.controlId).widget
            assert(widget._msuf2DesiredEnabled == false, "nonexistent Blizzard Pet Target must not be offered")
            local before = mw.env.MSUF_DB.pettarget.useBlizzardFrame
            widget._msuf2CommandAction.set(true)
            assert(mw.env.MSUF_DB.pettarget.useBlizzardFrame == before, "unavailable native ownership must not mutate profile")
            checked = true
        end
    end
    assert(checked, "native owner control was not tested")
else error(mode) end
print("menu lifecycle regression " .. mode .. ": PASS")

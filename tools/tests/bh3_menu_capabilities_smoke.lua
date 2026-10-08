local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local testRoot = assert(debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])"))
local h = assert(loadfile(testRoot .. "bh3_menu_page_fixture.lua"))()
local M, ns, env = h.M, h.MSUF, h.env
local mode = arg[3] or "anchors"
if mode == "spell" then
    ns.MSUF_GetPlayerSpecID = function() return nil end
    local _, class = env.UnitClass("player")
    local g = env.MSUF_DB.gameplay
    g.meleeSpellPerSpec, g.meleeSpellPerClass = true, true
    g.nameplateMeleeSpellIDByClass = { [class] = 10 }
    M.SetGameplayMeleeSpellID(20)
    assert(M.GetGameplayMeleeSpellID(g) == 20, "missing spec must write the class scope actually read")
    ns.MSUF_GetPlayerSpecID = function() return 123 end
    M.SetGameplayMeleeSpellID(30)
    assert(g.nameplateMeleeSpellIDByClass[class] == 20 and M.GetGameplayMeleeSpellID(g) == 30)
elseif mode == "spec" then
    if arg[2] == "Forever" then return end
    ns.Specialization = { GetNumSpecializations = function() return 1 end,
        GetSpecializationInfo = function(index) assert(index == 1); return 321, "Native specialization" end }
    env.GetNumSpecializations, env.GetSpecializationInfo = nil, nil
    local specs = M.GetProfileSpecializations()
    assert(#specs == 1 and specs[1].id == 321, "profile options must use the namespace specialization provider")
elseif mode == "anchors" then
    local dropdown = M.Widgets.Dropdown
    local lists = {}
    M.Widgets.Dropdown = function(parent, label, items, ...)
        if label == "Anchor To" then lists[#lists + 1] = items end
        return dropdown(parent, label, items, ...)
    end
    local GF = ns.GF
    GF.EnsureDB(); GF.InvalidateConfCache(true)
    M.SetMenuStateValue("gfScope", "party")
    GF.GetConf("party").anchorToFrame = "focus"
    env.MSUF_DB.target.anchorToUnitframe = "EssentialCooldownViewer"
    h.BuildPage("gf_layout"); h.BuildPage("uf_target")
    local seenGroup, seenUnit = false, false
    for _, items in ipairs(lists) do
        local values = type(items) == "function" and items() or items
        for _, item in ipairs(values) do
            if item.value == "focus" then
                seenGroup = true
                if arg[2] == "Vanilla" then assert(item.disabled == true, "imported unavailable focus must be read-only") end
            elseif item.value == "EssentialCooldownViewer" then
                seenUnit = true
                if ns.Client.HostsCooldownManager ~= true then assert(item.disabled == true, "imported unavailable cooldown anchor must be read-only") end
            elseif item.value == "focustarget" then
                assert(arg[2] ~= "Vanilla", "Era must not offer absent Focus Target")
            elseif item.value == "UtilityCooldownViewer" or item.value == "BuffIconCooldownViewer" then
                assert(ns.Client.HostsCooldownManager == true, "Classic must not offer absent cooldown viewers")
            end
        end
    end
    assert(seenGroup and seenUnit, "saved portable anchor must stay visible")
    assert(GF.GetConf("party").anchorToFrame == "focus")
    assert(env.MSUF_DB.target.anchorToUnitframe == "EssentialCooldownViewer")
elseif mode == "gates" then
    env.TotemFrame = nil
    local priorIndex = getmetatable(env).__index
    getmetatable(env).__index = function(t, key)
        if key == "TotemFrame" then return nil end
        return priorIndex(t, key)
    end
    ns.MSUF_GetPlayerSpecID = function() return nil end
    local g = env.MSUF_DB.gameplay
    g.enableCombatCrosshair, g.enableCombatCrosshairMeleeRangeColor, g.enablePlayerTotems = true, true, true
    local entry = h.BuildPage("gameplay"); h.RunRefreshers(entry)
    local found = 0
    for _, widget in pairs(h.widgetOf) do
        local label = widget._msuf2StableSearchLabel
        if label == "Store per spec" or label == "Blizzard TotemFrame" then
            assert(widget._msuf2DesiredEnabled == false, label .. " must be unavailable")
            found = found + 1
        end
    end
    -- Check by semantic setting identity too, independent of widget label internals.
    for _, payload in pairs(h.registered.gameplay or {}) do
        if payload.settingKey == "gameplay.enablePlayerTotems" or payload.settingKey == "gameplay.meleeSpellPerSpec" then
            assert(h.widgetOf[payload]._msuf2DesiredEnabled == false, payload.settingKey .. " unavailable " .. tostring(h.widgetOf[payload]._msuf2DesiredEnabled) .. " native=" .. tostring(env.TotemFrame))
            found = found + 1
        end
    end
    assert(found >= 2, "both capability gates must be exercised")
elseif mode == "sorting" then
    ns.GF.EnsureDB(); ns.GF.InvalidateConfCache(true)
    M.SetMenuStateValue("gfScope", "party")
    ns.GF.GetConf("party").sortMode = "GROUP_ROLE"
    local toggleAt, playerFirst = M.Widgets.ToggleAt
    M.Widgets.ToggleAt = function(parent, label, ...)
        local widget = toggleAt(parent, label, ...)
        if label == "Player first in role" then playerFirst = widget end
        return widget
    end
    local entry = h.BuildPage("gf_layout"); h.RunRefreshers(entry)
    assert(playerFirst, "player-first control must be checked")
    assert(playerFirst._msuf2DesiredEnabled ~= false, "GROUP_ROLE must allow player first")
else error(mode) end
print("capability regression " .. mode .. ": PASS")

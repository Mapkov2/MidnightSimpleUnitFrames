-- Reports #156/#157: real page builders, lazy disclosure, hidden search build,
-- eager fallback, wrapped descriptions and the client's available class count.
local root, flavor, only = assert(arg[1]), assert(arg[2]), arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "opt_fonts" })
local M, W, UP = mw.M, mw.M.Widgets, mw.M.UnitPage
local Shared = M.UnitSectionsShared
local function Check(ok, message) assert(ok, "bugreport_layout_smoke: " .. message) end
local function Y(region)
    local _, _, _, _, y = region:GetPoint(1)
    Check(type(y) == "number", "missing anchor")
    return y
end
local notices, classCard, toggle, rows = {}
local Notice = Shared.CreateSectionNotice
Shared.CreateSectionNotice = function(...)
    local notice, text, button = Notice(...); notices[#notices + 1] = notice; return notice, text, button
end
local wrappedHeight = 16
local Card = W.ControlCard
W.ControlCard = function(parent, title, ...)
    local card = Card(parent, title, ...)
    if title == "Class priority" then
        classCard = card
        card.subtitle.stringHeight = wrappedHeight
    end
    return card
end
local Toggle = W.ToggleAt
W.ToggleAt = function(parent, label, ...)
    local widget = Toggle(parent, label, ...)
    if label == "Use class priority" then toggle = widget end
    return widget
end
local Rows = Shared.MakeDragSortRows
Shared.MakeDragSortRows = function(parent, defs, opts)
    local holder = Rows(parent, defs, opts)
    if opts.controlPath == "sorting.class_priority" then rows = holder end
    return holder
end
local tokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
if flavor == "Mists" or flavor == "Mainline" then tokens[#tokens+1] = "DEATHKNIGHT"; tokens[#tokens+1] = "MONK" end
if flavor == "Mainline" then tokens[#tokens+1] = "DEMONHUNTER"; tokens[#tokens+1] = "EVOKER" end
mw.env.CLASS_SORT_ORDER = tokens
local Lazy = UP.BuildSectionLazy
local function Build(key, mode, id)
    mw:Select("opt_fonts")
    if mode == "eager" then UP.BuildSectionLazy = nil else UP.BuildSectionLazy = Lazy end
    M.InvalidatePage(key)
    if mode == "visible" then mw:Select(key) else M.BuildPageEntry(key, true); mw:RunTimers(20000) end
    local entry = assert(M.cache[key])
    local body = assert(entry.sections[id], key .. ": no " .. id)
    local section = assert(body._msuf2CollapsibleEntry)
    section.SetOpenImmediate(true)
    mw:RunTimers(20000)
    return entry, body, section
end
for _, mode in ipairs({ "visible", "hidden", "eager" }) do
    if only ~= "156" then
        notices = {}
        local _, body, section = Build("uf_player", mode, "anchoring")
        local found = false
        for _, notice in ipairs(notices) do
            if notice:GetParent() == body and Y(notice) == -238 then
                found = true
                Check(-Y(notice) + notice:GetHeight() + 12 <= section.contentHeight,
                    mode .. ": anchor notice extends outside section into the next header")
            end
        end
        Check(found, mode .. ": anchor notice not built")
        Check(body:GetHeight() == section.contentHeight, mode .. ": anchor body height diverges")
    end
    if only ~= "157" then
        for _, height in ipairs({ 16, 36 }) do
            wrappedHeight, classCard, toggle, rows = height, nil, nil, nil
            local _, body, section = Build("gf_layout", mode, "sorting")
            Check(classCard and toggle and rows, mode .. ": class priority content missing")
            Check(Y(toggle) <= Y(classCard.subtitle) - classCard.subtitle:GetStringHeight() - 8,
                mode .. ": class priority toggle overlaps description")
            Check(Y(rows) <= Y(toggle) - toggle:GetHeight() - 8, mode .. ": class rows overlap toggle")
            Check(#rows.rows == #tokens, flavor .. ": available class rows changed")
            Check(-Y(rows) + rows:GetHeight() + 12 <= classCard:GetHeight(), mode .. ": rows escape card")
            Check(-Y(classCard) + classCard:GetHeight() + 12 <= section.contentHeight,
                mode .. ": class card escapes sorting section")
            Check(body:GetHeight() == section.contentHeight, mode .. ": sorting body height diverges")
            local first, last = rows.rows[1], rows.rows[#rows.rows]
            local conf = M.GroupPage.Conf(M.GroupPage.CurrentScope())
            conf.sortClassPriority = true
            M.RunEntryRefreshers(M.cache.gf_layout, { force = true })
            Check(rows._enabled, "class priority toggle no longer enables rows")
            first.slotIndex, last.slotIndex = last.slotIndex, first.slotIndex
            rows:SnapRows()
            Check(Y(first.frame) < Y(last.frame), "class reorder no longer moves rows")
            local cardHeight, contentHeight = classCard:GetHeight(), section.contentHeight
            local writes, SetHeight = 0, classCard.SetHeight
            classCard.SetHeight = function(self, ...) writes = writes + 1; return SetHeight(self, ...) end
            for _ = 1, 3 do M.RunEntryRefreshers(M.cache.gf_layout, { force = true }) end
            Check(writes == 0 and cardHeight == classCard:GetHeight() and contentHeight == section.contentHeight,
                "unchanged refresh recomputes class card geometry")
        end
    end
end
UP.BuildSectionLazy = Lazy
print("bugreport_layout_smoke: ok (" .. flavor .. ": lazy, hidden, eager; wrapped text and class counts)")

-- Menu2 host API v1: page-reset providers. Another addon (the MSUF Suite)
-- owns the reset of its own pages through one registration instead of
-- wrapping the four page-reset functions:
--
--   M.HOST_API_VERSION = 1
--   M.RegisterPageResetProvider(id, provider)
--       provider = { pages = { [pageKey] = true, ... },
--                    canReset = fn(key) -> bool,
--                    warning = fn(key) -> string | nil,
--                    reset = fn(key) -> bool,
--                    prepare = fn(key) -> bool,        optional
--                    finish = fn(key),                 optional
--                    historyLabel = fn(key) -> string } optional
--       A reset runs: combat refusal, canReset, prepare (before the undo
--       snapshot, so what it loads is part of the state Undo restores), reset
--       inside one undo history entry, then finish (the provider's refresh and
--       feedback) after that entry is committed. historyLabel names the entry
--       (already translated); the host's "Reset %s" is the fallback.
--       Registering an id again replaces that provider; a page two providers
--       claim belongs to the latest registration. A malformed provider raises
--       and leaves the registry as it was.
--   M.RefreshPageResetProvider(id) -> registered
--       Re-reads that provider after it changed its pages.
--
-- MSUF_Menu2_Bindings_Reset.lua owns the four functions and the pageKey ->
-- provider map they read first (one table lookup, nothing allocated); a key
-- no provider owns keeps the host's own code. This file owns registration and
-- the provider paths those functions hand off to.
local _, MSUF = ...
local M = MSUF.MSUF2
local byPage = M.PageResetProviders
-- Kernel/MSUF_Boundary.lua: a raising provider step is reported and returns nil.
local RunStep = MSUF.RunPageResetProviderStep
-- Runtime/MSUF_HostAPI.lua: the host API's combat question.
local PlayerInCombat = MSUF.HostAPIPlayerInCombat
local records, order = {}, {}
M.HOST_API_VERSION = 1

local function OptionalFunction(value)
    return value == nil or type(value) == "function"
end

-- A checked copy of a provider: its callbacks and the pages it owns now. It
-- raises before anything changes, so a malformed provider never disturbs the
-- pages the other providers own.
local function Snapshot(id, provider, caller)
    if type(id) ~= "string" or id == "" or type(provider) ~= "table" or type(provider.pages) ~= "table"
        or type(provider.canReset) ~= "function" or type(provider.warning) ~= "function"
        or type(provider.reset) ~= "function" or not OptionalFunction(provider.prepare)
        or not OptionalFunction(provider.finish) or not OptionalFunction(provider.historyLabel) then
        error("MSUF " .. caller .. ": expected (id, { pages, canReset, warning, reset"
            .. " [, prepare, finish, historyLabel] })", 3)
    end
    local pages = {}
    for key, owned in pairs(provider.pages) do
        if owned == true and type(key) == "string" then pages[key] = true end
    end
    return {
        id = id, source = provider, pages = pages,
        canReset = provider.canReset, warning = provider.warning, reset = provider.reset,
        prepare = provider.prepare, finish = provider.finish, historyLabel = provider.historyLabel,
    }
end

-- Builds the new page map from the checked copies only, then publishes it into
-- the table the reset functions read. Registration order settles overlaps, so
-- a refresh that drops a page hands it back to the earlier provider.
local function RebuildPageMap()
    local staged = {}
    for index = 1, #order do
        local record = records[order[index]]
        for key in pairs(record.pages) do staged[key] = record end
    end
    for key in pairs(byPage) do
        if staged[key] == nil then byPage[key] = nil end
    end
    for key, record in pairs(staged) do byPage[key] = record end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end

function M.RegisterPageResetProvider(id, provider)
    local record = Snapshot(id, provider, "RegisterPageResetProvider")
    if records[id] then
        for index = 1, #order do
            if order[index] == id then
                table.remove(order, index)
                break
            end
        end
    end
    records[id] = record
    order[#order + 1] = id
    RebuildPageMap()
    return true
end

function M.RefreshPageResetProvider(id)
    local current = records[id]
    if not current then return false end
    records[id] = Snapshot(id, current.source, "RefreshPageResetProvider")
    RebuildPageMap()
    return true
end

-- The host's standard page warning: the locale key MSUF_Menu2_Bindings_Reset.lua
-- builds its own page warnings from ("Reset %s to defaults?\n\nThis resets %s
-- for the active profile. ..."), written as a long string to keep the lines short.
local STANDARD_PAGE_WARNING = [[Reset %s to defaults?

This resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically.]]

-- provider.warning(key), else the host's standard text: nil when the host has
-- reset info of its own for the key (the caller then builds that warning),
-- otherwise the generic page warning.
function M.ProviderPageResetWarning(key, provider, hostHasInfo)
    local warning = provider.warning(key)
    if warning ~= nil or hostHasInfo then return warning end
    local page = M.pages and M.pages[key]
    local title = M.Tr((page and page.title) or key)
    return string.format(M.Tr(STANDARD_PAGE_WARNING), title, title)
end

-- The menu's combat refusal, including the PLAYER_REGEN_DISABLED dispatch.
local function RefusedInCombat()
    if not PlayerInCombat() then return false end
    M.ShowConfigCombatLockMessage()
    return true
end

-- The undo entry's name: the provider's own (already translated), else the
-- host's "Reset %s" with the translated page title.
local function HistoryLabel(provider, key)
    local label = provider.historyLabel and provider.historyLabel(key)
    if type(label) == "string" and label ~= "" then return label end
    local page = M.pages and M.pages[key]
    return string.format(M.Tr("Reset %s"), M.Tr((page and page.title) or key))
end

-- The host's rules around the provider's steps: combat refuses, prepare runs
-- before the undo snapshot, reset is one undo history entry, and finish (the
-- provider's refresh and feedback) runs after that entry is committed. The
-- steps run through the boundary, so a raising one is reported and the
-- history never stays open; a reset that raised still records what it
-- changed, so Undo can restore it.
function M.ResetProviderPage(key, provider)
    if RefusedInCombat() or provider.canReset(key) ~= true then return false end
    if provider.prepare then
        if RunStep(provider.prepare, key, "prepare") ~= true then return false end
        -- An open menu session keeps the snapshot it took before prepare loaded
        -- anything, and that snapshot is the reset's "before". Refresh it, so
        -- Undo restores what prepare loaded. The session's start snapshot (Reset
        -- session, discard) stays as it was, and no entry is added.
        M.SyncExternalHistoryState()
    end
    local ok = M.RunWithHistory(HistoryLabel(provider, key), "page:reset:" .. key, function()
        local result = RunStep(provider.reset, key, "reset")
        if result == false then return false end
        return result == true or nil
    end) == true
    if ok and provider.finish then RunStep(provider.finish, key, "finish") end
    return ok
end

-- Blizzard's generic confirmation (Blizzard_StaticPopup SharedDialogDefs.lua
-- GENERIC_CONFIRMATION, on every supported client): nothing is added to
-- StaticPopupDialogs. One data table keeps one question open, like the host's
-- own dialog: StaticPopup_Show finds the visible dialog with this data and
-- replaces it. The text goes in as a format argument, so a '%' in it is shown
-- as is. Yes resets the page through its owner at that moment.
local confirmKey
local confirmation = {
    text = "%s",
    callback = function() M.ResetPageToDefaults(confirmKey) end,
}
function M.ShowProviderPageResetConfirm(key, provider)
    if RefusedInCombat() or provider.canReset(key) ~= true then return false end
    local warning = M.BuildPageResetWarning(key)
    if warning == nil then return false end
    confirmKey = key
    confirmation.text_arg1 = warning
    StaticPopup_ShowCustomGenericConfirmation(confirmation)
    return true
end

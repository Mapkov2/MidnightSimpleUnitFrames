-- Menu2 host API v1: page-reset providers. Another addon (the MSUF Suite)
-- owns the reset of its own pages through one registration instead of
-- wrapping the four page-reset functions:
--
--   M.HOST_API_VERSION = 1
--   M.RegisterPageResetProvider(id, provider)
--       provider = { pages = { [pageKey] = true, ... },
--                    canReset = fn(key) -> bool,
--                    warning = fn(key) -> string | nil,
--                    reset = fn(key) -> bool }
--       Registering an id again replaces that provider. A page two providers
--       claim belongs to the latest registration.
--   M.RefreshPageResetProvider(id) -> registered
--       Re-reads provider.pages after the provider changed it.
--
-- MSUF_Menu2_Bindings_Reset.lua owns the four functions and the pageKey ->
-- provider map they read first (one table lookup, nothing allocated); a key
-- no provider owns keeps the host's own code. This file owns registration and
-- the provider paths those functions hand off to.
local _, MSUF = ...
local M = MSUF.MSUF2
local byPage = M.PageResetProviders
local providers, order = {}, {}
M.HOST_API_VERSION = 1

local function RebuildPageMap()
    for key in pairs(byPage) do byPage[key] = nil end
    -- Registration order settles overlaps, so a refresh that drops a page
    -- hands it back to the earlier provider that still claims it.
    for index = 1, #order do
        local provider = providers[order[index]]
        for key, owned in pairs(provider.pages) do
            if owned == true and type(key) == "string" then byPage[key] = provider end
        end
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end

function M.RegisterPageResetProvider(id, provider)
    if type(id) ~= "string" or id == "" or type(provider) ~= "table" or type(provider.pages) ~= "table"
        or type(provider.canReset) ~= "function" or type(provider.warning) ~= "function"
        or type(provider.reset) ~= "function" then
        error("MSUF RegisterPageResetProvider: expected (id, { pages, canReset, warning, reset })", 2)
    end
    if providers[id] then
        for index = 1, #order do
            if order[index] == id then
                table.remove(order, index)
                break
            end
        end
    end
    providers[id] = provider
    order[#order + 1] = id
    RebuildPageMap()
    return true
end

function M.RefreshPageResetProvider(id)
    local provider = providers[id]
    if not provider then return false end
    if type(provider.pages) ~= "table" then
        error("MSUF RefreshPageResetProvider: provider '" .. id .. "' has no pages table", 2)
    end
    RebuildPageMap()
    return true
end

-- provider.warning(key), else the host's standard text: nil when the host has
-- reset info of its own for the key (the caller then builds that warning),
-- otherwise the generic page warning.
function M.ProviderPageResetWarning(key, provider, hostHasInfo)
    local warning = provider.warning(key)
    if warning ~= nil or hostHasInfo then return warning end
    local page = M.pages and M.pages[key]
    local title = M.Tr((page and page.title) or key)
    return string.format(M.Tr("Reset %s to defaults?\n\nThis resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."),
        title, title)
end

-- The host's rules around provider.reset: combat refuses and the reset is one
-- undo history entry, "Reset <page title>". The provider refreshes its page
-- and reports the reset itself, as it did before this API, so the host adds
-- no second refresh, feedback or history entry.
function M.ResetProviderPage(key, provider)
    if M.BlockCombatAction() or provider.canReset(key) ~= true then return false end
    local page = M.pages and M.pages[key]
    return M.RunWithHistory("Reset " .. ((page and page.title) or key), "page:reset:" .. key, function()
        return provider.reset(key) == true
    end) == true
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
    if M.BlockCombatAction() or provider.canReset(key) ~= true then return false end
    local warning = M.BuildPageResetWarning(key)
    if warning == nil then return false end
    confirmKey = key
    confirmation.text_arg1 = warning
    StaticPopup_ShowCustomGenericConfirmation(confirmation)
    return true
end

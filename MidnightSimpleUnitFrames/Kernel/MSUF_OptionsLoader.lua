--- Zero-idle LoadOnDemand facade for MidnightSimpleUnitFrames_Options.
--- This file deliberately creates no frame, event, hook, ticker, or timer.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local OPTIONS_ADDON = "MidnightSimpleUnitFrames_Options"
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local menu = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = menu
_G.MSUF2 = menu

local loading = false
local globalStubs = {}
local menuStubs = {}

local function IsAddonLoaded()
    local api = _G.C_AddOns
    if api and type(api.IsAddOnLoaded) == "function" then
        local loadedOrLoading, loaded = api.IsAddOnLoaded(OPTIONS_ADDON)
        return (loadedOrLoading == true or loaded == true) and true or false
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(OPTIONS_ADDON) and true or false
    end
    return MSUF.OptionsLODReady == true
end

local function IsReady()
    return IsAddonLoaded() and MSUF.OptionsLODReady == true
end

local function PrintLoadFailure(detail)
    local message = "|cffff4040MSUF:|r Please enable MSUF Options in Blizzard's AddOns menu"
    if detail and detail ~= "" then message = message .. " (" .. tostring(detail) .. ")" end
    message = message .. "."
    if type(_G.print) == "function" then _G.print(message) end
end

local function ConfigurationLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end

local function ShowCombatLock()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    end
end

local function EnsureOptionsLoaded(reason)
    if IsReady() then return true end
    if loading then return false end
    if ConfigurationLocked() then
        ShowCombatLock()
        return false
    end

    loading = true
    MSUF.OptionsLODLastReason = tostring(reason or "options-demand")
    local loader = _G.MSUF_EnsureAddonLoaded
    --- The normal API reports loaded=false plus a reason. The wrapper can still
    --- be supplied by another module, so protect this optional load boundary
    --- and always clear the re-entry flag.
    local ok, loaded
    if type(loader) == "function" then
        ok, loaded = pcall(loader, OPTIONS_ADDON)
    else
        local api = _G.C_AddOns
        loader = (api and api.LoadAddOn) or _G.LoadAddOn
        if type(loader) == "function" then
            ok, loaded = pcall(loader, OPTIONS_ADDON)
        else
            ok, loaded = false, "LoadAddOn unavailable"
        end
    end
    loading = false

    if ok and (loaded or IsAddonLoaded()) and IsReady() then return true end
    PrintLoadFailure(ok and (MSUF.OptionsLODLoadError or "incomplete load") or loaded)
    return false
end

ExportPublic("MSUF_EnsureOptionsLoaded", EnsureOptionsLoaded)
ExportPublic("MSUF_IsOptionsLoaded", IsReady)
MSUF.OptionsAddonName = OPTIONS_ADDON
MSUF.OptionsLODGlobalStubs = globalStubs
MSUF.OptionsLODMenuStubs = menuStubs

local function MakeGlobalForwarder(name)
    local stub
    stub = function(...)
        if not EnsureOptionsLoaded(name) then return false end
        local implementation = rawget(_G, name)
        if type(implementation) ~= "function" or implementation == stub then
            PrintLoadFailure(name .. " unavailable")
            return false
        end
        return implementation(...)
    end
    globalStubs[name] = stub
    return stub
end

local function MakeMenuForwarder(name)
    local stub
    stub = function(...)
        if not EnsureOptionsLoaded("MSUF2." .. name) then return false end
        local implementation = rawget(menu, name)
        if type(implementation) ~= "function" or implementation == stub then
            PrintLoadFailure("MSUF2." .. name .. " unavailable")
            return false
        end
        return implementation(...)
    end
    menuStubs[name] = stub
    return stub
end

--- Stable public entry points used by the minimap button, compartment, game
--- menu, keybinds, Edit Mode focus helpers, changelog, and Assistant routing.
local FORWARDED_GLOBALS = {
    "MSUF2_Open",
    "MSUF2_Toggle",
    "MSUF_OpenStandaloneOptionsWindow",
    "MSUF_ShowStandaloneOptionsWindow",
    "MSUF_HideStandaloneOptionsWindow",
    "MSUF_OpenOptionsMenu",
    "MSUF_OpenPage",
    "MSUF_SwitchMirrorPage",
    "MSUF_GetCurrentMirrorPage",
    "MSUF_GetMirrorPages",
    "MSUF_OpenExactSettingControl",
    "MSUF_OpenExactColorSettingPicker",
    "MSUF_OpenExactCatalogControl",
    "MSUF_StartGuidedTour",
    "MSUF_ResumeGuidedTour",
}

if not IsReady() then
    --- These are MSUF-owned compatibility globals. Menu2's former eager TOC
    --- load always replaced any earlier value through ExportPublic, so the cold
    --- facade must preserve that exact ownership rule.
    for i = 1, #FORWARDED_GLOBALS do
        local name = FORWARDED_GLOBALS[i]
        ExportPublic(name, MakeGlobalForwarder(name))
    end

    for _, name in ipairs({ "Open", "Toggle", "SelectPage", "ShowLocaleReloadRequired" }) do
        menu[name] = MakeMenuForwarder(name)
    end
end

local function DispatchSlashAfterLoad(msg)
    if not EnsureOptionsLoaded("slash:/msuf") then return false end
    local commands = MSUF.SlashCommands
    if type(commands) == "table" and type(commands.Dispatch) == "function" then
        return commands.Dispatch(msg)
    end
    return menu.Open()
end

--- Keep the established `/msuf help` surface complete even when the very
--- first help request happens in combat and the UI addon cannot be loaded.
--- These entries are metadata plus demand-call closures only: no frames,
--- events, hooks, timers, menu tables, or page code.
local function RegisterDeferredOptionCommands()
    local commands = MSUF.SlashCommands
    if type(commands) ~= "table" or type(commands.Register) ~= "function" then return end

    local specs = {
        {
            name = "edit",
            aliases = { "editmode", "move", "unlock" },
            group = "frames",
            usage = "/msuf edit [unit]",
            help = "Toggle MSUF Edit Mode. Add a unit such as player or target to open it there.",
        },
        {
            name = "lock",
            aliases = { "unedit" },
            group = "frames",
            usage = "/msuf lock",
            help = "Leave MSUF Edit Mode.",
        },
        {
            name = "search",
            aliases = { "find" },
            group = "general",
            usage = "/msuf search <text>",
            help = "Search the options menu and open the matching settings.",
        },
        {
            name = "tour",
            aliases = { "guide", "setup" },
            group = "general",
            usage = "/msuf tour",
            help = "Start or resume the guided setup.",
        },
        {
            name = "locale",
            aliases = { "locales", "loc" },
            group = "diagnostics",
            dev = true,
            usage = "/msuf locale",
            help = "Report how much of the current language is translated.",
        },
        {
            name = "versiontest",
            group = "diagnostics",
            dev = true,
            usage = "/msuf versiontest",
            help = "Fake an available update to test the version-check popup.",
        },
        {
            name = "firstload",
            group = "diagnostics",
            dev = true,
            usage = "/msuf firstload [fresh/upgrade/status]",
            help = "Replay the first-start flow or the upgrade highlights.",
        },
    }

    MSUF.OptionsLODCommandSpecs = specs
    for i = 1, #specs do
        local spec = specs[i]
        local entry = {}
        for key, value in pairs(spec) do entry[key] = value end
        entry._msufOptionsLODDeferred = true
        entry.run = function(rest, fullMessage)
            if not EnsureOptionsLoaded("slash:/msuf " .. spec.name) then return false end
            local implementation = type(commands.Get) == "function" and commands.Get(spec.name) or nil
            if type(implementation) ~= "table"
                or implementation._msufOptionsLODDeferred == true
                or type(implementation.run) ~= "function"
            then
                PrintLoadFailure("slash command " .. spec.name .. " unavailable")
                return false
            end
            return implementation.run(rest or "", fullMessage or spec.name)
        end
        commands.Register(entry)
    end
end

RegisterDeferredOptionCommands()

local function DispatchSlash(msg)
    msg = tostring(msg or "")
    local word = msg:match("^%s*(%S+)")
    local commands = MSUF.SlashCommands
    local entry = word and type(commands) == "table"
        and type(commands.Get) == "function" and commands.Get(word) or nil
    --- Core-owned commands do not need the options UI. Keep them genuinely
    --- lightweight; `help` is the exception because its established output
    --- includes Menu2-owned commands after the Options module registers them.
    if entry and tostring(word):lower() ~= "help" and type(commands.Dispatch) == "function" then
        return commands.Dispatch(msg)
    end
    --- Preserve already-loaded core diagnostics in combat without attempting a
    --- new addon load. Menu/page/search/edit commands still use the established
    --- configuration-lock message.
    if ConfigurationLocked() and entry and type(commands.Dispatch) == "function" then
        return commands.Dispatch(msg)
    end
    return DispatchSlashAfterLoad(msg)
end

if _G.SlashCmdList == nil then
    --- Headless smoke stubs only. In the client Blizzard defines SlashCmdList
    --- before any addon loads, and reassigning that global (even with the same
    --- table) taints the variable slot: secure chat dispatch re-reads it on
    --- every slash command (ChatFrameUtil.ImportAllListsToHash), which would
    --- carry MSUF taint into protected handlers (/pvp -> C_PvP.TogglePVP()
    --- => ADDON_ACTION_FORBIDDEN). Never write this global when it exists.
    _G.SlashCmdList = {}
end
_G.SLASH_MSUF2OPTIONS1 = "/msuf"
_G.SlashCmdList.MSUF2OPTIONS = DispatchSlash
_G.SLASH_MSUFOPTIONS1 = _G.SLASH_MSUFOPTIONS1 or "/msufoptions"
if not _G.SlashCmdList.MSUFOPTIONS then
    _G.SlashCmdList.MSUFOPTIONS = DispatchSlash
    MSUF.OptionsLODMSUFOptionsStub = DispatchSlash
end

local function MenuCheckSlash(...)
    if not EnsureOptionsLoaded("slash:/msufmenucheck") then return false end
    local implementation = _G.SlashCmdList and _G.SlashCmdList.MSUFMENUCHECK
    if type(implementation) == "function" and implementation ~= MenuCheckSlash then
        return implementation(...)
    end
    return false
end

_G.SLASH_MSUFMENUCHECK1 = "/msufmenucheck"
_G.SlashCmdList.MSUFMENUCHECK = MenuCheckSlash

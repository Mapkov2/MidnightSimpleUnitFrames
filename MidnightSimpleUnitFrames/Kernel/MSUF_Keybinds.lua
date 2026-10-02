--- Kernel/MSUF_Keybinds.lua
--- Keybinding support: binding display names, the Bindings.xml entry points
--- (MSUF_Keybind_*), the managed-binding API used by the options menu and the
--- observational SavedVariables mirror of the live binding set.
---
--- Bindings.xml is auto-discovered by WoW (NOT in the TOC) and calls the
--- MSUF_Keybind_* globals defined here. Loads right after MSUF_Util.lua.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

local type, select = type, select
local CreateFrame = CreateFrame

--- Keybinding support (Bindings.xml auto-discovered by WoW, NOT in TOC).
--- The menu language is known only once the saved locale is read at
--- ADDON_LOADED, so the translated labels are set again then.
local function ApplyBindingLabels()
    local translate = type(MSUF.Translate) == "function" and MSUF.Translate or function(text) return text end
    BINDING_HEADER_MSUF_HEADER = translate("Midnight Simple Unit Frames")
    BINDING_NAME_MSUF_TOGGLE_OPTIONS = translate("Toggle MSUF Options")
    BINDING_NAME_MSUF_TOGGLE_EDITMODE = translate("Toggle MSUF Edit Mode")
    local variantLabel = translate("Toggle profile variant %d")
    for slot = 1, 8 do _G["BINDING_NAME_MSUF_VARIANT_" .. slot] = variantLabel:format(slot) end
    BINDING_NAME_MSUF_PRIORITY_TOGGLE = translate("Pin or unpin hovered group member")
end
ApplyBindingLabels()
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_Keybinds", ApplyBindingLabels)
end
local MSUF_BINDING_COMMANDS = {
    "MSUF_TOGGLE_OPTIONS",
    "MSUF_TOGGLE_EDITMODE",
    "MSUF_PRIORITY_TOGGLE",
}
local MSUF_MANAGED_BINDING_COMMANDS = {}
for i = 1, #MSUF_BINDING_COMMANDS do
    MSUF_MANAGED_BINDING_COMMANDS[MSUF_BINDING_COMMANDS[i]] = true
end

local function MSUF_EnsureGlobalBindingState()
    ExportPublic("MSUF_GlobalDB", _G.MSUF_GlobalDB or {})
    local gdb = _G.MSUF_GlobalDB
    gdb.global = gdb.global or {}
    gdb.global.bindings = gdb.global.bindings or {}
    gdb.global.bindings.commands = gdb.global.bindings.commands or {}
    return gdb.global.bindings.commands
end

local function MSUF_GetBindingKeysForCommand(command)
    local keys = {}
    if type(command) ~= "string" or command == "" or type(_G.GetBindingKey) ~= "function" then
        return keys
    end

    local seen = {}
    local count = select("#", _G.GetBindingKey(command))
    for i = 1, count do
        local key = select(i, _G.GetBindingKey(command))
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end

    table.sort(keys)
    return keys
end

local function MSUF_CopyBindingKeys(keys)
    local out = {}
    if type(keys) ~= "table" then return out end

    local seen = {}
    for i = 1, #keys do
        local key = keys[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end

    table.sort(out)
    return out
end

local function MSUF_BindingListsEqual(a, b)
    a = MSUF_CopyBindingKeys(a)
    b = MSUF_CopyBindingKeys(b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function MSUF_GetStoredBindingKeys(command)
    local commands = MSUF_EnsureGlobalBindingState()
    return MSUF_CopyBindingKeys(commands[command])
end

local function MSUF_SetStoredBindingKeys(command, keys)
    if type(command) ~= "string" or command == "" then return end
    local commands = MSUF_EnsureGlobalBindingState()
    commands[command] = MSUF_CopyBindingKeys(keys)
end

local function MSUF_SyncCurrentBindingsIntoGlobalStore()
    for i = 1, #MSUF_BINDING_COMMANDS do
        local command = MSUF_BINDING_COMMANDS[i]
        local liveKeys = MSUF_GetBindingKeysForCommand(command)
        if not MSUF_BindingListsEqual(liveKeys, MSUF_GetStoredBindingKeys(command)) then
            MSUF_SetStoredBindingKeys(command, liveKeys)
        end
    end
end

local optionsOpenPending = false
local optionsOpenPage
local function OpenLoadedOptionsFromLauncher()
    optionsOpenPending = false
    local pageKey = optionsOpenPage
    optionsOpenPage = nil
    -- Combat can start between the demand load and the next-frame open.
    if _G.InCombatLockdown() then
        local showLock = _G.MSUF_ShowConfigCombatLockMessage
        if type(showLock) == "function" then showLock() end
        return false
    end
    local open = _G.MSUF_OpenStandaloneOptionsWindow
    if type(open) == "function" then return open(pageKey) end
    return false
end

-- Game Menu and keybind share one cold-open boundary. Loading Options and
-- building its skinned window must not consume the same script time budget.
-- Blizzard_FrameXML/Mainline/AlertFrames.lua (upstream/forever) also uses
-- C_Timer.After(0, ...) for work deferred until the first rendered frame.
function MSUF.OpenOptionsFromLauncher(pageKey)
    optionsOpenPage = pageKey
    if optionsOpenPending then return true end
    local isLoaded = _G.MSUF_IsOptionsLoaded
    local ensureLoaded = _G.MSUF_EnsureOptionsLoaded
    if type(isLoaded) == "function" and isLoaded() ~= true
        and type(ensureLoaded) == "function" then
        if ensureLoaded("MSUF_OpenStandaloneOptionsWindow") ~= true then
            optionsOpenPage = nil
            return false
        end
        local timer = _G.C_Timer
        if timer and type(timer.After) == "function" then
            optionsOpenPending = true
            timer.After(0, OpenLoadedOptionsFromLauncher)
            return true
        end
    end
    return OpenLoadedOptionsFromLauncher()
end

--- Kernel/MSUF_OptionsLoader.lua publishes the options entry points as cold
--- forwarders until the load-on-demand menu replaces them, so the window
--- controls exist whenever a key is pressed.
function MSUF_Keybind_ToggleOptions()
    local win = _G.MSUF_StandaloneOptionsWindow
    if win and win.IsShown and win:IsShown() then
        if _G.MSUF_HideStandaloneOptionsWindow then
            _G.MSUF_HideStandaloneOptionsWindow()
        elseif win.Hide then
            win:Hide()
        end
    else
        MSUF.OpenOptionsFromLauncher()
    end
end

--- Shell/EditMode (every core TOC) publishes the entry point after this file
--- loads, so it is resolved when the key is pressed.
function MSUF_Keybind_ToggleEditMode()
    local st = _G.MSUF_EditState
    local nextActive = true
    if st and st.active ~= nil then
        nextActive = not st.active
    end
    MSUF.Require("MSUF_SetMSUFEditModeDirect", "Kernel/MSUF_Keybinds.lua")(nextActive, nil)
end

local function MSUF_SaveCurrentBindings()
    if type(_G.SaveBindings) ~= "function" then return end
    local set = type(_G.GetCurrentBindingSet) == "function" and _G.GetCurrentBindingSet() or 1
    _G.SaveBindings(set)
end

local function MSUF_GetManagedBindingKeys(command)
    if not MSUF_MANAGED_BINDING_COMMANDS[command] then return {} end
    return MSUF_GetBindingKeysForCommand(command)
end
ExportPublic("MSUF_GetManagedBindingKeys", MSUF_GetManagedBindingKeys)

local function MSUF_SetManagedBinding(command, key, replaceConflict)
    if not MSUF_MANAGED_BINDING_COMMANDS[command] then return false, "INVALID_COMMAND" end
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        return false, "COMBAT"
    end
    key = type(key) == "string" and key:upper() or nil
    if not key or key == "" then return false, "INVALID_KEY" end
    if type(_G.SetBinding) ~= "function" then return false, "UNAVAILABLE" end
    local action = type(_G.GetBindingAction) == "function" and _G.GetBindingAction(key) or nil
    if type(action) == "string" and action ~= "" and action ~= command and replaceConflict ~= true then
        return false, "CONFLICT", action
    end
    local live = MSUF_GetBindingKeysForCommand(command)
    if _G.SetBinding(key, command) == false then return false, "SET_FAILED" end
    local cleared = {}
    for i = 1, #live do
        local oldKey = live[i]
        if oldKey ~= key then
            if _G.SetBinding(oldKey) == false then
                for j = 1, #cleared do _G.SetBinding(cleared[j], command) end
                if action and action ~= "" and action ~= command then
                    _G.SetBinding(key, action)
                elseif action ~= command then
                    _G.SetBinding(key)
                end
                return false, "CLEAR_FAILED", oldKey
            end
            cleared[#cleared + 1] = oldKey
        end
    end
    MSUF_SetStoredBindingKeys(command, { key })
    MSUF_SaveCurrentBindings()
    return true
end
ExportPublic("MSUF_SetManagedBinding", MSUF_SetManagedBinding)

local function MSUF_ClearManagedBinding(command)
    if not MSUF_MANAGED_BINDING_COMMANDS[command] then return false, "INVALID_COMMAND" end
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        return false, "COMBAT"
    end
    if type(_G.SetBinding) ~= "function" then return false, "UNAVAILABLE" end
    local live = MSUF_GetBindingKeysForCommand(command)
    local cleared = {}
    for i = 1, #live do
        local key = live[i]
        if _G.SetBinding(key) == false then
            for j = 1, #cleared do _G.SetBinding(cleared[j], command) end
            return false, "CLEAR_FAILED", key
        end
        cleared[#cleared + 1] = key
    end
    MSUF_SetStoredBindingKeys(command, {})
    MSUF_SaveCurrentBindings()
    return true
end
ExportPublic("MSUF_ClearManagedBinding", MSUF_ClearManagedBinding)

--- Group frames (every core TOC) publish the toggle after this file loads.
function MSUF_Keybind_TogglePriorityFrame()
    return MSUF.Require("MSUF_GF_ToggleHoveredPriority", "Kernel/MSUF_Keybinds.lua")()
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("UPDATE_BINDINGS")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" or event == "UPDATE_BINDINGS" then
            -- WoW owns the active account/character binding set. Keep the
            -- SavedVariables copy observational only: replaying account-wide
            -- MSUF keys here can steal spell/action bindings on another
            -- character when both use the same physical key. Explicit menu
            -- changes still use the conflict-aware managed-binding functions.
            MSUF_SyncCurrentBindingsIntoGlobalStore()
        end
    end)
end

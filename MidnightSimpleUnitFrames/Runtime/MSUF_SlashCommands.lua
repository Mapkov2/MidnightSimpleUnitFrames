--- Runtime/MSUF_SlashCommands.lua
--- Slash command registry, the /msuf sub-commands, lightweight debug print
--- helpers, and the reset commands. Unit tooltips live in
--- MSUF_UnitTooltips.lua, the Blizzard Edit Mode bridge in
--- MSUF_BlizzEditModeBridge.lua.
---
--- This is the user-command edge of the addon. Keep gameplay/runtime mutation
--- behind existing public helpers where possible, and keep destructive commands
--- guarded by combat checks and explicit confirmation.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local function PublishCompat(name, value)
    return ExportPublic(name, value)
end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

MSUF.Debug = MSUF.Debug or {}
local Debug = MSUF.Debug

Debug.IsGFHoverEnabled = Debug.IsGFHoverEnabled or function()
    return Debug.gfHover == true
end

Debug.PrintGFHover = Debug.PrintGFHover or function(message, ...)
    if Debug.gfHover ~= true then return end
    local prefix = "|cff7aa2f7MSUF GFDBG|r "
    if select("#", ...) > 0 then
        print(prefix .. string.format(message, ...))
        return
    end
    print(prefix .. tostring(message))
end
local function MSUF_Chat_RunEnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
        return true
    end
    return false
end
local function MSUF_Chat_RunApplyAllSettings()
    local UF = MSUF and MSUF.UF
    if UF and UF.Apply then
        UF.Apply(nil)
        return true
    end
    return false
end

local MSUF_RESET_DEFAULTS = {
    player = { width=275, height=40, offsetX=-260, offsetY=80, showName=true, showHP=true, showPower=true },
    target = { width=275, height=40, offsetX= 260, offsetY=80, showName=true, showHP=true, showPower=true },
    focus  = { width=220, height=30, offsetX= 260, offsetY=135, showName=true, showHP=false, showPower=false },
    pet    = { width=220, height=30, offsetX=-260, offsetY=135, showName=true, showHP=false, showPower=false },
    targettarget = { width=220, height=30, offsetX=260, offsetY=225, showName=true, showHP=true, showPower=false },
    focustarget = { width=180, height=30, offsetX=260, offsetY=180, showName=true, showHP=true, showPower=false },
    boss   = { width=180, height=30, offsetX=360, offsetY=230, spacing=-96, bossLayoutMode="VERTICAL_DOWN", showName=true, showHP=true, showPower=false },
}
local MSUF_RESET_ANCHOR_UNITS = { "player", "target", "focus", "focustarget", "pet", "targettarget", "boss" }
local MSUF_FullResetPending = false
local function MSUF_ResetPositionAnchorsToScreen()
    if type(MSUF_DB) ~= "table" then return end

    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    g.anchorToCooldown = false
    g.anchorName = "UIParent"

    for i = 1, #MSUF_RESET_ANCHOR_UNITS do
        local unit = MSUF_RESET_ANCHOR_UNITS[i]
        local conf = MSUF_DB[unit]
        if type(conf) == "table" then
            conf.anchorFrameName = nil
            conf.anchorToUnitframe = "GLOBAL"
        end
    end
end
--- Full reset intentionally clears SavedVariables references and asks for a
--- reload so defaults/migrations rebuild state from a clean profile.
local function MSUF_DoFullReset(opts)
    opts = opts or {}
    local skipReload = (opts.skipReload == true)
    if InCombatLockdown and InCombatLockdown() then
        print(Tr("|cffff0000MSUF:|r Cannot do FULL reset while in combat."))
         return
    end
    MSUF_DB = nil
    MSUF_GlobalDB = nil
    MSUF_ActiveProfile = nil
    print(Tr("|cffff0000MSUF:|r FULL RESET executed - all MSUF profiles & settings deleted for this account."))
    if skipReload then
        print(Tr("|cffffff00MSUF:|r Reset staged. Please type |cff00ff00/reload|r OR use: MSUF Menu > Advanced > Factory Reset."))
         return
    end
    print(Tr("|cffffff00MSUF:|r Reloading UI to rebuild clean defaults..."))
	--- NOTE: C_UI.Reload() is protected; addons may get ADDON_ACTION_BLOCKED.
	--- ReloadUI() is the safe public API for addons.
	if type(ReloadUI) == "function" then
		ReloadUI()
	end
 end
--- Expose for the Slash Menu (button click = hardware event, safe for ReloadUI)
PublishCompat("MSUF_DoFullReset", MSUF_DoFullReset)
--- ==========================================================================
--- Slash command registry
---
--- Every /msuf sub-command registers itself here: the generic ones below, the
--- menu-owned ones from the Options addon's Shell/Menu2/MSUF_Menu2_API.lua
--- once that LoadOnDemand addon has loaded,
--- and the standalone diagnostic commands from the files that own them.
--- Dispatch and the help text read the same table, so a command can never
--- exist without being listed, and help can never advertise something that is
--- not actually loaded (the old hand-written list drifted into both).
---
--- Cost model: building this table is load-time only. Nothing here registers
--- an event, hooks a frame, or schedules a ticker, so the whole command
--- surface costs exactly zero while the player is in combat.
--- ==========================================================================
local Commands = MSUF.SlashCommands or {}
MSUF.SlashCommands = Commands
Commands.order = Commands.order or {}
Commands.byWord = Commands.byWord or {}
Commands.external = Commands.external or {}
--- Namespaced mirror of the _G export above; new internal callers should use
--- this instead of the global.
Commands.DoFullReset = Commands.DoFullReset or MSUF_DoFullReset

local COMMAND_GROUPS = { "general", "frames", "profiles", "diagnostics" }
local COMMAND_GROUP_TITLES = {
    general = "General",
    frames = "Frames and Edit Mode",
    profiles = "Profiles and resets",
    diagnostics = "Diagnostics",
}

--- entry = { name, aliases, usage, help, group, dev, run(rest, fullMessage) }
function Commands.Register(entry)
    if type(entry) ~= "table" then return false, "invalid entry" end
    local name = tostring(entry.name or ""):lower()
    if name == "" or type(entry.run) ~= "function" then return false, "invalid command" end
    local words = { name }
    if type(entry.aliases) == "table" then
        for i = 1, #entry.aliases do words[#words + 1] = tostring(entry.aliases[i]):lower() end
    end
    --- Validate before publishing: a half-registered command would answer to
    --- some of its words and fall through to the page/search fallback on others.
    for i = 1, #words do
        if Commands.byWord[words[i]] then return false, "duplicate command word: " .. words[i] end
    end
    entry.name = name
    entry.group = COMMAND_GROUP_TITLES[entry.group] and entry.group or "general"
    entry.usage = entry.usage or ("/msuf " .. name)
    for i = 1, #words do Commands.byWord[words[i]] = entry end
    Commands.order[#Commands.order + 1] = entry
    return true
end

--- Standalone slash commands (/rl and the diagnostics) list themselves from the
--- file that owns them, so a command that ships unloaded never reaches help.
function Commands.RegisterExternal(entry)
    if type(entry) ~= "table" or type(entry.usage) ~= "string" then return false end
    Commands.external[#Commands.external + 1] = entry
    return true
end

function Commands.Get(word)
    return Commands.byWord[tostring(word or ""):lower()]
end

--- Menu2 installs the fallback for bare /msuf, page names, and unknown words.
function Commands.SetFallback(fn)
    if type(fn) ~= "function" then return false end
    Commands.fallback = fn
    return true
end

local function PrintCommandLine(usage, help)
    print("  |cffffff00" .. tostring(usage) .. "|r  " .. Tr(help or ""))
end

function Commands.PrintHelp(includeDev)
    print(Tr("|cff00ff00MSUF commands:|r"))
    local shown = 0
    for groupIndex = 1, #COMMAND_GROUPS do
        local group = COMMAND_GROUPS[groupIndex]
        local header = false
        for i = 1, #Commands.order do
            local entry = Commands.order[i]
            if entry.group == group and (includeDev or not entry.dev) then
                if not header then
                    header = true
                    print("|cff7aa2f7" .. Tr(COMMAND_GROUP_TITLES[group]) .. "|r")
                end
                shown = shown + 1
                PrintCommandLine(entry.usage, entry.help)
            end
        end
    end
    local externalHeader = false
    for i = 1, #Commands.external do
        local entry = Commands.external[i]
        if includeDev or not entry.dev then
            if not externalHeader then
                externalHeader = true
                print("|cff7aa2f7" .. Tr("Other commands") .. "|r")
            end
            shown = shown + 1
            PrintCommandLine(entry.usage, entry.help)
        end
    end
    if not includeDev then
        print(Tr("Type /msuf help all to also list the diagnostic commands."))
    end
    return shown
end

function Commands.Dispatch(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local word, rest = msg:match("^(%S+)%s*(.-)$")
    local entry = word and Commands.byWord[word:lower()] or nil
    --- Only the command word is lowercased. Arguments keep their original case
    --- because profile names are free text and stored verbatim.
    if entry then return entry.run(rest or "", msg) end
    if type(Commands.fallback) == "function" then return Commands.fallback(msg) end
    Commands.PrintHelp(false)
end

local function MSUF_PrintHelp(includeDev)
    return Commands.PrintHelp(includeDev == true)
end
PublishCompat("MSUF_PrintHelp", MSUF_PrintHelp)

local function MSUF_FrameDebugName(frame)
    if not frame then return "nil" end
    local name = frame.GetName and frame:GetName()
    if type(name) == "string" and name ~= "" then return name end
    return tostring(frame)
end

local function MSUF_SafeGetKeyboardPropagation(frame)
    if not (frame and frame.GetPropagateKeyboardInput) then return nil end
    return frame:GetPropagateKeyboardInput()
end

--- Diagnostic command for stuck movement/keybind reports. It only prints state;
--- it must not change keyboard propagation or frame focus.
local function MSUF_PrintInputDebug()
    print("|cff7aa2f7MSUF INPUT|r keyboard diagnostics")
    print("Bindings: W=" .. tostring(GetBindingAction and GetBindingAction("W") or "?")
        .. " SPACE=" .. tostring(GetBindingAction and GetBindingAction("SPACE") or "?"))

    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    print("Keyboard focus: " .. MSUF_FrameDebugName(focus))

    local st = _G.MSUF_EditState
    print("MSUF edit: active=" .. tostring(st and st.active)
        .. " popupOpen=" .. tostring(st and st.popupOpen)
        .. " unit=" .. tostring(st and st.unitKey))

    if type(EnumerateFrames) ~= "function" then
        print("EnumerateFrames unavailable.")
        return
    end

    local found, scanned = 0, 0
    local frame = EnumerateFrames()
    while frame and scanned < 12000 do
        scanned = scanned + 1
        local keyboard = frame.IsKeyboardEnabled and frame:IsKeyboardEnabled()
        if keyboard then
            local shown = (not frame.IsShown) or frame:IsShown()
            local propagate = MSUF_SafeGetKeyboardPropagation(frame)
            if shown or propagate == false then
                found = found + 1
                if found <= 20 then
                    print(string.format("%02d %s shown=%s propagate=%s strata=%s level=%s",
                        found,
                        MSUF_FrameDebugName(frame),
                        tostring(shown),
                        tostring(propagate),
                        tostring(frame.GetFrameStrata and frame:GetFrameStrata() or "?"),
                        tostring(frame.GetFrameLevel and frame:GetFrameLevel() or "?")))
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    if found == 0 then
        print("No shown keyboard-enabled frames found.")
    elseif found > 20 then
        print("... " .. tostring(found - 20) .. " more keyboard-enabled frames hidden.")
    end
end
--- ==========================================================================
--- Generic command registrations
---
--- Menu-owned commands (edit mode, search, guided setup, page navigation) are
--- registered from the Options addon's Shell/Menu2/MSUF_Menu2_API.lua, which
--- loads on first configuration demand.
--- ==========================================================================
local function CommandsInCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function CommandsAddonVersion()
    local getMeta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getMeta) == "function" then
        local version = getMeta(addonName or "MidnightSimpleUnitFrames", "Version")
        if type(version) == "string" and version ~= "" then return version end
    end
    return "unknown"
end

local function CommandsProfileList()
    if type(_G.MSUF_GetAllProfiles) ~= "function" then return nil end
    local list = _G.MSUF_GetAllProfiles()
    return (type(list) == "table") and list or nil
end

--- Profile names are free text, so a chat argument matches case-insensitively
--- and by unique prefix. An ambiguous prefix must never silently pick one:
--- loading the wrong profile is a destructive-feeling surprise.
local function CommandsResolveProfile(name)
    local list = CommandsProfileList()
    if not list then return nil, "unavailable" end
    name = tostring(name or "")
    if name == "" then return nil, "empty" end
    local lowered = name:lower()
    local prefix
    for i = 1, #list do
        local candidate = list[i]
        if candidate == name or candidate:lower() == lowered then return candidate end
        if candidate:lower():sub(1, #lowered) == lowered then
            if prefix and prefix ~= candidate then return nil, "ambiguous" end
            prefix = candidate
        end
    end
    if prefix then return prefix end
    return nil, "unknown"
end

local function CommandsProfilesUnavailable()
    print(Tr("|cffff0000MSUF:|r The profile module is not loaded."))
end

Commands.Register({
    name = "help",
    aliases = { "commands" },
    group = "general",
    usage = "/msuf help [all]",
    help = "List every MSUF command that is currently loaded.",
    run = function(rest)
        rest = rest:lower()
        Commands.PrintHelp(rest == "all" or rest == "full" or rest == "dev")
    end,
})

Commands.Register({
    name = "version",
    aliases = { "ver", "status" },
    group = "general",
    usage = "/msuf version",
    help = "Print the addon version, the active profile and the Edit Mode state.",
    run = function()
        local list = CommandsProfileList()
        local editing = type(_G.MSUF_IsInEditMode) == "function" and _G.MSUF_IsInEditMode() == true
        print("|cff00b7ebMSUF|r " .. CommandsAddonVersion())
        print(string.format(Tr("  Profile: %s (%d saved)"),
            tostring(_G.MSUF_ActiveProfile or "?"), list and #list or 0))
        print(string.format(Tr("  Edit Mode: %s - In combat: %s"),
            editing and "|cff73dacaON|r" or "|cfff7768eOFF|r",
            CommandsInCombat() and "|cff73dacaYES|r" or "|cfff7768eNO|r"))
    end,
})

Commands.Register({
    name = "reload",
    group = "general",
    usage = "/msuf reload",
    help = "Reload the interface, same as /rl.",
    run = function()
        if type(ReloadUI) == "function" then ReloadUI() end
    end,
})

Commands.Register({
    name = "absorb",
    group = "frames",
    usage = "/msuf absorb",
    help = "Toggle the absorb bars on and off.",
    run = function()
        --- The toggle runs the full apply pipeline, which writes layout. The
        --- old routing leaned on Menu2's blanket combat check for this.
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot change absorb bars while in combat."))
            return
        end
        MSUF_Chat_RunEnsureDB()
        local g = (type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table") and MSUF_DB.general or nil
        if not g then
            print(Tr("|cffff0000MSUF:|r DB not initialized."))
            return
        end
        g.enableAbsorbBar = not (g.enableAbsorbBar == true)
        g.absorbTextMode = g.enableAbsorbBar and 2 or 1
        g.showTotalAbsorbAmount = false
        MSUF_Chat_RunApplyAllSettings()
        if g.enableAbsorbBar then
            print(Tr("|cff00ff00MSUF:|r Absorb bars ENABLED."))
        else
            print(Tr("|cff00ff00MSUF:|r Absorb bars DISABLED."))
        end
    end,
})

Commands.Register({
    name = "profile",
    aliases = { "profiles" },
    group = "profiles",
    usage = "/msuf profile [name]",
    help = "List your profiles, or save the current settings as a new profile.",
    run = function(rest)
        local list = CommandsProfileList()
        if not list then return CommandsProfilesUnavailable() end
        if rest == "" then
            local active = tostring(_G.MSUF_ActiveProfile or "")
            print(Tr("|cff00b7ebMSUF|r profiles:"))
            for i = 1, #list do
                if list[i] == active then
                    print("  |cff00ff00> " .. list[i] .. "|r")
                else
                    print("    " .. list[i])
                end
            end
            print(Tr("  /msuf load <name> switches profile, /msuf profile <name> saves a new one."))
            return
        end
        if type(_G.MSUF_CreateProfile) ~= "function" or type(_G.MSUF_SwitchProfile) ~= "function" then
            return CommandsProfilesUnavailable()
        end
        --- Creating only copies a table, but the switch that follows runs the
        --- full apply pipeline, so the whole command stays out of combat.
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot change profiles while in combat."))
            return
        end
        if _G.MSUF_CreateProfile(rest) then _G.MSUF_SwitchProfile(rest) end
    end,
})

Commands.Register({
    name = "load",
    aliases = { "use", "switch" },
    group = "profiles",
    usage = "/msuf load <name>",
    help = "Load one of your saved profiles.",
    run = function(rest)
        if type(_G.MSUF_SwitchProfile) ~= "function" then return CommandsProfilesUnavailable() end
        if rest == "" then
            print(Tr("|cffffcc00MSUF:|r Usage: /msuf load <name>. Type /msuf profile to list them."))
            return
        end
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot change profiles while in combat."))
            return
        end
        local name, reason = CommandsResolveProfile(rest)
        if not name then
            if reason == "ambiguous" then
                print(string.format(Tr("|cffff0000MSUF:|r '%s' matches more than one profile. Type the full name."), rest))
            elseif reason == "unavailable" then
                CommandsProfilesUnavailable()
            else
                print(string.format(Tr("|cffff0000MSUF:|r Unknown profile '%s'. Type /msuf profile to list them."), rest))
            end
            return
        end
        if name == _G.MSUF_ActiveProfile then
            print(string.format(Tr("|cffffd700MSUF:|r Profile '%s' is already active."), name))
            return
        end
        _G.MSUF_SwitchProfile(name)
    end,
})

local MSUF_PendingProfileDelete
Commands.Register({
    name = "delete",
    aliases = { "deleteprofile" },
    group = "profiles",
    usage = "/msuf delete <name>",
    help = "Delete one of your saved profiles. Repeat the command to confirm.",
    run = function(rest)
        if type(_G.MSUF_DeleteProfile) ~= "function" then return CommandsProfilesUnavailable() end
        if rest == "" then
            print(Tr("|cffffcc00MSUF:|r Usage: /msuf delete <name>. Type /msuf profile to list them."))
            return
        end
        --- Deleting the active profile switches to a survivor, which runs the
        --- apply pipeline, so this is combat-guarded like every profile write.
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot change profiles while in combat."))
            return
        end
        local name, reason = CommandsResolveProfile(rest)
        if not name then
            if reason == "ambiguous" then
                print(string.format(Tr("|cffff0000MSUF:|r '%s' matches more than one profile. Type the full name."), rest))
            elseif reason == "unavailable" then
                CommandsProfilesUnavailable()
            else
                print(string.format(Tr("|cffff0000MSUF:|r Unknown profile '%s'. Type /msuf profile to list them."), rest))
            end
            return
        end
        if MSUF_PendingProfileDelete ~= name then
            MSUF_PendingProfileDelete = name
            print(string.format(Tr("|cffffcc00MSUF:|r Repeat |cffffff00/msuf delete %s|r to delete that profile for good."), name))
            return
        end
        MSUF_PendingProfileDelete = nil
        _G.MSUF_DeleteProfile(name)
    end,
})

Commands.Register({
    name = "reset",
    group = "profiles",
    usage = "/msuf reset",
    help = "Reset all frame positions and visibility to the defaults.",
    run = function()
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot reset while in combat."))
            return
        end
        MSUF_Chat_RunEnsureDB()
        if MSUF_DB then
            for unit, defaults in pairs(MSUF_RESET_DEFAULTS) do
                MSUF_DB[unit] = MSUF_DB[unit] or {}
                local t = MSUF_DB[unit]
                for k, v in pairs(defaults) do
                    t[k] = v
                end
                if t.enabled == nil then
                    t.enabled = true
                end
            end
            MSUF_ResetPositionAnchorsToScreen()
        end
        MSUF_Chat_RunApplyAllSettings()
        if type(_G.MSUF_ForceReanchorAllUnitFrames_Once) == "function" then
            _G.MSUF_ForceReanchorAllUnitFrames_Once()
        end
        local updateFonts = _G.MSUF_UpdateAllFonts
        if type(updateFonts) == "function" then
            updateFonts()
        end
        print(Tr("|cff00ff00MSUF:|r Positions and visibility reset to defaults."))
    end,
})

local MSUF_ProfileResetPending = false
Commands.Register({
    name = "default",
    aliases = { "defaults", "resetprofile" },
    group = "profiles",
    usage = "/msuf default [confirm]",
    help = "Reset every setting in the active profile back to the defaults.",
    run = function(rest)
        if type(_G.MSUF_ResetProfile) ~= "function" then return CommandsProfilesUnavailable() end
        if CommandsInCombat() then
            print(Tr("|cffff0000MSUF:|r Cannot reset a profile while in combat."))
            return
        end
        local active = tostring(_G.MSUF_ActiveProfile or "")
        if rest:lower() ~= "confirm" then
            MSUF_ProfileResetPending = true
            print(string.format(Tr("|cffffcc00MSUF:|r This resets every setting in profile '%s', not just positions."), active))
            print(Tr("|cffffcc00MSUF:|r Type |cffffff00/msuf default confirm|r to go ahead."))
            return
        end
        if not MSUF_ProfileResetPending then
            print(Tr("|cffffcc00MSUF:|r Type |cffffff00/msuf default|r first, then confirm it."))
            return
        end
        MSUF_ProfileResetPending = false
        _G.MSUF_ResetProfile(active ~= "" and active or nil)
    end,
})

--- Should clean this up since we have now a button for full reset.
Commands.Register({
    name = "fullreset",
    group = "profiles",
    usage = "/msuf fullreset [confirm]",
    help = "Delete every MSUF profile and setting on this account.",
    run = function(rest)
        if not MSUF_FullResetPending then
            MSUF_FullResetPending = true
            print(Tr("|cffff0000MSUF WARNING:|r This will delete |cffff0000ALL|r MSUF profiles & settings for this account."))
            print(Tr("|cffffcc00MSUF:|r Type |cffffff00/msuf fullreset confirm|r to stage the reset."))
            print(Tr("|cffffcc00MSUF:|r Then click: MSUF Menu > Advanced > Factory Reset (or type /reload)."))
            return
        end
        if rest:lower() ~= "confirm" then
            MSUF_FullResetPending = false
            print(Tr("|cffffcc00MSUF:|r Full reset cancelled. If you still want it, type:"))
            print("  /msuf fullreset")
            print("  /msuf fullreset confirm")
            print(Tr("  (then /reload OR MSUF Menu > Advanced > Factory Reset)"))
            return
        end
        MSUF_FullResetPending = false
        MSUF_DoFullReset({ skipReload = true })
    end,
})

Commands.Register({
    name = "analytics",
    group = "general",
    --- "/" and not "|" between the choices: the usage is printed inside a
    --- |cRRGGBB colour block and a stray pipe starts an escape sequence there.
    usage = "/msuf analytics on/off/status",
    help = "Turn the Wago Analytics beta telemetry on or off.",
    run = function(rest)
        if type(_G.MSUF_Analytics_HandleSlash) == "function" then
            _G.MSUF_Analytics_HandleSlash(rest)
        else
            print(Tr("|cffff0000MSUF:|r Analytics module not loaded."))
        end
    end,
})

Commands.Register({
    name = "gfhoverdebug",
    group = "diagnostics",
    dev = true,
    usage = "/msuf gfhoverdebug on/off/status",
    help = "Debug the group-frame hover and tooltip paths.",
    run = function(rest)
        local arg = rest:lower()
        if arg == "" or arg == "toggle" then
            Debug.gfHover = not (Debug.gfHover == true)
        elseif arg == "on" then
            Debug.gfHover = true
        elseif arg == "off" then
            Debug.gfHover = false
        elseif arg == "status" then
            --- no-op, only print below
        else
            print(Tr("|cffff0000MSUF:|r Usage: /msuf gfhoverdebug on|off|status"))
            return
        end
        print(string.format("|cff7aa2f7MSUF|r: Group-frame hover debug is %s.", Debug.gfHover == true and "|cff73dacaON|r" or "|cfff7768eOFF|r"))
    end,
})

Commands.Register({
    name = "inputdebug",
    group = "diagnostics",
    dev = true,
    usage = "/msuf inputdebug",
    help = "Print the keyboard-capture frames for movement-lock diagnosis.",
    run = function()
        MSUF_PrintInputDebug()
    end,
})

--- The old "!msuf help" chat trigger is gone: it kept 12 CHAT_MSG_* events
--- registered for the whole session (every trade/guild/say line paid string
--- work) to duplicate what /msuf help already does.
SLASH_MIDNIGHTSUF1 = "/msufold"
SlashCmdList["MIDNIGHTSUF"] = function(msg)
    return Commands.Dispatch(msg)
end
--- "/rl" is a shared convenience token rather than ours: ElvUI and others
--- register it under their own SlashCmdList key, so a second claim does not
--- collide at the key level and both survive until Blizzard folds every SLASH_*
--- token into hash_SlashCmdList. There the last key walked wins, and that walk
--- is unordered, so the reload command would belong to whichever addon the hash
--- happened to reach last. Claim the token only while it is still free.
--- Deliberately a plain table read on the load path: the command surface has to
--- stay inert (no frame, no event, no ticker -- slash_command_registry_smoke).
local function SlashTokenClaimed(token)
    local hash = _G.hash_SlashCmdList
    if type(hash) == "table" and hash[token] ~= nil then
        return true
    end
    local list = _G.SlashCmdList
    if type(list) ~= "table" then
        return false
    end
    -- Blizzard wipes SlashCmdList into a proxy on each hash import, so this walk
    -- sees exactly the registrations made since then -- which is where a
    -- competing addon's "/rl" lives when it loaded ahead of MSUF.
    for key in pairs(list) do
        local index = 1
        local tag = _G["SLASH_" .. key .. index]
        while type(tag) == "string" do
            if tag:upper() == token then
                return true
            end
            index = index + 1
            tag = _G["SLASH_" .. key .. index]
        end
    end
    return false
end

if not SlashTokenClaimed("/RL") then
    SLASH_MSUFRELOADUI1 = "/rl"
    SlashCmdList["MSUFRELOADUI"] = function()
        if type(ReloadUI) == "function" then
            ReloadUI()
        end
    end
end
--- Listed either way: when the token was already taken the other addon still
--- reloads the interface, so the help entry stays truthful.
Commands.RegisterExternal({ usage = "/rl", help = "Reload the interface." })

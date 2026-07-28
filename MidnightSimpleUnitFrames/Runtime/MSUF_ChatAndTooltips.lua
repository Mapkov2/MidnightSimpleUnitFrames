--- Runtime/MSUF_ChatAndTooltips.lua
--- Slash commands, lightweight debug print helpers, reset commands, tooltip
--- helpers, and Blizzard Edit Mode bridge.
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
local MSUF_PlayerInfoFrame
local function MSUF_GetPlayerInfoFrame()
    if MSUF_PlayerInfoFrame then
         return MSUF_PlayerInfoFrame
    end
    local f = CreateFrame("Frame", "MSUF_PlayerInfoFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 90)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 180)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)
    end
    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    nameFS:SetPoint("TOPLEFT", 8, -8)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    nameFS:SetTextColor(1, 1, 1) --- Wei wie normaler Tooltip-Text
    local line2FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line2FS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    line2FS:SetJustifyH("LEFT")
    local line3FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line3FS:SetPoint("TOPLEFT", line2FS, "BOTTOMLEFT", 0, -2)
    line3FS:SetJustifyH("LEFT")
    local line4FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line4FS:SetPoint("TOPLEFT", line3FS, "BOTTOMLEFT", 0, -2)
    line4FS:SetJustifyH("LEFT")
    local line5FS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    line5FS:SetPoint("TOPLEFT", line4FS, "BOTTOMLEFT", 0, -2)
    line5FS:SetJustifyH("LEFT")
    line5FS:SetTextColor(0.8, 0.8, 0.8) --- leicht ausgegraut wie Location-Zeile
    f.name  = nameFS
    f.line2 = line2FS
    f.line3 = line3FS
    f.line4 = line4FS
    f.line5 = line5FS
    f:Hide()
    MSUF_PlayerInfoFrame = f
     return f
end
MSUF.Tooltips = MSUF.Tooltips or {}
local Tooltips = MSUF.Tooltips

local TOOLTIP_PROVIDER_GAME = "GAME"
local TOOLTIP_PROVIDER_MSUF = "MSUF"
local TOOLTIP_ANCHOR_EXTERNAL = "EXTERNAL"
local TOOLTIP_ANCHOR_FIXED = "FIXED"
local TOOLTIP_ANCHOR_CURSOR = "CURSOR"
local TOOLTIP_MODE_ALWAYS = "ALWAYS"
local TOOLTIP_MODE_OOC = "OOC"
local TOOLTIP_MODE_MODIFIER = "MODIFIER"
local TOOLTIP_MODE_NEVER = "NEVER"
local TOOLTIP_MOD_ALT = "ALT"
local TOOLTIP_MOD_CTRL = "CTRL"
local TOOLTIP_MOD_SHIFT = "SHIFT"

local function MSUF_NormalizeTooltipModeValue(mode)
    if mode == TOOLTIP_MODE_OOC
        or mode == TOOLTIP_MODE_MODIFIER
        or mode == TOOLTIP_MODE_NEVER
    then
        return mode
    end
    if mode == "OFF" then
        return TOOLTIP_MODE_NEVER
    end
    return TOOLTIP_MODE_ALWAYS
end

local function MSUF_NormalizeTooltipModifierValue(modifier)
    if modifier == TOOLTIP_MOD_CTRL or modifier == TOOLTIP_MOD_SHIFT then
        return modifier
    end
    return TOOLTIP_MOD_ALT
end

local function MSUF_TooltipModeAllowed(mode, modifier)
    mode = MSUF_NormalizeTooltipModeValue(mode)
    if mode == TOOLTIP_MODE_NEVER then
        return false
    end
    if mode == TOOLTIP_MODE_OOC then
        return not (_G.InCombatLockdown and _G.InCombatLockdown())
    end
    if mode == TOOLTIP_MODE_MODIFIER then
        modifier = MSUF_NormalizeTooltipModifierValue(modifier)
        if modifier == TOOLTIP_MOD_CTRL then return _G.IsControlKeyDown and _G.IsControlKeyDown() end
        if modifier == TOOLTIP_MOD_SHIFT then return _G.IsShiftKeyDown and _G.IsShiftKeyDown() end
        return _G.IsAltKeyDown and _G.IsAltKeyDown()
    end
    return true
end

local function MSUF_GetTooltipGeneral()
    MSUF_Chat_RunEnsureDB()
    local db = (type(MSUF_DB) == "table") and MSUF_DB or nil
    db = db or {}
    db.general = db.general or {}
    return db.general
end

local function MSUF_NormalizeTooltipSettings(g)
    if type(g) ~= "table" then
        g = MSUF_GetTooltipGeneral()
    end

    local provider = g.unitTooltipProvider
    if provider ~= TOOLTIP_PROVIDER_GAME and provider ~= TOOLTIP_PROVIDER_MSUF then
        provider = (g.disableUnitInfoTooltips == false) and TOOLTIP_PROVIDER_MSUF or TOOLTIP_PROVIDER_GAME
        g.unitTooltipProvider = provider
    end

    local anchor = g.unitTooltipAnchor
    if anchor ~= TOOLTIP_ANCHOR_EXTERNAL and anchor ~= TOOLTIP_ANCHOR_FIXED and anchor ~= TOOLTIP_ANCHOR_CURSOR then
        local legacyStyle = (g.unitInfoTooltipStyle == "modern") and TOOLTIP_ANCHOR_CURSOR or TOOLTIP_ANCHOR_FIXED
        if provider == TOOLTIP_PROVIDER_MSUF then
            anchor = legacyStyle
        elseif type(g.tooltipPosX) == "number" and type(g.tooltipPosY) == "number" then
            anchor = TOOLTIP_ANCHOR_FIXED
        elseif g.unitInfoTooltipStyle == "modern" then
            anchor = TOOLTIP_ANCHOR_CURSOR
        elseif g.disableUnitInfoTooltips == true then
            anchor = TOOLTIP_ANCHOR_EXTERNAL
        else
            anchor = TOOLTIP_ANCHOR_EXTERNAL
        end
        g.unitTooltipAnchor = anchor
    end

    if provider == TOOLTIP_PROVIDER_MSUF and anchor == TOOLTIP_ANCHOR_EXTERNAL then
        anchor = TOOLTIP_ANCHOR_FIXED
        g.unitTooltipAnchor = anchor
    end

    g.disableUnitInfoTooltips = (provider ~= TOOLTIP_PROVIDER_MSUF)
    g.unitInfoTooltipStyle = (anchor == TOOLTIP_ANCHOR_CURSOR) and "modern" or "classic"

    local mode = MSUF_NormalizeTooltipModeValue(g.unitTooltipMode)
    if g.unitTooltipMode ~= mode then
        g.unitTooltipMode = mode
    end
    local modifier = MSUF_NormalizeTooltipModifierValue(g.unitTooltipModifier)
    if g.unitTooltipModifier ~= modifier then
        g.unitTooltipModifier = modifier
    end

    return provider, anchor, mode, modifier
end

local tooltipCache = {}
-- Combat fast-path flag. hoverInert is true exactly when a hover cannot show a
-- tooltip right now: mode NEVER (always) or mode OOC while in combat. The
-- per-frame OnEnter/OnLeave hooks read this single boolean and bail, so those
-- configs cost nothing per hover in combat. It is recomputed only on combat
-- transitions and setting changes (below), never per hover. Assigned near the
-- combat watcher further down; forward-declared here so the cache refresh can
-- call it.
local MSUF_RecomputeHoverInert
Tooltips.hoverInert = false

local function MSUF_GetTooltipCache()
    local g = MSUF_GetTooltipGeneral()
    if tooltipCache.general ~= g
        or tooltipCache.rawProvider ~= g.unitTooltipProvider
        or tooltipCache.rawAnchor ~= g.unitTooltipAnchor
        or tooltipCache.rawMode ~= g.unitTooltipMode
        or tooltipCache.rawModifier ~= g.unitTooltipModifier
        or tooltipCache.rawLegacyDisable ~= g.disableUnitInfoTooltips
        or tooltipCache.rawLegacyStyle ~= g.unitInfoTooltipStyle
    then
        local provider, anchor, mode, modifier = MSUF_NormalizeTooltipSettings(g)
        tooltipCache.general = g
        tooltipCache.rawProvider = g.unitTooltipProvider
        tooltipCache.rawAnchor = g.unitTooltipAnchor
        tooltipCache.rawMode = g.unitTooltipMode
        tooltipCache.rawModifier = g.unitTooltipModifier
        tooltipCache.rawLegacyDisable = g.disableUnitInfoTooltips
        tooltipCache.rawLegacyStyle = g.unitInfoTooltipStyle
        tooltipCache.provider = provider
        tooltipCache.anchor = anchor
        tooltipCache.mode = mode
        tooltipCache.modifier = modifier
    end
    return tooltipCache
end

local function MSUF_RefreshTooltipCache()
    tooltipCache.general = nil
    local cache = MSUF_GetTooltipCache()
    if MSUF_RecomputeHoverInert then MSUF_RecomputeHoverInert() end
    return cache
end

local function MSUF_ApplyTooltipFixedPoint(frame, g, defaultOffsetY)
    if not frame then return end
    frame:ClearAllPoints()
    local cx = g.tooltipPosX
    local cy = g.tooltipPosY
    if type(cx) == "number" and type(cy) == "number" then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx, cy)
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, defaultOffsetY or 16)
    end
end

local function MSUF_AnchorGameTooltip(owner, g, anchor)
    local gt = _G.GameTooltip
    if not gt or gt:IsForbidden() then return nil end

    if anchor == TOOLTIP_ANCHOR_CURSOR then
        gt:SetOwner(UIParent, "ANCHOR_CURSOR", 0, -100)
    elseif anchor == TOOLTIP_ANCHOR_FIXED then
        gt:SetOwner(UIParent, "ANCHOR_NONE")
        MSUF_ApplyTooltipFixedPoint(gt, g, 16)
    else
        if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
            _G.GameTooltip_SetDefaultAnchor(gt, owner or UIParent)
        elseif owner then
            gt:SetOwner(owner, "ANCHOR_RIGHT")
        else
            gt:SetOwner(UIParent, "ANCHOR_NONE")
        end
    end

    return gt
end

local function MSUF_ClearTrackedGameTooltip(owner, force)
    local gt = _G.GameTooltip
    if not gt or gt:IsForbidden() then return end
    if (not force) and gt._msufUnitTooltipOwner and gt._msufUnitTooltipOwner ~= owner then return end
    if (not force)
        and gt._msufUnitTooltipOwner == nil
        and gt._msufUnitTooltipUnit == nil
        and gt.IsShown
        and not gt:IsShown() then
        return
    end
    gt._msufUnitTooltipOwner = nil
    gt._msufUnitTooltipUnit = nil
    gt._msufUnitTooltipAnchor = nil
    if gt.IsShown and not gt:IsShown() then return end
    gt:Hide()
end

if _G.GameTooltip and (not _G.GameTooltip._msufTooltipTrackingHooked) then
    _G.GameTooltip._msufTooltipTrackingHooked = true
    _G.GameTooltip:HookScript("OnHide", function(tip)
        tip._msufUnitTooltipOwner = nil
        tip._msufUnitTooltipUnit = nil
    end)
end

local function MSUF_PositionPlayerInfoFrame(frame)
    local g = MSUF_GetTooltipGeneral()
    local _, anchor = MSUF_NormalizeTooltipSettings(g)

    if anchor == TOOLTIP_ANCHOR_CURSOR and GetCursorPosition and UIParent then
        frame:ClearAllPoints()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x, y = x / scale, y / scale
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 130, y - 150)
    else
        MSUF_ApplyTooltipFixedPoint(frame, g, 180)
    end
 end
--- Tooltip helpers (unified; keeps behavior, reduces copy/paste)
local MSUF_IsSecretValueAPI = _G.issecretvalue
local function MSUF_UnitInfo_IsSecret(value)
    return MSUF_IsSecretValueAPI and MSUF_IsSecretValueAPI(value) == true
end

local function MSUF_UnitInfo_PlainString(value)
    if MSUF_UnitInfo_IsSecret(value) then return nil end
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function MSUF_UnitInfo_PlainNumber(value)
    if MSUF_UnitInfo_IsSecret(value) then return nil end
    return tonumber(value)
end

local function MSUF_UnitInfo_PlainBoolean(value)
    if MSUF_UnitInfo_IsSecret(value) then return nil end
    return value == true or value == 1
end

local function MSUF_UnitInfo_DisplayName(unit, fallbackName)
    local name = UnitName(unit)
    if MSUF_UnitInfo_IsSecret(name) then return name end
    return MSUF_UnitInfo_PlainString(name) or MSUF_UnitInfo_PlainString(fallbackName) or ""
end

local function MSUF_UnitInfo_GetLocationText()
    local zoneValue, subzoneValue
    if GetZoneText then zoneValue = GetZoneText() end
    if GetSubZoneText then subzoneValue = GetSubZoneText() end
    local zone = MSUF_UnitInfo_PlainString(zoneValue)
    local subzone = MSUF_UnitInfo_PlainString(subzoneValue)
    if subzone and zone and subzone ~= zone then return subzone end
    return subzone or zone or ""
end
local function MSUF_UnitInfo_BuildNameLine(unit, fallbackName, isPlayer)
    local nameLine = MSUF_UnitInfo_DisplayName(unit, fallbackName)
    if MSUF_UnitInfo_IsSecret(nameLine) then return nameLine end
    if isPlayer then
        --- Secret-safe (12.0): UnitIsAFK/UnitIsDND may return secret booleans;
        --- direct boolean test in `if` would hard-error. Guard via issecretvalue.
        local getAway = _G.MSUF_GetCachedAwayStatus
        if getAway then
            local away = getAway(unit, true, true, false)
            if not MSUF_UnitInfo_IsSecret(away) and (away == 1 or away == 3) then
                nameLine = nameLine .. " <AFK>"
            elseif not MSUF_UnitInfo_IsSecret(away) and away == 2 then
                nameLine = nameLine .. " <DND>"
            end
        elseif UnitIsAFK then
            local afk = UnitIsAFK(unit)
            if MSUF_UnitInfo_PlainBoolean(afk) == true then
                nameLine = nameLine .. " <AFK>"
            elseif UnitIsDND then
                local dnd = UnitIsDND(unit)
                if MSUF_UnitInfo_PlainBoolean(dnd) == true then
                    nameLine = nameLine .. " <DND>"
                end
            end
        end
    end
     return nameLine
end
local function MSUF_UnitInfo_BuildLine4(faction, isPVP)
    if (not faction or faction == "") and not isPVP then
         return ""
    end
    local text = faction or ""
    if isPVP then
        if text ~= "" then
            text = text .. "  PvP"
        else
            text = "PvP"
        end
    end
     return text
end
local function MSUF_UnitInfo_BuildLine2_Player(level, race, classLoc)
    local n = MSUF_UnitInfo_PlainNumber(level)
    if n and n > 0 then
        if race and classLoc then
            return string.format("Level %d %s %s", n, race, classLoc)
        elseif classLoc then
            return string.format("Level %d %s", n, classLoc)
        else
            return string.format("Level %d", n)
        end
    end
    return classLoc or ""
end
local function MSUF_UnitInfo_ClassificationText(classification)
    classification = MSUF_UnitInfo_PlainString(classification)
    if classification == "elite" then
         return "Elite"
    elseif classification == "rare" then
         return "Rare"
    elseif classification == "rareelite" then
         return "Rare Elite"
    elseif classification == "worldboss" then
         return "Boss"
    end
     return nil
end
local function MSUF_UnitInfo_BuildLine2_NPC(level, classification)
    local n = MSUF_UnitInfo_PlainNumber(level)
    if not (n and n > 0) then
         return ""
    end
    local line2 = string.format("Level %d", n)
    local clsText = MSUF_UnitInfo_ClassificationText(classification)
    if clsText then
        line2 = line2 .. string.format(" (%s)", clsText)
    end
     return line2
end
local function MSUF_UnitInfo_SetText(fontString, value)
    if MSUF_UnitInfo_IsSecret(value) then
        fontString:SetText(value)
    else
        fontString:SetText(value or "")
    end
end
local function MSUF_UnitInfo_ShowFrame(f, nameLine, line2, line3, line4, loc)
    MSUF_UnitInfo_SetText(f.name, nameLine)
    MSUF_UnitInfo_SetText(f.line2, line2)
    MSUF_UnitInfo_SetText(f.line3, line3)
    MSUF_UnitInfo_SetText(f.line4, line4)
    MSUF_UnitInfo_SetText(f.line5, loc)
    MSUF_PositionPlayerInfoFrame(f)
    f:Show()
 end
local function ShowUnitInfoTooltip(unit, fallbackName)
    local f = MSUF_GetPlayerInfoFrame()
    local exists = UnitExists(unit)
    if not MSUF_UnitInfo_IsSecret(exists) and not exists then
        f:Hide()
         return
    end

    if unit == "pet" then
        local name = MSUF_UnitInfo_DisplayName(unit, fallbackName or "Pet")
        local level = MSUF_UnitInfo_PlainNumber(UnitLevel(unit))
        local creatureType = MSUF_UnitInfo_PlainString(UnitCreatureType(unit))
        local line2 = ""
        if level and level > 0 then
            line2 = string.format("Level %d", level)
        end
        MSUF_UnitInfo_ShowFrame(f, name, line2, creatureType or "", "", MSUF_UnitInfo_GetLocationText())
        return
    end

    local level = MSUF_UnitInfo_PlainNumber(UnitLevel(unit))
    local isPlayer = MSUF_UnitInfo_PlainBoolean(UnitIsPlayer(unit)) == true
    local race, classLoc, faction, isPVP
    if isPlayer then
        race = MSUF_UnitInfo_PlainString(UnitRace(unit))
        classLoc = MSUF_UnitInfo_PlainString(UnitClass(unit))
        faction = MSUF_UnitInfo_PlainString(UnitFactionGroup(unit))
        isPVP = MSUF_UnitInfo_PlainBoolean(UnitIsPVP(unit)) == true
    end

    local nameLine = MSUF_UnitInfo_BuildNameLine(unit, fallbackName, isPlayer)
    local line2 = isPlayer and MSUF_UnitInfo_BuildLine2_Player(level, race, classLoc)
        or MSUF_UnitInfo_BuildLine2_NPC(level, UnitClassification(unit))
    local line3 = isPlayer and (classLoc or "") or (MSUF_UnitInfo_PlainString(UnitCreatureType(unit)) or "")
    local line4 = isPlayer and MSUF_UnitInfo_BuildLine4(faction, isPVP) or ""

    if unit == "player" then
        local specName
        if GetSpecialization and GetSpecializationInfo then
            local specIndex = MSUF_UnitInfo_PlainNumber(GetSpecialization())
            if specIndex then
                local sex = MSUF_UnitInfo_PlainNumber(UnitSex("player"))
                local _, sName = GetSpecializationInfo(specIndex, nil, nil, nil, sex)
                specName = MSUF_UnitInfo_PlainString(sName)
            end
        end
        if specName and classLoc then
            line3 = string.format("%s %s", specName, classLoc)
        elseif specName then
            line3 = specName
        end
    end

    MSUF_UnitInfo_ShowFrame(f, nameLine, line2, line3, line4, MSUF_UnitInfo_GetLocationText())
 end
local function ShowPlayerInfoTooltip()
    ShowUnitInfoTooltip("player", "Player")
 end
local function ShowTargetInfoTooltip()
    ShowUnitInfoTooltip("target", "Target")
 end
local function ShowFocusInfoTooltip()
    ShowUnitInfoTooltip("focus", "Focus")
 end
local function ShowTargetTargetInfoTooltip()
    ShowUnitInfoTooltip("targettarget", "Target of Target")
 end
local function ShowFocusTargetInfoTooltip()
    ShowUnitInfoTooltip("focustarget", "Focus Target")
 end
local function ShowPetInfoTooltip()
    ShowUnitInfoTooltip("pet", "Pet")
 end
local function HidePlayerInfoTooltip()
    if MSUF_PlayerInfoFrame then
        --- If the Edit Mode tooltip preview is active, restore the preview
        --- instead of hiding the frame (OnLeave from unit frames must not
        --- kill the persistent drag-preview).
        if MSUF_PlayerInfoFrame._msufEditPreviewActive then
            if _G.MSUF_Tooltip_ShowEditPreview then
                _G.MSUF_Tooltip_ShowEditPreview()
            end
            return
        end
        if MSUF_PlayerInfoFrame.IsShown and not MSUF_PlayerInfoFrame:IsShown() then
            return
        end
        MSUF_PlayerInfoFrame:Hide()
    end
 end
PublishCompat("MSUF_ShowUnitInfoTooltip", ShowUnitInfoTooltip)
PublishCompat("MSUF_ShowPlayerInfoTooltip", ShowPlayerInfoTooltip)
PublishCompat("MSUF_ShowTargetInfoTooltip", ShowTargetInfoTooltip)
PublishCompat("MSUF_ShowFocusInfoTooltip", ShowFocusInfoTooltip)
PublishCompat("MSUF_ShowTargetTargetInfoTooltip", ShowTargetTargetInfoTooltip)
PublishCompat("MSUF_ShowFocusTargetInfoTooltip", ShowFocusTargetInfoTooltip)
PublishCompat("MSUF_ShowPetInfoTooltip", ShowPetInfoTooltip)
PublishCompat("MSUF_HidePlayerInfoTooltip", HidePlayerInfoTooltip)
Tooltips.GetGeneral = Tooltips.GetGeneral or MSUF_GetTooltipGeneral
Tooltips.Normalize = Tooltips.Normalize or MSUF_NormalizeTooltipSettings
Tooltips.Refresh = Tooltips.Refresh or MSUF_RefreshTooltipCache
Tooltips.Allowed = Tooltips.Allowed or function()
    local cache = MSUF_GetTooltipCache()
    return MSUF_TooltipModeAllowed(cache.mode, cache.modifier)
end
Tooltips.ShowUnit = Tooltips.ShowUnit or function(owner, unit, opts)
    if not unit then return false end
    local exists = UnitExists(unit)
    if not MSUF_UnitInfo_IsSecret(exists) and not exists then return false end
    local cache = MSUF_GetTooltipCache()
    local g = cache.general
    local provider, anchor = cache.provider, cache.anchor
    -- Fast disabled path: when the mode is NEVER, never reach gt:SetUnit (the
    -- ~0.3ms Blizzard tooltip build billed to MSUF on every hover). Cheap
    -- string compare before any cache/anchor work.
    if cache.mode == TOOLTIP_MODE_NEVER and not (opts and opts.ignoreMode == true) then
        return false
    end
    if not (opts and opts.ignoreMode == true) and not MSUF_TooltipModeAllowed(cache.mode, cache.modifier) then
        return false
    end
    if opts and opts.provider == TOOLTIP_PROVIDER_MSUF then
        provider = TOOLTIP_PROVIDER_MSUF
    end
    if opts and opts.anchor then
        anchor = opts.anchor
        if provider == TOOLTIP_PROVIDER_MSUF and anchor == TOOLTIP_ANCHOR_EXTERNAL then
            anchor = TOOLTIP_ANCHOR_FIXED
        end
    end

    if provider == TOOLTIP_PROVIDER_MSUF then
        MSUF_ClearTrackedGameTooltip(owner, true)
        ShowUnitInfoTooltip(unit, opts and opts.fallbackName)
        return true
    end

    -- Dedupe: re-hovering the same frame/unit (mouse jitter, or OnEnter
    -- re-firing) must not rebuild or re-anchor the tooltip.
    local gt = _G.GameTooltip
    if gt
        and gt._msufUnitTooltipOwner == owner
        and gt._msufUnitTooltipUnit == unit
        and gt._msufUnitTooltipAnchor == anchor
        and gt.IsShown and gt:IsShown()
        and gt.GetUnit then
        local _, shownUnit = gt:GetUnit()
        if shownUnit == unit then
            return true
        end
    end
    HidePlayerInfoTooltip()
    gt = MSUF_AnchorGameTooltip(owner, g, anchor)
    if not gt or type(gt.SetUnit) ~= "function" then return false end
    gt._msufUnitTooltipOwner = owner
    gt._msufUnitTooltipUnit = unit
    gt._msufUnitTooltipAnchor = anchor
    gt:SetUnit(unit)
    gt:Show()
    return true
end
Tooltips.HideUnit = Tooltips.HideUnit or function(owner)
    if MSUF_PlayerInfoFrame
        and (MSUF_PlayerInfoFrame._msufEditPreviewActive == true
            or not MSUF_PlayerInfoFrame.IsShown
            or MSUF_PlayerInfoFrame:IsShown()) then
        HidePlayerInfoTooltip()
    end
    MSUF_ClearTrackedGameTooltip(owner)
end

-- Assign the forward-declared fast-path recompute (see MSUF_GetTooltipCache).
-- Runs only on combat transitions, world entry, and setting changes -- never
-- per hover. When a config becomes inert we also drop any unit tooltip we own
-- (never another addon's, hence the owner check) so nothing lingers while the
-- OnLeave hooks are short-circuited.
MSUF_RecomputeHoverInert = function()
    local mode = MSUF_GetTooltipCache().mode
    local inert
    if mode == TOOLTIP_MODE_NEVER then
        inert = true
    elseif mode == TOOLTIP_MODE_OOC then
        inert = (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
    else
        inert = false
    end
    if inert == Tooltips.hoverInert then return end
    Tooltips.hoverInert = inert
    if inert then
        local gt = _G.GameTooltip
        if gt and not gt:IsForbidden() and gt._msufUnitTooltipOwner ~= nil then
            MSUF_ClearTrackedGameTooltip(gt._msufUnitTooltipOwner)
        end
        HidePlayerInfoTooltip()
    end
end

do
    local watcher = _G.CreateFrame and _G.CreateFrame("Frame")
    if watcher and type(watcher.RegisterEvent) == "function" and type(watcher.SetScript) == "function" then
        watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        watcher:SetScript("OnEvent", MSUF_RecomputeHoverInert)
    end
    MSUF_RecomputeHoverInert()
end
--- [8c6] Removed legacy Options UI relayout functions (Player/Bars).
--- These were dead/duplicate layout builders superseded by MSUF_Options_Core.lua.
do
    local SetBlizzardEditModeFromMSUF = _G.MSUF_SetBlizzardEditModeFromMSUF
    if type(SetBlizzardEditModeFromMSUF) ~= "function" then
        SetBlizzardEditModeFromMSUF = function(active)
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            MSUF_Chat_RunEnsureDB()
            if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
                return
            end
            local emf = _G.EditModeManagerFrame
            if not emf then return end
            if active then
                if not _G.MSUF_BlizzEditModeStartedByMSUF then
                    PublishCompat("MSUF_BlizzEditModeStartedByMSUF", true)
                end
                if type(securecallfunction) == "function" and type(_G.ShowUIPanel) == "function" then
                    securecallfunction(_G.ShowUIPanel, emf) --- this will show the edit mode panel and enter edit mode
                elseif emf.Show then
                    emf:Show()
                elseif emf.EnterEditMode then
                    emf:EnterEditMode()
                end
            else
                if not _G.MSUF_BlizzEditModeStartedByMSUF then return end
                PublishCompat("MSUF_BlizzEditModeStartedByMSUF", nil)
                if type(securecallfunction) == "function" and type(emf.ExitEditMode) == "function" then
                    securecallfunction(emf.ExitEditMode, emf)
                elseif emf.ExitEditMode then
                    emf:ExitEditMode()
                end
                if type(securecallfunction) == "function" and type(_G.HideUIPanel) == "function" and emf.IsShown and emf:IsShown() then
                    securecallfunction(_G.HideUIPanel, emf)
                elseif emf.Hide and emf.IsShown and emf:IsShown() then
                    emf:Hide()
                end
            end
        end
    end
    PublishCompat("MSUF_SetBlizzardEditModeFromMSUF", SetBlizzardEditModeFromMSUF)
end
--- [8c6] Removed PLAYER_LOGIN Options relayout hook (Bars).
MSUF.MSUF_UpdateAllFonts = MSUF.MSUF_UpdateAllFonts or _G.MSUF_UpdateAllFonts

--- ==========================================================================
--- Edit Mode: Tooltip Position Drag Handle
--- Shows a preview of the MSUF tooltip and makes it draggable to set a custom
--- position. Persists to MSUF_DB.general.tooltipPosX / .tooltipPosY.
--- Only active while MSUF Edit Mode is on; zero OnUpdate cost outside of drag.
--- ==========================================================================
do
    local tooltipDragHandle          --- overlay frame (lazy-created)
    local tooltipSettingsHandle      --- click-through-to-settings frame for non-draggable states
    local tooltipMiniPopup
    local tooltipEditPreviewActive = false
    local W8 = "Interface/Buttons/WHITE8X8"

    local function MSUF_Tooltip_OpenTooltipSettings()
        local menu = _G.MSUF2
        if menu and type(menu.Open) == "function" then
            menu.Open("opt_misc")
        elseif type(_G.MSUF2_Open) == "function" then
            _G.MSUF2_Open("opt_misc")
        elseif type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
            _G.MSUF_OpenStandaloneOptionsWindow("opt_misc")
        elseif type(_G.MSUF_OpenPage) == "function" then
            _G.MSUF_OpenPage("opt_misc")
        end

        local function OpenSection()
            menu = _G.MSUF2
            local search = menu and menu.Search
            if search and type(search.OpenTarget) == "function" then
                search.OpenTarget("opt_misc", "Unitframe tooltips", "Unitframe tooltips", "Unitframe tooltips")
            elseif type(_G.MSUF_OpenPage) == "function" then
                _G.MSUF_OpenPage("opt_misc")
            end
        end

        C_Timer.After(0, OpenSection)
    end

    local function MSUF_Tooltip_OpenMiscSettings()
        local menu = _G.MSUF2
        if menu and type(menu.Open) == "function" then
            menu.Open("opt_misc")
        elseif type(_G.MSUF2_Open) == "function" then
            _G.MSUF2_Open("opt_misc")
        elseif type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
            _G.MSUF_OpenStandaloneOptionsWindow("opt_misc")
        elseif type(_G.MSUF_OpenPage) == "function" then
            _G.MSUF_OpenPage("opt_misc")
        end
    end

    --- --- persistence ---
    local function MSUF_Tooltip_SavePosition(frame)
        if not frame then return end
        MSUF_Chat_RunEnsureDB()
        local g = MSUF_DB and MSUF_DB.general
        if not g then return end
        local left   = frame.GetLeft   and frame:GetLeft()
        local bottom = frame.GetBottom and frame:GetBottom()
        if type(left) == "number" and type(bottom) == "number" then
            g.tooltipPosX = math.floor(left + 0.5)
            g.tooltipPosY = math.floor(bottom + 0.5)
        end
    end

    local function MSUF_Tooltip_SetNudgeTarget(handle)
        if not handle or not _G.MSUF_EM2_SetPreviewNudgeTarget then return end
        _G.MSUF_EM2_SetPreviewNudgeTarget({
            frame = handle,
            IsActive = function()
                local p = handle:GetParent()
                return tooltipEditPreviewActive and handle:IsShown() and p and p.IsShown and p:IsShown()
            end,
            Nudge = function(_, dx, dy)
                local p = handle:GetParent()
                if not p then return end
                MSUF_Chat_RunEnsureDB()
                local g = MSUF_DB and MSUF_DB.general
                if not g then return end
                local left = tonumber(g.tooltipPosX)
                local bottom = tonumber(g.tooltipPosY)
                if left == nil then left = p:GetLeft() or 0 end
                if bottom == nil then bottom = p:GetBottom() or 0 end
                g.tooltipPosX = math.floor(left + (dx or 0) + 0.5)
                g.tooltipPosY = math.floor(bottom + (dy or 0) + 0.5)
                p:ClearAllPoints()
                p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", g.tooltipPosX, g.tooltipPosY)
            end,
        })
    end

    --- --- reset helper (called from Options / slash) ---
    local function MSUF_Tooltip_ResetPosition()
        MSUF_Chat_RunEnsureDB()
        local g = MSUF_DB and MSUF_DB.general
        if not g then return end
        g.tooltipPosX = nil
        g.tooltipPosY = nil
    end
    PublishCompat("MSUF_Tooltip_ResetPosition", MSUF_Tooltip_ResetPosition)

    local function MSUF_Tooltip_HideMiniPopup()
        if tooltipMiniPopup then tooltipMiniPopup:Hide() end
    end

    local function MSUF_Tooltip_Menu2Style()
        return _G.MSUF_EM2_Menu2Style, (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    end

    local function MSUF_Tooltip_KeepMenu2Skin(widget)
        if widget then widget._msufNoSlashSkin = true end
        return widget
    end

    local function MSUF_Tooltip_Button(parent, text, x, y, w, onClick)
        local S, UI = MSUF_Tooltip_Menu2Style()
        local function WrappedClick()
            MSUF_Tooltip_HideMiniPopup()
            if onClick then onClick() end
        end
        local b
        if S and S.Button then
            b = S.Button(parent, Tr(text), w or 190, 30, WrappedClick)
            if S.SetButtonText then S.SetButtonText(b, text) end
        elseif UI and UI.Button then
            b = UI.Button(parent, Tr(text), w or 190, 30, {
                onClick = WrappedClick,
                align = "CENTER",
                skipHistory = true,
            })
        else
            b = CreateFrame("Button", nil, parent, "BackdropTemplate")
            b:SetSize(w or 190, 30)
            b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
            b:SetBackdropColor(0.050, 0.062, 0.105, 0.88)
            b:SetBackdropBorderColor(0.10, 0.20, 0.42, 0.72)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.20, 0.40, 0.80, 0.10)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER")
            fs:SetText(Tr(text))
            fs:SetTextColor(0.86, 0.92, 1.00, 0.95)
            b._label = fs
            b:SetScript("OnClick", WrappedClick)
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 20, y)
        b:SetSize(w or 190, 30)
        if b.SetScript then b:SetScript("OnClick", WrappedClick) end
        return MSUF_Tooltip_KeepMenu2Skin(b)
    end

    local function MSUF_Tooltip_CloseButton(parent)
        local S, UI = MSUF_Tooltip_Menu2Style()
        local b
        if S and S.CloseButton then
            b = S.CloseButton(parent, MSUF_Tooltip_HideMiniPopup)
        elseif UI and UI.CloseButton then
            b = UI.CloseButton(parent, MSUF_Tooltip_HideMiniPopup)
        else
            b = CreateFrame("Button", nil, parent)
            b:SetSize(24, 24)
            local x = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            x:SetPoint("CENTER", 0, 0)
            x:SetText("x")
            x:SetTextColor(0.55, 0.62, 0.78, 0.85)
            b:SetScript("OnEnter", function() x:SetTextColor(1.00, 0.42, 0.42, 1) end)
            b:SetScript("OnLeave", function() x:SetTextColor(0.55, 0.62, 0.78, 0.85) end)
            b:SetScript("OnClick", MSUF_Tooltip_HideMiniPopup)
        end
        b:SetSize(24, 24)
        return MSUF_Tooltip_KeepMenu2Skin(b)
    end

    local function MSUF_Tooltip_ApplyPopupShell(frame)
        local S, UI = MSUF_Tooltip_Menu2Style()
        frame:SetBackdrop({
            bgFile = W8,
            edgeFile = W8,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(0.03, 0.05, 0.12, 0.96)
        frame:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.95)
        if S and S.Shell then
            S.Shell(frame)
        elseif UI and UI.ApplyMaterial then
            UI.ApplyMaterial(frame, "popup")
        end
    end

    local function MSUF_Tooltip_PopupTitle(parent, text, size, color)
        local fs = parent:CreateFontString(nil, "OVERLAY", size and "GameFontNormal" or "GameFontNormalSmall")
        size = tonumber(size) or 12
        if size <= 0 then size = 12 end
        if size < 6 then size = 6 elseif size > 128 then size = 128 end
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", size, "")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetText(Tr(text))
        local c = color or { 0.86, 0.92, 1.00, 0.95 }
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        return fs
    end

    local function MSUF_Tooltip_EnsureMiniPopup()
        if tooltipMiniPopup then return tooltipMiniPopup end

        local p = CreateFrame("Frame", "MSUF_TooltipMiniSettingsPopup", UIParent, "BackdropTemplate")
        p:SetSize(440, 176)
        p:SetFrameStrata("TOOLTIP")
        p:SetFrameLevel(940)
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:SetMovable(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", function(s)
            if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return end
            if InCombatLockdown and InCombatLockdown() then return end
            s:StartMoving()
        end)
        p:SetScript("OnDragStop", function(s)
            s:StopMovingOrSizing()
            s._msufTooltipPopupUserPlaced = true
        end)
        MSUF_Tooltip_ApplyPopupShell(p)

        local title = MSUF_Tooltip_PopupTitle(p, "Tooltip - Frame", 15, { 0.86, 0.92, 1.00, 0.95 })
        title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)

        local subtitle = MSUF_Tooltip_PopupTitle(p, "Tooltip bounds", 12, { 0.55, 0.62, 0.78, 0.70 })
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

        local close = MSUF_Tooltip_CloseButton(p)
        close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -10)

        MSUF_Tooltip_Button(p, "Tooltip settings", 20, -72, 190, MSUF_Tooltip_OpenTooltipSettings)
        MSUF_Tooltip_Button(p, "Miscellaneous", 224, -72, 190, MSUF_Tooltip_OpenMiscSettings)
        MSUF_Tooltip_Button(p, "Reset position", 20, -120, 394, function()
            MSUF_Tooltip_ResetPosition()
            if _G.MSUF_Tooltip_ShowEditPreview then _G.MSUF_Tooltip_ShowEditPreview() end
        end)
        if _G.MSUF_EM2 and _G.MSUF_EM2.AttachPopupScaleGrip then _G.MSUF_EM2.AttachPopupScaleGrip(p) end

        p:Hide()
        tooltipMiniPopup = p
        return p
    end

    local function MSUF_Tooltip_ShowMiniPopup(anchor)
        local p = MSUF_Tooltip_EnsureMiniPopup()
        if p:IsShown() then
            p:Hide()
            return
        end
        if p._msufTooltipPopupUserPlaced then
            p:Show()
            return
        end
        p:ClearAllPoints()
        if anchor and anchor.GetRight and anchor:GetRight() then
            local anchorRight = anchor:GetRight()
            local screenRight = UIParent and UIParent.GetRight and UIParent:GetRight()
            local popupW = p:GetWidth() or 440
            if anchorRight and screenRight and anchorRight + popupW + 12 > screenRight then
                p:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
            else
                p:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
            end
        else
            p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        p:Show()
    end

    --- --- drag handle (lazy) ---
    local function MSUF_Tooltip_EnsureDragHandle(parent)
        if tooltipDragHandle then
            --- Re-parent in case tooltip was re-created (shouldn't happen, but safe).
            if tooltipDragHandle:GetParent() ~= parent then
                tooltipDragHandle:SetParent(parent)
            end
            tooltipDragHandle:SetAllPoints(parent)
            return tooltipDragHandle
        end

        local dh = CreateFrame("Frame", "MSUF_TooltipDragHandle", parent)
        dh:SetAllPoints(parent)
        dh:EnableMouse(true)
        dh:RegisterForDrag("LeftButton")
        dh:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 10)

        --- Subtle visual overlay so the user knows it's draggable
        local bg = dh:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.6, 1.0, 0.12)
        dh._bg = bg

        local label = dh:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", dh, "TOP", 0, -2)
        label:SetText(Tr("Drag or arrow keys to reposition"))
        label:SetTextColor(0.4, 0.8, 1.0, 0.9)
        dh._label = label

        dh:SetScript("OnDragStart", function(self)
            if InCombatLockdown and InCombatLockdown() then return end
            self._msufTooltipSuppressClick = true
            MSUF_Tooltip_HideMiniPopup()
            MSUF_Tooltip_SetNudgeTarget(self)
            local p = self:GetParent()
            if p then
                p:SetMovable(true)
                p:SetClampedToScreen(true)
                p:StartMoving()
            end
        end)

        dh:SetScript("OnDragStop", function(self)
            local p = self:GetParent()
            if not p then return end
            p:StopMovingOrSizing()
            p:SetMovable(false)
            MSUF_Tooltip_SavePosition(p)
            C_Timer.After(0.05, function()
                if self then self._msufTooltipSuppressClick = nil end
            end)
        end)

        dh:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                MSUF_Tooltip_SetNudgeTarget(self)
            end
        end)

        dh:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or self._msufTooltipSuppressClick then return end
            MSUF_Tooltip_ShowMiniPopup(self)
        end)

        dh:Hide()
        tooltipDragHandle = dh
        return dh
    end

    local function MSUF_Tooltip_EnsureSettingsHandle(parent)
        if tooltipSettingsHandle then
            if tooltipSettingsHandle:GetParent() ~= parent then
                tooltipSettingsHandle:SetParent(parent)
            end
            tooltipSettingsHandle:SetAllPoints(parent)
            return tooltipSettingsHandle
        end

        local h = CreateFrame("Button", "MSUF_TooltipSettingsHandle", parent)
        h:SetAllPoints(parent)
        h:EnableMouse(true)
        h:RegisterForClicks("LeftButtonUp")
        h:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 10)

        local hover = h:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.2, 0.6, 1.0, 0.08)
        h._hover = hover

        h:SetScript("OnClick", function(self)
            MSUF_Tooltip_ShowMiniPopup(self)
        end)
        tooltipSettingsHandle = h
        return h
    end

    --- --- Edit Mode enter/exit ---
    local function MSUF_Tooltip_ShowEditPreview()
        local f = MSUF_GetPlayerInfoFrame()
        if not f then return end

        local g = MSUF_GetTooltipGeneral()
        local provider, anchor = MSUF_NormalizeTooltipSettings(g)
        local blizzardControlled = (provider == TOOLTIP_PROVIDER_GAME and anchor == TOOLTIP_ANCHOR_EXTERNAL)

        if blizzardControlled then
            if tooltipDragHandle then
                tooltipDragHandle:Hide()
            end
            tooltipEditPreviewActive = false
            f:SetMovable(false)

            if f.name  then f.name:SetText(Tr("GameTooltip (addon-compatible)")) end
            if f.line2 then f.line2:SetText(Tr("Addon / Blizzard controlled")) end
            if f.line3 then f.line3:SetText(Tr("Player Name")) end
            if f.line4 then f.line4:SetText(Tr("Level 80 Human Paladin")) end
            if f.line5 then f.line5:SetText("") end

            f:ClearAllPoints()
            f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 16)
            f:Show()
            f._msufEditPreviewActive = true
            MSUF_Tooltip_EnsureSettingsHandle(f):Show()
            return
        end

        if tooltipSettingsHandle then
            tooltipSettingsHandle:Hide()
        end

        --- Fill with placeholder content so the user sees size/layout
        if f.name  then f.name:SetText(Tr("Player Name")) end
        if f.line2 then f.line2:SetText(Tr("Level 80 Human Paladin")) end
        if f.line3 then f.line3:SetText(Tr("Protection Paladin")) end
        if f.line4 then f.line4:SetText(Tr("Alliance")) end
        if f.line5 then f.line5:SetText(Tr("Stormwind City")) end

        --- Position (uses saved pos if available, else style default)
        MSUF_PositionPlayerInfoFrame(f)
        f:Show()

        --- Mark frame as in edit-preview so MSUF_HidePlayerInfoTooltip
        --- restores the preview instead of hiding it.
        f._msufEditPreviewActive = true

        --- Enable drag
        local dh = MSUF_Tooltip_EnsureDragHandle(f)
        dh:Show()
        tooltipEditPreviewActive = true
    end

    local function MSUF_Tooltip_HideEditPreview()
        MSUF_Tooltip_HideMiniPopup()
        if tooltipDragHandle then
            tooltipDragHandle:Hide()
        end
        if tooltipSettingsHandle then
            tooltipSettingsHandle:Hide()
        end
        tooltipEditPreviewActive = false
        --- Hide the tooltip preview (but not if a real tooltip is being shown outside edit mode).
        --- The preview uses placeholder text, so we can safely hide it.
        if MSUF_PlayerInfoFrame then
            MSUF_PlayerInfoFrame._msufEditPreviewActive = false
            MSUF_PlayerInfoFrame:SetMovable(false)
            MSUF_PlayerInfoFrame:Hide()
        end
    end

    --- Expose for CloseAllPositionPopups and external callers
    PublishCompat("MSUF_Tooltip_HideEditPreview", MSUF_Tooltip_HideEditPreview)
    PublishCompat("MSUF_Tooltip_ShowEditPreview", MSUF_Tooltip_ShowEditPreview)

    --- Register as AnyEditMode listener (fires on MSUF and/or Blizzard Edit Mode transitions).
    if _G.MSUF_RegisterAnyEditModeListener then
        _G.MSUF_RegisterAnyEditModeListener(function(active)
            if active then
                MSUF_Tooltip_ShowEditPreview()
            else
                MSUF_Tooltip_HideEditPreview()
            end
        end)
    end
end

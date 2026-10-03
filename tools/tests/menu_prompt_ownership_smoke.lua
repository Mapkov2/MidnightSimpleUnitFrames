-- menu_prompt_ownership_smoke.lua <repoRoot>
--
-- Neither the core nor the Options addon writes Blizzard's StaticPopupDialogs
-- (re-review CX-RVC #2, R7 P2, R5 P1). M.InstallStaticPopup wrote it for 18
-- menu prompts in 11 files and GroupPriority wrote it directly; the core wrote
-- it for the cooldown-anchor consent (shown by itself at login when a layout
-- addon is detected), the missing-anchor warning, the client-version warning
-- and the gameplay colours tip. Every prompt now goes through the one core
-- prompt layer (Shell/UI/MSUF_Widgets.lua, MSUF.UI.ShowPrompt; the menu's
-- M.ShowPrompt passes its look): Blizzard's generic confirmation or
-- text-input dialog, or an MSUF-owned frame when the prompt has one button,
-- Escape must not answer it, or its answer is stored.
--   1. Source: no core or Options Lua file writes StaticPopupDialogs (an index
--      or field assignment, rawset, StaticPopup_AddDefinition or SetButtonText)
--      except the M.InstallStaticPopup host export kept for the MSUF Suite, and
--      no core or Options file calls that export.
--   2. Behaviour on the real Mainline graph (tools/tests/static_popup_stub.lua
--      models Blizzard's StaticPopup system and records every write):
--      * the page reset asks one question per key however often it is shown,
--        with the page warning and Yes / No, and Yes resets that page;
--      * the reload prompt formats its label in, Escape runs its cancel and
--        reloads nothing, Reload reloads;
--      * the language prompt translates when it is shown, not when it was
--        first installed, and the language selection hides it again;
--      * the group-frame reload prompt keeps Reload / Not now, and Escape
--        neither closes nor answers it; Reload in combat lockdown refuses;
--      * the Class Resources quick-setup result keeps Okay / Undo, Escape does
--        not undo, and Undo restores the settings it changed;
--      * a text prompt opens Blizzard's input box with its letter limit, keeps
--        Add disabled while empty and passes the text on;
--      * the core prompts: the cooldown-anchor consent is two owned steps
--        (Continue / Keep independent, Confirm anchoring / Cancel) whose
--        buttons and Escape store the answer; the missing-anchor warning is
--        Blizzard's generic confirmation (Fix now / Cancel); the client-version
--        warning and the gameplay colours tip are one Okay button that Escape
--        closes; nothing times out;
--      * none of it writes StaticPopupDialogs.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local OPTIONS = "MidnightSimpleUnitFrames_Options"
local CORE = "MidnightSimpleUnitFrames"

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end
local function Fatal(condition, message)
    if not condition then error("menu_prompt_ownership_smoke: " .. message, 2) end
    return condition
end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- Blank strings and comments (line breaks stay), so only code is matched.
local function Blank(source)
    local out, i, n = {}, 1, #source
    local function Mask(text) out[#out + 1] = (text:gsub("[^\n]", " ")) end
    while i <= n do
        local c = source:sub(i, i)
        local long = source:match("^%[(=*)%[", i)
        if source:sub(i, i + 1) == "--" then
            local level = source:match("^%-%-%[(=*)%[", i)
            local stop
            if level then
                local _, close = source:find("]" .. level .. "]", i, true)
                stop = close or n
            else
                stop = (source:find("\n", i, true) or (n + 1)) - 1
            end
            Mask(source:sub(i, stop))
            i = stop + 1
        elseif long then
            local _, close = source:find("]" .. long .. "]", i, true)
            close = close or n
            Mask(source:sub(i, close))
            i = close + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = source:sub(j, j)
                if d == "\\" then j = j + 2 elseif d == c or d == "\n" then break else j = j + 1 end
            end
            out[#out + 1] = c
            Mask(source:sub(i + 1, j - 1))
            out[#out + 1] = c
            i = j + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- 1. Source
---------------------------------------------------------------------------
local WRITES = {
    "StaticPopupDialogs%s*%b[]%s*=[^=]",
    "StaticPopupDialogs%s*%.%s*[%a_][%w_]*%s*=[^=]",
    "rawset%s*%(%s*[%w_%.]*StaticPopupDialogs",
    "StaticPopup_AddDefinition%s*%(",
    "StaticPopup_SetButtonText%s*%(",
    "StaticPopupDialogs%s*=[^=]",
    -- The whole table in a local, which then takes the writes.
    "[%w_]%s*=%s*[%w_%.]*StaticPopupDialogs%s*\n",
}
local EXPORT = OPTIONS .. "/Shell/Menu2/MSUF_Menu2_Support.lua"
local files, coreFiles = {}, 0
for _, addon in ipairs({ OPTIONS, CORE }) do
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. addon .. '/*.lua"'))
    for line in pipe:lines() do
        files[#files + 1] = line
        if addon == CORE then coreFiles = coreFiles + 1 end
    end
    pipe:close()
end
Fatal(#files - coreFiles > 100 and coreFiles > 200, "the addons list only " .. #files .. " Lua files")
local exportFound = false
for _, path in ipairs(files) do
    local code = Blank(Read(path))
    -- The host export's body, the one place a write is allowed.
    local exportFirst, exportLast
    if path == EXPORT then
        exportFirst = code:find("\nfunction M%.InstallStaticPopup%(")
        exportLast = exportFirst and code:find("\nend\n", exportFirst, true)
        exportFound = exportLast ~= nil
    end
    local lineStarts = { 1 }
    for pos in code:gmatch("()\n") do lineStarts[#lineStarts + 1] = pos + 1 end
    local function LineOf(pos)
        local line = 1
        while lineStarts[line + 1] and lineStarts[line + 1] <= pos do line = line + 1 end
        return line
    end
    for _, pattern in ipairs(WRITES) do
        local from = 1
        while true do
            local s, e = code:find(pattern, from)
            if not s then break end
            local allowed = exportFirst and s > exportFirst and s < exportLast
            Check(allowed, path .. ":" .. LineOf(s) .. ": writes StaticPopupDialogs (" .. pattern .. ")")
            from = e + 1
        end
    end
    local from = 1
    while true do
        local s, e = code:find("InstallStaticPopup%s*%(", from)
        if not s then break end
        local definition = exportFirst and s == exportFirst + #"\nfunction M."
        Check(definition, path .. ":" .. LineOf(s) .. ": calls M.InstallStaticPopup; menu prompts use M.ShowPrompt")
        from = e + 1
    end
end
Check(exportFound, "the M.InstallStaticPopup host export is gone from Support.lua; the Suite still calls it")

---------------------------------------------------------------------------
-- 2. Behaviour
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline", { locale = "enUS" })
local widgetMethods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "Normal", "Highlight", "Pushed", "Disabled", "Checked" }) do
    widgetMethods["Set" .. name .. "Texture"] = function(self, path)
        local texture = self["fixture" .. name] or self:CreateTexture()
        texture:SetTexture(path)
        self["fixture" .. name] = texture
    end
    widgetMethods["Get" .. name .. "Texture"] = function(self) return self["fixture" .. name] end
end
for _, name in ipairs({ "SetNumeric", "SetTextInsets", "SetMaxLetters", "ClearFocus", "SetCursorPosition", "HighlightText" }) do
    widgetMethods[name] = function(self, ...) self["fixture" .. name] = { ... } end
end
widgetMethods.EnableKeyboard = function(self, on) self.keyboard = on and true or false end
widgetMethods.SetPropagateKeyboardInput = function(self, on) self.propagate = on and true or false end
widgetMethods.HasFocus = function() return false end
widgetMethods.SetFocus = function(self) self.fixtureFocused = true end
widgetMethods.SetAutoFocus = function(self, value) self.autoFocus = value end
widgetMethods.SetValueStep = function(self, value) self.valueStep = value end
widgetMethods.SetObeyStepOnDrag = function(self, value) self.obeyStep = value end
widgetMethods.SetScrollChild = function(self, child) self.scrollChild = child end
widgetMethods.GetScrollChild = function(self) return self.scrollChild end
widgetMethods.SetVerticalScroll = function(self, value) self.verticalScroll = value end
widgetMethods.GetVerticalScroll = function(self) return self.verticalScroll or 0 end
widgetMethods.GetVerticalScrollRange = function() return 0 end
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
local popups = assert(loadfile(root .. "/tools/tests/static_popup_stub.lua"))().Install(world.env)
world:Boot()
local failure = world:FirstFailure()
Fatal(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, n = world.env, world.core
local M = Fatal(n.MSUF2, "Menu2 did not load")
e.MSUF_EnsureDB(true)
M.ApplyService.Flush = function() return true end
-- The unit-frame engine is not what this smoke models.
e.MSUF_UFCore_NotifyConfigChanged = function() return true end
local reloads = 0
e.ReloadUI = function() reloads = reloads + 1 end
local printed = {}
e.print = function(text) printed[#printed + 1] = tostring(text) end
local writesAtBoot = #popups.writes

local function One(key)
    local list = popups.ForKey(key)
    return #list == 1 and list[1] or nil, #list
end

-- Page reset: one question per key, the page warning, Yes resets that page.
do
    local reset, resetCalls = M.ResetPageToDefaults, {}
    M.ResetPageToDefaults = function(key) resetCalls[#resetCalls + 1] = key return true end
    Check(M.ShowPageResetConfirm("opt_bars") == true and M.ShowPageResetConfirm("opt_bars") == true,
        "the page reset prompt did not show")
    local dialog, count = One("MSUF2_PAGE_RESET_CONFIRM")
    if Check(dialog, "the page reset asked " .. count .. " questions, not one") then
        Check(dialog.which == "GENERIC_CONFIRMATION", "the page reset is not Blizzard's generic confirmation")
        Check(dialog.text == M.BuildPageResetWarning("opt_bars"), "the page reset shows " .. tostring(dialog.text))
        Check(dialog.button1:GetText() == e.YES and dialog.button2:GetText() == e.NO, "the page reset lost Yes / No")
        popups.Click(dialog, 1)
        Check(#resetCalls == 1 and resetCalls[1] == "opt_bars", "Yes did not reset the Bars page")
    end
    M.ResetPageToDefaults = reset
end

-- Reload recommended: label formatted in, Escape cancels, Reload reloads.
do
    e.MSUF_ShowReloadRecommendedPopup("Smoke label")
    local dialog = One("MSUF_RELOAD_RECOMMENDED")
    if Check(dialog, "the reload prompt did not show") then
        Check(dialog.text and dialog.text:find("Apply: Smoke label", 1, true), "the reload prompt lost its label: " .. tostring(dialog.text))
        Check(popups.Escape() and not dialog:IsShown() and reloads == 0, "Escape did not cancel the reload prompt, or reloaded")
    end
    e.MSUF_ShowReloadRecommendedPopup("Smoke label")
    dialog = One("MSUF_RELOAD_RECOMMENDED")
    if Check(dialog, "the reload prompt did not show again") then
        popups.Click(dialog, 1)
        Check(reloads == 1, "Reload on the reload prompt did not reload")
    end
    reloads = 0
end

-- Language: translated when shown; the language selection hides it.
do
    local KEY = "Menu language was changed. MSUF loads only one language per session, so a UI reload is required to apply it.\n\nReload now?"
    M.ShowLocaleReloadRequired()
    local before = One("MSUF2_LOCALE_RELOAD_REQUIRED")
    Check(before and before.text == KEY, "the language prompt shows " .. tostring(before and before.text))
    rawset(n.L, KEY, "Translated after the first show.")
    M.ShowLocaleReloadRequired()
    local after, count = One("MSUF2_LOCALE_RELOAD_REQUIRED")
    Check(after and after.text == "Translated after the first show.",
        "the language prompt kept the text of its first show (" .. tostring(after and after.text) .. ", " .. count .. " shown)")
    rawset(n.L, KEY, nil)
    M.ApplyLocaleSelection(n.LOCALE)
    Check(#popups.ForKey("MSUF2_LOCALE_RELOAD_REQUIRED") == 0, "keeping the language did not hide the language prompt")
end

-- Owned prompts: the group-frame reload and the quick-setup result.
local function OwnedButtons(frame)
    local buttons = frame and frame._msufPromptButtons
    return buttons and buttons[1], buttons and buttons[2]
end
do
    local frame = e.MSUF_ShowGroupFrameReloadRequiredPopup()
    local accept, cancel = OwnedButtons(frame)
    if Check(frame and frame:IsShown() and accept, "the group-frame reload prompt did not show") then
        Check(accept:GetText() == e.RELOAD or accept:GetText() == "Reload", "the group-frame prompt lost Reload: " .. tostring(accept:GetText()))
        Check(cancel:IsShown() and cancel:GetText() == e.CANCEL, "the group-frame prompt lost Not now")
        Check(frame.keyboard ~= true, "the group-frame prompt takes the keyboard, so Escape would answer it")
        popups.Escape()
        Check(frame:IsShown(), "Escape closed the group-frame reload prompt")
        world.widgets:SetCombat(true)
        accept:GetScript("OnClick")(accept)
        world.widgets:SetCombat(false)
        Check(reloads == 0 and #printed >= 1, "Reload during combat lockdown reloaded or said nothing")
        e.MSUF_ShowGroupFrameReloadRequiredPopup()
        accept:GetScript("OnClick")(accept)
        Check(reloads == 1 and not frame:IsShown(), "Reload on the group-frame prompt did not reload")
    end
    reloads = 0
end
do
    local quick = e.MSUF2_ClassPowerQuickSetup
    if Check(type(quick) == "function", "the Class Resources quick setup is not published") then
        local function Bars() return M.EnsureDB().bars end
        Bars().showClassPower = false
        quick()
        Check(Bars().showClassPower == true, "the quick setup did not turn Class Resources on")
        world.widgets:RunTimers()
        local frame
        for _, candidate in ipairs(world.widgets.frames) do
            if candidate._msufPromptSpec and candidate:IsShown() and candidate._msufPromptSpec.cancel == M.Tr("Undo") then frame = candidate end
        end
        local accept, cancel = OwnedButtons(frame)
        if Check(frame and accept, "the quick-setup result prompt did not show") then
            Check(accept:GetText() == e.OKAY and cancel:GetText() == M.Tr("Undo") and cancel:IsShown(),
                "the quick-setup result lost Okay / Undo")
            Check(frame._msufPromptText:GetText():find("Quick Setup applied!", 1, true), "the quick-setup result lost its text")
            Check(frame.keyboard ~= true, "the quick-setup result takes the keyboard, so Escape would undo it")
            popups.Escape()
            Check(frame:IsShown() and Bars().showClassPower == true, "Escape answered the quick-setup result")
            cancel:GetScript("OnClick")(cancel)
            Check(not frame:IsShown() and Bars().showClassPower == false,
                "Undo did not restore the settings the quick setup changed")
        end
    end
end

-- A text prompt: Blizzard's input box with its letter limit.
if Check(type(M.ShowPrompt) == "function", "Support.lua publishes no M.ShowPrompt") then
    local got
    M.ShowPrompt("MSUF2_SMOKE_INPUT", { text = "Type", accept = "Add", cancel = "Cancel", input = { maxLetters = 255 },
        onAccept = function(text) got = text end })
    local dialog = One("MSUF2_SMOKE_INPUT")
    if Check(dialog and dialog.which == "GENERIC_INPUT_BOX", "a text prompt is not Blizzard's input box") then
        Check(dialog.editBox.maxLetters == 255, "the input box lost its letter limit")
        Check(popups.Click(dialog, 1) == false and got == nil, "Add answered an empty input box")
        dialog.editBox:SetText("12345")
        popups.Click(dialog, 1)
        Check(got == "12345", "the input box did not pass its text on")
    end
end

-- The core prompts.
do
    -- The client-version warning: one Okay button, Escape closes it.
    local frame = e.MSUF_ShowClientVersionWarning()
    Check(frame == true and n.UI.IsPromptShown("MSUF_CLIENT_VERSION_WARNING"), "the client-version warning did not show")
    local warning
    for _, candidate in ipairs(world.widgets.frames) do
        if candidate._msufPromptSpec and candidate:IsShown()
            and candidate._msufPromptSpec.text == n.ClientVersionWarning.GetPopupText() then warning = candidate end
    end
    local accept, cancel = OwnedButtons(warning)
    if Check(warning and accept, "the client-version warning is not an MSUF-owned prompt") then
        Check(accept:GetText() == e.OKAY and not cancel:IsShown(), "the client-version warning lost its one Okay button")
        Check(warning.keyboard == true, "Escape does not close the client-version warning")
        warning:GetScript("OnKeyDown")(warning, "ESCAPE")
        Check(not warning:IsShown() and not n.UI.IsPromptShown("MSUF_CLIENT_VERSION_WARNING"),
            "Escape did not close the client-version warning")
    end
    -- The gameplay colours tip: once per profile, one Okay button.
    local gameplay = e.MSUF_DB.gameplay
    gameplay.shownGameplayColorsTip = false
    n.MSUF_MaybeShowGameplayColorsTip()
    Check(n.UI.IsPromptShown("MSUF_GAMEPLAY_COLORS_TIP") and e.MSUF_DB.gameplay.shownGameplayColorsTip == true,
        "the gameplay colours tip did not show, or did not remember it")
    n.UI.HidePrompt("MSUF_GAMEPLAY_COLORS_TIP")
    n.MSUF_MaybeShowGameplayColorsTip()
    Check(not n.UI.IsPromptShown("MSUF_GAMEPLAY_COLORS_TIP"), "the gameplay colours tip showed twice")
end
do
    -- The cooldown-anchor consent: a detected layout addon asks at login.
    -- The file keeps the C_AddOns table it loaded with; its loaded check is
    -- read on every call.
    local loaded = { Coolinator = true }
    local isLoaded = e.C_AddOns.IsAddOnLoaded
    e.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end
    e.MSUF_DB.general.anchorToCooldown = false
    e.MSUF_GlobalDB.global = e.MSUF_GlobalDB.global or {}
    local watcher
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.scripts and frame.scripts.OnEvent
        if handler and frame.events and frame.events.ADDON_LOADED and frame.events.PLAYER_LOGIN
            and debug.getinfo(handler, "S").source:find("MSUF_Integration_ThirdPartyAnchors.lua", 1, true) then
            watcher = frame
        end
    end
    local function Consent(answers)
        e.MSUF_GlobalDB.global.cooldownAnchorProviderDecisions = nil
        e.MSUF_DB.general.anchorToCooldown = false
        loaded.Coolinator = nil
        watcher.scripts.OnEvent(watcher, "ADDON_LOADED", "Coolinator")
        loaded.Coolinator = true
        watcher.scripts.OnEvent(watcher, "ADDON_LOADED", "Coolinator")
        for step, answer in ipairs(answers) do
            local key = step == 1 and "MSUF_COOLDOWN_ANCHOR_CONSENT" or "MSUF_COOLDOWN_ANCHOR_CONFIRM"
            local frame
            for _, candidate in ipairs(world.widgets.frames) do
                if candidate._msufPromptSpec and candidate:IsShown() then frame = candidate end
            end
            local accept, cancel = OwnedButtons(frame)
            if not Check(frame and n.UI.IsPromptShown(key), "consent step " .. step .. " is not an MSUF-owned prompt") then return end
            local labels = step == 1 and { "Continue", "Keep independent" } or { "Confirm anchoring", e.CANCEL }
            Check(accept:GetText() == labels[1] and cancel:GetText() == labels[2] and cancel:IsShown(),
                "consent step " .. step .. " lost " .. labels[1] .. " / " .. labels[2])
            Check(frame._msufPromptText:GetText():find("Coolinator", 1, true), "consent step " .. step .. " lost its text")
            Check(frame.keyboard == true, "Escape does not answer consent step " .. step)
            if answer == "escape" then
                frame:GetScript("OnKeyDown")(frame, "ESCAPE")
            else
                local button = answer == "accept" and accept or cancel
                button:GetScript("OnClick")(button)
            end
            Check(not frame:IsShown(), "answering consent step " .. step .. " left it open")
        end
        return n.GetCooldownAnchorConsentDecision("Coolinator"), e.MSUF_DB.general.anchorToCooldown
    end
    if Check(watcher, "the third-party anchor watcher is missing") then
        local decision, anchored = Consent({ "accept", "accept" })
        Check(decision == "accepted" and anchored == true, "accepting both consent steps did not anchor the layout")
        decision, anchored = Consent({ "cancel" })
        Check(decision == "declined" and anchored == false, "Keep independent did not store the refusal")
        decision, anchored = Consent({ "escape" })
        Check(decision == "declined" and anchored == false, "Escape on the first step did not store the refusal")
        decision, anchored = Consent({ "accept", "escape" })
        Check(decision == "declined" and anchored == false, "Escape on the second step did not store the refusal")
    end
    e.C_AddOns.IsAddOnLoaded = isLoaded
end

Check(#popups.writes == writesAtBoot, "the prompts wrote StaticPopupDialogs: " .. table.concat(popups.writes, ",", writesAtBoot + 1))
Check(writesAtBoot == 0, "booting the menu wrote StaticPopupDialogs: " .. table.concat(popups.writes, ","))

if #failures > 0 then
    error("menu_prompt_ownership_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_prompt_ownership_smoke: ok (" .. #files .. " core and Options files write no StaticPopupDialogs; page reset,"
    .. " reload, language, group-frame, quick-setup, text, consent, version and tip prompts keep their buttons,"
    .. " texts and Escape rules)")

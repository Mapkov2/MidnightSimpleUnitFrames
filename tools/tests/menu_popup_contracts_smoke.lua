-- menu_popup_contracts_smoke.lua <repoRoot>
--
-- Contracts of the "Fix now" jump and of the prompts the menu raises (review
-- 2026-09-30, F5, F8 and F21; Blizzard_StaticPopup/StaticPopup.lua on live,
-- forever, classic_era, classic_anniversary and classic):
--   * "Fix now" on the missing cooldown-anchor warning (the core prompt
--     layer, Blizzard's generic confirmation) opens the setting and closes the
--     dialog, and the warning writes nothing to StaticPopupDialogs;
--   * the jump applies its route and builds the target page once, whether the
--     menu window is open on another page or hidden;
--   * StaticPopup_Show always puts the dialog on DIALOG strata, the menu's
--     normal strata. In MSUF Edit Mode the menu sits on FULLSCREEN_DIALOG, so
--     every prompt the menu shows (M.ShowPrompt: Blizzard's generic dialog or
--     a menu-owned frame) lifts itself to the window's strata.
--
-- Boots the real Mainline core and Options graph and opens the real menu.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_popup_contracts_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Mainline")
-- Widget surface the real page builders use and the shared stubs leave out.
local widgetMethods = getmetatable(world.env.UIParent).__index
for _, name in ipairs({ "Normal", "Highlight", "Pushed", "Disabled", "Checked" }) do
    widgetMethods["Set" .. name .. "Texture"] = function(self, path)
        local texture = self["fixture" .. name] or self:CreateTexture()
        texture:SetTexture(path)
        self["fixture" .. name] = texture
    end
    widgetMethods["Get" .. name .. "Texture"] = function(self) return self["fixture" .. name] end
end
for _, name in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetNumeric", "SetTextInsets", "SetMaxLetters",
    "ClearFocus", "SetCursorPosition", "HighlightText" }) do
    widgetMethods[name] = function(self, ...) self["fixture" .. name] = { ... } end
end
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
local nativeCreate = world.env.CreateFrame
world.env.CreateFrame = function(kind, ...)
    local frame = nativeCreate(kind, ...)
    if kind == "Slider" then frame:SetValue(0)
    elseif kind == "CheckButton" then
        frame.SetChecked = function(self, value) self.checked = value end
        frame.GetChecked = function(self) return self.checked end
    end
    return frame
end
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
-- Blizzard's StaticPopup system, generic dialogs included (static_popup_stub.lua).
local popups = assert(loadfile(root .. "/tools/tests/static_popup_stub.lua"))().Install(world.env)
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, n = world.env, world.core
local M = Check(n.MSUF2, "Menu2 did not load")
M.ApplyService.Flush = function() return true end

local function Generic(key)
    local list = popups.ForKey(key)
    return #list == 1 and list[1] or nil
end

---------------------------------------------------------------------------
-- 1. "Fix now" closes the missing cooldown-anchor warning
---------------------------------------------------------------------------
e.MSUF_EnsureDB(true)
e.MSUF_DB.general.anchorToCooldown = true
local watcher
for _, frame in ipairs(world.widgets.frames) do
    local handler = frame.scripts and frame.scripts.OnEvent
    if handler and frame.events and frame.events.PLAYER_LOGIN
        and debug.getinfo(handler, "S").source:find("MSUF_Integration_ThirdPartyAnchors.lua", 1, true) then
        watcher = frame
    end
end
Check(watcher, "the third-party anchor login watcher is missing")
world.widgets:ClearTimers()
watcher.scripts.OnEvent(watcher, "PLAYER_LOGIN")
world.widgets:RunTimers(10)
local warning = Check(Generic("MSUF_COOLDOWN_ANCHOR_MISSING"), "the missing cooldown-anchor warning was not shown")
Check(warning.which == "GENERIC_CONFIRMATION", "the missing cooldown-anchor warning is not Blizzard's generic confirmation")
Check(warning.text and warning.text:find("No cooldown anchor found.", 1, true), "the warning lost its text")
Check(warning.button1:GetText():find("Fix now", 1, true) and warning.button2:GetText() == e.CANCEL,
    "the warning lost Fix now / Cancel")
local openExact = Check(e.MSUF_OpenExactSettingControl, "the exact setting jump is not published")
local opened = 0
e.MSUF_OpenExactSettingControl = function(settingKey, _, pageKey)
    Check(settingKey == "general.anchorToCooldown" and pageKey == "uf_player", "Fix now opened the wrong setting")
    opened = opened + 1
    return true
end
popups.Click(warning, 1)
Check(opened == 1, "Fix now did not open the cooldown-anchor setting")
Check(Generic("MSUF_COOLDOWN_ANCHOR_MISSING") == nil, "Fix now left the warning open")
e.MSUF_OpenExactSettingControl = openExact

---------------------------------------------------------------------------
-- 2. The jump applies its route and builds the target page once
---------------------------------------------------------------------------
local playerPage = Check(M.pages.uf_player, "the Player page is not registered")
local build, builds = playerPage.build, 0
playerPage.build = function(...) builds = builds + 1; return build(...) end
local applyRoute, bridgeApplies = M.Search.ApplyRoute, 0
M.Search.ApplyRoute = function(...) bridgeApplies = bridgeApplies + 1; return applyRoute(...) end
local function Jump(state)
    builds, bridgeApplies = 0, 0
    local focused = openExact("general.anchorToCooldown", "Follow Blizzard's Essential Cooldowns", "uf_player")
    Check(focused and M.activeKey == "uf_player", "the jump did not focus its setting (" .. state .. ")")
    Check(builds == 1, "the jump built the Player page " .. builds .. " times (" .. state .. ")")
    Check(bridgeApplies == 0, "the jump applied its route a second time before opening (" .. state .. ")")
end
Check(M.Open("home") ~= false and M.frame:IsShown(), "the menu did not open")
world.widgets:RunTimers(20)
Jump("window open on another page")
M.SelectPage("home")
M.InvalidatePage("uf_player")
M.frame:Hide()
Jump("window hidden")
M.Search.ApplyRoute = applyRoute
playerPage.build = build

---------------------------------------------------------------------------
-- 3. Menu prompts open above the menu window in MSUF Edit Mode
---------------------------------------------------------------------------
local editMode = false
M.IsMSUFEditModeActive = function() return editMode end
Check(M.frame:IsShown(), "the menu window is not shown")
local function ShowSmoke() return M.ShowPrompt("MSUF2_SMOKE_STRATA", { text = "smoke" }) end
M.ApplyMenuFramePriority(M.frame)
Check(M.frame:GetFrameStrata() == "DIALOG", "the menu window is not on DIALOG outside Edit Mode")
Check(ShowSmoke():GetFrameStrata() == "DIALOG", "a prompt outside Edit Mode left DIALOG")
editMode = true
M.ApplyMenuFramePriority(M.frame)
local windowStrata = M.frame:GetFrameStrata()
Check(windowStrata == M.MENU_EDIT_FRAME_STRATA and windowStrata ~= "DIALOG", "Edit Mode did not raise the menu window")
Check(ShowSmoke():GetFrameStrata() == windowStrata, "a prompt in Edit Mode opened behind the menu window")
-- The real prompts: page reset and the reload prompt (Blizzard's generic
-- dialog), and the group-frame reload prompt (menu-owned).
Check(M.ShowPageResetConfirm("opt_bars"), "the page reset prompt did not show")
local reset = Check(Generic("MSUF2_PAGE_RESET_CONFIRM"), "the page reset prompt is not one generic dialog")
Check(reset:GetFrameStrata() == windowStrata, "the page reset prompt opened behind the menu window in Edit Mode")
e.MSUF_ShowReloadRecommendedPopup("Smoke")
local reload = Check(Generic("MSUF_RELOAD_RECOMMENDED"), "the reload prompt is not one generic dialog")
Check(reload:GetFrameStrata() == windowStrata, "the reload prompt opened behind the menu window in Edit Mode")
local owned = e.MSUF_ShowGroupFrameReloadRequiredPopup()
Check(owned and owned:IsShown() and owned:GetFrameStrata() == windowStrata
    and (owned:GetFrameLevel() or 0) > (M.frame:GetFrameLevel() or 0),
    "the group-frame reload prompt opened behind the menu window in Edit Mode")
owned:Hide()
M.frame:Hide()
Check(ShowSmoke():GetFrameStrata() == "DIALOG", "a prompt was lifted although the menu window is hidden")
Check(#popups.writes == 0, "a prompt wrote StaticPopupDialogs: " .. table.concat(popups.writes, ","))

---------------------------------------------------------------------------
-- 4. One copy-link popup serves every link (F11)
---------------------------------------------------------------------------
local showCopy = Check(e.MSUF_ShowCopyLink, "MSUF_ShowCopyLink is not published")
local function CopyPopups()
    local list = {}
    for _, frame in ipairs(world.widgets.frames) do
        if type(frame.frameName) == "string" and frame.frameName:find("^MSUF_CopyLinkPopup") then list[#list + 1] = frame end
    end
    return list
end
showCopy("Discord", "https://example.invalid/one")
local framesAfterFirst = #world.widgets.frames
local popups = CopyPopups()
Check(#popups == 1 and popups[1]:IsShown(), "the first link did not open one copy-link popup")
local popup = popups[1]
-- The client runs OnShow/OnHide on visibility changes; the shared stubs do not.
local stubShow, stubHide = popup.Show, popup.Hide
function popup:Show()
    local was = self:IsShown()
    stubShow(self)
    if not was and self:GetScript("OnShow") then self:GetScript("OnShow")(self) end
end
function popup:Hide()
    local was = self:IsShown()
    stubHide(self)
    if was and self:GetScript("OnHide") then self:GetScript("OnHide")(self) end
end
popup:Hide()
showCopy("Discord", "https://example.invalid/one")
Check(popup:IsShown() and popup._msufEditBox:GetText() == "https://example.invalid/one", "the copy-link popup does not show its link")
showCopy("Wago", "https://example.invalid/two")
Check(popup:IsShown() and popup._msufEditBox:GetText() == "https://example.invalid/two",
    "a second link left the shown popup on the old link")
popup:Hide()
showCopy("GitHub", "https://example.invalid/three")
Check(#world.widgets.frames == framesAfterFirst and #CopyPopups() == 1, "link clicks keep creating copy-link frames")
Check(popup:IsShown() and popup._msufEditBox:GetText() == "https://example.invalid/three", "the reused popup lost its link")

print("menu_popup_contracts_smoke: ok (Fix now closes its dialog and builds its page once; menu prompts open above"
    .. " the Edit Mode window; one copy-link popup)")

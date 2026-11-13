local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = MenuWorld.InstallNativeUnitInputs }, arg[3])
local M, core, env = mw.M, mw.core, mw.env
local clock, prompts = 100, 0
local ShowPrompt = M.ShowPrompt
env.ReloadUI = function() error("reload before import confirmation") end
env.GetTime = function() return clock end
M.ShowPrompt = function(id)
    assert(id == "MSUF2_IMPORT_RELOAD_PROMPT", tostring(id))
    prompts = prompts + 1
end

local function Drain()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("menu timers did not settle")
end
local function Until(predicate)
    for _ = 1, 100 do
        if predicate() then return end
        clock = clock + 0.25
        mw:RunTimers(1)
    end
    error("queued import did not advance")
end
local function Control(suffix)
    for _, widget in ipairs(M.cache.profiles.searchWidgets or {}) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:sub(-#suffix) == suffix then return widget end
    end
    error("control missing: " .. suffix)
end
local function OpenImport()
    assert(mw:Select("profiles") ~= false)
    Drain()
    local import = Control("import.execute")
    local card = import:GetParent()
    local section = card:GetParent()
    assert(M.Widgets.FocusCollapsibleSection(section))
    Drain()
    return import, Control("import.export.buffer"), card
end
local function Progress(card)
    for _, child in ipairs({ card:GetChildren() }) do
        if child.bar and child.label then return child end
    end
end
local function Text(box, value)
    box:SetText(value)
    MenuWorld.FireScript(box, "OnTextChanged", true)
end

local widgetMethods = mw.world.widgets.Methods
widgetMethods.GetAlpha = widgetMethods.GetAlpha or function(self) return self.alpha or 1 end
widgetMethods.IsMouseEnabled = widgetMethods.IsMouseEnabled or function(self) return self.mouseEnabled ~= false end
local focusedEditBox
widgetMethods.SetFocus = function(self) focusedEditBox = self end
widgetMethods.HasFocus = function(self) return focusedEditBox == self end
widgetMethods.ClearFocus = function(self)
    if focusedEditBox == self then focusedEditBox = nil end
end

local contexts, bindText = {}, M.BindTextInput
M.BindTextInput = function(ctx, editBox, ...)
    contexts[editBox] = ctx
    return bindText(ctx, editBox, ...)
end
local import, box, card = OpenImport()
M.BindTextInput = bindText
local progress = Progress(card)
local db = M.EnsureDB()
local oldWidth, newWidth = db.player.width, db.player.width + 19
local harness = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local source = harness.Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "unitframe", payload = { player = { width = newWidth } } })
local begun, steps = 0, 0
local begin = core.ProfileImportReview.BeginImport
core.ProfileImportReview.BeginImport = function(...)
    begun = begun + 1
    local job, why, stage = begin(...)
    if not job then return nil, why, stage end
    local step = job.Step
    job.Step = function(self)
        steps = steps + 1
        return step(self)
    end
    return job
end

local function CheckPaste()
    local scroll = box:GetParent()
    local host = scroll:GetParent()
    local paste = assert(Progress(host), "profile input is missing paste feedback")
    local raw = "MSUFS3:" .. string.rep("A", 40000) .. "\r\nMSUF3:" .. string.rep("B", 8000) .. "\r\nMSUFSKIN:" .. string.rep("C", 2000)
    local changes, scrollWrites, textWrites, offset = 0, 0, 0, 0
    -- The widget model does not derive focus or viewport height from input and anchors.
    local hasFocus, getHeight = box.HasFocus, scroll.GetHeight
    local focused = true
    box.HasFocus = function() return focused end
    scroll.GetHeight = function() return 120 end
    local changed = M.ProfileWorkbenchUI.ImportChanged
    local setVerticalScroll, getVerticalScroll = scroll.SetVerticalScroll, scroll.GetVerticalScroll
    M.ProfileWorkbenchUI.ImportChanged = function(value)
        changes = changes + 1
        return changed(value)
    end
    scroll.SetVerticalScroll = function(_, value)
        scrollWrites = scrollWrites + 1
        offset = value
    end
    scroll.GetVerticalScroll = function() return offset end

    box:SetFocus()
    box:SetText(raw)
    MenuWorld.FireScript(box, "OnCursorChanged", 0, -300, 1, 12)
    MenuWorld.FireScript(box, "OnTextChanged", false)
    assert(paste:IsShown() and paste.bar:GetValue() == 1, "paste-only callback did not start visible feedback")
    assert(M.profileImportString == raw and box:GetText() == raw, "paste changed the raw Suite separators")
    MenuWorld.FireScript(box, "OnTextChanged", true)
    MenuWorld.FireScript(box, "OnCursorChanged", 0, -450, 1, 12)
    MenuWorld.FireScript(box, "OnCursorChanged", 0, -600, 1, 12)
    assert(changes == 1 and scrollWrites == 0, "paste repeated the text notification or scrolled inline")
    assert(begun == 0 and steps == 0 and not progress:IsShown() and db.player.width == oldWidth,
        "paste started the import job")
    mw:RunTimers(1)
    assert(paste:IsShown() and scrollWrites == 0, "paste feedback could not paint before caret scroll")
    Until(function() return scrollWrites == 1 end)
    assert(paste:IsShown() and paste.bar:GetValue() == 2, "paste bar did not mark the cursor pass complete")
    assert(offset == 612 - scroll:GetHeight(), "paste did not follow the final caret position")
    Drain()
    assert(not paste:IsShown() and scrollWrites == 1, "paste left stale feedback or repeated its cursor write")

    focused = false
    box:ClearFocus()
    MenuWorld.FireScript(box, "OnEditFocusLost")
    local setText = box.SetText
    box.SetText = function(self, value)
        textWrites = textWrites + 1
        return setText(self, value)
    end
    M.RequestRefresh(assert(contexts[box], "profile input was not bound"), "profile-paste-test")
    Drain()
    assert(textWrites == 0 and box:GetText() == raw and M.profileImportString == raw,
        "menu refresh rewrote the unchanged long text")
    box.SetText = setText

    Text(box, raw .. "DDEEFF")
    MenuWorld.FireScript(box, "OnCursorChanged", 0, -800, 1, 12)
    assert(paste:IsShown())
    MenuWorld.FireScript(host, "OnHide")
    Drain()
    assert(not paste:IsShown() and scrollWrites == 1, "hidden editor ran a stale paste callback")
    M.ProfileWorkbenchUI.ImportChanged = changed
    scroll.SetVerticalScroll, scroll.GetVerticalScroll = setVerticalScroll, getVerticalScroll
    box.HasFocus, scroll.GetHeight = hasFocus, getHeight
end
CheckPaste()

local function CheckQuickMode()
    local quick = Control("import.export.quick.mode")
    local scroll, editLimit = box:GetParent(), box.maxLetters
    local host = scroll:GetParent()
    local alpha, mouse = box:GetAlpha(), box:IsMouseEnabled()
    local scrollWrites, textWrites, highlights = 0, 0, 0
    local setScroll, setText, highlight = scroll.SetVerticalScroll, box.SetText, box.HighlightText
    scroll.SetVerticalScroll = function(self, offset)
        scrollWrites = scrollWrites + 1
        return setScroll(self, offset)
    end
    box.SetText = function(self, value)
        textWrites = textWrites + 1
        return setText(self, value)
    end
    box.HighlightText = function(self, ...)
        highlights = highlights + 1
        return highlight(self, ...)
    end
    assert(not quick:GetChecked() and scroll:GetScrollChild() == box, "quick mode must start off")
    local original = box:GetText()
    quick:Click()
    assert(quick:GetChecked() and box:GetParent() == host and scroll:GetScrollChild() ~= box and not scroll:IsShown(),
        "quick mode did not detach the native editbox from scroll layout")
    local point, anchor, relativePoint, x, y = box:GetPoint()
    assert(point == "TOPLEFT" and anchor == env.UIParent and relativePoint == "BOTTOMRIGHT" and x > 0 and y < 0,
        "native selection can still draw over the profile menu")
    local record, target = M.RuntimeControlCatalog.ResolveExactTarget("profiles", {
        controlId = box._msuf2RuntimeControlRecord.controlId,
    })
    assert(target == box and record.anchor == box._msuf2Title and record.anchor:IsVisible(),
        "exact profile-string search points to the off-screen editbox")
    assert(box:GetAlpha() == 0 and textWrites == 0 and box:GetText() == original and box.maxLetters == editLimit,
        "enabling quick mode changed the native buffer or input limit")
    assert(highlights == 1, "quick mode did not select the existing text for replacement")

    local raw = "MSUFS3:MSUF3:" .. string.rep("A", 102000) .. "\r\nMSUFM1:MSUF3:É雪\r\nMSKIN1:" .. string.rep("B", 7000)
    Text(box, raw)
    MenuWorld.FireScript(box, "OnCursorChanged", 0, -900, 1, 12)
    Drain()
    assert(M.profileImportString == raw and box:GetText() == raw and begun == 0 and prompts == 0 and db.player.width == oldWidth,
        "quick paste changed the multiline string or applied a profile")
    assert(scrollWrites == 0 and textWrites == 1, "quick paste scrolled or rewrote the native field")
    MenuWorld.FireScript(host, "OnMouseDown", "LeftButton")
    assert(highlights == 2, "quick paste area did not select text for replacement")

    quick:Click()
    assert(not quick:GetChecked() and box:GetParent() == scroll and scroll:GetScrollChild() == box and scroll:IsShown(),
        "leaving quick mode did not restore the normal editor")
    assert(box:GetAlpha() == alpha and box:IsMouseEnabled() == mouse and box:GetText() == raw and textWrites == 1,
        "leaving quick mode changed the text or failed to restore input presentation")
    local _, normalAnchor, normalPoint = box:GetPoint()
    assert(normalAnchor == scroll and normalPoint == "TOPLEFT", "normal editor kept its off-screen anchor")

    local setFocus = box.SetFocus
    box.SetFocus = function(self)
        if self:GetParent() == scroll then setFocus(self) end
    end
    quick:Click()
    assert(not quick:GetChecked() and box:HasFocus() and box:GetParent() == scroll,
        "a rejected off-screen focus left the user without a usable editor")
    assert(box:GetText() == raw and textWrites == 1, "focus fallback rewrote the profile string")
    box.SetFocus = setFocus
    assert(core.Util.InCombat("PLAYER_REGEN_DISABLED"))
    quick:Click()
    assert(not quick:GetChecked() and box:GetParent() == scroll, "quick mode reparented during combat")
    core.Util.InCombat("PLAYER_REGEN_ENABLED")

    local export = core.PublicGlobals.MSUF_ExportSelectionToString
    local exportKind = M.profileExportKind
    core.PublicGlobals.MSUF_ExportSelectionToString = function() return raw end
    env.MSUF_ExportSelectionToString = core.PublicGlobals.MSUF_ExportSelectionToString
    M.profileExportKind = "all"
    quick:Click()
    local before = highlights
    assert(Control("export.generate"):Click() == true, "export failed with quick mode enabled")
    assert(not quick:GetChecked() and box:GetText() == raw and box:GetParent() == scroll and highlights == before + 1,
        "export did not restore the full copyable string")
    quick:Click()
    assert(core.Util.InCombat("PLAYER_REGEN_DISABLED"))
    before = highlights
    assert(not Control("export.generate"):Click() and quick:GetChecked() and box:GetParent() == host,
        "the export action changed quick mode during the combat edge")
    assert(box:GetText() == raw and highlights == before, "the blocked export changed the native input")
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    quick:Click()
    core.PublicGlobals.MSUF_ExportSelectionToString, env.MSUF_ExportSelectionToString = export, export
    M.profileExportKind = exportKind
    scroll.SetVerticalScroll, box.SetText, box.HighlightText = setScroll, setText, highlight
    Drain()
end
CheckQuickMode()

Control("import.export.quick.mode"):Click()
Text(box, source)
local started = clock
assert(import:Click() == true, "click did not queue import")
assert(progress and progress:IsShown() and not import:IsEnabled(), "import did not show and lock progress immediately")
assert(begun == 0 and steps == 0 and db.player.width == oldWidth, "import ran in the click")
assert(MenuWorld.FireScript(import, "OnClick", "LeftButton") == false, "reentrant import click accepted")
Until(function() return begun == 1 end)
assert(steps == 0 and db.player.width == oldWidth, "constructor and first phase shared a timer")
Until(function() return steps == 1 end)
assert(progress:IsShown() and progress.bar:GetValue() == 1 and db.player.width == oldWidth, "first phase did not show detached progress")
assert(progress.label:GetText():find(string.format("%.1f s", clock - started), 1, true), "elapsed time did not update")
Until(function() return not progress:IsShown() end)
assert(import:IsEnabled() and db.player.width == newWidth and prompts == 1, "completed import did not apply and restore controls")
assert(M.profileImportString == source and box:GetText() == source, "completed import discarded the input")
Drain()
Control("import.export.quick.mode"):Click()
Drain()

local function CancelAfterStart(cancel)
    import, box, card = OpenImport()
    progress = assert(Progress(card))
    Text(box, source)
    local before = steps
    assert(import:Click() == true)
    Until(function() return steps > before end)
    cancel()
    local after = steps
    Drain()
    assert(not progress:IsShown() and import:IsEnabled() and steps == after and prompts == 1, "cancelled job ran or retained the busy state")
end
CancelAfterStart(function() Text(box, "changed input") end)
CancelAfterStart(function()
    box:SetText("replaced input")
    MenuWorld.FireScript(box, "OnTextChanged", false)
end)
CancelAfterStart(function() assert(mw:Select("home") ~= false) end)
CancelAfterStart(function()
    mw.world.widgets:EnterCombat()
    mw.world.widgets:LeaveCombat()
end)
assert(M.Open("profiles") ~= false)
Drain()
local originalName = env.MSUF_ActiveProfile
CancelAfterStart(function() env.MSUF_ActiveProfile = "Other profile" end)
env.MSUF_ActiveProfile = originalName
CancelAfterStart(function() M.HideSlashMenuAndMinibar(M.frame) end)
assert(M.Open("profiles") ~= false)
Drain()

import, box, card = OpenImport()
progress = assert(Progress(card))
local suiteCalls = 0
local oldSuite = core.SuiteLink.Profiles
core.SuiteLink.Profiles = function()
    return { ImportModule = function(text)
        assert(text == "MSUFM2:legacy")
        suiteCalls = suiteCalls + 1
        return true
    end }
end
Text(box, "MSUFM2:legacy")
assert(import:Click() == true and suiteCalls == 1 and not progress:IsShown(), "older Suite API lost its synchronous fallback")
core.SuiteLink.Profiles = function()
    return { BeginImport = function(text, name)
        assert(text == "MSUFM2:staged" and name == nil)
        return {
            completed = 0, total = 2, phase = "validate",
            Step = function(self)
                self.completed = self.completed + 1
                suiteCalls = suiteCalls + 1
                if self.completed == 2 then return true, true end
                self.phase = "apply"
                return false
            end,
        }
    end }
end
Text(box, "MSUFM2:staged")
assert(import:Click() == true and suiteCalls == 1 and progress:IsShown(), "staged Suite bypassed progress")
Until(function() return suiteCalls == 2 end)
assert(progress:IsShown() and progress.bar:GetValue() == 1)
Until(function() return suiteCalls == 3 end)
assert(not progress:IsShown() and import:IsEnabled(), "Suite job did not settle")
-- The final phase can synchronously trigger Menu2 hide through a profile
-- lifecycle notification. The completed import must still explain the restart.
local commitsToBlizzard, clickInProgress, staged = 0, false, core.Client.SupportsBlizzardEditMode
local activeLayout, saveFails = "Imported layout", false
local function CommitStaged(layoutName)
    assert(clickInProgress, "profile import committed staged Blizzard settings outside the confirmation click")
    assert(layoutName == "Imported layout", "profile import committed a different Blizzard layout")
    if layoutName ~= activeLayout then return false, "layout_changed" end
    if saveFails then return false end
    commitsToBlizzard = commitsToBlizzard + 1
    staged = false
    return true
end
local reloadPrompt
M.ShowPrompt = function(id, spec)
    assert(id == "MSUF2_IMPORT_RELOAD_PROMPT", tostring(id))
    reloadPrompt = ShowPrompt(id, spec)
    return reloadPrompt
end
env.RELOADUI, env.OKAY = "Reload UI", "Okay"
local reloads = 0
env.ReloadUI = function()
    assert(clickInProgress and reloadPrompt:IsShown(), "ReloadUI must be called by the click before the dialog closes")
    assert(not staged, "ReloadUI called with unsaved imported settings")
    reloads = reloads + 1
end
local function ClickPrompt(index)
    clickInProgress = true
    reloadPrompt._msufPromptButtons[index]:Click()
    clickInProgress = false
end
if core.Client.SupportsBlizzardEditMode then
    core.PublicGlobals.MSUF_BlizzardEditMode_StagedLayoutName = function() return staged and activeLayout end
    env.MSUF_BlizzardEditMode_CommitStaged = CommitStaged
    core.PublicGlobals.MSUF_BlizzardEditMode_CommitStaged = CommitStaged
end
local commits = 0
core.SuiteLink.Profiles = function()
    return { BeginImport = function(text, name)
        assert(text == "MSUFS3:staged" and name == "Imported Suite")
        return {
            completed = 0, total = 2, phase = "validate",
            Step = function(self)
                self.completed = self.completed + 1
                if self.completed == 1 then self.phase = "apply" return false end
                commits = commits + 1
                M.HideSlashMenuAndMinibar(M.frame)
                assert(MenuWorld.FireScript(import, "OnClick", "LeftButton") == false, "hide allowed a reentrant commit")
                return true, true
            end,
        }
    end }
end
Control("import.export.quick.mode"):Click()
Text(box, "MSUFS3:staged")
assert(import:Click() == false and M.profileImportCreateNew == true, "full Suite import lost its new-name requirement")
Drain()
import, box, card = OpenImport()
progress = assert(Progress(card))
local name = Control("import.new.profile.name")
Text(name, "Imported Suite")
assert(import:Click() == true)
Until(function() return not progress:IsShown() end)
assert(commits == 1 and commitsToBlizzard == 0 and M.profileImportNewName == "", "quiescing during commit swallowed or repeated completion")
assert(reloadPrompt and reloadPrompt:IsShown(), "completed named Suite import did not show restart instructions")
assert(reloads == 0, "import reloaded without a click")
if staged then
    assert(reloadPrompt._msufPromptButtons[1]:GetText() == "Apply", "reload was offered before staging was committed")
    mw.world.widgets:EnterCombat()
    ClickPrompt(1)
    assert(commitsToBlizzard == 0 and reloadPrompt:IsShown(), "combat committed staged settings or discarded the confirmation")
    mw.world.widgets:LeaveCombat()
    activeLayout = "Other layout"
    ClickPrompt(1)
    local recovery = reloadPrompt._msufPromptText:GetText()
    assert(commitsToBlizzard == 0 and recovery:find("Switch back", 1, true) and recovery:find("Imported layout", 1, true),
        "layout switch changed the consent target or failed to explain how to recover")
    activeLayout, saveFails = "Imported layout", true
    ClickPrompt(1)
    assert(reloads == 0 and commitsToBlizzard == 0 and staged and reloadPrompt:IsShown(),
        "failed save did not keep the imported settings and confirmation for retry")
    saveFails = false
    ClickPrompt(1)
    assert(reloads == 0 and commitsToBlizzard == 1 and reloadPrompt:IsShown(),
        "Apply did not commit once before offering reload")
end
local reloadLabel = env.RELOADUI or "Reload"
assert(reloadPrompt._msufPromptButtons[1]:GetText() == reloadLabel, "the confirmation does not offer a one-click reload")
local previousCommitCount = commitsToBlizzard
mw.world.widgets:EnterCombat()
ClickPrompt(1)
assert(reloads == 0 and reloadPrompt:IsShown(), "reload was attempted in combat")
mw.world.widgets:LeaveCombat()
ClickPrompt(1)
assert(reloads == 1 and commitsToBlizzard == previousCommitCount and reloadPrompt:IsShown(),
    "reload should perform no save work and remain retryable if the native call returns")
ClickPrompt(2)
assert(reloads == 1 and not reloadPrompt:IsShown(), "Not now triggered a reload or left the prompt open")
assert(M.Open("profiles") ~= false)
Drain()

import, box, card = OpenImport()
progress = assert(Progress(card))
core.SuiteLink.Profiles = function()
    return { BeginImport = function()
        return {
            completed = 0, total = 2, phase = "validate",
            Step = function() error("injected profile step error") end,
        }
    end }
end
Text(box, "MSUFM2:error")
-- Switch back to current profile mode to reach the injected module error.
Control("import.create.new.mode"):Click()
Drain()
local report = env.geterrorhandler
env.geterrorhandler = function() return error end
assert(import:Click() == true)
local ok, errorText = pcall(function() Until(function() return not progress:IsShown() end) end)
env.geterrorhandler = report
assert(not ok and tostring(errorText):find("injected profile step error", 1, true), "raising import did not report the error")
assert(not progress:IsShown() and import:IsEnabled(), "raising import kept the progress lock")
assert(M.MenuRuntime:PendingTaskCount() == 0, "raising import retained a queued callback")
core.SuiteLink.Profiles = oldSuite

if flavor == "Forever" then
    local retailSource
    for _, child in ipairs({ card:GetChildren() }) do
        local label = child._msuf2Label
        if label and label:GetText() == "Old profile is from Retail" then retailSource = child end
    end
    assert(retailSource, "legacy source switch missing")
    local nameField = Control("import.new.profile.name")
    local createNew = Control("import.create.new.mode")
    local hadCreateNew = createNew:GetChecked()
    if not hadCreateNew then
        createNew:Click()
        Drain()
    end
    assert(nameField:IsVisible(), "create-new mode did not show the name field")
    local _, _, _, _, nameTop = nameField._msuf2Title:GetPoint()
    local _, _, _, _, createTop = createNew:GetPoint()
    local _, _, _, _, retailTop = retailSource:GetPoint()
    assert(retailTop < createTop - createNew:GetHeight() and retailTop - retailSource:GetHeight() > nameTop,
        "the old Retail source switch overlaps the import mode or the profile name")
    if not hadCreateNew then
        createNew:Click()
        Drain()
    end
    local old = harness.Literal({ addon = "MSUF", fmt = 2, schema = 1, kind = "all",
        payload = { auras2 = { perUnit = { target = { overrideBlacklist = true,
            blacklist = { buffs = { spells = { ["299991"] = true } } } } } } },
    })
    local quick = Control("import.export.quick.mode")
    if not quick:GetChecked() then quick:Click() end
    assert(quick:GetChecked(), "quick mode did not enable")
    Text(box, old)
    retailSource:Click()
    assert(retailSource:GetChecked(), "legacy source switch did not select Retail")
    assert(import:Click() == true)
    assert(not retailSource:IsEnabled(), "legacy source switch remained enabled during staging")
    Until(function() return not progress:IsShown() end)
    local stored = M.EnsureDB()._msufAuraClients
    assert(stored and stored.clients.Mainline.auras2.perUnit.target.blacklist.buffs.spells["299991"],
        "legacy source was lost between the import control and staged job")
    Text(box, source)
    assert(not retailSource:GetChecked(), "legacy source followed an unrelated new paste")
end

print("profile_import_progress_smoke: " .. flavor .. " normal and quick paste, phased Core and Suite imports, time, cancellation and legacy fallback passed")

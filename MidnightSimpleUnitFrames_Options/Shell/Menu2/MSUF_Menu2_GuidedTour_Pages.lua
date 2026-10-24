-- Guided setup information pages and page registration.
local _, MSUF = ...
local Parts = MSUF.GuidedTourParts
local AutomaticCooldownProvider = Parts.AutomaticCooldownProvider
local BlockedByCombat = Parts.BlockedByCombat
local CooldownAnchorDecision = Parts.CooldownAnchorDecision
local CooldownAnchorSupported = Parts.CooldownAnchorSupported
local CurrentStage = Parts.CurrentStage
local EditDone = Parts.EditDone
local EditModeStatus = Parts.EditModeStatus
local Gfx = Parts.Gfx
local Invoke = Parts.Invoke
local M = Parts.M
local PixelLayoutRegion = Parts.PixelLayoutRegion
local PlayerDisplayName = Parts.PlayerDisplayName
local Preference = Parts.Preference
local ProfileMismatch = Parts.ProfileMismatch
local RegisterSpecialClickTargets = Parts.RegisterSpecialClickTargets
local Runtime = Parts.Runtime
local SelectedSetupArea = Parts.SelectedSetupArea
local SelectedSetupMode = Parts.SelectedSetupMode
local SetButtonEnabled = Parts.SetButtonEnabled
local SetButtonText = Parts.SetButtonText
local SetFontColor = Parts.SetFontColor
local SetGuidedCooldownAnchorDecision = Parts.SetGuidedCooldownAnchorDecision
local Tour = Parts.Tour
local TourState = Parts.TourState
local Tr = Parts.Tr
local floor = Parts.floor
local format = Parts.format
local max = Parts.max
local min = Parts.min
local function SetWrapped(fontString, width)
    if not fontString then return end
    fontString:SetWidth(max(40, width or 40))
    fontString:SetJustifyH("LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
end

local function AddCardIcon(card, T, iconKey)
    local well = T.Panel(card, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    well:SetSize(32, 32)
    local icon = PixelLayoutRegion(well:CreateTexture(nil, "ARTWORK"))
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    Gfx.NavIcon(icon, T, iconKey)
    return well
end

local function InfoCard(builder, T, title, body, iconKey, height)
    local card = builder:Section("", height or 82)
    if card.title then card.title:SetText("") end
    AddCardIcon(card, T, iconKey or "home")
    local heading = T.Font(card, "GameFontNormal", title, T.colors.text)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -12)
    heading:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    heading:SetJustifyH("LEFT")
    local copy = T.Font(card, "GameFontHighlightSmall", body, T.colors.muted)
    copy:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -36)
    SetWrapped(copy, builder.width - 70)
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(card, "controlFocusIn", { fromAlpha = 0.18, toAlpha = 1, duration = 0.20 })
    end
    return card, copy
end

-- InfoCard with a screenshot below the copy. Rounded corners are the one thing
-- on the overview page that a sentence cannot demonstrate, so that card shows a
-- real frame instead. The art is 2:1, so the card height follows the width.
local function TourPreview(key)
    local helpers = M.PreviewHelpers
    local previews = type(helpers) == "table" and helpers.TourPreviews or nil
    local spec = type(previews) == "table" and previews[key] or nil
    if type(spec) ~= "table" or type(spec.texture) ~= "string" then return nil end
    return spec
end

local function PreviewCard(builder, T, W, title, body, iconKey, spec)
    if not (type(spec) == "table" and type(W.PreviewImage) == "function") then
        return InfoCard(builder, T, title, body, iconKey, 92)
    end
    local maxWidth, copyHeight = 320, 76
    local imageWidth = min(maxWidth, max(180, builder.width - 72))
    local imageHeight = floor(imageWidth / (tonumber(spec.aspect) or 2) + 0.5)
    local card = InfoCard(builder, T, title, body, iconKey, copyHeight + imageHeight + 16)
    W.PreviewImage(card, spec, 56, -copyHeight, imageWidth)
    return card
end

local function Header(builder, title, subtitle)
    return builder:Header(title, subtitle, 72)
end

local function PersonalQuestion(ctx, builder, T, W, key, label, values, opts)
    opts = type(opts) == "table" and opts or {}
    local card = builder:Section("", 100)
    if card.title then card.title:SetText("") end
    local segment = W.Segment(card, label, values, max(240, builder.width - 28))
    RegisterSpecialClickTargets("menu_basics", key, segment.buttons)
    local function Refresh()
        segment:SetValue(Preference(key))
    end
    for i = 1, #(segment.buttons or {}) do
        local button = segment.buttons[i]
        local value = values[i]
        if value and type(T.AttachNavIcon) == "function" then T.AttachNavIcon(button, value.icon, false, true) end
        button:SetScript("OnClick", function(self)
            if BlockedByCombat() then return end
            Invoke(Tour(), "SetPreference", key, self._msuf2Value)
            Refresh()
            if type(T.PlayMotion) == "function" then
                T.PlayMotion(self, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.16 })
            end
            M.RefreshGuidedTourChrome("PERSONAL_CHOICE")
        end)
    end
    if opts.registerSearch ~= false then
        local identity = "guided_setup.preference." .. key
        M.RegisterSearchWidget(segment, {
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "guided_setup",
            label = Tr(label),
            kind = "segment",
            classification = "ephemeral",
            ephemeral = true,
            help = Tr("Personalizes guided setup hints without changing MSUF settings."),
        })
    end
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return card
end

local function BuildMenuBasicsPage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "menu_basics", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, format(Tr("Welcome, %s"), PlayerDisplayName()), "Choose a short setup or the complete learning tour.")
    PersonalQuestion(ctx, b, T, W, "setupMode", "How much help do you want?", {
        { value = "quick", text = "Quick Setup - essentials", icon = "home" },
        { value = "complete", text = "Complete Tour - every detail", icon = "profiles" },
    }, { registerSearch = false })
    PersonalQuestion(ctx, b, T, W, "setupArea", "What do you want to set up?", {
        { value = "unitframes", text = "Unitframes", icon = "uf_player" },
        { value = "groupframes", text = "Group Frames", icon = "gf_layout" },
        { value = "classresources", text = "Class Resources", icon = "classpower" },
        { value = "all", text = "Everything", icon = "home" },
    })
    InfoCard(b, T, "Quick Setup stays focused", "It shows only the essential choices. The Complete Tour keeps every advanced checkpoint available.", "home", 82)
    return math.abs(b.y) + 34
end

local function BuildChapterPage(ctx, T, W, stage)
    Runtime.specialClickTargets = { stageId = stage.id, groups = {} }
    local b = W.PageBuilder(ctx)
    local selected = SelectedSetupArea()
    local all = selected == "all"
    if stage.id == "unit_intro" then
        Header(b, all and "Part 1 of 3 - Unitframes" or "Unitframes", "Build Player once. Copy it when it feels right.")
        InfoCard(b, T, "Move the whole frame", "Edit Mode: drag the Player mover to place the frame on screen.", "uf_player", 76)
        InfoCard(b, T, "Change its size", "Click the mover in Edit Mode: its popup contains Width, Height, and other frame details.", "uf_player", 82)
        InfoCard(b, T, "Then Copy To", "Tune Player in the Live Preview, select All, and copy the result to another Unitframe.", "uf_target", 82)
    elseif stage.id == "group_intro" then
        if type(M.SetMenuStateValue) == "function" then M.SetMenuStateValue("gfScope", "party") else M.gfScope = "party" end
        Header(b, all and "Part 2 of 3 - Group Frames" or "Group Frames", "Build Party once. Copy it to Raid or Mythic Raid.")
        InfoCard(b, T, "Move the group", "Edit Mode: drag the Party Frames mover to place the complete group container.", "gf_layout", 76)
        InfoCard(b, T, "Change frame geometry", "Click the mover: its popup controls frame Width, Height, and Spacing.", "gf_layout", 82)
        InfoCard(b, T, "Then Copy To", "Finish Party, select All, and press Raid or Mythic to copy the setup instantly.", "gf_indicators", 82)
    else
        Header(b, all and "Part 3 of 3 - Class Resources" or "Class Resources", "Use the interactive preview to shape your class display.")
        InfoCard(b, T, "Class-aware preview", "Test the current class layout and change its size and arrangement live.", "classpower", 78)
        InfoCard(b, T, CooldownAnchorSupported() and "Cooldown-aware placement" or "Independent placement",
            CooldownAnchorSupported() and "Anchor it to Essential Cooldowns or keep it independently placed in Edit Mode."
                or "Place Class Resources independently in Edit Mode.", "classpower", 82)
    end
    return math.abs(b.y) + 34
end

local function RegisterGuidedPageButton(button, suffix, label, help)
    local identity = "guided_setup." .. suffix
    M.RegisterSearchWidget(button, {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = "guided_setup",
        label = Tr(label),
        kind = "button",
        classification = "action",
        help = Tr(help),
        historyMode = "none",
    })
end

local function CreateEditModeClick(Refresh)
    return function()
        if BlockedByCombat() then return end
        local status = EditModeStatus()
        if type(M.SetMSUFEditModeActive) == "function" then
            M.SetMSUFEditModeActive(not status.active, nil, { source = "guided_tour" })
        end
        Refresh()
    end
end

local function CreateEditModeAction(b, T, height, labelTop)
    local action = b:Section("", height)
    if action.title then action.title:SetText("") end
    local stateLabel = T.Font(action, "GameFontNormal", "", T.colors.text)
    stateLabel:SetPoint("TOPLEFT", action, "TOPLEFT", 16, labelTop)
    stateLabel:SetWidth(max(120, b.width - 252))
    stateLabel:SetJustifyH("LEFT")
    local stateCopy = T.Font(action, "GameFontDisableSmall", "", T.colors.muted)
    stateCopy:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)
    stateCopy:SetWidth(max(120, b.width - 252))
    stateCopy:SetJustifyH("LEFT")
    local button = T.Button(action, "Open MSUF Edit Mode", min(210, max(150, floor(b.width * 0.30))), 28)
    button:SetPoint("RIGHT", action, "RIGHT", -16, 0)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(button) end
    return stateLabel, stateCopy, button
end

local function BuildEditModePage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "edit_mode", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "Move vs size", "Drag Player to move it. Click Player to open the popup for Width and Height.")

    local cooldownSupported = CooldownAnchorSupported()
    local decisionCard = b:Section("", cooldownSupported and 146 or 62)
    if decisionCard.title then decisionCard.title:SetText("") end
    local decision
    if cooldownSupported then
        -- W.Segment translates its label and option texts itself.
        local decisionValues = {
            { value = "cooldown", text = "Follow Blizzard's Essential Cooldowns" },
            { value = "independent", text = "Independent placement" },
        }
        decision = W.Segment(decisionCard, "Should all Unitframes follow the Cooldown Manager?", decisionValues, max(240, b.width - 32))
        RegisterSpecialClickTargets("edit_mode", "anchor", decision.buttons)
        if type(W.MoveWidget) == "function" then W.MoveWidget(decision, decisionCard, 16, -18, max(240, b.width - 32), "LEFT") end
    end
    local decisionCopy = T.Font(decisionCard, "GameFontHighlightSmall", "", T.colors.muted)
    decisionCopy:SetPoint("TOPLEFT", decisionCard, "TOPLEFT", 16, cooldownSupported and -88 or -20)
    SetWrapped(decisionCopy, b.width - 32)

    InfoCard(b, T, "Two different actions", "DRAG = move the whole frame. CLICK = open its size and detail popup. Arrow keys nudge; Undo stays available.",
        "uf_player", 82)

    local stateLabel, stateCopy, button = CreateEditModeAction(b, T, 84, -20)

    local function Refresh()
        local status = EditModeStatus()
        local active = status.active == true
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local anchorDecision = CooldownAnchorDecision()
        local placementComplete = EditDone.placement()
        local movementComplete = EditDone.movement()
        if decision then
            decision:SetValue(anchorDecision)
            for i = 1, #(decision.buttons or {}) do
                SetButtonEnabled(decision.buttons[i], true)
            end
            if decision._msuf2Title and decision._msuf2Title.SetText then
                T.SetTranslatedText(decision._msuf2Title, automaticProviderLabel
                    and M.Format("Cooldown Manager anchoring (%s)", automaticProviderLabel)
                    or Tr("Should all Unitframes follow the Cooldown Manager?"))
            end
        end
        local anchorCopy
        if not decision then
            anchorCopy = Tr("This client has no Cooldown Manager. Unit Frames use their own anchor.")
        elseif anchorDecision == "cooldown" then
            anchorCopy = Tr("Selected: Unitframes follow Blizzard's Essential Cooldowns. If Blizzard's Essential Cooldowns move, the anchored " ..
                "Unitframe layout follows.")
        elseif anchorDecision == "independent" then
            anchorCopy = Tr("Selected: Unitframes use the current global/custom anchor. Moving Blizzard's Essential Cooldowns will not move them.")
        else
            anchorCopy = Tr("Required before placement. Changing this later can shift the whole layout because the saved offsets use a different anchor.")
        end
        T.SetTranslatedText(decisionCopy, anchorCopy)
        local label, copy
        if placementComplete then
            label = Tr("Frame moved - placement complete")
            copy = active and Tr("Exit keeps the result. You can now continue the guide.")
                or Tr("The required Edit Mode movement is complete.")
        elseif movementComplete then
            label, copy = Tr("Player moved - now open its size popup"), Tr("Click the highlighted Player mover. Width and Height live in that popup.")
        elseif active then
            label, copy = Tr("Move one highlighted frame to continue"),
                Tr("Two arrows point to a movable frame. Drag it once; Next unlocks after a real position change.")
        elseif anchorDecision then
            label, copy = Tr("Anchor chosen - open Edit Mode and move a frame"),
                Tr("The placement step completes after you drag the highlighted frame once.")
        else
            label, copy = Tr("Choose anchoring before placement"), Tr("Edit Mode unlocks after the anchor choice above.")
        end
        T.SetTranslatedText(stateLabel, label)
        T.SetTranslatedText(stateCopy, copy)
        SetFontColor(stateLabel, placementComplete and (T.colors.ok or T.colors.accent) or (active and (T.colors.warning or T.colors.accent) or T.colors.text))
        SetButtonText(button, active and "Exit and keep changes" or "Open MSUF Edit Mode")
        SetButtonEnabled(button, not status.combatLocked and (active or anchorDecision ~= nil))
    end
    for i = 1, #((decision and decision.buttons) or {}) do
        local choice = decision.buttons[i]
        choice:SetScript("OnClick", function(self)
            if SetGuidedCooldownAnchorDecision(self._msuf2Value) then
                Refresh()
                M.RefreshGuidedTourChrome("COOLDOWN_ANCHOR_DECISION")
            end
        end)
    end
    if decision then
        M.RegisterSearchWidget(decision, {
            controlId = "menu2.guided_setup.cooldown_anchor_decision",
            identityKey = "guided_setup.cooldown_anchor_decision",
            controlPath = "guided_setup/cooldown_anchor_decision",
            pageKey = "guided_setup",
            label = Tr("Unitframe Cooldown Manager anchoring"),
            kind = "segment",
            classification = "setting",
            help = Tr("Choose this before moving frames because it changes the anchor used by every Unitframe position."),
        })
    end
    button:SetScript("OnClick", CreateEditModeClick(Refresh))
    RegisterSpecialClickTargets("edit_mode", "edit_mode_toggle", { button })
    RegisterGuidedPageButton(button, "edit_mode_toggle", "Open or exit MSUF Edit Mode", "Moves whole MSUF frames and group containers; exiting keeps changes.")
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return math.abs(b.y) + 34
end

local function BuildGroupEditModePage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "group_edit_mode", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "Move vs size", "Drag Party Frames to move the group. Click it for Width, Height, and Spacing.")
    InfoCard(b, T, "Practice the real workflow", "DRAG the green-marked Party Frames mover once. CLICK the mover to inspect its geometry popup.", "gf_layout",
        86)

    local stateLabel, stateCopy, button = CreateEditModeAction(b, T, 92, -22)

    local function Refresh()
        local status = EditModeStatus()
        local complete = EditDone.groupPlacement()
        local moved = EditDone.groupMovement()
        local label, copy
        if complete then
            label, copy = Tr("Party Frames moved - checkpoint complete"),
                Tr("Click its mover whenever you want the Width, Height, and Spacing popup.")
        elseif moved then
            label, copy = Tr("Party moved - now open its geometry popup"),
                Tr("Click the highlighted Party Frames mover for Width, Height, and Spacing.")
        elseif status.active then
            label, copy = Tr("Drag the highlighted Party Frames mover"), Tr("After the drag, click that mover once to see the geometry popup.")
        else
            label, copy = Tr("Open Edit Mode and move Party Frames"),
                Tr("The next checkpoint unlocks after a real Party-frame position change.")
        end
        T.SetTranslatedText(stateLabel, label)
        T.SetTranslatedText(stateCopy, copy)
        SetFontColor(stateLabel, complete and (T.colors.ok or T.colors.accent) or T.colors.text)
        SetButtonText(button, status.active and "Exit and keep changes" or "Open MSUF Edit Mode")
        SetButtonEnabled(button, not status.combatLocked)
    end
    button:SetScript("OnClick", CreateEditModeClick(Refresh))
    RegisterSpecialClickTargets("group_edit_mode", "group_edit_mode_toggle", { button })
    RegisterGuidedPageButton(button, "group_edit_mode_toggle", "Open or exit MSUF Edit Mode for Party Frames",
        "Drag moves the group container; clicking its mover opens Width, Height, and Spacing.")
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return math.abs(b.y) + 34
end

local function BuildPowerMovesPage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "power_moves", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "MSUF power moves", "A focused frame workflow with direct control over the details that matter in combat.")
    InfoCard(b, T, "Touch the preview", "Click a handle to open its exact setting, drag it to move, or right-click for related actions.", "uf_player", 86)
    PreviewCard(b, T, W, "Rounded frames that match, corner for corner",
        "One clean corner style with five strength levels covers Health, embedded or detached Power, frame outlines, aggro, dispel and highlight " ..
            "borders, on Unitframes and Group Frames alike.",
        "opt_bars", TourPreview("rounded_frames"))
    InfoCard(b, T, "Spell Icons by spec",
        "Track presets or custom Spell IDs per spec, then choose icon or bar placement, cooldown behavior, and full-frame effects.", "gf_auras", 92)
    InfoCard(b, T, "Party combat intelligence", "Corner Indicators and External Defensives keep critical group information compact.", "gf_indicators", 92)
    InfoCard(b, T, CooldownAnchorSupported() and "Cooldown-aware layouts" or "Independent layouts",
        CooldownAnchorSupported() and "Anchor Unitframes and Class Resources to Essential Cooldowns, or keep every frame independently placed."
            or "Place Unitframes and Class Resources independently in Edit Mode.",
        "classpower", 86)
    InfoCard(b, T, "Find settings with Search", "Search Menu2 in everyday language to jump to the exact setting. Search only includes controls " ..
        "available in your active modules.", "home", 86)
    return math.abs(b.y) + 34
end

local function BuildFinalReviewPage(ctx, T, W)
    local b = W.PageBuilder(ctx)
    local quick = SelectedSetupMode() == "quick"
    Header(b, format(Tr("%s, your setup is ready"), PlayerDisplayName()), quick
        and "Finish returns to the Dashboard. Smart Search stays ready for settings and questions."
        or "Finish opens the Dashboard, where you can search settings across the active modules.")
    InfoCard(b, T, quick and "You are ready to play" or "Anything else? Just ask", quick
        and "Use the Dashboard for common tasks, or type a setting or full question into Smart Search."
        or "Try searches such as 'Party frame width', 'Spell Icons', or 'Class Resources'. Search opens the matching setting in Menu2.", "home", 104)
    local _, summaryCopy = InfoCard(b, T, "You trained on real settings", "", "uf_player", 82)
    ctx:AddRefresher(function()
        local summary = M.GetGuidedTourSummary()
        local handled = (tonumber(summary.reviewedControls) or 0) + (tonumber(summary.keptControls) or 0)
        T.SetTranslatedText(summaryCopy,
            format(Tr("%d guided settings were changed or deliberately kept. Nothing was copied into a separate wizard."), handled))
    end)

    local restorePoint = select(2, Invoke(Tour(), "GetRestorePoint"))
    if type(restorePoint) == "table" then
        local restoreAlreadyUsed = TourState().restorePointUsedAt ~= nil
        local restoreProfileMismatch = ProfileMismatch()
        local restore = b:Section("", 92)
        if restore.title then restore.title:SetText("") end
        local title = T.Font(restore, "GameFontNormal", restoreAlreadyUsed and "Starting setup restored" or "Starting setup saved", T.colors.text)
        title:SetPoint("TOPLEFT", restore, "TOPLEFT", 16, -20)
        title:SetWidth(max(120, b.width - 260))
        title:SetJustifyH("LEFT")
        local copy = T.Font(restore, "GameFontDisableSmall", restoreAlreadyUsed
            and "The starting profile values are active again. Finish when you are ready."
            or "You can restore the profile state captured before this guided setup.",
            restoreAlreadyUsed and (T.colors.ok or T.colors.accent) or T.colors.muted)
        copy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        SetWrapped(copy, max(120, b.width - 260))
        local button = T.Button(restore, restoreAlreadyUsed and "Starting setup restored" or "Restore starting setup",
            min(220, max(170, floor(b.width * 0.32))), 28)
        button:SetPoint("RIGHT", restore, "RIGHT", -16, 0)
        button._msuf2SkipHistoryCheckpoint = true
        if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
        local armedPoint
        local function RefreshRestore()
            restoreAlreadyUsed = TourState().restorePointUsedAt ~= nil
            restoreProfileMismatch = ProfileMismatch()
            local currentPoint = select(2, Invoke(Tour(), "GetRestorePoint"))
            if currentPoint ~= armedPoint or restoreAlreadyUsed or restoreProfileMismatch then armedPoint = nil end
            T.SetTranslatedText(title, Tr(restoreAlreadyUsed and "Starting setup restored" or "Starting setup saved"))
            T.SetTranslatedText(copy, Tr(restoreAlreadyUsed
                and "The starting profile values are active again. Finish when you are ready."
                or (armedPoint and "This replaces the current profile values with the setup starting point. Click again to confirm."
                    or "You can restore the profile state captured before this guided setup.")))
            SetFontColor(copy, armedPoint and (T.colors.warning or T.colors.warn or T.colors.muted)
                or (restoreAlreadyUsed and (T.colors.ok or T.colors.accent) or T.colors.muted))
            SetButtonText(button, restoreAlreadyUsed and "Starting setup restored" or (armedPoint and "Confirm restore" or "Restore starting setup"))
            SetButtonEnabled(button, type(currentPoint) == "table" and not restoreAlreadyUsed and not restoreProfileMismatch)
        end
        ctx:AddRefresher(RefreshRestore)
        ctx.wrapper:HookScript("OnHide", function() armedPoint = nil end)
        RefreshRestore()
        button:SetScript("OnClick", function()
            if TourState().restorePointUsedAt ~= nil or ProfileMismatch() or BlockedByCombat() then return end
            local point = select(2, Invoke(Tour(), "GetRestorePoint"))
            if type(point) ~= "table" then return end
            if armedPoint ~= point then
                armedPoint = point
                SetButtonText(button, "Confirm restore")
                M.Theme.SetTranslatedText(copy, Tr("This replaces the current profile values with the setup starting point. Click again to confirm."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
                return
            end
            armedPoint = nil
            Invoke(Tour(), "MarkRestorePointUsed", true)
            local restored = M.RestoreGuidedTourRestorePoint(point)
            if restored ~= true then
                Invoke(Tour(), "MarkRestorePointUsed", false)
                SetButtonText(button, "Restore starting setup")
                M.Theme.SetTranslatedText(copy, Tr("The starting setup could not be restored. Your current values remain active."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
            else
                RefreshRestore()
            end
        end)
        RegisterGuidedPageButton(button, "restore_start", "Restore starting setup",
            "Restores the active profile values captured before guided setup began after a second confirmation.")
    end

    -- The optional MSUF Suite gets one line and a way in, offered only while the
    -- Suite reports an overview and this menu has its module page registered.
    local suiteOverview = type(M.FormatSuiteTitle) == "function"
        and M.GetSuiteOverview() or nil
    local suitePage = suiteOverview and M.GetSuiteModulesPageKey(suiteOverview) or nil
    if suitePage then
        local suite = b:Section("", 92)
        if suite.title then suite.title:SetText("") end
        local suiteTitle = T.Font(suite, "GameFontNormal", M.FormatSuiteTitle(suiteOverview), T.colors.text)
        suiteTitle:SetPoint("TOPLEFT", suite, "TOPLEFT", 16, -20)
        suiteTitle:SetWidth(max(120, b.width - 260))
        suiteTitle:SetJustifyH("LEFT")
        local suiteCopy = T.Font(suite, "GameFontDisableSmall",
            Tr("Optional modules beyond unit frames: action bars, bags, chat, minimap and more."), T.colors.muted)
        suiteCopy:SetPoint("TOPLEFT", suiteTitle, "BOTTOMLEFT", 0, -8)
        SetWrapped(suiteCopy, max(120, b.width - 260))
        local suiteButton = T.Button(suite, "Open Suite Modules", min(220, max(170, floor(b.width * 0.32))), 28)
        suiteButton:SetPoint("RIGHT", suite, "RIGHT", -16, 0)
        suiteButton._msuf2SkipHistoryCheckpoint = true
        if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(suiteButton) end
        suiteButton:SetScript("OnClick", function()
            if BlockedByCombat() then return end
            M.SelectPage(suitePage)
        end)
        RegisterGuidedPageButton(suiteButton, "open_suite_modules", "Open Suite Modules", "Shows the Suite page that switches each optional module on or off.")
    end
    return math.abs(b.y) + 34
end

function M.BuildGuidedSetupPage(ctx)
    local T, W = M.Theme, M.Widgets
    if not (ctx and ctx.wrapper and T and W) then return 240 end
    local stage = CurrentStage()
    local builder = BuildMenuBasicsPage
    if stage.id == "unit_intro" or stage.id == "group_intro" or stage.id == "class_intro" then builder = BuildChapterPage
    elseif stage.id == "edit_mode" then builder = BuildEditModePage
    elseif stage.id == "group_edit_mode" then builder = BuildGroupEditModePage
    elseif stage.id == "power_moves" then builder = BuildPowerMovesPage
    elseif stage.id == "final_review" then builder = BuildFinalReviewPage end
    Runtime.specialClickTargets = { stageId = stage.id, groups = {} }
    local height = builder(ctx, T, W, stage)
    local targets = Runtime.specialClickTargets
    ctx:AddRefresher(function()
        Runtime.specialClickTargets = targets
        if stage.id == "group_intro" then M.SetMenuStateValue("gfScope", "party") end
    end)
    return height
end

M.navPrimaryForKey = type(M.navPrimaryForKey) == "table" and M.navPrimaryForKey or {}
M.navPrimaryForKey.guided_setup = "home"
M.RegisterPage("guided_setup", { title = "Guided Setup", build = M.BuildGuidedSetupPage, version = 1,
    variantKey = function()
        local stage = CurrentStage()
        local key = stage.special and stage.id or "menu_basics"
        if key == "unit_intro" or key == "group_intro" or key == "class_intro" then
            key = key .. (SelectedSetupArea() == "all" and ":all" or ":single")
        elseif key == "final_review" then
            local point = select(2, Invoke(Tour(), "GetRestorePoint"))
            local suite = M.GetSuiteOverview()
            key = key .. (SelectedSetupMode() == "quick" and ":quick" or ":complete")
                .. (type(point) == "table" and ":restore" or ":no-restore")
                .. (suite and M.GetSuiteModulesPageKey(suite) and ":suite" or ":no-suite")
        end
        return key
    end
})


-- Complete forward bindings once; gameplay closures keep direct local calls.
Parts.Bind2()
MSUF.GuidedTourParts = nil

-- Custom Aura setup tools; retains the shared per-build container context.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.CustomAuraWorkspaceParts
local HideInlineSwatch = Parts.HideInlineSwatch
local ResetButton = Parts.ResetButton
local W = Parts.W
local T = Parts.T
local Model = Parts.Model
local AurasPage = Parts.AurasPage
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type
local BindSwitch = Parts.BindSwitch
local BindSlider = Parts.BindSlider
local BindDropdown = Parts.BindDropdown
local BindTextInput = Parts.BindTextInput
local AddTooltip = Parts.AddTooltip
local AuraControlMeta = Parts.AuraControlMeta
local Rebuild = Parts.Rebuild
local Repaint = Parts.Repaint
local Tr = Parts.Tr
local CUSTOM_AURA_TYPES = Parts.CUSTOM_AURA_TYPES
local REMINDERS_AVAILABLE = Parts.REMINDERS_AVAILABLE
local CLASSIC_REMINDER_NOTICE = Parts.CLASSIC_REMINDER_NOTICE
local CUSTOM_DISPLAY_MODES = Parts.CUSTOM_DISPLAY_MODES
local TRANSLATED_TITLE = Parts.TRANSLATED_TITLE
local ContainerTitle = Parts.ContainerTitle


-- Player Defensives and Dots on target share one Setup layout: the same
-- switches and the portrait icon cap in the same places. A row is { label,
-- record key, y, width, apply reason, control path, tooltip title, tooltip
-- body, on }: an "on" switch reads as enabled until it is turned off, the others
-- only once set. The portrait icon cap is a slider across the full width.
local PORTRAIT_SETUP = {
    defensives = {
        title = "Defensive Buffs Setup", height = 390, resetReason = "AURAS3_PLAYER_DEFENSIVES_RESET",
        { "Enabled", "enabled", -48, 112, "AURAS3_PLAYER_DEFENSIVES_ENABLE", "custom-container.player-defensives.enabled",
            "Enable defensive buffs",
            "Core feature enabled by default for new profiles and once for existing profiles. It works as a normal defensive buff bar without an enabled "
                .. "portrait. Turn this off to disable both bar and portrait-position display." },
        { "Show buffs at portrait position", "portraitIcon", -86, 280, "AURAS3_PLAYER_DEFENSIVE_PORTRAIT", "custom-container.player-defensives.portrait-icon",
            "Show buffs at portrait position",
            "Optional presentation mode; the Defensive Buffs feature itself does not require a portrait. With an enabled portrait, the first icon occupies "
                .. "it. When the portrait is off, enable the position option below to keep the icons there; otherwise MSUF safely falls back to the normal "
                .. "defensive bar." },
        { "Max portrait icons", "portraitMaxIcons", -128, nil, "AURAS3_PLAYER_DEFENSIVE_PORTRAIT_MAX", "custom-container.player-defensives.portrait-max-icons",
            "Max portrait icons",
            "Limits the number of simultaneous defensive icons at the portrait from 1 to 8. Existing profiles remain at 1 until this value is changed." },
        { "Show cooldown text on portrait", "portraitCooldownText", -198, 280, "AURAS3_PLAYER_DEFENSIVE_PORTRAIT_COOLDOWN",
            "custom-container.player-defensives.portrait-cooldown-text",
            "Show cooldown text on portrait",
            "Shows the active defensive buff's remaining duration over its portrait icon. Blizzard updates the text natively.", true },
        { "Use portrait position while portrait is off", "portraitPositionWhenDisabled", -236, 326, "AURAS3_PLAYER_DEFENSIVE_PORTRAIT_POSITION",
            "custom-container.player-defensives.portrait-position-when-disabled",
            "Use portrait position while portrait is off",
            "Keeps the configured portrait size and position as an invisible anchor so the defensive icon can remain there while the portrait itself is "
                .. "disabled." },
        { "Auto-blacklist from player buffs", "autoBlacklistPlayerBuffs", -274, 280, "AURAS3_PLAYER_DEFENSIVE_AUTO_BLACKLIST",
            "custom-container.player-defensives.auto-blacklist",
            "Auto-blacklist from player buffs",
            "While the defensive bar or portrait icon is enabled, hides every enabled tracked defensive from the normal player Buffs lane. Disabled defensive "
                .. "entries remain visible there.", true },
    },
    dots = {
        title = "Dots on target Setup", height = 410, resetReason = "AURAS3_TARGET_DOTS_RESET",
        { "Enabled", "enabled", -48, 112, "AURAS3_TARGET_DOTS_ENABLE", "custom-container.target-dots.enabled",
            "Enable tracked DoTs",
            "Tracks your selected harmful auras on this UnitFrame's unit. Boss frames use their own boss1 through boss5 unit token." },
        { "Show DoTs at portrait position", "portraitIcon", -86, 280, "AURAS3_TARGET_DOTS_PORTRAIT", "custom-container.target-dots.portrait-icon",
            "Show DoTs at portrait position",
            "Replaces the normal DoT lane with portrait-sized icons. The first icon exactly follows this frame's portrait width, height, and shape." },
        { "Max portrait icons", "portraitMaxIcons", -128, nil, "AURAS3_TARGET_DOTS_PORTRAIT_MAX", "custom-container.target-dots.portrait-max-icons",
            "Max portrait icons",
            "Limits simultaneous DoT icons at the portrait from 1 to 8. Additional icons grow outward using this DoT lane's configured Growth direction." },
        { "Show cooldown text on portrait", "portraitCooldownText", -198, 280, "AURAS3_TARGET_DOTS_PORTRAIT_COOLDOWN",
            "custom-container.target-dots.portrait-cooldown-text",
            "Show cooldown text on portrait",
            "Shows the tracked DoT's remaining duration over its portrait icon. Blizzard updates the duration natively.", true },
        { "Use portrait position while portrait is off", "portraitPositionWhenDisabled", -236, 326, "AURAS3_TARGET_DOTS_PORTRAIT_POSITION",
            "custom-container.target-dots.portrait-position-when-disabled",
            "Use portrait position while portrait is off",
            "Keeps the configured portrait size, position, and shape as an invisible anchor for tracked DoTs while the portrait itself is disabled." },
        { "Auto-blacklist from Debuffs", "autoBlacklistDebuffs", -274, 280, "AURAS3_TARGET_DOTS_AUTO_BLACKLIST",
            "custom-container.target-dots.auto-blacklist-debuffs",
            "Auto-blacklist from Debuffs",
            "Hides this scope's selected DoT Spell IDs from the same UnitFrame's normal Debuff container while Dots on target is enabled. Blizzard's "
                .. "blacklist is SpellID-based, so the same spell cast by another player is hidden there too.", true },
    },
}
--- Builds the shared Setup section of Player Defensives or Dots on target
--- (spec = PORTRAIT_SETUP.<kind>) and its Reset; returns the section and its
--- inner width for the container's own status lines.
local function BuildPortraitContainerSetup(C, spec)
    local ctx, b, item, Apply = C.ctx, C.b, C.item, C.Apply
    local section = b:Section(spec.title, spec.height)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    for i = 1, #spec do
        local row = spec[i]
        local key, reason, defaultOn = row[2], row[5], row[9] == true
        local control
        if key == "portraitMaxIcons" then
            control = BindSlider(ctx, section, row[1], 24, row[3], 1, 8, 1, inner,
                function() return tonumber(item.portraitMaxIcons) or 1 end,
                { write = { container = C, source = function() return item end,
                convert = function(value) return max(1, min(8, floor((tonumber(value) or 1) + 0.5))) end, after = function() Apply(reason, true) end
            } --[[schema setter: J5.CustomSetup.1]] },
                AuraControlMeta(ctx, row[6]))
        else
            control = BindSwitch(ctx, section, row[1], 24, row[3], row[4],
                function()
                    if defaultOn then return item[key] ~= false end
                    return item[key] == true
                end,
                { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply(reason, true) end
            } --[[schema setter: J5.CustomSetup.2]] },
                AuraControlMeta(ctx, row[6]))
        end
        AddTooltip(control, row[7], row[8])
    end
    ResetButton(C, section, 88, -42, spec.resetReason)
    return section, inner
end
local function BuildCustomDefensivesSetup(C)
    local ctx, unit, index, isPlayerDefensives = C.ctx, C.unit, C.index, C.isPlayerDefensives
    if isPlayerDefensives then
        local section, inner = BuildPortraitContainerSetup(C, PORTRAIT_SETUP.defensives)
        -- The counts change in the Defensives tool. Its view stays cached while
        -- this one is shown, so the line repaints instead of keeping build data.
        local function SourceText()
            local predefined = Model.PlayerDefensivePreviewEntries
                and #Model.PlayerDefensivePreviewEntries() or 0
            local predefinedTotal = Model.PlayerDefensiveClassEntries
                and #Model.PlayerDefensiveClassEntries(true) or predefined
            local custom = #Model.CustomContainerSpellEntries(unit, index)
            return M.Format("Source: player buffs · %d / %d predefined enabled · %d custom · passive talent procs included",
                predefined, predefinedTotal, custom)
        end
        -- The 12.1 native aura buttons render their icon unmaskable; shaping
        -- was attempted exhaustively and reverted (2026-07-31). Keep users
        -- informed instead of letting them hunt for a shape option.
        W.Text(section, "Aura Style > Defensive Buffs can follow the frame portrait shape.", 24, -312, inner, T.colors.muted)
        local source = W.Text(section, "", 24, -344, inner, T.colors.muted)
        M.TrackRefresh(ctx, function() T.SetTranslatedText(source, SourceText()) end)
        return true
    end
end

local function BuildCustomDotsSetup(C)
    local ctx, unit, index, isTargetDots, item = C.ctx, C.unit, C.index, C.isTargetDots, C.item
    if isTargetDots then
        local section, inner = BuildPortraitContainerSetup(C, PORTRAIT_SETUP.dots)
        -- The DoT list changes in the Dots tool, whose view stays cached while
        -- this one is shown: both lines repaint from the saved data.
        local function SourceText()
            return M.Format("Source: this UnitFrame · Ownership: only mine · Harmful DoTs only · %d selected",
                #Model.CustomContainerSpellEntries(unit, index))
        end
        local function DisplayText()
            return item.portraitIcon == true and "Display: portrait position" or "Display: normal DoT lane"
        end
        local source = W.Text(section, "", 24, -324, inner, T.colors.muted)
        local display = W.Text(section, DisplayText(), 24, -356, inner, T.colors.muted)
        M.TrackRefresh(ctx, function()
            T.SetTranslatedText(source, SourceText())
            display:SetText(DisplayText())
        end)
        return true
    end
end

--- The Buff Reminder status line: how many fixed slots the whitelist fills,
--- how many of them react to a click, and where their order comes from.
local function PaintReminderStatus(C, reminderStatus, on)
    local unit, index, item = C.unit, C.index, C.item
    local cap = max(0, floor(tonumber(item.placed.max) or 8))
    local allEntries = Model.CustomContainerSpellEntries(unit, index)
    -- A filtered row is not a slot, so it must not be counted as one.
    local selfOnly = item.placed.reminderOnlyCastable == true
    local hidden, slots = 0, 0
    for i = 1, #allEntries do
        local entry = allEntries[i]
        if selfOnly and not entry.clickAction and entry.keep ~= true then
            hidden = hidden + 1
        elseif slots < cap then
            slots = slots + 1
        end
    end
    if unit == "player" then
        if item.reminderEnchantMainHand == true and slots < cap then slots = slots + 1 end
        if item.reminderEnchantOffHand == true and slots < cap then slots = slots + 1 end
    end
    -- One line, three facts: how many slots, how many of them react to a
    -- click, and where their order comes from.
    if not REMINDERS_AVAILABLE then
        reminderStatus:SetText(CLASSIC_REMINDER_NOTICE)
    elseif not on then
        reminderStatus:SetText("Off · switch Display to Fixed slots in Setup to use this.")
    else
        local clickable, counted = 0, 0
        for i = 1, #allEntries do
            local entry = allEntries[i]
            if not (selfOnly and not entry.clickAction and entry.keep ~= true) and counted < cap then
                counted = counted + 1
                if entry.clickAction then clickable = clickable + 1 end
            end
        end
        if unit == "player" then
            local hasItem = Model.CustomContainerReminderEnchantItem(unit, index) ~= nil
            if item.reminderEnchantMainHand == true and counted < cap then
                counted = counted + 1
                if hasItem then clickable = clickable + 1 end
            end
            if item.reminderEnchantOffHand == true and counted < cap then
                counted = counted + 1
                if hasItem then clickable = clickable + 1 end
            end
        end
        local base = item.placed.reminderClickCast == false
            and M.Format("%d fixed slots · order comes from the Whitelist.", slots)
            or M.Format("%d fixed slots · %d clickable · order comes from the Whitelist.",
                slots, clickable)
        -- Say it out loud when the filter is swallowing rows, otherwise a
        -- whitelisted entry would just be missing with no explanation.
        if hidden > 0 then
            base = base .. " " .. M.Format("%d hidden: not castable by this character.", hidden)
        end
        T.SetTranslatedText(reminderStatus, base)
    end
end
--- Setup > Buff Reminder: how the fixed reminder slots look and what a click
--- on one does. Its refresher also keeps the Setup Enabled switch actionable.
local function BuildCustomReminderSection(C, setupW, enabled)
    local ctx, b, index, item, Apply = C.ctx, C.b, C.index, C.item, C.Apply
    local reminderSection = AurasPage.Section(b, "aura_reminder_custom_" .. tostring(index),
        "Buff Reminder", 258, false)
    local rw = reminderSection._msuf2Width or setupW
    local rInner = rw - 48
    local rcol, rgap = C.Grid(rw, 2)
    -- A reminder switch writes its placed key and applies with a refresh; an
    -- "on" switch reads as enabled until it is turned off.
    local function PlacedSwitch(label, x, y, width, key, defaultOn, reason, path)
        return BindSwitch(ctx, reminderSection, label, x, y, width,
            function()
                if defaultOn then return item.placed[key] ~= false end
                return item.placed[key] == true
            end,
            { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply(reason, true) end
            } --[[schema setter: J5.CustomSetup.3]] },
            AuraControlMeta(ctx, path))
    end
    -- The mode itself lives in Setup next to Aura type; this section owns only
    -- how the reminder looks and what a click on it does.
    local reminderAlpha = BindSlider(ctx, reminderSection, "Placeholder opacity", 24, -46, 10, 100, 5, rcol,
        function() return floor(((tonumber(item.placed.reminderAlpha) or 0.45) * 100) + 0.5) end,
        { write = { container = C, source = function() return item end,
                convert = function(value) return max(0.1, min(1, (tonumber(value) or 45) / 100)) end,
                after = function() Apply("AURAS3_CUSTOM_REMINDER_ALPHA", true) end
            } --[[schema setter: J5.CustomSetup.4]] },
        AuraControlMeta(ctx, "custom-container.reminder.opacity"))
    AddTooltip(reminderAlpha, "Placeholder opacity",
        "How strongly a missing aura's placeholder is drawn. Lower values keep the frame calm; the running aura always covers it completely either way.")
    local reminderDesaturate = PlacedSwitch("Grey out placeholders", 24 + rcol + rgap, -46, rcol,
        "reminderDesaturate", true, "AURAS3_CUSTOM_REMINDER_DESATURATE", "custom-container.reminder.desaturate")
    AddTooltip(reminderDesaturate, "Grey out placeholders",
        "Draws the placeholder without colour so a missing aura reads at a glance. Turn this off to keep the spell's own colours and separate the two states "
            .. "by opacity or tint alone.")
    local reminderColor = W.Color(reminderSection, "Placeholder tint")
    AurasPage.BindColor(ctx, reminderColor,
        function()
            local c = type(item.placed.reminderColor) == "table" and item.placed.reminderColor or nil
            return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1
        end,
        function(r, g, blue)
            item.placed.reminderColor = { r, g, blue }
            Apply("AURAS3_CUSTOM_REMINDER_COLOR", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.color"))
    HideInlineSwatch(reminderColor)
    local reminderClick = PlacedSwitch("Click the icon to cast the spell", 24, -96, rInner,
        "reminderClickCast", true, "AURAS3_CUSTOM_REMINDER_CLICK_CAST", "custom-container.reminder.click-cast")
    AddTooltip(reminderClick, "Click the icon to cast the spell",
        "Turns every reminder slot into a cast button: clicking it casts that slot's spell at this frame's unit, whether the aura is missing or already "
            .. "running, so re-applying a poison or flask works. The binding is written once outside combat and never changes afterwards, so this costs no "
            .. "timer, no event and no aura read. Only spells work; food, flasks and other items cannot be triggered this way.")
    -- One whitelist for every character: with this on, a Mage's reminder row
    -- keeps Arcane Intellect and drops the Rogue poisons from the same profile.
    -- Rows with a bound item stay either way -- an item is class agnostic.
    local reminderSelfOnly = PlacedSwitch("Only show what I can apply myself", 24, -142, rInner,
        "reminderOnlyCastable", false, "AURAS3_CUSTOM_REMINDER_SELF_ONLY", "custom-container.reminder.only-castable")
    AddTooltip(reminderSelfOnly, "Only show what I can apply myself",
        "Hides every whitelisted spell this character cannot cast, without leaving a gap. One whitelist can then serve all your characters: the Mage keeps "
            .. "Arcane Intellect, the Rogue keeps the poisons. Nothing reports which class owns a Spell ID, so a flask buff looks exactly like a foreign "
            .. "class ability here - protect those with a bound item, or with Always show on the row in the Whitelist. MSUF re-checks this only when your "
            .. "spellbook or talents actually change, never during combat.")
    local reminderStatus = W.Text(reminderSection, "", 24, -190, rInner, T.colors.muted)
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(enabled, true)
        local on = REMINDERS_AVAILABLE and item.placed.reminderEnabled == true
        if W.SetControlsEnabled then
            W.SetControlsEnabled({ reminderAlpha, reminderDesaturate, reminderClick, reminderSelfOnly }, on)
        end
        PaintReminderStatus(C, reminderStatus, on)
        if W.SetCollapsibleBadges then
            local badges = {{
                text = on and "Reminder on" or "Reminder off", -- the badge translates it
                kind = on and "accent" or "muted", showWhenClosed = true,
            }}
            if on and item.placed.reminderClickCast ~= false then
                badges[#badges + 1] = { text = "Click-cast", kind = "info", showWhenClosed = true }
            end
            W.SetCollapsibleBadges(reminderSection, badges)
        end
    end)
end
local function BuildCustomContainerSetup(C)
    local ctx, b, unit, index, item, Apply = C.ctx, C.b, C.unit, C.index, C.item, C.Apply
    local setupW = b.width or 720
    local compactSetup = setupW < 680
    local section = b:Section(M.Format("%s Setup", ContainerTitle(C)), compactSetup and 262 or 210, TRANSLATED_TITLE)
    local w = section._msuf2Width or setupW
    local inner = w - 48
    local enabled = BindSwitch(ctx, section, "Enabled", 24, compactSetup and -52 or -62, 106,
        function() return item.enabled == true end,
        { write = { container = C, source = function() return item end,
                strictBoolean = true, after = function() Apply("AURAS3_CUSTOM_CONTAINER_ENABLE") end
            } --[[schema setter: J5.CustomSetup.5]] },
        AuraControlMeta(ctx, "custom-container.setup.enabled"))
    local resetW = 88
    ResetButton(C, section, resetW, compactSetup and -46 or -56, "AURAS3_CUSTOM_CONTAINER_RESET")

    local fieldX = compactSetup and 24 or 140
    local fieldY = compactSetup and -82 or -34
    local fieldRight = compactSetup and (w - 24) or (w - 24 - resetW - 12)
    local fieldGap = 12
    local fieldSpace = max(0, fieldRight - fieldX - fieldGap)
    local typeW = compactSetup and max(140, floor(fieldSpace * 0.34))
        or max(150, min(max(170, floor(inner * 0.18)), fieldSpace - 200))
    local nameW = compactSetup and max(120, fieldSpace - typeW)
        or max(120, min(max(260, floor(inner * 0.42)), fieldSpace - typeW))
    -- The model stores the factory name in English ("Custom N"). It is shown
    -- translated, and the shown text coming back unchanged keeps that saved name.
    local factoryName = "Custom " .. tostring(index)
    local shownFactoryName = M.Format("Custom %d", index)
    BindTextInput(ctx, section, "Container name", fieldX, fieldY, nameW,
        function()
            local name = item.name or factoryName
            return name == factoryName and shownFactoryName or name
        end,
        { write = { container = C, source = function() return item end,
                convert = function(value) return (value == "" or value == shownFactoryName) and factoryName or value end,
                after = function() Apply("AURAS3_CUSTOM_CONTAINER_NAME") end
            } --[[schema setter: J5.CustomSetup.6]] },
        false, AuraControlMeta(ctx, "custom-container.setup.name"))
    BindDropdown(ctx, section, "Aura type", fieldX + nameW + fieldGap, fieldY, CUSTOM_AURA_TYPES, typeW,
        function() return item.auraType == "DEBUFF" and "DEBUFF" or "BUFF" end,
        function(value)
            local nextType = value == "DEBUFF" and "DEBUFF" or "BUFF"
            local prevType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
            -- A duration ceiling configured for one aura type must not survive
            -- the switch: since 6.09 it compiles for every lane and would
            -- silently hide long or permanent auras of the other type.
            if nextType ~= prevType and type(item.filters) == "table" then
                item.filters.maxDuration = nil
            end
            item.auraType = nextType
            Apply("AURAS3_CUSTOM_CONTAINER_TYPE", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "custom-container.setup.aura-type"))
    local modeY = (compactSetup and -82 or -34) - 70
    local displayMode = BindDropdown(ctx, section, "Display", 24, modeY, CUSTOM_DISPLAY_MODES, max(200, min(320, floor(inner * 0.42))),
        function() return item.placed.reminderEnabled == true and "reminder" or "active" end,
        { write = { container = C, source = function() return item end,
            accept = function() return REMINDERS_AVAILABLE end,
            convert = function(value) return value == "reminder" end,
            after = function() Apply("AURAS3_CUSTOM_REMINDER", true) Repaint(ctx) end
        } --[[schema setter: J5.CustomSetup.Display]] },
        AuraControlMeta(ctx, "custom-container.reminder.enabled"))
    local modeNote = W.Text(section, "", 24, modeY - 44, inner, T.colors.muted)
    -- The Whitelist tool changes the count while this view stays cached.
    local function CountText()
        local count = #Model.CustomContainerSpellEntries(unit, index)
        return count == 1 and Tr("1 whitelisted spell · style remains live in Menu Preview and Edit Mode.")
            or M.Format("%d whitelisted spells · style remains live in Menu Preview and Edit Mode.", count)
    end
    local countNote = W.Text(section, "", 24, modeY - 66, inner, T.colors.muted)
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(displayMode, REMINDERS_AVAILABLE)
        modeNote:SetText(not REMINDERS_AVAILABLE and CLASSIC_REMINDER_NOTICE
            or item.placed.reminderEnabled == true
            and "Every whitelisted entry keeps its own place. A dimmed icon means that entry is missing."
            or "Only auras that are currently active are shown, packed together.")
        T.SetTranslatedText(countNote, CountText())
    end)

    -- Buff Reminder. Exact Spell ID whitelists are the only aura source that
    -- can carry one fixed slot per spell, so the mode belongs to Custom 1-3.
    -- It is never state driven: MSUF cannot read whether an aura is present
    -- on 12.1, so the placeholder is simply drawn beneath the native icon.
    BuildCustomReminderSection(C, setupW, enabled)
end


Parts.BuildCustomDefensivesSetup = BuildCustomDefensivesSetup

Parts.BuildCustomDotsSetup = BuildCustomDotsSetup

Parts.BuildCustomContainerSetup = BuildCustomContainerSetup

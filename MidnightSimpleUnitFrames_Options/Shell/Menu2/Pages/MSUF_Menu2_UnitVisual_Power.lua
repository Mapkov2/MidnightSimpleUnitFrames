-- Power state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.UnitVisualFactories = M.UnitVisualFactories or {}

local function RequireFields(domain, values, fields)
    assert(type(values) == "table", domain .. " interface is required")
    for key in fields:gmatch("%S+") do
        assert(values[key] ~= nil, domain .. "." .. key .. " is required")
    end
end

M.UnitVisualFactories.Power = function(profile, controls, runtime)
    RequireFields("Power.Profile", profile,
        "Units GetConf GetGeneral GetBars UnitTopLabel ReadBool SetBool ReadNumber SetNumber IsPlayerPowerManagedByClassResources")
    RequireFields("Power.Controls", controls, "Widgets Schema Row Card SettingMeta RegisterControl Shared")
    RequireFields("Power.Runtime", runtime, "Core EnsureCooldownWidthObservers")
local floor, max, min = math.floor, math.max, math.min
local VT = M.ValueTextList
local POWER_UNITS, GetConf, GetGeneral, GetBars = profile.Units, profile.GetConf, profile.GetGeneral, profile.GetBars
local UnitTopLabel, ReadBool, SetBool = profile.UnitTopLabel, profile.ReadBool, profile.SetBool
local ReadNumber, SetNumber = profile.ReadNumber, profile.SetNumber
local IsPlayerPowerManagedByClassResources = profile.IsPlayerPowerManagedByClassResources
local W, Schema, ControlRow, SectionCard = controls.Widgets, controls.Schema, controls.Row, controls.Card
local SettingMeta, RegisterControl = controls.SettingMeta, controls.RegisterControl
local UnitSectionShared = controls.Shared
local SetSectionHeaderStatus, CreateSectionNotice = UnitSectionShared.SetSectionHeaderStatus, UnitSectionShared.CreateSectionNotice
local Core, EnsureCooldownWidthObservers = runtime.Core, runtime.EnsureCooldownWidthObservers

local DETACHED_POWER_SHAPE_VALUES = VT("BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal", "ORB", "Orb")
local PLAYER_POWER_SOURCE_VALUES = M.PlayerPowerSourceValues
local NormalizePlayerPowerSource = M.NormalizePlayerPowerSource
-- Power Bar section card geometry. Player gets one extra resource-source row;
-- BuildPower and PowerSectionHeight share these helpers so the detached card
-- always follows the first row without overlap.
local function PowerMainCardHeight(unit) return unit == "player" and 284 or 220 end
local function PowerDetachedCardTop(unit) return -38 - PowerMainCardHeight(unit) - 26 end
local function PowerSectionHeight(unit)
    local isPlayer = unit == "player"
    return math.abs(PowerDetachedCardTop(unit)) + (isPlayer and 340 or 238) + 52
end
local function RefreshClassPowerDetachedState()
    -- Detached player power is influenced by both unitframe and class-resource controls, so
    -- ask the ClassPower page/runtime to recompute enabled state after relevant edits.
    if type(M.RefreshClassPowerDetachedState) == "function" then M.RefreshClassPowerDetachedState() end
end
local NormalizeDetachedPowerShape = Core("MSUF_UF_NormalizeDetachedPowerShape")
local function PreparePowerSwitch(ctx, sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then Schema.Section(sec, unit) end
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local show
    show = ControlRow(ctx, sec, { "sectionSwitch", "show", true, { "Show power bar" },
        get = function() return ReadBool(unit, "showPowerBar", true) end,
        write = { call = SetBool, args = { "MSUF2_POWER_SHOW", { power = true, preview = true } },
            after = function() EnsureCooldownWidthObservers() if show.refreshDetails then show.refreshDetails() end end },
                --[[schema setter: UnitFrameVisuals.8]]
        scope = unit, meta = SettingMeta(ctx, "power.show", unit, "showPowerBar"),
        beforeBind = function(widget)
            W.AttachUnitEditFocus(widget, unit, "powerbar")
        end,
    })
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(show, not (unit == "player" and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit)))
    end)
    return show
end

-- The Power Bar section builds in stages that share one table `pw`: the layout, the read/write helpers,
-- the cards, the visibility and border controls, the detached controls and the gate group that enables them.
local PowerSection = {}
function PowerSection.Layout(pw, sectionW)
    local isPlayer = pw.isPlayer
    pw.mainCardHeight = PowerMainCardHeight(pw.unit)
    pw.detachedCardY = PowerDetachedCardTop(pw.unit)
    pw.detachedCardHeight = isPlayer and 340 or 238
    local leftX = 16
    local cardGap = 28
    local availableW = max(340, sectionW - (leftX * 2))
    local cardW = max(260, min(460, floor((availableW - cardGap) * 0.5)))
    local rightX = leftX + cardW + cardGap
    local rightW = max(240, min(460, sectionW - rightX - leftX))
    local fullW = max(300, min(sectionW - (leftX * 2), cardW + cardGap + rightW))
    local detachedGap = 28
    local detachedLeftW = max(190, min(320, floor((fullW - 32 - detachedGap) * 0.5)))
    local detachedRightX = 16 + detachedLeftW + detachedGap
    local detachedRightW = max(180, min(320, fullW - detachedRightX - 16))
    pw.leftX, pw.cardW, pw.rightX, pw.rightW, pw.fullW = leftX, cardW, rightX, rightW, fullW
    pw.detachedLeftW, pw.detachedRightX, pw.detachedRightW = detachedLeftW, detachedRightX, detachedRightW
    pw.detachedSliderW = max(170, min(300, min(detachedLeftW, detachedRightW) - 42))
end
function PowerSection.Helpers(pw)
    local ctx, unit, isPlayer = pw.ctx, pw.unit, pw.isPlayer
    local powerControls, detachedControls = {}, {}
    pw.powerControls, pw.detachedControls = powerControls, detachedControls
    function pw.AddPowerControl(control)
        M.AppendValues(powerControls, control)
        W.AttachUnitEditFocus(control, unit, "powerbar")
        return control
    end
    function pw.AddDetachedControl(control)
        M.AppendValues(detachedControls, control)
        return pw.AddPowerControl(control)
    end
    local function ResolveDefault(value)
        if type(value) == "function" then return value() end
        return value
    end
    local POWER_OPTS = { power = true, preview = true }
    local DETACHED_POWER_OPTS = { power = true, detachedPowerBar = true, preview = true }
    pw.POWER_OPTS, pw.DETACHED_POWER_OPTS = POWER_OPTS, DETACHED_POWER_OPTS
    pw.POWER_TEXT_OPTS = M.KeySetFromWords "power text preview"
    local function ReadSyncedPlayerPowerOutline()
        if not isPlayer or GetConf(unit).powerBarDetached ~= true then return nil end
        local outline = tonumber(GetBars().detachedPowerBarOutline)
        if outline == nil then return nil end
        return max(0, min(8, floor(outline + 0.5)))
    end
    function pw.ReadPowerBorderEnabled()
        local outline = ReadSyncedPlayerPowerOutline()
        if outline ~= nil then return outline > 0 end
        local conf = GetConf(unit)
        if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
        return GetBars().powerBarBorderEnabled == true
    end
    function pw.ReadPowerBorderThickness()
        local outline = ReadSyncedPlayerPowerOutline()
        if outline ~= nil then return outline end
        local conf = GetConf(unit)
        return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
    end
    function pw.SetSyncedPlayerPowerOutline(outline, reason)
        outline = max(0, min(8, floor((tonumber(outline) or 0) + 0.5)))
        local function Write()
            local conf, bars = GetConf(unit), GetBars()
            local enabled, changed = outline > 0, false
            if conf.powerBarBorderEnabled ~= enabled then conf.powerBarBorderEnabled, changed = enabled, true end
            if enabled and conf.powerBarBorderThickness ~= outline then conf.powerBarBorderThickness, changed = outline, true end
            if bars.detachedPowerBarOutline ~= outline then bars.detachedPowerBarOutline, changed = outline, true end
            if not changed then return false end
            M.RequestUnitDomains(unit, reason, POWER_OPTS)
            RefreshClassPowerDetachedState()
            return true
        end
        if type(M.RunWithHistory) == "function" then
            return M.RunWithHistory("Power bar border", "unit:player:powerBarBorder", Write)
        end
        return Write()
    end
    local function SetManualDetachedPowerWidth(value, reason)
        local conf, bars = GetConf(unit), GetBars()
        local sharedSourceChanged = bars.detachedPowerBarWidthMode ~= nil
        bars.detachedPowerBarWidthMode = nil
        if isPlayer then conf.detachedPowerBarSyncClassPower = false end
        SetNumber(unit, "detachedPowerBarWidth", value, reason, DETACHED_POWER_OPTS)
        if pw.detachedSync and pw.detachedSync.SetChecked then pw.detachedSync:SetChecked(false) end
        EnsureCooldownWidthObservers()
        if sharedSourceChanged then
            M.RequestGeneralDomains(reason, DETACHED_POWER_OPTS)
        end
        RefreshClassPowerDetachedState()
    end
    function pw.BuildPowerControls(parent, addFn, rows)
        return Schema.Build(ctx, parent, rows, {
            beforeBind = addFn,
            bind = function(c, widget, row, kind)
                local key, fallback = row.key or row[2], row[3]
                row.get = function()
                    if row.read then return row.read() end
                    if kind == "toggle" then return ReadBool(unit, key, fallback) end
                    return ReadNumber(unit, key, ResolveDefault(fallback))
                end
                if kind ~= "toggle" and key == "detachedPowerBarWidth" then
                    row.customSetReason = "Disables synchronized width sources before writing the manual detached width."
                    row.companionWrites = { "bars.detachedPowerBarWidthMode", unit .. ".detachedPowerBarSyncClassPower" }
                    row.set = function(value)
                    if kind == "toggle" then
                        SetBool(unit, key, value, row.reason, row.opts or POWER_OPTS)
                        if row.afterSet then row.afterSet() end
                    elseif key == "detachedPowerBarWidth" then
                        return SetManualDetachedPowerWidth(value, row.reason)
                    else return SetNumber(unit, key, value, row.reason, row.opts or POWER_OPTS) end
                end
                else
                    row.write = { call = kind == "toggle" and SetBool or SetNumber,
                        args = { row.reason, row.opts or POWER_OPTS }, returns = kind ~= "toggle",
                        after = kind == "toggle" and row.afterSet or nil } --[[schema setter: UnitFrameVisuals.PowerRows]]
                end
                row.meta = SettingMeta(ctx, "power." .. tostring(key), unit, key)
                row.scope, row.roundStep = unit, kind == "slider"
                row[3] = ResolveDefault(fallback)
                Schema.UnitBinding(c, widget, row, kind)
            end,
        })
    end
end
-- The section notice with its Show Power button, the three cards and the Show switch.
function PowerSection.Cards(pw)
    local ctx, unit, sec, isPlayer = pw.ctx, pw.unit, pw.sec, pw.isPlayer
    local ReadPowerBorderEnabled = pw.ReadPowerBorderEnabled
    local powerNotice, _, powerNoticeButton = CreateSectionNotice(sec, pw.detachedCardY - pw.detachedCardHeight - 12, "Show Power", 126)
    pw.powerNotice, pw.powerNoticeButton = powerNotice, powerNoticeButton
    if powerNoticeButton then
        local powerShortcutMeta
        if not isPlayer then
            powerShortcutMeta = {
                settingKey = unit .. ".showPowerBar",
                command = {
                    kind = "toggle", valueKind = "boolean",
                    get = function() return ReadBool(unit, "showPowerBar", true) end,
                    customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
                        write = { virtual = true,
                            call = SetBool, strictBoolean = true,
                            args = { "MSUF2_POWER_SHOW", { power = true, preview = true } }
                        } --[[schema setter: H4.UnitFrameVisuals.8]],
                },
            }
        else
            powerShortcutMeta = {
                actionKey = "show_player_power_or_open_class_resources",
            }
        end
        RegisterControl(powerNoticeButton, ctx, "power.enable_now", "Show Power", "button",
            not isPlayer and "setting" or "action", powerShortcutMeta)
        powerNoticeButton:SetScript("OnClick", function()
            if isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) then
                if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
                return
            end
            SetBool(unit, "showPowerBar", true, "MSUF2_POWER_SHOW", { power = true, preview = true })
            EnsureCooldownWidthObservers()
            pw.Refresh()
        end)
        Schema.Owned(powerNoticeButton, unit, "power")
    end
    local mainCard = SectionCard(ctx, unit, sec, "power", "mainCard", { "Visibility & Size", nil, pw.leftX, -38, pw.cardW, pw.mainCardHeight })
    local borderCard = SectionCard(ctx, unit, sec, "power", "borderCard",
        { "Border & fill", "Outline and fill behavior.", pw.rightX, -38, pw.rightW, pw.mainCardHeight })
    local detachedCard = SectionCard(ctx, unit, sec, "power", "detachedCard",
        { "Detached placement", "Used only when the power bar is detached from the unit frame.", pw.leftX, pw.detachedCardY, pw.fullW, pw.detachedCardHeight })
    pw.mainCard, pw.borderCard, pw.detachedCard = mainCard, borderCard, detachedCard
    -- Power bar art is configured once on the Bars page. The per-unit keys stay
    -- scope-aware in the UF compiler (conf -> bars -> unit bar texture); they
    -- simply have no control on this page anymore.
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(borderCard, function()
            local refs = { "power.current" }
            if not (GetGeneral().powerBarBgMatchBarColor == true or GetBars().powerBarBgMatchBarColor == true) then
                refs[#refs + 1] = "bar.power_background"
            end
            refs[#refs + 1] = "bar.power_loss"
            if ReadPowerBorderEnabled() then refs[#refs + 1] = "power.border" end
            return refs
        end, {
            title = "Power Bar Colors",
            note = "Color by class applies to all unit power bars. Resource colors apply when it is off. A matched background follows Health.",
            historySource = "menu:unit-power-colors",
            context = function() return { unit = unit } end,
        })
    end
    pw.show = PreparePowerSwitch(ctx, sec, unit)
    pw.show.refreshDetails = function() pw.Refresh() end
    if isPlayer then
        local sourceMeta = SettingMeta(ctx, "power.resource_source", unit, "playerPowerSource")
        sourceMeta.label = M.PlayerPowerSourceSearchLabel
        sourceMeta.historySource = "classpower:playerPowerSource"
        local playerPowerSource = ControlRow(ctx, mainCard, { "dropdown", "playerPowerSource", nil, { "Displayed resource",
            PLAYER_POWER_SOURCE_VALUES, pw.cardW - 72 }, { 16, -132, pw.cardW - 72 },
            get = function() return NormalizePlayerPowerSource(GetConf(unit).playerPowerSource) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", write = {
                source = function() return GetConf(unit) end, convert = NormalizePlayerPowerSource,
                after = function() M.ApplyPlayerPowerSource("MSUF2_PLAYER_POWER_SOURCE") end
            } --[[schema setter: H4.UnitFrameVisuals.9]],
            scope = unit, meta = sourceMeta,
            beforeBind = function(widget)
                widget._msuf2StableSearchLabel = M.PlayerPowerSourceSearchLabel
            end,
        })
        RegisterControl(playerPowerSource, ctx, "power.resource_source",
            M.PlayerPowerSourceSearchLabel, "dropdown", "setting", {
                settingKey = "player.playerPowerSource",
                values = PLAYER_POWER_SOURCE_VALUES,
            })
        if M.AddTooltip then
            M.AddTooltip(playerPowerSource, "Displayed resource",
                M.PlayerPowerSourceTooltip,
                { hook = true, owner = "ANCHOR_RIGHT" })
        end
    end
end
-- The Visibility & Size card and the Border & fill card.
function PowerSection.Main(pw)
    local ctx, unit, isPlayer = pw.ctx, pw.unit, pw.isPlayer
    local mainCard, borderCard, rightW, cardW = pw.mainCard, pw.borderCard, pw.rightW, pw.cardW
    local POWER_OPTS, AddPowerControl = pw.POWER_OPTS, pw.AddPowerControl
    local ReadPowerBorderEnabled, ReadPowerBorderThickness = pw.ReadPowerBorderEnabled, pw.ReadPowerBorderThickness
    local SetSyncedPlayerPowerOutline = pw.SetSyncedPlayerPowerOutline
    ControlRow(ctx, borderCard, { "toggle", "powerBorder", false, { "Power bar border", 16, -62, rightW - 32 },
        get = ReadPowerBorderEnabled,
        companionWrites = { "bars.detachedPowerBarOutline", unit .. ".powerBarBorderThickness" },
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
        if isPlayer then
            local thickness = ReadPowerBorderThickness()
            if value and thickness <= 0 then
                thickness = tonumber(GetConf(unit).powerBarBorderThickness) or 1
                if thickness <= 0 then thickness = 1 end
            end
            SetSyncedPlayerPowerOutline(value and thickness or 0, "MSUF2_POWER_BORDER")
        else
            SetBool(unit, "powerBarBorderEnabled", value, "MSUF2_POWER_BORDER", POWER_OPTS)
        end
        pw.Refresh()
    end,
        scope = unit, meta = SettingMeta(ctx, "power.powerBarBorderEnabled", unit, "powerBarBorderEnabled"),
        beforeBind = AddPowerControl,
    })
    -- Smooth and chunked fill exclude each other: switching one on switches its peer off.
    local function FillToggle(id, key, peerKey, label, y, reason, historyLabel)
        ControlRow(ctx, borderCard, { "toggle", id, false, { label, 16, y, rightW - 32 },
            get = function() return ReadBool(unit, key, false) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                set = function(v) UnitSectionShared.SetFillMode(ctx, unit, "power", key, peerKey, v, reason, historyLabel, POWER_OPTS) end,
            scope = unit, meta = SettingMeta(ctx, "power." .. key, unit, key),
            beforeBind = AddPowerControl,
        })
    end
    FillToggle("smoothFill", "powerSmoothFill", "powerChunkedFill", "Smooth fill", -158, "MSUF2_POWER_SMOOTH", "Smooth power fill")
    FillToggle("chunkedFill", "powerChunkedFill", "powerSmoothFill", "Chunked power loss", -188, "MSUF2_POWER_CHUNKED", "Chunked power loss")
    local attachedPowerFields = pw.BuildPowerControls(mainCard, AddPowerControl, {
        { "slider", "powerBarHeight", 3, { "Power bar height", 1, 20, 1, 300 }, { 16, -76, cardW - 72, "CENTER" },
            reason = "MSUF2_POWER_HEIGHT", read = function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end },
        { "toggle", "embedPowerBarIntoHealth", false, { "Embed into health", 16, isPlayer and -202 or -138, cardW - 32 },
            reason = "MSUF2_POWER_EMBED", read = function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end },
    })
    pw.attachedPowerHeight = attachedPowerFields.powerBarHeight
    pw.embedPower = attachedPowerFields.embedPowerBarIntoHealth
    pw.borderSize = ControlRow(ctx, borderCard, { "slider", "borderSize", 1, { "Border thickness", 0, isPlayer and 8 or 6, 1, 300 }, { 16, -108,
        rightW - 72, "CENTER" },
        get = ReadPowerBorderThickness,
        companionWrites = { "bars.detachedPowerBarOutline", unit .. ".powerBarBorderEnabled" },
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(value)
        if isPlayer then
            SetSyncedPlayerPowerOutline(value, "MSUF2_POWER_BORDER_SIZE")
        else
            SetNumber(unit, "powerBarBorderThickness", value, "MSUF2_POWER_BORDER_SIZE", POWER_OPTS)
        end
        pw.Refresh()
    end,
        scope = unit, meta = SettingMeta(ctx, "power.powerBarBorderThickness", unit, "powerBarBorderThickness"), roundStep = true,
        beforeBind = AddPowerControl,
    })
    ControlRow(ctx, mainCard, { "toggle", "detached", false, { "Detach from frame", 16, isPlayer and -230 or -166, cardW - 32 },
        get = function() return ReadBool(unit, "powerBarDetached", false) end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = Schema.Fields({ unit }, { "detachedPowerBarOffsetX", "detachedPowerBarOffsetY",
                "detachedPowerBarWidth", "detachedPowerBarHeight", "detachedPowerBarFrameLevelOffset",
                "detachedPowerBarSyncClassPower", "detachedPowerBarShape", "detachedPowerOrbSize" }).recordPaths,
            set = function(v)
            local conf = GetConf(unit)
            conf.powerBarDetached = v and true or false
            if conf.powerBarDetached then
                conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
                conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
                conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
                conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
                conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
                if isPlayer and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
                if isPlayer and conf.detachedPowerBarShape == nil then conf.detachedPowerBarShape = "BAR" end
                if isPlayer and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
            end
            EnsureCooldownWidthObservers()
            M.RequestUnitDomains(unit, "MSUF2_POWER_DETACHED", pw.DETACHED_POWER_OPTS)
            pw.Refresh()
            RefreshClassPowerDetachedState()
        end,
        -- Enabling detached power also seeds its geometry and Player sync defaults (same unit root).
        scope = unit, meta = SettingMeta(ctx, "power.detached", unit, "powerBarDetached"),
        beforeBind = AddPowerControl,
    })
end
-- The Detached placement card.
function PowerSection.Detached(pw)
    local ctx, unit, isPlayer, detachedCard = pw.ctx, pw.unit, pw.isPlayer, pw.detachedCard
    local DETACHED_POWER_OPTS, AddDetachedControl = pw.DETACHED_POWER_OPTS, pw.AddDetachedControl
    local detachedLeftW, detachedRightX, detachedRightW, detachedSliderW = pw.detachedLeftW, pw.detachedRightX, pw.detachedRightW, pw.detachedSliderW
    pw.detachedTextToggle = pw.BuildPowerControls(detachedCard, AddDetachedControl, {
        { "toggle", "detachedPowerBarTextOnBar", false, { "Text on detached bar", 16, -62, detachedLeftW },
            reason = "MSUF2_POWER_DETACHED_TEXT", opts = pw.POWER_TEXT_OPTS },
    }).detachedPowerBarTextOnBar
    local sliderTop = -116
    if isPlayer then
        sliderTop = -148
        pw.detachedSync = pw.BuildPowerControls(detachedCard, AddDetachedControl, {
            { "toggle", "sync", true, { "Sync width to Class Resource", 16, -94, detachedLeftW }, key = "detachedPowerBarSyncClassPower",
                reason = "MSUF2_POWER_DETACHED_SYNC", read = function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
                afterSet = function() EnsureCooldownWidthObservers() end, opts = DETACHED_POWER_OPTS },
            { "toggle", "detachedPowerBarAnchorToClassPower", false, { "Anchor to Class Resource", detachedRightX, -94, detachedRightW },
                reason = "MSUF2_POWER_DETACHED_ANCHOR", opts = DETACHED_POWER_OPTS },
        }).sync
    end
    local detachedFields = pw.BuildPowerControls(detachedCard, AddDetachedControl, {
        { "slider", "width", function() return ReadNumber(unit, "width", 250) end, { "Detached width", 20, 800, 1, 300 }, { 16, sliderTop,
            detachedSliderW, "CENTER" }, key = "detachedPowerBarWidth", reason = "MSUF2_POWER_DETACHED_W", opts = DETACHED_POWER_OPTS },
        { "slider", "height", 6, { "Detached height", 2, 80, 1, 300 }, { detachedRightX, sliderTop, detachedSliderW, "CENTER" },
            key = "detachedPowerBarHeight", reason = "MSUF2_POWER_DETACHED_H", opts = DETACHED_POWER_OPTS },
        { "slider", "detachedPowerBarFrameLevelOffset", 6, { "Detached layer", 0, 30, 1, 300 }, { 16, sliderTop - 66, detachedSliderW, "CENTER" },
            reason = "MSUF2_POWER_DETACHED_LAYER", opts = DETACHED_POWER_OPTS },
    })
    pw.detachedWidth, pw.detachedHeight = detachedFields.width, detachedFields.height
    if pw.detachedWidth and M.AddTooltip then
        M.AddTooltip(pw.detachedWidth, "Detached width",
            "Changing this value selects Manual width. For Player, it also turns off Sync width to Class Resource so the new width takes effect immediately.",
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    if isPlayer then
        pw.detachedShape = ControlRow(ctx, detachedCard, { "dropdown", "detachedShape", "BAR", { "Detached shape", DETACHED_POWER_SHAPE_VALUES,
            detachedSliderW }, { detachedRightX, sliderTop - 66, detachedSliderW },
            get = function()
                return NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape)
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { unit .. ".detachedPowerOrbSize" },
            set = function(v)
                v = NormalizeDetachedPowerShape(v)
                local conf = GetConf(unit)
                conf.detachedPowerBarShape = v
                if v == "ORB" and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
                EnsureCooldownWidthObservers()
                M.RequestUnitDomains(unit, "MSUF2_POWER_DETACHED_SHAPE", DETACHED_POWER_OPTS)
                pw.Refresh()
                RefreshClassPowerDetachedState()
            end,
            scope = unit, meta = SettingMeta(ctx, "power.detached_shape", unit, "detachedPowerBarShape"),
            beforeBind = AddDetachedControl,
        })
        if M.AddTooltip then
            M.AddTooltip(pw.detachedShape, "Independent Powerbar Shape",
                "Changes only Player power. Class Resources keep their own shape setting. "
                .. "Round and Crystal fill horizontally; Orb fills bottom-to-top.", { hook = true, owner = "ANCHOR_RIGHT" })
        end
        pw.orbSize = pw.BuildPowerControls(detachedCard, AddDetachedControl, { { "slider", "detachedPowerOrbSize", 54, { "Orb size", 20, 160, 1, 300 },
            { 16, sliderTop - 132, detachedSliderW, "CENTER" }, reason = "MSUF2_POWER_DETACHED_ORB_SIZE",
            opts = DETACHED_POWER_OPTS } })["detachedPowerOrbSize"]
    end
end
-- Enables the controls from the Show switch, the detach switch and the shape; Class Resources can lock the section.
function PowerSection.Gates(pw)
    local ctx, unit, sec, isPlayer, show = pw.ctx, pw.unit, pw.sec, pw.isPlayer, pw.show
    local powerNotice, powerNoticeButton = pw.powerNotice, pw.powerNoticeButton
    local powerControls, detachedControls, detachedTextToggle = pw.powerControls, pw.detachedControls, pw.detachedTextToggle
    local borderSize, detachedSync, detachedWidth, detachedHeight = pw.borderSize, pw.detachedSync, pw.detachedWidth, pw.detachedHeight
    local detachedShape, orbSize = pw.detachedShape, pw.orbSize
    local ReadPowerBorderEnabled = pw.ReadPowerBorderEnabled
    local function PowerOn() return ReadBool(unit, "showPowerBar", true) end
    local function DetachedOn() return PowerOn() and ReadBool(unit, "powerBarDetached", false) end
    local function OrbSelected() return isPlayer and NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape) == "ORB" end
    local function ClassManaged() return isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) and true or false end
    -- While Class Resources owns the Player power bar the section notice
    -- explains the lock, so these hover reasons stay silent then.
    local turnOn = W.TurnOnReason
    pw.Refresh = pw.Refresh(M.BindGateGroup(ctx, nil, {
        { enable = { show }, controls = powerControls, on = PowerOn,
            reason = turnOn("Show power bar", function() return PowerOn() or ClassManaged() end) },
        { controls = detachedControls, on = DetachedOn,
            reason = turnOn("Detach from frame", function() return DetachedOn() or ClassManaged() end) },
        { controls = { pw.attachedPowerHeight, pw.embedPower }, on = function() return PowerOn() and not DetachedOn() end },
        { controls = borderSize, on = function() return PowerOn() and ReadPowerBorderEnabled() end },
        -- Detached width/height/sync exist only when a detached card was built; the `when`
        -- guard keeps the optional Player-only detached controls safe.
        { controls = detachedSync, when = function() return detachedSync ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedWidth, when = function() return detachedWidth ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedHeight, when = function() return detachedHeight ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedShape, when = function() return detachedShape ~= nil end, on = DetachedOn },
        { controls = orbSize, when = function() return orbSize ~= nil end, on = function() return DetachedOn() and OrbSelected() end },
    }, {
        -- Player power managed by Class Resources force-disables the whole group, overriding
        -- the rows above. Then update the section notice and header status.
        override = function(_, setEnabled)
            if ClassManaged() then
                setEnabled(powerControls, false)
                setEnabled(detachedControls, false)
                if detachedTextToggle then setEnabled(detachedTextToggle, DetachedOn()) end
                setEnabled({ show }, false)
                setEnabled(borderSize, false)
            end
        end,
        also = function()
            if ClassManaged() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Class Resources") or "Class Resources") end
                powerNotice:SetMessage(M.Tr("Player power bar is connected to Class Resources. "
                    .. "Manage detached power and power text in Class Resources > Detached Power Bar."), "warning")
                powerNotice:Show()
            elseif not PowerOn() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:SetMessage(M.Format("%s power bar is hidden. Turn it on to configure size, embed, or detached settings.",
                    UnitTopLabel(unit)), "warning")
                powerNotice:Show()
            else
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", PowerSectionHeight(unit), false)
    local pw = { ctx = ctx, unit = unit, sec = sec, isPlayer = unit == "player", Refresh = M.RefreshProxy() }
    PowerSection.Layout(pw, (sec and sec._msuf2Width) or (ctx and ctx.width) or 720)
    PowerSection.Helpers(pw)
    PowerSection.Cards(pw)
    PowerSection.Main(pw)
    PowerSection.Detached(pw)
    PowerSection.Gates(pw)
end

return BuildPower, PreparePowerSwitch, PowerSectionHeight
end

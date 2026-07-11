-- Assistant Dashboard status and indicator selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; keeps cold selector routing isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

function A.DashboardRegistry.BuildStatusSelectors(ctx)
    if type(ctx) ~= "table" then return nil end

    local ARef = ctx.A or A
    local NormalizeKey = ctx.NormalizeKey
    local ResolveUnitKey = ctx.ResolveUnitKey
    local ResolveGroupScope = ctx.ResolveGroupScope
    local PersistScalar = ctx.PersistScalar
    local PersistTableValue = ctx.PersistTableValue
    local OpenMenuPage = ctx.OpenMenuPage
    local UnitLabel = ctx.UnitLabel
    local GroupLabel = ctx.GroupLabel
    local UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS or {}

    if type(NormalizeKey) ~= "function" or type(ResolveUnitKey) ~= "function" then return nil end
    if type(ResolveGroupScope) ~= "function" or type(PersistScalar) ~= "function" then return nil end
    if type(PersistTableValue) ~= "function" or type(OpenMenuPage) ~= "function" then return nil end
    if type(UnitLabel) ~= "function" or type(GroupLabel) ~= "function" then return nil end

    local STATUS_TAB_LABELS = {
        basic = "Basic",
        advanced = "Advanced",
    }

    local function DisplayEnumLabel(label, value)
        if ARef and type(ARef.DisplayEnumLabel) == "function" then return ARef.DisplayEnumLabel(label, value) end
        if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(value or "") then return tostring(label) end
        local parser = ARef and ARef.Parser
        if parser and type(parser.ValueDisplay) == "function" then
            return parser.ValueDisplay({ type = "enum" }, value)
        end
        return tostring(value or "")
    end

    local GROUP_STATUS_ICON_SPECS = {
        roleIcon = "Role Icon",
        leaderIcon = "Leader Icon",
        assistIcon = "Assist Icon",
        raidMarker = "Raid Marker",
        readyCheckIcon = "Ready Check Icon",
        summonIcon = "Summon Icon",
        resurrectIcon = "Resurrection Icon",
        pvpIcon = "PvP Flag Icon",
        phaseIcon = "Phase Icon",
        statusText = "Dead Text",
        statusGhostText = "Ghost Text",
        statusAFKText = "AFK Text",
    }

    local GROUP_STATUS_ICON_ALIASES = {
        roleicon = "roleIcon",
        roleindicator = "roleIcon",
        leadericon = "leaderIcon",
        leaderindicator = "leaderIcon",
        assisticon = "assistIcon",
        assistanticon = "assistIcon",
        assistindicator = "assistIcon",
        raidmarker = "raidMarker",
        targetmarker = "raidMarker",
        readycheck = "readyCheckIcon",
        readycheckicon = "readyCheckIcon",
        summonicon = "summonIcon",
        summonindicator = "summonIcon",
        resurrecticon = "resurrectIcon",
        resurrectionicon = "resurrectIcon",
        rezicon = "resurrectIcon",
        pvpflag = "pvpIcon",
        pvpicon = "pvpIcon",
        pvpindicator = "pvpIcon",
        pvpstatus = "pvpIcon",
        phaseicon = "phaseIcon",
        phasingicon = "phaseIcon",
        statustext = "statusText",
        deadtext = "statusText",
        ghosttext = "statusGhostText",
        afktext = "statusAFKText",
        dndtext = "statusAFKText",
    }

    local function ResolveStatusTab(tab)
        tab = NormalizeKey(tab)
        if STATUS_TAB_LABELS[tab] then return tab end
        return nil
    end

    local function ResolveGroupStatusIcon(icon)
        local key = NormalizeKey(icon)
        local canonical = GROUP_STATUS_ICON_ALIASES[key]
        if canonical then return canonical, GROUP_STATUS_ICON_SPECS[canonical] end
        for value, label in pairs(GROUP_STATUS_ICON_SPECS) do
            if key == NormalizeKey(value) or key == NormalizeKey(label) then return value, label end
        end
        return nil
    end

    local function FocusUnitStatus(status)
        if type(_G.MSUF_UFPreview_SelectStatusIcon) == "function" then
            _G.MSUF_UFPreview_SelectStatusIcon(status)
        end
    end

    local function SetUnitStatusSelector(args)
        local unit = ResolveUnitKey(args and args.unit)
        local tab = ResolveStatusTab(args and args.tab)
        local spec = unit and ARef.ResolveUnitStatusSpec and ARef.ResolveUnitStatusSpec(unit, args and (args.status or args.text)) or nil
        if not unit then return false, "Which unit status menu do you want me to select?" end
        if not (tab or spec) then return false, "Which unit status indicator do you want me to select?" end
        if tab then PersistTableValue("unitStatusTabSelection", unit, tab) end
        if spec then
            PersistTableValue("unitStatusSelection", unit, spec.value)
            FocusUnitStatus(spec.value)
        end
        OpenMenuPage(UNIT_PAGE_KEYS[unit])
        if spec then
            return true, "Selected " .. UnitLabel(unit) .. " " .. DisplayEnumLabel(spec.label, spec.value) .. " status indicator."
        end
        return true, "Selected " .. UnitLabel(unit) .. " " .. STATUS_TAB_LABELS[tab] .. " status tab."
    end

    local function SetGroupStatusSelector(args)
        local scope = ResolveGroupScope(args and args.scope) or "party"
        local tab = ResolveStatusTab(args and args.tab)
        local icon, label = ResolveGroupStatusIcon(args and (args.icon or args.text))
        if not (tab or icon) then return false, "Which group status indicator do you want me to select?" end
        PersistScalar("gfScope", scope)
        if tab then PersistTableValue("gfStatusIconTabSelection", scope, tab) end
        if icon then PersistScalar("gfStatusIconSelection", icon) end
        OpenMenuPage("gf_indicators")
        if icon then return true, "Selected " .. GroupLabel(scope) .. " " .. DisplayEnumLabel(label, icon) .. " indicator." end
        return true, "Selected " .. GroupLabel(scope) .. " " .. STATUS_TAB_LABELS[tab] .. " status icon tab."
    end

    local function SetGroupSpellSelector(args)
        local scope = ResolveGroupScope(args and args.scope) or "party"
        local spec = ARef.ResolveGroupSpellSpec and ARef.ResolveGroupSpellSpec(args and (args.spec or args.text)) or nil
        local aura, resolvedSpec, display
        if type(ARef.ResolveGroupSpellAura) == "function" then
            aura, resolvedSpec, display = ARef.ResolveGroupSpellAura(spec, tostring(args and (args.aura or args.text) or ""))
        end
        spec = spec or resolvedSpec
        if not (spec or aura) then return false, "Which spell indicator do you want me to select?" end
        PersistScalar("gfScope", scope)
        if spec then PersistTableValue("gfSpellMultiSpecSelection", scope, spec) end
        if aura then PersistTableValue("gfSpellIndicatorSelection", scope, aura) end
        OpenMenuPage("gf_auras")
        local specLabel = spec and ARef.GroupSpellSpecDisplay and ARef.GroupSpellSpecDisplay(spec) or spec
        if aura then
            return true, "Selected " .. GroupLabel(scope) .. " " .. DisplayEnumLabel(display, aura) .. " spell indicator."
        end
        return true, "Selected " .. GroupLabel(scope) .. " " .. DisplayEnumLabel(specLabel, spec) .. " spell indicator spec."
    end

    local function SetGroupCornerSelector(args)
        local scope = ResolveGroupScope(args and args.scope) or "party"
        local slot = ARef.ResolveGroupCornerSlot and ARef.ResolveGroupCornerSlot(args and (args.slot or args.text)) or nil
        if not slot then return false, "Which corner editor slot do you want me to select?" end
        PersistScalar("gfScope", scope)
        PersistScalar("gfCornerSlotSelection", slot.key or slot.value)
        OpenMenuPage("gf_indicators")
        return true, "Selected " .. GroupLabel(scope) .. " " .. DisplayEnumLabel(slot.label or slot.text, slot.key or slot.value) .. " corner editor slot."
    end

    return {
        SetGroupCornerSelector = SetGroupCornerSelector,
        SetGroupSpellSelector = SetGroupSpellSelector,
        SetGroupStatusSelector = SetGroupStatusSelector,
        SetUnitStatusSelector = SetUnitStatusSelector,
    }
end

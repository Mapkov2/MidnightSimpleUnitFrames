local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Diagnostics registry domain. Shared helpers live in MSUF_AssistantRegistry_Core.lua.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB or function() return (_G.MSUF_DB and _G.MSUF_DB.bars) or {} end
local UnitDB = C.UnitDB
local GroupDB = C.GroupDB
local AuraSharedBool = C.AuraSharedBool
local AuraUnitEnabled = C.AuraUnitEnabled
local GFAuraLaneShown = C.GFAuraLaneShown
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeRead = C.GlobalScopeRead
local CASTBAR_KEYS = C.CASTBAR_KEYS

local function ActiveProfileName()
    if A and type(A.ActiveProfileName) == "function" then return A.ActiveProfileName() end
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

A.Workflow = A.Workflow or {}
A.Workflow.SupportLinks = {
    discord = { title = "Discord", parts = { "h", "tt", "ps", "://discord.gg/2Gf9b2Wprz" } },
    patreon = { title = "Patreon", parts = { "h", "tt", "ps", "://www.patreon.com/cw/MidnightSimpleUnitframes" } },
    paypal = { title = "PayPal", parts = { "h", "tt", "ps", "://www.paypal.com/ncp/payment/H3N2P87S53KBQ" } },
    kofi = { title = "Ko-fi", parts = { "h", "tt", "ps", "://ko-fi.com/midnightsimpleunitframes#linkModal" } },
    github = { title = "GitHub", parts = { "h", "tt", "ps", "://github.com/Mapkov2/MidnightSimpleUnitFrames" } },
}

function A.Workflow.SupportURL(key)
    local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
    if type(spec) ~= "table" or type(spec.parts) ~= "table" then return nil end
    return table.concat(spec.parts, "")
end

function A.Workflow.CopyText(title, value, help)
    if type(value) ~= "string" or value == "" then return false end
    if type(_G.MSUF_ShowCopyLink) == "function" then
        _G.MSUF_ShowCopyLink(title or "MSUF", value)
        return true
    end
    if A and type(A.ShowLargeTextPanel) == "function" then
        A.ShowLargeTextPanel({
            kind = "export",
            title = title or "MSUF",
            help = help or "Copy this value.",
            text = value,
            status = "Press Select all, then Ctrl+C.",
        })
        return true
    end
    return false
end

function A.Workflow.SupportSummaryText()
    local lines = { "MSUF support links:" }
    for _, key in ipairs({ "discord", "patreon", "paypal", "kofi", "github" }) do
        local spec = A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if spec and value then lines[#lines + 1] = "- " .. tostring(spec.title) .. ": " .. value end
    end
    return table.concat(lines, "\n")
end

function A.Workflow.StatusText()
    local lines = {}
    local version = (type(_G.GetAddOnMetadata) == "function" and _G.GetAddOnMetadata(addonName, "Version"))
        or (MSUF and (MSUF.version or MSUF.Version))
        or M.version
        or M.VERSION
        or "unknown"
    local locale = type(_G.GetLocale) == "function" and _G.GetLocale() or "unknown"
    local combat = ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and "yes" or "no"
    local edit = "unknown"
    if M and type(M.IsMSUFEditModeActive) == "function" then
        edit = M.IsMSUFEditModeActive(true) and "on" or "off"
    elseif _G.MSUF_UnitEditModeActive ~= nil then
        edit = _G.MSUF_UnitEditModeActive == true and "on" or "off"
    end
    lines[#lines + 1] = "MSUF status"
    lines[#lines + 1] = "Version: " .. tostring(version)
    lines[#lines + 1] = "Locale: " .. tostring(locale)
    lines[#lines + 1] = "Active page: " .. tostring((M and M.activeKey) or "unknown")
    lines[#lines + 1] = "Active profile: " .. ActiveProfileName()
    lines[#lines + 1] = "Combat lockdown: " .. combat
    lines[#lines + 1] = "Edit mode: " .. edit
    lines[#lines + 1] = "Assistant registry: " .. tostring(#(Registry.settings or {})) .. " settings, " .. tostring(#(Registry.actions or {})) .. " actions"
    lines[#lines + 1] = "Queued Assistant changes: " .. tostring(type(A.queuedPlans) == "table" and #A.queuedPlans or 0)
    return table.concat(lines, "\n")
end

function A.Workflow.HelpText()
    return table.concat({
        "Assistant command examples:",
        "- show profile summary",
        "- export colors profile",
        "- browse Wago profiles",
        "- start edit mode",
        "- hide player name",
        "- move target 10 down",
        "- copy player layout to target",
        "- reset target position",
        "- diagnose target castbar",
        "- diagnose raid frames",
        "- what can I change here",
        "- copy Discord link",
        "- show MSUF status",
    }, "\n")
end

local function LowOpacity(value)
    value = tonumber(value)
    return value ~= nil and value <= 0.05
end

local function SettingPreviewLines(settings, limit)
    local lines = {}
    local seen = {}
    limit = tonumber(limit) or 8
    for i = 1, #(settings or {}) do
        local setting = settings[i]
        local label = setting and setting.label
        if type(label) == "string" and label ~= "" and not seen[label] then
            lines[#lines + 1] = "- " .. label
            seen[label] = true
            if #lines >= limit then break end
        end
    end
    return lines
end

local function ScopeHelpExamples(frameType, unit, group, page)
    if frameType == "castbar" or page == "opt_castbar" then
        return {
            "show target castbar",
            "move player castbar 20 down",
            "set castbar height to 28",
            "reset castbar colors",
            "diagnose target castbar",
        }
    end
    if frameType == "group" or frameType == "groupAura" or group then
        local scope = group or "raid"
        return {
            "show " .. scope .. " group frames",
            "make " .. scope .. " width 90",
            "set " .. scope .. " growth right",
            "blacklist raid buffs category for " .. scope .. " buffs",
            "diagnose " .. scope .. " frames",
        }
    end
    if frameType == "profiles" or page == "profiles" then
        return {
            "show profile summary",
            "export current profile",
            "import profile",
            "copy current profile to Backup",
            "switch profile to Healer",
        }
    end
    if frameType == "aura" or page == "auras3" then
        return {
            "show player buffs",
            "set target debuff size 32",
            "apply clean aura preset",
            "blacklist spell 12345 for player auras",
            "show raid buff category blacklist",
        }
    end
    local subject = unit or "player"
    return {
        "show " .. subject .. " frame",
        "hide " .. subject .. " name",
        "make " .. subject .. " width 300",
        "move " .. subject .. " 20 down",
        "reset " .. subject .. " position",
    }
end

function A.Workflow.ScopeHelpText(args)
    args = args or {}
    local frameType = args.frameType
    local unit = args.unit
    local group = args.group
    local page = args.page
    local label = args.label or (unit and UNIT_LABELS[unit]) or (group and UNIT_LABELS[group]) or frameType or page or "current area"
    local filter = {}
    if unit then filter.unit = unit end
    if group then filter.unit = group end
    if frameType then filter.frameType = frameType end
    local settings = Registry and Registry.FindSettings and Registry:FindSettings(filter) or {}
    local lines = { "Assistant controls for " .. tostring(label) .. ":" }
    if #settings > 0 then
        lines[#lines + 1] = "Registered settings: " .. tostring(#settings)
        local preview = SettingPreviewLines(settings, 8)
        for i = 1, #preview do lines[#lines + 1] = preview[i] end
    else
        lines[#lines + 1] = "No narrow setting list matched, but the Assistant can still navigate and run known actions."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Try:"
    local examples = ScopeHelpExamples(frameType, unit, group, page)
    for i = 1, #examples do lines[#lines + 1] = "- " .. examples[i] end
    return table.concat(lines, "\n")
end

local function UnitFrameDiagnosticText(unit)
    unit = UNIT_LABELS[unit] and unit or "player"
    local conf = UnitDB(unit)
    local label = UNIT_LABELS[unit] or unit
    local issues = {}
    if conf.enabled == false then
        issues[#issues + 1] = label .. " frame is disabled. Say 'show " .. tostring(unit) .. " frame' to enable it."
    end
    local width = tonumber(conf.width)
    local height = tonumber(conf.height)
    if width ~= nil and width < 10 then
        issues[#issues + 1] = label .. " width is extremely small. Say 'make " .. tostring(unit) .. " width 275'."
    end
    if height ~= nil and height < 6 then
        issues[#issues + 1] = label .. " height is extremely small. Say 'make " .. tostring(unit) .. " height 40'."
    end
    if LowOpacity(conf.alphaInCombat) and LowOpacity(conf.alphaOutOfCombat) then
        issues[#issues + 1] = label .. " opacity is near zero in and out of combat. Open Alpha settings or set opacity back to 100%."
    elseif LowOpacity(conf.alphaOutOfCombat) then
        issues[#issues + 1] = label .. " out-of-combat opacity is near zero. It may disappear while not fighting."
    elseif LowOpacity(conf.alphaInCombat) then
        issues[#issues + 1] = label .. " in-combat opacity is near zero. It may disappear while fighting."
    end
    if unit == "pet" then
        issues[#issues + 1] = "Pet frames also require an active pet; this diagnostic only checks MSUF settings."
    elseif unit == "targettarget" then
        issues[#issues + 1] = "Target of Target only appears when your target has a target."
    elseif unit == "focustarget" then
        issues[#issues + 1] = "Focus Target only appears when your focus has a target."
    elseif unit == "boss" then
        issues[#issues + 1] = "Boss frames also require boss units from the encounter or preview context."
    end
    if #issues == 0 then
        return label .. " frame is enabled in MSUF and has no obvious hidden-size or opacity problem. Open " .. label .. " settings or Edit Mode to inspect position."
    end
    return table.concat(issues, "\n")
end

local function GroupFrameDiagnosticText(scope)
    scope = scope == "mythicraid" and "mythicraid" or (scope == "raid" and "raid" or "party")
    local conf = GroupDB(scope)
    local label = UNIT_LABELS[scope] or scope
    local issues = {}
    if conf.enabled ~= true then
        issues[#issues + 1] = label .. " Group Frames are disabled. Say 'show " .. tostring(scope) .. " group frames' to enable them."
    end
    if scope == "party" and conf.showSolo ~= true then
        issues[#issues + 1] = "Party frames are set to hide while solo. This is normal outside a group unless Show While Solo is enabled."
    end
    local width = tonumber(conf.width)
    local height = tonumber(conf.height)
    if width ~= nil and width < 10 then
        issues[#issues + 1] = label .. " frame width is extremely small. Say 'make " .. tostring(scope) .. " width 120'."
    end
    if height ~= nil and height < 6 then
        issues[#issues + 1] = label .. " frame height is extremely small. Say 'make " .. tostring(scope) .. " height 40'."
    end
    if LowOpacity(conf.alphaCurrentInCombat) and LowOpacity(conf.alphaCurrentOutOfCombat) then
        issues[#issues + 1] = label .. " opacity is near zero in and out of combat. Set group opacity back to 100%."
    elseif LowOpacity(conf.alphaCurrentOutOfCombat) then
        issues[#issues + 1] = label .. " out-of-combat opacity is near zero. It may disappear while not fighting."
    elseif LowOpacity(conf.alphaCurrentInCombat) then
        issues[#issues + 1] = label .. " in-combat opacity is near zero. It may disappear while fighting."
    end
    if conf.hideInClientScene == true then
        issues[#issues + 1] = label .. " frames hide during client scenes by setting; that only applies during those scenes."
    end
    if #issues == 0 then
        return label .. " Group Frames are enabled and have no obvious hidden-size or opacity problem. Open Group Frames or Edit Mode to inspect position and current group context."
    end
    return table.concat(issues, "\n")
end

local function CountKeys(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

local function CharProfileState()
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local chars = global and type(global.char) == "table" and global.char or nil
    local key
    if type(_G.MSUF_GetCharKey) == "function" then
        key = _G.MSUF_GetCharKey()
    elseif type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
        key = tostring(_G.UnitName("player") or "Player") .. "-" .. tostring(_G.GetRealmName() or "Realm")
    end
    local char = key and chars and chars[key] or nil
    return key, type(char) == "table" and char or nil
end

local function ProfileDiagnosticText()
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local profiles = global and type(global.profiles) == "table" and global.profiles or nil
    local active = ActiveProfileName()
    local activeTable = profiles and profiles[active] or nil
    local charKey, char = CharProfileState()
    local map = char and type(char.specProfileMap) == "table" and char.specProfileMap or nil
    local brokenSpecs = 0
    if map and profiles then
        for _, profileName in pairs(map) do
            if type(profileName) == "string" and type(profiles[profileName]) ~= "table" then brokenSpecs = brokenSpecs + 1 end
        end
    end

    local lines = {
        "Profile diagnostic:",
        "Active profile: " .. tostring(active),
        "Profiles loaded: " .. tostring(CountKeys(profiles)),
        "Active profile table: " .. (type(activeTable) == "table" and "ok" or "missing"),
        "Active DB reference: " .. ((type(activeTable) == "table" and _G.MSUF_DB == activeTable) and "ok" or "check"),
        "Character profile key: " .. tostring(charKey or "unknown"),
        "Spec auto-switch: " .. ((char and char.specAutoSwitch == true) and "on" or "off"),
        "Spec mappings: " .. tostring(CountKeys(map)),
    }
    if brokenSpecs > 0 then
        lines[#lines + 1] = "Broken spec mappings: " .. tostring(brokenSpecs) .. " point to missing profiles."
    end
    lines[#lines + 1] = "Profile staging:"
    lines[#lines + 1] = "- Create/copy name: " .. tostring((M and M.profileCreateCopyName ~= "" and M.profileCreateCopyName) or "empty")
    lines[#lines + 1] = "- Export kind: " .. tostring((M and M.profileExportKind) or "all")
    lines[#lines + 1] = "- Import string: " .. (((M and type(M.profileImportString) == "string" and M.profileImportString ~= "") and "present") or "empty")
    lines[#lines + 1] = "- Import as new profile: " .. ((M and M.profileImportCreateNew == true) and "on" or "off")
    lines[#lines + 1] = "Available helpers:"
    lines[#lines + 1] = "- create/switch/copy/delete/rename: "
        .. ((type(_G.MSUF_CreateProfile) == "function") and "create " or "")
        .. ((type(_G.MSUF_SwitchProfile) == "function") and "switch " or "")
        .. ((type(_G.MSUF_CopyProfile) == "function") and "copy " or "")
        .. ((type(_G.MSUF_DeleteProfile) == "function") and "delete " or "")
        .. ((type(_G.MSUF_RenameProfile) == "function") and "rename" or "")
    lines[#lines + 1] = "- import/export: "
        .. ((type(_G.MSUF_ImportFromString) == "function") and "import " or "")
        .. ((type(_G.MSUF_ExportSelectionToString) == "function") and "export" or "")
    if type(activeTable) ~= "table" then
        lines[#lines + 1] = "Next safe fix: switch to an existing profile or create/copy a new profile before importing."
    elseif brokenSpecs > 0 then
        lines[#lines + 1] = "Next safe fix: clear or reassign the broken spec profile mappings."
    else
        lines[#lines + 1] = "No obvious profile storage problem was found."
    end
    return table.concat(lines, "\n")
end

local function ClassPowerDiagnosticText()
    local bars = BarsDB()
    local player = UnitDB("player")
    local issues = {}
    if bars.showClassPower == false then
        issues[#issues + 1] = "Class Resources are disabled. Say 'turn on class resources' to enable them; reload may be required."
    end
    if tonumber(bars.classPowerHeight) ~= nil and tonumber(bars.classPowerHeight) < 1 then
        issues[#issues + 1] = "Class Resource height is extremely small. Say 'set class resource height to 4'."
    end
    if (bars.classPowerWidthMode == "custom" or bars.classPowerWidthMode == "manual") and (tonumber(bars.classPowerWidth) or 0) <= 0 then
        issues[#issues + 1] = "Class Resource width mode is custom but width is zero. Set a width or use player/cooldown width mode."
    end
    if LowOpacity(bars.classPowerFilledAlpha) and LowOpacity(bars.classPowerEmptyAlpha) then
        issues[#issues + 1] = "Filled and empty Class Resource opacity are both near zero."
    elseif LowOpacity(bars.classPowerFilledAlpha) then
        issues[#issues + 1] = "Filled Class Resource opacity is near zero."
    end
    if bars.classPowerHideOOC == true then
        issues[#issues + 1] = "Class Resources hide out of combat by setting."
    end
    if bars.classPowerHideWhenFull == true and bars.classPowerHideWhenEmpty == true then
        issues[#issues + 1] = "Class Resources are configured to hide when full and when empty."
    end
    if player.powerBarDetached == true then
        issues[#issues + 1] = "Player power bar is detached. If it should align with Class Resources, check detached power sync/anchor settings."
    end

    local lines = {
        "Class Resources diagnostic:",
        "Enabled: " .. (bars.showClassPower == false and "off" or "on"),
        "Height: " .. tostring(bars.classPowerHeight or "default"),
        "Width mode: " .. tostring(bars.classPowerWidthMode or "player"),
        "Width: " .. tostring(bars.classPowerWidth or "auto"),
        "Hide rules: OOC=" .. tostring(bars.classPowerHideOOC == true) .. ", full=" .. tostring(bars.classPowerHideWhenFull == true) .. ", empty=" .. tostring(bars.classPowerHideWhenEmpty == true),
    }
    if #issues == 0 then
        lines[#lines + 1] = "No obvious Class Resource settings problem was found. Some specs have no class-resource bar until the relevant resource exists."
    else
        for i = 1, #issues do lines[#lines + 1] = issues[i] end
    end
    return table.concat(lines, "\n")
end

local function DashboardSetupDiagnosticText()
    local ctx = A.GetContext and A.GetContext() or {}
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local dashRoot = global and type(global.global) == "table" and global.global or nil
    local dash = dashRoot and type(dashRoot.dashboard) == "table" and dashRoot.dashboard or {}
    local lines = {
        "Dashboard setup diagnostic:",
        "Active page: " .. tostring((M and M.activeKey) or "unknown"),
        "Open/select helper: " .. (((M and type(M.Open) == "function") or (M and type(M.SelectPage) == "function")) and "available" or "missing"),
        "Assistant page stack: " .. tostring(A.Workflow and type(A.Workflow.navStack) == "table" and #A.Workflow.navStack or 0),
        "Pending confirmation: " .. tostring(A.pendingConfirmation ~= nil),
        "Pending choices: " .. tostring(type(A.pendingChoices) == "table" and #A.pendingChoices or 0),
        "Pending flow: " .. tostring(type(A.pendingFlow) == "table" and (A.pendingFlow.label or A.pendingFlow.kind) or "none"),
        "Guided setup: " .. tostring(type(ctx.guidedSetup) == "table" and "active" or "inactive"),
        "Recovery panel: " .. tostring(dash.dashboardRecoveryOpen == true or (M and M.dashboardRecoveryOpen == true)),
        "Scaling panel: " .. tostring(dash.dashboardScalingOpen == true or (M and M.dashboardScalingOpen == true)),
        "Changelog panel: " .. tostring(dash.dashboardChangelogOpen == true or (M and M.dashboardChangelogOpen == true)),
        "Search intro seen: " .. tostring(M and M.searchIntroSeen == true),
    }
    if not (M and (type(M.Open) == "function" or type(M.SelectPage) == "function")) then
        lines[#lines + 1] = "Next safe fix: open Menu2 once so navigation helpers are initialized."
    elseif A.pendingConfirmation or (type(A.pendingChoices) == "table" and #A.pendingChoices > 0) or type(A.pendingFlow) == "table" then
        lines[#lines + 1] = "Next safe fix: answer the pending prompt or say 'cancel workflow'."
    else
        lines[#lines + 1] = "No obvious Dashboard setup blocker was found."
    end
    return table.concat(lines, "\n")
end

local GUIDED_SETUP_STEPS = {
    {
        key = "frame_size",
        title = "Main Frame Size",
        page = "uf_player",
        goal = "Start with readable Player and Target frames before tuning details.",
        body = "A solid baseline is Player width 275 and height 40, then Target can copy the same size.",
        examples = {
            "make player width 275",
            "make player height 40",
            "copy player layout to target",
        },
    },
    {
        key = "placement",
        title = "Player And Target Placement",
        page = "uf_player",
        goal = "Put the main frames where your eyes naturally rest in combat.",
        body = "Use Edit Mode for broad placement. Small nudges are easier to control than one big jump.",
        examples = {
            "start edit mode",
            "move player 20 left",
            "move target 20 right",
        },
    },
    {
        key = "castbars",
        title = "Castbars",
        page = "opt_castbar",
        goal = "Make important casts obvious without crowding the center.",
        body = "Target castbar is usually the first one to verify. After that, add Player, Focus, or Boss castbars only if you need them.",
        examples = {
            "show target castbar",
            "move target castbar 20 down",
            "set castbar height to 28",
        },
    },
    {
        key = "text",
        title = "Text Visibility",
        page = "uf_player",
        goal = "Keep the text you actually read and remove repeated noise.",
        body = "Clean layouts usually keep names and one clear health value, then reduce redundant power or HP text.",
        examples = {
            "hide player power text",
            "show target name",
            "set global font size 14",
        },
    },
    {
        key = "power",
        title = "Power Bars And Resources",
        page = "opt_bars",
        goal = "Make resource information clear without mistaking it for class resources.",
        body = "Power Bar controls live on unit and group frames. Class Resources are separate global controls.",
        examples = {
            "set target power bar height to 8",
            "detach target power bar",
            "turn on class resources",
        },
    },
    {
        key = "group_frames",
        title = "Group Frames",
        page = "gf_layout",
        goal = "Build Party and Raid after the main frames feel stable.",
        body = "Group frames need dense but readable sizing. Start with Party/Raid visibility, then tune width, text, and indicators.",
        examples = {
            "show party group frames",
            "make raid width 80",
            "turn off ready check symbol for all group frames",
        },
    },
    {
        key = "boss_frames",
        title = "Boss Frames And Final Check",
        page = "uf_boss",
        goal = "Finish with encounter information and a quick diagnostic pass.",
        body = "Boss frames and boss castbars should be readable without covering your main layout.",
        examples = {
            "show boss frame",
            "show boss castbar",
            "diagnose boss frames",
        },
    },
}

local function GuidedSetupStyleLabel(style)
    style = tostring(style or ""):lower()
    if style:find("healer", 1, true) or style:find("raid", 1, true) then return "healer raid" end
    if style:find("rogue", 1, true) then return "clean rogue" end
    if style:find("minimal", 1, true) then return "minimal" end
    return "clean"
end

local function GuidedSetupFlow()
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return nil end
    ctx.guidedSetup = type(ctx.guidedSetup) == "table" and ctx.guidedSetup or nil
    return ctx.guidedSetup
end

local function SetGuidedSetupFlow(flow)
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return nil end
    ctx.guidedSetup = flow
    return flow
end

local function CloseGuidedSetupPanel()
    if A and A.largeTextPanel ~= nil then
        if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
    end
end

local function GuidedSetupPageHint(step)
    if not step or type(step.page) ~= "string" or step.page == "" then return nil end
    return "I will stay on the current page. Ask me to open the matching page when you want to go there."
end

local function GuidedSetupStepText(flow)
    flow = flow or GuidedSetupFlow()
    if type(flow) ~= "table" then return "No guided setup is active. Say 'help me build a clean layout' to start." end
    local index = tonumber(flow.step) or 1
    if index < 1 then index = 1 end
    if index > #GUIDED_SETUP_STEPS then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup complete. You can keep typing normal MSUF commands, use 'undo' for the last Assistant change, or ask me to diagnose anything that is not visible."
    end
    flow.step = index
    local step = GUIDED_SETUP_STEPS[index]
    local lines = {
        "Guided setup - " .. tostring(flow.styleLabel or "clean") .. " layout",
        "Step " .. tostring(index) .. "/" .. tostring(#GUIDED_SETUP_STEPS) .. ": " .. step.title,
        "Goal: " .. tostring(step.goal or ""),
        tostring(step.body or ""),
    }
    local pageHint = GuidedSetupPageHint(step)
    if pageHint then lines[#lines + 1] = pageHint end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Useful commands to try:"
    for i = 1, #(step.examples or {}) do
        lines[#lines + 1] = tostring(i) .. ". " .. step.examples[i]
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Normal MSUF commands still work while this guide is active. Say 'next', 'back', 'show setup', 'done', or 'cancel setup' when you want to steer the tour."
    local text = table.concat(lines, "\n")
    CloseGuidedSetupPanel()
    return text
end

function A.Workflow.StartGuidedSetup(style)
    local label = GuidedSetupStyleLabel(style)
    local flow = SetGuidedSetupFlow({ style = tostring(style or "clean"), styleLabel = label, step = 1 })
    return GuidedSetupStepText(flow)
end

function A.Workflow.GuidedSetupStep(command)
    command = tostring(command or "show")
    local flow = GuidedSetupFlow()
    if type(flow) ~= "table" then
        return "No guided setup is active. Say 'help me build a clean layout' to start."
    end
    if command == "cancel" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Cancelled guided setup. You can keep typing normal MSUF commands."
    end
    if command == "finish" or command == "done" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask for diagnostics or use 'undo' for the last Assistant change."
    end
    if command == "back" or command == "previous" then
        flow.step = (tonumber(flow.step) or 1) - 1
    elseif command == "next" or command == "skip" then
        flow.step = (tonumber(flow.step) or 1) + 1
    end
    if flow.step < 1 then flow.step = 1 end
    if flow.step > #GUIDED_SETUP_STEPS then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask for diagnostics or use 'undo' for the last Assistant change."
    end
    return GuidedSetupStepText(flow)
end

Registry:RegisterAction({
    key = "open_page",
    label = "Open Dashboard Page",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        local page = args and args.page
        if type(page) ~= "string" or page == "" then return false, "I do not know which page to open." end
        local previousPage = M and M.activeKey
        local label = tostring(args.label or page)
        local opened = false
        local bridge = M and M.SearchBridge
        local query = args and args.query
        if bridge and type(bridge.OpenSearchTarget) == "function" and type(query) == "string" and query ~= "" then
            bridge.OpenSearchTarget(page, query, label, args and args.anchor)
            opened = M and M.activeKey == page
        end
        if not opened and M and type(M.Open) == "function" then
            opened = M.Open(page) ~= false
        elseif not opened and M and type(M.SelectPage) == "function" then
            opened = M.SelectPage(page) ~= false
        end
        if opened then
            if previousPage and previousPage ~= page and A.Workflow and type(A.Workflow.PushNavigationPage) == "function" then
                A.Workflow.PushNavigationPage(previousPage)
            end
            return true, "Opened " .. label .. "."
        end
        return false, "Dashboard navigation is not available right now."
    end,
})

Registry:RegisterAction({
    key = "assistant_status",
    label = "Show MSUF Status",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.StatusText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Status",
                help = "Read-only diagnostic status for the current menu and Assistant registry.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_help",
    label = "Show Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.HelpText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Help",
                help = "Deterministic command examples that are handled locally by MSUF.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_scope_help",
    label = "Show Scoped Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local text = A.Workflow.ScopeHelpText(args or {})
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Controls",
                help = "Registry-backed settings and examples for the requested area.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "copy_support_link",
    label = "Copy Support Link",
    type = "support",
    combatSafe = true,
    run = function(args)
        local key = tostring(args and args.link or "")
        local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if not (spec and value) then return false, "I do not know that support link." end
        if not A.Workflow.CopyText(spec.title, value, "Copy this MSUF support link.") then
            return false, "Support link copy UI is not available right now."
        end
        return true, "Done. The " .. tostring(spec.title) .. " link is ready to copy."
    end,
})

Registry:RegisterAction({
    key = "support_links_summary",
    label = "Show Support Links",
    type = "support",
    combatSafe = true,
    run = function()
        local text = A.Workflow.SupportSummaryText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Support Links",
                help = "Copy a specific link by asking for Discord, Patreon, PayPal, Ko-fi, or GitHub.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})


Registry:RegisterAction({
    key = "diagnose_castbar_visibility",
    label = "Diagnose Castbar Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "target"
        if not CASTBAR_KEYS[unit] then return false, "I can only diagnose player, target, focus, or boss castbars right now." end
        local g = GeneralDB()
        local backend = GetCastbarBackend(unit, g)
        local unitEnabled = true
        if unit ~= "boss" then unitEnabled = UnitDB(unit).enabled ~= false end
        local label = UNIT_LABELS[unit] or unit
        if backend == "HIDE" then
            return true, label .. " castbar is hidden by its backend setting. Say 'show " .. tostring(unit) .. " castbar' or open Castbar settings."
        end
        if unitEnabled == false then
            return true, label .. " frame is disabled, so its attached castbar may not be visible. Say 'show " .. tostring(unit) .. " frame' first."
        end
        if unit == "player" and backend == "BLIZZARD" then
            return true, "Player castbar is assigned to the Blizzard castbar. Say 'show player castbar' to use the MSUF castbar backend."
        end
        return true, label .. " castbar is enabled in MSUF. If it still is not visible, check Edit Mode position, castbar text/icon settings, and whether the unit is currently casting."
    end,
})

Registry:RegisterAction({
    key = "diagnose_unit_visibility",
    label = "Diagnose Unit Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "player"
        if not UNIT_LABELS[unit] then return false, "I do not know which unit frame to diagnose." end
        return true, UnitFrameDiagnosticText(unit)
    end,
})

Registry:RegisterAction({
    key = "diagnose_group_visibility",
    label = "Diagnose Group Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local scope = args and args.scope or "party"
        if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        return true, GroupFrameDiagnosticText(scope)
    end,
})

Registry:RegisterAction({
    key = "diagnose_profile_status",
    label = "Diagnose Profiles",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ProfileDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_class_power_status",
    label = "Diagnose Class Resources",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ClassPowerDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_dashboard_setup",
    label = "Diagnose Dashboard Setup",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, DashboardSetupDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "guided_setup",
    label = "Guided Setup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.StartGuidedSetup(args and args.style or "clean")
    end,
})

Registry:RegisterAction({
    key = "guided_setup_step",
    label = "Guided Setup Step",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.GuidedSetupStep(args and args.command or "show")
    end,
})

Registry:RegisterTodo("Auras3 remaining advanced work: whitelist-style operations where the UI exposes them beyond the registered filters, blacklists, color controls, and group category blacklists.")
Registry:RegisterTodo("Profiles remaining work: spec-profile edge cases should keep expanding as new public helpers appear.")
Registry:RegisterTodo("Preset operations remaining work: add Assistant routes for any future UI preset buttons only after they expose public shared helpers.")
Registry:RegisterTodo("Diagnostic/setup workflows remaining work: aura-specific troubleshooters, deeper branch-specific guided setup flows, and any future public factory-reset helper routed without slash-command execution.")

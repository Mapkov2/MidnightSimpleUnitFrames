-- Assistant Dashboard color-token and profile staging selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; the main dashboard registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

local PROFILE_EXPORT_KIND_LABELS = {
    all = "Full profile",
    unitframe = "Unit Frames",
    castbar = "Cast Bars",
    colors = "Colors",
    gameplay = "Gameplay",
    groupframe = "Group Frames",
}

function A.DashboardRegistry.BuildStagingSelectors(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local Assistant = ctx.A or A
    local NormalizeKey = ctx.NormalizeKey
    local ResolveToken = ctx.ResolveToken
    local PersistScalar = ctx.PersistScalar
    local OpenMenuPage = ctx.OpenMenuPage
    local SelectorBool = ctx.SelectorBool

    if type(Menu) ~= "table" or type(Assistant) ~= "table" then return {} end
    if type(NormalizeKey) ~= "function" or type(ResolveToken) ~= "function" then return {} end
    if type(PersistScalar) ~= "function" or type(OpenMenuPage) ~= "function" then return {} end
    if type(SelectorBool) ~= "function" then return {} end

    local function DisplayEnumLabel(label, value)
        if Assistant and type(Assistant.DisplayEnumLabel) == "function" then return Assistant.DisplayEnumLabel(label, value) end
        if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(value or "") then return tostring(label) end
        local parser = Assistant and Assistant.Parser
        if parser and type(parser.ValueDisplay) == "function" then
            return parser.ValueDisplay({ type = "enum" }, value)
        end
        return tostring(value or "")
    end

    local function ResolveProfileExportKind(kind)
        local workflow = Assistant and Assistant.ProfileWorkflow
        if workflow and type(workflow.ExportKind) == "function" then
            local resolved = workflow.ExportKind(kind)
            if PROFILE_EXPORT_KIND_LABELS[resolved] then return resolved, PROFILE_EXPORT_KIND_LABELS[resolved] end
        end
        kind = tostring(kind or "all"):lower()
        if kind == "full" or kind == "profile" then kind = "all" end
        if kind == "unitframes" or kind == "unit frame" or kind == "unit frames" then kind = "unitframe" end
        if kind == "castbars" or kind == "cast bar" or kind == "cast bars" then kind = "castbar" end
        if kind == "color" then kind = "colors" end
        if kind == "group" or kind == "groupframes" or kind == "group frame" or kind == "group frames" then kind = "groupframe" end
        if PROFILE_EXPORT_KIND_LABELS[kind] then return kind, PROFILE_EXPORT_KIND_LABELS[kind] end
        return "all", PROFILE_EXPORT_KIND_LABELS.all
    end

    local function SetColorTokenSelector(args)
        local kind = NormalizeKey(args and args.kind)
        if kind == "classpower" or kind == "classresource" or kind == "cp" then
            local token, label = ResolveToken(Assistant.ClassPowerColorTokens or {}, args and args.token)
            if not token then return false, "Which class resource color slot do you want me to select?" end
            PersistScalar("colorsCPToken", token)
            OpenMenuPage("opt_colors")
            return true, "Selected " .. DisplayEnumLabel(label, token) .. " class resource color slot."
        end
        local token, label = ResolveToken(Assistant.PowerColorTokens or {}, args and args.token)
        if not token then return false, "Which power color slot do you want me to select?" end
        PersistScalar("colorsPowerToken", token)
        OpenMenuPage("opt_colors")
        return true, "Selected " .. DisplayEnumLabel(label, token) .. " power color slot."
    end

    local function SetProfileStagingSelector(args)
        local field = NormalizeKey(args and (args.field or args.selector))
        if field == "profileexportkind" or field == "exportkind" or field == "exporttype" then
            local kind, label = ResolveProfileExportKind(args and args.kind)
            PersistScalar("profileExportKind", kind)
            OpenMenuPage("profiles")
            return true, "Selected " .. DisplayEnumLabel(label, kind) .. " profile export kind."
        end
        if field == "profileimportcreatenew" or field == "importcreatenew" or field == "importnewprofile" or field == "newprofileimport" then
            local value = SelectorBool(args and args.value)
            PersistScalar("profileImportCreateNew", value)
            OpenMenuPage("profiles")
            return true, "Set profile import and create new profile " .. (value and "on" or "off") .. "."
        end
        if field == "profilecreatecopyname" or field == "createname" or field == "copyname" or field == "profilename" then
            Menu.profileCreateCopyName = tostring(args and args.value or "")
            OpenMenuPage("profiles")
            return true, "Prepared profile name " .. tostring(Menu.profileCreateCopyName) .. "."
        end
        if field == "profileimportnewname" or field == "importnewname" or field == "newprofilename" then
            Menu.profileImportNewName = tostring(args and args.value or "")
            OpenMenuPage("profiles")
            return true, "Prepared imported profile name " .. tostring(Menu.profileImportNewName) .. "."
        end
        if field == "profilestring" or field == "profileimportstring" or field == "importstring" then
            Menu.profileImportString = tostring(args and args.value or "")
            OpenMenuPage("profiles")
            return true, "Prepared the profile import text."
        end
        return false, "Which profile value do you want me to prepare?"
    end

    return {
        SetColorTokenSelector = SetColorTokenSelector,
        SetProfileStagingSelector = SetProfileStagingSelector,
    }
end

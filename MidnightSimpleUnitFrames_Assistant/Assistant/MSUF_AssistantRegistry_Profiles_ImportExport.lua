-- Assistant profile import/export and summary actions.
-- Loaded before MSUF_AssistantRegistry_Profiles.lua; the profile registry passes workflow helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ProfileRegistry = A.ProfileRegistry or {}

function A.ProfileRegistry.RegisterImportExportActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Profile = ctx.Profile
    local ProfileExists = ctx.ProfileExists
    local ActiveProfileName = ctx.ActiveProfileName
    local Assistant = ctx.Assistant or A
    local Menu = ctx.Menu or M
    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(Profile) ~= "table" then return end
    if type(ProfileExists) ~= "function" or type(ActiveProfileName) ~= "function" then return end
    local RegisterProfileImportActions = A.ProfileRegistry and A.ProfileRegistry.RegisterProfileImportActions
    if type(RegisterProfileImportActions) ~= "function" then return end

    Registry:RegisterAction({
        key = "profile_summary",
        label = "Show Profile Summary",
        type = "profile",
        kind = "flow",
        combatSafe = true,
        run = function()
            local text = Profile.SummaryText()
            if Assistant and type(Assistant.ShowLargeTextPanel) == "function" then
                Assistant.ShowLargeTextPanel({
                    kind = "text",
                    title = "MSUF Profiles",
                    help = "Current profile, available profiles, and specialization profile links.",
                    text = text,
                    status = "Profile overview only. No MSUF options were changed.",
                })
            end
            return true, text
        end,
    })

    Registry:RegisterAction({
        key = "copy_wago_profiles_link",
        label = "Copy Wago Profiles Link",
        type = "profile",
        kind = "flow",
        combatSafe = true,
        run = function()
            local value = Profile.CopyURL()
            if Assistant and type(Assistant.ShowLargeTextPanel) == "function" then
                Assistant.ShowLargeTextPanel({
                    kind = "export",
                    title = "Wago MSUF Profiles",
                    help = "Copy this link to browse community MSUF profiles on Wago. Wago is a web profile hub; MSUF does not upload your profile automatically.",
                    text = value,
                    status = "Click Copy text, press Ctrl+C, then Close.",
                })
            elseif type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink("Wago MSUF Profiles", value)
            elseif Menu and type(Menu.SelectPage) == "function" then
                Menu.SelectPage("profiles")
            end
            return true, "Done. The Wago MSUF profile link is ready to copy."
        end,
    })

    Registry:RegisterAction({
        key = "export_profile",
        label = "Export Current Profile",
        type = "profile",
        kind = "flow",
        combatSafe = true,
        run = function(args)
            local kind = Profile.ExportKind(args and args.kind or "all")
            local fn = _G.MSUF_ExportSelectionToString
            if type(fn) ~= "function" then return false, "Open Profiles first so I can export the profile." end
            local value = fn(kind)
            if type(value) ~= "string" or value == "" then return false, "The export tool returned no profile string. Open Profiles first so I can build it." end
            if Assistant and type(Assistant.ShowLargeTextPanel) == "function" then
                Assistant.ShowLargeTextPanel({
                    kind = "export",
                    title = "Current Profile Export: " .. tostring(Profile.KindLabels[kind] or kind),
                    help = "Copy this MSUF profile string. Save it privately as a backup, or paste it on Wago if you want to share the profile.",
                    text = value,
                    status = "Click Copy text, press Ctrl+C, then Close.",
                })
            elseif type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink("MSUF Profile Export", value)
            elseif Menu and type(Menu.SelectPage) == "function" then
                Menu.SelectPage("profiles")
            end
            return true, "Done. Copy your current profile below. Save the string privately as a backup, or paste it on Wago if you want to share it."
        end,
    })

    Registry:RegisterAction({
        key = "open_profile_import",
        label = "Open Profile Import",
        type = "profile",
        kind = "flow",
        combatSafe = true,
        run = function()
            if Assistant and type(Assistant.ShowLargeTextPanel) == "function" then
                Assistant.ShowLargeTextPanel({
                    kind = "import",
                    title = "Import Profile",
                    help = "Add an MSUF profile string. I will ask for confirmation before importing into the active profile.",
                    text = "",
                    status = "No profile import has been applied yet.",
                })
                return true, "Add your MSUF profile string below."
            end
            if Menu and type(Menu.SelectPage) == "function" then Menu.SelectPage("profiles") end
            return true, "Opened Profiles. Add the import text to the profile import box."
        end,
    })

    RegisterProfileImportActions(ctx)
end

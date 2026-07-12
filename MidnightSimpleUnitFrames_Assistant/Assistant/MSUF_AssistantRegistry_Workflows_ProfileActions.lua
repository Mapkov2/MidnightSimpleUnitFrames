-- Assistant profile workflow action registrations.
-- Loaded before MSUF_AssistantRegistry_Workflows_Actions.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.RegisterProfileWorkflowActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Trim = ctx.Trim or function(text)
        text = tostring(text or "")
        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local function DisplayProfileName(name)
        local display = A.DisplayProfileName
        return type(display) == "function" and display(name) or Trim(name)
    end

    if not (Registry and type(Registry.RegisterAction) == "function") then return end

    Registry:RegisterAction({
        key = "copy_profile_from_to",
        label = "Copy Profile Source to Destination",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        lifecycle = { workflow = "profileCopy", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
        run = function(args)
            local source = Trim(args and args.source or "")
            local dest = Trim(args and args.name or args and args.destination or "")
            if source == "" then return false, "Which profile do you want me to copy from?" end
            if dest == "" then return false, "What should the destination profile be called?" end
            local resolve = A.ResolveProfileName
            if type(resolve) == "function" then
                local resolved, how = resolve(source)
                if how == "multiple" then return false, "I found multiple matching source profiles. Which full profile name do you want me to use?" end
                if resolved then source = resolved end
            end
            if type(A.ProfileExists) == "function" and not A.ProfileExists(source) then return false, "I don't see that profile: " .. tostring(source) .. "." end
            if type(_G.MSUF_CopyProfile) ~= "function" then return false, "Open Profiles first so I can copy that profile." end
            local copied = _G.MSUF_CopyProfile(source, dest)
            if copied and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(dest) end
            if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_COPY_FROM_TO") end
            return copied and true or false, copied and ("Done. Copied profile " .. tostring(source) .. " to " .. tostring(dest) .. ".") or "I kept the profile copy as it was."
        end,
    })

    Registry:RegisterAction({
        key = "start_profile_copy_flow",
        label = "Start Profile Copy Flow",
        type = "profile",
        combatSafe = true,
        lifecycle = { workflow = "profileCopy", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
        run = function(args)
            local source = Trim(args and args.source or "")
            if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
            source = DisplayProfileName(source)
            A.StartPendingFlow("profileCopyDestination", { source = source, label = "Profile copy" })
            return true, "What do you want me to call the copy of profile " .. tostring(source) .. "? For example: 'call it Raid Backup'. Say 'cancel' or 'never mind' to stop."
        end,
    })

    Registry:RegisterAction({
        key = "rename_profile",
        label = "Rename Profile",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        lifecycle = { workflow = "profileRename", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
        run = function(args)
            local source = Trim(args and args.source or "")
            local dest = Trim(args and args.name or args and args.destination or "")
            if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
            if dest == "" then return false, "What should the new profile name be?" end
            local requested = source
            local resolve = A.ResolveProfileName
            if type(resolve) == "function" then
                local resolved, how = resolve(source)
                if how == "multiple" then return false, "I found multiple matching source profiles. Which full profile name do you want me to use?" end
                if resolved then source = resolved end
            end
            if type(A.ProfileExists) == "function" then
                if not A.ProfileExists(source) then return false, "I don't see that profile: " .. tostring(requested) .. "." end
                if A.ProfileExists(dest) then return false, "Profile " .. tostring(dest) .. " already exists." end
            end
            if source == "Default" then return false, "The Default profile is protected. Copy it to a new profile instead." end
            local rename = _G.MSUF_RenameProfile or _G.MSUF_ProfileRename
            if type(rename) ~= "function" then
                return false, "Open Profiles first so I can rename that profile."
            end
            local ok = rename(source, dest)
            if ok == false then return false, "I kept the profile name as it was." end
            if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_RENAME") end
            return true, "Done. Renamed profile " .. tostring(source) .. " to " .. tostring(dest) .. "."
        end,
    })

    Registry:RegisterAction({
        key = "start_profile_rename_flow",
        label = "Start Profile Rename Flow",
        type = "profile",
        combatSafe = true,
        lifecycle = { workflow = "profileRename", canStart = true, canConfirmApply = true, canCancel = true, canReportStatus = true },
        run = function(args)
            local source = Trim(args and args.source or "")
            if source == "" then source = type(A.ActiveProfileName) == "function" and A.ActiveProfileName() or tostring(_G.MSUF_ActiveProfile or "Default") end
            source = DisplayProfileName(source)
            A.StartPendingFlow("profileRenameDestination", { source = source, label = "Profile rename" })
            return true, "What should the new name be for profile " .. tostring(source) .. "? For example: 'to Raid Renamed' or 'named Raid Renamed'. Say 'cancel' or 'never mind' to stop."
        end,
    })
end

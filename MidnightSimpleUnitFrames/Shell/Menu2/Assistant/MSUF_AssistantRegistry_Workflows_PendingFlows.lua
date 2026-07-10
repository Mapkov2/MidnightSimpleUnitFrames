-- Assistant pending workflow handlers.
-- Loaded before MSUF_AssistantRegistry_Workflows.lua; the main workflow module passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.RegisterPendingFlowHandlers(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Trim = ctx.Trim or function(text)
        text = tostring(text or "")
        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local Normalize = ctx.Normalize or function(text)
        text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
        return Trim(text)
    end

    if not (Registry and type(Registry.GetAction) == "function") then return end

    local function IsCancel(text)
        text = Normalize(text)
        if text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop" or text == "close" then return true end
        local phrases = {
            "never mind", "nevermind", "forget it", "cancel that", "abort that", "stop that", "not now",
            "no thanks", "no thank you", "dont", "do not",
            "abbrechen", "abbruch", "nein danke", "vergiss es", "lass es", "doch nicht",
        }
        for i = 1, #phrases do
            if (" " .. text .. " "):find(" " .. phrases[i] .. " ", 1, true) then return true end
        end
        return false
    end

    local function StripPrefixCI(raw, prefix)
        raw = Trim(raw)
        prefix = tostring(prefix or "")
        if raw == "" or prefix == "" then return nil end
        if raw:sub(1, #prefix):lower() == prefix:lower() then
            local value = Trim(raw:sub(#prefix + 1))
            value = Trim(value:gsub("^[:=%-%s]+", ""))
            return value
        end
        return nil
    end

    local function StripSuffixCI(raw, suffix)
        raw = Trim(raw)
        suffix = tostring(suffix or "")
        if raw == "" or suffix == "" or #raw < #suffix then return raw end
        if raw:sub(#raw - #suffix + 1):lower() == suffix:lower() then
            return Trim(raw:sub(1, #raw - #suffix))
        end
        return raw
    end

    local function CleanPendingProfileDestination(text, kind)
        local raw = Trim(text)
        if raw == "" then return "" end
        raw = Trim(raw:gsub("[%.!]+$", ""))
        raw = StripSuffixCI(raw, " please")
        raw = StripSuffixCI(raw, " bitte")
        local politePrefix = StripPrefixCI(raw, "please ") or StripPrefixCI(raw, "bitte ")
        if politePrefix and politePrefix ~= "" then raw = politePrefix end
        local prefixes = {
            "call it ", "name it ", "use name ", "use profile name ", "profile name ",
            "new profile name ", "new profile ", "destination profile ", "destination ",
            "to profile ", "to ",
            "nenn es ", "nenne es ", "name ist ", "profilname ", "zu profil ", "zu ",
            "nach profil ", "nach ", "als ",
        }
        if kind == "profileCopyDestination" then
            local copyPrefixes = { "copy it to ", "copy to ", "copy profile to ", "kopiere es nach ", "kopiere nach " }
            for i = 1, #copyPrefixes do
                local value = StripPrefixCI(raw, copyPrefixes[i])
                if value and value ~= "" then raw = value; break end
            end
        elseif kind == "profileRenameDestination" then
            local renamePrefixes = { "rename it to ", "rename to ", "rename profile to ", "benenne es um in ", "benenne es um zu ", "benenne es in ", "umbenennen in ", "umbenennen zu ", "in profile ", "in " }
            for i = 1, #renamePrefixes do
                local value = StripPrefixCI(raw, renamePrefixes[i])
                if value and value ~= "" then raw = value; break end
            end
        end
        for i = 1, #prefixes do
            local value = StripPrefixCI(raw, prefixes[i])
            if value and value ~= "" then raw = value; break end
        end
        raw = Trim(raw:gsub("^['\"`]+", ""):gsub("['\"`]+$", ""))
        return raw
    end

    local function OriginalDestination(text, kind)
        local cleaned = CleanPendingProfileDestination(text, kind)
        local history = type(A.GetHistory) == "function" and A.GetHistory() or nil
        if type(history) ~= "table" then return cleaned end
        for i = #history, 1, -1 do
            local item = history[i]
            if type(item) == "table" and item.role == "user" then
                local original = CleanPendingProfileDestination(item.text, kind)
                if original:lower() == cleaned:lower() then return original end
                break
            end
        end
        return cleaned
    end

    local function DisplayProfileName(name)
        local display = A.DisplayProfileName
        return type(display) == "function" and display(name) or Trim(name)
    end

    function A.HandlePendingFlow(text)
        local flow = A.Workflow.PendingFlow()
        if type(flow) ~= "table" then return nil end
        if IsCancel(text) or Normalize(text) == "cancel workflow" then
            local ok, message = A.Workflow.CancelActiveWorkflow()
            return { text = message, status = ok and "applied" or "failed" }
        end
        if flow.kind == "profileCopyDestination" then
            local source = DisplayProfileName(flow.source)
            local dest = OriginalDestination(text, flow.kind)
            if dest == "" then return { text = "What should the destination profile be called? Example: 'call it Raid Backup'. Say 'cancel' or 'never mind' to stop.", status = "confirmation_needed" } end
            A.ClearPendingFlow()
            local action = Registry:GetAction("copy_profile_from_to")
            if not action then return { text = "Open Profiles first so I can copy that profile.", status = "failed" } end
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Copy profile " .. tostring(source) .. " to " .. tostring(dest),
                summary = "Copies one named profile to a new destination profile.",
            })
        end
        if flow.kind == "profileRenameDestination" then
            local dest = CleanPendingProfileDestination(text, flow.kind)
            if dest == "" then return { text = "What should the new profile be called? Examples: 'to Raid Renamed' or 'named Raid Renamed'. Say 'cancel' or 'never mind' to stop.", status = "confirmation_needed" } end
            A.ClearPendingFlow()
            local action = Registry:GetAction("rename_profile")
            if not action then return { text = "Open Profiles first so I can rename that profile.", status = "failed" } end
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { source = flow.source, name = dest },
                confirmRequired = true,
                label = "Rename profile " .. tostring(flow.source) .. " to " .. tostring(dest),
                summary = "Renames the selected profile.",
            })
        end
        return nil
    end
end

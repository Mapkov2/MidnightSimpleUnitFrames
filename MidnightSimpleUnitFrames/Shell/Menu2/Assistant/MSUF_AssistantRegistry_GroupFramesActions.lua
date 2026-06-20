local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames assistant action domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for status-icon helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
MSUF = ctx.MSUF or MSUF
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local ResolveGroupStatusIcon = ctx.ResolveGroupStatusIcon
local ResetGroupStatusIcon = ctx.ResetGroupStatusIcon
local GROUP_STATUS_ICON_SPECS = ctx.GROUP_STATUS_ICON_SPECS or {}

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(ResolveGroupStatusIcon) ~= "function" or type(ResetGroupStatusIcon) ~= "function" then return end

local function GroupLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    local label = UNIT_LABELS[scope]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    return "Party"
end

Registry:RegisterAction({
    key = "reset_group_status_icon",
    label = "Reset Group Status Icon",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        local spec = ResolveGroupStatusIcon(args and args.icon)
        if not spec then return false, "Which group status icon do you want me to reset?" end
        ResetGroupStatusIcon(scope, spec)
        return true, "Done. Reset " .. GroupLabel(scope) .. " " .. tostring(spec.label) .. " placement and icon pack."
    end,
})

Registry:RegisterAction({
    key = "reset_group_status_icons",
    label = "Reset Group Status Icons",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        for i = 1, #GROUP_STATUS_ICON_SPECS do ResetGroupStatusIcon(scope, GROUP_STATUS_ICON_SPECS[i]) end
        return true, "Done. Reset " .. GroupLabel(scope) .. " status icon placement and icon packs."
    end,
})

Registry:RegisterAction({
    key = "preview_group_status_icon",
    label = "Preview Group Status Icon",
    type = "preview",
    combatSafe = true,
    aliases = { "preview group status icon", "preview group status indicator", "show all group status icons", "show all group status indicators" },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local spec = ResolveGroupStatusIcon(args and (args.icon or args.text))
        local gf = MSUF and MSUF.GF
        if gf and type(gf.SetPreviewFocus) == "function" then gf.SetPreviewFocus("sicons") end
        if gf and type(gf.SetStatusPreviewMode) == "function" then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and spec and gf and type(gf._PreviewSelectStatusIcon) == "function" then gf._PreviewSelectStatusIcon(spec.value) end
        if mode == "all" then return true, "Done. Showing all group status icons in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current group status icon") .. "."
    end,
})

local GROUP_COPY_SCOPE_LABELS = {
    { key = "general", label = "Basics" },
    { key = "health", label = "Health & Bars" },
    { key = "text", label = "Text & Name" },
    { key = "font", label = "Font Override" },
    { key = "border", label = "Background & Opacity" },
    { key = "range", label = "Range Fade" },
    { key = "indicators", label = "Indicators & Status Icons" },
    { key = "auras", label = "Auras" },
    { key = "highlight", label = "Highlight & Aggro" },
    { key = "dstripe", label = "Debuff Stripe" },
    { key = "features", label = "Corner/Spell" },
}

local function GroupCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #GROUP_COPY_SCOPE_LABELS do
        local row = GROUP_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " Which group-frame parts do you want me to copy?" end
    if #selected == total then return " Categories: all group-frame parts." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end

Registry:RegisterAction({
    key = "copy_group",
    label = "Copy Group Frame Options",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "copy party to raid", "copy group frame settings", "copy group settings", "copy raid settings" },
    run = function(args)
        local GP = M and M.GroupPage
        if not (GP and type(GP.CopyGroupSettings) == "function") then
            return false, "Open Group Frames first so I can copy those options."
        end
        local src = args and args.source
        if src ~= "raid" and src ~= "mythicraid" then src = "party" end
        local targets = args and args.targets
        if type(targets) ~= "table" or #targets == 0 then
            local target = args and args.target
            targets = target and { target } or {}
        end
        if #targets == 0 then return false, "Which group frame should receive the copied options?" end
        local scopes = args and args.scopes
        if type(scopes) ~= "table" and type(GP.NewGFCopyScopes) == "function" then scopes = GP.NewGFCopyScopes() end
        local count = 0
        local copiedLabels = {}
        for i = 1, #targets do
            local dst = targets[i]
            if dst ~= "raid" and dst ~= "mythicraid" then dst = "party" end
            if dst ~= src and GP.CopyGroupSettings(src, dst, scopes) then
                count = count + 1
                copiedLabels[#copiedLabels + 1] = GroupLabel(dst)
            end
        end
        if count == 0 then return false, "I did not copy any group-frame options. Pick a different source and destination." end
        return true, "Done. I copied " .. GroupLabel(src) .. " group-frame options to " .. table.concat(copiedLabels, ", ") .. "." .. GroupCopyScopeSummary(scopes)
    end,
})

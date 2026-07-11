-- Assistant workflow custom-anchor picker handlers.
-- Loaded before MSUF_AssistantRegistry_Workflows.lua; the main workflow module injects state helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.RegisterAnchorPickerHandlers(ctx)
    ctx = type(ctx) == "table" and ctx or {}

    local UnitDB = ctx.UnitDB or function() return {} end
    local GroupDB = ctx.GroupDB or function() return {} end
    local ApplyUnit = ctx.ApplyUnit or function() end
    local ApplyGroup = ctx.ApplyGroup or function() end
    local UNIT_LABELS = ctx.UNIT_LABELS or A.UnitLabels or {}

    local function DisplayUnitLabel(key)
        if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(key) end
        key = tostring(key or "")
        local label = UNIT_LABELS[key]
        if label ~= nil and tostring(label) ~= "" then return tostring(label) end
        if key == "targettarget" then return "Target of Target" end
        if key == "focustarget" then return "Focus Target" end
        if key == "mythicraid" then return "Mythic Raid" end
        key = key:gsub("^uf_", ""):gsub("_", " ")
        key = key:gsub("(%l)(%u)", "%1 %2")
        return (key:gsub("^%l", string.upper))
    end

    function A.Workflow.CancelAnchorPicker()
        local ov = _G.MSUF_AnchorPicker
        if ov then
            ov._onPick = nil
            if ov.Hide then ov:Hide() end
            return true, "Cancelled the custom anchor picker."
        end
        return false, "The custom anchor picker is closed."
    end

    function A.Workflow.StartUnitAnchorPicker(unit)
        unit = tostring(unit or "")
        if unit == "" then return false, "Which unit frame should use the custom anchor picker?" end
        local ensure = _G.MSUF_EnsureAnchorPicker
        local overlay = type(ensure) == "function" and ensure() or nil
        if not overlay then return false, "Open the Anchor Picker first so I can choose a frame anchor with you." end
        overlay._onPick = function(frameName)
            local function ApplyPickedAnchor()
                local conf = UnitDB(unit)
                conf.anchorFrameName = frameName
                conf.anchorToUnitframe = "GLOBAL"
                ApplyUnit(unit, "MSUF_ASSISTANT_PICK_CUSTOM_ANCHOR", { preview = true })
            end
            if M and type(M.CaptureHistory) == "function" and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Pick custom anchor", "assistant:unit:anchorPick:" .. tostring(unit), ApplyPickedAnchor)
            else
                ApplyPickedAnchor()
            end
            A.ClearPendingFlow()
            if type(A.AddHistory) == "function" then
                A.AddHistory("assistant", "Done. Picked " .. tostring(frameName or "") .. " as " .. DisplayUnitLabel(unit) .. " custom anchor.", "applied")
            end
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.workflow.anchor_pick")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
        end
        overlay:Show()
        A.StartPendingFlow("unitAnchorPicker", { source = unit, label = "Unit custom anchor picker" })
        return true, "Click a frame to pick a custom anchor for " .. DisplayUnitLabel(unit) .. ". 'cancel custom anchor picker' stops the picker."
    end

    function A.Workflow.StartGroupAnchorPicker(scope)
        scope = tostring(scope or "party")
        if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        local ensure = _G.MSUF_EnsureAnchorPicker
        local overlay = type(ensure) == "function" and ensure() or nil
        if not overlay then return false, "Open the Anchor Picker first so I can choose a frame anchor with you." end
        overlay._onPick = function(frameName)
            local function ApplyPickedAnchor()
                GroupDB(scope).anchorToFrame = frameName
                ApplyGroup(scope, "rebuild")
            end
            if M and type(M.CaptureHistory) == "function" and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Pick group anchor", "assistant:group:anchorPick:" .. tostring(scope), ApplyPickedAnchor)
            else
                ApplyPickedAnchor()
            end
            A.ClearPendingFlow()
            if type(A.AddHistory) == "function" then
                A.AddHistory("assistant", "Done. Picked " .. tostring(frameName or "") .. " as " .. DisplayUnitLabel(scope) .. " custom anchor.", "applied")
            end
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.workflow.group_anchor_pick")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
        end
        overlay:Show()
        A.StartPendingFlow("groupAnchorPicker", { source = scope, label = "Group custom anchor picker" })
        return true, "Click a frame to pick a custom anchor for " .. DisplayUnitLabel(scope) .. ". 'cancel custom anchor picker' stops the picker."
    end

    function A.Workflow.AnchorPickerStatus()
        local ov = _G.MSUF_AnchorPicker
        local shown = ov and ov.IsShown and ov:IsShown()
        local flow = A.Workflow.PendingFlow()
        if shown then
            return "Custom anchor picker is active. Click a frame to pick it. 'cancel custom anchor picker' stops the picker."
        end
        if type(flow) == "table" and (flow.kind == "unitAnchorPicker" or flow.kind == "groupAnchorPicker") then
            return "A custom anchor picker is waiting, but the picker overlay is hidden. 'cancel custom anchor picker' clears it."
        end
        return "The custom anchor picker is closed."
    end
end

-- Assistant Profiles summary text helper.
-- Loaded after MSUF_AssistantRegistry_Profiles_Workflow.lua so A.ProfileWorkflow is installed.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Profile = A.ProfileWorkflow
local ActiveProfileName = A.ActiveProfileName
if type(Profile) ~= "table" or type(ActiveProfileName) ~= "function" then return end

function Profile.SummaryText()
    local lines = {}
    lines[#lines + 1] = "Active profile: " .. ActiveProfileName()
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Profiles:"
    local profiles = Profile.List()
    for i = 1, #profiles do lines[#lines + 1] = "- " .. tostring(profiles[i]) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Specialization auto-switch: " .. (Profile.SpecAutoSwitchEnabled() and "on" or "off")
    local specs = Profile.SpecMeta()
    if #specs > 0 then
        lines[#lines + 1] = "Specialization profile links:"
        for i = 1, #specs do
            local spec = specs[i]
            lines[#lines + 1] = "- " .. spec.name .. ": " .. tostring(Profile.GetSpecProfile(spec.id) or "None selected")
        end
    else
        lines[#lines + 1] = "Specialization profile links: specialization data is still preparing for this character."
    end
    return table.concat(lines, "\n")
end

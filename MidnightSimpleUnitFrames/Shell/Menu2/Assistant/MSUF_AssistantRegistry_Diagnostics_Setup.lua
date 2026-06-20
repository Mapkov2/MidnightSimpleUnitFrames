-- Guided setup workflow for Assistant diagnostics.
-- Kept out of the diagnostic checks so the large registry stays reviewable.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A
A.Workflow = A.Workflow or {}

local DiagnosticsData = A.DiagnosticsRegistryData
if type(DiagnosticsData) ~= "table" then return end

local GUIDED_SETUP_STEPS = DiagnosticsData.GUIDED_SETUP_STEPS or {}
local GUIDED_SETUP_GUIDES = DiagnosticsData.GUIDED_SETUP_GUIDES or {}

local function SetupNormalize(text)
    if A and type(A.Normalize) == "function" then return A.Normalize(text) end
    text = tostring(text or ""):lower()
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SetupHasAny(text, terms)
    text = " " .. SetupNormalize(text) .. " "
    for i = 1, #(terms or {}) do
        local term = SetupNormalize(terms[i])
        if term ~= "" and text:find(" " .. term .. " ", 1, true) then return true end
    end
    return false
end

local function GuidedSetupGuideKey(style)
    local text = SetupNormalize(style)
    if text == "" then return "main" end
    if SetupHasAny(text, { "group frames", "group frame", "party frames", "raid frames", "mythic raid frames", "gruppenframes", "gruppe setup", "raid setup", "party setup" }) then return "group_frames" end
    if SetupHasAny(text, { "castbar", "castbars", "cast bar", "cast bars", "zauberleiste", "kick bar", "focus kick" }) then return "castbars" end
    if SetupHasAny(text, { "profile", "profiles", "profil", "profile setup", "profile guide", "spec profile", "import profile", "export profile" }) then return "profiles" end
    if SetupHasAny(text, { "class resource", "class resources", "class power", "class bar", "resource bar", "klassenressource", "klassenressourcen" }) then return "class_resources" end
    if SetupHasAny(text, { "gameplay", "combat timer", "combat text", "totem", "first dance", "crosshair", "spielhilfe" }) then return "gameplay" end
    if SetupHasAny(text, { "appearance", "bars and fonts", "fonts and bars", "global bars", "global fonts", "font setup", "bar setup", "color setup", "farben", "schrift" }) then return "appearance" end
    return "main"
end

local function GuidedSetupGuideForFlow(flow)
    local key = type(flow) == "table" and flow.guide or "main"
    local guide = GUIDED_SETUP_GUIDES[key]
    return guide or GUIDED_SETUP_GUIDES.main, guide and key or "main"
end

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
    if type(flow) ~= "table" then return "Guided setup is closed. Say 'help me build a clean layout' to start." end
    local guide = GuidedSetupGuideForFlow(flow)
    local steps = (guide and guide.steps) or GUIDED_SETUP_STEPS
    local index = tonumber(flow.step) or 1
    if index < 1 then index = 1 end
    if index > #steps then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup complete. You can keep making normal MSUF requests, use 'undo' for the last Assistant change, or ask me to check anything that is not visible."
    end
    flow.step = index
    local step = steps[index]
    local lines = {
        "Guided setup - " .. tostring(flow.guideTitle or (guide and guide.label) or "MSUF layout setup"),
        "Step " .. tostring(index) .. "/" .. tostring(#steps) .. ": " .. step.title,
        "Goal: " .. tostring(step.goal or ""),
        tostring(step.body or ""),
    }
    local pageHint = GuidedSetupPageHint(step)
    if pageHint then lines[#lines + 1] = pageHint end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Examples:"
    for i = 1, #(step.examples or {}) do
        lines[#lines + 1] = tostring(i) .. ". " .. step.examples[i]
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "You can still make normal MSUF requests during the guide. The tour responds to 'next', 'back', 'show setup', 'done', or 'cancel setup'."
    local text = table.concat(lines, "\n")
    CloseGuidedSetupPanel()
    return text
end

function A.Workflow.StartGuidedSetup(style)
    local guideKey = GuidedSetupGuideKey(style)
    local guide = GUIDED_SETUP_GUIDES[guideKey] or GUIDED_SETUP_GUIDES.main
    local label = GuidedSetupStyleLabel(style)
    local title = guide.label
    if guideKey == "main" then title = tostring(label or "clean") .. " layout" end
    local flow = SetGuidedSetupFlow({ style = tostring(style or "clean"), styleLabel = label, guide = guideKey, guideTitle = title, step = 1 })
    return GuidedSetupStepText(flow)
end

function A.Workflow.GuidedSetupStep(command)
    command = tostring(command or "show")
    local flow = GuidedSetupFlow()
    if type(flow) ~= "table" then
        return "Guided setup is closed. Say 'help me build a clean layout' to start."
    end
    if command == "cancel" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Cancelled guided setup. You can keep making normal MSUF requests."
    end
    if command == "finish" or command == "done" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask me to run checks or use 'undo' for the last Assistant change."
    end
    if command == "back" or command == "previous" then
        flow.step = (tonumber(flow.step) or 1) - 1
    elseif command == "next" or command == "skip" then
        flow.step = (tonumber(flow.step) or 1) + 1
    end
    if flow.step < 1 then flow.step = 1 end
    local guide = GuidedSetupGuideForFlow(flow)
    local steps = (guide and guide.steps) or GUIDED_SETUP_STEPS
    if flow.step > #steps then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask me to run checks or use 'undo' for the last Assistant change."
    end
    return GuidedSetupStepText(flow)
end

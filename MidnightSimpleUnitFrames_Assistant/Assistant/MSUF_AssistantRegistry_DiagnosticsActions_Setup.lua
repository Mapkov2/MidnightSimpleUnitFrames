-- Assistant diagnostics guided setup action registry.
-- Loaded before MSUF_AssistantRegistry_DiagnosticsActions.lua; the main file passes registry context in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

local function NativeTourIsActive()
    local tour = MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
    if type(tour) ~= "table" or type(tour.IsActive) ~= "function" then return false end
    local ok, active = pcall(tour.IsActive, tour)
    return ok and active == true
end

local function OpenNativeGuidedTour(source)
    local active = NativeTourIsActive()
    local open
    if active then
        open = type(_G.MSUF_ResumeGuidedTour) == "function" and _G.MSUF_ResumeGuidedTour
            or type(M.ResumeGuidedTour) == "function" and M.ResumeGuidedTour
    else
        open = type(_G.MSUF_StartGuidedTour) == "function" and _G.MSUF_StartGuidedTour
            or type(M.StartGuidedTour) == "function" and M.StartGuidedTour
    end

    local opened
    local usedNative = type(open) == "function"
    if type(open) == "function" then
        if active then
            opened = open()
        else
            opened = open({ source = tostring(source or "assistant") })
        end
    elseif type(M.Open) == "function" then
        -- The core add-on is a hard dependency, but keep a safe fallback for
        -- partial-load recovery and the standalone Assistant test harness.
        opened = M.Open(active and nil or "home")
    end

    if opened == false or opened == nil then
        local inCombat = type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()
        local reason = inCombat and " Leave combat, then ask me again." or " Open the MSUF menu, then ask me again."
        return false, "I could not open the guided setup." .. reason,
            { noMutation = true, userFacingFailure = true }
    end

    local verb = active and "Resumed" or "Opened"
    local message = verb .. " the native MSUF guided setup. Follow the highlighted control and the guided bar at the top."
    if usedNative then return true, message end
    return true, message, { noChange = true }
end

function A.DiagnosticsRegistry.RegisterGuidedSetupActions(ctx)
    if type(ctx) ~= "table" then return false end

    local Registry = ctx.Registry
    if not (Registry and type(Registry.RegisterAction) == "function") then return false end

    -- Retire runtime-only context left by the removed Assistant text wizard.
    -- The menu-native tour now owns progress in MSUF_GlobalDB.
    local legacyContext = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(legacyContext) == "table" then legacyContext.guidedSetup = nil end

    Registry:RegisterAction({
        key = "guided_setup",
        label = "Guided Setup",
        type = "setup",
        combatSafe = false,
        run = function()
            return OpenNativeGuidedTour("assistant")
        end,
    })

    Registry:RegisterAction({
        key = "restart_upgrade_highlight_tour",
        label = "Restart Upgrade Highlight Tour",
        aliases = {
            "start the highlight tour", "restart the highlight tour", "replay the highlight tour",
            "start upgrade highlights", "show update highlights again", "tour nochmal starten",
        },
        aliasNoArgs = true,
        type = "setup",
        combatSafe = false,
        confirmRequired = false,
        run = function()
            if not (M and type(M.RestartUpgradeHighlightTour) == "function") then
                return false, "The upgrade highlight tour is not available in this menu build."
            end
            return M.RestartUpgradeHighlightTour("assistant")
        end,
    })

    Registry:RegisterAction({
        key = "guided_setup_step",
        label = "Open Guided Setup",
        type = "setup",
        combatSafe = false,
        run = function(args)
            local step = type(args) == "table" and tostring(args.step or ""):lower() or ""
            if step ~= "" then
                if type(M.RunGuidedTourStep) ~= "function" then
                    return false, "Open the guided setup first so I can use that step."
                end
                local ok, reason, detail = M.RunGuidedTourStep(step)
                if not ok then
                    return false, reason == "guided_setup_inactive"
                        and "Open the guided setup first so I can use that step."
                        or "I do not recognize that guided-setup step."
                end
                if reason == "confirmation_needed" then
                    return true, tostring(detail or "Confirm Skip in the guided bar to continue."), { noChange = true }
                end
                local labels = { back = "Back", keep = "Keep current", skip = "Skip", next = "Next", pause = "Pause" }
                return true, "Used " .. tostring(labels[step] or step) .. " in the guided setup.",
                    step == "pause" and { noChange = true } or nil
            end
            return OpenNativeGuidedTour("assistant_followup")
        end,
    })

    return true
end

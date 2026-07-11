-- Assistant router context lifecycle and reference-follow-up helpers.
-- Loaded immediately before MSUF_AssistantRouter.lua; all referenced Router
-- helpers are resolved at call time after the main router has finished loading.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local R = A.RouterPrivate or {}
A.RouterPrivate = R

-- Router replies use status/result as externally visible semantics. Keep
-- read-only answers out of mutation telemetry and undo hints, while preserving
-- real failures, ambiguity, and confirmation states returned by the core.
function R.AsReadOnlyResult(result)
    if type(result) ~= "table" then return result end
    local status = result.status or result.result
    if status == nil
        or status == "applied"
        or status == "changed"
        or status == "unchanged"
        or status == "answered"
        or status == "info"
    then
        result.status = "info"
        result.result = "info"
    end
    return result
end

function R.AsReadOnlyProblemDiagnostic(result)
    result = R.AsReadOnlyResult(result)
    if type(result) ~= "table" then return result end
    local guard = "MSUF visibility troubleshooting\nI treated that as a problem report, not permission to enable, disable, or reset anything. I did not change a setting."
    local body = R.Trim(result.text or "")
    if not body:find("I treated that as a problem report", 1, true) then
        result.text = body ~= "" and (guard .. "\n\n" .. body) or guard
    end
    return result
end

-- Opening a page/control is successful work, but it is not a profile mutation.
-- Give navigation its own status so batches and telemetry do not offer Undo or
-- count it as an applied setting change.
function R.AsNavigationResult(result)
    if type(result) ~= "table" then return result end
    local status = result.status or result.result
    if status == nil
        or status == "applied"
        or status == "changed"
        or status == "unchanged"
        or status == "navigated"
    then
        result.status = "navigated"
        result.result = "navigated"
    end
    return result
end

function R.IsExplicitNavigationCommand(text)
    local norm = R.Normalize and R.Normalize(text) or R.Trim(text):lower()
    if norm:match("^open%s+") or norm:match("^go%s+to%s+") or norm:match("^oeffne%s+") then return true end
    if norm:match("^close%s+") and R.ContainsAny and R.ContainsAny(norm, { "panel", "dashboard", "menu", "picker", "import", "export" }) then return true end
    if norm == "support links"
        or norm == "show support links"
        or norm == "show me support links"
        or norm == "zeige support links"
        or norm == "zeige mir support links"
        or norm == "support links anzeigen"
    then
        return true
    end
    return norm == "back" or norm == "go back" or norm == "navigation back"
end

function R.IsExplicitReadOnlyDiagnosticCommand(text)
    local norm = R.Normalize and R.Normalize(text) or R.Trim(text):lower()
    if R.IsExactGenericDiagnosticRequest and R.IsExactGenericDiagnosticRequest(norm) then return true end
    return norm == "diagnostics"
        or norm == "diagnostik"
        or norm == "diagnosebericht"
        or norm == "run diagnostics"
        or norm == "run diagnostic"
        or norm == "run checks"
        or norm == "run check"
        or norm == "profile status"
        or norm == "profil status"
        or norm == "show profile summary"
        or norm == "edit mode status"
        or norm == "bearbeitungsmodus status"
        or norm == "assistant current step"
        or norm == "current assistant step"
        or norm == "current step"
        or norm == "show current step"
        or norm == "show assistant current step"
        or norm == "assistant step status"
        or norm == "step status"
        or norm == "what is the current step"
        or norm == "anchor picker status"
        or norm == "custom anchor picker status"
        or norm == "anker picker status"
        or norm == "assistant no match telemetry"
        or norm == "assistant no match worklist"
        or norm == "assistant learning list"
        or norm == "copy discord link"
        or norm:match("^diagnose%s+") ~= nil
        or norm:match("^diagnostic%s+") ~= nil
        or norm:match("^check%s+") ~= nil
        or norm:match("^help%s+") ~= nil
        or norm:match("%s+help$") ~= nil
end

function R.ReadabilityReply(title, body, examples, actions, clarification)    A.lastAssistantHelpContext = {
        kind = "readability",
        title = tostring(title or "Readability help"),
        examples = tostring(examples or "set player width to 300; set target cast bar height to 24."),
        actions = tostring(actions or "Open Dashboard Scaling | Open Fonts"),
        clarification = clarification,
    }
    return {
        text = tostring(title or "Readability help") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "set player width to 300; set target cast bar height to 24.") .. "\nYou can ask: " .. tostring(actions or "Open Dashboard Scaling | Open Fonts"),
        status = "info",
        summary = "Assistant readability help",
    }
end

R.HELP_CONTEXT_NEXT_TERMS = {    "what should i change first", "what should i do first", "where should i start",
    "what next", "what now", "next step", "next steps", "recommend a first change",
    "recommend first change", "what would you change first",
}

R.HELP_CONTEXT_EXAMPLE_TERMS = {    "show examples", "examples", "example", "give examples", "show me examples",
    "what can i say", "what should i type",
}

R.HELP_CONTEXT_OPEN_TERMS = {    "open it", "open that", "open this", "show it", "show that", "show this",
    "take me there", "go there", "open the page", "open that page",
}

R.HELP_CONTEXT_LOCATION_TERMS = {
    "where is it", "where is that", "where is this", "where are they", "where are those",
    "where do i change it", "where do i change that", "where do i change this", "where do i change them", "where do i change those",
    "where can i change it", "where can i change that", "where can i change this", "where can i change them", "where can i change those",
    "where do i configure it", "where do i configure that", "where do i configure this", "where do i configure them", "where do i configure those",
    "where can i configure it", "where can i configure that", "where can i configure this", "where can i configure them", "where can i configure those",
    "where do i find it", "where do i find that", "where do i find this", "where do i find them", "where do i find those",
    "where can i find it", "where can i find that", "where can i find this", "where can i find them", "where can i find those",
    "which page is it on", "which page is that on", "which page is this on", "which page are they on", "which page are those on",
    "what page is it on", "what page is that on", "what page is this on", "what page are they on", "what page are those on",
    "what menu is it in", "what menu is that in", "what menu is this in", "what menu are they in", "what menu are those in",
}

R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS = {
    "show it", "show that", "show this", "show them", "show those",
    "hide it", "hide that", "hide this", "hide them", "hide those",
    "enable it", "enable that", "enable this", "enable them", "enable those",
    "disable it", "disable that", "disable this", "disable them", "disable those",
    "toggle it", "toggle that", "toggle this", "toggle them", "toggle those",
    "turn it on", "turn that on", "turn this on", "turn them on", "turn those on",
    "turn it off", "turn that off", "turn this off", "turn them off", "turn those off",
    "switch it on", "switch that on", "switch this on", "switch them on", "switch those on",
    "switch it off", "switch that off", "switch this off", "switch them off", "switch those off",
}

R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS = {    "make it", "make that", "make this", "change it", "change that", "change this",
    "set it", "set that", "set this", "move it", "move that", "move this",
    "make them", "make those", "change them", "change those",
    "set them", "set those", "move them", "move those",
}

R.HELP_CONTEXT_PRONOUN_TERMS = { "it", "that", "this", "them", "those" }

function R.LooksLikeHelpContextFollowup(norm)    return R.ContainsAny(norm, R.HELP_CONTEXT_OPEN_TERMS)
        or (R.ContainsAny(norm, R.HELP_CONTEXT_LOCATION_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
        or R.ContainsAny(norm, R.HELP_CONTEXT_EXAMPLE_TERMS)
        or R.ContainsAny(norm, R.HELP_CONTEXT_NEXT_TERMS)
        or (R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
        or (R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS))
end

function R.ClearStaleHelpContextForInput(text)    if type(A.lastAssistantHelpContext) ~= "table" then return end
    local norm = R.Normalize(text)
    if norm == "" or R.LooksLikeHelpContextFollowup(norm) then return end
    A.lastAssistantHelpContext = nil
end

function R.TryContextlessReferenceClarification(text)
    local norm = R.Normalize(text)
    if norm == "" then return nil end

    -- Only intercept a reference with no real referent. Passing "that" or an
    -- absent result number to fuzzy search creates a plausible but random hit.
    local lastChanged = R.LastChangedSettingItem and R.LastChangedSettingItem() or nil
    if lastChanged
        or A.RouterHasPendingAssistantState()
        or A.RouterHasPendingSearchResults()
        or A.RouterHasPendingSelectedResult()
        or type(A.lastAssistantHelpContext) == "table"
        or type(A.lastAssistantPlanningContext) == "table"
    then
        return nil
    end

    if norm == "explain it simpler"
        or norm == "explain this simpler"
        or norm == "explain that simpler"
        or norm == "explain like im new"
        or norm == "explain like i'm new"
        or norm == "explain like i am new"
    then
        return A.RouterDecisionGuidanceReply(
            "Simple explanation help",
            "Name the MSUF setting, page, or result you want explained. Without that context, I would only be guessing.",
            "what is range fade; explain target buff cooldown text; open cast bars.",
            "Open Player | Open Auras | Open Cast Bars"
        )
    end

    if norm == "explain that"
        or norm == "explain this"
        or norm:match("^explain%s+option%s+%d+$")
        or norm:match("^explain%s+result%s+%d+$")
        or norm:match("^what%s+does%s+option%s+%d+%s+do$")
        or norm:match("^what%s+does%s+result%s+%d+%s+do$")
    then
        return R.ContextlessGuidanceReply()
    end

    return nil
end

function R.FirstOpenActionCommand(actions)    local first = tostring(actions or ""):match("([^|]+)")
    first = R.Trim(first or "")
    if first == "" then return nil end
    local label = first:match("^[Oo]pen%s+(.+)$")
    if not label or R.Trim(label) == "" then return nil end
    return "open " .. R.Trim(label)
end

function R.TryHelpContextFollowup(text, coreHandler)    local ctx = type(A.lastAssistantHelpContext) == "table" and A.lastAssistantHelpContext or nil
    if not ctx or (ctx.kind ~= "readability" and ctx.kind ~= "knowledge") then return nil end

    local norm = R.Normalize(text)
    if norm == "" then return nil end

    if R.ContainsAny(norm, R.HELP_CONTEXT_LOCATION_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local command = R.FirstOpenActionCommand(ctx.actions)
        local label = command and R.Trim(command:gsub("^open%s+", "")) or ""
        local location = label ~= "" and ("This topic is handled from " .. label .. ".") or ("Use the action list for this help topic: " .. tostring(ctx.actions))
        return {
            text = tostring(ctx.title) .. "\n" .. location .. "\nExamples: " .. tostring(ctx.examples) .. "\nYou can ask: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help location",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_VISIBILITY_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local clarification = tostring(ctx.clarification or "Name the exact MSUF area before I change it, so I do not guess wrong.")
        return {
            text = tostring(ctx.title) .. "\n" .. clarification .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help clarification",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_OPEN_TERMS) then
        local command = R.FirstOpenActionCommand(ctx.actions)
        if command and type(coreHandler) == "function" then
            local result = coreHandler(command)
            if result and not (type(result) == "table" and result.kind == "unknown") then
                if type(result) == "table" and R.Trim(result.text or "") == "" then
                    local label = R.Trim(command:gsub("^open%s+", ""))
                    result.text = label ~= "" and ("Opened " .. label .. ".") or "Opened the matching MSUF page."
                end
                return R.AsNavigationResult(result)
            end
        end
        return {
            text = tostring(ctx.title) .. "\nUse the matching action from this help topic: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help follow-up",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_EXAMPLE_TERMS) then
        return {
            text = tostring(ctx.title) .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help examples",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_NEXT_TERMS) then
        local nextStep = tostring(ctx.nextStep or "Start with the least destructive visible setting: open the matching page, adjust size or text first, then tune spacing, filters, or colors only if it is still hard to read.")
        return {
            text = tostring(ctx.title) .. "\n" .. nextStep .. "\nExamples: " .. tostring(ctx.examples) .. "\nYou can ask: " .. tostring(ctx.actions),
            status = "info",
            summary = "Assistant help next step",
        }
    end

    if R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_CHANGE_TERMS) and R.ContainsAny(norm, R.HELP_CONTEXT_PRONOUN_TERMS) then
        local clarification = tostring(ctx.clarification or "Name the exact MSUF area before I change it, so I do not guess wrong.")
        return {
            text = tostring(ctx.title) .. "\n" .. clarification .. "\nExamples: " .. tostring(ctx.examples),
            status = "info",
            summary = "Assistant help clarification",
        }
    end

    return nil
end

A.RouterSafePlanningReply = function(title, body, examples, actions)
    A.RouterClearPendingResultsForRoute()
    A.lastAssistantPlanningContext = {
        title = tostring(title or "Safe planning guidance"),
        examples = tostring(examples or "guided setup; run checks; open player."),
        actions = tostring(actions or "Guided Setup | Run Checks | Open Player"),
    }
    return {
        text = tostring(title or "Safe planning guidance") .. "\n" .. tostring(body or "") .. "\nExamples: " .. tostring(examples or "guided setup; run checks; open player.") .. "\nYou can ask: " .. tostring(actions or "Guided Setup | Run Checks | Open Player"),
        status = "info",
        summary = "Assistant safe planning guidance",
    }
end

A.RouterSafePlanningFollowupTerms = A.RouterSafePlanningFollowupTerms or {
    examples = {
        "examples", "example", "show examples", "show me examples",
        "give examples", "what should i type", "what can i type",
        "what can i say", "show commands", "show me commands",
    },
    open = {
        "open it", "open that", "open this", "open the page",
        "open first page", "open the first page", "open first page from checklist",
        "take me there", "go there", "show it", "show that", "show this",
    },
    details = {
        "explain more", "tell me more", "more details", "details",
        "why", "why this", "why that", "explain it", "explain that",
        "can you explain that", "can you explain more",
    },
    safe = {
        "which one is safer", "what is safest", "what is safer",
        "safer please", "yes but safer", "safe option", "safe step",
    },
    apply = {
        "do it", "do that", "run it", "run that", "apply it", "apply that",
        "make it happen", "ok do first step", "do first safe step",
        "do the first safe step", "apply first example", "apply the first example",
        "apply first checklist item", "use first example", "use the first example",
    },
}

function R.IsExactSafePlanningFollowup(norm)
    norm = R.Normalize(norm)
    if norm == "" then return false end
    for _, group in pairs(A.RouterSafePlanningFollowupTerms) do
        for i = 1, #group do
            if norm == R.Normalize(group[i]) then return true end
        end
    end
    return false
end

function R.ClearStalePlanningContextForInput(text)
    if type(A.lastAssistantPlanningContext) ~= "table" then return end
    local norm = R.Normalize(text)
    if norm == "" or R.IsExactSafePlanningFollowup(norm) then return end
    A.lastAssistantPlanningContext = nil
end

A.RouterTrySafePlanningFollowup = function(text, coreHandler)
    local ctx = type(A.lastAssistantPlanningContext) == "table" and A.lastAssistantPlanningContext or nil
    if not ctx then return nil end
    local norm = R.Normalize(text)
    if norm == "" then return nil end
    if R.ContainsAny(norm, R.CORRECTION_UNDO_TERMS) or R.ContainsAny(norm, R.CORRECTION_REDO_TERMS) then return nil end
    if R.ContainsAny(norm, {
        "why did that fail", "why did it fail", "why did this fail",
        "that did not work", "that didnt work", "that didn't work",
        "it did not work", "it didnt work", "it didn't work",
        "still broken", "still not working", "not fixed",
    }) then
        return nil
    end
    if (R.HasNaturalProblemTerm(norm) or R.ContainsAny(norm, R.VISIBILITY_PROBLEM_TERMS))
        and R.ContainsAny(norm, R.EXPLICIT_DOMAIN_TERMS)
    then
        return nil
    end
    if (norm:match("^why%s+is%s+") or norm:match("^why%s+are%s+") or norm:match("^why%s+cant%s+") or norm:match("^why%s+can't%s+"))
        and R.ContainsAny(norm, R.EXPLICIT_DOMAIN_TERMS)
    then
        return nil
    end
    local terms = A.RouterSafePlanningFollowupTerms
    local title = tostring(ctx.title or "Safe planning guidance")
    local examples = tostring(ctx.examples or "guided setup; run checks; open player.")
    local actions = tostring(ctx.actions or "Guided Setup | Run Checks | Open Player")

    if R.ContainsAny(norm, terms.apply) then
        return {
            text = title .. "\nI will not apply a planning suggestion from a vague follow-up. Type one exact example command when you want a change, or ask me to open the page first.\nExamples: " .. examples,
            status = "info",
            summary = "Assistant planning guarded apply",
        }
    end

    if R.ContainsAny(norm, terms.examples) then
        return {
            text = title .. "\nExamples: " .. examples,
            status = "info",
            summary = "Assistant planning examples",
        }
    end

    if R.ContainsAny(norm, terms.open) then
        local command = R.FirstOpenActionCommand(actions)
        if command and type(coreHandler) == "function" then
            local result = coreHandler(command)
            if result and not A.RouterIsUnknownResult(result) then return R.AsNavigationResult(result) end
        end
        return {
            text = title .. "\nOpen one of these pages or actions: " .. actions,
            status = "info",
            summary = "Assistant planning navigation",
        }
    end

    if R.ContainsAny(norm, terms.safe) then
        return A.RouterSafePlanningReply(
            title,
            "The safest next step is navigation or inspection, not applying a vague change. Open the relevant page first, review the current option, then use one exact example command if you want a change.",
            examples,
            actions
        )
    end

    if R.ContainsAny(norm, terms.details) then
        return {
            text = title .. "\nUse the examples when you want a concrete change, or open the relevant page first if you want to inspect settings safely.\nExamples: " .. examples .. "\nYou can ask: " .. actions,
            status = "info",
            summary = "Assistant planning details",
        }
    end

    return nil
end

function R.ContextlessGuidanceReply()    return {
        text = "I need a little more MSUF context before I choose or open something. Name the area, page, setting, or result number you mean.\nUseful next prompts: Guided Setup | Run Checks | Open Auras | Open Cast Bars | explain result 1 | why are target buffs hidden",
        status = "info",
        summary = "Assistant context guidance",
    }
end

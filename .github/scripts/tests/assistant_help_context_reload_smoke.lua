-- The help topic a follow-up refers to must survive /reload and logout.
--
-- A.lastAssistantHelpContext used to live only in this session's Lua table.
-- After a /reload the same "where is it" no longer found a help topic and
-- resolved against the last CHANGED setting instead, so a player who asked
-- about range fade, reloaded, and asked "where is it" was told the menu
-- location of an unrelated control. That is worse than a graceful fallback:
-- the answer is plausible, wrong, and gives no sign the referent was lost.
--
-- The topic is now mirrored into MSUF_DB.assistant.context.helpContext, which
-- is a real SavedVariable, and restored on the next input. This pins the whole
-- lifecycle: armed and persisted, identical answer across a reload, retired on
-- both sides when a new topic starts, and never persisting a non-scalar.
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function Exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local MSUF = { MSUF2 = {}, Assistant = {} }
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
local loader = root .. "/tools/assistant_runtime_manifest_loader.lua"
dofile(Exists(loader) and loader or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
local dashboard = root .. "/tools/assistant_dashboard_smoke.lua"
dofile(Exists(dashboard) and dashboard or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
local A = _G.MSUF_NS.Assistant
if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end

Check(type(A.RouterPersistHelpContext) == "function", "help-context persistence must be exported")
Check(type(A.RouterRestoreHelpContext) == "function", "help-context restore must be exported")

local function Reset()
    A.pendingChoices, A.pendingCandidates = nil, nil
    A.pendingConfirmation, A.pendingFlow = nil, nil
    A.lastAssistantHelpContext, A.lastAssistantPlanningContext = nil, nil
    local ctx = A.GetContext()
    for key in pairs(ctx) do ctx[key] = nil end
end

local function Say(text)
    local ok, result = pcall(A.HandleInput, text)
    Check(ok, "HandleInput errored on '" .. text .. "': " .. tostring(result))
    return tostring((result or {}).text or "")
end

local function FirstLine(text) return (tostring(text):match("^([^\n]*)") or "") end

-- A /reload keeps SavedVariables and destroys every session-local value,
-- including the once-per-session flag that gates the restore. Clearing that
-- flag is what makes this a reload rather than an in-session wipe: without it
-- the persisted topic stays deliberately silent, which is the behaviour the
-- conversation-reset helpers in the audit suites rely on.
local function SimulateReload()
    A.lastAssistantHelpContext = nil
    A.lastAssistantPlanningContext = nil
    A.pendingChoices, A.pendingCandidates = nil, nil
    A.pendingConfirmation, A.pendingFlow = nil, nil
    A._helpContextRestored = nil
end

local HELP_PROMPTS = { "explain range fade", "explain aura filters", "what is range fade" }
local FOLLOWUP = "where is it"

-- Find a help request that actually arms a topic, so one renamed article
-- cannot silently retire this contract.
local helpPrompt
for i = 1, #HELP_PROMPTS do
    Reset()
    Say(HELP_PROMPTS[i])
    if type(A.lastAssistantHelpContext) == "table" then
        helpPrompt = HELP_PROMPTS[i]
        break
    end
end
Check(helpPrompt ~= nil,
    "no help request armed a help context; tried: " .. table.concat(HELP_PROMPTS, ", "))

-- 1. Arming the topic must persist it.
local stored = A.GetContext().helpContext
Check(type(stored) == "table",
    "'" .. helpPrompt .. "' must mirror its help topic into the persisted context")
for key, value in pairs(stored) do
    local valueType = type(value)
    Check(valueType == "string" or valueType == "number" or valueType == "boolean",
        "persisted help context field '" .. tostring(key) .. "' is a " .. valueType
        .. "; only SavedVariables scalars may be stored")
end

-- 2. The follow-up before the reload.
local before = FirstLine(Say(FOLLOWUP))
Check(before ~= "", "the follow-up must produce an answer")

-- 3. The same follow-up after the reload must give the same answer. This is
--    the regression: it used to silently answer about the last changed setting.
Reset()
Say(helpPrompt)
SimulateReload()
Check(type(A.lastAssistantHelpContext) ~= "table",
    "the reload simulation must really drop the session-local topic")
local after = FirstLine(Say(FOLLOWUP))
Check(after == before,
    "the follow-up must answer identically after a reload.\n  before: " .. before
    .. "\n  after:  " .. after)

-- 4. The restore must not depend on a live table that a reload cannot have.
Reset()
Say(helpPrompt)
SimulateReload()
local restored = A.RouterRestoreHelpContext()
Check(type(restored) == "table", "the topic must be rebuildable from SavedVariables alone")
Check(tostring(restored.title or "") ~= "", "the restored topic must carry its title")

-- 5. Starting a new, unrelated topic retires BOTH copies, or the abandoned
--    help subject would come back at the next reload.
Reset()
Say(helpPrompt)
Say("set player width to 300")
Check(type(A.lastAssistantHelpContext) ~= "table",
    "a non-follow-up input must drop the live help topic")
Check(A.GetContext().helpContext == nil,
    "a non-follow-up input must drop the persisted help topic too")
SimulateReload()
Check(A.RouterRestoreHelpContext() == nil,
    "a retired help topic must not come back after a reload")

print("assistant_help_context_reload_smoke: PASS (" .. helpPrompt .. ")")

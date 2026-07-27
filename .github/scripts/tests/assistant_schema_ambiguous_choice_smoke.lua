-- An ambiguous mutation in the generated-schema lane must offer a choice the
-- player can actually answer.
--
-- Schema.TryConversation used to render its own list, number it from the second
-- entry ("Text Size ...", "2. ...", "3. ..."), and arm no pending state at all.
-- Replying "2" then fell through to "I'm not sure which MSUF request you mean
-- yet": the assistant asked a question it could not accept an answer to. Most
-- controls in this lane are catalog-backed and have no registry owner, so the
-- choices carry a schema semantic id that Schema.Execute settles on selection.
--
-- The lane itself is the unit under test. Which requests reach it depends on
-- how much of the curated registry matches first, so the ambiguity cases are
-- driven through Schema.TryConversation directly; the router-level contract
-- pinned at the end is the honest fallback, which must never promise a
-- numbered reply it cannot accept.
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
local Schema = assert(A.ControlSchema, "control schema missing")

local function Reset()
    A.pendingChoices, A.pendingCandidates = nil, nil
    A.pendingConfirmation, A.pendingFlow = nil, nil
    A.lastAssistantHelpContext, A.lastAssistantPlanningContext = nil, nil
    if type(A.GetContext) == "function" then
        local ctx = A.GetContext()
        for key in pairs(ctx) do ctx[key] = nil end
    end
end

-- Find a request this lane answers ambiguously. Several are tried so a single
-- control being renamed cannot silently retire the whole contract.
local CANDIDATE_PROMPTS = {
    "set stack text size to 12",
    "set the icon zoom to 30",
    "set the cooldown text size to 14",
    "set opacity to 50",
}

local prompt, ambiguous
for i = 1, #CANDIDATE_PROMPTS do
    Reset()
    local ok, result = pcall(Schema.TryConversation, CANDIDATE_PROMPTS[i])
    if ok and type(result) == "table"
        and tostring(result.result or result.status or "") == "ambiguous"
    then
        prompt, ambiguous = CANDIDATE_PROMPTS[i], result
        break
    end
end
Check(ambiguous ~= nil,
    "no schema-lane request produced an ambiguous choice; tried: "
    .. table.concat(CANDIDATE_PROMPTS, ", "))

local body = tostring(ambiguous.text or "")
Check(type(A.pendingChoices) == "table" and #A.pendingChoices >= 2,
    "the ambiguity must arm at least two pending choices, got "
    .. tostring(type(A.pendingChoices) == "table" and #A.pendingChoices or 0))

-- Every offered entry is numbered, starting at 1.
local numbered = {}
for line in body:gmatch("[^\n]+") do
    local index, label = line:match("^(%d+)%.%s+(.+)$")
    if index and tonumber(index) > 0 then numbered[#numbered + 1] = label end
end
Check(#numbered == #A.pendingChoices,
    "every pending choice must appear as a numbered line: " .. tostring(#numbered)
    .. " numbered vs " .. tostring(#A.pendingChoices) .. " choices")
Check(body:find("\n1%. ") ~= nil or body:find("^1%. ") ~= nil,
    "the list must start numbering at 1:\n" .. body)
Check(body:find("0%. Cancel") ~= nil, "the list must offer the cancel option")

-- Entries must be distinguishable, or the numbers mean nothing. This is the
-- reason a choice carries its page: three pages each own a plain "Text Size".
local seenLabel = {}
for i = 1, #numbered do
    local label = numbered[i]
    Check(not seenLabel[label],
        "two offered choices share the label '" .. tostring(label) .. "':\n" .. body)
    seenLabel[label] = true
end

-- Catalog-backed choices must carry the handle Schema.Execute resolves, and it
-- must survive the SavedVariables round trip a /reload performs.
local ctx = A.GetContext()
Check(type(ctx.pendingChoices) == "table" and #ctx.pendingChoices == #A.pendingChoices,
    "pending choices must be mirrored into the persisted context")
local serializedSemanticIds = 0
for i = 1, #ctx.pendingChoices do
    local row = ctx.pendingChoices[i]
    if type(row) == "table" and type(row.schemaSemanticId) == "string" and row.schemaSemanticId ~= "" then
        serializedSemanticIds = serializedSemanticIds + 1
    end
end
Check(serializedSemanticIds >= 2,
    "catalog-backed choices must serialize their schema semantic id, got "
    .. tostring(serializedSemanticIds) .. " for '" .. tostring(prompt) .. "'")

-- A numbered reply resolves to the entry the player picked. Under the desktop
-- stubs the live Menu2 catalog is absent, so the transaction itself cannot
-- complete -- Schema.Execute returns catalog_unavailable exactly as it does for
-- the pre-existing unambiguous catalog path. The contract pinned here is the
-- routing: the answer is about the chosen control and is never the
-- "no pending request" dead end.
local secondLabel = numbered[2]
local picked = A.HandleInput("2") or {}
local pickedText = tostring(picked.text or "")
Check(pickedText:find("not sure which MSUF request", 1, true) == nil,
    "a numbered reply must not fall through to the no-pending-request answer: " .. pickedText)
Check(secondLabel and pickedText:find(secondLabel, 1, true) ~= nil,
    "the reply must name the chosen entry '" .. tostring(secondLabel) .. "', got: " .. pickedText)

-- Same selection, rebuilt from SavedVariables alone.
Reset()
Schema.TryConversation(prompt)
A.pendingChoices, A.pendingCandidates = nil, nil
local afterReload = A.HandleInput("2") or {}
local reloadText = tostring(afterReload.text or "")
Check(reloadText:find("not sure which MSUF request", 1, true) == nil,
    "a numbered reply must still resolve after a reload: " .. reloadText)
Check(secondLabel and reloadText:find(secondLabel, 1, true) ~= nil,
    "the rehydrated choice must still name '" .. tostring(secondLabel) .. "', got: " .. reloadText)

-- The fallback, where no selectable choice could be built (no value in the
-- sentence), must not tell the player to reply with a number. Driven through
-- the router because that is where a player meets it.
Reset()
local fallback = A.HandleInput("make the health bar bigger") or {}
local fallbackText = tostring(fallback.text or "")
if tostring(fallback.result or fallback.status or "") == "needs_choice" then
    Check(fallbackText:find("0%. Cancel") == nil,
        "the no-choice fallback must not render a selectable list:\n" .. fallbackText)
    Check(fallbackText:find("Select one by number", 1, true) == nil,
        "the no-choice fallback must not promise a numbered reply:\n" .. fallbackText)
    Check(fallbackText:find("Name the frame or page", 1, true) ~= nil,
        "the no-choice fallback must say what the player should do instead:\n" .. fallbackText)
    -- Its location list is still numbered from 1 when it lists several.
    if fallbackText:find("close controls", 1, true) then
        Check(fallbackText:find("\n1%. ") ~= nil,
            "a multi-entry location list must number its first entry:\n" .. fallbackText)
    end
end

print("assistant_schema_ambiguous_choice_smoke: PASS (" .. tostring(prompt) .. ")")

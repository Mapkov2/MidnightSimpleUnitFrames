-- Screenshot regression: when the user names a frame ("player frame"), a
-- reviewed curated per-frame setting must win over a generated frameType=general
-- fallback that owns the same attribute.  Before the fix, "change the hp text
-- separator on player frame" resolved to the unconstrained generated
-- general.hpTextSeparator string and was refused, instead of the curated
-- player.hpTextSeparator enum.
--
-- P.GeneratedGeneralShadowedByScopedSetting is the guard; this drives it against
-- a controlled registry and then confirms the real parser resolves the prompt.
_G = _G or _ENV
_G.unpack = _G.unpack or table.unpack -- WoW Lua 5.1 has global unpack; desktop 5.4 needs the shim.

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

-- Part 1: the guard in isolation, against a controlled registry.
do
    local MSUF = { MSUF2 = {}, Assistant = {} }
    local M, A = MSUF.MSUF2, MSUF.Assistant
    _G.MSUF_NS, _G.MSUF2 = MSUF, M

    local SETTINGS = {
        { key = "player.hpTextSeparator", unit = "player", frameType = "unitframe", attribute = "hpTextSeparator", type = "enum" },
        { key = "general.hpTextSeparator", unit = nil, frameType = "general", attribute = "hpTextSeparator", type = "string", generated = true },
        -- A genuine global feature with no curated per-frame twin must stay matchable.
        { key = "general.someGlobalOnlyThing", unit = nil, frameType = "general", attribute = "someGlobalOnlyThing", type = "boolean", generated = true },
    }
    local Registry = { byKey = {} }
    for i = 1, #SETTINGS do Registry.byKey[SETTINGS[i].key] = SETTINGS[i] end
    function Registry:GetSetting(k) return self.byKey[k] end
    function Registry:AllSettings() return SETTINGS end
    function Registry:FindSettings(filter)
        local out = {}
        for i = 1, #SETTINGS do
            local s = SETTINGS[i]
            local ok = true
            if filter.unit ~= nil and s.unit ~= filter.unit then ok = false end
            if filter.attribute ~= nil and s.attribute ~= filter.attribute then ok = false end
            if ok then out[#out + 1] = s end
        end
        return out
    end
    A.Registry = Registry

    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Registry.lua"))
    chunk("MidnightSimpleUnitFrames", MSUF)
    local P = A.Parser
    Check(type(P.GeneratedGeneralShadowedByScopedSetting) == "function", "guard must be defined")

    local general = Registry:GetSetting("general.hpTextSeparator")
    local player = Registry:GetSetting("player.hpTextSeparator")
    local globalOnly = Registry:GetSetting("general.someGlobalOnlyThing")

    -- With an explicit "player" scope, the generated general fallback is shadowed
    -- by the curated player twin and must be excluded.
    Check(P.GeneratedGeneralShadowedByScopedSetting(general, { "player" }, {}) == true,
        "generated general fallback must be shadowed when a curated player twin owns the attribute")
    -- The curated per-frame setting itself is never shadowed.
    Check(P.GeneratedGeneralShadowedByScopedSetting(player, { "player" }, {}) == false,
        "the curated per-frame setting must never be excluded")
    -- A global-only generated feature with no curated twin stays matchable.
    Check(P.GeneratedGeneralShadowedByScopedSetting(globalOnly, { "player" }, {}) == false,
        "a genuine global-only feature must not be excluded")
    -- No explicit scope -> no shadowing (global requests still reach the general).
    Check(P.GeneratedGeneralShadowedByScopedSetting(general, {}, {}) == false,
        "without an explicit scope the general fallback stays allowed")
end

-- Part 2: the real registry + parser resolve the screenshot prompt to a
-- scoped setting instead of refusing the generated general string.
do
    local realMSUF = { MSUF2 = {}, Assistant = {} }
    _G.MSUF_NS, _G.MSUF2 = realMSUF, realMSUF.MSUF2
    local function e(p) local h = io.open(p, "r") if h then h:close() return true end return false end
    dofile((e(root .. "/tools/assistant_runtime_manifest_loader.lua") and root .. "/tools/assistant_runtime_manifest_loader.lua")
        or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
    dofile((e(root .. "/tools/assistant_dashboard_smoke.lua") and root .. "/tools/assistant_dashboard_smoke.lua")
        or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
    local A = _G.MSUF_NS.Assistant
    if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end

    local function freshContext()
        if A.GetContext then local c = A.GetContext() for k in pairs(c) do c[k] = nil end end
    end

    -- The generated general fallback must no longer be the chosen mutation target
    -- for an explicitly scoped request.
    freshContext()
    local res = A.Parser.ParseRegistryAlias("change the hp text separator on player frame to a dash",
        "change the hp text separator on player frame to a dash")
    local chosen = res and res.changes and res.changes[1] and res.changes[1].setting
    local chosenKey = chosen and chosen.key
    Check(chosenKey ~= "general.hpTextSeparator",
        "an explicitly-scoped request must not resolve to the generated general fallback, got " .. tostring(chosenKey))
    Check(chosenKey == nil or tostring(chosenKey):sub(1, 7) == "player.",
        "a scoped request should resolve within the player scope, got " .. tostring(chosenKey))

    -- Part 3: prove the WHOLE class, not just the separator.  For every generated
    -- frameType=general fallback that has a curated scoped twin sharing its
    -- attribute, the guard must shadow that fallback for every twin unit.  This
    -- audit is self-extending: any future general fallback that would let a
    -- scoped request fall to the generic string/number breaks this gate.
    local Reg = A.Registry
    local scopedByAttr = {}
    for _, s in ipairs(Reg:AllSettings()) do
        if s.generated ~= true and s.unit and s.unit ~= "global" and s.unit ~= "" and s.attribute then
            scopedByAttr[s.attribute] = scopedByAttr[s.attribute] or {}
            scopedByAttr[s.attribute][s.unit] = s.key
        end
    end
    local checked, notShadowed = 0, {}
    for _, s in ipairs(Reg:AllSettings()) do
        if s.generated == true and tostring(s.frameType) == "general"
            and s.attribute and scopedByAttr[s.attribute]
        then
            for unit, twinKey in pairs(scopedByAttr[s.attribute]) do
                checked = checked + 1
                if A.Parser.GeneratedGeneralShadowedByScopedSetting(s, { unit }, {}) ~= true then
                    notShadowed[#notShadowed + 1] = s.key .. " on " .. unit .. " (twin " .. twinKey .. ")"
                end
            end
        end
    end
    Check(checked > 0, "the audit must find generated general fallbacks with curated twins")
    Check(#notShadowed == 0, "every generated general fallback with a curated twin must be shadowed; unshadowed: "
        .. table.concat(notShadowed, "; "))
    io.write("scope-priority class audit: " .. tostring(checked) .. " general/unit combos, all shadowed\n")
end

print("assistant_scope_priority_smoke: PASS")

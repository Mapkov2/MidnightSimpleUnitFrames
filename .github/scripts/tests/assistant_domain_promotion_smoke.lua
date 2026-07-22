-- Charge 1: promote generated read-only number settings to a safe write domain
-- whenever a reviewed curated sibling with the same leaf key supplies one.
--
-- Every promotion must inherit a real min<max from a curated source, match its
-- percent flag, and clamp writes.  Generic leaves (size/width/x/...) and any
-- leaf whose curated siblings disagree must never be promoted, so the assistant
-- never guesses a value domain.  This exercises Auto.PromoteInheritedNumberDomains
-- directly against a controlled registry, then against the real one.
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local MSUF = { MSUF2 = {}, Assistant = {} }
local M, A = MSUF.MSUF2, MSUF.Assistant
_G.MSUF_NS, _G.MSUF2 = MSUF, M

-- Controlled registry: a few curated number settings plus generated read-only
-- twins, including the adversarial cases (generic leaf, conflicting domains).
local SETTINGS = {}
local function Reg(spec) SETTINGS[#SETTINGS + 1] = spec; return spec end
-- Curated sources.
Reg({ key = "player.combatStateIndicatorSize", type = "number", min = 8, max = 64, step = 1 })
Reg({ key = "target.combatStateIndicatorSize", type = "number", min = 8, max = 64, step = 1 })
Reg({ key = "player.portraitSize", type = "number", min = 10, max = 100, step = 1 }) -- generic leaf "portraitSize" is specific, fine
Reg({ key = "player.width", type = "number", min = 50, max = 400, step = 1 })       -- generic leaf "width"
Reg({ key = "player.healPredAlpha", type = "number", min = 0, max = 1, percent = true })
-- Conflicting curated domains for the same leaf "coolLeaf".
Reg({ key = "player.coolLeaf", type = "number", min = 0, max = 10 })
Reg({ key = "target.coolLeaf", type = "number", min = 0, max = 999 })
-- Generated read-only twins to be promoted (or not).
Reg({ key = "boss.combatStateIndicatorSize", type = "number", generated = true, assistantMutationSafe = false,
      set = function(spec, v) end })
Reg({ key = "boss.portraitSize", type = "number", generated = true, assistantMutationSafe = false })
Reg({ key = "boss.width", type = "number", generated = true, assistantMutationSafe = false })            -- generic leaf: must NOT promote
Reg({ key = "boss.healPredAlpha", type = "number", generated = true, assistantMutationSafe = false })    -- percent must transfer
Reg({ key = "boss.coolLeaf", type = "number", generated = true, assistantMutationSafe = false })         -- conflicting: must NOT promote
Reg({ key = "boss.orphanNumber", type = "number", generated = true, assistantMutationSafe = false })     -- no sibling: must NOT promote

local Registry = { byKey = {} }
for i = 1, #SETTINGS do Registry.byKey[SETTINGS[i].key] = SETTINGS[i] end
function Registry:AllSettings() return SETTINGS end
function Registry:GetSetting(k) return self.byKey[k] end
A.Registry = Registry

-- Load only the AutoCoverage module; the promotion pass needs nothing else.
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local Auto = A.AutoCoverage
Check(type(Auto.PromoteInheritedNumberDomains) == "function", "promotion pass must be defined")

local promoted = Auto.PromoteInheritedNumberDomains()
local function S(k) return Registry:GetSetting(k) end

-- combatStateIndicatorSize: two agreeing curated sources -> promote with [8..64].
local promo = S("boss.combatStateIndicatorSize")
Check(promo.assistantMutationSafe == true, "agreeing-domain twin must be promoted")
Check(promo.min == 8 and promo.max == 64, "promoted domain must match the curated sibling")
Check(promo.generatedMutationSafety == "inherited-curated-domain", "promotion must be tagged")
Check(promo.mutationDomainSource ~= nil, "promotion must record its domain source")
Check(promo.unsafeMutationReason == nil, "promotion must clear the unsafe reason")

-- portraitSize: single specific curated source -> promote.
Check(S("boss.portraitSize").assistantMutationSafe == true, "specific single-source twin must be promoted")

-- percent flag must transfer so the setter's percent math stays correct.
local alpha = S("boss.healPredAlpha")
Check(alpha.assistantMutationSafe == true and alpha.percent == true,
    "a percent domain must transfer its percent flag")

-- Generic leaf "width": must NEVER be promoted even with an agreeing source.
Check(S("boss.width").assistantMutationSafe == false, "a generic leaf must never be promoted")

-- Conflicting curated domains: must NEVER be promoted.
Check(S("boss.coolLeaf").assistantMutationSafe == false, "a conflicting-domain leaf must never be promoted")

-- No curated sibling: must NEVER be promoted.
Check(S("boss.orphanNumber").assistantMutationSafe == false, "a leaf with no curated sibling must stay read-only")

-- Exactly the three safe twins were promoted.
Check(promoted == 3, "exactly the three safe twins must be promoted, got " .. tostring(promoted))

-- Idempotent: a second pass promotes nothing new.
Check(Auto.PromoteInheritedNumberDomains() == 0, "re-running the pass must be idempotent")

-- Now confirm it behaves against the REAL registry: promotes a positive count,
-- and every promotion carries a valid inherited domain.
do
    local realMSUF = { MSUF2 = {}, Assistant = {} }
    _G.MSUF_NS, _G.MSUF2 = realMSUF, realMSUF.MSUF2
    local function e(p) local h = io.open(p, "r") if h then h:close() return true end return false end
    dofile((e(root .. "/tools/assistant_runtime_manifest_loader.lua") and root .. "/tools/assistant_runtime_manifest_loader.lua")
        or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
    dofile((e(root .. "/tools/assistant_dashboard_smoke.lua") and root .. "/tools/assistant_dashboard_smoke.lua")
        or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
    local RA = _G.MSUF_NS.Assistant
    if RA.AutoCoverage and RA.AutoCoverage.EnsureFilled then pcall(RA.AutoCoverage.EnsureFilled) end
    local realReg = RA.Registry
    local realPromoted, invalid = 0, 0
    for _, s in ipairs(realReg:AllSettings()) do
        if type(s) == "table" and s.generatedMutationSafety == "inherited-curated-domain" then
            realPromoted = realPromoted + 1
            if not (s.min and s.max and s.min < s.max and s.assistantMutationSafe == true
                and s.mutationDomainSource) then
                invalid = invalid + 1
            end
        end
    end
    Check(realPromoted > 0, "the real registry must promote at least one generated number")
    Check(invalid == 0, "no real promotion may carry an invalid or unsourced domain")
    io.write("real registry promotions = " .. tostring(realPromoted) .. "\n")
end

print("assistant_domain_promotion_smoke: PASS")

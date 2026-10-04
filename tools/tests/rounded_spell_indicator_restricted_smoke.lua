-- rounded_spell_indicator_restricted_smoke.lua <repoRoot>
--
-- Issue #160. Spell Indicator edges are textures on the effect root of a
-- native AuraButton. While auras are secret (combat, arena) Blizzard restricts
-- that button and all of its descendants: CanBeAccessedInContext() answers
-- false or a secret, IsForbidden() stays false, and Show or Hide on an edge
-- throws. RefreshSpellIndicatorRoundedEdges
-- (UnitFrames/Effects/MSUF_UF_RoundedFrames.lua) runs on every rounded apply.
-- It re-showed the rounded edge, and its square fallback then threw on Hide.
-- On a party frame the error escaped GF.RefreshHeaderLayout and aborted the
-- rest of the PLAYER_ENTERING_WORLD handler, so Solo Shuffle party frames
-- stayed empty until a reload.
--
-- A restricted button must be skipped without touching its edges, keep the
-- edges it has, and be restyled by the first refresh that finds it writable.
--
-- Plain Lua 5.1, repo root as arg 1. Boots each client's real load graph.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local SECRET = setmetatable({}, { __tostring = function() return "a secret" end })

-- The button and everything below it, as the client restricts them.
local function Descendants(widget, out)
    out[#out + 1] = widget
    for _, region in ipairs(widget.regions) do out[#out + 1] = region end
    for _, child in ipairs(widget.children) do Descendants(child, out) end
    return out
end

-- Every method call on a restricted widget raises, as in the client, except
-- the access query, which returns `answer`. Returns the function that lifts
-- the restriction again.
local function Restrict(widgets, answer)
    local saved = {}
    for _, widget in ipairs(widgets) do
        local meta = getmetatable(widget)
        local methods = meta.__index
        saved[widget] = meta
        setmetatable(widget, { __index = function(_, key)
            if key == "CanBeAccessedInContext" then
                return function() return answer end
            end
            local value = methods[key]
            if type(value) ~= "function" then return value end
            return function()
                error("calling '" .. key .. "' on bad self (Attempt to access forbidden object"
                    .. " from code tainted by an AddOn)", 2)
            end
        end })
    end
    return function()
        for widget, meta in pairs(saved) do setmetatable(widget, meta) end
    end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    local isSecret = env.issecretvalue
    env.issecretvalue = function(value) return value == SECRET or isSecret(value) end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local bars = env.MSUF_DB.bars
    bars.roundedFramesEnabled = true
    bars.roundedUnitFrames = true

    local UF = world.core.UF
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = "player"
    frame.MSUFSpec = { key = "player" }
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    -- The rounded pass walks the core's frame list (UF.ForEachFrame).
    local list = UF.frameList
    list[#list + 1] = frame

    local function Apply(label)
        local ok, err = pcall(env.MSUF_ApplyRoundedUnitframes)
        Check(ok, flavor .. ": " .. label .. ": the rounded apply raised: " .. tostring(err))
    end
    Apply("startup")

    -- A native AuraButton with a Spell Indicator border, built the way
    -- MSUF_Auras3_SpellIndicators_Effects.lua builds it (EnsureEffectRoot,
    -- EnsureEdges, LayoutEdges, ApplyButtonFrameEffect).
    local button = env.CreateFrame("Button", nil, frame)
    local effectRoot = env.CreateFrame("Frame", nil, button)
    button._msufA3SpellIndicatorEffectRoot = effectRoot
    local square = {}
    for i = 1, 4 do square[i] = effectRoot:CreateTexture(nil, "OVERLAY") end
    button._msufA3SpellIndicatorEdges = square
    frame._msufA3SpellIndicatorEffectButtons = { [button] = true }
    local edgeHook = env.MSUF_RoundedUF_OnSpellIndicatorEdge
    Check(type(edgeHook) == "function", flavor .. ": the Spell Indicator edge hook is not exported")
    Check(edgeHook(button, frame, frame.hpBar:GetStatusBarTexture(), true, 2, 1, 0.5, 0, 1, "BLEND") == true,
        flavor .. ": a writable button did not get a rounded Spell Indicator edge")
    for i = 1, 4 do square[i]:Hide() end
    local edge = button._msufRUFSpellIndicatorEdge

    local function Expect(rounded, label)
        Check(edge.shown == rounded, flavor .. ": " .. label .. ": the rounded edge is "
            .. (edge.shown and "shown" or "hidden"))
        for i = 1, 4 do
            Check(square[i].shown == not rounded, flavor .. ": " .. label .. ": square edge " .. i .. " is "
                .. (square[i].shown and "shown" or "hidden"))
        end
    end

    Apply("writable, rounded on")
    Expect(true, "writable, rounded on")

    -- Restricted (false): neither the rounded edge (the reported Show) nor the
    -- square fallback (the reported Hide) may be touched; the edges stay.
    local release = Restrict(Descendants(button, {}), false)
    Apply("restricted, rounded on")
    bars.roundedFramesEnabled = false
    Apply("restricted, rounded off")
    release()
    Expect(true, "restricted, rounded off")

    -- Writable again: the first refresh catches up.
    Apply("writable, rounded off")
    Expect(false, "writable, rounded off")

    -- A secret answer is a restriction too.
    release = Restrict(Descendants(button, {}), SECRET)
    Apply("secret access, rounded off")
    bars.roundedFramesEnabled = true
    Apply("secret access, rounded on")
    release()
    Expect(false, "secret access, rounded on")

    Apply("writable again, rounded on")
    Expect(true, "writable again, rounded on")

    list[#list] = nil
    print("rounded_spell_indicator_restricted_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end

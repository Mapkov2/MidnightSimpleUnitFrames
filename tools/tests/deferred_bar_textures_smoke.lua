-- deferred_bar_textures_smoke.lua <repoRoot>
--
-- Runtime/MSUF_TextureRuntime.lua replaces MSUF_UpdateAllBarTextures with a
-- deferred wrapper once the immediate pass is published. A unit scope marks
-- its frames dirty for the UF apply commit. A call without a scope (the LSM
-- texture migration in Kernel/MSUF_Libs.lua and Media/MSUF_Media.lua) and a
-- group scope have no dirty-frame route: the wrapper only scheduled an empty
-- commit, so the new texture never reached the bars until something else
-- repainted them. Pinned here on each client's real load graph:
--   * a global or group request repaints on the next frame, exactly once per
--     burst, and a global request covers the scoped ones;
--   * a unit scope still goes through MarkDirty plus the apply commit;
--   * the unprefixed UpdateAllBarTextures stays as a compatibility alias, but
--     never replaces a global another addon already owns.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor, foreignAlias)
    local world = World.New(root, flavor)
    local env = world.env
    if foreignAlias then env.UpdateAllBarTextures = foreignAlias end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local core = world.core
    local immediate = env.MSUF_UpdateAllBarTextures_Immediate
    Check(type(immediate) == "function" and immediate ~= env.MSUF_UpdateAllBarTextures,
        flavor .. ": the deferred texture wrapper is not installed")
    if foreignAlias then
        Check(env.UpdateAllBarTextures == foreignAlias, flavor .. ": another addon's UpdateAllBarTextures was replaced")
    else
        Check(env.UpdateAllBarTextures == immediate, flavor .. ": the UpdateAllBarTextures compatibility alias is gone")
    end

    -- Every texture pass refreshes the prediction elements once with its own
    -- reason; count the outermost of those calls.
    local passes, depth = 0, 0
    local UF = core.UF
    for _, name in ipairs({ "RefreshElements", "RefreshPredictionBars" }) do
        local original = UF[name]
        if type(original) == "function" then
            UF[name] = function(a, b, c, ...)
                local isPass = a == "MSUF2_BAR_TEXTURE" or b == "MSUF2_BAR_TEXTURE" or c == "MSUF2_BAR_TEXTURE"
                if isPass and depth == 0 then passes = passes + 1 end
                if isPass then depth = depth + 1 end
                local r1, r2 = original(a, b, c, ...)
                if isPass then depth = depth - 1 end
                return r1, r2
            end
        end
    end
    local scheduler = core.Scheduler
    local function NextFrame()
        local onUpdate = scheduler.frame:GetScript("OnUpdate")
        if onUpdate then onUpdate(scheduler.frame, 0.016) end
    end
    NextFrame()
    passes = 0

    env.MSUF_UpdateAllBarTextures()
    Check(passes == 0, flavor .. ": the deferred request repainted at once")
    env.MSUF_UpdateAllBarTextures()
    env.MSUF_UpdateAllBarTextures("gf_party")
    NextFrame()
    Check(passes == 1, flavor .. ": a global request did not repaint exactly once on the next frame (got " .. passes .. ")")
    NextFrame()
    Check(passes == 1, flavor .. ": the deferred repaint ran again without a request")

    -- A group scope repaints through the group visuals, once per burst.
    local GF = core.GF
    local refreshVisuals = GF.RefreshVisuals
    local groupPasses = 0
    GF.RefreshVisuals = function(kind, ...)
        if kind == "party" then groupPasses = groupPasses + 1 end
        return refreshVisuals(kind, ...)
    end
    env.MSUF_UpdateAllBarTextures("gf_party")
    env.MSUF_UpdateAllBarTextures("gf_party")
    Check(groupPasses == 0, flavor .. ": the deferred group request repainted at once")
    NextFrame()
    GF.RefreshVisuals = refreshVisuals
    Check(groupPasses == 1, flavor .. ": a group request did not repaint exactly once (got " .. groupPasses .. ")")

    -- A unit scope keeps the dirty-frame route and paints nothing directly.
    local marked = {}
    local markDirty = UF.MarkDirty
    UF.MarkDirty = function(key, ...)
        marked[#marked + 1] = key
        return markDirty(key, ...)
    end
    passes = 0
    -- (The commit itself is the engine's apply, not under test here.)
    env.MSUF_UpdateAllBarTextures("player")
    UF.MarkDirty = markDirty
    Check(marked[1] == "player", flavor .. ": a unit scope no longer marks its frames dirty")
    Check(passes == 0, flavor .. ": a unit scope ran the full texture pass")
    print("deferred_bar_textures_smoke: ok (" .. flavor .. (foreignAlias and ", foreign alias" or "") .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
Run("Mainline", function() return "another addon" end)

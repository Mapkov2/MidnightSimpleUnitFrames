-- totem_manager_flag_smoke.lua <repoRoot>
--
-- Features/Gameplay/MSUF_Feature_TotemPreview.lua moves Blizzard's TotemFrame.
-- ManagedFrameContainerMixin:AddManagedFrame (Blizzard_ManagedFrameSystem/
-- Shared/ManagedFrameSystem.lua:58; Classic Blizzard_UIParent/Shared/UIParent.lua:163)
-- re-adds the frame on every show unless frame.ignoreFramePositionManager is
-- set, and nothing may move it back in combat, so that field is the only lever.
-- It is a field on Blizzard's frame that Blizzard code reads: MSUF writes it
-- once per ownership, never on Blizzard's own rebuilds (TotemFrameMixin:Update,
-- which runs on every totem change), and hands the saved value back on release.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

for _, flavor in ipairs({ "Mainline", "TBC" }) do
    local world = World.New(root, flavor)
    local env = world.env
    -- Blizzard's TotemFrame with the managed-frame flag behind a write counter.
    local totem = world.widgets:CreateFrame("Frame", "TotemFrame", world.widgets.UIParent)
    local methods = getmetatable(totem).__index
    local flag, writes = nil, 0
    setmetatable(totem, {
        __index = function(_, key)
            if key == "ignoreFramePositionManager" then return flag end
            return methods[key]
        end,
        __newindex = function(t, key, value)
            if key == "ignoreFramePositionManager" then
                writes, flag = writes + 1, value
            else
                rawset(t, key, value)
            end
        end,
    })
    function totem.Update() end
    function totem.Layout() end
    env.TotemFrame = totem
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local ns = world.core
    local g = assert(ns.MSUF_GetGameplayDBFast or ns.MSUF_EnsureGameplayDefaults, flavor .. ": no gameplay DB")()
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(flag == true and writes == 1, flavor .. ": taking TotemFrame over wrote the managed-frame flag "
        .. writes .. " time(s)")
    for _ = 1, 5 do totem:Update() end
    Check(flag == true and writes == 1, flavor .. ": Blizzard's TotemFrame rebuilds rewrote the managed-frame flag ("
        .. writes .. " writes after 5 rebuilds)")
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(flag == nil and writes == 2, flavor .. ": releasing TotemFrame did not hand the flag back once ("
        .. tostring(flag) .. ", " .. writes .. " writes)")
    for _ = 1, 3 do totem:Update() end
    Check(writes == 2, flavor .. ": a released TotemFrame still gets the managed-frame flag written")
    print("totem_manager_flag_smoke: ok (" .. flavor .. ")")
end

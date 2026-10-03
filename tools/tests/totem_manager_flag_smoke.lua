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
-- Each takeover captures its own layout snapshot (a second takeover restores
-- the layout Blizzard had before it, not the one from the first takeover), and
-- a release hands the flag back only while it still holds the value MSUF
-- assigned: a change another owner made in between stays.
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

    -- A second takeover from a layout Blizzard changed after the first release.
    local blizzardParent = world.widgets:CreateFrame("Frame", nil, world.widgets.UIParent)
    totem:SetParent(blizzardParent)
    totem:ClearAllPoints()
    totem:SetPoint("TOPRIGHT", blizzardParent, "BOTTOMRIGHT", 7, 20)
    totem:SetScale(0.8)
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(totem:GetParent() ~= blizzardParent, flavor .. ": the second takeover did not take TotemFrame")
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    local point, relativeTo, relativePoint, x, y = totem:GetPoint(1)
    Check(totem:GetParent() == blizzardParent and totem:GetNumPoints() == 1 and point == "TOPRIGHT"
        and relativeTo == blizzardParent and relativePoint == "BOTTOMRIGHT" and x == 7 and y == 20
        and math.abs(totem:GetScale() - 0.8) < 0.001,
        flavor .. ": the second release restored the first takeover's layout, not Blizzard's current one")

    -- Another owner changes the flag while MSUF owns the frame.
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(flag == true, flavor .. ": the third takeover did not set the managed-frame flag")
    totem.ignoreFramePositionManager = false
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(flag == false, flavor .. ": the release overwrote another owner's managed-frame flag ("
        .. tostring(flag) .. ")")
    -- A flag another owner set before MSUF took over is not MSUF's to hand back.
    totem.ignoreFramePositionManager = true
    local before = writes
    g.enablePlayerTotems = true
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    g.enablePlayerTotems = false
    ns.MSUF_Gameplay_PlayerTotems_Apply(g)
    Check(flag == true and writes == before, flavor .. ": MSUF cleared a managed-frame flag it never assigned")
    totem.ignoreFramePositionManager = nil
    print("totem_manager_flag_smoke: ok (" .. flavor .. ")")
end

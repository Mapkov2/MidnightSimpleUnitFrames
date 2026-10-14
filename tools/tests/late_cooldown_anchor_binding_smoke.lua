-- Late optional providers are resolved by the real factory event handler.
local root, flavor = assert(arg[1]):gsub("\\", "/"), assert(arg[2])
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor)
local e = w.env
e.IsCooldownViewerAnchorUsable = function() error("unowned global anchor predicate reached") end
local frame, handler
for _, region in ipairs(w.h.widgets.frames) do
    local onEvent = region:GetScript("OnEvent")
    if region.events.EDIT_MODE_LAYOUTS_UPDATED and region.events.PLAYER_REGEN_DISABLED and onEvent
        and debug.getinfo(onEvent, "S").source:find("MSUF_UF_Factory.lua", 1, true) then
        assert(not handler, "duplicate factory late-anchor event owner")
        frame, handler = region, onEvent
    end
end
assert(handler, "real late-anchor event owner missing")
local calls = 0
local source = e.CreateFrame("Frame", nil, e.UIParent)
source:SetPoint("CENTER", e.UIParent, "CENTER", 0, 0)
e.MSUF_DB.general.anchorName = "EssentialCooldownViewer"
for _, shape in ipairs({ false, {}, setmetatable({}, { __call = function() error("callable table invoked") end }),
    function() calls = calls + 1; return source end }) do
    e.MSUF_GetEffectiveCooldownFrame = shape
    e.MSUF_GetUsableCooldownAnchorSize = function() return 100, 24 end
    handler(frame, "ADDON_LOADED", "ForeignAnchorProvider")
end
assert(calls > 0, "late callable provider did not run")
print("late_cooldown_anchor_binding_smoke: ok (" .. flavor .. ")")

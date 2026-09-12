-- The shared Aura modules must work before any page builder or preview loads.
local root = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
local function Values(text, ...)
    local out = {}
    if select("#", ...) > 0 then
        local values = { text, ... }
        for i = 1, #values, 2 do out[#out + 1] = { value = values[i], text = values[i + 1] } end
    else
        for item in text:gmatch("[^|]+") do
            local value, label = item:match("^(.-)=(.*)$")
            out[#out + 1] = { value = value, text = label }
        end
    end
    return out
end
local db, timers, applies, refreshes = { general = {} }, {}, {}, {}
local M = {
    ValueTextList = Values, ValueTextPairs = Values,
    KeySetFromWords = function(text) local t = {}; for word in text:gmatch("%S+") do t[word] = true end; return t end,
    EnsureDB = function() return db end,
    Format = string.format,
    MenuTimer = { After = function(_, callback) timers[#timers + 1] = callback end },
    RequestRefresh = function(ctx, reason) refreshes[#refreshes + 1] = { ctx, reason } end,
    ApplyService = { RequestAuras = function(scope, reason) applies[#applies + 1] = { scope, reason } end },
}
function M.SetMenuStateValue(key, value) M[key] = value end
local ns = { MSUF2 = M, MSUF_Auras3 = { MenuModel = {} } }
assert(loadfile(root .. "MSUF_Menu2_AuraSettings.lua"))("MSUF", ns)
assert(loadfile(root .. "MSUF_Menu2_AuraControls.lua"))("MSUF", ns)
assert(M.AurasPage == nil, "shared contracts must not require or create a page")
local settings, controls = M.AuraSettings, M.AuraControls
assert(settings.NormalizeAuraSortMethodForLane("buff", "unit_frame_debuff") == "DEFAULT")
assert(settings.NormalizeAuraSortMethodForLane("debuff", "unit_frame_debuff") == "UNIT_FRAME_DEBUFF")
assert(settings.NormalizeAuraSortMethodForLane("buff", "custom_priority", true) == "CUSTOM_PRIORITY")
settings.SetCurrentLane("unitLane", "buff")
assert(M.unitLane == "buff" and M.auraStyleGFLane == "buff")
local ctx = { key = "uf_player" }
local meta = controls.AuraControlMeta(ctx, "Lane/Custom Foo", "setting", "player.aura.setting")
assert(meta.controlId == "menu2.uf_player.auras.lane.custom-foo" and meta.settingKey == "player.aura.setting", "stable Aura control identity changed")
controls.ApplyUnit(ctx, "player", "first", true)
controls.ApplyUnit(ctx, "player", "second", true)
assert(#applies == 2 and #timers == 1 and #refreshes == 0, "shared apply changed coalescing")
timers[1]()
assert(#refreshes == 1 and refreshes[1][1] == ctx and refreshes[1][2] == "second", "latest refresh context/reason lost")
print("aura_contracts_smoke: OK (independent settings/controls, stable identities, coalescing)")

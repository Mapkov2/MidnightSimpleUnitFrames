-- menu_control_catalog_contracts_smoke.lua <repoRoot>
--
-- The removed in-game Assistant executed menu controls through a command
-- contract built for every bound control (getValues/labelFn/refresh/
-- blockCombat closures, value ranges, catalog issue logs). Nothing reads that
-- any more (review 2026-09-30, F10): a bound control carries only its identity,
-- its source and get/set. The catalog also validates declared setting-key
-- patterns for real (F17): string.match("", p) used to accept patterns that
-- raise on the first real key, e.g. a trailing "%".
--
-- Boots the real Mainline core and Options graph. Plain Lua 5.1, repo root.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_control_catalog_contracts_smoke: " .. message, 2) end
    return condition
end

local world = World.New(root, "Mainline")
world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local e, M = world.env, world.core.MSUF2
local Catalog = Check(M.RuntimeControlCatalog, "runtime control catalog missing")

---------------------------------------------------------------------------
-- 1. A bound control keeps identity and get/set only
---------------------------------------------------------------------------
local db = Check(M.EnsureDB(), "profile DB missing")
local ctx = { key = "uf_player", refreshers = {} }
local toggle = e.CreateFrame("CheckButton", nil, e.UIParent)
function toggle:SetChecked(value) self.checked = value end
M.BindToggle(ctx, toggle, function() return db.player.showPower end, function(value) db.player.showPower = value end,
    { controlId = "menu2.smoke.catalog.toggle", settingKey = "player.showPower", classification = "setting" })
local command = Check(toggle._msuf2CommandAction, "the bound toggle has no command")
Check(command.kind == "toggle" and command.settingKey == "player.showPower" and command.controlId == "menu2.smoke.catalog.toggle"
    and type(command.get) == "function" and type(command.set) == "function" and type(command.sourceFn) == "function",
    "the bound command lost its identity, source or get/set")
for _, field in ipairs({ "getValues", "labelFn", "refresh", "blockCombat", "min", "max", "step", "values", "valueKind",
    "percentIsValue", "historyMode", "label", "actionInputArg", "actionFixedArgs", "identityKey", "controlPath" }) do
    Check(command[field] == nil, "the bound command still builds the execution field " .. field)
end
local record = Check(Catalog.Get("menu2.smoke.catalog.toggle"), "the bound toggle is not in the catalog")
Check(record.classification == "setting" and record.settingKey == "player.showPower", "the catalog misclassified the toggle")
Check(record.sources == nil and record.registrationCount == nil, "the catalog still keeps registration audit fields")
Check(Catalog.GetRevision == nil and Catalog._state.issues == nil, "the catalog still keeps its issue log or revision API")
local exact = Catalog.FindBySettingKey("player.showPower", "uf_player")
Check(exact and exact.controlId == "menu2.smoke.catalog.toggle" and exact.sources == nil, "FindBySettingKey lost the toggle")

---------------------------------------------------------------------------
-- 2. Declared setting-key patterns are validated, not trusted
---------------------------------------------------------------------------
local aliasWidget = e.CreateFrame("Frame", nil, e.UIParent)
M.RegisterRuntimeControl(aliasWidget, { controlId = "menu2.smoke.catalog.patterns", pageKey = "zz_catalog", kind = "dropdown",
    label = "Pattern proof", classification = "setting",
    searchSettingKeyPatterns = { "^zzsmoke%", "^zzsmoke(", "zzsmoke[", "^zzsmoke%.%w+$" } }, "smoke")
local patterns = Check(Catalog.Get("menu2.smoke.catalog.patterns"), "the pattern control is not in the catalog").searchSettingKeyPatterns
Check(#patterns == 1 and patterns[1] == "^zzsmoke%.%w+$", "malformed setting-key patterns were kept: " .. table.concat(patterns, " "))
local ok, found = pcall(Catalog.FindBySettingKey, "zzsmoke.value", "zz_catalog")
Check(ok, "a declared pattern raised during setting lookup: " .. tostring(found))
Check(found and found.controlId == "menu2.smoke.catalog.patterns", "the valid declared pattern no longer resolves")

print("menu_control_catalog_contracts_smoke: ok (bound commands carry identity and get/set only; patterns validated)")

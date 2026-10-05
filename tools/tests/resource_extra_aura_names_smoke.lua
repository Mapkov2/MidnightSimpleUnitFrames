-- resource_extra_aura_names_smoke.lua <repoRoot>
--
-- The Edit Mode sample of the additional resources (ClassPower/
-- MSUF_CP_ExtraAuras.lua) labels its bar with the spell name. When the
-- client has no name for the spell, the fallback label must be translated
-- (the "Ignore Pain" and "Arcane Surge" keys exist in every locale pack),
-- never shown as the English literal.
--
-- Boots the real Mainline core with the German locale (tools/tests/client_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "repository root argument missing")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local CASES = {
    { class = "WARRIOR", spec = 3, spell = 190456, key = "showIgnorePain", label = "Zähne zusammenbeißen" },
    { class = "MAGE", spec = 1, spell = 365362, key = "showArcaneWindow", label = "Arkane Woge" }, -- the deDE client name (Wowhead de spell=365362)
}

for _, case in ipairs(CASES) do
    local world = World.New(root, "Mainline", { locale = "deDE" })
    world:Boot()
    assert(not world:FirstFailure(), "Mainline deDE boot failed")
    local MSUF, env = world.core, world.env
    MSUF.FinalizeLocale()
    env.InCombatLockdown = function() return false end
    env.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    env.MSUF_Auras3 = { CreateClassPowerAuraSensor = function(host)
        return { host = host, SetEnabled = function(self, enabled) self.enabled = enabled end }
    end }
    -- The spell exists, but the client gives no name for it.
    env.C_Spell = setmetatable({
        DoesSpellExist = function(id) return id == case.spell or id == 451038 end,
        GetSpellName = function() return nil end,
    }, { __index = World.Stub })
    local bars = { [case.key] = true, resourceExtraWidth = 220, resourceExtraHeight = 8,
        resourceExtraOffsetX = 0, resourceExtraOffsetY = -18 }
    local helper = MSUF.CPBuilders.ExtraAuras({ db = { bars = bars }, PLAYER_CLASS = case.class,
        GetSpec = function() return case.spec end, GetPlayerFrame = function() return env.UIParent end,
        Texture = function() return "texture" end, NotSecret = function() return true end })
    env.MSUF_EM2.State.IsActive = function() return env.MSUF_UnitEditModeActive == true end
    env.MSUF_EM2.State.GetProvider = function() return "msuf" end
    env.MSUF_UnitEditModeActive = true
    MSUF.EditModeAPI._BeginSession()
    helper.Refresh()
    local record = env.MSUF_EM2.Registry.Get("external:msuf:resource-extras")
    local frame = record and record.getFrame()
    local bar = frame and select(1, frame:GetChildren())
    local text = bar and bar.text and bar.text:GetText()
    Check(text == case.label, case.class .. " sample label is " .. tostring(text) .. ", expected " .. case.label)
    helper.Disable()
end

if #failures > 0 then
    error("resource_extra_aura_names_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("resource_extra_aura_names_smoke: ok (Ignore Pain and Arcane Surge fallback labels translated)")

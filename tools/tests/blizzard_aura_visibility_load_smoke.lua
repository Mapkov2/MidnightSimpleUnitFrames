-- blizzard_aura_visibility_load_smoke.lua <repoRoot>
--
-- Kernel/MSUF_BlizzardFrames.lua hides Blizzard's BuffFrame/DebuffFrame when
-- the profile asks for it. It also ran that pass once at file load, where no
-- SavedVariable exists yet, so the call could only read defaults and touched
-- Blizzard's frames for nothing (quality finding C4.8). The saved choice is
-- applied by DisableBlizzardFrames (first spawn and every profile apply).
-- Pinned on each client's real load graph:
--   * loading the addon touches neither aura frame;
--   * DisableBlizzardFrames hides the buff frame and the debuff container when
--     the profile says so, and gives them back when the choice is cleared.
-- The Edit Mode keybinding (Kernel/MSUF_Keybinds.lua) is checked on the way:
-- it toggles through the Edit Mode entry point, its only provider.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    local touched = 0
    local function Watched(frame)
        local proxy = setmetatable({}, { __index = function(_, key)
            local value = frame[key]
            if type(value) == "function" then
                return function(_, ...)
                    touched = touched + 1
                    return value(frame, ...)
                end
            end
            return value
        end })
        return proxy
    end
    local uiParent = env.UIParent or env.CreateFrame("Frame")
    local buffFrame = env.CreateFrame("Frame", nil, uiParent)
    local debuffFrame = env.CreateFrame("Frame", nil, uiParent)
    debuffFrame.AuraContainer = env.CreateFrame("Frame", nil, debuffFrame)
    debuffFrame.AuraContainer:Show()
    env.BuffFrame = Watched(buffFrame)
    env.DebuffFrame = { AuraContainer = Watched(debuffFrame.AuraContainer) }
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    Check(touched == 0, flavor .. ": loading the addon touched Blizzard's aura frames " .. touched
        .. " time(s) before any SavedVariable exists")

    env.MSUF_EnsureDB()
    local shared = env.MSUF_DB.auras3.shared
    shared.hideBlizzardBuffFrame = true
    shared.hideBlizzardDebuffFrame = true
    local UF = world.core.UF
    UF.ApplyBlizzardAuraVisibility()
    Check(buffFrame:GetParent() ~= uiParent, flavor .. ": the saved buff-frame choice was not applied")
    Check(not debuffFrame.AuraContainer:IsShown(), flavor .. ": the saved debuff-frame choice was not applied")
    shared.hideBlizzardBuffFrame = false
    shared.hideBlizzardDebuffFrame = false
    UF.ApplyBlizzardAuraVisibility()
    Check(buffFrame:GetParent() == uiParent, flavor .. ": the buff frame was not given back")
    Check(debuffFrame.AuraContainer:IsShown(), flavor .. ": the debuff container was not given back")

    local calls = {}
    env.MSUF_SetMSUFEditModeDirect = function(active, unitKey) calls[#calls + 1] = { active = active, unitKey = unitKey } end
    env.MSUF_EditState = { active = false }
    env.MSUF_Keybind_ToggleEditMode()
    env.MSUF_EditState.active = true
    env.MSUF_Keybind_ToggleEditMode()
    Check(#calls == 2 and calls[1].active == true and calls[2].active == false,
        flavor .. ": the Edit Mode keybinding no longer toggles through MSUF_SetMSUFEditModeDirect")
    print("blizzard_aura_visibility_load_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end

-- Assistant Profiles specialization workflow helpers.
-- Runtime profile operations remain delegated to the existing MSUF profile API.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ProfileWorkflowBuilders = A.ProfileWorkflowBuilders or {}

function A.ProfileWorkflowBuilders.InstallSpecProfileHelpers(Profile)
    if type(Profile) ~= "table" or type(Profile.CharMeta) ~= "function" then return false end

    function Profile.SpecAutoSwitchEnabled()
        if type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" then return _G.MSUF_IsSpecAutoSwitchEnabled() == true end
        local char = Profile.CharMeta(false)
        return char and char.specAutoSwitch == true or false
    end

    function Profile.SetSpecAutoSwitch(enabled)
        enabled = enabled and true or false
        if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then
            _G.MSUF_SetSpecAutoSwitchEnabled(enabled)
            return true
        end
        local char = Profile.CharMeta(true)
        if not char then return false end
        char.specAutoSwitch = enabled
        return true
    end

    function Profile.SpecMeta()
        local out = {}
        local n = type(_G.GetNumSpecializations) == "function" and _G.GetNumSpecializations() or 0
        for i = 1, n do
            if type(_G.GetSpecializationInfo) == "function" then
                local specID, specName = _G.GetSpecializationInfo(i)
                if type(specID) == "number" and type(specName) == "string" and specName ~= "" then
                    out[#out + 1] = { id = specID, name = specName }
                end
            end
        end
        return out
    end

    function Profile.CompactName(value)
        return tostring(value or ""):lower():gsub("[%s%-%_]+", "")
    end

    function Profile.ResolveSpecID(value)
        local n = tonumber(value)
        if n then return n, tostring(n) end
        local wanted = Profile.CompactName(value)
        if wanted == "" then return nil, nil end
        local partial
        local specs = Profile.SpecMeta()
        for i = 1, #specs do
            local spec = specs[i]
            local name = Profile.CompactName(spec.name)
            if name == wanted then return spec.id, spec.name end
            if name:find(wanted, 1, true) or wanted:find(name, 1, true) then
                if partial then return nil, "multiple" end
                partial = spec
            end
        end
        if partial then return partial.id, partial.name end
        return nil, nil
    end

    function Profile.SpecLabel(specID)
        local specs = Profile.SpecMeta()
        for i = 1, #specs do
            if specs[i].id == specID then return specs[i].name end
        end
        return "Spec " .. tostring(specID)
    end

    function Profile.GetSpecProfile(specID)
        if type(_G.MSUF_GetSpecProfile) == "function" then return _G.MSUF_GetSpecProfile(specID) end
        local char = Profile.CharMeta(false)
        local map = char and char.specProfileMap
        local value = type(map) == "table" and map[specID] or nil
        return type(value) == "string" and value ~= "" and value or nil
    end

    function Profile.SetSpecProfile(specID, profileName)
        if type(_G.MSUF_SetSpecProfile) == "function" then
            _G.MSUF_SetSpecProfile(specID, profileName)
            return true
        end
        local char = Profile.CharMeta(true)
        if not char then return false end
        if type(char.specProfileMap) ~= "table" then char.specProfileMap = {} end
        if type(profileName) == "string" and profileName ~= "" and profileName ~= "None" then
            char.specProfileMap[specID] = profileName
        else
            char.specProfileMap[specID] = nil
        end
        return true
    end

    -- Which profile a character that has never run MSUF starts on. This is
    -- account-wide meta in MSUF_GlobalDB.global, deliberately outside the
    -- profile tables so switching, resetting, or importing a profile never
    -- rewrites it. `nil` keeps the historical "new characters land on Default"
    -- behaviour, which is why clearing is a supported outcome rather than an
    -- error.
    function Profile.NewCharacterProfile()
        if type(_G.MSUF_GetDefaultProfileForNewCharacters) ~= "function" then return nil end
        local name = _G.MSUF_GetDefaultProfileForNewCharacters()
        return type(name) == "string" and name ~= "" and name or nil
    end

    function Profile.SetNewCharacterProfile(profileName)
        if type(_G.MSUF_SetDefaultProfileForNewCharacters) ~= "function" then return false end
        -- "None" is the shared dropdown sentinel for "no selection"; the engine
        -- treats nil as clear and validates any real name against the pool.
        if type(profileName) ~= "string" or profileName == "" or profileName == "None" then
            return _G.MSUF_SetDefaultProfileForNewCharacters(nil) ~= false
        end
        return _G.MSUF_SetDefaultProfileForNewCharacters(profileName) ~= false
    end

    return true
end

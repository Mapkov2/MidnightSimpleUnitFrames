-- Minimal LibSharedMedia-3.0 (compatible subset)
-- Supports: Register, Fetch, List, RegisterCallback (via CallbackHandler)
-- Enough for MSUF to populate dropdowns and fetch paths.

local MAJOR, MINOR = "LibSharedMedia-3.0", 1
local LibStub = _G.LibStub
if not LibStub then return end

local LSM, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not LSM then return end

local CallbackHandler = LibStub("CallbackHandler-1.0", true)

LSM._hash = LSM._hash or {}
LSM._default = LSM._default or {
    font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    statusbar = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    background = "Interface\\Buttons\\WHITE8x8",
    border = "Interface\\Buttons\\WHITE8x8",
    sound = "",
}

-- callbacks
if CallbackHandler and not LSM._callbacks then
    LSM._callbacks = CallbackHandler:New(LSM, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")
end

local function _EnsureType(mediaType)
    if type(mediaType) ~= "string" then return nil end
    mediaType = mediaType:lower()
    LSM._hash[mediaType] = LSM._hash[mediaType] or {}
    return mediaType
end

function LSM:Register(mediaType, key, data)
    mediaType = _EnsureType(mediaType)
    if not mediaType then return end
    if type(key) ~= "string" or key == "" then return end
    if type(data) ~= "string" or data == "" then return end

    LSM._hash[mediaType][key] = data

    if LSM._callbacks and LSM._callbacks.Fire then
        -- mimic LSM event name used by many addons
        LSM._callbacks:Fire("LibSharedMedia_Registered", mediaType, key)
    end
end

function LSM:Fetch(mediaType, key, noDefault)
    mediaType = _EnsureType(mediaType)
    if not mediaType then return nil end

    local t = LSM._hash[mediaType]
    if key and t and t[key] then
        return t[key]
    end

    if noDefault then
        return nil
    end

    return LSM._default[mediaType]
end

function LSM:List(mediaType)
    mediaType = _EnsureType(mediaType)
    if not mediaType then return {} end

    local out = {}
    local t = LSM._hash[mediaType] or {}
    for k in pairs(t) do
        out[#out + 1] = k
    end
    table.sort(out)
    return out
end

function LSM:SetDefault(mediaType, key)
    mediaType = _EnsureType(mediaType)
    if not mediaType then return end
    if type(key) ~= "string" or key == "" then return end
    LSM._default[mediaType] = key
end

-- seed some common built-ins so existing profiles like "Blizzard" work
LSM._hash.font = LSM._hash.font or {}
LSM._hash.statusbar = LSM._hash.statusbar or {}

LSM._hash.font["Friz Quadrata (default)"] = "Fonts\\FRIZQT__.TTF"
LSM._hash.statusbar["Blizzard"] = "Interface\\TARGETINGFRAME\\UI-StatusBar"
LSM._hash.statusbar["White8x8"] = "Interface\\Buttons\\WHITE8x8"


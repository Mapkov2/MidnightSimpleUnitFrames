local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

local providers = Data.FAQProviders or {}
Data.FAQProviders = providers

function Data.RegisterFAQProvider(fn)
    if type(fn) ~= "function" then return false end
    providers[#providers + 1] = fn
    return true
end

function Data.BuildFAQ(env)
    local out = {}
    for i = 1, #providers do
        local items = providers[i](env or {})
        if type(items) == "table" then
            for k = 1, #items do out[#out + 1] = items[k] end
        end
    end
    return out
end

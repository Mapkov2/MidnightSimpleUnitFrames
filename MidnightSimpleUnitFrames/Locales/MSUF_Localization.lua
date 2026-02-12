-- ============================================================================
-- MidnightSimpleUnitFrames - Localization Core
--
-- Minimal scaffold:
--   - ns.L: translation table with fallback to the key itself.
--   - ns.LOCALE: active client locale string.
--   - ns.AddLocale(locale, dict): merge translations for matching locale.
--
-- Translator workflow:
--   - Add translations in Locales/zhCN.lua or Locales/zhTW.lua via ns.AddLocale.
--   - Keys are the original English UI strings (the current UI text).
--
-- Notes:
--   - This is UI-only (no combat/secure/secret interactions).
--   - Safe: does not touch protected frames or unit APIs.
-- ============================================================================
local addonName, ns = ...
ns = ns or {}
if _G then _G.MSUF_NS = ns end

ns.LOCALE = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")

ns.L = ns.L or {}
local L = ns.L

-- Fallback: if no translation exists, show the key.
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end

-- Public global handle for external modules / debugging.
if _G then _G.MSUF_L = L end

-- Merge translations for the active locale.
ns.AddLocale = ns.AddLocale or function(locale, dict)
    if type(dict) ~= "table" then return end
    local active = ns.LOCALE or "enUS"
    if locale ~= active then return end
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            L[k] = v
        end
    end
end

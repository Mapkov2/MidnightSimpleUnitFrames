-- MSUF_A2_Core.lua
-- Thin Auras2 namespace entry. Runtime subsystems live in:
--   MSUF_A2_Cache.lua       cache, full scan, delta update, FilterAndSort
--   MSUF_A2_Collect.lua     fast aura helper accessors
--   MSUF_A2_Icons.lua       icon pool, visual commit, stacks/timers
--   MSUF_A2_Layout.lua      icon grid layout
local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
_G.MSUF_NS = ns
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}

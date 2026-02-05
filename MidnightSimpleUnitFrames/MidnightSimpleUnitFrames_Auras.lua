--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Auras.lua"); -- MidnightSimpleUnitFrames_Auras.lua
-- Legacy compatibility bridge.
-- The full Auras 2.0 runtime has been moved to Auras2\MSUF_A2_Render.lua (loaded via .toc).
-- This file intentionally stays lightweight to reduce line count and keep older patch assumptions intact.

local addonName, ns = ...
ns = ns or {}
-- (All runtime logic now lives in Auras2\MSUF_A2_Render.lua)

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MidnightSimpleUnitFrames_Auras.lua");
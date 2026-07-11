local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Root registry bootstrap for the Menu2 Assistant.
-- Domain files append declarative settings, actions, workflows, and diagnostics to these
-- tables; they should not execute commands themselves. Parser files read this registry
-- and return plans, while the router/assistant runtime applies the approved plan later.
A.Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Workflow = A.Workflow or {}

-- The explicit registry domain load order lives in MSUF_Menu2_AssistantRuntime.xml.

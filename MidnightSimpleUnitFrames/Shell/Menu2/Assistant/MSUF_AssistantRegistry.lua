local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Root registry bootstrap for the Menu2 Assistant.
-- Domain files append declarative settings, actions, workflows, and diagnostics to these
-- tables; they should not execute commands themselves. Parser files read this registry
-- and return plans, while the router/assistant runtime applies the approved plan later.
A.Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Workflow = A.Workflow or {}

-- Keep the load manifest explicit. A missing domain file is easier to spot here than when
-- a natural-language command silently cannot match an otherwise valid setting.
A.RegistryDomainFiles = {
    "MSUF_AssistantRegistry_Core.lua",
    "MSUF_AssistantRegistry_Unitframes.lua",
    "MSUF_AssistantRegistry_Castbars.lua",
    "MSUF_AssistantRegistry_Auras.lua",
    "MSUF_AssistantRegistry_GroupFrames.lua",
    "MSUF_AssistantRegistry_Boss.lua",
    "MSUF_AssistantRegistry_ClassPower.lua",
    "MSUF_AssistantRegistry_Gameplay.lua",
    "MSUF_AssistantRegistry_Global.lua",
    "MSUF_AssistantRegistry_Dashboard.lua",
    "MSUF_AssistantRegistry_Profiles.lua",
    "MSUF_AssistantRegistry_EditMode.lua",
    "MSUF_AssistantRegistry_Workflows.lua",
    "MSUF_AssistantRegistry_Diagnostics.lua",
}

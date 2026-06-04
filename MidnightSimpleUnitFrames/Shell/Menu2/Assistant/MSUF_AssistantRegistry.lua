local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Workflow = A.Workflow or {}

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

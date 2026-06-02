local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

A.RegistryBossCoverage = {
    unitframes = "MSUF_AssistantRegistry_Unitframes.lua",
    castbars = "MSUF_AssistantRegistry_Castbars.lua",
    globalBars = "MSUF_AssistantRegistry_Global.lua",
    diagnostics = "MSUF_AssistantRegistry_Diagnostics.lua",
}

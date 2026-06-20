-- Assistant registry domain load manifest bootstrap.
-- Chunk files append the explicit reviewable list of registry modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.RegistryDomainFiles = {}

function A.AppendRegistryDomainFiles(files)
    if type(files) ~= "table" then return end
    for i = 1, #files do
        A.RegistryDomainFiles[#A.RegistryDomainFiles + 1] = files[i]
    end
end

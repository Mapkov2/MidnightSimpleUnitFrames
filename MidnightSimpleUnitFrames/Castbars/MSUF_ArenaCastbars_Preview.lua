--- Castbars/MSUF_ArenaCastbars_Preview.lua
--- Edit/menu previews for arena castbars: the arena descriptor of
--- MSUF_CastbarPoolPreviews.lua.
---
--- Every slot is suffixed (MSUF_ArenaCastbarPreview1..N, N from the arena pool:
--- MSUF.Client.MaxArenaOpponents); slot 1 also has the MSUF_ArenaCastbarPreview
--- alias. The preview globals stay as compatibility aliases of the pool preview
--- module.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local Pools = assert(MSUF.Castbars and MSUF.Castbars.Pools, "MSUF_CastbarPools.lua must load first")
assert(Pools.DefinePreview, "MSUF_CastbarPoolPreviews.lua must load first")

local api = Pools.DefinePreview(Pools.kinds.arena, {
    namePrefix = "MSUF_ArenaCastbarPreview",
    firstUnsuffixed = false,
    publishFirstSlot = function(frame) ExportPublic("MSUF_ArenaCastbarPreview", frame) end,
    indexField = "_msufArenaIndex",
    label = "Greater Pyroblast",
    targetLabel = "Arena Ally",
    showTargetKey = "showArenaCastTargetName",
    showTimeKey = "showArenaCastTime",
    testModeKey = "arenaCastbarTestMode",
}).api

ExportPublic("MSUF_UpdateArenaCastbarPreview", api.Update)
ExportPublic("MSUF_HideAllArenaCastbarPreviews", api.HideAll)
ExportPublic("MSUF_CreateArenaCastbarPreview", api.Create)
ExportPublic("MSUF_ApplyArenaCastbarPreviewLayout", api.ApplyLayout)
ExportPublic("MSUF_PositionArenaCastbarPreview", api.Position)

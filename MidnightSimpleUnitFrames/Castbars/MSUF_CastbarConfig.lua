--- Reused config snapshots. Profile writes stay at apply/backend boundaries.
local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_CastbarConfig.lua").Castbars
local Config, Backend = Castbars.Config, Castbars.Backend
local PublicAPI = Castbars.PublicAPI
local Optional = MSUF.Optional
local KINDS = { "player", "target", "focus", "boss", "arena" }
local TIME_KEYS = {
    player = "showPlayerCastTime", target = "showTargetCastTime", focus = "showFocusCastTime",
    boss = "showBossCastTime", arena = "showArenaCastTime",
}
local TARGET_KEYS = {
    target = "castbarTargetShowTargetName", focus = "castbarFocusShowTargetName",
    boss = "showBossCastTargetName", arena = "showArenaCastTargetName",
}
local general = {}
Config.DB = {}
Config.records = {}
Config.revisions = { style = 1, time = 1, texture = 1 }
Config.styleRevision, Config.timeRevision, Config.textureRevision = 1, 1, 1
Config.revision = 1
local compiledRevision = 0

for index = 1, #KINDS do
    local kind = KINDS[index]
    Config.records[kind] = { unit = {}, general = general, backend = "MSUF", enabled = true, timeEnabled = true }
end
for index = 1, 5 do
    Config.records["boss" .. index] = Config.records.boss
    Config.records["arena" .. index] = Config.records.arena
end

-- Never called at file load: SavedVariables are available only after loading.
function Config.Source(create)
    local db = Optional("MSUF_DB")
    if not db and create then
        MSUF.Require("MSUF_EnsureDB", "Castbars/MSUF_CastbarConfig.lua")()
        db = MSUF.Require("MSUF_DB", "Castbars/MSUF_CastbarConfig.lua")
    end
    if db and create then db.general = db.general or {} end
    return db
end

-- Cold geometry observes public/drag edits without compiling unrelated settings.
function Config.Geometry()
    return Optional("MSUF_DB") or Config.DB
end

local function Copy(source, target)
    for key in pairs(target) do target[key] = nil end
    if source then
        for key, value in pairs(source) do target[key] = value end
    end
end

function Config.Advance(kind)
    if not kind then return end
    local revisions = Config.revisions
    revisions[kind] = revisions[kind] + 1
    Config.styleRevision = revisions.style
    Config.timeRevision = revisions.time
    Config.textureRevision = revisions.texture
    if kind == "texture" then PublicAPI.Publish("MSUF_CastbarStyleRevision", revisions.texture) end
end

-- Writes invalidate without running readers or holding state across callbacks.
function Config.Invalidate(kind)
    Config.revision = Config.revision + 1
    if kind then Config.Advance(kind) end
end
Config.Refresh = Config.Invalidate

-- Reuse every table; a shared snapshot compiles all unit records once per revision.
-- Explicit Compile remains the cold compatibility entry for source-only callers.
function Config.Compile(kind, current)
    if not current then Config.Invalidate(kind) end
    local source = Config.Source()
    Config.sourceGeneral = source and source.general
    Copy(source and source.general, general)
    Copy(source, Config.DB)
    Config.DB.general = source and source.general and general or nil
    for index = 1, #KINDS do
        local kind = KINDS[index]
        local record = Config.records[kind]
        Copy(source and source[kind], record.unit)
        Config.DB[kind] = source and source[kind] and record.unit or nil
        -- Drag/shake geometry must observe live edits between cold revisions.
        record.geometry = source and source.general or general
        record.backend = Backend.Resolve(kind, general)
        record.enabled = record.backend == "MSUF"
        record.timeEnabled = general[TIME_KEYS[kind]] ~= false
        local timeFormat = MSUF.Public and MSUF.Public.GetCastbarTimeFormat
        record.timeFormat = timeFormat and timeFormat(kind, general) or "CURRENT"
        record.showTargetName = TARGET_KEYS[kind] and general[TARGET_KEYS[kind]] == true or false
        record.showGlow = general.castbarShowGlow ~= false
        record.revision = Config.revision
    end
    Config.ready = true
    compiledRevision = Config.revision
    return Config.DB
end

-- The ordinary read is only a revision comparison after the first access.
function Config.Read(unit)
    if unit then
        local record = Config.records[unit]
        if record and record.revision ~= Config.revision then Config.Compile(nil, true) end
        return record
    end
    if compiledRevision ~= Config.revision then Config.Compile(nil, true) end
    return Config.DB
end

function Config.EnsureSource()
    return Config.Source(true)
end

PublicAPI.Publish("MSUF_CastbarStyleRevision", Config.textureRevision)

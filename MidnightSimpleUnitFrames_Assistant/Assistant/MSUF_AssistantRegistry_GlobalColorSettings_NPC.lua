-- Assistant global NPC and pet color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main color domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterNPCColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local ColorSetting = ctx.ColorSetting
    local ColorAPI = ctx.ColorAPI
    local GeneralDB = ctx.GeneralDB
    local GeneralRGB = ctx.GeneralRGB
    local SetGeneralRGB = ctx.SetGeneralRGB
    local TableRGB = ctx.TableRGB
    local ApiRGB = ctx.ApiRGB
    local ApiSetRGB = ctx.ApiSetRGB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local ApplyColors = ctx.ApplyColors
    local COLOR_NPC_ROWS = ctx.COLOR_NPC_ROWS or {}
    local COLOR_NPC_TYPE_TOGGLE_ROWS = ctx.COLOR_NPC_TYPE_TOGGLE_ROWS or {}
    local COLOR_NPC_TYPE_ROWS = ctx.COLOR_NPC_TYPE_ROWS or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(ColorSetting) ~= "function" or type(ColorAPI) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return end
    if type(ApiRGB) ~= "function" or type(ApiSetRGB) ~= "function" then return end
    if type(GeneralRGB) ~= "function" or type(SetGeneralRGB) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" then return end

    for i = 1, #COLOR_NPC_ROWS do
        local row = COLOR_NPC_ROWS[i]
        ColorSetting("npcColors." .. row.key, row.label, row.aliases, function()
            local fn = ColorAPI().GetNPCColor
            if type(fn) == "function" then return fn(row.key) end
            return TableRGB(GeneralDB().npcColors, row.key, row.dr, row.dg, row.db)
        end, function(r, g, b)
            local fn = ColorAPI().SetNPCColor
            if type(fn) == "function" then
                fn(row.key, r, g, b)
            else
                local db = GeneralDB()
                db.npcColors = type(db.npcColors) == "table" and db.npcColors or {}
                db.npcColors[row.key] = { r = r, g = g, b = b }
            end
        end, { category = "Colors / Unit Frame Colors", attribute = "npcColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
    end

    ColorSetting("general.petFrameColor", "Pet Frame Color", {
        "pet frame color", "pet color", "pet bar color",
    }, function()
        return ApiRGB("GetPetFrameColor", 0, 0.8, 0, function() return GeneralRGB("petFrameColor", 0, 0.8, 0) end)
    end, function(r, g, b)
        if not ApiSetRGB("SetPetFrameColor", r, g, b) then SetGeneralRGB("petFrameColor", r, g, b) end
    end, { category = "Colors / Unit Frame Colors", attribute = "petColor", defaultR = 0, defaultG = 0.8, defaultB = 0, apply = ApplyColors })
    RegisterGeneralBoolean("petFrameUsePlayerClassColor", "petUsePlayerClassColor",
        "Use Player Class Color For Pet Frame", false, {
            "pet player class color", "pet frame player class color", "use player class color for pet",
        }, {
            category = "Colors / Unit Frame Colors", frameType = "colors",
            apply = ApplyColors, reason = "MSUF_ASSISTANT_PET_PLAYER_CLASS_COLOR",
        })

    Registry:RegisterSetting({
        key = "general.npcColorMode",
        label = "NPC Type Colors",
        category = "Colors / NPC Type",
        unit = "global",
        frameType = "colors",
        attribute = "npcTypeColors",
        type = "boolean",
        aliases = { "npc type colors", "npc type coloring", "npc role colors" },
        get = function()
            local fn = ColorAPI().GetNPCColorMode
            if type(fn) == "function" then return fn() == "type" end
            return GeneralDB().npcColorMode == "type"
        end,
        set = function(value)
            local mode = value and "type" or "reaction"
            local fn = ColorAPI().SetNPCColorMode
            if type(fn) == "function" then fn(mode) else GeneralDB().npcColorMode = mode end
        end,
        apply = ApplyColors,
        combatSafe = false,
    })
    RegisterGeneralBoolean("npcTypeColorBar", "npcTypeColorHPBar", "NPC Type Color HP Bar", true, {
        "npc type color hp bar", "npc type color health bar", "npc role color hp",
    }, { category = "Colors / NPC Type", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_NPC_TYPE_HP_COLOR" })
    RegisterGeneralBoolean("npcTypeColorText", "npcTypeColorNameText", "NPC Type Color Name Text", true, {
        "npc type color name text", "npc type color names", "npc role color names",
    }, { category = "Colors / NPC Type", frameType = "colors", apply = ApplyColors, reason = "MSUF_ASSISTANT_NPC_TYPE_TEXT_COLOR" })
    for _, item in ipairs(COLOR_NPC_TYPE_TOGGLE_ROWS) do
        RegisterGeneralBoolean(item.key, item.key, item.label, true, item.aliases, {
            category = "Colors / NPC Type",
            frameType = "colors",
            apply = ApplyColors,
            reason = "MSUF_ASSISTANT_" .. item.key,
        })
    end

    for i = 1, #COLOR_NPC_TYPE_ROWS do
        local row = COLOR_NPC_TYPE_ROWS[i]
        ColorSetting("npcColors." .. row.key, row.label, row.aliases, function()
            local fn = ColorAPI().GetNPCColor
            if type(fn) == "function" then return fn(row.key) end
            return TableRGB(GeneralDB().npcColors, row.key, row.dr, row.dg, row.db)
        end, function(r, g, b)
            local fn = ColorAPI().SetNPCColor
            if type(fn) == "function" then
                fn(row.key, r, g, b)
            else
                local db = GeneralDB()
                db.npcColors = type(db.npcColors) == "table" and db.npcColors or {}
                db.npcColors[row.key] = { r = r, g = g, b = b }
            end
        end, { category = "Colors / NPC Type", attribute = "npcTypeColor", defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyColors })
    end
end

-- Assistant GroupFrames text color helpers.
-- Loaded before MSUF_AssistantRegistry_GroupFrames_Core_Text.lua; consumed by the text core context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildTextColorContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return nil end

    local function GroupColorSame(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        local ar, ag, ab = tonumber(a.r or a[1]) or 0, tonumber(a.g or a[2]) or 0, tonumber(a.b or a[3]) or 0
        local br, bg, bb = tonumber(b.r or b[1]) or 0, tonumber(b.g or b[2]) or 0, tonumber(b.b or b[3]) or 0
        return math.abs(ar - br) < 0.0005 and math.abs(ag - bg) < 0.0005 and math.abs(ab - bb) < 0.0005
    end

    local function GroupClamp01(value, fallback)
        value = tonumber(value)
        if value == nil then return fallback or 0 end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    local function RegisterGroupColor(scope, attr, keyPrefix, label, dr, dg, db, aliases, opts)
        opts = type(opts) == "table" and opts or {}
        local settingKey = keyPrefix:match("Color$") and keyPrefix or (keyPrefix .. "Color")
        Registry:RegisterSetting({
            key = "gf_" .. scope .. "." .. settingKey,
            label = UNIT_LABELS[scope] .. " " .. label,
            category = UNIT_LABELS[scope] .. " / Group Frames",
            unit = scope,
            frameType = "group",
            attribute = attr,
            -- One visible color picker owns all three scalar DB channels.
            -- Declaring them prevents unsafe raw R/G/B fallback controls from
            -- being generated alongside the canonical color setting.
            dbScopes = {
                { scope = "gf_" .. scope, dbKey = keyPrefix .. "R" },
                { scope = "gf_" .. scope, dbKey = keyPrefix .. "G" },
                { scope = "gf_" .. scope, dbKey = keyPrefix .. "B" },
            },
            dbScopesReplace = true,
            type = "color",
            aliases = aliases,
            get = function()
                local conf = GroupDB(scope)
                return { r = tonumber(conf[keyPrefix .. "R"]) or dr, g = tonumber(conf[keyPrefix .. "G"]) or dg, b = tonumber(conf[keyPrefix .. "B"]) or db }
            end,
            set = function(value)
                local conf = GroupDB(scope)
                conf[keyPrefix .. "R"] = GroupClamp01(type(value) == "table" and (value.r or value[1]) or dr, dr)
                conf[keyPrefix .. "G"] = GroupClamp01(type(value) == "table" and (value.g or value[2]) or dg, dg)
                conf[keyPrefix .. "B"] = GroupClamp01(type(value) == "table" and (value.b or value[3]) or db, db)
            end,
            sameValue = GroupColorSame,
            apply = function() ApplyGroup(scope, opts.mode or "visual") end,
            combatSafe = false,
        })
    end

    local function GetGroupHealthBarColor(scope)
        local conf = GroupDB(scope)
        local mode = conf.gfBarMode
        local prefix, dr, dg, db
        if mode == "dark" then
            prefix, dr, dg, db = "gfDark", 0, 0, 0
        elseif mode == "unified" then
            prefix, dr, dg, db = "gfUnified", 0.10, 0.60, 0.90
        else
            prefix, dr, dg, db = "healthCustom", 0.20, 0.80, 0.20
        end
        return {
            r = tonumber(conf[prefix .. "R"]) or dr,
            g = tonumber(conf[prefix .. "G"]) or dg,
            b = tonumber(conf[prefix .. "B"]) or db,
        }
    end

    local function SetGroupHealthBarColor(scope, value)
        local conf = GroupDB(scope)
        local mode = conf.gfBarMode
        local prefix, dr, dg, db
        if mode == "dark" then
            prefix, dr, dg, db = "gfDark", 0, 0, 0
        elseif mode == "unified" then
            prefix, dr, dg, db = "gfUnified", 0.10, 0.60, 0.90
        else
            conf.gfBarMode = "CUSTOM"
            conf.healthColorMode = "CUSTOM"
            prefix, dr, dg, db = "healthCustom", 0.20, 0.80, 0.20
        end
        conf[prefix .. "R"] = GroupClamp01(type(value) == "table" and (value.r or value[1]) or dr, dr)
        conf[prefix .. "G"] = GroupClamp01(type(value) == "table" and (value.g or value[2]) or dg, dg)
        conf[prefix .. "B"] = GroupClamp01(type(value) == "table" and (value.b or value[3]) or db, db)
    end

    return {
        RegisterGroupColor = RegisterGroupColor,
        GroupColorSame = GroupColorSame,
        GetGroupHealthBarColor = GetGroupHealthBarColor,
        SetGroupHealthBarColor = SetGroupHealthBarColor,
    }
end

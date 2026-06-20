-- Assistant class resource color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterClassPowerColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local ColorSetting = ctx.ColorSetting
    local BarsDB = ctx.BarsDB
    local EnsureClassPowerOverrides = ctx.EnsureClassPowerOverrides
    local ClassPowerRGB = ctx.ClassPowerRGB
    local SetClassPowerRGB = ctx.SetClassPowerRGB
    local ClassPowerBgRGB = ctx.ClassPowerBgRGB
    local SetClassPowerBgRGB = ctx.SetClassPowerBgRGB
    local ApplyClassPowerColors = ctx.ApplyClassPowerColors
    local COLOR_CP_TOKENS = ctx.COLOR_CP_TOKENS or {}

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(ColorSetting) ~= "function" or type(BarsDB) ~= "function" then return end
    if type(EnsureClassPowerOverrides) ~= "function" or type(ApplyClassPowerColors) ~= "function" then return end
    if type(ClassPowerRGB) ~= "function" or type(SetClassPowerRGB) ~= "function" then return end
    if type(ClassPowerBgRGB) ~= "function" or type(SetClassPowerBgRGB) ~= "function" then return end

    A.ClassPowerColorTokens = COLOR_CP_TOKENS

    local function AddUniqueAlias(out, seen, value)
        value = tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if value ~= "" and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end

    local function ClassPowerColorExactAliases(label, background)
        local lower = tostring(label or ""):lower()
        local out, seen = {}, {}
        if background then
            AddUniqueAlias(out, seen, "set " .. lower .. " background color")
            AddUniqueAlias(out, seen, "set " .. lower .. " background")
            AddUniqueAlias(out, seen, "set " .. lower .. " resource background")
            AddUniqueAlias(out, seen, "make " .. lower .. " background color")
            AddUniqueAlias(out, seen, "make " .. lower .. " background")
        else
            AddUniqueAlias(out, seen, "set " .. lower .. " color")
            AddUniqueAlias(out, seen, "set " .. lower .. " class resource color")
            AddUniqueAlias(out, seen, "set " .. lower .. " resource color")
            AddUniqueAlias(out, seen, "make " .. lower .. " color")
            AddUniqueAlias(out, seen, "make " .. lower)
        end
        return out
    end

    local function ComboPointSlotColorExactAliases(slot)
        local out, seen = {}, {}
        local n = tostring(slot)
        AddUniqueAlias(out, seen, "set combo point slot " .. n)
        AddUniqueAlias(out, seen, "set combo point slot " .. n .. " color")
        AddUniqueAlias(out, seen, "set combo point " .. n)
        AddUniqueAlias(out, seen, "set combo point " .. n .. " color")
        AddUniqueAlias(out, seen, "set cp " .. n)
        AddUniqueAlias(out, seen, "make combo point slot " .. n)
        AddUniqueAlias(out, seen, "make combo point " .. n)
        AddUniqueAlias(out, seen, "make cp " .. n)
        return out
    end

    for i = 1, #COLOR_CP_TOKENS do
        local token = COLOR_CP_TOKENS[i].key
        local label = COLOR_CP_TOKENS[i].label
        local lower = label:lower()
        ColorSetting("general.classPowerColorOverrides." .. token, label .. " Color", {
            lower .. " color", lower .. " class power color", lower .. " class resource color", lower .. " resource color",
        }, function()
            return ClassPowerRGB(token)
        end, function(r, g, b)
            SetClassPowerRGB(token, r, g, b)
        end, {
            category = "Colors / Class Power",
            attribute = "classPowerColor",
            apply = ApplyClassPowerColors,
            exactAliases = ClassPowerColorExactAliases(label, false),
        })
        ColorSetting("general.classPowerBgColorOverrides." .. token, label .. " Background Color", {
            lower .. " background color", lower .. " class power background color", lower .. " resource background color",
        }, function()
            return ClassPowerBgRGB(token)
        end, function(r, g, b)
            SetClassPowerBgRGB(token, r, g, b)
        end, {
            category = "Colors / Class Power",
            attribute = "classPowerBackgroundColor",
            defaultR = 0,
            defaultG = 0,
            defaultB = 0,
            apply = ApplyClassPowerColors,
            exactAliases = ClassPowerColorExactAliases(label, true),
        })
    end

    for i = 1, 7 do
        local token = "COMBO_POINTS_" .. tostring(i)
        ColorSetting("general.classPowerColorOverrides." .. token, "Combo Point " .. tostring(i) .. " Color", {
            "combo point " .. tostring(i), "combo point " .. tostring(i) .. " color",
            "combo point slot " .. tostring(i), "combo point slot " .. tostring(i) .. " color",
            "cp " .. tostring(i), "cp " .. tostring(i) .. " color",
        }, function()
            return ClassPowerRGB(token)
        end, function(r, g, b)
            BarsDB().classPowerComboPointColorMode = "custom"
            SetClassPowerRGB(token, r, g, b)
        end, {
            category = "Colors / Class Power",
            attribute = "comboPointSlotColor",
            apply = ApplyClassPowerColors,
            exactAliases = ComboPointSlotColorExactAliases(i),
        })
    end

    local function KnownClassPowerColorToken(token)
        token = tostring(token or "")
        for i = 1, #COLOR_CP_TOKENS do
            if COLOR_CP_TOKENS[i].key == token then return token, COLOR_CP_TOKENS[i].label end
        end
        for i = 1, 7 do
            local slot = "COMBO_POINTS_" .. tostring(i)
            if token == slot then return token, "Combo Point " .. tostring(i) end
        end
        return nil, nil
    end

    Registry:RegisterAction({
        key = "reset_class_power_color_token",
        label = "Reset Class Resource Token Color",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local token, label = KnownClassPowerColorToken(args and args.token)
            if not token then return false, "Which Class Resource color do you want me to change?" end
            local g = EnsureClassPowerOverrides()
            if args and args.background then
                g.classPowerBgColorOverrides[token] = nil
                ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_BG_COLOR")
                return true, "Done. Reset " .. tostring(label) .. " background color."
            end
            g.classPowerColorOverrides[token] = nil
            ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_COLOR")
            return true, "Done. Reset " .. tostring(label) .. " color."
        end,
    })

    Registry:RegisterAction({
        key = "reset_class_power_combo_slot_colors",
        label = "Reset Combo Point Slot Colors",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function()
            local g = EnsureClassPowerOverrides()
            for i = 1, 7 do g.classPowerColorOverrides["COMBO_POINTS_" .. tostring(i)] = nil end
            ApplyClassPowerColors("MSUF_ASSISTANT_RESET_COMBO_POINT_SLOT_COLORS")
            return true, "Done. Reset combo point slot colors."
        end,
    })
end

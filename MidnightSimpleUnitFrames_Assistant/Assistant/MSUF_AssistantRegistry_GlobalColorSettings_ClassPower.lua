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
    local SLOT_RESOURCES = ctx.CLASS_POWER_SLOT_RESOURCES or {}

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(ColorSetting) ~= "function" or type(BarsDB) ~= "function" then return end
    if type(EnsureClassPowerOverrides) ~= "function" or type(ApplyClassPowerColors) ~= "function" then return end
    if type(ClassPowerRGB) ~= "function" or type(SetClassPowerRGB) ~= "function" then return end
    if type(ClassPowerBgRGB) ~= "function" or type(SetClassPowerBgRGB) ~= "function" then return end

    A.ClassPowerColorTokens = COLOR_CP_TOKENS
    A.ClassPowerSlotResources = SLOT_RESOURCES
    A.ClassPowerSlotResourceByToken = {}
    for i = 1, #SLOT_RESOURCES do
        local spec = SLOT_RESOURCES[i]
        if spec and spec.token then A.ClassPowerSlotResourceByToken[spec.token] = spec end
    end

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

    local function ResourceSlotToken(resourceToken, slot)
        return tostring(resourceToken) .. "_" .. tostring(slot)
    end

    local function ResourceSlotColorExactAliases(spec, slot)
        local out, seen = {}, {}
        local n = tostring(slot)
        local label = tostring(spec.label or spec.token):lower()
        AddUniqueAlias(out, seen, "set " .. label .. " slot " .. n)
        AddUniqueAlias(out, seen, "set " .. label .. " " .. n .. " color")
        AddUniqueAlias(out, seen, "make " .. label .. " " .. n)
        local aliases = spec.aliases or {}
        for i = 1, math.min(#aliases, 5) do
            local alias = tostring(aliases[i]):lower()
            AddUniqueAlias(out, seen, "set " .. alias .. " " .. n)
            AddUniqueAlias(out, seen, "make " .. alias .. " " .. n)
        end
        return out
    end

    local SLOT_MODE_VALUE_ALIASES = {
        default = "default", resource = "default", resourcecolor = "default", base = "default", same = "default",
        ramp = "ramp", gradient = "ramp", colorramp = "ramp", farbverlauf = "ramp",
        custom = "custom", individual = "custom", slots = "custom", perslot = "custom", einzeln = "custom", individuell = "custom",
    }

    local function SlotMode(resourceToken)
        local bars = BarsDB()
        local modes = bars.classPowerSlotColorModes
        local mode = type(modes) == "table" and modes[resourceToken] or nil
        if mode == nil and resourceToken == "COMBO_POINTS" then mode = bars.classPowerComboPointColorMode end
        return (mode == "ramp" or mode == "custom") and mode or "default"
    end

    local function SetSlotMode(resourceToken, mode)
        local bars = BarsDB()
        if type(bars.classPowerSlotColorModes) ~= "table" then bars.classPowerSlotColorModes = {} end
        mode = (mode == "ramp" or mode == "custom") and mode or "default"
        bars.classPowerSlotColorModes[resourceToken] = mode ~= "default" and mode or nil
        if resourceToken == "COMBO_POINTS" then bars.classPowerComboPointColorMode = mode end
    end

    local function FullColorEnabled(resourceToken)
        local enabled = BarsDB().classPowerFullColorEnabled
        return type(enabled) == "table" and enabled[resourceToken] == true
    end

    local function SetFullColorEnabled(resourceToken, enabled)
        local bars = BarsDB()
        if type(bars.classPowerFullColorEnabled) ~= "table" then bars.classPowerFullColorEnabled = {} end
        bars.classPowerFullColorEnabled[resourceToken] = enabled == true and true or nil
    end

    local function ResourceFullAliases(spec, suffix)
        local out, seen = {}, {}
        local aliases = spec.aliases or {}
        AddUniqueAlias(out, seen, tostring(spec.label) .. " full " .. suffix)
        AddUniqueAlias(out, seen, tostring(spec.label) .. " max " .. suffix)
        AddUniqueAlias(out, seen, tostring(spec.className) .. " full resource " .. suffix)
        AddUniqueAlias(out, seen, tostring(spec.className) .. " capped resource " .. suffix)
        for i = 1, math.min(#aliases, 6) do
            AddUniqueAlias(out, seen, tostring(aliases[i]) .. " full " .. suffix)
            AddUniqueAlias(out, seen, "full " .. tostring(aliases[i]) .. " " .. suffix)
            AddUniqueAlias(out, seen, tostring(aliases[i]) .. " max " .. suffix)
        end
        return out
    end

    local function ResourceSlotAliases(spec, slot)
        local out, seen = {}, {}
        local n = tostring(slot)
        AddUniqueAlias(out, seen, tostring(spec.label) .. " " .. n)
        AddUniqueAlias(out, seen, tostring(spec.label) .. " slot " .. n)
        AddUniqueAlias(out, seen, tostring(spec.className) .. " " .. tostring(spec.label) .. " " .. n)
        local aliases = spec.aliases or {}
        for i = 1, math.min(#aliases, 10) do
            AddUniqueAlias(out, seen, tostring(aliases[i]) .. " " .. n)
        end
        return out
    end

    local function ResourceModeAliases(spec)
        local out, seen = {}, {}
        local aliases = spec.aliases or {}
        AddUniqueAlias(out, seen, tostring(spec.label) .. " slot color mode")
        AddUniqueAlias(out, seen, tostring(spec.label) .. " individual colors")
        AddUniqueAlias(out, seen, tostring(spec.className) .. " resource slot colors")
        for i = 1, math.min(#aliases, 8) do
            AddUniqueAlias(out, seen, tostring(aliases[i]) .. " slot mode")
            AddUniqueAlias(out, seen, tostring(aliases[i]) .. " slot colors")
        end
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

    for resourceIndex = 1, #SLOT_RESOURCES do
        local resource = SLOT_RESOURCES[resourceIndex]
        local resourceToken = resource.token
        local resourceLabel = resource.label
        local resourceClass = resource.className
        local count = tonumber(resource.count) or 0
        Registry:RegisterSetting({
            key = "bars.classPowerSlotColorModes." .. resourceToken,
            label = resourceClass .. " " .. resourceLabel .. " Slot Color Mode",
            category = "Colors / Class Power / " .. resourceLabel,
            unit = "global",
            frameType = "classPower",
            attribute = "classPowerSlotColorMode",
            resourceToken = resourceToken,
            resourceLabel = resourceLabel,
            className = resourceClass,
            type = "enum",
            aliases = ResourceModeAliases(resource),
            values = { "default", "ramp", "custom" },
            valueAliases = SLOT_MODE_VALUE_ALIASES,
            get = function() return SlotMode(resourceToken) end,
            set = function(value) SetSlotMode(resourceToken, value) end,
            apply = ApplyClassPowerColors,
            combatSafe = false,
            description = "Chooses resource color, color ramp, or individual colors for " .. resourceClass .. " " .. resourceLabel .. ".",
        })
        Registry:RegisterSetting({
            key = "bars.classPowerFullColorEnabled." .. resourceToken,
            label = resourceClass .. " " .. resourceLabel .. " Full Color",
            category = "Colors / Class Power / " .. resourceLabel,
            unit = "global",
            frameType = "classPower",
            attribute = "classPowerFullColorEnabled",
            resourceToken = resourceToken,
            resourceLabel = resourceLabel,
            className = resourceClass,
            type = "boolean",
            aliases = ResourceFullAliases(resource, "color"),
            get = function() return FullColorEnabled(resourceToken) end,
            set = function(value) SetFullColorEnabled(resourceToken, value == true) end,
            apply = ApplyClassPowerColors,
            combatSafe = false,
            description = "Uses a separate color when " .. resourceClass .. " " .. resourceLabel .. " reaches its dynamic maximum.",
        })
        local fullToken = resourceToken .. "_FULL"
        ColorSetting("general.classPowerColorOverrides." .. fullToken,
            resourceClass .. " " .. resourceLabel .. " Full Resource Color",
            ResourceFullAliases(resource, "color"), function()
                local overrides = EnsureClassPowerOverrides().classPowerColorOverrides
                if type(overrides[fullToken]) == "table" then return ClassPowerRGB(fullToken) end
                return ClassPowerRGB(resourceToken)
            end, function(r, g, b)
                SetFullColorEnabled(resourceToken, true)
                SetClassPowerRGB(fullToken, r, g, b)
            end, {
                category = "Colors / Class Power / " .. resourceLabel,
                attribute = "classPowerFullColor",
                apply = ApplyClassPowerColors,
                resourceToken = resourceToken,
                resourceLabel = resourceLabel,
                className = resourceClass,
                description = "Sets the color used when " .. resourceClass .. " " .. resourceLabel .. " is full and enables the full-resource color.",
            })
        for slot = 1, count do
            local slotIndex = slot
            local slotToken = ResourceSlotToken(resourceToken, slotIndex)
            ColorSetting("general.classPowerColorOverrides." .. slotToken,
                resourceClass .. " " .. resourceLabel .. " " .. tostring(slotIndex) .. " Color",
                ResourceSlotAliases(resource, slotIndex), function()
                    local overrides = EnsureClassPowerOverrides().classPowerColorOverrides
                    if type(overrides[slotToken]) == "table" or resourceToken == "COMBO_POINTS" then
                        return ClassPowerRGB(slotToken)
                    end
                    return ClassPowerRGB(resourceToken)
                end, function(r, g, b)
                    SetSlotMode(resourceToken, "custom")
                    SetClassPowerRGB(slotToken, r, g, b)
                end, {
                    category = "Colors / Class Power / " .. resourceLabel,
                    attribute = "classPowerSlotColor",
                    apply = ApplyClassPowerColors,
                    exactAliases = ResourceSlotColorExactAliases(resource, slotIndex),
                    resourceToken = resourceToken,
                    resourceLabel = resourceLabel,
                    className = resourceClass,
                    slot = slotIndex,
                    description = "Sets the color of " .. resourceClass .. " " .. resourceLabel .. " slot " .. tostring(slotIndex) .. " and enables individual slot colors for that resource.",
                })
        end
    end

    local function KnownClassPowerColorToken(token)
        token = tostring(token or "")
        for i = 1, #COLOR_CP_TOKENS do
            if COLOR_CP_TOKENS[i].key == token then return token, COLOR_CP_TOKENS[i].label end
        end
        for resourceIndex = 1, #SLOT_RESOURCES do
            local resource = SLOT_RESOURCES[resourceIndex]
            if token == resource.token .. "_FULL" then
                return token, resource.className .. " " .. resource.label .. " Full Resource"
            end
            for slot = 1, tonumber(resource.count) or 0 do
                local slotToken = ResourceSlotToken(resource.token, slot)
                if token == slotToken then return token, resource.label .. " " .. tostring(slot) end
            end
        end
        return nil, nil
    end

    local function ResetSlotColors(resourceToken)
        local resource = A.ClassPowerSlotResourceByToken[resourceToken]
        if not resource then return false, "Which Class Resource slots do you want me to reset?" end
        local g = EnsureClassPowerOverrides()
        for slot = 1, tonumber(resource.count) or 0 do
            g.classPowerColorOverrides[ResourceSlotToken(resourceToken, slot)] = nil
        end
        ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_SLOT_COLORS")
        return true, "Done. Reset " .. tostring(resource.className) .. " " .. tostring(resource.label) .. " slot colors."
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
            local fullResourceToken = token:match("^(.-)_FULL$")
            if fullResourceToken then SetFullColorEnabled(fullResourceToken, false) end
            ApplyClassPowerColors("MSUF_ASSISTANT_RESET_CLASS_POWER_COLOR")
            return true, "Done. Reset " .. tostring(label) .. " color."
        end,
    })

    Registry:RegisterAction({
        key = "reset_class_power_slot_colors",
        label = "Reset Class Resource Slot Colors",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            return ResetSlotColors(args and args.resourceToken)
        end,
    })

    Registry:RegisterAction({
        key = "reset_class_power_combo_slot_colors",
        label = "Reset Combo Point Slot Colors",
        type = "color",
        combatSafe = false,
        captureSnapshot = true,
        run = function() return ResetSlotColors("COMBO_POINTS") end,
    })
end

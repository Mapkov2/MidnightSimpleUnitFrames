-- Group frame opacity, bar-background, dead-background, and anchoring assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; the main loop preserves registration order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterFrameAlphaAnchorSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupString = ctx.RegisterGroupString
    local RegisterGroupColor = ctx.RegisterGroupColor
    local StandardGroupAnchorTarget = ctx.StandardGroupAnchorTarget
    local TrimString = ctx.TrimString
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupString) ~= "function" then return end
    if type(RegisterGroupColor) ~= "function" or type(StandardGroupAnchorTarget) ~= "function" then return end
    if type(TrimString) ~= "function" then return end

    local function GroupAnchorTargetExactAliases()
        local out = {}
        local scopeTerms = {
            party = { "party frames", "party frame", "party" },
            raid = { "raid frames", "raid frame", "raid" },
            mythicraid = { "mythic raid frames", "mythic raid frame", "mythic raid" },
        }
        local targetTerms = { "player", "target", "target of target", "focus target", "focus", "free", "none" }
        local terms = scopeTerms[scope] or {}
        for i = 1, #terms do
            for j = 1, #targetTerms do
                out[#out + 1] = terms[i] .. " anchor to " .. targetTerms[j]
                out[#out + 1] = "anchor " .. terms[i] .. " to " .. targetTerms[j]
            end
        end
        return out
    end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "opacity affects")
    AddAliasesForUnit(aliases, scope, "transparency affects")
    AddAliasesForUnit(aliases, scope, "alpha target")
    -- Unified colors transparency: health bar fill opacity, background opacity, and a toggle
    -- to keep text + portrait opaque while bars dim.
    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp bar opacity")
    AddAliasesForUnit(aliases, scope, "hp fill opacity")
    AddAliasesForUnit(aliases, scope, "health bar opacity")
    AddAliasesForUnit(aliases, scope, "foreground opacity")
    AddAliasesForUnit(aliases, scope, "foreground alpha")
    AddAliasesForUnit(aliases, scope, "bar foreground opacity")
    AddAliasesForUnit(aliases, scope, "bar fill opacity")
    AddAliasesForUnit(aliases, scope, "health foreground opacity")
    RegisterGroupNumber(scope, "hpBarAlpha", "hpBarAlpha", "Health Bar Opacity", 1, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "background opacity")
    AddAliasesForUnit(aliases, scope, "backdrop opacity")
    AddAliasesForUnit(aliases, scope, "background alpha")
    AddAliasesForUnit(aliases, scope, "hp track opacity")
    AddAliasesForUnit(aliases, scope, "health track opacity")
    AddAliasesForUnit(aliases, scope, "track opacity")
    AddAliasesForUnit(aliases, scope, "bar background opacity")
    AddAliasesForUnit(aliases, scope, "bar background alpha")
    RegisterGroupNumber(scope, "hpBgAlpha", "hpBgAlpha", "Bar Background Opacity", 0.85, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "keep text visible")
    AddAliasesForUnit(aliases, scope, "keep text portrait visible")
    AddAliasesForUnit(aliases, scope, "keep text and portrait visible")
    AddAliasesForUnit(aliases, scope, "exclude text from opacity")
    AddAliasesForUnit(aliases, scope, "keep portrait visible")
    AddAliasesForUnit(aliases, scope, "keep text visible when faded")
    AddAliasesForUnit(aliases, scope, "keep names visible when faded")
    RegisterGroupBoolean(scope, "alphaExcludeTextPortrait", "alphaExcludeTextPortrait", "Keep Text & Portrait Visible", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "fade out of combat")
    AddAliasesForUnit(aliases, scope, "out of combat fade")
    AddAliasesForUnit(aliases, scope, "ooc fade")
    AddAliasesForUnit(aliases, scope, "fade frame out of combat")
    AddAliasesForUnit(aliases, scope, "fade when out of combat")
    RegisterGroupBoolean(scope, "oocFadeEnabled", "oocFadeEnabled", "Fade Frame Out of Combat", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "out of combat opacity")
    AddAliasesForUnit(aliases, scope, "out of combat alpha")
    AddAliasesForUnit(aliases, scope, "ooc opacity")
    AddAliasesForUnit(aliases, scope, "ooc alpha")
    RegisterGroupNumber(scope, "oocFadeAlpha", "oocFadeAlpha", "Out of Combat Opacity", 0.5, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "group backdrop color")
    AddAliasesForUnit(aliases, scope, "group background color")
    AddAliasesForUnit(aliases, scope, "frame background color")
    AddAliasesForUnit(aliases, scope, "background color")
    AddAliasesForUnit(aliases, scope, "bar background color")
    AddAliasesForUnit(aliases, scope, "hp track color")
    AddAliasesForUnit(aliases, scope, "health track color")
    AddAliasesForUnit(aliases, scope, "track color")
    AddAliasesForUnit(aliases, scope, "backdrop color")
    RegisterGroupColor(scope, "groupBackdropColor", "bg", "Backdrop Color", 0.10, 0.10, 0.10, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background")
    AddAliasesForUnit(aliases, scope, "dead member background")
    AddAliasesForUnit(aliases, scope, "dead offline background")
    AddAliasesForUnit(aliases, scope, "dead background tint")
    RegisterGroupBoolean(scope, "deadBgEnabled", "deadBgEnabled", "Dead Background", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background color")
    AddAliasesForUnit(aliases, scope, "dead member background color")
    AddAliasesForUnit(aliases, scope, "dead offline background color")
    AddAliasesForUnit(aliases, scope, "dead bg color")
    RegisterGroupColor(scope, "deadBgColor", "deadBg", "Dead Background Color", 0.60, 0.05, 0.05, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "dead background opacity")
    AddAliasesForUnit(aliases, scope, "dead background alpha")
    AddAliasesForUnit(aliases, scope, "dead member background opacity")
    AddAliasesForUnit(aliases, scope, "dead offline background opacity")
    AddAliasesForUnit(aliases, scope, "dead bg opacity")
    RegisterGroupNumber(scope, "deadBgAlpha", "deadBgA", "Dead Background Opacity", 0.90, 0.05, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "tint offline members")
    AddAliasesForUnit(aliases, scope, "also tint offline members")
    AddAliasesForUnit(aliases, scope, "dead background offline members")
    AddAliasesForUnit(aliases, scope, "dead offline tint")
    RegisterGroupBoolean(scope, "deadBgOffline", "deadBgOffline", "Tint Offline Members", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor to")
    AddAliasesForUnit(aliases, scope, "anchor target")
    AddAliasesForUnit(aliases, scope, "anchor frame")
    RegisterGroupEnum(scope, "anchorToFrame", "anchorToFrame", "Anchor to", "FREE", { "FREE", "player", "target", "targettarget", "focustarget", "focus" }, {
        free = "FREE",
        none = "FREE",
        clear = "FREE",
        ui = "FREE",
        uiparent = "FREE",
        player = "player",
        target = "target",
        targettarget = "targettarget",
        ["target of target"] = "targettarget",
        tot = "targettarget",
        focustarget = "focustarget",
        ["focus target"] = "focustarget",
        focus = "focus",
    }, "rebuild", aliases, {
        exactAliases = GroupAnchorTargetExactAliases(),
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and (value and value ~= "" and value or "FREE") or "FREE"
        end,
        set = function(scopeKey, value)
            GroupDB(scopeKey).anchorToFrame = (value == "FREE") and nil or value
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "custom anchor frame")
    AddAliasesForUnit(aliases, scope, "custom anchor")
    AddAliasesForUnit(aliases, scope, "custom anchor name")
    RegisterGroupString(scope, "customAnchorFrame", "customAnchorFrame", "Custom Anchor Frame", "", "rebuild", aliases, {
        get = function(scopeKey)
            local value = GroupDB(scopeKey).anchorToFrame
            return StandardGroupAnchorTarget(value) and "" or tostring(value or "")
        end,
        set = function(scopeKey, value)
            value = TrimString(value)
            local lower = value:lower()
            GroupDB(scopeKey).anchorToFrame = (value == "" or lower == "free" or lower == "clear" or lower == "none") and nil or value
        end,
        description = "Sets a custom frame name for the group-frame anchor target.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "anchor point")
    AddAliasesForUnit(aliases, scope, "anchor position")
    RegisterGroupEnum(scope, "anchorPoint", "anchorPoint", "Anchor Point", "CENTER", { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }, {
        topleft = "TOPLEFT",
        ["top left"] = "TOPLEFT",
        top = "TOP",
        topright = "TOPRIGHT",
        ["top right"] = "TOPRIGHT",
        left = "LEFT",
        center = "CENTER",
        centre = "CENTER",
        middle = "CENTER",
        right = "RIGHT",
        bottomleft = "BOTTOMLEFT",
        ["bottom left"] = "BOTTOMLEFT",
        bottom = "BOTTOM",
        bottomright = "BOTTOMRIGHT",
        ["bottom right"] = "BOTTOMRIGHT",
    }, "rebuild", aliases)
end

-- Canonical player defensive container for defaults and the aura runtime.
local _, MSUF = ...
local stylePadding = not MSUF.Client.IsClassic and 0 or nil
local function MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer()
    return {
        enabled = true,
        name = "Defensive Buffs",
        auraType = "BUFF",
        sourceUnit = "player",
        playerDefensives = true,
        portraitIcon = false,
        portraitMaxIcons = 1,
        portraitCooldownText = true,
        portraitPositionWhenDisabled = false,
        autoBlacklistPlayerBuffs = true,
        disabledPredefinedSpellIDs = {},
        spellIDs = "",
        filters = {
            enabled = true,
            hidePermanent = false,
            onlyMine = false,
            onlyImportant = false,
            raid = false,
            raidInCombat = false,
            includeNameplateOnly = false,
            includeDispellable = false,
            dispellableAny = false,
            cancelable = false,
            notCancelable = false,
            crowdControl = false,
            externalDefensive = false,
            bigDefensive = false,
            exclusive = "none",
        },
        placed = {
            type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN",
            x = 0, y = 0, size = 24, barWidth = 54,
            max = 8, perRow = 4, spacing = 2, stylePadding = stylePadding,
            showCooldown = true, showCooldownSwipe = true, showStacks = true,
        },
        layer = 9,
        strata = "AUTO",
        frame = {
            type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
            priority = 5, thickness = 2, layer = 0, strata = "AUTO",
        },
    }
end
MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer = MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer
MSUF.ExportPublic("MSUF_CreateCanonicalPlayerDefensiveAuraContainer", MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer)

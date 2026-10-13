-- One castbar key schema for runtime positioning, previews and Edit Mode.
local _, MSUF = ...
MSUF.Castbars = MSUF.Castbars or {}
MSUF.Castbars.UNIT_CASTBAR = {
    player = {
        w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight",
        x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY",
        detached = "castbarPlayerDetached", match = "castbarPlayerMatchWidth", enable = "enablePlayerCastbar",
        dx = 0, dy = 5, test = "MSUF_SetPlayerCastbarTestMode",
    },
    target = {
        w = "castbarTargetBarWidth", h = "castbarTargetBarHeight",
        x = "castbarTargetOffsetX", y = "castbarTargetOffsetY",
        detached = "castbarTargetDetached", match = "castbarTargetMatchWidth", enable = "enableTargetCastbar",
        dx = 65, dy = -15, test = "MSUF_SetTargetCastbarTestMode",
    },
    focus = {
        w = "castbarFocusBarWidth", h = "castbarFocusBarHeight",
        x = "castbarFocusOffsetX", y = "castbarFocusOffsetY",
        detached = "castbarFocusDetached", match = "castbarFocusMatchWidth", enable = "enableFocusCastbar",
        fallbackX = "castbarTargetOffsetX", fallbackY = "castbarTargetOffsetY",
        dx = 65, dy = -15, test = "MSUF_SetFocusCastbarTestMode",
    },
    boss = {
        w = "bossCastbarWidth", h = "bossCastbarHeight", x = "bossCastbarOffsetX", y = "bossCastbarOffsetY",
        detached = "bossCastbarDetached", match = "bossCastbarMatchWidth", enable = "enableBossCastbar",
        dx = 0, dy = 0, test = "MSUF_SetBossCastbarTestMode",
    },
    arena = {
        w = "arenaCastbarWidth", h = "arenaCastbarHeight", x = "arenaCastbarOffsetX", y = "arenaCastbarOffsetY",
        detached = "arenaCastbarDetached", match = "arenaCastbarMatchWidth", enable = "enableArenaCastbar",
        dx = 0, dy = 0, test = "MSUF_SetArenaCastbarTestMode",
    },
}

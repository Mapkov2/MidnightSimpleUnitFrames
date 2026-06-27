-- Assistant Castbars interrupt/focus-kick appearance registry.
-- Loaded before MSUF_AssistantRegistry_Castbars_Appearance.lua; the appearance registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.RegisterInterruptAppearanceSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local CastbarAliases = ctx.CastbarAliases
    local RegisterCastbarBoolean = ctx.RegisterCastbarBoolean
    local RegisterCastbarNumber = ctx.RegisterCastbarNumber
    local RegisterCastbarEnum = ctx.RegisterCastbarEnum
    local ApplyFocusKick = ctx.ApplyFocusKick
    local ApplyFocusKickText = ctx.ApplyFocusKickText

    if type(Registry) ~= "table" or type(Registry.RegisterSetting) ~= "function" then return end
    if type(CastbarAliases) ~= "function" then return end
    if type(RegisterCastbarBoolean) ~= "function" or type(RegisterCastbarNumber) ~= "function" then return end
    if type(RegisterCastbarEnum) ~= "function" then return end

    RegisterCastbarBoolean("enableFocusKickIcon", "focusKick", "Focus Interrupt Tracker", false, CastbarAliases("focus interrupt tracker", "focus kick icon", "focus kick tracker", "fokus interrupt tracker", "fokus kick anzeige", "fokus kick tracker"), {
        reason = "MSUF2_FOCUS_KICK_ENABLE",
        apply = ApplyFocusKick,
    })
    Registry:RegisterSetting({
        key = "runtime.focusKickPreview",
        label = "Focus Kick On-screen Preview",
        category = "Appearance / Cast Bars",
        unit = "global",
        frameType = "castbar",
        attribute = "focusKickPreview",
        type = "boolean",
        aliases = CastbarAliases("focus kick preview", "focus interrupt preview", "show focus kick preview", "show on-screen preview", "on-screen preview", "fokus kick vorschau", "fokus interrupt vorschau", "fokus kick anzeige vorschau"),
        get = function()
            local fn = _G.MSUF_FocusKick_IsPreviewEnabled
            return type(fn) == "function" and (fn() and true or false) or false
        end,
        set = function(value)
            local fn = _G.MSUF_FocusKick_SetPreviewEnabled
            if type(fn) == "function" then fn(value and true or false) end
        end,
        apply = function() end,
        combatSafe = true,
        verifyAfterSet = true,
        description = "On-screen Focus Kick preview toggle.",
    })
    RegisterCastbarNumber("focusKickIconWidth", "focusKickWidth", "Focus Kick Width", 40, 16, 128, CastbarAliases("focus kick width", "focus interrupt tracker width", "fokus kick breite", "fokus interrupt tracker breite"), {
        reason = "MSUF2_FOCUS_KICK_WIDTH",
        apply = ApplyFocusKick,
    })
    RegisterCastbarNumber("focusKickIconHeight", "focusKickHeight", "Focus Kick Height", 40, 16, 128, CastbarAliases("focus kick height", "focus interrupt tracker height", "fokus kick hoehe", "fokus interrupt tracker hoehe"), {
        reason = "MSUF2_FOCUS_KICK_HEIGHT",
        apply = ApplyFocusKick,
    })
    RegisterCastbarNumber("focusKickTextSize", "focusKickTextSize", "Focus Kick Text Size", 12, 8, 24, CastbarAliases("focus kick text size", "focus interrupt tracker text size", "fokus kick textgroesse", "fokus interrupt tracker schriftgroesse"), {
        reason = "MSUF2_FOCUS_KICK_TEXT",
        apply = ApplyFocusKickText,
    })
    RegisterCastbarNumber("focusKickIconOffsetX", "focusKickOffsetX", "Focus Kick X Offset", 300, -500, 500, CastbarAliases("focus kick x offset", "focus interrupt tracker x", "fokus kick x versatz", "fokus interrupt tracker x"), {
        reason = "MSUF2_FOCUS_KICK_X",
        apply = ApplyFocusKick,
    })
    RegisterCastbarNumber("focusKickIconOffsetY", "focusKickOffsetY", "Focus Kick Y Offset", 0, -500, 500, CastbarAliases("focus kick y offset", "focus interrupt tracker y", "fokus kick y versatz", "fokus interrupt tracker y"), {
        reason = "MSUF2_FOCUS_KICK_Y",
        apply = ApplyFocusKick,
    })

    RegisterCastbarBoolean("kickReadyShowTarget", "kickReadyTarget", "Show Interrupt Ready on Target Castbar", false, CastbarAliases("target interrupt ready", "show interrupt ready on target", "ziel interrupt bereit", "interrupt bereit am ziel"), {
        reason = "MSUF2_KICK_READY_ENABLE",
    })
    RegisterCastbarBoolean("kickReadyShowFocus", "kickReadyFocus", "Show Interrupt Ready on Focus Castbar", false, CastbarAliases("focus interrupt ready", "show interrupt ready on focus", "fokus interrupt bereit", "interrupt bereit am fokus"), {
        reason = "MSUF2_KICK_READY_ENABLE",
    })
    RegisterCastbarBoolean("kickReadyShowBoss", "kickReadyBoss", "Show Interrupt Ready on Boss Cast Bars", false, CastbarAliases("boss interrupt ready", "show interrupt ready on boss", "boss interrupt bereit", "interrupt bereit am boss"), {
        reason = "MSUF2_KICK_READY_ENABLE",
    })
    RegisterCastbarEnum("kickReadyStyle", "kickReadyStyle", "Interrupt Ready Indicator Style", "border", { "border", "box", "fill" }, CastbarAliases("interrupt ready style", "kick ready style", "interrupt ready indicator style", "interrupt ready fill", "unavailable cast fill", "unavailable fill", "interrupt bereit stil", "interrupt bereit anzeige stil"), {
        reason = "MSUF2_KICK_READY_STYLE",
        valueAliases = {
            border = "border",
            outline = "border",
            rand = "border",
            box = "box",
            square = "box",
            kasten = "box",
            quadrat = "box",
            fill = "fill",
            bar = "fill",
            castbarfill = "fill",
            unavailable = "fill",
            unavailablefill = "fill",
        },
    })
    RegisterCastbarNumber("kickReadySize", "kickReadySize", "Interrupt Ready Indicator Size", 16, 8, 32, CastbarAliases("interrupt ready size", "kick ready size", "interrupt ready indicator size", "interrupt bereit groesse", "interrupt bereit anzeige groesse"), {
        reason = "MSUF2_KICK_READY_SIZE",
    })
    RegisterCastbarBoolean("kickReadyAutoSize", "kickReadyAutoSize", "Auto-Size Interrupt Ready Indicator", true, CastbarAliases("interrupt ready auto size", "kick ready auto size", "auto size interrupt ready indicator", "interrupt bereit automatische groesse"), {
        reason = "MSUF2_KICK_READY_AUTO",
    })
    RegisterCastbarEnum("kickReadyAnchor", "kickReadyAnchor", "Interrupt Ready Indicator Anchor", "RIGHT", { "RIGHT", "LEFT", "TOP", "BOTTOM" }, CastbarAliases("interrupt ready anchor", "kick ready anchor", "interrupt ready indicator anchor", "interrupt bereit anker", "interrupt bereit position"), {
        reason = "MSUF2_KICK_READY_ANCHOR",
        valueAliases = {
            right = "RIGHT",
            left = "LEFT",
            top = "TOP",
            bottom = "BOTTOM",
            oben = "TOP",
            unten = "BOTTOM",
            links = "LEFT",
            rechts = "RIGHT",
        },
    })
    RegisterCastbarNumber("kickReadyOffsetX", "kickReadyOffsetX", "Interrupt Ready X Offset", 4, -50, 50, CastbarAliases("interrupt ready x offset", "kick ready x", "interrupt ready indicator x offset", "interrupt bereit x versatz"), {
        reason = "MSUF2_KICK_READY_X",
    })
    RegisterCastbarNumber("kickReadyOffsetY", "kickReadyOffsetY", "Interrupt Ready Y Offset", 0, -50, 50, CastbarAliases("interrupt ready y offset", "kick ready y", "interrupt ready indicator y offset", "interrupt bereit y versatz"), {
        reason = "MSUF2_KICK_READY_Y",
    })
end

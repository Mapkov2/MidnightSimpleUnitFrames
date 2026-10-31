local _, MSUF = ...
local KickReady = MSUF.Require("MSUF", "Castbars/MSUF_InterruptReady_Consumers.lua").Castbars.KickReady
-- Public consumer look and native color selectors. The engine supplies its
-- private resolved slots and callbacks once at load; no profile is read here.
-- v1 consumers retain their nameplate-switch lifecycle and aggregate selector.
-- v2 cooldown consumers explicitly opt in independently and select one slot.
function KickReady.CreateConsumerAPI(engine)
    local look, fillColors = {}, { {}, {}, {} }
    local GeneralDB, IndicatorStyle, RGBAForReady = engine.General, engine.Style, engine.ReadyRGBA
    local MSUF, CreateColor = engine.Host, engine.Color
    local function Look()
        local general = GeneralDB()
        look.show = general.kickReadyShowNameplates == true
        look.style = IndicatorStyle(general)
        look.marker, look.segment = general.kickReadyTimeMarker == true, general.kickReadyTimeSegment == true
        look.readyR, look.readyG, look.readyB, look.readyA = RGBAForReady(true, general)
        look.outline = math.max(0, math.min(math.floor((tonumber(general.castbarOutlineThickness) or 1) + 0.5), 12))
        look.boxSize = general.kickReadyAutoSize == false and tonumber(general.kickReadySize) or 0
        look.boxAnchor = general.kickReadyAnchor or "RIGHT"
        look.boxOffsetX = tonumber(general.kickReadyOffsetX) or 4
        look.boxOffsetY = tonumber(general.kickReadyOffsetY) or 0
        local texture = MSUF.Public.GetCastbarTexture
        look.texture = texture and texture() or "Interface\\TargetingFrame\\UI-StatusBar"
        return look
    end
    local function RGBA(rawNotInterruptible)
        return engine.EvaluateRGBA(engine.Status(), rawNotInterruptible)
    end
    local function FillColor(cache, red, green, blue)
        if cache.r ~= red or cache.g ~= green or cache.b ~= blue or not cache.color then
            cache.r, cache.g, cache.b = red, green, blue
            cache.color = CreateColor(red, green, blue, 1)
        end
        return cache.color
    end
    local function FillColors()
        local public = MSUF.Public
        local castR, castG, castB, nonR, nonG, nonB = public.ResolveCastbarColors()
        local red, green, blue = public.ResolveInterruptUnavailableCastColor()
        return FillColor(fillColors[1], castR, castG, castB), FillColor(fillColors[2], nonR, nonG, nonB),
            FillColor(fillColors[3], red, green, blue)
    end
    local function Spell(index)
        if index < 1 or index > engine.SlotCount() then return nil end
        return engine.Slots[index].spellID
    end
    local function SelectSlotColor(index, readyColor, unavailableColor, rawNotInterruptible)
        local ready = engine.SlotReady(index)
        local selected
        if engine.IsSecret(ready) then
            if not engine.SelectNative then return unavailableColor end
            selected = engine.SelectNative(ready, readyColor, unavailableColor)
        else
            selected = ready == true and readyColor or unavailableColor
        end
        if engine.IsSecret(rawNotInterruptible) then
            if not engine.SelectNative then return unavailableColor end
            return engine.SelectNative(rawNotInterruptible, unavailableColor, selected)
        end
        return rawNotInterruptible == true and unavailableColor or selected
    end
    return {
        version = 2,
        Register = engine.Register, Unregister = engine.Unregister,
        HasConsumers = engine.HasConsumers, SetActive = engine.SetActive,
        Look = Look, RGBA = RGBA, FillColors = FillColors, SelectColor = engine.SelectColor,
        SlotCount = engine.SlotCount, Cooldown = engine.Cooldown,
        Spell = Spell, SelectSlotColor = SelectSlotColor,
    }
end

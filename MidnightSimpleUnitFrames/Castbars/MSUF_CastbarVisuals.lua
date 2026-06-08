local previousUpdateCastbarVisuals = _G.MSUF_UpdateCastbarVisuals

local function RefreshCastbarFrame(frame)
    if not (frame and frame.statusBar) then
        return
    end

    if type(_G.MSUF_ApplyCastbarOutline) == "function" then
        _G.MSUF_ApplyCastbarOutline(frame, false)
    end

    if type(_G.MSUF_KickReady_ApplyLayout) == "function" then
        _G.MSUF_KickReady_ApplyLayout(frame)
    end

    if type(_G.MSUF_KickReady_RefreshFrame) == "function" and frame.MSUF_castActive then
        _G.MSUF_KickReady_RefreshFrame(frame, nil)
    end

    if frame.backgroundBar and type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
        local red, green, blue, alpha = _G.MSUF_GetCastbarBackgroundColor()
        frame.backgroundBar:SetVertexColor(red or 0.176, green or 0.176, blue or 0.176, alpha or 1)
    end

    if frame.statusBar and type(_G.MSUF_RefreshCastbarStyleCache) == "function" then
        _G.MSUF_RefreshCastbarStyleCache(frame)

        if frame.MSUF_cachedCastbarTexture then
            frame.statusBar:SetStatusBarTexture(frame.MSUF_cachedCastbarTexture)
        end

        if frame.backgroundBar and frame.MSUF_cachedCastbarBackgroundTexture then
            frame.backgroundBar:SetTexture(frame.MSUF_cachedCastbarBackgroundTexture)
        end
    end
end

function _G.MSUF_UpdateCastbarVisuals(...)
    if type(previousUpdateCastbarVisuals) == "function" and previousUpdateCastbarVisuals ~= _G.MSUF_UpdateCastbarVisuals then
        previousUpdateCastbarVisuals(...)
    end

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            RefreshCastbarFrame(bossCastbars[index])
        end
    end
end

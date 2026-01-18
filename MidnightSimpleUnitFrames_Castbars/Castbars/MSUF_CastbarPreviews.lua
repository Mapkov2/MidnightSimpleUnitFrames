-- Castbars/MSUF_CastbarPreviews.lua
-- Step 13: Move preview factory functions out of MSUF_Castbars.lua
-- This file only creates preview frames (player/target/focus) and wires Edit Mode handlers.
-- No runtime cast logic, no timer/direction logic.

local addonName, ns = ...

local CreatePreviewFrame = _G.MSUF_CreateCastbarPreviewFrame
local SetupPreviewEditHandlers = _G.MSUF_SetupCastbarPreviewEditHandlers

local function DevPrint(msg)
    if _G.MSUF_DevPrint then
        _G.MSUF_DevPrint(msg)
    end
end

-- Local copy of the player castbar sizing helper (was local in MSUF_Castbars.lua).
local function MSUF_GetPlayerCastbarDesiredSize(g, fallbackW, fallbackH)
    local w = g and tonumber(g.castbarPlayerBarWidth) or nil
    local h = g and tonumber(g.castbarPlayerBarHeight) or nil

    if not w or w <= 0 then
        w = g and tonumber(g.castbarGlobalWidth) or nil
    end
    if not h or h <= 0 then
        h = g and tonumber(g.castbarGlobalHeight) or nil
    end

    if not w or w <= 0 then w = fallbackW or 250 end
    if not h or h <= 0 then h = fallbackH or 18 end

    return w, h
end

if type(_G.MSUF_CreatePlayerCastbarPreview) ~= "function" then
    function _G.MSUF_CreatePlayerCastbarPreview()
        if _G.MSUF_PlayerCastbarPreview then
            return _G.MSUF_PlayerCastbarPreview
        end

        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local w, h = MSUF_GetPlayerCastbarDesiredSize(g, 250, 18)

        if type(CreatePreviewFrame) ~= "function" then
            DevPrint("MSUF: MSUF_CreateCastbarPreviewFrame missing (player preview)")
            return
        end

        local frame = CreatePreviewFrame("player", "MSUF_PlayerCastbarPreview", {
            parent = UIParent,
            template = "BackdropTemplate",
            width = w,
            height = h,
            statusBarHeight = math.max(4, h - 2),
            initialValue = 0.5,
            showIcon = true,
            iconSize = h,
        })

        if frame then
            frame._msufIsPreview = true
        end
        _G.MSUF_PlayerCastbarPreview = frame

        -- Apply the same icon/statusbar layout rules as the real player castbar.
        if frame and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
            _G.MSUF_ApplyPlayerCastbarIconLayout(frame, g, -1, 1)
        end

        if type(SetupPreviewEditHandlers) == "function" then
            SetupPreviewEditHandlers(frame, "player")
        else
            DevPrint("MSUF: MSUF_SetupCastbarPreviewEditHandlers missing (player preview)")
        end

        return frame
    end
end

if type(_G.MSUF_CreateTargetCastbarPreview) ~= "function" then
    function _G.MSUF_CreateTargetCastbarPreview()
        if _G.MSUF_TargetCastbarPreview then
            return _G.MSUF_TargetCastbarPreview
        end

        if type(CreatePreviewFrame) ~= "function" then
            DevPrint("MSUF: MSUF_CreateCastbarPreviewFrame missing (target preview)")
            return
        end

        local frame = CreatePreviewFrame("target", "MSUF_TargetCastbarPreview", {
            parent = UIParent,
            template = "BackdropTemplate",
            width = 250,
            height = 18,
            statusBarHeight = 16,
            initialValue = 0.5,
            showIcon = true,
            iconSize = 18,
        })

        if frame then
            frame._msufIsPreview = true
        end
        _G.MSUF_TargetCastbarPreview = frame

        if type(SetupPreviewEditHandlers) == "function" then
            SetupPreviewEditHandlers(frame, "target")
        else
            DevPrint("MSUF: MSUF_SetupCastbarPreviewEditHandlers missing (target preview)")
        end

        return frame
    end
end

if type(_G.MSUF_CreateFocusCastbarPreview) ~= "function" then
    function _G.MSUF_CreateFocusCastbarPreview()
        if _G.MSUF_FocusCastbarPreview then
            return _G.MSUF_FocusCastbarPreview
        end

        if type(CreatePreviewFrame) ~= "function" then
            DevPrint("MSUF: MSUF_CreateCastbarPreviewFrame missing (focus preview)")
            return
        end

        local frame = CreatePreviewFrame("focus", "MSUF_FocusCastbarPreview", {
            parent = UIParent,
            template = "BackdropTemplate",
            width = 250,
            height = 18,
            statusBarHeight = 16,
            initialValue = 0.5,
            showIcon = true,
            iconSize = 18,
        })

        if frame then
            frame._msufIsPreview = true
        end
        _G.MSUF_FocusCastbarPreview = frame

        if type(SetupPreviewEditHandlers) == "function" then
            SetupPreviewEditHandlers(frame, "focus")
        else
            DevPrint("MSUF: MSUF_SetupCastbarPreviewEditHandlers missing (focus preview)")
        end

        return frame
    end
end

-- Assistant EditMode group preview workflow helpers.
-- Loaded before MSUF_AssistantRegistry_EditMode_Previews.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

local GROUP_PREVIEW_COUNTS = { party = 5, raid = 30, mythicraid = 20 }
local GROUP_PREVIEW_LABELS = { party = "Party Group Frame Preview", raid = "Raid Group Frame Preview", mythicraid = "Mythic Raid Group Frame Preview" }
local GROUP_PREVIEW_PAGES = { gf_layout = true, gf_bars = true, gf_indicators = true }

function A.EditModeRegistry.BuildGroupPreviewHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Menu = ctx.M or M
    local Namespace = ctx.MSUF or MSUF
    local Status = ctx.Status
    if type(Status) ~= "function" then return nil end

    local function NormalizeGroupPreviewScope(scope)
        scope = tostring(scope or ""):lower():gsub("%s+", "")
        if scope == "mythic" or scope == "mythicraid" then return "mythicraid" end
        if scope == "raid" then return "raid" end
        if scope == "party" or scope == "group" then return "party" end
        local current = Menu and Menu.gfScope
        if current == "party" or current == "raid" or current == "mythicraid" then return current end
        return "party"
    end

    local function GroupPreviewLabel(scope)
        return GROUP_PREVIEW_LABELS[scope] or "Group Frames Preview"
    end

    local function PersistGroupPreviewScope(scope)
        if not scope then return end
        if Menu and type(Menu.PersistMenuStateValue) == "function" then
            Menu.PersistMenuStateValue("gfScope", scope)
        elseif Menu then
            Menu.gfScope = scope
        end
    end

    local function OpenMenuPage(pageKey)
        if pageKey and Menu and type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage(pageKey) end
        if Menu and type(Menu.Open) == "function" then return Menu.Open(pageKey) ~= false end
        if Menu and type(Menu.SelectPage) == "function" then return Menu.SelectPage(pageKey) ~= false end
        return true
    end

    local function IsGroupPreviewActive(scope)
        if _G.MSUF2_GFPagePreviewActive == true then
            local activeKind = _G.MSUF2_GFPagePreviewKind
            if activeKind == nil or activeKind == scope then return true end
        end
        local gf = Namespace and Namespace.GF
        local active = gf and gf._previewActive
        return type(active) == "table" and active[scope] == true
    end

    local function IsEditModeActive()
        if Menu and type(Menu.IsMSUFEditModeActive) == "function" then
            return Menu.IsMSUFEditModeActive(true) and true or false
        end
        return Status().active == true
    end

    local function HideMenuGroupPreview(scope)
        local gf = Namespace and Namespace.GF
        if gf and type(gf.HidePreview) == "function" then
            if scope then
                gf.HidePreview(scope)
            else
                gf.HidePreview("party")
                gf.HidePreview("raid")
                gf.HidePreview("mythicraid")
            end
        end
        if _G.MSUF2_GFPagePreviewKind == nil or _G.MSUF2_GFPagePreviewKind == scope or scope == nil then
            _G.MSUF2_GFPagePreviewActive = nil
            _G.MSUF2_GFPagePreviewKind = nil
        end
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(nil) end
    end

    local function LiveRaidKind(gf)
        local kind = gf and type(gf.GetLiveRaidKind) == "function" and gf.GetLiveRaidKind() or nil
        if kind == "mythicraid" then return "mythicraid" end
        return "raid"
    end

    local function LiveGroupKind(gf)
        if gf and type(gf.GetLiveGroupKind) == "function" then return gf.GetLiveGroupKind() end
        if _G.IsInRaid and _G.IsInRaid() then return LiveRaidKind(gf) end
        if _G.IsInGroup and _G.IsInGroup() then return "party" end
        return nil
    end

    local function GroupConfEnabled(gf, scope)
        local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(scope) or nil
        return conf and conf.enabled == true
    end

    local function LiveGroupFramesCoverScope(gf, scope)
        local liveKind = LiveGroupKind(gf)
        if scope == "party" then
            if not GroupConfEnabled(gf, "party") then return false end
            local conf = gf and type(gf.GetConf) == "function" and gf.GetConf("party") or nil
            return liveKind == "party" or (liveKind == nil and conf and conf.showSolo == true) or false
        elseif scope == "raid" or scope == "mythicraid" then
            return liveKind == scope and GroupConfEnabled(gf, scope)
        end
        return false
    end

    local function ShowMenuGroupPreview(scope)
        PersistGroupPreviewScope(scope)
        OpenMenuPage(GROUP_PREVIEW_PAGES[Menu and Menu.activeKey] and Menu.activeKey or "gf_layout")

        local synced = false
        if Menu and type(Menu.SyncGFPagePreviewForKey) == "function" then
            Menu.SyncGFPagePreviewForKey(Menu.activeKey or "gf_layout", true)
            synced = true
        end

        local gf = Namespace and Namespace.GF
        local shown = false
        if gf and type(gf.ShowPreview) == "function" then
            _G.MSUF2_GFPagePreviewActive = true
            _G.MSUF2_GFPagePreviewKind = scope
            if gf.SetPreviewAnchor then
                gf.SetPreviewAnchor("party", nil)
                gf.SetPreviewAnchor("raid", nil)
                gf.SetPreviewAnchor("mythicraid", nil)
            end
            if scope ~= "party" and type(gf.HidePreview) == "function" then gf.HidePreview("party") end
            if scope ~= "raid" and type(gf.HidePreview) == "function" then gf.HidePreview("raid") end
            if scope ~= "mythicraid" and type(gf.HidePreview) == "function" then gf.HidePreview("mythicraid") end
            if LiveGroupFramesCoverScope(gf, scope) then
                if type(gf.HidePreview) == "function" then gf.HidePreview(scope) end
                shown = true
            else
                shown = gf.ShowPreview(scope, GROUP_PREVIEW_COUNTS[scope] or 5) ~= false
            end
            if shown and type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(scope) end
        end

        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(scope) end
        if not (synced or shown) then
            return false, "Enter Edit Mode so I can show the Group Frame preview."
        end
        return true
    end

    return {
        NormalizeGroupPreviewScope = NormalizeGroupPreviewScope,
        GroupPreviewLabel = GroupPreviewLabel,
        PersistGroupPreviewScope = PersistGroupPreviewScope,
        IsGroupPreviewActive = IsGroupPreviewActive,
        IsEditModeActive = IsEditModeActive,
        HideMenuGroupPreview = HideMenuGroupPreview,
        ShowMenuGroupPreview = ShowMenuGroupPreview,
    }
end

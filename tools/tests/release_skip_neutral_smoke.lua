-- Non-destructive release-tour choices keep neutral styling and action semantics.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local Stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ shown = true })
env:InstallGlobals()

for _, width in ipairs({ 480, 960 }) do
    local controls, blocked = {}, false
    local skipped, cancelled, refreshed = 0, 0, 0
    local record = { status = "skip_warning", outcomes = {} }
    local spec = { highlights = { { id = "portrait", missed = "Portrait options" } } }
    local controller = {
        ShouldShow = function() return true end,
        GetCurrent = function() return "6.5", spec, record end,
        ConfirmSkip = function() skipped = skipped + 1 end,
        CancelSkip = function() cancelled = cancelled + 1 end,
    }
    local color = { 0.2, 0.3, 0.4, 1 }
    local T = { colors = setmetatable({}, { __index = function() return color end }) }
    function T.Panel(parent) return CreateFrame("Frame", nil, parent) end
    function T.Font(parent, _, text)
        local label = parent:CreateFontString(nil, "OVERLAY")
        label:SetText(text)
        return label
    end
    function T.SetTranslatedText(label, text) label:SetText(text) end
    function T.Button(parent, text, w, h)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(w, h)
        button.caption, button.role = text, "secondary"
        return button
    end
    function T.SkinPrimaryButton(button) button.role = "primary" end
    function T.SkinDangerButton(button) button.role = "danger" end
    local M = {
        Theme = T, Tr = function(text) return text end,
        BlockCombatAction = function() return blocked end,
        InvalidatePage = function(page) assert(page == "home") end,
        SelectPage = function(page) assert(page == "home"); refreshed = refreshed + 1 end,
        Widgets = { SetTextLayout = function(label, w, alignment)
            label:SetWidth(w)
            label:SetJustifyH(alignment)
        end },
    }
    function M.RegisterSearchWidget(button, metadata)
        local action = metadata.actionKey:match("%.([^%.]+)$")
        controls[action] = { button = button, metadata = metadata }
    end
    local namespace = { MSUF2 = M, UpgradeHighlights = controller }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_UpgradeHighlights.lua"))(
        "MidnightSimpleUnitFrames_Options", namespace)
    local ctx = { wrapper = CreateFrame("Frame"), width = width }
    function ctx:SetContentHeight(height) self.height = height end
    assert(M.BuildUpgradeHighlightDashboardScene(ctx), "release-tour scene was not built")
    local skip, cancel = assert(controls.confirm_skip), assert(controls.cancel_skip)
    assert(skip.button.role == "secondary", "skipping an informational tour is painted as a destructive action")
    assert(cancel.button.role == "primary", "continuing the tour lost its primary action")
    for _, item in ipairs({ skip, cancel }) do
        assert(item.metadata.historyMode == "none" and item.button._msuf2SkipHistoryCheckpoint,
            "tour navigation must not add a settings undo checkpoint")
    end
    blocked = true
    skip.button:GetScript("OnClick")()
    cancel.button:GetScript("OnClick")()
    assert(skipped == 0 and cancelled == 0 and refreshed == 0, "tour actions bypassed combat refusal")
    blocked = false
    skip.button:GetScript("OnClick")()
    cancel.button:GetScript("OnClick")()
    assert(skipped == 1 and cancelled == 1 and refreshed == 2, "tour callbacks or page refresh changed")
    assert(ctx.height > 0, "release-tour scene has no scroll height")
end
print("release_skip_neutral_smoke: ok (compact/wide, neutral action, callbacks, combat, history)")

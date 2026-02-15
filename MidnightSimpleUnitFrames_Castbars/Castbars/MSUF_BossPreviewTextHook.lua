-- Ensures ALL Boss Castbar Previews use the shared StyleKit text layout (castText/timeText anchors, offsets, sizes).

local addonName, ns = ...
ns = ns or {}

if _G.__MSUF_BossPreviewTextHooked then
    return
end
_G.__MSUF_BossPreviewTextHooked = true

local function GetBossPreviewCount()
    local n = tonumber(_G.MAX_BOSS_FRAMES)
    if not n or n < 1 or n > 12 then n = 5 end
    return n
end

local function ApplyBossPreviewTextLayout()
    local function applyOne(f)
        if not f or not f.statusBar or not f.castText or not f.timeText then
            return
        end
        if type(_G.MSUF_ApplyBossCastbarTextsLayout) == "function" then
            -- Match legacy feel: time text baseline inset is -2,0
            pcall(_G.MSUF_ApplyBossCastbarTextsLayout, f, { baselineTimeX = -2, baselineTimeY = 0 })
        end
    end

    -- boss1 (stable name)
    applyOne(_G.MSUF_BossCastbarPreview)

    -- boss2..bossN (if created)
    local max = GetBossPreviewCount()
    for i = 2, max do
        applyOne(_G["MSUF_BossCastbarPreview" .. i])
    end
end

-- Try to hook preview updates so layout is always re-applied when sliders/toggles change.
if type(hooksecurefunc) == "function" then
    pcall(hooksecurefunc, "MSUF_UpdateBossCastbarPreview", ApplyBossPreviewTextLayout)
end

-- Also apply once on next tick (helps if preview exists already when we load).
if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0, ApplyBossPreviewTextLayout)
end

-- Large saved-profile fixture: customized aura lists, bar colors and presets.
return function(db)
    db.auras3 = db.auras3 or {}
    db.auras3.historyFixture = {}
    for i = 1, 2400 do
        db.auras3.historyFixture[i] = { spellID = 100000 + i, enabled = i % 2 == 0,
            units = { player = true, target = false }, color = { .2, .4, .6, 1 }, priority = i % 20 }
    end
    db.classPowerPresets = db.classPowerPresets or {}
    for i = 1, 24 do db.classPowerPresets["History " .. i] = { width = 200 + i, height = 12, slots = { 1, 2, 3, 4, 5 } } end
end

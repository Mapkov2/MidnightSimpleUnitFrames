param(
    [string]$AddonRoot = "MidnightSimpleUnitFrames",
    [int]$Examples = 12
)

$ErrorActionPreference = "Stop"

$locales = @(
    "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"
)

$englishLocales = @{
    enUS = $true
    enGB = $true
}

$menuRoot = Join-Path $AddonRoot "Menu2"
$localeRoot = Join-Path $AddonRoot "Locales"
$runtimeLocalePath = Join-Path $localeRoot "MSUF_RuntimeLocalization.lua"
$auditLocalePath = Join-Path $localeRoot "MSUF_AuditLocalization.lua"

function Add-Key {
    param([System.Collections.Generic.HashSet[string]]$Set, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    $Value = ConvertFrom-LuaStringLiteral $Value
    if ($Value -match '^MSUF2_') { return }
    if ($Value -match '^[\s0-9%.,:;+\-*/\\|<>=~_()]+$') { return }
    if ($Value -match '^(?:%[0-9.]*[sdif]|%%|\s|[.,:;+\-*/\\|<>=~_()])+$') { return }
    if ($Value -match '^\d+(?:p|K|k)?$') { return }
    if ($Value -in @("AaBbCc", "BUFFS", "DEBUFFS", "SPELL", "TEXT")) { return }
    if ($Value -match '^\|cff[0-9a-fA-F]{6}$') { return }
    if ($Value -match '^v\d') { return }
    if ($Value -match '^[a-z]+(?:[A-Z][A-Za-z0-9]*)+$') { return }
    [void]$Set.Add($Value)
}

function ConvertFrom-LuaStringLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    $Value = $Value -replace '\\n', "`n"
    $Value = $Value -replace '\\r', "`r"
    $Value = $Value -replace '\\t', "`t"
    $Value = $Value -replace '\\"', '"'
    $Value = $Value -replace '\\\\', '\'
    return $Value
}

function Read-LocalePairs {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $pairs = @{}
    $patterns = @(
        'L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"',
        '\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"'
    )
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $pairs[(ConvertFrom-LuaStringLiteral $match.Groups[1].Value)] = ConvertFrom-LuaStringLiteral $match.Groups[2].Value
        }
    }
    return $pairs
}

function Read-RuntimeLocalePairs {
    param([string]$Path, [string]$Locale)
    $pairs = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $pairs }

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    foreach ($match in [regex]::Matches($text, ('(?:AddMissing|SetLocale|SetAudit)\("' + [regex]::Escape($Locale) + '"\s*,\s*\{(?<body>.*?)\r?\n\}\)'), 'Singleline')) {
        $body = $match.Groups["body"].Value
        $bodyPairs = Read-LocalePairsFromText $body
        foreach ($key in $bodyPairs.Keys) { $pairs[$key] = $bodyPairs[$key] }
    }

    $tableBlocks = @{}
    foreach ($tableMatch in [regex]::Matches($text, 'local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{(?<body>.*?)\r?\n\}', 'Singleline')) {
        $tableBlocks[$tableMatch.Groups[1].Value] = $tableMatch.Groups["body"].Value
    }
    foreach ($aliasMatch in [regex]::Matches($text, ('(?:AddMissing|SetLocale|SetAudit)\("' + [regex]::Escape($Locale) + '"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'))) {
        $name = $aliasMatch.Groups[1].Value
        if ($tableBlocks.ContainsKey($name)) {
            $bodyPairs = Read-LocalePairsFromText $tableBlocks[$name]
            foreach ($key in $bodyPairs.Keys) { $pairs[$key] = $bodyPairs[$key] }
        }
    }

    return $pairs
}

function Read-LocalePairsFromText {
    param([string]$Text)
    $pairs = @{}
    $patterns = @(
        'L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"',
        '\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"'
    )
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Text, $pattern)) {
            $pairs[(ConvertFrom-LuaStringLiteral $match.Groups[1].Value)] = ConvertFrom-LuaStringLiteral $match.Groups[2].Value
        }
    }
    return $pairs
}

$keys = [System.Collections.Generic.HashSet[string]]::new()
$patterns = @(
    '\b(?:W\.)?(?:Toggle|Slider|Dropdown|Segment|Button|LabelAt|Text)\s*\([^\n]*?"((?:[^"\\]|\\.)*)"',
    '\bW\.(?:ToggleAt|SliderAt|DropdownAt)\s*\(\s*[^,\r\n]+,\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:BindTableToggle|BindTableSlider|BindTableDropdown|BindValueToggle|BindValueSlider|BindValueDropdown|BindNestedToggle|BindNestedSlider|BindNestedDropdown|BindScopeToggle|BindScopeSlider|BindScopeDropdown|ToggleAt|ValueToggleAt|ScopedToggleAt|SliderAt|ValueSliderAt|ScopedSliderAt|DropdownAt|ValueDropdownAt|ScopedDropdownAt)\s*\(\s*[^,\r\n]+,\s*[^,\r\n]+,\s*"((?:[^"\\]|\\.)*)"',
    'CollapsibleSection\s*\([^\n]*?,\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:\w+:)?Header\s*\(\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:\w+:)?Header\s*\(\s*"(?:(?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"',
    'RegisterPage\s*\([^\n]*?title\s*=\s*"((?:[^"\\]|\\.)*)"',
    '\{\s*"(?:(?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:label|text|title|answer|tooltip|hint|summary|help|subtitle|caption)\s*=\s*"((?:[^"\\]|\\.)*)"',
    '\bM\.Tr\s*\(\s*"((?:[^"\\]|\\.)*)"',
    '\bM\.Format\s*\(\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:SetText|AddLine|SetTextColor)\s*\(\s*"((?:[^"\\]|\\.)*)"'
)

Get-ChildItem -LiteralPath $menuRoot -Recurse -Filter "*.lua" | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            Add-Key $keys $match.Groups[1].Value
        }
    }
}

$searchPath = Join-Path $menuRoot "MSUF_Menu2_Search.lua"
if (Test-Path -LiteralPath $searchPath) {
    $searchText = Get-Content -LiteralPath $searchPath -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($searchText, '\btarget\s*=\s*"((?:[^"\\]|\\.)*)"')) {
        Add-Key $keys $match.Groups[1].Value
    }
}

$translatedCallPatterns = @(
    '\b(?:M\.Tr|Tr|TR|QuickTr|HelpText|ns\.Translate|ns\.TR)\s*\(\s*"((?:[^"\\]|\\.)*)"',
    '\b(?:M\.Tr|Tr|TR|QuickTr|HelpText|ns\.Translate|ns\.TR)\s*\([^\r\n)]*\bor\s*"((?:[^"\\]|\\.)*)"',
    '\bM\.Format\s*\(\s*(?:M\.Tr\s*\(\s*)?"((?:[^"\\]|\\.)*)"'
)

$runtimeRoots = @(
    "Core", "EditMode2", "Auras2", "GroupFrames", "Modules", "UI", "Features", "ClassPower"
) | ForEach-Object { Join-Path $AddonRoot $_ }
$castbarsRoot = "MidnightSimpleUnitFrames_Castbars"
if (Test-Path -LiteralPath $castbarsRoot) { $runtimeRoots += $castbarsRoot }

foreach ($root in $runtimeRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -Filter "*.lua" | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        foreach ($pattern in $translatedCallPatterns) {
            foreach ($match in [regex]::Matches($text, $pattern)) {
                Add-Key $keys $match.Groups[1].Value
            }
        }
    }
}

$corePath = Join-Path $menuRoot "MSUF_Menu2_Core.lua"
if (Test-Path -LiteralPath $corePath) {
    $coreText = Get-Content -LiteralPath $corePath -Raw -Encoding UTF8
    $navMatch = [regex]::Match($coreText, 'local\s+NAV\s*=\s*\{(?<body>.*?)\r?\n\}', 'Singleline')
    if ($navMatch.Success) {
        $navBody = $navMatch.Groups["body"].Value
        foreach ($match in [regex]::Matches($navBody, '\b(?:header|label)\s*=\s*"((?:[^"\\]|\\.)*)"')) {
            Add-Key $keys $match.Groups[1].Value
        }
    }
}

$sortedKeys = @($keys) | Sort-Object
Write-Host ("Visible/localized string keys: {0}" -f $sortedKeys.Count)

foreach ($locale in $locales) {
    $file = Join-Path $localeRoot ($locale + ".lua")
    $pairs = Read-LocalePairs $file
    $runtimePairs = Read-RuntimeLocalePairs $runtimeLocalePath $locale
    foreach ($key in $runtimePairs.Keys) { $pairs[$key] = $runtimePairs[$key] }
    $auditPairs = Read-RuntimeLocalePairs $auditLocalePath $locale
    foreach ($key in $auditPairs.Keys) { $pairs[$key] = $auditPairs[$key] }
    if ($englishLocales.ContainsKey($locale)) {
        foreach ($key in $sortedKeys) {
            if (-not $pairs.ContainsKey($key)) { $pairs[$key] = $key }
        }
    }
    $missing = @($sortedKeys | Where-Object { -not $pairs.ContainsKey($_) })
    $identical = @($sortedKeys | Where-Object { $pairs.ContainsKey($_) -and $pairs[$_] -ceq $_ })

    Write-Host ("{0}: entries={1} missing={2} identical={3}" -f $locale, $pairs.Count, $missing.Count, $identical.Count)
    if ($Examples -gt 0 -and $missing.Count -gt 0) {
        $sample = $missing | Select-Object -First $Examples
        Write-Host ("  missing examples: {0}" -f ($sample -join " | "))
    }
}

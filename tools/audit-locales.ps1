param(
    [string]$AddonRoot = "MidnightSimpleUnitFrames",
    [int]$Examples = 12
)

$ErrorActionPreference = "Stop"

$locales = @(
    "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"
)

$menuRoot = Join-Path $AddonRoot "Menu2"
$localeRoot = Join-Path $AddonRoot "Locales"

function Add-Key {
    param([System.Collections.Generic.HashSet[string]]$Set, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    $Value = ConvertFrom-LuaStringLiteral $Value
    if ($Value -match '^MSUF2_') { return }
    if ($Value -match '^[\s0-9%.,:;+\-*/\\|<>=~_()]+$') { return }
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
    '\b(?:label|text|title)\s*=\s*"((?:[^"\\]|\\.)*)"',
    '\bM\.Tr\s*\(\s*"((?:[^"\\]|\\.)*)"',
    '\bM\.Format\s*\(\s*"((?:[^"\\]|\\.)*)"'
)

Get-ChildItem -LiteralPath $menuRoot -Recurse -Filter "*.lua" | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            Add-Key $keys $match.Groups[1].Value
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
Write-Host ("Menu2 visible string keys: {0}" -f $sortedKeys.Count)

foreach ($locale in $locales) {
    $file = Join-Path $localeRoot ($locale + ".lua")
    $pairs = Read-LocalePairs $file
    $missing = @($sortedKeys | Where-Object { -not $pairs.ContainsKey($_) })
    $identical = @($sortedKeys | Where-Object { $pairs.ContainsKey($_) -and $pairs[$_] -eq $_ })

    Write-Host ("{0}: entries={1} missing={2} identical={3}" -f $locale, $pairs.Count, $missing.Count, $identical.Count)
    if ($Examples -gt 0 -and $missing.Count -gt 0) {
        $sample = $missing | Select-Object -First $Examples
        Write-Host ("  missing examples: {0}" -f ($sample -join " | "))
    }
}

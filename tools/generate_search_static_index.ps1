param(
    [switch]$Check
)

# Regenerates the baked Menu2 search index, or verifies that the committed file is
# current without writing (CI gate mode).
#
#   powershell -ExecutionPolicy Bypass -File tools/generate_search_static_index.ps1
#   powershell -ExecutionPolicy Bypass -File tools/generate_search_static_index.ps1 -Check

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (git rev-parse --show-toplevel).Trim()
if (-not $repo) { throw "Repository root was not found." }
Set-Location $repo

$lua = Get-Command lua -ErrorAction Stop
$output = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
$projector = ".github/scripts/search_static_index_project.lua"

# The projector builds every Menu2 page through the real crosswalk harness, which
# expects a deterministic English context just like the Assistant schema generator.
$previous = @{
    Class = $env:MSUF_TEST_CLASS_TOKEN
    Spec = $env:MSUF_TEST_SPEC_INDEX
    Locale = $env:MSUF_TEST_LOCALE
}
$env:MSUF_TEST_CLASS_TOKEN = "MAGE"
$env:MSUF_TEST_SPEC_INDEX = "1"
$env:MSUF_TEST_LOCALE = "enUS"

try {
    if ($Check) {
        if (-not (Test-Path -LiteralPath $output)) {
            throw "Search static index is missing. Run tools/generate_search_static_index.ps1."
        }
        $generated = & $lua.Source $projector --stdout
        if ($LASTEXITCODE -ne 0) { throw "Search static index projection failed." }
        $generatedText = ($generated -join "`n") + "`n"
        $committedText = [System.IO.File]::ReadAllText((Resolve-Path $output))
        # The projector emits LF; the working tree may hold CRLF after an editor save.
        $normalizedCommitted = $committedText.Replace("`r`n", "`n")
        $normalizedGenerated = $generatedText.Replace("`r`n", "`n")
        if ($normalizedCommitted -ne $normalizedGenerated) {
            throw "Search static index is stale. Run tools/generate_search_static_index.ps1 and commit the result."
        }
        Write-Host "search static index: up to date"
    } else {
        & $lua.Source $projector
        if ($LASTEXITCODE -ne 0) { throw "Search static index generation failed." }
    }
} finally {
    $env:MSUF_TEST_CLASS_TOKEN = $previous.Class
    $env:MSUF_TEST_SPEC_INDEX = $previous.Spec
    $env:MSUF_TEST_LOCALE = $previous.Locale
}

Set-StrictMode -Version Latest

# Shared rules for the Classic gate, the Classic release packager and the
# Classic release-line assertion. Every function here replaces code that used to
# exist once per script; the messages are the ones those scripts already threw,
# so a caller can adopt a function without changing what a failure says.

function Import-MsufClientMatrix {
    <#
        .SYNOPSIS
        Reads tools/classic-client-matrix.tsv, the single list of supported clients.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = "",
        [string]$EmptyMessage = ""
    )
    if ([string]::IsNullOrEmpty($Label)) { $Label = $Path }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Client matrix is missing: $Label"
    }
    $rows = @(Import-Csv -LiteralPath $Path -Delimiter "`t")
    if (-not [string]::IsNullOrEmpty($EmptyMessage) -and $rows.Count -eq 0) {
        throw $EmptyMessage
    }
    return $rows
}

function Assert-MsufClientMatrix {
    <#
        .SYNOPSIS
        The gate's full row validation for the client matrix.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Matrix,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $expectedColumns = @("Suffix", "Interfaces", "ClientToken", "ProjectGlobal", "GameType", "MirrorBranch", "CurseForgeVersions", "IsClassic")
    $actualColumns = @($Matrix[0].PSObject.Properties | ForEach-Object { $_.Name })
    if (($actualColumns -join "`t") -cne ($expectedColumns -join "`t")) {
        throw "Client matrix columns must be exactly: $($expectedColumns -join ', ')"
    }
    $suffixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($client in $Matrix) {
        if ($client.Suffix -cnotmatch '^[A-Z][A-Za-z0-9]*$' -or -not $suffixes.Add($client.Suffix)) {
            throw "Client matrix suffix is malformed or duplicated: '$($client.Suffix)'"
        }
        if ($client.IsClassic -cne "true" -and $client.IsClassic -cne "false") {
            throw "Client matrix IsClassic must be true or false: $($client.Suffix)"
        }
        [void](ConvertTo-MsufInterfaceSet -Value $client.Interfaces -Label "$Label $($client.Suffix)")
        if (($client.IsClassic -ceq "true") -ne ($client.ClientToken -cne "")) {
            throw "Client matrix $($client.Suffix): Classic clients need an X-MSUF-Client token and Mainline must not declare one"
        }
        if ($client.ProjectGlobal -cnotmatch '^WOW_PROJECT_[A-Z_]+$' -or $client.GameType -cnotmatch '^[a-z]+$' -or
            $client.MirrorBranch -cnotmatch '^upstream/[a-z0-9_]+$' -or [string]::IsNullOrWhiteSpace($client.CurseForgeVersions)) {
            throw "Client matrix row is incomplete: $($client.Suffix)"
        }
    }
    $mainline = @($Matrix | Where-Object { $_.IsClassic -ceq "false" })
    if ($mainline.Count -ne 1 -or $mainline[0].Suffix -cne "Mainline") {
        throw "Client matrix must contain exactly one non-Classic client, named Mainline"
    }
}

function ConvertTo-MsufInterfaceSet {
    <#
        .SYNOPSIS
        Parses a comma separated interface list into a sorted int set.
        .DESCRIPTION
        Without -AllowRepeats a repeated interface is an error, which is what a
        TOC or matrix row has to satisfy. With -AllowRepeats the list is only
        normalized, which is what a pure set comparison needs.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [string]$Label = "",
        [switch]$AllowRepeats
    )
    $set = [Collections.Generic.SortedSet[int]]::new()
    foreach ($item in @($Value -split ',' | ForEach-Object { $_.Trim() })) {
        if ($item -notmatch '^[1-9][0-9]*$') {
            if ([string]::IsNullOrEmpty($Label)) { throw "Malformed interface list: '$Value'" }
            throw "$Label has a malformed interface list: '$Value'"
        }
        if (-not $set.Add([int]$item) -and -not $AllowRepeats) { throw "$Label repeats interface $item" }
    }
    return [int[]]@($set)
}

function Get-MsufInterfaceSetKey {
    <#
        .SYNOPSIS
        A comparable key for an interface list: sorted, unique, comma joined.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return ((ConvertTo-MsufInterfaceSet -Value $Value -AllowRepeats) -join ',')
}

function Get-MsufTocField {
    <#
        .SYNOPSIS
        Reads one '## <Name>:' field out of TOC content.
        .DESCRIPTION
        A Mainline TOC carries one Version line per game type condition, so
        -AllowConditioned joins every match with ' | ' instead of demanding one.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowConditioned
    )
    $fields = [regex]::Matches($Content, "(?m)^##\s+$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if ($AllowConditioned -and $fields.Count -ge 1) {
        return (@($fields | ForEach-Object { $_.Groups[1].Value.Trim() }) -join ' | ')
    }
    if ($fields.Count -ne 1) {
        throw "Expected exactly one '$Name' field in TOC content; found $($fields.Count)."
    }
    return $fields[0].Groups[1].Value.Trim()
}

function Get-MsufTocEntries {
    <#
        .SYNOPSIS
        The load entries of a TOC: every non-empty line that is not a comment.
    #>
    param([Parameter(Mandatory = $true)][string]$Path, [string]$TextLocale = "", [string]$GameType = "")
    # An unspecified locale or game type inventories the union, for packaging
    # and parity. A line may stack conditions, e.g.
    # "file.lua [AllowLoadTextLocale deDE] [ExcludeLoadGameType camelot]".
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        $selected = $true
        while ($entry -match '^(?<file>.+?)\s+\[(?<kind>AllowLoadTextLocale|AllowLoadGameType|ExcludeLoadGameType)\s+(?<values>[A-Za-z, ]+)\]$') {
            $file, $kind = $Matches['file'], $Matches['kind']
            $values = @($Matches['values'] -split ',' | ForEach-Object { $_.Trim() })
            if ($kind -eq 'AllowLoadTextLocale' -and $TextLocale -and $TextLocale -notin $values) { $selected = $false }
            if ($kind -eq 'AllowLoadGameType' -and $GameType -and $GameType -notin $values) { $selected = $false }
            if ($kind -eq 'ExcludeLoadGameType' -and $GameType -and $GameType -in $values) { $selected = $false }
            $entry = $file
        }
        if ($entry.Contains('[')) { throw "Unsupported TOC load condition: $entry" }
        if ($selected) { $entry }
    }
}

function Get-MsufLoadGraph {
    <#
        .SYNOPSIS
        The one TOC/XML load-graph walker.
        .DESCRIPTION
        Walks a TOC or an XML manifest and returns every file the client would
        load, in load order, split into LuaPaths, XmlPaths and AllPaths.

        XML comments never reach the walk: only Script and Include elements are
        followed, so a commented-out entry is not a load.

        -Duplicates Skip visits a path once (a manifest included twice
        contributes once), which is what a load inventory needs.
        -Duplicates Repeat emits every occurrence and fails on an include cycle,
        which is what a load-order comparison needs.
        -RequireFiles fails when a TOC entry or an XML reference names a file
        that does not exist. Every condition stacked on a TOC line is read, so a
        line such as "x.lua [AllowLoadTextLocale enUS] [ExcludeLoadGameType
        camelot]" is a load of x.lua like any other.
        -VisitedXml shares the XML dedup set across calls, so a manifest that
        several TOCs include is walked once.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Skip', 'Repeat')][string]$Duplicates = 'Skip',
        [switch]$RequireFiles,
        [Collections.Generic.HashSet[string]]$VisitedXml = $null,
        [string]$TextLocale = "",
        [string]$GameType = ""
    )

    $luaPaths = [Collections.Generic.List[string]]::new()
    $xmlPaths = [Collections.Generic.List[string]]::new()
    $allPaths = [Collections.Generic.List[string]]::new()
    # Assigned as statements, never as the value of an if expression: PowerShell
    # unrolls an enumerable that leaves a block, and an empty set unrolls to $null.
    $xmlVisited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $VisitedXml) { $xmlVisited = $VisitedXml }
    $otherVisited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $active = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    function Add-MsufLoadGraphEntry {
        param([Parameter(Mandatory = $true)][string]$Current)

        # TOC and XML references use backslashes; on a Unix runner .NET keeps a
        # backslash as part of the name, so every path is normalized to the
        # platform separator before it is compared or stored.
        $full = [IO.Path]::GetFullPath($Current.Replace([char]92, [IO.Path]::DirectorySeparatorChar))
        $isXml = [IO.Path]::GetExtension($full) -ieq ".xml"
        if ($Duplicates -ceq 'Skip') {
            $visited = $otherVisited
            if ($isXml) { $visited = $xmlVisited }
            if (-not $visited.Add($full)) { return }
        } elseif ($isXml) {
            if (-not $active.Add($full)) { throw "XML include cycle detected at $full" }
        }
        $allPaths.Add($full)
        if ($isXml) {
            $xmlPaths.Add($full)
        } elseif ([IO.Path]::GetExtension($full) -ieq ".lua") {
            $luaPaths.Add($full)
        }
        if (-not $isXml) { return }

        [xml]$document = Get-Content -LiteralPath $full -Raw
        foreach ($node in $document.SelectNodes("//*[local-name()='Script' or local-name()='Include']")) {
            $reference = $node.GetAttribute("file")
            if ([string]::IsNullOrWhiteSpace($reference)) { continue }
            $child = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference.Replace([char]92, [IO.Path]::DirectorySeparatorChar)))
            if ($RequireFiles -and -not (Test-Path -LiteralPath $child -PathType Leaf)) {
                throw "Missing XML manifest reference: $full -> $reference"
            }
            Add-MsufLoadGraphEntry -Current $child
        }
        if ($Duplicates -cne 'Skip') { [void]$active.Remove($full) }
    }

    $entryFull = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($entryFull) -ieq ".toc") {
        $parent = Split-Path -Parent $entryFull
        foreach ($entry in (Get-MsufTocEntries -Path $entryFull -TextLocale $TextLocale -GameType $GameType)) {
            $child = Join-Path $parent $entry.Trim().Replace([char]92, [IO.Path]::DirectorySeparatorChar)
            if ($RequireFiles -and -not (Test-Path -LiteralPath $child -PathType Leaf)) {
                throw "Missing TOC entry: $entryFull -> $($entry.Trim())"
            }
            Add-MsufLoadGraphEntry -Current $child
        }
    } else {
        Add-MsufLoadGraphEntry -Current $entryFull
    }

    return [pscustomobject]@{
        LuaPaths = [string[]]@($luaPaths)
        XmlPaths = [string[]]@($xmlPaths)
        AllPaths = [string[]]@($allPaths)
    }
}

function Invoke-MsufGit {
    <#
        .SYNOPSIS
        Runs git and returns its exit code and output lines instead of throwing.
        .DESCRIPTION
        PowerShell 5.1 turns a native command's stderr into a terminating error
        under $ErrorActionPreference = "Stop"; every caller here reports a failed
        git call with its own message, so the call runs with "Continue".
    #>
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $exitCode = 0
    try {
        $output = @(& git @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Lines = [string[]]@($output) }
}

function Get-MsufVersionableFiles {
    <#
        .SYNOPSIS
        The files git versions below the given folders, as repository-relative
        forward-slash paths in ordinal order.
        .DESCRIPTION
        Tracked files plus untracked files that no ignore rule excludes, and only
        those that exist on disk. Scans read this list instead of walking the
        folders, so ignored local leftovers (luac.out, local scripts, scratch
        copies) never make a local result differ from CI, while a new file is
        checked before it is staged. -Extension keeps only the listed extensions.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Folders,
        [string[]]$Extension = @()
    )
    $listed = Invoke-MsufGit -Arguments (@("-C", $Root, "-c", "core.quotepath=off", "ls-files", "--cached", "--others", "--exclude-standard", "--") + $Folders)
    if ($listed.ExitCode -ne 0) {
        throw "Unable to list the versionable files below $($Folders -join ', '): $($listed.Lines -join ', ')"
    }
    $paths = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $listed.Lines) {
        $relative = $line.Replace([char]92, [char]47)
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if ($Extension.Count -gt 0 -and -not ($Extension -contains [IO.Path]::GetExtension($relative).ToLowerInvariant())) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) { continue }
        [void]$paths.Add($relative)
    }
    return [string[]]@($paths)
}

function Import-MsufAddonTombstones {
    <#
        .SYNOPSIS
        Reads tools/classic-addon-tombstones.txt: the Retail addons this tree
        retired and the Retail files of the shipped addons that retired with them.
        .DESCRIPTION
        A line with one field names a retired Retail addon folder. A line
        "<addon><TAB><path>" names a file below a shipped addon folder that
        retired with that addon. Blank lines and lines that start with '#' are
        comments. The same rules are implemented for Python in
        .github/scripts/classic_tombstones.py; keep the two in step.
        Returns Addons and Paths, each in manifest order.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ShippedAddons
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Addon tombstone manifest is missing: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Addon tombstone manifest starts with a byte order mark: $Path"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $shipped = [Collections.Generic.HashSet[string]]::new([string[]]$ShippedAddons, [StringComparer]::OrdinalIgnoreCase)
    $addons = [Collections.Generic.List[string]]::new()
    $paths = [Collections.Generic.List[string]]::new()
    $pathAddons = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lineNumber = 0
    foreach ($line in ($text -split "`r?`n")) {
        $lineNumber++
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        $where = "Addon tombstone manifest line ${lineNumber}"
        $fields = $line.Split([char]9)
        if ($fields.Count -gt 2 -or @($fields | Where-Object { $_.Length -eq 0 -or $_ -cne $_.Trim() }).Count -gt 0) {
            throw "$where must be '<addon>' or '<addon><TAB><path>' without surrounding blanks: '$line'"
        }
        $addon = $fields[0]
        if ($addon -cnotmatch '^[A-Za-z0-9_]+$') {
            throw "$where names a malformed addon folder: '$addon'"
        }
        if ($shipped.Contains($addon)) {
            throw "$where retires a shipped addon: $addon"
        }
        if ($fields.Count -eq 1) {
            if (-not $seen.Add("addon`t" + $addon)) { throw "$where repeats the addon $addon" }
            $addons.Add($addon)
            continue
        }
        $relative = $fields[1]
        $under = @($ShippedAddons | Where-Object { $relative.StartsWith($_ + '/', [StringComparison]::Ordinal) })
        if ($relative.Contains([char]92) -or $relative.EndsWith('/') -or $relative.Contains('//') -or
            $relative -match '(^|/)[.][.]?(?:/|$)' -or $relative.IndexOfAny([char[]](0..31)) -ge 0 -or $under.Count -eq 0) {
            throw "$where names a path that is not a normalized file path below a shipped addon folder: '$relative'"
        }
        if (-not $seen.Add("path`t" + $relative)) { throw "$where repeats the path $relative" }
        $paths.Add($relative)
        $pathAddons.Add($addon)
    }
    foreach ($addon in $pathAddons) {
        if (-not $addons.Contains($addon)) {
            throw "Addon tombstone manifest ties a path to $addon, which no addon line retires"
        }
    }
    return [pscustomobject]@{
        Addons = [string[]]$addons.ToArray()
        Paths = [string[]]$paths.ToArray()
    }
}

function Assert-MsufAddonTombstones {
    <#
        .SYNOPSIS
        Proves that the tree honours its addon tombstones, from git's view.
        .DESCRIPTION
        A retired addon folder may still exist on a Windows checkout after
        `git rm` (empty, or holding ignored files only): that is fine. It fails
        when git tracks anything below it or when it holds a TOC, which WoW would
        load from a linked AddOns folder. A retired path fails when git tracks it
        or when a shipped TOC or XML manifest loads it (-LoadedPaths: full paths
        of every file the shipped TOCs reach).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Tombstones,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$LoadedPaths
    )
    foreach ($addon in $Tombstones.Addons) {
        $tracked = Invoke-MsufGit -Arguments @("-C", $Root, "ls-files", "--", $addon)
        if ($tracked.ExitCode -ne 0) { throw "Unable to list tracked files of the retired addon ${addon}: $($tracked.Lines -join ', ')" }
        if ($tracked.Lines.Count -gt 0) {
            throw "Retired addon $addon still has tracked files; remove them with git rm: $(@($tracked.Lines | Select-Object -First 5) -join ', ')"
        }
        $folder = Join-Path $Root $addon
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $tocs = @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force -Filter "*.toc")
            if ($tocs.Count -gt 0) {
                throw "Retired addon folder $addon still holds a TOC that WoW would load; delete the folder: $(@($tocs | ForEach-Object { $_.FullName }) -join ', ')"
            }
        }
    }
    $loaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($loadedPath in $LoadedPaths) { [void]$loaded.Add([IO.Path]::GetFullPath($loadedPath)) }
    foreach ($relative in $Tombstones.Paths) {
        $tracked = Invoke-MsufGit -Arguments @("-C", $Root, "ls-files", "--", $relative)
        if ($tracked.ExitCode -ne 0) { throw "Unable to check the retired path ${relative}: $($tracked.Lines -join ', ')" }
        if ($tracked.Lines.Count -gt 0) {
            throw "Retired Retail path is tracked again; remove it with git rm or drop its tombstone line: $relative"
        }
        if ($loaded.Contains([IO.Path]::GetFullPath((Join-Path $Root $relative)))) {
            throw "Retired Retail path is still loaded by a TOC or XML manifest: $relative"
        }
    }
}

function Assert-MsufUnloadedAddonLua {
    <#
        .SYNOPSIS
        Every versioned addon Lua file is loaded by a shipped TOC, unless
        tools/classic-unloaded-addon-lua.tsv lists it with a kind and a reason.
        .DESCRIPTION
        The manifest starts with the header Path<TAB>Kind<TAB>Reason and lists
        one row per file in ordinal path order. Kinds:
          mirror    an unchanged Retail mirror that Retail itself never loads;
                    it may be neither Classic-owned nor overridden
          retained  a Classic-owned file the owner keeps unloaded on purpose;
                    it must be Classic-owned, never an override, and its reason
                    must cite the owner decision
        Any other unloaded file fails (an owned or overridden file nobody listed
        is dead weight), and so does a row whose file a shipped TOC now loads.
        -VersionableLua and -OwnedPaths/-OverridePaths/-TrackedPaths are
        repository-relative forward-slash paths; -LoadedPaths are full paths.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$VersionableLua,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$LoadedPaths,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OwnedPaths,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OverridePaths,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$TrackedPaths
    )
    $label = [IO.Path]::GetFileName($ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Unloaded addon Lua manifest is missing: $ManifestPath" }
    $lines = [string[]][IO.File]::ReadAllLines($ManifestPath)
    if ($lines.Count -eq 0 -or $lines[0] -cne "Path`tKind`tReason") {
        throw "$label must start with the header Path<TAB>Kind<TAB>Reason"
    }
    $owned = [Collections.Generic.HashSet[string]]::new([string[]]$OwnedPaths, [StringComparer]::Ordinal)
    $overridden = [Collections.Generic.HashSet[string]]::new([string[]]$OverridePaths, [StringComparer]::Ordinal)
    $tracked = [Collections.Generic.HashSet[string]]::new([string[]]$TrackedPaths, [StringComparer]::Ordinal)
    $loaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($loadedPath in $LoadedPaths) { [void]$loaded.Add([IO.Path]::GetFullPath($loadedPath)) }
    $listed = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $previous = $null
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $fields = $lines[$index].Split([char]9)
        if ($fields.Count -ne 3 -or @($fields | Where-Object { $_.Length -eq 0 -or $_ -cne $_.Trim() }).Count -gt 0) {
            throw "$label rows must be Path<TAB>Kind<TAB>Reason without empty or padded fields: $($lines[$index])"
        }
        $path, $kind, $reason = $fields
        if (-not $path.EndsWith(".lua", [StringComparison]::Ordinal) -or -not $tracked.Contains($path)) {
            throw "$label must name tracked addon Lua files: $path"
        }
        if ($listed.ContainsKey($path)) { throw "$label repeats $path" }
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous, $path) -ge 0) {
            throw "$label must use ordinal path sorting: $path"
        }
        $previous = $path
        if ($overridden.Contains($path)) {
            throw "An overridden file that no TOC loads is a dead Classic edit and cannot be listed in ${label}; restore the Retail bytes and drop its override row, or load it: $path"
        }
        switch -CaseSensitive ($kind) {
            "mirror" {
                if ($owned.Contains($path)) {
                    throw "$label lists the Classic-owned $path as a Retail mirror; a deliberately kept owned file is a 'retained' row"
                }
            }
            "retained" {
                if (-not $owned.Contains($path)) {
                    throw "$label retains $path, which is not Classic-owned; only a Classic-owned file can be retained"
                }
                if ($reason -notmatch '(?i)\bowner decision\b') {
                    throw "$label retains $path without citing the owner decision in its reason"
                }
            }
            default { throw "$label row has an unknown kind '$kind' (mirror or retained): $path" }
        }
        if ($loaded.Contains([IO.Path]::GetFullPath((Join-Path $Root $path)))) {
            throw "Stale $label row: a shipped TOC loads $path; remove the row"
        }
        $listed.Add($path, $kind)
    }
    $unreached = [string[]]@($VersionableLua | Where-Object {
        -not $listed.ContainsKey($_) -and -not $loaded.Contains([IO.Path]::GetFullPath((Join-Path $Root $_)))
    })
    if ($unreached.Count -gt 0) {
        throw "Addon Lua that no shipped TOC loads would ship as dead payload: $($unreached -join ', '). Load it from a TOC or XML manifest, delete it, or list it in $label (an unchanged Retail mirror Retail never loads as 'mirror', a Classic-owned file the owner keeps on purpose as 'retained')"
    }
    return [pscustomobject]@{
        Mirrors = @($listed.Values | Where-Object { $_ -ceq "mirror" }).Count
        Retained = @($listed.Values | Where-Object { $_ -ceq "retained" }).Count
    }
}

function Test-MsufToolingLeaf {
    <#
        .SYNOPSIS
        True for a file name that looks like tooling (test, tests, smoke, spec,
        perfy, graphify as a name token).
    #>
    param([Parameter(Mandatory = $true)][string]$Leaf)
    return $Leaf -match '(?i)(?:^|[-_.])(?:test|tests|smoke|spec|perfy|graphify)(?:[-_.]|$)'
}

function Assert-MsufStagedLoadGraph {
    <#
        .SYNOPSIS
        Every Lua and XML file a staged TOC reaches must exist in the stage.
        .DESCRIPTION
        Walks every TOC below -StageRoot with Get-MsufLoadGraph -RequireFiles, so
        a TOC line with several load conditions counts like any other and a file
        a staging rule removed fails the build instead of shipping a broken load
        graph. A Lua or XML file whose name looks like tooling ships only when
        the load graph reaches it. Returns the TOC count and the reached count.
    #>
    param([Parameter(Mandatory = $true)][string]$StageRoot)
    $stageFull = [IO.Path]::GetFullPath($StageRoot).TrimEnd([char]92, [char]47)
    $reached = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $visitedXml = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $tocs = @(Get-ChildItem -LiteralPath $stageFull -Filter '*.toc' -File -Recurse)
    foreach ($toc in $tocs) {
        try {
            $graph = Get-MsufLoadGraph -Path $toc.FullName -Duplicates Skip -RequireFiles -VisitedXml $visitedXml
        } catch {
            throw "Staged package load graph has missing files: $($_.Exception.Message.Replace($stageFull + [IO.Path]::DirectorySeparatorChar, ''))"
        }
        foreach ($path in $graph.AllPaths) {
            if ([IO.Path]::GetExtension($path) -match '(?i)^\.(?:lua|xml)$') { [void]$reached.Add($path) }
        }
    }
    $unreachedTooling = @(Get-ChildItem -LiteralPath $stageFull -File -Recurse | Where-Object {
        $_.Extension -match '(?i)^\.(?:lua|xml)$' -and (Test-MsufToolingLeaf -Leaf $_.Name) -and
        -not $reached.Contains([IO.Path]::GetFullPath($_.FullName))
    } | ForEach-Object { $_.FullName.Substring($stageFull.Length + 1).Replace([char]92, [char]47) })
    if ($unreachedTooling.Count -gt 0) {
        throw "Staged Lua/XML files are named like tooling and no TOC loads them; remove them from the addon tree or load them: $($unreachedTooling -join ', ')"
    }
    return [pscustomobject]@{ Tocs = $tocs.Count; Reached = $reached.Count }
}

Export-ModuleMember -Function Import-MsufClientMatrix, Assert-MsufClientMatrix, ConvertTo-MsufInterfaceSet,
    Get-MsufInterfaceSetKey, Get-MsufTocField, Get-MsufTocEntries, Get-MsufLoadGraph, Invoke-MsufGit,
    Get-MsufVersionableFiles, Import-MsufAddonTombstones, Assert-MsufAddonTombstones, Test-MsufToolingLeaf,
    Assert-MsufStagedLoadGraph, Assert-MsufUnloadedAddonLua

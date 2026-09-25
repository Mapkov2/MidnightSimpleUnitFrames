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
        -RequireFiles fails when a referenced file does not exist.
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

        $full = [IO.Path]::GetFullPath($Current)
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
            $child = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $full) $reference))
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
            Add-MsufLoadGraphEntry -Current (Join-Path $parent $entry.Trim())
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

Export-ModuleMember -Function Import-MsufClientMatrix, Assert-MsufClientMatrix, ConvertTo-MsufInterfaceSet,
    Get-MsufInterfaceSetKey, Get-MsufTocField, Get-MsufTocEntries, Get-MsufLoadGraph

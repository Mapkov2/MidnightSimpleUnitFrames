[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tag
)

# The one place the Classic release channel is derived. Everything that
# publishes a Classic build - the release workflow, the packager and the
# CurseForge metadata correction - takes version, display name and release type
# from here, so a beta can never reach a store as an alpha because one caller
# spelled the channel itself.
#
# Accepted forms, both naming the same release:
#   classic-v<base>-alpha<number>  classic-v<base>-beta<number>   (release tag)
#   <base>-alpha<number>           <base>-beta<number>            (VERSION line)
#
# The authored base is never int-cast: 6.05 and 6.5 are different releases.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $Tag.Trim() -replace '^refs/tags/', ''
if ($candidate -notmatch '^(?:classic-v)?(?<base>(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))*)-(?<channel>alpha|beta)(?<number>0|[1-9][0-9]*)$') {
    throw "Classic release must use 'classic-v<version>-alpha<number>' or 'classic-v<version>-beta<number>' without leading zeros. Got: $Tag"
}

$base = $Matches["base"]
$channel = $Matches["channel"]
$number = [int]$Matches["number"]
if ($channel -ceq "alpha") {
    $displayName = "MSUF_${base}A$number"
} else {
    $displayName = "MSUF_${base} Beta $number"
}

return [pscustomobject][ordered]@{
    Base        = $base
    Channel     = $channel
    Number      = $number
    Version     = "$base-$channel$number"
    DisplayName = $displayName
    ReleaseType = $channel
}

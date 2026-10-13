[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tag
)

# The one place the MSUF release channel is derived. Everything that
# publishes an MSUF build - the release workflow, the packager and the
# CurseForge metadata correction - takes version, display name and release type
# from here, so a beta can never reach a store as an alpha because one caller
# spelled the channel itself.
#
# Accepted forms; v<version> is canonical for the full Main release:
#   v<base>-alpha<number>          v<base>-beta<number>
#   v<base>                       (stable Main release)
# Historical Classic tags and raw VERSION values remain accepted:
#   classic-v<base>-alpha<number>  classic-v<base>-beta<number>   (release tag)
#   <base>-alpha<number>           <base>-beta<number>            (VERSION line)
#   classic-v<base>                <base>                         (stable release)
#
# The authored base is never int-cast: 6.05 and 6.5 are different releases.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $Tag.Trim() -replace '^refs/tags/', ''
# A stable release (6.50) names only its version; its two-digit minor may end
# in zero, so the base keeps every authored digit.
if ($candidate -match '^(?:classic-v|v)?(?<base>(?:0|[1-9][0-9]*)\.[0-9]+)$') {
    $base = $Matches["base"]
    return [pscustomobject][ordered]@{
        Base        = $base
        Channel     = "release"
        Number      = 0
        Version     = $base
        DisplayName = "MSUF_$base"
        ReleaseType = "release"
    }
}
if ($candidate -notmatch '^(?:classic-v|v)?(?<base>(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))*)-(?<channel>alpha|beta)(?<number>0|[1-9][0-9]*)$') {
    throw "MSUF release must use 'v<version>', 'v<version>-alpha<number>' or 'v<version>-beta<number>' (historical classic-v tags are also accepted) without leading zeros. Got: $Tag"
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

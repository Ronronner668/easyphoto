param(
    [switch]$Enable,
    [switch]$Disable,
    [string]$ManifestPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-tools.ps1')
if ($Enable -eq $Disable) { throw 'Specify exactly one of -Enable or -Disable' }
if (-not $ManifestPath) {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'entry\src\main\module.json5'
}
$mode = if ($Enable) { 'enable' } else { 'disable' }
$result = Invoke-ProjectNativeProcess -FilePath (Get-ProjectNodePath) -ArgumentList @((Join-Path $PSScriptRoot 'project-config.cjs'), 'write-probes', $ManifestPath, $mode)
if ($result.ExitCode -ne 0) { throw 'Write probe configuration failed; the original configuration was preserved' }
$result.StandardOutput.TrimEnd()

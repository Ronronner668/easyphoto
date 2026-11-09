param(
    [string]$DevEcoHome = 'E:\DevEcoStudio\DevEco Studio',
    [string]$LogPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-tools.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$savedPath = $env:Path
$savedJava = $env:JAVA_HOME
$savedSdk = $env:DEVECO_SDK_HOME
$buildExitCode = 1
try {
    $env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
    $nodePath = Join-Path $DevEcoHome 'tools\node\node.exe'
    $hvigorPath = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
    foreach ($toolPath in @($nodePath, $hvigorPath, (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
        if (-not (Test-Path -LiteralPath $toolPath)) { throw "Missing tool: $toolPath" }
    }
    $env:Path = (Join-Path $DevEcoHome 'tools\node') + ';' + (Join-Path $DevEcoHome 'tools\ohpm\bin') + ';' + (Join-Path $env:JAVA_HOME 'bin') + ';' + $savedPath
    $buildArguments = @($hvigorPath, '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon')
    $result = Invoke-ProjectNativeProcess -FilePath $nodePath -ArgumentList $buildArguments -WorkingDirectory $projectRoot
    $combined = $result.StandardOutput + "`n" + $result.StandardError + "`nHvigor process exit code: " + $result.ExitCode
    $combined = [regex]::Replace($combined, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    if ($LogPath) {
        if (-not [System.IO.Path]::IsPathRooted($LogPath)) { $LogPath = Join-Path $projectRoot $LogPath }
        [System.IO.File]::WriteAllText($LogPath, $combined, (New-Object System.Text.UTF8Encoding($false)))
    }
    $combined -split '\r?\n'
    $buildExitCode = $result.ExitCode
} finally {
    $env:Path = $savedPath
    $env:JAVA_HOME = $savedJava
    $env:DEVECO_SDK_HOME = $savedSdk
}
exit $buildExitCode

function Get-ProjectNodePath {
    $studioPath = if ($env:DEVECO_STUDIO_HOME) { $env:DEVECO_STUDIO_HOME } else { 'E:\DevEcoStudio\DevEco Studio' }
    $nodePath = Join-Path $studioPath 'tools\node\node.exe'
    if (-not (Test-Path -LiteralPath $nodePath)) { throw "Missing bundled Node.js: $nodePath" }
    return $nodePath
}

function Read-ProjectJson5 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $result = Invoke-ProjectNativeProcess -FilePath (Get-ProjectNodePath) -ArgumentList @((Join-Path $PSScriptRoot 'project-config.cjs'), 'read', $Path)
    if ($result.ExitCode -ne 0) { throw "JSON5 parsing failed: $Path" }
    return ($result.StandardOutput | ConvertFrom-Json)
}

function ConvertTo-ProjectNativeArgument {
    param([string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-ProjectNativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = (Split-Path -Parent $PSScriptRoot)
    )
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FilePath
    $start.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-ProjectNativeArgument $_ }) -join ' ')
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start the bundled tool' }
        # Drain both pipes concurrently; SDK warnings on stderr are data, not PowerShell errors.
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $outputTask.GetAwaiter().GetResult()
            StandardError = $errorTask.GetAwaiter().GetResult()
        }
    } finally { $process.Dispose() }
}

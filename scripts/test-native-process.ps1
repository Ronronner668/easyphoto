$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-tools.ps1')
$node = Get-ProjectNodePath
$result = Invoke-ProjectNativeProcess -FilePath $node -ArgumentList @('-e', 'process.stdout.write("out"); process.stderr.write("warning");')
if ($result.ExitCode -ne 0 -or $result.StandardOutput -ne 'out' -or $result.StandardError -ne 'warning') { throw 'stderr warning handling failed' }
'PASS native stderr is captured without turning warnings into terminating PowerShell errors'
$result = Invoke-ProjectNativeProcess -FilePath $node -ArgumentList @('-e', 'process.stderr.write("failed"); process.exit(7)')
if ($result.ExitCode -ne 7 -or $result.StandardError -ne 'failed') { throw 'native failure exit code lost' }
'PASS real native failure exit code is preserved'
$argument = 'a path with spaces\"quoted" and trailing\'
$result = Invoke-ProjectNativeProcess -FilePath $node -ArgumentList @('-e', 'process.stdout.write(JSON.stringify(process.argv[1]));', $argument)
if ($result.ExitCode -ne 0 -or ($result.StandardOutput | ConvertFrom-Json) -ne $argument) { throw 'Windows native argument quoting failed' }
'PASS native argument quoting preserves spaces, quotes and trailing backslashes'

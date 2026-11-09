$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-tools.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalPath = Join-Path $projectRoot 'entry\src\main\module.json5'
$testDirectory = Join-Path $projectRoot '.test'
New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
$fixturePath = Join-Path $testDirectory 'write-toggle.json5'
$originalHash = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash
Copy-Item -LiteralPath $originalPath -Destination $fixturePath
& (Join-Path $PSScriptRoot 'configure-write-probes.ps1') -Enable -ManifestPath $fixturePath | Out-Null
& (Join-Path $PSScriptRoot 'configure-write-probes.ps1') -Enable -ManifestPath $fixturePath | Out-Null
$fixture = Read-ProjectJson5 $fixturePath
if (@($fixture.module.requestPermissions | Where-Object name -eq 'ohos.permission.WRITE_IMAGEVIDEO').Count -ne 1) {
    throw 'Write permission activation is not idempotent'
}
if ($fixture.module.requestPermissions[-1].reason -ne '$string:gallery_write_reason') { throw 'Literal resource reference changed' }
'PASS write probe opt-in is idempotent and keeps the literal permission reason'
& (Join-Path $PSScriptRoot 'configure-write-probes.ps1') -Disable -ManifestPath $fixturePath | Out-Null
$fixture = Read-ProjectJson5 $fixturePath
if (@($fixture.module.requestPermissions | Where-Object name -eq 'ohos.permission.WRITE_IMAGEVIDEO').Count) { throw 'Write permission was not removed' }
$original = Read-ProjectJson5 $originalPath
$expectedCount = @($original.module.requestPermissions | Where-Object name -ne 'ohos.permission.WRITE_IMAGEVIDEO').Count
if ($fixture.module.requestPermissions.Count -ne $expectedCount -or $fixture.module.abilities[0].name -ne 'EntryAbility') { throw 'Unrelated configuration changed' }
'PASS write probe opt-in is reversible and preserves other permissions and abilities'
if ((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash -ne $originalHash) { throw 'Production manifest was modified by tests' }
'PASS configuration tests did not modify the production manifest'
$json5Path = Join-Path $testDirectory 'comments-unicode.json5'
$fixtureText = @'
// JSON5 syntax and UTF-8 fixture, not production configuration.
{
  module: {
    name: 'entry',
    note: 'UNICODE_VALUE',
    literal: 'https://example.invalid/a//b/*literal*/',
    requestPermissions: [
      { name: 'ohos.permission.READ_IMAGEVIDEO', reason: '$string:gallery_read_reason', },
      { name: 'ohos.permission.FILE_ACCESS_PERSIST', },
    ],
    abilities: [{ name: 'EntryAbility', }],
  },
}
'@
$unicodeValue = [string][char]0x4e2d + [char]0x6587
$fixtureText = $fixtureText.Replace('UNICODE_VALUE', $unicodeValue)
[System.IO.File]::WriteAllText($json5Path, ([string][char]0xfeff + $fixtureText), (New-Object System.Text.UTF8Encoding($false)))
$parsed = Read-ProjectJson5 $json5Path
if ($parsed.module.note -ne $unicodeValue -or $parsed.module.literal -ne 'https://example.invalid/a//b/*literal*/') { throw 'JSON5 Unicode or quoted comment markers corrupted' }
& (Join-Path $PSScriptRoot 'configure-write-probes.ps1') -Enable -ManifestPath $json5Path | Out-Null
$parsed = Read-ProjectJson5 $json5Path
if ($parsed.module.note -ne $unicodeValue -or $parsed.module.requestPermissions.Count -ne 3) { throw 'JSON5 toggle corrupted Unicode or permissions' }
'PASS full JSON5 comments, unquoted keys, single quotes, trailing commas, UTF-8 BOM and Unicode survive configuration'

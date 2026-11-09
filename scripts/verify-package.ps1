param(
    [string]$HapPath = '',
    [string[]]$ExpectedPermissions = @()
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-tools.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ExpectedPermissions.Count) {
    $sourceManifest = Read-ProjectJson5 (Join-Path $projectRoot 'entry\src\main\module.json5')
    $ExpectedPermissions = @($sourceManifest.module.requestPermissions | ForEach-Object { $_.name })
}
if (-not $HapPath) {
    $HapPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'entry\build\default\outputs\default\entry-default-unsigned.hap'
}
$packageArchive = [System.IO.Compression.ZipFile]::OpenRead($HapPath)
function Read-PackageText([string]$EntryName) {
    $packageEntry = $packageArchive.GetEntry($EntryName)
    if (-not $packageEntry) { throw "Missing package entry: $EntryName" }
    $packageReader = [System.IO.StreamReader]::new($packageEntry.Open())
    try { return $packageReader.ReadToEnd() } finally { $packageReader.Dispose() }
}
try {
    $manifest = Read-PackageText 'module.json' | ConvertFrom-Json
    if ($manifest.module.type -ne 'entry' -or $manifest.module.mainElement -ne 'EntryAbility') {
        throw 'Stage entry module metadata mismatch'
    }
    if ($manifest.app.bundleName -ne 'com.example.easyphoto') { throw 'Bundle name mismatch' }
    $declaredPermissions = @($manifest.module.requestPermissions | ForEach-Object { $_.name })
    $allowedPermissions = @('ohos.permission.READ_IMAGEVIDEO', 'ohos.permission.WRITE_IMAGEVIDEO', 'ohos.permission.MEDIA_LOCATION')
    if (@($declaredPermissions | Where-Object { $_ -notin $allowedPermissions }).Count) { throw 'Unexpected permission outside experiment scope' }
    if (@(Compare-Object -ReferenceObject $ExpectedPermissions -DifferenceObject $declaredPermissions).Count -gt 0) {
        throw 'Package permission declaration mismatch'
    }
    if (-not $packageArchive.GetEntry('ets/modules.abc')) { throw 'Missing compiled ArkTS bytecode' }
    if (-not $packageArchive.GetEntry('resources.index')) { throw 'Missing compiled resources' }
    $backup = Read-PackageText 'resources/base/profile/backup_config.json' | ConvertFrom-Json
    if ($backup.allowToBackupRestore -ne $false) { throw 'Experiment references must not migrate through system backup' }
    $pages = Read-PackageText 'resources/base/profile/main_pages.json' | ConvertFrom-Json
    $expectedPages = (Read-ProjectJson5 (Join-Path $projectRoot 'entry\src\main\resources\base\profile\main_pages.json')).src
    foreach ($expectedPage in $expectedPages) {
        if ($pages.src -notcontains $expectedPage) { throw "Missing route: $expectedPage" }
    }
    [ordered]@{
        scope = 'Host package structure checks only; no device runtime verification'
        result = 'PASS'
        bundle = $manifest.app.bundleName
        compileSdk = $manifest.app.compileSdkVersion
        minimumApi = $manifest.app.minAPIVersion
        targetApi = $manifest.app.targetAPIVersion
        routes = $pages.src
        declaredPermissions = $declaredPermissions
        systemBackupEnabled = $backup.allowToBackupRestore
        packageBytes = (Get-Item -LiteralPath $HapPath).Length
        sha256 = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash
        signing = 'Package payload inspected; signature validity and installation are separate checks'
    } | ConvertTo-Json -Depth 4
} finally { $packageArchive.Dispose() }

param(
    [Parameter(Mandatory = $true)]
    [string]$SignedHelperPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$helper = Get-Item -LiteralPath $SignedHelperPath
if ((Get-AuthenticodeSignature -LiteralPath $helper.FullName).Status -ne 'Valid') {
    throw 'Provide a signed LocalChat MSIX helper matching JaronAdmin.LocalChat and the configured publisher.'
}
$archive = [IO.Compression.ZipFile]::OpenRead($helper.FullName)
try {
    $entry = $archive.GetEntry('AppxManifest.xml')
    if (!$entry -or $entry.Length -gt 1048576) { throw 'Missing or oversized MSIX manifest' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    [xml]$expected = Get-Content -LiteralPath (Join-Path $repoRoot 'support/build/msix/content/AppxManifest.xml') -Raw
    if ($manifest.Package.Identity.Name -ne 'JaronAdmin.LocalChat' -or $manifest.Package.Identity.Publisher -ne $expected.Package.Identity.Publisher) {
        throw 'The signed helper does not belong to this LocalChat package and publisher.'
    }
} finally {
    $archive.Dispose()
}
$stageDir = Join-Path ([IO.Path]::GetTempPath()) ('localchat-inno-' + [guid]::NewGuid())
$payloadDir = Join-Path $stageDir 'payload'
$resultDir = Join-Path $repoRoot 'app/dist'
New-Item -ItemType Directory -Path $payloadDir, $resultDir -Force | Out-Null
Copy-Item -LiteralPath $helper.FullName -Destination (Join-Path $repoRoot 'app/windows/localchat_msix_helper.msix')

Push-Location (Join-Path $repoRoot 'app')
try {
    fvm flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    fvm flutter build windows
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    Copy-Item -Path 'build/windows/x64/runner/Release/*' -Destination $payloadDir -Recurse
    Copy-Item -LiteralPath 'assets/packaging/logo.ico' -Destination (Join-Path $payloadDir 'logo.ico')
    & iscc "/DPayloadDir=$payloadDir" "/DResultDir=$resultDir" (Join-Path $PSScriptRoot 'compile_windows_exe-inno.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
} finally {
    Pop-Location
}
Write-Output "LocalChat installer created in $resultDir. Staging retained at $stageDir."

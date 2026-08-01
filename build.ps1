[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = $PSScriptRoot
$packageJsonPath = Join-Path $repositoryRoot 'package.json'
$pluginJsonPath = Join-Path $repositoryRoot 'plugin.json'
$artifactRoot = Join-Path $repositoryRoot 'artifacts'
$pluginDirectoryName = 'vortex-launch-bridge'

if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
    throw "Package manifest not found: $packageJsonPath"
}
if (-not (Test-Path -LiteralPath $pluginJsonPath -PathType Leaf)) {
    throw "Plugin manifest not found: $pluginJsonPath"
}

$packageManifest = Get-Content -LiteralPath $packageJsonPath -Raw |
    ConvertFrom-Json
$pluginManifest = Get-Content -LiteralPath $pluginJsonPath -Raw |
    ConvertFrom-Json
$version = [string]$packageManifest.version

if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "package.json contains an invalid version: $version"
}
if ([string]$pluginManifest.version -ne $version) {
    throw (
        "Version mismatch: package.json is {0}, but plugin.json is {1}." -f
        $version,
        [string]$pluginManifest.version
    )
}
if ([string]$pluginManifest.name -ne $pluginDirectoryName) {
    throw (
        "Unexpected plugin ID in plugin.json: {0}" -f
        [string]$pluginManifest.name
    )
}

$corepack = Get-Command 'corepack' -ErrorAction SilentlyContinue
if (-not $corepack) {
    throw 'Corepack was not found on PATH. Install the Node version required by package.json.'
}

$previousCi = $env:CI
$env:CI = 'true'
Push-Location $repositoryRoot
try {
    & $corepack.Source pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed with exit code $LASTEXITCODE."
    }

    & $corepack.Source pnpm run build
    if ($LASTEXITCODE -ne 0) {
        throw "Production build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
    if ($null -eq $previousCi) {
        Remove-Item Env:CI -ErrorAction SilentlyContinue
    }
    else {
        $env:CI = $previousCi
    }
}

$requiredFiles = @(
    'plugin.json',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'backend\main.lua',
    'backend\util\process_shell.exe',
    'scripts\patch-vortex-dotnetprobe.ps1',
    '.millennium\Dist\index.js',
    '.millennium\Dist\webkit.js'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    $file = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
    if (-not $file -or $file.PSIsContainer -or $file.Length -eq 0) {
        throw "Runtime package is missing required file: $relativePath"
    }
}

$frontendBundle = Get-Item -LiteralPath (
    Join-Path $repositoryRoot '.millennium\Dist\index.js'
)
if ($frontendBundle.Length -lt 1024) {
    throw 'The compiled frontend is unexpectedly small.'
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

$stagingRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'VlbRuntimeBuild-' + [guid]::NewGuid().ToString('N')
)
$packageRoot = Join-Path $stagingRoot $pluginDirectoryName
$stagedArchive = Join-Path $stagingRoot (
    "VortexLaunchBridge-$version.zip"
)
$outputPath = Join-Path $artifactRoot (
    "VortexLaunchBridge-$version.zip"
)

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

try {
    foreach ($rootFile in @(
        'plugin.json',
        'README.md',
        'LICENSE',
        'CHANGELOG.md'
    )) {
        Copy-Item -LiteralPath (
            Join-Path $repositoryRoot $rootFile
        ) -Destination $packageRoot
    }

    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot 'backend'
    ) -Destination $packageRoot -Recurse

    $scriptsRoot = Join-Path $packageRoot 'scripts'
    New-Item -ItemType Directory -Path $scriptsRoot | Out-Null
    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot 'scripts\patch-vortex-dotnetprobe.ps1'
    ) -Destination $scriptsRoot

    $millenniumRoot = Join-Path $packageRoot '.millennium'
    New-Item -ItemType Directory -Path $millenniumRoot | Out-Null
    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot '.millennium\Dist'
    ) -Destination $millenniumRoot -Recurse

    $generatedAssets = Join-Path $repositoryRoot 'dist'
    if (Test-Path -LiteralPath $generatedAssets -PathType Container) {
        Copy-Item -LiteralPath $generatedAssets `
            -Destination $packageRoot `
            -Recurse
    }

    Compress-Archive -LiteralPath $packageRoot `
        -DestinationPath $stagedArchive `
        -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($stagedArchive)
    try {
        $archiveEntries = @(
            $archive.Entries |
                ForEach-Object { $_.FullName.Replace('\', '/') }
        )
        $requiredArchiveEntries = @(
            "$pluginDirectoryName/plugin.json",
            "$pluginDirectoryName/backend/main.lua",
            "$pluginDirectoryName/backend/util/process_shell.exe",
            "$pluginDirectoryName/scripts/patch-vortex-dotnetprobe.ps1",
            "$pluginDirectoryName/.millennium/Dist/index.js",
            "$pluginDirectoryName/.millennium/Dist/webkit.js"
        )

        foreach ($entry in $requiredArchiveEntries) {
            if ($archiveEntries -notcontains $entry) {
                throw "Generated archive is missing required file: $entry"
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    Move-Item -LiteralPath $stagedArchive -Destination $outputPath
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        $resolvedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()
        ).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        $stagingLeaf = [System.IO.Path]::GetFileName($resolvedStagingRoot)

        if (
            -not $resolvedStagingRoot.StartsWith(
                $resolvedTempRoot,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -or
            -not $stagingLeaf.StartsWith(
                'VlbRuntimeBuild-',
                [System.StringComparison]::Ordinal
            )
        ) {
            throw "Refusing to remove unexpected staging directory: $resolvedStagingRoot"
        }

        Remove-Item -LiteralPath $resolvedStagingRoot -Recurse -Force
    }
}

$artifact = Get-Item -LiteralPath $outputPath
$hash = Get-FileHash -LiteralPath $outputPath -Algorithm SHA256

[pscustomobject]@{
    Path = $artifact.FullName
    Version = $version
    SizeBytes = $artifact.Length
    SHA256 = $hash.Hash
}

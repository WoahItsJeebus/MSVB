[CmdletBinding()]
param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installerRoot = Join-Path $repositoryRoot 'installer'
$artifactRoot = Join-Path $repositoryRoot 'artifacts'
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $compiler) {
    throw 'The .NET Framework C# compiler was not found. Install .NET Framework 4.8 developer tools.'
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

$outputPath = Join-Path $artifactRoot 'VortexLaunchBridgeInstaller.exe'
$sourceFiles = @(
    (Join-Path $installerRoot 'AssemblyInfo.cs'),
    (Join-Path $installerRoot 'InstallerCore.cs'),
    (Join-Path $installerRoot 'InstallerServices.cs'),
    (Join-Path $installerRoot 'InstallerForm.cs'),
    (Join-Path $installerRoot 'Program.cs')
)
$references = @(
    'System.dll',
    'System.Core.dll',
    'System.Drawing.dll',
    'System.Windows.Forms.dll',
    'System.Net.Http.dll',
    'System.IO.Compression.dll',
    'System.IO.Compression.FileSystem.dll',
    'System.Web.Extensions.dll'
)

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    '/debug-',
    '/warn:4',
    '/checked+',
    ('/win32manifest:' + (Join-Path $installerRoot 'app.manifest')),
    ('/out:' + $outputPath)
)
$compilerArguments += $references | ForEach-Object { '/reference:' + $_ }
$compilerArguments += $sourceFiles

& $compiler $compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Installer compilation failed with exit code $LASTEXITCODE."
}

if (-not $SkipTests) {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('VlbInstallerBuildTests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    try {
        $testExecutable = Join-Path $testRoot 'InstallerCoreTests.exe'
        $testArguments = @(
            '/nologo',
            '/target:exe',
            '/platform:anycpu',
            '/optimize+',
            '/warn:4',
            ('/out:' + $testExecutable),
            '/reference:System.dll',
            '/reference:System.Core.dll',
            (Join-Path $installerRoot 'InstallerCore.cs'),
            (Join-Path $installerRoot 'tests\InstallerCoreTests.cs')
        )

        & $compiler $testArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Installer test compilation failed with exit code $LASTEXITCODE."
        }

        & $testExecutable
        if ($LASTEXITCODE -ne 0) {
            throw "Installer tests failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
            $tempRootFullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
            $resolvedTempRoot = $tempRootFullPath.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not ([System.IO.Path]::GetFileName($resolvedTestRoot)).StartsWith('VlbInstallerBuildTests-', [System.StringComparison]::Ordinal)) {
                throw "Refusing to remove unexpected test directory: $resolvedTestRoot"
            }
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

$artifact = Get-Item -LiteralPath $outputPath
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath

[pscustomobject]@{
    Path = $artifact.FullName
    SizeBytes = $artifact.Length
    FileVersion = $artifact.VersionInfo.FileVersion
    SHA256 = $hash.Hash
}

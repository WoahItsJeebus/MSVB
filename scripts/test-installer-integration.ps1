[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installerRoot = Join-Path $repositoryRoot 'installer'
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $compiler) {
    throw 'The .NET Framework C# compiler was not found.'
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'VlbInstallerIntegrationBuild-' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

try {
    $testExecutable = Join-Path $testRoot 'InstallerIntegrationTests.exe'
    $compilerArguments = @(
        '/nologo',
        '/target:exe',
        '/platform:anycpu',
        '/optimize+',
        '/warn:4',
        ('/out:' + $testExecutable),
        '/reference:System.dll',
        '/reference:System.Core.dll',
        '/reference:System.Net.Http.dll',
        '/reference:System.IO.Compression.dll',
        '/reference:System.IO.Compression.FileSystem.dll',
        '/reference:System.Web.Extensions.dll',
        (Join-Path $installerRoot 'InstallerCore.cs'),
        (Join-Path $installerRoot 'InstallerServices.cs'),
        (Join-Path $installerRoot 'tests\InstallerIntegrationTests.cs')
    )

    & $compiler $compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Installer integration test compilation failed with exit code $LASTEXITCODE."
    }

    & $testExecutable
    if ($LASTEXITCODE -ne 0) {
        throw "Installer integration tests failed with exit code $LASTEXITCODE."
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
            -not ([System.IO.Path]::GetFileName($resolvedTestRoot)).StartsWith('VlbInstallerIntegrationBuild-', [System.StringComparison]::Ordinal)) {
            throw "Refusing to remove unexpected test directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

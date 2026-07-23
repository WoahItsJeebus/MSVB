$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repositoryRoot 'backend\util\process_shell.cs'
$output = Join-Path $repositoryRoot 'backend\util\process_shell.exe'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
	throw 'The hidden process-shell source file is missing.'
}

$resolvedRoot = [System.IO.Path]::GetFullPath($repositoryRoot)
$resolvedOutput = [System.IO.Path]::GetFullPath($output)
if (-not $resolvedOutput.StartsWith(
	$resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
	[System.StringComparison]::OrdinalIgnoreCase
)) {
	throw 'The process-shell output path escaped the repository.'
}

if (Test-Path -LiteralPath $resolvedOutput) {
	Remove-Item -LiteralPath $resolvedOutput -Force
}

Add-Type `
	-TypeDefinition ([System.IO.File]::ReadAllText($source)) `
	-OutputAssembly $resolvedOutput `
	-OutputType WindowsApplication

if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
	throw 'The hidden process-shell executable was not produced.'
}

Write-Output "Built hidden process shell: $resolvedOutput"

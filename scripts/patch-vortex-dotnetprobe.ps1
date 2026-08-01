param(
	[string]$AsarPath = (
		Join-Path `
			$env:ProgramFiles `
			'Black Tree Gaming Ltd\Vortex\resources\app.asar'
	),
	[string]$BackupPath
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
	param([byte[]]$Bytes)

	$sha256 = [System.Security.Cryptography.SHA256]::Create()
	try {
		return (
			$sha256.ComputeHash($Bytes) |
				ForEach-Object { $_.ToString('x2') }
		) -join ''
	}
	finally {
		$sha256.Dispose()
	}
}

function Read-Exact {
	param(
		[System.IO.Stream]$Stream,
		[byte[]]$Buffer
	)

	$offset = 0
	while ($offset -lt $Buffer.Length) {
		$read = $Stream.Read(
			$Buffer,
			$offset,
			$Buffer.Length - $offset
		)
		if ($read -le 0) {
			throw 'Unexpected end of Vortex ASAR archive.'
		}
		$offset += $read
	}
}

if (-not (Test-Path -LiteralPath $AsarPath -PathType Leaf)) {
	throw "Vortex app.asar was not found: $AsarPath"
}
if (Get-Process -Name Vortex -ErrorAction SilentlyContinue) {
	throw 'Exit Vortex completely before patching its renderer.'
}

$resolvedAsar = [System.IO.Path]::GetFullPath($AsarPath)
$vortexRoot = Split-Path -Parent (Split-Path -Parent $resolvedAsar)
$vortexExecutable = Join-Path $vortexRoot 'Vortex.exe'
$vortexVersion =
	if (Test-Path -LiteralPath $vortexExecutable -PathType Leaf) {
		(Get-Item -LiteralPath $vortexExecutable).VersionInfo.ProductVersion
	}
	else {
		'unknown'
	}
$archive = [System.IO.File]::Open(
	$resolvedAsar,
	[System.IO.FileMode]::Open,
	[System.IO.FileAccess]::Read,
	[System.IO.FileShare]::Read
)
try {
	$sizePickle = New-Object byte[] 8
	Read-Exact -Stream $archive -Buffer $sizePickle
	if ([BitConverter]::ToUInt32($sizePickle, 0) -ne 4) {
		throw 'Vortex app.asar has an unsupported size pickle.'
	}
	$headerSize = [BitConverter]::ToUInt32($sizePickle, 4)
	if ($headerSize -lt 16 -or $headerSize -gt 64MB) {
		throw "Vortex app.asar has an invalid header size: $headerSize."
	}

	$headerBuffer = New-Object byte[] $headerSize
	Read-Exact -Stream $archive -Buffer $headerBuffer
	$headerPayloadSize = [BitConverter]::ToUInt32($headerBuffer, 0)
	$headerJsonSize = [BitConverter]::ToUInt32($headerBuffer, 4)
	if (
		$headerPayloadSize + 4 -ne $headerSize -or
		$headerJsonSize -lt 2 -or
		$headerJsonSize + 8 -gt $headerBuffer.Length
	) {
		throw 'Vortex app.asar has an unsupported header pickle.'
	}
	$headerJson = [Text.Encoding]::UTF8.GetString(
		$headerBuffer,
		8,
		$headerJsonSize
	)

	$rendererPattern = (
		'"renderer\.js":\{' +
		'"size":(?<size>\d+),' +
		'"integrity":\{' +
		'"algorithm":"SHA256",' +
		'"hash":"(?<hash>[0-9a-f]{64})",' +
		'"blockSize":(?<blockSize>\d+),' +
		'"blocks":\["(?<blockHash>[0-9a-f]{64})"\]\},' +
		'"offset":"(?<offset>\d+)"\}'
	)
	$rendererMatch = [regex]::Match($headerJson, $rendererPattern)
	if (-not $rendererMatch.Success) {
		throw 'Vortex app.asar does not contain the expected renderer.js entry.'
	}
	$rendererSize = [int64]$rendererMatch.Groups['size'].Value
	$rendererOffset = [int64]$rendererMatch.Groups['offset'].Value
	$rendererBlockSize = [int64]$rendererMatch.Groups['blockSize'].Value
	$rendererHash = $rendererMatch.Groups['hash'].Value
	$rendererBlockHash = $rendererMatch.Groups['blockHash'].Value
	if (
		$rendererSize -lt 1 -or
		$rendererSize -gt 16MB -or
		$rendererOffset -lt 0 -or
		$rendererBlockSize -lt $rendererSize -or
		$rendererHash -ne $rendererBlockHash
	) {
		throw 'Vortex renderer.js has unsupported ASAR integrity metadata.'
	}

	$headerRoot = $headerJson | ConvertFrom-Json
	$adminCheckEntry = (
		$headerRoot.files.node_modules.files.'is-admin'.files.'index.js'
	)
	if ($null -eq $adminCheckEntry) {
		throw 'Vortex app.asar does not contain the expected is-admin index.js entry.'
	}
	$adminCheckSize = [int64]$adminCheckEntry.size
	$adminCheckOffset = [int64]$adminCheckEntry.offset
	$adminCheckBlockSize = [int64]$adminCheckEntry.integrity.blockSize
	$adminCheckHash = [string]$adminCheckEntry.integrity.hash
	$adminCheckBlocks = @($adminCheckEntry.integrity.blocks)
	if (
		$adminCheckSize -lt 1 -or
		$adminCheckSize -gt 1MB -or
		$adminCheckOffset -lt 0 -or
		$adminCheckBlockSize -lt $adminCheckSize -or
		$adminCheckBlocks.Count -ne 1 -or
		$adminCheckHash -ne [string]$adminCheckBlocks[0]
	) {
		throw 'Vortex is-admin index.js has unsupported ASAR integrity metadata.'
	}

	$rendererAbsoluteOffset = 8L + $headerSize + $rendererOffset
	if (
		$rendererAbsoluteOffset -lt 0 -or
		$rendererAbsoluteOffset + $rendererSize -gt $archive.Length
	) {
		throw 'Vortex renderer.js extends beyond the ASAR archive.'
	}
	[void]$archive.Seek(
		$rendererAbsoluteOffset,
		[System.IO.SeekOrigin]::Begin
	)
	$rendererBytes = New-Object byte[] $rendererSize
	Read-Exact -Stream $archive -Buffer $rendererBytes

	$adminCheckAbsoluteOffset = 8L + $headerSize + $adminCheckOffset
	if (
		$adminCheckAbsoluteOffset -lt 0 -or
		$adminCheckAbsoluteOffset + $adminCheckSize -gt $archive.Length
	) {
		throw 'Vortex is-admin index.js extends beyond the ASAR archive.'
	}
	[void]$archive.Seek(
		$adminCheckAbsoluteOffset,
		[System.IO.SeekOrigin]::Begin
	)
	$adminCheckBytes = New-Object byte[] $adminCheckSize
	Read-Exact -Stream $archive -Buffer $adminCheckBytes
}
finally {
	$archive.Dispose()
}

$rendererText = [Text.Encoding]::UTF8.GetString($rendererBytes)
$patchedRendererText = $rendererText
$rendererChanged = $false
$originalFunction = (
	'function execFileWrapper(file,args=[]){return new Promise(' +
	'(resolve,reject)=>{const child=(0,child_process_1.execFile)' +
	'(file,args);let stdout="",stderr="";child.stdout?.on(' +
	'"data",data=>{stdout+=data.toString()}),child.stderr?.on(' +
	'"data",data=>{stderr+=data.toString()}),child.on(' +
	'"error",err=>{reject(err)}),child.on("close",exitCode=>{' +
	'resolve({stdout,stderr,exitCode:exitCode??0})})})}'
)
$replacementCore = (
	'function execFileWrapper(file,args=[]){return new Promise(' +
	'(resolve,reject)=>{const child=(0,child_process_1.execFile)' +
	'(file,args,{windowsHide:true});let stdout="",stderr="";' +
	'child.stdout?.on("data",data=>stdout+=data),child.stderr?.on(' +
	'"data",data=>stderr+=data),child.on("error",reject),child.on(' +
	'"close",exitCode=>resolve({stdout,stderr,exitCode:exitCode??0}))})}'
)
$patchedInvocation = '(file,args,{windowsHide:true})'
$originalIndex = $rendererText.IndexOf(
	$originalFunction,
	[StringComparison]::Ordinal
)
if ($originalIndex -ge 0) {
	if (
		$rendererText.IndexOf(
			$originalFunction,
			$originalIndex + $originalFunction.Length,
			[StringComparison]::Ordinal
		) -ge 0
	) {
		throw 'Vortex renderer.js contains more than one supported probe wrapper.'
	}
	if ($replacementCore.Length -gt $originalFunction.Length) {
		throw 'The signature-preserving renderer replacement is unexpectedly larger.'
	}

	$replacement = $replacementCore.PadRight($originalFunction.Length, ' ')
	$patchedRendererText = $patchedRendererText.Remove(
		$originalIndex,
		$originalFunction.Length
	).Insert($originalIndex, $replacement)
	$rendererChanged = $true
}
elseif (-not $rendererText.Contains($patchedInvocation)) {
	throw 'Vortex renderer.js does not contain the supported dotnet-probe call.'
}

$originalSpawnDeclaration = (
	'spawnOptions={cwd,env,detached:void 0===options.detach||' +
	'options.detach,shell:options.shell??!1}'
)
$patchedSpawnDeclaration = (
	'o={cwd,env,windowsHide:!0,detached:void 0===options.detach||' +
	'options.detach,shell:options.shell??!1}'
)
$originalSpawnUse = ',spawnOptions);if('
$patchedSpawnUse = ',o);       if('
$originalSpawnIndex = $patchedRendererText.IndexOf(
	$originalSpawnDeclaration,
	[StringComparison]::Ordinal
)
$originalSpawnUseIndex = $patchedRendererText.IndexOf(
	$originalSpawnUse,
	[StringComparison]::Ordinal
)
$patchedSpawnIndex = $patchedRendererText.IndexOf(
	$patchedSpawnDeclaration,
	[StringComparison]::Ordinal
)
$patchedSpawnUseIndex = $patchedRendererText.IndexOf(
	$patchedSpawnUse,
	[StringComparison]::Ordinal
)
if ($originalSpawnIndex -ge 0 -and $originalSpawnUseIndex -ge 0) {
	if (
		$patchedSpawnIndex -ge 0 -or
		$patchedSpawnUseIndex -ge 0 -or
		$patchedRendererText.IndexOf(
			$originalSpawnDeclaration,
			$originalSpawnIndex + $originalSpawnDeclaration.Length,
			[StringComparison]::Ordinal
		) -ge 0 -or
		$patchedRendererText.IndexOf(
			$originalSpawnUse,
			$originalSpawnUseIndex + $originalSpawnUse.Length,
			[StringComparison]::Ordinal
		) -ge 0
	) {
		throw 'Vortex renderer.js contains ambiguous executable-spawn wrappers.'
	}
	if (
		($patchedSpawnDeclaration.Length - $originalSpawnDeclaration.Length) +
		($patchedSpawnUse.Length - $originalSpawnUse.Length) -ne 0
	) {
		throw 'The hidden executable-spawn replacement must preserve renderer size.'
	}

	$patchedRendererText = $patchedRendererText.Remove(
		$originalSpawnIndex,
		$originalSpawnDeclaration.Length
	).Insert($originalSpawnIndex, $patchedSpawnDeclaration)
	$originalSpawnUseIndex = $patchedRendererText.IndexOf(
		$originalSpawnUse,
		[StringComparison]::Ordinal
	)
	$patchedRendererText = $patchedRendererText.Remove(
		$originalSpawnUseIndex,
		$originalSpawnUse.Length
	).Insert($originalSpawnUseIndex, $patchedSpawnUse)
	$rendererChanged = $true
}
elseif (
	$originalSpawnIndex -ge 0 -or
	$originalSpawnUseIndex -ge 0 -or
	$patchedSpawnIndex -lt 0 -or
	$patchedSpawnUseIndex -lt 0
) {
	throw 'Vortex renderer.js does not contain the supported executable-spawn wrapper.'
}

$adminCheckText = [Text.Encoding]::UTF8.GetString($adminCheckBytes)
$patchedAdminCheckText = $adminCheckText
$adminCheckChanged = $false
$originalAdminInvocation = (
	"await execa.shell('fsutil dirty query %systemdrive%');"
)
$hiddenShellAdminInvocation = (
	"await execa.shell('fsutil dirty query %systemdrive%', " +
	'{windowsHide: true});'
)
$directAdminInvocation = (
	"await execa('fsutil', ['dirty', 'query', " +
	'process.env.SystemDrive], hidden);'
)
$directAdminCheckCore = (
	@(
		"'use strict';"
		"const execa = require('execa');"
		'const hidden = {windowsHide: true};'
		''
		'async function testFltmc() {'
		"`ttry {"
		"`t`tawait execa('fltmc', [], hidden);"
		"`t`treturn true;"
		"`t} catch (_) {"
		"`t`treturn false;"
		"`t}"
		'}'
		''
		'module.exports = async () => {'
		"`tif (process.platform !== 'win32') {"
		"`t`treturn false;"
		"`t}"
		''
		"`ttry {"
		"`t`t$directAdminInvocation"
		"`t`treturn true;"
		"`t} catch (error) {"
		"`t`tif (error.code === 'ENOENT') {"
		"`t`t`treturn testFltmc();"
		"`t`t}"
		"`t`treturn false;"
		"`t}"
		'};'
		''
	) -join "`n"
)
$originalAdminInvocationIndex = $adminCheckText.IndexOf(
	$originalAdminInvocation,
	[StringComparison]::Ordinal
)
$hiddenShellAdminInvocationIndex = $adminCheckText.IndexOf(
	$hiddenShellAdminInvocation,
	[StringComparison]::Ordinal
)
$directAdminInvocationIndex = $adminCheckText.IndexOf(
	$directAdminInvocation,
	[StringComparison]::Ordinal
)
if ($directAdminInvocationIndex -ge 0) {
	if (
		$adminCheckText.IndexOf(
			$directAdminInvocation,
			$directAdminInvocationIndex + $directAdminInvocation.Length,
			[StringComparison]::Ordinal
		) -ge 0
	) {
		throw 'Vortex is-admin index.js contains an ambiguous direct admin check.'
	}
}
elseif (
	$originalAdminInvocationIndex -ge 0 -or
	$hiddenShellAdminInvocationIndex -ge 0
) {
	if (
		(
			$originalAdminInvocationIndex -ge 0 -and
			$hiddenShellAdminInvocationIndex -ge 0
		) -or
		$adminCheckText.IndexOf(
			$originalAdminInvocation,
			$originalAdminInvocationIndex + $originalAdminInvocation.Length,
			[StringComparison]::Ordinal
		) -ge 0 -or
		-not $adminCheckText.Contains(
			"const execa = require('execa');"
		) -or
		-not $adminCheckText.Contains("await execa('fltmc');") -or
		$directAdminCheckCore.Length -gt $adminCheckText.Length
	) {
		throw 'Vortex is-admin index.js contains an ambiguous admin-check shell call.'
	}

	$patchedAdminCheckText = $directAdminCheckCore.PadRight(
		$adminCheckText.Length,
		' '
	)
	$adminCheckChanged = $true
}
else {
	throw 'Vortex is-admin index.js does not contain the supported admin-check shell call.'
}

$patchedRendererBytes = [Text.Encoding]::UTF8.GetBytes($patchedRendererText)
if ($patchedRendererBytes.Length -ne $rendererBytes.Length) {
	throw 'The patched renderer would change the ASAR file layout.'
}
$patchedAdminCheckBytes = [Text.Encoding]::UTF8.GetBytes(
	$patchedAdminCheckText
)
if ($patchedAdminCheckBytes.Length -ne $adminCheckBytes.Length) {
	throw 'The patched admin check would change the ASAR file layout.'
}
if (-not $rendererChanged -and -not $adminCheckChanged) {
	[pscustomobject]@{
		changed = $false
		asarPath = $resolvedAsar
		vortexVersion = $vortexVersion
		backupPath = $null
		rendererPatched = $true
		dotnetProbePatched = $true
		shellLaunchPatched = $true
		adminCheckPatched = $true
		asarSha256 = (
			Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256
		).Hash
	}
	exit 0
}

$computedOriginalHash = Get-Sha256Hex -Bytes $rendererBytes
if ($computedOriginalHash -ne $rendererHash) {
	throw 'Vortex renderer.js failed its original ASAR integrity check.'
}
$patchedRendererHash = Get-Sha256Hex -Bytes $patchedRendererBytes

$computedOriginalAdminCheckHash = Get-Sha256Hex -Bytes $adminCheckBytes
if ($computedOriginalAdminCheckHash -ne $adminCheckHash) {
	throw 'Vortex is-admin index.js failed its original ASAR integrity check.'
}
$patchedAdminCheckHash = Get-Sha256Hex -Bytes $patchedAdminCheckBytes

$oldHashMatches = [regex]::Matches(
	$headerJson,
	[regex]::Escape($rendererHash)
)
if ($oldHashMatches.Count -ne 2) {
	throw 'Vortex renderer.js integrity hashes were not uniquely identified.'
}
$patchedHeaderJson = $headerJson.Replace(
	$rendererHash,
	$patchedRendererHash
)
$oldAdminCheckHashMatches = [regex]::Matches(
	$patchedHeaderJson,
	[regex]::Escape($adminCheckHash)
)
if ($oldAdminCheckHashMatches.Count -ne 2) {
	throw 'Vortex is-admin index.js integrity hashes were not uniquely identified.'
}
$patchedHeaderJson = $patchedHeaderJson.Replace(
	$adminCheckHash,
	$patchedAdminCheckHash
)
$patchedHeaderJsonBytes = [Text.Encoding]::UTF8.GetBytes(
	$patchedHeaderJson
)
if ($patchedHeaderJsonBytes.Length -ne $headerJsonSize) {
	throw 'The patched ASAR header would change size.'
}
[Array]::Copy(
	$patchedHeaderJsonBytes,
	0,
	$headerBuffer,
	8,
	$patchedHeaderJsonBytes.Length
)

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
	$backupDirectory = Join-Path `
		$env:LOCALAPPDATA `
		'VortexLaunchBridge\Backups'
	$backupName = (
		'vortex-app-{0:yyyyMMdd-HHmmss}-{1}.asar' -f
		(Get-Date),
		(Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256).
			Hash.Substring(0, 12)
	)
	$BackupPath = Join-Path $backupDirectory $backupName
}
$resolvedBackup = [System.IO.Path]::GetFullPath($BackupPath)
if ($resolvedBackup -eq $resolvedAsar) {
	throw 'The ASAR backup path must differ from the live archive.'
}
$backupDirectory = Split-Path -Parent $resolvedBackup
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
if (Test-Path -LiteralPath $resolvedBackup) {
	throw "Refusing to overwrite an existing backup: $resolvedBackup"
}
Copy-Item -LiteralPath $resolvedAsar -Destination $resolvedBackup

$originalAsarHash = (
	Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256
).Hash
$backupHash = (
	Get-FileHash -LiteralPath $resolvedBackup -Algorithm SHA256
).Hash
if ($originalAsarHash -ne $backupHash) {
	throw 'The Vortex app.asar backup failed hash verification.'
}

$writeStarted = $false
try {
	$archive = [System.IO.File]::Open(
		$resolvedAsar,
		[System.IO.FileMode]::Open,
		[System.IO.FileAccess]::ReadWrite,
		[System.IO.FileShare]::None
	)
	try {
		$writeStarted = $true
		[void]$archive.Seek(8, [System.IO.SeekOrigin]::Begin)
		$archive.Write($headerBuffer, 0, $headerBuffer.Length)
		[void]$archive.Seek(
			$rendererAbsoluteOffset,
			[System.IO.SeekOrigin]::Begin
		)
		$archive.Write(
			$patchedRendererBytes,
			0,
			$patchedRendererBytes.Length
		)
		[void]$archive.Seek(
			$adminCheckAbsoluteOffset,
			[System.IO.SeekOrigin]::Begin
		)
		$archive.Write(
			$patchedAdminCheckBytes,
			0,
			$patchedAdminCheckBytes.Length
		)
		$archive.Flush($true)
	}
	finally {
		$archive.Dispose()
	}

	$verifyArchive = [System.IO.File]::OpenRead($resolvedAsar)
	try {
		[void]$verifyArchive.Seek(
			$rendererAbsoluteOffset,
			[System.IO.SeekOrigin]::Begin
		)
		$verifiedRenderer = New-Object byte[] $rendererSize
		Read-Exact -Stream $verifyArchive -Buffer $verifiedRenderer
		[void]$verifyArchive.Seek(
			$adminCheckAbsoluteOffset,
			[System.IO.SeekOrigin]::Begin
		)
		$verifiedAdminCheck = New-Object byte[] $adminCheckSize
		Read-Exact -Stream $verifyArchive -Buffer $verifiedAdminCheck
	}
	finally {
		$verifyArchive.Dispose()
	}
	if (
		(Get-Sha256Hex -Bytes $verifiedRenderer) -ne
			$patchedRendererHash
	) {
		throw 'The patched renderer failed ASAR integrity verification.'
	}
	if (
		(Get-Sha256Hex -Bytes $verifiedAdminCheck) -ne
			$patchedAdminCheckHash
	) {
		throw 'The patched admin check failed ASAR integrity verification.'
	}
}
catch {
	if ($writeStarted -and (Test-Path -LiteralPath $resolvedBackup)) {
		Copy-Item `
			-LiteralPath $resolvedBackup `
			-Destination $resolvedAsar `
			-Force
	}
	throw
}

[pscustomobject]@{
	changed = $true
	asarPath = $resolvedAsar
	vortexVersion = $vortexVersion
	backupPath = $resolvedBackup
	rendererPatched = $true
	dotnetProbePatched = $true
	shellLaunchPatched = $true
	adminCheckPatched = $true
	originalRendererSha256 = $rendererHash
	patchedRendererSha256 = $patchedRendererHash
	originalAdminCheckSha256 = $adminCheckHash
	patchedAdminCheckSha256 = $patchedAdminCheckHash
	originalAsarSha256 = $originalAsarHash
	patchedAsarSha256 = (
		Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256
	).Hash
}

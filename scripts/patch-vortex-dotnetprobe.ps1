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
}
finally {
	$archive.Dispose()
}

$rendererText = [Text.Encoding]::UTF8.GetString($rendererBytes)
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
if ($originalIndex -lt 0) {
	if ($rendererText.Contains($patchedInvocation)) {
		[pscustomobject]@{
			changed = $false
			asarPath = $resolvedAsar
			backupPath = $null
			rendererPatched = $true
			asarSha256 = (
				Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256
			).Hash
		}
		exit 0
	}
	throw 'Vortex renderer.js does not contain the supported dotnet-probe call.'
}
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
$patchedRendererText = $rendererText.Remove(
	$originalIndex,
	$originalFunction.Length
).Insert($originalIndex, $replacement)
$patchedRendererBytes = [Text.Encoding]::UTF8.GetBytes($patchedRendererText)
if ($patchedRendererBytes.Length -ne $rendererBytes.Length) {
	throw 'The patched renderer would change the ASAR file layout.'
}
$computedOriginalHash = Get-Sha256Hex -Bytes $rendererBytes
if ($computedOriginalHash -ne $rendererHash) {
	throw 'Vortex renderer.js failed its original ASAR integrity check.'
}
$patchedRendererHash = Get-Sha256Hex -Bytes $patchedRendererBytes

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
	backupPath = $resolvedBackup
	rendererPatched = $true
	originalRendererSha256 = $rendererHash
	patchedRendererSha256 = $patchedRendererHash
	originalAsarSha256 = $originalAsarHash
	patchedAsarSha256 = (
		Get-FileHash -LiteralPath $resolvedAsar -Algorithm SHA256
	).Hash
}

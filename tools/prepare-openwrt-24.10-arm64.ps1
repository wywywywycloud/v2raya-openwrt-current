param(
    [Parameter(Mandatory = $true)] [string] $Version,
    [Parameter(Mandatory = $true)] [string] $OutputDir
)

$ErrorActionPreference = 'Stop'
if ($Version -notin @('24.10.0','24.10.1','24.10.2','24.10.3','24.10.4','24.10.5','24.10.6','24.10.7','24.10.8')) {
    throw "Unsupported OpenWrt version: $Version"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$filename = "openwrt-$Version-armsr-armv8-generic-ext4-combined-efi.img.gz"
$base = "https://downloads.openwrt.org/releases/$Version/targets/armsr/armv8"
$checksums = (Invoke-WebRequest -Uri "$base/sha256sums" -TimeoutSec 120).Content
$entry = $checksums -split "`n" | Where-Object { $_ -match "^[a-f0-9]{64} \*$([regex]::Escape($filename))`r?$" } | Select-Object -First 1
if (-not $entry) { throw "Official checksum missing for $filename" }
$expected = ($entry -split ' ')[0]
$archive = Join-Path $OutputDir $filename
if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) {
    $download = "$archive.download"
    Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri "$base/$filename" -OutFile $download -TimeoutSec 300
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash.ToLowerInvariant() -ne $expected) {
        throw "Checksum mismatch for $filename"
    }
    Move-Item -LiteralPath $download -Destination $archive -Force
}
$image = Join-Path $OutputDir "openwrt-$Version-armv8.img"
$tempImage = "$image.download"
$source = [IO.File]::OpenRead($archive)
try {
    $gzip = [IO.Compression.GZipStream]::new($source, [IO.Compression.CompressionMode]::Decompress)
    try {
        $target = [IO.File]::Create($tempImage)
        try { $gzip.CopyTo($target) } finally { $target.Dispose() }
    } finally { $gzip.Dispose() }
} finally { $source.Dispose() }
[IO.File]::Move($tempImage, $image, $true)
if ((Get-Item -LiteralPath $image).Length -lt 100MB) { throw "Decompressed image is unexpectedly small: $image" }
[pscustomobject]@{ Version = $Version; Image = $image; SHA256 = $expected }

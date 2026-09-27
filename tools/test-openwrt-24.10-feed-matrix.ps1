param(
    [Parameter(Mandatory = $true)] [string] $Qemu,
    [Parameter(Mandatory = $true)] [string] $Firmware,
    [Parameter(Mandatory = $true)] [string] $ImageDir,
    [Parameter(Mandatory = $true)] [string] $Packages,
    [Parameter(Mandatory = $true)] [string] $Python,
    [Parameter(Mandatory = $true)] [string] $AppVersion,
    [Parameter(Mandatory = $true)] [string] $PackageRelease,
    [Parameter(Mandatory = $true)] [string] $WorkRoot,
    [int] $ThrottleLimit = 3,
    [switch] $TrafficSmoke,
    [string[]] $Versions = @('24.10.0','24.10.1','24.10.2','24.10.3','24.10.4','24.10.5','24.10.6','24.10.7','24.10.8')
)

$ErrorActionPreference = 'Stop'
if ($ThrottleLimit -lt 1 -or $ThrottleLimit -gt 4) { throw 'ThrottleLimit must be 1–4' }
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
$WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path
$ImageDir = (Resolve-Path -LiteralPath $ImageDir).Path
$runner = Join-Path $PSScriptRoot 'test-openwrt-24.10.4-arm64.ps1'
foreach ($version in $Versions) {
    if ($version -notin @('24.10.0','24.10.1','24.10.2','24.10.3','24.10.4','24.10.5','24.10.6','24.10.7','24.10.8')) {
        throw "Unsupported OpenWrt version: $version"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ImageDir "openwrt-$version-armv8.img"))) {
        throw "Missing verified image for $version"
    }
}

$fixture = $null
if ($TrafficSmoke) {
    $fixtureInfo = [Diagnostics.ProcessStartInfo]::new()
    $fixtureInfo.FileName = $Python
    $fixtureInfo.UseShellExecute = $false
    $fixtureInfo.CreateNoWindow = $true
    $fixtureInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $fixtureInfo.RedirectStandardOutput = $true
    $fixtureInfo.RedirectStandardError = $true
    foreach ($argument in @((Join-Path $PSScriptRoot 'local-socks-fixture.py'), '--host', '0.0.0.0')) {
        [void] $fixtureInfo.ArgumentList.Add($argument)
    }
    $fixture = [Diagnostics.Process]::new()
    $fixture.StartInfo = $fixtureInfo
    if (-not $fixture.Start()) { throw 'SOCKS fixture did not start' }
    $fixtureStdout = $fixture.StandardOutput.ReadToEndAsync()
    $fixtureStderr = $fixture.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 1
    if ($fixture.HasExited) { throw "SOCKS fixture exited: $($fixtureStderr.GetAwaiter().GetResult())" }
}

try {
$results = $Versions | ForEach-Object -Parallel {
    $version = $_
    $revision = [int]($version.Split('.')[-1])
    $portBase = 28100 + 10 * $revision
    $image = Join-Path $using:ImageDir "openwrt-$version-armv8.img"
    $workDir = Join-Path $using:WorkRoot $version
    $runnerPath = $using:runner
    try {
        $output = & $runnerPath -Qemu $using:Qemu -Firmware $using:Firmware -Image $image `
            -Packages $using:Packages -Python $using:Python -AppVersion $using:AppVersion `
            -PackageRelease $using:PackageRelease -OpenWrtVersion $version -InstallFromPublishedFeed `
            -WorkDir $workDir -SshPort ($portBase + 2) -SerialPort ($portBase + 3) `
            -PackagePort ($portBase + 4) -TrafficSmoke:$using:TrafficSmoke 2>&1 | Out-String
        [pscustomobject]@{ Version = $version; Passed = $true; Output = $output.Trim(); SerialLog = (Join-Path $workDir 'serial.log') }
    } catch {
        [pscustomobject]@{ Version = $version; Passed = $false; Output = $_.Exception.Message; SerialLog = (Join-Path $workDir 'serial.log') }
    }
} -ThrottleLimit $ThrottleLimit
} finally {
    if ($null -ne $fixture) {
        if (-not $fixture.HasExited) { $fixture.Kill($true); $fixture.WaitForExit() }
        [IO.File]::WriteAllText((Join-Path $WorkRoot 'fixture.log'), $fixtureStdout.GetAwaiter().GetResult() + $fixtureStderr.GetAwaiter().GetResult())
        $fixture.Dispose()
    }
}

$results = @($results | Sort-Object Version)
$report = [pscustomobject]@{
    TestedAtUtc = [DateTime]::UtcNow.ToString('o')
    AppVersion = $AppVersion
    PackageRelease = $PackageRelease
    ThrottleLimit = $ThrottleLimit
    TrafficSmoke = [bool]$TrafficSmoke
    Results = $results
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $WorkRoot 'matrix-results.json') -Encoding utf8
$results | Select-Object Version,Passed,Output,SerialLog | Format-Table -Wrap
if (($results | Where-Object { -not $_.Passed }).Count -gt 0 -or $results.Count -ne $Versions.Count) { exit 1 }

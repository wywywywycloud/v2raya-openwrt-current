param(
    [Parameter(Mandatory = $true)] [string] $Qemu,
    [Parameter(Mandatory = $true)] [string] $Firmware,
    [Parameter(Mandatory = $true)] [string] $Image,
    [Parameter(Mandatory = $true)] [string] $Packages,
    [Parameter(Mandatory = $true)] [string] $Python,
    [string] $WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "v2raya-resilient-openwrt-arm64"),
    [int] $SshPort = 27922,
    [int] $SerialPort = 27923,
    [int] $PackagePort = 27924
)

$ErrorActionPreference = "Stop"
$nullDevice = if ($IsWindows) { "NUL" } else { "/dev/null" }
$Qemu = (Resolve-Path -LiteralPath $Qemu).Path
$Firmware = (Resolve-Path -LiteralPath $Firmware).Path
$Image = (Resolve-Path -LiteralPath $Image).Path
$Packages = (Resolve-Path -LiteralPath $Packages).Path
$Python = (Resolve-Path -LiteralPath $Python).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$runImage = Join-Path $WorkDir "openwrt-24.10.4-arm64-run.img"
$usrImage = Join-Path $WorkDir "openwrt-24.10.4-arm64-usr.img"
$sshKey = Join-Path $WorkDir "id_ed25519"
$serialLog = Join-Path $WorkDir "serial.log"
Copy-Item -LiteralPath $Image -Destination $runImage -Force
$usrStream = [IO.File]::Open($usrImage, [IO.FileMode]::Create, [IO.FileAccess]::Write)
try { $usrStream.SetLength(512MB) } finally { $usrStream.Dispose() }
[IO.File]::WriteAllText($serialLog, "")

function Invoke-Native([string] $File, [string[]] $Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File exited with $LASTEXITCODE" }
}

if (-not (Test-Path -LiteralPath $sshKey)) {
    Invoke-Native "ssh-keygen" @("-q", "-t", "ed25519", "-N", "", "-f", $sshKey)
}
$publicKeyParts = (Get-Content -LiteralPath "$sshKey.pub" -Raw).Trim() -split "\s+"
$sshPublicKey = $publicKeyParts[0..1] -join " "

function Invoke-Ssh([string] $Command, [switch] $Quiet) {
    $arguments = @(
        "-F", $nullDevice, "-p", "$SshPort", "-i", $sshKey,
        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
        "-o", "ConnectTimeout=20", "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=$nullDevice", "root@127.0.0.1", $Command
    )
    if ($Quiet) {
        $script:lastSshError = (& ssh @arguments 2>&1 | Out-String).Trim()
        return $LASTEXITCODE -eq 0
    }
    Invoke-Native "ssh" $arguments
}

$qemuArguments = @(
    "-machine", "virt,accel=tcg,gic-version=3", "-cpu", "cortex-a53",
    "-smp", "2", "-m", "512", "-bios", $Firmware,
    "-display", "none", "-no-reboot",
    "-serial", "tcp:127.0.0.1:${SerialPort},server=on,wait=off",
    "-drive", "file=$runImage,format=raw,if=none,id=disk0",
    "-device", "virtio-blk-pci,drive=disk0",
    "-drive", "file=$usrImage,format=raw,if=none,id=usr0",
    "-device", "virtio-blk-pci,drive=usr0",
    "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:${SshPort}-:22",
    "-device", "virtio-net-pci,netdev=net0"
)
$httpInfo = [Diagnostics.ProcessStartInfo]::new()
$httpInfo.FileName = $Python
$httpInfo.UseShellExecute = $false
$httpInfo.CreateNoWindow = $true
$httpInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$httpInfo.RedirectStandardOutput = $true
$httpInfo.RedirectStandardError = $true
foreach ($argument in @("-m", "http.server", "$PackagePort", "--bind", "127.0.0.1", "--directory", $Packages)) {
    [void] $httpInfo.ArgumentList.Add($argument)
}
$httpProcess = [Diagnostics.Process]::new()
$httpProcess.StartInfo = $httpInfo
if (-not $httpProcess.Start()) { throw "Package HTTP server did not start" }
$httpStdout = $httpProcess.StandardOutput.ReadToEndAsync()
$httpStderr = $httpProcess.StandardError.ReadToEndAsync()
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Qemu
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $qemuArguments) { [void] $startInfo.ArgumentList.Add($argument) }
$qemuProcess = [Diagnostics.Process]::new()
$qemuProcess.StartInfo = $startInfo
if (-not $qemuProcess.Start()) { throw "QEMU did not start" }
$stdout = $qemuProcess.StandardOutput.ReadToEndAsync()
$stderr = $qemuProcess.StandardError.ReadToEndAsync()
$serialClient = $null
$serialStream = $null
$serialText = [Text.StringBuilder]::new()

function Wait-Serial([string] $Pattern, [DateTime] $Deadline) {
    $buffer = [byte[]]::new(4096)
    while ([DateTime]::UtcNow -lt $Deadline -and -not $qemuProcess.HasExited) {
        if ($serialStream.DataAvailable) {
            $count = $serialStream.Read($buffer, 0, $buffer.Length)
            if ($count -gt 0) {
                $chunk = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
                [void] $serialText.Append($chunk)
                [IO.File]::AppendAllText($serialLog, $chunk)
                if ($serialText.ToString().Contains($Pattern)) { return }
            }
        } else { Start-Sleep -Milliseconds 100 }
    }
    throw "Serial console did not reach marker: $Pattern"
}

function Invoke-Serial([string] $Command, [string] $Marker, [int] $Minutes = 10) {
    $start = $serialText.Length
    $split = [Math]::Floor($Marker.Length / 2)
    $markerLeft = $Marker.Substring(0, $split)
    $markerRight = $Marker.Substring($split)
    # Keep the complete marker out of the echoed command. The serial terminal
    # echoes input, so matching a literal marker there would be a false pass.
    $line = "( $Command ) && printf '%s%s\n' '$markerLeft' '$markerRight'`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($line)
    $serialStream.Write($bytes, 0, $bytes.Length)
    $deadline = [DateTime]::UtcNow.AddMinutes($Minutes)
    $buffer = [byte[]]::new(4096)
    while ([DateTime]::UtcNow -lt $deadline -and -not $qemuProcess.HasExited) {
        if ($serialStream.DataAvailable) {
            $count = $serialStream.Read($buffer, 0, $buffer.Length)
            if ($count -gt 0) {
                $chunk = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
                [void] $serialText.Append($chunk)
                [IO.File]::AppendAllText($serialLog, $chunk)
                $result = $serialText.ToString().Substring($start)
                if ($result.Contains($Marker)) { return }
                if ($result -match 'root@[^\r\n]*# ') {
                    throw "Serial command returned before marker ${Marker}: $result"
                }
            }
        } else { Start-Sleep -Milliseconds 100 }
    }
    throw "Serial command timed out before marker: $Marker"
}

try {
    $deadline = [DateTime]::UtcNow.AddMinutes(8)
    while ([DateTime]::UtcNow -lt $deadline -and $null -eq $serialClient) {
        if ($qemuProcess.HasExited) { throw "QEMU exited before opening the serial console" }
        try {
            $candidate = [Net.Sockets.TcpClient]::new()
            $candidate.Connect("127.0.0.1", $SerialPort)
            $serialClient = $candidate
            $serialStream = $serialClient.GetStream()
        } catch {
            if ($null -ne $candidate) { $candidate.Dispose() }
            Start-Sleep -Milliseconds 200
        }
    }
    if ($null -eq $serialClient) { throw "Could not connect to QEMU serial console" }
    Wait-Serial "Please press Enter to activate this console." $deadline
    $enter = [Text.Encoding]::ASCII.GetBytes("`r`n")
    $serialStream.Write($enter, 0, $enter.Length)
    Wait-Serial "root@" $deadline
    Wait-Serial "br-lan: port 1(eth0) entered forwarding state" $deadline
    $ipks = Get-ChildItem -LiteralPath $Packages -Filter "*.ipk" -File
    if ($ipks.Count -ne 3) { throw "Expected exactly three IPKs, found $($ipks.Count)" }
    Invoke-Serial '(ip addr add 10.0.2.15/24 dev br-lan 2>/dev/null || true) && ip link set br-lan up && ip route replace default via 10.0.2.2 && mkdir -p /tmp/resolv.conf.d && printf "nameserver 10.0.2.3\n" > /tmp/resolv.conf.d/resolv.conf.auto && . /etc/openwrt_release && test "$DISTRIB_RELEASE" = "24.10.4" && test "$(uname -m)" = "aarch64" && ping -c 1 10.0.2.2' "__RESILIENT_NETWORK_OK__"
    Invoke-Serial 'mkfs.ext4 -F /dev/vdb && mkdir -p /mnt/resilient-usr && mount /dev/vdb /mnt/resilient-usr && cp -a /usr/. /mnt/resilient-usr/ && mount /dev/vdb /usr' "__RESILIENT_USR_READY__" 5
    $downloadNumber = 0
    foreach ($ipk in $ipks) {
        $downloadNumber++
        $download = "wget -O /tmp/$($ipk.Name) http://10.0.2.2:${PackagePort}/$($ipk.Name)"
        Invoke-Serial $download "__RESILIENT_IPK_${downloadNumber}__" 15
    }
    Invoke-Serial "printf 'arch all 1\narch noarch 1\narch aarch64_generic 10\narch aarch64_cortex-a53 100\n' >> /etc/opkg.conf; opkg update" "__RESILIENT_UPDATED__" 15
    Invoke-Serial "opkg install /tmp/v2raya-resilient-core_*_aarch64_cortex-a53.ipk /tmp/v2raya-resilient_2*_aarch64_cortex-a53.ipk /tmp/luci-app-v2raya-resilient_*_aarch64_cortex-a53.ipk" "__RESILIENT_INSTALLED__" 15
    Invoke-Serial 'test "$(opkg status v2raya-resilient | sed -n "s/^Version: //p")" = "2.5.7-resilient.7-r13.resilient1"' "__RESILIENT_APP_PACKAGE_OK__"
    Invoke-Serial 'test "$(opkg status v2raya-resilient-core | sed -n "s/^Version: //p")" = "2.5.7-resilient.7-r13.resilient1"' "__RESILIENT_CORE_PACKAGE_OK__"
    Invoke-Serial 'test "$(opkg status luci-app-v2raya-resilient | sed -n "s/^Version: //p")" = "26.268.0-r13.resilient1"' "__RESILIENT_LUCI_PACKAGE_OK__"
    Invoke-Serial 'test "$(/usr/bin/v2raya --version)" = "2.5.7-resilient.7"; /usr/bin/v2raya_core version | grep -q "V2RAYA_CORE 2.5.7-resilient.7 "' "__RESILIENT_BINARY_VERSIONS_OK__"
    Invoke-Serial 'test -f /usr/share/luci/menu.d/luci-app-v2raya.json; test -f /www/luci-static/resources/view/v2raya/config.js' "__RESILIENT_LUCI_FILES_OK__"
    Invoke-Serial "uci set v2raya.config.enabled='1'; uci commit v2raya; /etc/init.d/v2raya restart; sleep 8; /etc/init.d/v2raya running" "__RESILIENT_SERVICE_RUNNING__"
    Invoke-Serial "wget -qO /tmp/v2raya-index http://127.0.0.1:2017/; grep -q '<title>v2rayA</title>' /tmp/v2raya-index" "__RESILIENT_GUI_OK__"
    Invoke-Serial 'wget -qO /tmp/v2raya-version http://127.0.0.1:2017/api/version; grep -q ''"version":"2.5.7-resilient.7"'' /tmp/v2raya-version; grep -q ''"coreVersion":"2.5.7-resilient.7"'' /tmp/v2raya-version; grep -q ''"coreVersionValid":true'' /tmp/v2raya-version' "__RESILIENT_API_OK__"
} finally {
    if (-not $qemuProcess.HasExited) { $qemuProcess.Kill($true); $qemuProcess.WaitForExit() }
    if (-not $httpProcess.HasExited) { $httpProcess.Kill($true); $httpProcess.WaitForExit() }
    if ($null -ne $serialStream) {
        $buffer = [byte[]]::new(4096)
        while ($serialStream.DataAvailable) {
            $count = $serialStream.Read($buffer, 0, $buffer.Length)
            if ($count -le 0) { break }
            [void] $serialText.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $count))
        }
    }
    [IO.File]::WriteAllText($serialLog, $serialText.ToString())
    [IO.File]::WriteAllText((Join-Path $WorkDir "qemu-error.log"), $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $WorkDir "http.log"), $httpStdout.GetAwaiter().GetResult() + $httpStderr.GetAwaiter().GetResult())
    if ($null -ne $serialStream) { $serialStream.Dispose() }
    if ($null -ne $serialClient) { $serialClient.Dispose() }
    $qemuProcess.Dispose()
    Remove-Item -LiteralPath $runImage -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $usrImage -Force -ErrorAction SilentlyContinue
}

Write-Host "OpenWrt 24.10.4 ARM64 package checks passed; serial log: $serialLog"

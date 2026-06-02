param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "get-brightness",
        "set-brightness",
        "adjust-brightness",
        "get-volume",
        "set-volume",
        "adjust-volume",
        "mute",
        "unmute",
        "get-power",
        "set-display-timeout",
        "set-sleep-timeout",
        "set-power-scheme"
    )]
    [string]$Action,

    [int]$Value = -1,
    [int]$Delta = 0,

    [ValidateSet("ac", "dc", "both")]
    [string]$Power = "both",

    [ValidateSet("balanced", "power-saver", "high-performance")]
    [string]$Scheme = "balanced"
)

$ErrorActionPreference = "Stop"

function Assert-Percent {
    param([int]$Percent, [string]$Name)
    if ($Percent -lt 0 -or $Percent -gt 100) {
        throw "$Name must be between 0 and 100."
    }
}

function Assert-NonNegative {
    param([int]$Number, [string]$Name)
    if ($Number -lt 0) {
        throw "$Name must be 0 or greater."
    }
}

function Get-BrightnessMonitors {
    $monitors = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness
    if (-not $monitors) {
        throw "No brightness-capable monitor found via root/WMI WmiMonitorBrightness."
    }
    return $monitors
}

function Set-Brightness {
    param([int]$Target)
    Assert-Percent $Target "Brightness"
    $monitors = Get-BrightnessMonitors
    $methods = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods
    foreach ($monitor in $monitors) {
        $current = [int]$monitor.CurrentBrightness
        $method = $methods | Where-Object { $_.InstanceName -eq $monitor.InstanceName } | Select-Object -First 1
        if (-not $method) {
            throw "No brightness method found for $($monitor.InstanceName)."
        }
        Invoke-CimMethod -InputObject $method -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $Target } | Out-Null
        Start-Sleep -Milliseconds 250
        $after = (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness |
            Where-Object { $_.InstanceName -eq $monitor.InstanceName } |
            Select-Object -First 1).CurrentBrightness
        "$($monitor.InstanceName): $current -> $after"
    }
}

function Get-Brightness {
    foreach ($monitor in (Get-BrightnessMonitors)) {
        "$($monitor.InstanceName): $($monitor.CurrentBrightness)"
    }
}

function Add-CoreAudioType {
    if ("AudioVolume" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume
{
    [PreserveSig] int RegisterControlChangeNotify(IntPtr pNotify);
    [PreserveSig] int UnregisterControlChangeNotify(IntPtr pNotify);
    [PreserveSig] int GetChannelCount(out uint pnChannelCount);
    [PreserveSig] int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
    [PreserveSig] int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
    [PreserveSig] int GetMasterVolumeLevel(out float pfLevelDB);
    [PreserveSig] int GetMasterVolumeLevelScalar(out float pfLevel);
    [PreserveSig] int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
    [PreserveSig] int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
    [PreserveSig] int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    [PreserveSig] int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
    [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    [PreserveSig] int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    [PreserveSig] int VolumeStepUp(Guid pguidEventContext);
    [PreserveSig] int VolumeStepDown(Guid pguidEventContext);
    [PreserveSig] int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    [PreserveSig] int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice
{
    [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioEndpointVolume endpointVolume);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator
{
    [PreserveSig] int NotImpl1();
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject
{
}

public class AudioVolume
{
    private static IAudioEndpointVolume GetEndpointVolume()
    {
        IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        IAudioEndpointVolume endpoint;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out endpoint));
        return endpoint;
    }

    public static int GetVolume()
    {
        float value;
        Marshal.ThrowExceptionForHR(GetEndpointVolume().GetMasterVolumeLevelScalar(out value));
        return (int)Math.Round(value * 100.0f);
    }

    public static bool GetMute()
    {
        bool muted;
        Marshal.ThrowExceptionForHR(GetEndpointVolume().GetMute(out muted));
        return muted;
    }

    public static void SetVolume(int percent)
    {
        float value = Math.Max(0.0f, Math.Min(100.0f, (float)percent)) / 100.0f;
        Marshal.ThrowExceptionForHR(GetEndpointVolume().SetMasterVolumeLevelScalar(value, Guid.Empty));
    }

    public static void SetMute(bool muted)
    {
        Marshal.ThrowExceptionForHR(GetEndpointVolume().SetMute(muted, Guid.Empty));
    }
}
"@
}

function Get-Volume {
    Add-CoreAudioType
    "volume: $([AudioVolume]::GetVolume())"
    "muted: $([AudioVolume]::GetMute())"
}

function Set-Volume {
    param([int]$Target)
    Assert-Percent $Target "Volume"
    Add-CoreAudioType
    $before = [AudioVolume]::GetVolume()
    [AudioVolume]::SetVolume($Target)
    Start-Sleep -Milliseconds 150
    $after = [AudioVolume]::GetVolume()
    "volume: $before -> $after"
}

function Set-VolumeMute {
    param([bool]$Muted)
    Add-CoreAudioType
    $before = [AudioVolume]::GetMute()
    [AudioVolume]::SetMute($Muted)
    Start-Sleep -Milliseconds 150
    $after = [AudioVolume]::GetMute()
    "muted: $before -> $after"
}

function Set-PowerTimeout {
    param([string]$Kind, [int]$Minutes, [string]$TargetPower)
    Assert-NonNegative $Minutes "Minutes"
    $suffix = if ($Kind -eq "display") { "monitor" } else { "standby" }
    if ($TargetPower -eq "ac" -or $TargetPower -eq "both") {
        & powercfg.exe -change "-$suffix-timeout-ac" $Minutes
        "$Kind timeout AC: $Minutes minutes"
    }
    if ($TargetPower -eq "dc" -or $TargetPower -eq "both") {
        & powercfg.exe -change "-$suffix-timeout-dc" $Minutes
        "$Kind timeout DC: $Minutes minutes"
    }
}

switch ($Action) {
    "get-brightness" {
        Get-Brightness
    }
    "set-brightness" {
        if ($Value -lt 0) { throw "-Value is required for set-brightness." }
        Set-Brightness $Value
    }
    "adjust-brightness" {
        $monitors = Get-BrightnessMonitors
        $targets = @()
        foreach ($monitor in $monitors) {
            $target = [Math]::Max(0, [Math]::Min(100, ([int]$monitor.CurrentBrightness + $Delta)))
            $targets += $target
        }
        if (($targets | Select-Object -Unique).Count -eq 1) {
            Set-Brightness ([int]$targets[0])
        } else {
            $methods = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods
            for ($i = 0; $i -lt $monitors.Count; $i++) {
                $monitor = $monitors[$i]
                $target = [int]$targets[$i]
                $current = [int]$monitor.CurrentBrightness
                $method = $methods | Where-Object { $_.InstanceName -eq $monitor.InstanceName } | Select-Object -First 1
                if (-not $method) { throw "No brightness method found for $($monitor.InstanceName)." }
                Invoke-CimMethod -InputObject $method -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $target } | Out-Null
                "$($monitor.InstanceName): $current -> $target"
            }
        }
    }
    "get-volume" {
        Get-Volume
    }
    "set-volume" {
        if ($Value -lt 0) { throw "-Value is required for set-volume." }
        Set-Volume $Value
    }
    "adjust-volume" {
        Add-CoreAudioType
        $target = [Math]::Max(0, [Math]::Min(100, ([AudioVolume]::GetVolume() + $Delta)))
        Set-Volume $target
    }
    "mute" {
        Set-VolumeMute $true
    }
    "unmute" {
        Set-VolumeMute $false
    }
    "get-power" {
        & powercfg.exe /getactivescheme
        & powercfg.exe /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
        & powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
    }
    "set-display-timeout" {
        if ($Value -lt 0) { throw "-Value is required for set-display-timeout." }
        Set-PowerTimeout "display" $Value $Power
    }
    "set-sleep-timeout" {
        if ($Value -lt 0) { throw "-Value is required for set-sleep-timeout." }
        Set-PowerTimeout "sleep" $Value $Power
    }
    "set-power-scheme" {
        $schemeMap = @{
            "balanced" = "SCHEME_BALANCED"
            "power-saver" = "SCHEME_MIN"
            "high-performance" = "SCHEME_MAX"
        }
        $before = (& powercfg.exe /getactivescheme) -join " "
        & powercfg.exe /setactive $schemeMap[$Scheme]
        $after = (& powercfg.exe /getactivescheme) -join " "
        "power scheme: $before -> $after"
    }
}

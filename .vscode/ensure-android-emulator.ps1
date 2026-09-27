$ErrorActionPreference = "Continue"

# First available AVD is started only when no Android emulator is already online.
$emulatorId = "Pixel_7"
$timeout = [TimeSpan]::FromMinutes(3)

function Get-AndroidEmulators {
    $raw = & flutter devices --machine 2>$null | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $parsed = $raw | ConvertFrom-Json
    return @($parsed | Where-Object { $_.emulator -eq $true -and $_.targetPlatform -like "android*" })
}

$devices = Get-AndroidEmulators
if ($devices.Count -eq 0) {
    Write-Host "Starting Android emulator $emulatorId ..."
    & flutter emulators --launch $emulatorId
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $deadline = (Get-Date).Add($timeout)
    do {
        Start-Sleep -Seconds 3
        $devices = Get-AndroidEmulators
    } while ($devices.Count -eq 0 -and (Get-Date) -lt $deadline)
}

if ($devices.Count -eq 0) {
    Write-Error "The Android emulator did not become available within $($timeout.TotalMinutes) minutes."
    exit 1
}

$ready = $devices[0]
Write-Host "Android emulator ready: $($ready.name) ($($ready.id))"
exit 0

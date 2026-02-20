[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths,
    [switch]$RemoveOriginal,
    [switch]$NotifyWorker,
    [switch]$NoNotify,
    [ValidateSet("Jpg", "Webp")]
    [string]$Format = "Jpg",
    [ValidateRange(0, 100)]
    [int]$Quality = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
$scriptPath = $PSCommandPath

$logPath = Join-Path -Path $env:TEMP -ChildPath "png-converter-context.log"
$logMutexName = "Local\ContextConverterPngToolLog"
$notifyStateDir = Join-Path -Path $env:TEMP -ChildPath "png-converter-context-notify"
$notifyStatePath = Join-Path -Path $notifyStateDir -ChildPath "state.json"
$notifyWorkerLockPath = Join-Path -Path $notifyStateDir -ChildPath "worker.lock"
$notifyMutexName = "Local\ContextConverterPngToolNotify"

function Write-RunLog {
    param(
        [string]$Message
    )
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message

    $mutex = New-Object System.Threading.Mutex($false, $logMutexName)
    $hasLock = $false
    try {
        $hasLock = $mutex.WaitOne(3000)
        if ($hasLock) {
            [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        }
    } catch {
        # Best-effort logging only.
    } finally {
        if ($hasLock) {
            $mutex.ReleaseMutex() | Out-Null
        }
        $mutex.Dispose()
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message
    )

    if ($NoNotify) {
        return
    }

    try {
        # Most reliable in hidden/background context.
        $wshell = New-Object -ComObject WScript.Shell
        [void]$wshell.Popup($Message, 4, $Title, 64)
        return
    } catch {
        Write-RunLog "Popup notification failed: $($_.Exception.Message)"
    } finally {
        if ($wshell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshell) | Out-Null
        }
    }

    # Best-effort fallback to tray balloon.
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Message
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(3500)
        Start-Sleep -Milliseconds 1200
    } catch {
        Write-RunLog "Tray notification failed: $($_.Exception.Message)"
    } finally {
        if ($notifyIcon) {
            $notifyIcon.Dispose()
        }
    }
}

function Acquire-Mutex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $mutex = New-Object System.Threading.Mutex($false, $Name)
    $hasLock = $false

    try {
        $hasLock = $mutex.WaitOne(3000)
    } catch {
        $hasLock = $false
    }

    return [PSCustomObject]@{
        Mutex = $mutex
        HasLock = $hasLock
    }
}

function Release-Mutex {
    param(
        [Parameter(Mandatory = $true)]
        [System.Threading.Mutex]$Mutex,
        [Parameter(Mandatory = $true)]
        [bool]$HasLock
    )

    try {
        if ($HasLock) {
            $Mutex.ReleaseMutex() | Out-Null
        }
    } catch {
        # Ignore unlock failures.
    } finally {
        $Mutex.Dispose()
    }
}

function Read-NotificationState {
    $state = @{
        Converted = 0
        Removed = 0
        Failed = 0
        Active = 0
        LastUpdateUtc = [DateTime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if (Test-Path -LiteralPath $notifyStatePath) {
        try {
            $raw = Get-Content -LiteralPath $notifyStatePath -Raw -ErrorAction Stop
            if ($raw) {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $json.Converted) { $state.Converted = [int]$json.Converted }
                if ($null -ne $json.Removed) { $state.Removed = [int]$json.Removed }
                if ($null -ne $json.Failed) { $state.Failed = [int]$json.Failed }
                if ($null -ne $json.Active) { $state.Active = [int]$json.Active }
                if ($json.LastUpdateUtc) { $state.LastUpdateUtc = [string]$json.LastUpdateUtc }
            }
        } catch {
            # If state is invalid, ignore and start a fresh batch.
        }
    }

    return $state
}

function Update-NotificationState {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Converted,
        [Parameter(Mandatory = $true)]
        [int]$Removed,
        [Parameter(Mandatory = $true)]
        [int]$Failed,
        [Parameter(Mandatory = $true)]
        [int]$ActiveDelta
    )

    if ($NoNotify) {
        return
    }

    if (-not (Test-Path -LiteralPath $notifyStateDir)) {
        New-Item -ItemType Directory -Path $notifyStateDir -Force | Out-Null
    }

    $lock = Acquire-Mutex -Name $notifyMutexName
    try {
        if (-not $lock.HasLock) {
            return
        }

        $state = Read-NotificationState
        $state.Converted += $Converted
        $state.Removed += $Removed
        $state.Failed += $Failed
        $state.Active += $ActiveDelta
        if ($state.Active -lt 0) {
            $state.Active = 0
        }
        $state.LastUpdateUtc = [DateTime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)

        $json = $state | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($notifyStatePath, $json, [System.Text.Encoding]::UTF8)
    } finally {
        Release-Mutex -Mutex $lock.Mutex -HasLock $lock.HasLock
    }
}

function Ensure-NotificationWorker {
    if ($NoNotify) {
        return
    }

    if (-not (Test-Path -LiteralPath $notifyStateDir)) {
        New-Item -ItemType Directory -Path $notifyStateDir -Force | Out-Null
    }

    $lock = Acquire-Mutex -Name $notifyMutexName
    $startWorker = $false
    try {
        if (-not $lock.HasLock) {
            return
        }

        $stale = $false
        if (Test-Path -LiteralPath $notifyWorkerLockPath) {
            try {
                $age = (Get-Date) - (Get-Item -LiteralPath $notifyWorkerLockPath).LastWriteTime
                if ($age.TotalSeconds -gt 120) {
                    $stale = $true
                }
            } catch {
                $stale = $true
            }
        }

        if ($stale) {
            Remove-Item -LiteralPath $notifyWorkerLockPath -Force -ErrorAction SilentlyContinue
        }

        if (-not (Test-Path -LiteralPath $notifyWorkerLockPath)) {
            Set-Content -LiteralPath $notifyWorkerLockPath -Value ([DateTime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)) -Force
            $startWorker = $true
        }
    } finally {
        Release-Mutex -Mutex $lock.Mutex -HasLock $lock.HasLock
    }

    if (-not $startWorker) {
        return
    }

    $selfPath = $scriptPath
    if ([string]::IsNullOrWhiteSpace($selfPath)) {
        Write-RunLog "Notification worker not started: script path is unavailable."
        return
    }
    $pwsh = Get-Command -Name "pwsh.exe" -ErrorAction SilentlyContinue
    $hostExe = if ($pwsh) { $pwsh.Source } else { (Get-Command -Name "powershell.exe" -ErrorAction SilentlyContinue).Source }
    if (-not $hostExe) {
        return
    }

    $args = @(
        "-NoProfile",
        "-STA",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $selfPath,
        "-NotifyWorker"
    )

    try {
        Start-Process -FilePath $hostExe -ArgumentList $args -WindowStyle Hidden | Out-Null
        Write-RunLog "Notification worker started via $hostExe"
    } catch {
        Write-RunLog "Notification worker start failed: $($_.Exception.Message)"
        $recoverLock = Acquire-Mutex -Name $notifyMutexName
        try {
            if ($recoverLock.HasLock) {
                Remove-Item -LiteralPath $notifyWorkerLockPath -Force -ErrorAction SilentlyContinue
            }
        } finally {
            Release-Mutex -Mutex $recoverLock.Mutex -HasLock $recoverLock.HasLock
        }
    }
}

function Run-NotificationWorker {
    while ($true) {
        Start-Sleep -Seconds 2

        $lock = Acquire-Mutex -Name $notifyMutexName
        $shouldNotify = $false
        $state = $null
        try {
            if (-not $lock.HasLock) {
                continue
            }

            if (-not (Test-Path -LiteralPath $notifyStatePath)) {
                Remove-Item -LiteralPath $notifyWorkerLockPath -Force -ErrorAction SilentlyContinue
                return
            }

            $state = Read-NotificationState
            $last = [DateTime]::Parse(
                $state.LastUpdateUtc,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind
            )
            $quietSeconds = ((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalSeconds
            if ([int]$state.Active -gt 0 -or $quietSeconds -lt 2) {
                continue
            }

            Remove-Item -LiteralPath $notifyStatePath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $notifyWorkerLockPath -Force -ErrorAction SilentlyContinue
            $shouldNotify = $true
        } finally {
            Release-Mutex -Mutex $lock.Mutex -HasLock $lock.HasLock
        }

        if ($shouldNotify -and $state) {
            if ([int]$state.Failed -gt 0) {
                Show-Notification -Title "PNG Converter" -Message "Done with errors. Converted: $($state.Converted), Failed: $($state.Failed)"
            } elseif ([int]$state.Converted -gt 0) {
                Show-Notification -Title "PNG Converter" -Message "Done. Converted: $($state.Converted)"
            }
            return
        }
    }
}

if ($NotifyWorker) {
    Run-NotificationWorker
    exit 0
}

function Get-JpegCodec {
    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1

    if (-not $jpegCodec) {
        throw "JPEG encoder was not found on this system."
    }

    return $jpegCodec
}

function Save-AsJpeg {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$JpegQuality,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Imaging.ImageCodecInfo]$Codec
    )

    $source = [System.Drawing.Image]::FromFile($InputPath)
    try {
        # Flatten alpha to white because JPEG has no transparency.
        $canvas = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($canvas)
            try {
                $graphics.Clear([System.Drawing.Color]::White)
                $graphics.DrawImage($source, 0, 0, $source.Width, $source.Height)
            } finally {
                $graphics.Dispose()
            }

            $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            try {
                $qualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
                $qualityValue = [System.Int64]$JpegQuality
                $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($qualityEncoder, $qualityValue)
                $canvas.Save($OutputPath, $Codec, $encoderParams)
            } finally {
                $encoderParams.Dispose()
            }
        } finally {
            $canvas.Dispose()
        }
    } finally {
        $source.Dispose()
    }
}

function Get-MagickExe {
    $magick = Get-Command -Name "magick.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $magick) {
        throw "WebP conversion requires ImageMagick (magick.exe) in PATH."
    }
    return $magick.Source
}

function Save-AsWebp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$WebpQuality,
        [Parameter(Mandatory = $true)]
        [string]$MagickExePath
    )

    $args = @(
        $InputPath,
        "-strip",
        "-colorspace", "sRGB",
        "-depth", "8",
        "-define", "webp:method=6",
        "-define", "webp:use-sharp-yuv=true",
        "-define", "webp:alpha-quality=90",
        "-quality", [string]$WebpQuality,
        $OutputPath
    )

    & $MagickExePath @args
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed with exit code $LASTEXITCODE."
    }
}

function Resolve-InputFiles {
    param(
        [string[]]$RawPaths
    )

    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($path in $RawPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if ($path -eq "--") {
            continue
        }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "Skipping missing path: $path"
            continue
        }

        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -File -Filter "*.png" | ForEach-Object {
                $resolved.Add($_.FullName)
            }
        } else {
            $resolved.Add($item.FullName)
        }
    }

    return $resolved
}

function Remove-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $attempts = 10
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Force
            return
        } catch {
            if ($i -eq $attempts) {
                throw
            }
            Start-Sleep -Milliseconds 120
        }
    }
}

$inputFiles = @(
    Resolve-InputFiles -RawPaths $Paths |
        Where-Object { $_.ToLowerInvariant().EndsWith(".png") } |
        Select-Object -Unique
)

if (-not $inputFiles -or $inputFiles.Count -eq 0) {
    Write-RunLog "No PNG files selected."
    Write-Host "No PNG files selected."
    exit 0
}

$targetExt = if ($Format -eq "Webp") { ".webp" } else { ".jpg" }
$mode = if ($RemoveOriginal) { "convert+remove" } else { "convert" }
Write-RunLog "Started ($mode, format=$Format). Files: $($inputFiles.Count), Quality: $Quality"
Update-NotificationState -Converted 0 -Removed 0 -Failed 0 -ActiveDelta 1
Ensure-NotificationWorker
$activeRegistered = $true

$converted = 0
$removed = 0
$failed = 0

try {
    $jpegCodec = $null
    $magickExe = $null
    if ($Format -eq "Jpg") {
        $jpegCodec = Get-JpegCodec
    } else {
        $magickExe = Get-MagickExe
    }

    foreach ($file in $inputFiles) {
        try {
            $dir = [System.IO.Path]::GetDirectoryName($file)
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $outPath = [System.IO.Path]::Combine($dir, "$name$targetExt")

            if ($Format -eq "Jpg") {
                Save-AsJpeg -InputPath $file -OutputPath $outPath -JpegQuality $Quality -Codec $jpegCodec
            } else {
                Save-AsWebp -InputPath $file -OutputPath $outPath -WebpQuality $Quality -MagickExePath $magickExe
            }
            $converted++
            Write-RunLog "Converted: $file -> $outPath"
            Write-Host "Converted: $file -> $outPath"

            if ($RemoveOriginal) {
                Remove-WithRetry -Path $file
                $removed++
                Write-RunLog "Removed: $file"
                Write-Host "Removed: $file"
            }
        } catch {
            $failed++
            Write-RunLog "Failed: $file - $($_.Exception.Message)"
            Write-Warning "Failed: $file - $($_.Exception.Message)"
        }
    }
} finally {
    if ($activeRegistered) {
        Update-NotificationState -Converted $converted -Removed $removed -Failed $failed -ActiveDelta -1
        Ensure-NotificationWorker
    }
}

Write-Host ""
Write-Host "Done. Converted: $converted, Removed: $removed, Failed: $failed"
Write-RunLog "Done. Converted: $converted, Removed: $removed, Failed: $failed"

if ($failed -gt 0) {
    exit 1
}

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths,
    [switch]$RemoveOriginal,
    [switch]$NotifyWorker,
    [switch]$NoNotify,
    [ValidateSet("Jpg", "Webp", "Avif", "Png")]
    [string]$Format = "Jpg",
    [ValidateSet("Same", "New")]
    [string]$OutputMode = "Same",
    [ValidateSet("Skip", "Suffix")]
    [string]$IfExists = "Skip",
    [switch]$Overwrite,
    [switch]$UseMagickForJpg,
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
$magickMissingStampPath = Join-Path -Path $notifyStateDir -ChildPath "magick-missing.stamp"
$notifyStaleSeconds = 180

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
        Skipped = 0
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
                if ($null -ne $json.Skipped) { $state.Skipped = [int]$json.Skipped }
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
        [int]$Skipped,
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
        $state.Skipped += $Skipped
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
        $staleBatch = $false
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
            try {
                $last = [DateTime]::Parse(
                    $state.LastUpdateUtc,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                )
            } catch {
                $last = [DateTime]::UtcNow
            }
            $quietSeconds = ((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalSeconds
            if ([int]$state.Active -gt 0) {
                if ($quietSeconds -ge $notifyStaleSeconds) {
                    $activeBefore = [int]$state.Active
                    $staleBatch = $true
                    $state.Active = 0
                    Write-RunLog "Notification state marked stale after $([int]$quietSeconds)s with active=$activeBefore."
                } else {
                    continue
                }
            }

            if (-not $staleBatch -and $quietSeconds -lt 2) {
                continue
            }

            Remove-Item -LiteralPath $notifyStatePath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $notifyWorkerLockPath -Force -ErrorAction SilentlyContinue
            $shouldNotify = $true
        } finally {
            Release-Mutex -Mutex $lock.Mutex -HasLock $lock.HasLock
        }

        if ($shouldNotify -and $state) {
            if ($staleBatch) {
                Show-Notification -Title "Image Converter" -Message "Done with possible interruption. Converted: $($state.Converted), Skipped: $($state.Skipped), Failed: $($state.Failed)"
            } elseif ([int]$state.Failed -gt 0) {
                Show-Notification -Title "Image Converter" -Message "Done with errors. Converted: $($state.Converted), Skipped: $($state.Skipped), Failed: $($state.Failed)"
            } elseif ([int]$state.Converted -gt 0) {
                Show-Notification -Title "Image Converter" -Message "Done. Converted: $($state.Converted), Skipped: $($state.Skipped)"
            } elseif ([int]$state.Skipped -gt 0) {
                Show-Notification -Title "Image Converter" -Message "Done. Skipped: $($state.Skipped)"
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
        return $null
    }
    return [string]$magick.Source
}

function Show-MagickMissingOnce {
    if ($NoNotify) {
        return
    }

    if (-not (Test-Path -LiteralPath $notifyStateDir)) {
        New-Item -ItemType Directory -Path $notifyStateDir -Force | Out-Null
    }

    $shouldShow = $false
    $lock = Acquire-Mutex -Name $notifyMutexName
    try {
        if (-not $lock.HasLock) {
            return
        }

        $now = Get-Date
        $cooldownSeconds = 20
        if (Test-Path -LiteralPath $magickMissingStampPath) {
            try {
                $stampRaw = Get-Content -LiteralPath $magickMissingStampPath -Raw -ErrorAction Stop
                $stamp = [DateTime]::Parse(
                    $stampRaw,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                )
                $age = ($now.ToUniversalTime() - $stamp.ToUniversalTime()).TotalSeconds
                if ($age -lt $cooldownSeconds) {
                    return
                }
            } catch {
                # Ignore malformed stamp and show popup.
            }
        }

        [System.IO.File]::WriteAllText(
            $magickMissingStampPath,
            $now.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture),
            [System.Text.Encoding]::UTF8
        )
        $shouldShow = $true
    } finally {
        Release-Mutex -Mutex $lock.Mutex -HasLock $lock.HasLock
    }

    if ($shouldShow) {
        Show-Notification -Title "Image Converter" -Message "ImageMagick is required for WebP/AVIF and advanced transcoding.`nInstall: winget install ImageMagick.ImageMagick"
    }
}

function Resolve-OutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        [Parameter(Mandatory = $true)]
        [string]$BaseName,
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $candidate = [System.IO.Path]::Combine($DirectoryPath, "$BaseName$Extension")
    if ($Overwrite -or -not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    # Recover from broken partial outputs (e.g. zero-byte files).
    if (-not (Test-OutputFileReady -Path $candidate)) {
        return $candidate
    }

    if ($IfExists -eq "Skip") {
        return $null
    }

    $i = 1
    while ($true) {
        $suffixedName = ("{0}-{1}{2}" -f $BaseName, $i, $Extension)
        $next = [System.IO.Path]::Combine($DirectoryPath, $suffixedName)
        if (-not (Test-Path -LiteralPath $next) -or -not (Test-OutputFileReady -Path $next)) {
            return $next
        }
        $i++
    }
}

function Test-OutputFileReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return ($item.Length -gt 0)
    } catch {
        return $false
    }
}

function Save-AsJpegWithMagick {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$JpegQuality,
        [Parameter(Mandatory = $true)]
        [string]$MagickExePath
    )

    $args = @(
        $InputPath,
        "-auto-orient",
        "-strip",
        "-colorspace", "sRGB",
        "-depth", "8",
        "-quality", [string]$JpegQuality,
        $OutputPath
    )

    & $MagickExePath @args
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed with exit code $LASTEXITCODE."
    }
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
        "-auto-orient",
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

function Save-AsAvif {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$AvifQuality,
        [Parameter(Mandatory = $true)]
        [string]$MagickExePath
    )

    $args = @(
        $InputPath,
        "-auto-orient",
        "-strip",
        "-colorspace", "sRGB",
        "-depth", "8",
        "-define", "heic:speed=6",
        "-quality", [string]$AvifQuality,
        $OutputPath
    )

    & $MagickExePath @args
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed with exit code $LASTEXITCODE."
    }
}

function Save-AsPngWithMagick {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string]$MagickExePath
    )

    $args = @(
        $InputPath,
        "-auto-orient",
        "-strip",
        "-colorspace", "sRGB",
        "-depth", "8",
        "-define", "png:compression-level=9",
        $OutputPath
    )

    & $MagickExePath @args
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed with exit code $LASTEXITCODE."
    }
}

function Get-FormatFromExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    switch ($Extension.ToLowerInvariant()) {
        ".png" { return "Png" }
        ".jpg" { return "Jpg" }
        ".jpeg" { return "Jpg" }
        ".webp" { return "Webp" }
        ".avif" { return "Avif" }
        default { return $null }
    }
}

function Get-DefaultExtensionForFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFormat
    )

    switch ($TargetFormat) {
        "Png" { return ".png" }
        "Jpg" { return ".jpg" }
        "Webp" { return ".webp" }
        "Avif" { return ".avif" }
        default { throw "Unsupported target format: $TargetFormat" }
    }
}

function Test-LossyFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FormatName
    )

    return $FormatName -in @("Jpg", "Webp", "Avif")
}

function Test-LosslessFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FormatName
    )

    return $FormatName -eq "Png"
}

function Get-SupportedInputExtensions {
    return @(".png", ".jpg", ".jpeg", ".webp", ".avif")
}

function Resolve-InputFiles {
    param(
        [string[]]$RawPaths,
        [string[]]$AllowedExtensions
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
            Get-ChildItem -LiteralPath $item.FullName -File | Where-Object {
                $AllowedExtensions -contains $_.Extension.ToLowerInvariant()
            } | ForEach-Object {
                $resolved.Add($_.FullName)
            }
        } else {
            $resolved.Add($item.FullName)
        }
    }

    return $resolved
}

function Get-OutputDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFilePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetFormat
    )

    $sourceDir = [System.IO.Path]::GetDirectoryName($InputFilePath)
    if ($OutputMode -eq "Same") {
        return $sourceDir
    }

    $folderName = switch ($TargetFormat) {
        "Webp" { "WEBP" }
        "Avif" { "AVIF" }
        "Png" { "PNG" }
        default { "JPEG" }
    }
    $targetDir = Join-Path -Path $sourceDir -ChildPath $folderName
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    return $targetDir
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

$supportedExtensions = Get-SupportedInputExtensions
$inputFiles = @(
    Resolve-InputFiles -RawPaths $Paths -AllowedExtensions $supportedExtensions |
        Where-Object {
            $supportedExtensions -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant()
        } |
        Select-Object -Unique
)

if (-not $inputFiles -or $inputFiles.Count -eq 0) {
    Write-RunLog "No supported input files selected."
    Write-Host "No supported input files selected."
    exit 0
}

$targetExt = Get-DefaultExtensionForFormat -TargetFormat $Format
$mode = if ($RemoveOriginal) { "convert+remove" } else { "convert" }
$dependencyMagick = Get-MagickExe
$requiresMagickForAll = ($Format -in @("Webp", "Avif", "Png")) -or $UseMagickForJpg
if ($requiresMagickForAll -and -not $dependencyMagick) {
    $msg = "ImageMagick (magick.exe) is required for this conversion mode. Install with: winget install ImageMagick.ImageMagick"
    Write-RunLog $msg
    Show-MagickMissingOnce
    Write-Warning $msg
    exit 2
}

Write-RunLog "Started ($mode, format=$Format, outputMode=$OutputMode, ifExists=$IfExists, overwrite=$Overwrite). Files: $($inputFiles.Count), Quality: $Quality"
Update-NotificationState -Converted 0 -Removed 0 -Failed 0 -Skipped 0 -ActiveDelta 1
Ensure-NotificationWorker
$activeRegistered = $true

$converted = 0
$removed = 0
$failed = 0
$skipped = 0
$magickMissingShown = $false

try {
    $jpegCodec = $null
    $magickExe = $dependencyMagick
    if ($Format -eq "Jpg" -and -not $UseMagickForJpg) {
        $jpegCodec = Get-JpegCodec
    }

    foreach ($file in $inputFiles) {
        try {
            $sourceExt = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
            $sourceFormat = Get-FormatFromExtension -Extension $sourceExt
            if (-not $sourceFormat) {
                $skipped++
                Write-RunLog "Skipped (unsupported source): $file"
                Write-Host "Skipped (unsupported source): $file"
                continue
            }

            if ($sourceFormat -eq $Format) {
                $skipped++
                Write-RunLog "Skipped (same format): $file"
                Write-Host "Skipped (same format): $file"
                continue
            }

            if ((Test-LossyFormat -FormatName $sourceFormat) -and (Test-LosslessFormat -FormatName $Format)) {
                $skipped++
                Write-RunLog "Skipped (lossy->lossless blocked): $file"
                Write-Host "Skipped (lossy->lossless blocked): $file"
                continue
            }

            $needsMagick = $false
            switch ($Format) {
                "Jpg" {
                    $needsMagick = $UseMagickForJpg -or ($sourceFormat -in @("Webp", "Avif"))
                }
                default {
                    $needsMagick = $true
                }
            }

            if ($needsMagick -and -not $magickExe) {
                if (-not $magickMissingShown) {
                    $msg = "ImageMagick (magick.exe) is required for this conversion. Install with: winget install ImageMagick.ImageMagick"
                    Write-RunLog $msg
                    Show-MagickMissingOnce
                    Write-Warning $msg
                    $magickMissingShown = $true
                }

                $failed++
                Write-RunLog "Failed: $file - ImageMagick is not installed."
                Write-Warning "Failed: $file - ImageMagick is not installed."
                continue
            }

            $dir = Get-OutputDirectory -InputFilePath $file -TargetFormat $Format
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $outPath = Resolve-OutputPath -DirectoryPath $dir -BaseName $name -Extension $targetExt
            if (-not $outPath) {
                $skipped++
                Write-RunLog "Skipped (exists): $file"
                Write-Host "Skipped (exists): $file"
                continue
            }

            switch ($Format) {
                "Jpg" {
                    if ($needsMagick) {
                        Save-AsJpegWithMagick -InputPath $file -OutputPath $outPath -JpegQuality $Quality -MagickExePath $magickExe
                    } else {
                        Save-AsJpeg -InputPath $file -OutputPath $outPath -JpegQuality $Quality -Codec $jpegCodec
                    }
                }
                "Webp" {
                    Save-AsWebp -InputPath $file -OutputPath $outPath -WebpQuality $Quality -MagickExePath $magickExe
                }
                "Avif" {
                    Save-AsAvif -InputPath $file -OutputPath $outPath -AvifQuality $Quality -MagickExePath $magickExe
                }
                "Png" {
                    Save-AsPngWithMagick -InputPath $file -OutputPath $outPath -MagickExePath $magickExe
                }
                default {
                    throw "Unsupported target format: $Format"
                }
            }

            if (-not (Test-OutputFileReady -Path $outPath)) {
                throw "Output file is missing or empty: $outPath"
            }
            $converted++
            Write-RunLog "Converted: $file -> $outPath"
            Write-Host "Converted: $file -> $outPath"

            if ($RemoveOriginal) {
                if (-not (Test-OutputFileReady -Path $outPath)) {
                    throw "Original not removed because output is missing or empty: $outPath"
                }
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
        Update-NotificationState -Converted $converted -Removed $removed -Failed $failed -Skipped $skipped -ActiveDelta -1
        Ensure-NotificationWorker
    }
}

Write-Host ""
Write-Host "Done. Converted: $converted, Skipped: $skipped, Removed: $removed, Failed: $failed"
Write-RunLog "Done. Converted: $converted, Skipped: $skipped, Removed: $removed, Failed: $failed"

if ($failed -gt 0) {
    exit 1
}

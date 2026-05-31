# Play dahili testten kurulu uygulamanin imza SHA-1 degerini cikarir.
# Telefon: USB hata ayiklama acik, Play'den kurulu UNIQ uygulamasi yuklu.

$ErrorActionPreference = "Stop"
$package = "com.uniqperformance.mobile"

Write-Host "=== UNIQ Play imza SHA-1 ===" -ForegroundColor Cyan
Write-Host ""

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Host "adb bulunamadi. Android SDK platform-tools PATH'e ekleyin." -ForegroundColor Red
    exit 1
}

$devices = adb devices | Select-String "device$"
if (-not $devices) {
    Write-Host "Bagli telefon yok." -ForegroundColor Yellow
    Write-Host "1. Telefonda Gelistirici secenekleri > USB hata ayiklama acin"
    Write-Host "2. USB ile baglayin, 'Bu bilgisayara guven' deyin"
    Write-Host "3. Play dahili testten UNIQ uygulamasini kurun"
    Write-Host "4. Bu scripti tekrar calistirin"
    Write-Host ""
    Write-Host "Alternatif: Play'den indirdiginiz APK dosyasini bilgisayara atip:"
    Write-Host "  keytool -printcert -jarfile indirilen.apk"
    exit 2
}

$pathLines = @(adb shell pm path $package 2>$null)
if (-not $pathLines -or $pathLines.Count -eq 0) {
    Write-Host "Paket bulunamadi: $package" -ForegroundColor Red
    Write-Host "Once Play dahili test linkinden uygulamayi kurun."
    exit 3
}

$apkPath = $null
foreach ($line in $pathLines) {
    $p = ($line -replace "package:", "").Trim()
    if ($p -match "base\.apk$") {
        $apkPath = $p
        break
    }
}
if (-not $apkPath) {
    $apkPath = ($pathLines[0] -replace "package:", "").Trim()
}

$tempApk = Join-Path $env:TEMP "uniq-play-installed.apk"
Write-Host "APK kopyalaniyor: $apkPath"
adb pull $apkPath $tempApk 2>&1 | Out-Null
if (-not (Test-Path $tempApk)) {
    Write-Host "APK kopyalanamadi. USB hata ayiklama ve dosya aktarimini kontrol edin." -ForegroundColor Red
    exit 4
}

Write-Host ""
Write-Host "--- Play / kurulu surum SHA-1 (Firebase'e bunu ekleyin) ---" -ForegroundColor Green

$apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Directory.Name) } -Descending | Select-Object -First 1
if ($apksigner -and (Get-Command keytool -ErrorAction SilentlyContinue)) {
    $kt = (Get-Command keytool).Source
    $env:JAVA_HOME = Split-Path (Split-Path $kt -Parent) -Parent
    & $apksigner.FullName verify --print-certs $tempApk 2>&1 | Select-String "SHA-1 digest:|SHA-256 digest:" | Select-Object -First 2
} else {
    keytool -printcert -jarfile $tempApk 2>&1 | Select-String "SHA1:|SHA256:"
}

Write-Host ""
Write-Host "Firebase: Proje ayarlari > UNIQ Android > Parmak izi ekle > SHA-1 yapistir"
Write-Host "Sonra: google-services.json indir > android\app\ klasorune kopyala"
Write-Host "Sonra: .\scripts\build-release.ps1"

Remove-Item $tempApk -Force -ErrorAction SilentlyContinue

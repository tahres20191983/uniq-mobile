# UNIQ mobile — Windows build kilidi / ephemeral temizligi
# Kullanim: powershell -ExecutionPolicy Bypass -File .\scripts\clean-android-build.ps1

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build"
$AndroidDir = Join-Path $ProjectRoot "android"

Write-Host "Proje: $ProjectRoot"

if (Get-Command adb -ErrorAction SilentlyContinue) {
    Write-Host "Emulator uygulamasi durduruluyor..."
    adb shell am force-stop com.example.uniq_mobile 2>$null
}

if (Test-Path (Join-Path $AndroidDir "gradlew.bat")) {
    Write-Host "Gradle daemon durduruluyor..."
    Push-Location $AndroidDir
    & .\gradlew.bat --stop 2>$null
    Pop-Location
}

Get-ChildItem $ProjectRoot -Recurse -Directory -Filter "ephemeral" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "ephemeral siliniyor: $($_.FullName)"
        cmd /c "attrib -R `"$($_.FullName)\*.*`" /S /D 2>nul"
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

if (Test-Path $BuildDir) {
    Write-Host "build klasoru siliniyor..."
    Remove-Item -LiteralPath $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path $BuildDir) {
        Write-Host ""
        Write-Host "UYARI: build klasoru hala kilitli."
        Write-Host "  - Android Studio ve emulatoru kapatin"
        Write-Host "  - Calisan 'flutter run' varsa Ctrl+C ile durdurun"
        Write-Host "  - Sonra bu scripti tekrar calistirin"
        exit 1
    }
}

Write-Host "Temizlik tamam. Simdi: flutter pub get && flutter build apk --debug"
exit 0

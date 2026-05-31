# UNIQ mobil release AAB (Play dahili test icin)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$gs = "android\app\google-services.json"
if (-not (Test-Path $gs)) {
    Write-Host "HATA: $gs yok. Firebase'den indirin." -ForegroundColor Red
    exit 1
}

$json = Get-Content $gs -Raw | ConvertFrom-Json
$oauth = $json.client[0].oauth_client
if (-not $oauth -or @($oauth).Count -lt 2) {
    Write-Host "UYARI: google-services.json oauth_client eksik (Firebase indirmesi bazen bos gelir)." -ForegroundColor Yellow
    Write-Host "scripts\patch-google-services-play-sha1.ps1 ile duzeltin veya mevcut sablon dosyasini kullanin."
}
Write-Host "Surum: $((Get-Content 'pubspec.yaml' -Raw) -match 'version:\s*([^\s]+)' | Out-Null; $Matches[1])" -ForegroundColor Cyan

Write-Host "flutter clean..." -ForegroundColor Cyan
flutter clean
flutter pub get
Write-Host "flutter build appbundle --release..." -ForegroundColor Cyan
flutter build appbundle --release

$out = "build\app\outputs\bundle\release\app-release.aab"
if (Test-Path $out) {
    Write-Host ""
    Write-Host "Hazir: $((Resolve-Path $out).Path)" -ForegroundColor Green
    Write-Host "Play Console > Dahili test > yeni surum yukle > telefonda eski uygulamayi sil > yeniden kur"
} else {
    Write-Host "AAB olusturulamadi." -ForegroundColor Red
    exit 1
}

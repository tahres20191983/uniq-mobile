# Play SHA-1'i google-services.json'a ikinci Android oauth_client olarak ekler.
# Ornek: .\scripts\patch-google-services-play-sha1.ps1 -Sha1 "AA:BB:CC:..."

param(
    [Parameter(Mandatory = $true)]
    [string]$Sha1
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root "android\app\google-services.json"

$hash = ($Sha1 -replace ":", "").ToLowerInvariant()
if ($hash.Length -ne 40) {
    Write-Host "SHA-1 40 hex karakter olmali (iki nokta ust uste ile veya siz)." -ForegroundColor Red
    exit 1
}

$json = Get-Content $path -Raw | ConvertFrom-Json
$client = $json.client[0]
$androidClientId = "721753132038-36e6dd4j8srs6qmbr7u4lcqb21qor7e7.apps.googleusercontent.com"
$webClientId = "721753132038-7ouaeaqrsp91qj8bbnkcvqkmrvf7c89i.apps.googleusercontent.com"

$existing = @()
if ($client.oauth_client) { $existing = @($client.oauth_client) }

$hasHash = $false
foreach ($o in $existing) {
    if ($o.android_info -and $o.android_info.certificate_hash -eq $hash) { $hasHash = $true }
}

if (-not $hasHash) {
    $playEntry = [ordered]@{
        client_id     = $androidClientId
        client_type   = 1
        android_info  = [ordered]@{
            package_name     = "com.uniqperformance.mobile"
            certificate_hash = $hash
        }
    }
    $newList = @($existing) + @([pscustomobject]$playEntry)
    $client.oauth_client = $newList
}

# Web client yoksa ekle
$hasWeb = $false
foreach ($o in $client.oauth_client) {
    if ($o.client_type -eq 3) { $hasWeb = $true }
}
if (-not $hasWeb) {
    $client.oauth_client = @($client.oauth_client) + @([pscustomobject]@{
        client_id   = $webClientId
        client_type = 3
    })
}

$json | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
Write-Host "Guncellendi: $path" -ForegroundColor Green
Write-Host "certificate_hash eklendi: $hash"
Write-Host "Simdi: .\scripts\build-release.ps1"

# Google giris (Play dahili test) cozumu

## Sorun
- Yerel APK calisir, Play'den indirilen calismaz.
- Sebep: Play farkli sertifika ile imzalar; Firebase'de **Play SHA-1** eksik.

## Adim 1 — Play SHA-1 al (Play Console menusu gerekmez)

Telefonda **Play dahili testten** kurulu UNIQ + USB hata ayiklama:

```powershell
cd D:\work\uniq_mobile_build
.\scripts\get-play-sha1.ps1
```

Cikan **SHA1:** satirini kopyalayin.

**Telefon yoksa:** Dahili testten indirdiginiz APK'yi bilgisayara atin:

```powershell
keytool -printcert -jarfile C:\indirilen\uniq.apk
```

## Adim 2 — Firebase

1. https://console.firebase.google.com → **uniq-mobile-cf732**
2. Proje ayarlari → **UNIQ Android** → **Parmak izi ekle**
3. Adim 1'deki **SHA-1** yapistir (upload SHA ile karistirmayin)
4. **google-services.json** indir → `android\app\google-services.json` uzerine yaz

Veya script ile (SHA-1'i siz verin):

```powershell
.\scripts\patch-google-services-play-sha1.ps1 -Sha1 "XX:XX:..."
```

## Adim 3 — Build ve Play

```powershell
.\scripts\build-release.ps1
```

- `build\app\outputs\bundle\release\app-release.aab` → Dahili teste yukle
- Telefonda uygulamayi **sil** → Play'den **yeniden kur**

## Parmak izleri (telefondan okundu)

| Imza | SHA-1 |
|------|--------|
| Upload (yerel APK) | `72:7B:63:26:AC:FA:E4:12:D8:1E:FF:E8:D7:A8:53:D7:A8:61:C8:E4` |
| **Play (dahili test)** | **`01:AE:2D:2C:60:44:B0:0D:A3:EB:7D:9F:8C:4A:8D:29:77:07:AE:70`** |

Firebase'e **Play SHA-1** mutlaka eklenmeli (ikisi farkli).

## Google Cloud (istege bagli)

https://console.cloud.google.com/apis/credentials?project=uniq-mobile-cf732

Android client `...36e6dd4j8...` → Play SHA-1 burada da listelenmeli.

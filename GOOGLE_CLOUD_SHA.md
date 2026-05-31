# Google giris hala basarisizsa (Firebase yetmez)

Firebase'e SHA eklediniz ama hata suruyorsa **Google Cloud Console** tarafinda Android OAuth istemcisine de eklemeniz gerekir.

## Link

https://console.cloud.google.com/apis/credentials?project=uniq-mobile-cf732

## Google Cloud: tek alana tek SHA-1 (normal)

Ayni Android istemcisine **iki SHA-1 kutusu yok**. Cozum: **iki ayri Android istemcisi** (sizde zaten var).

| Istemci adi | SHA-1 | Kim icin |
|-------------|--------|----------|
| **UNIQ Android (Mobile)** | `72:7B:63:26:AC:FA:E4:12:D8:1E:FF:E8:D7:A8:53:D7:A8:61:C8:E4` | Yerel / upload APK |
| **uniq mobile play** | `01:AE:2D:2C:60:44:B0:0D:A3:EB:7D:9F:8C:4A:8D:29:77:07:AE:70` | Play dahili test |

Her ikisinde de package: `com.uniqperformance.mobile`

## google-services.json (iki farkli client id)

Play istemcisinin **tam Client ID**'sini kopyalayin (uniq mobile play satiri), sonra:

```cmd
cd /d D:\work\uniq_mobile_build
powershell -ExecutionPolicy Bypass -File .\scripts\set-google-services-two-clients.ps1 -PlayClientId "BURAYA_TAM_CLIENT_ID.apps.googleusercontent.com"
scripts\build-release.bat
```

5. 15-30 dakika bekleyin, AAB yukleyin, uygulamayi silip yeniden kurun

## OAuth consent screen

https://console.cloud.google.com/apis/credentials/consent?project=uniq-mobile-cf732

- Durum **Testing** ise giris yapacak Gmail **Test users** listesinde olmali.

## API'ler

https://console.cloud.google.com/apis/library?project=uniq-mobile-cf732

- **Google Sign-In API** veya **Google Identity** etkin olsun.

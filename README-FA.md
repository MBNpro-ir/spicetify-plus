# Spicetify Plus

Spicetify Plus یک wrapper منویی برای ویندوز است که کار با Spicetify CLI، Marketplace، themeها، extensionها و custom appها را ساده‌تر می‌کند. این پروژه fork منطق داخلی Spicetify نیست؛ ابزارهای رسمی upstream را اجرا می‌کند و فهرست منابع را در `spicetify-plus.catalog.json` نگه می‌دارد.

نسخه فعلی پروژه: `2.0.0`

زبان: [English](README.md) | [فارسی](README-FA.md)

## چه چیزهایی را مدیریت می‌کند

- نصب، به‌روزرسانی و حذف تاییدشده Spotify.
- نصب/به‌روزرسانی Spicetify CLI از asset واقعی آخرین release ویندوز.
- نصب Spicetify Marketplace از release رسمی Marketplace.
- extensionهای رسمی از مسیر `spicetify/cli/Extensions`.
- custom appهای رسمی از مسیر `spicetify/cli/CustomApps`: `lyrics-plus`، `new-releases` و `reddit`.
- themeهای رسمی از `spicetify/spicetify-themes`، فقط وقتی `color.ini` و `user.css` معتبر داشته باشند.
- community appهایی که در `spicetify-plus.catalog.json` تعریف شده‌اند.

برنامه `betterLibrary` به دلیل archived بودن repo upstream با وضعیت `Deprecated` نگه داشته شده است.

## فایل‌ها

- `spicetify-plus.ps1`: اسکریپت اصلی PowerShell.
- `spicetify-plus.exe`: فایل اجرایی ساخته‌شده از اسکریپت.
- `spicetify-plus.catalog.json`: catalog منابع رسمی و community.
- `tools/refresh-upstream.ps1`: clone/update کردن repoهای reference.
- `tools/build-exe.ps1`: ساخت `spicetify-plus.exe` با `ps2exe`.
- `.upstream/`: cloneهای محلی upstream، داخل git ذخیره نمی‌شود.
- `.tools/`: ابزارهای build محلی، داخل git ذخیره نمی‌شود.

فایل‌های JSON preset کنار پروژه در فرآیند update استفاده نمی‌شوند و خارج از scope نگه‌داری هستند.

## پیش‌نیازها

- ویندوز 10 یا 11.
- Windows PowerShell 5.1 یا جدیدتر.
- اینترنت برای GitHub، Spotify و دانلودهای upstream.
- Git، فقط برای refresh کردن `.upstream/`.

## اجرا

اجرای اسکریپت:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1
```

اجرای فایل exe:

```powershell
.\spicetify-plus.exe
```

اجرای تست read-only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1 -SelfTest -NoPause
```

استفاده از مسیر دلخواه برای referenceهای upstream:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1 -SelfTest -NoPause -UpstreamRoot .upstream
```

## منوها

منوی اصلی:

1. Install Spotify
2. Update Spotify
3. Remove Spotify
4. Install Spicetify
5. Install Spicetify Marketplace
6. Update Spicetify
7. Spicetify Settings
8. Remove Spicetify
9. GitHub API Token Settings
10. Run Self Test

منوی تنظیمات شامل backup/apply، auto، restore، refresh، developer tools، مدیریت extension/app/theme، تنظیمات config، نمایش read-only launch flagها، نمایش مسیرها، self-test، refresh upstream، پاک‌کردن backup، block/unblock آپدیت Spotify، refresh/watch پیشرفته، مدیریت رنگ‌های theme و بازکردن config directory است.

## Refresh کردن referenceهای upstream

برای clone یا update کردن repoهای reference:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\refresh-upstream.ps1
```

repoهای بزرگ mirror/archive به‌صورت پیش‌فرض skip می‌شوند تا clone طولانی و گیرکردن رخ ندهد:

- `spicetify/winget-pkgs`
- `spicetify/xpui-archive`
- `spicetify/pkgs`
- `spicetify/classmaps`

برای دریافت آن‌ها:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\refresh-upstream.ps1 -IncludeLargeMirrors
```

## ساخت exe

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-exe.ps1
```

اسکریپت build اگر `Invoke-PS2EXE` موجود باشد از همان استفاده می‌کند، وگرنه module `ps2exe` را داخل `.tools/` دانلود می‌کند.

## نکات ایمنی

- `-SelfTest` فقط read-only است و نصب، apply، backup، restore یا تغییر config انجام نمی‌دهد.
- تغییرات config فقط از مسیر `spicetify config` انجام می‌شود.
- حذف Spotify و cleanup فقط با تایید صریح اجرا می‌شود.
- مسیر ذخیره GitHub token برای سازگاری با نسخه قبلی حفظ شده است.

## snapshot بررسی‌شده

در آخرین بررسی 2026-07-01:

- آخرین release برای `spicetify/cli` برابر `v2.43.2` resolve شد.
- آخرین release برای Marketplace برابر `v1.0.8` resolve شد.
- extensionهای رسمی از repo CLI خوانده می‌شوند.
- themeهای رسمی محلی با وجود `color.ini` و `user.css` معتبر شناخته می‌شوند.

برای گرفتن وضعیت تازه روی سیستم خودتان `-SelfTest` را اجرا کنید.

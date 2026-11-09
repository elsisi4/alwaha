# يبني ملفي APK (المندوب والإدارة) ويضعهما في مجلد release بأسماء تحمل رقم الإصدار.
# الاستخدام من جذر المشروع:
#   powershell -File tool/build_release.ps1                 (الاثنان)
#   powershell -File tool/build_release.ps1 -App distributor
param([ValidateSet("both", "distributor", "admin")][string]$App = "both")
$ErrorActionPreference = "Stop"

$pubspec = Get-Content pubspec.yaml -Raw
if ($pubspec -notmatch 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
  throw "لم أجد السطر version: x.y.z+n في pubspec.yaml"
}
$versionName = $Matches[1]
$buildNumber = $Matches[2]
New-Item -ItemType Directory -Force release | Out-Null

function Build-App([string]$flavor, [string]$entry) {
  Write-Host "== بناء $flavor ($versionName+$buildNumber) =="
  flutter build apk --release --flavor $flavor -t $entry --dart-define-from-file=env.json
  if ($LASTEXITCODE -ne 0) { throw "فشل بناء $flavor" }
  $source = "build\app\outputs\flutter-apk\app-$flavor-release.apk"
  $target = "release\alwaha-$flavor-$versionName-b$buildNumber.apk"
  Copy-Item $source $target -Force
  Write-Host "تم: $target"
}

if ($App -eq "both" -or $App -eq "distributor") { Build-App "distributor" "lib/main_distributor.dart" }
if ($App -eq "both" -or $App -eq "admin") { Build-App "admin" "lib/main_admin.dart" }
Write-Host ""
Write-Host "الخطوة التالية: ارفع الملفات من مجلد release إلى Supabase > Storage > releases،"
Write-Host "ثم انشر الإصدار من تطبيق الإدارة: الإعدادات > إصدارات التطبيق."

import 'dart:io';

/// يجهّز مشروع الأندرويد لتطبيقين (المندوب والإدارة) بمعرّفين مختلفين حتى
/// يُثبّتا معًا على الهاتف، ويضيف إذن الإنترنت (ضروري لنسخة release).
/// آمن للتشغيل أكثر من مرة، ويحفظ نسخة .bak من كل ملف يعدّله.
///
/// الاستخدام (من جذر المشروع): dart run tool/setup_android.dart
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (!manifest.existsSync() || (!kts.existsSync() && !groovy.existsSync())) {
    stderr.writeln(
      'لم أجد مجلد android. شغّل أولًا: flutter create --platforms android,web .',
    );
    exit(1);
  }
  _patchManifest(manifest);
  if (kts.existsSync()) {
    _patchGradle(kts, _ktsFlavors);
  } else {
    _patchGradle(groovy, _groovyFlavors);
  }
  stdout.writeln('تم التجهيز. الخطوة التالية: powershell -File tool/build_release.ps1');
}

void _patchManifest(File file) {
  final original = file.readAsStringSync();
  var text = original;
  if (!text.contains('android.permission.INTERNET')) {
    final start = text.indexOf('<manifest');
    final end = start < 0 ? -1 : text.indexOf('>', start);
    if (end < 0) {
      stderr.writeln('تعذر تعديل AndroidManifest.xml (لم أجد وسم manifest).');
      exit(1);
    }
    text = '${text.substring(0, end + 1)}\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>'
        '${text.substring(end + 1)}';
  }
  text = text.replaceFirst(
    RegExp(r'android:label="[^"]*"'),
    'android:label="@string/app_name"',
  );
  if (text == original) {
    stdout.writeln('AndroidManifest.xml جاهز مسبقًا.');
    return;
  }
  File('${file.path}.bak').writeAsStringSync(original);
  file.writeAsStringSync(text);
  stdout.writeln('تم تعديل AndroidManifest.xml');
}

void _patchGradle(File file, String block) {
  final text = file.readAsStringSync();
  if (text.contains('productFlavors')) {
    stdout.writeln('${file.path} جاهز مسبقًا.');
    return;
  }
  final match = RegExp(r'^[ \t]*buildTypes\s*\{', multiLine: true).firstMatch(text);
  if (match == null) {
    stderr.writeln('لم أجد buildTypes في ${file.path}. أرسل لي الملف لأعدله لك.');
    exit(1);
  }
  File('${file.path}.bak').writeAsStringSync(text);
  file.writeAsStringSync(
    '${text.substring(0, match.start)}$block\n${text.substring(match.start)}',
  );
  stdout.writeln('تم تعديل ${file.path}');
}

const _ktsFlavors = '''    flavorDimensions += "app"
    productFlavors {
        create("distributor") {
            dimension = "app"
            applicationId = "com.alwaha.distributor"
            resValue("string", "app_name", "الواحة - المندوب")
        }
        create("admin") {
            dimension = "app"
            applicationId = "com.alwaha.admin"
            resValue("string", "app_name", "الواحة - الإدارة")
        }
    }
''';

const _groovyFlavors = '''    flavorDimensions "app"
    productFlavors {
        distributor {
            dimension "app"
            applicationId "com.alwaha.distributor"
            resValue "string", "app_name", "الواحة - المندوب"
        }
        admin {
            dimension "app"
            applicationId "com.alwaha.admin"
            resValue "string", "app_name", "الواحة - الإدارة"
        }
    }
''';

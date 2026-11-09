import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

bool get _supportsApkUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// يسأل Supabase عن أحدث إصدار منشور لهذا التطبيق (`distributor` أو `admin`)،
/// ويعرض نافذة تحديث إن كان أحدث من المثبّت. أي فشل هنا لا يمنع استخدام التطبيق.
Future<void> checkForUpdate(String app) async {
  if (!_supportsApkUpdate) return;
  try {
    final info = await PackageInfo.fromPlatform();
    final installedCode = int.tryParse(info.buildNumber) ?? 0;
    final rows = (await Supabase.instance.client
        .rpc('get_latest_release', params: {'p_app': app})) as List;
    if (rows.isEmpty) return;
    final latest = rows.first as Map<String, dynamic>;
    if ((latest['version_code'] as int) <= installedCode) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final mandatory = latest['is_required'] == true;
    final notes = (latest['notes'] as String?)?.trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: !mandatory,
      builder: (dialogContext) => PopScope(
        canPop: !mandatory,
        child: AlertDialog(
          title: const Text('يتوفر تحديث جديد'),
          content: Text(
            'الإصدار ${latest['version_name']} متاح، والمثبّت عندك '
            '${info.version} (${info.buildNumber}).'
            '${notes == null || notes.isEmpty ? '' : '\n\n$notes'}'
            '${mandatory ? '\n\nهذا التحديث إلزامي.' : ''}',
          ),
          actions: [
            if (!mandatory)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('لاحقًا'),
              ),
            FilledButton(
              onPressed: () => launchUrl(
                Uri.parse(latest['apk_url'] as String),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('تحديث الآن'),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    // التحقق من التحديث اختياري ولا يعطل التطبيق.
  }
}

/// رقم الإصدار المثبّت، ليعرف المختبر أي نسخة يجرب.
class VersionLabel extends StatelessWidget {
  const VersionLabel({super.key});

  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          if (info == null) return const SizedBox.shrink();
          return Text(
            'الإصدار ${info.version} (${info.buildNumber})',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      );
}

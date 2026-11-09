import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// نشر إصدار جديد من تطبيق الأندرويد: ارفع ملف APK في Supabase ← Storage ←
/// releases، ثم الصق رابطه هنا. التطبيقات المثبتة تعرض نافذة التحديث تلقائيًا.
class AppReleasesPage extends StatefulWidget {
  const AppReleasesPage({super.key});

  @override
  State<AppReleasesPage> createState() => _AppReleasesPageState();
}

class _AppReleasesPageState extends State<AppReleasesPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  String _app = 'distributor';
  bool _mandatory = false;
  bool _busy = false;
  String? _message;
  late Future<List<Map<String, dynamic>>> _releases;

  @override
  void initState() {
    super.initState();
    _releases = _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = (await Supabase.instance.client
        .rpc('admin_list_app_releases')) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  void _reload() {
    setState(() {
      _releases = _load();
    });
  }

  Future<void> _publish() async {
    final code = int.tryParse(_code.text.trim());
    final url = _url.text.trim();
    if (code == null ||
        code <= 0 ||
        _name.text.trim().isEmpty ||
        !url.startsWith('https://') ||
        !url.toLowerCase().contains('.apk')) {
      setState(() => _message =
          'أكمل رقم الإصدار واسمه ورابط ملف APK (يبدأ بـ https وينتهي بـ .apk).');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.rpc('publish_app_release', params: {
        'p_app': _app,
        'p_version_code': code,
        'p_version_name': _name.text.trim(),
        'p_apk_url': url,
        'p_notes': _notes.text.trim(),
        'p_is_required': _mandatory,
      });
      _code.clear();
      _name.clear();
      _url.clear();
      _notes.clear();
      if (mounted) setState(() => _message = 'تم نشر الإصدار.');
      _reload();
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر النشر: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _appLabel(String app) => app == 'admin' ? 'تطبيق الإدارة' : 'تطبيق المندوب';

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'ارفع ملف APK في Supabase ← Storage ← releases، ثم انسخ رابطه العام والصقه هنا. '
            'رقم الإصدار (build number) يجب أن يكون أكبر من آخر رقم منشور.',
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _app,
            decoration: const InputDecoration(labelText: 'التطبيق'),
            items: const [
              DropdownMenuItem(value: 'distributor', child: Text('تطبيق المندوب')),
              DropdownMenuItem(value: 'admin', child: Text('تطبيق الإدارة')),
            ],
            onChanged: (value) => setState(() => _app = value ?? 'distributor'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'رقم الإصدار (الرقم بعد + في pubspec)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم الإصدار (مثل 1.0.1)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'رابط ملف APK'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ما الذي تغيّر؟ (اختياري)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تحديث إلزامي'),
            subtitle: const Text('لا يستطيع المستخدم تجاوز النافذة'),
            value: _mandatory,
            onChanged: (value) => setState(() => _mandatory = value),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_message!),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.system_update),
            label: Text(_busy ? 'جارٍ النشر...' : 'نشر الإصدار'),
          ),
          const Divider(height: 32),
          Text('آخر الإصدارات', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _releases,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('تعذر تحميل الإصدارات: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final releases = snapshot.data!;
              if (releases.isEmpty) {
                return const ListTile(title: Text('لا توجد إصدارات منشورة بعد.'));
              }
              return Column(
                children: releases
                    .map((release) => ListTile(
                          dense: true,
                          title: Text(
                            '${_appLabel(release['app'] as String)} — ${release['version_name']} (${release['version_code']})',
                          ),
                          subtitle: Text(
                            '${release['created_at']}'.split('T').first +
                                (release['is_required'] == true ? ' — إلزامي' : ''),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      );
}

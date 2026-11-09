import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// طلبات تسجيل المناديب: المدير يوافق فيُنشأ المندوب ويُربط بمنفذه، أو يرفض.
class SignupRequestsPage extends StatefulWidget {
  const SignupRequestsPage({super.key});

  @override
  State<SignupRequestsPage> createState() => _SignupRequestsPageState();
}

class _SignupRequestsPageState extends State<SignupRequestsPage> {
  late Future<List<Map<String, dynamic>>> _requests;

  @override
  void initState() {
    super.initState();
    _requests = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = (await Supabase.instance.client
        .rpc('admin_list_signup_requests')) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  void _reload() {
    setState(() {
      _requests = _load();
    });
  }

  Future<void> _act(
    String function,
    Map<String, dynamic> params,
    String success,
  ) async {
    try {
      await Supabase.instance.client.rpc(function, params: params);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $error')));
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: Text(
          'سيُحذف طلب ${request['full_name']} ويمكنه التسجيل من جديد. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('رفض وحذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _act(
      'reject_distributor_signup',
      {'p_user_id': request['user_id']},
      'تم رفض الطلب.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تعذر تحميل الطلبات: ${snapshot.error}'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: requests.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('لا توجد طلبات تسجيل جديدة.')),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['full_name'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text('الهاتف: ${request['phone'] ?? '-'}'),
                            Text('المنفذ: ${request['outlet_name']}'),
                            const SizedBox(height: 10),
                            OverflowBar(
                              spacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: () => _act(
                                    'approve_distributor_signup',
                                    {'p_user_id': request['user_id']},
                                    'تمت الموافقة وأصبح المندوب نشطًا.',
                                  ),
                                  child: const Text('موافقة'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _reject(request),
                                  child: const Text('رفض'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

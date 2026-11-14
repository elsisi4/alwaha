import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/alwaha_theme.dart';
import '../theme/glass_widgets.dart';

/// الحسابات حسب المنفذ: تبويب لكل منفذ (أم بيومي، بهتيم، المصنع، وأي منفذ جديد)
/// برقم مجمّع للمنفذ، وتحته مناديب المنفذ وكل واحد بحسابه.
class OutletAccountsPage extends StatefulWidget {
  const OutletAccountsPage({this.canRecordPayments = true, super.key});

  /// المدير والمحاسب فقط يسجلان التحصيل ودفعات المنافذ.
  final bool canRecordPayments;

  @override
  State<OutletAccountsPage> createState() => _OutletAccountsPageState();
}

class _AccountsData {
  const _AccountsData(this.outlets, this.accounts);

  final List<Map<String, dynamic>> outlets;
  final List<Map<String, dynamic>> accounts;
}

class _OutletAccountsPageState extends State<OutletAccountsPage> {
  static final _money = NumberFormat('#,##0.00', 'en_US');
  late Future<_AccountsData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_AccountsData> _load() async {
    final client = Supabase.instance.client;
    final outlets = (await client.from('role_outlet_account_summary').select())
        .cast<Map<String, dynamic>>()
        .toList();
    final accounts = (await client
            .from('role_outlet_distributor_accounts')
            .select()
            .order('distributor_name'))
        .cast<Map<String, dynamic>>();
    // المنافذ الخارجية أولًا بالترتيب الأبجدي، ثم منفذ المصنع.
    outlets.sort((a, b) {
      final aFactory = a['outlet_type'] == 'factory_pickup' ? 1 : 0;
      final bFactory = b['outlet_type'] == 'factory_pickup' ? 1 : 0;
      if (aFactory != bFactory) return aFactory.compareTo(bFactory);
      return (a['external_outlet_name'] as String)
          .compareTo(b['external_outlet_name'] as String);
    });
    return _AccountsData(outlets, accounts);
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  String _fmt(Object? value) => _money.format((value as num?) ?? 0);

  Future<double?> _askAmount(String title) => showDialog<double>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ (جنيه)'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(controller.text.trim());
                  if (amount != null && amount > 0) {
                    Navigator.pop(context, amount);
                  }
                },
                child: const Text('تسجيل'),
              ),
            ],
          );
        },
      );

  Future<void> _run(Future<dynamic> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر التنفيذ: $error')));
    }
  }

  Future<void> _payDistributor(Map<String, dynamic> account) async {
    final amount = await _askAmount('تحصيل من ${account['distributor_name']}');
    if (amount == null) return;
    await _run(
      () => Supabase.instance.client.rpc('record_distributor_payment', params: {
        'p_distributor_id': account['distributor_id'],
        'p_external_outlet_id': account['external_outlet_id'],
        'p_amount': amount,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
      }),
      'تم تسجيل التحصيل.',
    );
  }

  Future<void> _payOutlet(Map<String, dynamic> summary) async {
    final amount =
        await _askAmount('دفعة ${summary['external_outlet_name']} للمصنع');
    if (amount == null) return;
    await _run(
      () => Supabase.instance.client.rpc('record_outlet_payment', params: {
        'p_external_outlet_id': summary['external_outlet_id'],
        'p_amount': amount,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
      }),
      'تم تسجيل دفعة المنفذ.',
    );
  }

  String _vehicle(String? group) => switch (group) {
        'vehicle_1' => 'السيارة الأولى',
        'vehicle_2' => 'السيارة الثانية',
        _ => 'مشترك',
      };

  Widget _line(String label, Object? value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: strong ? Colors.white : AlwahaColors.textMuted,
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
            ),
            Text(
              _fmt(value),
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                fontSize: strong ? 16 : 14,
              ),
            ),
          ],
        ),
      );

  Widget _outletTab(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> accounts,
  ) {
    final isFactory = summary['outlet_type'] == 'factory_pickup';
    final accent = isFactory ? AlwahaColors.gold : AlwahaColors.teal;
    final credits = (summary['distributors_credits'] as num?) ?? 0;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          GlowCard(
            accent: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي المستحق على المناديب',
                    style: TextStyle(color: AlwahaColors.textMuted)),
                Text(
                  '${_fmt(summary['distributors_balance'])} جنيه',
                  style: TextStyle(
                    color: accent,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _line('مبيعات المناديب (المسلّمة)', summary['distributors_sales']),
                _line('المحصّل من المناديب', summary['distributors_paid']),
                if (credits > 0)
                  _line('مرتجعات معتمدة (تعويض)', summary['distributors_credits']),
                if (!isFactory) ...[
                  const Divider(height: 24),
                  Text('حساب المنفذ مع المصنع',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  _line('بضاعة المنفذ بسعر شرائه', summary['purchased_from_factory']),
                  _line('المدفوع للمصنع', summary['paid_to_factory']),
                  _line('المتبقي على المنفذ', summary['outlet_balance'],
                      strong: true),
                  if (widget.canRecordPayments) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _payOutlet(summary),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('تسجيل دفعة المنفذ للمصنع'),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.groups_outlined),
              title: Text('المناديب (${accounts.length})'),
              children: accounts.isEmpty
                  ? const [ListTile(title: Text('لا يوجد مناديب مرتبطون بهذا المنفذ بعد.'))]
                  : accounts
                      .map((account) => ListTile(
                            title: Text(account['distributor_name'] as String),
                            subtitle: Text(
                              '${_vehicle(account['vehicle_group'] as String?)} — '
                              'مبيعات ${_fmt(account['sales_total'])} — '
                              'محصّل ${_fmt(account['payments_total'])}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _fmt(account['balance']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                                if (widget.canRecordPayments)
                                  IconButton(
                                    tooltip: 'تسجيل تحصيل',
                                    onPressed: () => _payDistributor(account),
                                    icon: const Icon(Icons.add_card),
                                  ),
                              ],
                            ),
                          ))
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AccountsData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعذر تحميل الحسابات: ${snapshot.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _reload, child: const Text('إعادة المحاولة')),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.outlets.isEmpty) {
            return const Center(child: Text('لا توجد منافذ مسجلة بعد.'));
          }
          return DefaultTabController(
            length: data.outlets.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: data.outlets.length > 3,
                  tabs: data.outlets
                      .map((outlet) => Tab(
                            text: 'حساب ${outlet['external_outlet_name']}',
                          ))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: data.outlets
                        .map((outlet) => _outletTab(
                              outlet,
                              data.accounts
                                  .where((account) =>
                                      account['external_outlet_id'] ==
                                      outlet['external_outlet_id'])
                                  .toList(),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

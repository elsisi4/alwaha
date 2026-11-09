import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/operational_workflows_page.dart';

class RoleHomePage extends StatefulWidget {
  const RoleHomePage({required this.role, this.embedded = false, super.key});

  final String role;

  /// عند true تُعرض الشاشة داخل تبويب بدون شريط عنوان خاص بها.
  final bool embedded;

  @override
  State<RoleHomePage> createState() => _RoleHomePageState();
}

class _RoleHomePageState extends State<RoleHomePage> {
  late Future<_PortalData> _data;
  String _vehicleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<_PortalData> _load() async {
    final client = Supabase.instance.client;
    final profile = await client
        .from('user_profiles')
        .select('distributor_id, external_outlet_id, pickup_location_id')
        .eq('user_id', client.auth.currentUser!.id)
        .single();
    final distributorId = profile['distributor_id'] as String?;
    final outletId = profile['external_outlet_id'] as String?;
    final pickupLocationId = profile['pickup_location_id'] as String?;

    if (widget.role == 'distributor') {
      final results = await Future.wait<dynamic>([
        _loadSales(financial: true, distributorId: distributorId),
        client
            .from('operational_distributor_account_balances')
            .select()
            .eq('distributor_id', distributorId!)
            .single(),
      ]);
      return _PortalData(
        title: 'طلباتي وحسابي',
        sales: results[0] as List<Map<String, dynamic>>,
        balances: [results[1] as Map<String, dynamic>],
        financial: true,
      );
    }

    if (widget.role == 'outlet_manager' || widget.role == 'collector') {
      final links = (await client
              .from('role_outlet_distributors')
              .select('distributor_id, distributor_name, vehicle_group'))
          .cast<Map<String, dynamic>>();
      final distributors = links
          .map((row) => <String, dynamic>{
                'id': row['distributor_id'],
                'name': row['distributor_name'],
                'vehicle_group': row['vehicle_group'],
              })
          .toList();
      final sales = widget.role == 'outlet_manager'
          ? await _loadSales(financial: true, outletId: outletId)
          : <Map<String, dynamic>>[];
      final distributorBalances = distributors.isEmpty
          ? <Map<String, dynamic>>[]
          : (await client
                  .from('operational_distributor_account_balances')
                  .select()
                  .inFilter(
                      'distributor_id',
                      distributors
                          .map((item) => item['id'] as String)
                          .toList()))
              .cast<Map<String, dynamic>>();
      final outletBalances = widget.role == 'outlet_manager'
          ? [
              await client
                  .from('outlet_account_balances')
                  .select()
                  .eq('external_outlet_id', outletId!)
                  .single(),
            ]
          : <Map<String, dynamic>>[];
      return _PortalData(
        title: widget.role == 'collector' ? 'تحصيل الحسابات' : 'إدارة المنفذ',
        distributors: distributors,
        sales: sales,
        balances: outletBalances,
        distributorBalances: distributorBalances,
        outletId: outletId,
        financial: widget.role == 'outlet_manager',
      );
    }

    if (widget.role == 'accountant') {
      final results = await Future.wait([
        _loadSales(financial: true),
        client.from('operational_distributor_account_balances').select(),
        client.from('outlet_account_balances').select(),
        client.from('distributors').select('id, name').order('name'),
      ]);
      return _PortalData(
        title: 'الحسابات والحركات المالية',
        sales: results[0],
        distributors: (results[3] as List).cast<Map<String, dynamic>>(),
        distributorBalances:
            (results[1] as List).cast<Map<String, dynamic>>(),
        balances: [
          ...(results[2] as List).cast<Map<String, dynamic>>(),
          ...(results[1] as List).cast<Map<String, dynamic>>(),
        ],
        financial: true,
      );
    }

    final sales = await _loadSales(
      financial: false,
      pickupLocationId: pickupLocationId,
    );
    return _PortalData(
      title: widget.role == 'factory_outlet_manager'
          ? 'طلبات منفذ المصنع — كميات التشغيل'
          : 'متابعة طلبات الإنتاج — كميات التشغيل',
      sales: sales,
    );
  }

  Future<List<Map<String, dynamic>>> _loadSales({
    required bool financial,
    String? distributorId,
    String? outletId,
    String? pickupLocationId,
  }) async {
    final client = Supabase.instance.client;
    var request = client
        .from('role_factory_sales')
        .select(
            'id, distributor_id, pickup_location_id, external_outlet_id, sold_at');
    if (distributorId != null) {
      request = request.eq('distributor_id', distributorId);
    }
    if (outletId != null) {
      request = request.eq('external_outlet_id', outletId);
    }
    if (pickupLocationId != null) {
      request = request.eq('pickup_location_id', pickupLocationId);
    }
    final sales = (await request
            .order('sold_at', ascending: false)
            .limit(100))
        .cast<Map<String, dynamic>>();
    if (sales.isEmpty) return sales;

    final saleIds = sales.map((sale) => sale['id'] as String).toList();
    final lines = (await client
            .from(financial
                ? 'role_financial_sale_lines'
                : 'role_factory_sale_quantities')
            .select()
            .inFilter('sale_id', saleIds))
        .cast<Map<String, dynamic>>();
    final productIds =
        lines.map((line) => line['product_id'] as String).toSet().toList();
    final products = productIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('products')
                .select('id, name')
                .inFilter('id', productIds))
            .cast<Map<String, dynamic>>();
    final names = {
      for (final product in products) product['id'] as String: product['name'],
    };
    final linesBySale = <String, List<Map<String, dynamic>>>{};
    for (final line in lines) {
      line['product_name'] = names[line['product_id']];
      linesBySale
          .putIfAbsent(line['sale_id'] as String, () => [])
          .add(line);
    }
    for (final sale in sales) {
      sale['lines'] = linesBySale[sale['id']] ?? <Map<String, dynamic>>[];
    }
    return sales;
  }

  Future<void> _recordPayment(Map<String, dynamic> balance, String outletId) async {
    final amount = await showDialog<num>(
      context: context,
      builder: (_) => const _PaymentDialog(),
    );
    if (amount == null) return;
    try {
      await Supabase.instance.client.rpc('record_distributor_payment', params: {
        'p_distributor_id': balance['distributor_id'],
        'p_external_outlet_id': outletId,
        'p_amount': amount,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
      });
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل التحصيل: $error')),
        );
      }
    }
  }

  Future<void> _recordOutletPayment(Map<String, dynamic> balance) async {
    final amount = await showDialog<num>(
      context: context,
      builder: (_) => const _PaymentDialog(),
    );
    if (amount == null) return;
    try {
      await Supabase.instance.client.rpc('record_outlet_payment', params: {
        'p_external_outlet_id': balance['external_outlet_id'],
        'p_amount': amount,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
      });
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل دفعة المنفذ: $error')),
        );
      }
    }
  }

  Future<void> _recordAccountantPayment(
    Map<String, dynamic> balance,
    String distributorId,
  ) async {
    try {
      final links = (await Supabase.instance.client
              .from('distributor_outlets')
              .select('external_outlet_id, external_outlets(name)')
              .eq('distributor_id', distributorId))
          .cast<Map<String, dynamic>>();
      if (links.isEmpty) {
        throw StateError('الموزع غير مرتبط بأي منفذ استلام.');
      }
      if (!mounted) return;
      final outletId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('اختر منفذ تسجيل التحصيل'),
          children: links.map((link) {
            final outlet = link['external_outlets'] as Map<String, dynamic>;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(
                context,
                link['external_outlet_id'] as String,
              ),
              child: Text(outlet['name'] as String),
            );
          }).toList(),
        ),
      );
      if (outletId != null) await _recordPayment(balance, outletId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تجهيز التحصيل: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
          title: Text('الواحة — ${_roleName(widget.role)}'),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: FutureBuilder<_PortalData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _PortalMessage(
                text: 'تعذر تحميل بيانات الحساب: ${snapshot.error}',
                retry: _reload,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final visibleDistributors = data.distributors.where((distributor) {
              return _vehicleFilter == 'all' ||
                  distributor['vehicle_group'] == _vehicleFilter;
            }).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xff176b55), Color(0xff0d493b)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24176b55),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0x30ffffff),
                        child: Icon(Icons.spa_rounded,
                            color: Colors.white, size: 29),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الواحة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                )),
                            const SizedBox(height: 4),
                            Text(data.title,
                                style: Theme.of(context)
                                    .textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!widget.embedded)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('الطلبات والإنتاج والتسليم'),
                        ),
                        body: OperationalWorkflowsPage(role: widget.role),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.factory_outlined),
                  label: const Text('فتح دورة الطلبات والتشغيل'),
                ),
                if (data.balances.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...data.balances.map((balance) => Card(
                        child: ListTile(
                          title: Text(balance['distributor_name'] as String? ??
                              balance['external_outlet_name'] as String? ??
                              'الحساب'),
                          subtitle: Text(
                            '${balance['sales_total'] == null ? 'مشتريات المصنع' : 'إجمالي المبيعات'}: '
                            '${balance['sales_total'] ?? balance['factory_purchase_total']}'
                            ' — المدفوع: ${balance['payments_total']}'
                            '${balance['approved_return_credits'] == null ? '' : ' — أرصدة المرتجعات: ${balance['approved_return_credits']}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('الرصيد: ${balance['balance']}'),
                              if (widget.role == 'accountant' &&
                                  balance['external_outlet_id'] != null &&
                                  balance['distributor_id'] == null)
                                IconButton(
                                  tooltip: 'تسجيل دفعة من المنفذ للمصنع',
                                  onPressed: () => _recordOutletPayment(balance),
                                  icon: const Icon(Icons.payments_outlined),
                                ),
                            ],
                          ),
                        ),
                      )),
                ],
                if (data.distributors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('الموزعون المرتبطون',
                      style: Theme.of(context).textTheme.titleLarge),
                  DropdownButtonFormField<String>(
                    value: _vehicleFilter,
                    decoration:
                        const InputDecoration(labelText: 'تصفية حسب السيارة'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('جميع المندوبين')),
                      DropdownMenuItem(
                          value: 'vehicle_1',
                          child: Text('السيارة الأولى فقط')),
                      DropdownMenuItem(
                          value: 'vehicle_2',
                          child: Text('السيارة الثانية فقط')),
                      DropdownMenuItem(
                          value: 'shared',
                          child: Text('مشترك / غير محدد فقط')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _vehicleFilter = value);
                      }
                    },
                  ),
                  ...visibleDistributors.map((distributor) => ListTile(
                        title: Text(distributor['name'] as String),
                        subtitle: Text(
                            '${_vehicleLabel(distributor['vehicle_group'] as String?)}\n'
                            '${_balanceFor(data.distributorBalances, distributor['id'])}'),
                        trailing: widget.role == 'collector' ||
                                widget.role == 'accountant'
                            ? TextButton(
                                onPressed: () {
                                  final balance =
                                      _accountFor(data.distributorBalances,
                                          distributor['id']);
                                  if (balance != null &&
                                      data.outletId != null) {
                                    _recordPayment(balance, data.outletId!);
                                  } else if (balance != null &&
                                      widget.role == 'accountant') {
                                    _recordAccountantPayment(
                                      balance,
                                      distributor['id'] as String,
                                    );
                                  }
                                },
                                child: const Text('تسجيل تحصيل'),
                              )
                            : null,
                      )),
                ],
                const SizedBox(height: 16),
                Text(
                  widget.role == 'distributor'
                      ? 'طلباتي'
                      : 'الطلبات المرتبطة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (data.sales.isEmpty)
                  const ListTile(title: Text('لا توجد طلبات حتى الآن.'))
                else
                  ...data.sales.map((sale) =>
                      _SaleTile(sale: sale, financial: data.financial)),
              ],
            );
          },
        ),
      );
}

class _PortalData {
  const _PortalData({
    required this.title,
    this.sales = const [],
    this.balances = const [],
    this.distributors = const [],
    this.distributorBalances = const [],
    this.outletId,
    this.financial = false,
  });

  final String title;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> balances;
  final List<Map<String, dynamic>> distributors;
  final List<Map<String, dynamic>> distributorBalances;
  final String? outletId;
  final bool financial;
}

String _vehicleLabel(String? group) => switch (group) {
      'vehicle_1' => 'السيارة الأولى',
      'vehicle_2' => 'السيارة الثانية',
      'shared' => 'مشترك / غير محدد',
      _ => 'غير مصنف',
    };

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.financial});

  final Map<String, dynamic> sale;
  final bool financial;

  @override
  Widget build(BuildContext context) {
    final lines = (sale['lines'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final amount = financial
        ? lines.fold<num>(
            0, (total, line) => total + (line['line_total'] as num? ?? 0))
        : null;
    final soldAt = DateTime.parse(sale['sold_at'] as String).toLocal();
    return Card(
      child: ExpansionTile(
        title: Text('طلب ${DateFormat.yMd('ar').format(soldAt)}'),
        subtitle: Text(financial
            ? 'الإجمالي: $amount — ${lines.length} صنف'
            : 'الكميات التشغيلية — ${lines.length} صنف'),
        children: lines.map((line) {
          return ListTile(
            dense: true,
            title: Text(line['product_name'] as String? ?? 'صنف'),
            trailing: Text(financial
                ? '${line['quantity']} × ${line['unit_price']}'
                : 'الكمية: ${line['quantity']}'),
          );
        }).toList(),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog();

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تسجيل مبلغ التحصيل'),
        content: TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'المبلغ', errorText: _error),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final amount = num.tryParse(_amount.text.trim());
              if (amount == null || amount <= 0) {
                setState(() => _error = 'أدخل مبلغًا أكبر من صفر.');
                return;
              }
              Navigator.pop(context, amount);
            },
            child: const Text('تسجيل'),
          ),
        ],
      );
}

class _PortalMessage extends StatelessWidget {
  const _PortalMessage({required this.text, required this.retry});

  final String text;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: retry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

Map<String, dynamic>? _accountFor(
    List<Map<String, dynamic>> balances, dynamic distributorId) {
  for (final balance in balances) {
    if (balance['distributor_id'] == distributorId) return balance;
  }
  return null;
}

String _balanceFor(List<Map<String, dynamic>> balances, dynamic distributorId) {
  final balance = _accountFor(balances, distributorId);
  return balance == null ? 'لا يوجد رصيد' : 'الرصيد: ${balance['balance']}';
}

String _roleName(String role) => switch (role) {
      'distributor' => 'الموزع',
      'outlet_manager' => 'مسؤول المنفذ',
      'collector' => 'المحصل',
      'production_manager' => 'مسؤول الإنتاج',
      'factory_outlet_manager' => 'مسؤول منفذ المصنع',
      'accountant' => 'المحاسب',
      _ => role,
    };

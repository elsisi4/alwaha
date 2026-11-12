import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingPage extends StatefulWidget {
  const PricingPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends State<PricingPage> {
  late Future<_PricingData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_PricingData> _load() async {
    final client = Supabase.instance.client;
    final results = await Future.wait([
      client
          .from('pricing_policies')
          .select('''
            id, name, scope_type, customer_type_id, pickup_location_id,
            external_outlet_id,
            price_policy_versions(
              id, starts_at, created_at,
              price_policy_entries(
                product_id, sale_price, factory_purchase_price,
                distributor_sale_price, products(code, name)
              )
            )
          ''')
          .order('name'),
      client.from('products').select('id, code, name').eq('is_active', true).order('name'),
      client.from('customer_types').select('id, name').order('name'),
      client.from('pickup_locations').select('id, name').order('name'),
      client
          .from('external_outlets')
          .select('id, name, outlet_type, pickup_location_id')
          .order('name'),
      client
          .from('outlet_account_balances')
          .select('external_outlet_id, external_outlet_name, factory_purchase_total, payments_total, balance')
          .order('external_outlet_name'),
    ]);

    return _PricingData(
      policies: (results[0] as List).cast<Map<String, dynamic>>(),
      products: (results[1] as List).cast<Map<String, dynamic>>(),
      customerTypes: (results[2] as List).cast<Map<String, dynamic>>(),
      pickupLocations: (results[3] as List).cast<Map<String, dynamic>>(),
      outlets: (results[4] as List).cast<Map<String, dynamic>>(),
      outletBalances: (results[5] as List).cast<Map<String, dynamic>>(),
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _createPolicy([Map<String, dynamic>? policy]) async {
    final data = await _data;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _PolicyEditor(data: data, policy: policy),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('سياسات الأسعار'),
                actions: [
                  IconButton(
                    tooltip: 'تسجيل الخروج',
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _createPolicy(),
          icon: const Icon(Icons.add),
          label: const Text('سياسة جديدة'),
        ),
        body: FutureBuilder<_PricingData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                message: 'تعذر تحميل سياسات الأسعار: ${snapshot.error}',
                onRetry: _reload,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final policies = snapshot.data!.policies;
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                Text('الحسابات المجمعة للمنافذ',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (data.outletBalances.isEmpty)
                  const Card(child: ListTile(title: Text('لا توجد منافذ مسجلة.')))
                else
                  ...data.outletBalances.map((balance) => Card(
                        child: ListTile(
                          title: Text(balance['external_outlet_name'] as String),
                          subtitle: Text(
                            'مشتريات المصنع: ${balance['factory_purchase_total']} '
                            '— المدفوع: ${balance['payments_total']}',
                          ),
                          trailing: Text('الرصيد: ${balance['balance']}'),
                        ),
                      )),
                const SizedBox(height: 20),
                Text('السياسات السعرية',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (policies.isEmpty)
                  const Card(child: ListTile(title: Text('لا توجد سياسات سعرية بعد.')))
                else
                  ...policies.map((policy) {
                    final versions =
                        (policy['price_policy_versions'] as List? ?? [])
                            .cast<Map<String, dynamic>>()
                          ..sort((a, b) =>
                              DateTime.parse(b['starts_at'] as String)
                                  .compareTo(DateTime.parse(
                                      a['starts_at'] as String)));
                    return Card(
                      child: ExpansionTile(
                        title: Text(policy['name'] as String),
                        subtitle: Text(_scopeLabel(policy, data)),
                        trailing: IconButton(
                          tooltip: 'إضافة إصدار سعر جديد',
                          onPressed: () => _createPolicy(policy),
                          icon: const Icon(Icons.edit),
                        ),
                        children: versions.isEmpty
                            ? [
                                const ListTile(
                                    title: Text('لا توجد إصدارات أسعار.'))
                              ]
                            : versions
                                .map((version) =>
                                    _VersionTile(version: version))
                                .toList(),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      );
}

class _PricingData {
  const _PricingData({
    required this.policies,
    required this.products,
    required this.customerTypes,
    required this.pickupLocations,
    required this.outlets,
    required this.outletBalances,
  });

  final List<Map<String, dynamic>> policies;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> customerTypes;
  final List<Map<String, dynamic>> pickupLocations;
  final List<Map<String, dynamic>> outlets;
  final List<Map<String, dynamic>> outletBalances;
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.version});

  final Map<String, dynamic> version;

  @override
  Widget build(BuildContext context) {
    final startsAt = DateTime.parse(version['starts_at'] as String).toLocal();
    final entries = (version['price_policy_entries'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return ExpansionTile(
      title: Text('ساري من ${DateFormat.yMd('ar').add_Hm().format(startsAt)}'),
      subtitle: Text('${entries.length} صنف'),
      children: entries.map((entry) {
        final product = entry['products'] as Map<String, dynamic>? ?? {};
        final prices = <String>[
          if (entry['sale_price'] != null) 'بيع: ${entry['sale_price']}',
          if (entry['factory_purchase_price'] != null)
            'شراء المصنع: ${entry['factory_purchase_price']}',
          if (entry['distributor_sale_price'] != null)
            'بيع للموزع: ${entry['distributor_sale_price']}',
        ].join(' — ');
        return ListTile(
          dense: true,
          title: Text('${product['name'] ?? 'صنف'} (${product['code'] ?? '-'})'),
          trailing: Text(prices),
        );
      }).toList(),
    );
  }
}

class _PolicyEditor extends StatefulWidget {
  const _PolicyEditor({required this.data, this.policy});

  final _PricingData data;
  final Map<String, dynamic>? policy;

  @override
  State<_PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends State<_PolicyEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _prices = <String, Map<String, TextEditingController>>{};
  String _scope = 'customer_type';
  String? _targetId;
  DateTime _startsAt = DateTime.now();
  bool _saving = false;
  String? _error;

  bool get _isOutlet => _scope == 'external_outlet';

  /// واجهة واحدة للمستخدم: «منفذ» (المصنع أو أم بيومي أو بهتيم أو أي منفذ جديد)
  /// أو «نوع عميل». داخليًا: المصنع سياسة موقع استلام، والمنافذ الخارجية سياسة منفذ.
  String get _mode => _scope == 'customer_type' ? 'customer_type' : 'place';

  String? get _placeValue {
    if (_scope == 'external_outlet') return _targetId;
    if (_scope == 'pickup_location') {
      for (final outlet in widget.data.outlets) {
        if (outlet['outlet_type'] == 'factory_pickup' &&
            outlet['pickup_location_id'] == _targetId) {
          return outlet['id'] as String;
        }
      }
    }
    return null;
  }

  void _choosePlace(String? outletId) {
    if (outletId == null) return;
    final outlet =
        widget.data.outlets.firstWhere((item) => item['id'] == outletId);
    setState(() {
      if (outlet['outlet_type'] == 'factory_pickup') {
        _scope = 'pickup_location';
        _targetId = outlet['pickup_location_id'] as String?;
      } else {
        _scope = 'external_outlet';
        _targetId = outletId;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    if (policy != null) {
      _name.text = policy['name'] as String;
      _scope = policy['scope_type'] as String;
      _targetId = switch (_scope) {
        'customer_type' => policy['customer_type_id'] as String?,
        'pickup_location' => policy['pickup_location_id'] as String?,
        _ => policy['external_outlet_id'] as String?,
      };
      final versions = (policy['price_policy_versions'] as List? ?? [])
          .cast<Map<String, dynamic>>()
        ..sort((a, b) => DateTime.parse(b['starts_at'] as String)
            .compareTo(DateTime.parse(a['starts_at'] as String)));
      if (versions.isNotEmpty) {
        final entries = (versions.first['price_policy_entries'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        for (final entry in entries) {
          _prices[entry['product_id'] as String] = {
            'sale': TextEditingController(text: '${entry['sale_price'] ?? ''}'),
            'purchase': TextEditingController(
                text: '${entry['factory_purchase_price'] ?? ''}'),
            'distributor': TextEditingController(
                text: '${entry['distributor_sale_price'] ?? ''}'),
          };
        }
      }
    } else {
      _name.text = '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final fields in _prices.values) {
      for (final controller in fields.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  TextEditingController _controller(String productId, String field) =>
      _prices.putIfAbsent(productId, () => {
            'sale': TextEditingController(),
            'purchase': TextEditingController(),
            'distributor': TextEditingController(),
          })[field]!;

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (date != null) setState(() => _startsAt = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_targetId == null) {
      setState(() => _error = 'اختر نوع العميل أو المنفذ أولًا.');
      return;
    }
    final entries = <Map<String, dynamic>>[];
    for (final product in widget.data.products) {
      final id = product['id'] as String;
      final sale = _prices[id]?['sale']?.text.trim() ?? '';
      final purchase = _prices[id]?['purchase']?.text.trim() ?? '';
      final distributor = _prices[id]?['distributor']?.text.trim() ?? '';
      if (sale.isEmpty && purchase.isEmpty && distributor.isEmpty) continue;

      final saleValue = sale.isEmpty ? null : num.tryParse(sale);
      final purchaseValue = purchase.isEmpty ? null : num.tryParse(purchase);
      final distributorValue =
          distributor.isEmpty ? null : num.tryParse(distributor);
      if ((sale.isNotEmpty && saleValue == null) ||
          (purchase.isNotEmpty && purchaseValue == null) ||
          (distributor.isNotEmpty && distributorValue == null) ||
          (saleValue != null && saleValue < 0) ||
          (purchaseValue != null && purchaseValue < 0) ||
          (distributorValue != null && distributorValue < 0)) {
        setState(() => _error = 'تحقق من الأسعار المدخلة؛ يجب أن تكون أرقامًا غير سالبة.');
        return;
      }
      entries.add({
        'product_id': id,
        'sale_price': saleValue,
        'factory_purchase_price': purchaseValue,
        'distributor_sale_price': distributorValue,
      });
    }
    if (entries.isEmpty) {
      setState(() => _error = 'أدخل سعرًا لصنف واحد على الأقل.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('save_pricing_policy', params: {
        'p_policy_id': widget.policy?['id'],
        'p_name': _name.text.trim(),
        'p_scope_type': _scope,
        'p_customer_type_id':
            _scope == 'customer_type' ? _targetId : null,
        'p_pickup_location_id':
            _scope == 'pickup_location' ? _targetId : null,
        'p_external_outlet_id':
            _scope == 'external_outlet' ? _targetId : null,
        'p_starts_at': _startsAt.toUtc().toIso8601String(),
        'p_prices': entries,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => _error = 'تعذر حفظ السياسة: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.policy == null ? 'إنشاء سياسة سعرية' : 'إصدار أسعار جديد'),
        content: SizedBox(
          width: 720,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم السياسة'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'تطبيق السياسة على'),
                  items: const [
                    DropdownMenuItem(
                        value: 'place',
                        child: Text('منفذ (المصنع، أم بيومي، بهتيم)')),
                    DropdownMenuItem(
                        value: 'customer_type',
                        child: Text('نوع عميل (سعر عام)')),
                  ],
                  onChanged: widget.policy == null
                      ? (value) => setState(() {
                            _scope = value == 'customer_type'
                                ? 'customer_type'
                                : 'external_outlet';
                            _targetId = null;
                          })
                      : null,
                ),
                const SizedBox(height: 12),
                if (_mode == 'customer_type')
                  DropdownButtonFormField<String>(
                    key: const ValueKey('target-customer-type'),
                    value: widget.data.customerTypes
                            .any((item) => item['id'] == _targetId)
                        ? _targetId
                        : null,
                    decoration: const InputDecoration(labelText: 'نوع العميل'),
                    items: widget.data.customerTypes
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ))
                        .toList(),
                    onChanged: widget.policy == null
                        ? (value) => setState(() => _targetId = value)
                        : null,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('target-place'),
                    value: _placeValue,
                    decoration: const InputDecoration(labelText: 'المنفذ'),
                    items: widget.data.outlets
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ))
                        .toList(),
                    onChanged: widget.policy == null ? _choosePlace : null,
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _chooseDate,
                  icon: const Icon(Icons.event),
                  label: Text(
                      'تاريخ بدء التطبيق: ${DateFormat.yMd('ar').format(_startsAt)}'),
                ),
                const SizedBox(height: 12),
                Text(_isOutlet
                    ? 'أسعار المنفذ: سعر شرائه من المصنع وسعر بيعه للمناديب'
                    : (_scope == 'pickup_location'
                        ? 'سعر بيع المصنع للمناديب المستلمين منه مباشرة'
                        : 'سعر البيع العام لنوع العميل')),
                const SizedBox(height: 8),
                ...widget.data.products.map((product) {
                  final id = product['id'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${product['name']} (${product['code']})'),
                        const SizedBox(height: 6),
                        if (_isOutlet)
                          Row(
                            children: [
                              Expanded(
                                child: _priceInput(
                                  id,
                                  'purchase',
                                  'شراء المصنع',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _priceInput(
                                  id,
                                  'distributor',
                                  'بيع للموزعين',
                                ),
                              ),
                            ],
                          )
                        else
                          _priceInput(id, 'sale', 'سعر البيع'),
                        const Divider(height: 18),
                      ],
                    ),
                  );
                }),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإصدار'),
          ),
        ],
      );

  Widget _priceInput(String productId, String field, String label) =>
      TextField(
        controller: _controller(productId, field),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

String _scopeLabel(Map<String, dynamic> policy, _PricingData data) {
  final scope = policy['scope_type'] as String;
  final (idKey, rows, prefix) = switch (scope) {
    'customer_type' => ('customer_type_id', data.customerTypes, 'نوع العميل'),
    'pickup_location' =>
      ('pickup_location_id', data.pickupLocations, 'المصنع'),
    _ => ('external_outlet_id', data.outlets, 'المنفذ الخارجي'),
  };
  final id = policy[idKey];
  Map<String, dynamic>? target;
  for (final row in rows) {
    if (row['id'] == id) {
      target = row;
      break;
    }
  }
  return '$prefix: ${target?['name'] ?? 'غير محدد'}';
}

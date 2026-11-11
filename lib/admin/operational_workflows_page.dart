import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// أي جزء من دورة التشغيل تعرضه الشاشة. `all` للأدوار التي تعرض كل شيء في صفحة واحدة.
enum OpsSection { all, orders, production, stock }

class OperationalWorkflowsPage extends StatefulWidget {
  const OperationalWorkflowsPage({
    required this.role,
    this.section = OpsSection.all,
    super.key,
  });

  final String role;
  final OpsSection section;

  @override
  State<OperationalWorkflowsPage> createState() =>
      _OperationalWorkflowsPageState();
}

class _OperationalWorkflowsPageState extends State<OperationalWorkflowsPage> {
  late Future<_WorkflowData> _data;
  final Set<String> _selectedOrders = {};

  bool _shows(OpsSection section) =>
      widget.section == OpsSection.all || widget.section == section;

  bool get _financial => const {
        'admin',
        'accountant',
        'distributor',
        'outlet_manager',
      }.contains(widget.role);

  bool get _canManageProduction =>
      widget.role == 'admin' || widget.role == 'production_manager';

  bool get _canDeliver => const {
        'admin',
        'accountant',
        'factory_outlet_manager',
        'outlet_manager',
      }.contains(widget.role);

  bool get _canDecideOrders =>
      widget.role == 'admin' || widget.role == 'accountant';

  bool get _canDecideReturns =>
      widget.role == 'admin' || widget.role == 'accountant';

  bool get _canManageCrates => const {
        'admin',
        'accountant',
        'factory_outlet_manager',
        'outlet_manager',
      }.contains(widget.role);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
    _selectedOrders.clear();
    if (mounted) setState(() {});
  }

  Future<_WorkflowData> _load() async {
    final client = Supabase.instance.client;
    final orders = (await client
            .from('role_orders')
            .select(
                'id, distributor_id, pickup_location_id, external_outlet_id, requested_for, status, status_reason, production_batch_id, created_at, lead_days_snapshot, decision_by, decision_at')
            .order('created_at', ascending: false)
            .limit(100))
        .cast<Map<String, dynamic>>();
    final orderIds = orders.map((row) => row['id'] as String).toList();
    final quantities = orderIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('role_order_quantities')
                .select(
                    'id, order_id, product_id, requested_quantity, allocated_quantity, delivered_quantity, delivered_crates, crate_capacity_snapshots, calculated_quantity')
                .inFilter('order_id', orderIds))
            .cast<Map<String, dynamic>>();

    final productIds =
        quantities.map((row) => row['product_id'] as String).toSet().toList();
    final products = productIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('products')
                .select('id, name')
                .inFilter('id', productIds))
            .cast<Map<String, dynamic>>();
    final names = {
      for (final product in products)
        product['id'] as String: product['name'] as String,
    };

    final distributorIds =
        orders.map((row) => row['distributor_id'] as String).toSet().toList();
    final distributors = distributorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('distributors')
                .select('id, name')
                .inFilter('id', distributorIds))
            .cast<Map<String, dynamic>>();
    final distributorNames = {
      for (final distributor in distributors)
        distributor['id'] as String: distributor['name'] as String,
    };

    final financialLines = _financial && orderIds.isNotEmpty
        ? (await client
                .from('role_financial_order_lines')
                .select('id, order_id, unit_price, requested_total')
                .inFilter('order_id', orderIds))
            .cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    final batches = (await client
            .from('role_production_batches')
            .select(
                'id, pickup_location_id, scheduled_for, status, finalized_at, distribution_approved, distribution_approved_by, distribution_approved_at')
            .order('scheduled_for', ascending: false)
            .limit(50))
        .cast<Map<String, dynamic>>();
    final productionLines = (await client
            .from('role_production_quantities')
            .select('id, batch_id, product_id, produced_quantity')
            .limit(100))
        .cast<Map<String, dynamic>>();
    final leadDays = await client.rpc('get_order_lead_days') as int;
    final returns = (await client
            .from('role_returns')
            .select(
                'id, order_id, reason, status, resolution, decision_reason, requested_at')
            .order('requested_at', ascending: false)
            .limit(50))
        .cast<Map<String, dynamic>>();
    final crateBalances = (await client
            .from('role_crate_balances')
            .select(
                'distributor_id, external_outlet_id, crate_type_id, balance, lost, damaged'))
        .cast<Map<String, dynamic>>();
    final inventory = (await client
            .from('role_inventory_balances')
            .select('pickup_location_id, product_id, quantity')
            .order('updated_at', ascending: false)
            .limit(100))
        .cast<Map<String, dynamic>>();
    final report = (await client
            .from('role_operational_order_summary')
            .select(
                'requested_for, pickup_location_id, product_id, requested_quantity, allocated_quantity, delivered_quantity')
            .order('requested_for', ascending: false)
            .limit(100))
        .cast<Map<String, dynamic>>();

    final returnIds = returns.map((row) => row['id'] as String).toList();
    final returnLines = returnIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('role_return_quantities')
                .select(
                    'id, return_request_id, order_line_id, requested_quantity, approved_quantity')
                .inFilter('return_request_id', returnIds))
            .cast<Map<String, dynamic>>();
    final orderCrateRows = orderIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('role_order_crates')
                .select(
                    'order_id, requested_crates, allocated_crates, delivered_crates')
                .inFilter('order_id', orderIds))
            .cast<Map<String, dynamic>>();
    var materials = <Map<String, dynamic>>[];
    if (_canManageProduction) {
      final planningIds = orders
          .where((order) =>
              const {'approved', 'in_production'}.contains(order['status']))
          .map((order) => order['id'] as String)
          .toList();
      if (planningIds.isNotEmpty) {
        final rows = await client.rpc('production_material_requirements',
            params: {
              'p_order_ids': planningIds,
              'p_for_date':
                  DateTime.now().toIso8601String().split('T').first,
            }) as List;
        materials = rows.cast<Map<String, dynamic>>();
      }
    }
    return _WorkflowData(
      orders: orders,
      quantities: quantities,
      productNames: names,
      distributorNames: distributorNames,
      financialLines: financialLines,
      batches: batches,
      productionLines: productionLines,
      leadDays: leadDays,
      returns: returns,
      returnLines: returnLines,
      crateBalances: crateBalances,
      inventory: inventory,
      report: report,
      orderCrates: {
        for (final row in orderCrateRows) row['order_id'] as String: row,
      },
      materials: materials,
    );
  }

  Future<void> _call(
    String function, {
    required Map<String, dynamic> parameters,
    required String success,
  }) async {
    try {
      await Supabase.instance.client.rpc(function, params: parameters);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ العملية: $error')),
      );
    }
  }

  Future<void> _createOrder() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _OrderComposer(),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _setLeadDays(int leadDays) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('مدة الاستلام للطلبات الجديدة'),
        children: [
          for (final days in const [1, 2])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, days),
              child: Text(
                  'بعد $days ${days == 1 ? 'يوم' : 'يومين'}${days == leadDays ? ' (الحالي)' : ''}'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _call(
      'set_order_lead_days',
      parameters: {'p_days': selected},
      success: 'تم تحديث مدة الاستلام للطلبات الجديدة.',
    );
  }

  Future<void> _reviewOrder(
    String orderId,
    String decision, {
    String? reason,
  }) async {
    if ((decision == 'rejected' || decision == 'cancelled') && reason == null) {
      reason = await _reasonDialog(
        decision == 'rejected' ? 'سبب الرفض' : 'سبب الإلغاء',
      );
      if (reason == null) return;
    }
    await _call(
      'review_sales_order',
      parameters: {
        'p_order_id': orderId,
        'p_decision': decision,
        'p_reason': reason,
      },
      success: 'تم تحديث حالة الطلب.',
    );
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'السبب'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _rescheduleOrder(Map<String, dynamic> order) async {
    final currentDate = DateTime.parse(order['requested_for'] as String);
    final date = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final reason = await _reasonDialog('سبب تعديل موعد الاستلام');
    if (reason == null) return;
    await _call(
      'reschedule_sales_order',
      parameters: {
        'p_order_id': order['id'],
        'p_requested_for': date.toIso8601String().split('T').first,
        'p_reason': reason,
      },
      success: 'تم تعديل موعد الطلب وتوثيق السبب.',
    );
  }

  Future<void> _createBatches(List<Map<String, dynamic>> orders) async {
    final selected = orders
        .where((order) => _selectedOrders.contains(order['id']))
        .toList();
    if (selected.isEmpty) return;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final order in selected) {
      final key =
          '${order['pickup_location_id']}|${order['requested_for']}';
      groups.putIfAbsent(key, () => []).add(order);
    }
    try {
      for (final group in groups.values) {
        await Supabase.instance.client.rpc('create_production_batch', params: {
          'p_pickup_location_id': group.first['pickup_location_id'],
          'p_scheduled_for': group.first['requested_for'],
          'p_order_ids': group.map((order) => order['id']).toList(),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء ${groups.length} دفعة إنتاج.')),
        );
        _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء دفعات الإنتاج: $error')),
        );
      }
    }
  }

  Future<void> _editDistribution(
    Map<String, dynamic> batch,
    Map<String, dynamic> productionLine,
    _WorkflowData data,
  ) async {
    final batchId = batch['id'] as String;
    final productId = productionLine['product_id'] as String;
    final orderIds = data.orders
        .where((order) => order['production_batch_id'] == batchId)
        .map((order) => order['id'])
        .toSet();
    final allocations = data.quantities
        .where((line) =>
            orderIds.contains(line['order_id']) &&
            line['product_id'] == productId)
        .toList();
    final revised = await showDialog<_DistributionDraft>(
      context: context,
      builder: (_) => _DistributionDialog(
        lines: allocations,
        productName: data.productNames[productId] ?? 'صنف',
        producedQuantity: productionLine['produced_quantity'] as int,
      ),
    );
    if (revised == null) return;
    await _call(
      'revise_production_distribution',
      parameters: {
        'p_batch_id': batchId,
        'p_product_id': productId,
        'p_allocations': revised.allocations,
        'p_reason': revised.reason,
      },
      success: 'تم حفظ تعديل التوزيع وتوثيقه.',
    );
  }

  Future<void> _approveDistribution(String batchId) async {
    await _call(
      'approve_production_distribution',
      parameters: {'p_batch_id': batchId},
      success: 'تم اعتماد التوزيع النهائي.',
    );
  }

  Future<void> _finalizeBatch(
    Map<String, dynamic> batch,
    _WorkflowData data,
  ) async {
    final batchId = batch['id'] as String;
    final batchOrderIds = data.orders
        .where((order) =>
            order['production_batch_id'] == batchId &&
            order['status'] == 'in_production')
        .map((order) => order['id'] as String)
        .toSet();
    final requestedByProduct = <String, int>{};
    for (final line in data.quantities.where(
      (line) => batchOrderIds.contains(line['order_id']),
    )) {
      final productId = line['product_id'] as String;
      requestedByProduct.update(
        productId,
        (quantity) => quantity + (line['requested_quantity'] as int),
        ifAbsent: () => line['requested_quantity'] as int,
      );
    }

    if (requestedByProduct.isEmpty) return;
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ProductionResultDialog(
        requested: requestedByProduct,
        productNames: data.productNames,
      ),
    );
    if (result == null) return;
    await _call(
      'finalize_production_batch',
      parameters: {'p_batch_id': batchId, 'p_lines': result},
      success: 'تم اعتماد الإنتاج وتوزيع الحصص.',
    );
  }

  Future<void> _deliverOrder(
    Map<String, dynamic> order,
    _WorkflowData data,
  ) async {
    final orderId = order['id'] as String;
    final lines = data.quantities
        .where((line) => line['order_id'] == orderId)
        .map((line) {
          final remaining =
              (line['allocated_quantity'] as int) -
              (line['delivered_quantity'] as int);
          if (remaining <= 0) return null;
          return {
            'order_line_id': line['id'],
            'quantity': remaining,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد كمية متبقية للتسليم.')),
      );
      return;
    }
    await _call(
      'record_order_delivery',
      parameters: {
        'p_order_id': orderId,
        'p_idempotency_key': '$orderId-delivery',
        'p_lines': lines,
        'p_note': null,
      },
      success: 'تم تسجيل التسليم.',
    );
  }

  Future<void> _requestReturn(
    Map<String, dynamic> order,
    _WorkflowData data,
  ) async {
    final orderId = order['id'] as String;
    final eligible = data.quantities
        .where((line) =>
            line['order_id'] == orderId &&
            (line['delivered_quantity'] as int) > 0)
        .toList();
    final result = await showDialog<_ReturnDraft>(
      context: context,
      builder: (_) => _ReturnRequestDialog(
        lines: eligible,
        productNames: data.productNames,
      ),
    );
    if (result == null) return;
    await _call(
      'submit_return_request',
      parameters: {
        'p_order_id': orderId,
        'p_reason': result.reason,
        'p_lines': result.lines,
      },
      success: 'تم إرسال طلب المرتجع للمراجعة.',
    );
  }

  Future<void> _decideReturn(
    Map<String, dynamic> request,
    _WorkflowData data,
  ) async {
    final reason = await _reasonDialog('سبب قرار المرتجع');
    if (reason == null) return;
    final requestId = request['id'] as String;
    final lines = data.returnLines
        .where((line) => line['return_request_id'] == requestId)
        .map((line) => {
              'return_line_id': line['id'],
              'approved_quantity': line['requested_quantity'],
            })
        .toList();
    final resolution = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('قرار المرتجع'),
        children: [
          for (final item in const {
            'credit': 'رصيد دائن',
            'replacement': 'استبدال',
            'destroy': 'إعدام / عزل',
            'reject': 'رفض',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.key),
              child: Text(item.value),
            ),
        ],
      ),
    );
    if (resolution == null) return;
    await _call(
      'decide_return_request',
      parameters: {
        'p_return_request_id': requestId,
        'p_resolution': resolution,
        'p_reason': reason,
        'p_lines': resolution == 'reject' ? [] : lines,
      },
      success: 'تم تسجيل قرار المرتجع.',
    );
  }

  Future<void> _recordCrates() async {
    final movement = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CrateMovementDialog(role: widget.role),
    );
    if (movement == null) return;
    await _call(
      'record_crate_movement',
      parameters: movement,
      success: 'تم تسجيل حركة البرانيك.',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_WorkflowData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعذر تحميل بيانات التشغيل: ${snapshot.error}'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.section == OpsSection.all)
                  Text('الطلبات والإنتاج والتسليم',
                      style: Theme.of(context).textTheme.headlineSmall),
                if (widget.role == 'admin' && _shows(OpsSection.orders))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => _setLeadDays(data.leadDays),
                      icon: const Icon(Icons.schedule),
                      label: Text(
                          'مدة الاستلام للطلبات الجديدة: ${data.leadDays} ${data.leadDays == 1 ? 'يوم' : 'يومان'}'),
                    ),
                  ),
                if (_canManageCrates && _shows(OpsSection.stock))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: OutlinedButton.icon(
                        onPressed: _recordCrates,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('تسجيل حركة برانيك'),
                      ),
                    ),
                  ),
                if (widget.role == 'distributor' && _shows(OpsSection.orders))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: FilledButton.icon(
                        onPressed: _createOrder,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('تقديم طلب جديد'),
                      ),
                    ),
                  ),
                if (_canManageProduction && _shows(OpsSection.orders))
                  _buildSelectionAction(data.orders),
                if (_shows(OpsSection.orders)) ...[
                  if (data.orders.isEmpty)
                    const ListTile(title: Text('لا توجد طلبات مسجلة.')),
                  ...data.orders.map((order) => _buildOrderCard(order, data)),
                ],
                if (_shows(OpsSection.production)) ..._buildPlanning(data),
                if (_shows(OpsSection.production) && data.batches.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('دفعات الإنتاج',
                      style: Theme.of(context).textTheme.titleLarge),
                  ...data.batches.map((batch) => _buildBatchCard(batch, data)),
                ],
                if (_shows(OpsSection.stock) && data.returns.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('المرتجعات',
                      style: Theme.of(context).textTheme.titleLarge),
                  ...data.returns.map((request) => _buildReturnCard(request, data)),
                ],
                if (_shows(OpsSection.stock) && data.crateBalances.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('أرصدة البرانيك',
                      style: Theme.of(context).textTheme.titleLarge),
                  ...data.crateBalances.map((balance) => ListTile(
                        title: Text(
                            data.distributorNames[balance['distributor_id']] ??
                                'موزع ${_shortId(balance['distributor_id'] as String)}'),
                        subtitle: Text('مفقود: ${balance['lost']} — '
                            'تالف: ${balance['damaged']} — منفذ ${_shortId(balance['external_outlet_id'] as String)}'),
                        trailing: Text('الرصيد: ${balance['balance']}'),
                      )),
                ],
                if (_shows(OpsSection.stock) && data.inventory.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('أرصدة المخزون التشغيلي',
                      style: Theme.of(context).textTheme.titleLarge),
                  ...data.inventory.map((balance) => ListTile(
                        title: Text(
                            data.productNames[balance['product_id']] ?? 'صنف'),
                        subtitle: Text(
                            'موقع الاستلام ${_shortId(balance['pickup_location_id'] as String)}'),
                        trailing: Text('المتاح: ${balance['quantity']}'),
                      )),
                ],
                if (_shows(OpsSection.production) && data.report.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('ملخص الطلبات حسب الصنف والتاريخ',
                      style: Theme.of(context).textTheme.titleLarge),
                  ...data.report.map((row) => ListTile(
                        title: Text(
                            data.productNames[row['product_id']] ?? 'صنف'),
                        subtitle: Text(
                            '${row['requested_for']} — مطلوب ${row['requested_quantity']}، موزع ${row['allocated_quantity']}، مسلم ${row['delivered_quantity']}'),
                      )),
                ],
                if (widget.section == OpsSection.production &&
                    data.batches.isEmpty &&
                    data.report.isEmpty)
                  const ListTile(
                    title: Text(
                      'لا توجد دفعات إنتاج بعد. اعتمد الطلبات من تبويب الطلبات ثم أنشئ دفعة.',
                    ),
                  ),
                if (widget.section == OpsSection.stock &&
                    data.returns.isEmpty &&
                    data.crateBalances.isEmpty &&
                    data.inventory.isEmpty)
                  const ListTile(
                    title: Text('لا توجد حركات مخزون أو برانيك أو مرتجعات بعد.'),
                  ),
              ],
            ),
          );
        },
      );

  /// الإجمالي التقديري من الكمية المطلوبة، والنهائي من الكمية بعد التوزيع.
  String _orderTotalsText(
    List<Map<String, dynamic>> lines,
    Map<String, Map<String, dynamic>> financialByLine,
  ) {
    var estimated = 0.0;
    var afterDistribution = 0.0;
    var distributed = false;
    for (final line in lines) {
      final price = financialByLine[line['id']];
      if (price == null) continue;
      final unitPrice = (price['unit_price'] as num).toDouble();
      estimated += (line['requested_quantity'] as int? ?? 0) * unitPrice;
      final allocated = line['allocated_quantity'] as int? ?? 0;
      if (allocated > 0) distributed = true;
      afterDistribution += allocated * unitPrice;
    }
    final estimatedText = 'الإجمالي التقديري: ${estimated.toStringAsFixed(2)}';
    return distributed
        ? '$estimatedText — بعد التوزيع: ${afterDistribution.toStringAsFixed(2)} جنيه'
        : '$estimatedText جنيه';
  }

  String _crateSummary(Map<String, dynamic> crates) {
    final requested = crates['requested_crates'] as int? ?? 0;
    final allocated = crates['allocated_crates'] as int? ?? 0;
    final delivered = crates['delivered_crates'] as int? ?? 0;
    final parts = <String>['البرانيك المتوقعة: $requested'];
    if (allocated > 0 && allocated != requested) {
      parts.add('بعد التوزيع: $allocated');
    }
    if (delivered > 0) parts.add('المسلّمة: $delivered');
    return ' — ${parts.join(' — ')}';
  }

  /// تجميع الطلبات المعتمدة للإنتاج: لكل صنف إجماليه وكمية كل مندوب،
  /// ثم احتياجات الخامات من الوصفات.
  List<Widget> _buildPlanning(_WorkflowData data) {
    final planningOrders = {
      for (final order in data.orders)
        if (const {'approved', 'in_production'}.contains(order['status']))
          order['id'] as String: order['distributor_id'] as String,
    };
    if (planningOrders.isEmpty) return const [];
    final byProduct = <String, Map<String, int>>{};
    for (final line in data.quantities) {
      final distributorId = planningOrders[line['order_id']];
      if (distributorId == null) continue;
      final quantity = line['requested_quantity'] as int? ?? 0;
      byProduct
          .putIfAbsent(line['product_id'] as String, () => {})
          .update(distributorId, (value) => value + quantity,
              ifAbsent: () => quantity);
    }
    final totalCrates = planningOrders.keys.fold<int>(
      0,
      (sum, orderId) =>
          sum + ((data.orderCrates[orderId]?['requested_crates'] as int?) ?? 0),
    );
    final neededMaterials =
        data.materials.where((row) => row['kind'] == 'material').toList();
    final missingRecipes =
        data.materials.where((row) => row['kind'] == 'missing_recipe').toList();
    return [
      const SizedBox(height: 8),
      Text('التجميع للإنتاج (الطلبات المعتمدة)',
          style: Theme.of(context).textTheme.titleLarge),
      ...byProduct.entries.map((entry) {
        final total = entry.value.values.fold<int>(0, (a, b) => a + b);
        return Card(
          child: ExpansionTile(
            title: Text(data.productNames[entry.key] ?? 'صنف'),
            subtitle: Text('إجمالي المطلوب: $total علبة'),
            children: entry.value.entries
                .map((item) => ListTile(
                      dense: true,
                      title: Text(data.distributorNames[item.key] ?? 'مندوب'),
                      trailing: Text('${item.value} علبة'),
                    ))
                .toList(),
          ),
        );
      }),
      ListTile(
        title: Text('مجموع البرانيك المتوقعة لهذه الطلبات: $totalCrates'),
      ),
      if (_canManageProduction &&
          data.orders.any((order) => order['status'] == 'approved'))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            onPressed: () {
              final approved = data.orders
                  .where((order) => order['status'] == 'approved')
                  .toList();
              _selectedOrders
                ..clear()
                ..addAll(approved.map((order) => order['id'] as String));
              _createBatches(approved);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء الإنتاج لكل الطلبات المعتمدة'),
          ),
        ),
      if (neededMaterials.isNotEmpty || missingRecipes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('احتياجات الخامات (شاملة نسبة الهالك)',
            style: Theme.of(context).textTheme.titleLarge),
        ...neededMaterials.map((row) => ListTile(
              dense: true,
              title: Text(row['item_name'] as String),
              trailing: Text('${row['quantity']} ${row['unit']}'),
            )),
        ...missingRecipes.map((row) => ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange),
              title: Text('${row['item_name']}: لا توجد وصفة، لم تُحسب خاماته'),
            )),
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _buildSelectionAction(List<Map<String, dynamic>> orders) {
    if (_selectedOrders.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FilledButton.icon(
        onPressed: () => _createBatches(orders),
        icon: const Icon(Icons.factory_outlined),
        label: Text('إنشاء دفعات (${_selectedOrders.length})'),
      ),
    );
  }

  Widget _buildOrderCard(
    Map<String, dynamic> order,
    _WorkflowData data,
  ) {
    final orderId = order['id'] as String;
    final status = order['status'] as String;
    final lines =
        data.quantities.where((line) => line['order_id'] == orderId).toList();
    final financialByLine = {
      for (final line in data.financialLines)
        line['id'] as String: line,
    };
    final selected = _selectedOrders.contains(orderId);
    final crates = data.orderCrates[orderId];
    return Card(
      child: ExpansionTile(
        leading: _canManageProduction && status == 'approved'
            ? Checkbox(
                value: selected,
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selectedOrders.add(orderId);
                  } else {
                    _selectedOrders.remove(orderId);
                  }
                }),
              )
            : null,
        title: Text(
          '${data.distributorNames[order['distributor_id']] ?? 'طلب ${_shortId(orderId)}'} — ${_statusLabel(status)}',
        ),
        subtitle: Text(
            'موعد الاستلام: ${order['requested_for']} — ${lines.length} صنف'
            '${order['lead_days_snapshot'] == null ? '' : ' — المدة المثبتة: ${order['lead_days_snapshot']} يوم'}'
            '${crates == null ? '' : _crateSummary(crates)}'),
        children: [
          ...lines.map((line) {
            final price = financialByLine[line['id']];
            final requested = line['requested_quantity'];
            final allocated = line['allocated_quantity'];
            final delivered = line['delivered_quantity'];
            return ListTile(
              dense: true,
              title: Text(data.productNames[line['product_id']] ?? 'صنف'),
              subtitle: Text(
                'مطلوب $requested — مخصص $allocated — مسلم $delivered',
              ),
              trailing: price == null
                  ? null
                  : Text('${price['unit_price']} / وحدة'),
            );
          }),
          if (financialByLine.isNotEmpty)
            ListTile(
              dense: true,
              title: Text(_orderTotalsText(lines, financialByLine)),
            ),
          if (status == 'submitted' && _canDecideOrders)
            TextButton(
              onPressed: () => _reviewOrder(orderId, 'in_review'),
              child: const Text('بدء المراجعة'),
            ),
          if ((status == 'submitted' || status == 'in_review') &&
              _canDecideOrders)
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _reviewOrder(orderId, 'approved'),
                  child: const Text('اعتماد'),
                ),
                TextButton(
                  onPressed: () => _reviewOrder(orderId, 'rejected'),
                  child: const Text('رفض مع ذكر السبب'),
                ),
              ],
            ),
          if (_canDeliver && (status == 'ready' || status == 'partially_delivered'))
            TextButton.icon(
              onPressed: () => _deliverOrder(order, data),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('تسليم الكمية المتبقية'),
            ),
          if (widget.role == 'distributor' &&
              (status == 'delivered' || status == 'partially_delivered'))
            TextButton.icon(
              onPressed: () => _requestReturn(order, data),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('طلب مرتجع'),
            ),
          if (status == 'cancelled' || status == 'rejected')
            ListTile(
              dense: true,
              title: Text(
                  status == 'rejected' ? 'سبب الرفض' : 'سبب الإلغاء'),
              subtitle: Text(order['status_reason'] as String? ?? 'لا يوجد سبب'),
            ),
          if (order['decision_at'] != null &&
              (status == 'approved' || status == 'rejected'))
            ListTile(
              dense: true,
              title: Text(status == 'approved' ? 'تم اعتماد الطلب' : 'قرار الرفض'),
              subtitle: Text(order['decision_at'] as String),
            ),
          if (widget.role == 'admin' &&
              order['production_batch_id'] == null &&
              !const {'delivered', 'closed', 'cancelled', 'rejected'}
                  .contains(status))
            TextButton(
              onPressed: () => _rescheduleOrder(order),
              child: const Text('تعديل موعد الاستلام مع تسجيل السبب'),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchCard(
    Map<String, dynamic> batch,
    _WorkflowData data,
  ) {
    final status = batch['status'] as String;
    final batchId = batch['id'] as String;
    final lines = data.productionLines
        .where((line) => line['batch_id'] == batchId)
        .toList();
    final distributionApproved =
        batch['distribution_approved'] as bool? ?? false;
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text('دفعة ${_shortId(batchId)} — '
                '${status == 'ready' ? 'جاهزة' : status == 'cancelled' ? 'ملغاة' : 'قيد الإنتاج'}'),
            subtitle: Text(
                'موعد التشغيل: ${batch['scheduled_for']} — '
                '${distributionApproved ? 'التوزيع معتمد' : 'التوزيع بانتظار الاعتماد'}'),
            trailing: status == 'in_production' && _canManageProduction
                ? IconButton(
                    tooltip: 'اعتماد الإنتاج',
                    onPressed: () => _finalizeBatch(batch, data),
                    icon: const Icon(Icons.check_circle_outline),
                  )
                : null,
          ),
          if (status == 'ready' && widget.role == 'admin') ...[
            for (final line in lines)
              ListTile(
                dense: true,
                title: Text(data.productNames[line['product_id']] ?? 'صنف'),
                subtitle: Text('الإنتاج المتاح: ${line['produced_quantity']}'),
                trailing: IconButton(
                  tooltip: 'تعديل التوزيع',
                  onPressed: () => _editDistribution(batch, line, data),
                  icon: const Icon(Icons.edit),
                ),
              ),
            if (!distributionApproved)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton(
                  onPressed: () => _approveDistribution(batchId),
                  child: const Text('اعتماد التوزيع النهائي'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildReturnCard(
    Map<String, dynamic> request,
    _WorkflowData data,
  ) {
    final status = request['status'] as String;
    return Card(
      child: ListTile(
        title: Text('مرتجع ${_shortId(request['id'] as String)} — '
            '${status == 'pending' ? 'بانتظار المراجعة' : status == 'approved' ? 'معتمد' : 'مرفوض'}'),
        subtitle: Text(request['reason'] as String),
        trailing: _canDecideReturns && status == 'pending'
            ? IconButton(
                tooltip: 'مراجعة المرتجع',
                onPressed: () => _decideReturn(request, data),
                icon: const Icon(Icons.fact_check_outlined),
              )
            : null,
      ),
    );
  }

  static String _shortId(String id) =>
      id.length > 8 ? id.substring(0, 8) : id;

  static String _statusLabel(String status) => switch (status) {
        'draft' => 'مسودة',
        'submitted' => 'بانتظار موافقة الإدارة',
        'in_review' => 'قيد المراجعة',
        'approved' => 'معتمد',
        'in_production' => 'قيد الإنتاج',
        'ready' => 'جاهز',
        'partially_delivered' => 'تسليم جزئي',
        'delivered' => 'تم التسليم',
        'closed' => 'مغلق',
        'cancelled' => 'ملغى',
        'rejected' => 'مرفوض',
        _ => status,
      };
}

class _WorkflowData {
  const _WorkflowData({
    required this.orders,
    required this.quantities,
    required this.productNames,
    required this.distributorNames,
    required this.financialLines,
    required this.batches,
    required this.productionLines,
    required this.leadDays,
    required this.returns,
    required this.returnLines,
    required this.crateBalances,
    required this.inventory,
    required this.report,
    required this.orderCrates,
    required this.materials,
  });

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> quantities;
  final Map<String, String> productNames;
  final Map<String, String> distributorNames;
  final List<Map<String, dynamic>> financialLines;
  final List<Map<String, dynamic>> batches;
  final List<Map<String, dynamic>> productionLines;
  final int leadDays;
  final List<Map<String, dynamic>> returns;
  final List<Map<String, dynamic>> returnLines;
  final List<Map<String, dynamic>> crateBalances;
  final List<Map<String, dynamic>> inventory;
  final List<Map<String, dynamic>> report;
  final Map<String, Map<String, dynamic>> orderCrates;
  final List<Map<String, dynamic>> materials;
}

class _DistributionDraft {
  const _DistributionDraft({
    required this.allocations,
    required this.reason,
  });

  final List<Map<String, dynamic>> allocations;
  final String reason;
}

class _DistributionDialog extends StatefulWidget {
  const _DistributionDialog({
    required this.lines,
    required this.productName,
    required this.producedQuantity,
  });

  final List<Map<String, dynamic>> lines;
  final String productName;
  final int producedQuantity;

  @override
  State<_DistributionDialog> createState() => _DistributionDialogState();
}

class _DistributionDialogState extends State<_DistributionDialog> {
  final _reason = TextEditingController();
  final _quantities = <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final line in widget.lines) {
      _quantities[line['id'] as String] = TextEditingController(
        text: '${line['allocated_quantity']}',
      );
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'اكتب سبب تعديل التوزيع.');
      return;
    }
    final allocations = <Map<String, dynamic>>[];
    var total = 0;
    for (final line in widget.lines) {
      final value = int.tryParse(_quantities[line['id']]!.text.trim());
      if (value == null || value < 0) {
        setState(() => _error = 'يجب أن تكون كل حصة عددًا صحيحًا غير سالب.');
        return;
      }
      total += value;
      allocations.add({
        'order_line_id': line['id'],
        'allocated_quantity': value,
      });
    }
    if (total != widget.producedQuantity) {
      setState(() => _error =
          'مجموع التوزيع $total ويجب أن يساوي الإنتاج المتاح ${widget.producedQuantity}.');
      return;
    }
    Navigator.pop(
      context,
      _DistributionDraft(
        allocations: allocations,
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('تعديل توزيع ${widget.productName}'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('الإنتاج المتاح: ${widget.producedQuantity}'),
              for (final line in widget.lines)
                TextField(
                  controller: _quantities[line['id']],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'المحسوب ${line['calculated_quantity']} — الحالي ${line['allocated_quantity']}',
                  ),
                ),
              TextField(
                controller: _reason,
                maxLength: 1000,
                decoration:
                    const InputDecoration(labelText: 'سبب التعديل (مطلوب)'),
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('حفظ التوزيع'),
          ),
        ],
      );
}

class _OrderComposer extends StatefulWidget {
  const _OrderComposer();

  @override
  State<_OrderComposer> createState() => _OrderComposerState();
}

class _OrderComposerState extends State<_OrderComposer> {
  final _quantities = <String, TextEditingController>{};
  late Future<_OrderOptions> _options;
  String? _outletId;
  DateTime _requestedFor = DateTime.now().add(const Duration(days: 2));
  String? _orderId;
  bool _saving = false;
  String? _error;
  final Map<String, num> _prices = {};
  String? _pricesOutlet;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _options = _loadOptions();
  }

  Future<_OrderOptions> _loadOptions() async {
    final client = Supabase.instance.client;
    final results = await Future.wait<dynamic>([
      client
          .from('user_profiles')
          .select('distributor_id')
          .eq('user_id', client.auth.currentUser!.id)
          .single(),
      client.rpc('get_order_lead_days'),
      client.from('products').select('id, name, crate_capacity')
          .eq('is_active', true).order('name'),
    ]);
    final distributorId =
        (results[0] as Map<String, dynamic>)['distributor_id'] as String;
    final leadDays = results[1] as int;
    final links = (await client
            .from('distributor_outlets')
            .select('external_outlet_id')
            .eq('distributor_id', distributorId))
        .cast<Map<String, dynamic>>();
    final outletIds =
        links.map((row) => row['external_outlet_id'] as String).toList();
    final outlets = outletIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                .from('external_outlets')
                .select('id, name, pickup_location_id')
                .inFilter('id', outletIds)
                .eq('is_active', true))
            .cast<Map<String, dynamic>>();
    final products = (results[2] as List).cast<Map<String, dynamic>>();
    _requestedFor = DateTime.now().add(Duration(days: leadDays));
    return _OrderOptions(
      outlets: outlets,
      products: products,
      leadDays: leadDays,
    );
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _requestedFor,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _requestedFor = date);
  }

  int _quantityOf(Map<String, dynamic> product) =>
      int.tryParse(_quantities[product['id']]?.text.trim() ?? '') ?? 0;

  int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// البرانيك على إجمالي الطلب: كل صنف يشغل (الكمية ÷ سعته) من البرنيكة،
  /// ثم يُقرَّب المجموع لأعلى، فتتشارك الأصناف في البرنيكة الأخيرة.
  int _expectedCrates(List<Map<String, dynamic>> products) {
    var denominator = 1;
    var numerator = 0;
    for (final product in products) {
      final quantity = _quantityOf(product);
      if (quantity <= 0) continue;
      final capacity = product['crate_capacity'] as int? ?? 75;
      final newDenominator = denominator ~/ _gcd(denominator, capacity) * capacity;
      numerator = numerator * (newDenominator ~/ denominator) +
          quantity * (newDenominator ~/ capacity);
      denominator = newDenominator;
    }
    return numerator == 0 ? 0 : (numerator + denominator - 1) ~/ denominator;
  }

  int _totalBoxes(List<Map<String, dynamic>> products) =>
      products.fold<int>(0, (sum, product) => sum + _quantityOf(product));

  double _estimatedTotal(List<Map<String, dynamic>> products) {
    var total = 0.0;
    for (final product in products) {
      final price = _prices[product['id']];
      if (price != null) total += _quantityOf(product) * price.toDouble();
    }
    return total;
  }

  bool _hasUnpriced(List<Map<String, dynamic>> products) => products.any(
      (product) =>
          _quantityOf(product) > 0 && !_prices.containsKey(product['id']));

  Future<void> _loadPrices(String outletId) async {
    try {
      final rows = await Supabase.instance.client.rpc('get_order_price_list',
          params: {'p_external_outlet_id': outletId}) as List;
      if (!mounted || _outletId != outletId) return;
      setState(() {
        _prices
          ..clear()
          ..addEntries(rows
              .cast<Map<String, dynamic>>()
              .where((row) => row['unit_price'] != null)
              .map((row) =>
                  MapEntry(row['product_id'] as String, row['unit_price'] as num)));
        _priceError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _priceError = 'تعذر تحميل الأسعار: $error');
    }
  }

  Future<void> _save(_OrderOptions options) async {
    if (_outletId == null) {
      setState(() => _error = 'اختر منفذ الاستلام.');
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (final entry in _quantities.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      final quantity = int.tryParse(text);
      if (quantity == null || quantity <= 0) {
        setState(() => _error = 'أدخل كميات صحيحة موجبة بالأعداد الصحيحة.');
        return;
      }
      lines.add({'product_id': entry.key, 'quantity': quantity});
    }
    if (lines.isEmpty) {
      setState(() => _error = 'أدخل كمية لصنف واحد على الأقل.');
      return;
    }
    final outlet = options.outlets.firstWhere(
      (item) => item['id'] == _outletId,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_orderId == null) {
        _orderId = await Supabase.instance.client.rpc(
          'create_sales_order',
          params: {
            'p_pickup_location_id': outlet['pickup_location_id'],
            'p_external_outlet_id': _outletId,
            'p_requested_for': _requestedFor.toIso8601String().split('T').first,
            'p_lines': lines,
          },
        ) as String;
      }
      await Supabase.instance.client.rpc(
        'submit_sales_order',
        params: {'p_order_id': _orderId},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            _orderId == null
                ? 'تعذر حفظ الطلب: $error'
                : 'حُفظت المسودة ${_orderId!.substring(0, 8)}؛ تعذر إرسالها: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_OrderOptions>(
        future: _options,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('طلب جديد'),
              content: Text('تعذر تحميل بيانات الطلب: ${snapshot.error}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }
          final options = snapshot.data!;
          if (options.outlets.isEmpty || options.products.isEmpty) {
            return AlertDialog(
              title: const Text('طلب جديد'),
              content: Text(options.outlets.isEmpty
                  ? 'لا توجد منافذ استلام مرتبطة بحسابك.'
                  : 'لا توجد أصناف متاحة حاليًا.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          }
          _outletId ??= options.outlets.first['id'] as String;
          if (_pricesOutlet != _outletId) {
            final outletForPrices = _outletId!;
            _pricesOutlet = outletForPrices;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadPrices(outletForPrices));
          }
          for (final product in options.products) {
            _quantities.putIfAbsent(
              product['id'] as String,
              TextEditingController.new,
            );
          }
          return AlertDialog(
            title: const Text('إنشاء طلب'),
            content: SizedBox(
              width: 540,
              child: ListView(
                shrinkWrap: true,
                children: [
                  DropdownButtonFormField<String>(
                    value: _outletId,
                    decoration:
                        const InputDecoration(labelText: 'منفذ الاستلام'),
                    items: options.outlets
                        .map((outlet) => DropdownMenuItem<String>(
                              value: outlet['id'] as String,
                              child: Text(outlet['name'] as String),
                            ))
                        .toList(),
                    onChanged: _orderId == null
                        ? (value) => setState(() => _outletId = value)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _selectDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      'موعد الاستلام المتوقع: ${_requestedFor.toLocal().toString().split(' ').first}',
                    ),
                  ),
                  Text('وفق مدة الإدارة الحالية: ${options.leadDays} '
                      '${options.leadDays == 1 ? 'يوم' : 'يومين'}'),
                  const SizedBox(height: 8),
                  ...options.products.map((product) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TextField(
                          controller: _quantities[product['id']],
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText:
                                '${product['name']} — الكمية المطلوبة',
                            helperText:
                                'السعر: ${_prices[product['id']] ?? 'غير محدد'} — سعة البرنيكة ${product['crate_capacity']}',
                          ),
                        ),
                      )),
                  const SizedBox(height: 8),
                  Card(
                    color: const Color(0x2222d3b6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('إجمالي العلب: ${_totalBoxes(options.products)}'),
                          Text(
                              'السعر التقديري: ${_estimatedTotal(options.products).toStringAsFixed(2)} جنيه'),
                          if (_hasUnpriced(options.products))
                            const Text(
                              'تنبيه: صنف مطلوب بلا سعر معتمد لمنفذك، تواصل مع الإدارة.',
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                          Text(
                              'البرانيك المتوقعة: ${_expectedCrates(options.products)} (كسور الأصناف تُجمع في برنيكة مشتركة)'),
                          Text(
                              'موعد الاستلام المتوقع: ${_requestedFor.toLocal().toString().split(' ').first}'),
                          const Text(
                            'الكميات والأسعار نهائية بعد الإنتاج الفعلي وتوزيع الإدارة.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (_priceError != null)
                            Text(
                              _priceError!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: _saving ? null : () => _save(options),
                child: Text(_saving ? 'جارٍ الإرسال...' : 'إرسال الطلب'),
              ),
            ],
          );
        },
      );
}

class _OrderOptions {
  const _OrderOptions({
    required this.outlets,
    required this.products,
    required this.leadDays,
  });

  final List<Map<String, dynamic>> outlets;
  final List<Map<String, dynamic>> products;
  final int leadDays;
}

class _ProductionResultDialog extends StatefulWidget {
  const _ProductionResultDialog({
    required this.requested,
    required this.productNames,
  });

  final Map<String, int> requested;
  final Map<String, String> productNames;

  @override
  State<_ProductionResultDialog> createState() =>
      _ProductionResultDialogState();
}

class _ProductionResultDialogState extends State<_ProductionResultDialog> {
  final _produced = <String, TextEditingController>{};
  final _rejected = <String, TextEditingController>{};
  final _reason = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.requested.entries) {
      _produced[entry.key] =
          TextEditingController(text: entry.value.toString());
      _rejected[entry.key] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    for (final controller in [..._produced.values, ..._rejected.values]) {
      controller.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  void _save() {
    final rows = <Map<String, dynamic>>[];
    for (final productId in widget.requested.keys) {
      final produced = int.tryParse(_produced[productId]!.text.trim());
      final rejected = int.tryParse(_rejected[productId]!.text.trim());
      if (produced == null || rejected == null || produced < 0 || rejected < 0) {
        setState(() => _error = 'الكميات المنتجة والمرفوضة يجب أن تكون أعدادًا غير سالبة.');
        return;
      }
      if (rejected > 0 && _reason.text.trim().isEmpty) {
        setState(() => _error = 'اذكر سبب الكمية التالفة أو المرفوضة.');
        return;
      }
      if (produced + rejected == 0) {
        setState(() => _error = 'يجب تسجيل كمية منتجة أو مرفوضة لكل صنف.');
        return;
      }
      rows.add({
        'product_id': productId,
        'produced_quantity': produced,
        'rejected_quantity': rejected,
        'variance_reason': rejected > 0 ? _reason.text.trim() : null,
      });
    }
    Navigator.pop(context, rows);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('نتيجة الإنتاج الفعلي'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in widget.requested.entries)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          title: Text(
                              widget.productNames[entry.key] ?? 'صنف'),
                          subtitle: Text('مطلوب: ${entry.value}'),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _produced[entry.key],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'سليم'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _rejected[entry.key],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'تالف / مرفوض'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              TextField(
                controller: _reason,
                maxLength: 1000,
                decoration: const InputDecoration(
                    labelText: 'سبب التالف أو فرق الإنتاج'),
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('اعتماد الإنتاج'),
          ),
        ],
      );
}

class _ReturnDraft {
  const _ReturnDraft({required this.reason, required this.lines});

  final String reason;
  final List<Map<String, dynamic>> lines;
}

class _ReturnRequestDialog extends StatefulWidget {
  const _ReturnRequestDialog({
    required this.lines,
    required this.productNames,
  });

  final List<Map<String, dynamic>> lines;
  final Map<String, String> productNames;

  @override
  State<_ReturnRequestDialog> createState() => _ReturnRequestDialogState();
}

class _ReturnRequestDialogState extends State<_ReturnRequestDialog> {
  final _reason = TextEditingController();
  final _quantities = <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final line in widget.lines) {
      _quantities[line['id'] as String] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'اكتب سبب المرتجع.');
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (final line in widget.lines) {
      final value = _quantities[line['id']]!.text.trim();
      if (value.isEmpty) continue;
      final quantity = int.tryParse(value);
      if (quantity == null ||
          quantity <= 0 ||
          quantity > (line['delivered_quantity'] as int)) {
        setState(() => _error = 'كمية المرتجع غير صحيحة.');
        return;
      }
      lines.add({'order_line_id': line['id'], 'quantity': quantity});
    }
    if (lines.isEmpty) {
      setState(() => _error = 'أدخل كمية مرتجعة لصنف واحد على الأقل.');
      return;
    }
    Navigator.pop(
      context,
      _ReturnDraft(reason: _reason.text.trim(), lines: lines),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('طلب مرتجع'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                controller: _reason,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'السبب'),
              ),
              for (final line in widget.lines)
                TextField(
                  controller: _quantities[line['id']],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        '${widget.productNames[line['product_id']] ?? 'صنف'} — المسلم ${line['delivered_quantity']}، المرتجع',
                  ),
                ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('إرسال للمراجعة'),
          ),
        ],
      );
}

class _CrateMovementOptions {
  const _CrateMovementOptions({
    required this.distributors,
    required this.outlets,
    required this.links,
    required this.crateTypes,
    required this.pickupLocationId,
    required this.fixedOutletId,
  });

  final List<Map<String, dynamic>> distributors;
  final List<Map<String, dynamic>> outlets;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> crateTypes;
  final String? pickupLocationId;
  final String? fixedOutletId;
}

class _CrateMovementDialog extends StatefulWidget {
  const _CrateMovementDialog({required this.role});

  final String role;

  @override
  State<_CrateMovementDialog> createState() => _CrateMovementDialogState();
}

class _CrateMovementDialogState extends State<_CrateMovementDialog> {
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  late Future<_CrateMovementOptions> _options;
  String? _distributorId;
  String? _outletId;
  String? _crateTypeId;
  String _movementType = 'issued';
  String? _error;

  @override
  void initState() {
    super.initState();
    _options = _loadOptions();
  }

  Future<_CrateMovementOptions> _loadOptions() async {
    final client = Supabase.instance.client;
    final profile = await client
    .from('user_profiles')
    .select('external_outlet_id, pickup_location_id')
    .eq('user_id', client.auth.currentUser!.id)
    .single();
    final pickupLocationId = profile['pickup_location_id'] as String?;
    final fixedOutletId = profile['external_outlet_id'] as String?;
    final outletsQuery = client
    .from('external_outlets')
    .select('id, name, pickup_location_id');
    final outletRows = fixedOutletId != null
    ? await outletsQuery.eq('id', fixedOutletId)
    : pickupLocationId != null
        ? await outletsQuery.eq('pickup_location_id', pickupLocationId)
        : await outletsQuery.order('name');
    final outlets = (outletRows as List).cast<Map<String, dynamic>>();
    if (outlets.isEmpty) {
  throw StateError('لا توجد منافذ متاحة لتسجيل حركة البرانيك.');
    }
    final outletIds = outlets.map((row) => row['id'] as String).toList();
    final links = (await client
        .from('distributor_outlets')
        .select('distributor_id, external_outlet_id')
        .inFilter('external_outlet_id', outletIds))
    .cast<Map<String, dynamic>>();
    final distributorIds = links
    .map((row) => row['distributor_id'] as String)
    .toSet()
    .toList();
    final distributors = distributorIds.isEmpty
    ? <Map<String, dynamic>>[]
    : (await client
            .from('distributors')
            .select('id, name')
            .inFilter('id', distributorIds)
            .order('name'))
        .cast<Map<String, dynamic>>();
    final crateTypes = (await client
        .from('crate_types')
        .select('id, name')
        .eq('is_active', true)
        .order('name'))
    .cast<Map<String, dynamic>>();
    return _CrateMovementOptions(
  distributors: distributors,
  outlets: outlets,
  links: links,
  crateTypes: crateTypes,
  pickupLocationId: pickupLocationId,
  fixedOutletId: fixedOutletId,
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save(_CrateMovementOptions options) {
    final quantity = int.tryParse(_quantity.text.trim());
    if (options.distributors.isEmpty || options.crateTypes.isEmpty) {
  setState(() => _error = 'لا يوجد موزعون أو أنواع برانيك متاحة.');
  return;
    }
    if (_distributorId == null || _outletId == null || _crateTypeId == null) {
  setState(() => _error = 'اختر الموزع والمنفذ ونوع البرنيكة.');
  return;
    }
    if (quantity == null || quantity <= 0) {
  setState(() => _error = 'أدخل عددًا صحيحًا موجبًا.');
  return;
    }
    Navigator.pop(context, {
  'p_distributor_id': _distributorId,
  'p_external_outlet_id': _outletId,
  'p_pickup_location_id': options.pickupLocationId ??
      options.outlets.firstWhere(
        (outlet) => outlet['id'] == _outletId,
      )['pickup_location_id'],
  'p_crate_type_id': _crateTypeId,
  'p_movement_type': _movementType,
  'p_quantity': quantity,
  'p_reference_id': null,
  'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    });
  }

  List<Map<String, dynamic>> _outletsFor(_CrateMovementOptions options) {
    final allowedIds = options.links
        .where((link) => link['distributor_id'] == _distributorId)
        .map((link) => link['external_outlet_id'] as String)
        .toSet();
    return options.outlets
        .where((outlet) => allowedIds.contains(outlet['id']))
        .toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CrateMovementOptions>(
    future: _options,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AlertDialog(
          title: const Text('حركة برانيك'),
          content: Text('تعذر تحميل بيانات البرانيك: ${snapshot.error}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const AlertDialog(
          content: Center(child: CircularProgressIndicator()),
        );
      }
      final options = snapshot.data!;
      _distributorId ??= options.distributors.isEmpty
          ? null
          : options.distributors.first['id'] as String;
      final allowedOutlets = _outletsFor(options);
      _outletId ??= options.fixedOutletId ??
          (allowedOutlets.isEmpty
              ? null
              : allowedOutlets.first['id'] as String);
      _crateTypeId ??= options.crateTypes.isEmpty
          ? null
          : options.crateTypes.first['id'] as String;
      return AlertDialog(
        title: const Text('تسجيل حركة برانيك'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              DropdownButtonFormField<String>(
                value: _distributorId,
                decoration: const InputDecoration(labelText: 'الموزع'),
                items: options.distributors
                    .map((row) => DropdownMenuItem<String>(
                          value: row['id'] as String,
                          child: Text(row['name'] as String),
                        ))
                    .toList(),
                onChanged: (value) => setState(() {
                  _distributorId = value;
                  final linked = options.links
                      .where((link) => link['distributor_id'] == value)
                      .map((link) => link['external_outlet_id'] as String)
                      .toSet();
                  final linkedOutlets = options.outlets
                      .where((outlet) => linked.contains(outlet['id']))
                      .toList();
                  _outletId = options.fixedOutletId ??
                      (linkedOutlets.isEmpty
                          ? null
                          : linkedOutlets.first['id'] as String);
                }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _outletId,
                decoration: const InputDecoration(labelText: 'المنفذ'),
                items: allowedOutlets
                    .map((row) => DropdownMenuItem<String>(
                          value: row['id'] as String,
                          child: Text(row['name'] as String),
                        ))
                    .toList(),
                onChanged: options.fixedOutletId != null
                    ? null
                    : (value) => setState(() => _outletId = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _crateTypeId,
                decoration:
                    const InputDecoration(labelText: 'نوع البرنيكة'),
                items: options.crateTypes
                    .map((row) => DropdownMenuItem<String>(
                          value: row['id'] as String,
                          child: Text(row['name'] as String),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _crateTypeId = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _movementType,
                decoration: const InputDecoration(labelText: 'نوع الحركة'),
                items: const [
                  DropdownMenuItem(value: 'issued', child: Text('تسليم')),
                  DropdownMenuItem(value: 'returned', child: Text('استلام مرتجع')),
                  DropdownMenuItem(value: 'lost', child: Text('مفقود')),
                  DropdownMenuItem(value: 'damaged', child: Text('تالف')),
                ],
                onChanged: (value) =>
                    setState(() => _movementType = value!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العدد'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
              ),
              if (_error != null)
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => _save(options),
            child: const Text('تسجيل الحركة'),
          ),
        ],
      );
    },
  );
}

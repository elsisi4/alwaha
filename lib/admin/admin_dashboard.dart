import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_recipes_page.dart';
import 'app_releases_page.dart';
import 'signup_requests_page.dart';
import 'operational_workflows_page.dart';
import '../portal/role_home_page.dart';
import '../pricing/pricing_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة الواحة'),
            actions: [
              IconButton(
                tooltip: 'تسجيل الخروج',
                onPressed: () => Supabase.instance.client.auth.signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.receipt_long), text: 'الطلبات'),
                Tab(icon: Icon(Icons.factory_outlined), text: 'الإنتاج والتوزيع'),
                Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المخزون والبرانيك'),
                Tab(icon: Icon(Icons.payments_outlined), text: 'الحسابات والتحصيل'),
                Tab(icon: Icon(Icons.how_to_reg), text: 'طلبات التسجيل'),
                Tab(icon: Icon(Icons.settings_outlined), text: 'الإعدادات'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              OperationalWorkflowsPage(
                role: 'admin',
                section: OpsSection.orders,
              ),
              OperationalWorkflowsPage(
                role: 'admin',
                section: OpsSection.production,
              ),
              OperationalWorkflowsPage(
                role: 'admin',
                section: OpsSection.stock,
              ),
              RoleHomePage(role: 'accountant', embedded: true),
              SignupRequestsPage(),
              _SettingsMenu(),
            ],
          ),
        ),
      );
}

/// الإعدادات: ما يحتاجه المدير نادرًا (أسعار، أصناف، مستخدمون، وصفات).
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu();

  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsTile(
            icon: Icons.price_change,
            title: 'الأسعار والسياسات السعرية',
            subtitle: 'سعر الشراء من المصنع وسعر البيع لكل منفذ ونوع عميل',
            onTap: () => _open(
              context,
              'الأسعار والسياسات السعرية',
              const PricingPage(embedded: true),
            ),
          ),
          _SettingsTile(
            icon: Icons.inventory_2,
            title: 'الأصناف والمناديب والمنافذ',
            subtitle: 'إضافة الأصناف وتعديلها، المناديب، المنافذ، مواقع الاستلام',
            onTap: () => _open(
              context,
              'الأصناف والمناديب والمنافذ',
              const _CatalogManagement(),
            ),
          ),
          _SettingsTile(
            icon: Icons.manage_accounts,
            title: 'المستخدمون والصلاحيات',
            subtitle: 'إسناد دور لكل حساب: محاسب، إنتاج، منافذ، منفذ المصنع',
            onTap: () => _open(
              context,
              'المستخدمون والصلاحيات',
              const _UserRoleManagement(),
            ),
          ),
          _SettingsTile(
            icon: Icons.restaurant_menu,
            title: 'الوصفات والبرانيك',
            subtitle: 'الخامات، وصفة كل صنف، وسعة البرنيكة لكل صنف',
            onTap: () => _open(
              context,
              'الوصفات والبرانيك',
              const CatalogRecipesPage(),
            ),
          ),
          _SettingsTile(
            icon: Icons.system_update,
            title: 'إصدارات التطبيق',
            subtitle: 'نشر تحديث جديد لتطبيق المندوب أو الإدارة',
            onTap: () => _open(
              context,
              'إصدارات التطبيق',
              const AppReleasesPage(),
            ),
          ),
        ],
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xff176b55)),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );
}

enum _CatalogKind {
  products,
  customerTypes,
  distributors,
  pickupLocations,
  outlets,
}

class _CatalogManagement extends StatefulWidget {
  const _CatalogManagement();

  @override
  State<_CatalogManagement> createState() => _CatalogManagementState();
}

class _CatalogManagementState extends State<_CatalogManagement> {
  _CatalogKind _kind = _CatalogKind.products;
  late Future<List<Map<String, dynamic>>> _rows;
  List<Map<String, dynamic>> _customerTypes = [];
  List<Map<String, dynamic>> _pickupLocations = [];
  List<Map<String, dynamic>> _outletOptions = [];
  Map<String, Map<String, String>> _outletGroups = {};
  String _vehicleFilter = 'all';
  String _filterOutletId = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String get _table => switch (_kind) {
        _CatalogKind.products => 'products',
        _CatalogKind.customerTypes => 'customer_types',
        _CatalogKind.distributors => 'distributors',
        _CatalogKind.pickupLocations => 'pickup_locations',
        _CatalogKind.outlets => 'external_outlets',
      };

  String get _title => switch (_kind) {
        _CatalogKind.products => 'الأصناف',
        _CatalogKind.customerTypes => 'أنواع العملاء',
        _CatalogKind.distributors => 'الموزعون',
        _CatalogKind.pickupLocations => 'منافذ الاستلام',
        _CatalogKind.outlets => 'المنافذ الخارجية',
      };

  void _reload() {
    final client = Supabase.instance.client;
    _rows = client.from(_table).select().order('name').then(
          (rows) => (rows as List).cast<Map<String, dynamic>>(),
        );
    if (_kind == _CatalogKind.distributors) {
      Future.wait([
        client.from('customer_types').select('id, name').order('name'),
        client.from('external_outlets').select().order('name'),
        client
            .from('distributor_outlets')
            .select('distributor_id, external_outlet_id, vehicle_group'),
      ]).then((result) {
        final grouped = <String, List<String>>{};
        final groups = <String, Map<String, String>>{};
        for (final row in (result[2] as List).cast<Map<String, dynamic>>()) {
          grouped
              .putIfAbsent(row['distributor_id'] as String, () => [])
              .add(row['external_outlet_id'] as String);
          groups
              .putIfAbsent(row['distributor_id'] as String, () => {})[
                  row['external_outlet_id'] as String] =
              row['vehicle_group'] as String? ?? 'shared';
        }
        if (mounted) {
          setState(() {
            _customerTypes =
                (result[0] as List).cast<Map<String, dynamic>>();
            _outletOptions =
                (result[1] as List).cast<Map<String, dynamic>>();
            _outletLinks = grouped;
            _outletGroups = groups;
          });
        }
      }).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تحميل بيانات الموزعين: $error')),
          );
        }
      });
    } else if (_kind == _CatalogKind.outlets) {
      client.from('pickup_locations').select('id, name').order('name').then(
            (rows) {
              if (mounted) {
                setState(() => _pickupLocations =
                    (rows as List).cast<Map<String, dynamic>>());
              }
            },
          );
    }
    if (_kind != _CatalogKind.distributors &&
        _kind != _CatalogKind.outlets) {
      _customerTypes = [];
    }
    if (_kind != _CatalogKind.outlets) {
      _pickupLocations = [];
    }
    if (_kind != _CatalogKind.distributors) {
      _outletOptions = [];
      _outletLinks = {};
      _outletGroups = {};
    }
    if (mounted) setState(() {});
  }

  Map<String, List<String>> _outletLinks = {};

  Future<void> _edit([Map<String, dynamic>? row]) async {
    late final List<Map<String, dynamic>> data;
    try {
      data = await _rows;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل بيانات $_title: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    try {
      if (_kind == _CatalogKind.distributors) {
        final result = await Future.wait([
          Supabase.instance.client
              .from('customer_types')
              .select('id, name')
              .order('name'),
          Supabase.instance.client.from('external_outlets').select().order('name'),
          Supabase.instance.client
              .from('distributor_outlets')
              .select('distributor_id, external_outlet_id, vehicle_group'),
        ]);
        final links = <String, List<String>>{};
        final groups = <String, Map<String, String>>{};
        for (final item in (result[2] as List).cast<Map<String, dynamic>>()) {
          links
              .putIfAbsent(item['distributor_id'] as String, () => [])
              .add(item['external_outlet_id'] as String);
          groups
              .putIfAbsent(item['distributor_id'] as String, () => {})[
                  item['external_outlet_id'] as String] =
              item['vehicle_group'] as String? ?? 'shared';
        }
        _customerTypes = (result[0] as List).cast<Map<String, dynamic>>();
        _outletOptions = (result[1] as List).cast<Map<String, dynamic>>();
        _outletLinks = links;
        _outletGroups = groups;
      } else if (_kind == _CatalogKind.outlets) {
        final rows = await Supabase.instance.client
            .from('pickup_locations')
            .select('id, name')
            .order('name');
        _pickupLocations = (rows as List).cast<Map<String, dynamic>>();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل خيارات البيانات: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CatalogEditor(
        kind: _kind,
        row: row,
        customerTypes: _customerTypes,
        pickupLocations: _pickupLocations,
        outlets: (_kind == _CatalogKind.distributors
                ? _outletOptions
                : data)
            .where((item) =>
                item['is_active'] != false ||
                (row != null &&
                    (_outletLinks[row['id']] ?? []).contains(item['id'])))
            .toList(),
        linkedOutletIds:
            row == null ? const [] : (_outletLinks[row['id']] ?? const []),
        vehicleGroups: row == null
            ? const {}
            : (_outletGroups[row['id']] ?? const {}),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<_CatalogKind>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'نوع البيانات'),
              items: const [
                DropdownMenuItem(
                    value: _CatalogKind.products, child: Text('الأصناف')),
                DropdownMenuItem(
                    value: _CatalogKind.customerTypes,
                    child: Text('أنواع العملاء')),
                DropdownMenuItem(
                    value: _CatalogKind.distributors, child: Text('الموزعون')),
                DropdownMenuItem(
                    value: _CatalogKind.pickupLocations,
                    child: Text('منافذ الاستلام')),
                DropdownMenuItem(
                    value: _CatalogKind.outlets,
                    child: Text('المنافذ الخارجية')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _kind = value;
                    _filterOutletId = 'all';
                    _vehicleFilter = 'all';
                  });
                }
                _reload();
              },
            ),
          ),
          if (_kind == _CatalogKind.distributors)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filterOutletId,
                      decoration:
                          const InputDecoration(labelText: 'منفذ الموزع'),
                      items: [
                        const DropdownMenuItem(
                            value: 'all', child: Text('جميع المنافذ')),
                        ..._outletOptions.map((outlet) => DropdownMenuItem(
                              value: outlet['id'] as String,
                              child: Text(outlet['name'] as String),
                            )),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _filterOutletId = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _vehicleFilter,
                      decoration:
                          const InputDecoration(labelText: 'مجموعة السيارة'),
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('جميع المندوبين')),
                        DropdownMenuItem(
                            value: 'vehicle_1',
                            child: Text('السيارة الأولى')),
                        DropdownMenuItem(
                            value: 'vehicle_2',
                            child: Text('السيارة الثانية')),
                        DropdownMenuItem(
                            value: 'shared',
                            child: Text('مشترك / غير محدد')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _vehicleFilter = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Message(
                    message: 'تعذر تحميل $_title: ${snapshot.error}',
                    onRetry: _reload,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                final visibleRows = _kind != _CatalogKind.distributors
                    ? rows
                    : rows.where((row) {
                        final id = row['id'] as String;
                        final linkedOutlets = _outletLinks[id] ?? const [];
                        final groups = _outletGroups[id] ?? const {};
                        if (_filterOutletId != 'all' &&
                            !linkedOutlets.contains(_filterOutletId)) {
                          return false;
                        }
                        if (_vehicleFilter == 'all') return true;
                        if (_filterOutletId != 'all') {
                          return groups[_filterOutletId] == _vehicleFilter;
                        }
                        return groups.values.contains(_vehicleFilter);
                      }).toList();
                if (visibleRows.isEmpty) {
                  return Center(child: Text('لا توجد بيانات مطابقة في $_title.'));
                }
                return ListView.builder(
                  itemCount: visibleRows.length,
                  itemBuilder: (context, index) {
                    final row = visibleRows[index];
                    return ListTile(
                      title: Text(row['name'] as String? ??
                          row['code'] as String? ??
                          'بيان'),
                      subtitle: Text(_subtitle(row)),
                      trailing: IconButton(
                        tooltip: 'تعديل',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(row),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text('إضافة إلى $_title'),
            ),
          ),
        ],
      );

  String _subtitle(Map<String, dynamic> row) {
    final status = row['is_active'] == false ? 'متوقف' : 'نشط';
    return switch (_kind) {
      _CatalogKind.products => '${row['code']} — $status',
      _CatalogKind.customerTypes => 'نوع العميل',
      _CatalogKind.distributors =>
        'نوع العميل: ${_nameFor(_customerTypes, row['customer_type_id'])} — '
            'المنافذ المسموحة: ${(_outletLinks[row['id']] ?? []).length} — $status',
      _CatalogKind.pickupLocations => status,
      _CatalogKind.outlets =>
        '${row['outlet_type'] == 'factory_pickup' ? 'استلام مصنع' : 'منفذ خارجي'} — '
            'الأدوار: ${(row['allowed_roles'] as List? ?? const []).join('، ')} — '
            'منفذ الاستلام: ${_nameFor(_pickupLocations, row['pickup_location_id'])} — $status',
    };
  }
}

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({
    required this.kind,
    required this.customerTypes,
    required this.pickupLocations,
    required this.outlets,
    required this.linkedOutletIds,
    required this.vehicleGroups,
    this.row,
  });

  final _CatalogKind kind;
  final Map<String, dynamic>? row;
  final List<Map<String, dynamic>> customerTypes;
  final List<Map<String, dynamic>> pickupLocations;
  final List<Map<String, dynamic>> outlets;
  final List<String> linkedOutletIds;
  final Map<String, String> vehicleGroups;

  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _category;
  late final TextEditingController _quality;
  late final TextEditingController _salesUnit;
  late final TextEditingController _description;
  late final TextEditingController _imageUrl;
  late final TextEditingController _crateCapacity;
  late final Set<String> _selectedOutlets;
  late final Map<String, String> _vehicleGroups;
  String? _customerTypeId;
  String? _pickupLocationId;
  String _outletType = 'external';
  Set<String> _allowedRoles = {'outlet_manager', 'collector'};
  bool _active = true;
  bool _saving = false;
  String? _error;

  bool get _isProduct => widget.kind == _CatalogKind.products;
  bool get _isCustomerType => widget.kind == _CatalogKind.customerTypes;
  bool get _isDistributor => widget.kind == _CatalogKind.distributors;
  bool get _isOutlet => widget.kind == _CatalogKind.outlets;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.row?['name'] as String? ?? '');
    _code = TextEditingController(text: widget.row?['code'] as String? ?? '');
    _category = TextEditingController(
        text: widget.row?['category'] as String? ?? '');
    _quality =
        TextEditingController(text: widget.row?['quality'] as String? ?? '');
    _salesUnit = TextEditingController(
        text: widget.row?['sales_unit'] as String? ?? 'علبة');
    _description = TextEditingController(
        text: widget.row?['description'] as String? ?? '');
    _imageUrl = TextEditingController(
        text: widget.row?['image_url'] as String? ?? '');
    _crateCapacity = TextEditingController(
        text: '${widget.row?['crate_capacity'] ?? 75}');
    _customerTypeId = widget.row?['customer_type_id'] as String?;
    _pickupLocationId = widget.row?['pickup_location_id'] as String?;
    _active = widget.row?['is_active'] as bool? ?? true;
    _selectedOutlets = widget.linkedOutletIds.toSet();
    _vehicleGroups = {
      for (final outletId in widget.linkedOutletIds)
        outletId: widget.vehicleGroups[outletId] ?? 'shared',
    };
    _outletType = widget.row?['outlet_type'] as String? ?? 'external';
    _allowedRoles =
        (widget.row?['allowed_roles'] as List?)?.cast<String>().toSet() ??
            {'outlet_manager', 'collector'};
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _category.dispose();
    _quality.dispose();
    _salesUnit.dispose();
    _description.dispose();
    _imageUrl.dispose();
    _crateCapacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_isDistributor && _customerTypeId == null) ||
        (_isOutlet &&
            (_pickupLocationId == null || _allowedRoles.isEmpty))) {
      setState(() => _error = 'أكمل الحقول المطلوبة.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      final values = <String, dynamic>{
        'name': _name.text.trim(),
        if (!_isCustomerType) 'is_active': _active,
        if (_isProduct) 'code': _code.text.trim(),
        if (_isProduct) 'category': _category.text.trim(),
        if (_isProduct) 'quality': _quality.text.trim(),
        if (_isProduct) 'sales_unit': _salesUnit.text.trim(),
        if (_isProduct)
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        if (_isProduct)
          'image_url':
              _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        if (_isProduct)
          'crate_capacity':
              int.tryParse(_crateCapacity.text.trim()) ?? 75,
        if (_isDistributor) 'customer_type_id': _customerTypeId,
        if (_isOutlet) ...{
          'pickup_location_id': _pickupLocationId,
          'outlet_type': _outletType,
          'allowed_roles': _allowedRoles.toList(),
        },
      };
      final id = widget.row?['id'] as String?;
      if (_isDistributor) {
        await client.rpc('save_distributor_assignments', params: {
          'p_distributor_id': id,
          'p_name': _name.text.trim(),
          'p_customer_type_id': _customerTypeId,
          'p_is_active': _active,
          'p_outlet_assignments': _selectedOutlets
              .map((outletId) => {
                    'external_outlet_id': outletId,
                    'vehicle_group': _vehicleGroups[outletId] ?? 'shared',
                  })
              .toList(),
        });
      } else if (id == null) {
        await client.from(_tableName).insert(values);
      } else {
        await client.from(_tableName).update(values).eq('id', id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر الحفظ: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _tableName => switch (widget.kind) {
        _CatalogKind.products => 'products',
        _CatalogKind.customerTypes => 'customer_types',
        _CatalogKind.distributors => 'distributors',
        _CatalogKind.pickupLocations => 'pickup_locations',
        _CatalogKind.outlets => 'external_outlets',
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.row == null ? 'إضافة بيانات' : 'تعديل البيانات'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_isProduct)
                  TextFormField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: 'كود الصنف'),
                    validator: _required,
                  ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  validator: _required,
                ),
                if (_isProduct) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'التصنيف'),
                    validator: _required,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _quality,
                    decoration: const InputDecoration(labelText: 'الجودة'),
                    validator: _required,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _salesUnit,
                    decoration: const InputDecoration(labelText: 'وحدة البيع'),
                    validator: _required,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _imageUrl,
                    keyboardType: TextInputType.url,
                    decoration:
                        const InputDecoration(labelText: 'رابط الصورة (اختياري)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _crateCapacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد العبوات في البرنيكة',
                      helperText: 'تستخدم الكمية الجزئية برنيكة غير مكتملة.',
                    ),
                    validator: (value) {
                      final capacity = int.tryParse(value?.trim() ?? '');
                      return capacity == null || capacity <= 0
                          ? 'أدخل سعة صحيحة أكبر من صفر'
                          : null;
                    },
                  ),
                ],
                if (_isDistributor) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _customerTypeId,
                    decoration:
                        const InputDecoration(labelText: 'نوع العميل'),
                    items: widget.customerTypes
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _customerTypeId = value),
                  ),
                  const SizedBox(height: 8),
                  Text('منافذ الاستلام المسموحة',
                      style: Theme.of(context).textTheme.titleSmall),
                  ...widget.outlets.map<Widget>((outlet) {
                    final outletId = outlet['id'] as String;
                    final active = outlet['is_active'] != false;
                    final selected = _selectedOutlets.contains(outletId);
                    return CheckboxListTile(
                      dense: true,
                      title: Text(
                        '${outlet['name']}${active ? '' : ' (متوقف)'}',
                      ),
                      value: selected,
                      onChanged: !active && !selected
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selectedOutlets.add(outletId);
                                  _vehicleGroups[outletId] = 'shared';
                                } else {
                                  _selectedOutlets.remove(outletId);
                                  _vehicleGroups.remove(outletId);
                                }
                              }),
                    );
                  }).followedBy(
                    widget.outlets
                        .where((outlet) => _selectedOutlets
                            .contains(outlet['id'] as String))
                        .map<Widget>((outlet) {
                      final outletId = outlet['id'] as String;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(start: 24),
                        child: DropdownButtonFormField<String>(
                          value: _vehicleGroups[outletId] ?? 'shared',
                          decoration: InputDecoration(
                            labelText: 'مجموعة السيارة — ${outlet['name']}',
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'vehicle_1',
                                child: Text('السيارة الأولى')),
                            DropdownMenuItem(
                                value: 'vehicle_2',
                                child: Text('السيارة الثانية')),
                            DropdownMenuItem(
                                value: 'shared',
                                child: Text('مشترك / غير محدد')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _vehicleGroups[outletId] = value);
                            }
                          },
                        ),
                      );
                    }),
                  ),
                ],
                if (_isOutlet) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _outletType,
                    decoration: const InputDecoration(labelText: 'نوع المنفذ'),
                    items: const [
                      DropdownMenuItem(
                          value: 'external', child: Text('منفذ خارجي')),
                      DropdownMenuItem(
                          value: 'factory_pickup',
                          child: Text('استلام من المصنع')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _outletType = value);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: _pickupLocationId,
                    decoration:
                        const InputDecoration(labelText: 'منفذ الاستلام'),
                    items: widget.pickupLocations
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _pickupLocationId = value),
                  ),
                  const SizedBox(height: 8),
                  Text('الأدوار المسموح بها على هذا المنفذ',
                      style: Theme.of(context).textTheme.titleSmall),
                  for (final role in const {
                    'outlet_manager': 'مسؤول المنفذ',
                    'collector': 'المحصّل',
                  }.entries)
                    CheckboxListTile(
                      dense: true,
                      title: Text(role.value),
                      value: _allowedRoles.contains(role.key),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _allowedRoles.add(role.key);
                        } else {
                          _allowedRoles.remove(role.key);
                        }
                      }),
                    ),
                  if (_allowedRoles.isEmpty)
                    Text(
                      'يجب اختيار دور واحد على الأقل.',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                ],
                const SizedBox(height: 8),
                if (!_isCustomerType)
                  SwitchListTile(
                    title: const Text('نشط'),
                    value: _active,
                    onChanged: (value) => setState(() => _active = value),
                  ),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
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
            child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
          ),
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;
}

class _UserRoleManagement extends StatefulWidget {
  const _UserRoleManagement();

  @override
  State<_UserRoleManagement> createState() => _UserRoleManagementState();
}

class _UserRoleManagementState extends State<_UserRoleManagement> {
  late Future<_UserData> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = Supabase.instance.client;
    _data = Future.wait<dynamic>([
      client.rpc('admin_list_users_v2'),
      client.from('distributors').select('id, name, is_active').order('name'),
      client
          .from('external_outlets')
          .select('id, name, is_active')
          .order('name'),
      client.from('pickup_locations').select('id, name, is_active').order('name'),
    ]).then((result) => _UserData(
          profiles: (result[0] as List).cast<Map<String, dynamic>>(),
          distributors: (result[1] as List).cast<Map<String, dynamic>>(),
          outlets: (result[2] as List).cast<Map<String, dynamic>>(),
          pickupLocations: (result[3] as List).cast<Map<String, dynamic>>(),
        ));
    setState(() {});
  }

  Future<void> _assign([Map<String, dynamic>? profile]) async {
    final data = await _data;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoleEditor(data: data, profile: profile),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_UserData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              message: 'تعذر تحميل المستخدمين: ${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: data.profiles.map((profile) {
                    final role = profile['role'] as String;
                    final subject = profile['distributor_id'] ??
                        profile['external_outlet_id'] ??
                        profile['pickup_location_id'];
                    return ListTile(
                      title: Text(profile['email'] as String? ??
                          profile['user_id'] as String),
                      subtitle: Text(
                        '${_roleLabels[role] ?? role}'
                        '${subject == null ? '' : ' — ${_nameFor(
                            role == 'distributor'
                                ? data.distributors
                                : role == 'factory_outlet_manager'
                                    ? data.pickupLocations
                                    : data.outlets,
                            subject,
                          )}'}',
                      ),
                      trailing: IconButton(
                        tooltip: 'تغيير الدور',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _assign(profile),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _assign(),
                  icon: const Icon(Icons.person_add),
                  label: const Text('إسناد مستخدم مسجل'),
                ),
              ),
            ],
          );
        },
      );
}

class _UserData {
  const _UserData({
    required this.profiles,
    required this.distributors,
    required this.outlets,
    required this.pickupLocations,
  });

  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> distributors;
  final List<Map<String, dynamic>> outlets;
  final List<Map<String, dynamic>> pickupLocations;
}

class _RoleEditor extends StatefulWidget {
  const _RoleEditor({required this.data, this.profile});

  final _UserData data;
  final Map<String, dynamic>? profile;

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  final _email = TextEditingController();
  String _role = 'distributor';
  String? _distributorId;
  String? _outletId;
  String? _pickupLocationId;
  bool _saving = false;
  String? _error;

  bool get _needsDistributor => _role == 'distributor';
  bool get _needsOutlet => _role == 'outlet_manager' || _role == 'collector';
  bool get _needsPickupLocation => _role == 'factory_outlet_manager';

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      _role = profile['role'] as String;
      _distributorId = profile['distributor_id'] as String?;
      _outletId = profile['external_outlet_id'] as String?;
      _pickupLocationId = profile['pickup_location_id'] as String?;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.profile == null && _email.text.trim().isEmpty) {
      setState(() => _error = 'أدخل بريد المستخدم المسجل.');
      return;
    }
    if ((_needsDistributor && _distributorId == null) ||
        (_needsOutlet && _outletId == null) ||
        (_needsPickupLocation && _pickupLocationId == null)) {
      setState(() => _error = 'اختر الموزع أو المنفذ المرتبط بالدور.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final params = {
        'p_role': _role,
        'p_distributor_id': _needsDistributor ? _distributorId : null,
        'p_external_outlet_id': _needsOutlet ? _outletId : null,
        'p_pickup_location_id':
            _needsPickupLocation ? _pickupLocationId : null,
      };
      if (widget.profile == null) {
        await client.rpc('assign_user_role_v2', params: {
          ...params,
          'p_email': _email.text.trim(),
        });
      } else {
        await client.rpc('update_user_role_v2', params: {
          ...params,
          'p_user_id': widget.profile!['user_id'],
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر إسناد الدور: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.profile == null ? 'إسناد دور' : 'تغيير الدور'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (widget.profile == null)
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'بريد مستخدم مسجل في النظام'),
                )
              else
                Text(widget.profile!['email'] as String? ??
                    widget.profile!['user_id'] as String),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: _roleLabels.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (value) => setState(() {
                  _role = value!;
                  _distributorId = null;
                  _outletId = null;
                  _pickupLocationId = null;
                }),
              ),
              if (_needsDistributor) ...[
                const SizedBox(height: 12),
                _referenceDropdown(
                  label: 'الموزع',
                  rows: widget.data.distributors,
                  value: _distributorId,
                  onChanged: (value) =>
                      setState(() => _distributorId = value),
                ),
              ],
              if (_needsOutlet) ...[
                const SizedBox(height: 12),
                _referenceDropdown(
                  label: 'المنفذ',
                  rows: widget.data.outlets,
                  value: _outletId,
                  onChanged: (value) => setState(() => _outletId = value),
                ),
              ],
              if (_needsPickupLocation) ...[
                const SizedBox(height: 12),
                _referenceDropdown(
                  label: 'منفذ المصنع',
                  rows: widget.data.pickupLocations,
                  value: _pickupLocationId,
                  onChanged: (value) =>
                      setState(() => _pickupLocationId = value),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
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
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الدور'),
          ),
        ],
      );
}

DropdownButtonFormField<String> _referenceDropdown({
  required String label,
  required List<Map<String, dynamic>> rows,
  required String? value,
  required ValueChanged<String?> onChanged,
}) =>
    DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: rows
          .map((row) => DropdownMenuItem<String>(
                value: row['id'] as String,
                child: Text(row['name'] as String),
              ))
          .toList(),
      onChanged: onChanged,
    );

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onRetry});

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
              OutlinedButton(
                  onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

String _nameFor(List<Map<String, dynamic>> rows, dynamic id) {
  for (final row in rows) {
    if (row['id'] == id) return row['name'] as String;
  }
  return 'غير محدد';
}

const _roleLabels = {
  'pending': 'غير مسند',
  'admin': 'مدير النظام',
  'accountant': 'المحاسب',
  'production_manager': 'مسؤول الإنتاج',
  'factory_outlet_manager': 'مسؤول منفذ المصنع',
  'outlet_manager': 'مسؤول المنفذ',
  'collector': 'المحصل',
  'distributor': 'الموزع',
};

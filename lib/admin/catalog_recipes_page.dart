import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CatalogRecipesPage extends StatelessWidget {
  const CatalogRecipesPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'الوصفات'),
                Tab(text: 'الخامات'),
                Tab(text: 'البرانيك'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RecipesTab(key: const ValueKey('recipes')),
                  _RawMaterialsTab(key: const ValueKey('materials')),
                  _CrateTypesTab(key: const ValueKey('crates')),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RecipesTab extends StatefulWidget {
  const _RecipesTab({super.key});

  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  late Future<List<Map<String, dynamic>>> _products;
  late Future<List<Map<String, dynamic>>> _materials;
  String? _productId;
  Future<List<Map<String, dynamic>>>? _versions;
  final Map<String, Future<List<Map<String, dynamic>>>> _versionLines = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = Supabase.instance.client;
    _products = client
        .from('products')
        .select('id, code, name')
        .order('name')
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
    _materials = client
        .from('raw_materials')
        .select('id, code, name, unit, is_active')
        .order('name')
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
    if (_productId != null) _loadVersions();
    setState(() {});
  }

  void _loadVersions() {
    if (_productId == null) {
      _versions = Future.value([]);
      return;
    }
    _versions = Supabase.instance.client
        .from('product_recipe_versions')
        .select('id, version_number, starts_at, created_at')
        .eq('product_id', _productId!)
        .order('version_number', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
    _versionLines.clear();
  }

  Future<List<Map<String, dynamic>>> _loadVersionLines(String versionId) =>
      Supabase.instance.client
          .from('product_recipe_lines')
          .select(
              'quantity_per_sales_unit, waste_percent, raw_materials(name, unit)')
          .eq('version_id', versionId)
          .then((rows) => (rows as List).cast<Map<String, dynamic>>());

  Future<void> _addRecipe(List<Map<String, dynamic>> materials) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeEditor(
        productId: _productId!,
        materials: materials,
      ),
    );
    if (saved == true && mounted) {
      setState(_loadVersions);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: Future.wait([_products, _materials]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: 'تعذر تحميل بيانات الوصفات: ${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data![0];
          final materials = snapshot.data![1];
          if (_productId == null && products.isNotEmpty) {
            _productId = products.first['id'] as String;
            _loadVersions();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: _productId,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items: products
                    .map((product) => DropdownMenuItem<String>(
                          value: product['id'] as String,
                          child: Text(
                              '${product['code']} — ${product['name']}'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() {
                  _productId = value;
                  _loadVersions();
                }),
              ),
              if (products.isEmpty)
                const ListTile(title: Text('أضف صنفًا قبل إعداد وصفته.')),
              if (_productId != null) ...[
                const SizedBox(height: 12),
                _ProductCrateSelector(
                  key: ValueKey(_productId),
                  productId: _productId!,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: materials.isEmpty
                        ? null
                        : () => _addRecipe(materials),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة إصدار وصفة'),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _versions,
                  builder: (context, versionsSnapshot) {
                    if (versionsSnapshot.hasError) {
                      return Text(
                          'تعذر تحميل الإصدارات: ${versionsSnapshot.error}');
                    }
                    if (!versionsSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final versions = versionsSnapshot.data!;
                    if (versions.isEmpty) {
                      return const ListTile(
                        title: Text('لا توجد وصفة مسجلة لهذا الصنف.'),
                      );
                    }
                    return Column(
                      children: versions.map((version) {
                        final id = version['id'] as String;
                        final lines = _versionLines.putIfAbsent(
                          id,
                          () => _loadVersionLines(id),
                        );
                        return Card(
                          child: ExpansionTile(
                            title: Text(
                                'الإصدار ${version['version_number']}'),
                            subtitle: Text(
                                'ساري من ${_dateLabel(version['starts_at'])}'),
                            children: [
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: lines,
                                builder: (context, linesSnapshot) {
                                  if (linesSnapshot.hasError) {
                                    return ListTile(
                                      title: Text(
                                          'تعذر تحميل مكونات الوصفة: ${linesSnapshot.error}'),
                                    );
                                  }
                                  if (!linesSnapshot.hasData) {
                                    return const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  return Column(
                                    children: linesSnapshot.data!.map((line) {
                                      final material = line['raw_materials']
                                          as Map<String, dynamic>;
                                      return ListTile(
                                        dense: true,
                                        title:
                                            Text(material['name'] as String),
                                        subtitle: Text(
                                            'هالك ${line['waste_percent']}%'),
                                        trailing: Text(
                                          '${line['quantity_per_sales_unit']} '
                                          '${material['unit']} / وحدة بيع',
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ],
          );
        },
      );
}

class _RecipeEditor extends StatefulWidget {
  const _RecipeEditor({
    required this.productId,
    required this.materials,
  });

  final String productId;
  final List<Map<String, dynamic>> materials;

  @override
  State<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<_RecipeEditor> {
  final _formKey = GlobalKey<FormState>();
  final List<_RecipeDraftLine> _lines = [_RecipeDraftLine()];
  DateTime _startsAt = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _startsAt = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.any((line) => line.materialId == null)) {
      setState(() => _error = 'اختر خامة لكل بند.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('save_product_recipe', params: {
        'p_product_id': widget.productId,
        'p_starts_at': _startsAt.toUtc().toIso8601String(),
        'p_lines': _lines
            .map((line) => {
                  'raw_material_id': line.materialId,
                  'quantity_per_sales_unit':
                      num.parse(line.quantity.text.trim()),
                  'waste_percent': line.waste.text.trim().isEmpty
                      ? 0
                      : num.parse(line.waste.text.trim()),
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ الوصفة: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إضافة إصدار وصفة'),
        content: SizedBox(
          width: 580,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _selectDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('ساري من ${_dateLabel(_startsAt.toIso8601String())}'),
                ),
                const SizedBox(height: 12),
                ..._lines.asMap().entries.map((entry) {
                  final index = entry.key;
                  final line = entry.value;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: line.materialId,
                                  decoration:
                                      const InputDecoration(labelText: 'الخامة'),
                                  items: widget.materials
                                      .where(
                                          (item) => item['is_active'] == true)
                                      .map((item) =>
                                          DropdownMenuItem<String>(
                                            value: item['id'] as String,
                                            child: Text(
                                                '${item['name']} (${item['unit']})'),
                                          ))
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => line.materialId = value),
                                ),
                              ),
                              IconButton(
                                tooltip: 'حذف البند',
                                onPressed: _saving || _lines.length == 1
                                    ? null
                                    : () => setState(() {
                                          _lines.removeAt(index).dispose();
                                        }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: line.quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'الكمية لكل وحدة بيع'),
                                  validator: _positiveNumber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: line.waste,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'الهالك المتوقع %'),
                                  validator: _wasteNumber,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _lines.add(_RecipeDraftLine())),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة خامة'),
                  ),
                ),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
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
}

class _RecipeDraftLine {
  String? materialId;
  final quantity = TextEditingController();
  final waste = TextEditingController(text: '0');

  void dispose() {
    quantity.dispose();
    waste.dispose();
  }
}

class _ProductCrateSelector extends StatefulWidget {
  const _ProductCrateSelector({required this.productId, super.key});

  final String productId;

  @override
  State<_ProductCrateSelector> createState() => _ProductCrateSelectorState();
}

class _ProductCrateSelectorState extends State<_ProductCrateSelector> {
  late Future<_CrateSelection> _selection;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = Supabase.instance.client;
    _selection = Future.wait([
      client
          .from('crate_types')
          .select('id, name, capacity, is_active')
          .eq('is_active', true)
          .order('name'),
      client
          .from('product_crate_types')
          .select('crate_type_id')
          .eq('product_id', widget.productId),
    ]).then((result) => _CrateSelection(
          crateTypes: (result[0] as List).cast<Map<String, dynamic>>(),
          selectedIds: (result[1] as List)
              .cast<Map<String, dynamic>>()
              .map((row) => row['crate_type_id'] as String)
              .toSet(),
        ));
    setState(() {});
  }

  Future<void> _toggle(String crateId, bool selected) async {
    try {
      final query = Supabase.instance.client
          .from('product_crate_types');
      if (selected) {
        await query.insert({
          'product_id': widget.productId,
          'crate_type_id': crateId,
        });
      } else {
        await query
            .delete()
            .eq('product_id', widget.productId)
            .eq('crate_type_id', crateId);
      }
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تعديل أنواع البرانيك: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: FutureBuilder<_CrateSelection>(
          future: _selection,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(
                  title: Text('تعذر تحميل أنواع البرانيك: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              );
            }
            final selection = snapshot.data!;
            return ExpansionTile(
              title: const Text('أنواع البرانيك المناسبة للصنف'),
              children: selection.crateTypes.map((crate) {
                final id = crate['id'] as String;
                return CheckboxListTile(
                  dense: true,
                  value: selection.selectedIds.contains(id),
                  title: Text(crate['name'] as String),
                  subtitle: Text('السعة: ${crate['capacity']} وحدة'),
                  onChanged: (checked) =>
                      _toggle(id, checked ?? false),
                );
              }).toList(),
            );
          },
        ),
      );
}

class _CrateSelection {
  const _CrateSelection({required this.crateTypes, required this.selectedIds});

  final List<Map<String, dynamic>> crateTypes;
  final Set<String> selectedIds;
}

class _RawMaterialsTab extends StatefulWidget {
  const _RawMaterialsTab({super.key});

  @override
  State<_RawMaterialsTab> createState() => _RawMaterialsTabState();
}

class _RawMaterialsTabState extends State<_RawMaterialsTab> {
  late Future<List<Map<String, dynamic>>> _materials;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _materials = Supabase.instance.client
        .from('raw_materials')
        .select()
        .order('name')
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
    setState(() {});
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RawMaterialEditor(row: row),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _materials,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: 'تعذر تحميل الخامات: ${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: rows.map((row) {
                    return ListTile(
                      title: Text('${row['name']} — ${row['code']}'),
                      subtitle: Text(
                          '${row['unit']} — ${row['is_active'] == true ? 'نشط' : 'متوقف'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(row),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة خامة'),
                ),
              ),
            ],
          );
        },
      );
}

class _RawMaterialEditor extends StatefulWidget {
  const _RawMaterialEditor({this.row});

  final Map<String, dynamic>? row;

  @override
  State<_RawMaterialEditor> createState() => _RawMaterialEditorState();
}

class _RawMaterialEditorState extends State<_RawMaterialEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _description;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.row?['code'] as String? ?? '');
    _name = TextEditingController(text: widget.row?['name'] as String? ?? '');
    _unit = TextEditingController(text: widget.row?['unit'] as String? ?? '');
    _description = TextEditingController(
        text: widget.row?['description'] as String? ?? '');
    _active = widget.row?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _unit.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = {
        'code': _code.text.trim(),
        'name': _name.text.trim(),
        'unit': _unit.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'is_active': _active,
      };
      final id = widget.row?['id'] as String?;
      if (id == null) {
        await Supabase.instance.client.from('raw_materials').insert(values);
      } else {
        await Supabase.instance.client
            .from('raw_materials')
            .update(values)
            .eq('id', id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ الخامة: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.row == null ? 'إضافة خامة' : 'تعديل خامة'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'كود الخامة'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم الخامة'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'وحدة القياس'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
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
}

class _CrateTypesTab extends StatefulWidget {
  const _CrateTypesTab({super.key});

  @override
  State<_CrateTypesTab> createState() => _CrateTypesTabState();
}

class _CrateTypesTabState extends State<_CrateTypesTab> {
  late Future<List<Map<String, dynamic>>> _crateTypes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _crateTypes = Supabase.instance.client
        .from('crate_types')
        .select()
        .order('name')
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
    setState(() {});
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CrateTypeEditor(row: row),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _crateTypes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: 'تعذر تحميل البرانيك: ${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: snapshot.data!.map((row) {
                    return ListTile(
                      title: Text('${row['name']} — ${row['code']}'),
                      subtitle: Text(
                          'السعة: ${row['capacity']} وحدة — ${row['is_active'] == true ? 'نشط' : 'متوقف'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(row),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة نوع برنيكة'),
                ),
              ),
            ],
          );
        },
      );
}

class _CrateTypeEditor extends StatefulWidget {
  const _CrateTypeEditor({this.row});

  final Map<String, dynamic>? row;

  @override
  State<_CrateTypeEditor> createState() => _CrateTypeEditorState();
}

class _CrateTypeEditorState extends State<_CrateTypeEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.row?['code'] as String? ?? '');
    _name = TextEditingController(text: widget.row?['name'] as String? ?? '');
    _capacity = TextEditingController(
        text: widget.row?['capacity']?.toString() ?? '');
    _active = widget.row?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = {
        'code': _code.text.trim(),
        'name': _name.text.trim(),
        'capacity': int.parse(_capacity.text.trim()),
        'is_active': _active,
      };
      final id = widget.row?['id'] as String?;
      if (id == null) {
        await Supabase.instance.client.from('crate_types').insert(values);
      } else {
        await Supabase.instance.client
            .from('crate_types')
            .update(values)
            .eq('id', id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ نوع البرنيكة: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.row == null ? 'إضافة نوع برنيكة' : 'تعديل نوع برنيكة'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'الكود'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'السعة بوحدات البيع'),
                  validator: _positiveInteger,
                ),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
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
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

String? _positiveNumber(String? value) {
  final number = num.tryParse(value?.trim() ?? '');
  return number == null || number <= 0 ? 'أدخل رقمًا أكبر من صفر' : null;
}

String? _wasteNumber(String? value) {
  final number = num.tryParse(value?.trim() ?? '');
  return number == null || number < 0 || number > 100
      ? 'أدخل نسبة بين 0 و100'
      : null;
}

String? _positiveInteger(String? value) {
  final number = int.tryParse(value?.trim() ?? '');
  return number == null || number <= 0 ? 'أدخل عددًا صحيحًا أكبر من صفر' : null;
}

String _dateLabel(dynamic value) {
  if (value is! String) return '$value';
  return value.length >= 10 ? value.substring(0, 10) : value;
}

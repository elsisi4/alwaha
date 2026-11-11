import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/alwaha_theme.dart';
import '../theme/glass_widgets.dart';

/// الصفحة الرئيسية للمدير: أرقام اليوم ورسم المبيعات الشهرية.
/// [onOpen] يفتح تبويب الشريط السفلي (1 الطلبات، 2 الإنتاج، 3 الحسابات، 4 المزيد).
class AdminHome extends StatefulWidget {
  const AdminHome({required this.onOpen, super.key});

  final void Function(int index) onOpen;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  static final _number = NumberFormat('#,##0', 'en_US');
  late Future<Map<String, dynamic>> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final result =
        await Supabase.instance.client.rpc('admin_dashboard_summary');
    return Map<String, dynamic>.from(result as Map);
  }

  void _reload() {
    setState(() {
      _summary = _load();
    });
  }

  int _int(Map<String, dynamic> data, String key) =>
      (data[key] as num?)?.toInt() ?? 0;

  Widget _stat({
    required String title,
    required int value,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: GlowCard(
          accent: accent,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 34, color: accent),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      color: AlwahaColors.textMuted,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                _number.format(value),
                style: TextStyle(
                  color: accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعذر تحميل اللوحة: ${snapshot.error}',
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
          final monthly = (data['monthly_sales'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final values =
              monthly.map((e) => (e['total'] as num).toDouble()).toList();
          final labels = monthly.map((e) => e['month'] as String).toList();
          final monthTotal = values.isEmpty ? 0.0 : values.last;
          final pending = _int(data, 'pending_signups');
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Row(
                  children: [
                    const LogoMark(size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('لوحة التحكم',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                      tooltip: 'تحديث',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _stat(
                      title: 'طلبات جديدة',
                      value: _int(data, 'new_orders'),
                      icon: Icons.assignment_outlined,
                      accent: AlwahaColors.gold,
                      onTap: () => widget.onOpen(1),
                    ),
                    const SizedBox(width: 10),
                    _stat(
                      title: 'الإنتاج اليومي',
                      value: _int(data, 'today_production'),
                      icon: Icons.precision_manufacturing_outlined,
                      accent: AlwahaColors.green,
                      onTap: () => widget.onOpen(2),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _stat(
                      title: 'قيد الإنتاج',
                      value: _int(data, 'orders_in_production'),
                      icon: Icons.local_fire_department_outlined,
                      accent: AlwahaColors.teal,
                      onTap: () => widget.onOpen(2),
                    ),
                    const SizedBox(width: 10),
                    _stat(
                      title: 'جاهزة للتسليم',
                      value: _int(data, 'orders_ready'),
                      icon: Icons.local_shipping_outlined,
                      accent: AlwahaColors.sky,
                      onTap: () => widget.onOpen(1),
                    ),
                  ],
                ),
                GlowCard(
                  accent: AlwahaColors.sky,
                  onTap: () => widget.onOpen(3),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up,
                          size: 38, color: AlwahaColors.sky),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إجمالي مبيعات الشهر',
                                style: TextStyle(
                                    color: AlwahaColors.textMuted,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              '${_number.format(monthTotal)} جنيه',
                              style: const TextStyle(
                                color: AlwahaColors.sky,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                GlowCard(
                  accent: AlwahaColors.teal,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تحليل المبيعات الشهرية',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 180,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SalesChartPainter(values, labels),
                        ),
                      ),
                    ],
                  ),
                ),
                if (pending > 0)
                  GlowCard(
                    accent: AlwahaColors.gold,
                    onTap: () => widget.onOpen(4),
                    child: Row(
                      children: [
                        const Icon(Icons.how_to_reg,
                            color: AlwahaColors.gold, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$pending طلب تسجيل مندوب بانتظار موافقتك',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class _SalesChartPainter extends CustomPainter {
  _SalesChartPainter(this.values, this.labels);

  final List<double> values;
  final List<String> labels;

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 22.0;
    final chart = Rect.fromLTWH(0, 6, size.width, size.height - labelHeight - 6);
    final maxValue = math.max(values.reduce(math.max), 1.0);

    final grid = Paint()
      ..color = const Color(0x22ffffff)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? chart.center.dx
              : chart.left + chart.width * i / (values.length - 1),
          chart.bottom - chart.height * (values[i] / maxValue),
        ),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final control = (previous.dx + current.dx) / 2;
      line.cubicTo(control, previous.dy, control, current.dy, current.dx,
          current.dy);
    }

    final fill = Path.from(line)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x5522d3b6), Color(0x0022d3b6)],
        ).createShader(chart),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AlwahaColors.teal.withAlpha(140)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AlwahaColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 5, Paint()..color = AlwahaColors.gold);
    canvas.drawCircle(
      points.last,
      9,
      Paint()
        ..color = AlwahaColors.gold.withAlpha(80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    for (var i = 0; i < labels.length; i++) {
      final monthIndex = (int.tryParse(labels[i].split('-').last) ?? 1) - 1;
      final painter = TextPainter(
        text: TextSpan(
          text: _months[monthIndex.clamp(0, 11)],
          style: const TextStyle(color: AlwahaColors.textMuted, fontSize: 11),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      painter.paint(
        canvas,
        Offset(points[i].dx - painter.width / 2, size.height - labelHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(_SalesChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.labels != labels;
}

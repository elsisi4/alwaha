import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/operational_workflows_page.dart';

/// شاشة مسؤول الإنتاج على الهاتف: الكميات المطلوبة مجمّعة وحساب الخامات،
/// ثم إدخال الكمية المنتجة فعليًا فقط، بدون أسعار أو حسابات.
class ProductionHome extends StatelessWidget {
  const ProductionHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الواحة — الإنتاج'),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: const OperationalWorkflowsPage(
          role: 'production_manager',
          section: OpsSection.production,
        ),
      );
}

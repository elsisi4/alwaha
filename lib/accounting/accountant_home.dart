import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/operational_workflows_page.dart';
import 'outlet_accounts_page.dart';

/// شاشة المحاسب: اعتماد الطلبات أو رفضها، والحسابات حسب المنفذ، والمرتجعات والبرانيك.
class AccountantHome extends StatefulWidget {
  const AccountantHome({super.key});

  @override
  State<AccountantHome> createState() => _AccountantHomeState();
}

class _AccountantHomeState extends State<AccountantHome> {
  int _index = 0;

  static const _titles = ['الطلبات', 'الحسابات والتحصيل', 'المرتجعات والبرانيك'];

  Widget _page() => switch (_index) {
        0 => const OperationalWorkflowsPage(
            role: 'accountant',
            section: OpsSection.orders,
          ),
        1 => const OutletAccountsPage(),
        _ => const OperationalWorkflowsPage(
            role: 'accountant',
            section: OpsSection.stock,
          ),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('الواحة — ${_titles[_index]}'),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: KeyedSubtree(key: ValueKey(_index), child: _page()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'الطلبات',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'الحسابات',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'المرتجعات',
            ),
          ],
        ),
      );
}

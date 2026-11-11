import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_dashboard.dart';
import 'accounting/accountant_home.dart';
import 'auth/distributor_auth.dart';
import 'theme/alwaha_theme.dart';
import 'theme/glass_widgets.dart';
import 'production/production_home.dart';
import 'update/app_update.dart';
import 'portal/role_home_page.dart';

/// التطبيقان يعملان من نفس الكود: staff للإدارة والمنافذ والإنتاج، وdistributor للمندوب.
enum AppMode { staff, distributor }

Future<void> main() => runAlWaha(AppMode.staff);

Future<void> runAlWaha(AppMode mode) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final supabaseConfigured = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  if (supabaseConfigured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  runApp(AlWahaApp(supabaseConfigured: supabaseConfigured, mode: mode));

  if (supabaseConfigured) {
    Future<void>.delayed(
      const Duration(seconds: 2),
      () => checkForUpdate(mode == AppMode.distributor ? 'distributor' : 'admin'),
    );
  }
}

class AlWahaApp extends StatelessWidget {
  const AlWahaApp({
    required this.supabaseConfigured,
    required this.mode,
    super.key,
  });

  final bool supabaseConfigured;
  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: mode == AppMode.distributor ? 'الواحة | المندوب' : 'الواحة | الإدارة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAlwahaTheme(),
      builder: (context, child) => Stack(
        children: [
          const Positioned.fill(child: AnimatedGlowBackground()),
          if (child != null) SafeArea(top: false, child: child),
        ],
      ),
      home: _ConfigurationGate(supabaseConfigured: supabaseConfigured, mode: mode),
    );
  }
}

class _ConfigurationGate extends StatelessWidget {
  const _ConfigurationGate({required this.supabaseConfigured, required this.mode});

  final bool supabaseConfigured;
  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    if (!supabaseConfigured) {
      return const _ConfigurationRequired();
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        if (Supabase.instance.client.auth.currentUser == null) {
          return _SignInPage(mode: mode);
        }
        return _RoleRouter(mode: mode);
      },
    );
  }
}

class _RoleRouter extends StatelessWidget {
  const _RoleRouter({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<Map<String, dynamic>>(
          future: Supabase.instance.client
              .from('user_profiles')
              .select('role')
              .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
              .single(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'تعذر تحميل صلاحيات الحساب: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Supabase.instance.client.auth.signOut(),
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final role = snapshot.data!['role'] as String;
            if (mode == AppMode.distributor) {
              if (role == 'distributor') return RoleHomePage(role: role);
              if (role == 'pending') return const PendingApprovalPage();
              return const WrongAppPage(
                message: 'هذا الحساب خاص بالإدارة. استخدم تطبيق الإدارة.',
              );
            }
            if (role == 'distributor') {
              return const WrongAppPage(
                message: 'هذا حساب مندوب. استخدم تطبيق المندوب.',
              );
            }
            if (role == 'production_manager') return const ProductionHome();
            if (role == 'accountant') return const AccountantHome();
            if (role == 'admin') return const AdminDashboard();
            if (role == 'pending') return const _AccessDenied();
            return RoleHomePage(role: role);
          },
        ),
      );
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('لم يحدد المدير صلاحيات هذا الحساب بعد.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      );
}

class _ConfigurationRequired extends StatelessWidget {
  const _ConfigurationRequired();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'أضف رابط Supabase ومفتاح anon عند التشغيل '
              'باستخدام SUPABASE_URL وSUPABASE_ANON_KEY.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class _SignInPage extends StatefulWidget {
  const _SignInPage({required this.mode});

  final AppMode mode;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        // الدخول يقبل رقم الهاتف أو البريد: كل حساب مسجل برقمه يدخل برقمه
        // حتى بعد أن يمنحه المدير دورًا إداريًا.
        email: widget.mode == AppMode.distributor ||
                !_email.text.contains('@')
            ? phoneToEmail(_email.text)
            : _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'تعذر تسجيل الدخول: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: const BorderSide(color: AlwahaColors.glassBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LogoMark(size: 104),
                        const SizedBox(height: 16),
                        Text('الواحة', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AlwahaColors.gold, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(widget.mode == AppMode.distributor ? 'تطبيق المندوب' : 'إدارة المصنع والتوزيع', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AlwahaColors.textMuted)),
                        const SizedBox(height: 26),
                  TextField(
                    controller: _email,
                    keyboardType: widget.mode == AppMode.distributor
                        ? TextInputType.phone
                        : TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: widget.mode == AppMode.distributor
                          ? 'رقم الهاتف'
                          : 'البريد الإلكتروني أو رقم الهاتف',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _busy ? null : _signIn(),
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    )),
                  ],
                  const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _signIn,
                            icon: const Icon(Icons.login_rounded),
                            label: Text(_busy ? 'جارٍ الدخول...' : 'تسجيل الدخول'),
                          ),
                        ),
                        if (widget.mode == AppMode.distributor) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const DistributorSignUpPage(),
                                      ),
                                    ),
                            child: const Text('إنشاء حساب مندوب جديد'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const VersionLabel(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

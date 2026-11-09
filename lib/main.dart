import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_dashboard.dart';
import 'auth/distributor_auth.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff8fbf8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff176b55),
          primary: const Color(0xff176b55),
          secondary: const Color(0xff57bdf3),
          tertiary: const Color(0xff8a6d00),
          surface: Colors.white,
          error: const Color(0xffb3261e),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff8fbf8),
          foregroundColor: Color(0xff174d3c),
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: Color(0xff174d3c),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: Color(0xff176b55)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xffe4eee7)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xffe7eee9),
          thickness: 1,
          space: 1,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xff28745d),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          minLeadingWidth: 24,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfffcfefc),
          labelStyle: const TextStyle(color: Color(0xff65766c)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xffdce8df)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xff176b55), width: 1.7),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xffb3261e)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xff176b55),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            foregroundColor: const Color(0xff176b55),
            side: const BorderSide(color: Color(0xffc9ded1)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xff176b55),
          foregroundColor: Colors.white,
          shape: StadiumBorder(),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xff176b55),
          unselectedLabelColor: Color(0xff718078),
          indicatorColor: Color(0xff22b34b),
          dividerColor: Color(0xffe4eee7),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xff174d3c),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
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
        email: widget.mode == AppMode.distributor
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
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xffeaf6ee), Color(0xfff7faf7), Color(0xffeef8fc)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: const BorderSide(color: Color(0xffdcebe1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xffe8f5ec),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(Icons.spa_rounded, size: 42, color: Color(0xff176b55)),
                        ),
                        const SizedBox(height: 16),
                        Text('الواحة', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xff176b55), fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(widget.mode == AppMode.distributor ? 'تطبيق المندوب' : 'إدارة المصنع والتوزيع', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xff6a7b71))),
                        const SizedBox(height: 26),
                  TextField(
                    controller: _email,
                    keyboardType: widget.mode == AppMode.distributor
                        ? TextInputType.phone
                        : TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: widget.mode == AppMode.distributor
                          ? 'رقم الهاتف'
                          : 'البريد الإلكتروني',
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

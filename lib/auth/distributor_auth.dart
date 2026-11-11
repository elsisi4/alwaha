import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// المندوب يسجّل ويدخل برقم هاتفه. Supabase يحتاج بريدًا، فنحوّل الرقم إلى
/// بريد داخلي ثابت لا يُرسل إليه شيء (تأكيد البريد يجب أن يكون معطلًا).
const phoneEmailDomain = 'phone.alwaha.app';

String normalizePhone(String input) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final arabicIndex = arabicDigits.indexOf(char);
    buffer.write(arabicIndex >= 0 ? '$arabicIndex' : char);
  }
  var digits = buffer.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0020')) {
    digits = '0${digits.substring(4)}';
  } else if (digits.startsWith('20') && digits.length == 12) {
    digits = '0${digits.substring(2)}';
  }
  return digits;
}

bool isValidPhone(String input) =>
    RegExp(r'^[0-9]{10,15}$').hasMatch(normalizePhone(input));

String phoneToEmail(String input) =>
    '${normalizePhone(input)}@$phoneEmailDomain';

class DistributorSignUpPage extends StatefulWidget {
  const DistributorSignUpPage({super.key});

  @override
  State<DistributorSignUpPage> createState() => _DistributorSignUpPageState();
}

class _DistributorSignUpPageState extends State<DistributorSignUpPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _outlets;
  String? _outletId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _outlets = _loadOutlets();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadOutlets() async {
    final rows =
        (await Supabase.instance.client.rpc('list_signup_outlets')) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  String? _validate() {
    if (_name.text.trim().length < 3) return 'اكتب اسمك الكامل.';
    if (!isValidPhone(_phone.text)) return 'رقم الهاتف غير صحيح.';
    if (_outletId == null) return 'اختر المنفذ التابع لك.';
    if (_password.text.length < 6) return 'كلمة المرور لا تقل عن 6 أحرف.';
    if (_password.text != _confirm.text) return 'كلمتا المرور غير متطابقتين.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: phoneToEmail(_phone.text),
        password: _password.text,
        data: {
          'full_name': _name.text.trim(),
          'phone': normalizePhone(_phone.text),
          'requested_outlet_id': _outletId,
        },
      );
      if (response.session == null) {
        setState(() => _error =
            'تم إنشاء الحساب لكن لم يُفتح تلقائيًا. تواصل مع الإدارة.');
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (error) {
      setState(() {
        _error = error.message.toLowerCase().contains('already')
            ? 'هذا الرقم مسجل بالفعل. ارجع وسجّل الدخول.'
            : error.message;
      });
    } catch (error) {
      setState(() => _error = 'تعذر إنشاء الحساب: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حساب مندوب جديد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _outlets,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'تعذر تحميل المنافذ: ${snapshot.error}',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  return DropdownButtonFormField<String>(
                    initialValue: _outletId,
                    decoration:
                        const InputDecoration(labelText: 'المنفذ التابع لك'),
                    items: snapshot.data!
                        .map(
                          (outlet) => DropdownMenuItem<String>(
                            value: outlet['id'] as String,
                            child: Text(outlet['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _outletId = value),
                  );
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirm,
                obscureText: true,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration:
                    const InputDecoration(labelText: 'تأكيد كلمة المرور'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(_busy ? 'جارٍ الإرسال...' : 'إرسال طلب التسجيل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب التسجيل')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 56, color: Color(0xff22d3b6)),
              const SizedBox(height: 16),
              Text('تم استلام طلب تسجيلك',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'بانتظار موافقة الإدارة. بعد الموافقة اضغط تحديث لفتح حسابك.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Supabase.instance.client.auth.refreshSession(),
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الحالة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WrongAppPage extends StatelessWidget {
  const WrongAppPage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phonelink_lock, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

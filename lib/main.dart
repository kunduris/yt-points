import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final api = Supabase.instance.client;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Gate()));
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}
class _GateState extends State<Gate> {
  @override
  void initState() {
    super.initState();
    api.auth.onAuthStateChange.listen((_) { if (mounted) setState(() {}); });
  }
  @override
  Widget build(BuildContext context) => api.auth.currentUser == null
      ? const LoginPage() : const KidsPage();
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  String message = '';
  Future<void> submit(bool signup) async {
    try {
      if (signup) {
        await api.auth.signUp(email: email.text.trim(), password: password.text);
        setState(() => message = 'Check your email to confirm your account.');
      } else {
        await api.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } catch (e) { setState(() => message = e.toString()); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('YT Points')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
      TextField(controller: email, decoration: const InputDecoration(labelText: 'Parent email')),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      FilledButton(onPressed: () => submit(false), child: const Text('Sign in')),
      TextButton(onPressed: () => submit(true), child: const Text('Create account')),
      Text(message),
    ])),
  );
}

Future<String?> prompt(BuildContext context, String title, {bool number = false}) async {
  final controller = TextEditingController();
  return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
    title: Text(title),
    content: TextField(controller: controller, autofocus: true,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK')),
    ],
  ));
}

class KidsPage extends StatefulWidget {
  const KidsPage({super.key});
  @override
  State<KidsPage> createState() => _KidsPageState();
}
class _KidsPageState extends State<KidsPage> {
  List<Map<String, dynamic>> kids = [];
  List<Map<String, dynamic>> transactions = [];
  String error = '';
  @override
  void initState() { super.initState(); reload(); }
  Future<void> reload() async {
    try {
      final a = await api.from('yt_children').select().eq('archived', false).order('created_at');
      final b = await api.from('yt_transactions').select();
      if (mounted) setState(() {
        kids = List<Map<String, dynamic>>.from(a);
        transactions = List<Map<String, dynamic>>.from(b);
        error = '';
      });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  int balance(String id) => transactions.where((t) => t['child_id'] == id)
    .fold<int>(0, (sum, t) => sum + (t['points_delta'] as num).toInt());
  Future<void> addKid() async {
    final name = await prompt(context, 'Child name');
    if (name == null || name.isEmpty) return;
    try { await api.from('yt_children').insert({'name': name}); await reload(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('YT Points'), actions: [
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
      IconButton(onPressed: () => api.auth.signOut(), icon: const Icon(Icons.logout)),
    ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: addKid, icon: const Icon(Icons.person_add), label: const Text('Add kid')),
    body: ListView(children: [
      if (error.isNotEmpty) Text(error),
      ...kids.map((kid) {
        final points = balance(kid['id'].toString());
        return Card(child: ListTile(
          leading: CircleAvatar(child: Text(kid['name'].toString()[0].toUpperCase())),
          title: Text(kid['name'].toString()),
          subtitle: Text('$points points | \${(points * 0.5).toStringAsFixed(2)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(kid: kid)));
            await reload();
          },
        ));
      }),
    ]),
  );
}

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic> kid;
  const ProfilePage({super.key, required this.kid});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage> {
  List<Map<String, dynamic>> transactions = [];
  String error = '';
  @override
  void initState() { super.initState(); reload(); }
  Future<void> reload() async {
    try {
      final rows = await api.from('yt_transactions').select()
        .eq('child_id', widget.kid['id']).order('created_at', ascending: false);
      if (mounted) setState(() {
        transactions = List<Map<String, dynamic>>.from(rows); error = '';
      });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  int get balance => transactions.fold<int>(
    0, (sum, t) => sum + (t['points_delta'] as num).toInt());
  Future<void> transact(String category) async {
    final amount = await prompt(context,
      category == 'purchase' ? 'Purchase amount in dollars' : 'Number of points', number: true);
    if (amount == null) return;
    final value = double.tryParse(amount);
    if (value == null || !value.isFinite || value <= 0) return;
    final points = category == 'purchase' ? (value * 2).round() : value.round();
    if (points < 1 || points > 1000000 ||
        (category == 'purchase' ? (points / 2 - value).abs() > 0.000001 : points != value)) {
      setState(() => error = 'Enter whole points or a purchase amount in 50-cent increments.');
      return;
    }
    final delta = category == 'reward' ? points : -points;
    if (balance + delta < 0) {
      setState(() => error = 'Insufficient points.');
      return;
    }
    final reason = await prompt(context, 'Reason');
    if (reason == null || reason.isEmpty) return;
    try {
      await api.from('yt_transactions').insert({
        'child_id': widget.kid['id'], 'points_delta': delta,
        'category': category, 'reason': reason,
      });
      await reload();
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("${widget.kid['name']}'s Profile")),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Icon(Icons.account_circle, size: 80),
      Center(child: Text(widget.kid['name'].toString(),
        style: Theme.of(context).textTheme.headlineMedium)),
      Center(child: Text('$balance points | \${(balance * 0.5).toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.titleLarge)),
      Wrap(spacing: 8, children: [
        FilledButton(onPressed: () => transact('reward'), child: const Text('Reward')),
        OutlinedButton(onPressed: () => transact('deduction'), child: const Text('Deduct')),
        OutlinedButton(onPressed: () => transact('purchase'), child: const Text('Purchase')),
      ]),
      if (error.isNotEmpty) Text(error),
      const ListTile(title: Text('Transaction history')),
      ...transactions.map((t) => Card(child: ListTile(
        title: Text(t['reason'].toString()),
        subtitle: Text(t['category'].toString()),
        trailing: Text("${t['points_delta']} pts"),
      ))),
      TextButton(onPressed: () async {
        await api.from('yt_children').update({'archived': true}).eq('id', widget.kid['id']);
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Archive child')),
    ]),
  );
}

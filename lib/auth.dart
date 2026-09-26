import 'package:flutter/material.dart';

import 'home.dart';
import 'password.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _passwords = LocalPassword();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = true;
  bool _hasPassword = false;
  bool _unlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final exists = await _passwords.exists();
      if (mounted) setState(() { _hasPassword = exists; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = 'Secure storage could not be opened: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _unlocked && mounted) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final password = _password.text;
    if (password.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_hasPassword) {
        if (!await _passwords.verify(password)) {
          if (mounted) setState(() => _error = 'Incorrect password.');
          return;
        }
      } else {
        if (password.length < 8) {
          setState(() => _error = 'Use at least 8 characters.');
          return;
        }
        if (password != _confirm.text) {
          setState(() => _error = 'The passwords do not match.');
          return;
        }
        await _passwords.create(password);
      }
      if (mounted) setState(() { _hasPassword = true; _unlocked = true; });
      _password.clear();
      _confirm.clear();
    } catch (error) {
      if (mounted) setState(() => _error = 'Password operation failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return MoneyMapHome(onLock: () => setState(() => _unlocked = false), passwords: _passwords);
    }
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.account_balance_wallet, size: 56, color: Color(0xFF62C4FF)),
              const SizedBox(height: 18),
              Text('MoneyMap', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(_hasPassword ? 'Unlock your money map' : 'Create a password for this device',
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
              ),
              if (!_hasPassword) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_reset)),
                ),
              ],
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8D9B))),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading || _error?.startsWith('Secure storage') == true ? null : _submit,
                child: Text(_loading ? 'Please wait...' : _hasPassword ? 'Unlock' : 'Create password'),
              ),
              if (!_hasPassword) const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Keep this password safe. This version has no password recovery.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ),
            ]),
          )),
        ),
      ))),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/auth_provider.dart';
import '../../data/deck_provider.dart';
import '../../data/session_provider.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final password = _controller.text;
      final ok = await client.adminLogin(password);
      if (ok && mounted) {
        ref.read(adminAuthProvider.notifier).state = true;
        ref.read(adminIdTokenProvider.notifier).state = null;
        ref.read(adminPasswordProvider.notifier).state = password;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/admin/dashboard');
        });
      } else if (mounted) {
        setState(() => _error = 'Invalid password');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      await auth.signInWithGoogle();
      final token = await auth.getIdToken();
      if (token == null) {
        throw Exception('Google sign-in did not return an ID token.');
      }

      final client = ref.read(apiClientProvider);
      final ok = await client.adminVerifyWithToken(token);
      if (!ok) {
        await auth.signOut();
        throw Exception('Signed in with Google, but this account is not allowlisted for admin access.');
      }

      if (mounted) {
        ref.read(adminAuthProvider.notifier).state = true;
        ref.read(adminIdTokenProvider.notifier).state = token;
        ref.read(adminPasswordProvider.notifier).state = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/admin/dashboard');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Admin login')),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Admin password',
              ),
              onSubmitted: (_) => _submitPassword(),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: AppTheme.negativeDislike), maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppTheme.spacingUnit),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _submitGoogle,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submitPassword,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login with password'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            const Text(
              'Use Google for hosted environments. Password login is intended for local or explicitly enabled legacy access.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

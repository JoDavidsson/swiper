import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';
import '../../data/session_provider.dart';
import '../../debug_log.dart';

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
    // #region agent log
    debugLog('admin_login_screen.dart:_submitPassword', 'submit started', {}, hypothesisId: 'H5');
    // #endregion
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final password = _controller.text;
      final ok = await client.adminLogin(password);
      // #region agent log
      debugLog('admin_login_screen.dart:_submitPassword', 'adminLogin result', {'ok': ok, 'mounted': mounted}, hypothesisId: 'H5');
      // #endregion
      if (ok && mounted) {
        ref.read(adminAuthProvider.notifier).state = true;
        ref.read(adminIdTokenProvider.notifier).state = null;
        ref.read(adminPasswordProvider.notifier).state = password;
        // #region agent log
        debugLog('admin_login_screen.dart:_submitPassword', 'state set to true, scheduling postFrameCallback', {}, hypothesisId: 'H1');
        // #endregion
        // Defer navigation so the router rebuilds with isAdmin=true (avoids landing on splash)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // #region agent log
          debugLog('admin_login_screen.dart:postFrameCallback', 'callback run', {'mounted': mounted}, hypothesisId: 'H5');
          // #endregion
          if (mounted) context.go('/admin/dashboard');
        });
      } else if (mounted) {
        setState(() => _error = 'Invalid password');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
            if (_error != null) ...[
              const SizedBox(height: AppTheme.spacingUnit),
              Text(_error!, style: TextStyle(color: AppTheme.negativeDislike), maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: AppTheme.spacingUnit * 2),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submitPassword,
                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

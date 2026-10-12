import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../auth/domain/entities/user_entity.dart';
import '../../auth/domain/usecases/restore_session_usecase.dart'
    show RestoreOutcome;
import '../../auth/login/screens/login_screen.dart';
import '../../auth/session/auth_session.dart';
import '../../main_navigation/screens/main_navigation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Shown when session verification failed transiently (offline, timeout,
  /// server error) while stored credentials still exist: the user may retry
  /// instead of being sent to Login. Never grants access without a verified
  /// session — retry simply re-attempts verification.
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  Future<void> _navigateToNext({bool withDelay = true}) async {
    // Preserve the branded splash delay while validating any stored session.
    // The restore starts immediately (not after the delay) in both paths.
    final restoreFuture = AuthSession.instance
        .restoreSession()
        .then<UserEntity?>((user) => user, onError: (_) => null);
    if (withDelay) await Future.delayed(const Duration(seconds: 2));
    final user = await restoreFuture;
    if (!mounted) return;
    if (user != null) {
      _go(const MainNavigationScreen());
      return;
    }
    if (AuthSession.instance.lastRestoreOutcome ==
        RestoreOutcome.temporaryFailure) {
      setState(() => _showRetry = true);
      return;
    }
    _go(const LoginScreen());
  }

  void _go(Widget destination) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _showRetry = false);
    await _navigateToNext(withDelay: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag, size: 120, color: AppTheme.primary),
            const SizedBox(height: 24),
            Text(
              'Huma-volve',
              style: Theme.of(context).textTheme.displayLarge
                  ?.copyWith(fontSize: 40, color: AppTheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Ultimate E-Commerce App',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 48),
            if (_showRetry) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Couldn\'t verify your session. Check your connection and try again.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ] else
              CircularProgressIndicator(color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

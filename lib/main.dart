import 'package:flutter/material.dart';

import 'core/di/app_dependencies.dart';
import 'core/di/app_scope.dart';
import 'core/theme.dart';
import 'features/splash/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Composition root: single shared Dio, repository implementations behind
  // domain contracts, use cases, and the AuthSession singleton.
  final dependencies = AppDependencies();
  dependencies.initAuthSession();
  runApp(AppScope(dependencies: dependencies, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Commerce App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

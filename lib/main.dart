import 'package:flutter/material.dart';

import 'core/network/dio_client.dart';
import 'core/theme.dart';
import 'features/auth/data/services/auth_service.dart';
import 'features/auth/data/services/auth_storage.dart';
import 'features/auth/session/auth_session.dart';
import 'features/splash/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthSession.init(
    authService: AuthService(dio: DioClient.create()),
    storage: SecureAuthStorage(),
  );
  runApp(const MyApp());
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

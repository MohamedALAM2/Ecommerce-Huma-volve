import 'package:app_links/app_links.dart';
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GlobalKey<NavigatorState> _navigatorKey;

  @override
  void initState() {
    super.initState();
    // Navigator key first so the deep-link coordinator can navigate from
    // outside the widget tree (platform events have no BuildContext).
    _navigatorKey = GlobalKey<NavigatorState>();
    // Subscribe before the first frame: AppLinks replays the cold-start
    // initial link to the first stream listener. Stream-only (no
    // getInitialLink) so the initial link is handled exactly once.
    final coordinator = AppScope.read(context).deepLinkCoordinator
      ..attachNavigatorKey(_navigatorKey);
    coordinator.listenTo(AppLinks().uriLinkStream);
  }

  @override
  void dispose() {
    AppScope.read(context).deepLinkCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Commerce App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: _navigatorKey,
      home: const SplashScreen(),
    );
  }
}

import 'package:flutter/widgets.dart';

import 'app_dependencies.dart';

/// Exposes the composition root to the widget tree without globals or
/// service-locator packages. Screens keep their constructors; owners that
/// build stateful objects (e.g. `MainNavigationScreen` creating its
/// `HomeCubit`) resolve factories here.
class AppScope extends InheritedWidget {
  final AppDependencies dependencies;

  const AppScope({super.key, required this.dependencies, required super.child});

  /// Listening lookup for build methods.
  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found above this widget.');
    return scope!.dependencies;
  }

  /// Non-listening lookup, safe in `initState`.
  static AppDependencies read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found above this widget.');
    return scope!.dependencies;
  }

  /// Nullable lookup for optional integrations (e.g. Splash marking
  /// deep-link readiness in tests that pump screens standalone).
  static AppDependencies? maybeRead(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope?.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.dependencies != dependencies;
}

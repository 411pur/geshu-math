import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';

/// Thin shell that delegates to [AppShell] (desktop workspace layout).
///
/// The former mobile bottom-tab [NavigationBar] and stats banner have been
/// removed — navigation now lives in the sidebar provided by [AppShell].
class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(navigationShell: navigationShell);
  }
}

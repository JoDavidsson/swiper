import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme.dart';

/// App shell: scaffold + top bar + optional bottom nav.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.body,
    this.showBottomNav = false,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const [],
    this.transparentAppBar = false,
    this.extendBodyBehindAppBar = false,
    this.onShareTap,
  });

  final String title;
  final Widget body;
  final bool showBottomNav;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget> actions;
  final bool transparentAppBar;
  final bool extendBodyBehindAppBar;
  final VoidCallback? onShareTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        backgroundColor:
            transparentAppBar ? Colors.transparent : AppTheme.background,
        elevation: transparentAppBar ? 0 : null,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: body,
      bottomNavigationBar: showBottomNav
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _indexForRoute(GoRouterState.of(context).uri.path),
              onTap: (i) => _onNavTap(context, i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Deck'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.favorite), label: 'Likes'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.share_outlined), label: 'Share'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person), label: 'Profile'),
              ],
            )
          : null,
    );
  }

  int _indexForRoute(String path) {
    if (path.startsWith('/likes')) return 1;
    if (path.startsWith('/profile')) return 3;
    return 0;
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/deck');
        break;
      case 1:
        context.go('/likes');
        break;
      case 2:
        if (onShareTap != null) {
          onShareTap!();
        } else {
          final base = Uri.base;
          final shareUrl =
              base.hasAuthority ? '${base.origin}/deck' : 'https://swiper.app';
          Share.share('Swiper\n$shareUrl', subject: 'Swiper');
        }
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }
}

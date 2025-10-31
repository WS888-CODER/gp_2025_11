import 'package:flutter/material.dart';

class ThemedScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool? resizeToAvoidBottomInset;
  final Color? overridePageBgColor;

  const ThemedScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.resizeToAvoidBottomInset,
    this.overridePageBgColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // خلفية الصفحة統一
    final Color pageBgColor = overridePageBgColor ??
        (isDark
            ? const Color(0xFF0F0F12) // دارك ناعم
            : const Color(0xFFF7F6FC)); // لايت وردي/رمادي خفيف تحبينه

    return Scaffold(
      backgroundColor: pageBgColor,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      endDrawer: endDrawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/board/board_page.dart';
import 'package:camaleon_billboard/presentation/theme_controller.dart';

class CamaleonBillboardApp extends StatelessWidget {
  const CamaleonBillboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeController()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => BillboardController()..bootstrap(),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Camaleon Billboard',
            debugShowCheckedModeBanner: false,
            theme: CamaleonTheme.light(),
            darkTheme: CamaleonTheme.dark(),
            themeMode: theme.mode,
            home: const BoardPage(),
          );
        },
      ),
    );
  }
}

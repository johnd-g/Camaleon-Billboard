import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/board/board_page.dart';
import 'package:camaleon_billboard/presentation/live_order/live_order_controller.dart';
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
        ChangeNotifierProxyProvider<BillboardController, LiveOrderController>(
          create: (_) => LiveOrderController()..bootstrap(),
          update: (_, billboard, live) {
            final c = live ?? LiveOrderController();
            c.attachRegisterLoader(
              billboard.connection.isComplete
                  ? billboard.findLiveOrderEndpointInUse
                  : null,
            );
            return c;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Camaleon Billboard',
        debugShowCheckedModeBanner: false,
        theme: CamaleonTheme.light(),
        themeMode: ThemeMode.light,
        home: const BoardPage(),
      ),
    );
  }
}

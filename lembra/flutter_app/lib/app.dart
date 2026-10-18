import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'ui/theme/app_theme.dart';
import 'ui/today_preview.dart';
import 'ui/home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Mantidas porque outros arquivos podem usar essas cores.
const corMarca = Color(0xFF0F766E);
const corCritico = Color(0xFFD97706);

/// true = mostra a tela nova de exemplo; false = volta pra HomePage original.
const bool _verPreview = false;

class LembraApp extends StatelessWidget {
  const LembraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lembra',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _verPreview ? const TodayPreviewPage() : const HomePage(),
    );
  }
}
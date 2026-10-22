import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/notification_service.dart';
import 'ui/alarm_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/today_preview.dart';
import 'ui/home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Mantidas porque outros arquivos podem usar essas cores.
const corMarca = Color(0xFF0F766E);
const corCritico = Color(0xFFD97706);

/// true = mostra a tela nova de exemplo; false = volta pra HomePage original.
const bool _verPreview = false;

class LembraApp extends StatefulWidget {
  const LembraApp({super.key});

  @override
  State<LembraApp> createState() => _LembraAppState();
}

class _LembraAppState extends State<LembraApp> {
  String? _alarmeAberto;

  @override
  void initState() {
    super.initState();
    // Alarme crítico tocado/aberto pela tela cheia → mostra a tela do despertador.
    NotificationService.instance.aoAbrirAlarme = _abrirAlarme;
  }

  @override
  void dispose() {
    NotificationService.instance.aoAbrirAlarme = null;
    super.dispose();
  }

  Future<void> _abrirAlarme(String itemId, int? notificacaoId) async {
    final chave = '$itemId-$notificacaoId';
    if (_alarmeAberto == chave) return; // evita abrir duas vezes o mesmo alarme
    final nav = navigatorKey.currentState;
    if (nav == null) {
      // O Navigator ainda não existe (app acabou de abrir): tenta no próximo frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirAlarme(itemId, notificacaoId));
      return;
    }
    _alarmeAberto = chave;
    await nav.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlarmPage(itemId: itemId, notificacaoId: notificacaoId),
    ));
    _alarmeAberto = null;
  }

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
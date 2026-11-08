import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/alarme_nativo.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';
import 'ui/alarm_page.dart';
import 'ui/boas_vindas_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/today_preview.dart';
import 'ui/home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Mantidas porque outros arquivos podem usar essas cores.
const corMarca = Color(0xFF0F766E);
const corCritico = Color(0xFFD97706);

/// true = mostra a tela nova de exemplo; false = volta pra HomePage original.
const bool _verPreview = false;

// ConsumerStatefulWidget (em vez de StatefulWidget) para poder ler o temaProvider.
class LembraApp extends ConsumerStatefulWidget {
  const LembraApp({super.key});

  @override
  ConsumerState<LembraApp> createState() => _LembraAppState();
}

class _LembraAppState extends ConsumerState<LembraApp> {
  String? _alarmeAberto;

  // Temas montados uma vez só, não a cada rebuild.
  final ThemeData _temaClaro = buildAppTheme();
  final ThemeData _temaEscuro = buildDarkTheme();

  @override
  void initState() {
    super.initState();
    // Alarme crítico tocado/aberto pela tela cheia → mostra a tela do despertador.
    NotificationService.instance.aoAbrirAlarme = _abrirAlarme;

    // Alarme nativo (serviço Kotlin): quando ele começa a tocar, abre a tela para poder parar.
    AlarmeNativo.instance.aoTocar = _alarmeNativoTocando; // app já aberto ou em segundo plano
    AlarmeNativo.instance.iniciar();
    // App fechado: o serviço abriu o app do zero, então pergunta se há alarme tocando.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final a = await AlarmeNativo.instance.atual();
      if (a != null && mounted) _alarmeNativoTocando(a);
    });
  }

  @override
  void dispose() {
    NotificationService.instance.aoAbrirAlarme = null;
    AlarmeNativo.instance.aoTocar = null;
    super.dispose();
  }

  /// O serviço nativo não tem id de notificação do Flutter, por isso vai null.
  void _alarmeNativoTocando(AlarmeTocando a) => _abrirAlarme(a.itemId, null);

  Future<void> _abrirAlarme(String itemId, int? notificacaoId) async {
    // Um alarme por item: se a tela deste item já está aberta, não abre outra
    // (o aviso pode chegar pelo serviço nativo e pela notificação ao mesmo tempo).
    if (_alarmeAberto == itemId) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      // O Navigator ainda não existe (app acabou de abrir): tenta no próximo frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirAlarme(itemId, notificacaoId));
      return;
    }
    _alarmeAberto = itemId;
    await nav.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlarmPage(itemId: itemId, notificacaoId: notificacaoId),
    ));
    _alarmeAberto = null;
  }

  @override
  Widget build(BuildContext context) {
    // Escolha feita em Ajustes > Aparência (Sistema / Claro / Escuro).
    final tema = ref.watch(temaProvider);

    return MaterialApp(
      title: 'Lembra',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: _temaClaro,
      darkTheme: _temaEscuro,
      themeMode: tema,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _verPreview ? const TodayPreviewPage() : const PrimeiroUso(child: HomePage()),
    );
  }
}
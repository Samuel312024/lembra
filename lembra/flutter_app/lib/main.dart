import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/diagnostico.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';
import 'ui/acoes_notificacao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sw = Stopwatch()..start();

  // AJUSTE 1: as duas inicializações independentes rodam em paralelo
  // (antes eram uma depois da outra).
  final (prefs, _) = await (
    SharedPreferences.getInstance(),
    initializeDateFormatting('pt_BR'),
  ).wait;
  debugPrint('[boot] prefs + datas: ${sw.elapsedMilliseconds}ms');

  Diagnostico.iniciar(prefs); // guarda os últimos erros para o relatório em Ajustes

  final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  NotificationService.instance.aoResponder =
      (acao, payload) => tratarRespostaNotificacao(container, acao, payload);

  // AJUSTE 2: começa a ler os cards do banco AGORA, em paralelo com a
  // inicialização das notificações. Quando a primeira tela abrir, a lista já
  // está pronta em vez de começar a carregar só nesse momento.
  container.read(itemsProvider);

  await NotificationService.instance.init();
  debugPrint('[boot] notificacoes prontas: ${sw.elapsedMilliseconds}ms');

  runApp(UncontrolledProviderScope(container: container, child: const LembraApp()));
}
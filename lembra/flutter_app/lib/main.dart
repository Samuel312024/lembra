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
  await initializeDateFormatting('pt_BR');
  final prefs = await SharedPreferences.getInstance();
  Diagnostico.iniciar(prefs); // guarda os últimos erros para o relatório em Ajustes
  await NotificationService.instance.init();

  final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  NotificationService.instance.aoResponder =
      (acao, payload) => tratarRespostaNotificacao(container, acao, payload);

  runApp(UncontrolledProviderScope(container: container, child: const LembraApp()));
}
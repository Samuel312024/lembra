// Coloque em: lib/state/som_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_notification.dart';
import '../services/notification_service.dart';
import 'providers.dart';

/// Som escolhido para o alarme crítico.
class SomAlarmeNotifier extends Notifier<SomAlarme> {
  @override
  SomAlarme build() => NotificationService.instance.somAlarme;

  /// Troca o som, reagenda os alarmes (eles passam a usar o canal novo) e
  /// toca uma vez para o usuário ouvir.
  Future<void> escolher(SomAlarme som) async {
    await NotificationService.instance.definirSom(som);
    state = som;
    await ref.read(itemsProvider.notifier).reagendarNotificacoes();
    await NotificationService.instance.testarSom();
  }

  Future<void> testar() => NotificationService.instance.testarSom();
}

final somAlarmeProvider = NotifierProvider<SomAlarmeNotifier, SomAlarme>(SomAlarmeNotifier.new);

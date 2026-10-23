// Coloque em: lib/ui/som_alarme_page.dart
//
// Ajustes > Som do alarme: o usuário escolhe como o alarme crítico toca.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_notification.dart';
import '../state/som_provider.dart';
import 'theme/app_theme.dart';

class SomAlarmePage extends ConsumerWidget {
  const SomAlarmePage({super.key});

  Widget _titulo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(
          texto,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
        ),
      );

  Widget _opcao(WidgetRef ref, SomAlarme som, SomAlarme atual) {
    final escolhido = som.id == atual.id;
    return ListTile(
      leading: Icon(
        som.doCelular ? Icons.phone_android_outlined : Icons.music_note_outlined,
        color: escolhido ? AppColors.brand : AppColors.muted,
      ),
      title: Text(som.rotulo, style: TextStyle(fontWeight: escolhido ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text(som.descricao),
      trailing: escolhido
          ? const Icon(Icons.check_circle, color: AppColors.brand)
          : const Icon(Icons.radio_button_unchecked, color: AppColors.cardBorder),
      onTap: () => ref.read(somAlarmeProvider.notifier).escolher(som),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final atual = ref.watch(somAlarmeProvider);
    final celular = sonsAlarme.where((s) => s.doCelular);
    final app = sonsAlarme.where((s) => !s.doCelular);

    return Scaffold(
      appBar: AppBar(title: const Text('Som do alarme')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Vale para os lembretes com urgência “Crítico”. O som toca no volume de alarme do '
              'celular e repete até você tocar em Feito, Adiar ou Só parar o som. '
              'Ao escolher, o som toca uma vez para você ouvir.',
            ),
          ),
          _titulo(context, 'SONS DO CELULAR'),
          for (final s in celular) _opcao(ref, s, atual),
          _titulo(context, 'SONS DO LEMBRA'),
          for (final s in app) _opcao(ref, s, atual),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: OutlinedButton.icon(
              onPressed: () => ref.read(somAlarmeProvider.notifier).testar(),
              icon: const Icon(Icons.volume_up_outlined),
              label: Text('Ouvir “${atual.rotulo}” de novo'),
            ),
          ),
        ],
      ),
    );
  }
}
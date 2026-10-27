import 'package:flutter/material.dart';

import '../../services/alarm_notification.dart';
import '../../services/alarme_som_nativo.dart';

class _Escolha {
  const _Escolha(this.id);
  final String? id; // null = padrão do app
}

class SeletorSomAlarme extends StatelessWidget {
  const SeletorSomAlarme({super.key, required this.somId, required this.aoMudar});

  /// null = usa o som padrão escolhido em Ajustes > Som do alarme.
  final String? somId;
  final ValueChanged<String?> aoMudar;

  @override
  Widget build(BuildContext context) {
    final atual = somId == null ? null : somAlarmePorId(somId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.alarm_outlined),
      title: const Text('Som do alarme'),
      subtitle: Text(atual?.rotulo ?? 'Padrão do app'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final r = await showModalBottomSheet<_Escolha>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Padrão do app'),
                  subtitle: const Text('O som escolhido em Ajustes'),
                  trailing: somId == null ? const Icon(Icons.check_circle) : null,
                  onTap: () => Navigator.pop(ctx, const _Escolha(null)),
                ),
                for (final s in sonsAlarme)
                  ListTile(
                    leading: Icon(s.doCelular ? Icons.phone_android_outlined : Icons.music_note_outlined),
                    title: Text(s.rotulo),
                    subtitle: Text(s.descricao),
                    trailing: somId == s.id ? const Icon(Icons.check_circle) : null,
                    onTap: () {
                      AlarmeSomNativo.tocar(s); // prévia de 8 s, como alarme
                      Navigator.pop(ctx, _Escolha(s.id));
                    },
                  ),
              ],
            ),
          ),
        );
        if (r != null) aoMudar(r.id);
      },
    );
  }
}
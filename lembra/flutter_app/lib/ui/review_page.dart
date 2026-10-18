import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/item.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'item_tile.dart';

/// Revisão da noite: o que foi feito, o que ficou para trás e o que passa para amanhã.
class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itens = ref.watch(itemsProvider).valueOrNull ?? [];
    final agora = DateTime.now();
    final g = agruparHoje(itens, agora);
    // Pendentes: o que já deveria ter acontecido e não foi concluído (hoje ou antes).
    final pendentes = [
      ...g.atrasados,
      ...g.hoje.where((i) => i.regra == null && (i.ancora?.isBefore(agora) ?? false)),
    ];
    final notifier = ref.read(itemsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Revisão do dia')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _Secao('Feito hoje (${g.feitos.length})'),
          if (g.feitos.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Text('Nada concluído ainda.')),
          for (final i in g.feitos)
            ItemTile(item: i, feito: true, onTap: () {}, onConcluir: () {}, onCancelar: () {}),
          const SizedBox(height: 12),
          _Secao('Ficou para trás (${pendentes.length})'),
          if (pendentes.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Text('Nada pendente. Bom trabalho!')),
          for (final i in pendentes)
            ItemTile(
              item: i,
              onTap: () {},
              onConcluir: () => notifier.concluir(i.id),
              onCancelar: () => notifier.cancelar(i.id),
            ),
          if (pendentes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(
                icon: const Icon(Icons.redo),
                label: const Text('Reagendar tudo para amanhã'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final n = await notifier.reagendarPendentesParaAmanha(pendentes);
                  messenger.showSnackBar(SnackBar(content: Text('$n ${n == 1 ? 'item passou' : 'itens passaram'} para amanhã.')));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo);
  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'item_form_page.dart';
import 'review_page.dart';

/// Trata toques e botões das notificações ("Feito", "Adiar 10 min", abrir item).
Future<void> tratarRespostaNotificacao(ProviderContainer c, String? acao, String? payload) async {
  if (payload == null) return;
  final nav = navigatorKey.currentState;

  if (payload == 'briefing') {
    final itens = await c.read(itemsProvider.future);
    await c.read(ttsProvider).falar(textoResumo(itens, DateTime.now(), DateTime.now()));
    return;
  }
  if (payload == 'revisao') {
    nav?.push(MaterialPageRoute(builder: (_) => const ReviewPage()));
    return;
  }

  final notifier = c.read(itemsProvider.notifier);
  switch (acao) {
    case 'feito':
      await notifier.concluir(payload);
    case 'soneca':
      await notifier.adiar(payload, const Duration(minutes: 10));
      final item = await c.read(repoProvider).buscar(payload);
      final ctx = navigatorKey.currentContext;
      // Soneca inteligente: na 3ª vez, em vez de insistir, pergunta para quando reagendar.
      if (item != null && item.soneca >= 3 && ctx != null && ctx.mounted) {
        await perguntarReagendar(ctx, c, item);
      }
    default:
      final item = await c.read(repoProvider).buscar(payload);
      if (item == null || nav == null) return;
      final d = await nav.push<Draft>(
        MaterialPageRoute(builder: (_) => ItemFormPage(rascunho: Draft.deItem(item), titulo: 'Editar lembrete')),
      );
      if (d != null) await notifier.atualizarDe(item.id, d);
  }
}

/// "Você adiou 3 vezes — reagendar pra quando?"
Future<void> perguntarReagendar(BuildContext context, ProviderContainer c, Item item) async {
  final agora = DateTime.now();
  final opcoes = <(String, DateTime)>[
    ('Hoje à noite (20:00)', DateTime(agora.year, agora.month, agora.day, 20)),
    ('Amanhã de manhã (09:00)', DateTime(agora.year, agora.month, agora.day + 1, 9)),
    ('Amanhã à tarde (15:00)', DateTime(agora.year, agora.month, agora.day + 1, 15)),
  ];
  final escolhido = await showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Você adiou “${item.titulo}” 3 vezes', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Reagendar pra quando?'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (rotulo, quando) in opcoes)
                  ActionChip(
                    label: Text(rotulo),
                    onPressed: quando.isAfter(agora) ? () => Navigator.of(ctx).pop(quando) : null,
                  ),
                ActionChip(
                  label: const Text('Escolher…'),
                  onPressed: () async {
                    final data = await showDatePicker(
                      context: ctx,
                      initialDate: agora,
                      firstDate: agora,
                      lastDate: DateTime(agora.year + 5),
                    );
                    if (data == null || !ctx.mounted) return;
                    final hora = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 9, minute: 0));
                    if (hora == null || !ctx.mounted) return;
                    Navigator.of(ctx).pop(DateTime(data.year, data.month, data.day, hora.hour, hora.minute));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (escolhido != null) await c.read(itemsProvider.notifier).reagendar(item.id, escolhido);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/draft.dart';
import '../domain/item.dart';
import '../nlp/comandos.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'confirmation_card.dart';
import 'voice_sheet.dart';

/// Captura por voz: ouve, decide se é um comando (cancelar, concluir, adiar,
/// listar) ou um novo lembrete, e conduz o usuário até a confirmação.
Future<void> iniciarVoz(BuildContext context, WidgetRef ref) async {
  final texto = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const VoiceSheet(
      dica: 'Ex.: “tenho médico dia 22 às 14h30” ou “cancela o lembrete do médico”',
    ),
  );
  if (texto == null || texto.trim().isEmpty || !context.mounted) return;
  await processarTexto(context, ref, texto, origem: Origem.voz);
}

Future<void> processarTexto(
  BuildContext context,
  WidgetRef ref,
  String texto, {
  required Origem origem,
  bool permitirComando = true,
}) async {
  final agora = DateTime.now();
  if (permitirComando) {
    final cmd = ParserComandos(agora).interpretar(texto);
    if (cmd != null) {
      await _executarComando(context, ref, cmd, texto);
      return;
    }
  }

  final drafts = await ref.read(entendimentoProvider).entender(texto, origem: origem);
  if (!context.mounted) return;
  if (drafts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não entendi. Tente de novo.')));
    return;
  }

  final padrao = ref.read(configProvider).horarioPadrao;
  var criados = 0;
  for (var i = 0; i < drafts.length; i++) {
    var d = drafts[i];
    // No máximo UMA pergunta curta por vez; cada resposta resolve a pendência.
    while (d.proximaPergunta != null) {
      if (!context.mounted) return;
      final r = await perguntarLacuna(context, d, padrao);
      if (r == null) break;
      d = r;
    }
    if (!context.mounted) return;
    final confirmado = await mostrarCartao(context, d, indice: i + 1, total: drafts.length);
    if (confirmado == null) continue;
    await ref.read(itemsProvider.notifier).criar(confirmado);
    criados++;
  }
  if (criados > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(criados == 1 ? 'Lembrete agendado.' : '$criados lembretes agendados.')),
    );
  }
}

Future<void> _executarComando(BuildContext context, WidgetRef ref, ComandoVoz cmd, String textoOriginal) async {
  switch (cmd) {
    case CancelarComando(:final alvo):
      await _cancelar(context, ref, alvo, textoOriginal);
    case ConcluirComando(:final alvo):
      await _concluir(context, ref, alvo);
    case AdiarComando c:
      await _adiar(context, ref, c);
    case ListarComando(:final dia):
      await _listar(context, ref, dia);
  }
}

List<Item> _ativos(WidgetRef ref) =>
    (ref.read(itemsProvider).valueOrNull ?? []).where((i) => i.status == StatusItem.ativo).toList();

/// Resolve qual item o usuário quis dizer; pergunta quando há dúvida.
Future<Item?> _resolverAlvo(
  BuildContext context,
  WidgetRef ref,
  String alvo,
  String acao, {
  bool proximoSeVazio = false,
}) async {
  final itens = _ativos(ref);
  if (itens.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Você não tem lembretes ativos.')));
    return null;
  }
  List<Item> candidatos;
  if (alvo.trim().isEmpty) {
    if (proximoSeVazio) {
      final agora = DateTime.now();
      final comData = itens.where((i) => i.ancora != null).toList()
        ..sort((a, b) => a.ancora!.difference(agora).abs().compareTo(b.ancora!.difference(agora).abs()));
      candidatos = comData.isEmpty ? [] : [comData.first];
    } else {
      final recentes = [...itens]..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      candidatos = [recentes.first]; // "cancela" = o último que criei
    }
  } else {
    candidatos = buscarItens(alvo, itens);
  }
  if (candidatos.length == 1) return candidatos.first;

  final lista = candidatos.isEmpty ? itens : candidatos;
  final titulo = candidatos.isEmpty ? 'Não achei esse. Qual você quer $acao?' : 'Qual deles?';
  return showModalBottomSheet<Item>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final i in lista)
            ListTile(
              title: Text(i.titulo),
              subtitle: i.ancora == null ? null : Text(quandoCurto(i.ancora!)),
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      ),
    ),
  );
}

/// Confirmação com resposta por voz ("sim" / "não"). Cancelar nunca é silencioso.
Future<bool> confirmarComVoz(
  BuildContext context, {
  required String titulo,
  required String corpo,
  required String rotuloConfirmar,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isDismissible: false,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(corpo),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(rotuloConfirmar),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Responder por voz',
                  icon: const Icon(Icons.mic),
                  onPressed: () async {
                    final t = await showModalBottomSheet<String>(
                      context: ctx,
                      isScrollControlled: true,
                      builder: (_) => const VoiceSheet(titulo: 'Confirma?', dica: 'Diga “sim” ou “não”'),
                    );
                    if (t == null || !ctx.mounted) return;
                    final resp = interpretarResposta(t);
                    if (resp == RespostaVoz.confirmar) Navigator.of(ctx).pop(true);
                    if (resp == RespostaVoz.descartar) Navigator.of(ctx).pop(false);
                  },
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Manter')),
            ),
          ],
        ),
      ),
    ),
  );
  return r ?? false;
}

Future<void> _cancelar(BuildContext context, WidgetRef ref, String alvo, String textoOriginal) async {
  // "Cancelar a assinatura da Netflix sexta" pode ser um lembrete novo, não um comando.
  if (alvo.isNotEmpty && buscarItens(alvo, _ativos(ref)).isEmpty) {
    final criar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Não achei esse lembrete'),
        content: Text('Nenhum item parecido com “$alvo”. Quer criar um lembrete com essa frase?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fechar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Criar lembrete')),
        ],
      ),
    );
    if (criar == true && context.mounted) {
      await processarTexto(context, ref, textoOriginal, origem: Origem.voz, permitirComando: false);
    }
    return;
  }

  final item = await _resolverAlvo(context, ref, alvo, 'cancelar');
  if (item == null || !context.mounted) return;
  final ok = await confirmarComVoz(
    context,
    titulo: 'Cancelar este lembrete?',
    corpo: item.ancora == null ? item.titulo : '${item.titulo}\n${quandoCurto(item.ancora!)}',
    rotuloConfirmar: 'Cancelar lembrete',
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(itemsProvider.notifier);
  final antes = await notifier.cancelar(item.id);
  messenger.showSnackBar(SnackBar(
    content: Text('“${item.titulo}” cancelado.'),
    action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
  ));
}

Future<void> _concluir(BuildContext context, WidgetRef ref, String alvo) async {
  final item = await _resolverAlvo(context, ref, alvo, 'concluir');
  if (item == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(itemsProvider.notifier);
  final antes = await notifier.concluir(item.id);
  messenger.showSnackBar(SnackBar(
    content: Text('“${item.titulo}” concluído.'),
    action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
  ));
}

Future<void> _adiar(BuildContext context, WidgetRef ref, AdiarComando c) async {
  final item = await _resolverAlvo(context, ref, c.alvo, 'adiar', proximoSeVazio: true);
  if (item == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(itemsProvider.notifier);
  Item? antes;
  if (c.duracao != null) {
    antes = await notifier.adiar(item.id, c.duracao!);
  } else if (c.novoQuando != null) {
    var novo = c.novoQuando!;
    if (c.novoSemHora && item.ancora != null) {
      novo = DateTime(novo.year, novo.month, novo.day, item.ancora!.hour, item.ancora!.minute);
    }
    antes = await notifier.reagendar(item.id, novo);
  }
  final depois = await ref.read(repoProvider).buscar(item.id);
  final quando = depois?.ancora == null ? '' : ' para ${quandoCurto(depois!.ancora!)}';
  messenger.showSnackBar(SnackBar(
    content: Text('“${item.titulo}” adiado$quando.'),
    action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes!)),
  ));
}

Future<void> _listar(BuildContext context, WidgetRef ref, DateTime dia) async {
  final itens = ref.read(itemsProvider).valueOrNull ?? [];
  final texto = textoResumo(itens, dia, DateTime.now());
  final tts = ref.read(ttsProvider);
  tts.falar(texto);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sua agenda'),
      content: Text(texto),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar'))],
    ),
  );
  await tts.parar();
}

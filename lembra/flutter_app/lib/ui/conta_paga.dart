// Coloque em: lib/ui/conta_paga.dart
//
// Aviso exibido depois de concluir um item. Para conta avulsa, oferece agendar
// a cobrança do mês seguinte (mesmo valor e tipo), em um toque.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/draft.dart';
import '../domain/item.dart';
import '../state/providers.dart';
import 'theme/app_theme.dart';

/// Soma meses mantendo o dia (31 de janeiro + 1 mês = 28 ou 29 de fevereiro).
DateTime somarMeses(DateTime d, int meses) {
  final total = d.month - 1 + meses;
  final ano = d.year + total ~/ 12;
  final mes = total % 12 + 1;
  final ultimoDia = DateTime(ano, mes + 1, 0).day;
  final dia = d.day > ultimoDia ? ultimoDia : d.day;
  return DateTime(ano, mes, dia, d.hour, d.minute);
}

/// Rascunho da próxima cobrança de uma conta: a mesma conta, um mês depois.
/// Só para contas avulsas (as que já se repetem não precisam).
Draft? proximaCobranca(Item i) {
  final a = i.ancora;
  if (i.tipo != TipoItem.conta || i.regra != null || a == null) return null;
  return Draft.deItem(i)..definirAncora(somarMeses(a, 1));
}

/// Chame depois de `concluir`. [antes] é o que `concluir` devolveu (para o "Desfazer").
void avisarConcluido(BuildContext context, WidgetRef ref, Item item, Item? antes) {
  HapticFeedback.mediumImpact();
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(itemsProvider.notifier);
  final eConta = item.tipo == TipoItem.conta;
  final proxima = proximaCobranca(item);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: Duration(seconds: proxima == null ? 4 : 9),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('“${item.titulo}” ${eConta ? 'paga' : 'concluído'}.'),
        if (proxima != null)
          TextButton.icon(
            onPressed: () async {
              messenger.hideCurrentSnackBar();
              final mes = DateFormat.MMMM('pt_BR').format(proxima.ancora!);
              await notifier.criar(proxima);
              messenger.showSnackBar(SnackBar(content: Text('Conta de $mes agendada.')));
            },
            icon: const Icon(Icons.event_repeat_outlined, size: 18),
            label: Text('Agendar para ${DateFormat.MMMM('pt_BR').format(proxima.ancora!)}'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandSoft,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    ),
    action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
  ));
}
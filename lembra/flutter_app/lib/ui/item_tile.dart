import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../domain/categoria_conta.dart';
import '../domain/dinheiro.dart';
import '../domain/item.dart';
import 'agenda.dart';
import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

IconData iconeDoTipo(TipoItem t) => switch (t) {
      TipoItem.compromisso => Icons.event_outlined,
      TipoItem.tarefa => Icons.task_alt_outlined,
      TipoItem.habito => Icons.repeat,
      TipoItem.conta => Icons.receipt_long_outlined,
    };

/// Ícone de cada tipo de conta (água, luz, ...).
IconData iconeDaCategoria(CategoriaConta c) => switch (c) {
      CategoriaConta.agua => Icons.water_drop_outlined,
      CategoriaConta.luz => Icons.bolt_outlined,
      CategoriaConta.gas => Icons.local_fire_department_outlined,
      CategoriaConta.internet => Icons.wifi_rounded,
      CategoriaConta.telefone => Icons.phone_android_outlined,
      CategoriaConta.aluguel => Icons.home_outlined,
      CategoriaConta.condominio => Icons.apartment_outlined,
      CategoriaConta.cartao => Icons.credit_card_outlined,
      CategoriaConta.financiamento => Icons.account_balance_outlined,
      CategoriaConta.impostos => Icons.receipt_long_outlined,
      CategoriaConta.saude => Icons.health_and_safety_outlined,
      CategoriaConta.educacao => Icons.school_outlined,
      CategoriaConta.assinaturas => Icons.subscriptions_outlined,
      CategoriaConta.outros => Icons.more_horiz_rounded,
    };

/// Conta com tipo definido usa o ícone do tipo; os demais usam o ícone do item.
IconData _icone(Item item) => (item.tipo == TipoItem.conta && item.categoria != null)
    ? iconeDaCategoria(item.categoria!)
    : iconeDoTipo(item.tipo);

/// Cor do quadradinho do ícone, por tipo de item.
Color corDoTipo(TipoItem t) => switch (t) {
      TipoItem.compromisso => AppColors.cyan,
      TipoItem.tarefa => AppColors.orange,
      TipoItem.habito => AppColors.green,
      TipoItem.conta => AppColors.yellow,
    };

String subtituloDoItem(Item item, DateTime agora) {
  final a = item.ancora;
  final r = item.regra;
  if (r != null) {
    final hora = a == null ? '' : ' • ${DateFormat.Hm('pt_BR').format(a)}';
    return '${r.descricao}$hora';
  }
  if (a == null) return 'Sem data';
  final temHora = a.hour != 0 || a.minute != 0;
  return quandoCurto(a, comHora: temHora, agora: agora);
}

/// Texto de apoio sem o horário (o horário aparece à direita, em destaque).
String _meta(Item item, DateTime agora) {
  final base = _metaData(item, agora);
  final c = item.tipo == TipoItem.conta ? item.categoria : null;
  return c == null ? base : '${c.rotulo} • $base';
}

String _metaData(Item item, DateTime agora) {
  final r = item.regra;
  if (r != null) return r.descricao;
  final a = item.ancora;
  if (a == null) return 'Sem data';
  return toBeginningOfSentenceCase(quandoCurto(a, comHora: false, agora: agora)) ?? '';
}

/// Mapeia a urgência do domínio para o chip visual.
Urgency _urgencia(Item item) {
  final u = item.urgencia.toString().toLowerCase();
  if (u.contains('critico')) return Urgency.critical;
  if (u.contains('discreto') || u.contains('silencio')) return Urgency.discreet;
  return Urgency.normal;
}

const _vermelhoAtraso = Color(0xFFDC2626);

/// Linha da agenda. Deslizar para a direita conclui; para a esquerda cancela.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onConcluir,
    required this.onCancelar,
    this.feito = false,
  });

  final Item item;
  final VoidCallback onTap;
  final VoidCallback onConcluir;
  final VoidCallback onCancelar;
  final bool feito;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final agora = DateTime.now();
    final a = item.ancora;
    final critico = item.urgencia == Urgencia.critico;
    final atrasado = !feito && item.regra == null && (a?.isBefore(agora) ?? false);
    final temHora = a != null && (a.hour != 0 || a.minute != 0);
    final mostraValor = item.tipo == TipoItem.conta && item.valor != null;
    final destaque = critico && !feito;

    final cartao = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Opacity(
        opacity: feito ? 0.65 : 1,
        child: Material(
          color: AppColors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: destaque ? corCritico : AppColors.cardBorder,
              width: destaque ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  IconBadge(icon: _icone(item), color: corDoTipo(item.tipo)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: feito ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!feito) UrgencyChip(_urgencia(item)),
                            Text(
                              _meta(item, agora),
                              style: t.bodySmall?.copyWith(
                                color: atrasado ? _vermelhoAtraso : AppColors.muted,
                                fontWeight: atrasado ? FontWeight.w600 : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (mostraValor || temHora)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (mostraValor) Text(formatarReais(item.valor!), style: AppText.mono(size: 14)),
                        if (temHora)
                          Text(
                            DateFormat.Hm('pt_BR').format(a),
                            style: mostraValor
                                ? AppText.mono(size: 12, weight: FontWeight.w500, color: AppColors.muted)
                                : AppText.mono(size: 15),
                          ),
                      ],
                    ),
                  if (feito)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle, color: AppColors.green),
                    )
                  else
                    IconButton(
                      tooltip: 'Concluir',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: onConcluir,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (feito) return cartao;

    Widget fundo(Color cor, Color fg, IconData icone, Alignment alinhamento) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(20)),
          alignment: alinhamento,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Icon(icone, color: fg),
        );

    return Dismissible(
      key: ValueKey(item.id),
      // Itens recorrentes não somem ao concluir: só dá para cancelar deslizando (concluir pelo botão).
      direction: item.regra != null ? DismissDirection.endToStart : DismissDirection.horizontal,
      background: fundo(AppColors.green, AppColors.ink, Icons.check, Alignment.centerLeft),
      secondaryBackground: fundo(AppColors.red, Colors.white, Icons.close, Alignment.centerRight),
      onDismissed: (dir) => dir == DismissDirection.startToEnd ? onConcluir() : onCancelar(),
      child: cartao,
    );
  }
}
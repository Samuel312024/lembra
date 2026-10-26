// Coloque em: lib/ui/resumo_mes_page.dart
//
// Resumo do mês: quanto já foi pago, quanto falta pagar e para onde vai o
// dinheiro (por tipo de conta). Abre pelo ícone de gráfico na lista de contas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/categoria_conta.dart';
import '../domain/dinheiro.dart';
import '../domain/item.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'item_tile.dart' show iconeDaCategoria;
import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

class _Totais {
  _Totais({required this.pago, required this.aPagar, required this.porTipo, required this.semValor});

  final double pago;
  final double aPagar;
  final Map<CategoriaConta?, double> porTipo;
  final int semValor;

  double get total => pago + aPagar;
}

/// Contas com valor de um mês: pagas (concluídas nele) e a pagar (vencem nele).
_Totais _calcular(List<Item> itens, DateTime mes, DateTime agora) {
  final inicio = DateTime(mes.year, mes.month);
  final fim = DateTime(mes.year, mes.month + 1);
  bool noMes(DateTime d) => !d.isBefore(inicio) && d.isBefore(fim);

  var pago = 0.0;
  var aPagar = 0.0;
  var semValor = 0;
  final porTipo = <CategoriaConta?, double>{};

  void somar(Item i, bool paga) {
    final v = i.valor;
    if (v == null) {
      semValor++;
      return;
    }
    if (paga) {
      pago += v;
    } else {
      aPagar += v;
    }
    porTipo[i.categoria] = (porTipo[i.categoria] ?? 0) + v;
  }

  for (final i in itens) {
    if (i.tipo != TipoItem.conta || i.status == StatusItem.cancelado) continue;
    final c = i.concluidoEm;
    if (c != null && noMes(c) && (i.status == StatusItem.concluido || i.regra != null)) {
      somar(i, true);
    } else if (i.status == StatusItem.ativo) {
      final d = dataExibicao(i, agora);
      if (d != null && noMes(d)) somar(i, false);
    }
  }
  return _Totais(pago: pago, aPagar: aPagar, porTipo: porTipo, semValor: semValor);
}

class ResumoMesPage extends ConsumerStatefulWidget {
  const ResumoMesPage({super.key});

  @override
  ConsumerState<ResumoMesPage> createState() => _ResumoMesPageState();
}

class _ResumoMesPageState extends ConsumerState<ResumoMesPage> {
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  void _mudarMes(int delta) => setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  Widget _seletorDeMes(BuildContext context) {
    final rotulo = toBeginningOfSentenceCase(DateFormat("MMMM 'de' y", 'pt_BR').format(_mes)) ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _mudarMes(-1),
          ),
          Expanded(
            child: Center(
              child: Text(rotulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            tooltip: 'Próximo mês',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _mudarMes(1),
          ),
        ],
      ),
    );
  }

  Widget _numero(BuildContext context, String rotulo, double valor, Color cor) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: t.bodySmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatarReais(valor), style: AppText.mono(size: 16, color: cor)),
          ),
        ],
      ),
    );
  }

  Widget _linhaDoTipo(BuildContext context, CategoriaConta? tipo, double valor, double maior, double total) {
    final t = Theme.of(context).textTheme;
    final percentual = total > 0 ? (valor / total * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(
            icon: tipo == null ? Icons.receipt_long_outlined : iconeDaCategoria(tipo),
            color: AppColors.yellow,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tipo?.rotulo ?? 'Sem tipo', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Text(formatarReais(valor), style: AppText.mono(size: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maior > 0 ? valor / maior : 0,
                    minHeight: 6,
                    color: AppColors.brand,
                    backgroundColor: AppColors.cardBorder,
                  ),
                ),
                const SizedBox(height: 2),
                Text('$percentual% do mês', style: t.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _corpo(BuildContext context, List<Item> lista) {
    final t = Theme.of(context).textTheme;
    final r = _calcular(lista, _mes, DateTime.now());
    final tipos = r.porTipo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maior = tipos.isEmpty ? 0.0 : tipos.first.value;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _seletorDeMes(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total do mês', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatarReais(r.total), style: AppText.mono(size: 32)),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.cardBorder),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _numero(context, 'Já pago', r.pago, const Color(0xFF15803D)),
                    const SizedBox(width: 12),
                    _numero(context, 'A pagar', r.aPagar, r.aPagar > 0 ? AppColors.brand : AppColors.ink),
                  ],
                ),
                if (r.semValor > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    r.semValor == 1
                        ? '1 conta do mês está sem valor e não entrou na soma.'
                        : '${r.semValor} contas do mês estão sem valor e não entraram na soma.',
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Text('Por tipo de conta', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (tipos.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Nenhuma conta com valor neste mês. Informe o valor ao cadastrar uma conta para ver o resumo.',
              style: t.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [for (final e in tipos) _linhaDoTipo(context, e.key, e.value, maior, r.total)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Text(
            'Contas que se repetem mostram apenas o último pagamento feito.',
            style: t.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = ref.watch(itemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo do mês')),
      body: itens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar: $e')),
        data: (lista) => _corpo(context, lista),
      ),
    );
  }
}
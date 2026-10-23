// Coloque em: lib/ui/resumo_contas.dart
//
// Contas em aberto, separadas por situação, com os totais em reais.
// É a mesma conta usada no card da tela inicial e na lista de contas.

import '../domain/categoria_conta.dart';
import '../domain/item.dart';
import 'agenda.dart';

class ResumoContas {
  ResumoContas._(this.vencidas, this.proximas, this.depois, this.semData);

  /// [categoria] filtra por tipo de conta (null = todas).
  factory ResumoContas.de(List<Item> itens, DateTime agora, {CategoriaConta? categoria}) {
    final hoje = inicioDoDia(agora);
    final limite = agora.add(const Duration(days: 7));
    // Conta só com data (00:00) só está vencida a partir do dia seguinte.
    bool vencida(DateTime d) => d.isBefore(agora) && (d.hour != 0 || d.minute != 0 || d.isBefore(hoje));

    final comData = <(DateTime, Item)>[];
    final semData = <Item>[];
    for (final i in itens) {
      if (i.tipo != TipoItem.conta || i.status != StatusItem.ativo) continue;
      if (categoria != null && i.categoria != categoria) continue;
      // Conta recorrente já paga hoje não conta como em aberto.
      if (i.regra != null && i.concluidoEm != null && mesmoDia(i.concluidoEm!, agora)) continue;
      final d = dataExibicao(i, agora);
      if (d == null) {
        semData.add(i);
      } else {
        comData.add((d, i));
      }
    }
    comData.sort((a, b) => a.$1.compareTo(b.$1));

    final vencidas = <Item>[];
    final proximas = <Item>[];
    final depois = <Item>[];
    for (final (d, i) in comData) {
      if (vencida(d)) {
        vencidas.add(i);
      } else if (d.isBefore(limite)) {
        proximas.add(i);
      } else {
        depois.add(i);
      }
    }
    return ResumoContas._(vencidas, proximas, depois, semData);
  }

  final List<Item> vencidas;
  final List<Item> proximas; // próximos 7 dias
  final List<Item> depois; // mais adiante
  final List<Item> semData;

  List<Item> get abertas => [...vencidas, ...proximas, ...depois, ...semData];

  int get quantidade => vencidas.length + proximas.length + depois.length + semData.length;

  /// Soma dos valores informados (contas sem valor entram como zero).
  static double somaDe(Iterable<Item> itens) => itens.fold(0.0, (s, i) => s + (i.valor ?? 0));

  double get total => somaDe(abertas);
  double get totalVencidas => somaDe(vencidas);
  double get totalProximas => somaDe(proximas);
  double get totalDepois => somaDe(depois);

  bool get temValor => abertas.any((i) => i.valor != null);

  int get semValor => abertas.where((i) => i.valor == null).length;
}

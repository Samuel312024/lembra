// Coloque em: lib/domain/renda.dart
//
// Perfil de renda (CLT ou PJ) e a comparação "contas do mês x renda",
// incluindo a "margem vermelha" (faixa acima do limite escolhido).

import 'dart:math' as math;

import 'dinheiro.dart';

enum TipoRenda {
  clt('CLT'),
  pj('PJ (empresa)');

  const TipoRenda(this.rotulo);
  final String rotulo;
}

class PerfilRenda {
  const PerfilRenda({
    this.tipo = TipoRenda.clt,
    this.salarioLiquido = 0,
    this.outrasRendas = 0,
    this.faturamento = 0,
    this.impostoPct = 6,
    this.custosEmpresa = 0,
    this.limitePct = 70,
  });

  final TipoRenda tipo;

  /// CLT: o que cai na conta (salário líquido).
  final double salarioLiquido;

  /// Qualquer renda extra mensal (opcional, vale para CLT e PJ).
  final double outrasRendas;

  /// PJ: faturamento mensal bruto da empresa.
  final double faturamento;

  /// PJ: % de imposto sobre o faturamento (ex.: 6 no Simples Nacional).
  final double impostoPct;

  /// PJ: custos fixos mensais da empresa (contador, taxas, etc.).
  final double custosEmpresa;

  /// A partir de quantos % da renda as contas entram na margem vermelha.
  final double limitePct;

  double get imposto => tipo == TipoRenda.pj ? faturamento * impostoPct / 100 : 0;

  /// Renda mensal considerada na comparação.
  /// CLT: salário líquido + outras rendas.
  /// PJ: faturamento − impostos − custos da empresa + outras rendas.
  double get rendaMensal {
    final base = tipo == TipoRenda.clt ? salarioLiquido : faturamento - imposto - custosEmpresa;
    return math.max(0.0, base + outrasRendas);
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo.name,
        'salarioLiquido': salarioLiquido,
        'outrasRendas': outrasRendas,
        'faturamento': faturamento,
        'impostoPct': impostoPct,
        'custosEmpresa': custosEmpresa,
        'limitePct': limitePct,
      };

  factory PerfilRenda.fromJson(Map<String, dynamic> j) {
    double n(String k, double padrao) => (j[k] as num?)?.toDouble() ?? padrao;
    return PerfilRenda(
      tipo: TipoRenda.values.firstWhere((t) => t.name == j['tipo'], orElse: () => TipoRenda.clt),
      salarioLiquido: n('salarioLiquido', 0),
      outrasRendas: n('outrasRendas', 0),
      faturamento: n('faturamento', 0),
      impostoPct: n('impostoPct', 6),
      custosEmpresa: n('custosEmpresa', 0),
      limitePct: n('limitePct', 70),
    );
  }
}

enum NivelGasto { semRenda, folga, margemVermelha, estourou }

class ComparativoRenda {
  const ComparativoRenda({required this.renda, required this.gasto, required this.limitePct});

  final double renda;
  final double gasto;
  final double limitePct;

  bool get temRenda => renda > 0;
  double get sobra => renda - gasto;

  /// Fração da renda comprometida (1.0 = 100%; pode passar de 1).
  double get fracao => temRenda ? gasto / renda : 0;

  double get valorLimite => renda * limitePct / 100;

  NivelGasto get nivel {
    if (!temRenda) return NivelGasto.semRenda;
    if (gasto > renda) return NivelGasto.estourou;
    if (gasto > valorLimite) return NivelGasto.margemVermelha;
    return NivelGasto.folga;
  }

  bool get emVermelho => nivel == NivelGasto.margemVermelha || nivel == NivelGasto.estourou;

  String get mensagem => switch (nivel) {
        NivelGasto.semRenda => '',
        NivelGasto.folga => 'Dentro do limite: sobram ${formatarReais(sobra)} depois das contas.',
        NivelGasto.margemVermelha =>
          'Margem vermelha: as contas passaram de ${limitePct.round()}% da renda. Sobram ${formatarReais(sobra)}.',
        NivelGasto.estourou => 'As contas passaram da renda em ${formatarReais(-sobra)}.',
      };
}

String nomeMes(DateTime d) => const [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ][d.month - 1];

/// Converte "5.000,50", "5000,5", "5000" ou "R$ 5.000" em número.
double lerValor(String texto) {
  var s = texto.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (s.isEmpty) return 0;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s) ?? 0;
}
// Coloque em: lib/domain/dinheiro.dart

import 'package:intl/intl.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 2);

/// 1250.5 -> "R$ 1.250,50"
String formatarReais(double valor) => _moeda.format(valor).replaceAll('\u00A0', ' ');

/// Lê um valor digitado no padrão brasileiro: "1.250,50", "1250,5", "50".
/// Devolve null se estiver vazio ou inválido.
double? lerReais(String texto) {
  var s = texto.replaceAll(RegExp(r'[^0-9,.]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    // vírgula = centavos; pontos = milhar
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    // "1.250" = mil duzentos e cinquenta
    s = s.replaceAll('.', '');
  }
  final v = double.tryParse(s);
  if (v == null || v < 0) return null;
  return (v * 100).round() / 100;
}
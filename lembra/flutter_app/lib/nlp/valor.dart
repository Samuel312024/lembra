// Coloque em: lib/nlp/valor.dart

import '../domain/dinheiro.dart';

/// Valor em reais achado numa frase e a posição dele no texto.
class ValorEncontrado {
  const ValorEncontrado(this.valor, this.inicio, this.fim);

  final double valor;
  final int inicio;
  final int fim;
}

const _numero = r'(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)';
final _reCifrao = RegExp(r'r\$\s*' + _numero);
final _reReais = RegExp(_numero + r'\s*(?:reais|real|conto|contos)\b');

/// Procura "R$ 150", "R$ 1.250,50" ou "150 reais" em um texto JÁ normalizado
/// (minúsculo, sem acento). Os índices valem também para o texto original.
ValorEncontrado? extrairValor(String textoNormalizado) {
  for (final re in [_reCifrao, _reReais]) {
    final m = re.firstMatch(textoNormalizado);
    if (m == null) continue;
    final v = lerReais(m.group(1)!);
    if (v != null && v > 0) return ValorEncontrado(v, m.start, m.end);
  }
  return null;
}
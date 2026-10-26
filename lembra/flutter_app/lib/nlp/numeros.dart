// Coloque em: lib/nlp/numeros.dart
//
// Números por extenso em português ("quinhentos", "dois mil e duzentos").
// Trabalha com texto já normalizado (minúsculo, sem acento).

const _valores = <String, int>{
  'zero': 0,
  'um': 1,
  'uma': 1,
  'dois': 2,
  'duas': 2,
  'tres': 3,
  'quatro': 4,
  'cinco': 5,
  'seis': 6,
  'sete': 7,
  'oito': 8,
  'nove': 9,
  'dez': 10,
  'onze': 11,
  'doze': 12,
  'treze': 13,
  'quatorze': 14,
  'catorze': 14,
  'quinze': 15,
  'dezesseis': 16,
  'dezessete': 17,
  'dezoito': 18,
  'dezenove': 19,
  'vinte': 20,
  'trinta': 30,
  'quarenta': 40,
  'cinquenta': 50,
  'sessenta': 60,
  'setenta': 70,
  'oitenta': 80,
  'noventa': 90,
  'cem': 100,
  'cento': 100,
  'duzentos': 200,
  'duzentas': 200,
  'trezentos': 300,
  'trezentas': 300,
  'quatrocentos': 400,
  'quatrocentas': 400,
  'quinhentos': 500,
  'quinhentas': 500,
  'seiscentos': 600,
  'seiscentas': 600,
  'setecentos': 700,
  'setecentas': 700,
  'oitocentos': 800,
  'oitocentas': 800,
  'novecentos': 900,
  'novecentas': 900,
};

/// Palavras que formam um número, separadas por "|" (para expressões regulares).
final String palavrasDeNumero = [..._valores.keys, 'mil'].join('|');

/// "dois mil e quinhentos" -> 2500. Devolve null se houver palavra desconhecida.
int? lerNumeroPorExtenso(String texto) {
  var total = 0;
  var atual = 0;
  var achou = false;
  for (final p in texto.trim().split(RegExp(r'\s+'))) {
    if (p.isEmpty || p == 'e') continue;
    if (p == 'mil') {
      total += (atual == 0 ? 1 : atual) * 1000;
      atual = 0;
      achou = true;
      continue;
    }
    final v = _valores[p];
    if (v == null) return null;
    atual += v;
    achou = true;
  }
  return achou ? total + atual : null;
}
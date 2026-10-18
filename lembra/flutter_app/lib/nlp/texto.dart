/// Utilitários de texto para o interpretador de português.
const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
const _semAcento = 'aaaaaeeeeiiiiooooouuuuc';

/// Minúsculas e sem acentos, preservando o comprimento: os índices do texto
/// normalizado valem também para o texto original.
String normalizar(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = _comAcento.indexOf(c);
    b.write(i >= 0 ? _semAcento[i] : c);
  }
  return b.toString();
}

String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Remove do [original] os trechos (início, fim) já interpretados como data/hora.
String removerTrechos(String original, List<(int, int)> trechos) {
  final ordenados = [...trechos]..sort((a, b) => b.$1.compareTo(a.$1));
  var s = original;
  for (final t in ordenados) {
    if (t.$1 >= 0 && t.$2 <= s.length) s = s.replaceRange(t.$1, t.$2, ' ');
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

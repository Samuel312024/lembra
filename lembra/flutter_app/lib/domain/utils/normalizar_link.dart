/// Aceita "site.com", "www.site.com/pagina" ou "https://site.com" e devolve o
/// endereço completo (com https:// quando faltar). Devolve null se o texto não
/// parecer um link válido.
String? normalizarLink(String texto) {
  var t = texto.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;

  final temEsquema = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(t);
  if (!temEsquema) t = 'https://$t';

  final uri = Uri.tryParse(t);
  if (uri == null) return null;

  final esquema = uri.scheme.toLowerCase();
  if (esquema != 'http' && esquema != 'https') return null;

  final host = uri.host;
  if (host.isEmpty) return null;
  // "abc" sozinho não é um endereço; precisa de ponto (site.com) ou ser localhost.
  if (!host.contains('.') && host != 'localhost') return null;

  return t;
}
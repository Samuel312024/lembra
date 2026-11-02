import '../domain/reuniao.dart';

/// Procura e classifica links de videoconferência em textos de eventos
/// (descrição, local, URL). Função pura: fácil de cobrir com testes unitários.
class LeitorLinkReuniao {
  const LeitorLinkReuniao._();

  static final _regexUrl = RegExp(r'''https?://[^\s<>"')\]]+''', caseSensitive: false);

  /// Devolve o primeiro link de reunião encontrado nos [textos], na ordem dada.
  static LinkReuniao? extrair(Iterable<String?> textos) {
    for (final texto in textos) {
      if (texto == null || texto.isEmpty) continue;
      for (final m in _regexUrl.allMatches(texto)) {
        final bruto = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
        final link = _classificar(Uri.tryParse(bruto));
        if (link != null) return link;
      }
    }
    return null;
  }

  static LinkReuniao? _classificar(Uri? uri) {
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    final caminho = uri.path.toLowerCase();

    // O Outlook "embrulha" links em safelinks; o link real vem no parâmetro url.
    if (host.endsWith('safelinks.protection.outlook.com')) {
      return _classificar(Uri.tryParse(uri.queryParameters['url'] ?? ''));
    }

    PlataformaReuniao? plataforma;
    if (host == 'teams.microsoft.com' || host == 'teams.live.com') {
      if (caminho.contains('/meetup-join') || caminho.startsWith('/meet/')) {
        plataforma = PlataformaReuniao.teams;
      }
    } else if (host == 'meet.google.com') {
      // Ex.: /abc-defg-hij (ignora a página inicial do Meet)
      if (caminho.length > 1) plataforma = PlataformaReuniao.meet;
    } else if (host == 'zoom.us' || host.endsWith('.zoom.us')) {
      if (caminho.startsWith('/j/') || caminho.startsWith('/my/')) {
        plataforma = PlataformaReuniao.zoom;
      }
    } else if (host.endsWith('.webex.com') || host == 'webex.com') {
      plataforma = PlataformaReuniao.webex;
    }

    return plataforma == null
        ? null
        : LinkReuniao(plataforma: plataforma, url: uri);
  }
}
/// Plataformas de videoconferência reconhecidas pelo Lembra.
enum PlataformaReuniao { teams, meet, zoom, webex }

extension PlataformaReuniaoNome on PlataformaReuniao {
  String get nome => switch (this) {
        PlataformaReuniao.teams => 'Microsoft Teams',
        PlataformaReuniao.meet => 'Google Meet',
        PlataformaReuniao.zoom => 'Zoom',
        PlataformaReuniao.webex => 'Webex',
      };
}

/// Link de entrada de uma reunião online, já classificado por plataforma.
class LinkReuniao {
  const LinkReuniao({required this.plataforma, required this.url});

  final PlataformaReuniao plataforma;
  final Uri url;
}

/// Reunião exibida na aba "Reuniões" (vinda do calendário do aparelho).
class Reuniao {
  const Reuniao({
    required this.id,
    required this.calendarioId,
    required this.calendarioNome,
    required this.titulo,
    required this.inicio,
    required this.fim,
    this.local,
    this.link,
    this.participantes = const [],
    this.diaInteiro = false,
  });

  final String id;
  final String calendarioId;
  final String calendarioNome;
  final String titulo;
  final DateTime inicio;
  final DateTime fim;
  final String? local;
  final LinkReuniao? link;
  final List<String> participantes;
  final bool diaInteiro;

  bool get temLink => link != null;

  bool get emAndamento {
    final agora = DateTime.now();
    return !agora.isBefore(inicio) && agora.isBefore(fim);
  }

  /// O botão "Entrar" é liberado 10 minutos antes do início e até o fim.
  bool get podeEntrar {
    if (!temLink) return false;
    final agora = DateTime.now();
    return agora.isAfter(inicio.subtract(const Duration(minutes: 10))) &&
        agora.isBefore(fim);
  }
}
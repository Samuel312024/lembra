// Coloque em: lib/services/convite_remoto.dart
//
// Tradução entre o Agendamento do app e a reunião do backend (rotas /convites).
// Não faz chamada de rede: só monta o corpo dos pedidos e aplica a resposta do
// servidor no registro local.

import '../data/api_client.dart' show isoComFuso;
import '../domain/agendamento.dart';

class ConviteRemoto {
  const ConviteRemoto._();

  static String _cortar(String t, int max) => t.length <= max ? t : t.substring(0, max);

  static String _norm(String? s) => (s ?? '').trim().toLowerCase();

  static RespostaConvite _resposta(Object? nome) {
    for (final r in RespostaConvite.values) {
      if (r.name == nome) return r;
    }
    return RespostaConvite.pendente;
  }

  // -------------------------------------------------------------------------
  // App -> servidor
  // -------------------------------------------------------------------------

  /// Corpo do POST /convites. O fuso fica de fora de propósito: o servidor usa
  /// America/Sao_Paulo quando ele não vem. O "fim" também não existe no servidor.
  static Map<String, Object?> corpoCriar(Agendamento a) {
    final onde = a.linkOuLocal?.trim() ?? '';
    return {
      'titulo': _cortar(a.titulo.trim(), 200),
      'inicio': isoComFuso(a.inicio),
      if (onde.isNotEmpty) 'local': _cortar(onde, 500),
      'participantes': [for (final c in a.convidados) _participante(c)],
    };
  }

  /// Corpo do PATCH /convites/:id (título, início e local).
  static Map<String, Object?> corpoEditar(Agendamento a) {
    final onde = a.linkOuLocal?.trim() ?? '';
    return {
      'titulo': _cortar(a.titulo.trim(), 200),
      'inicio': isoComFuso(a.inicio),
      'local': onde.isEmpty ? null : _cortar(onde, 500),
    };
  }

  static Map<String, Object?> _participante(Convidado c) {
    final contato = c.contato.trim();
    final nome = c.nome.trim().isEmpty ? contato : c.nome.trim();
    return {
      'nome': _cortar(nome, 120),
      if (c.canal == CanalConvite.email) 'email': contato else 'telefone': _cortar(contato, 30),
    };
  }

  // -------------------------------------------------------------------------
  // Servidor -> app
  // -------------------------------------------------------------------------

  /// Acha o participante do servidor que corresponde ao convidado, pelo contato
  /// (a ordem da lista do servidor é por nome, então não dá para usar a posição).
  static Map<String, dynamic>? _achar(Convidado c, List<Map<String, dynamic>> remotos) {
    final email = c.canal == CanalConvite.email;
    final chave = email ? _norm(c.contato) : _norm(_cortar(c.contato.trim(), 30));
    if (chave.isEmpty) return null;
    for (final r in remotos) {
      if (_norm(r[email ? 'email' : 'telefone'] as String?) == chave) return r;
    }
    return null;
  }

  /// Aplica no [a] a reunião devolvida pelo servidor (POST, PATCH ou um item do
  /// GET /convites): guarda os ids e os links e traz as respostas novas.
  /// Nunca troca uma resposta já registrada por "pendente". Devolve true se algo mudou,
  /// para o chamador saber se precisa salvar.
  static bool aplicar(Agendamento a, Map<String, dynamic> remota) {
    var mudou = false;

    final id = remota['id'] as String?;
    if (id != null && a.remotoId != id) {
      a.remotoId = id;
      mudou = true;
    }

    final lista = <Map<String, dynamic>>[
      for (final p in (remota['participantes'] as List? ?? const [])) (p as Map).cast<String, dynamic>(),
    ];

    for (final c in a.convidados) {
      final r = _achar(c, lista);
      if (r == null) continue;

      final rid = r['id'] as String?;
      if (rid != null && c.remotoId != rid) {
        c.remotoId = rid;
        mudou = true;
      }

      final link = r['link'] as String?;
      if (link != null && c.link != link) {
        c.link = link;
        mudou = true;
      }

      // E-mail enviado pelo servidor conta como convite enviado.
      final enviado = DateTime.tryParse('${r['enviadoEm'] ?? ''}')?.toLocal();
      if (enviado != null && c.conviteEnviadoEm == null) {
        c.conviteEnviadoEm = enviado;
        mudou = true;
      }

      final resposta = _resposta(r['resposta']);
      if (resposta != RespostaConvite.pendente && resposta != c.resposta) {
        c.resposta = resposta;
        c.respondidoEm = DateTime.tryParse('${r['respondidoEm'] ?? ''}')?.toLocal() ?? DateTime.now();
        c.automatica = false;
        mudou = true;
      }
    }
    return mudou;
  }
}
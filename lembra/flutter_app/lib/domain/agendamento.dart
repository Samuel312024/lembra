// Coloque em: lib/domain/agendamento.dart
//
// Registro local de uma reunião agendada pelo Lembra: dados da reunião, lista de
// convidados e a resposta (aceito / recusado / talvez) de cada um. É isso que
// forma o "histórico de criação": o registro fica salvo até o usuário excluir.

import 'package:uuid/uuid.dart';

/// Resposta de um convidado ao convite.
enum RespostaConvite { pendente, aceito, recusado, talvez }

/// Por onde o convite é enviado (decidido pelo contato digitado).
enum CanalConvite { whatsapp, email }

// ---------------------------------------------------------------------------
// Contatos
// ---------------------------------------------------------------------------

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool emailValido(String texto) => _regexEmail.hasMatch(texto.trim());

/// Telefone pronto para o wa.me (só dígitos, com DDI).
/// Aceita "(19) 99999-0000", "+55 19 99999-0000", "5519999990000"...
/// Números de 10 ou 11 dígitos ganham o DDI do Brasil (55).
String? telefoneParaWhatsapp(String texto) {
  var d = texto.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 10 || d.length == 11) return '55$d';
  if (d.length >= 12 && d.length <= 15) return d;
  return null;
}

bool contatoValido(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return false;
  return t.contains('@') ? emailValido(t) : telefoneParaWhatsapp(t) != null;
}

/// Procura um link de reunião (Teams, Meet, Zoom...) dentro de um texto.
/// Retorna null quando o texto é só um local ("Sala 3").
({Uri url, String plataforma})? detectarLink(String? texto) {
  final t = texto?.trim() ?? '';
  if (t.isEmpty) return null;
  final m = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  final uri = Uri.tryParse(m.group(0)!);
  if (uri == null || !uri.hasAuthority) return null;
  final host = uri.host.toLowerCase();
  final nome = host.contains('teams.microsoft') || host.contains('teams.live')
      ? 'Microsoft Teams'
      : host.contains('meet.google')
          ? 'Google Meet'
          : host.contains('zoom.us')
              ? 'Zoom'
              : host.contains('webex')
                  ? 'Webex'
                  : 'Link da reunião';
  return (url: uri, plataforma: nome);
}

DateTime? _dt(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

RespostaConvite _resposta(Object? nome) {
  for (final r in RespostaConvite.values) {
    if (r.name == nome) return r;
  }
  return RespostaConvite.pendente;
}

// ---------------------------------------------------------------------------
// Convidado
// ---------------------------------------------------------------------------

class Convidado {
  Convidado({
    String? id,
    required this.nome,
    required this.contato,
    this.resposta = RespostaConvite.pendente,
    this.conviteEnviadoEm,
    this.respondidoEm,
    this.automatica = false,
    this.remotoId,
    this.link,
  }) : id = id ?? const Uuid().v4();

  final String id;
  String nome;

  /// Telefone (WhatsApp) ou e-mail, como o usuário digitou.
  String contato;
  RespostaConvite resposta;
  DateTime? conviteEnviadoEm;
  DateTime? respondidoEm;

  /// true = a resposta veio sozinha do Google Agenda; false = registrada pelo usuário.
  bool automatica;

  /// Id deste convidado no backend (preenchido depois de POST /convites).
  String? remotoId;

  /// Link de resposta gerado pelo backend. Vai na mensagem do WhatsApp no lugar de "responda SIM/NÃO".
  String? link;

  CanalConvite get canal => contato.contains('@') ? CanalConvite.email : CanalConvite.whatsapp;

  String get primeiroNome {
    final partes = nome.trim().split(RegExp(r'\s+'));
    return partes.isEmpty || partes.first.isEmpty ? nome : partes.first;
  }

  /// Texto curto do estado atual, para etiquetas.
  String get statusRotulo => switch (resposta) {
        RespostaConvite.aceito => 'Aceitou',
        RespostaConvite.recusado => 'Recusou',
        RespostaConvite.talvez => 'Talvez',
        RespostaConvite.pendente => conviteEnviadoEm == null ? 'Convite não enviado' : 'Aguardando resposta',
      };

  Convidado copiar() => Convidado(
        id: id,
        nome: nome,
        contato: contato,
        resposta: resposta,
        conviteEnviadoEm: conviteEnviadoEm,
        respondidoEm: respondidoEm,
        automatica: automatica,
        remotoId: remotoId,
        link: link,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'nome': nome,
        'contato': contato,
        'resposta': resposta.name,
        'convite_enviado_em': conviteEnviadoEm?.millisecondsSinceEpoch,
        'respondido_em': respondidoEm?.millisecondsSinceEpoch,
        'automatica': automatica,
        'remoto_id': remotoId,
        'link': link,
      };

  factory Convidado.fromJson(Map<String, dynamic> j) => Convidado(
        id: j['id'] as String?,
        nome: (j['nome'] as String?) ?? '',
        contato: (j['contato'] as String?) ?? '',
        resposta: _resposta(j['resposta']),
        conviteEnviadoEm: _dt(j['convite_enviado_em']),
        respondidoEm: _dt(j['respondido_em']),
        automatica: (j['automatica'] as bool?) ?? false,
        remotoId: j['remoto_id'] as String?,
        link: j['link'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Agendamento
// ---------------------------------------------------------------------------

class Agendamento {
  Agendamento({
    required this.id,
    this.eventoId,
    this.calendarioId,
    this.calendarioNome = '',
    required this.titulo,
    required this.inicio,
    required this.fim,
    this.linkOuLocal,
    List<Convidado>? convidados,
    required this.criadoEm,
    required this.atualizadoEm,
    this.remotoId,
  }) : convidados = convidados ?? [];

  final String id;

  /// Id do evento no calendário do celular (para editar e excluir lá também).
  String? eventoId;
  String? calendarioId;
  String calendarioNome;

  /// Id da reunião no backend (preenchido depois de POST /convites).
  String? remotoId;

  String titulo;
  DateTime inicio;
  DateTime fim;

  /// Link da videochamada ou local, em um campo só (como no formulário).
  String? linkOuLocal;
  List<Convidado> convidados;
  final DateTime criadoEm;
  DateTime atualizadoEm;

  int _contar(RespostaConvite r) => convidados.where((c) => c.resposta == r).length;

  int get aceitos => _contar(RespostaConvite.aceito);
  int get recusados => _contar(RespostaConvite.recusado);
  int get talvez => _contar(RespostaConvite.talvez);

  /// Todos que ainda não responderam (com ou sem convite enviado).
  int get pendentes => _contar(RespostaConvite.pendente);

  /// Pendentes que ainda não receberam o convite.
  int get semConvite =>
      convidados.where((c) => c.resposta == RespostaConvite.pendente && c.conviteEnviadoEm == null).length;

  /// Pendentes que já receberam o convite e não responderam.
  int get aguardandoResposta => pendentes - semConvite;

  bool get todosAceitaram => convidados.isNotEmpty && aceitos == convidados.length;

  /// "2 aceitaram · 1 talvez · 1 aguardando". Vazio quando não há convidados.
  String get resumoRespostas {
    final partes = <String>[
      if (aceitos > 0) '$aceitos ${aceitos == 1 ? 'aceitou' : 'aceitaram'}',
      if (talvez > 0) '$talvez talvez',
      if (recusados > 0) '$recusados ${recusados == 1 ? 'recusou' : 'recusaram'}',
      if (aguardandoResposta > 0) '$aguardandoResposta aguardando',
      if (semConvite > 0) '$semConvite sem convite',
    ];
    return partes.join(' · ');
  }

  Agendamento copiar() => Agendamento(
        id: id,
        eventoId: eventoId,
        calendarioId: calendarioId,
        calendarioNome: calendarioNome,
        titulo: titulo,
        inicio: inicio,
        fim: fim,
        linkOuLocal: linkOuLocal,
        convidados: [for (final c in convidados) c.copiar()],
        criadoEm: criadoEm,
        atualizadoEm: atualizadoEm,
        remotoId: remotoId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'evento_id': eventoId,
        'calendario_id': calendarioId,
        'calendario_nome': calendarioNome,
        'titulo': titulo,
        'inicio': inicio.millisecondsSinceEpoch,
        'fim': fim.millisecondsSinceEpoch,
        'link_ou_local': linkOuLocal,
        'convidados': [for (final c in convidados) c.toJson()],
        'criado_em': criadoEm.millisecondsSinceEpoch,
        'atualizado_em': atualizadoEm.millisecondsSinceEpoch,
        'remoto_id': remotoId,
      };

  factory Agendamento.fromJson(Map<String, dynamic> j) {
    final lista = (j['convidados'] as List?) ?? const [];
    return Agendamento(
      id: j['id'] as String,
      eventoId: j['evento_id'] as String?,
      calendarioId: j['calendario_id'] as String?,
      calendarioNome: (j['calendario_nome'] as String?) ?? '',
      titulo: (j['titulo'] as String?) ?? '',
      inicio: _dt(j['inicio'])!,
      fim: _dt(j['fim'])!,
      linkOuLocal: j['link_ou_local'] as String?,
      convidados: [for (final e in lista) Convidado.fromJson((e as Map).cast<String, dynamic>())],
      criadoEm: _dt(j['criado_em']) ?? DateTime.now(),
      atualizadoEm: _dt(j['atualizado_em']) ?? DateTime.now(),
      remotoId: j['remoto_id'] as String?,
    );
  }
}
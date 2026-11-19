// Coloque em: lib/state/agendamentos_provider.dart
//
// Histórico de reuniões agendadas pelo Lembra, salvo no aparelho (SharedPreferences).
// Nada aqui apaga sozinho: um registro só sai quando o usuário exclui.
//
// Com login, a reunião também é criada no servidor (rotas /convites): cada convidado
// ganha um link de resposta e as respostas voltam sozinhas para cá.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart' show ApiErro;
import '../domain/agendamento.dart';
import '../services/convite_remoto.dart';
import '../services/evento_calendario.dart';
import 'providers.dart' show apiProvider, prefsProvider;

final agendamentosProvider =
    NotifierProvider<AgendamentosNotifier, List<Agendamento>>(AgendamentosNotifier.new);

/// Como terminou uma conversa com o servidor de convites.
enum EstadoServidor { ok, semLogin, falhou }

class ResultadoServidor {
  const ResultadoServidor(this.estado, {this.mensagem, this.criou = false});

  final EstadoServidor estado;

  /// Texto em português para mostrar ao usuário, quando houver.
  final String? mensagem;

  /// true = a reunião acabou de ser criada no servidor (e os e-mails saíram agora).
  final bool criou;

  bool get ok => estado == EstadoServidor.ok;
}

class AgendamentosNotifier extends Notifier<List<Agendamento>> {
  static const _chave = 'agendamentos_v1';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  List<Agendamento> build() {
    final bruto = _prefs.getString(_chave);
    if (bruto == null || bruto.isEmpty) return [];
    try {
      final lista = jsonDecode(bruto) as List;
      return [for (final e in lista) Agendamento.fromJson((e as Map).cast<String, dynamic>())];
    } catch (_) {
      // Dado ilegível: guarda uma cópia para não perder nada e começa limpo.
      _prefs.setString('${_chave}_ilegivel', bruto);
      return [];
    }
  }

  Future<void> _gravar(List<Agendamento> nova) async {
    state = nova;
    await _prefs.setString(_chave, jsonEncode([for (final a in nova) a.toJson()]));
  }

  Future<void> adicionar(Agendamento a) => _gravar([...state, a]);

  /// Salva a edição. Se a reunião já existe no servidor e título, horário ou local
  /// mudaram, o servidor também é atualizado (e avisa os convidados por e-mail).
  Future<void> atualizar(Agendamento a) async {
    final antes = _buscar(a.id);
    if (antes != null) _herdarDadosDoServidor(antes, a);
    await _gravar([for (final x in state) x.id == a.id ? a : x]);
    if (antes != null && a.remotoId != null && _mudouNoServidor(antes, a)) {
      unawaited(_editarNoServidor(a.id, horarioMudou: antes.inicio != a.inicio));
    }
  }

  /// Remove só do histórico do Lembra. Quem chama decide o que fazer com o calendário.
  Future<void> excluir(String id) => _gravar([for (final x in state) if (x.id != id) x]);

  /// Desfazer de uma exclusão.
  Future<void> restaurar(Agendamento a) async {
    if (state.any((x) => x.id == a.id)) return;
    await _gravar([...state, a]);
  }

  Future<void> _alterar(String id, void Function(Agendamento a) alterar) {
    final nova = <Agendamento>[];
    for (final a in state) {
      if (a.id == id) {
        final copia = a.copiar();
        alterar(copia);
        copia.atualizadoEm = DateTime.now();
        nova.add(copia);
      } else {
        nova.add(a);
      }
    }
    return _gravar(nova);
  }

  Future<void> definirResposta(String agendamentoId, String convidadoId, RespostaConvite resposta) {
    return _alterar(agendamentoId, (a) {
      for (final c in a.convidados) {
        if (c.id != convidadoId) continue;
        c.resposta = resposta;
        c.respondidoEm = resposta == RespostaConvite.pendente ? null : DateTime.now();
        c.automatica = false; // registrada pelo usuário
      }
    });
  }

  Agendamento? _buscar(String id) {
    for (final a in state) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// A reunião como está salva agora (útil depois de um await, quando o objeto antigo ficou velho).
  Agendamento? porId(String id) => _buscar(id);

  /// O convidado como está salvo agora.
  Convidado? convidadoAtual(String agendamentoId, String convidadoId) {
    final a = _buscar(agendamentoId);
    if (a == null) return null;
    for (final c in a.convidados) {
      if (c.id == convidadoId) return c;
    }
    return null;
  }

  bool _sincronizando = false;

  /// Lê no calendário do celular quem aceitou ou recusou o convite do Google Agenda
  /// e atualiza os convidados de e-mail. WhatsApp não passa por aqui (segue manual).
  ///
  /// Só altera quando o calendário traz uma resposta definitiva; nunca "volta" uma
  /// resposta que o usuário já registrou para "aguardando".
  Future<void> sincronizarComCalendario() async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final agora = DateTime.now();
      final servico = EventoCalendario();
      for (final a in [...state]) {
        final eventoId = a.eventoId;
        final calendarioId = a.calendarioId;
        if (eventoId == null || calendarioId == null) continue;
        if (!a.convidados.any((c) => c.canal == CanalConvite.email)) continue;
        // Reunião encerrada há mais de 7 dias: ninguém mais responde.
        if (agora.difference(a.fim) > const Duration(days: 7)) continue;
        final respostas = await servico.lerRespostas(calendarioId, eventoId);
        if (respostas == null) continue;
        await _aplicarRespostas(a.id, respostas);
      }
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _aplicarRespostas(String agendamentoId, Map<String, RespostaConvite> respostas) async {
    final atual = _buscar(agendamentoId);
    if (atual == null) return;

    bool mudaria(Convidado c) {
      if (c.canal != CanalConvite.email) return false;
      final r = respostas[c.contato.trim().toLowerCase()];
      if (r == null) return false;
      return c.conviteEnviadoEm == null || (r != RespostaConvite.pendente && r != c.resposta);
    }

    if (!atual.convidados.any(mudaria)) return;

    final agora = DateTime.now();
    await _alterar(agendamentoId, (a) {
      for (final c in a.convidados) {
        if (c.canal != CanalConvite.email) continue;
        final r = respostas[c.contato.trim().toLowerCase()];
        if (r == null) continue;
        // Estar na lista de convidados do evento = o Google Agenda mandou o convite.
        c.conviteEnviadoEm ??= agora;
        if (r != RespostaConvite.pendente && r != c.resposta) {
          c.resposta = r;
          c.respondidoEm = agora;
          c.automatica = true;
        }
      }
    });
  }

  Future<void> marcarEnviado(String agendamentoId, String convidadoId) {
    return _alterar(agendamentoId, (a) {
      for (final c in a.convidados) {
        if (c.id == convidadoId) c.conviteEnviadoEm = DateTime.now();
      }
    });
  }

  // -------------------------------------------------------------------------
  // Servidor de convites (precisa de login)
  // -------------------------------------------------------------------------

  /// Garante que a reunião existe no servidor. Se ainda não existe, cria: o servidor
  /// grava os convidados, manda o e-mail aos que têm e-mail e devolve o link de cada um.
  /// Se já existe, não faz nada (editar é com [atualizar]).
  Future<ResultadoServidor> garantirNoServidor(String agendamentoId) async {
    final api = ref.read(apiProvider);
    if (await api.token() == null) return const ResultadoServidor(EstadoServidor.semLogin);

    final a = _buscar(agendamentoId);
    if (a == null) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Esta reunião não existe mais.');
    }
        if (a.remotoId != null) return _incluirNovosNoServidor(agendamentoId);

    try {
      final remota = await api.criarConvite(ConviteRemoto.corpoCriar(a));
      await _alterar(agendamentoId, (x) {
        ConviteRemoto.aplicar(x, remota);
      });
      return const ResultadoServidor(EstadoServidor.ok, criou: true);
    } on ApiErro catch (e) {
      return ResultadoServidor(EstadoServidor.falhou, mensagem: e.mensagem);
    } catch (_) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Sem conexão com o servidor.');
    }
  }

    /// Reunião que já está no servidor: manda só os convidados que ainda não estão lá.
  /// O servidor manda o e-mail aos novos que têm e-mail e devolve o link de cada um.
  Future<ResultadoServidor> _incluirNovosNoServidor(String agendamentoId) async {
    final a = _buscar(agendamentoId);
    final remotoId = a?.remotoId;
    if (a == null || remotoId == null) return const ResultadoServidor(EstadoServidor.ok);
    if (!a.convidados.any((c) => c.remotoId == null)) return const ResultadoServidor(EstadoServidor.ok);

    try {
      // Mesmo formato do corpo de criação, só que apenas com quem ainda não está no servidor.
      final soNovos = a.copiar()..convidados.removeWhere((c) => c.remotoId != null);
      final corpo = ConviteRemoto.corpoCriar(soNovos);
      final remota = await ref
          .read(apiProvider)
          .adicionarParticipantes(remotoId, <String, Object?>{'participantes': corpo['participantes']});
      await _alterar(agendamentoId, (x) {
        ConviteRemoto.aplicar(x, remota);
      });
      final adicionados = remota['adicionados'];
      return ResultadoServidor(EstadoServidor.ok, criou: adicionados is num && adicionados > 0);
    } on ApiErro catch (e) {
      return ResultadoServidor(EstadoServidor.falhou, mensagem: e.mensagem);
    } catch (_) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Sem conexão com o servidor.');
    }
  }

  /// Cancela a reunião no servidor e avisa os convidados por e-mail. Recebe o id do
  /// servidor porque o registro local já pode ter sido excluído. Sem login, não faz nada.
  Future<ResultadoServidor> cancelarNoServidor(String remotoId) async {
    try {
      final api = ref.read(apiProvider);
      if (await api.token() == null) return const ResultadoServidor(EstadoServidor.semLogin);
      await api.cancelarConvite(remotoId);
      return const ResultadoServidor(EstadoServidor.ok);
    } on ApiErro catch (e) {
      return ResultadoServidor(EstadoServidor.falhou, mensagem: e.mensagem);
    } catch (_) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Sem conexão com o servidor.');
    }
  }

  bool _buscandoServidor = false;

  /// Traz do servidor as respostas dadas pelos links e atualiza os convidados.
  /// Sem login ou sem conexão, não faz nada e mantém o que já está salvo.
  Future<void> atualizarRespostasDoServidor() async {
    if (_buscandoServidor) return;
    _buscandoServidor = true;
    try {
      if (!state.any((a) => a.remotoId != null)) return;
      final api = ref.read(apiProvider);
      if (await api.token() == null) return;

      final dados = await api.listarConvites();
      final remotas = <String, Map<String, dynamic>>{};
      for (final r in (dados['reunioes'] as List? ?? const [])) {
        final m = (r as Map).cast<String, dynamic>();
        final id = m['id'];
        if (id is String) remotas[id] = m;
      }

      for (final a in [...state]) {
        final id = a.remotoId;
        final remota = id == null ? null : remotas[id];
        if (remota == null) continue;
        // Aplica primeiro numa cópia só para saber se mudou algo (evita gravar à toa).
        if (ConviteRemoto.aplicar(a.copiar(), remota)) {
          await _alterar(a.id, (x) {
            ConviteRemoto.aplicar(x, remota);
          });
        }
      }
    } catch (_) {
      // Sem internet ou sem login: mantém o que já está salvo.
    } finally {
      _buscandoServidor = false;
    }
  }

  /// Pede ao servidor para reenviar o e-mail do convite a uma pessoa.
  Future<ResultadoServidor> reenviarPeloServidor(String agendamentoId, String convidadoId) async {
    final remotoId = _buscar(agendamentoId)?.remotoId;
    final participanteId = convidadoAtual(agendamentoId, convidadoId)?.remotoId;
    if (remotoId == null || participanteId == null) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Esta pessoa ainda não está no servidor.');
    }
    try {
      final r = await ref.read(apiProvider).reenviarConvite(remotoId, participanteId: participanteId);

      final envio = r['envio'];
      if (envio is Map) {
        if (envio['emailConfigurado'] == false) {
          return const ResultadoServidor(
            EstadoServidor.falhou,
            mensagem: 'O envio de e-mail não está configurado no servidor.',
          );
        }
        final bloqueados = envio['bloqueados'];
        if (bloqueados is num && bloqueados > 0) {
          return const ResultadoServidor(
            EstadoServidor.falhou,
            mensagem: 'Essa pessoa pediu para não receber convites por e-mail.',
          );
        }
      }

      final ignorados = r['ignoradosPorIntervalo'];
      if (ignorados is num && ignorados > 0) {
        return const ResultadoServidor(
          EstadoServidor.ok,
          mensagem: 'O e-mail já foi enviado há poucos minutos. Tente de novo daqui a pouco.',
        );
      }
      return const ResultadoServidor(EstadoServidor.ok);
    } on ApiErro catch (e) {
      return ResultadoServidor(EstadoServidor.falhou, mensagem: e.mensagem);
    } catch (_) {
      return const ResultadoServidor(EstadoServidor.falhou, mensagem: 'Sem conexão com o servidor.');
    }
  }

  /// Se o formulário de edição montou o registro do zero, os dados do servidor
  /// (ids e links) iriam embora. Copia do registro antigo o que faltar.
  void _herdarDadosDoServidor(Agendamento antes, Agendamento a) {
    a.remotoId ??= antes.remotoId;
    for (final c in a.convidados) {
      for (final o in antes.convidados) {
        if (o.id != c.id) continue;
        c.remotoId ??= o.remotoId;
        c.link ??= o.link;
      }
    }
  }

  bool _mudouNoServidor(Agendamento antes, Agendamento a) =>
      antes.titulo.trim() != a.titulo.trim() ||
      antes.inicio != a.inicio ||
      (antes.linkOuLocal ?? '').trim() != (a.linkOuLocal ?? '').trim();

  Future<void> _editarNoServidor(String agendamentoId, {required bool horarioMudou}) async {
    final a = _buscar(agendamentoId);
    final remotoId = a?.remotoId;
    if (a == null || remotoId == null) return;
    try {
      final api = ref.read(apiProvider);
      if (await api.token() == null) return;
      final remota = await api.editarConvite(remotoId, ConviteRemoto.corpoEditar(a));
      await _alterar(agendamentoId, (x) {
        if (horarioMudou) {
          // O servidor zera as respostas quando o horário muda; o app acompanha.
          for (final c in x.convidados) {
            if (c.remotoId == null) continue;
            c.resposta = RespostaConvite.pendente;
            c.respondidoEm = null;
            c.automatica = false;
          }
        }
        ConviteRemoto.aplicar(x, remota);
      });
    } catch (_) {
      // Sem internet ou servidor fora: a edição local já está salva.
    }
  }
}

/// Pessoas já convidadas antes (mais recentes primeiro, sem repetir o contato).
/// Alimentam os atalhos "convidar de novo" do formulário.
List<Convidado> contatosRecentes(List<Agendamento> registros, {int limite = 8}) {
  final ordenados = [...registros]..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
  final vistos = <String>{};
  final saida = <Convidado>[];
  for (final a in ordenados) {
    for (final c in a.convidados) {
      final chave = c.contato.trim().toLowerCase();
      if (chave.isEmpty || !vistos.add(chave)) continue;
      saida.add(Convidado(nome: c.nome, contato: c.contato));
      if (saida.length >= limite) return saida;
    }
  }
  return saida;
}
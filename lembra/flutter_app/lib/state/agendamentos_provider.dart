// Coloque em: lib/state/agendamentos_provider.dart
//
// Histórico de reuniões agendadas pelo Lembra, salvo no aparelho (SharedPreferences).
// Nada aqui apaga sozinho: um registro só sai quando o usuário exclui.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/agendamento.dart';
import '../services/evento_calendario.dart';
import 'providers.dart' show prefsProvider;

final agendamentosProvider =
    NotifierProvider<AgendamentosNotifier, List<Agendamento>>(AgendamentosNotifier.new);

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

  Future<void> atualizar(Agendamento a) => _gravar([for (final x in state) x.id == a.id ? a : x]);

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
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/item_repository.dart';
import '../data/sync_service.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../nlp/interpretador.dart';
import '../services/notification_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';

/// Sobrescrito no main() com a instância real.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final repoProvider = Provider((ref) => ItemRepository());
final apiProvider = Provider((ref) => ApiClient());
final speechProvider = Provider((ref) => SpeechService());
final ttsProvider = Provider((ref) => TtsService());

// ---------- configurações ----------

class Config {
  const Config({
    this.horarioPadrao = 540,
    this.briefing = true,
    this.briefingMin = 480,
    this.revisao = false,
    this.revisaoMin = 1260,
    this.usarIA = true,
  });

  final int horarioPadrao; // minutos desde 00:00 (9h = 540)
  final bool briefing;
  final int briefingMin;
  final bool revisao;
  final int revisaoMin;
  final bool usarIA;

  Config copyWith({
    int? horarioPadrao,
    bool? briefing,
    int? briefingMin,
    bool? revisao,
    int? revisaoMin,
    bool? usarIA,
  }) =>
      Config(
        horarioPadrao: horarioPadrao ?? this.horarioPadrao,
        briefing: briefing ?? this.briefing,
        briefingMin: briefingMin ?? this.briefingMin,
        revisao: revisao ?? this.revisao,
        revisaoMin: revisaoMin ?? this.revisaoMin,
        usarIA: usarIA ?? this.usarIA,
      );
}

class ConfigNotifier extends Notifier<Config> {
  @override
  Config build() {
    final p = ref.read(prefsProvider);
    return Config(
      horarioPadrao: p.getInt('horario_padrao') ?? 540,
      briefing: p.getBool('briefing') ?? true,
      briefingMin: p.getInt('briefing_min') ?? 480,
      revisao: p.getBool('revisao') ?? false,
      revisaoMin: p.getInt('revisao_min') ?? 1260,
      usarIA: p.getBool('usar_ia') ?? true,
    );
  }

  Future<void> salvar(Config c) async {
    state = c;
    final p = ref.read(prefsProvider);
    await p.setInt('horario_padrao', c.horarioPadrao);
    await p.setBool('briefing', c.briefing);
    await p.setInt('briefing_min', c.briefingMin);
    await p.setBool('revisao', c.revisao);
    await p.setInt('revisao_min', c.revisaoMin);
    await p.setBool('usar_ia', c.usarIA);
    await NotificationService.instance.atualizarRotinas(
      briefing: c.briefing,
      briefingMin: c.briefingMin,
      revisao: c.revisao,
      revisaoMin: c.revisaoMin,
    );
  }
}

final configProvider = NotifierProvider<ConfigNotifier, Config>(ConfigNotifier.new);

// ---------- conta ----------

/// E-mail da conta conectada (null = usando só no aparelho).
class SessaoNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).getString('email');

  Future<void> entrar(String email, String senha, {required bool criar}) async {
    final api = ref.read(apiProvider);
    final r = criar ? await api.registrar(email, senha) : await api.entrar(email, senha);
    await api.guardarToken(r['token'] as String);
    final prefs = ref.read(prefsProvider);
    await prefs.setString('email', email);
    await prefs.remove('sync_desde');
    await ref.read(repoProvider).marcarTodosSujos(); // envia tudo o que já existe no aparelho
    state = email;
    await ref.read(itemsProvider.notifier).sincronizar();
  }

  Future<void> sair() async {
    await ref.read(apiProvider).apagarToken();
    await ref.read(prefsProvider).remove('email');
    await ref.read(prefsProvider).remove('sync_desde');
    state = null;
  }
}

final sessaoProvider = NotifierProvider<SessaoNotifier, String?>(SessaoNotifier.new);

// ---------- itens ----------

class ItemsNotifier extends AsyncNotifier<List<Item>> {
  ItemRepository get _repo => ref.read(repoProvider);
  NotificationService get _notif => NotificationService.instance;

  @override
  Future<List<Item>> build() => _repo.listar();

  Future<void> _recarregar() async {
    state = AsyncData(await _repo.listar());
  }

  /// Atualiza a lista na hora (o Dismissible exige que o item saia da árvore no mesmo frame).
  void _otimista(String id, Item? novo) {
    final atual = state.valueOrNull;
    if (atual == null) return;
    final lista = [...atual];
    final i = lista.indexWhere((e) => e.id == id);
    if (i >= 0) {
      if (novo == null) {
        lista.removeAt(i);
      } else {
        lista[i] = novo;
      }
    }
    state = AsyncData(lista);
  }

  Future<Item> criar(Draft d) async {
    final item = d.toItem();
    await _repo.salvar(item);
    await _notif.agendarItem(item);
    await _recarregar();
    unawaited(sincronizar());
    return item;
  }

  Future<void> atualizarDe(String id, Draft d) async {
    final base = await _repo.buscar(id);
    if (base == null) return;
    final item = d.mesclarEm(base);
    await _repo.salvar(item);
    await _notif.agendarItem(item);
    await _recarregar();
    unawaited(sincronizar());
  }

  /// Retorna a versão anterior (para "Desfazer").
  Future<Item?> concluir(String id) async {
    final antes = await _repo.buscar(id);
    if (antes == null) return null;
    final novo = antes.copiar()
      ..concluidoEm = DateTime.now()
      ..atualizadoEm = DateTime.now()
      ..dirty = true;
    final recorrente = antes.regra != null;
    if (!recorrente) novo.status = StatusItem.concluido;
    _otimista(id, novo);
    await _repo.salvar(novo);
    if (!recorrente) await _notif.cancelarItem(id);
    unawaited(sincronizar());
    return antes;
  }

  Future<Item?> cancelar(String id) async {
    final antes = await _repo.buscar(id);
    if (antes == null) return null;
    final novo = antes.copiar()
      ..status = StatusItem.cancelado
      ..atualizadoEm = DateTime.now()
      ..dirty = true;
    _otimista(id, null);
    await _repo.salvar(novo);
    await _notif.cancelarItem(id);
    unawaited(sincronizar());
    return antes;
  }

  /// Volta o item ao estado [antes] (Desfazer).
  Future<void> restaurar(Item antes) async {
    final item = antes.copiar()
      ..atualizadoEm = DateTime.now()
      ..dirty = true;
    await _repo.salvar(item);
    await _notif.agendarItem(item);
    await _recarregar();
    unawaited(sincronizar());
  }

  /// Adia o item. Se ele ainda está no futuro, desloca o horário; se já tocou,
  /// reagenda para agora + [duracao]. Itens recorrentes só ganham um aviso extra.
  Future<Item?> adiar(String id, Duration duracao) async {
    final antes = await _repo.buscar(id);
    if (antes == null) return null;
    final item = antes.copiar()
      ..soneca = antes.soneca + 1
      ..atualizadoEm = DateTime.now()
      ..dirty = true;
    if (item.regra != null) {
      await _repo.salvar(item);
      await _notif.agendarSoneca(item, duracao);
    } else {
      final agora = DateTime.now();
      final a = item.ancora;
      final novo = (a != null && a.isAfter(agora)) ? a.add(duracao) : agora.add(duracao);
      item.definirAncora(DateTime(novo.year, novo.month, novo.day, novo.hour, novo.minute));
      await _repo.salvar(item);
      await _notif.agendarItem(item);
    }
    await _recarregar();
    unawaited(sincronizar());
    return antes;
  }

  Future<Item?> reagendar(String id, DateTime novo) async {
    final antes = await _repo.buscar(id);
    if (antes == null) return null;
    final item = antes.copiar()
      ..soneca = 0
      ..atualizadoEm = DateTime.now()
      ..dirty = true;
    item.definirAncora(novo);
    await _repo.salvar(item);
    await _notif.agendarItem(item);
    await _recarregar();
    unawaited(sincronizar());
    return antes;
  }

  /// Revisão da noite: passa tudo o que ficou para trás para amanhã, no mesmo horário.
  Future<int> reagendarPendentesParaAmanha(List<Item> pendentes) async {
    final agora = DateTime.now();
    for (final p in pendentes) {
      final a = p.ancora ?? agora;
      await reagendar(p.id, DateTime(agora.year, agora.month, agora.day + 1, a.hour, a.minute));
    }
    return pendentes.length;
  }

  /// Reagenda todos os alarmes (após reiniciar o aparelho, mudar o fuso ou sincronizar).
  Future<void> reagendarNotificacoes() async {
    final todos = await _repo.listar(incluirCancelados: true);
    for (final i in todos) {
      await _notif.agendarItem(i);
    }
  }

  Future<bool> sincronizar() async {
    final mudou = await SyncService(_repo, ref.read(apiProvider), ref.read(prefsProvider)).sincronizar();
    if (mudou) {
      await reagendarNotificacoes();
      await _recarregar();
    }
    return mudou;
  }

  Future<void> aoRetomar() async {
    await _recarregar();
    await reagendarNotificacoes();
    unawaited(sincronizar());
  }

  Future<void> apagarTudo() async {
    await _repo.limparTudo();
    await _notif.cancelarTudo();
    await _recarregar();
  }
}

final itemsProvider = AsyncNotifierProvider<ItemsNotifier, List<Item>>(ItemsNotifier.new);

// ---------- entendimento (IA com fallback local) ----------

class ServicoEntendimento {
  ServicoEntendimento(this.ref);
  final Ref ref;

  /// Tenta a IA no servidor (até 3 s); se estiver offline, sem conta ou a resposta
  /// for inválida, usa o interpretador local — o app nunca fica sem resposta.
  Future<List<Draft>> entender(String texto, {Origem origem = Origem.voz}) async {
    final cfg = ref.read(configProvider);
    final agora = DateTime.now();
    final local = InterpretadorLocal(agora: agora).interpretar(texto, origem: origem);
    if (!cfg.usarIA || ref.read(sessaoProvider) == null) return local;
    try {
      final r = await ref
          .read(apiProvider)
          .entender(texto, agora, cfg.horarioPadrao)
          .timeout(const Duration(seconds: 3));
      final lista = (r['itens'] as List)
          .map((e) => Draft.deJsonIA((e as Map).cast<String, dynamic>(), origem: origem))
          .toList();
      return lista.isEmpty ? local : lista;
    } catch (_) {
      return local;
    }
  }
}

final entendimentoProvider = Provider((ref) => ServicoEntendimento(ref));

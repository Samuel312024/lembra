import 'dart:convert';

import 'categoria_conta.dart';
import 'recorrencia.dart';

enum TipoItem { compromisso, tarefa, habito, conta }

enum Urgencia { discreto, normal, critico }

enum StatusItem { ativo, concluido, cancelado }

enum Origem { voz, texto, reuniao }

extension TipoItemRotulo on TipoItem {
  String get rotulo => switch (this) {
        TipoItem.compromisso => 'Compromisso',
        TipoItem.tarefa => 'Tarefa',
        TipoItem.habito => 'Hábito',
        TipoItem.conta => 'Conta',
      };
}

extension UrgenciaRotulo on Urgencia {
  String get rotulo => switch (this) {
        Urgencia.discreto => 'Discreto',
        Urgencia.normal => 'Normal',
        Urgencia.critico => 'Crítico',
      };
}

T _enumPor<T extends Enum>(List<T> valores, Object? nome, T padrao) {
  for (final v in valores) {
    if (v.name == nome) return v;
  }
  return padrao;
}

DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

/// Item da agenda (compromisso, tarefa, hábito ou conta). Mutável de propósito:
/// o estado exibido é sempre recarregado do banco após cada operação.
class Item {
  Item({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.inicio,
    this.prazo,
    this.recorrencia,
    List<int>? antecedencias,
    this.urgencia = Urgencia.normal,
    this.status = StatusItem.ativo,
    this.origem = Origem.voz,
    this.responsavel = 'eu',
    this.soneca = 0,
    this.valor,
    this.categoria,
    this.concluidoEm,
    required this.criadoEm,
    required this.atualizadoEm,
    this.dirty = true,
  }) : antecedencias = antecedencias ?? [];

  String id;
  TipoItem tipo;
  String titulo;
  DateTime? inicio;
  DateTime? prazo;
  String? recorrencia;
  List<int> antecedencias; // minutos antes do horário-âncora
  Urgencia urgencia;
  StatusItem status;
  Origem origem;
  String responsavel;
  int soneca; // quantas vezes o alarme foi adiado
  double? valor; // só para contas: valor em reais
  CategoriaConta? categoria; // só para contas: água, luz, ...
  DateTime? concluidoEm;
  DateTime criadoEm;
  DateTime atualizadoEm;
  bool dirty; // alterado localmente e ainda não sincronizado

  /// Tarefas e contas usam "prazo"; compromissos e hábitos usam "início".
  bool get usaPrazo => tipo == TipoItem.tarefa || tipo == TipoItem.conta;

  DateTime? get ancora => usaPrazo ? (prazo ?? inicio) : (inicio ?? prazo);

  void definirAncora(DateTime? d) {
    if (usaPrazo) {
      prazo = d;
      inicio = null;
    } else {
      inicio = d;
      prazo = null;
    }
  }

  Recorrencia? get regra => Recorrencia.parse(recorrencia);

  Item copiar() => Item(
        id: id,
        tipo: tipo,
        titulo: titulo,
        inicio: inicio,
        prazo: prazo,
        recorrencia: recorrencia,
        antecedencias: List.of(antecedencias),
        urgencia: urgencia,
        status: status,
        origem: origem,
        responsavel: responsavel,
        soneca: soneca,
        valor: valor,
        categoria: categoria,
        concluidoEm: concluidoEm,
        criadoEm: criadoEm,
        atualizadoEm: atualizadoEm,
        dirty: dirty,
      );

  /// Mapa para o SQLite local.
  Map<String, Object?> toMap() => {
        ...toJson(),
        'antecedencias': jsonEncode(antecedencias),
        'dirty': dirty ? 1 : 0,
      };

  /// JSON da API de sincronização (datas em milissegundos UTC).
  Map<String, Object?> toJson() => {
        'id': id,
        'tipo': tipo.name,
        'titulo': titulo,
        'inicio': inicio?.millisecondsSinceEpoch,
        'prazo': prazo?.millisecondsSinceEpoch,
        'recorrencia': recorrencia,
        'antecedencias': antecedencias,
        'urgencia': urgencia.name,
        'status': status.name,
        'origem': origem.name,
        'responsavel': responsavel,
        'soneca': soneca,
        'valor': valor,
        'categoria': categoria?.name,
        'concluido_em': concluidoEm?.millisecondsSinceEpoch,
        'criado_em': criadoEm.millisecondsSinceEpoch,
        'atualizado_em': atualizadoEm.millisecondsSinceEpoch,
      };

  factory Item.fromMap(Map<String, Object?> m) {
    final ant = m['antecedencias'];
    final lista = ant is String ? (jsonDecode(ant) as List) : ((ant as List?) ?? const []);
    return Item(
      id: m['id'] as String,
      tipo: _enumPor(TipoItem.values, m['tipo'], TipoItem.tarefa),
      titulo: m['titulo'] as String,
      inicio: _dt(m['inicio']),
      prazo: _dt(m['prazo']),
      recorrencia: m['recorrencia'] as String?,
      antecedencias: lista.map((e) => (e as num).toInt()).toList(),
      urgencia: _enumPor(Urgencia.values, m['urgencia'], Urgencia.normal),
      status: _enumPor(StatusItem.values, m['status'], StatusItem.ativo),
      origem: _enumPor(Origem.values, m['origem'], Origem.voz),
      responsavel: (m['responsavel'] as String?) ?? 'eu',
      soneca: (m['soneca'] as num?)?.toInt() ?? 0,
      valor: (m['valor'] as num?)?.toDouble(),
      categoria: categoriaContaDoNome(m['categoria']),
      concluidoEm: _dt(m['concluido_em']),
      criadoEm: _dt(m['criado_em'])!,
      atualizadoEm: _dt(m['atualizado_em'])!,
      dirty: (m['dirty'] as num?)?.toInt() == 1,
    );
  }

  String? get somAlarmeId => null;
}
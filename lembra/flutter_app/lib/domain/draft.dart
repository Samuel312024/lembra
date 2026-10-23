import 'package:uuid/uuid.dart';

import 'categoria_conta.dart';
import 'item.dart';
import 'recorrencia.dart';

enum Ambiguidade { nenhuma, hojeOuProxima }

enum TipoPergunta { hojeOuProxima, data, horario }

/// Rascunho do que a IA (ou o interpretador local) entendeu. Só vira [Item]
/// depois que o usuário confirma no cartão.
class Draft {
  Draft({
    required this.tipo,
    required this.titulo,
    this.inicio,
    this.prazo,
    this.recorrencia,
    List<int>? antecedencias,
    this.urgencia = Urgencia.normal,
    this.responsavel = 'eu',
    this.origem = Origem.voz,
    List<String>? camposFaltando,
    this.confianca = 1,
    this.ambiguidade = Ambiguidade.nenhuma,
    this.alternativaData,
    this.horarioPadrao = false,
    this.valor,
    this.categoria,
  })  : antecedencias = antecedencias ?? antecedenciasPadrao(tipo),
        camposFaltando = camposFaltando ?? [];

  TipoItem tipo;
  String titulo;
  DateTime? inicio;
  DateTime? prazo;
  String? recorrencia;
  List<int> antecedencias;
  Urgencia urgencia;
  String responsavel;
  Origem origem;
  List<String> camposFaltando;
  double confianca;
  Ambiguidade ambiguidade;
  DateTime? alternativaData; // outra data possível quando há ambiguidade
  bool horarioPadrao; // o horário foi preenchido com o padrão do usuário
  double? valor; // só para contas: valor em reais
  CategoriaConta? categoria; // só para contas: água, luz, ...

  /// Antecedências padrão por tipo (spec 4.4).
  static List<int> antecedenciasPadrao(TipoItem t) {
    switch (t) {
      case TipoItem.compromisso:
        return [1440, 120, 30];
      case TipoItem.tarefa:
        return [60, 0];
      case TipoItem.conta:
        return [2880, 0];
      case TipoItem.habito:
        return [0];
    }
  }

  factory Draft.vazio() => Draft(tipo: TipoItem.tarefa, titulo: '', origem: Origem.texto);

  factory Draft.deItem(Item i) => Draft(
        tipo: i.tipo,
        titulo: i.titulo,
        inicio: i.inicio,
        prazo: i.prazo,
        recorrencia: i.recorrencia,
        antecedencias: List.of(i.antecedencias),
        urgencia: i.urgencia,
        responsavel: i.responsavel,
        origem: i.origem,
        valor: i.valor,
        categoria: i.categoria,
      );

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

  /// Próxima pergunta curta a fazer ao usuário (ou null se está tudo claro).
  TipoPergunta? get proximaPergunta {
    if (ambiguidade == Ambiguidade.hojeOuProxima && alternativaData != null) {
      return TipoPergunta.hojeOuProxima;
    }
    if (camposFaltando.contains('data')) return TipoPergunta.data;
    if (camposFaltando.contains('horario')) return TipoPergunta.horario;
    return null;
  }

  Item toItem({String? id, DateTime? agora}) {
    final t = agora ?? DateTime.now();
    return Item(
      id: id ?? const Uuid().v4(),
      tipo: tipo,
      titulo: titulo.trim(),
      inicio: inicio,
      prazo: prazo,
      recorrencia: recorrencia,
      antecedencias: List.of(antecedencias),
      urgencia: urgencia,
      origem: origem,
      responsavel: responsavel,
      valor: tipo == TipoItem.conta ? valor : null,
      categoria: tipo == TipoItem.conta ? categoria : null,
      criadoEm: t,
      atualizadoEm: t,
    );
  }

  /// Aplica as edições do rascunho sobre um item existente.
  Item mesclarEm(Item base) {
    final i = base.copiar();
    i.tipo = tipo;
    i.titulo = titulo.trim();
    i.inicio = inicio;
    i.prazo = prazo;
    i.recorrencia = recorrencia;
    i.antecedencias = List.of(antecedencias);
    i.urgencia = urgencia;
    i.responsavel = responsavel;
    // Valor e tipo só existem em contas; ao mudar para outro tipo, somem.
    i.valor = tipo == TipoItem.conta ? valor : null;
    i.categoria = tipo == TipoItem.conta ? categoria : null;
    i.soneca = 0;
    i.atualizadoEm = DateTime.now();
    i.dirty = true;
    return i;
  }

  /// Converte um objeto do JSON estruturado da IA (spec seção 5). Lança
  /// [FormatException] se o formato for inválido — o chamador cai no fallback local.
  factory Draft.deJsonIA(Map<String, dynamic> j, {required Origem origem}) {
    T enumDe<T extends Enum>(List<T> valores, Object? nome) {
      for (final v in valores) {
        if (v.name == nome) return v;
      }
      throw FormatException('valor inválido: $nome');
    }

    DateTime? data(Object? v) {
      if (v == null) return null;
      final d = DateTime.tryParse(v as String);
      if (d == null) throw FormatException('data inválida: $v');
      return d.toLocal();
    }

    final titulo = (j['titulo'] as String?)?.trim();
    if (titulo == null || titulo.isEmpty) throw const FormatException('título ausente');

    final tipo = enumDe(TipoItem.values, j['tipo']);
    String? rec;
    final recBruta = j['recorrencia'];
    if (recBruta != null) {
      final r = Recorrencia.parse(recBruta as String);
      if (r == null) throw FormatException('recorrência não suportada: $recBruta');
      rec = r.toRRule();
    }
    final ant = ((j['antecedencias_minutos'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();

    final d = Draft(
      tipo: tipo,
      titulo: titulo,
      recorrencia: rec,
      antecedencias: ant.isEmpty ? antecedenciasPadrao(tipo) : ant,
      urgencia: enumDe(Urgencia.values, j['urgencia']),
      responsavel: (j['responsavel'] as String?) ?? 'eu',
      origem: origem,
      camposFaltando: ((j['campos_faltando'] as List?) ?? const []).map((e) => '$e').toList(),
      confianca: (j['confianca'] as num?)?.toDouble() ?? 0.5,
      valor: (j['valor'] is num && (j['valor'] as num) > 0) ? (j['valor'] as num).toDouble() : null,
      categoria: categoriaContaDoNome(j['categoria']),
    );
    d.inicio = data(j['inicio']);
    d.prazo = data(j['prazo']);
    return d;
  }
}
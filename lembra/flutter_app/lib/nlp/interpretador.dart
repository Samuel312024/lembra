import '../domain/draft.dart';
import '../domain/item.dart';
import 'pt_date_parser.dart';
import 'texto.dart';

/// Transforma uma frase em rascunhos (um por item) sem depender de internet.
/// É o fallback offline do entendimento por IA e também serve de base para os testes.
class InterpretadorLocal {
  InterpretadorLocal({required this.agora});

  final DateTime agora;

  static final _reConta = RegExp(
      r'\b(pagar|pague|paguei|boleto|fatura|condominio|aluguel|vencimento|parcela|mensalidade|iptu|ipva|imposto|financiamento)\b');
  static final _reEvento = RegExp(
      r'\b(medico|consulta|reuniao|dentista|aniversario|exame|jantar|almoco|voo|viagem|show|entrevista|prova|aula|fisioterapia|encontro|casamento|festa|cinema|evento|formatura|apresentacao|audiencia|cirurgia|vacina|check-?in)\b');
  static final _reVerbo = RegExp(r'^[a-z]{3,}(?:ar|er|ir|or)\b');
  static final _reCritico =
      RegExp(r'\b(urgente|urgentissimo|nao pode esquecer|nao esqueca|importante|critico|alarme)\b');
  static final _reDiscreto =
      RegExp(r'\b(discreto|discretamente|silencioso|silenciosa|sem barulho|sem som)\b');
  static final _reRemedio = RegExp(r'\b(remedio|remedios|medicamento|comprimido|insulina)\b');

  static final _prefixos = <RegExp>[
    RegExp(
        r'^(?:por\s+favor[,\s]+)?(?:me\s+)?(?:lembra|lembre|lembrar|avisa|avise|avisar|anota|anote|anotar|agenda|agende|agendar|cria|crie|criar|coloca|coloque)\b(?:\s+(?:de|que|pra|para|o|a|um|uma|lembrete|alarme))*\s*'),
    RegExp(
        r'^(?:eu\s+)?(?:tenho\s+que|tenho\s+de|tenho|tem|preciso\s+de|preciso|vou|devo|quero)\s+'),
    RegExp(r'^(?:do|da|dos|das|de|o|a|os|as)\s+'),
  ];
  static final _reFinal =
      RegExp(r'\s+(?:as|a|no|na|em|de|do|da|para|pra|e|dia|todo|toda|que|me|ate|por|pelo|pela)$');

  /// Interpreta a frase. Frases como "amanhã pagar a luz e ligar pro banco"
  /// viram dois itens que compartilham a data.
  List<Draft> interpretar(String texto, {Origem origem = Origem.voz}) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return [];
    final partes = _dividir(limpo);
    final parser = PtDateParser(agora);
    final quandos = partes.map(parser.parse).toList();

    Quando? contexto;
    for (final q in quandos) {
      if (q.temData && contexto == null) contexto = q;
    }

    final saida = <Draft>[];
    for (var i = 0; i < partes.length; i++) {
      var q = quandos[i];
      if (partes.length > 1 && !q.temData && q.recorrencia == null && contexto != null) {
        q = q.herdandoDe(contexto);
      }
      saida.add(_montar(partes[i], q, origem));
    }
    return saida;
  }

  Draft _montar(String texto, Quando q, Origem origem) {
    var titulo = _titulo(texto, q.trechos);
    if (titulo.isEmpty) titulo = texto.trim();
    final tipo = _classificar(normalizar(titulo), q);
    final todo = normalizar(texto);

    final urgencia = _reCritico.hasMatch(todo)
        ? Urgencia.critico
        : _reDiscreto.hasMatch(todo)
            ? Urgencia.discreto
            : _reRemedio.hasMatch(todo)
                ? Urgencia.critico
                : Urgencia.normal;

    final faltando = <String>[];
    if (tipo == TipoItem.compromisso && !q.temData) faltando.add('data');
    if ((q.temData || q.recorrencia != null) && !q.temHorario) faltando.add('horario');

    var conf = 0.9;
    if (faltando.contains('horario')) conf -= 0.25;
    if (faltando.contains('data')) conf -= 0.35;
    if (titulo.length < 3) conf -= 0.3;
    if (q.ambiguoHojeOuProxima) conf -= 0.2;

    final d = Draft(
      tipo: tipo,
      titulo: capitalizar(titulo),
      recorrencia: q.recorrencia,
      antecedencias: q.antecedencias ?? Draft.antecedenciasPadrao(tipo),
      urgencia: urgencia,
      origem: origem,
      camposFaltando: faltando,
      confianca: conf.clamp(0.0, 1.0).toDouble(),
      ambiguidade: q.ambiguoHojeOuProxima ? Ambiguidade.hojeOuProxima : Ambiguidade.nenhuma,
      alternativaData: q.alternativa,
    );
    d.definirAncora(q.dataHora);
    return d;
  }

  TipoItem _classificar(String tituloNorm, Quando q) {
    if (_reConta.hasMatch(tituloNorm)) return TipoItem.conta;
    if (!_reVerbo.hasMatch(tituloNorm) && _reEvento.hasMatch(tituloNorm)) {
      return TipoItem.compromisso;
    }
    if (q.recorrencia != null) return TipoItem.habito;
    return TipoItem.tarefa;
  }

  /// Remove data/hora e expressões de comando ("me lembra de", "tenho") do texto.
  String _titulo(String original, List<(int, int)> trechos) {
    var s = removerTrechos(original, trechos);
    for (final re in _prefixos) {
      final m = re.firstMatch(normalizar(s));
      if (m != null && m.end > 0) s = s.substring(m.end).trimLeft();
    }
    var anterior = '';
    while (anterior != s) {
      anterior = s;
      s = s.replaceAll(RegExp(r'^[\s,.;:\-]+|[\s,.;:\-]+$'), '');
      final mt = _reFinal.firstMatch(normalizar(s));
      if (mt != null) s = s.substring(0, mt.start);
    }
    return s;
  }

  /// Separa itens ditos juntos quando o segundo começa com um verbo no infinitivo.
  List<String> _dividir(String texto) {
    final n = normalizar(texto);
    final re = RegExp(
        r'\s+e\s+(?=[a-z]{3,}(?:ar|er|ir|or)\b)|,\s*(?=[a-z]{3,}(?:ar|er|ir|or)\b)');
    final partes = <String>[];
    var ini = 0;
    for (final m in re.allMatches(n)) {
      partes.add(texto.substring(ini, m.start));
      ini = m.end;
    }
    partes.add(texto.substring(ini));
    return partes.where((p) => p.trim().isNotEmpty).toList();
  }
}

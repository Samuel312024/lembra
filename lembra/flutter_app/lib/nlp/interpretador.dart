import '../domain/categoria_conta.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import 'pt_date_parser.dart';
import 'texto.dart';
import 'valor.dart';

/// Transforma uma frase em rascunhos (um por item) sem depender de internet.
/// É o fallback offline do entendimento por IA e também serve de base para os testes.
class InterpretadorLocal {
  InterpretadorLocal({required this.agora});

  final DateTime agora;

  static final _reConta = RegExp(
      r'\b(pagar|pague|paguei|boleto|fatura|condominio|aluguel|vencimento|parcela|mensalidade|iptu|ipva|imposto|financiamento)\b');
  /// "conta de luz", "vence dia 10": também indicam uma conta a pagar.
  static final _reContaExtra = RegExp(r'\b(conta\s+d[aeo]s?|vence|vencem|vencendo|vencer)\b');
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
      RegExp(r'\s+(?:as|a|no|na|em|de|do|da|para|pra|e|dia|todo|toda|que|me|ate|por|pelo|pela|vence|vencem|vencendo|valor|custa)$');

  /// Interpreta a frase. Frases como "amanhã pagar a luz e ligar pro banco"
  /// viram dois itens que compartilham a data.
  List<Draft> interpretar(String texto, {Origem origem = Origem.voz}) {
    final limpo = texto.trim();
    if (limpo.isEmpty) return [];
    final brutas = _dividir(limpo);
    // O valor de uma conta ("luz 150 reais") sai do texto antes de ler a data,
    // para o número não ser confundido com dia ou hora.
    final valores = brutas.map(_valorDeConta).toList();
    final partes = [
      for (var i = 0; i < brutas.length; i++)
        valores[i] == null ? brutas[i] : _apagar(brutas[i], valores[i]!),
    ];
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
      saida.add(_montar(partes[i], q, origem, valor: valores[i]?.valor));
    }
    return saida;
  }

  Draft _montar(String texto, Quando q, Origem origem, {double? valor}) {
    var titulo = _titulo(texto, q.trechos);
    if (titulo.isEmpty) titulo = texto.trim();
    final todo = normalizar(texto);
    final tipo = _classificar(normalizar(titulo), q, todo);

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
      valor: tipo == TipoItem.conta ? valor : null,
      categoria: tipo == TipoItem.conta ? detectarCategoriaConta(todo) : null,
    );
    d.definirAncora(q.dataHora);
    return d;
  }

  TipoItem _classificar(String tituloNorm, Quando q, String todoNorm) {
    if (_reConta.hasMatch(tituloNorm) || _reContaExtra.hasMatch(todoNorm)) return TipoItem.conta;
    if (!_reVerbo.hasMatch(tituloNorm) && _reEvento.hasMatch(tituloNorm)) {
      return TipoItem.compromisso;
    }
    if (q.recorrencia != null) return TipoItem.habito;
    return TipoItem.tarefa;
  }

  /// Valor em reais de uma conta falada ("conta de luz 150 reais"). Só vale para
  /// frases que falam de conta: "comprar pão 5 reais" não vira conta.
  ValorEncontrado? _valorDeConta(String parte) {
    final n = normalizar(parte);
    if (!_reConta.hasMatch(n) && !_reContaExtra.hasMatch(n)) return null;
    return extrairValor(n);
  }

  /// Troca o valor por espaços, mantendo o tamanho (os índices continuam valendo).
  String _apagar(String parte, ValorEncontrado v) =>
      parte.replaceRange(v.inicio, v.fim, ' ' * (v.fim - v.inicio));

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

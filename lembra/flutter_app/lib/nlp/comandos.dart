import '../domain/item.dart';
import 'pt_date_parser.dart';
import 'texto.dart';

/// Comandos de voz que atuam sobre itens já existentes.
sealed class ComandoVoz {
  const ComandoVoz();
}

class CancelarComando extends ComandoVoz {
  const CancelarComando(this.alvo);
  final String alvo; // texto normalizado; vazio = "o último"
}

class ConcluirComando extends ComandoVoz {
  const ConcluirComando(this.alvo);
  final String alvo;
}

class AdiarComando extends ComandoVoz {
  const AdiarComando(this.alvo, {this.duracao, this.novoQuando, this.novoSemHora = false});
  final String alvo; // vazio = o item mais próximo
  final Duration? duracao; // "adia 10 minutos"
  final DateTime? novoQuando; // "adia para amanhã às 10"
  final bool novoSemHora; // só a data foi dita: mantém o horário do item
}

class ListarComando extends ComandoVoz {
  const ListarComando(this.dia);
  final DateTime dia;
}

/// Reconhece comandos como "cancela o lembrete do médico" ou "já paguei o condomínio".
/// Se a frase não for um comando, retorna null (e ela é tratada como um novo lembrete).
class ParserComandos {
  ParserComandos(this.agora);
  final DateTime agora;

  static final _reCancelar = RegExp(
      r'^(?:por favor )?(?:cancela|cancele|cancelar|apaga|apague|apagar|exclui|exclua|excluir|remove|remova|remover|deleta|delete|deletar|tira|tire|tirar|esquece|esqueca|esquecer)\b\s*(.*)$');
  static final _reConcluir = RegExp(
      r'^(?:marca(?:r)?\s+(?:como\s+)?(?:feit[oa]|concluid[oa]|pront[oa])\s*(.*)|marca(?:r)?\s+(.*?)\s+como\s+(?:feit[oa]|concluid[oa]|pront[oa])|(?:ja\s+)?(?:fiz|paguei|liguei|comprei|terminei|tomei|resolvi|enviei|mandei)\b\s*(.*)|(?:conclui|conclua|concluir|finaliza|finalize|finalizar)\s*(.*))$');
  static final _reAdiar = RegExp(
      r'^(?:adia|adie|adiar|empurra|empurre|remarca|remarque|remarcar|reagenda|reagende|reagendar|soneca|snooze)\b\s*(.*)$');
  static final _reListar = RegExp(
      r'^(?:o que (?:eu )?(?:tenho|tem)|qual (?:e )?(?:a )?minha agenda|minha agenda|meus lembretes|resumo do dia|resume meu dia|le meu dia|leia meu dia|briefing|meu dia)\b(.*)$');
  static final _reDuracao = RegExp(
      r'(?:por|mais|em)?\s*\b(\d+|um|uma|meia|dois|duas)\s*(minutos?|min|horas?|h|dias?)\b');
  static final _reInicioAlvo = RegExp(
      r'^\s*(?:o|a|os|as|um|uma|lembrete|alarme|tarefa|compromisso|evento|de|do|da|dos|das|sobre|pra|pro|para|por|mais|em)\b\s*');
  static final _reFimAlvo = RegExp(r'\s+(?:para|pra|por|mais|em|de|do|da|as|a)$');

  ComandoVoz? interpretar(String texto) {
    final n = normalizar(texto)
        .replaceAll(RegExp(r'[^a-z0-9/:\-\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (n.isEmpty) return null;

    var m = _reListar.firstMatch(n);
    if (m != null) {
      final q = PtDateParser(agora).parse(m.group(1) ?? '');
      final dia = q.temData ? q.dataHora! : agora;
      return ListarComando(DateTime(dia.year, dia.month, dia.day));
    }

    m = _reCancelar.firstMatch(n);
    if (m != null) return CancelarComando(_limparAlvo(m.group(1) ?? ''));

    m = _reAdiar.firstMatch(n);
    if (m != null) return _adiar(m.group(1) ?? '');

    m = _reConcluir.firstMatch(n);
    if (m != null) {
      final alvo = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      return ConcluirComando(_limparAlvo(alvo));
    }
    return null;
  }

  ComandoVoz _adiar(String resto) {
    final d = _reDuracao.firstMatch(resto);
    if (d != null) {
      final minutos = _minutos(d.group(1)!, d.group(2)!);
      final alvo = resto.replaceRange(d.start, d.end, ' ');
      return AdiarComando(_limparAlvo(alvo), duracao: Duration(minutes: minutos));
    }
    final q = PtDateParser(agora).parse(resto);
    if (q.dataHora != null) {
      return AdiarComando(
        _limparAlvo(removerTrechos(resto, q.trechos)),
        novoQuando: q.dataHora,
        novoSemHora: !q.temHorario,
      );
    }
    return AdiarComando(_limparAlvo(resto), duracao: const Duration(minutes: 10));
  }

  int _minutos(String n, String un) {
    const nums = {'um': 1, 'uma': 1, 'dois': 2, 'duas': 2};
    final q = n == 'meia' ? 0.5 : (num.tryParse(n) ?? nums[n] ?? 1);
    final f = un.startsWith('min') ? 1 : (un.startsWith('h') ? 60 : 1440);
    return (q * f).round();
  }

  String _limparAlvo(String s) {
    var r = s.trim();
    var anterior = '';
    while (anterior != r) {
      anterior = r;
      r = r.replaceFirst(_reInicioAlvo, '').trim();
      r = r.replaceFirst(_reFimAlvo, '').trim();
    }
    return r;
  }
}

// ---------- busca do item-alvo ----------

const _stop = {
  'o', 'a', 'os', 'as', 'de', 'do', 'da', 'dos', 'das', 'pra', 'pro', 'para', 'um', 'uma',
  'lembrete', 'alarme', 'tarefa', 'compromisso', 'evento', 'que', 'sobre', 'meu', 'minha',
  'e', 'em', 'no', 'na', 'ao', 'por', 'favor',
};

List<String> _tokens(String s) => normalizar(s)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.length > 1 && !_stop.contains(t))
    .toList();

bool _casa(String a, String b) {
  if (a == b) return true;
  if (a.length < 4 || b.length < 4) return false;
  return a.startsWith(b) || b.startsWith(a);
}

/// Itens cujo título combina com [alvo]. Retorna todos os empatados no topo
/// (mais de um = ambíguo, o app pergunta qual). Lista vazia = nada encontrado.
List<Item> buscarItens(String alvo, List<Item> itens) {
  final alvoTokens = _tokens(alvo);
  if (alvoTokens.isEmpty) return [];
  final pontuados = <(Item, double)>[];
  for (final i in itens) {
    final itTokens = _tokens(i.titulo);
    var acertos = 0;
    for (final t in alvoTokens) {
      if (itTokens.any((x) => _casa(t, x))) acertos++;
    }
    final score = acertos / alvoTokens.length;
    if (score >= 0.5) pontuados.add((i, score));
  }
  if (pontuados.isEmpty) return [];
  pontuados.sort((a, b) => b.$2.compareTo(a.$2));
  final topo = pontuados.first.$2;
  return pontuados.where((p) => p.$2 >= topo - 0.01).map((p) => p.$1).toList();
}

// ---------- resposta por voz ao cartão de confirmação ----------

enum RespostaVoz { confirmar, descartar, editar, desconhecida }

RespostaVoz interpretarResposta(String texto) {
  final n = normalizar(texto).replaceAll(RegExp(r'[^a-z\s]'), ' ');
  bool tem(String p) => RegExp('\\b(?:$p)\\b').hasMatch(n);
  if (tem('nao|cancela|cancelar|descarta|descartar|deixa pra la|esquece|para|desisto')) {
    return RespostaVoz.descartar;
  }
  if (tem('edita|editar|muda|mudar|altera|alterar|corrige|corrigir')) return RespostaVoz.editar;
  if (tem('sim|confirma|confirmar|confirmo|pode|isso|ok|salva|salvar|certo|beleza|correto|manda ver')) {
    return RespostaVoz.confirmar;
  }
  return RespostaVoz.desconhecida;
}

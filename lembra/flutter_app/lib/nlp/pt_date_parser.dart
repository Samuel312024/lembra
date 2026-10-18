import '../domain/recorrencia.dart';
import 'texto.dart';

enum OrigemHorario { nenhum, explicito, periodo }

/// Resultado da leitura de data/hora/recorrência de uma frase.
class Quando {
  const Quando({
    this.dataHora,
    this.temData = false,
    this.origemHorario = OrigemHorario.nenhum,
    this.recorrencia,
    this.antecedencias,
    this.ambiguoHojeOuProxima = false,
    this.alternativa,
    this.trechos = const [],
  });

  /// Data e hora resolvidas. Quando não há horário, vale 00:00 do dia.
  final DateTime? dataHora;
  final bool temData;
  final OrigemHorario origemHorario;
  final String? recorrencia; // RRULE
  final List<int>? antecedencias; // "me avisa um dia antes"
  final bool ambiguoHojeOuProxima; // "sexta" dito numa sexta
  final DateTime? alternativa; // a outra data possível na ambiguidade
  final List<(int, int)> trechos; // trechos do texto consumidos

  bool get temHorario => origemHorario != OrigemHorario.nenhum;

  /// Copia data/hora de outra cláusula ("amanhã pagar a luz e ligar pro banco").
  Quando herdandoDe(Quando outro) => Quando(
        dataHora: outro.dataHora,
        temData: true,
        origemHorario: outro.origemHorario,
        recorrencia: recorrencia,
        antecedencias: antecedencias ?? outro.antecedencias,
        ambiguoHojeOuProxima: outro.ambiguoHojeOuProxima,
        alternativa: outro.alternativa,
        trechos: trechos,
      );
}

/// Interpretador de datas em português brasileiro coloquial.
class PtDateParser {
  PtDateParser(this.agora) : _hoje = DateTime(agora.year, agora.month, agora.day);

  final DateTime agora;
  final DateTime _hoje;

  static const _numeros = {
    'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5,
    'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9, 'dez': 10,
  };
  static const _diasSemana = {
    'segunda': 1, 'terca': 2, 'quarta': 3, 'quinta': 4, 'sexta': 5, 'sabado': 6, 'domingo': 7,
  };
  static const _meses = {
    'janeiro': 1, 'fevereiro': 2, 'marco': 3, 'abril': 4, 'maio': 5, 'junho': 6,
    'julho': 7, 'agosto': 8, 'setembro': 9, 'outubro': 10, 'novembro': 11, 'dezembro': 12,
  };

  static const _un = r'(minutos?|min|horas?|h|dias?|semanas?|meses|mes)';
  static const _wd = r'(?:segunda|terca|quarta|quinta|sexta|sabado|domingo)s?(?:-?\s*feiras?)?';

  // --- antecedência e duração relativa
  static final _reAntes = RegExp(
      r'(?:me\s+)?(?:avisa|avise|avisar|lembra|lembre)?\s*\b(\d+|um|uma|meia|dois|duas)\s+(minutos?|min|horas?|dias?|semanas?)\s+antes\b');
  static final _reRelativo = RegExp(
      r'\b(?:daqui\s+a|daqui|em|dentro\s+de)\s+(\d+|um|uma|meia|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez)\s*' +
          _un +
          r'\b');

  // --- horário
  static final _reMeioDia = RegExp(r'\bmeio[\s-]?dia\b');
  static final _reHoraDoisPontos = RegExp(r'(?:\bas\s+)?\b(\d{1,2}):(\d{2})\b');
  static final _reHoraH =
      RegExp(r'(?:\bas\s+)?\b(\d{1,2})\s*(?:h|hs|hr|hrs|hora|horas)(?:\s*(\d{2}))?(?!\w)');
  static final _reAsN = RegExp(r'\bas\s+(\d{1,2})(?:\s+e\s+(meia|\d{2}))?(?!\d|:)\b');
  static final _rePeriodo =
      RegExp(r'(?<!mais\s)\b(?:(?:de|da|pela|na|a|as|ao|no)\s+)?(manha|tarde|noite|madrugada)\b');

  // --- recorrência
  static final _reTodoDiaN = RegExp(r'\btodo\s+dia\s+(\d{1,2})\b');
  static final _reUteis = RegExp(
      r'\b(?:todo\s+dia\s+util|todos\s+os\s+dias\s+uteis|dias?\s+uteis|de\s+segunda\s+a\s+sexta(?:-?\s*feira)?)\b');
  static final _reTodoSemana =
      RegExp(r'\b(?:toda|todas\s+as|todo|todos\s+os)\s+(' + _wd + r'(?:\s*(?:,|e)\s*' + _wd + r')*)');
  static final _reDiario = RegExp(r'\b(?:todo\s+(?:santo\s+)?dia|todos\s+os\s+dias|diariamente)\b');
  static final _reSemanal = RegExp(r'\b(?:toda\s+semana|semanalmente)\b');
  static final _reMensal = RegExp(r'\b(?:todo\s+mes|mensalmente)\b');

  // --- datas
  static final _reDepoisAmanha = RegExp(r'\bdepois\s+de\s+amanha\b');
  static final _reAmanha = RegExp(r'\bamanha\b');
  static final _reHoje = RegExp(r'\bhoje\b');
  static final _reSemanaVem = RegExp(r'\b(?:semana\s+que\s+vem|proxima\s+semana|semana\s+proxima)\b');
  static final _reMesVem = RegExp(r'\b(?:mes\s+que\s+vem|proximo\s+mes)\b');
  static final _reDataBarra = RegExp(r'(?:\bdia\s+)?\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');
  static final _reDataExtenso = RegExp(
      r'(?:\bdia\s+)?\b(\d{1,2})\s+de\s+(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)(?:\s+de\s+(\d{4}))?\b');
  static final _reDiaN = RegExp(r'\bdia\s+(\d{1,2})\b');
  static final _reDiaSemana = RegExp(
      r'\b(?:(proxim[ao])\s+)?(segunda|terca|quarta|quinta|sexta|sabado|domingo)(?:-?\s*feira)?(?:\s+(que\s+vem|proxim[ao]))?\b');

  Quando parse(String texto) {
    var w = normalizar(texto);
    final trechos = <(int, int)>[];

    RegExpMatch? achar(RegExp re) {
      final m = re.firstMatch(w);
      if (m == null) return null;
      trechos.add((m.start, m.end));
      w = w.replaceRange(m.start, m.end, ' ' * (m.end - m.start));
      return m;
    }

    // Tenta as opções em ordem; consome só a primeira que casar.
    bool primeiro(List<(RegExp, void Function(RegExpMatch))> opcoes) {
      for (final (re, fn) in opcoes) {
        final m = achar(re);
        if (m != null) {
          fn(m);
          return true;
        }
      }
      return false;
    }

    // 1) antecedência explícita: "me avisa um dia antes"
    List<int>? antecedencias;
    final mAnt = achar(_reAntes);
    if (mAnt != null) antecedencias = [_minutos(mAnt.group(1)!, mAnt.group(2)!), 0];

    // 2) duração relativa: "daqui a 2 horas", "em 3 dias"
    DateTime? relativoExato;
    DateTime? relativoData;
    final mRel = achar(_reRelativo);
    if (mRel != null) {
      final n = mRel.group(1)!;
      final un = mRel.group(2)!;
      final q = _numero(n);
      if (un.startsWith('min') || un.startsWith('h')) {
        final t = agora.add(Duration(minutes: _minutos(n, un)));
        relativoExato = DateTime(t.year, t.month, t.day, t.hour, t.minute);
      } else if (un.startsWith('mes')) {
        relativoData = _somaMeses(_hoje, q.round());
      } else {
        relativoData = _somaDias(_hoje, un.startsWith('semana') ? q.round() * 7 : q.round());
      }
    }

    // 3) horário
    int? hora;
    int? minuto;
    var viaAsN = false;
    if (relativoExato != null) {
      hora = relativoExato.hour;
      minuto = relativoExato.minute;
    } else {
      primeiro([
        (_reMeioDia, (x) {
          hora = 12;
          minuto = 0;
        }),
        (_reHoraDoisPontos, (x) {
          hora = int.parse(x.group(1)!);
          minuto = int.parse(x.group(2)!);
        }),
        (_reHoraH, (x) {
          hora = int.parse(x.group(1)!);
          minuto = int.tryParse(x.group(2) ?? '') ?? 0;
        }),
        (_reAsN, (x) {
          hora = int.parse(x.group(1)!);
          final e = x.group(2);
          minuto = e == null ? 0 : (e == 'meia' ? 30 : int.parse(e));
          viaAsN = true;
        }),
      ]);
    }
    int? hF = hora;
    int? mF = minuto;
    var origem = OrigemHorario.nenhum;
    if (hF != null) {
      if (hF > 23 || (mF ?? 0) > 59) {
        hF = null;
        mF = null;
      } else {
        origem = OrigemHorario.explicito;
      }
    }

    // 4) recorrência
    String? recFreq;
    var recDias = <int>{};
    int? recDiaMes;
    var recSemanalSemDia = false;
    var recMensalSemDia = false;
    primeiro([
      (_reTodoDiaN, (x) {
        recFreq = 'MONTHLY';
        recDiaMes = int.parse(x.group(1)!);
      }),
      (_reUteis, (x) {
        recFreq = 'WEEKLY';
        recDias = {1, 2, 3, 4, 5};
      }),
      (_reTodoSemana, (x) {
        recFreq = 'WEEKLY';
        recDias = RegExp(r'segunda|terca|quarta|quinta|sexta|sabado|domingo')
            .allMatches(x.group(1)!)
            .map((e) => _diasSemana[e.group(0)!]!)
            .toSet();
      }),
      (_reDiario, (x) {
        recFreq = 'DAILY';
      }),
      (_reSemanal, (x) {
        recFreq = 'WEEKLY';
        recSemanalSemDia = true;
      }),
      (_reMensal, (x) {
        recFreq = 'MONTHLY';
        recMensalSemDia = true;
      }),
    ]);

    // 5) período do dia
    String? periodo;
    final mPer = achar(_rePeriodo);
    if (mPer != null) periodo = mPer.group(1);

    if (hF != null) {
      if (periodo == 'tarde' || periodo == 'noite') {
        if (hF < 12) hF = hF + 12; // "8 da noite" = 20h
      } else if (periodo == null && viaAsN && hF >= 1 && hF <= 6) {
        hF = hF + 12; // "às 3" sem período: assume tarde
      }
    } else if (periodo != null) {
      hF = const {'manha': 9, 'tarde': 15, 'noite': 20, 'madrugada': 5}[periodo];
      mF = 0;
      origem = OrigemHorario.periodo;
    }
    final int? hh = hF;
    final int? mm = mF;

    // 6) data
    DateTime? data = relativoExato != null
        ? DateTime(relativoExato.year, relativoExato.month, relativoExato.day)
        : relativoData;
    var ambiguo = false;
    DateTime? alternativa;
    var semanaQueVem = false;

    if (data == null) {
      primeiro([
        (_reDepoisAmanha, (x) {
          data = _somaDias(_hoje, 2);
        }),
        (_reAmanha, (x) {
          data = _somaDias(_hoje, 1);
        }),
        (_reHoje, (x) {
          data = _hoje;
        }),
        (_reSemanaVem, (x) {
          data = _somaDias(_hoje, 7);
          semanaQueVem = true;
        }),
        (_reMesVem, (x) {
          data = _somaMeses(_hoje, 1);
        }),
        (_reDataBarra, (x) {
          final d = int.parse(x.group(1)!);
          final mes = int.parse(x.group(2)!);
          var a = x.group(3) == null ? agora.year : int.parse(x.group(3)!);
          if (a < 100) a += 2000;
          var c = _valida(a, mes, d);
          if (c != null && x.group(3) == null && c.isBefore(_hoje)) c = _valida(a + 1, mes, d);
          data = c;
        }),
        (_reDataExtenso, (x) {
          final d = int.parse(x.group(1)!);
          final mes = _meses[x.group(2)!]!;
          final a = x.group(3) == null ? agora.year : int.parse(x.group(3)!);
          var c = _valida(a, mes, d);
          if (c != null && x.group(3) == null && c.isBefore(_hoje)) c = _valida(a + 1, mes, d);
          data = c;
        }),
        (_reDiaN, (x) {
          data = _proximoDiaMes(int.parse(x.group(1)!), hh, mm);
        }),
        (_reDiaSemana, (x) {
          final alvo = _diasSemana[x.group(2)!]!;
          final explicito = x.group(1) != null || x.group(3) != null;
          final diff = (alvo - agora.weekday + 7) % 7;
          if (diff == 0) {
            data = _somaDias(_hoje, 7);
            if (!explicito) {
              ambiguo = true; // "sexta" dito numa sexta: hoje ou a próxima?
              alternativa = _hoje;
            }
          } else {
            data = _somaDias(_hoje, diff);
          }
        }),
      ]);
    }

    var d = data;
    if (semanaQueVem) {
      // "segunda da semana que vem"
      final mw = achar(_reDiaSemana);
      if (mw != null) {
        final alvo = _diasSemana[mw.group(2)!]!;
        d = _somaDias(_hoje, 8 - agora.weekday + (alvo - 1));
      }
    }

    // Só horário, sem data: hoje se ainda não passou, senão amanhã.
    if (d == null && hF != null && recFreq == null) {
      final hojeNoHorario = DateTime(agora.year, agora.month, agora.day, hF, mF ?? 0);
      d = hojeNoHorario.isAfter(agora) ? _hoje : _somaDias(_hoje, 1);
    }

    // Recorrência: monta a regra e calcula a primeira ocorrência.
    String? regra;
    if (recFreq != null) {
      final Recorrencia r;
      if (recFreq == 'DAILY') {
        r = const Recorrencia('DAILY');
      } else if (recFreq == 'WEEKLY') {
        final dias = recDias.isNotEmpty ? recDias.toList() : [(d ?? _hoje).weekday];
        dias.sort();
        r = Recorrencia('WEEKLY', dias: dias);
      } else {
        r = Recorrencia('MONTHLY', diaMes: recDiaMes ?? (d ?? _hoje).day);
      }
      regra = r.toRRule();
      final explicita = d != null && (recFreq == 'DAILY' || recSemanalSemDia || recMensalSemDia);
      if (!explicita) {
        final prox = r.proxima(agora, hF ?? 23, mF ?? 59);
        final p = prox ?? _hoje;
        d = DateTime(p.year, p.month, p.day);
      }
    }

    DateTime? dh;
    if (relativoExato != null) {
      dh = relativoExato;
    } else if (d != null) {
      dh = DateTime(d.year, d.month, d.day, hF ?? 0, mF ?? 0);
    }

    return Quando(
      dataHora: dh,
      temData: d != null,
      origemHorario: origem,
      recorrencia: regra,
      antecedencias: antecedencias,
      ambiguoHojeOuProxima: ambiguo,
      alternativa: alternativa,
      trechos: trechos,
    );
  }

  // ---------- auxiliares ----------

  num _numero(String n) => n == 'meia' ? 0.5 : (num.tryParse(n) ?? _numeros[n] ?? 1);

  int _minutos(String n, String un) {
    final q = _numero(n);
    final f = un.startsWith('min')
        ? 1
        : un.startsWith('h')
            ? 60
            : un.startsWith('dia')
                ? 1440
                : un.startsWith('seman')
                    ? 10080
                    : 1;
    return (q * f).round();
  }

  DateTime _somaDias(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  DateTime _somaMeses(DateTime d, int n) {
    final alvo = DateTime(d.year, d.month + n, 1);
    final ultimo = DateTime(alvo.year, alvo.month + 1, 0).day;
    return DateTime(alvo.year, alvo.month, d.day > ultimo ? ultimo : d.day);
  }

  DateTime? _valida(int a, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return null;
    final c = DateTime(a, m, d);
    return (c.month == m && c.day == d) ? c : null;
  }

  /// Próximo "dia N": este mês se ainda não passou, senão o próximo mês que tenha o dia.
  DateTime _proximoDiaMes(int dia, int? h, int? mi) {
    for (var i = 0; i < 24; i++) {
      final base = DateTime(agora.year, agora.month + i, 1);
      final c = DateTime(base.year, base.month, dia);
      if (c.month != base.month) continue; // o mês não tem esse dia
      if (c.isBefore(_hoje)) continue;
      if (c == _hoje && h != null && !DateTime(c.year, c.month, c.day, h, mi ?? 0).isAfter(agora)) {
        continue; // hoje, mas o horário já passou
      }
      return c;
    }
    return _hoje;
  }
}

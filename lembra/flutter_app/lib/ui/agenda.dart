import 'package:intl/intl.dart';

import '../domain/item.dart';

DateTime inicioDoDia(DateTime d) => DateTime(d.year, d.month, d.day);

bool mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hoje • 14:30", "Amanhã", "qua., 22 de out. • 09:00".
String quandoCurto(DateTime d, {bool comHora = true, DateTime? agora}) {
  final a = agora ?? DateTime.now();
  final dif = inicioDoDia(d).difference(inicioDoDia(a)).inDays;
  final String dia;
  if (dif == 0) {
    dia = 'Hoje';
  } else if (dif == 1) {
    dia = 'Amanhã';
  } else if (dif == -1) {
    dia = 'Ontem';
  } else {
    dia = DateFormat("EEE, d 'de' MMM", 'pt_BR').format(d);
  }
  return comHora ? '$dia • ${DateFormat.Hm('pt_BR').format(d)}' : dia;
}

String horaMinutos(int minutos) =>
    '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

/// Data/hora em que o item aparece na agenda (a próxima ocorrência, se recorrente).
DateTime? dataExibicao(Item i, DateTime agora) {
  final r = i.regra;
  final a = i.ancora;
  if (r != null) {
    final base = inicioDoDia(agora).subtract(const Duration(minutes: 1));
    return r.proxima(base, a?.hour ?? 9, a?.minute ?? 0);
  }
  return a;
}

/// Primeira data a partir de amanhã (para a aba "Próximos").
DateTime? _dataAposHoje(Item i, DateTime agora) {
  final limite = DateTime(agora.year, agora.month, agora.day + 1);
  final r = i.regra;
  final a = i.ancora;
  if (r != null) {
    return r.proxima(limite.subtract(const Duration(minutes: 1)), a?.hour ?? 9, a?.minute ?? 0);
  }
  return (a != null && !a.isBefore(limite)) ? a : null;
}

int _porHorario(Item a, Item b, DateTime agora) {
  final da = dataExibicao(a, agora);
  final db = dataExibicao(b, agora);
  if (da == null || db == null) return 0;
  return da.compareTo(db);
}

class GruposHoje {
  GruposHoje(this.atrasados, this.hoje, this.feitos);
  final List<Item> atrasados;
  final List<Item> hoje;
  final List<Item> feitos;
  bool get vazio => atrasados.isEmpty && hoje.isEmpty && feitos.isEmpty;
}

GruposHoje agruparHoje(List<Item> itens, DateTime agora, {TipoItem? filtro}) {
  final atrasados = <Item>[];
  final hoje = <Item>[];
  final feitos = <Item>[];
  final inicio = inicioDoDia(agora);
  for (final i in itens) {
    if (filtro != null && i.tipo != filtro) continue;
    final feitoHoje = i.concluidoEm != null && mesmoDia(i.concluidoEm!, agora);
    if (i.status == StatusItem.concluido) {
      if (feitoHoje) feitos.add(i);
      continue;
    }
    if (i.status != StatusItem.ativo) continue;
    if (i.regra != null && feitoHoje) {
      feitos.add(i);
      continue;
    }
    final d = dataExibicao(i, agora);
    if (d == null) continue;
    if (d.isBefore(inicio)) {
      atrasados.add(i);
    } else if (mesmoDia(d, agora)) {
      hoje.add(i);
    }
  }
  atrasados.sort((a, b) => _porHorario(a, b, agora));
  hoje.sort((a, b) => _porHorario(a, b, agora));
  return GruposHoje(atrasados, hoje, feitos);
}

class GruposProximos {
  GruposProximos(this.porDia, this.semData);
  final Map<DateTime, List<Item>> porDia;
  final List<Item> semData;
  bool get vazio => porDia.isEmpty && semData.isEmpty;
}

GruposProximos agruparProximos(List<Item> itens, DateTime agora, {TipoItem? filtro}) {
  final porDia = <DateTime, List<Item>>{};
  final semData = <Item>[];
  for (final i in itens) {
    if (filtro != null && i.tipo != filtro) continue;
    if (i.status != StatusItem.ativo) continue;
    if (i.regra == null && i.ancora == null) {
      semData.add(i);
      continue;
    }
    final d = _dataAposHoje(i, agora);
    if (d == null) continue;
    porDia.putIfAbsent(inicioDoDia(d), () => []).add(i);
  }
  final chaves = porDia.keys.toList()..sort();
  final ordenado = <DateTime, List<Item>>{};
  for (final k in chaves) {
    final l = porDia[k]!..sort((a, b) => (_dataAposHoje(a, agora) ?? k).compareTo(_dataAposHoje(b, agora) ?? k));
    ordenado[k] = l;
  }
  return GruposProximos(ordenado, semData);
}

/// Texto do briefing (lido em voz alta e mostrado na tela).
String textoResumo(List<Item> itens, DateTime dia, DateTime agora) {
  final fim = inicioDoDia(dia);
  final lista = <(DateTime, Item)>[];
  for (final i in itens) {
    if (i.status != StatusItem.ativo) continue;
    final d = i.regra != null
        ? i.regra!.proxima(fim.subtract(const Duration(minutes: 1)), i.ancora?.hour ?? 9, i.ancora?.minute ?? 0)
        : i.ancora;
    if (d == null || !mesmoDia(d, dia)) continue;
    lista.add((d, i));
  }
  lista.sort((a, b) => a.$1.compareTo(b.$1));
  final nome = mesmoDia(dia, agora)
      ? 'hoje'
      : (inicioDoDia(dia).difference(inicioDoDia(agora)).inDays == 1 ? 'amanhã' : 'nesse dia');
  if (lista.isEmpty) return 'Você não tem nada marcado para $nome.';
  final partes = lista.map((e) {
    final temHora = e.$1.hour != 0 || e.$1.minute != 0;
    return temHora ? 'às ${DateFormat.Hm('pt_BR').format(e.$1)}, ${e.$2.titulo}' : e.$2.titulo;
  });
  final n = lista.length;
  return 'Para $nome você tem $n ${n == 1 ? 'item' : 'itens'}: ${partes.join('. ')}.';
}

/// Regra de recorrência simplificada (subconjunto de RRULE suportado pelo app):
/// FREQ=DAILY | FREQ=WEEKLY;BYDAY=MO,WE | FREQ=MONTHLY;BYMONTHDAY=5
class Recorrencia {
  const Recorrencia(this.freq, {this.dias = const [], this.diaMes});

  final String freq; // DAILY | WEEKLY | MONTHLY
  final List<int> dias; // DateTime.weekday: 1 = segunda ... 7 = domingo
  final int? diaMes;

  static const _codigos = {1: 'MO', 2: 'TU', 3: 'WE', 4: 'TH', 5: 'FR', 6: 'SA', 7: 'SU'};
  static const _abrev = {1: 'seg', 2: 'ter', 3: 'qua', 4: 'qui', 5: 'sex', 6: 'sáb', 7: 'dom'};

  /// Lê uma RRULE (com ou sem o prefixo "RRULE:"). Retorna null se não for suportada.
  static Recorrencia? parse(String? rrule) {
    if (rrule == null || rrule.trim().isEmpty) return null;
    final partes = <String, String>{};
    for (final p in rrule.replaceFirst('RRULE:', '').split(';')) {
      final kv = p.split('=');
      if (kv.length == 2) partes[kv[0].trim().toUpperCase()] = kv[1].trim().toUpperCase();
    }
    switch (partes['FREQ']) {
      case 'DAILY':
        return const Recorrencia('DAILY');
      case 'WEEKLY':
        final dias = <int>[];
        for (final c in (partes['BYDAY'] ?? '').split(',')) {
          for (final e in _codigos.entries) {
            if (e.value == c) dias.add(e.key);
          }
        }
        dias.sort();
        return dias.isEmpty ? null : Recorrencia('WEEKLY', dias: dias);
      case 'MONTHLY':
        final d = int.tryParse(partes['BYMONTHDAY'] ?? '');
        return d == null ? null : Recorrencia('MONTHLY', diaMes: d);
    }
    return null;
  }

  String toRRule() {
    switch (freq) {
      case 'WEEKLY':
        final ord = [...dias]..sort();
        return 'FREQ=WEEKLY;BYDAY=${ord.map((d) => _codigos[d]).join(',')}';
      case 'MONTHLY':
        return 'FREQ=MONTHLY;BYMONTHDAY=$diaMes';
      default:
        return 'FREQ=DAILY';
    }
  }

  bool ocorreEm(DateTime d) {
    switch (freq) {
      case 'DAILY':
        return true;
      case 'WEEKLY':
        return dias.contains(d.weekday);
      case 'MONTHLY':
        return d.day == diaMes;
    }
    return false;
  }

  /// Primeira ocorrência estritamente depois de [depois], no horário [hora]:[minuto].
  DateTime? proxima(DateTime depois, int hora, int minuto) {
    final base = DateTime(depois.year, depois.month, depois.day);
    for (var i = 0; i < 400; i++) {
      final d = DateTime(base.year, base.month, base.day + i);
      if (!ocorreEm(d)) continue;
      final c = DateTime(d.year, d.month, d.day, hora, minuto);
      if (c.isAfter(depois)) return c;
    }
    return null;
  }

  /// Próxima ocorrência de um único dia da semana (usado nos alarmes semanais).
  DateTime? proximaDoDia(int diaSemana, DateTime depois, int hora, int minuto) =>
      Recorrencia('WEEKLY', dias: [diaSemana]).proxima(depois, hora, minuto);

  String get descricao {
    switch (freq) {
      case 'DAILY':
        return 'Todo dia';
      case 'WEEKLY':
        if (dias.length == 5 && dias.every((d) => d <= 5)) return 'Dias úteis';
        return 'Toda semana: ${dias.map((d) => _abrev[d]).join(', ')}';
      case 'MONTHLY':
        return 'Todo dia $diaMes';
    }
    return '';
  }
}

// Coloque em: lib/ui/alarme_tocando_page.dart
//
// Tela cheia exibida quando um alarme crítico toca (ou quando o usuário toca
// na notificação do alarme). O som continua até o usuário escolher uma ação.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'theme/app_theme.dart';

class AlarmeTocandoPage extends StatefulWidget {
  const AlarmeTocandoPage({
    super.key,
    required this.titulo,
    required this.mensagem,
    required this.aoFeito,
    required this.aoAdiar,
    required this.aoSilenciar,
  });

  /// Texto do lembrete (o que o usuário pediu para ser avisado).
  final String titulo;

  /// Linha de apoio, por exemplo "Qui, 22 de out às 07:00".
  final String mensagem;

  final Future<void> Function() aoFeito;
  final Future<void> Function() aoAdiar;
  final Future<void> Function() aoSilenciar;

  @override
  State<AlarmeTocandoPage> createState() => _AlarmeTocandoPageState();
}

class _AlarmeTocandoPageState extends State<AlarmeTocandoPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso;
  Timer? _relogio;
  DateTime _agora = DateTime.now();
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    // Tela inteira, sem barras do sistema.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _agora = DateTime.now());
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _pulso.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _encerrar(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await acao();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return PopScope(
      // O alarme só sai da tela por uma das ações.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.forestDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              children: [
                const Spacer(flex: 2),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1.08)
                      .animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandSoft.withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.alarm_rounded, size: 52, color: AppColors.brandSoft),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  DateFormat.Hm('pt_BR').format(_agora),
                  style: t.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onDark,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.titulo,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onDark,
                  ),
                ),
                if (widget.mensagem.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.mensagem,
                    textAlign: TextAlign.center,
                    style: t.titleMedium?.copyWith(color: AppColors.onDarkMuted),
                  ),
                ],
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: _ocupado ? null : () => _encerrar(widget.aoFeito),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Feito'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandSoft,
                      foregroundColor: AppColors.ink,
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _ocupado ? null : () => _encerrar(widget.aoAdiar),
                    icon: const Icon(Icons.snooze_rounded),
                    label: const Text('Adiar 10 min'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onDark,
                      side: BorderSide(color: AppColors.onDark.withValues(alpha: 0.6)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _ocupado ? null : () => _encerrar(widget.aoSilenciar),
                  style: TextButton.styleFrom(foregroundColor: AppColors.onDarkMuted),
                  child: const Text('Só silenciar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

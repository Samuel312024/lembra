import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/item.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';

/// Tela cheia do alarme crítico: acende a tela, aparece por cima do bloqueio
/// (ver `showWhenLocked`/`turnScreenOn` no AndroidManifest) e mostra a mensagem
/// do lembrete com os botões "Feito" e "Adiar 10 min".
class AlarmPage extends ConsumerStatefulWidget {
  const AlarmPage({super.key, required this.itemId, this.notificacaoId});

  final String itemId;
  final int? notificacaoId;

  @override
  ConsumerState<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends ConsumerState<AlarmPage> with SingleTickerProviderStateMixin {
  static const _fundoTopo = Color(0xFF111827);
  static const _fundoBase = Color(0xFF7C2D12);
  static const _destaque = Color(0xFFFBBF24);

  late final AnimationController _pulso;
  Timer? _relogio;
  DateTime _agora = DateTime.now();
  bool _agindo = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
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

  Item? _achar(List<Item> itens) {
    for (final i in itens) {
      if (i.id == widget.itemId) return i;
    }
    return null;
  }

  /// [acao] = 'feito' | 'soneca' | null (só silenciar).
  Future<void> _agir(String? acao, Item? item) async {
    if (_agindo) return;
    setState(() => _agindo = true);
    final servico = NotificationService.instance;
    await servico.pararAlarme(notificacaoId: widget.notificacaoId, item: item);
    if (item != null && acao != null) {
      final resposta = servico.aoResponder;
      if (resposta != null) {
        // Mesmo caminho dos botões da notificação.
        resposta(acao, item.id);
      } else if (acao == 'feito') {
        await ref.read(itemsProvider.notifier).concluir(item.id);
      } else if (acao == 'soneca') {
        await servico.agendarSoneca(item, const Duration(minutes: 10));
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _quando(Item i) {
    final a = i.ancora;
    if (a == null) return '';
    final regra = i.regra;
    if (regra != null) return '${regra.descricao} • às ${DateFormat.Hm('pt_BR').format(a)}';
    return DateFormat("EEE, d 'de' MMM 'às' HH:mm", 'pt_BR').format(a);
  }

  @override
  Widget build(BuildContext context) {
    final itens = ref.watch(itemsProvider);
    final item = _achar(itens.valueOrNull ?? const <Item>[]);
    final carregando = item == null && itens.isLoading;
    final t = Theme.of(context).textTheme;
    final branco70 = Colors.white.withValues(alpha: 0.7);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _fundoTopo,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_fundoTopo, _fundoBase],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                children: [
                  Text(
                    DateFormat.Hm('pt_BR').format(_agora),
                    style: t.displayLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text(
                    toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_agora)) ?? '',
                    style: t.titleMedium?.copyWith(color: branco70),
                  ),
                  Expanded(
                    child: Center(
                      child: carregando
                          ? const CircularProgressIndicator(color: Colors.white)
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ScaleTransition(
                                    scale: Tween<double>(begin: 0.9, end: 1.1)
                                        .animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                                    child: Container(
                                      width: 132,
                                      height: 132,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _destaque.withValues(alpha: 0.18),
                                        border: Border.all(color: _destaque.withValues(alpha: 0.6), width: 2),
                                      ),
                                      child: const Icon(Icons.alarm_rounded, size: 64, color: _destaque),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  if (item != null)
                                    Text(
                                      item.tipo.rotulo.toUpperCase(),
                                      style: t.labelLarge?.copyWith(
                                        color: _destaque,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item?.titulo ?? 'Alarme',
                                    textAlign: TextAlign.center,
                                    style: t.headlineLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item != null && _quando(item).isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      _quando(item),
                                      textAlign: TextAlign.center,
                                      style: t.titleMedium?.copyWith(color: branco70),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      onPressed: (_agindo || item == null) ? null : () => _agir('feito', item),
                      icon: const Icon(Icons.check_rounded, size: 28),
                      label: const Text('Feito'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _fundoTopo,
                        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: (_agindo || item == null) ? null : () => _agir('soneca', item),
                      icon: const Icon(Icons.snooze_rounded),
                      label: const Text('Adiar 10 min'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white38,
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _agindo ? null : () => _agir(null, item),
                    style: TextButton.styleFrom(foregroundColor: branco70),
                    child: const Text('Só parar o som'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
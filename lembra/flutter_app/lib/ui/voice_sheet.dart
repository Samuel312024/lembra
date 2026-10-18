import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/speech_service.dart';
import '../state/providers.dart';

/// Folha de escuta: mostra a transcrição ao vivo e devolve o texto final.
/// Se o reconhecimento de voz não estiver disponível, oferece digitar.
class VoiceSheet extends ConsumerStatefulWidget {
  const VoiceSheet({super.key, this.titulo = 'Pode falar…', this.dica});

  final String titulo;
  final String? dica;

  @override
  ConsumerState<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<VoiceSheet> with SingleTickerProviderStateMixin {
  late final SpeechService _speech;
  late final AnimationController _pulso;
  final _ctrl = TextEditingController();
  String _texto = '';
  String? _aviso;
  bool _digitar = false;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechProvider);
    _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ouvir());
  }

  Future<void> _ouvir() async {
    setState(() {
      _aviso = null;
      _texto = '';
    });
    final ok = await _speech.ouvir(
      aoParcial: (t) {
        if (mounted) setState(() => _texto = t);
      },
      aoFinal: (t) {
        if (mounted) Navigator.of(context).pop(t);
      },
      aoVazio: () {
        if (mounted) setState(() => _aviso = 'Não ouvi nada. Toque no microfone para tentar de novo.');
      },
    );
    if (!ok && mounted) {
      setState(() {
        _digitar = true;
        _aviso = 'Reconhecimento de voz indisponível. Digite o que você quer lembrar.';
      });
    }
  }

  @override
  void dispose() {
    _speech.cancelar();
    _pulso.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final teclado = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + teclado),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.titulo, style: Theme.of(context).textTheme.titleLarge),
          if (widget.dica != null) ...[
            const SizedBox(height: 4),
            Text(widget.dica!, style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          if (!_digitar) ...[
            GestureDetector(
              onTap: _ouvir,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.08).animate(
                  CurvedAnimation(parent: _pulso, curve: Curves.easeInOut),
                ),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: cs.primary,
                  child: Icon(Icons.mic, size: 44, color: cs.onPrimary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Text(
                _texto.isEmpty ? 'Ouvindo…' : '“$_texto”',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ] else ...[
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex.: tenho médico dia 22 às 14h30',
              ),
              onSubmitted: (t) => t.trim().isEmpty ? null : Navigator.of(context).pop(t.trim()),
            ),
          ],
          if (_aviso != null) ...[
            const SizedBox(height: 8),
            Text(_aviso!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              if (_digitar)
                FilledButton(
                  onPressed: () {
                    final t = _ctrl.text.trim();
                    if (t.isNotEmpty) Navigator.of(context).pop(t);
                  },
                  child: const Text('Enviar'),
                )
              else ...[
                TextButton(
                  onPressed: () {
                    _speech.cancelar();
                    setState(() => _digitar = true);
                  },
                  child: const Text('Digitar'),
                ),
                FilledButton(onPressed: _speech.parar, child: const Text('Terminei')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Coloque em: lib/ui/boas_vindas_page.dart
//
// Tela de boas-vindas, exibida uma vez na primeira abertura: explica o app em
// três passos e já pede as permissões que os alarmes precisam.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import '../state/providers.dart';
import 'theme/app_theme.dart';

const _chaveVisto = 'boas_vindas_ok';

/// Mostra as boas-vindas só na primeira vez; depois, o app normal.
class PrimeiroUso extends ConsumerStatefulWidget {
  const PrimeiroUso({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PrimeiroUso> createState() => _PrimeiroUsoState();
}

class _PrimeiroUsoState extends ConsumerState<PrimeiroUso> {
  late bool _visto = ref.read(prefsProvider).getBool(_chaveVisto) ?? false;

  Future<void> _concluir() async {
    await ref.read(prefsProvider).setBool(_chaveVisto, true);
    if (mounted) setState(() => _visto = true);
  }

  @override
  Widget build(BuildContext context) => _visto ? widget.child : BoasVindasPage(aoConcluir: _concluir);
}

class _Passo {
  const _Passo(this.icone, this.titulo, this.texto);

  final IconData icone;
  final String titulo;
  final String texto;
}

const _passos = <_Passo>[
  _Passo(
    Icons.mic_rounded,
    'Fale e eu anoto',
    'Toque em “Falar agora” e diga, por exemplo: “Tenho médico dia 22 às 14h30”. '
        'Eu entendo a data e a hora e aviso você na hora certa.',
  ),
  _Passo(
    Icons.account_balance_wallet_rounded,
    'Contas sob controle',
    'Diga “conta de luz de 150 reais dia 10”. O Lembra separa o tipo da conta, '
        'soma o que falta pagar e avisa antes de vencer.',
  ),
  _Passo(
    Icons.notifications_active_rounded,
    'Para avisar na hora certa',
    'Para os alarmes tocarem no minuto certo, mesmo com o app fechado, o Android precisa '
        'da sua permissão para notificações e alarmes.',
  ),
];

class BoasVindasPage extends StatefulWidget {
  const BoasVindasPage({super.key, required this.aoConcluir});

  final Future<void> Function() aoConcluir;

  @override
  State<BoasVindasPage> createState() => _BoasVindasPageState();
}

class _BoasVindasPageState extends State<BoasVindasPage> {
  final _controle = PageController();
  int _pagina = 0;
  String? _resultado;
  bool _ocupado = false;

  bool get _ultima => _pagina == _passos.length - 1;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  Future<void> _proximo() async {
    if (_ultima) {
      await _terminar();
    } else {
      await _controle.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  Future<void> _terminar() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    await widget.aoConcluir();
  }

  Future<void> _liberar() async {
    await NotificationService.instance.pedirPermissoes();
    final e = await NotificationService.instance.estadoPermissoes();
    if (!mounted) return;
    setState(() {
      _resultado = 'Notificações: ${e.notificacoes ? 'ok' : 'bloqueadas'} • '
          'Alarme exato: ${e.alarmeExato ? 'ok' : 'não liberado'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _ocupado ? null : _terminar,
                child: const Text('Pular'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controle,
                itemCount: _passos.length,
                onPageChanged: (i) => setState(() => _pagina = i),
                itemBuilder: (_, i) {
                  final p = _passos[i];
                  final permissoes = i == _passos.length - 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.forest),
                          child: Icon(p.icone, size: 56, color: AppColors.brandSoft),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p.titulo,
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.texto,
                          textAlign: TextAlign.center,
                          style: t.bodyLarge?.copyWith(color: AppColors.muted, height: 1.4),
                        ),
                        if (permissoes) ...[
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _liberar,
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('Liberar notificações e alarmes'),
                          ),
                          if (_resultado != null) ...[
                            const SizedBox(height: 10),
                            Text(_resultado!, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _passos.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _pagina ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _pagina ? AppColors.brand : AppColors.cardBorder,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _ocupado ? null : _proximo,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                  child: Text(_ultima ? 'Começar' : 'Próximo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
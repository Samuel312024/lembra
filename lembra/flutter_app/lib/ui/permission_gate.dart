// Coloque em: lib/ui/permission_gate.dart
// Dependência: flutter pub add permission_handler
//
// Uso no MaterialApp (lib/app.dart) — cobre todas as telas do app:
//
//   MaterialApp(
//     builder: (context, child) => PermissionGate(
//       exigirSobreposicao: true, // opcional, veja abaixo
//       child: child ?? const SizedBox.shrink(),
//     ),
//     ...
//   )
//
// Android: para a sobreposição aparecer na lista do celular, declare no
// AndroidManifest.xml:
//   <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bloqueia o app até as notificações (e, opcionalmente, os alarmes exatos e a
/// sobreposição de tela) estarem permitidas. Reavalia sempre que o app volta
/// das configurações.
class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.child,
    this.exigirAlarmesExatos = true,
    this.exigirSobreposicao = false,
  });

  final Widget child;

  /// No Android 12+, o alarme exato é uma permissão especial, ativada em
  /// "Alarmes e lembretes". Sem ela, o lembrete pode não tocar na hora.
  final bool exigirAlarmesExatos;

  /// "Aparecer sobre outros apps" (SYSTEM_ALERT_WINDOW). Ajuda o alarme crítico
  /// a aparecer na tela mesmo com o celular desbloqueado e em uso.
  /// Fica desligado por padrão: como o gate bloqueia o app inteiro, exigir isso
  /// trava o usuário até ele ligar o botão nas configurações do sistema.
  final bool exigirSobreposicao;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool _verificando = true;
  PermissionStatus _notificacoes = PermissionStatus.denied;
  PermissionStatus _alarmes = PermissionStatus.granted;
  bool _sobreposicao = true;

  bool get _tudoOk =>
      _notificacoes.isGranted &&
      (!widget.exigirAlarmesExatos || _alarmes.isGranted) &&
      (!widget.exigirSobreposicao || _sobreposicao);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _atualizar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volta das configurações do sistema: confere de novo.
    if (state == AppLifecycleState.resumed) _atualizar();
  }

  Future<void> _atualizar() async {
    final sobrepoe = (Platform.isAndroid && widget.exigirSobreposicao)
        ? await Permission.systemAlertWindow.isGranted
        : true;
    final notif = await Permission.notification.status;
    final alarmes = (Platform.isAndroid && widget.exigirAlarmesExatos)
        ? await Permission.scheduleExactAlarm.status
        : PermissionStatus.granted;
    if (!mounted) return;
    setState(() {
      _notificacoes = notif;
      _alarmes = alarmes;
      _sobreposicao = sobrepoe;
      _verificando = false;
    });
  }

  Future<void> _pedirNotificacoes() async {
    // Depois de negar duas vezes no Android 13+, o sistema não mostra mais o
    // diálogo. Nesse caso só resta levar o usuário às configurações do app.
    if (_notificacoes.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await Permission.notification.request();
    await _atualizar();
  }

  Future<void> _pedirAlarmes() async {
    // No Android 12+ isto abre a tela "Alarmes e lembretes" do sistema.
    await Permission.scheduleExactAlarm.request();
    await _atualizar();
  }

  Future<void> _pedirSobreposicao() async {
    // Abre a tela "Aparecer sobre outros apps" do sistema. O usuário liga o
    // botão e volta; o didChangeAppLifecycleState reavalia ao retornar.
    await Permission.systemAlertWindow.request();
    await _atualizar();
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_tudoOk) return widget.child;

    final tema = Theme.of(context);
    final notifPendente = !_notificacoes.isGranted;
    final alarmesPendente = widget.exigirAlarmesExatos && !_alarmes.isGranted;

    // Ordem dos passos: notificações -> alarmes exatos -> sobreposição.
    final String mensagem;
    if (notifPendente) {
      mensagem = 'O Lembra existe para avisar você na hora certa. '
          'Sem permitir as notificações, os lembretes e alarmes '
          'não conseguem tocar.';
    } else if (alarmesPendente) {
      mensagem = 'Para despertar no horário exato, permita '
          '"Alarmes e lembretes" para o Lembra.';
    } else {
      mensagem = 'Para o alarme aparecer na tela mesmo com o celular em uso, '
          'permita "Aparecer sobre outros apps" para o Lembra.';
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 72,
                color: tema.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Precisamos das suas permissões',
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (notifPendente)
                FilledButton(
                  onPressed: _pedirNotificacoes,
                  child: Text(
                    _notificacoes.isPermanentlyDenied
                        ? 'Abrir configurações'
                        : 'Permitir notificações',
                  ),
                )
              else if (alarmesPendente)
                FilledButton(
                  onPressed: _pedirAlarmes,
                  child: const Text('Permitir alarmes e lembretes'),
                )
              else
                FilledButton(
                  onPressed: _pedirSobreposicao,
                  child: const Text('Permitir aparecer sobre outros apps'),
                ),
              if (notifPendente && _notificacoes.isPermanentlyDenied) ...[
                const SizedBox(height: 12),
                Text(
                  'Em Configurações > Notificações, ative as notificações do '
                  'Lembra e volte para o app.',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
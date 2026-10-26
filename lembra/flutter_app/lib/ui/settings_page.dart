import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import '../state/providers.dart';
import '../state/som_provider.dart';
import 'account_page.dart';
import 'agenda.dart';
import 'dados_page.dart';
import 'som_alarme_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<int?> _escolherHora(BuildContext context, int atual) async {
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: atual ~/ 60, minute: atual % 60),
    );
    return r == null ? null : r.hour * 60 + r.minute;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final email = ref.watch(sessaoProvider);
    final som = ref.watch(somAlarmeProvider);
    final android = defaultTargetPlatform == TargetPlatform.android;
    final notifier = ref.read(configProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Conta e sincronização'),
            subtitle: Text(email ?? 'Usando só neste aparelho'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountPage())),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('Entender com IA na nuvem'),
            subtitle: const Text('Precisa de conta e internet. Sem isso, o app usa o interpretador do aparelho.'),
            value: cfg.usarIA,
            onChanged: (v) => notifier.salvar(cfg.copyWith(usarIA: v)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Horário padrão'),
            subtitle: Text('${horaMinutos(cfg.horarioPadrao)} — sugerido quando você não diz a hora'),
            onTap: () async {
              final m = await _escolherHora(context, cfg.horarioPadrao);
              if (m != null) notifier.salvar(cfg.copyWith(horarioPadrao: m));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Briefing da manhã'),
            subtitle: Text('Resumo do dia às ${horaMinutos(cfg.briefingMin)}'),
            value: cfg.briefing,
            onChanged: (v) => notifier.salvar(cfg.copyWith(briefing: v)),
          ),
          if (cfg.briefing)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Horário do briefing'),
              trailing: Text(horaMinutos(cfg.briefingMin)),
              onTap: () async {
                final m = await _escolherHora(context, cfg.briefingMin);
                if (m != null) notifier.salvar(cfg.copyWith(briefingMin: m));
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.nights_stay_outlined),
            title: const Text('Revisão da noite'),
            subtitle: Text('O que ficou para trás, às ${horaMinutos(cfg.revisaoMin)}'),
            value: cfg.revisao,
            onChanged: (v) => notifier.salvar(cfg.copyWith(revisao: v)),
          ),
          if (cfg.revisao)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Horário da revisão'),
              trailing: Text(horaMinutos(cfg.revisaoMin)),
              onTap: () async {
                final m = await _escolherHora(context, cfg.revisaoMin);
                if (m != null) notifier.salvar(cfg.copyWith(revisaoMin: m));
              },
            ),
          const Divider(),
          if (android)
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('Som do alarme'),
              subtitle: Text(som.rotulo),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SomAlarmePage())),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Permissões de alarme'),
            subtitle: const Text('Verificar e liberar notificações, alarme exato e tela cheia'),
            onTap: () => _permissoes(context),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Android: alarme exato e tela cheia no nível “crítico” (precisam das permissões acima).\n'
              'iPhone: o sistema não permite alarmes em segundo plano; o app usa notificações com som e '
              'prioridade alta (“time-sensitive”). Elas não ignoram o modo Silencioso nem o Foco.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Dados e diagnóstico'),
            subtitle: const Text('Backup dos lembretes e relatório de problemas'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DadosPage())),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: const Text('Excluir todos os meus dados'),
            subtitle: const Text('Apaga os itens do aparelho e, se houver conta, do servidor.'),
            onTap: () => _excluir(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _permissoes(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Para os alarmes funcionarem'),
        content: const Text(
          'Vou pedir três permissões:\n\n'
          '• Notificações — para avisar você.\n'
          '• Alarmes exatos — para tocar no minuto certo, mesmo com o app fechado.\n'
          '• Tela cheia — para o alarme “crítico” aparecer por cima da tela bloqueada.\n\n'
          'Sem elas, os avisos podem atrasar ou não aparecer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok != true) return;
    await NotificationService.instance.pedirPermissoes();
    final e = await NotificationService.instance.estadoPermissoes();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Notificações: ${e.notificacoes ? 'ok' : 'bloqueadas'} • Alarme exato: ${e.alarmeExato ? 'ok' : 'não liberado'}',
      ),
    ));
  }

  Future<void> _excluir(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir todos os dados?'),
        content: const Text('Isso apaga todos os seus lembretes e não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir tudo')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return; // 👈 adiciona essa linha
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(sessaoProvider) != null) {
      try {
        await ref.read(apiProvider).excluirConta();
        await ref.read(sessaoProvider.notifier).sair();
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Não consegui apagar no servidor agora. Tente de novo com internet.'),
        ));
        return;
      }
    }
    await ref.read(itemsProvider.notifier).apagarTudo();
    messenger.showSnackBar(const SnackBar(content: Text('Dados excluídos.')));
  }
}
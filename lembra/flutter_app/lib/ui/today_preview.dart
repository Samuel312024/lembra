import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

/// Tela "Hoje" com dados de exemplo, só para validar o visual.
/// Depois você troca os dados fixos pelos do seu estado/banco.
class TodayPreviewPage extends StatelessWidget {
  const TodayPreviewPage({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _today() {
    const dias = [
      'segunda-feira',
      'terça-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sábado',
      'domingo',
    ];
    const meses = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    final d = DateTime.now();
    return '${dias[d.weekday - 1]}, ${d.day} de ${meses[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: VoiceFab(onPressed: () {}),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, Samuel',
                  style: t.bodyMedium?.copyWith(color: AppColors.onDarkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  _greeting(),
                  style: t.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _today(),
                  style: t.bodySmall?.copyWith(color: AppColors.onDarkMuted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _HeroTab('Hoje', selected: true),
                    _HeroTab('Semana'),
                    _HeroTab('Próximos'),
                    _HeroTab('Contas'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DayGauge(progress: 0.14, done: 1, total: 7),
                const SizedBox(height: 16),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatCard(
                        icon: Icons.alarm_rounded,
                        iconColor: AppColors.orange,
                        label: 'Regar as plantas da varanda',
                        value: '07:00',
                        valueColor: AppColors.brandSoft,
                        caption: 'Próximo alarme • amanhã',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AppColors.yellow,
                        label: 'Contas a vencer',
                        value: 'R\$ 2735,64',
                        valueColor: AppColors.cyanDeep,
                        caption: '3 contas nos próximos dias',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionHeader('Amanhã', count: 4),
                const SizedBox(height: 12),
                ReminderTile(
                  title: 'Regar as plantas da varanda',
                  time: '07:00',
                  icon: Icons.repeat_rounded,
                  iconColor: AppColors.green,
                  urgency: Urgency.discreet,
                  meta: 'Recorrente',
                  metaIcon: Icons.repeat_rounded,
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                ReminderTile(
                  title: 'Pagar condomínio',
                  time: '09:00',
                  icon: Icons.receipt_long_rounded,
                  iconColor: AppColors.yellow,
                  urgency: Urgency.normal,
                  meta: 'R\$ 842,50',
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                ReminderTile(
                  title: 'Enviar proposta revisada ao Rafael',
                  time: '11:00',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: AppColors.orange,
                  urgency: Urgency.normal,
                  meta: 'Da reunião',
                  metaIcon: Icons.groups_rounded,
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                ReminderTile(
                  title: 'Consulta médica',
                  time: '14:30',
                  icon: Icons.event_rounded,
                  iconColor: AppColors.cyan,
                  urgency: Urgency.critical,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTab extends StatelessWidget {
  const _HeroTab(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.onDark : AppColors.onDarkMuted,
                ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: selected ? AppColors.brandSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
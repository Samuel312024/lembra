import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------

/// Card branco com borda fina, o bloco básico de todas as telas.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Quadradinho colorido com ícone (usado nos lembretes e nos cards de resumo).
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: AppColors.ink),
    );
  }
}

/// Título de seção com contador: "Amanhã  6".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text('$count', style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Lembretes
// ---------------------------------------------------------------------------

enum Urgency { discreet, normal, critical }

class UrgencyChip extends StatelessWidget {
  const UrgencyChip(this.urgency, {super.key});

  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    final (String label, Color bg) = switch (urgency) {
      Urgency.discreet => ('Discreto', AppColors.slate),
      Urgency.normal => ('Normal', AppColors.cyan),
      Urgency.critical => ('Alarme crítico', AppColors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
      ),
    );
  }
}

/// Linha de lembrete: ícone, título, chip de urgência, detalhe e horário.
class ReminderTile extends StatelessWidget {
  const ReminderTile({
    super.key,
    required this.title,
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.urgency,
    this.meta,
    this.metaIcon,
    this.onTap,
  });

  final String title;
  final String time;
  final IconData icon;
  final Color iconColor;
  final Urgency urgency;
  final String? meta;
  final IconData? metaIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconBadge(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UrgencyChip(urgency),
                    if (meta != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (metaIcon != null) ...[
                            Icon(metaIcon, size: 14, color: AppColors.muted),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            meta!,
                            style: t.bodySmall?.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: AppText.mono(size: 16)),
        ],
      ),
    );
  }
}

/// Card de resumo: ícone, rótulo, valor grande em mono e legenda.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.caption,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;
  final String caption;

  /// Quando informado, o card vira um botão (com uma setinha no canto).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: iconColor, size: 40),
              if (onTap != null) ...[
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Valores em reais são longos: encolhem para caber em vez de quebrar a linha.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: AppText.mono(size: 24, color: valueColor)),
          ),
          const SizedBox(height: 4),
          Text(caption, style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero verde-floresta
// ---------------------------------------------------------------------------

/// Faixa escura no topo da tela, com os cantos de baixo arredondados.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.radius = 28,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.forest, AppColors.forestDeep],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: SafeArea(bottom: false, child: child),
    );
  }
}

/// Card escuro com o medidor de progresso do dia (arco de tracinhos).
class DayGauge extends StatelessWidget {
  const DayGauge({
    super.key,
    required this.progress,
    required this.done,
    required this.total,
    this.title = 'Dia sob controle',
  });

  /// Valor de 0.0 a 1.0.
  final double progress;
  final int done;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final percent = (progress.clamp(0.0, 1.0) * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forest, AppColors.forestDeep],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 190,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _TickGaugePainter(progress)),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$percent%',
                      style: t.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.onDark,
                      ),
                    ),
                    Text(
                      'do dia concluído',
                      style: t.bodySmall?.copyWith(color: AppColors.onDarkMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.onDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$done de $total itens',
            style: t.bodySmall?.copyWith(color: AppColors.onDarkMuted),
          ),
        ],
      ),
    );
  }
}

class _TickGaugePainter extends CustomPainter {
  _TickGaugePainter(this.progress);

  final double progress;

  static const int _ticks = 36;
  static const double _start = 150 * math.pi / 180; // canto inferior esquerdo
  static const double _sweep = 240 * math.pi / 180; // passa por cima do arco

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = math.min(size.width, size.height) / 2;
    final inner = outer * 0.80;

    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < _ticks; i++) {
      final t = i / (_ticks - 1);
      final angle = _start + _sweep * t;
      final dir = Offset(math.cos(angle), math.sin(angle));

      paint.color = t < progress
          ? AppColors.yellow
          : Colors.white.withValues(alpha: 0.22);

      canvas.drawLine(center + dir * inner, center + dir * outer, paint);
    }
  }

  @override
  bool shouldRepaint(_TickGaugePainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Ações
// ---------------------------------------------------------------------------

/// Botão flutuante principal do app: "Falar agora".
class VoiceFab extends StatelessWidget {
  const VoiceFab({super.key, required this.onPressed, this.label = 'Falar agora'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.mic_rounded),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Barra fixa embaixo da tela de revisão: contagem + ação principal.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.done_all_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// Coloque em: lib/ui/comparativo_renda_card.dart
//
// Cartão "Contas do mês x renda" com a barra de margem vermelha.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/dinheiro.dart';
import '../domain/renda.dart';
import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

class ComparativoRendaCard extends StatelessWidget {
  const ComparativoRendaCard({
    super.key,
    required this.perfil,
    required this.gasto,
    required this.mes,
  });

  final PerfilRenda? perfil;
  final double gasto;
  final DateTime mes;

  Widget _mini(BuildContext context, String rotulo, String valor, Color cor) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: t.bodySmall?.copyWith(color: context.cores.suave)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: AppText.mono(size: 14, color: cor)),
          ),
        ],
      ),
    );
  }

  Widget _legenda(BuildContext context, Color cor, String texto) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(texto, style: t.bodySmall?.copyWith(color: context.cores.suave)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;
    final p = perfil;
    final titulo = 'Contas de ${nomeMes(mes)} × renda';

    if (p == null || p.rendaMensal <= 0) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.pie_chart_rounded, color: AppColors.yellow, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(titulo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Informe quanto você ganha (CLT ou PJ) para ver quanto das contas do mês já compromete da sua renda.',
              style: t.bodyMedium?.copyWith(color: cores.suave),
            ),
          ],
        ),
      );
    }

    final c = ComparativoRenda(renda: p.rendaMensal, gasto: gasto, limitePct: p.limitePct);
    final vermelho = c.emVermelho;
    final corDestaque = vermelho ? cores.perigo : cores.texto;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: vermelho ? Icons.warning_amber_rounded : Icons.pie_chart_rounded,
                color: vermelho ? cores.perigo : AppColors.yellow,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      '${p.tipo.rotulo} • renda de ${formatarReais(c.renda)}',
                      style: t.bodySmall?.copyWith(color: cores.suave),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${(c.fracao * 100).round()}%', style: AppText.mono(size: 32, color: corDestaque)),
          ),
          Text('da renda vai para as contas', style: t.bodySmall?.copyWith(color: cores.suave)),
          const SizedBox(height: 12),
          BarraMargem(comparativo: c),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _legenda(context, cores.marca, 'Dentro do limite'),
              _legenda(context, cores.perigo, 'Margem vermelha (acima de ${p.limitePct.round()}%)'),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: cores.borda),
          const SizedBox(height: 12),
          Row(
            children: [
              _mini(context, 'Renda', formatarReais(c.renda), cores.texto),
              const SizedBox(width: 12),
              _mini(context, 'Contas', formatarReais(c.gasto), corDestaque),
              const SizedBox(width: 12),
              _mini(
                context,
                c.sobra >= 0 ? 'Sobra' : 'Falta',
                formatarReais(c.sobra.abs()),
                c.sobra >= 0 ? cores.texto : cores.perigo,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (vermelho ? cores.perigo : cores.marca).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              c.mensagem,
              style: t.bodySmall?.copyWith(color: vermelho ? cores.perigo : cores.texto, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra que representa 100% da renda. Até o limite fica na cor da marca;
/// o que passa do limite fica vermelho (a "margem vermelha").
class BarraMargem extends StatelessWidget {
  const BarraMargem({super.key, required this.comparativo});

  final ComparativoRenda comparativo;

  @override
  Widget build(BuildContext context) {
    final c = comparativo;
    final cores = context.cores;
    if (!c.temRenda) return const SizedBox.shrink();

    final seguro = math.min(c.gasto, c.valorLimite) / c.renda;
    final vermelho = (math.min(c.gasto, c.renda) - math.min(c.gasto, c.valorLimite)) / c.renda;
    final limite = c.limitePct / 100;
    final estourou = c.nivel == NivelGasto.estourou;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 24,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                height: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: cores.borda)),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: w * seguro,
                        child: ColoredBox(color: estourou ? cores.perigo : cores.marca),
                      ),
                      Positioned(
                        left: w * seguro,
                        top: 0,
                        bottom: 0,
                        width: w * vermelho,
                        child: ColoredBox(color: cores.perigo),
                      ),
                    ],
                  ),
                ),
              ),
              // Marcador do limite
              Positioned(
                left: w * limite - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: cores.texto.withValues(alpha: 0.7)),
              ),
            ],
          ),
        );
      },
    );
  }
}
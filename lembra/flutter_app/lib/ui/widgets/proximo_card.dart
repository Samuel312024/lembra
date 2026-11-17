import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Cartão de destaque da tela inicial: mostra o item mais importante do momento
/// (atrasado ou o próximo) com contagem regressiva e ações rápidas.
/// Se [titulo] for nulo, mostra o estado "dia livre" / "tudo em dia".
class ProximoCard extends StatefulWidget {
  const ProximoCard({
    super.key,
    required this.concluidos,
    required this.total,
    this.titulo,
    this.horario,
    this.subtitulo,
    this.categoria,
    this.atrasado = false,
    this.onConcluir,
    this.onEditar,
    this.onAbrirLink,
    this.onTap,
  });

  final String? titulo;

  /// Horário do item. Se for nulo (item sem hora), não há contagem regressiva.
  final DateTime? horario;

  /// Texto do "quando" (ex.: "Hoje às 09:00"). Se nulo, monta a partir do horário.
  final String? subtitulo;
  final String? categoria;

  /// Usado quando o item está atrasado mas não tem horário definido.
  final bool atrasado;
  final int concluidos;
  final int total;
  final VoidCallback? onConcluir;
  final VoidCallback? onEditar;
  final VoidCallback? onAbrirLink; // o botão de link só aparece se não for nulo
  final VoidCallback? onTap;

  @override
  State<ProximoCard> createState() => _ProximoCardState();
}

class _ProximoCardState extends State<ProximoCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Atualiza a contagem regressiva a cada 30 segundos.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  ({String texto, bool atrasado}) _contagem() {
    final h = widget.horario;
    if (h == null) {
      return (
        texto: widget.atrasado ? 'Atrasado' : 'Hoje',
        atrasado: widget.atrasado,
      );
    }
    final diff = h.difference(DateTime.now());
    final d = diff.abs();
    if (d.inMinutes < 1) return (texto: 'Agora', atrasado: false);

    final String t;
    if (d.inMinutes < 60) {
      t = '${d.inMinutes} min';
    } else if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      t = m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}min';
    } else {
      t = '${d.inDays} d';
    }
    return diff.isNegative
        ? (texto: 'há $t', atrasado: true)
        : (texto: 'em $t', atrasado: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final temItem = widget.titulo != null;

    return Material(
      color: c.cartao,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.borda),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: temItem ? _conteudoItem(context) : _conteudoVazio(context),
        ),
      ),
    );
  }

  Widget _conteudoItem(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final contagem = _contagem();
    final corChip = contagem.atrasado ? c.perigo : c.marca;
    final partes = <String>[
      widget.subtitulo ??
          (widget.horario != null ? 'Hoje às ${_hora(widget.horario!)}' : 'Hoje'),
      if (widget.categoria != null) widget.categoria!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              contagem.atrasado ? Icons.error_outline_rounded : Icons.schedule_rounded,
              size: 16,
              color: corChip,
            ),
            const SizedBox(width: 6),
            Text(
              contagem.atrasado ? 'ATRASADO' : 'PRÓXIMO',
              style: t.labelSmall?.copyWith(
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: c.suave,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: corChip.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                contagem.texto,
                style: t.labelMedium?.copyWith(
                  color: corChip,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          widget.titulo!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
        ),
        const SizedBox(height: 4),
        Text(
          partes.join(' · '),
          style: t.bodyMedium?.copyWith(color: c.suave),
        ),
        if (widget.total > 0) ...[
          const SizedBox(height: 16),
          _progresso(context),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.onConcluir,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Concluir'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size.fromHeight(46),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onEditar,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            if (widget.onAbrirLink != null) ...[
              const SizedBox(width: 10),
              IconButton.outlined(
                onPressed: widget.onAbrirLink,
                tooltip: 'Abrir link',
                icon: const Icon(Icons.link_rounded),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _conteudoVazio(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final semNada = widget.total == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              semNada ? Icons.wb_sunny_outlined : Icons.check_circle_rounded,
              color: c.marca,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                semNada ? 'Dia livre' : 'Tudo em dia',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          semNada
              ? 'Você não tem nada marcado para hoje.'
              : 'Você não tem mais itens pendentes para hoje.',
          style: t.bodyMedium?.copyWith(color: c.suave),
        ),
        if (!semNada) ...[
          const SizedBox(height: 16),
          _progresso(context),
        ],
      ],
    );
  }

  Widget _progresso(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final valor = widget.total == 0 ? 0.0 : widget.concluidos / widget.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: valor,
            minHeight: 6,
            color: c.marca,
            backgroundColor: c.suave.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.concluidos} de ${widget.total} concluídos hoje',
          style: t.labelMedium?.copyWith(color: c.suave),
        ),
      ],
    );
  }
}
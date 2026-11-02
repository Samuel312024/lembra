// Coloque em: lib/ui/widgets/filtro_chips.dart
//
// Faixa de filtros (Todos, Compromissos, Tarefas, Hábitos, Contas) que SEMPRE
// mostra os nomes por completo. Em vez de rolar para o lado e cortar o último
// chip, os chips quebram para a linha de baixo quando não cabem (inclusive
// quando o usuário aumenta o tamanho da fonte do celular).

import 'package:flutter/material.dart';

class FiltroChips<T> extends StatelessWidget {
  const FiltroChips({
    super.key,
    required this.opcoes,
    required this.selecionado,
    required this.rotulo,
    required this.aoSelecionar,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  /// Todas as opções, na ordem em que aparecem.
  final List<T> opcoes;

  /// Opção atualmente marcada.
  final T selecionado;

  /// Texto de cada chip.
  final String Function(T) rotulo;

  final ValueChanged<T> aoSelecionar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme.primary;

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in opcoes)
            Builder(builder: (context) {
              final marcado = o == selecionado;
              return ChoiceChip(
                label: Text(
                  rotulo(o),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
                selected: marcado,
                showCheckmark: false,
                onSelected: (_) => aoSelecionar(o),
                selectedColor: cor.withValues(alpha: 0.15),
                side: BorderSide(color: marcado ? cor : tema.dividerColor),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: marcado ? FontWeight.w600 : FontWeight.w500,
                  color: marcado ? cor : null,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }),
        ],
      ),
    );
  }
}
// Coloque em: lib/ui/renda_sheet.dart
//
// Folha para informar a renda mensal: CLT (salário líquido) ou PJ (empresa).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dinheiro.dart';
import '../domain/renda.dart';
import '../state/renda_provider.dart';
import 'theme/app_theme.dart';

Future<void> abrirConfiguracaoRenda(BuildContext context, WidgetRef ref) async {
  final atual = ref.read(rendaProvider).value;
  final novo = await showModalBottomSheet<PerfilRenda>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RendaForm(inicial: atual ?? const PerfilRenda()),
  );
  if (novo != null) await ref.read(rendaProvider.notifier).salvar(novo);
}

class RendaForm extends StatefulWidget {
  const RendaForm({super.key, required this.inicial});

  final PerfilRenda inicial;

  @override
  State<RendaForm> createState() => _RendaFormState();
}

class _RendaFormState extends State<RendaForm> {
  late TipoRenda _tipo = widget.inicial.tipo;
  late double _limite = widget.inicial.limitePct;

  late final _salario = TextEditingController(text: _txt(widget.inicial.salarioLiquido));
  late final _outras = TextEditingController(text: _txt(widget.inicial.outrasRendas));
  late final _fat = TextEditingController(text: _txt(widget.inicial.faturamento));
  late final _imp = TextEditingController(text: _txtPct(widget.inicial.impostoPct));
  late final _custos = TextEditingController(text: _txt(widget.inicial.custosEmpresa));

  static String _txt(double v) => v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');
  static String _txtPct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _salario.dispose();
    _outras.dispose();
    _fat.dispose();
    _imp.dispose();
    _custos.dispose();
    super.dispose();
  }

  PerfilRenda _montar() => PerfilRenda(
        tipo: _tipo,
        salarioLiquido: lerValor(_salario.text),
        outrasRendas: lerValor(_outras.text),
        faturamento: lerValor(_fat.text),
        impostoPct: lerValor(_imp.text).clamp(0, 100).toDouble(),
        custosEmpresa: lerValor(_custos.text),
        limitePct: _limite,
      );

  Widget _campo(TextEditingController c, String rotulo, {String? prefixo = 'R\$ ', String? sufixo, String? ajuda}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: rotulo, prefixText: prefixo, suffixText: sufixo, helperText: ajuda),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;
    final p = _montar();
    final pj = _tipo == TipoRenda.pj;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sua renda mensal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Usada só para comparar com as contas do mês. Fica salva apenas neste aparelho.',
              style: t.bodySmall?.copyWith(color: cores.suave),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TipoRenda>(
                segments: [
                  for (final tp in TipoRenda.values) ButtonSegment(value: tp, label: Text(tp.rotulo)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
            ),
            const SizedBox(height: 16),
            if (!pj)
              _campo(_salario, 'Salário líquido', ajuda: 'O valor que cai na sua conta')
            else ...[
              _campo(_fat, 'Faturamento mensal da empresa'),
              _campo(_imp, 'Imposto sobre o faturamento', prefixo: null, sufixo: '%', ajuda: 'Ex.: 6% no Simples Nacional'),
              _campo(_custos, 'Custos fixos da empresa por mês', ajuda: 'Contador, taxas, ferramentas...'),
            ],
            _campo(_outras, 'Outras rendas (opcional)'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cores.marca.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Renda considerada por mês', style: t.bodySmall?.copyWith(color: cores.suave)),
                  const SizedBox(height: 2),
                  Text(formatarReais(p.rendaMensal), style: AppText.mono(size: 20, color: cores.texto)),
                  if (pj) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Faturamento − impostos (${formatarReais(p.imposto)}) − custos da empresa.',
                      style: t.bodySmall?.copyWith(color: cores.suave),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Margem vermelha a partir de ${_limite.round()}% da renda',
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Slider(
              value: _limite,
              min: 40,
              max: 100,
              divisions: 12,
              label: '${_limite.round()}%',
              onChanged: (v) => setState(() => _limite = v),
            ),
            Text(
              'Quando as contas do mês passarem desse limite, a barra fica vermelha.',
              style: t.bodySmall?.copyWith(color: cores.suave),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: p.rendaMensal > 0 ? () => Navigator.of(context).pop(p) : null,
                child: const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
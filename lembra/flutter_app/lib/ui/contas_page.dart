// Coloque em: lib/ui/contas_page.dart
//
// Lista das contas em aberto, com o total em reais e filtro por tipo de conta.
// Abre ao tocar no card "Contas a vencer" da tela inicial.
//
// Novo: cartão "Contas do mês × renda" (CLT ou PJ) com margem vermelha e
// opção de salvar o relatório em PDF ou imagem.

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/categoria_conta.dart';
import '../domain/dinheiro.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../domain/renda.dart';
import '../services/relatorio_export.dart';
import '../state/providers.dart';
import '../state/renda_provider.dart';
import 'comparativo_renda_card.dart';
import 'conta_paga.dart';
import 'item_form_page.dart';
import 'item_tile.dart';
import 'relatorios_salvos_sheet.dart';
import 'renda_sheet.dart';
import 'resumo_contas.dart';
import 'resumo_mes_page.dart';
import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

class ContasPage extends ConsumerStatefulWidget {
  const ContasPage({super.key});

  @override
  ConsumerState<ContasPage> createState() => _ContasPageState();
}

class _ContasPageState extends ConsumerState<ContasPage> {
  CategoriaConta? _filtro;

  /// Marca o cartão de renda para tirar o "print" (imagem).
  final _capturaKey = GlobalKey();

  // >>> AJUSTE AQUI: nome do campo de data/vencimento do Item (aqui: `quando`).
  // É a única linha que depende de um campo que eu não vi no seu modelo.
  DateTime? _dataDe(Item i) => i.ancora;

  /// Contas em aberto que vencem até o fim do mês atual (inclui as já vencidas).
  List<Item> _contasDoMes(Iterable<Item> abertas, DateTime agora) {
    final fimDoMes = DateTime(agora.year, agora.month + 1, 1);
    return [
      for (final i in abertas)
        if (_dataDe(i) case final d? when d.isBefore(fimDoMes)) i,
    ];
  }

  Future<void> _nova() async {
    final d = await Navigator.of(context).push<Draft>(
      MaterialPageRoute(
        builder: (_) => ItemFormPage(
          rascunho: Draft(tipo: TipoItem.conta, titulo: '', origem: Origem.texto),
          titulo: 'Nova conta',
        ),
      ),
    );
    if (d != null) await ref.read(itemsProvider.notifier).criar(d);
  }

  Future<void> _editar(Item item) async {
    final d = await Navigator.of(context).push<Draft>(
      MaterialPageRoute(builder: (_) => ItemFormPage(rascunho: Draft.deItem(item), titulo: 'Editar lembrete')),
    );
    if (d != null) await ref.read(itemsProvider.notifier).atualizarDe(item.id, d);
  }

  Future<void> _concluir(Item item) async {
    final antes = await ref.read(itemsProvider.notifier).concluir(item.id);
    if (!mounted) return;
    avisarConcluido(context, ref, item, antes);
  }

  Future<void> _cancelar(Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(itemsProvider.notifier);
    final antes = await notifier.cancelar(item.id);
    messenger.showSnackBar(SnackBar(
      content: Text('“${item.titulo}” cancelada.'),
      action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
    ));
  }

  Future<void> _exportar(FormatoRelatorio formato, DadosRelatorio dados) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final File arquivo;
      if (formato == FormatoRelatorio.pdf) {
        arquivo = await RelatorioExport.salvarPdf(dados);
      } else {
        final png = await RelatorioExport.capturarPng(_capturaKey);
        if (png == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Role até o cartão de renda e tente de novo.')),
          );
          return;
        }
        arquivo = await RelatorioExport.salvarImagem(dados, png);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(formato == FormatoRelatorio.pdf ? 'PDF salvo em “Salvos”.' : 'Imagem salva em “Salvos”.'),
        action: SnackBarAction(label: 'Compartilhar', onPressed: () => RelatorioExport.compartilhar(arquivo)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  ItemTile _tile(Item i) => ItemTile(
        key: ValueKey('conta-${i.id}'),
        item: i,
        onTap: () => _editar(i),
        onConcluir: () => _concluir(i),
        onCancelar: () => _cancelar(i),
      );

  Widget _secao(String titulo, List<Item> lista, {Color? corTotal}) {
    final total = ResumoContas.somaDe(lista);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          SectionHeader(titulo, count: lista.length),
          const Spacer(),
          if (total > 0)
            Text(formatarReais(total), style: AppText.mono(size: 13, color: corTotal ?? context.cores.suave)),
        ],
      ),
    );
  }

  Widget _mini(String rotulo, double valor, Color cor) {
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
            child: Text(formatarReais(valor), style: AppText.mono(size: 14, color: cor)),
          ),
        ],
      ),
    );
  }

  Widget _resumo(ResumoContas r) {
    final t = Theme.of(context).textTheme;
    final qtd = r.quantidade;
    final venc = r.vencidas.length;

    final String legenda;
    if (qtd == 0) {
      legenda = 'Nenhuma conta em aberto';
    } else {
      final partes = <String>[
        qtd == 1 ? '1 conta em aberto' : '$qtd contas em aberto',
        if (venc > 0) (venc == 1 ? '1 vencida' : '$venc vencidas'),
        if (r.temValor && r.semValor > 0) '${r.semValor} sem valor',
      ];
      legenda = partes.join(' • ');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.account_balance_wallet_rounded, color: AppColors.yellow, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Total em aberto', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatarReais(r.total),
                style: AppText.mono(size: 32, color: venc > 0 ? context.cores.perigo : context.cores.texto),
              ),
            ),
            const SizedBox(height: 4),
            Text(legenda, style: t.bodySmall?.copyWith(color: context.cores.suave)),
            if (!r.temValor && qtd > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Toque em uma conta e informe o valor para ver o total.',
                style: t.bodySmall?.copyWith(color: context.cores.suave),
              ),
            ],
            if (r.temValor) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: context.cores.borda),
              const SizedBox(height: 12),
              Row(
                children: [
                  _mini('Vencidas', r.totalVencidas, r.totalVencidas > 0 ? context.cores.perigo : context.cores.texto),
                  const SizedBox(width: 12),
                  _mini('Próximos 7 dias', r.totalProximas, context.cores.texto),
                  const SizedBox(width: 12),
                  _mini('Depois', r.totalDepois, context.cores.texto),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _acao(IconData icone, String rotulo, VoidCallback aoTocar) => ActionChip(
        avatar: Icon(icone, size: 18, color: context.cores.marca),
        label: Text(rotulo),
        onPressed: aoTocar,
        shape: const StadiumBorder(),
        backgroundColor: context.cores.cartao,
        side: BorderSide(color: context.cores.borda),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: context.cores.texto),
      );

  /// Cartão "Contas do mês × renda" + ações (editar renda, PDF, imagem, salvos).
  Widget _comparativo(PerfilRenda? perfil, double gasto, List<Item> doMes, DateTime agora) {
    final dados = (perfil == null || perfil.rendaMensal <= 0)
        ? null
        : DadosRelatorio(
            mes: agora,
            perfil: perfil,
            gasto: gasto,
            linhas: [
              for (final i in doMes)
                LinhaRelatorio(
                  titulo: i.titulo,
                  tipo: i.categoria?.rotulo,
                  data: _dataDe(i),
                  valor: ResumoContas.somaDe([i]),
                ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tudo que está dentro do RepaintBoundary vira a imagem salva.
          RepaintBoundary(
            key: _capturaKey,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ComparativoRendaCard(perfil: perfil, gasto: gasto, mes: agora),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _acao(
                  Icons.tune_rounded,
                  dados == null ? 'Informar renda' : 'Editar renda',
                  () => abrirConfiguracaoRenda(context, ref),
                ),
                if (dados != null) ...[
                  _acao(Icons.picture_as_pdf_outlined, 'Salvar PDF', () => _exportar(FormatoRelatorio.pdf, dados)),
                  _acao(Icons.image_outlined, 'Salvar imagem', () => _exportar(FormatoRelatorio.imagem, dados)),
                ],
                _acao(Icons.folder_open_rounded, 'Salvos', () => abrirRelatoriosSalvos(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String rotulo, bool selecionado, VoidCallback aoTocar) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(rotulo),
          selected: selecionado,
          onSelected: (_) => aoTocar(),
          showCheckmark: false,
          shape: const StadiumBorder(),
          backgroundColor: context.cores.cartao,
          selectedColor: context.cores.marca.withValues(alpha: 0.14),
          side: BorderSide(color: selecionado ? context.cores.marca : context.cores.borda),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: selecionado ? context.cores.marca : context.cores.texto,
          ),
        ),
      );

  Widget _vazio(bool comFiltro) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
      child: Column(
        children: [
          const IconBadge(icon: Icons.receipt_long_outlined, color: AppColors.yellow, size: 72),
          const SizedBox(height: 16),
          Text(
            comFiltro ? 'Nenhuma conta deste tipo' : 'Nenhuma conta em aberto',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            comFiltro
                ? 'Escolha outro tipo ou toque em “Todas”.'
                : 'Toque em “Nova conta” ou diga, por exemplo:\n“Conta de luz de 150 reais dia 10”.',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: context.cores.suave),
          ),
        ],
      ),
    );
  }

  Widget _corpo(List<Item> lista) {
    final agora = DateTime.now();
    final todas = ResumoContas.de(lista, agora);

    // Comparativo com a renda: considera todas as contas do mês, sem filtro de tipo.
    final rendaAsync = ref.watch(rendaProvider);
    final perfil = rendaAsync.value;
    final doMes = _contasDoMes(todas.abertas, agora);
    final gastoMes = ResumoContas.somaDe(doMes);

    // Só oferece filtro para os tipos que existem entre as contas em aberto.
    final tipos = <CategoriaConta>{
      for (final i in todas.abertas)
        if (i.categoria != null) i.categoria!,
    }.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    // Se a última conta do tipo filtrado foi paga, volta para "Todas".
    final filtro = tipos.contains(_filtro) ? _filtro : null;
    final r = filtro == null ? todas : ResumoContas.de(lista, agora, categoria: filtro);

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _resumo(r),
        if (!rendaAsync.isLoading) _comparativo(perfil, gastoMes, doMes, agora),
        if (tipos.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _chip('Todas', filtro == null, () => setState(() => _filtro = null)),
                for (final c in tipos)
                  _chip(c.rotulo, filtro == c, () => setState(() => _filtro = filtro == c ? null : c)),
              ],
            ),
          ),
        if (r.quantidade == 0) _vazio(filtro != null),
        if (r.vencidas.isNotEmpty) ...[
          _secao('Vencidas', r.vencidas, corTotal: context.cores.perigo),
          ...r.vencidas.map(_tile),
        ],
        if (r.proximas.isNotEmpty) ...[
          _secao('Próximos 7 dias', r.proximas),
          ...r.proximas.map(_tile),
        ],
        if (r.depois.isNotEmpty) ...[
          _secao('Mais adiante', r.depois),
          ...r.depois.map(_tile),
        ],
        if (r.semData.isNotEmpty) ...[
          _secao('Sem data', r.semData),
          ...r.semData.map(_tile),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = ref.watch(itemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas a pagar'),
        actions: [
          IconButton(
            tooltip: 'Resumo do mês',
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResumoMesPage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      body: itens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar: $e')),
        data: _corpo,
      ),
    );
  }
}
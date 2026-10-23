import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/dinheiro.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'contas_page.dart';
import 'item_form_page.dart';
import 'item_tile.dart';
import 'resumo_contas.dart';
import 'review_page.dart';
import 'settings_page.dart';
import 'theme/app_theme.dart';
import 'voice_flow.dart';
import 'widgets/ui_kit.dart';

/// Tela "Hoje" (home) com a aba "Próximos" e filtro por tipo.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  TipoItem? _filtro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _aoIniciar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) {
      ref.read(itemsProvider.notifier).aoRetomar();
    }
  }

  Future<void> _aoIniciar() async {
    final notif = NotificationService.instance;
    final cfg = ref.read(configProvider);
    await notif.atualizarRotinas(
      briefing: cfg.briefing,
      briefingMin: cfg.briefingMin,
      revisao: cfg.revisao,
      revisaoMin: cfg.revisaoMin,
    );
    await ref.read(itemsProvider.notifier).aoRetomar();
    await notif.verificarLancamento();
    if (mounted) await _permissoesGuiadas();
  }

  /// Na primeira abertura, explica por que as permissões são necessárias antes de pedir.
  Future<void> _permissoesGuiadas() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.getBool('permissoes_pedidas') ?? false) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Vamos configurar os alarmes'),
        content: const Text(
          'O Lembra precisa de permissão para enviar notificações, tocar alarmes no minuto certo e '
          'mostrar o alarme crítico em tela cheia. Sem isso, um lembrete pode falhar justamente quando você precisa.\n\n'
          'O microfone só é usado quando você toca no botão de falar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Depois')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Permitir')),
        ],
      ),
    );
    await prefs.setBool('permissoes_pedidas', true);
    if (ok == true) await NotificationService.instance.pedirPermissoes();
  }

  Future<void> _novoManual() async {
    final d = await Navigator.of(context).push<Draft>(MaterialPageRoute(builder: (_) => const ItemFormPage()));
    if (d != null) await ref.read(itemsProvider.notifier).criar(d);
  }

  Future<void> _editar(Item item) async {
    final d = await Navigator.of(context).push<Draft>(
      MaterialPageRoute(builder: (_) => ItemFormPage(rascunho: Draft.deItem(item), titulo: 'Editar lembrete')),
    );
    if (d != null) await ref.read(itemsProvider.notifier).atualizarDe(item.id, d);
  }

  Future<void> _concluir(Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(itemsProvider.notifier);
    final antes = await notifier.concluir(item.id);
    messenger.showSnackBar(SnackBar(
      content: Text('“${item.titulo}” concluído.'),
      action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
    ));
  }

  Future<void> _cancelar(Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(itemsProvider.notifier);
    final antes = await notifier.cancelar(item.id);
    messenger.showSnackBar(SnackBar(
      content: Text('“${item.titulo}” cancelado.'),
      action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
    ));
  }

  void _lerDia() {
    final itens = ref.read(itemsProvider).valueOrNull ?? [];
    final agora = DateTime.now();
    ref.read(ttsProvider).falar(textoResumo(itens, agora, agora));
  }

  ItemTile _tile(Item i, {bool feito = false}) => ItemTile(
        key: ValueKey('${i.id}-$feito'),
        item: i,
        feito: feito,
        onTap: () => _editar(i),
        onConcluir: () => _concluir(i),
        onCancelar: () => _cancelar(i),
      );

  // -------------------------------------------------------------------------
  // Visual
  // -------------------------------------------------------------------------

  String _saudacao() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _dataHoje() => DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now());

  Widget _acao(IconData icone, String dica, VoidCallback aoTocar) => IconButton.filled(
        tooltip: dica,
        onPressed: aoTocar,
        icon: Icon(icone, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.cream,
          foregroundColor: AppColors.ink,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _chip(String rotulo, bool selecionado, VoidCallback aoTocar) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(rotulo),
          selected: selecionado,
          onSelected: (_) => aoTocar(),
          showCheckmark: false,
          shape: const StadiumBorder(),
          backgroundColor: Colors.white,
          selectedColor: AppColors.brand.withValues(alpha: 0.14),
          side: BorderSide(color: selecionado ? AppColors.brand : AppColors.cardBorder),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: selecionado ? AppColors.brand : AppColors.ink,
          ),
        ),
      );

  Widget _secao(String titulo, int quantidade) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: SectionHeader(titulo, count: quantidade),
      );

  Widget _vazio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(icon: Icons.mic_none_rounded, color: AppColors.orange, size: 72),
              const SizedBox(height: 16),
              Text(
                'Nada por aqui',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque em “Falar agora” e diga, por exemplo:\n“Tenho médico dia 22 às 14h30”.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );

  Widget _semResultadoNoFiltro() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: Center(
          child: Text(
            'Nenhum item deste tipo hoje.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
      );

  /// Próximo item com horário definido, olhando hoje e os dias seguintes.
  Item? _proximoAlarme(List<Item> itens, DateTime agora) {
    final hoje = agruparHoje(itens, agora);
    final prox = agruparProximos(itens, agora);
    final candidatos = <Item>[
      ...hoje.hoje,
      for (final lista in prox.porDia.values) ...lista,
    ].where((i) {
      final a = i.ancora;
      return a != null && a.isAfter(agora) && (a.hour != 0 || a.minute != 0);
    });

    Item? melhor;
    for (final i in candidatos) {
      if (melhor == null || i.ancora!.isBefore(melhor.ancora!)) melhor = i;
    }
    return melhor;
  }

  /// Itens vencidos ou críticos que merecem atenção agora.
  List<Item> _criticosProximos(List<Item> itens, DateTime agora) {
    final limite = agora.add(const Duration(hours: 24));
    final lista = itens.where((i) {
      final a = i.ancora;
      return i.status == StatusItem.ativo &&
          i.urgencia == Urgencia.critico &&
          a != null &&
          a.isAfter(agora) &&
          a.isBefore(limite);
    }).toList();
    lista.sort((x, y) => x.ancora!.compareTo(y.ancora!));
    return lista;
  }

  bool _temAlerta(List<Item> itens) {
    final agora = DateTime.now();
    return agruparHoje(itens, agora).atrasados.isNotEmpty || _criticosProximos(itens, agora).isNotEmpty;
  }

  /// Sino do topo: bolinha vermelha quando há atrasados ou críticos nas próximas 24 h.
  Widget _sino(bool alerta) => Stack(
        clipBehavior: Clip.none,
        children: [
          _acao(Icons.notifications_none_rounded, 'Precisa de atenção', _abrirAtencao),
          if (alerta)
            Positioned(
              right: 6,
              top: 6,
              child: IgnorePointer(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cream, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      );

  void _abrirAtencao() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Consumer(
        builder: (ctx, r, _) {
          final lista = r.watch(itemsProvider).valueOrNull ?? const <Item>[];
          final agora = DateTime.now();
          final atrasados = agruparHoje(lista, agora).atrasados;
          final criticos = _criticosProximos(lista, agora);
          final t = Theme.of(ctx).textTheme;

          Widget tile(Item i) => ItemTile(
                key: ValueKey('atencao-${i.id}'),
                item: i,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _editar(i);
                },
                onConcluir: () => _concluir(i),
                onCancelar: () => _cancelar(i),
              );

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Precisa de atenção',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (atrasados.isEmpty && criticos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                    child: Column(
                      children: [
                        const IconBadge(icon: Icons.check_rounded, color: AppColors.green, size: 64),
                        const SizedBox(height: 16),
                        Text('Tudo em dia', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          'Nada atrasado e nenhum alarme crítico nas próximas 24 horas.',
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                if (atrasados.isNotEmpty) ...[
                  _secao('Atrasados', atrasados.length),
                  ...atrasados.map(tile),
                ],
                if (criticos.isNotEmpty) ...[
                  _secao('Críticos nas próximas 24 h', criticos.length),
                  ...criticos.map(tile),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Card "Contas a vencer": soma dos valores das contas em aberto (vencidas e
  /// futuras). Tocar abre a lista de contas.
  Widget _cardContas(List<Item> itens, DateTime agora) {
    final r = ResumoContas.de(itens, agora);
    final qtd = r.quantidade;
    final venc = r.vencidas.length;
    final vencidas = venc == 1 ? '1 vencida' : '$venc vencidas';

    final String valor;
    final String legenda;
    if (qtd == 0) {
      valor = formatarReais(0);
      legenda = 'Nenhuma conta em aberto';
    } else if (!r.temValor) {
      valor = '$qtd';
      legenda = [
        qtd == 1 ? 'conta sem valor informado' : 'contas sem valor informado',
        if (venc > 0) vencidas,
      ].join(' • ');
    } else {
      valor = formatarReais(r.total);
      legenda = [
        qtd == 1 ? '1 conta' : '$qtd contas',
        if (venc > 0) vencidas,
        if (r.semValor > 0) '${r.semValor} sem valor',
      ].join(' • ');
    }

    return StatCard(
      icon: Icons.account_balance_wallet_rounded,
      iconColor: AppColors.yellow,
      label: 'Contas a vencer',
      value: valor,
      valueColor: venc > 0 ? const Color(0xFFDC2626) : AppColors.cyanDeep,
      caption: legenda,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContasPage())),
    );
  }

  Widget _resumoDoDia(List<Item> itens, DateTime agora) {
    final todos = agruparHoje(itens, agora);
    final feitos = todos.feitos.length;
    final atrasados = todos.atrasados.length;
    final pendentes = atrasados + todos.hoje.length;
    final total = pendentes + feitos;
    final progresso = total == 0 ? 0.0 : feitos / total;
    final titulo = atrasados > 0
        ? 'Há itens atrasados'
        : (feitos == total ? 'Dia concluído' : 'Dia sob controle');

    final proximo = _proximoAlarme(itens, agora);
    final quando = proximo?.ancora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          DayGauge(progress: progresso, done: feitos, total: total, title: titulo),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.alarm_rounded,
                    iconColor: AppColors.orange,
                    label: proximo?.titulo ?? 'Próximo alarme',
                    value: quando == null ? '--:--' : DateFormat.Hm('pt_BR').format(quando),
                    valueColor: AppColors.brand,
                    caption: quando == null
                        ? 'Nenhum alarme à frente'
                        : 'Próximo alarme • ${quandoCurto(quando, comHora: false, agora: agora)}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _cardContas(itens, agora)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _abaHoje(List<Item> itens) {
    final agora = DateTime.now();
    final todos = agruparHoje(itens, agora);
    if (todos.vazio) return _vazio();

    final g = _filtro == null ? todos : agruparHoje(itens, agora, filtro: _filtro);

    return ListView(
      padding: const EdgeInsets.only(bottom: 200),
      children: [
        _resumoDoDia(itens, agora),
        if (g.vazio) _semResultadoNoFiltro(),
        if (g.atrasados.isNotEmpty) ...[
          _secao('Atrasados', g.atrasados.length),
          ...g.atrasados.map(_tile),
        ],
        if (g.hoje.isNotEmpty) ...[
          _secao('Hoje', g.hoje.length),
          ...g.hoje.map(_tile),
        ],
        if (g.feitos.isNotEmpty) ...[
          _secao('Feitos hoje', g.feitos.length),
          ...g.feitos.map((i) => _tile(i, feito: true)),
        ],
      ],
    );
  }

  Widget _abaProximos(List<Item> itens) {
    final g = agruparProximos(itens, DateTime.now(), filtro: _filtro);
    if (g.vazio) return _vazio();
    final agora = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 200),
      children: [
        for (final e in g.porDia.entries) ...[
          _secao(
            toBeginningOfSentenceCase(quandoCurto(e.key, comHora: false, agora: agora)) ?? '',
            e.value.length,
          ),
          ...e.value.map(_tile),
        ],
        if (g.semData.isNotEmpty) ...[
          _secao('Sem data', g.semData.length),
          ...g.semData.map(_tile),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = ref.watch(itemsProvider);
    final t = Theme.of(context).textTheme;
    final alerta = _temAlerta(itens.valueOrNull ?? const <Item>[]);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: Column(
            children: [
              HeroPanel(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _saudacao(),
                                style: t.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.onDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _dataHoje(),
                                style: t.bodySmall?.copyWith(color: AppColors.onDarkMuted),
                              ),
                            ],
                          ),
                        ),
                        _sino(alerta),
                        _acao(Icons.volume_up_outlined, 'Ouvir o resumo do dia', _lerDia),
                        _acao(
                          Icons.fact_check_outlined,
                          'Revisão do dia',
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewPage())),
                        ),
                        _acao(
                          Icons.settings_outlined,
                          'Ajustes',
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.only(right: 24),
                      dividerColor: Colors.transparent,
                      indicatorColor: AppColors.brandSoft,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: AppColors.onDark,
                      unselectedLabelColor: AppColors.onDarkMuted,
                      labelStyle: TextStyle(fontWeight: FontWeight.w700),
                      tabs: [Tab(text: 'Hoje'), Tab(text: 'Próximos')],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: [
                    _chip('Todos', _filtro == null, () => setState(() => _filtro = null)),
                    for (final tipo in TipoItem.values)
                      _chip(
                        tipo.rotulo,
                        _filtro == tipo,
                        () => setState(() => _filtro = _filtro == tipo ? null : tipo),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: itens.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erro ao carregar: $e')),
                  data: (lista) => TabBarView(children: [_abaHoje(lista), _abaProximos(lista)]),
                ),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'manual',
                tooltip: 'Adicionar digitando',
                onPressed: _novoManual,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brand,
                elevation: 1,
                child: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(height: 12),
              VoiceFab(onPressed: () => iniciarVoz(context, ref)),
            ],
          ),
        ),
      ),
    );
  }
}

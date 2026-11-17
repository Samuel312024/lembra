// Coloque em: lib/ui/reuniao_form_sheet.dart
//
// Folha para AGENDAR e para EDITAR uma reunião.
//  - detecta conflito de horário e sugere o próximo horário livre do dia;
//  - convidados com nome + WhatsApp ou e-mail, com atalho para quem já foi convidado antes;
//  - ao criar: grava no calendário do celular e no histórico do Lembra;
//  - ao editar: atualiza o calendário e o histórico; se o horário mudou e já havia
//    respostas, pergunta se deve zerá-las para pedir nova confirmação.

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../domain/agendamento.dart';
import '../services/calendario_service.dart';
import '../services/evento_calendario.dart';
import '../state/agendamentos_provider.dart';
import 'theme/app_theme.dart';

/// Faixa de horário já ocupada (usada para avisar conflito).
class Intervalo {
  const Intervalo({required this.titulo, required this.inicio, required this.fim});

  final String titulo;
  final DateTime inicio;
  final DateTime fim;

  bool sobrepoe(DateTime i, DateTime f) => inicio.isBefore(f) && fim.isAfter(i);
}

/// O que a folha devolve quando o usuário salva.
class ResultadoReuniao {
  const ResultadoReuniao({required this.agendamento, required this.criada, required this.calendarioOk});

  final Agendamento agendamento;
  final bool criada;

  /// Falso quando o Lembra salvou, mas não conseguiu atualizar o evento no calendário.
  final bool calendarioOk;
}

String nomeCalendario(Calendar c) {
  final nome = c.name ?? 'Calendário';
  final conta = c.accountName;
  if (conta == null || conta.isEmpty || conta == nome) return nome;
  return '$nome · $conta';
}

String _rotuloDuracao(int m) {
  if (m < 60) return '$m min';
  if (m % 60 == 0) return '${m ~/ 60} h';
  return '${m ~/ 60} h ${m % 60}';
}

String _nomePeloContato(String contato) {
  final i = contato.indexOf('@');
  return i > 0 ? contato.substring(0, i) : contato;
}

class _LinhaConvidado {
  _LinhaConvidado({String? id, String nome = '', String contato = ''})
      : id = id ?? const Uuid().v4(),
        nomeCtrl = TextEditingController(text: nome),
        contatoCtrl = TextEditingController(text: contato);

  final String id;
  final TextEditingController nomeCtrl;
  final TextEditingController contatoCtrl;

  void dispose() {
    nomeCtrl.dispose();
    contatoCtrl.dispose();
  }
}

class FolhaReuniao extends ConsumerStatefulWidget {
  const FolhaReuniao({
    super.key,
    required this.servico,
    this.calendarios = const [],
    this.existente,
    this.ocupados = const [],
    this.sugestoes = const [],
  });

  final CalendarioService servico;

  /// Calendários editáveis (só para criar).
  final List<Calendar> calendarios;

  /// Reunião sendo editada. null = nova reunião.
  final Agendamento? existente;

  /// Horários já ocupados, para o aviso de conflito.
  final List<Intervalo> ocupados;

  /// Pessoas já convidadas antes.
  final List<Convidado> sugestoes;

  @override
  ConsumerState<FolhaReuniao> createState() => _FolhaReuniaoState();
}

class _FolhaReuniaoState extends ConsumerState<FolhaReuniao> {
  static const _duracoesPadrao = [30, 45, 60, 90, 120];

  final _titulo = TextEditingController();
  final _linkOuLocal = TextEditingController();
  final _linhas = <_LinhaConvidado>[];
  late DateTime _data;
  late TimeOfDay _hora;
  Calendar? _calendario;
  int _duracaoMin = 60;
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _titulo.text = e.titulo;
      _linkOuLocal.text = e.linkOuLocal ?? '';
      _data = DateTime(e.inicio.year, e.inicio.month, e.inicio.day);
      _hora = TimeOfDay(hour: e.inicio.hour, minute: e.inicio.minute);
      final d = e.fim.difference(e.inicio).inMinutes;
      _duracaoMin = d > 0 ? d : 60;
      for (final c in e.convidados) {
        _linhas.add(_LinhaConvidado(id: c.id, nome: c.nome, contato: c.contato));
      }
    } else {
      final agora = DateTime.now();
      // Sugere a próxima meia hora cheia.
      final proxima = agora.add(Duration(minutes: 30 - agora.minute % 30));
      _data = DateTime(proxima.year, proxima.month, proxima.day);
      _hora = TimeOfDay(hour: proxima.hour, minute: proxima.minute);
      if (widget.calendarios.isNotEmpty) _calendario = widget.calendarios.first;
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    _linkOuLocal.dispose();
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  DateTime get _inicio => DateTime(_data.year, _data.month, _data.day, _hora.hour, _hora.minute);

  DateTime get _fim => _inicio.add(Duration(minutes: _duracaoMin));

  // -------------------------------------------------------------------------
  // Conflito de horário
  // -------------------------------------------------------------------------

  Intervalo? get _conflito {
    final i = _inicio;
    final f = _fim;
    for (final o in widget.ocupados) {
      if (o.sobrepoe(i, f)) return o;
    }
    return null;
  }

  /// Próximo horário (de 15 em 15 min, até as 20h do mesmo dia) sem conflito.
  DateTime? _proximoHorarioLivre() {
    final dur = Duration(minutes: _duracaoMin);
    final limite = DateTime(_data.year, _data.month, _data.day, 20);
    var t = _inicio.add(const Duration(minutes: 15));
    while (!t.isAfter(limite)) {
      final fim = t.add(dur);
      if (!widget.ocupados.any((o) => o.sobrepoe(t, fim))) return t;
      t = t.add(const Duration(minutes: 15));
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Visual
  // -------------------------------------------------------------------------

  InputDecoration _decoracao(String rotulo, {String? ajuda}) {
    final c = context.cores;
    return InputDecoration(
      labelText: rotulo,
      helperText: ajuda,
      helperMaxLines: 2,
      filled: true,
      fillColor: c.cartao,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.borda),
      ),
    );
  }

  /// Chip de escolha (duração e calendário), no mesmo estilo dos filtros da home.
  Widget _opcao(String rotulo, bool selecionado, VoidCallback aoTocar) {
    final c = context.cores;
    return ChoiceChip(
      label: Text(rotulo),
      selected: selecionado,
      showCheckmark: false,
      onSelected: (_) => aoTocar(),
      shape: const StadiumBorder(),
      backgroundColor: c.cartao,
      selectedColor: c.marca.withValues(alpha: 0.18),
      side: BorderSide(color: selecionado ? c.marca : c.borda),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selecionado ? c.marca : c.texto,
      ),
    );
  }

  Widget _avisoConflito() {
    final o = _conflito;
    if (o == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final hm = DateFormat.Hm('pt_BR');
    final livre = _proximoHorarioLivre();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conflito de horário', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Você já tem “${o.titulo}” das ${hm.format(o.inicio)} às ${hm.format(o.fim)}.',
                    style: t.bodySmall?.copyWith(color: context.cores.suave),
                  ),
                  if (livre != null)
                    TextButton(
                      onPressed: () => setState(() => _hora = TimeOfDay.fromDateTime(livre)),
                      style: TextButton.styleFrom(
                        foregroundColor: context.cores.marca,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerLeft,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: Text('Usar ${hm.format(livre)}, que está livre'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoConvidado(_LinhaConvidado l) {
    final c = context.cores;
    return Container(
      key: ValueKey(l.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: c.cartao,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.borda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: l.nomeCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoracao('Nome'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: l.contatoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoracao('WhatsApp ou e-mail'),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover convidado',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              setState(() => _linhas.remove(l));
              // Descarta os controladores só depois que o frame tirar os campos da tela.
              WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
            },
          ),
        ],
      ),
    );
  }

  Widget _secaoConvidados() {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;
    final jaTem = {for (final l in _linhas) l.contatoCtrl.text.trim().toLowerCase()};
    final sugestoes = [
      for (final s in widget.sugestoes)
        if (!jaTem.contains(s.contato.trim().toLowerCase())) s,
    ].take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Convidados', style: t.labelMedium?.copyWith(color: cores.suave)),
        const SizedBox(height: 6),
        for (final l in _linhas) _cartaoConvidado(l),
        if (sugestoes.isNotEmpty) ...[
          Text('Convidar de novo', style: t.labelSmall?.copyWith(color: cores.suave)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final s in sugestoes)
                ActionChip(
                  avatar: Icon(Icons.person_add_alt_1_rounded, size: 16, color: cores.marca),
                  label: Text(s.nome),
                  shape: const StadiumBorder(),
                  backgroundColor: cores.cartao,
                  side: BorderSide(color: cores.borda),
                  onPressed: () => setState(() => _linhas.add(_LinhaConvidado(nome: s.nome, contato: s.contato))),
                ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _linhas.add(_LinhaConvidado())),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Adicionar convidado'),
            style: TextButton.styleFrom(foregroundColor: cores.marca),
          ),
        ),
        Text(
          'E-mail: o convite sai pelo Google Agenda e a resposta chega sozinha (escolha um calendário da sua conta Google). '
          'WhatsApp: você registra a resposta no cartão da reunião.',
          style: t.bodySmall?.copyWith(color: cores.suave),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Ações
  // -------------------------------------------------------------------------

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      // Ao editar uma reunião passada, o seletor precisa aceitar a data atual dela.
      firstDate: _data.isBefore(inicioHoje) ? _data : inicioHoje,
      lastDate: DateTime(hoje.year + 2, hoje.month, hoje.day),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _escolherHora() async {
    final h = await showTimePicker(context: context, initialTime: _hora);
    if (h != null) setState(() => _hora = h);
  }

  /// Lê as linhas de convidados. Retorna null (e mostra o erro) se algo estiver inválido.
  List<Convidado>? _coletarConvidados() {
    final antigos = {for (final c in widget.existente?.convidados ?? const <Convidado>[]) c.id: c};
    final resultado = <Convidado>[];
    for (final l in _linhas) {
      final nome = l.nomeCtrl.text.trim();
      final contato = l.contatoCtrl.text.trim();
      if (nome.isEmpty && contato.isEmpty) continue;
      if (contato.isEmpty) {
        setState(() => _erro = 'Informe o WhatsApp ou e-mail de $nome.');
        return null;
      }
      if (!contatoValido(contato)) {
        setState(() => _erro = 'Contato inválido: $contato');
        return null;
      }
      // Se o contato não mudou, mantém a resposta já registrada.
      final antigo = antigos[l.id];
      final base = (antigo != null && antigo.contato.trim().toLowerCase() == contato.toLowerCase()) ? antigo : null;
      resultado.add(Convidado(
        id: l.id,
        nome: nome.isEmpty ? _nomePeloContato(contato) : nome,
        contato: contato,
        resposta: base?.resposta ?? RespostaConvite.pendente,
        conviteEnviadoEm: base?.conviteEnviadoEm,
        respondidoEm: base?.respondidoEm,
      ));
    }
    return resultado;
  }

  Future<void> _salvar() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      setState(() => _erro = 'Dê um título para a reunião.');
      return;
    }
    final convidados = _coletarConvidados();
    if (convidados == null) return;

    final inicio = _inicio;
    final fim = _fim;
    final antiga = widget.existente;
    final horarioMudou = antiga == null || antiga.inicio != inicio || antiga.fim != fim;
    if (horarioMudou && inicio.isBefore(DateTime.now())) {
      setState(() => _erro = 'Escolha um horário no futuro.');
      return;
    }
    setState(() => _erro = null);

    if (antiga == null) {
      await _criar(titulo, inicio, fim, convidados);
    } else {
      await _atualizar(antiga, titulo, inicio, fim, convidados, horarioMudou);
    }
  }

  Future<void> _criar(String titulo, DateTime inicio, DateTime fim, List<Convidado> convidados) async {
    final cal = _calendario;
    if (cal == null || cal.id == null) {
      setState(() => _erro = 'Nenhum calendário disponível.');
      return;
    }

    final hm = DateFormat.Hm('pt_BR');
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reunião'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(inicio)) ?? ''),
            Text('${hm.format(inicio)} – ${hm.format(fim)}'),
            if (convidados.isNotEmpty) Text('Convidados: ${convidados.length}'),
            Text('Calendário: ${nomeCalendario(cal)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Agendar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _salvando = true);
    final texto = _linkOuLocal.text.trim();
    final emails = [
      for (final c in convidados)
        if (c.canal == CanalConvite.email) c.contato.trim(),
    ];
    final eventoId = await widget.servico.criarReuniao(
      calendarioId: cal.id!,
      titulo: titulo,
      inicio: inicio,
      fim: fim,
      descricao: texto.isEmpty ? null : texto,
      local: texto.isEmpty ? null : texto,
      participantes: emails,
    );
    if (!mounted) return;

    if (eventoId == null) {
      setState(() {
        _salvando = false;
        _erro = 'Não foi possível salvar no calendário. Tente escolher outro calendário.';
      });
      return;
    }

    final agora = DateTime.now();
    final registro = Agendamento(
      id: const Uuid().v4(),
      eventoId: eventoId,
      calendarioId: cal.id,
      calendarioNome: nomeCalendario(cal),
      titulo: titulo,
      inicio: inicio,
      fim: fim,
      linkOuLocal: texto.isEmpty ? null : texto,
      convidados: convidados,
      criadoEm: agora,
      atualizadoEm: agora,
    );
    await ref.read(agendamentosProvider.notifier).adicionar(registro);
    if (!mounted) return;
    Navigator.of(context).pop(ResultadoReuniao(agendamento: registro, criada: true, calendarioOk: true));
  }

  Future<void> _atualizar(
    Agendamento antiga,
    String titulo,
    DateTime inicio,
    DateTime fim,
    List<Convidado> convidados,
    bool horarioMudou,
  ) async {
    final texto = _linkOuLocal.text.trim();
    final novo = antiga.copiar()
      ..titulo = titulo
      ..inicio = inicio
      ..fim = fim
      ..linkOuLocal = texto.isEmpty ? null : texto
      ..convidados = convidados;

    // Horário novo + gente que já foi avisada ou respondeu: pergunta o que fazer.
    final jaAvisados = convidados.any((c) => c.resposta != RespostaConvite.pendente || c.conviteEnviadoEm != null);
    if (horarioMudou && jaAvisados) {
      final zerar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('O horário mudou'),
          content: const Text(
            'Os convidados foram avisados do horário antigo. Quer zerar as respostas e pedir uma nova confirmação?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Manter respostas')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Zerar e reenviar')),
          ],
        ),
      );
      if (!mounted) return;
      if (zerar == true) {
        for (final c in novo.convidados) {
          c.resposta = RespostaConvite.pendente;
          c.respondidoEm = null;
          c.conviteEnviadoEm = null;
        }
      }
    }

    setState(() => _salvando = true);
    var calendarioOk = true;
    final eventoId = novo.eventoId;
    final calendarioId = novo.calendarioId;
    if (eventoId != null && calendarioId != null) {
      // Convidados de e-mail que entraram ou saíram: o evento do calendário acompanha,
      // e é por ele que o Google Agenda envia o convite e devolve a resposta.
      final emailsAntes = {
        for (final c in antiga.convidados)
          if (c.canal == CanalConvite.email) c.contato.trim().toLowerCase(),
      };
      final emailsAgora = {
        for (final c in convidados)
          if (c.canal == CanalConvite.email) c.contato.trim().toLowerCase(): c.nome,
      };
      calendarioOk = await EventoCalendario().atualizar(
        calendarioId: calendarioId,
        eventoId: eventoId,
        titulo: titulo,
        inicio: inicio,
        fim: fim,
        linkOuLocal: texto,
        adicionarConvidados: {
          for (final e in emailsAgora.entries)
            if (!emailsAntes.contains(e.key)) e.key: e.value,
        },
        removerEmails: emailsAntes.difference(emailsAgora.keys.toSet()),
      );
    }
    if (!mounted) return;

    novo.atualizadoEm = DateTime.now();
    await ref.read(agendamentosProvider.notifier).atualizar(novo);
    if (!mounted) return;
    Navigator.of(context).pop(ResultadoReuniao(agendamento: novo, criada: false, calendarioOk: calendarioOk));
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;
    final dataTxt = toBeginningOfSentenceCase(DateFormat("EEE, d 'de' MMM", 'pt_BR').format(_data)) ?? '';
    final duracoes = ({..._duracoesPadrao, _duracaoMin}).toList()..sort();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editando ? 'Editar reunião' : 'Agendar reunião',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cores.texto),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoracao('Título'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherData,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(dataTxt),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherHora,
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(_hora.format(context)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Duração', style: t.labelMedium?.copyWith(color: cores.suave)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in duracoes) _opcao(_rotuloDuracao(m), _duracaoMin == m, () => setState(() => _duracaoMin = m)),
                ],
              ),
              _avisoConflito(),
              const SizedBox(height: 12),
              TextField(
                controller: _linkOuLocal,
                keyboardType: TextInputType.url,
                decoration: _decoracao(
                  'Link ou local',
                  ajuda: 'Cole o link do Teams, Meet ou Zoom. O Lembra reconhece e mostra o botão Entrar.',
                ),
              ),
              const SizedBox(height: 16),
              _secaoConvidados(),
              if (_editando) ...[
                const SizedBox(height: 12),
                if (widget.existente!.calendarioNome.isNotEmpty)
                  Text(
                    'Calendário: ${widget.existente!.calendarioNome}',
                    style: t.bodySmall?.copyWith(color: cores.suave),
                  ),
              ] else if (widget.calendarios.length > 1) ...[
                const SizedBox(height: 12),
                Text('Salvar no calendário', style: t.labelMedium?.copyWith(color: cores.suave)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final cal in widget.calendarios)
                      _opcao(nomeCalendario(cal), identical(cal, _calendario), () => setState(() => _calendario = cal)),
                  ],
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: t.bodyMedium?.copyWith(color: cores.perigo)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _salvando ? null : _salvar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.brand,
                  shape: const StadiumBorder(),
                ),
                child: _salvando
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(_editando ? 'Salvar alterações' : 'Revisar e agendar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
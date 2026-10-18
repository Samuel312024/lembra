import 'package:flutter/material.dart';

import '../domain/draft.dart';
import '../domain/item.dart';
import '../domain/recorrencia.dart';
import 'agenda.dart';

enum _Rep { nenhuma, diaria, uteis, semanal, mensal }

/// Formulário manual (captura por texto) e edição completa. Devolve o [Draft] ao salvar.
class ItemFormPage extends StatefulWidget {
  const ItemFormPage({super.key, this.rascunho, this.titulo = 'Novo lembrete'});

  final Draft? rascunho;
  final String titulo;

  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final _chave = GlobalKey<FormState>();
  late final Draft d = widget.rascunho ?? Draft.vazio();
  late final TextEditingController _titulo = TextEditingController(text: d.titulo);
  late _Rep _rep;
  late Set<int> _dias;

  static const _opcoesAviso = [
    (0, 'No horário'),
    (10, '10 min'),
    (30, '30 min'),
    (60, '1 hora'),
    (120, '2 horas'),
    (1440, '1 dia'),
    (2880, '2 dias'),
  ];
  static const _nomesDias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  void initState() {
    super.initState();
    final r = Recorrencia.parse(d.recorrencia);
    _dias = {...?r?.dias};
    if (r == null) {
      _rep = _Rep.nenhuma;
    } else if (r.freq == 'DAILY') {
      _rep = _Rep.diaria;
    } else if (r.freq == 'MONTHLY') {
      _rep = _Rep.mensal;
    } else if (r.dias.length == 5 && r.dias.every((x) => x <= 5)) {
      _rep = _Rep.uteis;
    } else {
      _rep = _Rep.semanal;
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  void _aplicarRecorrencia() {
    switch (_rep) {
      case _Rep.nenhuma:
        d.recorrencia = null;
      case _Rep.diaria:
        d.recorrencia = 'FREQ=DAILY';
      case _Rep.uteis:
        d.recorrencia = const Recorrencia('WEEKLY', dias: [1, 2, 3, 4, 5]).toRRule();
      case _Rep.semanal:
        d.recorrencia = _dias.isEmpty ? null : Recorrencia('WEEKLY', dias: _dias.toList()..sort()).toRRule();
      case _Rep.mensal:
        d.recorrencia = Recorrencia('MONTHLY', diaMes: (d.ancora ?? DateTime.now()).day).toRRule();
    }
  }

  Future<void> _escolherData() async {
    final agora = DateTime.now();
    final atual = d.ancora ?? agora;
    final r = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(agora.year, agora.month, agora.day - 1),
      lastDate: DateTime(agora.year + 5),
    );
    if (r == null) return;
    setState(() {
      d.definirAncora(DateTime(r.year, r.month, r.day, atual.hour, atual.minute));
      d.camposFaltando.remove('data');
      if (_rep == _Rep.mensal) _aplicarRecorrencia();
    });
  }

  Future<void> _escolherHora() async {
    final base = d.ancora ?? DateTime.now();
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour == 0 ? 9 : base.hour, minute: base.minute),
    );
    if (r == null) return;
    setState(() {
      d.definirAncora(DateTime(base.year, base.month, base.day, r.hour, r.minute));
      d.camposFaltando.remove('horario');
      d.horarioPadrao = false;
    });
  }

  void _salvar() {
    if (!_chave.currentState!.validate()) return;
    d.titulo = _titulo.text.trim();
    if (_rep == _Rep.semanal && _dias.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Escolha ao menos um dia da semana.')));
      return;
    }
    _aplicarRecorrencia();
    Navigator.of(context).pop(d);
  }

  @override
  Widget build(BuildContext context) {
    final a = d.ancora;
    final temHora = a != null && (a.hour != 0 || a.minute != 0);
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Form(
        key: _chave,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final t in TipoItem.values)
                  ChoiceChip(
                    label: Text(t.rotulo),
                    selected: d.tipo == t,
                    onSelected: (_) => setState(() {
                      final ancora = d.ancora;
                      d.tipo = t;
                      d.definirAncora(ancora);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titulo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'O quê', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Dê um nome ao lembrete' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherData,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(a == null ? 'Data' : quandoCurto(a, comHora: false)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: a == null ? null : _escolherHora,
                    icon: const Icon(Icons.schedule),
                    label: Text(temHora ? horaMinutos(a.hour * 60 + a.minute) : 'Hora'),
                  ),
                ),
              ],
            ),
            if (a != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    d.definirAncora(null);
                    _rep = _Rep.nenhuma;
                  }),
                  child: const Text('Remover data'),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_Rep>(
              value: _rep,
              decoration: const InputDecoration(labelText: 'Repetir', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: _Rep.nenhuma, child: Text('Não repete')),
                DropdownMenuItem(value: _Rep.diaria, child: Text('Todo dia')),
                DropdownMenuItem(value: _Rep.uteis, child: Text('Dias úteis')),
                DropdownMenuItem(value: _Rep.semanal, child: Text('Dias da semana…')),
                DropdownMenuItem(value: _Rep.mensal, child: Text('Todo mês (no dia da data)')),
              ],
              onChanged: (v) => setState(() {
                _rep = v ?? _Rep.nenhuma;
                if (_rep != _Rep.nenhuma && d.ancora == null) {
                  final n = DateTime.now();
                  d.definirAncora(DateTime(n.year, n.month, n.day, 9));
                }
              }),
            ),
            if (_rep == _Rep.semanal)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(_nomesDias[i]),
                        selected: _dias.contains(i + 1),
                        onSelected: (s) => setState(() => s ? _dias.add(i + 1) : _dias.remove(i + 1)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text('Urgência', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Urgencia>(
              segments: [for (final u in Urgencia.values) ButtonSegment(value: u, label: Text(u.rotulo))],
              selected: {d.urgencia},
              onSelectionChanged: (s) => setState(() => d.urgencia = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              switch (d.urgencia) {
                Urgencia.discreto => 'Notificação silenciosa.',
                Urgencia.normal => 'Notificação com som.',
                Urgencia.critico => 'Alarme alto em tela cheia; repete até você confirmar.',
              },
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Avisar antes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (min, rotulo) in _opcoesAviso)
                  FilterChip(
                    label: Text(rotulo),
                    selected: d.antecedencias.contains(min),
                    onSelected: (s) => setState(() => s ? d.antecedencias.add(min) : d.antecedencias.remove(min)),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

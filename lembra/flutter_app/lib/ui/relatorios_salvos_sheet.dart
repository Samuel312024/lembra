// Coloque em: lib/ui/relatorios_salvos_sheet.dart
//
// Lista os relatórios (PDF e imagem) que ficaram salvos no aparelho.

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/relatorio_export.dart';
import 'theme/app_theme.dart';

Future<void> abrirRelatoriosSalvos(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SalvosSheet(),
    );

class _SalvosSheet extends StatefulWidget {
  const _SalvosSheet();

  @override
  State<_SalvosSheet> createState() => _SalvosSheetState();
}

class _SalvosSheetState extends State<_SalvosSheet> {
  late Future<List<File>> _futuro = RelatorioExport.salvos();

  void _recarregar() => setState(() => _futuro = RelatorioExport.salvos());

  String _dois(int n) => n.toString().padLeft(2, '0');

  String _dataHora(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year} ${_dois(d.hour)}:${_dois(d.minute)}';

  Future<void> _apagar(File arquivo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar arquivo?'),
        content: const Text('Ele será removido deste aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await arquivo.delete();
    if (mounted) _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: FutureBuilder<List<File>>(
          future: _futuro,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final arquivos = snap.data ?? const <File>[];
            if (arquivos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  'Nenhum relatório salvo ainda. Use “Salvar PDF” ou “Salvar imagem” no cartão de renda.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: cores.suave),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: arquivos.length,
              itemBuilder: (context, i) {
                final f = arquivos[i];
                final nome = f.uri.pathSegments.last;
                final png = nome.toLowerCase().endsWith('.png');
                return ListTile(
                  leading: png
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(f, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 132),
                        )
                      : SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.picture_as_pdf_rounded, color: cores.marca),
                        ),
                  title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_dataHora(f.lastModifiedSync())),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Compartilhar ou salvar em outro lugar',
                        icon: const Icon(Icons.ios_share_rounded),
                        onPressed: () => RelatorioExport.compartilhar(f),
                      ),
                      IconButton(
                        tooltip: 'Apagar',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _apagar(f),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
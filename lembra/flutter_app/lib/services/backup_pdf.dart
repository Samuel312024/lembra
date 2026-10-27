import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/dinheiro.dart';
import '../domain/item.dart';

/// Backup profissional: PDF para ler/guardar + arquivo de texto para restaurar.
class BackupPdf {
  static const _marca = PdfColor.fromInt(0xFFB7550B);
  static const _fundo = PdfColor.fromInt(0xFFF7F1E8);
  static const _linha = PdfColor.fromInt(0xFFE2D8CB);
  static const _texto = PdfColor.fromInt(0xFF2B2B2B);
  static const _suave = PdfColor.fromInt(0xFF7A746C);

  static String _maiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _repeticao(Item i) {
    switch (i.regra?.freq) {
      case 'DAILY':
        return 'Todo dia';
      case 'WEEKLY':
        return 'Toda semana';
      case 'MONTHLY':
        return 'Todo mês';
      default:
        return 'Não repete';
    }
  }

  static String _titulo(Item i) {
    final conta = i.tipo == TipoItem.conta && i.valor != null;
    return conta ? '${i.titulo} • ${formatarReais(i.valor!)}' : i.titulo;
  }

  static pw.Widget _celula(String t, {bool cab = false, PdfColor? cor}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: cab ? 9 : 9.5,
            fontWeight: cab ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: cab ? PdfColors.white : (cor ?? _texto),
          ),
        ),
      );

  static pw.Widget _quadro(String rotulo, String valor) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _fundo, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(valor, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _marca)),
            pw.SizedBox(height: 2),
            pw.Text(rotulo, style: const pw.TextStyle(fontSize: 9, color: _suave)),
          ]),
        ),
      );

  static pw.Widget _tabela(List<Item> itens) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(5),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(2.5),
        3: pw.FlexColumnWidth(2),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _linha, width: 0.5),
        bottom: pw.BorderSide(color: _linha, width: 0.5),
      ),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _marca),
          children: [
            _celula('Lembrete', cab: true),
            _celula('Quando', cab: true),
            _celula('Repetição', cab: true),
            _celula('Situação', cab: true),
          ],
        ),
        for (final i in itens)
          pw.TableRow(children: [
            _celula(_titulo(i)),
            _celula(i.ancora == null ? '—' : fmt.format(i.ancora!)),
            _celula(_repeticao(i), cor: _suave),
            _celula(_maiuscula(i.status.name), cor: _suave),
          ]),
      ],
    );
  }

  static Future<Uint8List> gerarPdf(List<Item> itens) async {
    final agora = DateTime.now();
    final geradoEm = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(agora);

    int ordem(Item a, Item b) {
      if (a.ancora == null && b.ancora == null) return 0;
      if (a.ancora == null) return 1;
      if (b.ancora == null) return -1;
      return a.ancora!.compareTo(b.ancora!);
    }

    final grupos = <String, List<Item>>{
      'Críticos': itens.where((i) => i.urgencia == Urgencia.critico).toList()..sort(ordem),
      'Normais': itens.where((i) => i.urgencia == Urgencia.normal).toList()..sort(ordem),
      'Discretos': itens.where((i) => i.urgencia == Urgencia.discreto).toList()..sort(ordem),
    };
    final ativos = itens.where((i) => i.status == StatusItem.ativo).length;

    final doc = pw.Document(title: 'Backup do Lembra', author: 'Lembra');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _linha, width: 0.5))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Lembra • Gerado em $geradoEm', style: const pw.TextStyle(fontSize: 8, color: _suave)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: _suave)),
          ]),
        ),
        build: (ctx) => [
          pw.Text('Lembra', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: _marca)),
          pw.SizedBox(height: 2),
          pw.Text('Backup dos lembretes', style: const pw.TextStyle(fontSize: 13, color: _texto)),
          pw.Text('Gerado em $geradoEm', style: const pw.TextStyle(fontSize: 9, color: _suave)),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            _quadro('Lembretes no total', '${itens.length}'),
            _quadro('Ativos', '$ativos'),
            _quadro('Críticos', '${grupos['Críticos']!.length}'),
          ]),
          pw.SizedBox(height: 18),
          if (itens.isEmpty)
            pw.Text('Nenhum lembrete salvo.', style: const pw.TextStyle(fontSize: 11, color: _suave)),
          for (final e in grupos.entries)
            if (e.value.isNotEmpty) ...[
              pw.Text('${e.key} (${e.value.length})',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _texto)),
              pw.SizedBox(height: 6),
              _tabela(e.value),
              pw.SizedBox(height: 16),
            ],
        ],
      ),
    );
    return doc.save();
  }

  /// Abre o menu de compartilhar (WhatsApp, e-mail, Drive, Salvar em arquivos)
  /// com o PDF e o arquivo de texto usado para restaurar.
  static Future<void> compartilhar({required List<Item> itens, required String backupTexto}) async {
    final dir = await getTemporaryDirectory();
    final data = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final pdf = File('${dir.path}/lembra-backup-$data.pdf');
    await pdf.writeAsBytes(await gerarPdf(itens));

    final txt = File('${dir.path}/lembra-backup-$data.txt');
    await txt.writeAsString(backupTexto);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(pdf.path, mimeType: 'application/pdf'),
          XFile(txt.path, mimeType: 'text/plain'),
        ],
        subject: 'Backup do Lembra',
        text: 'Backup dos meus lembretes ($data).',
      ),
    );
  }
}
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

String _data(dynamic ms) {
  if (ms == null) return '-';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms as int);
  return DateFormat('dd/MM/yyyy HH:mm').format(dt);
}

Future<void> exportarLembretesPdf(List<Map<String, dynamic>> itens) async {
  final doc = pw.Document();
  final hoje = DateFormat('dd/MM/yyyy').format(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text('Meus lembretes - $hoje',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9)),
      ),
      build: (_) => [
        if (itens.isEmpty)
          pw.Text('Nenhum lembrete.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Título', 'Tipo', 'Prazo', 'Urgência', 'Status', 'Valor'],
            data: itens.map((i) => [
                  i['titulo'] ?? '',
                  i['tipo'] ?? '',
                  _data(i['prazo']),
                  i['urgencia'] ?? '',
                  i['status'] ?? '',
                  i['valor'] == null ? '-' : 'R\$ ${i['valor']}',
                ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
      ],
    ),
  );

  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final nome = 'lembretes_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
  final file = File('${dir.path}/$nome');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf', name: nome)],
      subject: 'Meus lembretes',
    ),
  );
}
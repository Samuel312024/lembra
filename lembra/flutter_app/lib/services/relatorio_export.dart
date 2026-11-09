// Coloque em: lib/services/relatorio_export.dart
//
// Gera o relatório do mês em PDF ou imagem (PNG), deixa salvo no aparelho
// (pasta "relatorios" do app) e permite compartilhar / guardar onde quiser.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart' show GlobalKey;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/dinheiro.dart';
import '../domain/renda.dart';

enum FormatoRelatorio { pdf, imagem }

class LinhaRelatorio {
  const LinhaRelatorio({required this.titulo, required this.valor, this.tipo, this.data});

  final String titulo;
  final String? tipo;
  final DateTime? data;
  final double valor;
}

class DadosRelatorio {
  const DadosRelatorio({
    required this.mes,
    required this.perfil,
    required this.gasto,
    required this.linhas,
  });

  final DateTime mes;
  final PerfilRenda perfil;
  final double gasto;
  final List<LinhaRelatorio> linhas;

  ComparativoRenda get comparativo =>
      ComparativoRenda(renda: perfil.rendaMensal, gasto: gasto, limitePct: perfil.limitePct);
}

class RelatorioExport {
  RelatorioExport._();

  // ---------------------------------------------------------------- arquivos

  static Future<Directory> _pasta() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}relatorios');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _dois(int n) => n.toString().padLeft(2, '0');

  static String _nomeArquivo(DateTime mes, String ext) {
    final agora = DateTime.now();
    return 'contas-${mes.year}-${_dois(mes.month)}_${_dois(agora.hour)}${_dois(agora.minute)}${_dois(agora.second)}.$ext';
  }

  static String _data(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

  /// Relatórios já salvos, do mais novo para o mais antigo.
  static Future<List<File>> salvos() async {
    final dir = await _pasta();
    final arquivos = dir.listSync().whereType<File>().where((f) {
      final n = f.path.toLowerCase();
      return n.endsWith('.pdf') || n.endsWith('.png');
    }).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return arquivos;
  }

  static Future<void> compartilhar(File arquivo) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(arquivo.path)], text: 'Contas do mês'),
    );
  }

  // ------------------------------------------------------------------ imagem

  /// Tira um "print" (PNG) do widget que está dentro de um RepaintBoundary.
  /// Devolve null se o widget não estiver na tela no momento.
  static Future<Uint8List?> capturarPng(GlobalKey chave, {double pixelRatio = 3}) async {
    final objeto = chave.currentContext?.findRenderObject();
    if (objeto is! RenderRepaintBoundary) return null;
    final imagem = await objeto.toImage(pixelRatio: pixelRatio);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  static Future<File> salvarImagem(DadosRelatorio dados, Uint8List png) async {
    final arquivo = File('${(await _pasta()).path}${Platform.pathSeparator}${_nomeArquivo(dados.mes, 'png')}');
    return arquivo.writeAsBytes(png, flush: true);
  }

  // --------------------------------------------------------------------- pdf

  static Future<File> salvarPdf(DadosRelatorio dados) async {
    final bytes = await _montarPdf(dados);
    final arquivo = File('${(await _pasta()).path}${Platform.pathSeparator}${_nomeArquivo(dados.mes, 'pdf')}');
    return arquivo.writeAsBytes(bytes, flush: true);
  }

  static pw.Widget _kpi(String rotulo, String valor, PdfColor cor) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(rotulo, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(valor, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: cor)),
        ],
      ),
    );
  }

  static pw.Widget _barraPdf(ComparativoRenda c) {
    if (!c.temRenda) return pw.SizedBox();
    int f(double v) => (v.clamp(0.0, 1.0) * 1000).round();

    final seguro = f(math.min(c.gasto, c.valorLimite) / c.renda);
    final vermelho = f((math.min(c.gasto, c.renda) - math.min(c.gasto, c.valorLimite)) / c.renda);
    final resto = 1000 - seguro - vermelho;
    final estourou = c.nivel == NivelGasto.estourou;

    return pw.Row(
      children: [
        if (seguro > 0)
          pw.Expanded(
            flex: seguro,
            child: pw.Container(height: 10, color: estourou ? PdfColors.red700 : PdfColors.green700),
          ),
        if (vermelho > 0)
          pw.Expanded(flex: vermelho, child: pw.Container(height: 10, color: PdfColors.red700)),
        if (resto > 0)
          pw.Expanded(flex: resto, child: pw.Container(height: 10, color: PdfColors.grey300)),
      ],
    );
  }

  static Future<Uint8List> _montarPdf(DadosRelatorio d) {
    final c = d.comparativo;
    final p = d.perfil;
    final vermelho = c.emVermelho;
    final corDestaque = vermelho ? PdfColors.red700 : PdfColors.green700;

    final linhas = [...d.linhas]..sort((a, b) {
        final da = a.data;
        final db = b.data;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    String detalhePj = '';
    if (p.tipo == TipoRenda.pj) {
      detalhePj = 'PJ: faturamento ${formatarReais(p.faturamento)}'
          ' - impostos (${p.impostoPct.toStringAsFixed(1)}%) ${formatarReais(p.imposto)}'
          ' - custos da empresa ${formatarReais(p.custosEmpresa)}';
      if (p.outrasRendas > 0) detalhePj += ' + outras rendas ${formatarReais(p.outrasRendas)}';
    } else if (p.outrasRendas > 0) {
      detalhePj = 'CLT: salário líquido ${formatarReais(p.salarioLiquido)}'
          ' + outras rendas ${formatarReais(p.outrasRendas)}';
    }

    final doc = pw.Document(title: 'Contas de ${nomeMes(d.mes)} de ${d.mes.year}');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Text(
            'Contas de ${nomeMes(d.mes)} de ${d.mes.year}',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Comparativo entre renda e contas - ${p.tipo.rotulo}',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              _kpi('Renda do mês', formatarReais(c.renda), PdfColors.black),
              _kpi('Contas do mês', formatarReais(c.gasto), corDestaque),
              _kpi(c.sobra >= 0 ? 'Sobra' : 'Falta', formatarReais(c.sobra.abs()), corDestaque),
              _kpi('Comprometido', '${(c.fracao * 100).round()}%', corDestaque),
            ],
          ),
          pw.SizedBox(height: 12),
          _barraPdf(c),
          pw.SizedBox(height: 6),
          pw.Text(
            'Limite de ${p.limitePct.round()}% da renda = ${formatarReais(c.valorLimite)}. '
            'Acima dele a barra fica vermelha (margem vermelha).',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: vermelho ? PdfColors.red50 : PdfColors.green50,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(c.mensagem, style: pw.TextStyle(fontSize: 11, color: corDestaque)),
          ),
          if (detalhePj.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(detalhePj, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 20),
          pw.Text(
            'Contas consideradas (${linhas.length})',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (linhas.isEmpty)
            pw.Text('Nenhuma conta neste período.', style: pw.TextStyle(fontSize: 10))
          else ...[
            pw.TableHelper.fromTextArray(
              headers: ['Conta', 'Tipo', 'Vencimento', 'Valor'],
              data: [
                for (final l in linhas)
                  [
                    l.titulo,
                    l.tipo ?? '-',
                    l.data == null ? '-' : _data(l.data!),
                    l.valor > 0 ? formatarReais(l.valor) : 'sem valor',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: pw.TextStyle(fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
              border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1.6),
              },
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total: ${formatarReais(c.gasto)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
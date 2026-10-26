// Coloque em: test/contas_test.dart
//
// Testes das contas: valores, tipos, números por extenso, totais e leitura por voz.
// Rode com: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:lembra/domain/categoria_conta.dart';
import 'package:lembra/domain/dinheiro.dart';
import 'package:lembra/domain/item.dart';
import 'package:lembra/nlp/interpretador.dart';
import 'package:lembra/nlp/numeros.dart';
import 'package:lembra/nlp/valor.dart';
import 'package:lembra/ui/conta_paga.dart';
import 'package:lembra/ui/resumo_contas.dart';

Item _conta(String id, {DateTime? prazo, double? valor, StatusItem status = StatusItem.ativo}) {
  final t = DateTime(2026, 10, 1);
  return Item(
    id: id,
    tipo: TipoItem.conta,
    titulo: 'Conta $id',
    prazo: prazo,
    valor: valor,
    status: status,
    criadoEm: t,
    atualizadoEm: t,
  );
}

void main() {
  group('dinheiro', () {
    test('lerReais entende o padrão brasileiro', () {
      expect(lerReais('1.250,50'), 1250.5);
      expect(lerReais('1250,5'), 1250.5);
      expect(lerReais('50'), 50);
      expect(lerReais('1.250'), 1250);
      expect(lerReais('R\$ 99,9'), 99.9);
    });

    test('lerReais devolve null para vazio ou inválido', () {
      expect(lerReais(''), isNull);
      expect(lerReais('abc'), isNull);
      expect(lerReais('1,2,3'), isNull);
    });

    test('formatarReais usa vírgula e ponto', () {
      expect(formatarReais(1250.5), 'R\$ 1.250,50');
      expect(formatarReais(0), 'R\$ 0,00');
    });
  });

  group('números por extenso', () {
    test('lerNumeroPorExtenso', () {
      expect(lerNumeroPorExtenso('quinhentos'), 500);
      expect(lerNumeroPorExtenso('cento e cinquenta'), 150);
      expect(lerNumeroPorExtenso('vinte e cinco'), 25);
      expect(lerNumeroPorExtenso('mil e duzentos'), 1200);
      expect(lerNumeroPorExtenso('dois mil e quinhentos'), 2500);
      expect(lerNumeroPorExtenso('banana'), isNull);
    });
  });

  group('extrairValor', () {
    test('com cifrão e com "reais"', () {
      expect(extrairValor('conta de luz r\$ 500')?.valor, 500);
      expect(extrairValor('pagar 89,90 reais')?.valor, 89.9);
      expect(extrairValor('boleto de 2.500 reais')?.valor, 2500);
    });

    test('por extenso', () {
      expect(extrairValor('pagar cento e cinquenta reais')?.valor, 150);
      expect(extrairValor('aluguel de mil e quinhentos reais')?.valor, 1500);
    });

    test('sem valor', () {
      expect(extrairValor('ligar para o joao'), isNull);
      expect(extrairValor('medico dia 22 as 14h30'), isNull);
    });

    test('a posição encontrada corresponde ao trecho do valor', () {
      const texto = 'conta de luz r\$ 500 dia 20';
      final v = extrairValor(texto)!;
      expect(texto.substring(v.inicio, v.fim), 'r\$ 500');
    });
  });

  group('tipo de conta', () {
    test('detectarCategoriaConta', () {
      expect(detectarCategoriaConta('conta de luz'), CategoriaConta.luz);
      expect(detectarCategoriaConta('fatura de luz'), CategoriaConta.luz);
      expect(detectarCategoriaConta('fatura do cartao'), CategoriaConta.cartao);
      expect(detectarCategoriaConta('taxa de condominio'), CategoriaConta.condominio);
      expect(detectarCategoriaConta('pagar o aluguel'), CategoriaConta.aluguel);
      expect(detectarCategoriaConta('comprar pao'), isNull);
    });

    test('categoriaContaDoNome ignora nomes desconhecidos', () {
      expect(categoriaContaDoNome('agua'), CategoriaConta.agua);
      expect(categoriaContaDoNome('xyz'), isNull);
      expect(categoriaContaDoNome(null), isNull);
    });
  });

  group('ResumoContas', () {
    final agora = DateTime(2026, 10, 22, 10);

    test('separa por situação e soma os valores', () {
      final r = ResumoContas.de([
        _conta('vencida', prazo: DateTime(2026, 10, 20, 9), valor: 100),
        _conta('proxima', prazo: DateTime(2026, 10, 25, 9), valor: 50.5),
        _conta('depois', prazo: DateTime(2026, 11, 20, 9), valor: 500),
        _conta('semdata'),
        _conta('paga', prazo: DateTime(2026, 10, 21, 9), valor: 999, status: StatusItem.concluido),
      ], agora);

      expect(r.vencidas.length, 1);
      expect(r.proximas.length, 1);
      expect(r.depois.length, 1);
      expect(r.semData.length, 1);
      expect(r.quantidade, 4);
      expect(r.total, closeTo(650.5, 0.001));
      expect(r.totalVencidas, closeTo(100, 0.001));
      expect(r.semValor, 1);
      expect(r.temValor, isTrue);
    });

    test('filtra por tipo de conta', () {
      final luz = _conta('luz', prazo: DateTime(2026, 10, 25, 9), valor: 80)..categoria = CategoriaConta.luz;
      final agua = _conta('agua', prazo: DateTime(2026, 10, 26, 9), valor: 40)..categoria = CategoriaConta.agua;
      final r = ResumoContas.de([luz, agua], agora, categoria: CategoriaConta.luz);
      expect(r.quantidade, 1);
      expect(r.total, closeTo(80, 0.001));
    });
  });

  group('próxima cobrança', () {
    test('somarMeses mantém o dia e respeita o fim do mês', () {
      expect(somarMeses(DateTime(2026, 10, 20, 9), 1), DateTime(2026, 11, 20, 9));
      expect(somarMeses(DateTime(2026, 12, 15, 9), 1), DateTime(2027, 1, 15, 9));
      expect(somarMeses(DateTime(2026, 1, 31, 9), 1), DateTime(2026, 2, 28, 9));
    });

    test('proximaCobranca copia valor e tipo, um mês depois', () {
      final c = _conta('luz', prazo: DateTime(2026, 10, 20, 9), valor: 150)..categoria = CategoriaConta.luz;
      final d = proximaCobranca(c)!;
      expect(d.valor, 150);
      expect(d.categoria, CategoriaConta.luz);
      expect(d.ancora, DateTime(2026, 11, 20, 9));
    });

    test('só vale para conta com data', () {
      expect(proximaCobranca(_conta('semdata')), isNull);
    });
  });

  group('voz', () {
    final interpretador = InterpretadorLocal(agora: DateTime(2026, 10, 22, 10));

    test('conta de luz com valor em números', () {
      final d = interpretador.interpretar('conta de luz de 500 reais dia 30').first;
      expect(d.tipo, TipoItem.conta);
      expect(d.valor, 500);
      expect(d.categoria, CategoriaConta.luz);
    });

    test('aluguel com valor por extenso', () {
      final d = interpretador.interpretar('pagar aluguel de mil e quinhentos reais amanhã').first;
      expect(d.tipo, TipoItem.conta);
      expect(d.valor, 1500);
      expect(d.categoria, CategoriaConta.aluguel);
    });

    test('uma compra com valor não vira conta', () {
      final d = interpretador.interpretar('comprar pão 5 reais amanhã').first;
      expect(d.tipo, isNot(TipoItem.conta));
      expect(d.valor, isNull);
    });
  });
}
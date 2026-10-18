import 'package:flutter_test/flutter_test.dart';
import 'package:lembra/domain/item.dart';
import 'package:lembra/nlp/comandos.dart';
import 'package:lembra/nlp/interpretador.dart';
import 'package:lembra/nlp/pt_date_parser.dart';

// Quarta-feira, 14/10/2026, 10:00 — referência fixa para todos os testes.
final quarta = DateTime(2026, 10, 14, 10, 0);
// Sexta-feira, 16/10/2026, 10:00 — para os casos de ambiguidade.
final sexta = DateTime(2026, 10, 16, 10, 0);

DateTime? quando(String frase, [DateTime? agora]) =>
    PtDateParser(agora ?? quarta).parse(frase).dataHora;

void main() {
  group('Datas e horários (pt-BR coloquial)', () {
    final casos = <String, DateTime>{
      'amanhã às 9': DateTime(2026, 10, 15, 9),
      'amanhã às 14:30': DateTime(2026, 10, 15, 14, 30),
      'amanhã às 9h30': DateTime(2026, 10, 15, 9, 30),
      'amanhã às 7 e meia': DateTime(2026, 10, 15, 7, 30),
      'amanhã de tarde': DateTime(2026, 10, 15, 15),
      'hoje às 15h': DateTime(2026, 10, 14, 15),
      'hoje à noite': DateTime(2026, 10, 14, 20),
      'depois de amanhã': DateTime(2026, 10, 16),
      'sexta': DateTime(2026, 10, 16),
      'sábado às 20h': DateTime(2026, 10, 17, 20),
      'domingo': DateTime(2026, 10, 18),
      'quinta-feira às 10h': DateTime(2026, 10, 15, 10),
      'segunda de manhã': DateTime(2026, 10, 19, 9),
      'segunda da semana que vem': DateTime(2026, 10, 19),
      'semana que vem': DateTime(2026, 10, 21),
      'mês que vem': DateTime(2026, 11, 14),
      'dia 22': DateTime(2026, 10, 22),
      'dia 5': DateTime(2026, 11, 5), // já passou neste mês
      'dia 14': DateTime(2026, 10, 14), // hoje, sem horário
      'dia 14 às 9h': DateTime(2026, 11, 14, 9), // hoje às 9h já passou
      'dia 22 às 14h30': DateTime(2026, 10, 22, 14, 30),
      'Tenho médico dia 22 às 14h30': DateTime(2026, 10, 22, 14, 30),
      '25/12': DateTime(2026, 12, 25),
      '10/10': DateTime(2027, 10, 10), // já passou: próximo ano
      '22 de outubro às 14h30': DateTime(2026, 10, 22, 14, 30),
      'daqui a 2 horas': DateTime(2026, 10, 14, 12),
      'daqui a 30 minutos': DateTime(2026, 10, 14, 10, 30),
      'em 3 dias': DateTime(2026, 10, 17),
      'em 2 semanas': DateTime(2026, 10, 28),
      'às 3 da tarde': DateTime(2026, 10, 14, 15),
      'às 9 da noite': DateTime(2026, 10, 14, 21),
      'meio-dia': DateTime(2026, 10, 14, 12),
      'às 8': DateTime(2026, 10, 15, 8), // 8h de hoje já passou: amanhã
    };
    casos.forEach((frase, esperado) {
      test('"$frase"', () => expect(quando(frase), esperado));
    });

    test('sem horário não inventa hora', () {
      final q = PtDateParser(quarta).parse('sexta');
      expect(q.temData, isTrue);
      expect(q.temHorario, isFalse);
    });

    test('horário por período é marcado como aproximado', () {
      final q = PtDateParser(quarta).parse('segunda de manhã');
      expect(q.origemHorario, OrigemHorario.periodo);
    });
  });

  group('Ambiguidade de "sexta"', () {
    test('dito numa quarta: é a sexta desta semana', () {
      final q = PtDateParser(quarta).parse('sexta');
      expect(q.ambiguoHojeOuProxima, isFalse);
    });
    test('dito numa sexta: pergunta se é hoje ou a próxima', () {
      final q = PtDateParser(sexta).parse('sexta');
      expect(q.ambiguoHojeOuProxima, isTrue);
      expect(q.dataHora, DateTime(2026, 10, 23));
      expect(q.alternativa, DateTime(2026, 10, 16));
    });
    test('"próxima sexta" dito numa sexta não é ambíguo', () {
      final q = PtDateParser(sexta).parse('próxima sexta');
      expect(q.ambiguoHojeOuProxima, isFalse);
      expect(q.dataHora, DateTime(2026, 10, 23));
    });
  });

  group('Recorrência', () {
    String? regra(String f) => PtDateParser(quarta).parse(f).recorrencia;

    test('todo dia às 8h', () {
      expect(regra('todo dia às 8h'), 'FREQ=DAILY');
      expect(quando('todo dia às 8h'), DateTime(2026, 10, 15, 8)); // 8h de hoje já passou
    });
    test('toda segunda e quarta', () => expect(regra('toda segunda e quarta'), 'FREQ=WEEKLY;BYDAY=MO,WE'));
    test('toda segunda, quarta e sexta',
        () => expect(regra('toda segunda, quarta e sexta'), 'FREQ=WEEKLY;BYDAY=MO,WE,FR'));
    test('todo dia 5', () => expect(regra('todo dia 5'), 'FREQ=MONTHLY;BYMONTHDAY=5'));
    test('todo mês usa o dia de hoje', () => expect(regra('todo mês'), 'FREQ=MONTHLY;BYMONTHDAY=14'));
    test('dias úteis', () {
      expect(regra('de segunda a sexta às 7h'), 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
    });
    test('toda sexta às 18h começa na próxima sexta', () {
      expect(quando('toda sexta às 18h'), DateTime(2026, 10, 16, 18));
    });
  });

  group('Antecedência explícita', () {
    List<int>? ant(String f) => PtDateParser(quarta).parse(f).antecedencias;
    test('um dia antes', () => expect(ant('me avisa um dia antes'), [1440, 0]));
    test('2 horas antes', () => expect(ant('2 horas antes'), [120, 0]));
    test('meia hora antes', () => expect(ant('me avisa meia hora antes'), [30, 0]));
  });

  group('Frases completas (interpretador local)', () {
    final interp = InterpretadorLocal(agora: quarta);

    test('compromisso com data e hora', () {
      final d = interp.interpretar('Tenho médico dia 22 às 14h30').single;
      expect(d.titulo, 'Médico');
      expect(d.tipo, TipoItem.compromisso);
      expect(d.inicio, DateTime(2026, 10, 22, 14, 30));
      expect(d.antecedencias, [1440, 120, 30]);
      expect(d.camposFaltando, isEmpty);
    });

    test('conta sem horário gera pergunta curta', () {
      final d = interp.interpretar('Lembra de pagar o condomínio sexta').single;
      expect(d.titulo, 'Pagar o condomínio');
      expect(d.tipo, TipoItem.conta);
      expect(d.prazo, DateTime(2026, 10, 16));
      expect(d.camposFaltando, ['horario']);
      expect(d.antecedencias, [2880, 0]);
    });

    test('hábito diário de remédio é crítico', () {
      final d = interp.interpretar('Todo dia às 8h me lembra do remédio').single;
      expect(d.titulo, 'Remédio');
      expect(d.tipo, TipoItem.habito);
      expect(d.recorrencia, 'FREQ=DAILY');
      expect(d.urgencia, Urgencia.critico);
      expect(d.antecedencias, [0]);
    });

    test('vários itens numa frase compartilham a data', () {
      final ds = interp.interpretar('Amanhã pagar a luz e ligar pro banco');
      expect(ds.map((d) => d.titulo), ['Pagar a luz', 'Ligar pro banco']);
      expect(ds.every((d) => d.ancora == DateTime(2026, 10, 15)), isTrue);
      expect(ds.every((d) => d.camposFaltando.contains('horario')), isTrue);
    });

    test('tarefa sem data fica só na lista', () {
      final d = interp.interpretar('Me lembra de ligar pro João quando eu chegar no trabalho').single;
      expect(d.titulo, 'Ligar pro João quando eu chegar no trabalho');
      expect(d.tipo, TipoItem.tarefa);
      expect(d.ancora, isNull);
      expect(d.camposFaltando, isEmpty);
    });

    test('conta mensal recorrente', () {
      final d = interp.interpretar('Pagar o aluguel todo dia 5').single;
      expect(d.tipo, TipoItem.conta);
      expect(d.recorrencia, 'FREQ=MONTHLY;BYMONTHDAY=5');
    });

    test('hábito semanal com horário', () {
      final d = interp.interpretar('Academia toda segunda e quarta às 7h').single;
      expect(d.titulo, 'Academia');
      expect(d.tipo, TipoItem.habito);
      expect(d.recorrencia, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(d.inicio, DateTime(2026, 10, 19, 7));
    });

    test('verbo no início indica tarefa, não compromisso', () {
      final d = interp.interpretar('Marcar consulta com o dentista sexta').single;
      expect(d.tipo, TipoItem.tarefa);
    });

    test('compromisso recorrente (aula)', () {
      final d = interp.interpretar('Aula de inglês toda terça às 19h').single;
      expect(d.tipo, TipoItem.compromisso);
      expect(d.recorrencia, 'FREQ=WEEKLY;BYDAY=TU');
    });
  });

  group('Comandos de voz', () {
    final p = ParserComandos(quarta);

    test('cancelar', () {
      final c = p.interpretar('Cancela o lembrete do médico');
      expect(c, isA<CancelarComando>());
      expect((c as CancelarComando).alvo, 'medico');
    });
    test('apagar alarme', () {
      expect((p.interpretar('Apaga o alarme da academia') as CancelarComando).alvo, 'academia');
    });
    test('cancelar sem alvo = o último', () {
      expect((p.interpretar('cancela') as CancelarComando).alvo, '');
    });
    test('concluir: marcar como feito', () {
      expect((p.interpretar('marca como feito o remédio') as ConcluirComando).alvo, 'remedio');
      expect((p.interpretar('Marca o remédio como feito') as ConcluirComando).alvo, 'remedio');
    });
    test('concluir: já paguei', () {
      expect((p.interpretar('já paguei o condomínio') as ConcluirComando).alvo, 'condominio');
    });
    test('adiar por duração', () {
      final c = p.interpretar('adia o remédio por 1 hora') as AdiarComando;
      expect(c.alvo, 'remedio');
      expect(c.duracao, const Duration(hours: 1));
    });
    test('adiar sem alvo', () {
      final c = p.interpretar('adia 10 minutos') as AdiarComando;
      expect(c.alvo, '');
      expect(c.duracao, const Duration(minutes: 10));
    });
    test('adiar para outro dia e hora', () {
      final c = p.interpretar('adia a reunião para amanhã às 10') as AdiarComando;
      expect(c.alvo, 'reuniao');
      expect(c.novoQuando, DateTime(2026, 10, 15, 10));
    });
    test('listar o dia', () {
      expect(p.interpretar('o que eu tenho hoje'), isA<ListarComando>());
      expect((p.interpretar('o que tenho amanhã') as ListarComando).dia, DateTime(2026, 10, 15));
    });
    test('criar um lembrete não é comando', () {
      expect(p.interpretar('Tenho médico dia 22'), isNull);
      expect(p.interpretar('fizemos o bolo'), isNull);
    });
  });

  group('Busca do item-alvo', () {
    Item item(String t) => Item(
          id: t,
          tipo: TipoItem.tarefa,
          titulo: t,
          criadoEm: quarta,
          atualizadoEm: quarta,
        );
    final itens = [item('Médico'), item('Pagar o condomínio'), item('Remédio'), item('Pagar a luz')];

    test('encontra por palavra-chave', () {
      expect(buscarItens('medico', itens).single.titulo, 'Médico');
      expect(buscarItens('condominio', itens).single.titulo, 'Pagar o condomínio');
    });
    test('termo genérico devolve todos os candidatos', () {
      expect(buscarItens('pagar', itens).length, 2);
    });
    test('sem correspondência devolve vazio', () {
      expect(buscarItens('academia', itens), isEmpty);
    });
  });

  group('Resposta por voz ao cartão', () {
    test('confirmar', () => expect(interpretarResposta('sim, pode salvar'), RespostaVoz.confirmar));
    test('descartar', () => expect(interpretarResposta('não, descarta'), RespostaVoz.descartar));
    test('editar', () => expect(interpretarResposta('quero editar'), RespostaVoz.editar));
    test('não entendi', () => expect(interpretarResposta('hmm'), RespostaVoz.desconhecida));
  });
}

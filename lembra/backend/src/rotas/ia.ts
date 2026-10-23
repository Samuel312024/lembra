import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { db } from '../db.js';
import { IaIndisponivel, chamarLLM, extrairJson } from '../llm.js';

const corpoEsquema = z.object({
  texto: z.string().trim().min(1).max(1000),
  agora: z.string().datetime({ offset: true }),
  fuso: z.string().max(60).default('America/Sao_Paulo'),
  horario_padrao_min: z.number().int().min(0).max(1439).default(540),
});

const iso = z
  .string()
  .refine((v) => !Number.isNaN(Date.parse(v)) && /([zZ]|[+-]\d\d:\d\d)$/.test(v), 'ISO 8601 com fuso')
  .nullable();

const itemIA = z.object({
  tipo: z.enum(['compromisso', 'tarefa', 'habito', 'conta']),
  titulo: z.string().min(1).max(200),
  inicio: iso,
  prazo: iso,
  recorrencia: z
    .string()
    .regex(/^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY)(;[A-Z]+=[A-Z0-9,]+)*$/)
    .nullable(),
  antecedencias_minutos: z.array(z.number().int().min(0)).max(6),
  urgencia: z.enum(['discreto', 'normal', 'critico']),
  responsavel: z.string().max(100).default('eu'),
  origem: z.enum(['voz', 'texto', 'reuniao']),
  campos_faltando: z.array(z.string()).default([]),
  confianca: z.number().min(0).max(1),
  valor: z.number().min(0).max(1_000_000_000).nullable().default(null),
  categoria: z.string().max(30).nullable().default(null),
});

const SISTEMA = `Você converte falas em português do Brasil em itens de lembrete/agenda.
Responda SOMENTE com JSON válido (sem markdown, sem texto extra): um ARRAY com um objeto por item.
Se a fala tiver vários itens ("amanhã pagar a luz e ligar pro banco"), devolva um objeto para cada um.

Formato de cada objeto:
{
  "tipo": "compromisso | tarefa | habito | conta",
  "titulo": "string curta, sem data/hora, sem 'me lembra de'",
  "inicio": "ISO 8601 com fuso ou null",
  "prazo": "ISO 8601 com fuso ou null",
  "recorrencia": "FREQ=DAILY | FREQ=WEEKLY;BYDAY=MO,WE | FREQ=MONTHLY;BYMONTHDAY=5 | null",
  "antecedencias_minutos": [1440, 120, 30],
  "urgencia": "discreto | normal | critico",
  "responsavel": "eu",
  "origem": "voz",
  "valor": null,
  "categoria": null,
  "campos_faltando": [],
  "confianca": 0.0
}

Regras:
- tipo: compromisso = evento com data/hora marcada (consulta, reunião, aniversário) e usa "inicio";
  tarefa = algo a fazer, com ou sem prazo, usa "prazo"; habito = rotina recorrente (remédio, academia), usa "inicio";
  conta = pagamento com vencimento, usa "prazo".
- Use a data/hora atual e o fuso informados na mensagem do usuário para resolver expressões relativas.
- "sexta" = próxima sexta. Se hoje for sexta e não disser "próxima", NÃO adivinhe: use inicio/prazo null e campos_faltando ["data"].
- "semana que vem" = daqui a 7 dias. "dia 22" = próximo dia 22 (este mês se ainda não passou). "daqui a 2 horas" = agora + 2h.
- Sem horário: coloque a data com hora 00:00 e campos_faltando ["horario"] (o app pergunta ao usuário). Nunca invente horário.
  Exceção: "de manhã" = 09:00, "de tarde" = 15:00, "à noite" = 20:00.
- Sem data em compromisso: inicio null e campos_faltando ["data"].
- recorrencia: apenas FREQ=DAILY, FREQ=WEEKLY;BYDAY=... ou FREQ=MONTHLY;BYMONTHDAY=n. Em recorrentes, "inicio" é a primeira ocorrência futura.
- antecedencias_minutos padrão: compromisso [1440,120,30]; tarefa com prazo [60,0]; conta [2880,0]; habito [0].
  Se o usuário pedir ("me avisa um dia antes"), use [1440,0].
- urgencia: "critico" para remédio ou quando disser urgente/importante/não pode esquecer; "discreto" se pedir silêncio; senão "normal".
- confianca de 0 a 1: baixe quando faltar dado essencial ou a fala for ambígua.
- valor e categoria só para tipo conta (nos outros tipos, sempre null). valor = quanto é a conta, em reais, como número
  (150.5), sem "R$"; null se o usuário não disse. O valor NÃO entra no titulo.
  categoria = agua | luz | gas | internet | telefone | aluguel | condominio | cartao | financiamento | impostos | saude
  | educacao | assinaturas | outros; null se não der para saber.`;

export async function rotasIa(app: FastifyInstance) {
  app.post('/ia/entender', { preHandler: [app.autenticar] }, async (req, reply) => {
    const { texto, agora, fuso, horario_padrao_min } = corpoEsquema.parse(req.body);
    const uid = req.user.sub;

    // Controle de custo: limite diário por usuário.
    const dia = new Date().toISOString().slice(0, 10);
    const uso = db.prepare('SELECT qtd FROM uso_ia WHERE usuario_id = ? AND dia = ?').get(uid, dia) as
      | { qtd: number }
      | undefined;
    if ((uso?.qtd ?? 0) >= config.LIMITE_IA_DIARIO) {
      return reply.code(429).send({ erro: 'limite_diario' });
    }
    db.prepare(
      `INSERT INTO uso_ia (usuario_id, dia, qtd) VALUES (?, ?, 1)
       ON CONFLICT(usuario_id, dia) DO UPDATE SET qtd = qtd + 1`,
    ).run(uid, dia);

    const mensagem = JSON.stringify({ agora, fuso, horario_padrao: horario_padrao_min, texto });
    try {
      const bruto = await chamarLLM(SISTEMA, mensagem);
      const json = extrairJson(bruto);
      const lista = z.array(itemIA).min(1).max(10).parse(Array.isArray(json) ? json : [json]);
      return { itens: lista };
    } catch (e) {
      if (e instanceof IaIndisponivel) return reply.code(503).send({ erro: 'ia_indisponivel' });
      req.log.warn({ err: e }, 'falha ao interpretar com IA');
      // O app cai no interpretador local quando recebe erro.
      return reply.code(502).send({ erro: 'ia_falhou' });
    }
  });
}
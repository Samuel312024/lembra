import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { IaIndisponivel, chamarLLM, extrairJson } from '../llm.js';

/**
 * Transcrição de áudio (Fase 3). O provedor fica atrás desta interface para trocar
 * entre Whisper, Deepgram ou AssemblyAI sem mexer no resto do sistema.
 */
export interface Fala {
  falante: string;
  texto: string;
  inicioMs: number;
}

export interface ProvedorTranscricao {
  transcrever(audio: Buffer, mime: string): Promise<{ falas: Fala[] }>;
}

export class TranscricaoNaoConfigurada implements ProvedorTranscricao {
  async transcrever(): Promise<never> {
    throw new Error('Provedor de transcrição ainda não configurado (Fase 3).');
  }
}

const corpoEsquema = z.object({
  transcricao: z.string().trim().min(1).max(60000),
  agora: z.string().datetime({ offset: true }),
  fuso: z.string().max(60).default('America/Sao_Paulo'),
});

const resultadoEsquema = z.object({
  decisoes: z.array(z.string()).default([]),
  tarefas: z
    .array(
      z.object({
        titulo: z.string(),
        responsavel: z.string().default('eu'),
        prazo: z.string().nullable().default(null),
        trecho: z.string().default(''),
      }),
    )
    .default([]),
  duvidas: z.array(z.string()).default([]),
});

const SISTEMA = `Você analisa a transcrição de uma reunião em português do Brasil.
Responda SOMENTE com JSON válido: {"decisoes": [string], "tarefas": [{"titulo": string, "responsavel": string, "prazo": "ISO 8601 com fuso ou null", "trecho": string}], "duvidas": [string]}.
- tarefas: só o que alguém se comprometeu a fazer. "responsavel" é o nome dito na reunião ou "eu" se não ficar claro. "trecho" é a frase curta que originou a tarefa.
- Resolva prazos relativos ("até sexta") com a data atual informada. Sem prazo claro, use null.
- Não invente nada que não esteja na transcrição.`;

export async function rotasReunioes(app: FastifyInstance) {
  // Extração de decisões, tarefas e dúvidas a partir de texto já transcrito.
  app.post('/reunioes/extrair', { preHandler: [app.autenticar] }, async (req, reply) => {
    const { transcricao, agora, fuso } = corpoEsquema.parse(req.body);
    try {
      const bruto = await chamarLLM(SISTEMA, JSON.stringify({ agora, fuso, transcricao }), 2000);
      return resultadoEsquema.parse(extrairJson(bruto));
    } catch (e) {
      if (e instanceof IaIndisponivel) return reply.code(503).send({ erro: 'ia_indisponivel' });
      req.log.warn({ err: e }, 'falha ao extrair tarefas da reunião');
      return reply.code(502).send({ erro: 'ia_falhou' });
    }
  });
}

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { db } from '../db.js';

const ms = z.number().int().nullable().optional();

const itemEsquema = z.object({
  id: z.string().uuid(),
  tipo: z.enum(['compromisso', 'tarefa', 'habito', 'conta']),
  titulo: z.string().min(1).max(300),
  inicio: ms,
  prazo: ms,
  recorrencia: z.string().max(200).nullable().optional(),
  antecedencias: z.array(z.number().int().min(0).max(60 * 24 * 60)).max(8),
  urgencia: z.enum(['discreto', 'normal', 'critico']),
  status: z.enum(['ativo', 'concluido', 'cancelado']),
  origem: z.enum(['voz', 'texto', 'reuniao']),
  responsavel: z.string().max(100).default('eu'),
  soneca: z.number().int().min(0).default(0),
  concluido_em: ms,
  criado_em: z.number().int(),
  atualizado_em: z.number().int(),
});

const corpoEsquema = z.object({
  desde: z.number().int().min(0).default(0),
  itens: z.array(itemEsquema).max(500),
});

type Linha = Record<string, unknown> & { antecedencias: string };

export async function rotasSync(app: FastifyInstance) {
  // Em conflito vence a alteração mais recente (atualizado_em). O WHERE do upsert também
  // impede que um usuário sobrescreva o item de outro usando o mesmo id.
  const upsert = db.prepare(`
    INSERT INTO itens (id, usuario_id, tipo, titulo, inicio, prazo, recorrencia, antecedencias,
      urgencia, status, origem, responsavel, soneca, concluido_em, criado_em, atualizado_em, servidor_em)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      tipo = excluded.tipo, titulo = excluded.titulo, inicio = excluded.inicio, prazo = excluded.prazo,
      recorrencia = excluded.recorrencia, antecedencias = excluded.antecedencias,
      urgencia = excluded.urgencia, status = excluded.status, origem = excluded.origem,
      responsavel = excluded.responsavel, soneca = excluded.soneca, concluido_em = excluded.concluido_em,
      atualizado_em = excluded.atualizado_em, servidor_em = excluded.servidor_em
    WHERE itens.usuario_id = excluded.usuario_id AND itens.atualizado_em < excluded.atualizado_em
  `);

  app.post('/sync', { preHandler: [app.autenticar] }, async (req) => {
    const { desde, itens } = corpoEsquema.parse(req.body);
    const uid = req.user.sub;
    const agora = Date.now();

    db.exec('BEGIN');
    try {
      for (const i of itens) {
        upsert.run(
          i.id,
          uid,
          i.tipo,
          i.titulo,
          i.inicio ?? null,
          i.prazo ?? null,
          i.recorrencia ?? null,
          JSON.stringify(i.antecedencias),
          i.urgencia,
          i.status,
          i.origem,
          i.responsavel,
          i.soneca,
          i.concluido_em ?? null,
          i.criado_em,
          i.atualizado_em,
          agora,
        );
      }
      db.exec('COMMIT');
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }

    const linhas = db
      .prepare('SELECT * FROM itens WHERE usuario_id = ? AND servidor_em > ?')
      .all(uid, desde) as unknown as Linha[];

    return {
      agora,
      itens: linhas.map(({ usuario_id: _u, servidor_em: _s, ...resto }) => ({
        ...resto,
        antecedencias: JSON.parse(resto.antecedencias) as number[],
      })),
    };
  });
}

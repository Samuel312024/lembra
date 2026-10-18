import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { db } from '../db.js';

const credenciais = z.object({
  email: z.string().trim().toLowerCase().email().max(200),
  senha: z.string().min(8).max(200),
});

type Usuario = { id: string; senha_hash: string };

export async function rotasAuth(app: FastifyInstance) {
  // Limite mais rígido contra tentativas de senha.
  const limiteAuth = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };

  app.post('/auth/registrar', limiteAuth, async (req, reply) => {
    const { email, senha } = credenciais.parse(req.body);
    const existe = db.prepare('SELECT 1 FROM usuarios WHERE email = ?').get(email);
    if (existe) return reply.code(409).send({ erro: 'email_em_uso' });

    const id = randomUUID();
    const hash = await bcrypt.hash(senha, 12);
    db.prepare('INSERT INTO usuarios (id, email, senha_hash, criado_em) VALUES (?, ?, ?, ?)').run(
      id,
      email,
      hash,
      Date.now(),
    );
    return { token: app.jwt.sign({ sub: id }, { expiresIn: '30d' }), email };
  });

  app.post('/auth/entrar', limiteAuth, async (req, reply) => {
    const { email, senha } = credenciais.parse(req.body);
    const u = db.prepare('SELECT id, senha_hash FROM usuarios WHERE email = ?').get(email) as
      | Usuario
      | undefined;
    // Mesma resposta para e-mail inexistente e senha errada (não revela quais e-mails existem).
    if (!u || !(await bcrypt.compare(senha, u.senha_hash))) {
      return reply.code(401).send({ erro: 'credenciais_invalidas' });
    }
    return { token: app.jwt.sign({ sub: u.id }, { expiresIn: '30d' }), email };
  });

  // Exclusão total dos dados do usuário (LGPD): itens, uso e conta saem em cascata.
  app.delete('/conta', { preHandler: [app.autenticar] }, async (req, reply) => {
    db.prepare('DELETE FROM usuarios WHERE id = ?').run(req.user.sub);
    return reply.code(204).send();
  });
}

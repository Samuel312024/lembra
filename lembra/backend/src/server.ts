import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { config } from './config.js';
import './db.js';
import { rotasAuth } from './rotas/auth.js';
import { rotasIa } from './rotas/ia.js';
import { rotasReunioes } from './rotas/reunioes.js';
import { rotasSync } from './rotas/sync.js';

declare module 'fastify' {
  interface FastifyInstance {
    autenticar: (req: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
  }
}
declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { sub: string };
    user: { sub: string };
  }
}

const app = Fastify({ logger: true, bodyLimit: 2 * 1024 * 1024 });

await app.register(cors, { origin: config.CORS_ORIGIN === '*' ? true : config.CORS_ORIGIN.split(',') });
await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute' });
await app.register(jwt, { secret: config.JWT_SECRET });

app.decorate('autenticar', async (req: FastifyRequest, reply: FastifyReply) => {
  try {
    await req.jwtVerify();
  } catch {
    return reply.code(401).send({ erro: 'nao_autenticado' });
  }
});

app.setErrorHandler((err, _req, reply) => {
  if (err instanceof ZodError) {
    return reply.code(400).send({ erro: 'dados_invalidos', detalhes: err.flatten() });
  }
  app.log.error(err);
  const status = (err as { statusCode?: number }).statusCode ?? 500;
  return reply.code(status).send({ erro: status === 429 ? 'muitas_requisicoes' : 'erro_interno' });
});

app.get('/saude', async () => ({ ok: true, ia: Boolean(config.ANTHROPIC_API_KEY) }));

await app.register(rotasAuth);
await app.register(rotasSync);
await app.register(rotasIa);
await app.register(rotasReunioes);

await app.listen({ port: config.PORT, host: '0.0.0.0' });

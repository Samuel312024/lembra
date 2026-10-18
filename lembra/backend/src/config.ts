import { z } from 'zod';

const esquema = z.object({
  PORT: z.coerce.number().default(3000),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET precisa ter ao menos 16 caracteres'),
  DB_PATH: z.string().default('./data/lembra.db'),
  ANTHROPIC_API_KEY: z.string().optional(),
  ANTHROPIC_MODEL: z.string().default('claude-haiku-5-5'),
  LIMITE_IA_DIARIO: z.coerce.number().default(100),
  CORS_ORIGIN: z.string().default('*'),
});

export const config = esquema.parse(process.env);

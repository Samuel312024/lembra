import { z } from 'zod';

// Variável vazia no .env (ex.: "SMTP_PORT=") vale como "não definida".
const vazioVira = <T extends z.ZodTypeAny>(s: T) => z.preprocess((v) => (v === '' ? undefined : v), s);

const esquema = z.object({
  PORT: z.coerce.number().default(3000),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET precisa ter ao menos 16 caracteres'),
  DB_PATH: z.string().default('./data/lembra.db'),
  ANTHROPIC_API_KEY: z.string().optional(),
  ANTHROPIC_MODEL: z.string().default('claude-haiku-5-5'),
  LIMITE_IA_DIARIO: z.coerce.number().default(100),
  CORS_ORIGIN: z.string().default('*'),

  // ---- Convites de reunião ----
  // Endereço público do backend (é ele que aparece nos links dos e-mails).
  PUBLIC_URL: vazioVira(z.string().url().default('http://localhost:3000')),
  // Assina os links dos convites. Se vazio, usa o JWT_SECRET.
  CONVITE_SECRET: vazioVira(z.string().min(16).optional()),
  // Limite de participantes convidados por usuário a cada 24 h (controle de custo e de abuso).
  LIMITE_CONVITES_DIARIO: vazioVira(z.coerce.number().default(100)),

  // E-mail (SMTP). Sem SMTP_HOST o servidor não envia e-mail, mas ainda gera os links para compartilhar.
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: vazioVira(z.coerce.number().default(587)),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
  EMAIL_DE: vazioVira(z.string().default('Lembra <nao-responda@localhost>')),

  // Push (Firebase Cloud Messaging). Use UM dos dois. Sem nenhum, o push fica desligado.
  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().optional(),
  FIREBASE_SERVICE_ACCOUNT_BASE64: z.string().optional(),
});

export const config = esquema.parse(process.env);
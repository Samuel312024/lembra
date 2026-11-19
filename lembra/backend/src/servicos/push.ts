import { readFileSync } from 'node:fs';
import { cert, getApps, initializeApp, type ServiceAccount } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { config } from '../config.js';
import { db } from '../db.js';

let pronto: boolean | undefined;

/** Liga o Firebase na primeira vez que precisa. Sem chave configurada, o push fica desligado. */
function iniciar(): boolean {
  if (pronto !== undefined) return pronto;
  try {
    let conta: ServiceAccount | null = null;
    if (config.FIREBASE_SERVICE_ACCOUNT_BASE64) {
      conta = JSON.parse(Buffer.from(config.FIREBASE_SERVICE_ACCOUNT_BASE64, 'base64').toString('utf8'));
    } else if (config.FIREBASE_SERVICE_ACCOUNT_PATH) {
      conta = JSON.parse(readFileSync(config.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8'));
    }
    if (!conta) {
      pronto = false;
      return false;
    }
    if (getApps().length === 0) initializeApp({ credential: cert(conta) });
    pronto = true;
  } catch (e) {
    console.error('Firebase: não foi possível ler a chave da conta de serviço.', e);
    pronto = false;
  }
  return pronto;
}

export const pushConfigurado = () => iniciar();

export interface Push {
  titulo: string;
  corpo: string;
  /** O FCM só aceita texto nos valores. */
  dados: Record<string, string>;
}

/** Envia para todos os aparelhos do usuário e apaga os tokens que o Firebase diz estarem mortos. */
export async function enviarPush(usuarioId: string, push: Push): Promise<number> {
  if (!iniciar()) return 0;

  const tokens = (
    db.prepare('SELECT token FROM dispositivos WHERE usuario_id = ?').all(usuarioId) as unknown as {
      token: string;
    }[]
  ).map((r) => r.token);
  if (tokens.length === 0) return 0;

  const resposta = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: push.titulo, body: push.corpo },
    data: push.dados,
    android: {
      priority: 'high',
      // O app cria este canal; enquanto não existir, o Android usa o canal padrão do Firebase.
      notification: { channelId: 'respostas' },
    },
  });

  const apagar = db.prepare('DELETE FROM dispositivos WHERE token = ?');
  resposta.responses.forEach((r, i) => {
    const codigo = r.error?.code;
    if (
      codigo === 'messaging/registration-token-not-registered' ||
      codigo === 'messaging/invalid-registration-token'
    ) {
      apagar.run(tokens[i]!);
    }
  });
  return resposta.successCount;
}
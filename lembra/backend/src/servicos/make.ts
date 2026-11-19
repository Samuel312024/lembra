// backend/src/servicos/make.ts
export async function sendToMake(event: string, data: Record<string, unknown>) {
  const url = process.env.MAKE_WEBHOOK_URL;
  if (!url) return;
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ event, sentAt: new Date().toISOString(), data }),
    });
  } catch (err) {
    console.error('Falha ao avisar o Make', err); // não derruba o app se o Make cair
  }
}
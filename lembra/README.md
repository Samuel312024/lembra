# Lembra — lembretes e organização do dia a dia por voz

Falou → virou item → entrou na agenda → o alarme cobrou até você resolver.

- `flutter_app/` — app Flutter (Android e iOS)
- `backend/` — API Node.js + TypeScript (Fastify, SQLite embutido, JWT, IA com chave só no servidor)
- `scripts/setup.ps1` — prepara o app (gera `android/` e `ios/`, aplica permissões e dependências nativas)

## Requisitos

- Flutter 3.27+ (Dart 3.4+) e Android Studio/SDK
- Node.js **22.13+** (o backend usa o SQLite embutido do Node, então não compila nada no Windows)

## Rodando (PowerShell)

### 1) Backend

```powershell
cd backend
npm install
Copy-Item .env.example .env      # ajuste JWT_SECRET; ANTHROPIC_API_KEY é opcional
npm run dev                      # http://localhost:3000  (teste: http://localhost:3000/saude)
```

Sem `ANTHROPIC_API_KEY`, o app usa o interpretador local do aparelho (funciona offline, sem custo).

### 2) App

```powershell
.\scripts\setup.ps1              # uma vez
cd flutter_app
flutter analyze
flutter test                     # testes do interpretador de datas e dos comandos de voz
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

`10.0.2.2` é o seu PC visto pelo emulador Android. Em aparelho físico, use o IP do PC na rede (ex.: `http://192.168.0.10:3000`).

## Como usar por voz

**Criar** (o app mostra o cartão e você confirma; nada é agendado sem confirmação):

- “Tenho médico dia 22 às 14h30”
- “Lembra de pagar o condomínio sexta” → pergunta “Que horas?”
- “Todo dia às 8h me lembra do remédio”
- “Amanhã pagar a luz e ligar pro banco” → dois itens
- “Toda segunda e quarta às 7h academia”, “todo dia 5 pagar o aluguel”, “me avisa um dia antes”

**Cancelar, concluir e adiar** (comandos sobre itens que já existem):

- “Cancela o lembrete do médico” / “apaga o alarme da academia” → pede confirmação (por toque ou por voz) e oferece **Desfazer**
- “Marca como feito o remédio” / “já paguei o condomínio”
- “Adia o remédio por 1 hora” / “adia 10 minutos” / “adia a reunião para amanhã às 10”
- “O que eu tenho hoje?” / “o que tenho amanhã?” → mostra e lê a agenda em voz alta

Se o app não achar o item, pergunta qual você quis dizer (ou oferece criar um lembrete novo com a frase). No cartão de confirmação, o botão do microfone aceita “confirma”, “edita” e “descarta”.

## O que está pronto

| Fase | Status |
|---|---|
| 1 — Voz/texto → entendimento → cartão → lembrete local; tela Hoje e Próximos; recorrência | ✅ |
| 2 — Urgência (discreto/normal/crítico), antecedências por tipo, soneca inteligente (3ª vez pergunta), briefing da manhã, revisão da noite | ✅ |
| Extras — cancelar/concluir/adiar/listar por voz, resposta por voz ao cartão, desfazer, ler o dia (TTS), sincronização entre aparelhos, exclusão total de dados (LGPD), limite diário de IA | ✅ |
| 3 — Reuniões | ⏳ backend com `POST /reunioes/extrair` (texto → decisões, tarefas, dúvidas) e interface `ProvedorTranscricao`; falta a tela e o provedor de transcrição |
| 4 — Google Calendar, bloqueio de tempo, lembrete por local | ⏳ |
| 5 — Gravação ao vivo, colaboração por WhatsApp/e-mail, resumo compartilhável | ⏳ |

## Arquitetura em uma olhada

- **Entendimento**: o aparelho interpreta a frase na hora (offline). Com conta e internet, tenta a IA no servidor por até 3 s e valida o JSON; se falhar, usa o resultado local.
- **Cartão de confirmação**: se faltar dado essencial, faz **uma** pergunta curta (“Que horas?”, “hoje ou na próxima sexta?”) em vez de chutar.
- **Offline-first**: SQLite local; alarmes são locais. A sincronização envia só o que mudou; em conflito vence a alteração mais recente.
- **Alarmes**: `flutter_local_notifications` com alarme exato; o nível crítico usa tela cheia e repete o som até confirmar. Os alarmes são reagendados ao abrir o app e após reiniciar o aparelho.

## Limitações de plataforma (sem surpresa)

- **Android**: alarme exato e tela cheia exigem permissões, pedidas de forma guiada na primeira abertura e em Ajustes. Fabricantes com economia de bateria agressiva (Xiaomi, Samsung, etc.) podem matar o app; vale liberar “sem restrição de bateria”.
- **iPhone**: não existe alarme em segundo plano para apps comuns. O app usa notificações locais com som e prioridade “time-sensitive”, que **não** ignoram o modo Silencioso nem o Foco. O iOS também limita a 64 notificações pendentes por app. Para compilar para iOS é preciso um Mac; adicione em `ios/Runner/Info.plist` as chaves `NSMicrophoneUsageDescription` e `NSSpeechRecognitionUsageDescription`.
- Em itens semanais, cada dia da semana vira um alarme só no horário (sem antecedências extras); em itens mensais, também.

## Decisão: backend próprio ou Supabase/Firebase?

Escolhi **backend próprio (Fastify + SQLite)** para você ter o fluxo inteiro rodando local, com a chave de IA só no servidor e a lógica de sincronização visível.

- Próprio: controle total, custo zero para testar; em troca, você cuida de hospedagem e backup.
- Supabase: Postgres, auth e sincronização prontos; a melhor opção para produção. Recomendo migrar para ele quando for publicar — o contrato da API (`/auth`, `/sync`, `/ia/entender`) é pequeno e dá para manter.
- Firebase: bom em tempo real e push, mas o modelo de consultas é mais limitado para agenda.

Para trocar o provedor de transcrição (Whisper, Deepgram ou AssemblyAI) basta implementar `ProvedorTranscricao` em `backend/src/rotas/reunioes.ts`.

## Ideias que valem a pena a seguir

- Widget/atalho de tela inicial com o microfone (Android App Actions e Atalhos da Siri)
- “Hey Google, abre o Lembra e diz…” para criar sem tocar no celular
- Lembretes por local (“quando eu chegar no trabalho”) com geofence — Fase 4
- Hábitos com sequência de dias seguidos
- Modo “não perturbe” inteligente: adiar automaticamente avisos discretos durante reuniões do calendário

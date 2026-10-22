// Copie este arquivo para a MESMA pasta do MainActivity.kt
// (android/app/src/main/kotlin/<seu/pacote>/) e ajuste a linha "package" abaixo.
package com.example.lembra

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** Um disparo agendado (um item pode ter vários: antecedências, dias da semana...). */
data class AlarmeSlot(
    val chave: String,
    val itemId: String,
    val titulo: String,
    val corpo: String,
    val quando: Long,
    val freq: String?, // null = disparo único | DAILY | WEEKLY | MONTHLY
    val dia: Int,      // WEEKLY: 1 = segunda ... 7 = domingo
    val diaMes: Int,   // MONTHLY
    val hora: Int,
    val minuto: Int,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("chave", chave)
        put("itemId", itemId)
        put("titulo", titulo)
        put("corpo", corpo)
        put("quando", quando)
        put("freq", freq ?: JSONObject.NULL)
        put("dia", dia)
        put("diaMes", diaMes)
        put("hora", hora)
        put("minuto", minuto)
    }

    companion object {
        fun fromJson(o: JSONObject) = AlarmeSlot(
            chave = o.getString("chave"),
            itemId = o.getString("itemId"),
            titulo = o.getString("titulo"),
            corpo = o.getString("corpo"),
            quando = o.getLong("quando"),
            freq = if (o.isNull("freq")) null else o.getString("freq"),
            dia = o.getInt("dia"),
            diaMes = o.getInt("diaMes"),
            hora = o.getInt("hora"),
            minuto = o.getInt("minuto"),
        )
    }
}

/**
 * Guarda os disparos em SharedPreferences e os arma no AlarmManager com setAlarmClock
 * (o tipo "despertador": acorda o aparelho mesmo em Doze). Assim os alarmes sobrevivem
 * a reinício do celular e a app fechado, sem depender do Flutter estar rodando.
 */
object AlarmeStore {
    private const val PREFS = "lembra_alarmes"
    private const val CHAVE = "slots"
    private const val TOLERANCIA_PERDIDO_MS = 10 * 60 * 1000L

    @Synchronized
    fun todos(ctx: Context): MutableList<AlarmeSlot> {
        val json = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(CHAVE, "[]") ?: "[]"
        val lista = mutableListOf<AlarmeSlot>()
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) lista.add(AlarmeSlot.fromJson(arr.getJSONObject(i)))
        } catch (_: Exception) {
        }
        return lista
    }

    @Synchronized
    private fun salvar(ctx: Context, lista: List<AlarmeSlot>) {
        val arr = JSONArray()
        lista.forEach { arr.put(it.toJson()) }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(CHAVE, arr.toString()).apply()
    }

    fun buscar(ctx: Context, chave: String): AlarmeSlot? = todos(ctx).firstOrNull { it.chave == chave }

    fun agendar(ctx: Context, slot: AlarmeSlot) {
        val lista = todos(ctx)
        lista.removeAll { it.chave == slot.chave }
        lista.add(slot)
        salvar(ctx, lista)
        armar(ctx, slot)
    }

    fun remover(ctx: Context, chave: String) {
        val lista = todos(ctx)
        lista.removeAll { it.chave == chave }
        salvar(ctx, lista)
        desarmar(ctx, chave)
    }

    fun cancelarItem(ctx: Context, itemId: String) {
        val lista = todos(ctx)
        lista.filter { it.itemId == itemId }.forEach { desarmar(ctx, it.chave) }
        lista.removeAll { it.itemId == itemId }
        salvar(ctx, lista)
    }

    fun cancelarTudo(ctx: Context) {
        todos(ctx).forEach { desarmar(ctx, it.chave) }
        salvar(ctx, emptyList())
    }

    private fun pendente(ctx: Context, chave: String): PendingIntent {
        val i = Intent(ctx, AlarmeReceiver::class.java).apply {
            data = Uri.Builder().scheme("lembra").authority("alarme").appendPath(chave).build()
            putExtra("chave", chave)
        }
        return PendingIntent.getBroadcast(
            ctx, chave.hashCode(), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun armar(ctx: Context, slot: AlarmeSlot) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendente(ctx, slot.chave)
        val abrir = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()
        val mostrar = PendingIntent.getActivity(
            ctx, 0, abrir, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(slot.quando, mostrar), pi)
        } catch (_: SecurityException) {
            // Sem permissão de alarme exato: melhor esforço.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, slot.quando, pi)
        }
    }

    private fun desarmar(ctx: Context, chave: String) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendente(ctx, chave))
    }

    /** Próxima ocorrência estritamente depois de [depois] (mesma regra do Recorrencia.proxima do Dart). */
    fun proximo(slot: AlarmeSlot, depois: Long): Long? {
        val freq = slot.freq ?: return null
        val base = Calendar.getInstance().apply {
            timeInMillis = depois
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (i in 0..400) {
            val c = (base.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, i) }
            val dow = c.get(Calendar.DAY_OF_WEEK)
            val diaSemana = if (dow == Calendar.SUNDAY) 7 else dow - 1
            val ocorre = when (freq) {
                "DAILY" -> true
                "WEEKLY" -> diaSemana == slot.dia
                "MONTHLY" -> c.get(Calendar.DAY_OF_MONTH) == slot.diaMes
                else -> false
            }
            if (!ocorre) continue
            c.set(Calendar.HOUR_OF_DAY, slot.hora)
            c.set(Calendar.MINUTE, slot.minuto)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            if (c.timeInMillis > depois) return c.timeInMillis
        }
        return null
    }

    /** Depois de reiniciar o celular / mudar a hora: rearma tudo. */
    fun rearmarTudo(ctx: Context) {
        val agora = System.currentTimeMillis()
        val novos = mutableListOf<AlarmeSlot>()
        for (s in todos(ctx)) {
            var q = s.quando
            if (q <= agora) {
                q = if (s.freq != null) {
                    proximo(s, agora) ?: continue
                } else if (agora - q <= TOLERANCIA_PERDIDO_MS) {
                    agora + 3000 // alarme perdido há pouco (celular desligado): toca já
                } else {
                    continue
                }
            }
            novos.add(s.copy(quando = q))
        }
        salvar(ctx, novos)
        novos.forEach { armar(ctx, it) }
    }
}

/** Chamado pelo AlarmManager na hora exata. */
class AlarmeReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val chave = intent.getStringExtra("chave") ?: return
        val slot = AlarmeStore.buscar(ctx, chave) ?: return

        // Recorrente: já arma a próxima ocorrência; único: remove.
        val prox = if (slot.freq != null) AlarmeStore.proximo(slot, System.currentTimeMillis() + 1000) else null
        if (prox != null) AlarmeStore.agendar(ctx, slot.copy(quando = prox)) else AlarmeStore.remover(ctx, chave)

        val i = Intent(ctx, AlarmeService::class.java)
            .putExtra("itemId", slot.itemId)
            .putExtra("titulo", slot.titulo)
            .putExtra("corpo", slot.corpo)
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
    }
}

class AlarmeBootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        AlarmeStore.rearmarTudo(ctx)
    }
}

/**
 * Serviço em primeiro plano que toca o alarme: som no volume de ALARME (em loop),
 * vibração, acende a tela e abre o app por cima de tudo.
 */
@Suppress("DEPRECATION")
class AlarmeService : Service() {
    companion object {
        const val EXTRA_ITEM = "alarme_item"
        const val EXTRA_TITULO = "alarme_titulo"
        const val EXTRA_CORPO = "alarme_corpo"
        private const val ACAO_PARAR = "lembra.PARAR_ALARME"
        private const val CANAL = "alarme_tocando"
        private const val ID_NOTIFICACAO = 7731
        private const val LIMITE_MS = 10 * 60 * 1000L

        /** Alarme que está tocando agora (itemId, titulo, corpo) ou null. */
        @Volatile
        var atual: Map<String, String>? = null

        fun intentTela(ctx: Context, itemId: String, titulo: String, corpo: String): Intent =
            Intent(ctx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra(EXTRA_ITEM, itemId)
                putExtra(EXTRA_TITULO, titulo)
                putExtra(EXTRA_CORPO, corpo)
            }

        fun parar(ctx: Context) {
            atual = null
            ctx.stopService(Intent(ctx, AlarmeService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var vibrador: Vibrator? = null
    private var wake: PowerManager.WakeLock? = null
    private var sobreposicao: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACAO_PARAR) {
            atual = null
            stopSelf()
            return START_NOT_STICKY
        }
        val itemId = intent?.getStringExtra("itemId") ?: ""
        val titulo = intent?.getStringExtra("titulo") ?: "Alarme"
        val corpo = intent?.getStringExtra("corpo") ?: ""
        atual = mapOf("itemId" to itemId, "titulo" to titulo, "corpo" to corpo)

        iniciarPrimeiroPlano(itemId, titulo, corpo)
        silenciar() // se já havia outro alarme tocando, recomeça limpo
        acordarTela()
        tocarSom()
        vibrar()
        abrirTela(itemId, titulo, corpo)
        handler.postDelayed({ stopSelf() }, LIMITE_MS) // desiste após 10 min
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        silenciar()
        atual = null
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        super.onDestroy()
    }

    private fun iniciarPrimeiroPlano(itemId: String, titulo: String, corpo: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val canal = NotificationChannel(CANAL, "Alarme tocando", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Mostra o alarme que está tocando"
                setSound(null, null) // o som é tocado pelo serviço, no volume de alarme
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(canal)
        }
        val flagsPi = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val tela = PendingIntent.getActivity(this, 1, intentTela(this, itemId, titulo, corpo), flagsPi)
        val parar = PendingIntent.getService(
            this, 2, Intent(this, AlarmeService::class.java).setAction(ACAO_PARAR), flagsPi,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CANAL) else Notification.Builder(this)
        b.setSmallIcon(applicationInfo.icon)
            .setContentTitle(titulo)
            .setContentText(if (corpo.isEmpty()) "Alarme" else corpo)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(tela)
            .setFullScreenIntent(tela, true)
            .addAction(0, "Parar", parar)
        if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_MAX)
        val n = b.build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID_NOTIFICACAO, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID_NOTIFICACAO, n)
        }
    }

    private fun acordarTela() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val w = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "lembra:alarme",
            )
            w.acquire(60_000L)
            wake = w
        } catch (_: Exception) {
        }
    }

    private fun tocarSom() {
        try {
            // Garante um volume de alarme audível (pelo menos 70% do máximo).
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val minimo = (max * 0.7).toInt().coerceAtLeast(1)
            if (am.getStreamVolume(AudioManager.STREAM_ALARM) < minimo) {
                am.setStreamVolume(AudioManager.STREAM_ALARM, minimo, 0)
            }
        } catch (_: Exception) {
        }
        val candidatos = listOfNotNull(
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
        )
        for (uri in candidatos) {
            var p: MediaPlayer? = null
            try {
                p = MediaPlayer()
                p.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                p.setDataSource(this, uri)
                p.isLooping = true
                p.prepare()
                p.start()
                player = p
                return
            } catch (_: Exception) {
                try {
                    p?.release()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun vibrar() {
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val padrao = longArrayOf(0, 900, 500)
            if (Build.VERSION.SDK_INT >= 26) {
                val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
                v.vibrate(VibrationEffect.createWaveform(padrao, 0), attrs)
            } else {
                v.vibrate(padrao, 0)
            }
            vibrador = v
        } catch (_: Exception) {
        }
    }

    /**
     * Abre o app por cima de qualquer coisa. Com a permissão "Exibir sobre outros apps",
     * uma janela de 1 px é criada antes (o Android 15 exige uma sobreposição visível para
     * liberar startActivity em segundo plano). A notificação com fullScreenIntent cobre
     * o caso de tela bloqueada se algo disso falhar.
     */
    private fun abrirTela(itemId: String, titulo: String, corpo: String) {
        if (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)) mostrarSobreposicao()
        val intent = intentTela(this, itemId, titulo, corpo)
        handler.postDelayed({
            try {
                startActivity(intent)
            } catch (_: Exception) {
            }
        }, 300)
        handler.postDelayed({ removerSobreposicao() }, 8000)
    }

    private fun mostrarSobreposicao() {
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val tipo = if (Build.VERSION.SDK_INT >= 26) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val lp = WindowManager.LayoutParams(
                1, 1, tipo,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT,
            )
            val v = View(this)
            wm.addView(v, lp)
            sobreposicao = v
        } catch (_: Exception) {
        }
    }

    private fun removerSobreposicao() {
        try {
            sobreposicao?.let { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) }
        } catch (_: Exception) {
        }
        sobreposicao = null
    }

    private fun silenciar() {
        handler.removeCallbacksAndMessages(null)
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        try {
            vibrador?.cancel()
        } catch (_: Exception) {
        }
        vibrador = null
        try {
            if (wake?.isHeld == true) wake?.release()
        } catch (_: Exception) {
        }
        wake = null
        removerSobreposicao()
    }
}
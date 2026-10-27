package com.samsolution.mylembra

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.*

object AlarmeSom {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private val pararDepois = Runnable { parar() }

    private val atributos = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    private fun uriPadrao(ctx: Context, uri: String?): Uri {
        val tipo = when {
            uri?.contains("ringtone") == true -> RingtoneManager.TYPE_RINGTONE
            uri?.contains("notification") == true -> RingtoneManager.TYPE_NOTIFICATION
            else -> RingtoneManager.TYPE_ALARM
        }
        return RingtoneManager.getActualDefaultRingtoneUri(ctx, tipo)
            ?: RingtoneManager.getDefaultUri(tipo)
    }

    /** repetir = true: alarme de verdade (loop, vibra, até 10 min). false: prévia de 8 s. */
    @Synchronized
    fun tocar(ctx: Context, recurso: String?, uri: String?, repetir: Boolean) {
        parar()
        val app = ctx.applicationContext
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(atributos)
            val id = if (recurso.isNullOrEmpty()) 0 else app.resources.getIdentifier(recurso, "raw", app.packageName)
            if (id != 0) {
                app.resources.openRawResourceFd(id).use { afd ->
                    mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                }
            } else {
                mp.setDataSource(app, uriPadrao(app, uri))
            }
            mp.isLooping = repetir
            mp.setOnCompletionListener { if (!repetir) parar() }
            mp.setOnErrorListener { _, _, _ -> parar(); true }
            mp.prepare()
            mp.start()
            player = mp
        } catch (e: Exception) {
            parar()
            return
        }

        val pm = app.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lembra:alarme").apply { acquire(10 * 60 * 1000L) }

        if (repetir) {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
                (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val padrao = longArrayOf(0, 600, 400)
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(padrao, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(padrao, 0)
            }
            vibrator = v
        }
        handler.postDelayed(pararDepois, if (repetir) 10 * 60 * 1000L else 8000L)
    }

    @Synchronized
    fun parar() {
        handler.removeCallbacks(pararDepois)
        player?.let {
            try { if (it.isPlaying) it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
        vibrator?.cancel(); vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
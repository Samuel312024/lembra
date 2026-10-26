// Substitui o seu MainActivity.kt (se o seu tiver código extra, mescle).
// Ajuste a linha "package" para a mesma do seu arquivo original.
package com.samsolution.mylembra

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {
    private var canal: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ehAlarme(intent)) prepararJanela()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (ehAlarme(intent)) {
            prepararJanela()
            AlarmeService.atual?.let { canal?.invokeMethod("tocando", it) }
        }
    }

    private fun ehAlarme(i: Intent?) = i?.hasExtra(AlarmeService.EXTRA_ITEM) == true

    /** Só durante o alarme: aparece sobre o bloqueio, acende a tela e a mantém acesa. */
    private fun prepararJanela() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun soltarJanela() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ctx = applicationContext
        val c = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lembra/alarme")
        canal = c
        c.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "agendar" -> {
                        val slot = AlarmeSlot(
                            chave = call.argument<String>("chave")!!,
                            itemId = call.argument<String>("itemId")!!,
                            titulo = call.argument<String>("titulo") ?: "",
                            corpo = call.argument<String>("corpo") ?: "",
                            quando = call.argument<Number>("quando")!!.toLong(),
                            freq = call.argument<String>("freq"),
                            dia = call.argument<Number>("dia")?.toInt() ?: 0,
                            diaMes = call.argument<Number>("diaMes")?.toInt() ?: 0,
                            hora = call.argument<Number>("hora")?.toInt() ?: 0,
                            minuto = call.argument<Number>("minuto")?.toInt() ?: 0,
                        )
                        AlarmeStore.agendar(ctx, slot)
                        result.success(true)
                    }
                    "cancelarItem" -> {
                        AlarmeStore.cancelarItem(ctx, call.argument<String>("itemId")!!)
                        result.success(true)
                    }
                    "cancelarTudo" -> {
                        AlarmeStore.cancelarTudo(ctx)
                        result.success(true)
                    }
                    "parar" -> {
                        AlarmeService.parar(ctx)
                        soltarJanela()
                        result.success(true)
                    }
                    "alarmeAtual" -> result.success(AlarmeService.atual)
                    "temSobreposicao" ->
                        result.success(Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(ctx))
                    "pedirSobreposicao" -> {
                        val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        startActivity(i)
                        result.success(true)
                    }
                    "podeAlarmeExato" -> {
                        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        result.success(Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("alarme", e.message, null)
            }
        }
    }
}

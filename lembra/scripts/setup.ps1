# Prepara o app Flutter: gera as pastas de plataforma (android/ios), aplica as permissões
# e dependências nativas necessárias e baixa os pacotes.
# Uso (PowerShell, a partir da raiz do projeto):   .\scripts\setup.ps1
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$app = Join-Path $raiz 'flutter_app'
Set-Location $app

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter não encontrado no PATH. Instale em https://docs.flutter.dev/get-started/install/windows'
}

if (-not (Test-Path 'android')) {
    Write-Host '>> Gerando os projetos de plataforma (flutter create)...'
    flutter create . --project-name lembra --org br.com.lembra --platforms android,ios
}
# O flutter create pode recriar o teste de exemplo, que não existe neste projeto.
if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' -Force }

# ---------- AndroidManifest.xml ----------
$manifest = 'android\app\src\main\AndroidManifest.xml'
$xml = Get-Content $manifest -Raw
if ($xml -notmatch 'RECORD_AUDIO') {
    Write-Host '>> Aplicando permissões e receivers no AndroidManifest.xml...'
    $perms = @'

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
    </queries>
'@
    $receivers = @'

        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'@
    $xml = [regex]::new('(<manifest[^>]*>)').Replace($xml, ('$1' + $perms), 1)
    $xml = $xml -replace '</application>', ($receivers + "`n    </application>")
    # Alarme crítico precisa acender a tela e aparecer sobre a tela de bloqueio.
    $xml = [regex]::new('<activity\s').Replace($xml, '<activity android:showWhenLocked="true" android:turnScreenOn="true" ', 1)
    Set-Content -Path $manifest -Value $xml -Encoding UTF8
}

# ---------- build.gradle.kts (desugaring exigido pelo flutter_local_notifications; minSdk 24) ----------
$gradle = 'android\app\build.gradle.kts'
if (Test-Path $gradle) {
    $g = Get-Content $gradle -Raw
    if ($g -notmatch 'isCoreLibraryDesugaringEnabled') {
        Write-Host '>> Ajustando build.gradle.kts...'
        $g = $g -replace 'compileOptions\s*\{', ("compileOptions {`n        isCoreLibraryDesugaringEnabled = true")
        $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
        $g += "`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
        Set-Content -Path $gradle -Value $g -Encoding UTF8
    }
} else {
    Write-Warning 'build.gradle.kts não encontrado (projeto com Gradle Groovy?). Veja o README para o ajuste manual.'
}

Write-Host '>> Baixando pacotes...'
flutter pub get

Write-Host ''
Write-Host 'Pronto. Próximos passos:'
Write-Host '  flutter analyze'
Write-Host '  flutter test'
Write-Host '  flutter run --dart-define=API_URL=http://10.0.2.2:3000   # emulador Android falando com a API no seu PC'

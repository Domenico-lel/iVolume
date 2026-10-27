# iVolume

**Controlla il volume del Mac, anche con cuffie collegate a una TV HDMI.**

Un’applicazione di **Domenico Lella** per macOS, con finestra nativa e icona nella barra dei menu.

## Scarica e installa

[**Scarica iVolume 0.10.0 per Mac Intel**](https://github.com/Domenico-lel/iVolume/raw/refs/heads/main/iVolume-0.10.0-Intel.zip).

1. Estrai il file ZIP e sposta **iVolume.app** in Applicazioni.
2. Apri l’app e seleziona l’uscita audio desiderata.
3. Premi **Attiva controllo audio** e consenti l’accesso al solo audio di sistema.
4. Per usare i tasti volume e muto, abilita iVolume in **Impostazioni di Sistema → Privacy e sicurezza → Accessibilità**.
5. Avvia una riproduzione: il controllo si attiva quando riceve audio.

Il pacchetto è firmato localmente con un certificato Apple Development, ma **non è notarizzato per la distribuzione pubblica**: macOS può richiedere l’autorizzazione all’apertura. Non contiene certificati privati o chiavi di firma.

Il download qui sopra punta al pacchetto aggiornato nel repository. Le precedenti release e i collegamenti di aggiornamento del launcher non sono stati sostituiti.

## Novità della versione 0.10.0 · build 12

- Finestra apribile avviando l’app e da **Apri iVolume** nel menu dell’icona.
- Volume generale software per uscite HDMI, mantenendo le cuffie collegate alla presa AUX del televisore.
- Supporto ai tasti volume e muto del Mac, con indicatore a schermo.
- Volume separato delle applicazioni e memorizzazione dei livelli.
- Ripresa del controllo alla riapertura dell’app, se era stato attivato.
- Correzione del crash causato dall’aggiornamento ricorsivo del valore del volume.

Chiudere la finestra lascia attiva l’app. **Disattiva** oppure **Esci da iVolume** ripristinano il normale percorso audio: il livello torna a essere gestito dalla TV. Il cursore volume HDMI integrato di macOS può restare disabilitato; si usano i tasti intercettati da iVolume o il cursore della sua finestra.

Il 100% corrisponde al segnale originale, senza amplificazione. L’audio viene elaborato in memoria e non viene salvato o inviato in rete.

## Compatibilità

- macOS **14.2 o successivo**.
- Pacchetto incluso: **Intel x86_64**, verificato su macOS 15.8.1 con uscita HDMI stereo a 48 kHz.
- Motore per flussi **PCM stereo Float32**; audio multicanale non supportato.
- Su Apple Silicon è possibile compilare dai sorgenti per arm64. Il pacchetto Intel richiede Rosetta e non è stato verificato su Apple Silicon.
- I cambi di uscita o composizione del mixer possono causare una breve interruzione audio.

## Sorgenti e compilazione

Il repository ora include il sorgente della versione 0.10.0, ricostruita perché della precedente 0.9.0 era disponibile solo il pacchetto compilato. Il vecchio ZIP resta disponibile per il ripristino.

Servono Xcode e il relativo SDK macOS:

```sh
bash build.sh
```

Lo script genera `dist/iVolume.app` per l’architettura del Mac. Per usare un certificato di firma stabile:

```sh
CODE_SIGN_IDENTITY="Nome del proprio certificato" bash build.sh
```

In assenza della variabile viene usata una firma ad hoc; ricompilare può richiedere di concedere nuovamente i permessi di macOS.

Il rendering audio è implementato in C, senza allocazioni o lock nel callback; finestra e gestione del percorso audio sono in Swift, AppKit e SwiftUI. Vengono usate le API pubbliche [Core Audio taps di Apple](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).

## Verifiche

Verificati sul Mac di sviluppo: riproduzione reale, attenuazione misurata, muto, tasti della tastiera, finestra e volume separato di Spotify. I test includono il rendering con AddressSanitizer/UndefinedBehaviorSanitizer e una regressione su aggiornamenti ripetuti di volume, muto e limiti 0–100%.

Per eseguire i test del rendering:

```sh
mkdir -p build
xcrun clang -O1 -g -fsanitize=address,undefined Render.c RenderTests.c -o build/render-tests
build/render-tests
```

Il test `ModelTests.swift` può essere compilato insieme a `Audio.swift`, `Model.swift` e `build/Render.o`, usando `-import-objc-header Render.h` e i framework AppKit, CoreAudio e ApplicationServices. Esegue modifiche in un dominio di preferenze temporaneo; non eseguirlo mentre si sta verificando il file diagnostico dell’app, perché scrive nello stesso percorso di stato.

Non sono state effettuate prove fisiche di sospensione o scollegamento dell’uscita durante questa verifica.

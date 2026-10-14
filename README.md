# iVolume

**Volume separato per le applicazioni su macOS.**

Un’applicazione di **Domenico Lella** per regolare separatamente il volume delle applicazioni sul Mac.

## Scarica e installa

**[Scarica iVolume.app.zip](https://github.com/Domenico-lel/iVolume/releases/latest/download/iVolume.app.zip)** dalla [release ufficiale](https://github.com/Domenico-lel/iVolume/releases/latest).

1. Estrai il file ZIP.
2. Trascina **iVolume.app** nella cartella **Applicazioni**.
3. Apri l’app. Consenti l’accesso all’audio di sistema quando macOS lo richiede: serve per regolare il volume delle applicazioni.

Per installare e gestire gli aggiornamenti puoi usare anche **[iDom Launcher](https://github.com/Domenico-lel/iDom-Hub/releases/latest)**. I collegamenti **Source code** aggiunti da GitHub non sono installer.

## Versione e compatibilità

| Voce | Pacchetto attualmente distribuito |
| --- | --- |
| Versione | **0.9.0** (build 10) |
| Sistema | **macOS 14.2 o successivo** |
| Processore | **Intel, x86_64** |
| Mac Apple Silicon | Richiede **Rosetta** per eseguire il pacchetto Intel |
| Windows | Non disponibile |

Rosetta è la tecnologia Apple che permette ai Mac con chip Apple Silicon, come M1 e successivi, di eseguire applicazioni compilate per Intel. Se necessario, macOS propone di installarla quando apri l’app. [Spiegazione ufficiale Apple](https://support.apple.com/102527).

Questi dati sono stati verificati nel bundle distribuito (`Info.plist` e architettura dell’eseguibile). Il pacchetto attuale **non è universale**. Il tag della release si chiama `iVolume`; il numero reale dell’app è **0.9.0**.

## Aggiornamenti

In iDom Launcher, quando esce una nuova release compatibile compare **Aggiorna**. Chiudi iVolume prima di aggiornarlo. Per collegare una copia già installata alla release iniziale, che usa un tag senza numero, usa **Collega al launcher** nei dettagli dell’app.

Per le prossime pubblicazioni usa tag numerici, per esempio `v0.9.1`, allineati a `CFBundleShortVersionString`, e allega `iVolume.app.zip` o `iVolume.dmg`. La pubblicazione di un README non cambia la versione del pacchetto già distribuito.

## Contenuto del repository

Questo repository distribuisce il pacchetto compilato. Attualmente contiene `iVolume-0.9.0-Intel.zip`; per l’installazione consigliamo il file **iVolume.app.zip** nella sezione Releases. Il codice sorgente e le istruzioni di compilazione non sono presenti.

## Segnalazioni

Per segnalare un problema usa [Issues](https://github.com/Domenico-lel/iVolume/issues), indicando versione di macOS, modello del Mac e passaggi per riprodurlo.

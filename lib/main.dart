import 'package:flutter_svg/flutter_svg.dart';
import 'smart_scan_page.dart';

import 'energy_service.dart';
import 'energy_widget.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'login_page.dart';

import 'dart:io'; // Per File
import 'dart:ui'; // Per effetti Glass (BackdropFilter)
import 'package:flutter/services.dart'; // Per status bar e assets
import 'package:path_provider/path_provider.dart'; // Per trovare la cartella temp

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:intl/intl.dart'; // Per formattare le date

import 'database_helper.dart';
import 'package:true_lens_ai_v2/src/rust/frb_generated.dart'; // Importa Rust
import 'package:true_lens_ai_v2/src/rust/api/ai_engine.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

// --- TEMA & STILI ---
class AppTheme {
  static const Color background = Color(0xFF000000); // Nero Assoluto OLED
  static const Color surface = Color(0xFF121212); // Grigio scuro
  static const Color accentPurple = Color(0xFFBB86FC); // Viola Neon
  static const Color fakeRed = Color(0xFFCF6679); // Rosso Pastello
  static const Color realGreen = Color(0xFF03DAC6); // Verde Acqua
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF8E8E93);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza Firebase
  await Firebase.initializeApp();

  // Impostiamo la UI di sistema trasparente per immersività
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
    ),
  );

  await RustLib.init();
  print("✅ Rust inizializzato con successo");

  runApp(const TruthLensApp());
}

class TruthLensApp extends StatelessWidget {
  const TruthLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'True Lens V2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.background,
        primaryColor: AppTheme.accentPurple,
        useMaterial3: true,
        fontFamily: 'Roboto', // Default font
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppTheme.textWhite),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return const HomePage(); // Utente loggato!
          }
          return const LoginPage(); // Utente sloggato!
        },
      ),
    );
  }
}

class AnalysisRecord {
  final int? id;
  final String text;
  final String status; // CLAIM, IGNORE, ERROR, PROCESSING
  final bool? isFake;
  final double confidence;
  final DateTime timestamp;
  // --- NUOVI CAMPI ---
  final int localTimeMs; // Tempo Rust
  final int cloudTimeMs; // Tempo API

  AnalysisRecord({
    this.id,
    required this.text,
    required this.status,
    this.isFake,
    this.confidence = 0.0,
    required this.timestamp,
    this.localTimeMs = 0,
    this.cloudTimeMs = 0,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _energy = 5;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Usiamo una lista di AnalysisRecord invece di ChatMessage
  List<AnalysisRecord> _records = [];
  bool _isLoading = false;

  final String serverIp = "http://46.101.180.80";

  // Variabili Voce
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;

  // Variabili Sharing
  late StreamSubscription _intentDataStreamSubscription;

  late AiModel _aiEngine;

  @override
  void initState() {
    super.initState();
    _loadHistory(); // Carica e converte la storia
    _loadEnergy();
    _initVoice();
    _initSharingListener();
    _initAiEngine();

    _textController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _loadEnergy() async {
    int e = await EnergyService.instance.getEnergy();
    setState(() => _energy = e);
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- INIT ENGINE (RUST & ASSETS) ---
  Future<String> _copyAssetToLocal(String assetName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$assetName';
    final file = File(filePath);
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/models/$assetName');
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes);
      print("✅ Modello estratto in: $filePath");
    }
    return filePath;
  }

  Future<void> _initAiEngine() async {
    try {
      final modelPath = await _copyAssetToLocal("ai_model.onnx");
      final tokenizerPath = await _copyAssetToLocal("tokenizer.json");
      _aiEngine = await AiModel.new(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
      );
      print("✅ Motore AI e Tokenizer caricati!");
    } catch (e) {
      print("❌ Errore caricamento AI: $e");
    }
  }

  // --- GESTIONE CONDIVISIONE ---
  void _initSharingListener() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
          if (value.isNotEmpty && value.first.path.isNotEmpty) {
            setState(() => _textController.text = value.first.path);
          }
        }, onError: (err) => print("Errore sharing: $err"));

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty && value.first.path.isNotEmpty) {
        setState(() => _textController.text = value.first.path);
      }
    });
  }

  // --- GESTIONE VOCE ---
  void _initVoice() async {
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    await _speech.initialize();
    await _flutterTts.setLanguage("it-IT");
  }

  void _listen() async {
    HapticFeedback.lightImpact(); // Vibrazione
    print(
      "🎤 Tasto microfono premuto. Stato attuale isListening: $_isListening",
    );

    if (!_isListening) {
      // PROVIAMO AD AVVIARE
      print("🔄 Tentativo inizializzazione SpeechToText...");

      try {
        bool available = await _speech.initialize(
          onStatus: (status) => print('🎤 Status voce: $status'),
          onError: (errorNotification) =>
              print('❌ Errore voce: $errorNotification'),
        );

        print("✅ SpeechToText inizializzato. Disponibile? $available");

        if (available) {
          setState(() => _isListening = true);
          print("🔴 Inizio ascolto...");

          _speech.listen(
            onResult: (val) {
              print("🗣️ Parole rilevate: ${val.recognizedWords}");
              setState(() {
                _textController.text = val.recognizedWords;
              });
            },
            localeId: "it_IT",
            cancelOnError: true,
            listenMode: stt.ListenMode.dictation,
          );
        } else {
          print(
            "⛔ L'utente ha negato i permessi o il dispositivo non supporta la voce.",
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Impossibile accedere al microfono 🎤"),
            ),
          );
        }
      } catch (e) {
        print("💥 Eccezione durante _listen: $e");
      }
    } else {
      // STOP
      print("⏹️ Stop ascolto richiesto.");
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) await _flutterTts.speak(text);
  }

  // --- OCR SCANNER ---
  Future<void> _scanImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      setState(() => _isLoading = true);
      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      String extractedText = recognizedText.text;
      await textRecognizer.close();

      if (extractedText.isNotEmpty) {
        setState(
          () => _textController.text = extractedText.replaceAll('\n', ' '),
        );
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Testo estratto! 📸")));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Errore OCR: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- STORIA E DB ---
  Future<void> _loadHistory() async {
    // 1. Otteniamo l'utente corrente da Firebase
    final user = AuthService.instance.currentUser;

    // Se l'utente non è loggato, puliamo la lista e usciamo
    if (user == null) {
      setState(() {
        _records = [];
      });
      return;
    }

    // 2. Chiediamo al DB solo i messaggi di QUESTO utente
    final data = await DatabaseHelper.instance.getMessages(user.uid);

    setState(() {
      _records = data.map((row) {
        // Recuperiamo il testo completo
        String fullText = row['text'];

        // Determiniamo se è un messaggio dell'utente o del sistema
        bool isUser = row['isUser'] == 1;

        // Gestione del booleano isFake (che nel DB è 0, 1 o NULL)
        bool? isFake;
        if (row['isFake'] == 1)
          isFake = true;
        else if (row['isFake'] == 0)
          isFake = false;
        else
          isFake = null;

        // Logica per determinare lo STATUS (per colorare la card)
        String status = "UNKNOWN";
        if (isUser) {
          status = "USER_INPUT"; // O qualsiasi status usi per i messaggi utente
        } else {
          // Cerchiamo parole chiave nel testo salvato per capire lo stato
          if (fullText.contains("FILTRO SUPERATO")) {
            status = "CLAIM";
          } else if (fullText.contains("FILTRO BLOCCATO") ||
              fullText.contains("IGNORE")) {
            status = "IGNORE";
          } else if (fullText.contains("Errore") ||
              fullText.contains("ERROR")) {
            status = "ERROR";
          } else {
            // Fallback se è un claim vecchio o non standard
            status = "CLAIM";
          }
        }

        // 3. Creiamo l'oggetto AnalysisRecord
        return AnalysisRecord(
          id: row['id'],
          text: fullText,
          status: status,
          isFake: isFake,
          // Parsing della data (se fallisce usa "adesso")
          timestamp: DateTime.tryParse(row['time']) ?? DateTime.now(),
          // I nuovi campi per le metriche (se nulli metti 0)
          localTimeMs: row['localTime'] ?? 0,
          cloudTimeMs: row['cloudTime'] ?? 0,
        );
      }).toList();
    });
  }

  // --- CORE LOGIC (Gestione Invio) ---
  Future<void> _handleSubmitted(String text) async {
    if (text.isEmpty) return;

    // 1. RECUPERIAMO L'UTENTE CORRENTE (Importante!)
    final user = AuthService.instance.currentUser;
    if (user == null) {
      // Se per assurdo non c'è utente, mostriamo errore e usciamo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Errore: Utente non loggato")),
      );
      return;
    }

    _textController.clear();
    _speech.stop();
    setState(() => _isListening = false);

    final stopwatch = Stopwatch();
    int rustTime = 0;
    int cloudTime = 0;

    final tempRecord = AnalysisRecord(
      text: text,
      status: "PROCESSING",
      timestamp: DateTime.now(),
    );
    setState(() {
      _records.insert(0, tempRecord);
      _isLoading = true;
    });

    // 2. SALVIAMO INPUT UTENTE (Passiamo user.uid)
    await DatabaseHelper.instance.insertMessage(text, true, user.uid);

    try {
      // --- FASE 1: RUST (Locale) ---
      stopwatch.start();
      final String rawResult = await _aiEngine.checkSentence(text: text);
      stopwatch.stop();
      rustTime = stopwatch.elapsedMilliseconds;
      stopwatch.reset();

      if (rawResult.startsWith("ERROR") || !rawResult.contains("|")) {
        throw Exception(rawResult);
      }

      final parts = rawResult.split('|');
      final decision = parts[0];
      final scoreStr = parts[1];
      double score = double.tryParse(scoreStr) ?? 0.0;

      String statusText = decision == "CLAIM"
          ? "✅ FILTRO SUPERATO (Rilevanza: $scoreStr%)"
          : "⛔ FILTRO BLOCCATO (Rilevanza: $scoreStr%)";

      AnalysisRecord finalRecord;

      if (decision == "IGNORE") {
        String msg =
            "CLAIM: $text\n\n$statusText\nIl testo non sembra un claim politico verificabile.";

        finalRecord = AnalysisRecord(
          text: msg,
          status: "IGNORE",
          confidence: score,
          timestamp: DateTime.now(),
          isFake: null,
          localTimeMs: rustTime,
          cloudTimeMs: 0,
        );

        // 3. SALVIAMO RISPOSTA IGNORE (Passiamo user.uid)
        await DatabaseHelper.instance.insertMessage(
          msg,
          false,
          user.uid,
          isFake: null,
          localTime: rustTime,
          cloudTime: 0,
        );
      } else if (decision == "CLAIM") {
        // --- CONTROLLO ENERGIA ---
        // Prima di chiamare il server, controlliamo se abbiamo benzina
        bool hasEnergy = await EnergyService.instance.consumeEnergy();

        // Aggiorniamo subito la UI per far vedere che la tacca scende
        _loadEnergy();

        if (!hasEnergy) {
          // ENERGIA FINITA!
          String msg =
              "CLAIM: $text\n\n⛔ ENERGIA ESAURITA.\nIl filtro locale ha rilevato un claim, ma non hai abbastanza energia cloud per verificarlo oggi.";

          // Salviamo come errore/blocco
          AnalysisRecord finalRecord = AnalysisRecord(
            text: msg,
            status: "ERROR",
            timestamp: DateTime.now(),
            localTimeMs: rustTime,
            cloudTimeMs: 0,
          );

          await DatabaseHelper.instance.insertMessage(
            msg,
            false,
            user.uid,
            isFake: null,
            localTime: rustTime,
            cloudTime: 0,
          );

          setState(() {
            _records.removeAt(0);
            _records.insert(0, finalRecord);
            _isLoading = false; // Fermiamo il caricamento
          });

          // Mostra dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Batteria Scarica 🪫"),
              content: const Text(
                "Hai esaurito le 5 analisi Cloud giornaliere.\n\nL'analisi locale (Rust) continuerà a funzionare gratuitamente.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
          return;
        }
        // -------------------------

        // --- FASE 2: CLOUD (RAG) ---
        final url = Uri.parse('$serverIp/api/check');

        try {
          stopwatch.start();
          final response = await http
              .post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "claim": text,
                  "timestamp": DateTime.now().toIso8601String(),
                }),
              )
              .timeout(const Duration(seconds: 180));

          stopwatch.stop();
          cloudTime = stopwatch.elapsedMilliseconds;

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            String explanation =
                data['explanation'] ?? data['messaggio'] ?? "Nessun dettaglio.";
            String verdict = data['verdict'] ?? "UNKNOWN";

            String sourcesText = "";
            if (data['sources'] != null &&
                (data['sources'] as List).isNotEmpty) {
              sourcesText =
                  "\n\n📚 FONTI CITATE:\n" +
                  (data['sources'] as List).map((s) => "• $s").join("\n");
            }

            String fullMsg =
                "CLAIM: $text\n\n$statusText\n☁️ RAG Cloud: $explanation$sourcesText";

            bool? fakeStatus;
            String vUpper = verdict.toUpperCase();
            if (vUpper.contains("FALSE") || vUpper.contains("FAKE"))
              fakeStatus = true;
            else if (vUpper.contains("TRUE") || vUpper.contains("REAL"))
              fakeStatus = false;
            else
              fakeStatus = null;

            finalRecord = AnalysisRecord(
              text: fullMsg,
              status: "CLAIM",
              confidence: score,
              isFake: fakeStatus,
              timestamp: DateTime.now(),
              localTimeMs: rustTime,
              cloudTimeMs: cloudTime,
            );

            // 4. SALVIAMO RISPOSTA RAG (Passiamo user.uid)
            await DatabaseHelper.instance.insertMessage(
              fullMsg,
              false,
              user.uid,
              isFake: fakeStatus,
              localTime: rustTime,
              cloudTime: cloudTime,
            );
          } else {
            throw Exception("Status ${response.statusCode}");
          }
        } catch (e) {
          String err = "CLAIM: $text\n\n$statusText\n❌ Errore Server: $e";
          finalRecord = AnalysisRecord(
            text: err,
            status: "ERROR",
            confidence: score,
            timestamp: DateTime.now(),
            localTimeMs: rustTime,
            cloudTimeMs: 0,
          );
          // 5. SALVIAMO ERRORE SERVER (Passiamo user.uid)
          await DatabaseHelper.instance.insertMessage(
            err,
            false,
            user.uid,
            isFake: null,
            localTime: rustTime,
            cloudTime: 0,
          );
        }
      } else {
        throw Exception("Unknown decision");
      }

      setState(() {
        _records.removeAt(0);
        _records.insert(0, finalRecord);
      });

      if (finalRecord.status != "ERROR") {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.vibrate();
      }
    } catch (e) {
      String err = "Errore Tecnico: $e";
      setState(() {
        _records.removeAt(0);
        _records.insert(
          0,
          AnalysisRecord(
            text: "CLAIM: $text\n\n$err",
            status: "ERROR",
            timestamp: DateTime.now(),
          ),
        );
      });
      // 6. SALVIAMO ERRORE GENERICO (Passiamo user.uid)
      await DatabaseHelper.instance.insertMessage(
        "CLAIM: $text\n\n$err",
        false,
        user.uid,
        isFake: null,
      );
      HapticFeedback.vibrate();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSmartScan() async {
    final ImagePicker picker = ImagePicker();
    // 1. Scatta la foto con la fotocamera
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);

    if (photo != null) {
      if (!mounted) return; // Controllo di sicurezza

      // 2. Naviga verso la pagina SmartScanPage e ATTENDI il risultato
      // Il risultato sarà la stringa di testo che l'utente ha selezionato
      final String? selectedText = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SmartScanPage(imageFile: File(photo.path)),
        ),
      );

      // 3. Se è tornato del testo, inseriscilo nel campo di input
      if (selectedText != null && selectedText.isNotEmpty) {
        setState(() {
          // Sostituisce il testo attuale.
          // Se preferisci aggiungerlo in coda, usa: _textController.text += " $selectedText";
          _textController.text = selectedText;
        });
      }
    }
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App Bar Trasparente
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: true, // Teniamo l'energia al centro

        leadingWidth: 100,

        // 1. LOGO A SINISTRA (Automatico)
        // Usiamo il file che hai sicuramente (app_icon.png o quello trasparente)
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Image.asset(
            'assets/images/icon-horizontal2.png',
            fit: BoxFit.contain,
          ),
        ),

        // 2. ENERGIA AL CENTRO (Con protezione Overflow)
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: EnergyWidget(
            energyLevel: _energy,
            onTap: () async {
              await EnergyService.instance.debugRefill();
              _loadEnergy();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("🔋 Cheat Mode: Ricarica!"),
                  duration: Duration(milliseconds: 500),
                ),
              );
            },
          ),
        ),

        // 3. AZIONI A DESTRA
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.textGrey),
            tooltip: "Cancella tutto",
            onPressed: () async {
              final user = AuthService.instance.currentUser;
              if (user != null) {
                // ... Dialog e Logica Cancellazione ...
                bool confirm =
                    await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: const Text(
                          "Cancellare tutto?",
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const Text(
                          "Eliminare la cronologia?",
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text("No"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text("Sì"),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (confirm) {
                  await DatabaseHelper.instance.clearAll(user.uid);
                  setState(() {
                    _records.clear();
                  });
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textGrey),
            onPressed: () async {
              setState(() {
                _records.clear();
              });
              await AuthService.instance.signOut();
            },
          ),
        ],
      ),

      body: Stack(
        children: [
          // 1. IL FEED (Contenuto)
          Padding(
            padding: const EdgeInsets.only(bottom: 100),
            child: _records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.query_stats,
                          size: 60,
                          color: Colors.grey[900],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Nessuna analisi recente",
                          style: TextStyle(color: Colors.grey[800]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    itemCount: _records.length,

                    // --- CERCA QUESTA PARTE NEL TUO ListView.builder ---
                    itemBuilder: (context, index) {
                      final rec = _records[index];
                      if (rec.status == "USER_INPUT")
                        return const SizedBox.shrink();

                      return Dismissible(
                        // 1. CHIAVE SICURA:
                        // Se l'ID è null (es. elemento in caricamento), usiamo una chiave univoca casuale
                        // per evitare conflitti. Se c'è l'ID, usiamo quello.
                        key: rec.id != null
                            ? Key(rec.id.toString())
                            : UniqueKey(),

                        direction: DismissDirection.startToEnd,

                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.fakeRed.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),

                        onDismissed: (direction) {
                          // A. SALVIAMO L'ID PRIMA DI RIMUOVERE L'OGGETTO
                          final idToDelete = rec.id;

                          // B. RIMUOVIAMO DALLA UI (SINCRONO E IMMEDIATO)
                          // Usiamo .remove(rec) invece di .removeAt(index) per sicurezza assoluta
                          setState(() {
                            _records.remove(rec);
                          });

                          // C. RIMUOVIAMO DAL DB (IN BACKGROUND)
                          // Non usiamo 'await' qui per non bloccare l'animazione di chiusura
                          if (idToDelete != null) {
                            DatabaseHelper.instance.deleteMessage(idToDelete);
                          }

                          // D. FEEDBACK
                          HapticFeedback.mediumImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text("Analisi eliminata"),
                              duration: const Duration(seconds: 1),
                              backgroundColor: AppTheme.surface,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },

                        child: AnalysisCard(
                          record: rec,
                          onTap: () => _showDetail(rec),
                          // CALLBACK RETRY
                          onRetry: (textToRetry) {
                            // 1. Cancelliamo il messaggio di errore vecchio
                            if (rec.id != null)
                              DatabaseHelper.instance.deleteMessage(rec.id!);
                            setState(() => _records.remove(rec));

                            // 2. Rilanciamo l'analisi come se fosse nuova
                            _textController.text =
                                textToRetry; // (Opzionale, rimette il testo nella bar)
                            _handleSubmitted(textToRetry);
                          },
                        ),
                      );
                    },
                  ),
          ),

          // 2. INPUT BAR (Glassmorphism)
          // La nascondiamo visivamente o la lasciamo sotto?
          // Meglio lasciarla sotto e sfocare tutto.
          Align(
            alignment: Alignment.bottomCenter,
            child: GlassInputBar(
              controller: _textController,
              isListening: _isListening,
              isLoading:
                  _isLoading, // Nota: Passiamo isLoading, ma l'animazione interna alla barra la rimuoviamo dopo
              onSubmitted: _handleSubmitted,
              onMicTap: _listen,
              onScanTap: _handleSmartScan,
            ),
          ),

          // 3. --- NUOVO: OVERLAY DI CARICAMENTO ---
          if (_isLoading)
            Positioned.fill(
              // Occupa tutto lo schermo
              child: Stack(
                children: [
                  // A. SFOCATURA (Blur)
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: 0.3,
                      ), // Leggero velo scuro
                    ),
                  ),
                  // B. ANIMAZIONE GEOMETRICA CENTRALE
                  const Center(child: GeometricLoader()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDetail(AnalysisRecord record) {
    // Navigazione fluida verso la pagina di dettaglio
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            AnalysisDetailPage(record: record, onSpeak: _speak),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Effetto Fade + Slide leggero dal basso
          const begin = Offset(0.0, 0.1);
          const end = Offset.zero;
          const curve = Curves.easeOutExpo;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          var fadeAnimation = animation.drive(Tween(begin: 0.0, end: 1.0));

          return FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
      ),
    );
  }
}

// --- NUOVI WIDGET DI DESIGN ---
class AnalysisCard extends StatelessWidget {
  final AnalysisRecord record;
  final VoidCallback onTap;
  final Function(String)? onRetry;

  const AnalysisCard({
    super.key,
    required this.record,
    required this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    // Logica Colori
    switch (record.status) {
      case "PROCESSING":
        color = AppTheme.accentPurple;
        icon = Icons.hourglass_top;
        label = "ANALISI IN CORSO";
        break;
      case "IGNORE":
        color = AppTheme.textGrey;
        icon = Icons.block;
        label = "FILTRATO";
        break;
      case "CLAIM":
        if (record.isFake == true) {
          color = AppTheme.fakeRed;
          icon = Icons.warning_amber_rounded;
          label = "POTENZIALMENTE FALSO";
        } else if (record.isFake == false) {
          color = AppTheme.realGreen;
          icon = Icons.verified_outlined;
          label = "VERIFICATO";
        } else {
          color = Colors.amber;
          icon = Icons.help_outline;
          label = "INCONCLUDENTE";
        }
        break;
      case "ERROR":
      default:
        color = AppTheme.fakeRed;
        icon = Icons.error_outline;
        label = "ERRORE";
        break;
    }

    // Logica Testo Pulito
    String displayText = record.text;
    if (displayText.contains("CLAIM: ")) {
      displayText = displayText.split("\n")[0].replaceAll("CLAIM: ", "").trim();
    } else if (displayText.contains("\n")) {
      var lines = displayText.split("\n");
      for (var line in lines) {
        if (line.isNotEmpty &&
            !line.startsWith("http") &&
            !line.contains("FONTI CITATE") &&
            !line.contains("RAG Cloud")) {
          displayText = line;
          break;
        }
      }
    }

    // --- ECCO IL RETURN COMPLETO ---
    return GestureDetector(
      onTap: onTap,
      child: Container(
        //margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Banda Colorata Laterale
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Etichetta a Sinistra, Orario o Retry a Destra
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Etichetta (Icona + Testo)
                          Row(
                            children: [
                              Icon(icon, size: 14, color: color),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),

                          // --- LOGICA RETRY vs ORARIO ---
                          if (record.status == "ERROR" && onRetry != null)
                            InkWell(
                              onTap: () {
                                // Puliamo il testo prima di riprovare
                                String textToRetry = record.text;
                                if (textToRetry.contains("CLAIM:")) {
                                  textToRetry = textToRetry
                                      .split("\n")[0]
                                      .replaceAll("CLAIM:", "")
                                      .trim();
                                }
                                onRetry!(textToRetry);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.refresh,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      "RIPROVA",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            // Se non è errore, mostra l'orario
                            Text(
                              DateFormat('HH:mm').format(record.timestamp),
                              style: const TextStyle(
                                color: AppTheme.textGrey,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Testo del Claim
                      Text(
                        displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isListening;
  final bool
  isLoading; // Lo usiamo solo per bloccare i click, non per mostrare la rotellina
  final Function(String) onSubmitted;
  final VoidCallback onMicTap;
  final VoidCallback onScanTap;

  const GlassInputBar({
    super.key,
    required this.controller,
    required this.isListening,
    required this.isLoading,
    required this.onSubmitted,
    required this.onMicTap,
    required this.onScanTap,
  });

  @override
  Widget build(BuildContext context) {
    bool showSend = controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.7),
              border: Border.all(
                color: isListening
                    ? AppTheme.fakeRed.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                // 1. TASTO FOTOCAMERA
                Opacity(
                  opacity: (isListening || isLoading)
                      ? 0.3
                      : 1.0, // Diventa opaco se sta caricando
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      // Icona "Scanner" invece della vecchia camera
                      icon: const Icon(Icons.document_scanner_outlined),

                      color: AppTheme.accentPurple,

                      splashRadius: 20,
                      tooltip: "Smart Scan (Seleziona testo)",

                      // Se l'app è libera, chiama la tua nuova funzione _handleSmartScan
                      onPressed: (isListening || isLoading) ? null : onScanTap,
                    ),
                  ),
                ),

                // 2. CAMPO DI TESTO
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled:
                        !isListening &&
                        !isLoading, // Blocca scrittura se carica
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: AppTheme.accentPurple,
                    decoration: InputDecoration(
                      hintText: isListening
                          ? "Ti ascolto..."
                          : "Analizza un claim...",
                      hintStyle: TextStyle(
                        color: isListening ? AppTheme.fakeRed : Colors.grey,
                        fontWeight: isListening
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (text) {
                      if (!isLoading) onSubmitted(text);
                    },
                  ),
                ),

                // 3. TASTO AZIONE (NIENTE PIÙ ROTELLINA QUI!)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isListening
                      ? Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: PulsingMicButton(onTap: onMicTap),
                        )
                      : Container(
                          key: ValueKey(showSend ? 'send' : 'mic'),
                          margin: const EdgeInsets.only(left: 4),
                          child: IconButton(
                            icon: Icon(
                              showSend ? Icons.arrow_upward : Icons.mic_none,
                              size: 24,
                            ),
                            // Se showSend è true -> Viola. Altrimenti -> Grigio.
                            color: showSend
                                ? AppTheme.accentPurple
                                : Colors.grey,
                            splashRadius: 24,
                            onPressed: () {
                              if (isLoading) return;

                              if (showSend) {
                                onSubmitted(controller.text);
                              } else {
                                onMicTap();
                              }
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnalysisDetailSheet extends StatelessWidget {
  final AnalysisRecord record;
  final Function(String) onSpeak;

  const AnalysisDetailSheet({
    super.key,
    required this.record,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DETTAGLIO ANALISI",
                style: TextStyle(
                  color: AppTheme.accentPurple,
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => onSpeak(record.text),
                icon: const Icon(Icons.volume_up, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            // Scrollable se il testo è lungo
            child: SingleChildScrollView(
              child: Text(
                record.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PulsingMicButton extends StatefulWidget {
  final VoidCallback onTap;

  const PulsingMicButton({super.key, required this.onTap});

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(); // Loop infinito

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(
      begin: 0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Cerchio che si espande (Onda)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppTheme.fakeRed, // Rosso Neon
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          // Bottone Centrale Fisso
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppTheme.fakeRed,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.fakeRed,
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.stop, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class AnalysisDetailPage extends StatelessWidget {
  final AnalysisRecord record;

  final Function(String) onSpeak;

  const AnalysisDetailPage({
    super.key,
    required this.record,
    required this.onSpeak,
  });

  // --- FUNZIONE 1: Estrae SOLO il testo che l'utente ha scritto ---
  String _getCleanClaim(String fullText) {
    // 1. Se abbiamo il nuovo formato con "CLAIM:"
    if (fullText.contains("CLAIM:")) {
      // Prende la prima riga e rimuove l'etichetta
      return fullText.split("\n")[0].replaceAll("CLAIM:", "").trim();
    }

    // 2. Fallback per vecchi messaggi o formati strani:
    // Rimuove tutto ciò che viene dopo le parole chiave tecniche
    if (fullText.contains("✅ FILTRO")) {
      return fullText.split("✅ FILTRO")[0].trim();
    }
    if (fullText.contains("⛔ FILTRO")) {
      return fullText.split("⛔ FILTRO")[0].trim();
    }
    if (fullText.contains("☁️ RAG")) {
      return fullText.split("☁️ RAG")[0].trim();
    }

    return fullText; // Se non trova nulla, restituisce tutto
  }

  // --- FUNZIONE 2: Estrae SOLO la spiegazione e le fonti ---
  String _getCleanReport(String fullText) {
    if (fullText.contains("☁️ RAG Cloud:")) {
      return fullText.split("☁️ RAG Cloud:").last.trim();
    } else if (fullText.contains("Il testo non sembra")) {
      return "Il filtro locale ha determinato che questo testo non richiede verifica fattuale.";
    }
    return "Nessun dettaglio aggiuntivo disponibile dal server.";
  }

  @override
  Widget build(BuildContext context) {
    // Determiniamo i colori e le icone in base allo stato
    // Inizializziamo con valori di default (ERROR) per evitare l'errore "must be assigned"
    Color themeColor = AppTheme.fakeRed;
    String verdictText = "ERRORE";
    IconData icon = Icons.error_outline;

    if (record.status == "CLAIM") {
      if (record.isFake == true) {
        // CASO FALSO
        themeColor = AppTheme.fakeRed;
        verdictText = "FAKE NEWS";
        icon = Icons.warning_amber_rounded;
      } else if (record.isFake == false) {
        // CASO VERO (Solo se è esplicitamente false)
        themeColor = AppTheme.realGreen;
        verdictText = "VERIFICATO";
        icon = Icons.verified_outlined;
      } else {
        // CASO NULL (Inconcludente / Errore API / Unverifiable)
        themeColor = Colors.amber; // Giallo Attenzione
        verdictText = "NON VERIFICABILE";
        icon = Icons.help_outline;
      }
    } else if (record.status == "IGNORE") {
      themeColor = AppTheme.textGrey;
      verdictText = "FILTRATO";
      icon = Icons.block;
    } else if (record.status == "PROCESSING") {
      themeColor = AppTheme.accentPurple;
      verdictText = "IN ANALISI";
      icon = Icons.hourglass_top;
    }
    // Se è "ERROR" o altro, rimangono i valori di default definiti sopra.

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // 1. BACKGROUND GLOW
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    themeColor.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                  radius: 0.6,
                ),
              ),
            ),
          ),

          // 2. CONTENUTO
          SafeArea(
            child: Column(
              children: [
                // NAVBAR
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      // Tasto TTS
                      IconButton(
                        onPressed: () {
                          String textToRead =
                              "$verdictText. ${_getCleanReport(record.text)}";
                          onSpeak(textToRead);
                          // Qui leggiamo solo la spiegazione pulita, non tutto il blob
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("🔊 Lettura in corso..."),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.volume_up, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),

                        // ICONA GIGANTE E VERDETTO
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: themeColor.withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: themeColor.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.2),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Icon(icon, size: 50, color: themeColor),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                verdictText,
                                style: TextStyle(
                                  fontFamily: 'RobotoMono',
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: themeColor,
                                  letterSpacing: 3.0,
                                  shadows: [
                                    Shadow(
                                      color: themeColor.withValues(alpha: 0.5),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // INDICATORI HUD
                        Row(
                          children: [
                            // 1. RUST TIME (Edge)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFE57373,
                                ).withValues(alpha: 0.2), // Rosso ruggine
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(
                                    0xFFE57373,
                                  ).withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.flash_on,
                                    size: 14,
                                    color: Color(0xFFE57373),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "EDGE: ${record.localTimeMs}ms",
                                    style: const TextStyle(
                                      color: Color(0xFFE57373),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),

                            // 2. CLOUD TIME (Server)
                            // Lo mostriamo solo se il server è stato chiamato (>0)
                            if (record.cloudTimeMs > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF64B5F6,
                                  ).withValues(alpha: 0.2), // Azzurro Cloud
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF64B5F6,
                                    ).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_queue,
                                      size: 14,
                                      color: Color(0xFF64B5F6),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "CLOUD: ${record.cloudTimeMs}ms",
                                      style: const TextStyle(
                                        color: Color(0xFF64B5F6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 40),

                        // IL CLAIM PULITO (Titolo Utente)
                        Text(
                          "CLAIM ANALIZZATO",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "\"${_getCleanClaim(record.text)}\"",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.4,
                            fontWeight: FontWeight.w300,
                            fontStyle: FontStyle.italic,
                          ),
                        ),

                        const SizedBox(height: 40),

                        // REPORT AI (Dossier)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151515),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                    color: AppTheme.accentPurple,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "REPORT INTELLIGENZA ARTIFICIALE",
                                    style: TextStyle(
                                      color: AppTheme.accentPurple,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Linkify(
                                onOpen: (link) async {
                                  // Questa logica apre il link nel browser esterno (Chrome/Safari)
                                  if (!await launchUrl(
                                    Uri.parse(link.url),
                                    mode: LaunchMode
                                        .externalApplication, // Importante per aprire fuori dall'app
                                  )) {
                                    throw Exception(
                                      'Impossibile aprire ${link.url}',
                                    );
                                  }
                                },
                                text: _getCleanReport(record.text),

                                // Stile del testo normale
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 15,
                                  height: 1.6,
                                ),

                                // Stile dei LINK (Li facciamo del colore Accent Purple per risaltare)
                                linkStyle: const TextStyle(
                                  color: AppTheme.accentPurple,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration
                                      .underline, // Sottolineati come veri link
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontFamily: 'RobotoMono',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class GeometricLoader extends StatefulWidget {
  const GeometricLoader({super.key});

  @override
  State<GeometricLoader> createState() => _GeometricLoaderState();
}

class _GeometricLoaderState extends State<GeometricLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // Loop infinito
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. ANELLO ESTERNO (Ciano - Ruota orario)
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.realGreen.withValues(alpha: 0.5),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.all(4.0),
                  child: CircleAvatar(
                    radius: 3,
                    backgroundColor: AppTheme.realGreen,
                  ),
                ),
              ),
            ),
          ),

          // 2. QUADRATO ROTANTE (Viola - Ruota veloce)
          RotationTransition(
            turns: Tween(
              begin: 0.0,
              end: -1.0,
            ).animate(_controller), // Ruota al contrario
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.accentPurple, width: 2),
              ),
            ),
          ),

          // 3. NUCLEO PULSANTE (Bianco)
          FadeTransition(
            opacity: Tween(begin: 0.5, end: 1.0).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple,
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
          ),

          // TESTO SOTTOSTANTE
          Positioned(
            top: 100,
            child: Text(
              "ELABORAZIONE DATI...",
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 12,
                color: AppTheme.accentPurple.withValues(alpha: 0.8),
                letterSpacing: 2.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

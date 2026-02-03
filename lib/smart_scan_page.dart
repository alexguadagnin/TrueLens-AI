import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class SmartScanPage extends StatefulWidget {
  final File imageFile;

  const SmartScanPage({super.key, required this.imageFile});

  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage> {
  RecognizedText? _recognizedText;
  ui.Image? _visualImage;

  // USIAMO UN SET PER LA MULTI-SELEZIONE
  // Il Set impedisce i duplicati (non puoi selezionare due volte lo stesso blocco)
  final Set<TextBlock> _selectedBlocks = {};

  bool _isAnalyzing = true;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    try {
      final data = await widget.imageFile.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(data, completer.complete);
      final visualImage = await completer.future;

      final inputImage = InputImage.fromFile(widget.imageFile);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final recognizedText = await textRecognizer.processImage(inputImage);

      if (mounted) {
        setState(() {
          _visualImage = visualImage;
          _recognizedText = recognizedText;
          _isAnalyzing = false;
        });
      }
      textRecognizer.close();
    } catch (e) {
      debugPrint("Errore analisi: $e");
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // Funzione che mette insieme tutto il testo selezionato
  // e lo ordina dall'alto verso il basso (per avere frasi di senso compiuto)
  String _getCombinedText() {
    if (_selectedBlocks.isEmpty) return "";

    // Convertiamo il Set in Lista per poterla ordinare
    List<TextBlock> sortedBlocks = _selectedBlocks.toList();

    // Ordiniamo in base alla posizione verticale (Y) e poi orizzontale (X)
    sortedBlocks.sort((a, b) {
      int verticalDiff = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (verticalDiff != 0) return verticalDiff;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    // Uniamo i testi con uno spazio
    return sortedBlocks
        .map((block) => block.text.replaceAll('\n', ' '))
        .join(" ");
  }

  void _toggleBlock(TextBlock block) {
    setState(() {
      if (_selectedBlocks.contains(block)) {
        _selectedBlocks.remove(block);
      } else {
        _selectedBlocks.add(block);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Definizione colori al volo
    const Color accentColor = Color(0xFF6200EA);
    const Color overlayColor = Colors.black54;

    return Scaffold(
      backgroundColor: Colors.black,
      // Stack permette di sovrapporre l'interfaccia SOPRA la foto
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. LIVELLO BASE: L'IMMAGINE E I RETTANGOLI
          if (_visualImage != null && _recognizedText != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final double scaleX =
                    constraints.maxWidth / _visualImage!.width;
                final double scaleY =
                    constraints.maxHeight / _visualImage!.height;
                final double scale = scaleX < scaleY ? scaleX : scaleY;

                final double offsetX =
                    (constraints.maxWidth - (_visualImage!.width * scale)) / 2;
                final double offsetY =
                    (constraints.maxHeight - (_visualImage!.height * scale)) /
                    2;

                return InteractiveViewer(
                  // Permette di zoomare la foto!
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Stack(
                    children: [
                      // FOTO CENTRATA
                      Center(
                        child: Image.file(
                          widget.imageFile,
                          fit: BoxFit.contain,
                        ),
                      ),

                      // RETTANGOLI INTERATTIVI
                      ..._recognizedText!.blocks.map((block) {
                        final rect = block.boundingBox;
                        final double left = (rect.left * scale) + offsetX;
                        final double top = (rect.top * scale) + offsetY;
                        final double width = rect.width * scale;
                        final double height = rect.height * scale;

                        final bool isSelected = _selectedBlocks.contains(block);

                        return Positioned(
                          left: left,
                          top: top,
                          width: width,
                          height: height,
                          child: GestureDetector(
                            onTap: () => _toggleBlock(block),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentColor.withOpacity(
                                        0.5,
                                      ) // Evidenziato forte
                                    : Colors.white.withOpacity(
                                        0.1,
                                      ), // Appena visibile se non selezionato
                                border: Border.all(
                                  color: isSelected
                                      ? accentColor
                                      : Colors.white54,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              },
            ),

          // 2. LIVELLO CARICAMENTO
          if (_isAnalyzing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: accentColor),
                    SizedBox(height: 16),
                    Text(
                      "Cerco il testo...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // 3. LIVELLO APPBAR (In alto, trasparente)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              backgroundColor:
                  Colors.transparent, // Trasparente per vedere la foto sotto
              elevation: 0,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: overlayColor, // Sfondo scuro per il tasto indietro
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // 4. LIVELLO BOTTOM BAR (In basso, mostra il testo e la conferma)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E), // Sfondo scuro elegante
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black54)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Testo Anteprima
                  Text(
                    _selectedBlocks.isEmpty
                        ? "Tocca le parole evidenziate per selezionarle"
                        : _getCombinedText(),
                    style: TextStyle(
                      color: _selectedBlocks.isEmpty
                          ? Colors.grey
                          : Colors.white,
                      fontSize: 16,
                      fontStyle: _selectedBlocks.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // Bottone Conferma
                  ElevatedButton.icon(
                    onPressed: _selectedBlocks.isEmpty
                        ? null
                        : () {
                            Navigator.pop(context, _getCombinedText());
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check),
                    label: Text("IMPORTA (${_selectedBlocks.length})"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

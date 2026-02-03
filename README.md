# 🕵️ TrueLens AI - Fact Checking in Tempo Reale

Un'applicazione mobile ibrida (Flutter + Rust + Python) che utilizza l'Intelligenza Artificiale per verificare la veridicità delle affermazioni politiche in tempo reale.

## 🚀 Funzionalità Principali
- **Analisi Ibrida:** Un motore neurale locale (Rust + ONNX) filtra i claim irrilevanti offline per risparmiare energia e costi.
- **RAG Cloud (Python):** I claim validi vengono analizzati da un server Python (Dockerizzato su DigitalOcean) che incrocia i dati con Tavily (Web Search) e OpenAI.
- **Smart Scan:** OCR integrato per analizzare testi da foto e manifesti.
- **Design:** Interfaccia moderna "Glassmorphism" con indicatori di consumo energetico simulato.

## 🛠️ Tecnologie Utilizzate
- **Frontend:** Flutter (Dart)
- **Edge AI:** Rust (tramite Flutter Rust Bridge), Tokenizers HuggingFace.
- **Backend:** Python (FastAPI), LangChain, Docker.
- **Database:** SQLite (Locale), Firebase Auth (Login).

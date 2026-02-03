use flutter_rust_bridge::frb;
// Importiamo SessionInputValue e Cow esplicitamente come richiesto
use ort::session::{Session, builder::GraphOptimizationLevel, SessionInputValue};
use ort::value::Value;
use std::sync::Mutex;
use tokenizers::Tokenizer;
use ndarray::Array2;
use std::borrow::Cow; 

pub struct AiModel {
    pub(crate) session: Mutex<Option<Session>>,
    pub(crate) tokenizer: Mutex<Option<Tokenizer>>,
}

impl AiModel {
    #[frb(sync)]
    pub fn new(model_path: String, tokenizer_path: String) -> AiModel {
        println!("RUST LOG: Tentativo caricamento modello da: {}", model_path);

        let builder = Session::builder().unwrap();
        let session_result = builder
            .with_optimization_level(GraphOptimizationLevel::Level1)
            .unwrap()
            .commit_from_file(model_path);

        let session = match session_result {
            Ok(s) => Some(s),
            Err(e) => {
                println!("RUST LOG: ERRORE Modello: {:?}", e);
                None
            }
        };

        let tokenizer = match Tokenizer::from_file(tokenizer_path) {
            Ok(t) => Some(t),
            Err(e) => {
                println!("RUST LOG: ERRORE Tokenizer: {:?}", e);
                None
            }
        };

        AiModel {
            session: Mutex::new(session),
            tokenizer: Mutex::new(tokenizer),
        }
    }

    #[frb(sync)]
    pub fn check_sentence(&self, text: String) -> String {
        // 1. FILTRO LUNGHEZZA (Risolve il problema "Ciao")
        if text.len() < 10 || text.split_whitespace().count() < 3 {
            println!("RUST LOG: Frase troppo breve, ignorata.");
            return "IGNORE|0.0".to_string();
        }

        let mut session_guard = self.session.lock().unwrap();
        let tokenizer_guard = self.tokenizer.lock().unwrap();

        if session_guard.is_none() || tokenizer_guard.is_none() {
            return "ERROR_NOT_INIT".to_string();
        }

        let session = session_guard.as_mut().unwrap();
        let tokenizer = tokenizer_guard.as_ref().unwrap();

        // 2. Tokenizzazione
        let encoding = match tokenizer.encode(text.clone(), true) {
            Ok(e) => e,
            Err(_) => return "ERROR_TOKENIZER".to_string(),
        };

        let input_ids: Vec<i64> = encoding.get_ids().iter().map(|&x| x as i64).collect();
        let attention_mask: Vec<i64> = encoding.get_attention_mask().iter().map(|&x| x as i64).collect();
        let seq_len = input_ids.len();

        let input_array = Array2::from_shape_vec((1, seq_len), input_ids).unwrap();
        let mask_array = Array2::from_shape_vec((1, seq_len), attention_mask).unwrap();

        let input_tensor = Value::from_array(input_array).unwrap();
        let mask_tensor = Value::from_array(mask_array).unwrap();

        // 3. Creazione Input Manuale CON TIPI ESPLICITI (Fix Errore Compilazione)
        // Diciamo a Rust: "Questo è un vettore di coppie (Stringa, Valore ONNX)"
        let inputs: Vec<(Cow<str>, SessionInputValue)> = vec![
            ("input_ids".into(), input_tensor.into()),
            ("attention_mask".into(), mask_tensor.into())
        ];

        // 4. Inferenza
        let outputs = match session.run(inputs) {
            Ok(o) => o,
            Err(e) => {
                println!("RUST LOG: Errore inferenza: {:?}", e);
                return "ERROR_INFERENCE".to_string();
            } 
        };

        let (_, output_data) = outputs[0].try_extract_tensor::<f32>().unwrap();
        let logits: Vec<f32> = output_data.to_vec();

        // LOGGING FONDAMENTALE PER IL DEBUG
        // Guarda il terminale quando invii un messaggio!
        println!("RUST LOG: Raw Logits -> [0]: {:.4}, [1]: {:.4}", logits[0], logits[1]);

        // CALCOLO PROBABILITÀ
        // Assunzione Attuale: [0] = Irrilevante, [1] = Claim Politico
        // Se vedendo i log noti che per i claim sale lo [0], dovremo invertire queste due righe.
        let score_irrelevant = logits[0];
        let score_claim = logits[1];

        // Softmax
        let max_val = if score_irrelevant > score_claim { score_irrelevant } else { score_claim };
        let exp_irr = (score_irrelevant - max_val).exp();
        let exp_claim = (score_claim - max_val).exp();
        let prob_claim = exp_claim / (exp_irr + exp_claim);
        let percentage = prob_claim * 100.0;

        println!("RUST LOG: Probabilità calcolata: {:.2}%", percentage);

        // FORMATO RISPOSTA: "DECISIONE|PERCENTUALE"
        // Abbassiamo la soglia a 0.50 per vedere se passa qualcosa
        if prob_claim > 0.50 {
            format!("CLAIM|{:.1}", percentage)
        } else {
            format!("IGNORE|{:.1}", percentage)
        }
    }
}
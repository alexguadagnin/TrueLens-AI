use flutter_rust_bridge::frb;
use ort::session::Session; // Importiamo per verificare il link

#[frb(sync)] 
pub fn greet(name: String) -> String {
    format!("Hello {}, Rust is connected!", name)
}

#[frb(sync)]
pub fn check_ai() -> String {
    // Questo codice non fa nulla di utile ma costringe il compilatore
    // a verificare se libonnxruntime.so è linkato correttamente.
    // Se l'app non crasha chiamando questa funzione, ABBIAMO VINTO.
    let _builder = Session::builder(); 
    "Motore AI (ONNX) rilevato e funzionante!".to_string()
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
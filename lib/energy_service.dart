import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class EnergyService {
  // Singleton
  static final EnergyService instance = EnergyService._init();
  EnergyService._init();

  static const int MAX_ENERGY = 3;
  static const String KEY_ENERGY = 'user_energy';
  static const String KEY_DATE = 'last_reset_date';

  // Carica l'energia attuale
  Future<int> getEnergy() async {
    final prefs = await SharedPreferences.getInstance();

    // Controlliamo se è un nuovo giorno
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String? lastDate = prefs.getString(KEY_DATE);

    if (lastDate != today) {
      // È un nuovo giorno! RICARICA TOTALE
      await _resetEnergy(prefs, today);
      return MAX_ENERGY;
    }

    // Se è lo stesso giorno, restituisci quella salvata (o 5 se non esiste)
    return prefs.getInt(KEY_ENERGY) ?? MAX_ENERGY;
  }

  // Consuma 1 unità di energia
  Future<bool> consumeEnergy() async {
    final prefs = await SharedPreferences.getInstance();
    int current = await getEnergy(); // Questo controlla anche la data

    if (current > 0) {
      await prefs.setInt(KEY_ENERGY, current - 1);
      return true; // Consumo riuscito
    } else {
      return false; // Energia esaurita!
    }
  }

  // Funzione di debug per ricaricare (utile per la demo!)
  Future<void> debugRefill() async {
    final prefs = await SharedPreferences.getInstance();
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _resetEnergy(prefs, today);
  }

  // Helper privato per resettare
  Future<void> _resetEnergy(SharedPreferences prefs, String date) async {
    await prefs.setString(KEY_DATE, date);
    await prefs.setInt(KEY_ENERGY, MAX_ENERGY);
  }
}

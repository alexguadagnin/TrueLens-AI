import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('history_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'INTEGER NOT NULL';
    const nullableBoolType = 'INTEGER';
    const intNullable = 'INTEGER';

    await db.execute('''
CREATE TABLE messages ( 
  id $idType, 
  userId $textType,  
  text $textType,
  isUser $boolType,
  isFake $nullableBoolType,
  time $textType,
  localTime $intNullable,
  cloudTime $intNullable
  )
''');
  }

  // Inserimento (Richiede userId)
  Future<void> insertMessage(
    String text,
    bool isUser,
    String userId, {
    bool? isFake,
    int? localTime,
    int? cloudTime,
  }) async {
    final db = await instance.database;

    await db.insert('messages', {
      'userId': userId,
      'text': text,
      'isUser': isUser ? 1 : 0,
      'isFake': isFake == null ? null : (isFake ? 1 : 0),
      'time': DateTime.now().toIso8601String(),
      'localTime': localTime,
      'cloudTime': cloudTime,
    });
  }

  // Lettura (Richiede userId per filtrare)
  Future<List<Map<String, dynamic>>> getMessages(String userId) async {
    final db = await instance.database;
    // FILTRO MAGICO: WHERE userId = ?
    return await db.query(
      'messages',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'time DESC',
    );
  }

  // Cancellazione (Solo i messaggi dell'utente corrente)
  Future<void> deleteMessage(int id) async {
    final db = await instance.database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  // Cancellazione Totale (Solo per l'utente corrente)
  Future<void> clearAll(String userId) async {
    final db = await instance.database;
    await db.delete('messages', where: 'userId = ?', whereArgs: [userId]);
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ----------------------------------------------------------------------
// CONFIGURATION & COULEURS
// ----------------------------------------------------------------------
const List<String> ORDRE_INSTALLATION = ["4", "3", "2", "1"];

const String MDP_PARAM_SIEGES = "123456";
const String MDP_CORRECTION_CHARIOT = "";

const Color NAVY = Color(0xFF0F2159);
const Color BLEU_LABEL = Color(0xFF0D3380);
const Color GRIS_CLAIR = Color(0xFFD9D9D9);
const Color VERT_OK = Color(0xFF269926);
const Color ROUGE_ERR = Color(0xFFBF2626);
const Color BG_OK = Color(0xFFD9F7D9);
const Color BG_ERREUR = Color(0xFFFFD9D9);
const Color BG_ENCOURS = Color(0xFFFFF0BF);
const Color BORDER_ENCOURS = Color(0xFFD98C0D);

// ----------------------------------------------------------------------
// SERVICE BASE DE DONNÉES
// ----------------------------------------------------------------------
class DatabaseHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    String dbPath = await getDatabasesPath();
    String path = p.join(dbPath, 'conformite.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tables_ref (
            numero TEXT PRIMARY KEY
          )
        ''');
        await db.execute('''
          CREATE TABLE references_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_numero TEXT NOT NULL,
            code_siege TEXT NOT NULL,
            reference TEXT NOT NULL,
            UNIQUE(table_numero, code_siege)
          )
        ''');
        await db.execute('''
          CREATE TABLE etat_chariot (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            dernier_code_base INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE controles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_numero TEXT,
            chariot_type TEXT,
            chariot_label TEXT,
            code_base TEXT,
            position TEXT,
            reference_attendue TEXT,
            code_siege TEXT,
            reference_trouvee TEXT,
            conforme INTEGER,
            date_scan TEXT
          )
        ''');
      },
    );
  }

  // --- Tables ---
  static Future<void> ajouterTable(String numero) async {
    final db = await database;
    await db.insert(
      'tables_ref',
      {'numero': numero.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> supprimerTable(String numero) async {
    final db = await database;
    await db.delete('references_table', where: 'table_numero = ?', whereArgs: [numero]);
    await db.delete('tables_ref', where: 'numero = ?', whereArgs: [numero]);
  }

  static Future<List<String>> listerTables() async {
    final db = await database;
    final res = await db.query('tables_ref', orderBy: 'numero');
    return res.map((r) => r['numero'] as String).toList();
  }

  static Future<bool> tableExiste(String numero) async {
    final db = await database;
    final res = await db.query('tables_ref', where: 'numero = ?', whereArgs: [numero]);
    return res.isNotEmpty;
  }

  // --- Références ---
  static Future<void> ajouterReference(String tableNumero, String codeSiege, String reference) async {
    final db = await database;
    await db.insert(
      'references_table',
      {
        'table_numero': tableNumero,
        'code_siege': codeSiege.trim(),
        'reference': reference.trim()
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> supprimerReference(String tableNumero, String codeSiege) async {
    final db = await database;
    await db.delete(
      'references_table',
      where: 'table_numero = ? AND code_siege = ?',
      whereArgs: [tableNumero, codeSiege],
    );
  }

  static Future<List<Map<String, dynamic>>> listerReferences(String tableNumero) async {
    final db = await database;
    return await db.query(
      'references_table',
      where: 'table_numero = ?',
      whereArgs: [tableNumero],
      orderBy: 'code_siege',
    );
  }

  // RECHERCHE UNIFIÉE ET GLOBALE
  static Future<String?> lookupReference(String codeSiege, String? tableNumero) async {
    final db = await database;

    // 1. Recherche exacte sur la table sélectionnée si spécifiée
    if (tableNumero != null) {
      final res = await db.query(
        'references_table',
        columns: ['reference'],
        where: 'table_numero = ? AND code_siege = ?',
        whereArgs: [tableNumero, codeSiege],
      );
      if (res.isNotEmpty) return res.first['reference'] as String;
    }

    // 2. Recherche exacte sur TOUTES les tables (recherche globale)
    final resGlobal = await db.query(
      'references_table',
      columns: ['reference'],
      where: 'code_siege = ?',
      whereArgs: [codeSiege],
    );
    if (resGlobal.isNotEmpty) return resGlobal.first['reference'] as String;

    // 3. Fallback : Correspondance par préfixe globale
    final all = await db.query('references_table');
    return _matchPrefix(all, codeSiege);
  }

  static String? _matchPrefix(List<Map<String, dynamic>> rows, String codeSiege) {
    String? bestRef;
    int bestLen = 0;
    for (var r in rows) {
      String cs = r['code_siege'] as String;
      String ref = r['reference'] as String;
      if (codeSiege.startsWith(cs) && cs.length > bestLen) {
        bestRef = ref;
        bestLen = cs.length;
      }
    }
    return bestRef;
  }

  // --- Séquence Chariot ---
  static Future<int?> getDernierCodeBase() async {
    final db = await database;
    final res = await db.query('etat_chariot', where: 'id = 1');
    if (res.isNotEmpty) return res.first['dernier_code_base'] as int?;
    return null;
  }

  static Future<void> setDernierCodeBase(int codeBase) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO etat_chariot (id, dernier_code_base) VALUES (1, ?)
      ON CONFLICT(id) DO UPDATE SET dernier_code_base=excluded.dernier_code_base
    ''', [codeBase]);
  }

  // --- Contrôles ---
  static Future<void> enregistrerControle({
    String? tableNumero,
    required String chariotType,
    required String chariotLabel,
    required String codeBase,
    required String position,
    required String referenceAttendue,
    required String codeSiege,
    String? referenceTrouvee,
    required bool conforme,
  }) async {
    final db = await database;
    await db.insert('controles', {
      'table_numero': tableNumero,
      'chariot_type': chariotType,
      'chariot_label': chariotLabel,
      'code_base': codeBase,
      'position': position,
      'reference_attendue': referenceAttendue,
      'code_siege': codeSiege,
      'reference_trouvee': referenceTrouvee,
      'conforme': conforme ? 1 : 0,
      'date_scan': DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' '),
    });
  }

  static Future<List<Map<String, dynamic>>> listerControles({int limit = 200}) async {
    final db = await database;
    return await db.query('controles', orderBy: 'id DESC', limit: limit);
  }
}

// ----------------------------------------------------------------------
// MAIN APP
// ----------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConformiteApp());
}

class ConformiteApp extends StatelessWidget {
  const ConformiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conformité Sièges',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primaryColor: NAVY,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const ScanScreen(),
        '/historique': (context) => const HistoryScreen(),
        '/config_chariot': (context) => const ConfigChariotScreen(),
        '/config_sieges': (context) => const ConfigSiegesScreen(),
      },
    );
  }
}

// ----------------------------------------------------------------------
// ÉCRAN PRINCIPAL : SCAN
// ----------------------------------------------------------------------
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? _tableCourante;
  Map<String, dynamic>? _chariotActuel;
  List<String> _filePositions = [];
  String? _positionCourante;

  Map<String, String> _theoRef = {"1": "", "2": "", "3": "", "4": ""};
  Map<String, String> _reelRef = {"1": "", "2": "", "3": "", "4": ""};
  Map<String, Color> _bgStatus = {};
  Map<String, Color> _borderStatus = {};

  String _labelEtat = "• Flashez le QR de la table (facultatif)\n"
      "• Flashez le QR code Fakir\n"
      "• Flashez les sièges";

  @override
  void initState() {
    super.initState();
    _resetCases();
  }

  void _resetCases() {
    setState(() {
      _theoRef = {"1": "", "2": "", "3": "", "4": ""};
      _reelRef = {"1": "", "2": "", "3": "", "4": ""};
      _bgStatus = {};
      _borderStatus = {};
    });
  }

  void _focusInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Si la page principale n'est pas active, on ne capture pas le focus
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

      if (!_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  void _afficherErreur(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Attention"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _focusInput();
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  void _resetChariot() {
    setState(() {
      _chariotActuel = null;
      _filePositions = [];
      _positionCourante = null;
      _resetCases();
      _labelEtat = "Flashez le QR du chariot pour commencer.";
    });
    _focusInput();
  }

  // --- TRAITEMENT DU SCAN ---
  void _onScanValide(String raw) async {
    _controller.clear();
    _focusInput();
    raw = raw.trim();
    if (raw.isEmpty) return;

    if (raw.contains(';')) {
      await _traiterScanChariot(raw);
    } else if (RegExp(r'^\d+$').hasMatch(raw) && raw.length <= 6) {
      await _traiterScanTable(raw);
    } else {
      await _traiterScanSiege(raw);
    }
  }

  Future<void> _traiterScanTable(String raw) async {
    bool existe = await DatabaseHelper.tableExiste(raw);
    if (!existe) {
      _afficherErreur("Table inconnue : $raw\nCréez-la d'abord dans Code Siège (menu).");
      return;
    }
    setState(() {
      _tableCourante = raw;
      _labelEtat = "Table $raw sélectionnée.\nScannez le chariot pour commencer.";
    });
  }

  Future<void> _traiterScanChariot(String raw) async {
    if (_tableCourante == null) {
      _afficherErreur(
        "Rappel : aucune table de correspondance n'a été flashée.\n"
        "Les sièges seront vérifiés sur toutes les tables enregistrées.",
      );
    }

    // Parsing du chariot
    List<String> parts = raw.split(';').where((p) => p.isNotEmpty).toList();
    if (parts.length < 4) {
      _afficherErreur("QR chariot mal formé (structure inattendue).");
      return;
    }

    String type = parts[0];
    String label = parts[1];
    String codeBase = parts[2];

    if (int.tryParse(codeBase) == null) {
      _afficherErreur("Numéro de chariot invalide : '$codeBase'");
      return;
    }

    Map<String, String> positions = {};
    for (int i = 3; i < parts.length; i++) {
      List<String> segs = parts[i].split('!');
      if (segs.length == 3) {
        positions[segs[0]] = segs[2];
      }
    }

    if (positions.isEmpty) {
      _afficherErreur("Aucune position de siège trouvée dans le QR chariot.");
      return;
    }

    // Vérification de la séquence
    int nouveau = int.parse(codeBase);
    int? dernier = await DatabaseHelper.getDernierCodeBase();

    if (dernier != null && nouveau != dernier + 1) {
      _afficherErreur(
        "CHARIOT NON CONFORME A LA SEQUENCE\n"
        "Attendu : ${dernier + 1}\nScanné  : $nouveau",
      );
      setState(() {
        _chariotActuel = null;
        _filePositions = [];
        _positionCourante = null;
        _resetCases();
        _labelEtat = "Scan des sièges bloqué : le chariot ne suit pas la séquence.\nScannez le bon chariot.";
      });
      return;
    }

    Map<String, dynamic> chariot = {
      "type": type,
      "label": label,
      "code_base": codeBase,
      "positions": positions
    };

    setState(() {
      _chariotActuel = chariot;
      _filePositions = ORDRE_INSTALLATION.where((p) => positions.containsKey(p)).toList();
      _resetCases();

      positions.forEach((p, ref) {
        _theoRef[p] = ref;
      });
    });

    await DatabaseHelper.setDernierCodeBase(nouveau);
    _avancerPosition();
  }

  void _avancerPosition() {
    if (_filePositions.isEmpty) {
      String termine = _chariotActuel != null ? _chariotActuel!["code_base"] : "?";
      setState(() {
        _labelEtat = "Chariot $termine terminé et conforme.\nScannez le chariot suivant.";
        _chariotActuel = null;
        _positionCourante = null;
      });
      return;
    }

    setState(() {
      _positionCourante = _filePositions.removeAt(0);
      String refAttendue = _chariotActuel!["positions"][_positionCourante];
      _bgStatus[_positionCourante!] = BG_ENCOURS;
      _borderStatus[_positionCourante!] = BORDER_ENCOURS;
      _labelEtat = "Position $_positionCourante — Réf. attendue : $refAttendue\nScannez le siège.";
    });
  }

  Future<void> _traiterScanSiege(String codeSiege) async {
    if (_chariotActuel == null || _positionCourante == null) {
      _afficherErreur(
        "Scan de siège non autorisé.\n"
        "Aucun chariot valide en cours : scannez d'abord un chariot conforme.",
      );
      return;
    }

    String pos = _positionCourante!;
    String refAttendue = _chariotActuel!["positions"][pos];
    String? refTrouvee = await DatabaseHelper.lookupReference(codeSiege, _tableCourante);

    setState(() {
      _reelRef[pos] = codeSiege;
    });

    if (refTrouvee == null) {
      await DatabaseHelper.enregistrerControle(
        tableNumero: _tableCourante,
        chariotType: _chariotActuel!["type"],
        chariotLabel: _chariotActuel!["label"],
        codeBase: _chariotActuel!["code_base"],
        position: pos,
        referenceAttendue: refAttendue,
        codeSiege: codeSiege,
        referenceTrouvee: null,
        conforme: false,
      );

      setState(() {
        _bgStatus[pos] = BG_ERREUR;
        _borderStatus[pos] = ROUGE_ERR;
      });

      _afficherErreur(
        "Code siège inconnu : $codeSiege\n(absent de la table de correspondance)\n\n"
        "Position $pos reste à faire.",
      );
      return;
    }

    bool conforme = (refTrouvee == refAttendue);
    await DatabaseHelper.enregistrerControle(
      tableNumero: _tableCourante,
      chariotType: _chariotActuel!["type"],
      chariotLabel: _chariotActuel!["label"],
      codeBase: _chariotActuel!["code_base"],
      position: pos,
      referenceAttendue: refAttendue,
      codeSiege: codeSiege,
      referenceTrouvee: refTrouvee,
      conforme: conforme,
    );

    if (!conforme) {
      setState(() {
        _bgStatus[pos] = BG_ERREUR;
        _borderStatus[pos] = ROUGE_ERR;
      });

      _afficherErreur(
        "NON CONFORME — position $pos\n"
        "Attendu : $refAttendue\nScanné  : $refTrouvee\n\n"
        "Retirez ce siège et scannez le bon.",
      );
      return;
    }

    setState(() {
      _bgStatus[pos] = BG_OK;
      _borderStatus[pos] = VERT_OK;
    });

    _avancerPosition();
  }

  @override
  Widget build(BuildContext context) {
    _focusInput();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: NAVY,
        title: const Text("Siège Rang 3", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: Colors.white),
            onSelected: (val) {
              Navigator.pushNamed(context, val).then((_) => _focusInput());
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: '/historique', child: Text('Historique')),
              const PopupMenuItem(value: '/config_chariot', child: Text('Correction N° Chariot')),
              const PopupMenuItem(value: '/config_sieges', child: Text('Code Siège')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          // En-tête : Table n° / Chariot n°
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(child: _buildCaseBloc("Table n°", _tableCourante ?? "", color: _tableCourante != null ? BG_OK : GRIS_CLAIR)),
                const SizedBox(width: 10),
                Expanded(child: _buildCaseBloc("Chariot n°", _chariotActuel?["code_base"] ?? "", color: _chariotActuel != null ? BG_OK : GRIS_CLAIR)),
              ],
            ),
          ),

          // Lignes des positions (1, 2, 3, 4)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: ["1", "2", "3", "4"].map((p) => _buildLignePosition(p)).toList(),
            ),
          ),

          // État / Instruction
          Container(
            height: 90,
            alignment: Alignment.center,
            child: Text(
              _labelEtat,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),

          // Champ de scan + Réinitialiser
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    onSubmitted: _onScanValide,
                    decoration: const InputDecoration(
                      hintText: "Zone de Scan",
                      fillColor: GRIS_CLAIR,
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ROUGE_ERR,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _resetChariot,
                    child: const Text("Réinitialiser", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCaseBloc(String label, String text, {Color color = Colors.white}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontStyle: FontStyle.italic, color: BLEU_LABEL, fontSize: 12)),
        Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black38)),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildLignePosition(String pos) {
    Color bg = _bgStatus[pos] ?? Colors.white;
    Color border = _borderStatus[pos] ?? Colors.black38;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(pos, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
          ),
          Expanded(
            child: Column(
              children: [
                const Text("Théorique", style: TextStyle(fontSize: 11, color: BLEU_LABEL)),
                Container(
                  height: 38,
                  decoration: BoxDecoration(color: bg, border: Border.all(color: border)),
                  child: Row(
                    children: [
                      SizedBox(width: 30, child: Center(child: Text(_theoRef[pos]!.isNotEmpty ? pos : ""))),
                      const VerticalDivider(width: 1),
                      Expanded(child: Center(child: Text(_theoRef[pos]!))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                const Text("Réel", style: TextStyle(fontSize: 11, color: BLEU_LABEL)),
                Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, border: Border.all(color: border)),
                  child: Text(_reelRef[pos]!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ÉCRAN HISTORIQUE
// ----------------------------------------------------------------------
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _controles = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() async {
    final list = await DatabaseHelper.listerControles();
    setState(() => _controles = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _charger),
        ],
      ),
      body: _controles.isEmpty
          ? const Center(child: Text("Aucun contrôle enregistré."))
          : ListView.builder(
              itemCount: _controles.length,
              itemBuilder: (ctx, i) {
                final r = _controles[i];
                bool ok = r['conforme'] == 1;
                return Card(
                  child: ListTile(
                    title: Text("[${r['date_scan']}] Table ${r['table_numero'] ?? '-'} | Chariot ${r['code_base']}"),
                    subtitle: Text("Pos ${r['position']} | Attendu: ${r['reference_attendue']} | Scanné: ${r['reference_trouvee']}"),
                    trailing: Text(
                      ok ? "OK" : "NON CONFORME",
                      style: TextStyle(color: ok ? VERT_OK : ROUGE_ERR, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ----------------------------------------------------------------------
// ÉCRAN CORRECTION CHARIOT
// ----------------------------------------------------------------------
class ConfigChariotScreen extends StatefulWidget {
  const ConfigChariotScreen({super.key});

  @override
  State<ConfigChariotScreen> createState() => _ConfigChariotScreenState();
}

class _ConfigChariotScreenState extends State<ConfigChariotScreen> {
  bool _deverrouille = false;
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _seqCtrl = TextEditingController();
  int? _dernierCode;

  void _verifier() {
    if (_pwdCtrl.text == MDP_CORRECTION_CHARIOT) {
      setState(() => _deverrouille = true);
      _charger();
    } else {
      _pwdCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mot de passe incorrect.")));
    }
  }

  void _charger() async {
    int? code = await DatabaseHelper.getDernierCodeBase();
    setState(() => _dernierCode = code);
  }

  void _appliquer() async {
    if (_seqCtrl.text.isNotEmpty) {
      await DatabaseHelper.setDernierCodeBase(int.parse(_seqCtrl.text));
      _seqCtrl.clear();
      _charger();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Séquence mise à jour.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Correction N° Chariot")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: !_deverrouille
            ? Column(
                children: [
                  const Text("Accès protégé par mot de passe."),
                  TextField(
                    controller: _pwdCtrl,
                    autofocus: true,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Mot de passe"),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: _verifier, child: const Text("Déverrouiller")),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Dernier numéro de chariot enregistré : ${_dernierCode ?? '—'}", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _seqCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Forcer dernier n° chariot"))),
                      const SizedBox(width: 10),
                      ElevatedButton(onPressed: _appliquer, child: const Text("Appliquer")),
                    ],
                  )
                ],
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ÉCRAN CODE SIÈGE
// ----------------------------------------------------------------------
class ConfigSiegesScreen extends StatefulWidget {
  const ConfigSiegesScreen({super.key});

  @override
  State<ConfigSiegesScreen> createState() => _ConfigSiegesScreenState();
}

class _ConfigSiegesScreenState extends State<ConfigSiegesScreen> {
  bool _deverrouille = false;
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _newTableCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _refCtrl = TextEditingController();

  List<String> _tables = [];
  String? _tableSelectionee;
  List<Map<String, dynamic>> _references = [];

  void _verifier() {
    if (_pwdCtrl.text == MDP_PARAM_SIEGES) {
      setState(() => _deverrouille = true);
      _rafraichirTables();
    } else {
      _pwdCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mot de passe incorrect.")));
    }
  }

  void _rafraichirTables() async {
    List<String> t = await DatabaseHelper.listerTables();
    setState(() {
      _tables = t;
      if (_tableSelectionee == null && t.isNotEmpty) _tableSelectionee = t.first;
    });
    _rafraichirReferences();
  }

  void _rafraichirReferences() async {
    if (_tableSelectionee != null) {
      List<Map<String, dynamic>> refs = await DatabaseHelper.listerReferences(_tableSelectionee!);
      setState(() => _references = refs);
    } else {
      setState(() => _references = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Code Siège")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: !_deverrouille
            ? Column(
                children: [
                  const Text("Accès protégé par mot de passe."),
                  TextField(
                    controller: _pwdCtrl,
                    autofocus: true,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Mot de passe"),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: _verifier, child: const Text("Déverrouiller")),
                ],
              )
            : ListView(
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _newTableCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Numéro de table"))),
                      ElevatedButton(
                        onPressed: () async {
                          if (_newTableCtrl.text.isNotEmpty) {
                            await DatabaseHelper.ajouterTable(_newTableCtrl.text);
                            _newTableCtrl.clear();
                            _rafraichirTables();
                          }
                        },
                        child: const Text("Créer table"),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: _tables.map((num) {
                      bool sel = num == _tableSelectionee;
                      return ChoiceChip(
                        label: Text("Table $num"),
                        selected: sel,
                        onSelected: (_) {
                          setState(() => _tableSelectionee = num);
                          _rafraichirReferences();
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(),
                  if (_tableSelectionee != null) ...[
                    Text("Correspondances de la table $_tableSelectionee :", style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: "Code siège")),
                    TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: "Référence")),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        if (_codeCtrl.text.isNotEmpty && _refCtrl.text.isNotEmpty) {
                          await DatabaseHelper.ajouterReference(_tableSelectionee!, _codeCtrl.text, _refCtrl.text);
                          _codeCtrl.clear();
                          _refCtrl.clear();
                          _rafraichirReferences();
                        }
                      },
                      child: const Text("Ajouter / Mettre à jour"),
                    ),
                    const SizedBox(height: 10),
                    ..._references.map((r) => ListTile(
                          title: Text("${r['code_siege']} -> ${r['reference']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              await DatabaseHelper.supprimerReference(_tableSelectionee!, r['code_siege']);
                              _rafraichirReferences();
                            },
                          ),
                        )),
                  ]
                ],
              ),
      ),
    );
  }
}

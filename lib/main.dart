import 'package:flutter/material.dart';

void main() {
  runApp(const ConformiteApp());
}

class ConformiteApp extends StatelessWidget {
  const ConformiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conformité Sièges',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const ScanScreen(),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  
  String? tableCourante;
  String? chariotActuel;

  void _traiterScan(String raw) {
    _scanController.clear();
    _scanFocusNode.requestFocus(); // Maintenir le focus pour le scanner Honeywell

    if (raw.contains(';')) {
      // Logique Chariot
    } else if (raw.length <= 6 && RegExp(r'^\d+$').hasMatch(raw)) {
      // Logique Table
      setState(() {
        tableCourante = raw;
      });
    } else {
      // Logique Siège
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Siège Rang 3'),
        backgroundColor: const Color(0xFF0F2159), // NAVY
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              // Navigation vers Historique / Config
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'historique', child: Text('Historique')),
              const PopupMenuItem(value: 'chariot', child: Text('Correction N° Chariot')),
              const PopupMenuItem(value: 'sieges', child: Text('Code Siège')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // En-tête Table / Chariot
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: Text('Table n° : ${tableCourante ?? ""}')),
                Expanded(child: Text('Chariot n° : ${chariotActuel ?? ""}')),
              ],
            ),
          ),
          
          // Zone des 4 positions (1 à 4)
          // ...

          // Champ de scan
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _scanController,
              focusNode: _scanFocusNode,
              autofocus: true,
              onSubmitted: _traiterScan,
              decoration: const InputDecoration(
                hintText: 'Zone de Scan',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

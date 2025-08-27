// lib/main.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:cross_file/cross_file.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomerApp());
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Customer Ledger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomePage(),
    );
  }
}

/* --- Model --- */
class TransactionModel {
  final int? id;
  final String name;
  final double amount;
  final String type; // "Give" or "Take"
  final String date; // yyyy-MM-dd

  TransactionModel({this.id, required this.name, required this.amount, required this.type, required this.date});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'amount': amount, 'type': type, 'date': date};
}

/* --- DB helper (singleton) --- */
class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    // initialize DB
    final dbPath = join(await getDatabasesPath(), 'transactions.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          amount REAL,
          type TEXT,
          date TEXT
        )
      ''');
    });
    return _db!;
  }

  Future<int> insertTransaction(TransactionModel t) async {
    final db = await database;
    return await db.insert('transactions', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TransactionModel>> fetchAll({String? name, String? date}) async {
    final db = await database;
    String? where;
    List<dynamic>? args;

    if ((name != null && name.isNotEmpty) || (date != null && date.isNotEmpty)) {
      final clauses = <String>[];
      args = [];
      if (name != null && name.isNotEmpty) {
        clauses.add('LOWER(name) LIKE ?');
        args.add('%${name.toLowerCase()}%');
      }
      if (date != null && date.isNotEmpty) {
        clauses.add('date = ?');
        args.add(date);
      }
      where = clauses.join(' AND ');
    }

    final rows = await db.query('transactions', where: where, whereArgs: args, orderBy: 'id DESC');
    return rows.map((r) => TransactionModel(
      id: r['id'] as int?,
      name: r['name'] as String,
      amount: (r['amount'] as num).toDouble(),
      type: r['type'] as String,
      date: r['date'] as String,
    )).toList();
  }
}

/* --- Home Page --- */
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'Give';
  String _searchName = '';
  DateTime? _selectedDate;
  List<TransactionModel> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dateStr = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : null;
    _transactions = await DatabaseHelper.instance.fetchAll(name: _searchName, date: dateStr);
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) {
      _selectedDate = picked;
      await _load();
    }
  }

  Future<void> _addTransaction() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (name.isEmpty || amount <= 0) return;

    final t = TransactionModel(
      name: name,
      amount: amount,
      type: _type,
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    await DatabaseHelper.instance.insertTransaction(t);
    _nameCtrl.clear();
    _amountCtrl.clear();
    await _load();
  }

  double get _totalGive => _transactions.where((t) => t.type.toLowerCase()=='give').fold(0.0, (s,v) => s + v.amount);
  double get _totalTake => _transactions.where((t) => t.type.toLowerCase()=='take').fold(0.0, (s,v) => s + v.amount);
  double get _balance => _totalTake - _totalGive;

  Future<void> _exportToExcel() async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Transactions'];

    sheet.appendRow(['Name','Amount','Type','Date']);
    for (var t in _transactions) {
      sheet.appendRow([t.name, t.amount, t.type, t.date]);
    }
    sheet.appendRow([]);
    sheet.appendRow(['Total Given', _totalGive]);
    sheet.appendRow(['Total Taken', _totalTake]);
    sheet.appendRow(['Balance', _balance]);

    var bytes = excel.encode();
    if (bytes == null) return;
    final xfile = XFile.fromData(Uint8List.fromList(bytes), name: 'transactions.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await Share.shareXFiles([xfile], text: 'Transactions report');
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context ctx) {
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Transactions Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: ['Name','Amount','Type','Date'],
            data: _transactions.map((t) => [t.name, t.amount.toStringAsFixed(2), t.type, t.date]).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Total Given: ${_totalGive.toStringAsFixed(2)}'),
          pw.Text('Total Taken: ${_totalTake.toStringAsFixed(2)}'),
          pw.Text('Balance: ${_balance.toStringAsFixed(2)}'),
        ]);
      },
    ));

    final bytes = await pdf.save();
    final xfile = XFile.fromData(Uint8List.fromList(bytes), name: 'transactions.pdf', mimeType: 'application/pdf');
    await Share.shareXFiles([xfile], text: 'Transactions report');
  }

  @override
  Widget build(BuildContext context) {
    final selectedDateStr = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Transactions'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'excel') await _exportToExcel();
              if (v == 'pdf') await _exportToPdf();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'excel', child: Text('Export to Excel')),
              PopupMenuItem(value: 'pdf', child: Text('Export to PDF')),
            ],
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blueAccent, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: const InputDecoration(labelText: 'Search by name', border: OutlineInputBorder()),
                onChanged: (v) { _searchName = v; _load(); },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.date_range), label: const Text('Pick Date')),
              if (selectedDateStr != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text('Selected: $selectedDateStr')),
              TextButton(onPressed: () { _selectedDate = null; _load(); }, child: const Text('Clear Date')),
            ]),
            Expanded(
              child: _transactions.isEmpty
                ? const Center(child: Text('No transactions found'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (ctx, i) {
                      final t = _transactions[i];
                      return Card(margin: const EdgeInsets.all(8), child: ListTile(
                        title: Text(t.name),
                        subtitle: Text('${t.type.toUpperCase()} • Rs.${t.amount.toStringAsFixed(2)} • ${t.date}'),
                      ));
                    },
                  ),
            ),
            Card(
              color: Colors.indigo.shade100,
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  const Text('Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Total Given: Rs.${_totalGive.toStringAsFixed(2)}'),
                  Text('Total Taken: Rs.${_totalTake.toStringAsFixed(2)}'),
                  Text('Balance: Rs.${_balance.toStringAsFixed(2)}'),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(child: TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Customer Name', filled: true, fillColor: Colors.white)) ),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Amount', filled: true, fillColor: Colors.white)) ),
                const SizedBox(width: 8),
                DropdownButton<String>(value: _type, items: const [DropdownMenuItem(value: 'Give', child: Text('Give')), DropdownMenuItem(value: 'Take', child: Text('Take'))], onChanged: (v){ setState((){ _type = v!; }); }),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () async { await _addTransaction(); }, child: const Text('Add')),
              ]),
            )
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';

void main() {
  runApp(CustomerLedgerApp());
}

class CustomerLedgerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Customer Ledger',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LedgerHomePage(),
    );
  }
}

class Transaction {
  final String name;
  final double amount;
  final bool isCredit;
  final DateTime date;

  Transaction(
      {required this.name,
      required this.amount,
      required this.isCredit,
      required this.date});
}

class LedgerHomePage extends StatefulWidget {
  @override
  _LedgerHomePageState createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends State<LedgerHomePage> {
  final List<Transaction> _transactions = [];
  String _searchQuery = "";
  DateTime? _selectedDate;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  void _addTransaction(bool isCredit) {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) return;

    setState(() {
      _transactions.add(Transaction(
        name: _nameController.text,
        amount: double.parse(_amountController.text),
        isCredit: isCredit,
        date: DateTime.now(),
      ));
    });

    _nameController.clear();
    _amountController.clear();
  }

  List<Transaction> get _filteredTransactions {
    return _transactions.where((tx) {
      final matchName = _searchQuery.isEmpty ||
          tx.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchDate = _selectedDate == null ||
          (tx.date.year == _selectedDate!.year &&
              tx.date.month == _selectedDate!.month &&
              tx.date.day == _selectedDate!.day);
      return matchName && matchDate;
    }).toList();
  }

  double get _totalAmount {
    return _filteredTransactions.fold(
        0,
        (sum, tx) => sum + (tx.isCredit ? tx.amount : -tx.amount));
  }

  Future<void> _exportToExcel() async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Transactions'];
    sheet.appendRow(["Name", "Amount", "Type", "Date"]);

    for (var tx in _filteredTransactions) {
      sheet.appendRow([
        tx.name,
        tx.amount,
        tx.isCredit ? "Credit" : "Debit",
        DateFormat('yyyy-MM-dd').format(tx.date)
      ]);
    }

    final fileBytes = excel.encode()!;
    final tempFile = Uint8List.fromList(fileBytes);

    await Share.shareXFiles(
      [XFile.fromData(tempFile, name: 'transactions.xlsx')],
      text: 'Customer Transactions',
    );
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Table.fromTextArray(
          headers: ["Name", "Amount", "Type", "Date"],
          data: _filteredTransactions.map((tx) {
            return [
              tx.name,
              tx.amount.toString(),
              tx.isCredit ? "Credit" : "Debit",
              DateFormat('yyyy-MM-dd').format(tx.date),
            ];
          }).toList(),
        ),
      ),
    );

    final pdfBytes = await pdf.save();
    await Share.shareXFiles(
      [XFile.fromData(pdfBytes, name: 'transactions.pdf')],
      text: 'Customer Transactions',
    );
  }

  void _pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Customer Ledger"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "excel") {
                _exportToExcel();
              } else if (value == "pdf") {
                _exportToPdf();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: "excel", child: Text("Export to Excel")),
              PopupMenuItem(value: "pdf", child: Text("Export to PDF")),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: "Customer Name"),
            ),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Amount"),
            ),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _addTransaction(true),
                  child: Text("Credit"),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _addTransaction(false),
                  child: Text("Debit"),
                ),
              ],
            ),
            TextField(
              decoration: InputDecoration(labelText: "Search by Name"),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _pickDate,
                  child: Text("Pick Date"),
                ),
                SizedBox(width: 10),
                if (_selectedDate != null)
                  Text(DateFormat('yyyy-MM-dd').format(_selectedDate!)),
              ],
            ),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredTransactions.length,
                itemBuilder: (context, index) {
                  final tx = _filteredTransactions[index];
                  return ListTile(
                    title: Text(tx.name),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(tx.date)),
                    trailing: Text(
                      "${tx.isCredit ? '+' : '-'}${tx.amount}",
                      style: TextStyle(
                        color: tx.isCredit ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
            Text(
              "Total: $_totalAmount",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            )
          ],
        ),
      ),
    );
  }
}

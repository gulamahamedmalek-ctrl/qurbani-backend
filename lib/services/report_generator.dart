import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'platform_helper.dart';

/// Generates PDF reports for filtered booking data.
class ReportGenerator {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_regularFont != null && _boldFont != null) return;
    try {
      final regularResp = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/fontsource/fonts/noto-sans@latest/latin-400-normal.ttf'));
      final boldResp = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/fontsource/fonts/noto-sans@latest/latin-700-normal.ttf'));
      if (regularResp.statusCode == 200 && boldResp.statusCode == 200) {
        _regularFont = pw.Font.ttf(regularResp.bodyBytes.buffer.asByteData());
        _boldFont = pw.Font.ttf(boldResp.bodyBytes.buffer.asByteData());
      }
    } catch (_) {}
  }

  /// Generate a filtered bookings report as PDF.
  static Future<void> generateReport({
    required List<Map<String, dynamic>> bookings,
    required String title,
    required String currencySymbol,
    required String organizationName,
    String? dateRange,
    String? categoryFilter,
    String? referenceFilter,
  }) async {
    await _loadFonts();

    final cur = currencySymbol == '\u20b9' ? 'Rs.' : currencySymbol;
    final navy = PdfColor.fromHex('#0D5C46');
    final lightBg = PdfColor.fromHex('#e6efe9');

    // Calculate totals
    double totalAmount = 0;
    int totalHissah = 0;
    for (var b in bookings) {
      totalAmount += (b['total_amount'] ?? 0).toDouble();
      totalHissah += (b['hissah_count'] ?? 0) as int;
    }

    // Reference breakdown
    final refMap = <String, _RefStat>{};
    for (var b in bookings) {
      final ref = (b['reference'] ?? 'N/A').toString();
      refMap.putIfAbsent(ref, () => _RefStat());
      refMap[ref]!.count++;
      refMap[ref]!.hissahs += (b['hissah_count'] ?? 0) as int;
      refMap[ref]!.amount += (b['total_amount'] ?? 0).toDouble();
    }

    // Category breakdown
    final catMap = <String, _RefStat>{};
    for (var b in bookings) {
      final cat = (b['category_title'] ?? 'N/A').toString();
      catMap.putIfAbsent(cat, () => _RefStat());
      catMap[cat]!.count++;
      catMap[cat]!.hissahs += (b['hissah_count'] ?? 0) as int;
      catMap[cat]!.amount += (b['total_amount'] ?? 0).toDouble();
    }

    final pdf = pw.Document(
      theme: _regularFont != null
          ? pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont ?? _regularFont!)
          : null,
    );

    // Build filter description
    final filters = <String>[];
    if (dateRange != null) filters.add('Date: $dateRange');
    if (categoryFilter != null && categoryFilter != 'All') filters.add('Category: $categoryFilter');
    if (referenceFilter != null && referenceFilter != 'All') filters.add('Reference: $referenceFilter');
    final filterStr = filters.isEmpty ? 'All Bookings' : filters.join(' | ');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(organizationName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.Text('Booking Report', style: pw.TextStyle(fontSize: 14, color: navy)),
          ]),
          pw.SizedBox(height: 4),
          pw.Text(filterStr, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Divider(color: navy, thickness: 1.5),
          pw.SizedBox(height: 8),
        ]),
        footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Generated on ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ]),
        build: (ctx) => [
          // Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: lightBg, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              _summaryItem('Total Bookings', '${bookings.length}'),
              _summaryItem('Total Hissahs', '$totalHissah'),
              _summaryItem('Total Amount', '$cur${totalAmount.toStringAsFixed(0)}'),
            ]),
          ),
          pw.SizedBox(height: 16),

          // Category Breakdown
          if (catMap.length > 1) ...[
            pw.Text('Category Breakdown', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              headers: ['Category', 'Bookings', 'Hissahs', 'Amount'],
              data: catMap.entries.map((e) => [e.key, '${e.value.count}', '${e.value.hissahs}', '$cur${e.value.amount.toStringAsFixed(0)}']).toList(),
            ),
            pw.SizedBox(height: 16),
          ],

          // Reference Breakdown
          if (refMap.length > 1) ...[
            pw.Text('Reference Breakdown', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              headers: ['Reference', 'Bookings', 'Hissahs', 'Amount'],
              data: refMap.entries.map((e) => [e.key, '${e.value.count}', '${e.value.hissahs}', '$cur${e.value.amount.toStringAsFixed(0)}']).toList(),
            ),
            pw.SizedBox(height: 16),
          ],

          // Booking Details Table
          pw.Text('Booking Details', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            columnWidths: {0: const pw.FixedColumnWidth(50), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2), 3: const pw.FixedColumnWidth(40), 4: const pw.FlexColumnWidth(1.5), 5: const pw.FlexColumnWidth(2)},
            headers: ['Receipt', 'Name', 'Category', 'Hissah', 'Amount', 'Reference'],
            data: bookings.map((b) => [
              b['receipt_no'] ?? '',
              b['representative_name'] ?? '',
              b['category_title'] ?? '',
              '${b['hissah_count'] ?? 0}',
              '$cur${(b['total_amount'] ?? 0).toDouble().toStringAsFixed(0)}',
              b['reference'] ?? '',
            ]).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await PlatformHelper.instance.saveAndOpenPdf(Uint8List.fromList(bytes), 'Booking_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  static pw.Widget _summaryItem(String label, String value) {
    return pw.Column(children: [
      pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ]);
  }
}

class _RefStat {
  int count = 0;
  int hissahs = 0;
  double amount = 0;
}

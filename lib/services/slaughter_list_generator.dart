import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'platform_helper.dart';
import 'database_service.dart';

/// Generates a "Slaughter List" PDF organized by Token.
/// Each token shows all owner names so the person performing
/// the sacrifice knows exactly whose names to recite.
class SlaughterListGenerator {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_regularFont != null && _boldFont != null) return;
    try {
      final r = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/fontsource/fonts/noto-sans@latest/latin-400-normal.ttf'));
      final b = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/fontsource/fonts/noto-sans@latest/latin-700-normal.ttf'));
      if (r.statusCode == 200 && b.statusCode == 200) {
        _regularFont = pw.Font.ttf(r.bodyBytes.buffer.asByteData());
        _boldFont = pw.Font.ttf(b.bodyBytes.buffer.asByteData());
      }
    } catch (_) {}
  }

  /// Generate and download the Slaughter List PDF.
  /// [category] - optional filter by category name.
  static Future<void> generate({
    required String organizationName,
    required String currencySymbol,
    String? category,
  }) async {
    await _loadFonts();

    final navy = PdfColor.fromHex('#0D5C46');
    final lightGreen = PdfColor.fromHex('#e6efe9');
    final cur = currencySymbol == '\u20b9' ? 'Rs.' : currencySymbol;

    // Fetch all tokens from backend
    final tokens = await DatabaseService.loadTokens(category: category);
    if (tokens.isEmpty) return;

    // Sort tokens by token_no
    tokens.sort((a, b) => (a['token_no'] ?? 0).compareTo(b['token_no'] ?? 0));

    final pdf = pw.Document(
      theme: _regularFont != null
          ? pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont ?? _regularFont!)
          : null,
    );

    final catLabel = category ?? 'All Categories';
    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}/${now.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => pw.Column(children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(organizationName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('SLAUGHTER LIST',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: navy)),
                  pw.Text(catLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.Divider(color: navy, thickness: 2),
          pw.SizedBox(height: 4),
        ]),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated: $dateStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          ],
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[];

          for (final token in tokens) {
            final int tokenNo = token['token_no'] ?? 0;
            final int maxSlots = token['max_slots'] ?? 7;
            final bool isDone = token['qurbani_done'] == true;
            final String catTitle = token['category_title'] ?? '';
            List<dynamic> entries = List.from(token['entries'] ?? []);
            entries.sort((a, b) => (a['serial_no'] ?? 0).compareTo(b['serial_no'] ?? 0));

            // Token Header
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: isDone ? PdfColor.fromHex('#d4edda') : lightGreen,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: navy, width: 1),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOKEN #$tokenNo',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: navy)),
                    pw.Row(children: [
                      pw.Text('$catTitle  |  ${entries.length}/$maxSlots Hissah',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                      if (isDone) ...[
                        pw.SizedBox(width: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#28a745'), borderRadius: pw.BorderRadius.circular(4)),
                          child: pw.Text('DONE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            );

            // Names Table for this token
            final tableData = <List<String>>[];
            for (int i = 0; i < maxSlots; i++) {
              if (i < entries.length) {
                final e = entries[i];
                tableData.add([
                  '${i + 1}',
                  e['owner_name'] ?? '—',
                  e['purpose'] ?? '',
                  e['representative_name'] ?? '',
                  e['receipt_no'] ?? '',
                ]);
              } else {
                tableData.add(['${i + 1}', '— (Empty) —', '', '', '']);
              }
            }

            widgets.add(
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: navy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FixedColumnWidth(25),
                  1: const pw.FlexColumnWidth(4),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(3),
                  4: const pw.FlexColumnWidth(1.5),
                },
                headers: ['#', 'Owner Name (Say During Sacrifice)', 'Purpose', 'Booked By', 'Receipt'],
                data: tableData,
              ),
            );

            widgets.add(pw.SizedBox(height: 6));
          }

          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'Slaughter_List_${category ?? "All"}_${now.millisecondsSinceEpoch}.pdf';
    await PlatformHelper.instance.saveAndOpenPdf(Uint8List.fromList(bytes), fileName);
  }
}

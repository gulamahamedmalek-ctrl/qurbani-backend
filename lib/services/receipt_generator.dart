import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'platform_helper.dart';

/// Generates a PDF receipt matching the Qurbani receipt format.
class ReceiptGenerator {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  /// Load Google Noto Sans fonts for full Unicode support.
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

  /// Decode base64 logo into a MemoryImage for the PDF.
  static pw.MemoryImage? _decodeLogo(String logoBase64) {
    if (logoBase64.isEmpty) return null;
    try {
      // Handle data URI format: "data:image/png;base64,..."
      String cleanBase64 = logoBase64;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      final bytes = base64Decode(cleanBase64);
      if (bytes.isNotEmpty) {
        return pw.MemoryImage(Uint8List.fromList(bytes));
      }
    } catch (_) {}
    return null;
  }

  /// Generate and trigger download of the receipt PDF.
  static Future<void> generateAndPrint({
    required String receiptNo,
    required String date,
    required String categoryTitle,
    required String representativeName,
    required String referenceName,
    required List<String> ownerNames,
    required String address,
    required String mobile,
    required String purpose,
    required double amountPerHissah,
    required int hissahCount,
    required double totalAmount,
    required String currencySymbol,
    required String organizationName,
    required List<Map<String, dynamic>> tokenAssignments,
    int maxSlots = 7,
    String logoBase64 = '',
    String rulesAttachmentBase64 = '',
  }) async {
    await _loadFonts();

    // Decode logo
    final logoImage = _decodeLogo(logoBase64);
    final rulesImage = _decodeLogo(rulesAttachmentBase64);

    // Safe currency (avoid Unicode issues with built-in fonts)
    final cur = currencySymbol == '\u20b9' ? 'Rs.' : currencySymbol;

    // Token numbers string
    final tokenNos = tokenAssignments.map((a) => a['token_no']).toSet().toList();
    final tokenNoStr = tokenNos.isNotEmpty ? tokenNos.map((n) => '#$n').join(', ') : '-';

    final pdf = pw.Document(
      theme: _regularFont != null
          ? pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont ?? _regularFont!)
          : null,
    );

    final navy = PdfColor.fromHex('#0D5C46');
    final lightBg = PdfColor.fromHex('#e6efe9');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context ctx) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: navy, width: 2),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: navy, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // ── HEADER ──
                    _header(navy, logoImage, organizationName, receiptNo, date, tokenNoStr),

                    // ── CUSTOMER INFO ──
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: navy, width: 0.5)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                            _field('Name (Janaab)', representativeName, 5),
                          ]),
                          pw.SizedBox(height: 4),
                          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                            _field('Address', address, 3),
                            pw.SizedBox(width: 16),
                            _field('Mobile', mobile, 2),
                          ]),
                        ],
                      ),
                    ),

                    // ── BODY: Table + Summary ──
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // LEFT: Names table
                          pw.Expanded(
                            flex: 3,
                            child: pw.Container(
                              decoration: pw.BoxDecoration(
                                border: pw.Border(right: pw.BorderSide(color: navy, width: 0.5)),
                              ),
                              child: pw.Column(
                                children: [
                                  // Table header
                                  pw.Container(
                                    color: navy,
                                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                    child: pw.Row(children: [
                                      pw.SizedBox(width: 28, child: pw.Text('No.',
                                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                                      pw.Expanded(child: pw.Text('Name',
                                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                                    ]),
                                  ),
                                  // Rows
                                  ...List.generate(maxSlots, (i) {
                                    final name = i < ownerNames.length ? ownerNames[i] : '';
                                    final tkn = i < tokenAssignments.length
                                        ? 'T${tokenAssignments[i]['token_no']}-${tokenAssignments[i]['serial_no']}'
                                        : '';
                                    return pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                                      decoration: pw.BoxDecoration(
                                        color: i % 2 == 0 ? PdfColors.white : lightBg,
                                        border: pw.Border(bottom: pw.BorderSide(color: navy, width: 0.3)),
                                      ),
                                      child: pw.Row(children: [
                                        pw.SizedBox(width: 28, child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 9))),
                                        pw.Expanded(child: pw.Text(name, style: const pw.TextStyle(fontSize: 9))),
                                      ]),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),

                          // RIGHT: Summary panel
                          pw.Expanded(
                            flex: 2,
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Column(
                                children: [
                                  // Purpose
                                  pw.Container(
                                    padding: const pw.EdgeInsets.all(8),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border.all(color: navy, width: 0.5),
                                      borderRadius: pw.BorderRadius.circular(4),
                                    ),
                                    child: pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _checkBox('Qurbani', purpose == 'Qurbani'),
                                        _checkBox('Aqiqah', purpose == 'Aqiqah'),
                                      ],
                                    ),
                                  ),
                                  pw.SizedBox(height: 10),
                                  _summaryLine('Fee / Hissah', '$cur ${amountPerHissah.toStringAsFixed(0)}', navy),
                                  _summaryLine('Total Hissah', '$hissahCount', navy),
                                  _summaryLine('Category', categoryTitle, navy),
                                  pw.SizedBox(height: 10),
                                  // Total
                                  pw.Container(
                                    padding: const pw.EdgeInsets.all(10),
                                    decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(6)),
                                    child: pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                      children: [
                                        pw.Text('TOTAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                                        pw.Text('$cur ${totalAmount.toStringAsFixed(0)}',
                                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.yellow)),
                                      ],
                                    ),
                                  ),
                                  pw.Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── FOOTER ──
                    pw.Container(
                      color: lightBg,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Zimmedar Signature ___________', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('Collector Signature ___________', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('Note: Keep this receipt safe.',
                              style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    // ── PAGE 2: Rules Attachment (If exists) ──
    if (rulesImage != null) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context ctx) {
            return pw.Center(
              child: pw.Image(rulesImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    // Download/Save PDF
    final bytes = await pdf.save();
    await PlatformHelper.instance.saveAndOpenPdf(bytes, 'Receipt_$receiptNo.pdf');
  }

  // ════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════

  /// Build the header section with optional logo.
  static pw.Widget _header(PdfColor bg, pw.MemoryImage? logo,
      String orgName, String receiptNo, String date, String tokenNo) {
    final leftWidgets = <pw.Widget>[];

    if (logo != null) {
      leftWidgets.add(pw.Container(
        width: 55, height: 55,
        margin: const pw.EdgeInsets.only(right: 10),
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      ));
    }

    // Auto-size org name font: shrink if name is long
    final nameSize = orgName.length > 20 ? 12.0 : 16.0;

    leftWidgets.add(pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(3)),
            child: pw.Text('Qurbani Department',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: bg)),
          ),
          pw.SizedBox(height: 4),
          pw.Text(orgName,
              style: pw.TextStyle(fontSize: nameSize, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              maxLines: 2,
              overflow: pw.TextOverflow.clip),
        ],
      ),
    ));

    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left: Logo + Org name (flexible, takes remaining space)
          pw.Expanded(child: pw.Row(children: leftWidgets)),
          pw.SizedBox(width: 10),
          // Right: Receipt info (fixed width, never gets pushed off)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _labelValue('Receipt No.', receiptNo, PdfColors.white),
              pw.SizedBox(height: 3),
              _labelValue('Date', date, PdfColors.white),
              pw.SizedBox(height: 3),
              _labelValue('Token', tokenNo, PdfColors.white),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _labelValue(String label, String value, PdfColor color) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('$label: ', style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#A3D1C6'))),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  static pw.Widget _field(String label, String value, int flex) {
    return pw.Expanded(
      flex: flex,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Expanded(
            child: pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
              child: pw.Text(' $value', style: const pw.TextStyle(fontSize: 9), softWrap: true),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _checkBox(String label, bool checked) {
    final navy = PdfColor.fromHex('#1B2A4A');
    return pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Container(
        width: 12, height: 12,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 1, color: navy),
          borderRadius: pw.BorderRadius.circular(2),
          color: checked ? navy : PdfColors.white,
        ),
        child: checked
            ? pw.Center(child: pw.Text('✓', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)))
            : pw.SizedBox(),
      ),
      pw.SizedBox(width: 4),
      pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: checked ? pw.FontWeight.bold : pw.FontWeight.normal)),
    ]);
  }

  static pw.Widget _summaryLine(String label, String value, PdfColor borderColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: borderColor, width: 0.3))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}

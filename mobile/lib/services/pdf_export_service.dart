/// DesignMirror AI — PDF Export Service
///
/// Generates a styled PDF report for a fit-check result that can be
/// shared or printed directly from the app.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../config/units.dart';

class PdfExportService {
  PdfExportService._();

  /// Generate and share a fit-check report PDF.
  ///
  /// [roomName], [roomDims] – room metadata.
  /// [productName], [productCategory], [productDims] – product metadata.
  /// [fits], [verdict], [designScore] – fit-check result.
  /// [clearance] – N/S/E/W clearances in meters.
  /// [fillPercent] – floor fill percentage.
  /// [suggestion] – AI suggestion text.
  /// [diagramKey] – GlobalKey of the diagram widget for screenshot.
  static Future<void> generateAndShare({
    required String roomName,
    required Map<String, double> roomDims,
    required String productName,
    required String productCategory,
    required Map<String, double> productDims,
    required bool fits,
    required String verdict,
    required int designScore,
    required Map<String, double> clearance,
    required double fillPercent,
    String? suggestion,
    GlobalKey? diagramKey,
  }) async {
    final pdf = pw.Document();

    final accentColor = PdfColor.fromInt(0xFFE17055);
    final successColor = PdfColor.fromInt(0xFF00B894);
    final errorColor = PdfColor.fromInt(0xFFD63031);
    final verdictColor = fits ? successColor : errorColor;

    Uint8List? diagramImage;
    if (diagramKey != null) {
      diagramImage = await _captureDiagram(diagramKey);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DesignMirror',
                      style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF2D3436))),
                  pw.Text('Fit-Check Report',
                      style: pw.TextStyle(
                          fontSize: 14, color: accentColor)),
                ],
              ),
              pw.Divider(thickness: 2, color: accentColor),
              pw.SizedBox(height: 16),

              // Verdict Banner
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: verdictColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  fits
                      ? 'FITS — Design Score: $designScore/100'
                      : verdict == 'too_large'
                          ? 'DOES NOT FIT — Too Large'
                          : 'TIGHT FIT — Design Score: $designScore/100',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 20),

              // Room & Product Side by Side
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                      child: _infoBox(
                    'Room: $roomName',
                    [
                      'Width: ${_fmt(roomDims['width'] ?? 0)}',
                      'Length: ${_fmt(roomDims['length'] ?? 0)}',
                      'Height: ${_fmt(roomDims['height'] ?? 0)}',
                    ],
                    PdfColor.fromInt(0xFF90CAF9),
                  )),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                      child: _infoBox(
                    'Product: $productName',
                    [
                      'Category: $productCategory',
                      'Width: ${_fmt(productDims['width'] ?? 0)}',
                      'Depth: ${_fmt(productDims['depth'] ?? 0)}',
                      'Height: ${_fmt(productDims['height'] ?? 0)}',
                    ],
                    accentColor,
                  )),
                ],
              ),
              pw.SizedBox(height: 20),

              // Clearance & Fill
              pw.Text('Clearance',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Row(children: [
                _clearanceBox('N', clearance['north'] ?? 0),
                pw.SizedBox(width: 8),
                _clearanceBox('S', clearance['south'] ?? 0),
                pw.SizedBox(width: 8),
                _clearanceBox('E', clearance['east'] ?? 0),
                pw.SizedBox(width: 8),
                _clearanceBox('W', clearance['west'] ?? 0),
                pw.Spacer(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                      'Floor Coverage: ${fillPercent.toStringAsFixed(1)}%',
                      style: const pw.TextStyle(fontSize: 12)),
                ),
              ]),
              pw.SizedBox(height: 20),

              // Suggestion
              if (suggestion != null && suggestion.isNotEmpty) ...[
                pw.Text('Suggestion',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFFF3E0),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(suggestion,
                      style: const pw.TextStyle(fontSize: 11)),
                ),
                pw.SizedBox(height: 20),
              ],

              // Diagram screenshot
              if (diagramImage != null)
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(diagramImage),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),

              // Footer
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.Text(
                'Generated by DesignMirror AI • ${DateTime.now().toString().substring(0, 16)}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/fitcheck_${roomName.replaceAll(' ', '_')}_${productName.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)],
        text: 'DesignMirror Fit-Check Report');
  }

  static String _fmt(double meters) => DimensionFormatter.format(meters);

  static pw.Widget _infoBox(
      String title, List<String> lines, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 1.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
          pw.SizedBox(height: 6),
          ...lines.map((l) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(l, style: const pw.TextStyle(fontSize: 11)),
              )),
        ],
      ),
    );
  }

  static pw.Widget _clearanceBox(String dir, double meters) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(children: [
        pw.Text(dir,
            style:
                pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(_fmt(meters), style: const pw.TextStyle(fontSize: 10)),
      ]),
    );
  }

  /// Capture a widget tree as a PNG image.
  static Future<Uint8List?> _captureDiagram(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pay_period_service.dart';

/// Builds a printable PDF timesheet report from detailed, punch-level
/// data — the printable counterpart to PayPeriodService's CSV/summary
/// exports.
///
/// Uses pw.MultiPage rather than a fixed pw.Page: an earlier version
/// hard-batched 4 employees per page inside a fixed-height pw.Expanded,
/// which assumed every employee's two-week table would always fit that
/// quarter of a page. That assumption broke on data-heavy companies —
/// lots of punches in a week (edits, multiple entries a day) pushed a
/// page's total content taller than the page itself, which the pdf
/// package can't reflow inside a single fixed pw.Page and instead
/// throws a layout assertion (childSize <= maxChildExtent) rather than
/// silently clipping.
///
/// A second, subtler version of the same crash survived that first fix:
/// each employee's block was still one pw.Container (a bordered box)
/// wrapping a pw.Row of two side-by-side week tables. Container and Row
/// are BOTH atomic in this library — pw.MultiPage can break the page
/// between one employee's block and the next, but it can't split
/// *inside* either of them. A locked pay period is always a full,
/// completed two weeks (a still-open current period is whatever's
/// elapsed so far, usually less) — enough extra punch rows to make one
/// employee's whole boxed block taller than a page's remaining space,
/// which still isn't splittable, so it hit the exact same assertion.
/// Every week table below is now its own top-level item in the page's
/// widget list instead of being nested inside a Container/Row — since
/// pw.Table itself DOES support splitting across a page break, there is
/// no longer any single atomic block whose height depends on how much
/// data it holds.
class TimesheetPdfGenerator {
  static Future<Uint8List> generate({
    required String companyName,
    required String payPeriodLabel,
    required List<DetailedTimesheet> timesheets,
  }) async {
    final doc = pw.Document();

    if (timesheets.isEmpty) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Center(
          child: pw.Text('No time entries for this pay period.', style: const pw.TextStyle(fontSize: 14)),
        ),
      ));
      return doc.save();
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Timesheet Report — $payPeriodLabel', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ),
        build: (context) => timesheets.expand(_buildEmployeeBlocks).toList(),
      ),
    );

    return doc.save();
  }

  /// One employee's worth of content as a flat list of independent
  /// top-level widgets (a header row, then each week's table) rather
  /// than a single nested block — see the class doc comment for why
  /// that nesting was the actual source of the "locked periods only"
  /// crash. A thin pw.Divider stands in for the old bordered box's
  /// visual separation between employees; unlike a real border it has
  /// a fixed, tiny height regardless of data volume, so it can never
  /// itself be the thing that doesn't fit.
  static List<pw.Widget> _buildEmployeeBlocks(DetailedTimesheet ts) {
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Divider(color: PdfColors.grey300, thickness: 0.6),
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            ts.employeeName + (ts.isArchived ? ' (Archived)' : ''),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Period Total: ${_fmtHours(ts.periodTotalHours)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
      pw.SizedBox(height: 4),
      // Stacked rather than side-by-side now (see class doc comment),
      // so each week needs its own label to stay visually distinct —
      // previously that distinction came for free from their left/
      // right position in a Row.
      for (final week in ts.weeks) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text(
            'Week of ${_fmtDate(week.weekStart)}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
          ),
        ),
        _buildWeekTable(week),
        pw.SizedBox(height: 8),
      ],
    ];
  }

  static pw.Widget _buildWeekTable(WeekTimesheet week) {
    final headerStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700);
    final cellStyle = const pw.TextStyle(fontSize: 7);

    pw.Widget cell(String text, {pw.TextStyle? style}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
          child: pw.Text(text, style: style ?? cellStyle),
        );
    final editedCellStyle = pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(1.1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [cell('Date', style: headerStyle), cell('Time', style: headerStyle), cell('Hours', style: headerStyle)],
        ),
        for (final punch in week.punches)
          pw.TableRow(children: [
            cell(_fmtDate(punch.date)),
            cell(punch.isMissingClockOut ? '${_fmtTime(punch.clockInAt)} - (open)' : '${_fmtTime(punch.clockInAt)} - ${_fmtTime(punch.clockOutAt!)}'),
            cell(punch.isMissingClockOut ? '—' : _fmtHours(punch.hours), style: punch.isEdited ? editedCellStyle : cellStyle),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            cell(''),
            cell('Week Total', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
            cell(_fmtHours(week.totalHours), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  static String _fmtDate(DateTime d) => '${d.month}/${d.day}';

  static String _fmtTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  static String _fmtHours(double hours) {
    final wholeHours = hours.floor();
    final minutes = ((hours - wholeHours) * 60).round();
    if (minutes == 0) return '${wholeHours}h';
    return '${wholeHours}h ${minutes}m';
  }
}

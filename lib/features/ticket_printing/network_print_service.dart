import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:myapp/core/constants/network_constants.dart';

class NetworkPrintService {
  Future<bool> printMultipleTickets({
    required String ip,
    int port = 9100,
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
  }) async {
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);
    final res = await printer.connect(ip, port: port, timeout: const Duration(seconds: 2));
    if (res != PosPrintResult.success) {
      return false;
    }

    try {
      for (int i = 0; i < numberOfTickets; i++) {
        final code = ticketCodes[i];
        final validationUrl = '${kBaseUrl.replaceAll('/api', '')}/validate/$code';

        printer.feed(1);
        printer.text('TICKET', styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2, bold: true));
        printer.text('Ticket #${i + 1} of $numberOfTickets', styles: const PosStyles(align: PosAlign.center));
        printer.feed(1);

        printer.text('================================', styles: const PosStyles(align: PosAlign.center));
        printer.text(eventName.toUpperCase(), styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2));
        printer.text('================================', styles: const PosStyles(align: PosAlign.center));
        printer.feed(1);

        printer.row([
          PosColumn(text: 'Type:', width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: ticketType, width: 8),
        ]);
        printer.row([
          PosColumn(text: 'Price:', width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: 'N ${price.toStringAsFixed(2)}', width: 8, styles: const PosStyles(bold: true)),
        ]);
        printer.feed(1);

        printer.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));
        printer.text('CUSTOMER', styles: const PosStyles(bold: true));
        printer.text(customerName);
        if (customerEmail != null && customerEmail.isNotEmpty) printer.text(customerEmail);
        if (customerPhone != null && customerPhone.isNotEmpty) printer.text(customerPhone);
        printer.feed(1);

        printer.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));
        printer.feed(1);

        printer.qrcode(validationUrl, size: QRSize.Size7, align: PosAlign.center);
        printer.feed(1);
        printer.text('SCAN THIS CODE AT ENTRANCE', styles: const PosStyles(align: PosAlign.center, bold: true));

        final now = DateTime.now();
        final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
        printer.text('Txn: ${transactionId.substring(0, transactionId.length > 20 ? 20 : transactionId.length)}');
        printer.text(dateStr, styles: const PosStyles(align: PosAlign.center));

        printer.feed(2);
        printer.cut();
      }
    } catch (e) {
      try { printer.disconnect(); } catch (_) {}
      return false;
    }

    try { printer.disconnect(); } catch (_) {}
    return true;
  }
}

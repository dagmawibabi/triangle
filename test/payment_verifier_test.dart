import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:teleai/features/finance/payment_verifier.dart';

void main() {
  test('reads a receipt PDF laid out in rows and in label-above-value blocks', () async {
    final doc = pw.Document();
    pw.Widget row(String a, String b) => pw.Row(children: [pw.SizedBox(width: 200, child: pw.Text(a)), pw.Text(b)]);
    doc.addPage(pw.Page(build: (_) => pw.Column(children: [
      row('Payer', 'ABEBE KEBEDE'),
      row('Payment Date & Time', '11/12/2026, 9:41:22 AM'),
      row('Transferred Amount', '1,250.00 ETB'),
      pw.Text('Reference No.'),
      pw.Text('FT26316ABCDE'),
      row('Receiver', 'SELAM TADESSE'),
    ])));
    final text = PaymentVerifier.pdfText(Uint8List.fromList(await doc.save()));
    final f = PaymentVerifier.fieldsFromText(text);
    expect(f['payer'], 'ABEBE KEBEDE');
    expect(f['receiver'], 'SELAM TADESSE');
    expect(f['date'], '11/12/2026, 9:41:22 AM');
    expect(f['reference'], 'FT26316ABCDE');
    expect(PaymentVerifier.amountOf(f['amount']), 1250.0);
  });

  test('guesses the bank from the reference and builds receipt links', () {
    expect(PaymentVerifier.guessBank('FT26316ABCDE'), 'cbe');
    expect(PaymentVerifier.guessBank('CHQ0FJ403O'), 'telebirr');
    expect(PaymentVerifier.receiptUrls('cbe', 'ft26316abcde', ['1000123456789']).single.toString(), 'https://apps.cbe.com.et:100/?id=FT26316ABCDE23456789');
    expect(PaymentVerifier.receiptUrls('telebirr', 'CHQ0FJ403O', const []).single.host, 'transactioninfo.ethiotelecom.et');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seqotia/app/seqotia_app.dart';

void main() {
  testWidgets('local login page explains that authentication is not configured',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('ยินดีต้อนรับสู่ Seqotia'), findsOneWidget);
    expect(find.text('เข้าสู่พื้นที่ทดลอง'), findsOneWidget);
    expect(find.textContaining('ระบบเข้าสู่ระบบยังไม่ได้เชื่อมต่อ'), findsOneWidget);
  });
}

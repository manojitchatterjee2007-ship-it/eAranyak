import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec.yaml has release version 3.0.0+4', () {
    final file = File('pubspec.yaml');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content.contains('version: 3.0.0+4'), isTrue);
  });

  test('main_navigation_shell.dart contains eআরণ্যক 3.0 release title and Bengali statement', () {
    final file = File('lib/screens/main_navigation_shell.dart');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content.contains("String _appVersion = '3.0.0';"), isTrue);
    expect(content.contains('eআরণ্যক 3.0 — প্রকৃতির সঙ্গে পরিচয়ের এক নতুন অধ্যায়!'), isTrue);
    expect(content.contains('প্রকৃতিকে জানা, বন্যপ্রাণী সংরক্ষণে অংশ নেওয়া এবং আনন্দের সঙ্গে শেখার অভিজ্ঞতাকে আরও সমৃদ্ধ করতে এসেছে eআরণ্যক 3.0।'), isTrue);
  });
}

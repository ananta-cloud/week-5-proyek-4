import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:logbook_app_001/features/models/log_model.dart';

void main() {
  test(
    'RBAC Security Check: Private logs should NOT be visible to teammates',
    () {
      String useraId = "user_A";
      String userbId = "user_B";

      // 1. Setup: Membuat data simulasi
      List<LogModel> allDatabaseLogs = [
        LogModel(
          title: "Log Rahasia",
          description: "Rahasia User A",
          date: DateTime.parse("2026-03-22"),
          authorId: useraId,
          teamId: "tim_1",
          isPublic: false,
        ),
        LogModel(
          title: "Log Umum",
          description: "Bisa dilihat siapa saja",
          date: DateTime.parse("2026-03-22"),
          authorId: useraId,
          teamId: "tim_1",
          isPublic: true,
        ),
      ];

      // 2. Action: Filter logic (User B hanya bisa melihat miliknya sendiri ATAU yang public)
      List<LogModel> userbViewablelogs = allDatabaseLogs.where((log) {
        return log.authorId == userbId || log.isPublic == true;
      }).toList();

      // 3. Assert (Validasi)
      expect(userbViewablelogs.length, 1); // Hasil harus 1
      expect(userbViewablelogs.first.title, "Log Umum");
      expect(
        userbViewablelogs.any((log) => log.title == "Log Rahasia"),
        isFalse,
      );
    },
  );
}

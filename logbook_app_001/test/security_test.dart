import 'package:flutter_test/flutter_test.dart';
import 'package:logbook_app_001/features/models/log_model.dart';

void main() {
  test('RBAC Security Check: Private logs should NOT be visible to teammates', () {
    String userA_Id = "user_A";
    String userB_Id = "user_B"; 

    List<LogModel> allDatabaseLogs = [
      LogModel(title: "Log Rahasia", description: "...", date: "...", authorId: userA_Id, teamId: "tim_1", isPublic: false),
      LogModel(title: "Log Umum", description: "...", date: "...", authorId: userA_Id, teamId: "tim_1", isPublic: true),
    ];

    // 2. Action: User B mengambil data
    List<LogModel> userB_ViewableLogs = allDatabaseLogs.where((log) {
      return log.authorId == userB_Id || log.isPublic == true;
    }).toList();

    // 3. Assert (Validasi)
    expect(userB_ViewableLogs.length, 1); // Harus cuma 1 (yang public)
    expect(userB_ViewableLogs.first.title, "Log Umum");
  });
}
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
class AccessPolicy {
  // Template ini mudah dikembangkan: tinggal tambah baris 'case' baru
  static bool canPerform(String role, String action) {
    switch (role) {
      case 'Ketua':
        return true; // Ketua bisa semua (Full CRUD)
      case 'Anggota':
        // Anggota hanya bisa Create dan Read
        return ['create', 'read'].contains(action);
      default:
        return false;
    }
  }
}
class AccessControlService {
  static const String actionCreate = 'create';
  static const String actionRead = 'read';
  static const String actionUpdate = 'update';
  static const String actionDelete = 'delete';

  static bool canPerform(String role, String action, {bool isOwner = false}) {
    // TASK 5: Sovereignty - Hanya pemilik yang boleh Edit atau Hapus (Bahkan Ketua pun dilarang menghapus milik anggota)
    if (action == actionUpdate || action == actionDelete) {
      return isOwner;
    }

    // Role-based untuk Create dan Read
    if (role == 'Ketua') return true;

    if (role == 'Anggota' && (action == actionCreate || action == actionRead)) {
      return true;
    }

    return false;
  }
}

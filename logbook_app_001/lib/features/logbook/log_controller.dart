import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId, where;
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
import 'package:logbook_app_001/services/access_control_services.dart' as access_control;
import 'package:logbook_app_001/helpers/log_helper.dart';

class LogController {
  // Notifier untuk UI
  final ValueNotifier<List<LogModel>> logsNotifier = ValueNotifier<List<LogModel>>([]);
  final ValueNotifier<List<LogModel>> filteredLogsNotifier = ValueNotifier<List<LogModel>>([]);

  // Akses Box Hive
  final Box<LogModel> _logBox = Hive.box<LogModel>('offline_logs');

  // Identitas User
  String userId = "";
  String userRole = "";
  String lastQuery = "";

  LogController() {
    // Memastikan setiap perubahan pada list utama akan otomatis mengupdate list filter
    logsNotifier.addListener(() => _applyFilter());
  }

  void searchLogs(String query) {
    lastQuery = query;
    _applyFilter();
  }

  void _applyFilter() {
    if (lastQuery.isEmpty) {
      filteredLogsNotifier.value = logsNotifier.value;
    } else {
      filteredLogsNotifier.value = logsNotifier.value
          .where(
            (log) =>
                log.title.toLowerCase().contains(lastQuery.toLowerCase()) ||
                log.description.toLowerCase().contains(lastQuery.toLowerCase()),
          )
          .toList();
    }
  }

  Future<void> syncLog(LogModel log) async {
    await _logBox.add(log); // Simpan lokal dulu
    try {
      await MongoService().insertLog(log); 
      await LogHelper.writeLog("Sync Success", source: "SyncManager");
    } catch (e) {
      await LogHelper.writeLog("Offline Mode: Data saved locally", level: 3);
    }
  }

  // --- CRUD OPERATIONS ---

  Future<void> loadLogs(String userTeamId) async {
    try {
      // 1. Ambil data mentah (List of Map) dari MongoDB
      final List<Map<String, dynamic>> data = await MongoService().db!
          .collection('logs')
          .find(where.eq('teamId', userTeamId))
          .toList();

      // 2. Ubah List<Map> menjadi List<LogModel>
      final List<LogModel> cloudLogs = data
          .map((json) => LogModel.fromJson(json))
          .toList();

      // 3. Update Notifier dan Hive
      logsNotifier.value = cloudLogs;

      await _logBox.clear();
      await _logBox.addAll(cloudLogs);

      _applyFilter();
      await LogHelper.writeLog(
        "SUCCESS: Memuat ${cloudLogs.length} data tim.",
        source: "log_controller.dart",
      );
    } catch (e) {
      // Jika offline, ambil dari Hive yang sudah difilter berdasarkan teamId
      logsNotifier.value = _logBox.values
          .where((log) => log.teamId == userTeamId)
          .toList();
      _applyFilter();
      await LogHelper.writeLog("OFFLINE: Memuat data lokal - $e", level: 2);
    }
  }

  /// ADD DATA
  Future<void> addLog(
    String title,
    String desc,
    String kategori, // PERBAIKAN: Kategori ditambahkan
    String authorId,
    String teamId,
  ) async {
    final newLog = LogModel(
      id: ObjectId(), 
      title: title,
      description: desc,
      date: DateTime.now(),
      authorId: authorId,
      teamId: teamId,
    );

    // ACTION 1: Simpan ke Hive (Instan)
    await _logBox.add(newLog);
    logsNotifier.value = [...logsNotifier.value, newLog];

    // ACTION 2: Kirim ke MongoDB Atlas (Background)
    try {
      await MongoService().insertLog(newLog);
      await LogHelper.writeLog(
        "SUCCESS: Data tersinkron ke Cloud",
        source: "log_controller.dart",
      );
    } catch (e) {
      await LogHelper.writeLog(
        "WARNING: Data tersimpan lokal, akan sinkron saat online",
        level: 1,
      );
    }
  }

  /// UPDATE DATA (PERBAIKAN: Gunakan LogModel lama, bukan index)
  Future<void> updateLog(
    LogModel oldLog,
    String newTitle,
    String newDesc,
    String tempKategori,
  ) async {
    final updatedLog = LogModel(
      id: oldLog.id,
      title: newTitle,
      description: newDesc,
      date: DateTime.now(),
      authorId: oldLog.authorId,
      teamId: oldLog.teamId,
    );

    try {
      // Update MongoDB
      await MongoService().updateLog(updatedLog);

      // Update Hive (Cari key secara akurat berdasarkan ID)
      final dynamic key = _logBox.keys.firstWhere(
        (k) => _logBox.get(k)?.id == oldLog.id,
        orElse: () => null,
      );

      if (key != null) {
        await _logBox.put(key, updatedLog);
        _updateLocalList();
      }
    } catch (e) {
      await LogHelper.writeLog("ERROR: Update Gagal - $e", level: 1);
    }
  }

  /// REMOVE DATA
  Future<void> removeLog(LogModel targetLog) async {
    // 1. Security Check
    bool isOwner = targetLog.authorId == userId;
    
    // PERBAIKAN: Pemanggilan AccessControl yang benar menggunakan Alias
    if (!access_control.AccessControlService.canPerform(
        userRole, access_control.AccessControlService.actionDelete, isOwner: isOwner)) {
      await LogHelper.writeLog("SECURITY: Unauthorized Delete", level: 1);
      return;
    }

    try {
      if (targetLog.id == null) throw Exception("ID Null");

      // 2. Hapus di Cloud
      await MongoService().deleteLog(targetLog.id!);

      // 3. Hapus di Hive
      final Map<dynamic, LogModel> map = _logBox.toMap();
      final dynamic keyToDelete = map.keys.firstWhere(
        (k) => map[k]?.id == targetLog.id,
        orElse: () => null,
      );

      if (keyToDelete != null) {
        await _logBox.delete(keyToDelete);
        _updateLocalList();
      }

      await LogHelper.writeLog("SUCCESS: Log dihapus", level: 2);
    } catch (e) {
      await LogHelper.writeLog("ERROR: Hapus Gagal - $e", level: 1);
    }
  }

  // --- PERSISTENCE ---

  void _updateLocalList() {
    logsNotifier.value = _logBox.values.toList();
  }

  Future<void> loadFromDisk(String userTeamId) async {
    try {
      _updateLocalList();
      final cloudData = await MongoService().getLogs(userTeamId);
      await _logBox.clear();
      await _logBox.addAll(cloudData);
      _updateLocalList();
    } catch (e) {
      await LogHelper.writeLog("INFO: Berjalan dalam mode Offline", level: 2);
    }
  }
}
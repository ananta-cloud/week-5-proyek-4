import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId, where;

// Pastikan import path sesuai dengan struktur folder proyek Anda
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
import 'package:logbook_app_001/services/access_control_services.dart';
import 'package:logbook_app_001/helpers/log_helper.dart';

class LogController {
  // Notifier untuk reaktivitas UI
  final ValueNotifier<List<LogModel>> logsNotifier = ValueNotifier<List<LogModel>>([]);
  final ValueNotifier<List<LogModel>> filteredLogsNotifier = ValueNotifier<List<LogModel>>([]);
  
  // Akses ke Hive Box untuk Local Persistence (Offline-First)
  final Box<LogModel> _logBox = Hive.box<LogModel>('offline_logs');

  // Identitas Pengguna & State Pencarian
  String currentUserId = "";
  String currentTeamId = "";
  String userRole = "";
  String lastQuery = "";

  LogController() {
    // Listener: Setiap ada perubahan data utama, otomatis jalankan filter
    logsNotifier.addListener(() => _applyFilters());
  }

  // ==========================================
  // FITUR PENCARIAN & PRIVASI (HOMEWORK & TASK 5)
  // ==========================================

  void searchLogs(String query) {
    lastQuery = query.toLowerCase();
    _applyFilters();
  }

  void _applyFilters() {
    // 1. FILTER VISIBILITAS PRIVASI (Sovereignty)
    // Tampilkan jika: User adalah pemilik catatan ATAU catatan di-set Public
    List<LogModel> visibleLogs = logsNotifier.value.where((log) {
      return log.authorId == currentUserId || log.isPublic == true;
    }).toList();

    // 2. FILTER PENCARIAN (Search bar)
    if (lastQuery.isNotEmpty) {
      visibleLogs = visibleLogs.where((log) => 
        log.title.toLowerCase().contains(lastQuery) || 
        log.description.toLowerCase().contains(lastQuery)
      ).toList();
    }

    // Update UI
    filteredLogsNotifier.value = visibleLogs;
  }

  // ==========================================
  // CRUD & SYNC MANAGER (TASK 2 & TASK 4)
  // ==========================================

  /// LOAD DATA: Optimistic Loading (Local First -> Cloud Background)
  Future<void> loadLogs(String teamId, String userId, String role) async {
    currentTeamId = teamId;
    currentUserId = userId;
    userRole = role;

    // 1. Tampilkan data lokal secepat mungkin
    final localData = _logBox.values.where((log) => log.teamId == teamId).toList();
    logsNotifier.value = localData;

    try {
      // 2. Cek apakah ada data lokal yang BELUM tersinkron (isSynced == false)
      final pendingLogs = localData.where((log) => !log.isSynced).toList();
      
      // 3. Jika ada, push ke Cloud DULU sebelum mengambil data baru
      if (pendingLogs.isNotEmpty) {
        await LogHelper.writeLog("Mencoba sinkronisasi ${pendingLogs.length} data tertunda...", level: 2);
        for (var log in pendingLogs) {
          try {
            // Buat salinan log dengan status isSynced = true
            final syncedLog = LogModel(
              id: log.id, title: log.title, description: log.description, 
              date: log.date, authorId: log.authorId, teamId: log.teamId, 
              category: log.category, isPublic: log.isPublic, isSynced: true
            );
            
            await MongoService().insertLog(syncedLog);
            
            // Update status di Hive lokal
            final key = _logBox.keys.firstWhere((k) => _logBox.get(k)?.id == log.id);
            await _logBox.put(key, syncedLog);
          } catch (e) {
            await LogHelper.writeLog("Gagal push data tertunda: $e", level: 1);
          }
        }
      }

      // 4. Setelah push selesai, baru tarik data terbaru dari Cloud
      final List<Map<String, dynamic>> data = await MongoService().db!
          .collection('logs').find(where.eq('teamId', teamId)).toList();

      final List<LogModel> cloudLogs = data.map((json) {
        var log = LogModel.fromMap(json);
        // Pastikan data dari cloud ditandai sebagai sudah sinkron
        return LogModel(
              id: log.id, title: log.title, description: log.description, 
              date: log.date, authorId: log.authorId, teamId: log.teamId, 
              category: log.category, isPublic: log.isPublic, isSynced: true
        );
      }).toList();

      // 5. Update Hive dengan data Cloud yang benar-benar sinkron
      await _logBox.clear();
      await _logBox.addAll(cloudLogs);
      logsNotifier.value = cloudLogs;
      
    } catch (e) {
      await LogHelper.writeLog("OFFLINE: Memuat data lokal - $e", level: 2);
    }
  }

  /// ADD DATA: Simpan ke Hive Instan, Upload ke Cloud di Background
  Future<void> addLog({
    required String title, required String description, 
    required String category, required bool isPublic,
  }) async {
    // Awalnya kita anggap belum sinkron
    var newLog = LogModel(
      id: ObjectId().oid, title: title, description: description,
      date: DateTime.now().toIso8601String(), authorId: currentUserId,
      teamId: currentTeamId, category: category, isPublic: isPublic,
      isSynced: false, // TANDAI BELUM SINKRON
    );

    // Simpan ke Hive Instan
    await _logBox.add(newLog);
    _updateLocalList();

    try {
      // Coba upload ke Cloud
      await MongoService().insertLog(newLog);
      
      // Jika berhasil, update status isSynced di Hive menjadi true
      final syncedLog = LogModel(
        id: newLog.id, title: newLog.title, description: newLog.description,
        date: newLog.date, authorId: newLog.authorId, teamId: newLog.teamId,
        category: newLog.category, isPublic: newLog.isPublic, isSynced: true
      );
      
      final key = _logBox.keys.firstWhere((k) => _logBox.get(k)?.id == newLog.id);
      await _logBox.put(key, syncedLog);
      _updateLocalList();
      
      await LogHelper.writeLog("SUCCESS: Data tersinkron ke Cloud");
    } catch (e) {
      await LogHelper.writeLog("WARNING: Offline, data antre untuk disinkron", level: 1);
    }
  }

  /// UPDATE DATA: Perbarui Hive dan Cloud
  Future<void> updateLog({
    required LogModel oldLog,
    required String newTitle,
    required String newDesc,
    required String newCategory,
    required bool newIsPublic,
  }) async {
    final updatedLog = LogModel(
      id: oldLog.id,
      title: newTitle,
      description: newDesc,
      date: DateTime.now().toIso8601String(),
      authorId: oldLog.authorId,
      teamId: oldLog.teamId,
      category: newCategory,
      isPublic: newIsPublic,
    );

    try {
      // 1. Update ke Cloud
      await MongoService().updateLog(updatedLog);

      // 2. Update ke Hive lokal
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

  /// REMOVE DATA: Hapus dari Hive dan Cloud dengan Gatekeeper Security
  Future<void> removeLog(LogModel targetLog) async {
    // 1. Security Check (Gatekeeper lapis kedua)
    bool isOwner = targetLog.authorId == currentUserId;
    
    if (!AccessControlService.canPerform(userRole, AccessControlService.actionDelete, isOwner: isOwner)) {
      await LogHelper.writeLog("SECURITY BREACH: Unauthorized Delete Attempt", level: 1);
      return;
    }

    try {
      if (targetLog.id == null) throw Exception("ID Null");

      // 2. Hapus di Cloud
      await MongoService().deleteLog(targetLog.id!);

      // 3. Hapus di Hive lokal
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

  // ==========================================
  // HELPER METHODS
  // ==========================================

  void _updateLocalList() {
    logsNotifier.value = _logBox.values.where((log) => log.teamId == currentTeamId).toList();
  }
}
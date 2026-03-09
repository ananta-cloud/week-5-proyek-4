import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId; // Spesifik import
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
import 'package:logbook_app_001/services/access_control_services.dart' as AccessControl;
import 'package:logbook_app_001/helpers/log_helper.dart';

class LogController {
  // Notifier untuk UI
  final ValueNotifier<List<LogModel>> logsNotifier = ValueNotifier<List<LogModel>>([]);
  final ValueNotifier<List<LogModel>> filteredLogsNotifier = ValueNotifier<List<LogModel>>([]);
  
  // Akses Box Hive (Gunakan nama yang sama dengan di main.dart)
  final Box<LogModel> _logBox = Hive.box<LogModel>('offline_logs');

  // Identitas User (Harus diisi saat login atau inisialisasi)
  String userId = "";
  String userRole = "";
  String lastQuery = "";

  LogController() {
    loadFromDisk();
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
          .where((log) =>
              log.title.toLowerCase().contains(lastQuery.toLowerCase()) ||
              log.description.toLowerCase().contains(lastQuery.toLowerCase()))
          .toList();
    }
  }

  // --- CRUD OPERATIONS ---

  Future<void> addLog(String title, String desc, String kategori, String authorId, String teamId) async {
    final newLog = LogModel(
      id: ObjectId(),
      title: title,
      description: desc,
      kategori: kategori,
      date: DateTime.now(),
      authorId: authorId,
      teamId: teamId,
    );

    try {
      // 1. Simpan Lokal Dulu (Hive) - Instant UI update
      await _logBox.add(newLog);
      _updateLocalList();

      // 2. Coba kirim ke Cloud
      await MongoService().insertLog(newLog);
      
      await LogHelper.writeLog("SUCCESS: Data tersimpan di Cloud & Lokal", source: "log_controller.dart");
    } catch (e) {
      await LogHelper.writeLog("OFFLINE: Tersimpan di lokal, gagal upload - $e", level: 3);
    }
  }

  Future<void> updateLog(int index, String newTitle, String newDesc, String tempKategori) async {
    final oldLog = logsNotifier.value[index];
    final updatedLog = LogModel(
      id: oldLog.id,
      title: newTitle,
      description: newDesc,
      kategori: tempKategori,
      date: DateTime.now(),
      authorId: oldLog.authorId,
      teamId: oldLog.teamId,
    );

    try {
      // Update MongoDB
      await MongoService().updateLog(updatedLog);

      // Update Hive (Cari key berdasarkan objek lama)
      final dynamic key = _logBox.keys.elementAt(index);
      await _logBox.put(key, updatedLog);
      
      _updateLocalList();
    } catch (e) {
      await LogHelper.writeLog("ERROR: Update Gagal - $e", level: 1);
    }
  }

  Future<void> removeLog(LogModel targetLog) async {
    // 1. Security Check
    bool isOwner = targetLog.authorId == userId; 
    if (!AccessControl.canDelete(userRole, isOwner: isOwner)) {
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

  // Helper untuk sinkronisasi Notifier dengan data di Hive
  void _updateLocalList() {
    logsNotifier.value = _logBox.values.toList();
  }

  Future<void> loadFromDisk() async {
    try {
      // 1. Selalu muat data lokal dulu agar UI cepat muncul
      _updateLocalList();

      // 2. Coba ambil data terbaru dari Cloud untuk refresh
      final cloudData = await MongoService().getLogs();
      
      // 3. Update Hive dengan data terbaru dari Cloud (Clear & Re-add)
      await _logBox.clear();
      await _logBox.addAll(cloudData);
      
      _updateLocalList();
    } catch (e) {
      await LogHelper.writeLog("INFO: Berjalan dalam mode Offline", level: 2);
    }
  }
}
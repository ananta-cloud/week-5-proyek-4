import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:logbook_app_001/helpers/log_helper.dart'; // Import LogHelper

class MongoService {
  static final MongoService _instance = MongoService._internal();
  factory MongoService() => _instance;
  MongoService._internal();

  Db? db;
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(false);
  
  // Definisi source untuk LogHelper
  static const String _source = "mongo_service.dart"; 

  Future<void> connect(String uri) async {
    if (db != null && db!.state == mongo.State.OPEN) {
      return;
    }
    
    try {
      db = await Db.create(uri);
      // PERBAIKAN: Pindahkan timeout ke sini agar dibatalkan secara bersih
      await db!.open().timeout(const Duration(seconds: 10)); 
      
      isOnline.value = true;
      await LogHelper.writeLog("DATABASE: Berhasil terhubung", source: _source, level: 2);
    } catch (e) {
      isOnline.value = false;
      db = null; // WAJIB: Reset ke null agar query tidak nyangkut menjadi Infinite Loop
      
      await LogHelper.writeLog("ERROR: Gagal terhubung - $e", source: _source, level: 1);
      throw Exception("Gagal terhubung ke MongoDB: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getLogs(String teamId) async {
    if (db == null || !db!.isConnected) {
      await LogHelper.writeLog("WARNING: Mencoba getLogs saat offline", source: _source, level: 1);
      throw Exception("Offline");
    }
    
    await LogHelper.writeLog("INFO: Mengambil data untuk Team: $teamId", source: _source, level: 3);
    return await db!
        .collection('logs')
        .find(where.eq('teamId', teamId))
        .toList();
  }

  Future<void> insertLog(LogModel log) async {
    if (db == null || !db!.isConnected) {
      await LogHelper.writeLog("WARNING: Mencoba insertLog saat offline", source: _source, level: 1);
      throw Exception("Offline");
    }
    
    await db!.collection('logs').insert(log.toMap());
    await LogHelper.writeLog("SUCCESS: Data baru ditambahkan ke Cloud", source: _source, level: 2);
  }

  Future<void> updateLog(LogModel log) async {
    if (db == null || !db!.isConnected || log.id == null) {
      await LogHelper.writeLog("ERROR: Update gagal (Offline atau ID Null)", source: _source, level: 1);
      throw Exception("Offline or Null ID");
    }
    
    await db!
        .collection('logs')
        .update(where.id(ObjectId.fromHexString(log.id!)), log.toMap());
    await LogHelper.writeLog("SUCCESS: Data berhasil diperbarui di Cloud", source: _source, level: 2);
  }

  Future<void> deleteLog(String id) async {
    if (db == null || !db!.isConnected) {
      await LogHelper.writeLog("ERROR: Hapus data gagal (Offline)", source: _source, level: 1);
      throw Exception("Offline");
    }
    
    await db!.collection('logs').remove(where.id(ObjectId.fromHexString(id)));
    await LogHelper.writeLog("SUCCESS: Data berhasil dihapus dari Cloud", source: _source, level: 2);
  }

  Future<void> close() async {
    if (db != null) {
      await db!.close();
      db = null;
      isOnline.value = false; // Pastikan state UI berubah menjadi merah (cloud_off)
      
      await LogHelper.writeLog(
        "DATABASE: Koneksi ditutup",
        source: _source,
        level: 2,
      );
    }
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logbook_app_001/features/logbook/log_controller.dart';
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:logbook_app_001/services/access_control_services.dart';
import 'package:logbook_app_001/features/logbook/log_editor_page.dart';
import 'package:logbook_app_001/features/auth/login_view.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
import 'package:logbook_app_001/services/hive_service.dart';
import 'package:logbook_app_001/features/widgets/search_log.dart';

class LogView extends StatefulWidget {
  final dynamic currentUser;

  const LogView({super.key, required this.currentUser});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late LogController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LogController();

    // Ambil data user dengan aman
    String teamId = widget.currentUser['teamId'] ?? "";
    String uid = widget.currentUser['uid'] ?? "";
    String role = widget.currentUser['role'] ?? "Anggota";

    _initDatabase(teamId, uid, role);

    // Listener untuk koneksi
    MongoService().isOnline.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    MongoService().isOnline.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initDatabase(String teamId, String uid, String role) async {
    try {
      final String? mongoUri = dotenv.env['MONGODB_URI'];
      if (mongoUri != null) {
        await MongoService().connect(mongoUri);
        // Jalankan sinkronisasi setelah terhubung ke cloud
        await HiveService.syncData();
      }
    } catch (e) {
      debugPrint("Koneksi cloud gagal: $e");
    } finally {
      // Selalu muat data lokal agar UI tidak kosong (Offline-First)
      await _controller.loadLogs(teamId, uid, role);
    }
  }

  void _confirmDelete(LogModel log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Logbook?"),
        content: const Text("Tindakan ini akan menghapus data secara permanen dari lokal dan cloud."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          TextButton(
            onPressed: () async {
              await _controller.removeLog(log);
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Log berhasil dihapus")),
              );
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _goToEditor({LogModel? log}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogEditorPage(
          log: log,
          controller: _controller,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Mechanical': return Colors.green.shade50;
      case 'Electronic': return Colors.blue.shade50;
      case 'Software': return Colors.purple.shade50;
      default: return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String role = widget.currentUser['role'] ?? 'Anggota';
    final String currentUid = widget.currentUser['uid'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text("Logbook: ${widget.currentUser['username']}"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.loadLogs(
              widget.currentUser['teamId'],
              currentUid,
              role,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: MongoService().isOnline,
            builder: (context, online, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                color: online ? Colors.green : Colors.red,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginView()),
              (route) => false,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SearchBarWidget(onSearch: (value) => _controller.searchLogs(value)),
          Expanded(
            child: ValueListenableBuilder<List<LogModel>>(
              valueListenable: _controller.filteredLogsNotifier,
              builder: (context, logs, child) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text("Belum ada aktivitas. Mulai catat sekarang!"),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final bool isOwner = log.authorId == currentUid;
                    final bool isPublic = log.isPublic;

                    return Card(
                      color: _getCategoryColor(log.category),
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: log.isSynced ? Colors.green : Colors.orange,
                          child: Icon(
                            log.isSynced ? Icons.check : Icons.upload,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          log.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(log.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                              "${isPublic ? "🌐 Publik" : "🔒 Privat"} • ${log.category}",
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // EDIT BUTTON
                            if (AccessControlService.canPerform(
                              role,
                              AccessControlService.actionUpdate,
                              isOwner: isOwner,
                              isPublic: isPublic,
                            ))
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _goToEditor(log: log),
                              ),

                            // DELETE BUTTON
                            if (AccessControlService.canPerform(
                              role,
                              AccessControlService.actionDelete,
                              isOwner: isOwner,
                              isPublic: isPublic,
                            ))
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmDelete(log),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _goToEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
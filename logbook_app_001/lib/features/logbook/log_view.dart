import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logbook_app_001/features/logbook/log_controller.dart';
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
import 'package:logbook_app_001/features/logbook/log_editor_page.dart';
import 'package:logbook_app_001/features/widgets/search_log.dart';
import 'package:logbook_app_001/services/access_policy.dart';
import 'package:logbook_app_001/services/access_control_services.dart';
import 'package:logbook_app_001/services/hive_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logbook_app_001/features/widgets/empty_log.dart';
import 'package:uuid/uuid.dart';
import 'package:logbook_app_001/features/auth/login_view.dart';

class LogView extends StatefulWidget {
  final dynamic currentUser;
  const LogView({super.key, required this.currentUser});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with SingleTickerProviderStateMixin {
  late LogController _controller;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _controller = LogController();

    // Konfigurasi animasi icon refresh
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _controller.isSyncingNotifier.addListener(() {
      if (_controller.isSyncingNotifier.value) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    });

    _initData();
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

  void _initData() async {
    final String teamId = widget.currentUser['teamId'] ?? "";
    final String uid = widget.currentUser['uid'] ?? "";
    final String role = widget.currentUser['role'] ?? "Anggota";

    final String? mongoUri = dotenv.env['MONGODB_URI'];
    if (mongoUri != null) await MongoService().connect(mongoUri);
    await _controller.loadLogs(teamId, uid, role);
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
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUid = widget.currentUser['uid'] ?? '';
    final String role = widget.currentUser['role'] ?? 'Anggota';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Logbook"),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _controller.isSyncingNotifier,
            builder: (context, syncing, _) {
              return RotationTransition(
                turns: _rotationController,
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: syncing
                      ? null
                      : () => _controller.loadLogs(
                          widget.currentUser['teamId'],
                          widget.currentUser['uid'],
                          widget.currentUser['role'],
                        ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginView()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Bar Status Reconnect
          ValueListenableBuilder<bool>(
            valueListenable: MongoService().isOnline,
            builder: (context, online, _) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: online ? 0 : 35, // Langsung menciut jika online
                width: double.infinity,
                color: online ? Colors.green : Colors.orange,
                child: Center(
                  child: Text(
                    online
                        ? "Koneksi Cloud Aktif"
                        : "⚠️ Mode Offline: Data disimpan di HP",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          SearchBarWidget(onSearch: (v) => _controller.searchLogs(v)),
          Expanded(
            child: ValueListenableBuilder<List<LogModel>>(
              valueListenable: _controller.filteredLogsNotifier,
              builder: (context, logs, _) {
                if (logs.isEmpty)
                  return EmptyLog(
                    isSearchMode: _controller.lastQuery.isNotEmpty,
                    searchQuery: _controller.lastQuery,
                  );
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final bool isOwner = log.authorId == currentUid;
                    final bool isPublic = log.isPublic;
                    return Card(
                      color: _getCategoryColor(log.category),
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: Icon(
                          log.isSynced ? Icons.cloud_done : Icons.cloud_upload,
                          color: log.isSynced ? Colors.green : Colors.orange,
                        ),
                        title: Text(log.title),
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
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
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
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
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
      floatingActionButton: (widget.currentUser['role'] == 'Ketua' || widget.currentUser['role'] == 'Anggota')
      ? FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LogEditorPage(
              controller: _controller,
              currentUser: widget.currentUser,
            ),
          ),
        ),
        child: const Icon(Icons.add),
      )
    : null, // Jika bukan Ketua/Anggota, tombol tidak akan muncul
    );
  }
}

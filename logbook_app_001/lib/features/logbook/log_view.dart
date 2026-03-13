import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logbook_app_001/features/logbook/log_controller.dart';
import 'package:logbook_app_001/features/models/log_model.dart';
import 'package:logbook_app_001/services/access_control_services.dart';
import 'package:logbook_app_001/features/logbook/log_editor_page.dart';
import 'package:logbook_app_001/features/auth/login_view.dart';
import 'package:logbook_app_001/services/mongo_service.dart';
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

    // Inisialisasi data berdasarkan pengguna yang login
    String teamId = widget.currentUser['teamId'] ?? "";
    String uid = widget.currentUser['uid'] ?? "";
    String role = widget.currentUser['role'] ?? "Anggota";

    _initDatabase(teamId, uid, role);

    // Listener untuk update ikon cloud secara real-time
    MongoService().isOnline.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initDatabase(String teamId, String uid, String role) async {
    try {
      final String? mongoUri = dotenv.env['MONGODB_URI'];
      if (mongoUri != null) {
        await MongoService().connect(mongoUri);
      }
    } catch (e) {
      print("Koneksi cloud gagal, beralih ke offline penuh");
    } finally {
      // Selalu muat data lokal (Offline-First)
      _controller.loadLogs(teamId, uid, role);
    }
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

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Mechanical':
        return Colors.green.shade100;
      case 'Electronic':
        return Colors.blue.shade100;
      case 'Software':
        return Colors.purple.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String role = widget.currentUser['role'] ?? 'Anggota';

    return Scaffold(
      appBar: AppBar(
        title: Text("Logbook: ${widget.currentUser['username']}"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.loadLogs(
              widget.currentUser['teamId'],
              widget.currentUser['uid'],
              role,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: MongoService().isOnline,
            builder: (context, online, _) => Icon(
              online ? Icons.cloud_done : Icons.cloud_off,
              color: online ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
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
                    child: Text(
                      "Belum ada aktivitas hari ini? Mulai catat kemajuan Anda!",
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final bool isOwner =
                        log.authorId == widget.currentUser['uid'];

                    return Card(
                      color: _getCategoryColor(log.category),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: Icon(
                          log.id != null
                              ? Icons.cloud_done
                              : Icons.cloud_upload_outlined,
                          color: log.id != null ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          log.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "${log.isPublic ? "🌐 Publik" : "🔒 Privat"} • ${log.category}",
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (AccessControlService.canPerform(
                              role,
                              'update',
                              isOwner: isOwner,
                            ))
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _goToEditor(log: log),
                              ),
                            if (AccessControlService.canPerform(
                              role,
                              'delete',
                              isOwner: isOwner,
                            ))
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _controller.removeLog(log),
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

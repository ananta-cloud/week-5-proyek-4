import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'log_controller.dart';
import '../models/log_model.dart';
import '../auth/login_view.dart';
import '../widgets/search_log.dart';
import '../widgets/empty_log.dart';
import 'log_editor_page.dart';
import '../../services/mongo_service.dart';
import '../../services/access_control_services.dart';
import '../../helpers/log_helper.dart';

class LogView extends StatefulWidget {
  final dynamic currentUser;

  const LogView({super.key, required this.currentUser});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late LogController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = LogController();
    
    // Sinkronisasi identitas user ke controller
    _controller.userId = widget.currentUser['uid'] ?? "";
    _controller.userRole = widget.currentUser['role'] ?? "Anggota";

    _initDatabase();

    // Listener status online untuk update ikon cloud di AppBar
    MongoService().isOnline.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    try {
      final String? mongoUri = dotenv.env['MONGODB_URI'];
      if (mongoUri == null) throw Exception("MONGODB_URI tidak ditemukan");

      // Pastikan koneksi cloud terjalin
      await MongoService().connect(mongoUri).timeout(
            const Duration(seconds: 15),
          );

      // Muat data dari Disk (Hive) lalu sinkron ke Cloud
      await _controller.loadFromDisk(widget.currentUser['teamId']);
    } catch (e) {
      await LogHelper.writeLog("UI: Init Error - $e", level: 1);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToEditor({LogModel? log, int? index}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogEditorPage(
          log: log,
          index: index,
          controller: _controller,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Logbook: ${widget.currentUser['username']}"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.loadFromDisk(widget.currentUser['teamId']),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: MongoService().isOnline,
            builder: (context, online, _) {
              return Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                color: online ? Colors.green : Colors.red,
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.logout), onPressed: _showLogoutConfirmation),
        ],
      ),
      body: Column(
        children: [
          // Widget pencarian tetap dipertahankan
          SearchBarWidget(onSearch: (value) => _controller.searchLogs(value)),
          
          Expanded(
            child: ValueListenableBuilder<List<LogModel>>(
              valueListenable: _controller.filteredLogsNotifier,
              builder: (context, logs, _) {
                if (_isLoading && logs.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (logs.isEmpty) {
                  return const EmptyLog(isSearchMode: false);
                }

                return RefreshIndicator(
                  onRefresh: () async => await _controller.loadFromDisk(widget.currentUser['teamId']),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final bool isOwner = log.authorId == widget.currentUser['uid'];
                      final String role = widget.currentUser['role'] ?? 'Anggota';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            log.id != null ? Icons.cloud_done : Icons.cloud_upload_outlined,
                            color: log.id != null ? Colors.green : Colors.orange,
                          ),
                          title: Text(log.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(log.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // GATEKEEPER: Tombol Edit
                              if (AccessControlService.canPerform(role, AccessControlService.actionUpdate, isOwner: isOwner))
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _goToEditor(log: log, index: index),
                                ),
                              
                              // GATEKEEPER: Tombol Delete
                              if (AccessControlService.canPerform(role, AccessControlService.actionDelete, isOwner: isOwner))
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _showDeleteConfirmation(log),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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

  // --- Dialog Helpers ---
  void _showDeleteConfirmation(LogModel log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Catatan"),
        content: const Text("Tindakan ini tidak dapat dibatalkan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              await _controller.removeLog(log);
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Apakah Anda yakin ingin keluar?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginView()),
              (route) => false,
            ),
            child: const Text("Keluar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
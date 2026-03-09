import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'log_controller.dart';
import '../onboarding/onboarding_view.dart';
import '../models/log_model.dart';
import '../auth/login_view.dart'; // Pastikan path ini benar
import '../widgets/search_log.dart';
import '../widgets/empty_log.dart';
import '../../helpers/log_helper.dart';
import 'package:intl/intl.dart';
import 'package:logbook_app_001/services/mongo_service.dart'; 
import 'package:logbook_app_001/services/access_control_services.dart' as AccessPolicy; 

class LogView extends StatefulWidget {
  // Gunakan data user yang konsisten dari Login
  final dynamic currentUser; 

  const LogView({super.key, required this.currentUser});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late LogController _controller;
  late Future<List<LogModel>> _logsFuture;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = LogController();
    
    // Sinkronkan ID dan Role ke Controller untuk pengecekan AccessPolicy
    _controller.userId = widget.currentUser['uid'] ?? "";
    _controller.userRole = widget.currentUser['role'] ?? "user";

    Future.microtask(() => _initDatabase());
    _refreshData();
    
    // Listener status online untuk update ikon cloud secara real-time
    MongoService().isOnline.addListener(() {
      if (mounted) setState(() {}); 
    });
  }

  void _refreshData() {
    setState(() {
      _logsFuture = MongoService().getLogs();
    });
  }

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    try {
      await LogHelper.writeLog("UI: Memulai inisialisasi...", source: "log_view.dart");

      final String? mongoUri = dotenv.env['MONGODB_URI'];
      if (mongoUri == null) throw Exception("MONGODB_URI tidak ditemukan di .env");

      await MongoService().connect(mongoUri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception("Koneksi Cloud Timeout."),
          );

      await LogHelper.writeLog("UI: Koneksi Berhasil.", source: "log_view.dart");
      await _controller.loadFromDisk();
    } catch (e) {
      await LogHelper.writeLog("UI: Error - $e", source: "log_view.dart", level: 1);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // DIALOG TAMBAH
  void _showAddLogDialog() {
    _titleController.clear();
    _contentController.clear();
    String tempKategori = "Kerja";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Tambah Catatan Baru"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _titleController, decoration: const InputDecoration(hintText: "Judul")),
              TextField(controller: _contentController, decoration: const InputDecoration(hintText: "Isi Deskripsi")),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: tempKategori,
                isExpanded: true,
                items: ["Kerja", "Pribadi", "Urgent"]
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (val) => setDialogState(() => tempKategori = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              onPressed: () async {
                if (_titleController.text.isNotEmpty) {
                  // Gunakan field 'uid' dan 'teamId' yang sesuai dengan objek currentUser
                  await _controller.addLog(
                    _titleController.text,
                    _contentController.text,
                    tempKategori,
                    widget.currentUser['uid'], 
                    widget.currentUser['teamId'],
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    _refreshData();
                  }
                }
              },
              child: const Text("Simpan"),
            ),
          ],
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
          ValueListenableBuilder<bool>(
            valueListenable: MongoService().isOnline,
            builder: (context, online, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  online ? Icons.cloud_done : Icons.cloud_off,
                  color: online ? Colors.green : Colors.red,
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _showLogoutConfirmation),
        ],
      ),
      body: Column(
        children: [
          SearchBarWidget(onSearch: (value) => _controller.searchLogs(value)),
          Expanded(
            child: FutureBuilder<List<LogModel>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                // Jika error atau data kosong, tampilkan empty state
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return const EmptyLog(isSearchMode: false);
                }

                final logs = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: () async => _refreshData(),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final bool isOwner = log.authorId == widget.currentUser['uid'];

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
                              // Tombol Delete dengan Gatekeeper AccessPolicy
                              if (AccessPolicy.canPerform(widget.currentUser['role'], 'delete', isOwner: isOwner))
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
        onPressed: _showAddLogDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDeleteConfirmation(LogModel log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Catatan"),
        content: const Text("Apakah Anda yakin ingin menghapus catatan ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              await _controller.removeLog(log);
              if (mounted) {
                Navigator.pop(context);
                _refreshData();
              }
            },
            child: const Text("Ya, Hapus", style: TextStyle(color: Colors.red)),
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
            child: const Text("Ya, Keluar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
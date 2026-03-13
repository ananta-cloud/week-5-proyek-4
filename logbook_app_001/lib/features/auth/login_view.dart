import 'package:flutter/material.dart';
import 'package:logbook_app_001/features/logbook/log_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _userController = TextEditingController();
  String _selectedRole = 'Anggota';

  void _login() {
    if (_userController.text.isEmpty) return;

    // Simulasi data pengguna (Biasanya ini didapat dari database)
    final currentUser = {
      'uid': _userController.text.toLowerCase().replaceAll(' ', '_'),
      'username': _userController.text,
      'role': _selectedRole,
      'teamId': 'MEKTRA_KLP_01', // Semua disimulasikan berada di tim yang sama
    };

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LogView(currentUser: currentUser)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login Simulator")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: "Nama Pengguna", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(labelText: "Peran", border: OutlineInputBorder()),
              items: ['Ketua', 'Anggota'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (val) => setState(() => _selectedRole = val!),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _login,
              child: const Text("Masuk ke Logbook"),
            )
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

class EmptyLog extends StatelessWidget {
  const EmptyLog({super.key, this.isSearchMode = false, this.searchQuery = ""});
  final bool isSearchMode;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              isSearchMode
                  ? "lib/assets/gif/empty_search.gif"
                  : "lib/assets/gif/empty_page.gif",
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 20),
            Text(
              isSearchMode
                  ? "Tidak ada hasil untuk '$searchQuery'"
                  : "Belum ada catatan",
              textAlign: TextAlign.center, // Membuat teks ke tengah
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8), // Jarak antar baris teks
            Text(
              isSearchMode
                  ? "Coba gunakan kata kunci lain atau pastikan ejaan benar."
                  : "Mulai buat catatan dengan menekan tombol tambah!",
              textAlign: TextAlign.center, // Membuat teks ke tengah
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

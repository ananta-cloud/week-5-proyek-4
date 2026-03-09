import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/models/log_model.dart';
import 'features/onboarding/onboarding_view.dart';

void main() async {
  // Wajib untuk operasi asinkron sebelum runApp
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load ENV
  await dotenv.load(fileName: ".env");

  // INISIALISASI HIVE
  await Hive.initFlutter();
  
  // Registrasi adapter agar Hive mengenali objek LogModel
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(LogModelAdapter());
  }

  // Buka box dengan nama 'offline_logs'
  await Hive.openBox<LogModel>('offline_logs');

  runApp(const MyApp());
}

TypeAdapter<LogModel> LogModelAdapter() {
  return LogModelAdapter();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logbook App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // PERBAIKAN: Menambahkan ColorScheme
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const OnboardingView(),
    );
  }
}
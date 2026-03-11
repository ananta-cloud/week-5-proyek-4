import 'package:mongo_dart/mongo_dart.dart';
import 'package:hive/hive.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;

part 'log_model.g.dart';

@HiveType(typeId: 0)
class LogModel {
  @HiveField(0)
  final ObjectId? id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String description;
  @HiveField(3)
  final DateTime date;
  @HiveField(4)
  final String authorId; // Contoh: "MEKTRA_KLP_01"
  @HiveField(5)
  final String teamId; // Contoh: "MEKTRA_KLP_01"

  factory LogModel.fromJson(Map<String, dynamic> json) {
    return LogModel(
      // Map JSON fields to your model properties, e.g.:
      id: json['id'],
      title: json['title'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      authorId: json['authorId'],
      teamId: json['teamId'],
      // Add other fields as needed
    );
  }

  LogModel({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.authorId,
    required this.teamId,
  });

  // Color get categoryColor {
  //   switch (kategori) {
  //     case 'Urgent':
  //       return Colors.red;
  //     case 'Kerja':
  //       return Colors.blue;
  //     case 'Pribadi':
  //       return Colors.green;
  //     default:
  //       return Colors.grey;
  //   }
  // }

  // Konversi Object ke Map (JSON) untuk disimpan
  Map<String, dynamic> toMap() {
    return {
      '_id': id ?? ObjectId(), // Pastikan selalu ada ID, buat baru jika null
      'title': title,
      'description': description,
      'date': date,
      'authorId': authorId,
      'teamId': teamId,
    };
  }

  // Untuk Tugas HOTS: Konversi Map (JSON) ke Object
  factory LogModel.fromMap(Map<String, dynamic> map) {
    return LogModel(
      id: map['_id'] is ObjectId
          ? map['_id']
          : ObjectId.fromHexString(map['_id']?.toString() ?? ''),
      title: map['title'],
      description: map['description'],
      date: map['date'] is DateTime
          ? map['date']
          : DateTime.parse(map['date'] ?? DateTime.now().toString()),
      authorId: map['authorId'] ?? 'unknown_user', // Cegah error null
      teamId: map['teamId'] ?? 'no_team',
    );
  }
}

class RecordingModel {
  final String name;
  final String path;
  final DateTime date;
  final String transcription;
  final double confidence;
  final double? latitude;
  final double? longitude;
  final bool pinned; // Added pinned flag

  RecordingModel({
    required this.name,
    required this.path,
    required this.date,
    this.transcription = '',
    this.confidence = 1.0,
    this.latitude,
    this.longitude,
    this.pinned = false, // Default to false
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'date': date.toIso8601String(),
      'transcription': transcription,
      'confidence': confidence,
      'latitude': latitude,
      'longitude': longitude,
      'pinned': pinned, // Include in JSON
    };
  }

  factory RecordingModel.fromJson(Map<String, dynamic> json) {
    return RecordingModel(
      name: json['name'],
      path: json['path'],
      date: DateTime.parse(json['date']),
      transcription: json['transcription'] ?? '',
      confidence: json['confidence'] ?? 1.0,
      latitude: json['latitude'],
      longitude: json['longitude'],
      pinned: json['pinned'] ?? false, // Parse from JSON
    );
  }
  
  // Add method to create a copy with modified values
  RecordingModel copyWith({
    String? name,
    String? path,
    DateTime? date,
    String? transcription,
    double? confidence,
    double? latitude,
    double? longitude,
    bool? pinned,
  }) {
    return RecordingModel(
      name: name ?? this.name,
      path: path ?? this.path,
      date: date ?? this.date,
      transcription: transcription ?? this.transcription,
      confidence: confidence ?? this.confidence,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pinned: pinned ?? this.pinned,
    );
  }
}
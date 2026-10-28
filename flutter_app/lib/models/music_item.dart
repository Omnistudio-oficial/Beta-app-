class MusicItem {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final String coverUrl;
  final String? audioPath;
  final bool isRecording;

  const MusicItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.coverUrl = '',
    this.audioPath,
    this.isRecording = false,
  });
}

class AudioProject {
  final String id;
  final String title;
  final String ownerUid;
  final String sourceTrack;
  final int createdAt;

  const AudioProject({required this.id, required this.title, required this.ownerUid, required this.sourceTrack, required this.createdAt});

  factory AudioProject.fromSnapshot(String id, String ownerUid, Map<Object?, Object?> value) => AudioProject(
    id: id, ownerUid: ownerUid, title: value['title']?.toString() ?? 'Untitled',
    sourceTrack: value['sourceTrack']?.toString() ?? '', createdAt: (value['createdAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object> toJson() => {
    'ownerUid': ownerUid, 'title': title, 'sourceTrack': sourceTrack, 'createdAt': createdAt,
  };
}

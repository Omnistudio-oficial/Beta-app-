class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    this.photoUrl,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: data['phone'] as String?,
      photoUrl: data['photoUrl'] as String?,
      createdAt: data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'].toString())
          : null,
    );
  }

  UserProfile copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    DateTime? createdAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

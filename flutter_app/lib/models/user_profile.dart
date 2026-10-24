import 'package:flutter/material.dart';

class UserProfile {
  final String uid;
  final String name;
  final String email;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
      };
}

/// User profile model returned by `POST /users` and `GET /auth/profile`.
class UserModel {
  final int id;
  final String email;
  final String name;
  final String role;
  final String avatar;

  const UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.avatar,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _asInt(json['id']),
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      avatar: (json['avatar'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'avatar': avatar,
    };
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }
}

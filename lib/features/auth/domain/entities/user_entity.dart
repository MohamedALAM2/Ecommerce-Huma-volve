/// Authenticated user as the application understands it.
///
/// Pure Dart: no JSON, no Dio, no Flutter. Data models map to this type at
/// the Data/Domain boundary.
class UserEntity {
  final int id;
  final String email;
  final String name;
  final String role;
  final String avatar;

  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.avatar,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UserEntity &&
            other.id == id &&
            other.email == email &&
            other.name == name &&
            other.role == role &&
            other.avatar == avatar);
  }

  @override
  int get hashCode => Object.hash(id, email, name, role, avatar);

  @override
  String toString() => 'UserEntity(id: $id, email: $email, name: $name)';
}

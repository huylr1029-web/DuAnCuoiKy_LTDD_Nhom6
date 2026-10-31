class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final bool online;
  final DateTime? lastSeen;
  final String avatarUrl;

  const AppUser({
    required this.uid,
    required this.name,
    this.email = '',
    this.phone,
    this.online = false,
    this.lastSeen,
    this.avatarUrl = '',
  });

  /// JSON tu backend: UserDto {uid, name, email, phone, online, lastSeen}.
  /// Backend tra camelCase (uid, lastSeen...), nen doc dung ten do.
  factory AppUser.fromJson(Map<String, dynamic> m) => AppUser(
        uid: (m['uid'] ?? m['id'] ?? '').toString(),
        name: (m['name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        phone: m['phone'] as String?,
        online: (m['online'] as bool?) ?? false,
        lastSeen: m['lastSeen'] == null
            ? null
            : DateTime.tryParse(m['lastSeen'].toString()),
        avatarUrl: (m['avatarUrl'] ?? '').toString(),
      );

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser.fromJson(m);
}

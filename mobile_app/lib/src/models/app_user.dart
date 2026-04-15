class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.name,
  });

  final String id;
  final String username;
  final String role;
  final String name;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role,
      'name': name,
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
  });

  final String token;
  final AppUser user;

  factory AuthSession.fromLoginResponse(Map<String, dynamic> json) {
    final rawUser = json['user'];
    if (rawUser is! Map) {
      throw const FormatException('Invalid user payload in login response');
    }
    return AuthSession(
      token: json['token']?.toString() ?? '',
      user: AppUser.fromJson(Map<String, dynamic>.from(rawUser)),
    );
  }
}

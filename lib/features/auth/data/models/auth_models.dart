/// Tokens returned by `POST /auth/login` and `POST /auth/refresh-token`.
class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final access = (json['access_token'] ?? json['accessToken'] ?? '')
        .toString();
    final refresh = (json['refresh_token'] ?? json['refreshToken'] ?? '')
        .toString();
    if (access.isEmpty || refresh.isEmpty) {
      throw const FormatException('Missing auth tokens in response');
    }
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  Map<String, dynamic> toJson() {
    return {'access_token': accessToken, 'refresh_token': refreshToken};
  }
}

/// Payload for `POST /users`.
class SignUpRequest {
  final String name;
  final String email;
  final String password;
  final String role;
  final String avatar;

  const SignUpRequest({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.avatar,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'avatar': avatar,
    };
  }
}

/// Payload for `POST /auth/login`.
class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}

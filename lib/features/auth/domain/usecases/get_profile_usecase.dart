import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Retrieves the authenticated user's profile for a valid access token.
class GetProfileUseCase {
  final AuthRepository _repository;

  const GetProfileUseCase(this._repository);

  Future<UserEntity> call(String accessToken) {
    return _repository.getProfile(accessToken);
  }
}

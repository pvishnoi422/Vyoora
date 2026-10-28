import 'domain.dart';

enum TryOnState { queued, running, succeeded, failed, cancelled }

class TryOnJob {
  final String id, ownerId, garmentId, referenceId;
  final TryOnState state;
  final DateTime createdAt, expiresAt;
  final String? errorCode;
  const TryOnJob({
    required this.id,
    required this.ownerId,
    required this.garmentId,
    required this.referenceId,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
    this.errorCode,
  });
  bool get active => state == TryOnState.queued || state == TryOnState.running;
  bool get expired => !DateTime.now().toUtc().isBefore(expiresAt);
  factory TryOnJob.fromJson(Map<String, dynamic> json) {
    final state = enumValue(TryOnState.values, json['status']);
    if (state == TryOnState.succeeded && json['aiGenerated'] != true) {
      throw const FormatException('Unverified generated preview');
    }
    return TryOnJob(
      id: checkedId(requiredText(json, 'id'), 'id'),
      ownerId: checkedId(requiredText(json, 'ownerId'), 'ownerId'),
      garmentId: checkedId(requiredText(json, 'garmentId'), 'garmentId'),
      referenceId: checkedId(requiredText(json, 'referenceId'), 'referenceId'),
      state: state,
      createdAt: dateField(json, 'createdAt'),
      expiresAt: dateField(json, 'expiresAt'),
      errorCode: json['errorCode'] as String?,
    );
  }
  String get failureMessage => switch (errorCode) {
    'generation_blocked' =>
      'These photos could not be used. Try different photos.',
    'reference_expired' || 'not_found' =>
      'A selected photo is no longer available. Choose a new photo.',
    'tryon_disabled' =>
      'Try-on testing was paused before this request could finish.',
    'provider_access_denied' =>
      'The try-on provider is unavailable for this test environment.',
    'generation_expired' || 'generation_interrupted' =>
      'This generation could not finish. It will not restart automatically.',
    _ => 'The preview could not be generated. You can choose to try again.',
  };
}

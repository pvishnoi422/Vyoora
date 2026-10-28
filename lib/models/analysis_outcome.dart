/// A result is usable only after the server explicitly confirms completion.
/// Legacy saved payloads are unverified, never an implicit successful scan.
class AnalysisOutcome {
  final bool isSuccess;
  final String message;
  const AnalysisOutcome._(this.isSuccess, this.message);

  factory AnalysisOutcome.fromJson(Map<String, dynamic> data) {
    const unavailable = AnalysisOutcome._(
      false,
      'Analysis could not be completed. No ingredient assessment is available. Please try again.',
    );
    if (data['status'] != 'success' || data['analysis_complete'] != true) {
      return unavailable;
    }
    final count = data['ingredient_count'];
    final ingredients = data['all_ingredients'];
    final concerns = data['concerns'];
    final summary = data['summary'];
    final score = data['smart_score'];
    if (count is! int ||
        count <= 0 ||
        count > 200 ||
        ingredients is! List ||
        ingredients.length != count ||
        ingredients.any((e) => e is! String || e.trim().isEmpty) ||
        concerns is! List ||
        concerns.length > 200 ||
        summary is! String ||
        summary.trim().isEmpty ||
        score is! int ||
        score < 0 ||
        score > 100) {
      return unavailable;
    }
    for (final concern in concerns) {
      if (concern is! Map ||
          concern['ingredient'] is! String ||
          (concern['ingredient'] as String).trim().isEmpty ||
          concern['reason'] is! String ||
          (concern['reason'] as String).trim().isEmpty) {
        return unavailable;
      }
      if (concern['links'] != null &&
          (concern['links'] is! List ||
              (concern['links'] as List).any(
                (link) =>
                    link is! Map ||
                    link['source'] is! String ||
                    link['url'] is! String,
              ))) {
        return unavailable;
      }
    }
    for (final key in [
      'brand',
      'product_name',
      'product_type',
      'product_type_detail',
      'formula_type',
      'score_label',
      'confidence',
    ]) {
      if (data[key] != null && data[key] is! String) return unavailable;
    }
    for (final key in ['score_rationale', 'skin_compatibility']) {
      if (data[key] != null && data[key] is! Map<String, dynamic>)
        return unavailable;
    }
    for (final entry in {
      'score_rationale': ['positives', 'negatives'],
      'skin_compatibility': ['best_for', 'use_caution', 'less_ideal_for'],
    }.entries) {
      final object = data[entry.key] as Map<String, dynamic>?;
      if (object == null) continue;
      for (final key in entry.value) {
        final value = object[key];
        if (value != null &&
            (value is! List || value.any((e) => e is! String))) {
          return unavailable;
        }
      }
    }
    final evidence =
        (data['score_rationale']
            as Map<String, dynamic>?)?['evidence_confidence'];
    if (evidence != null && evidence is! String) return unavailable;
    for (final concern in concerns) {
      if (concern['ingredient_position'] != null &&
          concern['ingredient_position'] is! int)
        return unavailable;
    }
    if (data['who_should_avoid'] != null && data['who_should_avoid'] is! List) {
      return unavailable;
    }
    return const AnalysisOutcome._(true, 'Analysis completed.');
  }
}

String analysisRequestError(int statusCode, Map<String, dynamic> data) {
  switch (data['code']) {
    case 'no_ingredients':
      return "We couldn't read an ingredient list. Try a clearer photo of the full label.";
    case 'rate_limited':
      return 'Too many requests. Please wait and try again.';
    case 'budget_exhausted':
      return 'Analysis is paused because its usage limit was reached. Please try again later.';
    case 'invalid_image':
    case 'image_too_large':
      return 'Choose a valid JPEG, PNG, or WebP image smaller than 5 MB.';
    default:
      return 'Analysis could not be completed. No ingredient assessment is available. Please try again.';
  }
}

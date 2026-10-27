// Override for staging with --dart-define=API_BASE_URL=...
const String apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://vyoora-backend-622371052799.us-central1.run.app',
);

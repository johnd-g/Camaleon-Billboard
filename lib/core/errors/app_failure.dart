/// Maps raw exceptions to short, user-facing messages.
///
/// This app never alters DB schema (no ADD COLUMN). If POS columns are missing,
/// we tell the user to update POS instead of migrating from here.
class AppFailure {
  AppFailure._();

  static String message(Object error, {String? fallback}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (lower.contains('unknown column') ||
        (lower.contains('doesn\'t have a default value') &&
            lower.contains('bb_arrangement'))) {
      return 'This MySQL is missing newer bb_arrangement columns '
          '(content_type, media_*, borders, …). '
          'Update Camaleon POS so it can add them.';
    }

    if (lower.contains('access denied') ||
        lower.contains('1045') ||
        lower.contains('auth')) {
      return 'Could not sign in to MySQL. Check user and password.';
    }

    if (lower.contains('unknown database') || lower.contains('1049')) {
      return 'Database not found. Check the database name.';
    }

    if (lower.contains('unknown host') ||
        lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('timed out') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup') ||
        lower.contains('no route to host')) {
      return 'Cannot reach MySQL. Check host, port, and network.';
    }

    if (lower.contains('mysql is not connected') ||
        lower.contains('not connected')) {
      return 'Not connected to MySQL. Open connection settings.';
    }

    if (lower.contains('packets out of order') ||
        lower.contains('gone away') ||
        lower.contains('broken pipe')) {
      return 'MySQL connection dropped. Try reconnecting.';
    }

    // Prefer a clean first line when possible.
    final firstLine = raw.split('\n').first.trim();
    if (firstLine.isEmpty) {
      return fallback ?? 'Something went wrong.';
    }
    if (firstLine.length > 220) {
      return '${firstLine.substring(0, 217)}…';
    }
    return firstLine;
  }
}

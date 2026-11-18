import 'package:flutter/widgets.dart';

final _openingNavigation = Expando<bool>('bird_navigation_in_progress');

/// Owns one navigation intent per source route, from before any asynchronous
/// reads until the destination is dismissed. Descendant routes have their own
/// ownership, so their controls remain usable. Failures always release it.
Future<T?> guardBirdNavigation<T>(BuildContext context, Future<T?> Function() open) async {
  if (!context.mounted) return null;
  final route = ModalRoute.of(context);
  if (route?.isCurrent == false) return null;
  final owner = route ?? Navigator.of(context);
  if (_openingNavigation[owner] == true) return null;
  _openingNavigation[owner] = true;
  try {
    return await open();
  } finally {
    _openingNavigation[owner] = false;
  }
}

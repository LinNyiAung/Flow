import 'package:flutter/material.dart';

/// Maps a category or budget name to a representative icon. Covers the
/// app's real main categories (see `backend/database.py`) plus a couple of
/// common budget-name variants; anything unrecognised falls back to a
/// generic category glyph rather than guessing.
IconData iconForCategoryName(String name) {
  final n = name.toLowerCase();

  // Outflow main categories
  if (n.contains('food') || n.contains('daily living') || n.contains('grocer')) {
    return Icons.restaurant_rounded;
  }
  if (n.contains('housing') || n.contains('utilit') || n.contains('rent')) {
    return Icons.home_rounded;
  }
  if (n.contains('transport') || n.contains('fuel') || n.contains('taxi') || n.contains('vehicle')) {
    return Icons.directions_bus_rounded;
  }
  if (n.contains('shopping') || n.contains('lifestyle') || n.contains('cloth')) {
    return Icons.shopping_bag_rounded;
  }
  if (n.contains('entertainment') || n.contains('leisure') || n.contains('movie') || n.contains('game')) {
    return Icons.movie_rounded;
  }
  if (n.contains('health') || n.contains('insurance') || n.contains('doctor') || n.contains('fitness')) {
    return Icons.favorite_rounded;
  }
  if (n.contains('education') || n.contains('self-improvement') || n.contains('learning')) {
    return Icons.school_rounded;
  }
  if (n.contains('travel') || n.contains('vacation')) {
    return Icons.flight_rounded;
  }
  if (n.contains('financial') && n.contains('expense')) {
    return Icons.account_balance_rounded;
  }
  if (n.contains('business')) {
    return Icons.work_rounded;
  }

  // Inflow main categories
  if (n.contains('employment') || n.contains('salary')) {
    return Icons.work_rounded;
  }
  if (n.contains('investment') || n.contains('dividend') || n.contains('interest')) {
    return Icons.trending_up_rounded;
  }
  if (n.contains('gift') || n.contains('support')) {
    return Icons.card_giftcard_rounded;
  }
  if (n.contains('refund') || n.contains('reimburse')) {
    return Icons.replay_rounded;
  }

  return Icons.category_rounded;
}

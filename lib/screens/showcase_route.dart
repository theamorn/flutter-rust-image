import 'package:flutter/material.dart';

/// Shared route transition for the showcase flow: the incoming page fades in
/// while rising and settling to full scale; the outgoing page recedes
/// slightly. Used for Solar → Dashboard → Camera.
Route<T> buildShowcaseRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 600),
    reverseTransitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final incoming = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final recede = Tween(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOut),
      );
      return ScaleTransition(
        scale: recede,
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(incoming),
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(incoming),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

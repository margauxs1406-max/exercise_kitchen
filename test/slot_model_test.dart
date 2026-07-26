import 'package:flutter_test/flutter_test.dart';
import 'package:exercise_kitchen/models/slot_model.dart';

/// Test unitaire simple, sans dépendance à Firebase (qui nécessite une
/// configuration réelle) — vérifie la logique d'alerte utilisée par
/// `SlotCard` et l'écran coach (section 1.3bis : créneau vide ou à un seul
/// inscrit).
void main() {
  SlotModel buildSlot({required int registeredCount, int capacity = 12}) {
    return SlotModel(
      id: 's1',
      courseId: 'c1',
      courseTitle: 'Functional Pattern',
      type: 'collective',
      date: DateTime(2026, 7, 13),
      startTime: '18:00',
      endTime: '19:00',
      capacity: capacity,
      registeredCount: registeredCount,
      waitlistCount: 0,
    );
  }

  test('un créneau à 0 inscrit est signalé comme vide', () {
    final slot = buildSlot(registeredCount: 0);
    expect(slot.isEmpty, isTrue);
    expect(slot.hasOnlyOneRegistered, isFalse);
    expect(slot.isFull, isFalse);
  });

  test('un créneau à 1 inscrit déclenche l\'alerte (à annuler d\'après la spec)', () {
    final slot = buildSlot(registeredCount: 1);
    expect(slot.hasOnlyOneRegistered, isTrue);
    expect(slot.isEmpty, isFalse);
  });

  test('un créneau plein n\'accepte plus d\'inscription directe', () {
    final slot = buildSlot(registeredCount: 12, capacity: 12);
    expect(slot.isFull, isTrue);
  });
}

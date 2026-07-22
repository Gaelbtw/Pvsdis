// Pruebas de GuidGenerator (puro, sin Flutter): formato RFC 4122 v4 y
// unicidad práctica entre llamadas sucesivas.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/guid_generator.dart';

void main() {
  final formato = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('genera un GUID con el formato v4 esperado (versión y variante correctas)', () {
    for (var i = 0; i < 200; i++) {
      final guid = GuidGenerator.nuevo();
      expect(guid, matches(formato), reason: 'GUID inválido: $guid');
    }
  });

  test('dos llamadas sucesivas no producen el mismo GUID', () {
    final generados = List.generate(1000, (_) => GuidGenerator.nuevo());
    expect(generados.toSet(), hasLength(1000));
  });
}

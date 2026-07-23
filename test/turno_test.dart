// AppConfig.turnoPara: clasifica una hora en Matutino/Vespertino según los
// horarios configurados. Sin BD: AppConfig.actual cae a Configuracion.porDefecto
// (matutino 07:00-14:00, vespertino 14:00-21:00).
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/core/config/app_config.dart';

DateTime _hora(int h, int m) => DateTime(2026, 1, 1, h, m);

void main() {
  test('dentro del matutino', () {
    expect(AppConfig.turnoPara(_hora(7, 0)), 'Matutino');
    expect(AppConfig.turnoPara(_hora(10, 30)), 'Matutino');
    expect(AppConfig.turnoPara(_hora(13, 59)), 'Matutino');
  });

  test('el minuto de traslape (14:00) cuenta como Vespertino, no doble', () {
    expect(AppConfig.turnoPara(_hora(14, 0)), 'Vespertino');
  });

  test('dentro del vespertino', () {
    expect(AppConfig.turnoPara(_hora(18, 0)), 'Vespertino');
    expect(AppConfig.turnoPara(_hora(20, 59)), 'Vespertino');
  });

  test('fuera de ambos turnos devuelve null', () {
    expect(AppConfig.turnoPara(_hora(6, 0)), isNull);
    expect(AppConfig.turnoPara(_hora(21, 0)), isNull);
    expect(AppConfig.turnoPara(_hora(23, 30)), isNull);
  });

  test('turnoDeIso parsea la fecha y clasifica; null si no parsea', () {
    expect(AppConfig.turnoDeIso('2026-01-01T09:00:00'), 'Matutino');
    expect(AppConfig.turnoDeIso('2026-01-01T19:00:00'), 'Vespertino');
    expect(AppConfig.turnoDeIso('basura'), isNull);
    expect(AppConfig.turnoDeIso(null), isNull);
  });
}

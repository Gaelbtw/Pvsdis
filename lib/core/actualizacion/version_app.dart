/// Número de versión con orden comparable (`MAYOR.MENOR.PARCHE`).
///
/// Existe porque comparar versiones como texto es una trampa clásica:
/// `'1.10.0' < '1.9.0'` es cierto alfabéticamente y falso en la realidad. Con
/// diez clientes en versiones distintas, ese error significa avisarle a alguien
/// que "actualice" a una versión más vieja que la suya.
class VersionApp implements Comparable<VersionApp> {
  const VersionApp(this.mayor, this.menor, this.parche);

  final int mayor;
  final int menor;
  final int parche;

  /// Acepta `1.2.3`, `v1.2.3`, `1.2.3+45` y espacios sobrantes. Devuelve
  /// `null` si no se puede leer, en vez de adivinar: un manifiesto con la
  /// versión mal escrita debe ignorarse, no interpretarse a medias.
  ///
  /// El `+build` se descarta a propósito. Es un dato interno para distinguir
  /// dos instaladores con la misma versión pública; usarlo para decidir si hay
  /// actualización avisaría por recompilaciones que al cliente no le cambian
  /// nada.
  static VersionApp? parsear(String? texto) {
    if (texto == null) return null;

    final limpio = texto.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    final sinBuild = limpio.split('+').first;

    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(sinBuild);
    if (m == null) return null;

    return VersionApp(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(VersionApp otra) {
    if (mayor != otra.mayor) return mayor.compareTo(otra.mayor);
    if (menor != otra.menor) return menor.compareTo(otra.menor);
    return parche.compareTo(otra.parche);
  }

  bool esMasNuevaQue(VersionApp otra) => compareTo(otra) > 0;

  /// `true` si esta versión cambia MAYOR o MENOR respecto a [otra].
  ///
  /// Por la regla del proyecto, toda migración de esquema obliga a subir al
  /// menos MENOR (ver README). Así que un salto de MENOR o MAYOR significa,
  /// en la práctica, "esta actualización va a tocar la base de datos" — y eso
  /// cambia el aviso que se le da al cliente.
  bool cambiaEsquemaRespectoA(VersionApp otra) =>
      mayor != otra.mayor || menor != otra.menor;

  @override
  String toString() => '$mayor.$menor.$parche';

  @override
  bool operator ==(Object other) =>
      other is VersionApp &&
      other.mayor == mayor &&
      other.menor == menor &&
      other.parche == parche;

  @override
  int get hashCode => Object.hash(mayor, menor, parche);
}

/// Redondea un monto a centavos. Se usa en cada paso intermedio de un
/// cálculo financiero (nunca solo al final) para que el error de punto
/// flotante de `double` no se vaya acumulando entre sumas sucesivas — la
/// misma garantía práctica que buscaría `Decimal`, sin cambiar el tipo de
/// las columnas `REAL` ya usadas en toda la base de datos.
double redondearMoneda(double valor) => (valor * 100).round() / 100;

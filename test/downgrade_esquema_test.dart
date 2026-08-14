// Protección contra instalar una versión ANTERIOR encima de una al día.
//
// El escenario no es teórico: los instaladores se reparten a mano (USB y
// WhatsApp), así que la copia vieja se queda para siempre en el escritorio del
// cliente. Tarde o temprano alguien la ejecuta.
//
// `sqflite` no sabe bajar de versión —no hay `_onDowngrade` que deshaga las
// migraciones—, así que sin este chequeo el código viejo abre la base nueva y
// lee columnas que en su esquema no existen. La prueba verifica que la
// apertura se aborta ANTES de tocar el archivo, y que los datos siguen ahí.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/database/db_exceptions.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;
  Database? abierta;

  Future<Database> abrir() async {
    abierta = await DatabaseHelper().abrirEnRuta(path);
    return abierta!;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_downgrade');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rechaza una base creada por una versión más reciente', () async {
    // 1. Base al día, con un dato reconocible.
    var db = await abrir();
    final idCategoria = await db.insert('Categorias', {'nombre': 'Abarrotes'});
    await db.insert('Producto', {
      'nombre': 'Arroz 1kg',
      'descripcion': 'bolsa',
      'precio': 32.0,
      'estado': 'Activo',
      'id_categoria': idCategoria,
    });

    // 2. Simula que una versión futura ya migró este archivo.
    final futura = DatabaseHelper.versionEsquema + 5;
    await db.execute('PRAGMA user_version = $futura');
    await db.close();
    abierta = null;

    // 3. Abrir con ESTA versión debe abortar, no migrar ni escribir.
    await expectLater(
      abrir(),
      throwsA(
        isA<BaseDeDatosMasNuevaException>()
            .having((e) => e.versionArchivo, 'versionArchivo', futura)
            .having((e) => e.versionApp, 'versionApp',
                DatabaseHelper.versionEsquema),
      ),
    );
    abierta = null;

    // 4. El archivo quedó intacto: misma versión y el producto sigue ahí.
    //    Esto es lo que de verdad importa — el mensaje de error se puede
    //    mejorar después, los datos del negocio no se recuperan.
    final crudo = await databaseFactory.openDatabase(path);
    expect(await crudo.getVersion(), futura);
    final productos = await crudo.query('Producto');
    expect(productos.single['nombre'], 'Arroz 1kg');
    await crudo.close();
  });

  test('el mensaje al usuario no es un error técnico', () async {
    const e = BaseDeDatosMasNuevaException(
      versionArchivo: 30,
      versionApp: 24,
      rutaArchivo: r'C:\datos\pos.db',
    );

    // Nada de jerga ni de rutas en el texto que ve el dueño del negocio: eso
    // va en el bloque de detalle técnico, aparte.
    final mensaje = e.mensajeParaElUsuario.toLowerCase();
    expect(mensaje, isNot(contains('exception')));
    expect(mensaje, isNot(contains('esquema')));
    expect(mensaje, isNot(contains('pragma')));
    // Y sí dice qué hacer y que los datos están bien.
    expect(mensaje, contains('versión más reciente'));
    expect(mensaje, contains('intact'));
  });

  test('una base en la misma versión abre normal', () async {
    var db = await abrir();
    await db.insert('Categorias', {'nombre': 'Bebidas'});
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
    await db.close();
    abierta = null;

    db = await abrir();
    expect((await db.query('Categorias')).single['nombre'], 'Bebidas');
  });

  test('una base más vieja sí migra (no se confunde con un downgrade)', () async {
    var db = await abrir();
    await db.insert('Categorias', {'nombre': 'Limpieza'});
    // Marcarla una versión atrás basta para disparar `_onUpgrade`: las
    // migraciones son idempotentes, así que volver a correr la última sobre un
    // esquema al día no rompe nada. Se usa la anterior inmediata y no una
    // mucho más vieja para que esta prueba siga verificando lo suyo —que un
    // upgrade no se confunda con un downgrade— y no se convierta sin querer en
    // una prueba de toda la cadena de migraciones, que ya tienen las suyas.
    await db.execute(
      'PRAGMA user_version = ${DatabaseHelper.versionEsquema - 1}',
    );
    await db.close();
    abierta = null;

    db = await abrir();
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
    expect((await db.query('Categorias')).single['nombre'], 'Limpieza');
  });

  test('un archivo que no existe todavía no dispara el chequeo', () async {
    // Instalación nueva: no hay nada que comparar y la base se crea al día.
    expect(await File(path).exists(), isFalse);
    final db = await abrir();
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });
}

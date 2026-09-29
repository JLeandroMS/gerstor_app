import 'dart:io';

import 'package:archive/archive_io.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gestor_archivos/file_repository.dart';

void main() {
  late Directory root;
  late FileRepository repo;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file_manager_test_');
    final db = await databaseFactoryFfi.openDatabase(
      '${root.path}/test.db',
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: FileRepository.createSchema,
      ),
    );
    repo = FileRepository(
      db,
      await Directory('${root.path}/contents').create(),
    );
  });
  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });

  test(
    'importa bytes reales, renombra y conserva contenido al reabrir',
    () async {
      final source = await File('${root.path}/original.txt')
          .writeAsString('Hola SQLite');
      final id = await repo.importFile(source, 'tarea.txt', null);
      await repo.rename(id, 'trabajo.txt');
      expect(
        await repo.physical(await repo.get(id)).readAsString(),
        'Hola SQLite',
      );
      final dbPath = repo.db.path;
      final storage = repo.storage;
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      repo = FileRepository(db, storage);
      expect((await repo.get(id)).name, 'trabajo.txt');
      expect(await source.readAsString(), 'Hola SQLite');
    },
  );

  test('rechaza duplicados y ciclos sin alterar la jerarquia', () async {
    final a = await repo.createFolder(null, 'Documentos');
    final b = await repo.createFolder(a, 'Universidad');
    await expectLater(repo.createFolder(null, 'documentos'), throwsStateError);
    await expectLater(repo.move(a, b), throwsStateError);
    await expectLater(repo.copy(a, b), throwsStateError);
    expect((await repo.get(a)).parentId, isNull);
    expect((await repo.get(b)).parentId, a);
  });

  test(
    'copia carpetas y elimina en cascada sin borrar originales ni copia',
    () async {
      final a = await repo.createFolder(null, 'A');
      final b = await repo.createFolder(a, 'B');
      final source = await File('${root.path}/source.txt')
          .writeAsString('contenido');
      await repo.importFile(source, 'dato.txt', b);
      final duplicate = await repo.copy(a, null);
      expect((await repo.get(duplicate)).name, 'A (1)');
      await repo.delete(a);
      final copiedFolder = (await repo.children(duplicate)).single;
      final copiedFile = (await repo.children(copiedFolder.id)).single;
      expect(await repo.physical(copiedFile).readAsString(), 'contenido');
      expect(await repo.storage.list().length, 1);
      expect(await source.exists(), isTrue);
    },
  );

  test(
    'importacion fallida no deja registros y mover conserva bytes',
    () async {
      await expectLater(
        repo.importFile(File('${root.path}/missing'), 'x.txt', null),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repo.all(), isEmpty);
      final source = await File('${root.path}/s.txt').writeAsString('abc');
      final id = await repo.importFile(source, 's.txt', null);
      final folder = await repo.createFolder(null, 'Destino');
      await repo.move(id, folder);
      expect((await repo.get(id)).parentId, folder);
      expect(await repo.physical(await repo.get(id)).readAsString(), 'abc');
    },
  );
  test('mueve varios en una transacción o rechaza todo el lote', () async {
    final source = await File('${root.path}/s.txt').writeAsString('a');
    final a = await repo.importFile(source, 'a.txt', null);
    final b = await repo.importFile(source, 'b.txt', null);
    final folder = await repo.createFolder(null, 'Destino');
    await repo.moveMany([a, b], folder);
    expect((await repo.children(folder)).length, 2);
    final blocker = await repo.importFile(source, 'a.txt', null);
    await expectLater(repo.moveMany([a, b], null), throwsStateError);
    expect((await repo.get(a)).parentId, folder);
    expect((await repo.get(b)).parentId, folder);
    expect((await repo.get(blocker)).parentId, isNull);
  });

  test(
    'copia varios archivos en el mismo destino con nombres disponibles',
    () async {
      final source = await File('${root.path}/s.txt').writeAsString('abc');
      final a = await repo.importFile(source, 'a.txt', null);
      final b = await repo.importFile(source, 'b.txt', null);
      await repo.copyMany([a, b], null);
      final names = (await repo.children(null)).map((e) => e.name).toSet();
      expect(names, containsAll(['a.txt', 'b.txt', 'a (1).txt', 'b (1).txt']));
    },
  );

  test('comprime selección y extrae carpetas y bytes originales', () async {
    final source = await File('${root.path}/s.txt').writeAsString('contenido');
    final folder = await repo.createFolder(null, 'Fotos');
    final file = await repo.importFile(source, 'imagen.txt', folder);
    final zipId = await repo.compress([folder], null, 'respaldo.zip');
    expect(await repo.physical(await repo.get(zipId)).length(), greaterThan(0));
    final extractedId = await repo.extract(zipId, null);
    final extractedFolder = (await repo.children(extractedId)).single;
    final extractedFile = (await repo.children(extractedFolder.id)).single;
    expect(extractedFolder.name, 'Fotos');
    expect(await repo.physical(extractedFile).readAsString(), 'contenido');
    expect(
      await repo.physical(await repo.get(file)).readAsString(),
      'contenido',
    );
  });

  test('rechaza traversal dentro de ZIP sin crear carpeta destino', () async {
    final zipFile = File('${root.path}/evil.zip');
    final encoder = ZipFileEncoder()..create(zipFile.path);
    encoder.addArchiveFile(ArchiveFile.bytes('../outside.txt', [1, 2, 3]));
    await encoder.close();
    final zipId = await repo.importFile(zipFile, 'evil.zip', null);
    await expectLater(
      repo.extract(zipId, null),
      throwsA(isA<FormatException>()),
    );
    expect((await repo.children(null)).length, 1);
  });
}

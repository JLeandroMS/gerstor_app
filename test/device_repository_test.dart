import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gestor_archivos/application/indexed_file_browser.dart';
import 'package:gestor_archivos/data/local_file_storage.dart';
import 'package:gestor_archivos/data/sqlite_metadata_store.dart';

void main() {
  late Directory temp;
  late Directory root;
  late IndexedFileBrowser repo;
  late LocalFileStorage storage;
  late SqliteMetadataStore metadata;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('device_test_');
    root = await Directory('${temp.path}/phone').create();
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/index.db',
      options: OpenDatabaseOptions(version: 1, onCreate: SqliteMetadataStore.createSchema));
    storage = LocalFileStorage();
    await storage.configureRoots([root.path]);
    metadata = SqliteMetadataStore(() async => db);
    repo = IndexedFileBrowser(storage: storage, metadata: metadata);
  });
  tearDown(() async { await metadata.close(); await temp.delete(recursive: true); });

  test('descubre archivos existentes y sincroniza cambios externos con SQLite', () async {
    final source = await File('${root.path}/foto.txt').writeAsString('contenido');
    expect((await repo.list(root.path)).single.name, 'foto.txt');
    expect((await (await metadata.database).query('device_entries')).single['size'], 9);
    await source.delete();
    expect(await repo.list(root.path), isEmpty);
    expect(await (await metadata.database).query('device_entries'), isEmpty);
  });

  test('copiar conserva bytes, colisiones no sobrescriben y mover cambia el disco', () async {
    await File('${root.path}/original.txt').writeAsString('datos');
    final source = (await repo.list(root.path)).single;
    await repo.createFolder(root.path, 'destino');
    final dest = '${root.path}/destino';
    await repo.paste(source, dest, move: false);
    expect(await File('$dest/original.txt').readAsString(), 'datos');
    expect(await File(source.path).exists(), isTrue);
    await expectLater(repo.paste(source, dest, move: false), throwsStateError);
    await repo.rename(source, 'renombrado.txt');
    final renamed = (await repo.list(root.path)).firstWhere((e) => !e.folder);
    await repo.paste(renamed, dest, move: true);
    expect(await File(renamed.path).exists(), isFalse);
    final moved = (await repo.list(dest)).firstWhere((e) => e.name == 'renombrado.txt');
    await repo.delete(moved);
    expect(await File(moved.path).exists(), isFalse);
  });

  test('rechaza destino descendiente, nombres con traversal y rutas externas', () async {
    await repo.createFolder(root.path, 'padre');
    final folder = (await repo.list(root.path)).single;
    await repo.createFolder(folder.path, 'hijo');
    await expectLater(repo.paste(folder, '${folder.path}/hijo', move: false), throwsStateError);
    await expectLater(repo.createFolder(root.path, '../escape'), throwsFormatException);
    await expectLater(repo.list(temp.path), throwsStateError);
    await expectLater(storage.check(root.path, allowRoot: false), throwsStateError);
  });
}

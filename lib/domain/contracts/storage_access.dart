/// Solo permisos y descubrimiento de volúmenes; sustituible por un fake en pruebas.
abstract interface class StorageAccess {
  Future<bool> hasAccess();
  Future<void> requestAccess();
  Future<List<String>> roots();
}

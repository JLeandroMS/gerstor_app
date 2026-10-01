/// Integración con visores y menú de compartir; la pantalla no importa plugins.
abstract interface class FileActions {
  Future<void> open(String path);
  Future<void> share(String path);
}

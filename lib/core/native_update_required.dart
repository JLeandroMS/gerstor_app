/// El código instalado de Android no implementa una función que esta versión necesita.
class NativeUpdateRequired implements Exception {
  const NativeUpdateRequired();
  @override
  String toString() => 'Instalá la versión actualizada de la aplicación para consultar el almacenamiento.';
}

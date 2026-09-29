# Gestor de archivos del teléfono — Flutter, Android y SQLite

Esta versión abre el almacenamiento compartido real del celular. No hace falta importar los archivos: muestra Download, DCIM, Pictures, Documents, Music y cualquier otra carpeta accesible que exista. Permite navegar por almacenamiento interno y volúmenes SD/USB que Android exponga. Funciona offline.

## Actualizar tu proyecto en Windows

1. Detené `flutter run` y respaldá tu carpeta del proyecto.
2. Copiá `lib`, `test`, `android_template`, `pubspec.yaml`, `preparar.ps1` y `preparar.bat` de este ZIP sobre tu proyecto. Conservá tu carpeta `android` existente.
3. En la terminal, dentro de la carpeta del proyecto, ejecutá:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\preparar.ps1
flutter run
```

El script configura permisos y reemplaza MainActivity con el puente nativo, conservando el namespace existente. Si tu proyecto tiene modificaciones nativas propias, respaldalas antes. No basta con hot reload: hay cambios Android y hay que recompilar. No desinstalés la aplicación si querés conservar sus archivos privados.

También podés extraer este ZIP en una carpeta nueva y ejecutar `preparar.bat`: genera la estructura Android con tu Flutter instalado. Para actualizar la misma app se debe conservar el applicationId y la firma de instalación anterior.

## Primera apertura

1. Tocá **Dar acceso a los archivos**.
2. Android 11 o posterior: activá **Permitir administrar todos los archivos** y volvé a la app. En Android 10 o anterior aceptá el permiso de almacenamiento.
3. Se muestran las carpetas reales del almacenamiento. Entrá a `Download`, `DCIM`, etc.
4. Si no se actualiza, tocá el botón de actualizar. Si denegaste el permiso, podés solicitarlo otra vez.

Android no permite explorar los datos privados de otras apps, las carpetas protegidas Android/data y Android/obb ni los archivos del sistema. No requiere root ni intenta evadir estas restricciones.

## Acciones

- Tocar una carpeta: entrar. Flecha arriba o botón Atrás: subir.
- Tocar un archivo: abrir con una app compatible instalada.
- Menú del elemento: copiar, mover, renombrar, compartir archivos, propiedades o eliminar.
- Copiar/mover: seleccionar en el menú, navegar al destino y tocar Pegar. No sobrescribe nombres existentes.
- Mover entre volúmenes puede ser rechazado: copiá, verificá el destino y después eliminá el original.
- Crear carpeta: botón Carpeta.
- Buscar: filtra nombres de la carpeta actual, no hace una búsqueda recursiva de todo el teléfono.
- Eliminar: confirmación explícita; borra el archivo real y, para carpetas, su contenido. No hay papelera.
- Menú superior → Archivos guardados en la app: conserva el modo privado anterior y sus funciones.

## SQLite

`sqflite` crea las bases automáticamente en el celular. No debés instalar SQLite aparte.

- `device_files.db`: índice de metadatos de las carpetas visitadas, con ruta, nombre, carpeta padre, tipo, tamaño y fecha de modificación.
- `files.db`: conserva los metadatos del modo privado anterior, sin migración destructiva.
- El contenido real permanece en el sistema de archivos, nunca en BLOBs.
- Cada lectura exitosa actualiza el índice de esa carpeta en una transacción. Cambios externos se reflejan al refrescar o volver a entrar. No se escanea todo el teléfono al iniciar.
- Borrar registros del índice nunca borra archivos del teléfono.

## Verificación local

```powershell
flutter analyze
flutter test
flutter run
```

Se incluyen pruebas de repositorio y una lista de pruebas manuales. Este ZIP no incluye APK ni una compilación verificada: el entorno de elaboración no dispone de Flutter/Android SDK. Debe compilarse y probarse en tu PC y teléfono. Las pruebas de SQLite FFI en Windows pueden requerir la biblioteca nativa correspondiente.

Si el proceso se interrumpe durante una copia, puede quedar una carpeta temporal `.gestor-copy-*` en el destino. Los errores capturados limpian esa copia temporal y conservan el origen. No modifiques simultáneamente desde otra app los archivos que se están copiando.

Referencia del permiso: https://developer.android.com/training/data-storage/manage-all-files

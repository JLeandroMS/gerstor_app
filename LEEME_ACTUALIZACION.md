# Actualización: acceso rápido y almacenamiento

## Cambios

La pantalla inicial muestra «Acceso rápido», los iconos de carpetas y debajo «Almacenamiento» con barra, porcentaje y capacidad. Se retiraron el saludo «Todo a mano», el subtítulo y los párrafos explicativos. El modo privado está disponible desde el menú superior.

## Resolver MissingPluginException de dashboard

El código Dart pide dashboard a Kotlin mediante gestor/storage. El ZIP contiene esa implementación en android_template/MainActivity.kt, pero debe copiarse a android/app/src/main/kotlin/<paquete>/MainActivity.kt y compilarse en el APK. Hot reload y hot restart no actualizan Kotlin. El error observado significa que el canal instalado no está implementando ese método; reemplazar solamente lib no basta.

1. Detener flutter run anterior con q o Ctrl+C. Respaldar la carpeta del proyecto.
2. Reemplazar lib, test, docs y android_template con los de este ZIP. Copiar pubspec.yaml, preparar.ps1, preparar.bat, actualizar.ps1 y actualizar.bat en la raíz del proyecto.
3. Conservar android existente para mantener applicationId, firma y configuración. No desinstalar la app.
4. Conectar y desbloquear el teléfono. Aceptar depuración USB si se solicita.
5. Desde la terminal en la raíz del proyecto, ejecutar:

```powershell
.\actualizar.bat
```

Si hay varios dispositivos, seleccionar el teléfono cuando Flutter lo pregunte, o indicar el ID:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\actualizar.ps1 -Device ARGKUT3830001477
```

El actualizador hace flutter clean, ejecuta el preparador (que copia el Kotlin y verifica dashboard), descarga dependencias y ejecuta flutter run. No borra los datos del celular. No continuar si aparece un error durante la preparación: copiar el primer error.

Si persiste, verificar que la consola muestre «Android actualizado» y que se esté ejecutando este proyecto y el teléfono correcto. Revisar también si el manifiesto apunta a una Activity personalizada distinta de MainActivity; ese caso requiere revisar la configuración local.

## Verificación

Se comprobaron las referencias locales, los límites entre capas, el orden visual en el código y la presencia de dashboard en la plantilla Kotlin y el preparador. Se añadió una prueba con canal simulado para el método ausente y el método disponible. No fue posible ejecutar Flutter, la compilación Android ni las pruebas aquí porque no hay SDK instalado. La validación final debe hacerse en el equipo del usuario.

# Pruebas en Android (pendientes de ejecución en dispositivo)

Usar archivos desechables y una carpeta PruebaGestor en Download.

1. Arranque sin permiso: explicación visible, sin bloqueo ni falsa carpeta vacía.
2. Denegar permiso: volver a la app; el botón permanece disponible.
3. Otorgar acceso total y volver: aparecen Download, DCIM y carpetas existentes sin importar nada.
4. Crear desde otra app un archivo en PruebaGestor. Actualizar: aparece. Abrirlo.
5. Crear carpeta, renombrar archivo y verificar en el explorador original del teléfono.
6. Copiar carpeta con dos archivos: comparar contenido y comprobar que el origen sigue presente.
7. Mover archivo a otra carpeta: desaparece del origen y aparece en destino.
8. Intentar pegar donde ya existe el nombre: rechaza y no sobrescribe.
9. Intentar copiar una carpeta dentro de sí misma: rechaza.
10. Cancelar eliminar: conserva contenido. Confirmar sobre archivo desechable: desaparece del disco.
11. Revocar permiso en Ajustes y volver: no muestra el listado anterior como si tuviera acceso.
12. Entrar en Android/data: informa restricción y conserva navegación anterior.
13. Consultar con Database Inspector device_files.db: filas con rutas y metadatos, sin BLOBs.
14. Cerrar y abrir; menú de archivos privados: siguen disponibles los archivos agregados antes, si se actualizó la misma app sin desinstalarla.
15. Probar SD/USB si existe, acceso sin internet y compartir con una app instalada.
16. Botón Atrás, rotación y volver desde un visor: sin errores de setState después de dispose.

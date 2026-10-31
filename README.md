# Mis datos y MultiMundos 3D

App estática publicada con GitHub Pages; Supabase gestiona autenticación, perfiles, permisos y progreso.

## Usuarios

1. Registrarse y confirmar el correo.
2. Esperar aprobación del administrador.
3. Iniciar sesión en Mis datos y abrir Juegos.

Los perfiles se guardan por cuenta en `profiles`. Al completar un nivel se guarda en `game_progress` el nivel completado, siguiente nivel disponible, mejor puntaje e intentos. Los datos se pueden consultar desde otro navegador con la misma cuenta. El progreso anterior guardado localmente no se migra automáticamente. Si el guardado falla, el juego permite reintentarlo antes de salir.

## Administración

Abrir `admin.html` después de iniciar sesión con una cuenta administrativa. Permite aprobar, bloquear o dejar pendiente a un usuario, asignar acceso premium manual, activar juegos y elegir cuáles son premium. Incluye progreso e historial de cambios. La cuenta del administrador está protegida contra cambios desde el panel.

Los administradores se asignan únicamente mediante una operación autorizada en la base de datos `private.app_admins`; no existe registro público como administrador. Los permisos se verifican en Supabase mediante RLS y no dependen de botones ocultos o de datos editables del perfil.

Los bloqueos impiden acceder a perfiles y progreso en el servidor inmediatamente; el juego comprueba el estado de la cuenta cada 20 segundos y al entrar a un nivel. Como los archivos 3D se sirven desde un repositorio público, no se consideran una protección anticopia de contenido premium. Los pagos y la entrega protegida de contenido están pendientes.

## Archivos

- `app-client.js`: cliente público Supabase compartido y consulta de acceso.
- `juegos-engine.js`: motor 3D y guardado del progreso.
- `admin.html`, `admin.js`: panel de administración.
- `supabase/access-and-progress.sql`: referencia del esquema aplicado.

Las claves secretas y service_role no deben incluirse en GitHub. La clave publishable es pública y las tablas están protegidas con RLS.

## Publicación

En GitHub, Settings → Pages → Deploy from a branch → main → / (root) → Save.

Página: https://web-2022.github.io/datos/
Panel: https://web-2022.github.io/datos/admin.html

## Verificación

Se comprobaron políticas con identidades temporales dentro de una transacción revertida: aislamiento entre usuarios, prohibición de autoasignarse permisos, aprobación, bloqueo, acceso premium, persistencia de progreso y auditoría. No se conservaron usuarios de prueba. Se revisó sintaxis JavaScript y referencias de los elementos de interfaz. Pendiente prueba visual y flujo completo con la cuenta del propietario.

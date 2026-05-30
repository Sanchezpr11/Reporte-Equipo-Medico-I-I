# Opciones de diseño (vistas previas)

Prototipos **mobile-first** para rediseñar la UI/UX de la app. Son archivos
**independientes** y **no tocan** `index.html` ni los datos reales: usan
contenido de ejemplo solo para mostrar el estilo y la navegación.

> Objetivo: ver y comparar direcciones de diseño **antes** de cambiar la app.

## Cómo verlas

Abre cualquiera de estos archivos en el navegador (idealmente en el teléfono):

- **`index.html`** — menú para elegir entre las 3 opciones.
- **`option-a-barra-inferior.html`** — navegación con barra inferior tipo app.
- **`option-b-menu-lateral.html`** — navegación con menú lateral (☰ drawer).
- **`option-c-selector.html`** — navegación con un selector de sección desplegable.

Todas funcionan sin conexión (CSS propio, sin CDNs).

## Las 3 direcciones

| Opción | Navegación | Mejor para |
|--------|-----------|-----------|
| **A** | Barra inferior fija (4 accesos + “Más”) | Uso con una mano; sensación de app nativa |
| **B** | Menú lateral con todas las secciones agrupadas | Muchas secciones; ver todo de un vistazo |
| **C** | Selector/desplegable de sección | Máxima simpleza y un header compacto |

Las tres comparten el **mismo sistema visual** (colores, tipografía, tarjetas,
gráficos), así que la comparación es justa y se centra en la navegación.

## Siguiente paso

Cuando elijas una (o una mezcla), se implementa el rediseño completo en la app
real `index.html`, sección por sección.

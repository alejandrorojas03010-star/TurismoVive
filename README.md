# TurismoVive · Grupo 6 — Proyecto Integrador (Base de Datos III)

Integrantes: Alejandro Rojas Espinoza · Alejandro Yabeta Arias · Mathias Ethan Cordova Rodrigues · Sebastian Maldonado Salazar

## Estructura

```
sql/
  01_Avance1_TurismoVive.sql                 Avance 1: tipos, Nested Table, tablas de objetos, REF, datos reales
  02_Avance2_Semana1_PKG_TURISMOVIVE.sql     Avance 2 · Semana 1: paquete PKG_TURISMOVIVE
  03_Avance2_Semana2_TRIGGER_Y_PRUEBAS.sql   Avance 2 · Semana 2: trigger TRG_RESGUARDO_RESERVAS,
                                             pruebas del paquete, pruebas del trigger, integración
docs/
  Diseno_PKG_TURISMOVIVE_Semana1.pdf         Diseño del paquete (Semana 1)
  Informe_Final_Integracion_Avance2_TurismoVive.docx / .pdf   Informe final (Semana 3, 4 páginas)
  Guia_Defensa_Oral_y_Checklist.md           Reparto de la defensa y lista de verificación
capturas/                                    Capturas A (éxito) y B (violación) del trigger
```

## Cómo ejecutar (Oracle SQL Developer, "Run Script" F5)

1. `01_Avance1_TurismoVive.sql`: **solo si el esquema aún no existe** (crea tablas y datos).
2. `02_Avance2_Semana1_PKG_TURISMOVIVE.sql`: crea el paquete.
3. `03_Avance2_Semana2_TRIGGER_Y_PRUEBAS.sql`: crea el trigger y ejecuta todas las pruebas.

El script 03 no modifica el esquema ni los datos del Avance 1: cada bloque de pruebas corre dentro de un
`SAVEPOINT` que se revierte. Busca los comentarios `>>> CAPTURA A` y `>>> CAPTURA B` para las evidencias.

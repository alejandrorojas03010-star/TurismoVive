# TurismoVive · Grupo 6 — Guía de defensa oral y lista de verificación (Avance 2)

Cada integrante debe poder explicar **solo, sin ayuda**, su parte y demostrarla en vivo con el script
`sql/03_Avance2_Semana2_TRIGGER_Y_PRUEBAS.sql`. El reparto es una propuesta: pueden intercambiarlo, pero
cada persona debe quedar con al menos un subprograma o con el trigger completo.

---

## 1. Alejandro Rojas Espinoza — `TRG_RESGUARDO_RESERVAS` (trigger completo)

**Qué decir (1 minuto):**
- Protege la regla: *un paquete nunca tiene más pasajeros activos (PENDIENTE/CONFIRMADA) que su cupo (20), y
  cada reserva es válida (pax > 0, estado permitido, viajero y paquete existentes, fecha antes del viaje).*
- Es un **COMPOUND TRIGGER** `FOR INSERT OR UPDATE ON tabla_reservas` con dos secciones:
  - **BEFORE EACH ROW:** reglas de cada fila con `:NEW`. BEFORE porque valida antes de escribir, así la fila
    inválida nunca entra. Aquí anota qué paquetes se tocaron.
  - **AFTER STATEMENT:** suma los pasajeros activos por paquete. STATEMENT porque un trigger de fila no puede leer
    la tabla que se está modificando (**ORA-04091, tabla mutante**). AFTER porque la suma debe verse con la
    sentencia ya aplicada.
- Si falla, `RAISE_APPLICATION_ERROR` revierte **la sentencia completa**.

**Demostrar:** sección 5: T1 (llena el paquete 3 hasta 20) y V1 (un pasajero más da ORA-20014). Luego V4 (un
UPDATE de 3 filas se revierte entero).

**Preguntas probables:**
- *¿Por qué no un BEFORE ROW simple?* → Tabla mutante: fallaría con `INSERT … SELECT` y con todo `UPDATE`, y
  además vería estados intermedios.
- *¿Por qué no se vigila DELETE?* → Borrar una reserva solo libera cupo y no puede violar la regla.
- *¿Para qué el trigger si el paquete ya valida?* → DML directo lo salta, y `sp_cambiar_estado_reserva` no
  revisa el cupo al reactivar (prueba 6.5).
- *¿Qué es ORA-04088?* → Oracle lo agrega para indicar que el error ocurrió dentro de un trigger.

---

## 2. Alejandro Yabeta Arias — `sp_registrar_reserva` y `sp_cambiar_estado_reserva`

**Qué decir:**
- `sp_registrar_reserva` valida en orden: pasajeros > 0, estado permitido, viajero (con `SELECT REF(v) INTO`;
  si da `NO_DATA_FOUND` lanza `e_viajero_inexistente`), paquete (`obtener_paquete`), fecha < `fecha_inicio` y
  cupo (`fn_cupos_disponibles`). Recién después hace el `INSERT` con el constructor `tipo_reserva` y las REF.
  `DUP_VAL_ON_INDEX` se convierte en `e_reserva_duplicada`.
- `sp_cambiar_estado_reserva` normaliza con `UPPER(TRIM())`, valida el estado y usa `SQL%ROWCOUNT = 0` para
  detectar una reserva inexistente. Cancelar libera cupo sin código extra.
- Ninguno hace COMMIT: la transacción la controla el cliente.

**Demostrar:** 4.6 y 4.7 (un éxito y un fallo cada uno).

**Pregunta probable:** *¿Qué pasa si reactivo una reserva cancelada y ya no hay cupo?* → El procedimiento no lo
revisa, pero el trigger lo bloquea (6.5).

---

## 3. Mathias Ethan Cordova Rodrigues — `fn_precio_paquete`, `fn_total_reserva`, `fn_cupos_disponibles`

**Qué decir:**
- `fn_precio_paquete` no repite la fórmula: llama al método del tipo `calcula_precio_total()`, que calcula
  `(precio_base + Σ actividades) × (1 + comisión/100)`. Ejemplo: paquete 3 da (1500 + 100) × 1.08 = **1728**.
- `fn_total_reserva` navega con `DEREF(r.ref_paquete)` y multiplica por `num_pasajeros`. Ejemplo: reserva 3
  da 1728 × 4 = **6912**. Si la REF está dangling, DEREF devuelve NULL y se lanza `e_paquete_inexistente`.
- `fn_cupos_disponibles` = 20 − Σ pasajeros de reservas PENDIENTE/CONFIRMADA (filtra con DEREF en el WHERE).
  Usa `GREATEST(…, 0)` para no devolver negativos. Valores reales: **18 / 19 / 16**.

**Demostrar:** 4.1, 4.2 y 4.3.

---

## 4. Sebastian Maldonado Salazar — `sp_listar_actividades`, `sp_resumen_paquete` y excepciones

**Qué decir:**
- `sp_listar_actividades` aplana la Nested Table con `TABLE(p.actividades)` y lista cada actividad con la suma,
  el precio base, la comisión y el total.
- `sp_resumen_paquete` devuelve 4 parámetros **OUT** (destino, número de actividades, precio y cupos) y
  protege contra `COLLECTION_IS_NULL` si la colección es atómicamente nula.
- Excepciones: seis propias en la especificación con `PRAGMA EXCEPTION_INIT` (−20010 a −20015), que el cliente
  captura **por nombre** (`WHEN pkg_turismovive.e_sin_cupo`). El trigger reutiliza los mismos códigos, así que
  el cliente atrapa igual el error venga del paquete o del trigger.

**Demostrar:** 4.4 y 4.5.

---

## Lista de verificación antes de entregar

| # | Punto | Dónde | ¿Listo? |
|---|---|---|---|
| 1 | Momento (BEFORE/AFTER) y nivel (ROW/STATEMENT) justificados por escrito | Informe §4.3 · script §0 | ☑ |
| 2 | Trigger implementado y la regla se cumple | Script §2 y §5 | ☑ VALID en FreeSQL (29/09/2026) |
| 3 | Cada subprograma: 1 caso de éxito + 1 de fallo | Script §4 | ☑ ejecutado, 7/7 correctos |
| 4 | Trigger: intento deliberado de violar la regla | Script §5 (V1–V8) | ☑ ejecutado, 8/8 bloqueados |
| 5 | Verificación con datos **reales** del Avance 1 | Script §1, §6 y §7 | ☑ ejecutado, datos intactos |
| 6 | Informe final (≤ 5 páginas) | `docs/Informe_Final_…docx` (4 págs.) | ☑ |
| 7 | Nombres idénticos a la Sección 5 de la guía (`PKG_TURISMOVIVE`, `TRG_RESGUARDO_RESERVAS`) | Script §3 · captura C | ☐ **cotejar con la guía** |
| 8 | Capturas: **A** = T1 éxito · **B** = V1 violación · **C** = nombres y datos intactos | carpeta `capturas/` | ☑ |
| 9 | Scripts versionados en el repositorio Git del equipo | — | ☐ |
| 10 | Defensa ensayada: cada integrante explica su parte sin ayuda | Esta guía | ☐ |

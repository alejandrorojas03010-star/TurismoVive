-- =====================================================================
-- TURISMOVIVE - GRUPO 6
-- AVANCE 2 - SEMANA 2: TRIGGER DE RESGUARDO + PRUEBAS + INTEGRACION
-- =====================================================================
-- Integrantes:
--    Alejandro Rojas Espinoza
--    Alejandro Yabeta Arias
--    Mathias Ethan Cordova Rodrigues
--    Sebastian Maldonado Salazar
--
-- PRERREQUISITOS (en este orden, una sola vez):
--    1. 01_Avance1_TurismoVive.sql                (tipos, tablas y datos reales)
--    2. 02_Avance2_Semana1_PKG_TURISMOVIVE.sql    (paquete PKG_TURISMOVIVE)
--
-- Este script NO crea ni modifica tipos ni tablas del Avance 1 y NO
-- inserta datos de prueba aislados: todas las pruebas se hacen sobre los
-- paquetes 1-3, viajeros 1-3 y reservas 1-3 ya insertados en el Avance 1.
-- Cada bloque de pruebas trabaja dentro de un SAVEPOINT y se revierte al
-- final, por lo que los datos reales quedan intactos.
--
-- ORDEN:
--  0. DISENO Y JUSTIFICACION DEL TRIGGER (Actividad 1)
--  1. VERIFICACION PREVIA: los datos reales ya cumplen la regla
--  2. CREACION DEL TRIGGER TRG_RESGUARDO_RESERVAS (Actividad 2)
--  3. VERIFICACION DE NOMBRES Y COMPILACION (Actividad 7)
--  4. PRUEBAS INDIVIDUALES DEL PAQUETE: exito + fallo (Actividad 3)
--  5. PRUEBAS DEL TRIGGER: exito + violacion deliberada (Actividad 4)
--  6. INTEGRACION PAQUETE + TRIGGER SOBRE DATOS REALES (Actividad 5)
--  7. VERIFICACION FINAL: datos del Avance 1 intactos
--
-- Ejecutar como SCRIPT (F5) en Oracle SQL Developer.
-- Los puntos marcados con ">>> CAPTURA" son los que se entregan como
-- evidencia (caso exitoso y caso de violacion del trigger).
-- =====================================================================

SET SERVEROUTPUT ON;


-- =====================================================================
-- 0. DISENO Y JUSTIFICACION DEL TRIGGER
-- =====================================================================
-- REGLA DE NEGOCIO PROTEGIDA
--    "Un paquete turistico nunca puede tener mas pasajeros en reservas
--     activas (PENDIENTE o CONFIRMADA) que su cupo maximo
--     (pkg_turismovive.c_cupo_maximo = 20), y toda reserva debe ser
--     valida: pasajeros > 0, estado permitido, viajero y paquete
--     existentes, y fecha de reserva anterior al inicio del viaje."
--
-- POR QUE UN TRIGGER, SI EL PAQUETE YA VALIDA
--    El paquete solo protege a quien lo usa. Un INSERT/UPDATE directo
--    (SQL Developer, otra aplicacion, las capas de avances posteriores)
--    lo salta. Ademas, sp_cambiar_estado_reserva no revisa el cupo al
--    reactivar una reserva CANCELADA. El trigger es la ultima linea de
--    defensa: vive en la tabla y se ejecuta sin importar el camino.
--
-- EVENTOS: INSERT OR UPDATE sobre TABLA_RESERVAS.
--    DELETE no se vigila: borrar una reserva solo libera cupo y nunca
--    puede violar la regla.
--
-- MOMENTO Y NIVEL: COMPOUND TRIGGER = BEFORE EACH ROW + AFTER STATEMENT
--
--  a) BEFORE EACH ROW  -> reglas de la propia fila
--     (pasajeros, estado, viajero, paquete, fecha)
--     - ROW: la regla depende de los valores de cada fila (:NEW).
--     - BEFORE: se valida ANTES de escribir; una fila invalida nunca
--       llega a la tabla y el error indica exactamente que fila fallo.
--       Aqui tambien se anota que paquetes fueron afectados.
--
--  b) AFTER STATEMENT  -> regla agregada del cupo
--     (SUM de pasajeros activos por paquete <= 20)
--     - STATEMENT: el cupo es una regla sobre el CONJUNTO de reservas,
--       no sobre una fila. Un trigger de fila no puede consultar
--       TABLA_RESERVAS mientras se modifica (ORA-04091, tabla mutante):
--       fallaria con los INSERT ... SELECT del Avance 1 y con todo UPDATE.
--     - AFTER: la suma debe calcularse sobre el estado FINAL de la tabla,
--       con todas las filas del enunciado ya aplicadas (un UPDATE de
--       varias filas se evalua una sola vez y en su resultado real).
--       Si se viola, RAISE_APPLICATION_ERROR revierte el enunciado
--       completo (atomicidad a nivel de sentencia).
--
-- CODIGOS DE ERROR: se reutilizan los del paquete (-20010, -20011,
--    -20014, -20015). Asi el cliente captura pkg_turismovive.e_sin_cupo o
--    e_dato_invalido por nombre, sin importar si el error lo detecto el
--    paquete o el trigger. Los mensajes del trigger empiezan con
--    [TRG_RESGUARDO_RESERVAS] para distinguir quien lo detecto.
-- =====================================================================


-- =====================================================================
-- 1. VERIFICACION PREVIA: LOS DATOS REALES DEL AVANCE 1 CUMPLEN LA REGLA
-- =====================================================================
-- Un trigger no revisa filas que ya existian. Antes de crearlo se
-- comprueba que los datos reales no violan la regla que va a proteger.

-- 1.1 Datos reales disponibles. Esperado: 3 / 3 / 3.
SELECT (SELECT COUNT(*) FROM tabla_paquetes_turisticos) AS paquetes,
       (SELECT COUNT(*) FROM tabla_viajeros)            AS viajeros,
       (SELECT COUNT(*) FROM tabla_reservas)            AS reservas
  FROM dual;

-- 1.2 Ocupacion por paquete. Esperado: 2, 1 y 4 pasajeros activos
--     (todos <= 20); cupos disponibles 18, 19 y 16.
SELECT p.id_paquete,
       p.destino,
       (SELECT NVL(SUM(r.num_pasajeros), 0)
          FROM tabla_reservas r
         WHERE DEREF(r.ref_paquete).id_paquete = p.id_paquete
           AND r.estado_reserva IN ('PENDIENTE', 'CONFIRMADA'))  AS pasajeros_activos,
       20                                                        AS cupo_maximo,
       pkg_turismovive.fn_cupos_disponibles(p.id_paquete)        AS cupos_disponibles
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;

-- 1.3 Reservas reales que violarian alguna regla de fila.
--     Esperado: 0 filas.
SELECT r.id_reserva
  FROM tabla_reservas r
 WHERE r.num_pasajeros IS NULL
    OR r.num_pasajeros <= 0
    OR r.estado_reserva IS NULL
    OR r.estado_reserva NOT IN ('PENDIENTE', 'CONFIRMADA', 'CANCELADA')
    OR r.ref_viajero IS NULL
    OR r.ref_paquete IS NULL
    OR r.ref_viajero IS DANGLING
    OR r.ref_paquete IS DANGLING
    OR r.fecha_reserva IS NULL
    OR r.fecha_reserva >= DEREF(r.ref_paquete).fecha_inicio;


-- =====================================================================
-- 2. TRIGGER DE RESGUARDO: TRG_RESGUARDO_RESERVAS
-- =====================================================================

CREATE OR REPLACE TRIGGER trg_resguardo_reservas
FOR INSERT OR UPDATE ON tabla_reservas
COMPOUND TRIGGER

   -- Estado compartido por las secciones del trigger durante UNA sentencia.
   -- Se reinicia automaticamente en cada sentencia que dispara el trigger.
   TYPE t_paquetes IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
   g_paquetes  t_paquetes;              -- paquetes a revisar (sin repetidos)

   v_viajero   tipo_viajero;
   v_paquete   tipo_paquete_turistico;
   v_id        PLS_INTEGER;
   v_ocupados  NUMBER;

   -- ------------------------------------------------------------------
   -- BEFORE EACH ROW: reglas de la fila, antes de escribirla
   -- ------------------------------------------------------------------
   BEFORE EACH ROW IS
   BEGIN
      -- R1. Numero de pasajeros
      IF :NEW.num_pasajeros IS NULL OR :NEW.num_pasajeros <= 0 THEN
         RAISE_APPLICATION_ERROR(-20015,
            '[TRG_RESGUARDO_RESERVAS] Reserva ' || :NEW.id_reserva ||
            ': el numero de pasajeros debe ser mayor a 0');
      END IF;

      -- R2. Estado permitido
      IF :NEW.estado_reserva IS NULL
         OR :NEW.estado_reserva NOT IN ('PENDIENTE', 'CONFIRMADA', 'CANCELADA') THEN
         RAISE_APPLICATION_ERROR(-20015,
            '[TRG_RESGUARDO_RESERVAS] Reserva ' || :NEW.id_reserva ||
            ': estado no permitido (' || NVL(:NEW.estado_reserva, 'NULL') || ')');
      END IF;

      -- R3. La REF al viajero debe apuntar a un viajero existente
      --     (cubre REF nula y REF dangling)
      BEGIN
         SELECT VALUE(v)
           INTO v_viajero
           FROM tabla_viajeros v
          WHERE REF(v) = :NEW.ref_viajero;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011,
               '[TRG_RESGUARDO_RESERVAS] Reserva ' || :NEW.id_reserva ||
               ': la REF al viajero es nula o apunta a un viajero inexistente');
      END;

      -- R4. La REF al paquete debe apuntar a un paquete existente
      BEGIN
         SELECT VALUE(p)
           INTO v_paquete
           FROM tabla_paquetes_turisticos p
          WHERE REF(p) = :NEW.ref_paquete;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20010,
               '[TRG_RESGUARDO_RESERVAS] Reserva ' || :NEW.id_reserva ||
               ': la REF al paquete es nula o apunta a un paquete inexistente');
      END;

      -- R5. La reserva debe hacerse antes de que empiece el viaje
      IF :NEW.fecha_reserva IS NULL
         OR :NEW.fecha_reserva >= v_paquete.fecha_inicio THEN
         RAISE_APPLICATION_ERROR(-20015,
            '[TRG_RESGUARDO_RESERVAS] Reserva ' || :NEW.id_reserva ||
            ': la fecha de reserva (' ||
            NVL(TO_CHAR(:NEW.fecha_reserva, 'DD/MM/YYYY'), 'NULL') ||
            ') debe ser anterior al inicio del paquete (' ||
            TO_CHAR(v_paquete.fecha_inicio, 'DD/MM/YYYY') || ')');
      END IF;

      -- Solo las reservas activas consumen cupo: se anota el paquete
      -- para revisarlo una vez terminada la sentencia.
      IF :NEW.estado_reserva IN ('PENDIENTE', 'CONFIRMADA') THEN
         g_paquetes(v_paquete.id_paquete) := TRUE;
      END IF;
   END BEFORE EACH ROW;

   -- ------------------------------------------------------------------
   -- AFTER STATEMENT: regla agregada del cupo, sobre el estado final
   -- ------------------------------------------------------------------
   AFTER STATEMENT IS
   BEGIN
      v_id := g_paquetes.FIRST;

      WHILE v_id IS NOT NULL LOOP
         SELECT NVL(SUM(r.num_pasajeros), 0)
           INTO v_ocupados
           FROM tabla_reservas r
          WHERE DEREF(r.ref_paquete).id_paquete = v_id
            AND r.estado_reserva IN ('PENDIENTE', 'CONFIRMADA');

         IF v_ocupados > pkg_turismovive.c_cupo_maximo THEN
            RAISE_APPLICATION_ERROR(-20014,
               '[TRG_RESGUARDO_RESERVAS] Sobreventa en el paquete ' || v_id ||
               ': ' || v_ocupados || ' pasajeros activos superan el cupo maximo de ' ||
               pkg_turismovive.c_cupo_maximo || '. La operacion fue revertida');
         END IF;

         v_id := g_paquetes.NEXT(v_id);
      END LOOP;
   END AFTER STATEMENT;

END trg_resguardo_reservas;
/

SHOW ERRORS TRIGGER trg_resguardo_reservas;


-- =====================================================================
-- 3. VERIFICACION DE NOMBRES Y COMPILACION (deben coincidir con la
--    Seccion 5 de la guia: PKG_TURISMOVIVE y TRG_RESGUARDO_RESERVAS)
-- =====================================================================

-- Esperado: PACKAGE VALID, PACKAGE BODY VALID, TRIGGER VALID.
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_TURISMOVIVE', 'TRG_RESGUARDO_RESERVAS')
 ORDER BY object_name, object_type;

-- Esperado: COMPOUND, INSERT OR UPDATE, TABLA_RESERVAS, ENABLED,
--           BEFORE_ROW = YES, AFTER_STATEMENT = YES.
SELECT trigger_name,
       trigger_type,
       triggering_event,
       table_name,
       status,
       before_row,
       after_statement
  FROM user_triggers
 WHERE trigger_name = 'TRG_RESGUARDO_RESERVAS';

-- Esperado: los 7 subprogramas publicos del paquete.
SELECT procedure_name
  FROM user_procedures
 WHERE object_name = 'PKG_TURISMOVIVE'
   AND procedure_name IS NOT NULL
 ORDER BY procedure_name;


-- =====================================================================
-- 4. PRUEBAS INDIVIDUALES DEL PAQUETE (un caso de exito y uno de fallo
--    por subprograma, sobre los datos reales del Avance 1)
-- =====================================================================

SAVEPOINT sp_pruebas_paquete;

-- ---------------------------------------------------------------------
-- 4.1 fn_precio_paquete
-- ---------------------------------------------------------------------
-- EXITO: paquete real 3 (Amazonia). (1500 + 100) x 1.08 = 1728
SELECT pkg_turismovive.fn_precio_paquete(3) AS precio_paquete_3 FROM dual;

-- FALLO: paquete 99 no existe -> e_paquete_inexistente (ORA-20010)
BEGIN
   DBMS_OUTPUT.PUT_LINE(pkg_turismovive.fn_precio_paquete(99));
EXCEPTION
   WHEN pkg_turismovive.e_paquete_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('4.1 FALLO ESPERADO -> ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- 4.2 fn_total_reserva
-- ---------------------------------------------------------------------
-- EXITO: reservas reales. 1573 x 2 = 3146 | 868 x 1 = 868 | 1728 x 4 = 6912
SELECT r.id_reserva,
       r.num_pasajeros,
       pkg_turismovive.fn_total_reserva(r.id_reserva) AS total_reserva
  FROM tabla_reservas r
 ORDER BY r.id_reserva;

-- FALLO: reserva 99 no existe -> e_reserva_inexistente (ORA-20012)
BEGIN
   DBMS_OUTPUT.PUT_LINE(pkg_turismovive.fn_total_reserva(99));
EXCEPTION
   WHEN pkg_turismovive.e_reserva_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('4.2 FALLO ESPERADO -> ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- 4.3 fn_cupos_disponibles
-- ---------------------------------------------------------------------
-- EXITO: 20 - pasajeros activos reales -> 18 / 19 / 16
SELECT p.id_paquete,
       pkg_turismovive.fn_cupos_disponibles(p.id_paquete) AS cupos
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;

-- FALLO: paquete 99 -> e_paquete_inexistente (ORA-20010)
BEGIN
   DBMS_OUTPUT.PUT_LINE(pkg_turismovive.fn_cupos_disponibles(99));
EXCEPTION
   WHEN pkg_turismovive.e_paquete_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('4.3 FALLO ESPERADO -> ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- 4.4 sp_listar_actividades
-- ---------------------------------------------------------------------
-- EXITO: paquete real 2 -> 3 actividades, suma 125, precio total 868
-- FALLO: paquete 99 -> e_paquete_inexistente (ORA-20010)
BEGIN
   pkg_turismovive.sp_listar_actividades(2);

   BEGIN
      pkg_turismovive.sp_listar_actividades(99);
   EXCEPTION
      WHEN pkg_turismovive.e_paquete_inexistente THEN
         DBMS_OUTPUT.PUT_LINE('4.4 FALLO ESPERADO -> ' || SQLERRM);
   END;
END;
/

-- ---------------------------------------------------------------------
-- 4.5 sp_resumen_paquete
-- ---------------------------------------------------------------------
-- EXITO: paquete real 3 -> Amazonia Boliviana - Rurrenabaque | 1 | 1728 | 16
-- FALLO: paquete 99 -> e_paquete_inexistente (ORA-20010)
DECLARE
   v_destino VARCHAR2(60);
   v_num_act NUMBER;
   v_precio  NUMBER;
   v_cupos   NUMBER;
BEGIN
   pkg_turismovive.sp_resumen_paquete(3, v_destino, v_num_act, v_precio, v_cupos);
   DBMS_OUTPUT.PUT_LINE('4.5 EXITO -> ' || v_destino ||
      ' | actividades = ' || v_num_act ||
      ' | precio = '      || v_precio  ||
      ' | cupos = '       || v_cupos);

   BEGIN
      pkg_turismovive.sp_resumen_paquete(99, v_destino, v_num_act, v_precio, v_cupos);
   EXCEPTION
      WHEN pkg_turismovive.e_paquete_inexistente THEN
         DBMS_OUTPUT.PUT_LINE('4.5 FALLO ESPERADO -> ' || SQLERRM);
   END;
END;
/

-- ---------------------------------------------------------------------
-- 4.6 sp_registrar_reserva
-- ---------------------------------------------------------------------
-- EXITO: viajera real 1 (Ana) reserva 2 pasajeros en el paquete real 3.
--        Cupos del paquete 3: 16 -> 14. (El trigger tambien la valida.)
-- FALLO: viajero real 2 pide 15 pasajeros y solo quedan 14 -> e_sin_cupo
BEGIN
   pkg_turismovive.sp_registrar_reserva(
      p_id_reserva    => 4,
      p_id_viajero    => 1,
      p_id_paquete    => 3,
      p_num_pasajeros => 2,
      p_fecha_reserva => DATE '2026-10-01');

   DBMS_OUTPUT.PUT_LINE('4.6 EXITO -> cupos paquete 3 = ' ||
      pkg_turismovive.fn_cupos_disponibles(3));              -- 14

   BEGIN
      pkg_turismovive.sp_registrar_reserva(5, 2, 3, 15, DATE '2026-10-01');
   EXCEPTION
      WHEN pkg_turismovive.e_sin_cupo THEN
         DBMS_OUTPUT.PUT_LINE('4.6 FALLO ESPERADO -> ' || SQLERRM);
   END;
END;
/

-- ---------------------------------------------------------------------
-- 4.7 sp_cambiar_estado_reserva
-- ---------------------------------------------------------------------
-- EXITO: la reserva 4 (creada en 4.6) pasa a CONFIRMADA ('confirmada'
--        se normaliza a mayusculas).
-- FALLO: estado 'VOLANDO' no permitido -> e_dato_invalido (ORA-20015)
BEGIN
   pkg_turismovive.sp_cambiar_estado_reserva(4, 'confirmada');

   BEGIN
      pkg_turismovive.sp_cambiar_estado_reserva(4, 'VOLANDO');
   EXCEPTION
      WHEN pkg_turismovive.e_dato_invalido THEN
         DBMS_OUTPUT.PUT_LINE('4.7 FALLO ESPERADO -> ' || SQLERRM);
   END;

   BEGIN
      pkg_turismovive.sp_cambiar_estado_reserva(99, 'CANCELADA');
   EXCEPTION
      WHEN pkg_turismovive.e_reserva_inexistente THEN
         DBMS_OUTPUT.PUT_LINE('4.7 FALLO ESPERADO (adicional) -> ' || SQLERRM);
   END;
END;
/

-- Revertir: los datos reales vuelven a su estado original.
ROLLBACK TO sp_pruebas_paquete;


-- =====================================================================
-- 5. PRUEBAS DEL TRIGGER: EXITO Y VIOLACION DELIBERADA DE LA REGLA
-- =====================================================================
-- Todas las operaciones son DML DIRECTO sobre TABLA_RESERVAS, sin pasar
-- por el paquete: se prueba que el trigger protege la regla aunque
-- alguien "se salte" PKG_TURISMOVIVE. Se usa el mismo estilo
-- INSERT ... SELECT REF(v), REF(p) del Avance 1.
--
-- Punto de partida real: paquete 3 tiene 4 pasajeros activos (reserva 3).

SAVEPOINT sp_pruebas_trigger;

-- ---------------------------------------------------------------------
-- >>> CAPTURA A - CASO EXITOSO
-- T1. Se llena el paquete 3 exactamente hasta el cupo: 4 + 16 = 20.
--     Esperado: "1 fila insertada" y cupos disponibles = 0.
-- ---------------------------------------------------------------------
INSERT INTO tabla_reservas
   SELECT 10, REF(v), REF(p), DATE '2026-09-20', 16, 'PENDIENTE'
     FROM tabla_viajeros v, tabla_paquetes_turisticos p
    WHERE v.id_viajero = 1 AND p.id_paquete = 3;

SELECT r.id_reserva,
       DEREF(r.ref_viajero).nombre AS viajero,
       DEREF(r.ref_paquete).destino AS destino,
       r.num_pasajeros,
       r.estado_reserva,
       pkg_turismovive.fn_cupos_disponibles(3) AS cupos_paquete_3
  FROM tabla_reservas r
 WHERE DEREF(r.ref_paquete).id_paquete = 3
 ORDER BY r.id_reserva;

-- ---------------------------------------------------------------------
-- >>> CAPTURA B - CASO DE VIOLACION (intento deliberado de sobreventa)
-- V1. El paquete 3 esta lleno (20/20). Se intenta reservar 1 pasajero
--     mas con DML directo. 21 > 20.
--     Esperado: ORA-20014 [TRG_RESGUARDO_RESERVAS] Sobreventa en el
--     paquete 3 ... + ORA-04088 (error durante la ejecucion del trigger)
-- ---------------------------------------------------------------------
INSERT INTO tabla_reservas
   SELECT 11, REF(v), REF(p), DATE '2026-09-21', 1, 'PENDIENTE'
     FROM tabla_viajeros v, tabla_paquetes_turisticos p
    WHERE v.id_viajero = 2 AND p.id_paquete = 3;

-- La reserva 11 NO existe: el trigger revirtio la sentencia. Esperado: 0.
SELECT COUNT(*) AS existe_reserva_11
  FROM tabla_reservas
 WHERE id_reserva = 11;

-- ---------------------------------------------------------------------
-- T2. EXITO: cancelar la reserva 10 libera cupo (CANCELADA no consume).
--     Esperado: cupos paquete 3 = 16.
-- T3. EXITO: nueva reserva 12 de 10 pasajeros -> 4 + 10 = 14 <= 20.
-- ---------------------------------------------------------------------
UPDATE tabla_reservas
   SET estado_reserva = 'CANCELADA'
 WHERE id_reserva = 10;

INSERT INTO tabla_reservas
   SELECT 12, REF(v), REF(p), DATE '2026-09-21', 10, 'PENDIENTE'
     FROM tabla_viajeros v, tabla_paquetes_turisticos p
    WHERE v.id_viajero = 2 AND p.id_paquete = 3;

SELECT pkg_turismovive.fn_cupos_disponibles(3) AS cupos_paquete_3 FROM dual;  -- 6

-- ---------------------------------------------------------------------
-- V2 a V8: mas intentos deliberados de violar la regla. Cada bloque
-- captura el error POR NOMBRE con las excepciones de PKG_TURISMOVIVE,
-- aunque el que lo lanza es el trigger.
-- ---------------------------------------------------------------------

-- V2. Reactivar la reserva cancelada 10 (16 pax): 14 + 16 = 30 > 20.
--     Demuestra por que el trigger vigila tambien UPDATE del estado.
BEGIN
   UPDATE tabla_reservas
      SET estado_reserva = 'CONFIRMADA'
    WHERE id_reserva = 10;
   DBMS_OUTPUT.PUT_LINE('V2 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('V2 BLOQUEADA -> ' || SQLERRM);
END;
/

-- V3. Aumentar la reserva REAL 3 de 4 a 11 pasajeros: 10 + 11 = 21 > 20.
BEGIN
   UPDATE tabla_reservas
      SET num_pasajeros = 11
    WHERE id_reserva = 3;
   DBMS_OUTPUT.PUT_LINE('V3 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('V3 BLOQUEADA -> ' || SQLERRM);
END;
/

-- V4. UPDATE de VARIAS filas reales en una sola sentencia (+7 pasajeros
--     a las reservas 1, 2 y 3). Los paquetes 1 y 2 quedarian bien (9 y 8),
--     pero el paquete 3 llegaria a 11 + 10 = 21. Por ser AFTER STATEMENT,
--     se revierte la sentencia COMPLETA: ninguna de las 3 filas cambia.
BEGIN
   UPDATE tabla_reservas
      SET num_pasajeros = num_pasajeros + 7
    WHERE id_reserva IN (1, 2, 3);
   DBMS_OUTPUT.PUT_LINE('V4 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('V4 BLOQUEADA -> ' || SQLERRM);
END;
/

-- Esperado: reservas 1, 2, 3 conservan 2, 1 y 4 pasajeros.
SELECT id_reserva, num_pasajeros
  FROM tabla_reservas
 WHERE id_reserva IN (1, 2, 3)
 ORDER BY id_reserva;

-- V5. Fecha posterior al inicio del viaje: reserva REAL 2 (paquete 2
--     inicia el 01/10/2026) movida al 05/10/2026 -> ORA-20015.
BEGIN
   UPDATE tabla_reservas
      SET fecha_reserva = DATE '2026-10-05'
    WHERE id_reserva = 2;
   DBMS_OUTPUT.PUT_LINE('V5 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('V5 BLOQUEADA -> ' || SQLERRM);
END;
/

-- V6. Cero pasajeros en la reserva REAL 1 -> ORA-20015.
BEGIN
   UPDATE tabla_reservas
      SET num_pasajeros = 0
    WHERE id_reserva = 1;
   DBMS_OUTPUT.PUT_LINE('V6 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('V6 BLOQUEADA -> ' || SQLERRM);
END;
/

-- V7. Estado inventado en la reserva REAL 1 -> ORA-20015.
BEGIN
   UPDATE tabla_reservas
      SET estado_reserva = 'VOLANDO'
    WHERE id_reserva = 1;
   DBMS_OUTPUT.PUT_LINE('V7 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('V7 BLOQUEADA -> ' || SQLERRM);
END;
/

-- V8. Reserva sin viajero (REF nula) -> ORA-20011.
BEGIN
   INSERT INTO tabla_reservas
      SELECT 13, NULL, REF(p), DATE '2026-09-21', 1, 'PENDIENTE'
        FROM tabla_paquetes_turisticos p
       WHERE p.id_paquete = 2;
   DBMS_OUTPUT.PUT_LINE('V8 ERROR: el trigger debio bloquear la operacion');
EXCEPTION
   WHEN pkg_turismovive.e_viajero_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('V8 BLOQUEADA -> ' || SQLERRM);
END;
/

-- Revertir: los datos reales vuelven a su estado original.
ROLLBACK TO sp_pruebas_trigger;

-- Esperado: solo las reservas 1, 2, 3 del Avance 1.
SELECT id_reserva, num_pasajeros, estado_reserva
  FROM tabla_reservas
 ORDER BY id_reserva;


-- =====================================================================
-- 6. INTEGRACION: PAQUETE + TRIGGER AUTOMATIZANDO EL PROCESO DE RESERVA
--    SOBRE LOS DATOS REALES DEL AVANCE 1
-- =====================================================================
-- Escenario: temporada alta en la Amazonia (paquete real 3, cupo 20,
-- 4 pasajeros ya reservados por Marie Dubois en la reserva real 3).

SAVEPOINT sp_integracion;

-- 6.1 Carlos Fernandez (viajero real 2) reserva 16 pasajeros por el
--     paquete. El paquete valida y el trigger re-valida: 4 + 16 = 20.
BEGIN
   pkg_turismovive.sp_registrar_reserva(4, 2, 3, 16, DATE '2026-10-01');
   DBMS_OUTPUT.PUT_LINE('6.1 Cupos paquete 3 = ' ||
      pkg_turismovive.fn_cupos_disponibles(3));                     -- 0
END;
/

-- 6.2 Ana Gutierrez (viajera real 1) intenta 1 pasajero: el PAQUETE
--     lo rechaza antes de tocar la tabla (e_sin_cupo).
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 1, 3, 1, DATE '2026-10-01');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('6.2 Rechazada por el paquete -> ' || SQLERRM);
END;
/

-- 6.3 Marie Dubois cancela su reserva real 3: se liberan 4 cupos
--     automaticamente (CANCELADA no consume cupo).
BEGIN
   pkg_turismovive.sp_cambiar_estado_reserva(3, 'CANCELADA');
   DBMS_OUTPUT.PUT_LINE('6.3 Cupos paquete 3 = ' ||
      pkg_turismovive.fn_cupos_disponibles(3));                     -- 4
END;
/

-- 6.4 Ana vuelve a intentar con 4 pasajeros: ahora si hay cupo.
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 1, 3, 4, DATE '2026-10-02');
   DBMS_OUTPUT.PUT_LINE('6.4 Cupos paquete 3 = ' ||
      pkg_turismovive.fn_cupos_disponibles(3));                     -- 0
END;
/

-- 6.5 Se intenta reactivar la reserva 3 por el paquete.
--     sp_cambiar_estado_reserva NO revisa el cupo, pero el TRIGGER si:
--     4 + 16 + 4 = 24 > 20 -> se evita la sobreventa.
BEGIN
   pkg_turismovive.sp_cambiar_estado_reserva(3, 'CONFIRMADA');
   DBMS_OUTPUT.PUT_LINE('6.5 ERROR: se produjo una sobreventa');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('6.5 Bloqueada por el trigger -> ' || SQLERRM);
END;
/

-- 6.6 Reporte integrado: REF + DEREF (Avance 1) + funciones del paquete.
--     Esperado: reserva 3 CANCELADA, reservas 4 y 5 PENDIENTE;
--     totales 3146 / 868 / 6912 / 27648 / 6912.
SELECT r.id_reserva,
       DEREF(r.ref_viajero).nombre || ' ' ||
       DEREF(r.ref_viajero).apellido                   AS viajero,
       DEREF(r.ref_paquete).destino                    AS destino,
       r.num_pasajeros,
       r.estado_reserva,
       pkg_turismovive.fn_total_reserva(r.id_reserva)  AS total_reserva
  FROM tabla_reservas r
 ORDER BY r.id_reserva;

-- Esperado: cupos 18 / 19 / 0.
SELECT p.id_paquete,
       p.destino,
       pkg_turismovive.fn_precio_paquete(p.id_paquete)    AS precio_por_persona,
       pkg_turismovive.fn_cupos_disponibles(p.id_paquete) AS cupos_disponibles
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;

ROLLBACK TO sp_integracion;


-- =====================================================================
-- 7. VERIFICACION FINAL: DATOS DEL AVANCE 1 INTACTOS Y OBJETOS VALIDOS
-- =====================================================================

-- Esperado: 3 / 3 / 3.
SELECT (SELECT COUNT(*) FROM tabla_paquetes_turisticos) AS paquetes,
       (SELECT COUNT(*) FROM tabla_viajeros)            AS viajeros,
       (SELECT COUNT(*) FROM tabla_reservas)            AS reservas
  FROM dual;

-- Esperado: reservas 1-3 apuntando a viajeros 1-3 y paquetes 1-3,
--           con 2 / 1 / 4 pasajeros, sin REF dangling.
SELECT r.id_reserva,
       DEREF(r.ref_viajero).id_viajero AS id_viajero,
       DEREF(r.ref_paquete).id_paquete AS id_paquete,
       r.num_pasajeros,
       r.estado_reserva,
       CASE WHEN r.ref_viajero IS DANGLING OR r.ref_paquete IS DANGLING
            THEN 'DANGLING' ELSE 'VALIDA' END AS estado_ref
  FROM tabla_reservas r
 ORDER BY r.id_reserva;

-- Esperado: 18 / 19 / 16 (igual que en la seccion 1).
SELECT p.id_paquete,
       pkg_turismovive.fn_cupos_disponibles(p.id_paquete) AS cupos_disponibles
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;

-- Esperado: PACKAGE, PACKAGE BODY y TRIGGER en estado VALID.
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_TURISMOVIVE', 'TRG_RESGUARDO_RESERVAS')
 ORDER BY object_name, object_type;


-- =====================================================================
-- FIN DEL SCRIPT
-- =====================================================================

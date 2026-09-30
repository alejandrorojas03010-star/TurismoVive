-- =====================================================================
-- TURISMOVIVE - GRUPO 6
-- AVANCE 2 - SEMANA 1: PAQUETE PL/SQL PKG_TURISMOVIVE
-- =====================================================================
-- PRERREQUISITO: haber ejecutado TurismoVive.sql (Avance 1).
-- Este script NO crea ni modifica tipos ni tablas del Avance 1;
-- solo agrega el paquete PKG_TURISMOVIVE y lo prueba.
--
-- ORDEN:
-- 1. ESPECIFICACION DEL PAQUETE (CREATE OR REPLACE PACKAGE)
-- 2. CUERPO DEL PAQUETE (CREATE OR REPLACE PACKAGE BODY)
-- 3. VERIFICACION DE COMPILACION
-- 4. PRUEBAS - CAMINO NORMAL
-- 5. PRUEBAS - EXCEPCIONES
-- 6. RESTAURAR ESTADO DEL AVANCE 1 (ROLLBACK)
-- 7. VERIFICACION FINAL
--
-- Ejecutar como SCRIPT (F5) en Oracle SQL Developer.
-- =====================================================================

SET SERVEROUTPUT ON;


-- =====================================================================
-- 1. ESPECIFICACION DEL PAQUETE
-- =====================================================================
-- Agrupa la logica de negocio operativa de TurismoVive sobre la capa
-- transaccional del Avance 1: tarifas y comisiones, disponibilidad de
-- cupos, registro y ciclo de vida de reservas, y consulta de paquetes.

CREATE OR REPLACE PACKAGE pkg_turismovive AS

   -- Politica de cupo. El esquema del Avance 1 no almacena la capacidad
   -- de cada paquete y no debe modificarse, por lo que el paquete define
   -- el cupo maximo como constante (parametrizable en fn_cupos_disponibles).
   c_cupo_maximo CONSTANT NUMBER := 20;

   -- Excepciones propias. Se asocian a un codigo ORA-20xxx con
   -- PRAGMA EXCEPTION_INIT para que el cliente pueda capturarlas por
   -- nombre y ademas reciba un mensaje descriptivo.
   e_paquete_inexistente  EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_paquete_inexistente, -20010);

   e_viajero_inexistente  EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_viajero_inexistente, -20011);

   e_reserva_inexistente  EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_reserva_inexistente, -20012);

   e_reserva_duplicada    EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_reserva_duplicada, -20013);

   e_sin_cupo             EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_sin_cupo, -20014);

   e_dato_invalido        EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_dato_invalido, -20015);

   -- ------------------------------------------------------------------
   -- Tarifas y comisiones
   -- ------------------------------------------------------------------

   -- Precio final del paquete (precio base + actividades + comision),
   -- reutilizando el metodo calcula_precio_total() del tipo.
   FUNCTION fn_precio_paquete(p_id_paquete IN NUMBER) RETURN NUMBER;

   -- Importe total de una reserva: precio del paquete x num_pasajeros.
   FUNCTION fn_total_reserva(p_id_reserva IN NUMBER) RETURN NUMBER;

   -- ------------------------------------------------------------------
   -- Disponibilidad de cupos
   -- ------------------------------------------------------------------

   -- Cupos libres = cupo maximo - pasajeros en reservas PENDIENTE/CONFIRMADA.
   FUNCTION fn_cupos_disponibles(
      p_id_paquete  IN NUMBER,
      p_cupo_maximo IN NUMBER DEFAULT c_cupo_maximo
   ) RETURN NUMBER;

   -- ------------------------------------------------------------------
   -- Reservas
   -- ------------------------------------------------------------------

   -- Registra una reserva con REF a viajero y paquete, validando
   -- existencia, fecha, cantidad de pasajeros y cupo disponible.
   PROCEDURE sp_registrar_reserva(
      p_id_reserva    IN NUMBER,
      p_id_viajero    IN NUMBER,
      p_id_paquete    IN NUMBER,
      p_num_pasajeros IN NUMBER,
      p_fecha_reserva IN DATE     DEFAULT TRUNC(SYSDATE),
      p_estado        IN VARCHAR2 DEFAULT 'PENDIENTE'
   );

   -- Cambia el estado de una reserva (PENDIENTE / CONFIRMADA / CANCELADA).
   PROCEDURE sp_cambiar_estado_reserva(
      p_id_reserva   IN NUMBER,
      p_nuevo_estado IN VARCHAR2
   );

   -- ------------------------------------------------------------------
   -- Consulta de paquetes
   -- ------------------------------------------------------------------

   -- Muestra por DBMS_OUTPUT las actividades de la Nested Table del paquete.
   PROCEDURE sp_listar_actividades(p_id_paquete IN NUMBER);

   -- Devuelve por parametros OUT un resumen del paquete.
   PROCEDURE sp_resumen_paquete(
      p_id_paquete        IN  NUMBER,
      p_destino           OUT VARCHAR2,
      p_num_actividades   OUT NUMBER,
      p_precio_total      OUT NUMBER,
      p_cupos_disponibles OUT NUMBER
   );

END pkg_turismovive;
/

SHOW ERRORS PACKAGE pkg_turismovive;


-- =====================================================================
-- 2. CUERPO DEL PAQUETE
-- =====================================================================
-- Ningun procedimiento hace COMMIT: el control de la transaccion queda
-- en manos del cliente que invoca el paquete.

CREATE OR REPLACE PACKAGE BODY pkg_turismovive AS

   -- ------------------------------------------------------------------
   -- Subprogramas PRIVADOS (no aparecen en la especificacion)
   -- ------------------------------------------------------------------

   -- Recupera el objeto paquete o lanza e_paquete_inexistente.
   -- Centraliza el manejo de NO_DATA_FOUND para todo el paquete.
   FUNCTION obtener_paquete(p_id_paquete IN NUMBER)
      RETURN tipo_paquete_turistico
   IS
      v_paquete tipo_paquete_turistico;
   BEGIN
      SELECT VALUE(p)
        INTO v_paquete
        FROM tabla_paquetes_turisticos p
       WHERE p.id_paquete = p_id_paquete;

      RETURN v_paquete;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RAISE_APPLICATION_ERROR(-20010,
            'El paquete ' || p_id_paquete || ' no existe');
   END obtener_paquete;


   FUNCTION estado_valido(p_estado IN VARCHAR2) RETURN BOOLEAN IS
   BEGIN
      RETURN p_estado IS NOT NULL
         AND p_estado IN ('PENDIENTE', 'CONFIRMADA', 'CANCELADA');
   END estado_valido;


   -- ------------------------------------------------------------------
   -- fn_precio_paquete
   -- ------------------------------------------------------------------
   FUNCTION fn_precio_paquete(p_id_paquete IN NUMBER) RETURN NUMBER IS
      v_paquete tipo_paquete_turistico;
   BEGIN
      v_paquete := obtener_paquete(p_id_paquete);
      RETURN v_paquete.calcula_precio_total();
   END fn_precio_paquete;


   -- ------------------------------------------------------------------
   -- fn_total_reserva
   -- ------------------------------------------------------------------
   FUNCTION fn_total_reserva(p_id_reserva IN NUMBER) RETURN NUMBER IS
      v_paquete       tipo_paquete_turistico;
      v_num_pasajeros NUMBER;
   BEGIN
      SELECT DEREF(r.ref_paquete), r.num_pasajeros
        INTO v_paquete, v_num_pasajeros
        FROM tabla_reservas r
       WHERE r.id_reserva = p_id_reserva;

      -- DEREF de una REF dangling devuelve NULL (ver Avance 1, IS DANGLING)
      IF v_paquete IS NULL THEN
         RAISE_APPLICATION_ERROR(-20010,
            'La reserva ' || p_id_reserva ||
            ' apunta a un paquete inexistente (REF dangling)');
      END IF;

      RETURN ROUND(v_paquete.calcula_precio_total() * v_num_pasajeros, 2);
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RAISE_APPLICATION_ERROR(-20012,
            'La reserva ' || p_id_reserva || ' no existe');
   END fn_total_reserva;


   -- ------------------------------------------------------------------
   -- fn_cupos_disponibles
   -- ------------------------------------------------------------------
   FUNCTION fn_cupos_disponibles(
      p_id_paquete  IN NUMBER,
      p_cupo_maximo IN NUMBER DEFAULT c_cupo_maximo
   ) RETURN NUMBER IS
      v_paquete  tipo_paquete_turistico;
      v_ocupados NUMBER;
   BEGIN
      v_paquete := obtener_paquete(p_id_paquete);   -- valida existencia

      -- Solo las reservas activas consumen cupo.
      SELECT NVL(SUM(r.num_pasajeros), 0)
        INTO v_ocupados
        FROM tabla_reservas r
       WHERE DEREF(r.ref_paquete).id_paquete = p_id_paquete
         AND r.estado_reserva IN ('PENDIENTE', 'CONFIRMADA');

      RETURN GREATEST(p_cupo_maximo - v_ocupados, 0);
   END fn_cupos_disponibles;


   -- ------------------------------------------------------------------
   -- sp_registrar_reserva
   -- ------------------------------------------------------------------
   PROCEDURE sp_registrar_reserva(
      p_id_reserva    IN NUMBER,
      p_id_viajero    IN NUMBER,
      p_id_paquete    IN NUMBER,
      p_num_pasajeros IN NUMBER,
      p_fecha_reserva IN DATE     DEFAULT TRUNC(SYSDATE),
      p_estado        IN VARCHAR2 DEFAULT 'PENDIENTE'
   ) IS
      v_ref_viajero REF tipo_viajero;
      v_ref_paquete REF tipo_paquete_turistico;
      v_paquete     tipo_paquete_turistico;
      v_disponibles NUMBER;
      v_estado      VARCHAR2(50);
   BEGIN
      v_estado := UPPER(TRIM(p_estado));

      -- 1. Validacion de datos de entrada
      IF p_num_pasajeros IS NULL OR p_num_pasajeros <= 0 THEN
         RAISE_APPLICATION_ERROR(-20015,
            'El numero de pasajeros debe ser mayor a 0');
      END IF;

      IF NOT estado_valido(v_estado) THEN
         RAISE_APPLICATION_ERROR(-20015,
            'Estado de reserva no permitido: ' || p_estado);
      END IF;

      -- 2. Viajero: obtener su REF (NO_DATA_FOUND -> e_viajero_inexistente)
      BEGIN
         SELECT REF(v)
           INTO v_ref_viajero
           FROM tabla_viajeros v
          WHERE v.id_viajero = p_id_viajero;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011,
               'El viajero ' || p_id_viajero || ' no existe');
      END;

      -- 3. Paquete: obtener el objeto (valida existencia) y su REF
      v_paquete := obtener_paquete(p_id_paquete);

      SELECT REF(p)
        INTO v_ref_paquete
        FROM tabla_paquetes_turisticos p
       WHERE p.id_paquete = p_id_paquete;

      -- 4. Regla de negocio: la reserva debe hacerse antes de iniciar el viaje
      IF p_fecha_reserva IS NULL OR p_fecha_reserva >= v_paquete.fecha_inicio THEN
         RAISE_APPLICATION_ERROR(-20015,
            'La fecha de reserva (' ||
            NVL(TO_CHAR(p_fecha_reserva, 'DD/MM/YYYY'), 'NULL') ||
            ') debe ser anterior al inicio del paquete (' ||
            TO_CHAR(v_paquete.fecha_inicio, 'DD/MM/YYYY') || ')');
      END IF;

      -- 5. Regla de negocio: debe haber cupo suficiente
      v_disponibles := fn_cupos_disponibles(p_id_paquete);

      IF p_num_pasajeros > v_disponibles THEN
         RAISE_APPLICATION_ERROR(-20014,
            'Sin cupo: se solicitan ' || p_num_pasajeros ||
            ' pasajero(s) y solo quedan ' || v_disponibles ||
            ' en el paquete ' || p_id_paquete);
      END IF;

      -- 6. Insercion con las REF obtenidas (respeta SCOPE FOR de la tabla)
      INSERT INTO tabla_reservas VALUES (
         tipo_reserva(p_id_reserva, v_ref_viajero, v_ref_paquete,
                      p_fecha_reserva, p_num_pasajeros, v_estado)
      );

      DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' registrada: ' ||
         p_num_pasajeros || ' pasajero(s), paquete ' || p_id_paquete ||
         ', estado ' || v_estado);

   EXCEPTION
      -- Excepcion PREDEFINIDA: id_reserva repetido (PK de tabla_reservas)
      WHEN DUP_VAL_ON_INDEX THEN
         RAISE_APPLICATION_ERROR(-20013,
            'Ya existe una reserva con id ' || p_id_reserva);
   END sp_registrar_reserva;


   -- ------------------------------------------------------------------
   -- sp_cambiar_estado_reserva
   -- ------------------------------------------------------------------
   PROCEDURE sp_cambiar_estado_reserva(
      p_id_reserva   IN NUMBER,
      p_nuevo_estado IN VARCHAR2
   ) IS
      v_estado VARCHAR2(50);
   BEGIN
      v_estado := UPPER(TRIM(p_nuevo_estado));

      IF NOT estado_valido(v_estado) THEN
         RAISE_APPLICATION_ERROR(-20015,
            'Estado de reserva no permitido: ' || p_nuevo_estado);
      END IF;

      UPDATE tabla_reservas
         SET estado_reserva = v_estado
       WHERE id_reserva = p_id_reserva;

      IF SQL%ROWCOUNT = 0 THEN
         RAISE_APPLICATION_ERROR(-20012,
            'La reserva ' || p_id_reserva || ' no existe');
      END IF;

      DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva ||
                           ' cambiada a estado ' || v_estado);
   END sp_cambiar_estado_reserva;


   -- ------------------------------------------------------------------
   -- sp_listar_actividades
   -- ------------------------------------------------------------------
   PROCEDURE sp_listar_actividades(p_id_paquete IN NUMBER) IS
      v_paquete tipo_paquete_turistico;
      v_total   NUMBER := 0;
   BEGIN
      v_paquete := obtener_paquete(p_id_paquete);

      DBMS_OUTPUT.PUT_LINE('Actividades del paquete ' || p_id_paquete ||
                           ' - ' || v_paquete.destino || ':');

      -- TABLE() aplana la Nested Table en filas (igual que en el Avance 1)
      FOR a IN (SELECT act.id_actividad,
                       act.nombre_actividad,
                       act.duracion_horas,
                       act.costo_actividad
                  FROM tabla_paquetes_turisticos p,
                       TABLE(p.actividades) act
                 WHERE p.id_paquete = p_id_paquete
                 ORDER BY act.id_actividad)
      LOOP
         DBMS_OUTPUT.PUT_LINE('   [' || a.id_actividad || '] ' ||
            RPAD(a.nombre_actividad, 30) ||
            LPAD(a.duracion_horas, 3) || ' h   costo ' ||
            LPAD(a.costo_actividad, 6));
         v_total := v_total + a.costo_actividad;
      END LOOP;

      DBMS_OUTPUT.PUT_LINE('   Suma actividades: ' || v_total ||
                           ' | Precio base: ' || v_paquete.precio_base ||
                           ' | Comision: ' || v_paquete.comision_agente || '%' ||
                           ' | Precio total: ' || v_paquete.calcula_precio_total());
   END sp_listar_actividades;


   -- ------------------------------------------------------------------
   -- sp_resumen_paquete
   -- ------------------------------------------------------------------
   PROCEDURE sp_resumen_paquete(
      p_id_paquete        IN  NUMBER,
      p_destino           OUT VARCHAR2,
      p_num_actividades   OUT NUMBER,
      p_precio_total      OUT NUMBER,
      p_cupos_disponibles OUT NUMBER
   ) IS
      v_paquete tipo_paquete_turistico;
   BEGIN
      v_paquete := obtener_paquete(p_id_paquete);

      p_destino := v_paquete.destino;

      -- Evita COLLECTION_IS_NULL si la Nested Table es atomicamente nula
      IF v_paquete.actividades IS NULL THEN
         p_num_actividades := 0;
      ELSE
         p_num_actividades := v_paquete.actividades.COUNT;
      END IF;

      p_precio_total      := v_paquete.calcula_precio_total();
      p_cupos_disponibles := fn_cupos_disponibles(p_id_paquete);
   END sp_resumen_paquete;

END pkg_turismovive;
/

SHOW ERRORS PACKAGE BODY pkg_turismovive;


-- =====================================================================
-- 3. VERIFICACION DE COMPILACION
-- =====================================================================
-- Esperado: PACKAGE VALID y PACKAGE BODY VALID.

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_TURISMOVIVE'
 ORDER BY object_type;


-- =====================================================================
-- 4. PRUEBAS - CAMINO NORMAL
-- =====================================================================

-- 4.1 fn_precio_paquete debe coincidir con calcula_precio_total() del tipo.
--     Esperado: 1573, 868, 1728 (mismos valores del informe del Avance 1).

SELECT p.id_paquete,
       p.destino,
       p.calcula_precio_total()                        AS metodo_objeto,
       pkg_turismovive.fn_precio_paquete(p.id_paquete) AS fn_precio_paquete
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;


-- 4.2 fn_cupos_disponibles: cupo maximo 20 - pasajeros en reservas activas.
--     Datos del Avance 1: reserva 1 (2 pax, paq 1), reserva 2 (1 pax, paq 2),
--     reserva 3 (4 pax, paq 3).
--     Esperado: paquete 1 -> 18, paquete 2 -> 19, paquete 3 -> 16.

SELECT p.id_paquete,
       p.destino,
       pkg_turismovive.fn_cupos_disponibles(p.id_paquete) AS cupos_disponibles
  FROM tabla_paquetes_turisticos p
 ORDER BY p.id_paquete;


-- 4.3 sp_listar_actividades (Nested Table) y sp_resumen_paquete (parametros OUT)

DECLARE
   v_destino VARCHAR2(60);
   v_num_act NUMBER;
   v_precio  NUMBER;
   v_cupos   NUMBER;
BEGIN
   pkg_turismovive.sp_listar_actividades(2);

   DBMS_OUTPUT.PUT_LINE('---');

   pkg_turismovive.sp_resumen_paquete(
      p_id_paquete        => 1,
      p_destino           => v_destino,
      p_num_actividades   => v_num_act,
      p_precio_total      => v_precio,
      p_cupos_disponibles => v_cupos
   );

   DBMS_OUTPUT.PUT_LINE('Resumen paquete 1: ' || v_destino ||
      ' | actividades = ' || v_num_act ||
      ' | precio total = ' || v_precio ||
      ' | cupos disponibles = ' || v_cupos);
   -- Esperado: Salar de Uyuni | 2 | 1573 | 18
END;
/


-- 4.4 Flujo completo de una reserva nueva.
--     Se trabaja dentro de un SAVEPOINT para revertir al final y dejar
--     los datos del Avance 1 intactos (misma tecnica usada con IS DANGLING).

SAVEPOINT antes_pruebas;

BEGIN
   -- Marie Dubois (viajero 3) reserva 3 pasajeros en La Paz (paquete 2,
   -- inicia el 01/10/2026). La fecha de reserva es anterior al inicio.
   pkg_turismovive.sp_registrar_reserva(
      p_id_reserva    => 4,
      p_id_viajero    => 3,
      p_id_paquete    => 2,
      p_num_pasajeros => 3,
      p_fecha_reserva => DATE '2026-09-15'
   );

   DBMS_OUTPUT.PUT_LINE('Cupos paquete 2 tras registrar: ' ||
      pkg_turismovive.fn_cupos_disponibles(2));           -- esperado 16

   pkg_turismovive.sp_cambiar_estado_reserva(4, 'confirmada');

   DBMS_OUTPUT.PUT_LINE('Total a pagar reserva 4: ' ||
      pkg_turismovive.fn_total_reserva(4));                -- esperado 868 x 3 = 2604

   pkg_turismovive.sp_cambiar_estado_reserva(4, 'CANCELADA');

   DBMS_OUTPUT.PUT_LINE('Cupos paquete 2 tras cancelar: ' ||
      pkg_turismovive.fn_cupos_disponibles(2));           -- esperado 19
END;
/

-- La reserva creada por el paquete se navega con DEREF como en el Avance 1.

SELECT r.id_reserva,
       DEREF(r.ref_viajero).nombre || ' ' ||
       DEREF(r.ref_viajero).apellido        AS viajero,
       DEREF(r.ref_paquete).destino         AS destino,
       r.fecha_reserva,
       r.num_pasajeros,
       r.estado_reserva
  FROM tabla_reservas r
 WHERE r.id_reserva = 4;


-- =====================================================================
-- 5. PRUEBAS - EXCEPCIONES
-- =====================================================================
-- Cada bloque provoca un error controlado y lo captura POR NOMBRE usando
-- las excepciones publicas del paquete.

-- 5.1 Paquete inexistente (NO_DATA_FOUND -> e_paquete_inexistente)
BEGIN
   DBMS_OUTPUT.PUT_LINE(pkg_turismovive.fn_precio_paquete(99));
EXCEPTION
   WHEN pkg_turismovive.e_paquete_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('5.1 Capturada e_paquete_inexistente -> ' || SQLERRM);
END;
/

-- 5.2 Reserva duplicada (DUP_VAL_ON_INDEX -> e_reserva_duplicada)
--     La reserva 4 ya fue creada en 4.4 dentro de esta misma transaccion.
BEGIN
   pkg_turismovive.sp_registrar_reserva(4, 1, 1, 1, DATE '2026-09-01');
EXCEPTION
   WHEN pkg_turismovive.e_reserva_duplicada THEN
      DBMS_OUTPUT.PUT_LINE('5.2 Capturada e_reserva_duplicada -> ' || SQLERRM);
END;
/

-- 5.3 Sin cupo (e_sin_cupo): 30 pasajeros > 16 disponibles en el paquete 3
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 2, 3, 30, DATE '2026-10-01');
EXCEPTION
   WHEN pkg_turismovive.e_sin_cupo THEN
      DBMS_OUTPUT.PUT_LINE('5.3 Capturada e_sin_cupo -> ' || SQLERRM);
END;
/

-- 5.4 Fecha invalida (e_dato_invalido): reserva posterior al inicio del viaje
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 2, 2, 1, DATE '2026-10-15');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('5.4 Capturada e_dato_invalido -> ' || SQLERRM);
END;
/

-- 5.5 Pasajeros invalidos (e_dato_invalido)
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 2, 2, 0, DATE '2026-09-01');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('5.5 Capturada e_dato_invalido -> ' || SQLERRM);
END;
/

-- 5.6 Viajero inexistente (e_viajero_inexistente)
BEGIN
   pkg_turismovive.sp_registrar_reserva(5, 99, 2, 1, DATE '2026-09-01');
EXCEPTION
   WHEN pkg_turismovive.e_viajero_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('5.6 Capturada e_viajero_inexistente -> ' || SQLERRM);
END;
/

-- 5.7 Estado no permitido (e_dato_invalido)
BEGIN
   pkg_turismovive.sp_cambiar_estado_reserva(4, 'VOLANDO');
EXCEPTION
   WHEN pkg_turismovive.e_dato_invalido THEN
      DBMS_OUTPUT.PUT_LINE('5.7 Capturada e_dato_invalido -> ' || SQLERRM);
END;
/

-- 5.8 Reserva inexistente (e_reserva_inexistente)
BEGIN
   pkg_turismovive.sp_cambiar_estado_reserva(99, 'CANCELADA');
EXCEPTION
   WHEN pkg_turismovive.e_reserva_inexistente THEN
      DBMS_OUTPUT.PUT_LINE('5.8 Capturada e_reserva_inexistente -> ' || SQLERRM);
END;
/

-- 5.9 (Opcional) Excepcion NO capturada: asi la ve el cliente.
--     Descomentar para ver "ORA-20010: El paquete 99 no existe".
-- EXEC pkg_turismovive.sp_listar_actividades(99);


-- =====================================================================
-- 6. RESTAURAR ESTADO DEL AVANCE 1
-- =====================================================================

ROLLBACK TO antes_pruebas;

SELECT COUNT(*) AS total_reservas
  FROM tabla_reservas;
-- Esperado: 3 (la reserva 4 de prueba fue revertida).


-- =====================================================================
-- 7. VERIFICACION FINAL
-- =====================================================================

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_TURISMOVIVE'
 ORDER BY object_type;
-- Esperado: PACKAGE VALID, PACKAGE BODY VALID.

SELECT procedure_name
  FROM user_procedures
 WHERE object_name = 'PKG_TURISMOVIVE'
   AND procedure_name IS NOT NULL
 ORDER BY procedure_name;
-- Esperado: los 7 subprogramas publicos del paquete.


-- =====================================================================
-- FIN DEL SCRIPT
-- =====================================================================

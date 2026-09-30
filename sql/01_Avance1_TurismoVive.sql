-- =====================================================================
-- TURISMOVIVE - GRUPO 6
-- SCRIPT UNIFICADO COMPLETO PARA EXPOSICION Y DEFENSA
-- SEMANA 1 + SEMANA 2 + DEMOSTRACIONES DE INTEGRACION
-- =====================================================================
-- ORDEN:
-- 1. TIPO_ACTIVIDAD + ACTIVIDADES_NT
-- 2. TIPO_PAQUETE_TURISTICO + CONSTRUCTOR + METODO
-- 3. PRUEBA DEL CONSTRUCTOR Y METODO
-- 4. TABLA DE PAQUETES
-- 5. VIAJEROS
-- 6. RESERVAS CON REF
-- 7. DATOS DE PRUEBA
-- 8. CRUD
-- 9. TABLE()
-- 10. DEREF()
-- 11. IS DANGLING
-- 12. VERIFICACION FINAL
--
-- Ejecutar como SCRIPT (F5) en Oracle SQL Developer.
-- =====================================================================


-- =====================================================================
-- 1. TIPO DE OBJETO ANIDADO: TIPO_ACTIVIDAD
-- =====================================================================

CREATE OR REPLACE TYPE tipo_actividad AS OBJECT (
   id_actividad      NUMBER,
   nombre_actividad  VARCHAR2(80),
   duracion_horas    NUMBER,
   costo_actividad   NUMBER
);
/

CREATE OR REPLACE TYPE actividades_nt AS TABLE OF tipo_actividad;
/

DESCRIBE tipo_actividad;


-- =====================================================================
-- 2. TIPO DE OBJETO PRINCIPAL: TIPO_PAQUETE_TURISTICO
--    CONSTRUCTOR VALIDADO + METODO PROPIO
-- =====================================================================

CREATE OR REPLACE TYPE tipo_paquete_turistico AS OBJECT (
   id_paquete        NUMBER,
   destino           VARCHAR2(60),
   duracion_dias     NUMBER,
   fecha_inicio      DATE,
   fecha_fin         DATE,
   precio_base       NUMBER,
   comision_agente   NUMBER,
   actividades       actividades_nt,

   CONSTRUCTOR FUNCTION tipo_paquete_turistico(
      p_id_paquete       NUMBER,
      p_destino          VARCHAR2,
      p_duracion_dias    NUMBER,
      p_fecha_inicio     DATE,
      p_fecha_fin        DATE,
      p_precio_base      NUMBER,
      p_comision_agente  NUMBER,
      p_actividades      actividades_nt
   ) RETURN SELF AS RESULT,

   MEMBER FUNCTION calcula_precio_total RETURN NUMBER
);
/

CREATE OR REPLACE TYPE BODY tipo_paquete_turistico AS

   CONSTRUCTOR FUNCTION tipo_paquete_turistico(
      p_id_paquete       NUMBER,
      p_destino          VARCHAR2,
      p_duracion_dias    NUMBER,
      p_fecha_inicio     DATE,
      p_fecha_fin        DATE,
      p_precio_base      NUMBER,
      p_comision_agente  NUMBER,
      p_actividades      actividades_nt
   ) RETURN SELF AS RESULT IS
   BEGIN
      IF p_fecha_fin <= p_fecha_inicio THEN
         RAISE_APPLICATION_ERROR(
            -20001,
            'fecha_fin debe ser posterior a fecha_inicio'
         );
      END IF;

      id_paquete      := p_id_paquete;
      destino         := p_destino;
      duracion_dias   := p_duracion_dias;
      fecha_inicio    := p_fecha_inicio;
      fecha_fin       := p_fecha_fin;
      precio_base     := p_precio_base;
      comision_agente := p_comision_agente;
      actividades     := p_actividades;

      RETURN;
   END;

   MEMBER FUNCTION calcula_precio_total RETURN NUMBER IS
      v_total NUMBER := precio_base;
   BEGIN
      IF actividades IS NOT NULL THEN
         FOR i IN 1 .. actividades.COUNT LOOP
            v_total := v_total + actividades(i).costo_actividad;
         END LOOP;
      END IF;

      RETURN ROUND(
         v_total * (1 + comision_agente / 100),
         2
      );
   END;

END;
/

DESCRIBE tipo_paquete_turistico;


-- =====================================================================
-- 3. PRUEBA RAPIDA DEL CONSTRUCTOR Y DEL METODO
-- =====================================================================

SET SERVEROUTPUT ON;

DECLARE
   v_paquete tipo_paquete_turistico;
BEGIN
   v_paquete := tipo_paquete_turistico(
      1,
      'Salar de Uyuni',
      3,
      DATE '2026-09-10',
      DATE '2026-09-13',
      1200,
      10,
      actividades_nt(
         tipo_actividad(
            1,
            'Tour Salar al amanecer',
            6,
            150
         ),
         tipo_actividad(
            2,
            'Visita Isla Incahuasi',
            4,
            80
         )
      )
   );

   DBMS_OUTPUT.PUT_LINE('Destino: ' || v_paquete.destino);
   DBMS_OUTPUT.PUT_LINE(
      'Precio total: ' || v_paquete.calcula_precio_total()
   );
END;
/

-- =====================================================================
-- A PARTIR DE AQUI CONTINUA LA PARTE DE SEMANA 2
-- =====================================================================

-- =====================================================================
-- 4. TABLA DE OBJETOS PRINCIPAL: PAQUETES TURISTICOS
-- =====================================================================
-- TIPO_PAQUETE_TURISTICO contiene la Nested Table ACTIVIDADES.
-- Por eso indicamos donde se almacenara fisicamente la coleccion.

CREATE TABLE tabla_paquetes_turisticos OF tipo_paquete_turistico (
   id_paquete PRIMARY KEY
)
NESTED TABLE actividades STORE AS actividades_paquetes_tab;

DESCRIBE tabla_paquetes_turisticos;


-- =====================================================================
-- 5. TIPO Y TABLA DE VIAJEROS
-- =====================================================================

CREATE OR REPLACE TYPE tipo_viajero AS OBJECT (
   id_viajero      NUMBER,
   nombre          VARCHAR2(50),
   apellido        VARCHAR2(50),
   email           VARCHAR2(80),
   nacionalidad    VARCHAR2(40),
   telefono        VARCHAR2(20)
);
/

CREATE TABLE tabla_viajeros OF tipo_viajero (
   id_viajero PRIMARY KEY
);

DESCRIBE tipo_viajero;
DESCRIBE tabla_viajeros;


-- =====================================================================
-- 6. TIPO Y TABLA DE RESERVAS CON REF
-- =====================================================================
-- Cada reserva tiene:
--   REF -> viajero
--   REF -> paquete turistico
-- SCOPE restringe cada referencia a su tabla correspondiente.

CREATE OR REPLACE TYPE tipo_reserva AS OBJECT (
   id_reserva       NUMBER,
   ref_viajero      REF tipo_viajero,
   ref_paquete      REF tipo_paquete_turistico,
   fecha_reserva    DATE,
   num_pasajeros    NUMBER,
   estado_reserva   VARCHAR2(20)
);
/

CREATE TABLE tabla_reservas OF tipo_reserva (
   id_reserva PRIMARY KEY,
   SCOPE FOR (ref_viajero) IS tabla_viajeros,
   SCOPE FOR (ref_paquete) IS tabla_paquetes_turisticos
);

DESCRIBE tipo_reserva;
DESCRIBE tabla_reservas;


-- =====================================================================
-- 7. DATOS DE PRUEBA
-- =====================================================================

-- ---------------------- PAQUETES ----------------------

INSERT INTO tabla_paquetes_turisticos VALUES (
   tipo_paquete_turistico(
      1, 'Salar de Uyuni', 3,
      DATE '2026-09-10', DATE '2026-09-13',
      1200, 10,
      actividades_nt(
         tipo_actividad(1, 'Tour Salar al amanecer', 6, 150),
         tipo_actividad(2, 'Visita Isla Incahuasi', 4, 80)
      )
   )
);

INSERT INTO tabla_paquetes_turisticos VALUES (
   tipo_paquete_turistico(
      2, 'La Paz - Valle de la Luna', 2,
      DATE '2026-10-01', DATE '2026-10-03',
      650, 12,
      actividades_nt(
         tipo_actividad(3, 'City tour La Paz', 5, 60),
         tipo_actividad(4, 'Teleferico panoramico', 2, 25),
         tipo_actividad(5, 'Valle de la Luna', 3, 40)
      )
   )
);

INSERT INTO tabla_paquetes_turisticos VALUES (
   tipo_paquete_turistico(
      3, 'Amazonia Boliviana - Rurrenabaque', 4,
      DATE '2026-11-05', DATE '2026-11-09',
      1500, 8,
      actividades_nt(
         tipo_actividad(6, 'Navegacion por el rio Beni', 5, 100)
      )
   )
);

COMMIT;


-- ---------------------- VIAJEROS ----------------------

INSERT INTO tabla_viajeros VALUES (
   tipo_viajero(1, 'Ana', 'Gutierrez',
      'ana.gutierrez@email.com', 'Boliviana', '70011111')
);

INSERT INTO tabla_viajeros VALUES (
   tipo_viajero(2, 'Carlos', 'Fernandez',
      'carlos.fernandez@email.com', 'Argentina', '70022222')
);

INSERT INTO tabla_viajeros VALUES (
   tipo_viajero(3, 'Marie', 'Dubois',
      'marie.dubois@email.com', 'Francesa', '70033333')
);

COMMIT;


-- ---------------------- RESERVAS CON REF ----------------------
-- REF(v) obtiene la referencia al objeto viajero.
-- REF(p) obtiene la referencia al objeto paquete.

INSERT INTO tabla_reservas
   SELECT 1, REF(v), REF(p), DATE '2026-08-20', 2, 'CONFIRMADA'
   FROM tabla_viajeros v, tabla_paquetes_turisticos p
   WHERE v.id_viajero = 1 AND p.id_paquete = 1;

INSERT INTO tabla_reservas
   SELECT 2, REF(v), REF(p), DATE '2026-08-22', 1, 'CONFIRMADA'
   FROM tabla_viajeros v, tabla_paquetes_turisticos p
   WHERE v.id_viajero = 2 AND p.id_paquete = 2;

INSERT INTO tabla_reservas
   SELECT 3, REF(v), REF(p), DATE '2026-08-25', 4, 'PENDIENTE'
   FROM tabla_viajeros v, tabla_paquetes_turisticos p
   WHERE v.id_viajero = 3 AND p.id_paquete = 3;

COMMIT;


-- =====================================================================
-- 8. COMPROBACION DE DATOS
-- =====================================================================

SELECT COUNT(*) AS total_paquetes
FROM tabla_paquetes_turisticos;

SELECT COUNT(*) AS total_viajeros
FROM tabla_viajeros;

SELECT COUNT(*) AS total_reservas
FROM tabla_reservas;


-- =====================================================================
-- 9. CRUD - CREATE
-- =====================================================================
-- Creamos un paquete de prueba utilizando el constructor y la coleccion.

INSERT INTO tabla_paquetes_turisticos VALUES (
   tipo_paquete_turistico(
      4, 'Tiwanaku - Arqueologia', 1,
      DATE '2026-12-01', DATE '2026-12-02',
      300, 15,
      actividades_nt(
         tipo_actividad(7, 'Visita ruinas de Tiwanaku', 4, 50)
      )
   )
);

COMMIT;


-- =====================================================================
-- 10. CRUD - READ
-- =====================================================================
-- READ 1: leer paquetes y utilizar el metodo propio.

SELECT p.id_paquete,
       p.destino,
       p.calcula_precio_total() AS precio_total
FROM tabla_paquetes_turisticos p
ORDER BY p.id_paquete;


-- READ 2: navegar desde RESERVAS hacia los objetos con DEREF.

SELECT r.id_reserva,
       DEREF(r.ref_viajero).nombre || ' ' ||
       DEREF(r.ref_viajero).apellido AS viajero,
       DEREF(r.ref_paquete).destino AS destino,
       r.estado_reserva
FROM tabla_reservas r
ORDER BY r.id_reserva;


-- =====================================================================
-- 11. CRUD - UPDATE
-- =====================================================================

UPDATE tabla_reservas
SET estado_reserva = 'CONFIRMADA'
WHERE id_reserva = 3;

COMMIT;

SELECT id_reserva,
       estado_reserva
FROM tabla_reservas
WHERE id_reserva = 3;


-- =====================================================================
-- 12. CRUD - DELETE
-- =====================================================================
-- Eliminamos solamente el paquete de prueba creado en CREATE.

DELETE FROM tabla_paquetes_turisticos
WHERE id_paquete = 4;

COMMIT;

SELECT id_paquete
FROM tabla_paquetes_turisticos
WHERE id_paquete = 4;
-- No debe devolver filas.


-- =====================================================================
-- 13. TABLE() - APLANAR LA COLECCION ANIDADA
-- =====================================================================
-- TABLE() convierte los elementos de la Nested Table en filas consultables.

SELECT p.id_paquete,
       p.destino,
       a.nombre_actividad,
       a.costo_actividad
FROM tabla_paquetes_turisticos p,
     TABLE(p.actividades) a
ORDER BY p.id_paquete;


-- =====================================================================
-- 14. DEREF - NAVEGAR POR LAS REFERENCIAS
-- =====================================================================
-- DEREF permite acceder al objeto apuntado por cada REF.

SELECT r.id_reserva,
       DEREF(r.ref_viajero).nombre AS nombre_viajero,
       DEREF(r.ref_paquete).destino AS destino_paquete,
       r.num_pasajeros,
       r.estado_reserva
FROM tabla_reservas r
ORDER BY r.id_reserva;


-- =====================================================================
-- 15. IS DANGLING - ESTADO INICIAL
-- =====================================================================
-- Al inicio no deberia existir ninguna referencia colgada.

SELECT id_reserva
FROM tabla_reservas r
WHERE r.ref_viajero IS DANGLING;
-- Resultado esperado: 0 filas.


-- =====================================================================
-- 16. DEMOSTRACION DE IS DANGLING
-- =====================================================================
-- Eliminamos temporalmente un viajero que esta siendo referenciado.
-- La referencia de la reserva queda dangling.
--
-- IMPORTANTE:
-- Para una defensa se recomienda usar SAVEPOINT + ROLLBACK, para no
-- dejar la base de datos inconsistente.

SAVEPOINT prueba_dangling;

DELETE FROM tabla_viajeros
WHERE id_viajero = 2;

SELECT id_reserva,
       CASE
          WHEN ref_viajero IS DANGLING THEN 'DANGLING'
          ELSE 'VALIDA'
       END AS estado_ref
FROM tabla_reservas
ORDER BY id_reserva;

SELECT id_reserva
FROM tabla_reservas r
WHERE r.ref_viajero IS DANGLING;
-- Durante la prueba debe aparecer la reserva 2.


-- Restauramos el estado original.

ROLLBACK TO prueba_dangling;

SELECT id_reserva
FROM tabla_reservas r
WHERE r.ref_viajero IS DANGLING;
-- Despues del ROLLBACK: 0 filas.


-- =====================================================================
-- 17. VERIFICACION FINAL
-- =====================================================================

SELECT r.id_reserva,
       DEREF(r.ref_viajero).id_viajero AS id_viajero,
       DEREF(r.ref_viajero).nombre AS viajero,
       DEREF(r.ref_paquete).id_paquete AS id_paquete,
       DEREF(r.ref_paquete).destino AS destino
FROM tabla_reservas r
ORDER BY r.id_reserva;


-- =====================================================================
-- FIN DEL SCRIPT
-- =====================================================================

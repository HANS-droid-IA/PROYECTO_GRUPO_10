-- =====================================================================
-- 03 - Programación PL/SQL (equivalente a PL/pgSQL del modelo PostgreSQL)
-- Elementos propios de Oracle que se demuestran:
--   * PACKAGE (especificación + cuerpo): agrupa funciones/procedimientos con
--     estado y encapsulamiento. PostgreSQL no tiene paquetes (se usan schemas).
--   * %TYPE / %ROWTYPE, excepciones con nombre y RAISE_APPLICATION_ERROR
--     (PG: RAISE EXCEPTION ... USING ERRCODE)
--   * PRAGMA AUTONOMOUS_TRANSACTION: el log de errores persiste aunque la
--     transacción principal haga ROLLBACK (PG no lo soporta de forma nativa;
--     requiere dblink o una extensión).
--   * Trigger de fila con :NEW / :OLD (PG: función trigger + NEW/OLD)
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- Procedimiento autónomo de bitácora de errores
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_log_error (p_origen IN VARCHAR2, p_mensaje IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO log_error (origen, mensaje) VALUES (p_origen, SUBSTR(p_mensaje, 1, 4000));
    COMMIT;   -- confirma SOLO esta transacción autónoma
END sp_log_error;
/

-- ---------------------------------------------------------------------
-- Especificación del paquete
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_tracking AS
    e_transicion_invalida EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_transicion_invalida, -20010);

    FUNCTION fn_calcular_tarifa (
        p_id_servicio       IN tipo_servicio.id_servicio%TYPE,
        p_id_region_origen  IN region.id_region%TYPE,
        p_id_region_destino IN region.id_region%TYPE,
        p_peso_kg           IN NUMBER,
        p_fecha             IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER;

    FUNCTION fn_estado_sla (
        p_id_envio IN envio.id_envio%TYPE,
        p_corte    IN TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP
    ) RETURN VARCHAR2;

    PROCEDURE sp_registrar_escaneo (
        p_nro_tracking IN envio.nro_tracking%TYPE,
        p_tipo_evento  IN evento_tracking.tipo_evento%TYPE,
        p_id_hub       IN hub.id_hub%TYPE,
        p_observacion  IN VARCHAR2 DEFAULT NULL,
        p_fecha_hora   IN TIMESTAMP WITH TIME ZONE DEFAULT NULL
    );
END pkg_tracking;
/

-- ---------------------------------------------------------------------
-- Cuerpo del paquete
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_tracking AS

    FUNCTION fn_calcular_tarifa (
        p_id_servicio       IN tipo_servicio.id_servicio%TYPE,
        p_id_region_origen  IN region.id_region%TYPE,
        p_id_region_destino IN region.id_region%TYPE,
        p_peso_kg           IN NUMBER,
        p_fecha             IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER IS
        v_peso_max tipo_servicio.peso_max_kg%TYPE;
        v_tarifa   tarifa%ROWTYPE;
    BEGIN
        IF p_peso_kg IS NULL OR p_peso_kg <= 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'El peso debe ser mayor a cero');
        END IF;

        SELECT peso_max_kg INTO v_peso_max FROM tipo_servicio WHERE id_servicio = p_id_servicio;
        IF p_peso_kg > v_peso_max THEN
            RAISE_APPLICATION_ERROR(-20002, 'Peso ' || p_peso_kg || ' kg excede el máximo del servicio (' || v_peso_max || ' kg)');
        END IF;

        SELECT * INTO v_tarifa
          FROM tarifa
         WHERE id_servicio = p_id_servicio
           AND id_region_origen = p_id_region_origen
           AND id_region_destino = p_id_region_destino
           AND vigente_desde <= p_fecha
           AND (vigente_hasta IS NULL OR vigente_hasta > p_fecha)
         ORDER BY vigente_desde DESC
         FETCH FIRST 1 ROW ONLY;

        RETURN ROUND(v_tarifa.precio_base + GREATEST(0, CEIL(p_peso_kg - 1)) * v_tarifa.precio_kg_adicional, 2);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003, 'No existe servicio o tarifa vigente para los parámetros indicados');
    END fn_calcular_tarifa;

    FUNCTION fn_estado_sla (
        p_id_envio IN envio.id_envio%TYPE,
        p_corte    IN TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP
    ) RETURN VARCHAR2 IS
        v_e envio%ROWTYPE;
    BEGIN
        SELECT * INTO v_e FROM envio WHERE id_envio = p_id_envio;
        IF v_e.estado_actual = 'ENTREGADO' THEN
            RETURN CASE WHEN v_e.fecha_entrega <= v_e.fecha_compromiso THEN 'ENTREGADO_A_TIEMPO' ELSE 'ENTREGADO_CON_RETRASO' END;
        ELSIF v_e.estado_actual = 'DEVUELTO' THEN
            RETURN 'DEVUELTO';
        ELSIF p_corte > v_e.fecha_compromiso THEN
            RETURN 'VENCIDO';
        ELSIF v_e.fecha_compromiso - p_corte <= INTERVAL '6' HOUR THEN
            RETURN 'EN_RIESGO';
        END IF;
        RETURN 'EN_PLAZO';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END fn_estado_sla;

    PROCEDURE sp_registrar_escaneo (
        p_nro_tracking IN envio.nro_tracking%TYPE,
        p_tipo_evento  IN evento_tracking.tipo_evento%TYPE,
        p_id_hub       IN hub.id_hub%TYPE,
        p_observacion  IN VARCHAR2 DEFAULT NULL,
        p_fecha_hora   IN TIMESTAMP WITH TIME ZONE DEFAULT NULL
    ) IS
        v_envio      envio%ROWTYPE;
        v_permitidos VARCHAR2(100);
    BEGIN
        -- FOR UPDATE bloquea la fila del envío (igual que en PostgreSQL)
        SELECT * INTO v_envio FROM envio WHERE nro_tracking = p_nro_tracking FOR UPDATE;

        v_permitidos := CASE v_envio.estado_actual
            WHEN 'REGISTRADO'      THEN ',ADMISION,'
            WHEN 'ADMITIDO'        THEN ',SALIDA_HUB,'
            WHEN 'EN_HUB'          THEN ',CLASIFICACION,SALIDA_HUB,EN_REPARTO,'
            WHEN 'EN_TRANSITO'     THEN ',LLEGADA_HUB,'
            WHEN 'EN_REPARTO'      THEN ',ENTREGA,INTENTO_FALLIDO,'
            WHEN 'INTENTO_FALLIDO' THEN ',EN_REPARTO,DEVOLUCION,'
            ELSE ',' END;

        IF INSTR(v_permitidos, ',' || p_tipo_evento || ',') = 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Transición inválida: envío ' || p_nro_tracking || ' en estado '
                                    || v_envio.estado_actual || ' no admite evento ' || p_tipo_evento);
        END IF;

        INSERT INTO evento_tracking (id_envio, tipo_evento, id_hub, fecha_hora, observacion)
        VALUES (v_envio.id_envio, p_tipo_evento, p_id_hub, NVL(p_fecha_hora, SYSTIMESTAMP), p_observacion);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            sp_log_error('pkg_tracking.sp_registrar_escaneo', 'Tracking inexistente: ' || p_nro_tracking);
            RAISE_APPLICATION_ERROR(-20011, 'Tracking ' || p_nro_tracking || ' no existe');
        WHEN e_transicion_invalida THEN
            sp_log_error('pkg_tracking.sp_registrar_escaneo', SQLERRM);
            RAISE;
    END sp_registrar_escaneo;

END pkg_tracking;
/

-- ---------------------------------------------------------------------
-- Trigger: cada evento actualiza el estado del envío
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_evento_actualiza_estado
AFTER INSERT ON evento_tracking
FOR EACH ROW
DECLARE
    v_estado envio.estado_actual%TYPE;
BEGIN
    v_estado := CASE :NEW.tipo_evento
        WHEN 'ADMISION'        THEN 'ADMITIDO'
        WHEN 'LLEGADA_HUB'     THEN 'EN_HUB'
        WHEN 'CLASIFICACION'   THEN 'EN_HUB'
        WHEN 'SALIDA_HUB'      THEN 'EN_TRANSITO'
        WHEN 'EN_REPARTO'      THEN 'EN_REPARTO'
        WHEN 'INTENTO_FALLIDO' THEN 'INTENTO_FALLIDO'
        WHEN 'ENTREGA'         THEN 'ENTREGADO'
        WHEN 'DEVOLUCION'      THEN 'DEVUELTO'
    END;

    UPDATE envio
       SET estado_actual = v_estado,
           fecha_entrega = CASE WHEN v_estado = 'ENTREGADO' THEN :NEW.fecha_hora ELSE fecha_entrega END
     WHERE id_envio = :NEW.id_envio;
END;
/

SHOW ERRORS
SELECT object_name, object_type, status FROM user_objects
 WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'TRIGGER') ORDER BY object_type, object_name;

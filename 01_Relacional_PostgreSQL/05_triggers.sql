-- =====================================================================
-- 05 - Triggers
-- =====================================================================

-- ---------------------------------------------------------------------
-- T1. Cada evento de tracking actualiza el estado actual del envío
--     (desnormalización controlada) y su fecha de entrega.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.trg_fn_evento_actualiza_estado()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = operacion, pg_temp AS
$$
DECLARE
    v_estado VARCHAR(15);
BEGIN
    v_estado := CASE NEW.tipo_evento
        WHEN 'ADMISION'        THEN 'ADMITIDO'
        WHEN 'LLEGADA_HUB'     THEN 'EN_HUB'
        WHEN 'CLASIFICACION'   THEN 'EN_HUB'
        WHEN 'SALIDA_HUB'      THEN 'EN_TRANSITO'
        WHEN 'EN_REPARTO'      THEN 'EN_REPARTO'
        WHEN 'INTENTO_FALLIDO' THEN 'INTENTO_FALLIDO'
        WHEN 'ENTREGA'         THEN 'ENTREGADO'
        WHEN 'DEVOLUCION'      THEN 'DEVUELTO'
    END;

    UPDATE operacion.envio
       SET estado_actual = v_estado,
           fecha_entrega = CASE WHEN v_estado = 'ENTREGADO' THEN NEW.fecha_hora ELSE fecha_entrega END
     WHERE id_envio = NEW.id_envio
       AND estado_actual IS DISTINCT FROM v_estado;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_evento_actualiza_estado
AFTER INSERT ON operacion.evento_tracking
FOR EACH ROW EXECUTE FUNCTION operacion.trg_fn_evento_actualiza_estado();

-- ---------------------------------------------------------------------
-- T2. Auditoría: registra cada cambio de estado del envío.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.trg_fn_log_estado_envio()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = auditoria, pg_temp AS
$$
BEGIN
    INSERT INTO auditoria.log_estado_envio (id_envio, estado_anterior, estado_nuevo, usuario_bd)
    VALUES (NEW.id_envio, CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado_actual END, NEW.estado_actual, session_user);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_estado_envio
AFTER INSERT OR UPDATE OF estado_actual ON operacion.envio
FOR EACH ROW
WHEN (pg_trigger_depth() < 5)
EXECUTE FUNCTION auditoria.trg_fn_log_estado_envio();

-- ---------------------------------------------------------------------
-- T3. Valida que el medio de transporte del despacho coincida con la
--     modalidad de la ruta (regla entre tablas que un CHECK no puede expresar):
--       ruta AEREO     -> nro_vuelo obligatorio
--       ruta TERRESTRE -> vehículo propio, activo, con base en el hub de origen
--                         o en la agencia/hub del otro extremo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.trg_fn_validar_despacho()
RETURNS TRIGGER LANGUAGE plpgsql AS
$$
DECLARE
    v_ruta maestro.ruta%ROWTYPE;
    v_veh  maestro.vehiculo%ROWTYPE;
BEGIN
    SELECT * INTO v_ruta FROM maestro.ruta WHERE id_ruta = NEW.id_ruta;
    IF NOT v_ruta.activa THEN
        RAISE EXCEPTION 'La ruta % está inactiva', NEW.id_ruta;
    END IF;

    IF v_ruta.modalidad = 'AEREO' AND NEW.nro_vuelo IS NULL THEN
        RAISE EXCEPTION 'Un despacho por ruta aérea requiere número de vuelo';
    ELSIF v_ruta.modalidad = 'TERRESTRE' THEN
        IF NEW.id_vehiculo IS NULL THEN
            RAISE EXCEPTION 'Un despacho por ruta terrestre requiere vehículo';
        END IF;
        SELECT * INTO v_veh FROM maestro.vehiculo WHERE id_vehiculo = NEW.id_vehiculo;
        IF NOT v_veh.activo THEN
            RAISE EXCEPTION 'El vehículo % está inactivo', v_veh.placa;
        END IF;
        IF v_veh.id_hub_base NOT IN (v_ruta.id_hub_origen, v_ruta.id_hub_destino) THEN
            RAISE EXCEPTION 'El vehículo % no pertenece a ningún extremo de la ruta', v_veh.placa;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_despacho
BEFORE INSERT OR UPDATE OF id_ruta, id_vehiculo, nro_vuelo ON operacion.despacho
FOR EACH ROW EXECUTE FUNCTION operacion.trg_fn_validar_despacho();

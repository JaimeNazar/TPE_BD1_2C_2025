
-- Dudas: 
--habria que validar email?
        


CREATE OR REPLACE FUNCTION insert_suscripcion()
RETURNS TRIGGER AS $$
DECLARE
    v_last_sub       suscripcion%ROWTYPE;
    v_new_id         INTEGER;
    v_new_inicio     DATE;
    v_new_fin        DATE;
    v_fecha_limite   DATE;
    v_tipo           VARCHAR(20);  -- 'nueva' o 'renovacion'
BEGIN
    -- 1) Buscar última suscripción del cliente (me parece que con ORDER BY y LIMIT 1 es suficiente. que tal?)
    SELECT *
    INTO v_last_sub
    FROM suscripcion
    WHERE cliente_email = NEW.cliente_email
    ORDER BY fecha_fin DESC
    LIMIT 1; --para que tome una sola 

    IF NOT FOUND THEN
        -- CASO A: No tiene suscripciones , entonces nueva
        v_tipo := 'nueva';
        v_new_inicio := NEW.fecha;

        IF NEW.modalidad = 'mensual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 month' - INTERVAL '1 day';
        ELSIF NEW.modalidad = 'anual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 year' - INTERVAL '1 day';
        ELSE
            RAISE EXCEPTION 'Modalidad inválida: %', NEW.modalidad;
        END IF;

    ELSE
        -- Se deberia modularizar!
        -- CASO B: Tiene suscripciones previas
        v_fecha_limite := v_last_sub.fecha_fin - INTERVAL '30 days';

        -- B1: pago demasiado anticipado
        IF NEW.fecha < v_fecha_limite THEN
            RAISE EXCEPTION 'Pago demasiado anticipado para renovar. Solo se permite dentro de los 30 días previos al vencimiento. (pago=%, fin_anterior=%)', 
                NEW.fecha, v_last_sub.fecha_fin;
        END IF;

        -- B2: ¿Renovación o nueva?
        IF NEW.fecha <= v_last_sub.fecha_fin THEN
            -- Renovación
            v_tipo := 'renovacion';
            v_new_inicio := v_last_sub.fecha_fin + INTERVAL '1 day';
        ELSE
            -- Nueva (pago después del vencimiento)
            v_tipo := 'nueva';
            v_new_inicio := NEW.fecha;
        END IF;

        -- B3: calcular fecha_fin
        IF NEW.modalidad = 'mensual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 month' - INTERVAL '1 day';
        ELSIF NEW.modalidad = 'anual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 year' - INTERVAL '1 day';
        ELSE
            RAISE EXCEPTION 'Modalidad inválida: %', NEW.modalidad;
        END IF;
    END IF;

    -- 5) Validar superposición de períodos (podria ser una funcion aparte)
    PERFORM 1  -- descarto el resultado :)
    FROM suscripcion s
    WHERE s.cliente_email = NEW.cliente_email
      AND NOT (v_new_fin < s.fecha_inicio OR v_new_inicio > s.fecha_fin);

    IF FOUND THEN
        RAISE EXCEPTION 'No se permite crear una suscripción superpuesta para el cliente %. Periodo nuevo: % a %', 
            NEW.cliente_email, v_new_inicio, v_new_fin;
    END IF;

    -- 6) Insertar suscripción
    INSERT INTO suscripcion (cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
    VALUES (NEW.cliente_email, v_tipo, NEW.modalidad, v_new_inicio, v_new_fin)
    RETURNING id INTO v_new_id;

    -- 7) Asociar pago a esa suscripción
    NEW.suscripcion_id := v_new_id; -- actualizar el pago entrante

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;




CREATE TRIGGER insertPagoTrigger
BEFORE
INSERT ON pago
FOR EACH ROW --una vez por cada fila insertada
EXECUTE PROCEDURE insert_suscripcion();
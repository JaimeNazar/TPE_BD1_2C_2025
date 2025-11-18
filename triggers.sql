
-- Dudas: 
--habria que validar email?

-- Funcion auxiliar de validacion de tipo suscripcion, lanza excepcion en caso de que sea invalida
-- Retorna verdadero si es nueva suscripcion, falso en caso contrario(renovacion)
CREATE OR REPLACE FUNCTION nueva_suscripcion(fecha_pago pago.fecha%TYPE, email pago.cliente_email%TYPE) 
RETURNS BOOLEAN
AS $$
DECLARE
    v_last_sub       suscripcion%ROWTYPE;
    v_fecha_limite   suscripcion.fecha_fin%TYPE;

BEGIN   
    -- Buscar, si existe, la ultima suscripcion vigente
    SELECT *
    INTO v_last_sub
    FROM suscripcion
    WHERE cliente_email = email
    ORDER BY fecha_fin DESC
    LIMIT 1; --para que tome una sola 

    IF NOT FOUND THEN
        RETURN TRUE;
    END IF;

    -- Validar si la suscripcion es valida para el pago
    -- Chequear si tiene suscripciones previas
    v_fecha_limite := v_last_sub.fecha_fin - INTERVAL '30 days';

    -- Caso A: Pago demasiado anticipado
    IF fecha_pago < v_fecha_limite THEN
        RAISE EXCEPTION 'Pago demasiado anticipado para renovar. Solo se permite dentro de los 30 días previos al vencimiento. (pago=%, fin_anterior=%)', 
            fecha_pago, v_last_sub.fecha_fin;
    END IF;

    -- Caso B: ¿Renovación o nueva?
    IF fecha_pago <= v_last_sub.fecha_fin THEN
        -- Renovación
        RETURN FALSE;
    ELSE
        -- Nueva (pago después del vencimiento)
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Funcion auxiliar de validacion de superposicion, lanza excepcion en caso de que sea invalida
CREATE OR REPLACE FUNCTION superposicion_suscripcion(inicio suscripcion.fecha_inicio%TYPE, fin suscripcion.fecha_fin%TYPE, email pago.cliente_email%TYPE) 
RETURNS VOID
AS $$

BEGIN   
    PERFORM 1  -- descarto el resultado :)
    FROM suscripcion s
    WHERE s.cliente_email = email
      AND NOT (fin < s.fecha_inicio OR inicio > s.fecha_fin);

    IF FOUND THEN
        RAISE EXCEPTION 'No se permite crear una suscripción superpuesta para el cliente %. Periodo nuevo: % a %', 
            email, inicio, fin;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_suscripcion()
RETURNS TRIGGER AS $$
DECLARE
    v_last_sub       suscripcion%ROWTYPE;
    v_new_id         suscripcion.id%TYPE;
    v_new_inicio     suscripcion.fecha_inicio%TYPE;
    v_new_fin        suscripcion.fecha_fin%TYPE;
    v_fecha_limite   suscripcion.fecha_fin%TYPE;
    v_tipo   suscripcion.tipo%TYPE;  -- 'nueva' o 'renovacion'
BEGIN

    IF nueva_suscripcion(NEW.fecha, NEW.cliente_email) THEN
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
        -- Renovación
        v_tipo := 'renovacion';
        v_new_inicio := v_last_sub.fecha_fin + INTERVAL '1 day';

        -- B3: calcular fecha_fin
        IF NEW.modalidad = 'mensual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 month' - INTERVAL '1 day';
        ELSIF NEW.modalidad = 'anual' THEN
            v_new_fin := v_new_inicio + INTERVAL '1 year' - INTERVAL '1 day';
        ELSE
            RAISE EXCEPTION 'Modalidad inválida: %', NEW.modalidad;
        END IF;
    END IF;

    -- Validar superposición de períodos (podria ser una funcion aparte)
    PERFORM superposicion_suscripcion(v_new_inicio, v_new_fin, NEW.cliente_email);

    -- Insertar suscripción
    INSERT INTO suscripcion (cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
    VALUES (NEW.cliente_email, v_tipo, NEW.modalidad, v_new_inicio, v_new_fin)
    RETURNING id INTO v_new_id;

    -- Asociar pago a esa suscripción
    NEW.suscripcion_id := v_new_id; -- actualizar el pago entrante

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;




CREATE TRIGGER insertPagoTrigger
BEFORE
INSERT ON pago
FOR EACH ROW --una vez por cada fila insertada
EXECUTE PROCEDURE insert_suscripcion();
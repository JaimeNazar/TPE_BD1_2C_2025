
-- Funcion auxiliar de validacion de fechas, lanza excepcion en caso de que sea invalida
-- Retorna verdadero si es nueva suscripcion, falso en caso contrario
CREATE OR REPLACE FUNCTION nueva_suscripcion(fecha_pago pago.fecha%TYPE, email pago.cliente_email%TYPE) 
RETURNS BOOLEAN
AS $$
DECLARE
cant_suscripcion INTEGER;
suscripcion_actual suscripcion%ROWTYPE;

BEGIN   
    -- Buscar, si existe, la ultima subcripcion vigente
    -- TODO: Chequear si esta bien

    -- Verificar unicidad
    SELECT COUNT(*) INTO cant_suscripcion
    FROM suscripcion
    WHERE cliente_email = new.cliente_email AND fecha_fin >= ALL(
        SELECT fecha_fin
        FROM suscripcion
        WHERE cliente_email = new.cliente_email
    );

    IF cant_suscripcion > 1 THEN
        RAISE EXCEPTION 'ESTADO INVALIDO, NO PUEDE HABER MAS DE UNA SUSCRIPCION VIGENTE A LA VEZ';
    ELSIF cant_suscripcion = 0 THEN
        RETURN TRUE;
    END IF;

    -- Si estoy aca se que hay una sola subcripcion(cuidado que PostgreSQL agarraria el primero si hubiera mas de uno)
    SELECT * INTO suscripcion_actual
    FROM suscripcion
    WHERE cliente_email = new.cliente_email AND fecha_fin >= ALL(
        SELECT fecha_fin
        FROM suscripcion
        WHERE cliente_email = new.cliente_email
    );

    -- Chequear si se trata de una suscripcion nueva
    IF fecha_pago > suscripcion_actual.fecha_fin THEN
        -- Suscripcion nueva
        RETURN TRUE;
    ELSIF EXTRACT(DAY FROM AGE(suscripcion_actual.fecha_fin, fecha_pago)) > 30 THEN
        -- TODO: Chequear si la cota esta bien
        RETURN TRUE;
    END IF;
    
    -- Si llegue aca estonces es una renovacion
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Trigger de insercion para subcripcion
CREATE OR REPLACE FUNCTION insert_suscripcion() 
RETURNS TRIGGER
AS $$
DECLARE
fecha_inicio suscripcion.fecha_inicio%TYPE;
fecha_fin suscripcion.fecha_fin%TYPE;
tipo suscripcion.tipo%TYPE;
id suscripcion.id%TYPE;

BEGIN   
    -- Primero obtener la fecha de inicio
    fecha_inicio := new.fecha;

    -- Chequear que no sea muy temprano o se este superponiendo con otra suscripcion
    IF nueva_suscripcion(fecha_inicio, new.cliente_email) THEN 
        RAISE 'NUEVA SUB';
    END IF;

    -- Calcular fecha fin en base a la modalidad
    CASE
        WHEN lower(new.modalidad) = 'mensual' THEN fecha_fin := fecha_inicio + interval '1 MONTH';
        WHEN lower(new.modalidad) = 'anual' THEN fecha_fin := fecha_inicio + interval '1 YEAR';
    END CASE;


    RETURN new;
END;
$$ LANGUAGE plpgsql;

-- Debe ser BEFORE para permitir rechazar el pago
CREATE TRIGGER insertPagoTrigger
BEFORE
INSERT ON pago
EXECUTE PROCEDURE insert_suscripcion();
-- === TABLAS ===

-- Drop si existen las tablas
DROP TABLE IF EXISTS pago;
DROP TABLE IF EXISTS suscripcion;

-- Definicion de tablas
CREATE TABLE suscripcion (
    id SERIAL PRIMARY KEY,
    cliente_email VARCHAR(255) NOT NULL CHECK (cliente_email ~* '^\S+@\S+\.\S+$'),
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('nueva', 'renovacion')),
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual', 'anual')),
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL
);

CREATE TABLE pago (
    fecha DATE NOT NULL,
    medio_pago VARCHAR(50) NOT NULL CHECK (medio_pago IN ('tarjeta_credito', 'tarjeta_debito', 'transferencia', 'efectivo', 'mercadopago')),
    id_transaccion VARCHAR(255) PRIMARY KEY,
    cliente_email VARCHAR(255) NOT NULL CHECK (cliente_email ~* '^\S+@\S+\.\S+$'),
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual', 'anual')),
    monto DECIMAL(10, 2) NOT NULL CHECK (monto > 0),
    suscripcion_id INTEGER REFERENCES suscripcion(id)
);

-- === TRIGGERS Y FUNCIONES

DROP TRIGGER IF EXISTS insertPagoTrigger ON pago;
DROP FUNCTION IF EXISTS nueva_suscripcion;
DROP FUNCTION IF EXISTS superposicion_suscripcion;
DROP FUNCTION IF EXISTS insert_suscripcion;
DROP FUNCTION IF EXISTS consolidar_cliente;

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
    IF fecha_pago < v_fecha_limite AND fecha_pago >= v_last_sub.fecha_inicio THEN
        RAISE EXCEPTION 'Pago demasiado anticipado para renovar. Solo se permite dentro de los 30 días previos al vencimiento. (pago=%, fin_anterior=%)', 
            fecha_pago, v_last_sub.fecha_fin;
    END IF;

    -- Caso B: ¿Renovación o nueva?
    IF fecha_pago <= v_last_sub.fecha_fin AND fecha_pago >= v_last_sub.fecha_inicio THEN
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
    v_last_sub_fin   suscripcion.fecha_fin%TYPE;
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
        SELECT fecha_fin
        INTO v_last_sub_fin
        FROM suscripcion
        WHERE cliente_email = NEW.cliente_email
        ORDER BY fecha_fin DESC
        LIMIT 1; --para que tome una sola 
    
        -- Renovación
        v_tipo := 'renovacion';
        v_new_inicio := v_last_sub_fin + INTERVAL '1 day';

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

-- Funcion que devuelve informacion de cliente
CREATE OR REPLACE FUNCTION consolidar_cliente(email suscripcion.cliente_email%TYPE) 
RETURNS VOID AS $$
DECLARE
    -- Variables para recorrer los datos (el cursor implícito)
    r RECORD;
    
    periodo_num INTEGER := 1;
    periodo_inicio DATE; 
    periodo_fin DATE;
    ultimo_fin DATE := NULL;
    
    meses_periodo INTEGER := 0;
    meses_total INTEGER := 0;
    meses_actual INTEGER := 0;
    
    primera_vez BOOLEAN := TRUE;
    
    texto_modalidad VARCHAR;
BEGIN
    --Si no existe un cliente con ese email, termina la ejecucion
    IF NOT EXISTS (SELECT 1 FROM suscripcion WHERE cliente_email = email) THEN
        RAISE NOTICE 'El cliente % no tiene suscripciones registradas.', email;
        RETURN;
    END IF;

    RAISE NOTICE '== Cliente: % ==', email;
    RAISE NOTICE 'Periodo #%', periodo_num;

    -- Recorrer todas las los pagos y subscripciones del cliente
    FOR r IN 
        SELECT s.id, s.tipo, s.modalidad, s.fecha_inicio, s.fecha_fin,
               p.fecha AS fecha_pago, p.medio_pago
        FROM suscripcion s
        JOIN pago p ON s.id = p.suscripcion_id
        WHERE s.cliente_email = email
        ORDER BY s.fecha_inicio ASC
    LOOP

        -- Dependiendo de la modalidad, definimos cantidad de meses y texto
        IF r.modalidad = 'mensual' THEN
            meses_actual := 1;
            texto_modalidad := 'MENSUAL (1 mes)';
        ELSE
            meses_actual := 12;
            texto_modalidad := 'ANUAL (12 meses)';
        END IF;

        -- Verificar que no haya un hueco entre sus subscripciones, si lo hay, cerrar periodo
        IF (NOT primera_vez) AND (r.fecha_inicio > (ultimo_fin + INTERVAL '1 day')) THEN
            
            RAISE NOTICE '(Fin del periodo #%: % a %) | Total periodo: % %', 
             periodo_num, periodo_inicio, ultimo_fin,
             meses_periodo, CASE WHEN meses_periodo = 1 THEN 'mes' ELSE 'meses' END;
            
            RAISE NOTICE 'PERIODO DE BAJA';
            
            -- Resetear variables para el proximo periodo
            periodo_num := periodo_num + 1;
            meses_periodo := 0;
            periodo_inicio := r.fecha_inicio;
            
            RAISE NOTICE 'Periodo #%', periodo_num;
        END IF;

        
        IF primera_vez THEN
            periodo_inicio := r.fecha_inicio;
            primera_vez := FALSE;
        END IF;

        -- Imprimir detalle de la subscripcion
        RAISE NOTICE '% % | pago=% medio=% | cobertura=% a %',
                     UPPER(r.tipo), 
                     texto_modalidad,
                     r.fecha_pago, 
                     r.medio_pago,
                     r.fecha_inicio, 
                     r.fecha_fin;

        meses_periodo := meses_periodo + meses_actual;
        meses_total := meses_total + meses_actual;
        
        -- Guardar ultimo fin de subscripcion
        IF ultimo_fin IS NULL OR r.fecha_fin > ultimo_fin THEN
            periodo_fin := r.fecha_fin;
            ultimo_fin := r.fecha_fin;
        END IF;

    END LOOP;

    -- Terminar el ultimo periodo y mostrar total acumulado
    RAISE NOTICE '(Fin del periodo #%: % a %) | Total periodo: % %', 
             periodo_num, periodo_inicio, ultimo_fin,
             meses_periodo, CASE WHEN meses_periodo = 1 THEN 'mes' ELSE 'meses' END;

    RAISE NOTICE '== Total acumulado: % % ==', meses_total, CASE WHEN meses_total = 1 THEN 'mes' ELSE 'meses' END;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION consolidar_cliente(email VARCHAR) 
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

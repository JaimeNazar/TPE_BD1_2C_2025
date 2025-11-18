#!/bin/bash

if ( $# != 1 ); then
    echo "Usage: ./create_tables_and_triggers.sh [username]"
fi

# Insertar todas las tuplas
\copy pago from pagos.csv header delimiter ',' csv;

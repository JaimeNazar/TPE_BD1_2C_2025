#!/bin/bash

if ( $# != 1 ); then
    echo "Usage: ./create_tables_and_triggers.sh [username]"
fi

# Crear las tablas
psql -h bd1.it.itba.edu.ar -U $1 -f tables.sql PROOF

# Crear los triggers
psql -h bd1.it.itba.edu.ar -U $1 -f triggers.sql PROOF

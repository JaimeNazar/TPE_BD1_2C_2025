#!/bin/bash

# Crear las tablas
psql -h bd1.it.itba.edu.ar -U $USER -f tables.sql PROOF

# Crear los triggers
psql -h bd1.it.itba.edu.ar -U $USER -f triggers.sql PROOF

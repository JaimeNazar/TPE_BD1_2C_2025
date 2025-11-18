#!/bin/bash

# Insertar todas las tuplas
\copy pago from pagos.csv header delimiter ',' csv;


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
    id_transaccion VARCHAR(255) PRIMARY KEY,
    fecha DATE NOT NULL,
    medio_pago VARCHAR(50) NOT NULL CHECK (medio_pago IN ('tarjeta_credito', 'tarjeta_debito', 'transferencia', 'efectivo', 'mercadopago')),
    cliente_email VARCHAR(255) NOT NULL CHECK (cliente_email ~* '^\S+@\S+\.\S+$'),
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual', 'anual')),
    monto DECIMAL(10, 2) NOT NULL CHECK (monto > 0),
    suscripcion_id INTEGER REFERENCES suscripcion(id)
);

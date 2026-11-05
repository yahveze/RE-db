-- V018: fuentes externas y separación explícita de Sandbox y Production.
-- Las referencias previas se conservan como Mercado Libre Production.
ALTER TABLE repuesto_guardado ADD COLUMN entorno_proveedor text NOT NULL DEFAULT 'production';
ALTER TABLE repuesto_guardado
  DROP CONSTRAINT ck_repuesto_guardado_proveedor,
  DROP CONSTRAINT ck_repuesto_guardado_id_externo,
  DROP CONSTRAINT ck_repuesto_guardado_enlace,
  ADD CONSTRAINT ck_repuesto_guardado_proveedor CHECK (proveedor IN ('mercadolibre','ebay')),
  ADD CONSTRAINT ck_repuesto_guardado_entorno CHECK (
    (proveedor='mercadolibre' AND entorno_proveedor='production') OR
    (proveedor='ebay' AND entorno_proveedor IN ('sandbox','production') AND tipo_referencia='listing')),
  ADD CONSTRAINT ck_repuesto_guardado_id_externo CHECK (
    (proveedor='mercadolibre' AND id_externo ~ '^MLC[0-9]{5,20}$') OR
    (proveedor='ebay' AND id_externo ~ '^v1[|][0-9]{1,20}[|][0-9]{1,20}$')),
  ADD CONSTRAINT ck_repuesto_guardado_enlace CHECK (enlace IS NULL OR (
    length(enlace) BETWEEN 1 AND 2000 AND (
      (proveedor='mercadolibre' AND enlace ~ '^https://([a-z0-9-]+[.])*mercadolibre[.]cl/') OR
      (proveedor='ebay' AND entorno_proveedor='sandbox' AND enlace ~ '^https://([a-z0-9-]+[.])*sandbox[.]ebay[.]com(:443)?/itm/[^[:space:]#]+$') OR
      (proveedor='ebay' AND entorno_proveedor='production' AND enlace ~ '^https://([a-z0-9-]+[.])*ebay[.]com(:443)?/itm/[^[:space:]#]+$'
        AND enlace !~ '^https://([a-z0-9-]+[.])*sandbox[.]ebay[.]com(:443)?/')
    )
  ));
COMMENT ON COLUMN repuesto_guardado.entorno_proveedor IS 'Entorno de la referencia externa: production o sandbox. Sandbox nunca acredita una oferta comercial real.';
COMMENT ON COLUMN repuesto_guardado.proveedor IS 'Origen de la referencia: mercadolibre o ebay; fijado por el recibo validado del servidor.';
COMMENT ON COLUMN repuesto_guardado.id_externo IS 'Identificador del proveedor: MLC para Mercado Libre, itemId REST v1|item|variation para eBay.';
COMMENT ON COLUMN repuesto_guardado.enlace IS 'Enlace HTTPS de publicación validado por proveedor y entorno; nulo para catálogo técnico de Mercado Libre.';
GRANT INSERT(entorno_proveedor) ON repuesto_guardado TO taller_admin,taller_mecanico;

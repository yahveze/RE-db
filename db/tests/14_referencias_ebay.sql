-- Referencias sintéticas; toda la prueba termina con ROLLBACK.
\ir incluir/inicio.sql
\echo '### 14 Referencias eBay por proveedor y entorno'
SELECT d.id AS dtc_eb,c.id AS comp_eb FROM dtc_catalogo d JOIN dtc_componente dc ON dc.dtc_id=d.id
 JOIN componente_repuesto c ON c.id=dc.componente_id WHERE d.codigo='P0301' ORDER BY c.id LIMIT 1 \gset
\ir incluir/rol_mecanico_1.sql
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:mec_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|110590963673|0','listing','https://sandbox.ebay.com/itm/110590963673',gen_random_uuid(),repeat('a',64)) RETURNING id_publico AS ebay_id,id AS ebay_interno \gset
\set prueba 'EBAY-01 mecánico guarda una referencia Sandbox visible con su entorno'
SELECT count(*)=1 AND bool_and(entorno_proveedor='sandbox') AS ok FROM repuesto_guardado WHERE id_publico=:'ebay_id'::uuid \gset
\ir incluir/afirmar.sql
\ir incluir/rol_admin_1.sql
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','production','v1|110590963673|0','listing','https://www.ebay.com/itm/110590963673',gen_random_uuid(),repeat('b',64));
\set prueba 'EBAY-02 propietario distingue el mismo identificador en dos entornos'
SELECT count(*)=2 AND count(DISTINCT entorno_proveedor)=2 AS ok FROM repuesto_guardado WHERE proveedor='ebay' AND id_externo='v1|110590963673|0' \gset
\ir incluir/afirmar.sql
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,id_externo,tipo_referencia,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'mercadolibre','MLC12345678','catalog_product',gen_random_uuid(),repeat('c',64)) RETURNING id_publico AS meli_id \gset
\set prueba 'EBAY-03 contrato previo de Mercado Libre conserva Production por defecto'
SELECT entorno_proveedor='production' AND enlace IS NULL AS ok FROM repuesto_guardado WHERE id_publico=:'meli_id'::uuid \gset
\ir incluir/afirmar.sql

\set prueba 'EBAY-04 rechaza ID de Mercado Libre en eBay'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','MLC12345678','listing','https://sandbox.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-05 rechaza ID de eBay en Mercado Libre'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'mercadolibre','production','v1|123|0','listing','https://articulo.mercadolibre.cl/producto',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-06 Sandbox no acepta un enlace de Production'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|123|0','listing','https://www.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-07 Production no acepta un enlace de Sandbox'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','production','v1|123|0','listing','https://sandbox.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-08 rechaza dominio falsificado'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|123|0','listing','https://sandbox.ebay.com.attacker.example/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-09 rechaza credenciales en enlace'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|123|0','listing','https://user:password@sandbox.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-10 rechaza HTTP'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|123|0','listing','http://sandbox.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-11 no presenta catálogo técnico como eBay'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','sandbox','v1|123|0','catalog_product',NULL,gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-12 Mercado Libre no puede marcarse Sandbox'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'mercadolibre','sandbox','MLC12345678','catalog_product',NULL,gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-13 rechaza entornos desconocidos'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'ebay','qa','v1|123|0','listing','https://sandbox.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-14 rechaza un proveedor desconocido'
\set esperado 23514
INSERT INTO repuesto_guardado(taller_id,usuario_id,dtc_id,componente_id,proveedor,entorno_proveedor,id_externo,tipo_referencia,enlace,clave_idempotencia,hash_solicitud)
VALUES(:taller_1,:admin_1,:dtc_eb,:comp_eb,'other','production','v1|123|0','listing','https://www.ebay.com/itm/123',gen_random_uuid(),repeat('d',64));
\ir incluir/error.sql

\set prueba 'EBAY-15 referencias guardadas son inmutables para roles de trabajo'
\set esperado 42501
UPDATE repuesto_guardado SET entorno_proveedor='production' WHERE id_publico=:'ebay_id'::uuid;
\ir incluir/error.sql
\ir incluir/rol_admin_2.sql
\set prueba 'EBAY-16 otro taller no ve la referencia eBay'
SELECT NOT EXISTS(SELECT 1 FROM repuesto_guardado WHERE id_publico=:'ebay_id'::uuid) AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
\set prueba 'EBAY-17 cada selección genera auditoría'
SELECT count(*)=1 AS ok FROM auditoria_operacion WHERE tabla='repuesto_guardado' AND registro_id=:ebay_interno \gset
\ir incluir/afirmar.sql
\set prueba 'EBAY-18 RLS forzada conserva las políticas originales'
SELECT c.relrowsecurity AND c.relforcerowsecurity AND (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='repuesto_guardado')=2 AS ok FROM pg_class c WHERE c.oid='public.repuesto_guardado'::regclass \gset
\ir incluir/afirmar.sql
ROLLBACK;

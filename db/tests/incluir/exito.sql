-- La sentencia anterior debia terminar sin error.
SELECT :'SQLSTATE' = '00000' AS ok, :'SQLSTATE' AS obtenido \gset
\if :ok
  \echo 'PASS |' :prueba
\else
  \echo 'FAIL |' :prueba '-> SQLSTATE' :obtenido
\endif
\set ok f

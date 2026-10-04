-- La sentencia anterior debia terminar sin error y afectar/devolver :esperado filas.
SELECT :'SQLSTATE' = '00000' AND :ROW_COUNT = :esperado AS ok, :ROW_COUNT AS obtenido \gset
\if :ok
  \echo 'PASS |' :prueba
\else
  \echo 'FAIL |' :prueba '-> filas esperadas' :esperado ', obtenidas' :obtenido
\endif
\set ok f

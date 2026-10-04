-- La sentencia anterior debia fallar con el SQLSTATE :esperado.
SELECT :'SQLSTATE' = :'esperado' AS ok, :'SQLSTATE' AS obtenido \gset
\if :ok
  \echo 'PASS | [E]' :prueba '->' :esperado
\else
  \echo 'FAIL | [E]' :prueba '-> esperado' :esperado ', obtenido' :obtenido
\endif
\set ok f

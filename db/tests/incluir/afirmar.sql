-- Afirmacion: la consulta anterior dejo el booleano :ok con \gset.
-- Si esa consulta fallo, :ok conserva 'f' y la prueba es FAIL.
\if :ok
  \echo 'PASS |' :prueba
\else
  \echo 'FAIL |' :prueba
\endif
\set ok f

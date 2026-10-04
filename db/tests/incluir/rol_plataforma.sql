-- Superusuario (plataforma): prepara datos y verifica sin RLS.
RESET ROLE;
RESET SESSION AUTHORIZATION;
EXECUTE ctx('', '', '', '') \gset ctx_

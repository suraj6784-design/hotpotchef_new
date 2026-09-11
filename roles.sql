
SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '15s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '15s';

GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin";

RESET ALL;

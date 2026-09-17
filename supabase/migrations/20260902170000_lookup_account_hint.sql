-- P1-2: forgot-email lookup must not be an account oracle.

CREATE TABLE IF NOT EXISTS public.email_lookup_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bucket text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS email_lookup_attempts_bucket_time_idx
  ON public.email_lookup_attempts (bucket, created_at DESC);

ALTER TABLE public.email_lookup_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.email_lookup_attempts FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.email_lookup_attempts TO service_role;

CREATE OR REPLACE FUNCTION public.lookup_account_hint(p_query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text := btrim(COALESCE(p_query, ''));
  v_norm text;
  v_digits text;
  v_ip text;
  v_headers json;
  v_ip_hits int;
  v_q_hits int;
  v_email text;
  v_local text;
  v_domain text;
  v_hint text := NULL;
BEGIN
  -- Same envelope whether we found a row, missed, or hit the rate limit.
  IF length(v_raw) < 3 OR length(v_raw) > 80
     OR v_raw ~ '[,();%]' THEN
    RETURN jsonb_build_object('success', true, 'hint', NULL);
  END IF;

  v_norm := lower(regexp_replace(v_raw, '\s+', ' ', 'g'));
  v_digits := regexp_replace(v_raw, '\D', '', 'g');

  BEGIN
    v_headers := current_setting('request.headers', true)::json;
    v_ip := nullif(btrim(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1)), '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;
  v_ip := COALESCE(v_ip, inet_client_addr()::text, 'unknown');

  DELETE FROM email_lookup_attempts WHERE created_at < now() - interval '24 hours';

  INSERT INTO email_lookup_attempts (bucket) VALUES ('ip:' || v_ip), ('q:' || md5(v_norm));

  SELECT count(*) INTO v_ip_hits
  FROM email_lookup_attempts
  WHERE bucket = 'ip:' || v_ip AND created_at > now() - interval '15 minutes';

  SELECT count(*) INTO v_q_hits
  FROM email_lookup_attempts
  WHERE bucket = 'q:' || md5(v_norm) AND created_at > now() - interval '15 minutes';

  IF v_ip_hits > 8 OR v_q_hits > 5 THEN
    RETURN jsonb_build_object('success', true, 'hint', NULL);
  END IF;

  IF length(v_digits) >= 10 THEN
    SELECT u.email INTO v_email
    FROM users u
    WHERE regexp_replace(COALESCE(u.phone, ''), '\D', '', 'g') LIKE '%' || right(v_digits, 10)
    LIMIT 1;
  ELSE
    SELECT u.email INTO v_email
    FROM users u
    WHERE lower(btrim(COALESCE(u.name, ''))) = v_norm
       OR lower(btrim(COALESCE(u.full_name, ''))) = v_norm
    LIMIT 1;
  END IF;

  IF v_email IS NOT NULL AND position('@' in v_email) > 1 THEN
    v_local := split_part(v_email, '@', 1);
    v_domain := split_part(v_email, '@', 2);
    v_hint := left(v_local, 1) || '***@' || v_domain;
  END IF;

  RETURN jsonb_build_object('success', true, 'hint', v_hint);
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_account_hint(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_account_hint(text) TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "Public read users" ON public.users;

DROP POLICY IF EXISTS "Authenticated can read user directory" ON public.users;
CREATE POLICY "Authenticated can read user directory"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (true);

GRANT SELECT ON public.users TO authenticated;
REVOKE SELECT ON public.users FROM anon;

NOTIFY pgrst, 'reload schema';

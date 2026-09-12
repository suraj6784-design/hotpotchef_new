-- Scanned FSSAI card fields for chefs + ops review, and expiry reminders.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS fssai_legal_name text,
  ADD COLUMN IF NOT EXISTS fssai_registered_address text,
  ADD COLUMN IF NOT EXISTS fssai_valid_until date,
  ADD COLUMN IF NOT EXISTS fssai_expiry_notified_on date;

COMMENT ON COLUMN public.users.fssai_legal_name IS
  'Name printed on the FSSAI licence, scanned from the uploaded certificate.';
COMMENT ON COLUMN public.users.fssai_registered_address IS
  'Address printed on the FSSAI licence, scanned from the uploaded certificate.';
COMMENT ON COLUMN public.users.fssai_valid_until IS
  'Valid-upto date scanned from the FSSAI certificate (calendar date, Asia/Kolkata).';

CREATE OR REPLACE FUNCTION public.notify_ops_fssai_submission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text;
  v_body text;
BEGIN
  IF NEW.fssai_proof_url IS NULL OR btrim(NEW.fssai_proof_url) = '' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.fssai_proof_url IS NOT DISTINCT FROM OLD.fssai_proof_url
     AND NEW.fssai_number IS NOT DISTINCT FROM OLD.fssai_number
     AND NEW.fssai_legal_name IS NOT DISTINCT FROM OLD.fssai_legal_name
     AND NEW.fssai_registered_address IS NOT DISTINCT FROM OLD.fssai_registered_address
     AND NEW.fssai_valid_until IS NOT DISTINCT FROM OLD.fssai_valid_until THEN
    RETURN NEW;
  END IF;
  IF lower(NEW.role::text) NOT IN ('chef', 'cook') THEN
    RETURN NEW;
  END IF;

  v_title := 'FSSAI proof to review';
  v_body := trim(both ' ' FROM concat_ws(
    ' · ',
    coalesce(nullif(btrim(NEW.name), ''), nullif(btrim(NEW.full_name), ''), 'A chef'),
    CASE WHEN nullif(btrim(NEW.fssai_number), '') IS NULL THEN NULL ELSE 'Reg ' || btrim(NEW.fssai_number) END,
    CASE WHEN nullif(btrim(NEW.fssai_legal_name), '') IS NULL THEN NULL ELSE btrim(NEW.fssai_legal_name) END,
    CASE WHEN NEW.fssai_valid_until IS NULL THEN NULL ELSE 'valid upto ' || NEW.fssai_valid_until::text END
  ));

  INSERT INTO public.user_notifications (user_id, title, body, kind, data)
  SELECT
    po.user_id,
    v_title,
    v_body,
    'fssai_review',
    jsonb_build_object(
      'chef_id', NEW.id,
      'fssai_number', NEW.fssai_number,
      'fssai_legal_name', NEW.fssai_legal_name,
      'fssai_registered_address', NEW.fssai_registered_address,
      'fssai_valid_until', NEW.fssai_valid_until,
      'fssai_proof_url', NEW.fssai_proof_url
    )
  FROM public.platform_ops po
  WHERE po.user_id IS NOT NULL
    AND po.revoked_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_notifications n
      WHERE n.user_id = po.user_id
        AND n.kind = 'fssai_review'
        AND n.data->>'chef_id' = NEW.id::text
        AND n.created_at > now() - interval '15 minutes'
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_notify_ops_fssai_submission ON public.users;
CREATE TRIGGER users_notify_ops_fssai_submission
  AFTER INSERT OR UPDATE OF fssai_proof_url, fssai_number, fssai_legal_name, fssai_registered_address, fssai_valid_until
  ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_ops_fssai_submission();

CREATE OR REPLACE FUNCTION public.expire_lapsed_fssai_licences()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n integer := 0;
  r record;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  FOR r IN
    SELECT u.id, u.name, u.full_name, u.fssai_valid_until
    FROM public.users u
    WHERE lower(u.role::text) IN ('chef', 'cook')
      AND u.fssai_valid_until IS NOT NULL
      AND u.fssai_valid_until < v_today
      AND (
        u.fssai_expiry_notified_on IS NULL
        OR u.fssai_expiry_notified_on < u.fssai_valid_until
      )
  LOOP
    UPDATE public.users
    SET
      fssai_verification_status = CASE
        WHEN lower(fssai_verification_status) = 'verified' THEN 'pending'
        ELSE fssai_verification_status
      END,
      fssai_review_note = 'FSSAI licence validity ended. Upload a current certificate.',
      fssai_expiry_notified_on = v_today,
      updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.user_notifications (user_id, title, body, kind, data)
    VALUES (
      r.id,
      'Update your FSSAI certificate',
      'Your FSSAI licence validity ended on ' || r.fssai_valid_until::text ||
        '. Open Chef Profile, scan a current certificate, and wait for HotPotChef to verify.',
      'fssai_expired',
      jsonb_build_object(
        'kind', 'fssai_expired',
        'fssai_valid_until', r.fssai_valid_until
      )
    );

    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_lapsed_fssai_licences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_lapsed_fssai_licences() TO service_role;

NOTIFY pgrst, 'reload schema';

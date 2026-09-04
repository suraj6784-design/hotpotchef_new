-- Keep last-four Aadhaar and drop plaintext values already stored.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'aadhaar_number'
  ) THEN
    UPDATE public.users
    SET aadhaar_masked = COALESCE(
      NULLIF(aadhaar_masked, ''),
      CASE
        WHEN length(regexp_replace(coalesce(aadhaar_number, ''), '\D', '', 'g')) >= 4
        THEN 'XXXX-XXXX-' || right(regexp_replace(aadhaar_number, '\D', '', 'g'), 4)
        ELSE aadhaar_masked
      END
    )
    WHERE aadhaar_number IS NOT NULL
      AND aadhaar_number <> '';

    UPDATE public.users
    SET aadhaar_number = NULL
    WHERE aadhaar_number IS NOT NULL;
  END IF;
END $$;

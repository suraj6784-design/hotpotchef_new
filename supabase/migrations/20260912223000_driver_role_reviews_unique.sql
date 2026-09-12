-- Driver profile upsert was inserting users.role as null.
-- Reviews had no per-order unique key.
-- Keep signup role on INSERT as well as UPDATE.

CREATE OR REPLACE FUNCTION public.keep_users_signup_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.role IS NULL OR btrim(NEW.role::text) = '' THEN
      NEW.role := coalesce(
        nullif(btrim(auth.jwt() -> 'user_metadata' ->> 'role'), ''),
        'Customer'
      );
    END IF;
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_keep_signup_role ON public.users;
CREATE TRIGGER users_keep_signup_role
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.keep_users_signup_role();

ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS order_id uuid;

DELETE FROM public.reviews a
USING public.reviews b
WHERE a.ctid < b.ctid
  AND a.customer_id = b.customer_id
  AND a.meal_id = b.meal_id
  AND a.order_id IS NOT DISTINCT FROM b.order_id;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reviews_one_per_customer_order_meal'
  ) THEN
    ALTER TABLE public.reviews
      ADD CONSTRAINT reviews_one_per_customer_order_meal UNIQUE (customer_id, order_id, meal_id);
  END IF;
END $$;

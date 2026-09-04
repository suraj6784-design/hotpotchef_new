-- Kitchen GSTIN for tax invoices, and stop needing plaintext Aadhaar on users.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS gstin text,
  ADD COLUMN IF NOT EXISTS aadhaar_masked text;

COMMENT ON COLUMN public.users.gstin IS
  '15-character GSTIN. When set, customer PDFs are tax invoices; otherwise a bill of supply.';

COMMENT ON COLUMN public.users.aadhaar_masked IS
  'Last-four Aadhaar only (XXXX-XXXX-1234). Do not store the full number.';

NOTIFY pgrst, 'reload schema';

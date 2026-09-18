-- Chat insert impersonation + unused anon EXECUTE on complete_delivery_order.
--
-- Live `messages` INSERT used WITH CHECK (true), so any authenticated user could
-- insert a row as another sender_id. The Flutter chat client already sends
-- sender_id = auth.uid(); this policy matches that contract.
--
-- complete_delivery_order is SECURITY DEFINER and returns false when
-- auth.uid() is null, but GRANT EXECUTE to anon is unused. Revoke it.

DROP POLICY IF EXISTS "Allow authenticated users to insert messages" ON public.messages;
DROP POLICY IF EXISTS messages_insert_own_sender ON public.messages;
CREATE POLICY messages_insert_own_sender
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (sender_id = auth.uid());

DO $$
BEGIN
  IF to_regprocedure('public.complete_delivery_order(uuid, text, text)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.complete_delivery_order(uuid, text, text) FROM PUBLIC, anon';
  ELSIF to_regprocedure('public.complete_delivery_order(uuid)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.complete_delivery_order(uuid) FROM PUBLIC, anon';
  END IF;
END $$;

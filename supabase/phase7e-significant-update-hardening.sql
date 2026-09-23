-- Phase 7E: Explicit RLS hardening for significant_update_events
REVOKE ALL ON TABLE public.significant_update_events FROM anon, authenticated;
REVOKE ALL ON TABLE public.significant_update_deliveries FROM anon, authenticated;
GRANT ALL ON TABLE public.significant_update_events TO service_role;
GRANT ALL ON TABLE public.significant_update_deliveries TO service_role;
ALTER TABLE public.significant_update_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.significant_update_deliveries ENABLE ROW LEVEL SECURITY;

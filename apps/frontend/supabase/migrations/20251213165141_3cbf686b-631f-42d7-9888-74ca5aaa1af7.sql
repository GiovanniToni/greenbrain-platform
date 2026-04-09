-- Tabella eventi calendario per Garden Center
CREATE TABLE public.calendar_events (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  garden_center_id UUID,
  date DATE NOT NULL,
  name TEXT NOT NULL,
  impact_level TEXT DEFAULT 'medium' CHECK (impact_level IN ('low', 'medium', 'high')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

-- Policy: tutti possono leggere eventi (pubblici/festività)
CREATE POLICY "Events are viewable by authenticated users" 
ON public.calendar_events 
FOR SELECT 
TO authenticated
USING (true);

-- Index per query per mese
CREATE INDEX idx_calendar_events_date ON public.calendar_events(date);
CREATE INDEX idx_calendar_events_garden_center ON public.calendar_events(garden_center_id);
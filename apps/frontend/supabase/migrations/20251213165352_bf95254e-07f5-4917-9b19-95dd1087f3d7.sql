-- Tabella impostazioni Garden Center
CREATE TABLE public.garden_center_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  garden_center_id UUID UNIQUE,
  city TEXT,
  lat DECIMAL(10, 7),
  lon DECIMAL(10, 7),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.garden_center_settings ENABLE ROW LEVEL SECURITY;

-- Policy: authenticated users can read/write their settings
CREATE POLICY "Users can view their settings" 
ON public.garden_center_settings 
FOR SELECT 
TO authenticated
USING (true);

CREATE POLICY "Users can insert their settings" 
ON public.garden_center_settings 
FOR INSERT 
TO authenticated
WITH CHECK (true);

CREATE POLICY "Users can update their settings" 
ON public.garden_center_settings 
FOR UPDATE 
TO authenticated
USING (true);

-- Index
CREATE INDEX idx_settings_garden_center ON public.garden_center_settings(garden_center_id);
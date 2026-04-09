import { useState, useEffect } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Building2, User, Users, Settings, MapPin } from "lucide-react";
import { useGardenCenterSettings } from "@/hooks/useGardenCenterSettings";
import { useToast } from "@/hooks/use-toast";

// TODO: Fetch dati garden center da Supabase
const mockGardenCenter = {
  nome: "Garden Center Demo",
  indirizzo: "Via delle Rose 123, 20100 Milano",
  telefono: "+39 02 1234567",
  email: "info@gardendemo.it",
  partitaIva: "IT12345678901",
};

const mockUser = {
  nome: "Mario",
  cognome: "Rossi",
  email: "mario.rossi@gardendemo.it",
  ruolo: "Amministratore",
};

export default function Account() {
  const { settings, loading: settingsLoading, saving, saveSettings } = useGardenCenterSettings();
  const { toast } = useToast();

  const [city, setCity] = useState("");
  const [lat, setLat] = useState("");
  const [lon, setLon] = useState("");

  // ✅ FIX: usare useEffect (non useState)
  useEffect(() => {
    if (settings.city) setCity(settings.city);
    if (settings.lat !== null && settings.lat !== undefined) setLat(String(settings.lat));
    if (settings.lon !== null && settings.lon !== undefined) setLon(String(settings.lon));
  }, [settings.city, settings.lat, settings.lon]);

  const handleSaveLocation = async () => {
    const result = await saveSettings({
      city,
      lat: lat ? parseFloat(lat) : null,
      lon: lon ? parseFloat(lon) : null,
    });

    if (result.error) {
      toast({
        title: "Errore",
        description: result.error,
        variant: "destructive",
      });
    } else {
      toast({
        title: "Salvato!",
        description: "Preferenze località aggiornate.",
      });
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Account</h1>
        <p className="text-muted-foreground">Gestisci le impostazioni del tuo account</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Dati Garden Center */}
        <Card className="p-6 animate-fade-in">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
              <Building2 className="w-5 h-5 text-primary" />
            </div>
            <h2 className="text-lg font-semibold">Dati Garden Center</h2>
          </div>

          <div className="space-y-4">
            <Input defaultValue={mockGardenCenter.nome} />
            <Input defaultValue={mockGardenCenter.indirizzo} />
            <Input defaultValue={mockGardenCenter.telefono} />
            <Input defaultValue={mockGardenCenter.email} />
            <Input defaultValue={mockGardenCenter.partitaIva} />
            <Button className="w-full mt-4">Salva Modifiche</Button>
          </div>
        </Card>

        {/* Preferenze Località */}
        <Card className="p-6 animate-fade-in">
          <div className="space-y-4">
            <Input value={city} onChange={(e) => setCity(e.target.value)} />
            <Input value={lat} onChange={(e) => setLat(e.target.value)} />
            <Input value={lon} onChange={(e) => setLon(e.target.value)} />
            <Button className="w-full mt-4" onClick={handleSaveLocation} disabled={saving || settingsLoading}>
              {saving ? "Salvataggio..." : "Salva Località"}
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}

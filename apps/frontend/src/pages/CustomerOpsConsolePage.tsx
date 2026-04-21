import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Users, LayoutDashboard, Terminal, RefreshCw } from "lucide-react";
import { Card } from "@/components/ui/card";
import { listCustomers, type CustomerOpsItem } from "@/lib/customerOpsApi";

function computeKpis(items: CustomerOpsItem[]) {
  return {
    total: items.length,
    active: items.filter((x) => x.subscription_status === "active").length,
    slotPending: items.filter((x) => x.onboarding_status === "slot_requested").length,
    dataValidation: items.filter((x) => x.onboarding_status === "data_validation_pending").length,
    deliveryPending: items.filter(
      (x) => x.subscription_status === "active" && !x.bundle_generated_at,
    ).length,
  };
}

type Kpis = ReturnType<typeof computeKpis>;

export default function CustomerOpsConsolePage() {
  const [kpis, setKpis] = useState<Kpis | null>(null);
  const [loadingKpis, setLoadingKpis] = useState(true);

  useEffect(() => {
    setLoadingKpis(true);
    listCustomers(200)
      .then((data) => setKpis(computeKpis(data.items || [])))
      .catch(() => setKpis(null))
      .finally(() => setLoadingKpis(false));
  }, []);

  const kpiItems: { label: string; value: number; color: string }[] = kpis
    ? [
        { label: "Clienti totali", value: kpis.total, color: "#374151" },
        { label: "Abbonamenti attivi", value: kpis.active, color: "#16a34a" },
        { label: "Slot da confermare", value: kpis.slotPending, color: "#d97706" },
        { label: "Validazione pendente", value: kpis.dataValidation, color: "#7c3aed" },
        { label: "Delivery pendenti", value: kpis.deliveryPending, color: "#0369a1" },
      ]
    : [];

  return (
    <div className="max-w-3xl">
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
            <Terminal className="w-5 h-5 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">Console operativa GreenBrain</h1>
        </div>
        <p className="text-muted-foreground text-sm">
          Area riservata al team GreenBrain. Gestisci clienti, provisioning, delivery e la piattaforma interna.
        </p>
      </div>

      {/* live KPI strip */}
      <div className="mb-8">
        {loadingKpis ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            Caricamento dati...
          </div>
        ) : kpis ? (
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
            {kpiItems.map(({ label, value, color }) => (
              <div key={label} className="bg-muted/50 border rounded-lg p-3 text-center">
                <div style={{ fontSize: 30, fontWeight: 800, color, lineHeight: 1 }}>{value}</div>
                <div className="text-xs text-muted-foreground mt-1.5 leading-tight">{label}</div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">Dati non disponibili.</p>
        )}
      </div>

      {/* main entry cards */}
      <div className="grid sm:grid-cols-2 gap-4">
        <Link to="/customers">
          <Card className="p-6 hover:border-primary/50 hover:shadow-sm transition-all cursor-pointer h-full">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
                <Users className="w-5 h-5 text-primary" />
              </div>
              <h2 className="font-semibold text-lg">Gestisci clienti</h2>
            </div>
            <p className="text-sm text-muted-foreground">
              Visualizza e gestisci tutti i clienti: onboarding, slot di setup, delivery, abbonamenti.
            </p>
          </Card>
        </Link>

        <Link to="/dashboard">
          <Card className="p-6 hover:border-primary/50 hover:shadow-sm transition-all cursor-pointer h-full">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
                <LayoutDashboard className="w-5 h-5 text-primary" />
              </div>
              <h2 className="font-semibold text-lg">Piattaforma</h2>
            </div>
            <p className="text-sm text-muted-foreground">
              Accedi alla dashboard GreenBrain: forecast, analytics, pianificazione e fornitori.
            </p>
          </Card>
        </Link>
      </div>

      <p className="text-xs text-muted-foreground mt-8">
        Quest&apos;area è riservata al team interno GreenBrain. Non condividere l&apos;accesso con i clienti.
      </p>
    </div>
  );
}

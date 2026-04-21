import { Link } from "react-router-dom";
import { Users, LayoutDashboard, Terminal } from "lucide-react";
import { Card } from "@/components/ui/card";

export default function CustomerOpsConsolePage() {
  return (
    <div className="max-w-2xl">
      <div className="mb-8">
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

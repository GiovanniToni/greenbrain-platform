import { useState } from "react";
import { Link } from "react-router-dom";
import { Leaf, Mail } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { ApiError, apiPost } from "@/lib/apiClient";

export default function ForgotPassword() {
  const [email, setEmail] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const { toast } = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail) {
      setMessage("Inserisci l'email del tuo account GreenBrain.");
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const res = await apiPost("/api/v1/auth/request-password-reset", {
        email: cleanEmail,
      });

      const genericMessage =
        res?.message ||
        "Se l'email è registrata, riceverai le istruzioni per reimpostare la password.";

      setMessage(genericMessage);
      toast({
        title: "Richiesta inviata",
        description: genericMessage,
      });
    } catch (err) {
      const msg =
        err instanceof ApiError && err.status === 400
          ? "Controlla l'email inserita e riprova."
          : err instanceof Error
            ? err.message
            : "Impossibile inviare la richiesta.";

      setMessage(msg);
      toast({
        title: "Errore",
        description: msg,
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-background flex flex-col items-center justify-center gap-4 p-4">
      <div className="w-full max-w-md">
        <Link to="/login" className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1">
          ← Torna al login
        </Link>
      </div>

      <Card className="w-full max-w-md p-8 animate-fade-in">
        <Link to="/" className="flex items-center justify-center gap-3 mb-8 hover:opacity-80 transition-opacity">
          <div className="w-12 h-12 bg-primary rounded-xl flex items-center justify-center">
            <Leaf className="w-7 h-7 text-primary-foreground" />
          </div>
          <span className="text-2xl font-bold">GreenBrain</span>
        </Link>

        <h1 className="text-xl font-semibold text-center mb-2">Password dimenticata?</h1>
        <p className="text-sm text-muted-foreground text-center mb-8">
          Inserisci la tua email. Se l'account esiste, riceverai le istruzioni per reimpostare la password.
        </p>

        <form onSubmit={handleSubmit} className="space-y-4" autoComplete="off">
          <div className="space-y-2">
            <label className="text-sm font-medium">Email</label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                type="email"
                name="gb_reset_email"
                autoComplete="off"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="nome@gardencenter.it"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          {message && (
            <p className="text-sm text-muted-foreground text-center">
              {message}
            </p>
          )}

          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? "Invio in corso..." : "Invia istruzioni"}
          </Button>
        </form>
      </Card>
    </div>
  );
}

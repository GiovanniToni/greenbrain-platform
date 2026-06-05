import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Leaf, Lock } from "lucide-react";

import { PasswordInput } from "@/components/PasswordInput";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { ApiError, apiPost, clearStoredToken } from "@/lib/apiClient";
import { useQueryClient } from "@tanstack/react-query";

export default function ResetPassword() {
  const [searchParams] = useSearchParams();
  const token = useMemo(() => (searchParams.get("token") || "").trim(), [searchParams]);
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!token) {
      setMessage("Link di reset non valido o incompleto.");
      return;
    }

    if (newPassword.length < 8) {
      setMessage("La nuova password deve contenere almeno 8 caratteri.");
      return;
    }

    if (newPassword !== confirmPassword) {
      setMessage("Le due password non coincidono.");
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      await apiPost("/api/v1/auth/reset-password", {
        token,
        new_password: newPassword,
      });

      toast({
        title: "Password aggiornata",
        description: "Ora puoi accedere con la nuova password.",
      });

      clearStoredToken();
      queryClient.clear();
      setMessage("Password aggiornata. Ora puoi accedere con la nuova password.");
      setTimeout(() => window.location.replace("/login"), 1200);
    } catch (err) {
      const detail = err instanceof ApiError ? err.message : err instanceof Error ? err.message : "";

      const msg =
        detail === "password_reset_token_invalid_or_expired"
          ? "Il link non è valido o è scaduto. Richiedi un nuovo reset password."
          : detail === "new_password_too_short"
            ? "La nuova password deve contenere almeno 8 caratteri."
            : detail === "new_password_same_as_current"
              ? "La nuova password deve essere diversa da quella attuale."
              : "Impossibile aggiornare la password. Richiedi un nuovo link e riprova.";

      setMessage(msg);
      toast({
        title: "Errore reset password",
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

        <h1 className="text-xl font-semibold text-center mb-2">Imposta nuova password</h1>
        <p className="text-sm text-muted-foreground text-center mb-8">
          Scegli una nuova password per il tuo account GreenBrain.
        </p>

        {!token && (
          <p className="text-sm text-destructive text-center mb-4">
            Link di reset non valido o incompleto.
          </p>
        )}

        <form onSubmit={handleSubmit} className="space-y-4" autoComplete="off">
          <div className="space-y-2">
            <label className="text-sm font-medium">Nuova password</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <PasswordInput
                name="gb_new_password"
                autoComplete="new-password"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="Almeno 8 caratteri"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                className="pl-10"
                required
                disabled={!token || isSubmitting}
              />
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">Conferma password</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <PasswordInput
                name="gb_confirm_password"
                autoComplete="new-password"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="Ripeti la password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className="pl-10"
                required
                disabled={!token || isSubmitting}
              />
            </div>
          </div>

          {message && (
            <p className="text-sm text-muted-foreground text-center">
              {message}
            </p>
          )}

          <Button type="submit" className="w-full" disabled={!token || isSubmitting}>
            {isSubmitting ? "Aggiornamento..." : "Aggiorna password"}
          </Button>
        </form>
      </Card>
    </div>
  );
}

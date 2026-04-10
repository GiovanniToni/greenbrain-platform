# Phase 4 - Remote Access Plan

## Obiettivo
Consentire accesso remoto al cliente senza spostare i suoi dati nel cloud GreenBrain.

## Strategia scelta
- tunnel sicuro outbound
- auth centrale su www.greenbrain.it
- tenant routing centrale
- backend cliente raggiungibile solo tramite tunnel
- nessuna apertura porte inbound lato cliente

## Stato attuale
- Fase 3 locale completata
- tenant local-runtime registrato
- login centrale già instradato
- tunnel non ancora attivato

## Regole
- non toccare dev cloud
- non toccare auth centrale oltre metadata
- non fare sync raw verso cloud GreenBrain
- non attivare ancora proxy tenant live finché il tunnel non è collaudato

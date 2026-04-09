--
-- PostgreSQL database dump
--

\restrict flQF1Sw59Jb65ztbdGzZUxTxXBhi1T85pVDbwzfDh2zpFRjFZrVnahhoSwJb8eg

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: t_core_analytics__series_daily_categoria; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__series_daily_categoria (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_famiglia; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__series_daily_famiglia (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_fascia; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__series_daily_fascia (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_fascia_prezzo; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__series_daily_fascia_prezzo (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- PostgreSQL database dump complete
--

\unrestrict flQF1Sw59Jb65ztbdGzZUxTxXBhi1T85pVDbwzfDh2zpFRjFZrVnahhoSwJb8eg


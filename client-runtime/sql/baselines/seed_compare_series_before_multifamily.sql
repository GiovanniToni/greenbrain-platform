--
-- PostgreSQL database dump
--

\restrict Sjx6cO1q7oaIyhUY9Yyx9gkqEXj2ohxvWOQfRekdup2FBtWvWP1LSLpLgH5f58q

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
-- Data for Name: greenhouse_forecast_features_dense; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_forecast_features_dense (data, famiglia, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, fascia_corretta, categoria_corretta, pot_sizes_text, pot_sizes_json, articoli_inclusi, articoli_json, tmin_c, tmax_c, tavg_c, rain_mm, sun_hours, is_holiday, holiday_name, dow, week_num, month_num, year_num, qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14, qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28, created_at, updated_at) FROM stdin;
2026-03-01	test_family_a	A	5.000	50.00	5	fascia_test	categoria_test	P10	["P10"]	TEST001	["TEST001"]	\N	\N	\N	\N	\N	f	\N	7	9	3	2026	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-03-31 12:40:54.746195	2026-03-31 12:40:54.746195
2026-03-02	test_family_a	A	6.000	60.00	6	fascia_test	categoria_test	P10	["P10"]	TEST001	["TEST001"]	\N	\N	\N	\N	\N	f	\N	1	10	3	2026	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-03-31 12:40:54.746195	2026-03-31 12:40:54.746195
2026-03-03	test_family_a	A	7.000	70.00	7	fascia_test	categoria_test	P10	["P10"]	TEST001	["TEST001"]	\N	\N	\N	\N	\N	f	\N	2	10	3	2026	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-03-31 12:40:54.746195	2026-03-31 12:40:54.746195
\.


--
-- Data for Name: greenhouse_forecast_results_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_forecast_results_v2 (data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at) FROM stdin;
2026-03-01	test_family_a	A	6.000	2026-03-31 12:40:54.747642
2026-03-02	test_family_a	A	6.000	2026-03-31 12:40:54.747642
2026-03-03	test_family_a	A	6.000	2026-03-31 12:40:54.747642
\.


--
-- PostgreSQL database dump complete
--

\unrestrict Sjx6cO1q7oaIyhUY9Yyx9gkqEXj2ohxvWOQfRekdup2FBtWvWP1LSLpLgH5f58q


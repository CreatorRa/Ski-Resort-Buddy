module Localization

export t, localize, set_language!, current_language, available_languages, DEFAULT_LANGUAGE, is_supported_language, normalize_language

const DEFAULT_LANGUAGE = :en
const ACTIVE_LANGUAGE = Base.RefValue{Symbol}(DEFAULT_LANGUAGE)

const TEMPLATE_PATTERN = r"\{\{(\w+)\}\}"

const TRANSLATION_DATA = raw"""
greeting	Hello, welcome to our tool!	Hallo, willkommen in unserem Tool!
info_no_data_after_filters	No data available after applying filters.	Keine Daten nach Anwendung der Filter verfügbar.
info_terminal_finished	Done. Terminal reporting finished.	Fertig. Terminalausgabe beendet.
warn_invalid_force_weight_prompt_env	Ignoring invalid FORCE_WEIGHT_PROMPT env value	Ungültiger FORCE_WEIGHT_PROMPT-Umgebungswert wird ignoriert
warn_unknown_weight_flag	Unknown weight option	Unbekannte Gewichtungsoption
warn_weight_flag_requires_value	Option {{flag}} requires a numeric value	Option {{flag}} benötigt einen numerischen Wert
warn_weight_parse_failed	Could not parse weight value	Gewichtswert konnte nicht interpretiert werden
warn_unknown_option	Unknown option	Unbekannte Option
warn_unrecognized_argument	Unrecognized argument	Unbekanntes Argument
warn_invalid_from_date	Could not parse FROM_DATE	FROM_DATE konnte nicht geparst werden
warn_invalid_to_date	Could not parse TO_DATE	TO_DATE konnte nicht geparst werden
warn_unsupported_language	Unsupported language '{{requested}}'. Available: {{options}}	Nicht unterstützte Sprache '{{requested}}'. Verfügbar: {{options}}
warn_using_fallback_csv	Using fallback CSV	Verwende Ersatz-CSV
error_csv_missing	CSV not found. Set CSV_PATH env, pass a path argument, or keep {{default_file}} in the project directory.	CSV nicht gefunden. Setze die Umgebungsvariable CSV_PATH, übergib einen Pfad oder lege {{default_file}} im Projektverzeichnis ab.
info_loading_csv	[INFO] Loading CSV: {{path}}	[INFO] Lade CSV: {{path}}
error_no_date_column	No date column detected. Expecting something like 'Date'.	Keine Datumsspalte gefunden. Erwartet wird etwas wie 'Date'.
info_no_country_metadata	[INFO] No country information available in the dataset.	[INFO] Keine Länderinformation im Datensatz verfügbar.
language_name_en	English	Englisch
language_name_de	German	Deutsch
prompt_language_header	Select a language (press Enter to keep current):	Sprache auswählen (Enter für aktuelle Sprache)
prompt_language_option	 {{index}}) {{name}}	 {{index}}) {{name}}
prompt_language_hint	Current language: {{current}}	Aktuelle Sprache: {{current}}
prompt_language_retry	Not recognized. Please choose a listed option or language code.	Nicht erkannt. Bitte wähle eine aufgelistete Option oder einen Sprachcode.
prompt_language_cancelled	Language selection cancelled: {{error}}	Sprachauswahl abgebrochen: {{error}}
menu_available_countries_header	Available countries:	Verfügbare Länder:
menu_country_entry	 {{index}}) {{country}}	 {{index}}) {{country}}
menu_country_prompt	Choose a number or enter the country name (empty for all countries).	Nummer wählen oder Ländernamen eingeben (leer für alle Länder).
info_input_aborted	[INFO] Input aborted: {{error}}	[INFO] Eingabe abgebrochen: {{error}}
menu_country_retry	Not recognized. Please try again (press Enter to cancel).	Nicht erkannt. Bitte erneut versuchen (Enter zum Abbrechen).
info_input_expected	[INFO] Input expected – press Ctrl+C to cancel if no keyboard input is possible.	[INFO] Eingabe erwartet – breche mit Strg+C ab, falls keine Tastatureingabe möglich ist.
prompt_adjust_weights	Adjust weights? (y/N)	Gewichtung anpassen? (y/N)
menu_header	==== Menu ====	==== Menü ====
menu_option_overview	1) Overview of all regions	1) Überblick aller Regionen
menu_option_country	2) Select country	2) Land auswählen
menu_option_exit	3) Exit	3) Beenden
info_return_menu	Back to the menu...	Zurück zum Menü...
info_no_country_selection	[INFO] No selection made – returning to the menu.	[INFO] Keine Auswahl – kehre zum Menü zurück.
info_no_data_for_country	[INFO] No data available for {{country}}.	[INFO] Keine Daten für {{country}} vorhanden.
farewell	Goodbye!	Auf Wiedersehen!
menu_select_option	Please choose an option.	Bitte eine Option wählen.
menu_unknown_choice	Unknown selection: {{choice}}	Unbekannte Auswahl: {{choice}}
info_weights_prompt_skipped	[INFO] Weight prompt skipped (non-interactive session).	[INFO] Gewichtungsabfrage übersprungen (nicht-interaktive Sitzung).
weights_prompt_header	== Metric Weighting ==	== Gewichtung der Metriken ==
weights_prompt_instructions	Enter a priority between 0 and 100 for each metric (values like 30 or 30% are fine). The sum must equal 100.	Für jede Metrik eine Wichtigkeit zwischen 0 und 100 eingeben (Angaben wie 30 oder 30% sind erlaubt). Die Summe muss 100 ergeben.
weights_prompt_hint_lower_better	Hint: Temperature, precipitation, and wind are treated as 'lower is better'.	Hinweis: Temperatur, Niederschlag und Wind werden als 'niedriger ist besser' interpretiert.
error_weight_value_range	  -> Please enter a value between 0 and 100.	  -> Bitte einen Wert zwischen 0 und 100 eingeben.
error_weight_sum	The sum of the weights is {{sum}}. Please enter the values again.	Die Summe der Gewichte beträgt {{sum}}. Bitte erneut eingeben.
warn_weight_sum_non_positive	Weight sum <= 0. Reverting to defaults.	Gewichtssumme <= 0. Setze Standardwerte zurück.
weights_active_header	== Active Weights ==	== Aktive Gewichte ==
weights_active_line	 - {{label}}: {{value}}%{{preference}}	 - {{label}}: {{value}}%{{preference}}
weights_preference_lower_suffix	 (lower is better)	 (weniger ist besser)
weights_active_sum	   Sum = {{total}}%	   Summe = {{total}}%
weight_label_snow_new	Fresh Snow	Frischer Schnee
weight_label_snow_depth	Snow Depth	Schneehöhe
weight_label_temperature	Temperature	Temperatur
weight_label_precipitation	Precipitation	Niederschlag
weight_label_wind	Wind	Wind
weight_prompt_snow_new	Fresh snow – prefer higher values [0-100%]	Frischer Schnee – höhere Werte bevorzugt [0-100%]
weight_prompt_snow_depth	Snow depth – prefer higher values [0-100%]	Schneehöhe – höhere Werte bevorzugt [0-100%]
weight_prompt_temperature	Temperature – cooler is better [0-100%]	Temperatur – kühler ist besser [0-100%]
weight_prompt_precipitation	Precipitation – less rain is better [0-100%]	Niederschlag – weniger Regen ist besser [0-100%]
weight_prompt_wind	Wind – calmer is better [0-100%]	Wind – ruhiger ist besser [0-100%]
metric_snow_depth	Snow Depth (cm)	Schneehöhe (cm)
metric_snow_new	New Snow (cm)	Neuschnee (cm)
metric_temperature	Temperature (°C)	Temperatur (°C)
metric_precipitation	Precipitation (mm)	Niederschlag (mm)
metric_wind	Wind (Beaufort)	Wind (Beaufort)
info_default_csv_found	File found at {{path}}	Datei gefunden unter {{path}}
info_default_csv_reading	Reading data...	Lese Daten...
info_default_csv_preview	Showing the first 10 rows:	Anzeige der ersten 10 Zeilen:
error_default_csv_missing	File not found!	Datei nicht gefunden!
error_default_csv_hint	Please ensure the file '{{file}}' is located in the project directory.	Bitte stelle sicher, dass die Datei '{{file}}' im Projektverzeichnis liegt.
speech_prompt_active	(Speech input active – please speak...)	(Spracheingabe aktiv – bitte sprechen …)
speech_no_result	[INFO] No usable speech result detected – please type your input.	[INFO] Spracherkennung ohne verwertbares Ergebnis – bitte Eingabe tippen.
speech_failed	[WARN] Speech recognition failed – please type your input.	[WARN] Spracherkennung fehlgeschlagen – bitte Eingabe tippen.
speech_enable_prompt	Enable speech control at startup? (y/N)	Sprachsteuerung beim Start aktivieren? (y/N)
speech_candidate_found	Detected candidate: {{command}}	Gefundener Kandidat: {{command}}
speech_candidate_prompt	Press Enter to use it or type an alternative command.	Drücke Enter, um diesen zu verwenden, oder gib einen alternativen Befehl ein.
speech_candidate_request	Please provide the command that runs speech recognition (Enter to cancel).	Bitte gib den Befehl an, der die Spracherkennung ausführt (Enter zum Abbrechen).
speech_candidate_example	Example: python3 bin/transcribe.py	Beispiel: python3 bin/transcribe.py
speech_disabled	[INFO] Speech control remains disabled.	[INFO] Sprachsteuerung bleibt deaktiviert.
speech_enabled	[INFO] Speech control enabled.	[INFO] Sprachsteuerung aktiviert.
regions_header	== Available Regions ==	== Verfügbare Regionen ==
regions_none	 (no regions found)	 (keine Regionen gefunden)
regions_entry	 - {{name}}	 - {{name}}
filters_header	== Active Filters ==	== Aktive Filter ==
filters_season	 - Season: {{value}}	 - Saison: {{value}}
filters_date_range	 - Date range: {{from}} -> {{to}}	 - Datumsbereich: {{from}} -> {{to}}
filters_region_selected	 - Preselected region: {{value}}	 - Vorgewählte Region: {{value}}
filters_region_env	 - Preselected region (ENV): {{value}}	 - Vorgewählte Region (ENV): {{value}}
filters_region_none	 - No region preselected	 - Keine Region vorausgewählt
filters_country_menu	 - Country filter (menu): {{value}}	 - Länderfilter (Menü): {{value}}
filters_country_env	 - Country filter (ENV): {{value}}	 - Länderfilter (ENV): {{value}}
filters_country_none	 - No country preselected	 - Kein Land vorausgewählt
filters_observation_window	 - Observations: {{rows}} rows, window {{start}} - {{stop}}	 - Beobachtungen: {{rows}} Zeilen, Zeitraum {{start}} - {{stop}}
filters_no_data	 - No data available after applying filters	 - Keine Daten nach Anwendung der Filter
data_preview_first	== Data Preview — first {{rows}} rows ==	== Datenvorschau — erste {{rows}} Zeilen ==
data_preview_last	== Data Preview — last {{rows}} rows ==	== Datenvorschau — letzte {{rows}} Zeilen ==
current_month_header	== Current Month Overview — {{label}} ==	== Monatsübersicht — {{label}} ==
info_no_current_month_data	[INFO] No data for the current or latest month.	[INFO] Keine Daten für den aktuellen oder letzten Monat.
info_no_metrics_to_summarise	[INFO] No numeric metrics available to summarise.	[INFO] Keine numerischen Metriken zum Zusammenfassen vorhanden.
metric_group_summary_header	== {{metric}} — by {{group}} ==	== {{metric}} — nach {{group}} ==
info_daily_board_missing_columns	[INFO] Unable to build the daily snowfall leaderboard (missing required columns).	[INFO] Tägliches Schneefall-Ranking kann nicht erstellt werden (fehlende Spalten).
info_daily_board_no_rows	[INFO] No rows available for the daily snowfall leaderboard.	[INFO] Keine Zeilen für das tägliche Schneefall-Ranking verfügbar.
daily_leaderboard_today_label	today ({{date}})	heute ({{date}})
daily_leaderboard_latest_label	latest available date ({{date}})	letztes verfügbares Datum ({{date}})
info_daily_board_latest_no_rows	[INFO] No rows match the latest available date for the daily snowfall leaderboard.	[INFO] Keine Zeilen entsprechen dem letzten Datum für das tägliche Schneefall-Ranking.
daily_leaderboard_header	== Daily Snowfall Leaderboard — {{label}} ==	== Tägliches Schneefall-Ranking — {{label}} ==
info_monthly_no_date	[INFO] No Date column available - cannot build the monthly overview.	[INFO] Keine Datumsspalte verfügbar – Monatsübersicht kann nicht erstellt werden.
info_monthly_no_metrics	[INFO] No numeric metrics available to build the monthly overview.	[INFO] Keine numerischen Metriken für die Monatsübersicht vorhanden.
info_monthly_no_month_values	[INFO] Monthly overview not available (no month values detected).	[INFO] Monatsübersicht nicht verfügbar (keine Monatswerte gefunden).
info_monthly_no_rows	[INFO] No rows for the monthly overview.	[INFO] Keine Zeilen für die Monatsübersicht.
info_monthly_empty_grouping	[INFO] Monthly overview could not be generated (empty grouping result).	[INFO] Monatsübersicht konnte nicht erstellt werden (leeres Gruppierungsergebnis).
monthly_overview_header	== Monthly Overview - Regional Averages for {{month}} ==	== Monatsübersicht - regionale Durchschnitte für {{month}} ==
info_ranking_unavailable	[INFO] No ranking available. Check your filters or data.	[INFO] Kein Ranking verfügbar. Prüfe Filter oder Datenlage.
info_ranking_missing_score	[INFO] Weighted score unavailable – ranking skipped.	[INFO] Gewichteter Score nicht verfügbar – Ranking übersprungen.
info_ranking_no_valid_scores	[INFO] No valid score values – ranking skipped.	[INFO] Keine gültigen Score-Werte – Ranking übersprungen.
ranking_header	== Top Ski Regions by Weight{{label}} ==	== Top-Skigebiete nach Gewichtung{{label}} ==
commands_header	Available commands	Verfügbare Befehle
commands_menu	- interactive terminal menu	- interaktives Terminalmenü
commands_report	- default full dashboard (this view)	- Standard-Dashboard (diese Ansicht)
commands_list	- list all DACH regions	- alle DACH-Regionen anzeigen
commands_region	- deep dive into a single resort (replace NAME)	- Detailansicht für ein Resort (NAME ersetzen)
commands_options_label	Options:	Optionen:
commands_options	 --from YYYY-MM-DD | --to YYYY-MM-DD | --season WINTER|SUMMER|ALL	 --from YYYY-MM-DD | --to YYYY-MM-DD | --season WINTER|SUMMER|ALL
commands_weights_label	Weights:	Gewichte:
commands_weights	 --weight-snow-new <v> | --weight-temperature <v> | ... (Prompt via --ask-weights)	 --weight-snow-new <v> | --weight-temperature <v> | ... (Abfrage über --ask-weights)
commands_env_label	Environment:	Umgebung:
commands_env	 REGION, CSV_PATH, WEIGHT_SNOW_NEW, SPEECH_CMD, ...	 REGION, CSV_PATH, WEIGHT_SNOW_NEW, SPEECH_CMD, ...
commands_quick_label	Quick copy:	Schneller Start:
commands_region_example_label	Region example:	Regionsbeispiel:
decision_support_header	== Decision Support ==	== Entscheidungshilfe ==
decision_hint_fresh_powder	Fresh powder in {{region}} {{amount}}	Frischer Pulverschnee in {{region}} {{amount}}
decision_hint_best_overall	Best overall score: {{region}} (score {{score}})	Beste Gesamtwertung: {{region}} (Score {{score}})
decision_hint_metric_label	Highlight	Highlight
decision_hint_metric	{{label}}: {{region}} (avg {{value}}{{unit}})	{{label}}: {{region}} (Ø {{value}}{{unit}})
decision_hint_coldest	Coldest regions	Kälteste Regionen
decision_hint_calmest	Calmest wind spots	Ruhigste Windstandorte
decision_hint_wettest	Highest precipitation	Höchster Niederschlag
decision_no_hints	No quick suggestions available - please adjust filters.	Keine schnellen Empfehlungen verfügbar – bitte Filter anpassen.
decision_hint_line	 - {{hint}}	 - {{hint}}
info_region_no_data	[INFO] No data available for {{region}}. Adjust filters or check the region name.	[INFO] Keine Daten für {{region}} verfügbar. Filter anpassen oder Namen prüfen.
info_region_no_aggregates	[INFO] No monthly aggregates available for {{region}}.	[INFO] Keine Monatsaggregationen für {{region}} verfügbar.
region_insights_header	== Region Insights — {{region}} (last {{months}} months) ==	== Regions-Einblicke — {{region}} (letzte {{months}} Monate) ==
region_prompt_missing	Please provide a region name, e.g. `{{command}} region "Zermatt"`.	Bitte gib einen Regionsnamen an, z. B. `{{command}} region "Zermatt"`.
region_not_found_exact	Region "{{region}}" not found.	Region "{{region}}" wurde nicht gefunden.
region_did_you_mean	Did you mean: {{suggestions}}?	Meintest du: {{suggestions}}?
region_run_list_hint	Run `list` to show all available regions.	Führe `list` aus, um alle verfügbaren Regionen anzuzeigen.
region_overview_header	== Region Overview — {{region}} ==	== Regionsübersicht — {{region}} ==
region_overview_stats	Country: {{country}} | Observations: {{rows}} | Date range: {{start}} to {{stop}}	Land: {{country}} | Beobachtungen: {{rows}} | Zeitraum: {{start}} bis {{stop}}
region_top_snow_days	== Top fresh snow days ==	== Top-Neuschneetage ==
region_recent_conditions	== Recent conditions (last 14 days) ==	== Letzte Bedingungen (letzte 14 Tage) ==
info_snow_plot_saved	[INFO] Snow trend plot saved to: {{path}}	[INFO] Schneetrend-Diagramm gespeichert unter: {{path}}
info_snow_plot_skipped	[INFO] Snow trend plot skipped (missing numeric data).	[INFO] Schneetrend-Diagramm übersprungen (fehlende numerische Daten).
info_score_plot_saved	[INFO] Score trend plot saved to: {{path}}	[INFO] Score-Trend-Diagramm gespeichert unter: {{path}}
info_score_plot_skipped	[INFO] Score trend plot skipped (insufficient data).	[INFO] Score-Trend-Diagramm übersprungen (unzureichende Daten).
info_metric_plot_skipped	[INFO] Metric plot for {{metric}} skipped (no data).	[INFO] Diagramm für {{metric}} übersprungen (keine Daten).
info_metric_plot_saved	[INFO] Metric plot for {{metric}} saved to: {{path}}	[INFO] Diagramm für {{metric}} gespeichert unter: {{path}}
warn_region_metrics_unknown	[WARN] REGION_METRICS token not understood: {{tokens}}	[WARN] REGION_METRICS nicht verstanden: {{tokens}}
info_region_metrics_env	[INFO] Generating attribute plots from REGION_METRICS...	[INFO] Erstelle Attribut-Diagramme gemäß REGION_METRICS...
info_region_metrics_none	[INFO] No additional attribute plots (REGION_METRICS not set or empty).	[INFO] Keine weiteren Attribut-Diagramme (REGION_METRICS nicht gesetzt oder leer).
info_region_metrics_no_tty	[INFO] No TTY detected – attempting plot selection anyway. Set REGION_METRICS (e.g. REGION_METRICS="Snow Depth,Temperature").	[INFO] Keine TTY erkannt – Auswahl der Diagramme wird dennoch versucht. REGION_METRICS setzen (z. B. REGION_METRICS="Schneehöhe,Temperatur").
prompt_metric_plots_header	Additional attributes to plot? (numbers or names, Enter to skip)	Zusätzliche Attribute visualisieren? (Nummern oder Namen, Enter zum Überspringen)
prompt_metric_plots_options	Available options:	Verfügbare Optionen:
prompt_metric_plots_option_entry	 {{index}}) {{label}}	 {{index}}) {{label}}
prompt_metric_plots_examples	Example input: 1,3 or Snow Depth Temperature or 'all'	Beispieleingabe: 1,3 oder Schneehöhe Temperatur oder 'all'
prompt_metric_plots_unknown_tokens	Not recognized: {{tokens}}	Nicht erkannt: {{tokens}}
prompt_metric_plots_retry	Please enter valid numbers or names (Enter to cancel).	Bitte gültige Nummern oder Namen eingeben (Enter zum Abbruch).
prompt_metric_plots_repeat	Plot additional attributes? (y/N)	Weitere Attribute plotten? (y/N)
prompt_metric_plots_next	Next selection (press Enter to finish):	Nächste Auswahl (Enter zum Beenden):
region_prompt_header	Enter region for a focused review (press Enter to skip):	Region für eine Detailansicht eingeben (Enter zum Überspringen):
prompt_session_finish	Exit tool? (q = Quit, Enter to stay)	Tool beenden? (q = Quit, Enter zum Zurückkehren)
metric_plot_title	{{region}} — {{metric}}	{{region}} — {{metric}}
warn_invalid_weight_env	Ignoring invalid weight from ENV	Ungültiger Gewichtswert aus ENV wird ignoriert
qc_header	== QC Checks ==	== QC-Prüfungen ==
qc_missing_days	[MISSING] Region={{region}}: {{count}} missing days ({{sample}}{{extra}})	[FEHLT] Region={{region}}: {{count}} fehlende Tage ({{sample}}{{extra}})
qc_outlier_wind	[OUTLIER] {{count}} wind values > 12 Beaufort	[AUSREISSER] {{count}} Windwerte > 12 Beaufort
qc_outlier_precipitation	[OUTLIER] {{count}} negative precipitation values	[AUSREISSER] {{count}} negative Niederschlagswerte
qc_outlier_snow_depth	[OUTLIER] {{count}} negative snow depth values	[AUSREISSER] {{count}} negative Schneehöhen
qc_outlier_temperature	[OUTLIER] {{count}} temperature values outside [-60,50]°C	[AUSREISSER] {{count}} Temperaturwerte außerhalb [-60,50]°C
qc_no_issues	No anomalies detected.	Keine Auffälligkeiten erkannt.
hint_region_command	Hint: use `region <NAME>` for details about a specific resort.	Hinweis: Nutze `region <NAME>` für Details zu einem bestimmten Ort.
info_no_tty_region_top	[INFO] No TTY detected – input may be limited. `region {{region}}` shows the top region.	[INFO] Keine TTY erkannt – Eingaben funktionieren eventuell eingeschränkt. `region {{region}}` zeigt die Top-Region.
info_no_tty_region_generic	[INFO] No TTY detected – input may be limited. Alternatively use `region <NAME>`.	[INFO] Keine TTY erkannt – Eingaben funktionieren eventuell eingeschränkt. Alternativ: `region <NAME>`.
prompt_region_details	Show region details? (rank number or name, Enter to skip)	Regiondetails anzeigen? (Rangnummer oder Name, Enter zum Überspringen)
region_prompt_suggestions	Suggestions: {{suggestions}}	Vorschläge: {{suggestions}}
region_not_found_with_suggestions	Region not found. Suggestions: {{suggestions}}	Region nicht gefunden. Vorschläge: {{suggestions}}
region_not_found_no_suggestions	Region not found. Use `list` to show all locations.	Region nicht gefunden. Nutze `list` für alle Orte.
region_input_error	Input could not be processed ({{error}}).	Eingabe konnte nicht verarbeitet werden ({{error}}).
region_prompt_retry	Region not found. Please enter the number or exact name (Enter to cancel).	Region nicht gefunden. Bitte Nummer oder exakten Namen eingeben (Enter zum Abbruch).
prompt_region_another	View another region? (y/N)	Weitere Region ansehen? (y/N)
prompt_region_next	Next region (number or name, Enter to finish):	Nächste Region (Nummer oder Name, Enter zum Beenden):
"""

function build_translation_strings()
    en = Dict{Symbol,String}()
    de = Dict{Symbol,String}()
    for line in split(TRANSLATION_DATA, '
')
        entry = strip(line)
        isempty(entry) && continue
        startswith(entry, '#') && continue
        parts = split(entry, '	')
        length(parts) == 3 || continue
        key, en_txt, de_txt = parts
        en[Symbol(key)] = en_txt
        de[Symbol(key)] = de_txt
    end
    return Dict{Symbol,Dict{Symbol,String}}(:en => en, :de => de)
end

const STRINGS = build_translation_strings()


function normalize_language(lang)
    raw = lowercase(strip(String(lang)))
    raw == "" && return DEFAULT_LANGUAGE
    sanitized = replace(replace(raw, '-' => '_'), '.' => '_')
    segments = split(sanitized, '_')
    candidates = String[sanitized]
    if !isempty(segments)
        base = segments[1]
        base != sanitized && push!(candidates, base)
    end
    for cand in candidates
        sym = Symbol(cand)
        if sym in (:en, :english)
            return :en
        elseif sym in (:de, :german, :deutsch)
            return :de
        end
    end
    return Symbol(candidates[1])
end

function is_supported_language(lang)
    sym = normalize_language(lang)
    return haskey(STRINGS, sym)
end

function available_languages()
    return collect(keys(STRINGS))
end

function current_language()
    return ACTIVE_LANGUAGE[]
end

function string_map(lang::Symbol)
    if haskey(STRINGS, lang)
        return STRINGS[lang]
    else
        return STRINGS[DEFAULT_LANGUAGE]
    end
end

function set_language!(lang)
    sym = normalize_language(lang)
    if haskey(STRINGS, sym)
        ACTIVE_LANGUAGE[] = sym
    else
        ACTIVE_LANGUAGE[] = DEFAULT_LANGUAGE
    end
    return ACTIVE_LANGUAGE[]
end

function localize(key::Symbol; kwargs...)
    lang = current_language()
    dict = string_map(lang)
    if !haskey(dict, key) && lang != DEFAULT_LANGUAGE
        dict = string_map(DEFAULT_LANGUAGE)
    end
    text = get(dict, key, String(key))
    if isempty(kwargs)
        return text
    end
    replacements = Dict{String,String}()
    for (k, v) in kwargs
        replacements[String(k)] = string(v)
    end
    replacer = m -> begin
        inner = m[3:end-2]
        get(replacements, inner, m)
    end
    return replace(text, TEMPLATE_PATTERN => replacer)
end

t = localize

end

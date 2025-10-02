# Ski-Resort-Buddy

Ski-Resort-Buddy is a Julia CLI that ranks alpine resorts by weather, snow quality, and user-defined priorities. A guided menu walks you through the latest dataset (downloaded automatically from Supabase and cached locally) and lets you explore yearly snowfall leaders, monthly summaries, and deep regional dives with optional plots.

## Highlights

- **One-command menu** – `julia --project=. bin/dach_resort_advisor menu` prompts for weights, lets you focus on a country, and keeps looping until you exit.
- **Remote dataset, cached offline** – the current CSV is fetched once and reused (`data/remote_cache/`). No manual downloads needed.
- **Yearly snowfall leaderboard** – the former “daily” list now reports total fresh snow per region across the last 12 months for more realistic comparisons.
- **Region deep dive** – after running a report you can pick regions by table rank or name, view history, and optionally save snow or attribute plots.
- **Custom weights** – adjust the five core metrics (fresh snow, snow depth, temperature, precipitation, wind) interactively or via CLI flags; the weighted score is reflected everywhere in the report.

## Getting Started

1. Install dependencies (once):
   ```bash
   julia --project=. -e 'import Pkg; Pkg.instantiate()'
   ```
2. Launch the menu:
   ```bash
   julia --project=. bin/dach_resort_advisor menu
   ```
3. Follow the prompts:
   - Adjust metric weights (sum 100) or press Enter to retain the defaults.
   - Choose a country or leave blank to analyse all regions.
   - Review the yearly snowfall leaderboard and monthly overview, then select a region for a deep dive.
   - When asked, choose whether to create snow trend or attribute plots (saved to `plots/`).

## Non-interactive Usage

The classic commands still exist if you prefer scripting:
- `julia --project=. bin/dach_resort_advisor report` – run the full report without the menu.
- `julia --project=. bin/dach_resort_advisor list` – list all available regions.
- `julia --project=. bin/dach_resort_advisor region "Zermatt"` – jump straight to a region summary.
- Filters (`--season`, `--from`, `--to`) and weight flags (`--weight-snow-new`, etc.) remain available for automation.

## Notes

- The tool detects non-interactive environments and skips prompts automatically; you can also set `FORCE_WEIGHT_PROMPT=false` or `--no-ask-weights` to suppress the weight dialog.
- Override the dataset with `CSV_PATH=/absolute/path.csv` if you need a custom file.

Enjoy planning your next powder day! 🚡

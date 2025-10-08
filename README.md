# Ski-Resort-Buddy

Ski-Resort-Buddy is a Julia CLI that ranks alpine resorts by weather, snow quality, and user-defined priorities. A guided menu walks you through the latest dataset (downloaded automatically from Supabase and cached locally) and lets you explore yearly snowfall leaders, monthly summaries, and deep regional dives with optional plots.

## Highlights

- **One-command menu** – `julia --project=. bin/dach_resort_advisor menu` prompts for weights, lets you focus on a country, and keeps looping until you exit.
- **Remote dataset, cached offline** – the current CSV is fetched once and reused (`data/remote_cache/`). No manual downloads needed.
- **Yearly snowfall leaderboard** – the former “daily” list now reports total fresh snow per region across the last 12 months for more realistic comparisons.
- **Region deep dive** – after running a report you can pick regions by table rank or name, view history, and optionally save snow or attribute plots.
- **Custom weights** – adjust the five core metrics (fresh snow, snow depth, temperature, precipitation, wind) interactively or via CLI flags; the weighted score is reflected everywhere in the report.

## Data
The data used in the project can be found here: https://www.kaggle.com/datasets/cartermc/dach-ski-resort-advisor-data/data/data


## Getting Started
How to Run the DACH Ski Resort Advisor
Open your system's terminal. This is the command line interface for your operating system, not the Julia REPL that starts with julia>. 
   
Navigate to your project directory. Use the cd command to go to the folder that contains the Project.toml and Manifest.toml files
   ```bash
  cd path/to/your/Ski-Resort-Buddy'
   ```
1. Install dependencies (once):
   ```bash
   julia --project=. -e 'import Pkg; Pkg.instantiate()'
   ```
2. Launch the menu:
   ```bash
   julia --project=. bin/dach_resort_advisor
   ```
3. Follow the prompts:
   - Adjust metric weights (sum 100) or press Enter to retain the defaults.
   - Choose a country or leave blank to analyse all regions.
   - Review the yearly snowfall leaderboard and monthly overview, then select a region for a deep dive.
   - When asked, choose whether to create snow trend or attribute plots (saved to `plots/`).



## Testing:

This project has Test included to check functioning of the program. Follow the steps to run test.
From the project directory, type the following command:
```bash
julia --project=. test/runtests.jl
 ```


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

## Disclaimer and Terms of Use

This project was developed for purely educational and non-commercial purposes as part of an academic assignment. The data used in this project is sourced from a publicly available dataset hosted on Zenodo, and all rights, ownership, and credit for the data belong entirely to the original authors and publishers.

The information and analysis presented are provided "as is" without any warranty of accuracy, completeness, or suitability for any particular purpose. No commercial use of this data or the resulting analysis is intended or permitted. The use of this data adheres to the Creative Commons Attribution 4.0 International license under which it was published.
Data Source and Citation

The climatological and snow data used in this project was obtained from the following source:

    Authors: Schmucki, E., Marty, C., Fierz, C., & Lehning, M.

    Year: (2021).

    Title: Long-term snow and climate measurement data from the IMIS and national observation networks.

    Publisher: Zenodo.

    Date Accessed: September 29, 2025.

    DOI (Digital Object Identifier): https://doi.org/10.5281/zenodo.5109574

Please refer to the source link for the original dataset and full metadata.

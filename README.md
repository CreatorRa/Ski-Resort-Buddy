# Ski-Resort-Buddy

Ski-Resort-Buddy is a Julia CLI that ranks alpine resorts by weather, snow quality, and user-defined priorities. A guided menu walks you through the latest dataset (downloaded automatically from Supabase and cached locally) and lets you explore yearly snowfall leaders, monthly summaries, and deep regional dives with optional plots.

## Highlights

- **One-command menu** – `julia --project=. bin/dach_resort_advisor menu` prompts for weights, lets you focus on a country, and keeps looping until you exit.
- **Remote dataset, cached offline** – the current CSV is fetched once and reused (`data/remote_cache/`). No manual downloads needed.
- **Yearly snowfall leaderboard** – the former “daily” list now reports total fresh snow per region across the last 12 months for more realistic comparisons.
- **Region deep dive** – after running a report you can pick regions by table rank or name, view history, and optionally save snow or attribute plots.
- **Custom weights** – adjust the five core metrics (fresh snow, snow depth, temperature, precipitation, wind) interactively or via CLI flags; the weighted score is reflected everywhere in the report.

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
3. Interactive Menu Flow

   - When you run the program, you’ll see a guided text menu.
   - Here’s what happens step-by-step:

   # Step 1 – Select Your Language
   - The program will ask which language to use (currently English or German).
   - Type your choice and press Enter.

   # Step 2 – Overview or Country
   - Next, you’ll be prompted to choose either to select a country or see an overview of all regions. 
   - If you choose to select a country you will then be asked to select the you are intereseted in visiting: Germany, Austria, Switzerland.

   # Step 3 – Adjust Metric Weights
   - You will now be prompted to declare if you want adjust the weighting of the main variables. It is recommended for first time user to select N for No, to gain a better understanding of the program.
   - If you have chosen y, you will now see the option to either:
      1. Press enter and choose your own weighting
      2. Press 1 to choose the preconfigured Balanced Allrounder
      3. Press 2 to choose the preconfigured Powder Hunter
      4. Press 3 to choose the preconfigured Family friendly
      5. Press 4 to choose the preconfigured Sunny Cruiser
      6. Press 5 to choose again to enter your own weighting
   - If you choose to enter your own weights you must now enter custom weight percentages for  (total must equal 100) or press enter to keep the default balanced weights. The weight determines how much each factor influences the ranking resort.

   # Step 4: Active Filter and Weighting.
   - You will now see all active filters that are being applied to the data:
      - Season: The current season of the year.
      - Date range: The current range of the data.
      - Whether you have preselected the region.
      - Observations: The total number of data points being analzyed. 
   - You will see below the active filters the default weighting we are applying to the data:
      - Fresh snow: 
      - Snow Depth: The overall snow fall in centimeters
      - Temperature: The overall temperature in celcius
      - Precipitation: The overall rainfall in millimeters
      - Wind: The wind measure by the Beaufort scale (0-12). A lower value is better. 

   # Step 5 – View the Results
   - After confirming your weights:
   - Either the Top ski regions by your chosen weighting will appear or if you requested an overiview The yearly snowfall leaderboard appears, showing top-performing regions.
   - A monthly summary table provides weather and snow averages.
   - You can then select a region (by number or name) to see more granular data about:
   - Historical data
   - Weighted scores
   - Optional trend plots (saved in the `plots/` folder)

   # Step 6 – Exit the Program
   - When finished:
   - You can type “exit” or choose the Exit option in the menu.
   - The program will close safely, and your cached data remains saved locally for next time.



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

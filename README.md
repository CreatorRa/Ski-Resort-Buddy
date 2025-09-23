# Ski-Resort-Buddy

This project is a Julia-based data analytics tool that ranks ski resorts by weather-related attributes. The system evaluates snowfall, temperature, and rainfall to generate a composite score for each resort, enabling better decision-making for tourism, travel, and business planning.

# Aim of the project
<ul>
<li>Provide a data-driven ranking system for ski resorts</li>
<li>Demonstrate how Julia can be used for real-world analytics workflows</li>
</ul>

Create a foundation for future extensions
<ul>
  <li>Adjustable attribute weights</li>
  <li>Distance-based filtering (e.g., proximity to a city)</li>
  <li>Integration with live weather APIs</li>
  <li>Additional environmental or business attributes (e.g., ticket prices, amenities)</li>
</ul>

## 🚀 Running the DACH Resort Advisor

1. Open a terminal in the project root (`Ski-Resort-Buddy`).
2. Install dependencies (once):
   ```bash
   julia --project=. -e 'import Pkg; Pkg.instantiate()'
   ```
3. (Optional) Place `ski-regions-data.csv` in the root or set `CSV_PATH=/absolute/path/to/your.csv`.
4. Use the commands below to explore the data.

## 🧭 Command Cheat Sheet

| Command | Description |
| --- | --- |
| `julia --project=. bin/dach_resort_advisor report` | Full terminal dashboard (monthly snapshot, leaderboards, QC, summaries). |
| `julia --project=. bin/dach_resort_advisor list` | Lists every available DACH region that can be queried. |
| `julia --project=. bin/dach_resort_advisor region "Zermatt"` | Deep dive into one resort (replace `"Zermatt"` with any region name from the list). |
| `julia --project=. bin/dach_resort_advisor report --season WINTER` | Run the dashboard focusing on winter months only (accepts `WINTER`, `SUMMER`, `ALL`). |
| `julia --project=. bin/dach_resort_advisor report --from 2024-11-01 --to 2025-04-30` | Limit the data window using custom date filters. |

Environment helpers: set `REGION="Verbier"` to preselect a region or `CSV_PATH=/path/to/data.csv` to override the dataset before running the script.

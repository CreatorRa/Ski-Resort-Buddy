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

https://prod.liveshare.vsengsaas.visualstudio.com/join?86D4A45EFAFE053D7A4376FE5D646CC2E281

https://prod.liveshare.vsengsaas.visualstudio.com/join?86D4A45EFAFE053D7A4376FE5D646CC2E281

---
Possible Datasources: 
https://data.hub.geosphere.at/ -- Austria
https://opendatadocs.meteoswiss.ch/ -- Switzerland
https://www.dwd.de/EN/ourservices/opendata/opendata.html -- Germany
https://www.smhi.se/en/research/about-us/open-access-to-data-for-research-and-development -- Sweden
---
API's: 
https://open-meteo.com/en/docs -- Lots of Weather Data for different Countries.
https://openweathermap.org/current
https://www.icpac.net/open-data-sources/
https://data.europa.eu/data/datasets/0bd84be4-cec8-4180-97a6-8b3adaac4d26?locale=en
https://github.com/open-meteo/open-meteo


## 📦 Setup

Clone this repository and open it in VS Code or your terminal.

Install Julia packages (once, inside the project folder):

```bash
julia --project=. -e 'import Pkg; Pkg.activate("."); Pkg.instantiate()'

Build processed data
This creates data/processed/resorts_processed.csv from your raw file:

julia --project=. scripts/build_resorts.jl

List available resorts
julia --project=. bin/ski_lookup.jl --list

Query one resort
julia --project=. bin/ski_lookup.jl --name "NAME_OF_RESORT_FROM_LIST"

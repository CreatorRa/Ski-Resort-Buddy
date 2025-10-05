# --- PART 1: SETUP ---
# It is best practice to have all 'using' statements at the top of the script.
using DataFrames
using CSV
using Dates

# --- PART 2: A REUSABLE FUNCTION FOR DATA CLEANING ---

"""
    process_country_data(filepath, country_name, region_replacements)

Loads, cleans, and transforms a country's monthly ski data from a given CSV file.
This function handles dropping unnecessary columns, removing missing values,
renaming columns for clarity, adding a country identifier, and cleaning region names.

# Arguments
- `filepath::String`: The full path to the input CSV file.
- `country_name::String`: The name of the country to add to the 'Country' column.
- `region_replacements::Vector{Pair{String, String}}`: A list of text replacements to apply to the region names.

# Returns
- `DataFrame`: A cleaned and processed DataFrame for the specified country.
"""
function process_country_data(filepath::String, country_name::String, region_replacements::Vector{Pair{String, String}})
    println("Processing data for $country_name from '$filepath'...")

    # Load the data from the CSV file, interpreting empty cells as 'missing'
    df = CSV.read(filepath, DataFrame, missingstring="")

    # 1. Define and remove unnecessary columns (e.g., gap-filled data)
    columns_to_drop = [
        "SCD1gt", "SCD10", "SCD20", "SCD30", "SCD50", "SCD100",
        "HSmean_gapfill", "frac_gapfilled", "HSmax_gapfill", "SCD1_gapfill",
        "SCD1gt_gapfill", "SCD10_gapfill", "SCD20_gapfill", "SCD30_gapfill",
        "SCD50_gapfill", "SCD100_gapfill"
    ]
    select!(df, Not(columns_to_drop))

    # 2. Drop any rows where the key snow depth value 'HNsum' is missing
    dropmissing!(df, :HNsum)

    # 3. Rename columns for better readability using symbols (:)
    rename!(df, :Name => :Region)
    rename!(df, :HNsum => Symbol("Snow Depth (cm)"))
    rename!(df, :HSmean => Symbol("Mean Snow Depth (cm)"))
    rename!(df, :HSmax => Symbol("Max Snow Depth (cm)"))
    rename!(df, :SCD1 => Symbol("Days where AVG Temp < 0C"))
    rename!(df, :year => :Date)

    # 4. Add a 'Country' column right after the 'Region' column
    insertcols!(df, 2, :Country => country_name)

    # 5. Clean up the region names using the provided text replacements
    for replacement in region_replacements
        df.Region = replace.(df.Region, replacement)
    end
    
    println("Finished processing for $country_name.")
    return df
end


# --- PART 3: PROCESS DATA FOR EACH COUNTRY USING THE FUNCTION ---

# --- Switzerland ---
swiss_filepath = "C:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\data_monthly_CH_SLF.csv"
swiss_replacements = ["_CH_SLF" => "", "Davos_Fluelastr_" => "Davos", "St_Moritz" => "St Moritz"]
df_switzerland = process_country_data(swiss_filepath, "Switzerland", swiss_replacements)
println("-"^40)

# --- Germany ---
germany_filepath = "C:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\data_monthly_DE_DWD.csv"
germany_replacements = ["Berchtesgaden_KKst_" => "Berchtesgaden", "Feldberg_Schwarzwald" => "Feldberg", "Garmisch_Partenkirchen" => "Garmisch-Partenkirchen", "Oberndorf_Neckar" => "Oberstdorf"]
df_germany = process_country_data(germany_filepath, "Germany", germany_replacements)
println("-"^40)

# --- Austria ---
austria_filepath = "C:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\data_monthly_AT_HZB.csv" 
# Define any specific text cleanups for Austrian region names here
austria_replacements = [ "_AT_HZB" => "" ] # Example: remove the suffix
df_austria = process_country_data(austria_filepath, "Austria", austria_replacements)
println("-"^40)


# --- PART 4: COMBINE AND JOIN THE DATASETS ---

# 1. Combine the three cleaned country DataFrames into a single historical dataset
println("Combining data for all three countries...")
df_combined = vcat(df_switzerland, df_germany, df_austria)

# 2. Filter the combined data to only include records from the year 2000 onwards
filter!(:Date => >=(2000), df_combined)
rename!(df_combined, :Date => :Year) # Rename 'Date' column to 'Year' for clarity
rename!(df_combined, :month => :Month)
rename!(df_combined, Symbol("Snow Depth (cm)") => Symbol("Monthly Snow Depth (cm)"))
println("Combined and filtered historical data. Total rows: ", nrow(df_combined))
println("-"^40)

# 3. Load and process the separate ski region attribute data
regions_filepath = "c:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\ski-regions-data.csv"
println("Loading and processing regional attribute data from '$regions_filepath'...")
df_regions = CSV.read(regions_filepath, DataFrame)
# Convert string dates to Date objects to extract year, month, day
df_regions.Date = Date.(df_regions.Date)
df_regions.Year = year.(df_regions.Date)
df_regions.Month = month.(df_regions.Date)
df_regions.Day = day.(df_regions.Date)
select!(df_regions, Not(:Date)) # Remove original string Date column
rename!(df_regions, Symbol("Snow Depth (cm)") => Symbol("Daily Snow Depth (cm)"))
println("Finished processing regional data.")
println("-"^40)

# 4. Join the historical snow data with the regional attributes
println("Joining the two datasets on Region and Country...")
# An inner join combines rows where the keys (:Region, :Country) match in both tables
df_final = innerjoin(df_combined, df_regions, on = [:Region, :Country, :Year, :Month])
println("Successfully joined the data. Final dataset has ", nrow(df_final), " rows.")
println("-"^40)

# --- PART 5: EXPORT THE FINAL DATASET ---
"""
output_filepath = "C:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\DACH_Ski_Resort_Final_Dataset.csv"
println("Exporting final combined dataset to '$output_filepath'...")

CSV.write(output_filepath, df_final)

println("Export complete. Workflow finished successfully!")
println("\nDisplaying first 5 rows of the final joined data:")
println(first(df_final, 5))
"""

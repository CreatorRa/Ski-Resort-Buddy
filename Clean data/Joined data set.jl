using CSV
using DataFrames

#Combine the data from ski-regions with the previous dataframes. 

filepath_combined = "c:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\combined_ski_data.csv"
println("Loading historical snow data from '$filepath_combined'...")
df_snow = CSV.read(filepath_combined, DataFrame)

# Load the regional weather/elevation data
filepath_regions = "c:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\ski-regions-data.csv"
println("Loading regional weather data from '$filepath_regions'...")
df_regions = CSV.read(filepath_regions, DataFrame)

println("Preparing data for the join...")

rename!(df_snow, "Snow Depth (cm)" => "Monthly Snow Depth (cm)")
rename!(df_regions, "Snow Depth (cm)" => "Daily Snow Depth (cm)"
# The 'Date' in the regional data is a daily date, which we'll keep.
# The 'Date' in the combined snow data is the year, so let's rename it for clarity.
rename!(df_snow, "Date" => "Year")

df_final = innerjoin(df_snow, df_regions, on = [:Region, :Country])

println("Successfully joined the data.")
println("The final DataFrame has ", nrow(df_final), " rows and ", ncol(df_final), " columns.")
println("-"^40)

println("Displaying the first 5 rows of the final joined data:")
# Use `first` to show a preview. Note the many new columns from both files.
println(first(df_final, 5))

println("\nFinal column names in the joined DataFrame:")
println(names(df_final))

filepath_regions = "c:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\ski-regions-data.csv"
df_regions = CSV.read(filepath_regions, DataFrame)
df_regions.Date = Date.(df_regions.Date)
df_regions.Year = year.(df_regions.Date)
df_regions.Month = month.(df_regions.Date)
df_regions.Day = day.(df_regions.Date)

select!(df_regions, Not(:Date))
rename!(df_regions, "Snow Depth (cm)" => "Daily Snow Depth (cm)")

sort!(df_regions, :Region)
all_cols = names(df_regions)
date_cols_to_move = ["Year", "Month", "Day"]
other_cols = setdiff(all_cols, date_cols_to_move)
country_index = findfirst(isequal("Country"), other_cols)
new_order = vcat(
    other_cols[1:country_index],      # Columns up to and including 'Country'
    date_cols_to_move,                # Insert the date columns here
    other_cols[country_index+1:end]   # Add the rest of the columns
)
select!(df_regions, new_order)
insertcols!(df_regions, 11, :"Mean Snow Depth (cm)" => missing)
insertcols!(df_regions, 12, :"Monthly Snow Depth (cm)" => missing)
insertcols!(df_regions, 13, :"Max Snow Depth (cm)" => missing)
insertcols!(df_regions, 14, :"Days where AVG Temp < 0C" => missing)

# --- Export the edited DataFrame to a new CSV file ---
#Output_filepath_regions_edited = "c:\\Users\\Carter\\OneDrive\\Documents\\KLU\\KLU Studies\\Scientific Programming\\Clean Data\\more data\\Regions edited.csv"
#CSV.write(Output_filepath_regions_edited, df_regions)



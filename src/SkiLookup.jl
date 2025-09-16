module SkiLookup

using CSV, DataFrames, PrettyTables

# -------- Helper --------
# Robust gegen „komische“ Zeichen: wenn lowercase crasht, fällt es auf Original zurück
normalize_str(x) = begin
    s = try
        String(x)
    catch
        string(x)
    end
    try
        lowercase(strip(s))
    catch
        strip(s)   # Fallback ohne lowercase (verhindert InvalidCharError)
    end
end

# -------- Loader nur für resorts.csv --------
"""
load_resorts_csv(path) -> DataFrame

Erwartete Pflichtspalten (weitere sind ok): "Resort", "Country", "Continent" (falls vorhanden)
"""
function load_resorts_csv(path::AbstractString)
    df = CSV.read(path, DataFrame)  # wenn es Encoding-Probleme gibt, sag mir die Fehlermeldung

    # Pflichtspalte "Resort" muss existieren
    @assert "Resort" ∈ names(df) "resorts.csv braucht mindestens die Spalte: Resort"

    # Normalisierter Schlüssel für exakte Suche (ohne Fuzzy)
    df.name_key = normalize_str.(df.Resort)

    return df
end

# -------- Build (nur Aufbereiten & Speichern) --------
"""
build_resorts(raw_path; out_path="data/processed/resorts_processed.csv")

- liest nur resorts.csv
- fügt 'name_key' hinzu
- speichert als processed CSV
"""
function build_resorts(raw_path::AbstractString; out_path::AbstractString="data/processed/resorts_processed.csv")
    df = load_resorts_csv(raw_path)
    sort!(df, :Resort)
    mkpath(dirname(out_path))
    CSV.write(out_path, df)
    return df
end

# -------- Queries --------
"""
list_resorts(data_dir="data/processed") -> Vector{String}
"""
function list_resorts(data_dir::AbstractString="data/processed")
    df = CSV.read(joinpath(data_dir, "resorts_processed.csv"), DataFrame)
    collect(df.Resort)
end

"""
query_resort_meta(name; data_dir="data/processed") -> DataFrame (eine Zeile)

Sucht exakten Namen (case-insensitive über 'name_key').
"""
function query_resort_meta(name::AbstractString; data_dir::AbstractString="data/processed")
    df = CSV.read(joinpath(data_dir, "resorts_processed.csv"), DataFrame)
    key = normalize_str(name)
    idx = findfirst(df.name_key .== key)
    idx === nothing && error("Kein Resort gefunden: $(name). Erst --list aufrufen und exakten Namen verwenden.")
    return df[idx:idx, :]
end

# -------- Ausgabe --------
"""
print_resort_meta(meta; prefer_cols = [...])

Zeigt bevorzugte Spalten (falls vorhanden) in schöner Tabelle,
und falls etwas fehlt, zeigt alle übrigen Felder kompakt darunter.
"""
function print_resort_meta(meta::DataFrame; prefer_cols = [
        "Resort","Country","Continent","Region","Price","Season",
        "Skiable area","Elevation","Vertical","Runs","Lifts","Snowmaking",
        "Latitude","Longitude","Website"
    ])
    # 1) Bevorzugte Spalten, die es tatsächlich gibt
    cols_present = String[]
    for c in prefer_cols
        if c ∈ names(meta)
            push!(cols_present, c)
        end
    end

    if !isempty(cols_present)
        println("— Wichtigste Felder —")
        PrettyTables.pretty_table(meta[:, cols_present]; alignment=:l)
    end

    # 2) Restliche Felder (optional)
    remaining = setdiff(names(meta), vcat(cols_present, ["name_key"]))
    if !isempty(remaining)
        println("\n— Weitere Felder —")
        PrettyTables.pretty_table(meta[:, remaining]; alignment=:l)
    end
end

end # module

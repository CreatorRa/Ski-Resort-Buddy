#!/usr/bin/env julia
using Pkg
Pkg.activate(".")
using SkiLookup

# Rohdatei einlesen und processed speichern
SkiLookup.build_resorts("data/raw/resorts.csv"; out_path="data/processed/resorts_processed.csv")
println("Fertig: data/processed/resorts_processed.csv")


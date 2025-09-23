# menu.jl
# A simple Julia menu where users can navigate up and down for ski project

function show_menu(options::Vector{String}, current_index::Int)
    println("\n--- Main Menu ---")
    for (i, opt) in enumerate(options)
        if i == current_index
            println("> $opt")         # highlight current option
        else
            println("  $opt")
        end
    end
    println("\nUse W (up), S (down), Enter (select), Q (quit).")
end

function run_menu()
    options = ["Start Game", "Settings", "Help", "Exit"]
    current_index = 1

    while true
        show_menu(options, current_index)

        print("> ")
        user_input = readline()

        if lowercase(user_input) == "w"          # move up
            current_index = max(1, current_index - 1)
        elseif lowercase(user_input) == "s"      # move down
            current_index = min(length(options), current_index + 1)
        elseif user_input == ""                  # Enter selects
            println("\nYou selected: ", options[current_index], "\n")
            if options[current_index] == "Exit"
                println("Exiting the menu. Goodbye!")
                break
            end
        elseif lowercase(user_input) == "q"
            println("Exiting menu...")
            break
        else
            println("Invalid input. Use W, S, Enter, or Q.")
        end
    end
end

# Run the menu
run_menu()

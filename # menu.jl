# menu.jl
A simple julia menu where users can navigate up and down for ski project
    fucntion show_menu(option, current_index)
    Println("\n---Main Menu---")
    for (i, option) in enumerate(options)
        if i == current_index
             Println("   $option") # Highlight the current option
        else
        end
    end
        println("\nUse W (up), s (down), Enter (select), Q (Quit).")
end
function run_menu()
    options = ["Start Game", "Settings", "Help", "Exit"]
    current_index = 1
    while true
        show_menu(options, current_index)

    print("> ")
    user_input = readline()
    if lowercase(input) =="w"    # move up
        current_index = max(1, current_index - 1)
    elseif lowercase(user_input) == "s" # move down
        current_index = min(length(options), current_index + 1)
    elseif user_input == "" # Enter key (just press Enter key)
        println("\n you selected: ", options[current_index], "\n")
        if options[current_index] == "Exit"
            println("Exiting the menu. Goodbye!")
            break
        end
    elseif lowercase(user_input) == "q"
        println("Exiting menu...")
        break 
    else 
        println("invalid iniput. Use W, S, Enter, or Q.")
    end
    end
end
# Run the menu
run_menu()

        